import Foundation
import os

public struct ImportOptions: Sendable {
    /// Project name; defaults to the imported folder's name.
    public var projectName: String?
    /// Files per catalog transaction and progress update.
    public var chunkSize: Int
    /// Files hashed at the same time.
    public var hashingConcurrency: Int

    public init(projectName: String? = nil, chunkSize: Int = 64, hashingConcurrency: Int = 4) {
        self.projectName = projectName
        self.chunkSize = max(1, chunkSize)
        self.hashingConcurrency = max(1, hashingConcurrency)
    }
}

public struct ImportProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case scanning
        case importing
        case finished
    }

    public var phase: Phase
    public var filesFound = 0
    public var filesProcessed = 0
    public var imported = 0
    /// Same content as a master already in the catalog (or earlier in this import).
    public var duplicates = 0
    /// Same path, size and date as a master already in the catalog.
    public var alreadyInCatalog = 0
    /// A catalogued path whose content changed on disk. Skipped in phase 1.
    public var changedOnDisk = 0
    public var failed = 0

    public init(phase: Phase) {
        self.phase = phase
    }
}

public struct ImportFailure: Sendable, Equatable {
    public var path: String
    public var reason: String
}

public struct ImportTimings: Sendable, Equatable {
    public var scan: Duration = .zero
    public var hash: Duration = .zero
    public var metadata: Duration = .zero
    public var catalog: Duration = .zero
    public var total: Duration = .zero
}

public struct ImportSummary: Sendable {
    /// The project created for this import; nil when nothing new was found.
    public var project: ProjectRecord?
    public var progress: ImportProgress
    public var failures: [ImportFailure]
    public var insertedVersionIDs: [Int64]
    public var timings: ImportTimings
}

