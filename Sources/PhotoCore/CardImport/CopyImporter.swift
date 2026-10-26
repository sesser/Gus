import CryptoKit
import Foundation
import os

/// Where copied photos go in the catalog.
public enum ProjectChoice: Hashable, Sendable {
    case existing(Int64)
    /// A new project, its name rendered from a template such as
    /// "{capture:yyyy-MM-dd} {job}" with the first shot.
    case new(nameTemplate: String)
}

public struct CopyImportOptions: Sendable {
    public var destination: URL
    public var template: ImportTemplate
    public var project: ProjectChoice
    public var jobCode: String
    /// The persistent counter's next value (`{counter}`).
    public var firstCounter: Int
    /// Creator, copyright, usage terms and contact to give every copied photo.
    /// Text may use template tokens ("© {capture:yyyy} Pat Doe"). Applying it
    /// always writes sidecars, whatever the sidecar setting.
    public var metadata: SidecarValues?

    public init(destination: URL, template: ImportTemplate = ImportTemplate(),
                project: ProjectChoice = .new(nameTemplate: "{capture:yyyy-MM-dd} {job}"), jobCode: String = "",
                firstCounter: Int = 1, metadata: SidecarValues? = nil) {
        self.destination = destination
        self.template = template
        self.project = project
        self.jobCode = jobCode
        self.firstCounter = firstCounter
        self.metadata = metadata
    }
}

public struct CopyImportProgress: Sendable, Equatable {
    public var filesDone = 0
    public var filesTotal = 0
    public var bytesDone: Int64 = 0
    public var bytesTotal: Int64 = 0
    public var currentName = ""

    public init() {}
}

public struct CopyImportResult: Sendable {
    public var project: ProjectRecord?
    /// Source files whose copies were read back and matched by hash; only these
    /// may be deleted from the source.
    public var verifiedSources: [URL] = []
    public var failures: [ImportFailure] = []
    public var insertedVersionIDs: [Int64] = []
    /// Value for the persistent counter after this import.
    public var nextCounter: Int
    public var copied = 0
    /// Files already at the destination with the same content (not copied again).
    public var alreadyAtDestination = 0
}

