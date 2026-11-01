import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

private let hashA = String(repeating: "ab", count: 32)
private let hashB = String(repeating: "cd", count: 32)

@Suite("Preview cache keys")
struct PreviewCacheKeyTests {
    @Test func keysAreDeterministicAndLaidOutByMaster() throws {
        let key = try #require(PreviewCacheKey(contentHash: hashA, editStackHash: EditStack.identity.renderHash, tier: .thumbnail))
        #expect(key.relativePath == "v\(PreviewCacheKey.currentPipelineVersion)/thumb/ab/\(hashA)-6c76a50e5dc3f0cd.jpg")
        #expect(key == PreviewCacheKey(contentHash: hashA, editStackHash: EditStack.identity.renderHash, tier: .thumbnail))
    }

    @Test func everyComponentChangesTheKey() throws {
        let identity = EditStack.identity.renderHash
        let edited = EditStack(operations: [EditOperation(kind: "exposure", parameters: ["ev": .number(1)])]).renderHash
        let base = try #require(PreviewCacheKey(contentHash: hashA, editStackHash: identity, tier: .thumbnail))
        let variants = [
            PreviewCacheKey(contentHash: hashB, editStackHash: identity, tier: .thumbnail),
            PreviewCacheKey(contentHash: hashA, editStackHash: edited, tier: .thumbnail),
            PreviewCacheKey(contentHash: hashA, editStackHash: identity, tier: .preview),
            PreviewCacheKey(contentHash: hashA, editStackHash: identity, tier: .thumbnail, pipelineVersion: PreviewCacheKey.currentPipelineVersion + 1),
        ].compactMap { $0 }
        #expect(variants.count == 4)
        #expect(Set(variants.map(\.relativePath) + [base.relativePath]).count == 5)
    }

    @Test func disabledEditsShareTheIdentityKey() throws {
        let disabled = EditStack(operations: [EditOperation(kind: "exposure", isEnabled: false, parameters: ["ev": .number(1)])])
        #expect(PreviewCacheKey(contentHash: hashA, editStackHash: disabled.renderHash, tier: .preview)
            == PreviewCacheKey(contentHash: hashA, editStackHash: EditStack.identity.renderHash, tier: .preview))
    }

    @Test func rejectsHashesThatCouldEscapeTheCache() {
        #expect(PreviewCacheKey(contentHash: "../../etc/passwd/aaaaaaaaaaaaaaa", editStackHash: hashA, tier: .thumbnail) == nil)
        #expect(PreviewCacheKey(contentHash: hashA.uppercased(), editStackHash: hashA, tier: .thumbnail) == nil)
        #expect(PreviewCacheKey(contentHash: "abc", editStackHash: hashA, tier: .thumbnail) == nil)
        #expect(PreviewCacheKey(contentHash: hashA, editStackHash: hashA, tier: .thumbnail, pipelineVersion: 0) == nil)
    }

    @Test func keysComeFromCatalogItems() throws {
        let item = CatalogItem(versionID: 1, imageID: 1, volumeID: 1, rating: .unrated, flag: .none, colorLabel: .none,
                               contentHash: hashA, editStackHash: hashB, relativePath: "a.jpg",
                               pixelWidth: 10, pixelHeight: 10, orientation: 1)
        #expect(PreviewCacheKey(item: item, tier: .preview)
            == PreviewCacheKey(contentHash: hashA, editStackHash: hashB, tier: .preview))
    }
}

@Suite("Preview pipeline")
struct PreviewPipelineTests {
    private func writeJPEG(_ url: URL, width: Int, height: Int, seed: UInt64 = 1, orientation: Int = 1) throws {
        try SyntheticImages.writeJPEG(to: url, width: width, height: height, seed: seed,
                                      exif: .init(dateTimeOriginal: "2024:01:01 00:00:00", orientation: orientation))
    }

