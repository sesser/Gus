import CryptoKit
import Foundation
import os

/// Where a server import's photos go in the catalog. The name is plain text
/// (design §5.3), never a template.
public enum RemoteProjectChoice: Hashable, Sendable {
    case existing(Int64)
    case named(String)
}

public struct RemoteImportOptions: Sendable {
    public var destination: URL
    public var template: ImportTemplate
    public var project: RemoteProjectChoice
    public var jobCode: String
    public var firstCounter: Int
    /// The metadata preset's values, as for a card (written to sidecars).
    public var metadata: SidecarValues?
    public var link: RemoteLinkTarget

    public init(destination: URL, template: ImportTemplate = ImportTemplate(), project: RemoteProjectChoice,
                jobCode: String = "", firstCounter: Int = 1, metadata: SidecarValues? = nil, link: RemoteLinkTarget) {
        self.destination = destination
        self.template = template
        self.project = project
        self.jobCode = jobCode
        self.firstCounter = firstCounter
        self.metadata = metadata
        self.link = link
    }
}

/// One photo that was not imported, and why (design §6.2's reasons).
public struct RemoteImportFailure: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The bytes' SHA-1 is not the server's checksum.
        case checksumMismatch
        /// Fewer or more bytes than the server reported.
        case incomplete
        /// The server no longer has it (404).
        case deletedOnServer
        /// The server answered with this status for this photo.
        case serverError(Int)
        /// It could not be written here: the system's reason.
        case disk(String)
    }

    public var name: String
    public var kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }
}

/// Why an import ended early (design §6.3). A person's Stop is `.stopped`.
public enum RemoteImportStop: Hashable, Sendable {
    case stopped
    case unreachable
    case keyRejected
    case missingPermission(String)
    case certificateChanged
}

public struct RemoteImportResult: Sendable {
    public var project: ProjectRecord?
    public var imported = 0
    /// Content already in the library, or a link that appeared since the
    /// photo was listed (design §6.2: "already in the library").
    public var alreadyInLibrary = 0
    /// Live Photo stills imported without their videos (R14).
    public var liveVideosLeftOut = 0
    public var failures: [RemoteImportFailure] = []
    /// Nil when every photo was tried.
    public var stop: RemoteImportStop?
    public var insertedVersionIDs: [Int64] = []
    /// Value for the persistent counter after this import.
    public var nextCounter: Int

    public init(nextCounter: Int) {
        self.nextCounter = nextCounter
    }
}

/// How often and how long a failing request is tried again (R20; status.md,
/// "Retries and timeouts").
public struct RemoteRetryPolicy: Sendable {
    public var delays: [Duration]

    public init(delays: [Duration]) {
        self.delays = delays
    }

    /// Three more tries, after 1, 2 and 4 seconds.
    public static let standard = RemoteRetryPolicy(delays: [.seconds(1), .seconds(2), .seconds(4)])
    public static let none = RemoteRetryPolicy(delays: [])
}

