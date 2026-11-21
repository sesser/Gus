import CoreImage
import Foundation
import ImageIO
import os

/// Where a running merge is (design §7.1): the step, and the fraction of the
/// whole job done, weighted by what each step costs (status.md, "Spike 3").
public struct MergeProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case reading(Int, Int)
        case aligning(Int, Int)
        case merging
        case toneMapping
        case saving
        case adding
    }

    public var phase: Phase
    public var fraction: Double

    /// The fraction at the start of each step, and the reading and aligning
    /// steps' share per frame: reading (both decodes of every frame) and
    /// measuring take most of a merge; rendering and writing are quick on
    /// the GPU.
    static let readingShare = 0.5
    static let aligningShare = 0.3
    static let merging = 0.8
    static let toneMapping = 0.83
    static let saving = 0.86
    static let adding = 0.97
}

/// One HDR merge, from the selected photos to a new photo in the library
/// (issue #150): reads the frames, merges and tone maps them (`HDRMerger`),
/// writes the file beside the reference without replacing anything
/// (`MergeOutput`), and catalogues it in the reference's project with the
/// reference's values (`Catalog.insertMergedMaster`). Shared by the app and
/// `photocli`. Cancelling the task stops it at the next step, with nothing
/// written; once the file is in place, the job finishes cataloguing it.
public struct HDRMergeJob: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// A refusal found when the merge started (design §6.2's second check).
        case refused(MergeRefusal)
        /// This frame doesn't line up with the reference (R9).
        case misaligned(name: String, reference: String)
        case unreadable(name: String)
        case differentSize(name: String, reference: String)
        /// Not enough space on this volume.
        case noSpace(volume: String)
        case writeFailed(String)
        case noMemory
        /// The file is complete at `path` but couldn't be catalogued.
        case catalogFailed(path: String, reason: String)
    }

    /// How a merge ended well.
    public struct Result: Sendable, Hashable {
        public var url: URL
        public var master: MergedMaster?
        /// The file's path or content was already in the library (another
        /// import took it first): the version that holds it, when found.
        public var existingVersionID: Int64?
        public var frameCount: Int
    }

    public let catalog: Catalog
    public let metadataReader: any MetadataReader
    public var preflight: MergePreflight = .disk
    /// Where volumes are mounted now, for placing masters the name must avoid.
    public var mountedVolumes: @Sendable () -> [VolumeDescriptor] = { VolumeAvailability.mountedVolumes() }

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "merge")

    public init(catalog: Catalog, metadataReader: any MetadataReader) {
        self.catalog = catalog
        self.metadataReader = metadataReader
    }

    /// The file the merge would write now (R3, R4).
    public func resultURL(for selection: MergeSelection, format: MergeFormat) async throws -> URL {
        let folder = selection.referenceFrame.folder
        let masters = try await catalog.masterFiles(mounted: mountedVolumes()).names(in: folder)
        return folder.appending(path: selection.resultName(format: format, masters: masters), directoryHint: .notDirectory)
    }

    /// Runs the merge. `catalogue` runs the catalog write (the app puts it on
    /// its write chain, after every change made before it).
    public func run(_ selection: MergeSelection, format: MergeFormat,
                    progress: @escaping @Sendable (MergeProgress) -> Void = { _ in },
                    catalogue: @escaping @Sendable (@escaping @Sendable () async throws -> MergedMaster) async throws
                        -> MergedMaster = { try await $0() }) async throws -> Result {
        if let refusal = selection.refusal { throw Failure.refused(refusal) }
        if let (refusal, _) = preflight.check(selection) { throw Failure.refused(refusal) }
        let frames = selection.frames
        let count = frames.count
        let reference = selection.reference
        let referenceFrame = selection.referenceFrame
        let merger = HDRMerger()
        let sources = frames.map { MergeDecoder.source(of: $0.url) }

        // Reading: each frame's reduced copy and its full-resolution pixels, one
        // frame at a time so only one decoder's buffers are held at once.
        var copies: [MergeBitmap] = []
        var full: [CIImage] = []
        for (index, frame) in frames.enumerated() {
            progress(MergeProgress(phase: .reading(index + 1, count),
                                   fraction: MergeProgress.readingShare * Double(index) / Double(count)))
            try Task.checkCancellation()
            do {
                copies.append(try merger.measuringCopy(of: frame.url, source: sources[index]))
                try Task.checkCancellation()
                full.append(try merger.fullFrame(of: frame.url, source: sources[index]))
            } catch let cancelled as CancellationError {
                throw cancelled
            } catch {
                Self.log.error("Merge: \(frame.fileName, privacy: .private) couldn't be read: \(String(describing: error), privacy: .public)")
                throw Failure.unreadable(name: frame.displayName)
            }
        }
        let size = full[reference].extent.integral.size
        for (index, image) in full.enumerated() where image.extent.integral.size != size {
            throw Failure.differentSize(name: frames[index].displayName, reference: referenceFrame.displayName)
        }

        // Aligning, exposure, ghosts and tone statistics on the copies.
        progress(MergeProgress(phase: .aligning(1, count), fraction: MergeProgress.readingShare))
        let plan: HDRMerger.Plan
        do {
            plan = try merger.plan(measuring: copies, reference: reference,
                                   metadataExposures: frames.map(\.metadataExposure)) { done in
                progress(MergeProgress(phase: .aligning(min(done + 1, count), count),
                                       fraction: MergeProgress.readingShare
                                           + MergeProgress.aligningShare * Double(done) / Double(count)))
            }
        } catch HDRMerger.Failure.misaligned(let index) {
            throw Failure.misaligned(name: frames[index].displayName, reference: referenceFrame.displayName)
        } catch HDRMerger.Failure.sizeMismatch(let index) {
            throw Failure.differentSize(name: frames[index].displayName, reference: referenceFrame.displayName)
        } catch HDRMerger.Failure.renderFailed {
            throw Failure.noMemory
        }
        copies = []
        try Task.checkCancellation()

        progress(MergeProgress(phase: .merging, fraction: MergeProgress.merging))
        let radiance = try graph { try merger.radiance(plan, frames: full) }
        progress(MergeProgress(phase: .toneMapping, fraction: MergeProgress.toneMapping))
        let mapped = format == .tiff ? try graph { try merger.toneMapped(plan, radiance: radiance) } : radiance
        try Task.checkCancellation()

        // Saving: the reference's metadata, read now, and the file.
        progress(MergeProgress(phase: .saving, fraction: MergeProgress.saving))
        let values = try await catalog.libraryValues(forVersion: referenceFrame.versionID)
        let metadata = MergeOutput.Metadata(sourceProperties: MergeOutput.Metadata.properties(of: referenceFrame.url),
                                            values: values)
        let exposure = MergeDecoder.defaultExposure(of: referenceFrame.url, source: sources[reference])
        var url = try await resultURL(for: selection, format: format)
        for attempt in 0..<3 {
            do {
                switch format {
                case .tiff: try MergeOutput.writeTIFF(mapped, context: merger.context, metadata: metadata, to: url)
                case .dng:
                    try MergeOutput.writeDNG(radiance, context: merger.context, metadata: metadata, to: url,
                                             brightest: plan.brightest, exposure: exposure)
                }
                break
            } catch MergeOutput.Failure.nameTaken where attempt < 2 {
                // A file appeared under the name meanwhile: the next free one.
                url = try await resultURL(for: selection, format: format)
            } catch MergeOutput.Failure.noSpace {
                throw Failure.noSpace(volume: Self.volumeName(of: url))
            } catch MergeOutput.Failure.writeFailed(let reason) {
                throw Failure.writeFailed(reason)
            } catch MergeOutput.Failure.renderFailed {
                throw Failure.noMemory
            } catch MergeOutput.Failure.nameTaken {
                throw Failure.writeFailed(url.lastPathComponent)
            }
        }
        full = []

        // The file is in place: from here on the job finishes, whatever Stop says.
        progress(MergeProgress(phase: .adding, fraction: MergeProgress.adding))
        let master: NewMaster
        do {
            master = try await newMaster(url, reference: referenceFrame)
        } catch {
            throw Failure.catalogFailed(path: url.path, reason: error.localizedDescription)
        }
        let catalog = self.catalog
        do {
            // Detached: a Stop that comes now doesn't cancel the write (design §7.1).
            let merged = try await Task.detached {
                try await catalogue {
                    try await catalog.insertMergedMaster(master, volumeID: referenceFrame.volumeID,
                                                         projectID: referenceFrame.projectID, values: values)
                }
            }.value
            progress(MergeProgress(phase: .adding, fraction: 1))
            return Result(url: url, master: merged, existingVersionID: nil, frameCount: count)
        } catch MergeCatalogFailure.alreadyInLibrary(let versionID) {
            return Result(url: url, master: nil, existingVersionID: versionID, frameCount: count)
        } catch {
            throw Failure.catalogFailed(path: url.path, reason: error.localizedDescription)
        }
    }

    private func graph(_ make: () throws -> CIImage) throws -> CIImage {
        do {
            return try make()
        } catch HDRMerger.Failure.renderFailed {
            throw Failure.noMemory
        } catch {
            throw Failure.writeFailed(String(describing: error))
        }
    }

    /// The written file as an import catalogues it: hash, size, date and the
    /// metadata its reader finds. Not cancellable: the file is in place.
    private func newMaster(_ url: URL, reference: MergeFrame) async throws -> NewMaster {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attributes[.modificationDate] as? Date ?? Date()
        let hash = try await Task.detached { try await SHA256ContentHasher().contentHash(of: url) }.value
        let metadata = try await Task.detached { [metadataReader] in
            try await metadataReader.metadata(for: [url])
        }.value[url] ?? .empty
        let folder = (reference.relativePath as NSString).deletingLastPathComponent
        let relative = folder.isEmpty ? url.lastPathComponent : folder + "/" + url.lastPathComponent
        return NewMaster(relativePath: relative, fileSize: size, modifiedAt: modified, contentHash: hash,
                         metadata: metadata)
    }

    static func volumeName(of url: URL) -> String {
        (try? url.deletingLastPathComponent().resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.path
    }
}

extension Catalog {
    /// A version's values as a sidecar holds them: its rating, flag, label
    /// and keywords, and its master's descriptive fields.
    public func libraryValues(forVersion id: Int64) async throws -> SidecarValues {
        guard let details = try await details(forVersion: id) else { return SidecarValues() }
        var values = details.image.descriptiveValues
        values.rating = details.version.rating
        values.flag = details.version.flag
        values.colorLabel = details.version.colorLabel
        values.keywords = try await keywords(forVersion: id).map(\.name)
        return values
    }
}