    private func size(of data: Data) -> (Int, Int, String?) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        return (props[kCGImagePropertyPixelWidth] as! Int, props[kCGImagePropertyPixelHeight] as! Int,
                image.colorSpace?.name as String?)
    }

    @Test func diskCacheStoresLoadsAndCanBeWiped() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let cache = PreviewDiskCache(root: root.appending(path: "Previews"))
            let key = try #require(PreviewCacheKey(contentHash: hashA, editStackHash: hashB, tier: .thumbnail))
            #expect(!cache.contains(key))
            #expect(cache.loadImage(for: key) == nil)

            let source = root.appending(path: "src.jpg")
            try writeJPEG(source, width: 512, height: 256)
            try cache.store(try Data(contentsOf: source), for: key)
            #expect(cache.contains(key))
            #expect(cache.loadImage(for: key)?.width == 512)
            #expect(cache.loadImage(for: key, maxPixelSize: 128)?.width == 128)
            #expect(cache.diskUsage() > 0)

            let old = try #require(PreviewCacheKey(contentHash: hashA, editStackHash: hashB, tier: .thumbnail, pipelineVersion: 7))
            try cache.store(Data([1, 2, 3]), for: old)
            cache.removeObsoletePipelineVersions()
            #expect(cache.contains(key))
            #expect(!cache.contains(old))

            try cache.removeAll()
            #expect(!cache.contains(key))
            #expect(cache.loadImage(for: key) == nil)
        }
    }

    @Test func renderEngineIsMetalBackedAndOutputsDisplayP3() {
        let engine = RenderEngine()
        #expect(engine.isMetalBacked)
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let cgImage = engine.makeCGImage(image)
        #expect(cgImage?.colorSpace?.name == CGColorSpace.displayP3)
        #expect(cgImage?.width == 8)
    }

    @Test func jpegMastersAreDownsampledOrientedAndNeverUpscaled() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let generator = PreviewGenerator()
            let large = root.appending(path: "large.jpg")
            try writeJPEG(large, width: 1600, height: 1000)
            let (w1, h1, space1) = size(of: try generator.jpegData(source: large, stack: .identity, tier: .thumbnail))
            #expect((w1, h1) == (512, 320))
            #expect(space1 == CGColorSpace.displayP3 as String)

            let small = root.appending(path: "small.jpg")
            try writeJPEG(small, width: 300, height: 200)
            let (w2, h2, _) = size(of: try generator.jpegData(source: small, stack: .identity, tier: .thumbnail))
            #expect((w2, h2) == (300, 200))

            let rotated = root.appending(path: "rotated.jpg")
            try writeJPEG(rotated, width: 300, height: 200, orientation: 6)
            let (w3, h3, _) = size(of: try generator.jpegData(source: rotated, stack: .identity, tier: .preview))
            #expect((w3, h3) == (200, 300))

            let full = try generator.cgImage(source: large, stack: .identity)
            #expect((full.width, full.height) == (1600, 1000))
        }
    }

    @Test func dngMastersDecodeThroughCIRAWFilter() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let dng = root.appending(path: "synthetic.dng")
            try SyntheticDNG.write(to: dng, options: .init(width: 1200, height: 800, seed: 5, dateTimeOriginal: "2024:02:03 04:05:06"))
            let raw = try #require(CIRAWFilter(imageURL: dng), "CIRAWFilter rejected the synthetic DNG")
            #expect(raw.nativeSize == CGSize(width: 1200, height: 800))

            let generator = PreviewGenerator()
            let (w, h, _) = size(of: try generator.jpegData(source: dng, stack: .identity, tier: .thumbnail))
            // RAW decodes at a reduced scale first, so the short edge may round either way.
            #expect(w == 512 && (341...342).contains(h))
            let full = try generator.cgImage(source: dng, stack: .identity)
            #expect((full.width, full.height) == (1200, 800))

            let metadata = try #require(ImageIOMetadataReader.read(dng))
            #expect(metadata.pixelWidth == 1200)
            #expect(metadata.captureDate == ExifDate.parse("2024:02:03 04:05:06")?.date)
        }
    }

    @Test func hdrRenditionsKeepHighlightsAboveWhite() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let generator = PreviewGenerator()
            let plain = root.appending(path: "plain.jpg")
            try writeJPEG(plain, width: 800, height: 600)
            #expect(try generator.hdrImage(source: plain, stack: .identity, longEdge: 512) == nil)

            // A JPEG with a gain map whose HDR rendition has a patch at four times SDR white.
            let engine = generator.engine
            let sdr = try #require(CIImage(contentsOf: plain))
            let patch = CIImage(color: CIColor(red: 4, green: 4, blue: 4, colorSpace: RenderEngine.hdrColorSpace)!)
                .cropped(to: CGRect(x: 100, y: 100, width: 200, height: 150))
            let hdr = patch.composited(over: sdr)
            let data = try #require(engine.withContext {
                $0.jpegRepresentation(of: sdr, colorSpace: RenderEngine.outputColorSpace, options: [.hdrImage: hdr])
            })
            let gainMapped = root.appending(path: "gain-map.jpg")
            try data.write(to: gainMapped)

            let image = try #require(try generator.hdrImage(source: gainMapped, stack: .identity, longEdge: 512))
            #expect((image.width, image.height) == (512, 384))
            #expect(image.bitsPerComponent == 16 && image.bitmapInfo.contains(.floatComponents))
            #expect(image.colorSpace?.name == CGColorSpace.extendedLinearDisplayP3)
            #expect(image.contentHeadroom > 2)

            let dng = root.appending(path: "synthetic.dng")
            try SyntheticDNG.write(to: dng, options: .init(width: 1200, height: 800, seed: 5))
            // A camera's integer raw stays SDR; only floating-point DNGs (HDR merges) count.
            #expect(try generator.hdrImage(source: dng, stack: .identity, longEdge: 512) == nil)
        }
    }

    @Test func dngLayoutDescribesRawImages() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            typealias Image = SyntheticDNG.SubImage
            func layout(_ name: String, _ subIFDs: [Image]) throws -> DNGLayout? {
                let url = root.appending(path: name)
                try SyntheticDNG.structureData(subIFDs: subIFDs).write(to: url)
                return DNGLayout(contentsOf: url)
            }
            // A Lightroom HDR merge: full float linear raw, transparency mask, preview, reduced linear raw.
            let merge = try #require(try layout("merge.dng", [Image(0, 34892, sampleFormat: 3), Image(4, 32844),
                                                              Image(1, 2), Image(1, 34892, sampleFormat: 3)]))
            #expect(merge.images.count == 5)
            #expect(merge.hasReducedLinearRaw && merge.hasFloatingPointRaw)
            let reducedOnly = try #require(try layout("single.dng", [Image(1, 34892)]))
            #expect(reducedOnly.hasReducedLinearRaw && !reducedOnly.hasFloatingPointRaw)
            let linear = try #require(try layout("linear.dng", [Image(0, 34892), Image(1, 2)]))
            #expect(!linear.hasReducedLinearRaw && !linear.hasFloatingPointRaw)
            let floatBayer = try #require(try layout("float-bayer.dng", [Image(0, 32803, sampleFormat: 3), Image(1, 6)]))
            #expect(!floatBayer.hasReducedLinearRaw && floatBayer.hasFloatingPointRaw)
            // A floating-point preview does not make the raw an HDR one.
            let floatPreview = try #require(try layout("float-preview.dng", [Image(0, 32803), Image(1, 2, sampleFormat: 3)]))
            #expect(!floatPreview.hasFloatingPointRaw)
            #expect(try layout("merge.tif", [Image(0, 34892, sampleFormat: 3)]) == nil)

            let bayer = root.appending(path: "synthetic.dng")
            try SyntheticDNG.write(to: bayer, options: .init(width: 64, height: 64, seed: 1))
            let camera = try #require(DNGLayout(contentsOf: bayer))
            #expect(camera.images.count == 1 && !camera.hasReducedLinearRaw && !camera.hasFloatingPointRaw)
            let truncated = root.appending(path: "truncated.dng")
            try Data(SyntheticDNG.structureData(subIFDs: [Image(0, 34892), Image(1, 34892)]).prefix(20)).write(to: truncated)
            #expect(DNGLayout(contentsOf: truncated) == nil)
        }
    }

    @Test func serviceGeneratesOnceThenServesFromCache() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let source = root.appending(path: "a.jpg")
            try writeJPEG(source, width: 800, height: 600)
            let loads = Mutex(0)
            let service = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "cache")),
                                         editStack: { _ in loads.withLock { $0 += 1 }; return .identity })
            let key = try #require(PreviewCacheKey(contentHash: hashA, editStackHash: EditStack.identity.renderHash, tier: .thumbnail))
            let request = PreviewRequest(versionID: 1, key: key, sourceURL: source)

            #expect(service.memoryCachedImage(for: request) == nil)
            let first = try await service.image(for: request)
            #expect(first.width == 512)
            #expect(service.cache.contains(key))
            #expect(service.memoryCachedImage(for: request) != nil)

            // Several concurrent requests for a fresh key generate once.
            let other = try #require(PreviewCacheKey(contentHash: hashB, editStackHash: EditStack.identity.renderHash, tier: .thumbnail))
            let otherRequest = PreviewRequest(versionID: 2, key: other, sourceURL: source)
            try await withThrowingTaskGroup(of: Int.self) { group in
                for _ in 0..<8 { group.addTask { try await service.image(for: otherRequest, maxPixelSize: 200).width } }
                for try await width in group { #expect(width == 256) }
            }
            #expect(loads.withLock { $0 } == 2)

            // After a memory flush the disk copy is used; no regeneration.
            service.clearMemory()
            _ = try await service.image(for: request)
            #expect(loads.withLock { $0 } == 2)

            // Deleting the cache directory is safe: the next request regenerates.
            try FileManager.default.removeItem(at: root.appending(path: "cache"))
            service.clearMemory()
            _ = try await service.image(for: request)
            #expect(loads.withLock { $0 } == 3)
        }
    }

    @Test func offlineMastersAreServedFromCacheOnly() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let source = root.appending(path: "a.jpg")
            try writeJPEG(source, width: 400, height: 300)
            let service = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "cache")), editStack: { _ in .identity })
            let cachedKey = try #require(PreviewCacheKey(contentHash: hashA, editStackHash: hashB, tier: .preview))
            let missingKey = try #require(PreviewCacheKey(contentHash: hashB, editStackHash: hashB, tier: .preview))
            try await service.prepare(PreviewRequest(versionID: 1, key: cachedKey, sourceURL: source))

            let offlineCached = PreviewRequest(versionID: 1, key: cachedKey, sourceURL: nil)
            #expect(try await service.image(for: offlineCached).width == 400)
            await #expect(throws: PreviewService.Failure.sourceUnavailable) {
                _ = try await service.image(for: PreviewRequest(versionID: 2, key: missingKey, sourceURL: nil))
            }
        }
    }
}

