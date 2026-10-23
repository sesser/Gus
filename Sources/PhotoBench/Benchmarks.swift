import CoreGraphics
import Foundation
import PhotoCore

/// Opens the catalog and preview service of a `--library-root` folder.
struct BenchLibrary {
    let locations: LibraryLocations
    let catalog: Catalog

    init(_ arguments: Arguments) throws {
        locations = LibraryLocations.rooted(at: try arguments.url("library-root"))
        try locations.createDirectories()
        catalog = try Catalog.open(at: locations.catalogFileURL)
    }

    func service(generateConcurrency: Int = PreviewService.defaultGenerateConcurrency,
                 loadConcurrency: Int = 6) -> PreviewService {
        let catalog = self.catalog
        return PreviewService(cache: PreviewDiskCache(root: locations.previewCacheDirectory), editStack: { id in
            try await catalog.version(id: id)?.decodedEditStack() ?? .identity
        }, loadConcurrency: loadConcurrency, generateConcurrency: generateConcurrency)
    }

    /// Items with their master URLs (nil when the volume is offline).
    func itemsWithSources() async throws -> [(CatalogItem, URL?)] {
        let volumes = try await catalog.volumes()
        let online = try await catalog.refreshVolumeAvailability()
        let byID = Dictionary(uniqueKeysWithValues: volumes.compactMap { volume in volume.id.map { ($0, volume) } })
        return try await catalog.libraryItems(matching: LibraryFilter()).map { item in
            let url = online.contains(item.volumeID) ? byID[item.volumeID]?.url(forRelativePath: item.relativePath) : nil
            return (item, url)
        }
    }
}

enum ImportBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let library = try BenchLibrary(arguments)
        let source = try arguments.url("source")
        let reader: any MetadataReader = arguments.flags.contains("imageio")
            ? ImageIOMetadataReader() : MetadataReaders.makeDefault()
        let readerName = reader is ImageIOMetadataReader ? "ImageIO" : "ExifTool (+ImageIO fallback)"
        let importer = Importer(catalog: library.catalog, metadataReader: reader)
        let options = ImportOptions(chunkSize: arguments.int("chunk", default: 64),
                                    hashingConcurrency: arguments.int("hash-concurrency", default: 4))
        let bytes = Generate.folderSize(source)
        let summary = try await importer.importFolder(source, options: options)
        let t = summary.timings
        let p = summary.progress
        let total = t.total.seconds
        print("Import of \(p.filesFound) files (\(formatBytes(bytes))) with \(readerName)")
        print(String(format: "  imported %d, duplicates %d, already catalogued %d, failed %d", p.imported, p.duplicates, p.alreadyInCatalog, p.failed))
        print(String(format: "  total %.2f s  (%.0f files/s, %.0f MB/s)", total, Double(p.filesFound) / total, Double(bytes) / 1e6 / total))
        print(String(format: "  scan %.2f s   hash %.2f s   metadata %.2f s   catalog %.2f s",
                     t.scan.seconds, t.hash.seconds, t.metadata.seconds, t.catalog.seconds))
        return ["machine": machineDescription(), "files": p.filesFound, "imported": p.imported,
                "duplicates": p.duplicates, "already": p.alreadyInCatalog, "failed": p.failed, "bytes": bytes,
                "metadata_reader": readerName, "total_s": total, "scan_s": t.scan.seconds, "hash_s": t.hash.seconds,
                "metadata_s": t.metadata.seconds, "catalog_s": t.catalog.seconds]
    }
}

enum PreviewBenchmark {
    static func tier(_ arguments: Arguments) -> PreviewTier {
        arguments.values["tier"] == "preview" ? .preview : .thumbnail
    }