/// Copies shots from a card or folder into the library's folders, verifies each
/// copy, and catalogs the copies as referenced masters. Without a catalog it
/// only copies (the standalone importer).
///
/// Each file is read once while being written to a hidden temporary name and
/// hashed, renamed into place, given the original's modification date, then
/// read back without the file cache and hashed again. Only when both hashes
/// match is the file verified (and later deletable from the card).
public final class CopyImporter: Sendable {
    public let catalog: Catalog?
    public let sidecars: SidecarSync?
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "copy-import")

    /// `catalog` nil: copy only. Preset metadata then goes into new sidecars
    /// next to the copies.
    public init(catalog: Catalog?, sidecars: SidecarSync? = nil) {
        self.catalog = catalog
        self.sidecars = sidecars
    }

    public struct VerificationFailed: Error, CustomStringConvertible {
        public var description: String { "the copy does not match the original" }
    }

    /// The volume, project and import run copies are catalogued under.
    private struct CatalogTarget {
        var catalog: Catalog
        var volume: VolumeRecord
        var volumeID: Int64
        var project: ProjectRecord
        var runID: Int64?
    }

    public func run(shots: [SourceShot], sourceRoot: URL, options: CopyImportOptions,
                    progress report: @Sendable (CopyImportProgress) -> Void = { _ in }) async throws -> CopyImportResult {
        let shots = shots.filter { !$0.isDuplicate }
        var result = CopyImportResult(nextCounter: options.firstCounter)
        var progress = CopyImportProgress()
        progress.filesTotal = shots.flatMap(\.files).filter { !$0.isDuplicate }.count
        progress.bytesTotal = shots.map(\.byteCount).reduce(0, +)
        report(progress)
        guard let first = shots.first else { return result }

        try FileManager.default.createDirectory(at: options.destination, withIntermediateDirectories: true)
        let importDate = Date()
        var target: CatalogTarget?
        if let catalog {
            target = try await catalogTarget(catalog, first: first, sourceRoot: sourceRoot, options: options,
                                             importDate: importDate)
            guard target != nil else { return result }
            result.project = target?.project
        }

        var pending: [NewMaster] = []
        var forcedSidecars: [Int64] = []
        var writtenSidecars: Set<URL> = []
        for (index, shot) in shots.enumerated() {
            try Task.checkCancellation()
            let sequence = index + 1
            let counter = options.firstCounter + index
            result.nextCounter = counter + 1
            let context = Self.context(shot, file: shot.primary, sequence: sequence, counter: counter,
                                       importDate: importDate, job: options.jobCode)
            let rendered = options.template.render(context)
            let folder = rendered.folders.reduce(options.destination) { $0.appending(path: $1, directoryHint: .isDirectory) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Both files of a pair get the same stem (and the same suffix on a clash).
            let stem = (rendered.fileName as NSString).deletingPathExtension
            let files = shot.files.filter { !$0.isDuplicate }
            let destinations = try Self.freeNames(stem: stem, files: files, in: folder)
            var copiedPrimary: URL?

            for (file, destination) in zip(files, destinations) {
                progress.currentName = file.name
                report(progress)
                do {
                    let hash: String
                    if destination.existing {
                        hash = try await SHA256ContentHasher().contentHash(of: destination.url)
                        result.alreadyAtDestination += 1
                    } else {
                        hash = try Self.copyVerified(file.url, to: destination.url, modifiedAt: file.modifiedAt) {
                            progress.bytesDone += $0
                            report(progress)
                        }
                        result.copied += 1
                    }
                    result.verifiedSources.append(file.url)
                    if file == files.first { copiedPrimary = destination.url }
                    if let target {
                        guard let relative = VolumeResolver.relativePath(of: destination.url,
                                                                         inVolumeAt: target.volume.mountPath) else {
                            throw CocoaError(.fileWriteInvalidFileName)
                        }
                        var metadata = file.metadata
                        if let preset = options.metadata {
                            let fileContext = Self.context(shot, file: file, sequence: sequence, counter: counter,
                                                           importDate: importDate, job: options.jobCode)
                            Self.apply(preset, to: &metadata, context: fileContext)
                        }
                        pending.append(NewMaster(relativePath: relative, fileSize: file.size, modifiedAt: file.modifiedAt,
                                                 contentHash: hash, metadata: metadata))
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    Self.log.error("Copying \(file.url.path, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                    result.failures.append(ImportFailure(path: file.url.path, reason: String(describing: error)))
                }
                progress.filesDone += 1
                report(progress)
            }
            if let target, pending.count >= 64 || index == shots.count - 1 {
                let inserted = try await target.catalog.insertMasters(pending, volumeID: target.volumeID,
                                                                      projectID: target.project.id!,
                                                                      importRunID: target.runID, importedAt: importDate)
                result.insertedVersionIDs += inserted.insertedVersionIDs
                if options.metadata != nil { forcedSidecars += inserted.insertedImageIDs }
                pending = []
            }
            if target == nil, let preset = options.metadata, let copy = copiedPrimary, let file = files.first {
                var metadata = file.metadata
                Self.apply(preset, to: &metadata, context: context)
                do {
                    try Self.writeNewSidecar(SidecarSync.values(from: metadata), forCopy: copy, written: &writtenSidecars)
                } catch {
                    Self.log.error("Writing a sidecar for \(copy.path, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
        // Metadata given at import always goes into sidecars.
        if let sidecars, let target, !forcedSidecars.isEmpty {
            _ = try await sidecars.writeSidecars(forImages: forcedSidecars, mountedVolumes: [target.volumeID])
        }
        return result
    }

    /// Registers the destination's volume and creates the project and import run.
    private func catalogTarget(_ catalog: Catalog, first: SourceShot, sourceRoot: URL, options: CopyImportOptions,
                               importDate: Date) async throws -> CatalogTarget? {
        let volumeURL = try options.destination.resourceValues(forKeys: [.volumeURLKey]).volume ?? URL(fileURLWithPath: "/")
        let volume = try await catalog.registerVolume(try VolumeResolver.descriptor(forVolumeAt: volumeURL))
        guard let volumeID = volume.id else { return nil }

        let project: ProjectRecord
        switch options.project {
        case .existing(let id):
            guard let existing = try await catalog.projectSummaries(groupingPairs: false).first(where: { $0.id == id })?.project
            else { throw CocoaError(.fileNoSuchFile) }
            project = existing
        case .new(let nameTemplate):
            let context = Self.context(first, file: first.primary, sequence: 1, counter: options.firstCounter,
                                       importDate: importDate, job: options.jobCode)
            var name = ImportTemplate.sanitize(ImportTemplate.expand(nameTemplate, context))
            if name.isEmpty { name = sourceRoot.lastPathComponent }
            project = try await catalog.createProject(name: name, sourcePath: options.destination.path)
        }
        let run = try await catalog.createImportRun(sourcePath: sourceRoot.path, projectID: project.id)
        return CatalogTarget(catalog: catalog, volume: volume, volumeID: volumeID, project: project, runID: run.id)
    }

    /// Deletes source files (after the person confirmed). Returns the ones that
    /// could not be deleted.
    public static func deleteSources(_ urls: [URL]) -> [URL] {
        urls.filter { url in (try? FileManager.default.removeItem(at: url)) == nil }
    }

    // MARK: Pieces

    static func context(_ shot: SourceShot, file: SourceFile, sequence: Int, counter: Int, importDate: Date,
                        job: String) -> TemplateContext {
        let metadata = shot.primary.metadata
        return TemplateContext(captureDate: metadata.captureDate, captureOffsetSeconds: metadata.captureOffsetSeconds,
                               fileDate: shot.primary.modifiedAt, importDate: importDate, make: metadata.cameraMake,
                               model: metadata.cameraModel, serial: metadata.cameraSerial, lens: metadata.lensModel,
                               originalName: file.name, sequence: sequence, counter: counter, jobCode: job)
    }

    /// The preset's fields, with tokens expanded, in place of the file's.
    static func apply(_ preset: SidecarValues, to metadata: inout ImageMetadata, context: TemplateContext) {
        func expand(_ text: String?) -> String? {
            text.map { ImportTemplate.expand($0, context) }?.trimmedNonEmpty
        }
        if let creator = expand(preset.creator) { metadata.artist = creator }
        if let rights = expand(preset.rights) { metadata.copyright = rights }
        if let usage = expand(preset.usageTerms) { metadata.usageTerms = usage }
        if let caption = expand(preset.caption) { metadata.caption = caption }
        if let contact = preset.contact, !contact.isEmpty { metadata.creatorContact = contact }
    }

    /// Writes `values` into a new sidecar for `copy` (a pair's sidecar is named
    /// after its RAW and shared). A sidecar already there belongs to another app
    /// or an earlier import and is left alone. `written` holds this import's
    /// sidecars, so a photo and a video with the same stem each get their own.
    static func writeNewSidecar(_ values: SidecarValues, forCopy copy: URL, written: inout Set<URL>) throws {
        let folder = copy.deletingLastPathComponent()
        var name = SidecarFiles.preferredName(forMaster: copy.lastPathComponent, stemIsShared: false)
        if written.contains(folder.appending(path: name, directoryHint: .notDirectory)) {
            name = SidecarFiles.preferredName(forMaster: copy.lastPathComponent, stemIsShared: true)
        } else if SidecarFiles.locate(in: folder, names: SidecarFiles.candidateNames(forMaster: copy.lastPathComponent,
                                                                                    preferred: name)) != nil {
            return
        }
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        _ = try SidecarFiles.write(values, previous: nil, to: url)
        written.insert(url)
    }

    struct Destination {
        var url: URL
        /// An identical file is already there.
        var existing: Bool
    }

    /// `stem.ext` for each file, or `stem-1.ext`, `stem-2.ext`… for all of them
    /// when any name is taken by a different file.
    static func freeNames(stem: String, files: [SourceFile], in folder: URL) throws -> [Destination] {
        for attempt in 0..<1000 {
            let base = attempt == 0 ? stem : "\(stem)-\(attempt)"
            var destinations: [Destination] = []
            var free = true
            for file in files {
                let url = folder.appending(path: base + "." + file.url.pathExtension, directoryHint: .notDirectory)
                guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
                    destinations.append(Destination(url: url, existing: false))
                    continue
                }
                if Int64(size) == file.size, try sameContent(url, file.url) {
                    destinations.append(Destination(url: url, existing: true))
                } else {
                    free = false
                    break
                }
            }
            if free { return destinations }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    static func sameContent(_ a: URL, _ b: URL) throws -> Bool {
        try hash(of: a, uncached: false) == hash(of: b, uncached: false)
    }

    /// Copies `source` to `destination` (which must not exist) and returns the
    /// content hash after verifying the copy.
    static func copyVerified(_ source: URL, to destination: URL, modifiedAt: Date,
                             progress: (Int64) -> Void) throws -> String {
        let folder = destination.deletingLastPathComponent()
        let temporary = folder.appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).partial")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        var moved = false
        defer { if !moved { try? FileManager.default.removeItem(at: temporary) } }

        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: temporary)
        var hasher = SHA256()
        do {
            defer { try? output.close() }
            while true {
                try Task.checkCancellation()
                let chunk = try input.read(upToCount: 4 << 20) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
                try output.write(contentsOf: chunk)
                progress(Int64(chunk.count))
            }
            try output.synchronize()
        }
        let sourceHash = hasher.finalize().hexString
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: temporary.path)
        try FileManager.default.moveItem(at: temporary, to: destination)
        moved = true
        guard try hash(of: destination, uncached: true) == sourceHash else {
            try? FileManager.default.removeItem(at: destination)
            throw VerificationFailed()
        }
        return sourceHash
    }

    /// SHA-256 of a file; `uncached` reads around the file cache, so a copy is
    /// checked as stored rather than as still in memory.
    static func hash(of url: URL, uncached: Bool) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if uncached { _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1) }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().hexString
    }
}