/// A mutex held by reference: Swift 6.3 rejects capturing a local `Mutex` in a closure sent to a task.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) { mutex = Mutex(value) }

    func withLock<Result: Sendable>(_ body: (inout Value) -> Result) -> Result {
        mutex.withLock { body(&$0) }
    }
}

/// Opens once; everyone waiting is released.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

@Suite("Work lane")
struct WorkLaneTests {
    @Test func requestsForTheSameKeyShareOneJob() async throws {
        let lane = WorkLane<Int>(concurrency: 2)
        let runs = Locked(0)
        let gate = Gate()
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await lane.run(key: "k", priority: 1) {
                        runs.withLock { $0 += 1 }
                        await gate.wait()
                        return 42
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(50))
            await gate.open()
            for try await value in group { #expect(value == 42) }
        }
        #expect(runs.withLock { $0 } == 1)
    }

    @Test func higherPriorityAndNewerRequestsRunFirst() async throws {
        let lane = WorkLane<String>(concurrency: 1)
        let order = Locked<[String]>([])
        let gate = Gate()
        let blocker = Task { try await lane.run(key: "blocker", priority: 2) { await gate.wait(); return "blocker" } }
        try await Task.sleep(for: .milliseconds(20))

        var tasks: [Task<String, any Error>] = []
        for (key, priority) in [("old-low", 0), ("old-visible", 2), ("new-low", 0), ("new-visible", 2)] {
            tasks.append(Task { try await lane.run(key: key, priority: priority) { order.withLock { $0.append(key) }; return key } })
            try await Task.sleep(for: .milliseconds(10))
        }
        await gate.open()
        _ = try await blocker.value
        for task in tasks { _ = try await task.value }
        #expect(order.withLock { $0 } == ["new-visible", "old-visible", "new-low", "old-low"])
    }

