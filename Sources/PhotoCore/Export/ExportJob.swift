import Foundation
import os

/// One version as the export sees it.
public struct ExportItem: Sendable {
    public var versionID: Int64
    public var details: VersionDetails
    /// The library's keywords and descriptive fields for the version.
    public var values: SidecarValues
    /// The master's location at its volume's last known mount point.
    public var sourceURL: URL
    /// The master is reachable (its volume is mounted and the file is there).
    public var isOnline: Bool

    public var isVideo: Bool { FileKind(pathExtension: (details.image.fileName as NSString).pathExtension) == .video }

    /// What the file name template can refer to, for the `sequence`th image of an export.
    public func templateContext(sequence: Int, exportDate: Date) -> TemplateContext {
        let image = details.image
        return TemplateContext(captureDate: image.captureDate, captureOffsetSeconds: image.captureOffsetSeconds,
                               fileDate: image.modifiedAt, importDate: image.importedAt, make: image.cameraMake,
                               model: image.cameraModel, serial: image.cameraSerial, lens: image.lensModel,
                               originalName: image.fileName, sequence: sequence, counter: sequence, jobCode: "",
                               exportDate: exportDate)
    }
}

/// What to export and where.
public struct ExportRequest: Sendable {
    public var versionIDs: [Int64]
    public var settings: ExportSettings
    public var destination: URL
    public var policy: ExportConflictPolicy
    public var date: Date

    public init(versionIDs: [Int64], settings: ExportSettings, destination: URL,
                policy: ExportConflictPolicy = .keepBoth, date: Date = Date()) {
        self.versionIDs = versionIDs
        self.settings = settings
        self.destination = destination
        self.policy = policy
        self.date = date
    }
}

/// How an export went.
public struct ExportSummary: Sendable, Hashable {
    public struct Failure: Sendable, Hashable {
        public enum Reason: Sendable, Hashable {
            /// The master's volume is not mounted (its name) or the file is gone.
            case offline(volumeName: String)
            case unreadable
            case missingWatermark
            case writeFailed(String)
        }

        public var fileName: String
        public var reason: Reason
    }

    public var destination: URL
    /// In completion order.
    public var written: [URL] = []
    public var skippedExisting = 0
    public var skippedVideos = 0
    public var failures: [Failure] = []
    public var cancelled = false

    public init(destination: URL) {
        self.destination = destination
    }
}

/// Exports versions to a folder: a few renders at a time, cancellable with the
/// task that runs it.
public struct ExportJob: Sendable {
    public let catalog: Catalog
    public let renderer: ExportRenderer
    /// Full-resolution renders are large (a 60 MP RAW is about 1 GB in the
    /// working format), so only a few run at once.
    public var maxConcurrentRenders: Int

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "export")

    public init(catalog: Catalog, renderer: ExportRenderer, maxConcurrentRenders: Int = 2) {
        self.catalog = catalog
        self.renderer = renderer
        self.maxConcurrentRenders = max(1, maxConcurrentRenders)
    }

    /// The versions with what export needs to know about them, in order.
    /// Unknown ids are left out.
    public func items(for versionIDs: [Int64]) async throws -> [ExportItem] {
        var items: [ExportItem] = []
        for id in versionIDs {
            guard let details = try await catalog.details(forVersion: id) else { continue }
            let image = details.image
            var values = SidecarValues()
            values.keywords = try await catalog.keywords(forVersion: id).map(\.name)
            values.creator = image.artist
            values.rights = image.copyright
            values.caption = image.caption
            values.usageTerms = image.usageTerms
            values.contact = image.metadata.creatorContact
            let url = details.volume.url(forRelativePath: image.relativePath)
            items.append(ExportItem(versionID: id, details: details, values: values, sourceURL: url,
                                    isOnline: FileManager.default.fileExists(atPath: url.path)))
        }
        return items
    }

    /// Exports `items` (or the request's versions when nil). Videos are
    /// counted and skipped. `progress` gets (done, total) after each image.
    public func run(_ request: ExportRequest, items: [ExportItem]? = nil,
                    progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async -> ExportSummary {
        var summary = ExportSummary(destination: request.destination)
        let all: [ExportItem]
        do {
            if let items {
                all = items
            } else {
                all = try await self.items(for: request.versionIDs)
            }
        } catch {
            summary.cancelled = Task.isCancelled
            return summary
        }
        let exportable = all.filter { !$0.isVideo }
        summary.skippedVideos = all.count - exportable.count

        do {
            try FileManager.default.createDirectory(at: request.destination, withIntermediateDirectories: true)
        } catch {
            summary.failures = exportable.map {
                .init(fileName: $0.details.image.fileName, reason: .writeFailed(error.localizedDescription))
            }
            return summary
        }
        let contexts = exportable.enumerated().map { $1.templateContext(sequence: $0 + 1, exportDate: request.date) }
        let destinations = ExportNaming.plan(contexts, settings: request.settings, in: request.destination,
                                             policy: request.policy)
        let total = exportable.count
        var done = 0
        progress(0, total)

        let renderer = self.renderer
        let settings = request.settings
        await withTaskGroup(of: Outcome.self) { group in
            var pending = zip(exportable, destinations).makeIterator()
            var running = 0
            func startNext() -> Bool {
                guard !Task.isCancelled, let (item, destination) = pending.next() else { return false }
                group.addTask { Self.export(item, to: destination, settings: settings, renderer: renderer) }
                running += 1
                return true
            }
            while running < maxConcurrentRenders, startNext() {}
            while let outcome = await group.next() {
                running -= 1
                switch outcome {
                case .written(let url): summary.written.append(url)
                case .skipped: summary.skippedExisting += 1
                case .failed(let failure): summary.failures.append(failure)
                }
                done += 1
                progress(done, total)
                _ = startNext()
            }
        }
        summary.cancelled = Task.isCancelled && done < total
        return summary
    }

    private enum Outcome: Sendable {
        case written(URL)
        case skipped
        case failed(ExportSummary.Failure)
    }

    private static func export(_ item: ExportItem, to destination: ExportDestination, settings: ExportSettings,
                               renderer: ExportRenderer) -> Outcome {
        let name = item.details.image.fileName
        guard case .write(let url, let replacing) = destination else { return .skipped }
        guard item.isOnline else { return .failed(.init(fileName: name, reason: .offline(volumeName: item.details.volume.name))) }
        do {
            let stack = try item.details.version.decodedEditStack()
            try renderer.export(source: item.sourceURL, stack: stack, values: item.values, settings: settings,
                                to: url, replacing: replacing)
            return .written(url)
        } catch ExportRenderer.Failure.missingWatermark {
            return .failed(.init(fileName: name, reason: .missingWatermark))
        } catch PreviewGenerator.Failure.undecodable {
            return .failed(.init(fileName: name, reason: .unreadable))
        } catch {
            log.error("Export of \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return .failed(.init(fileName: name, reason: .writeFailed(error.localizedDescription)))
        }
    }
}