    /// Generates renditions for every version with `concurrency` in flight and
    /// records how long each one took, grouped by file format.
    static func generate(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let library = try BenchLibrary(arguments)
        let tier = tier(arguments)
        let concurrency = arguments.int("concurrency", default: PreviewService.defaultGenerateConcurrency)
        let service = library.service(generateConcurrency: concurrency)
        if arguments.flags.contains("fresh") { try service.cache.removeAll() }
        var items = try await library.itemsWithSources()
        if let format = arguments.values["format"]?.lowercased() {
            items = items.filter { ($0.0.relativePath as NSString).pathExtension.lowercased() == format }
        }
        if let limit = arguments.values["limit"].flatMap(Int.init) { items = Array(items.prefix(limit)) }
        let requests: [(String, PreviewRequest)] = items.compactMap { item, url in
            guard let key = PreviewCacheKey(item: item, tier: tier), let url else { return nil }
            return ((item.relativePath as NSString).pathExtension.lowercased(),
                    PreviewRequest(versionID: item.versionID, key: key, sourceURL: url))
        }
        let pending = requests.filter { !service.cache.contains($0.1.key) }
        print("Generating \(tier.rawValue) (\(tier.longEdge) px) for \(pending.count) of \(requests.count) versions, \(concurrency) at a time")

        let (samples, elapsed) = await measure {
            await withTaskGroup(of: (String, Double, Bool).self) { group in
                var results: [(String, Double, Bool)] = []
                var iterator = pending.makeIterator()
                func addNext() {
                    guard let (format, request) = iterator.next() else { return }
                    group.addTask {
                        let (ok, duration) = await measure { (try? await service.prepare(request, priority: .visible)) != nil }
                        return (format, duration.milliseconds, ok)
                    }
                }
                for _ in 0..<concurrency { addNext() }
                var done = 0
                for await result in group {
                    results.append(result)
                    done += 1
                    if done % 1000 == 0 { print("  \(done) done") }
                    addNext()
                }
                return results
            }
        }
        var byFormat: [String: [Double]] = [:]
        for (format, ms, ok) in samples where ok { byFormat[format, default: []].append(ms) }
        let failures = samples.filter { !$0.2 }.count
        print(String(format: "  wall %.1f s, %.1f renditions/s, %d failed", elapsed.seconds, Double(samples.count) / max(elapsed.seconds, 0.001), failures))
        var formats: [String: any Sendable] = [:]
        for (format, values) in byFormat.sorted(by: { $0.key < $1.key }) {
            let stats = Stats(values)
            print("  \(format.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0)) \(stats.line)")
            formats[format] = stats.dictionary
        }
        let usage = service.cache.diskUsage()
        print("  cache on disk: \(formatBytes(usage))")
        return ["machine": machineDescription(), "tier": tier.rawValue, "concurrency": concurrency,
                "generated": samples.count, "failed": failures, "wall_s": elapsed.seconds,
                "per_second": Double(samples.count) / max(elapsed.seconds, 0.001), "formats": formats,
                "cache_bytes": usage]
    }

    /// Decodes cached renditions at grid size: single-threaded latency, then
    /// end-to-end through `PreviewService` with a cold memory cache.
    static func readCache(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let library = try BenchLibrary(arguments)
        let tier = tier(arguments)
        let pixelSize = arguments.int("pixel-size", default: 360)
        let limit = arguments.int("limit", default: 2000)
        let service = library.service()
        let requests = try await library.itemsWithSources().prefix(limit).compactMap { item, url -> PreviewRequest? in
            guard let key = PreviewCacheKey(item: item, tier: tier), service.cache.contains(key) else { return nil }
            return PreviewRequest(versionID: item.versionID, key: key, sourceURL: url)
        }
        print("Reading \(requests.count) cached \(tier.rawValue) renditions at \(pixelSize) px")

        var single: [Double] = []
        for request in requests.prefix(500) {
            let (_, duration) = await measure { _ = service.cache.loadImage(for: request.key, maxPixelSize: pixelSize) }
            single.append(duration.milliseconds)
        }
        let singleStats = Stats(single)
        print("  disk decode, one at a time: \(singleStats.line)")

        service.clearMemory()
        let (latencies, elapsed) = await measure {
            await withTaskGroup(of: Double.self) { group in
                for request in requests {
                    group.addTask {
                        let (_, duration) = await measure { _ = try? await service.image(for: request, maxPixelSize: pixelSize) }
                        return duration.milliseconds
                    }
                }
                var all: [Double] = []
                for await value in group { all.append(value) }
                return all
            }
        }
        let throughput = Double(requests.count) / max(elapsed.seconds, 0.001)
        print(String(format: "  through PreviewService, all requested at once: %.0f images/s", throughput))
        print("    time to image (includes queueing): \(Stats(latencies).line)")

        let (_, memoryElapsed) = await measure {
            for request in requests { _ = service.memoryCachedImage(for: request, maxPixelSize: pixelSize) }
        }
        let memoryMicros = memoryElapsed.milliseconds * 1000 / Double(max(requests.count, 1))
        print(String(format: "  memory cache lookup: %.1f µs each", memoryMicros))
        return ["machine": machineDescription(), "tier": tier.rawValue, "pixel_size": pixelSize, "count": requests.count,
                "single_decode": singleStats.dictionary, "service_per_second": throughput,
                "service_latency": Stats(latencies).dictionary, "memory_lookup_us": memoryMicros]
    }
}