/// Registers the image files under a folder as referenced masters.
///
/// Files are never moved, copied or written. The work runs in chunks: unchanged
/// known paths are skipped without hashing, the rest are hashed in parallel,
/// de-duplicated by content hash (against the catalog and earlier files of the
/// same import), their metadata is read in one batch, and the chunk is inserted
/// in one transaction. Cancelling the calling task stops at the next file or
/// chunk boundary; chunks already written stay in the catalog.
public final class Importer: Sendable {
    public let catalog: Catalog
    public let metadataReader: any MetadataReader
    public let hasher: any ContentHasher

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "import")

    public init(catalog: Catalog, metadataReader: any MetadataReader,
                hasher: any ContentHasher = SHA256ContentHasher()) {
        self.catalog = catalog
        self.metadataReader = metadataReader
        self.hasher = hasher
    }

    public func importFolder(
        _ folder: URL,
        options: ImportOptions = ImportOptions(),
        progress report: @Sendable (ImportProgress) -> Void = { _ in }
    ) async throws -> ImportSummary {
        let clock = ContinuousClock()
        let started = clock.now
        var timings = ImportTimings()
        var progress = ImportProgress(phase: .scanning)
        report(progress)

        let scanStart = clock.now
        let files = try FileScanner.scan(folder)
        timings.scan = clock.now - scanStart
        progress.phase = .importing
        progress.filesFound = files.count
        report(progress)

        let projectName = options.projectName ?? Self.defaultProjectName(for: folder)
        var run = Run(projectName: projectName, sourcePath: folder.path)

        // Files are grouped by volume so each chunk maps onto one volume row.
        let byVolume = Dictionary(grouping: files, by: \.volumeURL)
        for volumeURL in byVolume.keys.sorted(by: { $0.path < $1.path }) {
            let descriptor = try VolumeResolver.descriptor(forVolumeAt: volumeURL)
            let volume = try await catalog.registerVolume(descriptor)
            guard let volumeID = volume.id else { continue }
            let volumeFiles = byVolume[volumeURL] ?? []
            for start in stride(from: 0, to: volumeFiles.count, by: options.chunkSize) {
                try Task.checkCancellation()
                let chunk = Array(volumeFiles[start..<min(start + options.chunkSize, volumeFiles.count)])
                try await importChunk(chunk, volume: volume, volumeID: volumeID, options: options,
                                      run: &run, progress: &progress, timings: &timings)
                report(progress)
            }
        }

        progress.phase = .finished
        timings.total = clock.now - started
        report(progress)
        Self.log.info("Imported \(progress.imported) of \(progress.filesFound) files from \(folder.path, privacy: .public)")
        return ImportSummary(project: run.project, progress: progress, failures: run.failures,
                             insertedVersionIDs: run.insertedVersionIDs, timings: timings)
    }

    static func defaultProjectName(for folder: URL) -> String {
        let name = folder.lastPathComponent
        return name.isEmpty || name == "/" ? folder.path : name
    }

    /// Mutable state of one import.
    private struct Run {
        var projectName: String
        var sourcePath: String
        var project: ProjectRecord?
        var importRun: ImportRunRecord?
        var seenHashes: Set<String> = []
        var failures: [ImportFailure] = []
        var insertedVersionIDs: [Int64] = []
    }

    private struct Candidate {
        var file: ScannedFile
        var relativePath: String
        var known: KnownFile?
        var hash: String = ""
    }

    private func importChunk(
        _ chunk: [ScannedFile], volume: VolumeRecord, volumeID: Int64, options: ImportOptions,
        run: inout Run, progress: inout ImportProgress, timings: inout ImportTimings
    ) async throws {
        let clock = ContinuousClock()

        // 1. Paths the catalog already has with the same size and date need no work.
        var candidates: [Candidate] = []
        for file in chunk {
            guard let relativePath = VolumeResolver.relativePath(of: file.url, inVolumeAt: volume.mountPath) else {
                run.failures.append(ImportFailure(path: file.url.path, reason: "not on volume \(volume.mountPath)"))
                progress.failed += 1
                continue
            }
            candidates.append(Candidate(file: file, relativePath: relativePath))
        }
        var catalogStart = clock.now
        let known = try await catalog.knownFiles(volumeID: volumeID, relativePaths: candidates.map(\.relativePath))
        timings.catalog += clock.now - catalogStart
        var toHash: [Candidate] = []
        for var candidate in candidates {
            candidate.known = known[candidate.relativePath]
            // The catalog keeps dates to the millisecond.
            if let existing = candidate.known, existing.fileSize == candidate.file.fileSize,
               abs(existing.modifiedAt.timeIntervalSince(candidate.file.modifiedAt)) < 0.001 {
                progress.alreadyInCatalog += 1
            } else {
                toHash.append(candidate)
            }
        }

        // 2. Hash what is left.
        let hashStart = clock.now
        let hashes = try await hashFiles(toHash.map(\.file.url), concurrency: options.hashingConcurrency)
        timings.hash += clock.now - hashStart

        // 3. Drop duplicates and changed known paths.
        var fresh: [Candidate] = []
        for var candidate in toHash {
            switch hashes[candidate.file.url] {
            case .failure(let error):
                run.failures.append(ImportFailure(path: candidate.file.url.path, reason: error.localizedDescription))
                progress.failed += 1
            case .success(let hash):
                candidate.hash = hash
                if let existing = candidate.known {
                    if existing.contentHash == hash {
                        progress.alreadyInCatalog += 1
                    } else {
                        progress.changedOnDisk += 1
                    }
                } else if run.seenHashes.contains(hash) {
                    progress.duplicates += 1
                } else {
                    run.seenHashes.insert(hash)
                    fresh.append(candidate)
                }
            case nil:
                break
            }
        }
        catalogStart = clock.now
        let inCatalog = try await catalog.existingContentHashes(fresh.map(\.hash))
        timings.catalog += clock.now - catalogStart
        let newMasters = fresh.filter { !inCatalog.contains($0.hash) }
        progress.duplicates += fresh.count - newMasters.count

        // 4. Metadata and insert.
        if !newMasters.isEmpty {
            let metadataStart = clock.now
            let metadata = try await metadataReader.metadata(for: newMasters.map(\.file.url))
            timings.metadata += clock.now - metadataStart

            catalogStart = clock.now
            if run.project == nil {
                run.project = try await catalog.createProject(name: run.projectName, sourcePath: run.sourcePath)
                run.importRun = try await catalog.createImportRun(sourcePath: run.sourcePath, projectID: run.project?.id)
            }
            let masters = newMasters.map { candidate in
                NewMaster(relativePath: candidate.relativePath, fileSize: candidate.file.fileSize,
                          modifiedAt: candidate.file.modifiedAt, contentHash: candidate.hash,
                          metadata: metadata[candidate.file.url] ?? .empty)
            }
            let result = try await catalog.insertMasters(masters, volumeID: volumeID, projectID: run.project!.id!,
                                                         importRunID: run.importRun?.id)
            timings.catalog += clock.now - catalogStart
            progress.imported += result.insertedImageIDs.count
            progress.duplicates += result.duplicateHashes.count
            progress.changedOnDisk += result.conflictingPaths.count
            run.insertedVersionIDs += result.insertedVersionIDs
        }
        progress.filesProcessed += chunk.count
    }

    private func hashFiles(_ urls: [URL], concurrency: Int) async throws -> [URL: Result<String, any Error>] {
        let hasher = self.hasher
        return try await withThrowingTaskGroup(of: (URL, Result<String, any Error>).self) { group in
            var results: [URL: Result<String, any Error>] = [:]
            var pending = urls.makeIterator()
            func addNext() {
                guard let url = pending.next() else { return }
                group.addTask {
                    do {
                        return (url, .success(try await hasher.contentHash(of: url)))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }
            for _ in 0..<concurrency { addNext() }
            while let (url, result) = try await group.next() {
                results[url] = result
                addNext()
            }
            return results
        }
    }
}
