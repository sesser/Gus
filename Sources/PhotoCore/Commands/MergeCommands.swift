import Foundation
import GRDB

/// `photocli merge` (issue #150, R17): an HDR merge of versions, as File ▸
/// Merge to HDR… makes it, through `HDRMergeJob`.
enum MergeCommands {
    static let merge = CommandSpec(
        id: "merge",
        summary: """
            Merges versions (two to nine photos of one scene, all raws or all non-raws; a RAW+JPEG pair once, as \
            its raw) into one new photo written beside the reference (--reference, else the 0 EV frame, else the \
            earliest) as <name>_HDR.tif (16-bit, Display P3, tone-mapped) or .dng (linear, 16-bit floating point), \
            and adds it to the library in the reference's project with the reference's values. The frames are \
            lined up to the reference and moving things taken from it, unless --no-align or --no-deghost. Refused, \
            with nothing written, as the app refuses. Writes no sidecar.
            """,
        access: .write,
        parameters: [
            LibraryCommands.versions,
            CommandParameter("format", .string, "tiff (default) or dng."),
            CommandParameter("reference", .integer,
                             "The version that names the result, gives its folder, project and values, and that the "
                                 + "others are lined up to; one of the --version values (a RAW+JPEG pair's JPEG means "
                                 + "its raw). Default: the 0 EV frame, else the earliest."),
            CommandParameter("noAlign", .flag,
                             "Merge the frames as they are: no alignment, and no frame refused for not lining up."),
            CommandParameter("noDeghost", .flag,
                             "Blend by exposure alone: no area is taken from the reference only."),
            LibraryCommands.libraryRoot,
        ],
        run: run)

    static func run(_ invocation: CommandInvocation) async throws -> JSONValue {
        let arguments = invocation.arguments
        let format: MergeFormat
        switch arguments.string("format") ?? "tiff" {
        case "tiff": format = .tiff
        case "dng": format = .dng
        default: throw CommandError(.invalidValue, "--format is tiff or dng")
        }
        let library = try invocation.environment.openLibrary(arguments)
        let catalog = library.catalog
        let online = Set(VolumeAvailability.mountedVolumes().map(\.identity))
        var frames: [MergeFrame] = []
        // As the app reads a selection: a pair's JPEG stands for its raw.
        let items = try await catalog.libraryItems(versionIDs: arguments.integers("version"))
        for versionID in arguments.integers("version") where !items.contains(where: { $0.versionID == versionID }) {
            throw CommandError(.versionNotFound, "No version \(versionID)")
        }
        let partners = try await catalog.pairPartners(of: items.map(\.versionID))
        let resolved = items.map { item -> CatalogItem in
            var item = item
            if let partner = partners[item.versionID] {
                item.partnerVersionID = partner.versionID
                item.partnerKind = partner.kind
            }
            return item
        }
        for id in MergeSelection.versionIDs(for: resolved) {
            guard let details = try await catalog.details(forVersion: id) else {
                throw CommandError(.versionNotFound, "No version \(id)")
            }
            // By the volume's identity, as the app decides: a folder left at an
            // old mount point is not the volume (security review L4).
            let isOnline = online.contains(details.volume.identity)
            frames.append(MergeFrame(details: details,
                                     displayName: CopyNaming.plain.copyName(of: details.version,
                                                                            fileName: details.image.fileName),
                                     isOnline: isOnline))
        }
        var selection = MergeSelection(frames: frames)
        if let reference = arguments.integer("reference").map(Int64.init) {
            // As the frames were read: a pair's JPEG stands for its raw.
            let item = resolved.first { $0.versionID == reference }
            let id = item.flatMap { MergeSelection.versionIDs(for: [$0]).first } ?? reference
            guard let chosen = selection.choosingReference(id) else {
                throw CommandError(.invalidValue, "--reference \(reference) is not one of the --version values")
            }
            selection = chosen
        }
        let options = MergeOptions(align: !arguments.flag("noAlign"), deghost: !arguments.flag("noDeghost"))
        let job = HDRMergeJob(catalog: catalog, metadataReader: MetadataReaders.makeDefault())
        do {
            let result = try await job.run(selection, format: format, options: options)
            return [
                "path": .string(result.url.path),
                "format": .string(format.rawValue),
                "frames": .array(selection.frames.map { JSONValue($0.versionID) }),
                "reference": JSONValue(selection.referenceFrame.versionID),
                "align": .bool(options.align),
                "deghost": .bool(options.deghost),
                "versionID": result.master.map { JSONValue($0.versionID) } ?? result.existingVersionID.map(JSONValue.init)
                    ?? .null,
            ]
        } catch let failure as HDRMergeJob.Failure {
            switch failure {
            case .refused(let refusal):
                throw CommandError(.invalidValue, "Refused: \(String(describing: refusal))")
            case .catalogFailed(let path, let reason):
                throw CommandError(.failed, "The merged file was written at \(path) but couldn't be catalogued: \(reason)")
            case .writeFailed, .noSpace:
                throw CommandError(.writeFailed, String(describing: failure))
            case .misaligned(let name, let reference):
                // The sheet's remedy is its Auto-align box; here it is the flag (design D-H10).
                throw CommandError(.failed, "\(name) doesn't line up with \(reference). Merge photos of the same "
                                       + "scene, or pass --no-align.")
            default:
                throw CommandError(.failed, String(describing: failure))
            }
        }
    }
}

extension Catalog {
    /// For each of `versionIDs` that is half of a RAW+JPEG pair's default
    /// versions, the other half's version and file type.
    public func pairPartners(of versionIDs: [Int64]) async throws -> [Int64: (versionID: Int64, kind: FileKind?)] {
        guard !versionIDs.isEmpty else { return [:] }
        return try await database.read { db in
            var result: [Int64: (versionID: Int64, kind: FileKind?)] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT v.id AS source, p.id AS partner, pi.relativePath AS path
                FROM version v
                JOIN imagePair ON imagePair.rawImageId = v.imageId OR imagePair.companionImageId = v.imageId
                JOIN version p ON p.isDefault AND p.imageId = CASE WHEN imagePair.rawImageId = v.imageId
                    THEN imagePair.companionImageId ELSE imagePair.rawImageId END
                JOIN image pi ON pi.id = p.imageId
                WHERE v.isDefault AND v.id IN (\(databaseQuestionMarks(count: versionIDs.count)))
                """, arguments: StatementArguments(versionIDs))
            for row in rows {
                let path: String = row["path"]
                result[row["source"]] = (row["partner"], FileKind(pathExtension: (path as NSString).pathExtension))
            }
            return result
        }
    }
}