enum QueryBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let library = try BenchLibrary(arguments)
        let catalog = library.catalog
        let projects = try await catalog.projectSummaries()
        let largest = projects.max { $0.versionCount < $1.versionCount }
        var filters: [(String, LibraryFilter)] = [
            ("all", LibraryFilter()),
            ("rating>=3", LibraryFilter(rating: .atLeast(Rating(clamping: 3)))),
            ("picked", LibraryFilter(flag: .picked)),
            ("not rejected", LibraryFilter(flag: .notRejected)),
        ]
        if let largest { filters.append(("largest project", LibraryFilter(scope: .project(largest.id)))) }

        let total = try await catalog.versionCount()
        print("Catalog with \(total) versions in \(projects.count) projects")
        var report: [String: any Sendable] = ["machine": machineDescription(), "versions": total]

        // Mark some items so the filters return something.
        let all = try await catalog.libraryItems(matching: LibraryFilter())
        let sample = stride(from: 0, to: all.count, by: 7).map { all[$0].versionID }
        try await catalog.setRating(Rating(clamping: 3), forVersions: sample)
        try await catalog.setFlag(.picked, forVersions: sample.prefix(sample.count / 2))

        for (name, filter) in filters {
            var times: [Double] = []
            var count = 0
            for _ in 0..<7 {
                let (items, duration) = try await measure { try await catalog.libraryItems(matching: filter) }
                count = items.count
                times.append(duration.milliseconds)
            }
            let stats = Stats(times)
            print(String(format: "  query %-16@ %6d rows   median %.1f ms   max %.1f ms", name as NSString, count, stats.percentile(0.5), stats.max))
            let entry: [String: any Sendable] = ["rows": count, "median_ms": stats.percentile(0.5), "max_ms": stats.max]
            report["query \(name)"] = entry
        }

        let (_, summaryTime) = try await measure { try await catalog.projectSummaries() }
        print(String(format: "  project summaries          %.1f ms", summaryTime.milliseconds))
        report["project_summaries_ms"] = summaryTime.milliseconds

        var writes: [Double] = []
        for index in 0..<300 {
            let id = all[(index * 31) % all.count].versionID
            let (_, duration) = try await measure { try await catalog.setRating(Rating(clamping: index % 6), forVersions: [id]) }
            writes.append(duration.milliseconds)
        }
        let writeStats = Stats(writes)
        print("  single rating write:       \(writeStats.line)")
        report["rating_write"] = writeStats.dictionary
        // Leave the library the way it was.
        try await catalog.setRating(.unrated, forVersions: all.map(\.versionID))
        try await catalog.setFlag(.none, forVersions: all.map(\.versionID))
        return report
    }
}