    @Test func cancellingTheLastWaiterCancelsTheJob() async throws {
        let lane = WorkLane<Int>(concurrency: 1)
        let started = Gate()
        let sawCancellation = Mutex(false)
        let pendingRan = Mutex(false)

        let running = Task {
            try await lane.run(key: "running", priority: 1) {
                await started.open()
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    sawCancellation.withLock { $0 = true }
                    throw error
                }
                return 1
            }
        }
        await started.wait()
        let pending = Task { try await lane.run(key: "pending", priority: 1) { pendingRan.withLock { $0 = true }; return 2 } }
        try await Task.sleep(for: .milliseconds(20))

        pending.cancel()
        await #expect(throws: CancellationError.self) { _ = try await pending.value }
        running.cancel()
        await #expect(throws: CancellationError.self) { _ = try await running.value }
        try await Task.sleep(for: .milliseconds(50))
        #expect(sawCancellation.withLock { $0 })
        #expect(!pendingRan.withLock { $0 }, "a pending job with no waiters must not start")

        // The lane keeps working afterwards.
        #expect(try await lane.run(key: "after", priority: 1) { 3 } == 3)
    }

    @Test func aJobKeepsRunningWhileOtherWaitersRemain() async throws {
        let lane = WorkLane<Int>(concurrency: 1)
        let gate = Gate()
        let first = Task { try await lane.run(key: "shared", priority: 1) { await gate.wait(); return 7 } }
        try await Task.sleep(for: .milliseconds(20))
        let second = Task { try await lane.run(key: "shared", priority: 1) { 0 } }
        try await Task.sleep(for: .milliseconds(20))
        first.cancel()
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        await gate.open()
        #expect(try await second.value == 7)
    }

    @Test func reservedSlotsStartOnlyUrgentJobs() async throws {
        let lane = WorkLane<String>(concurrency: 3, reserved: 1, reservedPriority: 2)
        let started = Locked<[String]>([])
        let gate = Gate()
        func job(_ key: String, _ priority: Int) -> Task<String, any Error> {
            Task { try await lane.run(key: key, priority: priority) { started.withLock { $0.append(key) }; await gate.wait(); return key } }
        }
        /// Waits for `condition` up to two seconds: under a loaded test run, tasks
        /// can take longer than a fixed sleep to start.
        func eventually(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(2)
            while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        }
        var tasks = (0..<4).map { job("background-\($0)", 0) }
        try await eventually { started.withLock { $0.count } >= 2 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(started.withLock { $0.count } == 2, "background work leaves the reserved slot free")

        tasks.append(job("visible", 2))
        try await eventually { started.withLock { $0.contains("visible") } }
        #expect(started.withLock { $0.contains("visible") }, "an urgent job starts at once in the reserved slot")
        #expect(started.withLock { $0.count } == 3)

        await gate.open()
        for task in tasks { _ = try await task.value }
        #expect(started.withLock { $0.count } == 5)
    }
}

@Suite("Render engine")
struct RenderEngineTests {
    @Test func rendersRunOnTheLeastBusyContext() async throws {
        let engine = RenderEngine(contextCount: 3)
        #expect(engine.contextCount == 3)
        let identifiers = engine.withContext { first in
            engine.withContext { second in
                engine.withContext { third in [first, second, third].map(ObjectIdentifier.init) }
            }
        }
        #expect(Set(identifiers).count == 3, "renders in flight get different contexts")
        let again = engine.withContext(ObjectIdentifier.init)
        #expect(again == identifiers[0], "the first context is free again")
    }
}