/// Copies photos from a server into the library (R12 to R21): downloads each
/// original under a hidden temporary name, checks its size and the server's
/// SHA-1 as it arrives and again as stored (read around the file cache),
/// moves it into place under the import template's name, and catalogs it as
/// an ordinary local master with a link to its remote asset, in one
/// transaction. A photo that does not verify leaves no file and no row.
public final class RemoteImporter: Sendable {
    public let catalog: Catalog
    public let sidecars: SidecarSync?
    private let source: any RemotePhotoSource
    private let metadataReader: any MetadataReader
    private let retry: RemoteRetryPolicy
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "remote-import")

    public init(catalog: Catalog, sidecars: SidecarSync?, source: any RemotePhotoSource,
                metadataReader: any MetadataReader, retry: RemoteRetryPolicy = .standard) {
        self.catalog = catalog
        self.sidecars = sidecars
        self.source = source
        self.metadataReader = metadataReader
        self.retry = retry
    }

    private struct Target {
        var volume: VolumeRecord
        var volumeID: Int64
        var projectID: Int64
        var runID: Int64?
    }

    /// Imports `assets` in order. Never throws for one photo: failures are
    /// counted, and a failure of the server, the key or the certificate ends
    /// the run with what finished kept (`stop`). A cancelled task ends it as
    /// `.stopped`.
    public func run(_ assets: [RemoteAsset], options: RemoteImportOptions,
                    progress report: @escaping @Sendable (CopyImportProgress) -> Void = { _ in }) async
        -> RemoteImportResult {
        var result = RemoteImportResult(nextCounter: options.firstCounter)
        let tally = ProgressTally(total: assets.count, bytes: assets.map { $0.byteCount ?? 0 }.reduce(0, +), report: report)
        tally.publish()
        let importDate = Date()
        var target: Target?
        var forcedSidecars: [Int64] = []
        var linked: Set<String> = []
        do {
            linked = try await catalog.linkedRemoteIDs(provider: options.link.provider, address: options.link.address,
                                                       among: assets.map(\.id))
        } catch {
            Self.log.error("Reading links failed: \(String(describing: error), privacy: .public)")
        }

        assets: for (index, asset) in assets.enumerated() {
            if Task.isCancelled {
                result.stop = .stopped
                break
            }
            result.nextCounter = options.firstCounter + index + 1
            tally.begin(asset.fileName)
            if linked.contains(asset.id) {
                result.alreadyInLibrary += 1
                tally.finishFile(skippedBytes: asset.byteCount ?? 0)
                continue
            }
            do {
                try FileManager.default.createDirectory(at: options.destination, withIntermediateDirectories: true)
            } catch {
                result.failures.append(RemoteImportFailure(name: asset.fileName, kind: .disk(error.localizedDescription)))
                tally.finishFile(skippedBytes: asset.byteCount ?? 0)
                continue
            }
            let ext = (asset.fileName as NSString).pathExtension
            let partial = options.destination.appending(path: ".download-\(UUID().uuidString)" + (ext.isEmpty ? "" : "." + ext),
                                                        directoryHint: .notDirectory)
            // Download, trying a failing server again (R20).
            var download: RemoteHTTPSession.Download?
            var attempt = 0
            while download == nil {
                do {
                    download = try await source.download(assetID: asset.id, to: partial) { tally.add($0) }
                } catch {
                    tally.resetFile()
                    if error == .cancelled || Task.isCancelled {
                        result.stop = .stopped
                        break assets
                    }
                    if error.isTransient, attempt < retry.delays.count {
                        tally.waiting(true)
                        do {
                            try await Task.sleep(for: retry.delays[attempt])
                        } catch {
                            result.stop = .stopped
                            break assets
                        }
                        attempt += 1
                        continue
                    }
                    tally.waiting(false)
                    switch error {
                    case .status(404):
                        result.failures.append(RemoteImportFailure(name: asset.fileName, kind: .deletedOnServer))
                    case .status(401):
                        result.stop = .keyRejected
                        break assets
                    case .status(403):
                        result.stop = .missingPermission(ImmichEndpoint.original(assetID: asset.id).permission ?? "")
                        break assets
                    case .status(let code) where !error.isTransient:
                        result.failures.append(RemoteImportFailure(name: asset.fileName, kind: .serverError(code)))
                    case .certificate:
                        result.stop = .certificateChanged
                        break assets
                    case .disk(let reason):
                        result.failures.append(RemoteImportFailure(name: asset.fileName, kind: .disk(reason)))
                    default:
                        result.stop = .unreachable
                        break assets
                    }
                    tally.finishFile(skippedBytes: 0)
                    continue assets
                }
            }
            tally.waiting(false)
            guard let download else { continue }
            // Check the bytes (R13); a photo that fails leaves no file.
            if let failure = Self.verify(download, partial: partial, asset: asset) {
                try? FileManager.default.removeItem(at: partial)
                result.failures.append(RemoteImportFailure(name: asset.fileName, kind: failure))
                tally.finishFile(skippedBytes: 0)
                continue
            }
            let contentHash: String
            do {
                contentHash = try Self.verifyStored(partial, sha1: asset.checksum)
            } catch let failure as RemoteImportFailure.Kind {
                try? FileManager.default.removeItem(at: partial)
                result.failures.append(RemoteImportFailure(name: asset.fileName, kind: failure))
                tally.finishFile(skippedBytes: 0)
                continue
            } catch {
                try? FileManager.default.removeItem(at: partial)
                result.failures.append(RemoteImportFailure(name: asset.fileName, kind: .disk(error.localizedDescription)))
                tally.finishFile(skippedBytes: 0)
                continue
            }
            do {
                // Content already in the library: not imported twice (R13), linked (R15b).
                if try await catalog.linkRemoteDuplicate(contentHash: contentHash, remoteID: asset.id,
                                                         fingerprint: asset.checksum, link: options.link,
                                                         at: importDate) {
                    try? FileManager.default.removeItem(at: partial)
                    result.alreadyInLibrary += 1
                    tally.finishFile(skippedBytes: 0)
                    continue
                }
                if target == nil {
                    target = try await makeTarget(options: options, importDate: importDate)
                    result.project = try await catalog.projectSummaries(groupingPairs: false)
                        .first { $0.id == target?.projectID }?.project
                }
                guard let target else { break }
                var metadata = (try? await metadataReader.metadata(for: [partial]))?[partial] ?? .empty
                let context = TemplateContext(
                    captureDate: metadata.captureDate ?? asset.metadata.captureDate,
                    captureOffsetSeconds: metadata.captureDate != nil ? metadata.captureOffsetSeconds
                        : asset.metadata.captureOffsetSeconds,
                    fileDate: asset.modifiedAt, importDate: importDate,
                    make: metadata.cameraMake ?? asset.metadata.cameraMake,
                    model: metadata.cameraModel ?? asset.metadata.cameraModel, serial: metadata.cameraSerial,
                    lens: metadata.lensModel ?? asset.metadata.lensModel, originalName: asset.fileName,
                    sequence: index + 1, counter: options.firstCounter + index, jobCode: options.jobCode)
                let rendered = options.template.render(context)
                let folder = rendered.folders.reduce(options.destination) { $0.appending(path: $1, directoryHint: .isDirectory) }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let final = try Self.freeName(rendered.fileName, in: folder)
                try FileManager.default.setAttributes([.modificationDate: asset.modifiedAt], ofItemAtPath: partial.path)
                try FileManager.default.moveItem(at: partial, to: final)
                guard let relative = VolumeResolver.relativePath(of: final, inVolumeAt: target.volume.mountPath) else {
                    try? FileManager.default.removeItem(at: final)
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                if let preset = options.metadata { CopyImporter.apply(preset, to: &metadata, context: context) }
                let master = NewMaster(relativePath: relative, fileSize: download.byteCount, modifiedAt: asset.modifiedAt,
                                       contentHash: contentHash, metadata: metadata)
                let outcome = try await catalog.insertRemoteMaster(
                    master, remoteID: asset.id, fingerprint: asset.checksum, link: options.link,
                    serverDescription: asset.serverDescription, serverRating: asset.serverRating,
                    volumeID: target.volumeID, projectID: target.projectID, importRunID: target.runID,
                    importedAt: importDate)
                switch outcome {
                case .inserted(let imageID, let versionID):
                    result.imported += 1
                    result.insertedVersionIDs.append(versionID)
                    if asset.hasLiveVideo { result.liveVideosLeftOut += 1 }
                    if options.metadata != nil { forcedSidecars.append(imageID) }
                case .duplicate, .alreadyLinked:
                    try? FileManager.default.removeItem(at: final)
                    result.alreadyInLibrary += 1
                case .pathTaken:
                    try? FileManager.default.removeItem(at: final)
                    result.failures.append(RemoteImportFailure(name: asset.fileName,
                                                               kind: .disk(CocoaError(.fileWriteFileExists).localizedDescription)))
                }
            } catch {
                try? FileManager.default.removeItem(at: partial)
                Self.log.error("Cataloging \(asset.fileName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                result.failures.append(RemoteImportFailure(name: asset.fileName, kind: .disk(error.localizedDescription)))
            }
            tally.finishFile(skippedBytes: 0)
        }
        if let sidecars, let target, !forcedSidecars.isEmpty {
            _ = try? await sidecars.writeSidecars(forImages: forcedSidecars, mountedVolumes: [target.volumeID])
        }
        return result
    }

    /// The destination's volume, the project and the import run; made when
    /// the first photo verifies, so a run that imports nothing leaves no
    /// empty project.
    private func makeTarget(options: RemoteImportOptions, importDate: Date) async throws -> Target {
        let volumeURL = try options.destination.resourceValues(forKeys: [.volumeURLKey]).volume ?? URL(fileURLWithPath: "/")
        let volume = try await catalog.registerVolume(try VolumeResolver.descriptor(forVolumeAt: volumeURL))
        guard let volumeID = volume.id else { throw CocoaError(.fileNoSuchFile) }
        let projectID: Int64
        switch options.project {
        case .existing(let id):
            projectID = id
        case .named(let name):
            var cleaned = ImportTemplate.sanitize(name)
            if cleaned.isEmpty { cleaned = options.link.address }
            let project = try await catalog.createProject(name: cleaned, sourcePath: options.destination.path)
            guard let id = project.id else { throw CocoaError(.fileNoSuchFile) }
            projectID = id
        }
        let run = try await catalog.createImportRun(sourcePath: options.link.address, projectID: projectID)
        return Target(volume: volume, volumeID: volumeID, projectID: projectID, runID: run.id)
    }

    /// Size and checksum of the bytes as they arrived.
    static func verify(_ download: RemoteHTTPSession.Download, partial: URL, asset: RemoteAsset) -> RemoteImportFailure.Kind? {
        if let expected = asset.byteCount ?? download.expectedLength, download.byteCount != expected { return .incomplete }
        guard download.sha1 == asset.checksum else { return .checksumMismatch }
        return nil
    }

    /// Reads the stored file back around the file cache: its SHA-1 must
    /// still be the server's, and its SHA-256 is the catalog's content hash.
    static func verifyStored(_ url: URL, sha1 expected: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
        var sha1 = Insecure.SHA1()
        var sha256 = SHA256()
        try FileChunks.forEach(in: handle.fileDescriptor, chunkSize: CopyImporter.copyChunkSize, checksCancellation: false) {
            sha1.update(bufferPointer: $0)
            sha256.update(bufferPointer: $0)
        }
        guard Data(sha1.finalize()).base64EncodedString() == expected else { throw RemoteImportFailure.Kind.checksumMismatch }
        return sha256.finalize().hexString
    }

    /// `name`, or `stem-1.ext`, `stem-2.ext`… when it is taken: nothing is
    /// ever replaced.
    static func freeName(_ name: String, in folder: URL) throws -> URL {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for attempt in 0..<10_000 {
            let base = attempt == 0 ? stem : "\(stem)-\(attempt)"
            let url = folder.appending(path: ext.isEmpty ? base : base + "." + ext, directoryHint: .notDirectory)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

extension RemoteImportFailure.Kind: Error {}

/// The running import's progress, reported after each change.
private final class ProgressTally: Sendable {
    private let state: OSAllocatedUnfairLock<(progress: CopyImportProgress, fileBytes: Int64)>
    private let report: @Sendable (CopyImportProgress) -> Void

    init(total: Int, bytes: Int64, report: @escaping @Sendable (CopyImportProgress) -> Void) {
        var progress = CopyImportProgress()
        progress.filesTotal = total
        progress.bytesTotal = bytes
        state = OSAllocatedUnfairLock(initialState: (progress, 0))
        self.report = report
    }

    func publish() {
        report(state.withLock { $0.progress })
    }

    func begin(_ name: String) {
        report(state.withLock { state in
            state.progress.currentName = name
            state.fileBytes = 0
            return state.progress
        })
    }

    func add(_ bytes: Int64) {
        report(state.withLock { state in
            state.fileBytes += bytes
            state.progress.bytesDone += bytes
            state.progress.waitingForServer = false
            return state.progress
        })
    }

    /// A failed attempt: its bytes no longer count.
    func resetFile() {
        state.withLock { state in
            state.progress.bytesDone -= state.fileBytes
            state.fileBytes = 0
        }
    }

    func waiting(_ waiting: Bool) {
        report(state.withLock { state in
            state.progress.waitingForServer = waiting
            return state.progress
        })
    }

    /// The file is done with; `skippedBytes` are counted as done when it was
    /// never downloaded.
    func finishFile(skippedBytes: Int64) {
        report(state.withLock { state in
            state.progress.filesDone += 1
            state.progress.bytesDone += skippedBytes
            state.fileBytes = 0
            return state.progress
        })
    }
}

extension Catalog {
    /// When the catalog already holds `contentHash`, links the remote asset to
    /// that master's default version (R15b; not when either already has a link
    /// to this server) and returns true; false when the content is new.
    public func linkRemoteDuplicate(contentHash: String, remoteID: String, fingerprint: String, link: RemoteLinkTarget,
                                    at date: Date = Date()) async throws -> Bool {
        try await database.write { db in
            guard let versionID = try Int64.fetchOne(db, sql: """
                SELECT version.id FROM image JOIN version ON version.imageId = image.id AND version.isDefault
                WHERE image.contentHash = ?
                """, arguments: [contentHash]) else { return false }
            try Self.insertLink(db, remoteID: remoteID, fingerprint: fingerprint, link: link, versionID: versionID, at: date)
            return true
        }
    }
}