/// Grows a catalog for grid-scale tests: clones existing masters under new content
/// hashes and hard-links their cached renditions, so the grid sees N distinct
/// cache keys without rendering N previews.
enum Synthesize {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let library = try BenchLibrary(arguments)
        let target = arguments.int("count", default: 50_000)
        let catalog = library.catalog
        let cache = PreviewDiskCache(root: library.locations.previewCacheDirectory)
        let originals = try await catalog.libraryItems(matching: LibraryFilter())
        let images = try await catalog.allImages()
        let byID = Dictionary(uniqueKeysWithValues: images.compactMap { image in image.id.map { ($0, image) } })
        guard !originals.isEmpty, let volumeID = originals.first?.volumeID else { throw BenchError("catalog is empty") }
        let needed = target - originals.count
        guard needed > 0 else {
            print("Catalog already has \(originals.count) versions")
            return ["versions": originals.count]
        }
        let project = try await catalog.createProject(name: "Synthetic clones")
        var masters: [NewMaster] = []
        var links = 0
        for index in 0..<needed {
            let original = originals[index % originals.count]
            guard let image = byID[original.imageID] else { continue }
            let hash = String(Digest.sha256Hex("clone-\(index)-\(original.contentHash)"))
            var metadata = image.metadata
            metadata.captureDate = (image.captureDate ?? image.sortDate).addingTimeInterval(Double(index / originals.count + 1) * 86_400)
            masters.append(NewMaster(relativePath: image.relativePath + ".clone-\(index)", fileSize: image.fileSize,
                                     modifiedAt: image.modifiedAt, contentHash: hash, metadata: metadata))
            for tier in PreviewTier.allCases {
                guard let from = PreviewCacheKey(item: original, tier: tier),
                      let to = PreviewCacheKey(contentHash: hash, editStackHash: original.editStackHash, tier: tier),
                      cache.contains(from) else { continue }
                let destination = cache.url(for: to)
                try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? FileManager.default.linkItem(at: cache.url(for: from), to: destination)) != nil { links += 1 }
            }
            if masters.count == 1000 {
                _ = try await catalog.insertMasters(masters, volumeID: volumeID, projectID: project.id!)
                masters.removeAll()
            }
        }
        _ = try await catalog.insertMasters(masters, volumeID: volumeID, projectID: project.id!)
        let total = try await catalog.versionCount()
        print("Catalog now has \(total) versions (\(links) cached renditions hard-linked)")
        return ["versions": total, "links": links]
    }
}

/// Times on-device keyword analysis the way the app runs it: cached thumbnail,
/// Vision classification, then storing the suggestions.
enum SuggestionBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let library = try BenchLibrary(arguments)
        let limit = arguments.int("limit", default: 500)
        let service = library.service()
        let suggester = VisionKeywordSuggester()
        let candidates = try await library.itemsWithSources().prefix(limit).compactMap { item, url -> (CatalogItem, PreviewRequest)? in
            guard let key = PreviewCacheKey(item: item, tier: .thumbnail) else { return nil }
            return (item, PreviewRequest(versionID: item.versionID, key: key, sourceURL: url))
        }
        print("Analyzing \(candidates.count) photos (thumbnails are generated when not cached)")

        var load: [Double] = []
        var classify: [Double] = []
        var store: [Double] = []
        var labels = 0
        let (_, elapsed) = try await measure {
            for (item, request) in candidates {
                let (image, loadTime) = await measure { try? await service.image(for: request, maxPixelSize: 512, priority: .background) }
                load.append(loadTime.milliseconds)
                guard let image else { continue }
                let (suggestions, classifyTime) = try await measure { try await suggester.suggestions(for: image) }
                classify.append(classifyTime.milliseconds)
                labels += suggestions.count
                let (_, storeTime) = try await measure {
                    try await library.catalog.storeSuggestions(suggestions, forImage: item.imageID,
                                                               analysisVersion: suggester.analysisVersion)
                }
                store.append(storeTime.milliseconds)
            }
        }
        let perSecond = Double(candidates.count) / max(elapsed.seconds, 0.001)
        print(String(format: "  %.0f photos/s one at a time, %.1f suggestions per photo", perSecond,
                     Double(labels) / Double(max(classify.count, 1))))
        print("  thumbnail: \(Stats(load).line)")
        print("  classify:  \(Stats(classify).line)")
        print("  store:     \(Stats(store).line)")
        return ["machine": machineDescription(), "count": candidates.count, "per_second": perSecond,
                "thumbnail": Stats(load).dictionary, "classify": Stats(classify).dictionary,
                "store": Stats(store).dictionary]
    }
}
