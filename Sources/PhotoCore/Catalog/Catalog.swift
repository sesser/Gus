import Foundation
import GRDB

/// The photo catalog: a SQLite database of volumes, masters, versions and their
/// organization. All access is async and safe from any task.
public final class Catalog: Sendable {
    public let database: any DatabaseWriter

    /// Opens (creating if needed) the catalog at `url` in WAL mode and runs migrations.
    public static func open(at url: URL) throws -> Catalog {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path, configuration: makeConfiguration())
        return try Catalog(database: pool)
    }

    /// A private in-memory catalog, for tests and previews.
    public static func makeInMemory() throws -> Catalog {
        try Catalog(database: DatabaseQueue(configuration: makeConfiguration()))
    }

    init(database: any DatabaseWriter) throws {
        self.database = database
        try CatalogSchema.migrator.migrate(database)
    }

    private static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "catalog"
        configuration.prepareDatabase { db in
            // WAL with NORMAL sync is durable across app crashes; only a power loss
            // can drop the last few transactions.
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        return configuration
    }
}

// MARK: - Volumes

/// What the file system says about a volume.
public struct VolumeDescriptor: Hashable, Sendable {
    public var identity: String
    public var name: String
    public var mountPath: String
    public var isRemovable: Bool
    public var isNetwork: Bool

    public init(identity: String, name: String, mountPath: String, isRemovable: Bool = false, isNetwork: Bool = false) {
        self.identity = identity
        self.name = name
        self.mountPath = mountPath
        self.isRemovable = isRemovable
        self.isNetwork = isNetwork
    }
}

extension Catalog {
    /// Inserts the volume or refreshes its name and mount point.
    public func registerVolume(_ descriptor: VolumeDescriptor, seenAt date: Date = Date()) async throws -> VolumeRecord {
        try await database.write { db in
            if var existing = try VolumeRecord.filter(VolumeRecord.Columns.identity == descriptor.identity).fetchOne(db) {
                existing.name = descriptor.name
                existing.mountPath = descriptor.mountPath
                existing.isRemovable = descriptor.isRemovable
                existing.isNetwork = descriptor.isNetwork
                existing.lastSeenAt = date
                try existing.update(db)
                return existing
            }
            var record = VolumeRecord(id: nil, identity: descriptor.identity, name: descriptor.name,
                                      mountPath: descriptor.mountPath, isRemovable: descriptor.isRemovable,
                                      isNetwork: descriptor.isNetwork, lastSeenAt: date)
            try record.insert(db)
            return record
        }
    }

    public func volumes() async throws -> [VolumeRecord] {
        try await database.read { db in try VolumeRecord.order(VolumeRecord.Columns.id).fetchAll(db) }
    }

    public func updateVolume(id: Int64, mountPath: String, seenAt date: Date = Date()) async throws {
        try await database.write { db in
            _ = try VolumeRecord.filter(key: id).updateAll(db, [
                VolumeRecord.Columns.mountPath.set(to: mountPath),
                VolumeRecord.Columns.lastSeenAt.set(to: date),
            ])
        }
    }
}

// MARK: - Projects

public struct ProjectSummary: Hashable, Sendable, Identifiable {
    public var project: ProjectRecord
    public var versionCount: Int
    public var id: Int64 { project.id ?? 0 }
}

extension Catalog {
    public func createProject(name: String, sourcePath: String? = nil, createdAt: Date = Date()) async throws -> ProjectRecord {
        try await database.write { db in
            var project = ProjectRecord(name: name, sourcePath: sourcePath, createdAt: createdAt)
            try project.insert(db)
            return project
        }
    }

    /// Projects, newest first, with the number of versions in each. With
    /// `groupingPairs`, a RAW+JPEG pair counts once.
    public func projectSummaries(groupingPairs: Bool = true) async throws -> [ProjectSummary] {
        try await database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT project.*, COUNT(version.id) AS versionCount
                FROM project
                LEFT JOIN image ON image.projectId = project.id
                LEFT JOIN version ON version.imageId = image.id
                GROUP BY project.id
                ORDER BY project.createdAt DESC, project.id DESC
                """)
            // Both halves of a pair are in one project, and grouping hides one.
            let pairs = groupingPairs ? try ImagePairing.pairCountsByProject(db) : [:]
            return try rows.map { row in
                let project = try ProjectRecord(row: row)
                let count: Int = row["versionCount"]
                return ProjectSummary(project: project, versionCount: count - (pairs[project.id ?? 0] ?? 0))
            }
        }
    }

    /// Starts an import run; the masters it adds point back to it.
    public func createImportRun(sourcePath: String?, projectID: Int64?, startedAt: Date = Date()) async throws -> ImportRunRecord {
        try await database.write { db in
            var run = ImportRunRecord(id: nil, startedAt: startedAt, sourcePath: sourcePath, projectId: projectID)
            try run.insert(db)
            return run
        }
    }

    /// The most recent import run that added at least one master.
    public func lastImportRun() async throws -> ImportRunRecord? {
        try await database.read { db in
            try ImportRunRecord.fetchOne(db, sql: """
                SELECT * FROM importRun WHERE EXISTS (SELECT 1 FROM image WHERE image.importRunId = importRun.id)
                ORDER BY startedAt DESC, id DESC LIMIT 1
                """)
        }
    }

    public func renameProject(id: Int64, to name: String) async throws {
        try await database.write { db in
            _ = try ProjectRecord.filter(key: id).updateAll(db, ProjectRecord.Columns.name.set(to: name))
        }
    }

    /// Removes the project and its masters from the catalog. Files on disk are
    /// never touched.
    public func deleteProject(id: Int64) async throws {
        _ = try await database.write { db in try ProjectRecord.deleteOne(db, key: id) }
    }
}

// MARK: - Import support

/// A master about to be registered by the importer.
public struct NewMaster: Hashable, Sendable {
    public var relativePath: String
    public var fileSize: Int64
    public var modifiedAt: Date
    public var contentHash: String
    public var metadata: ImageMetadata
    /// The sidecar found next to the file, if any. Its values take precedence
    /// over the ones embedded in the file.
    public var sidecar: SidecarRead?

    public init(relativePath: String, fileSize: Int64, modifiedAt: Date, contentHash: String, metadata: ImageMetadata,
                sidecar: SidecarRead? = nil) {
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.contentHash = contentHash
        self.metadata = metadata
        self.sidecar = sidecar
    }

    /// Metadata with the sidecar's values in place of the embedded ones.
    var effectiveMetadata: ImageMetadata {
        guard let values = sidecar?.values else { return metadata }
        var merged = metadata
        merged.rating = values.flag == .rejected ? -1 : values.rating.rawValue
        merged.label = values.colorLabel.xmpName
        if !values.keywords.isEmpty { merged.keywords = values.keywords }
        merged.artist = values.creator ?? metadata.artist
        merged.copyright = values.rights ?? metadata.copyright
        merged.caption = values.caption ?? metadata.caption
        merged.usageTerms = values.usageTerms ?? metadata.usageTerms
        merged.creatorContact = values.contact ?? metadata.creatorContact
        return merged
    }
}

/// What the catalog already knows about a path.
public struct KnownFile: Hashable, Sendable {
    public var imageId: Int64
    public var fileSize: Int64
    public var modifiedAt: Date
    public var contentHash: String
}

public struct MasterInsertionResult: Hashable, Sendable {
    public var insertedImageIDs: [Int64] = []
    public var insertedVersionIDs: [Int64] = []
    /// Content hashes that were already in the catalog (lost a race with another import).
    public var duplicateHashes: [String] = []
    /// Paths that are already registered with different content.
    public var conflictingPaths: [String] = []
    /// RAW+JPEG pairs formed with the inserted masters.
    public var pairsCreated = 0
}

extension Catalog {
    /// Catalog entries for the given paths on one volume, keyed by relative path.
    public func knownFiles(volumeID: Int64, relativePaths: [String]) async throws -> [String: KnownFile] {
        guard !relativePaths.isEmpty else { return [:] }
        return try await database.read { db in
            var result: [String: KnownFile] = [:]
            let request = ImageRecord
                .filter(ImageRecord.Columns.volumeId == volumeID)
                .filter(relativePaths.contains(ImageRecord.Columns.relativePath))
            for image in try request.fetchAll(db) {
                result[image.relativePath] = KnownFile(imageId: image.id ?? 0, fileSize: image.fileSize,
                                                       modifiedAt: image.modifiedAt, contentHash: image.contentHash)
            }
            return result
        }
    }

    /// The subset of `hashes` already registered.
    public func existingContentHashes(_ hashes: some Collection<String>) async throws -> Set<String> {
        guard !hashes.isEmpty else { return [] }
        let values = Array(hashes)
        return try await database.read { db in
            Set(try String.fetchAll(db, ImageRecord
                .select(ImageRecord.Columns.contentHash)
                .filter(values.contains(ImageRecord.Columns.contentHash))))
        }
    }

    /// Registers masters and creates one default version for each, in one
    /// transaction. Rows that collide with an existing hash or path are skipped
    /// and reported; they never abort the batch.
    public func insertMasters(_ masters: [NewMaster], volumeID: Int64, projectID: Int64, importRunID: Int64? = nil,
                              importedAt: Date = Date()) async throws -> MasterInsertionResult {
        guard !masters.isEmpty else { return MasterInsertionResult() }
        return try await database.write { db in
            var result = MasterInsertionResult()
            var insertedMasters: [NewMaster] = []
            for master in masters {
                let metadata = master.effectiveMetadata
                var image = ImageRecord(
                    id: nil, volumeId: volumeID, projectId: projectID,
                    relativePath: master.relativePath,
                    fileName: (master.relativePath as NSString).lastPathComponent,
                    fileSize: master.fileSize, modifiedAt: master.modifiedAt,
                    contentHash: master.contentHash,
                    format: (master.relativePath as NSString).pathExtension.lowercased(),
                    captureDate: metadata.captureDate, captureOffsetSeconds: metadata.captureOffsetSeconds,
                    sortDate: metadata.captureDate ?? master.modifiedAt,
                    pixelWidth: metadata.pixelWidth, pixelHeight: metadata.pixelHeight,
                    orientation: metadata.orientation,
                    cameraMake: metadata.cameraMake, cameraModel: metadata.cameraModel,
                    lensModel: metadata.lensModel, iso: metadata.iso, exposureTime: metadata.exposureTime,
                    fNumber: metadata.fNumber, focalLength: metadata.focalLength, importedAt: importedAt,
                    pairingKey: ImagePairing.key(forRelativePath: master.relativePath), importRunId: importRunID,
                    localDate: LocalDate.string(captureDate: metadata.captureDate, offset: metadata.captureOffsetSeconds,
                                                fallback: master.modifiedAt),
                    metadataRevision: ImageMetadata.revision)
                image.applyExtendedMetadata(metadata)
                try image.insert(db, onConflict: .ignore)
                guard db.changesCount > 0, let imageID = image.id else {
                    let hashExists = try ImageRecord.filter(ImageRecord.Columns.contentHash == master.contentHash).fetchCount(db) > 0
                    if hashExists {
                        result.duplicateHashes.append(master.contentHash)
                    } else {
                        result.conflictingPaths.append(master.relativePath)
                    }
                    continue
                }
                var version = VersionRecord.makeDefault(imageId: imageID, at: importedAt)
                (version.rating, version.flag, version.colorLabel) = metadata.embeddedCulling
                // A sidecar can hold a rating and a reject at once.
                if let values = master.sidecar?.values {
                    (version.rating, version.flag, version.colorLabel) = (values.rating, values.flag, values.colorLabel)
                }
                try version.insert(db)
                result.insertedImageIDs.append(imageID)
                insertedMasters.append(master)
                guard let versionID = version.id else { continue }
                result.insertedVersionIDs.append(versionID)
                for name in metadata.keywords {
                    let keyword = try Self.findOrCreateKeyword(db, name: name)
                    if let keywordID = keyword.id {
                        try VersionKeywordRecord(versionId: versionID, keywordId: keywordID).insert(db, onConflict: .ignore)
                    }
                }
            }
            // What the files say now is the sidecar baseline: values only change
            // the files once the library's values differ from it.
            for (imageID, master) in zip(result.insertedImageIDs, insertedMasters) {
                guard let image = try ImageRecord.fetchOne(db, key: imageID) else { continue }
                let values = try Self.sidecarValues(db, image: image)
                let file = master.sidecar?.file
                try MetadataSyncRecord(
                    imageId: imageID, sidecarName: file?.name, sidecarSize: file?.size, sidecarModifiedAt: file?.modifiedAt,
                    sidecarDigest: file?.digest, baseline: try values.jsonString(), status: .inStep, diskValues: nil,
                    diskSource: file == nil ? .embedded : .sidecar, checkedAt: importedAt, error: nil).insert(db)
            }
            // Partners may have come in an earlier batch or an earlier import.
            let keys = Set(masters.map { ImagePairing.key(forRelativePath: $0.relativePath) })
            result.pairsCreated = try ImagePairing.pair(db, volumeID: volumeID, projectID: projectID, keys: keys)
            // A pair's sidecar belongs to its RAW.
            try db.execute(sql: "DELETE FROM metadataSync WHERE imageId IN (SELECT companionImageId FROM imagePair)")
            return result
        }
    }
}

// MARK: - Metadata refresh

/// A master whose metadata columns were filled by an older reader.
public struct StaleMetadata: Hashable, Sendable {
    public var imageID: Int64
    public var url: URL
}

extension Catalog {
    /// Up to `limit` masters on the given (mounted) volumes whose metadata was
    /// read by an older `ImageMetadata.revision`.
    public func staleMetadata(onVolumes volumeIDs: Set<Int64>, limit: Int = 64) async throws -> [StaleMetadata] {
        guard !volumeIDs.isEmpty else { return [] }
        return try await database.read { db in
            let volumes = try VolumeRecord.fetchAll(db, keys: Array(volumeIDs))
            let mountPaths = Dictionary(uniqueKeysWithValues: volumes.compactMap { volume in volume.id.map { ($0, volume) } })
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, volumeId, relativePath FROM image
                WHERE metadataRevision < ? AND volumeId IN (\(databaseQuestionMarks(count: volumeIDs.count)))
                ORDER BY id LIMIT ?
                """, arguments: StatementArguments([ImageMetadata.revision as (any DatabaseValueConvertible)?]
                                                    + volumeIDs.map { $0 } + [limit]))
            return rows.compactMap { row in
                guard let volume = mountPaths[row["volumeId"]] else { return nil }
                return StaleMetadata(imageID: row["id"], url: volume.url(forRelativePath: row["relativePath"]))
            }
        }
    }

    /// Stores freshly read metadata columns. Masters missing from `metadata`
    /// (unreadable) are marked as read too, so they are not retried forever.
    public func refreshMetadata(_ metadata: [Int64: ImageMetadata], checked imageIDs: [Int64]) async throws {
        try await database.write { db in
            for imageID in imageIDs {
                guard var image = try ImageRecord.fetchOne(db, key: imageID) else { continue }
                if let values = metadata[imageID] {
                    image.applyExtendedMetadata(values)
                } else {
                    image.metadataRevision = ImageMetadata.revision
                }
                try image.update(db)
            }
        }
    }
}

// MARK: - Versions and culling

/// Everything the loupe info overlay needs about one version.
public struct VersionDetails: Hashable, Sendable {
    public var version: VersionRecord
    public var image: ImageRecord
    public var volume: VolumeRecord
}

extension Catalog {
    public func version(id: Int64) async throws -> VersionRecord? {
        try await database.read { db in try VersionRecord.fetchOne(db, key: id) }
    }

    public func versions(ofImage imageID: Int64) async throws -> [VersionRecord] {
        try await database.read { db in
            try VersionRecord.filter(VersionRecord.Columns.imageId == imageID)
                .order(VersionRecord.Columns.versionNumber).fetchAll(db)
        }
    }

    /// Every master, for tooling. The app never needs all of them at once.
    public func allImages() async throws -> [ImageRecord] {
        try await database.read { db in try ImageRecord.fetchAll(db) }
    }

    public func details(forVersion id: Int64) async throws -> VersionDetails? {
        try await database.read { db in
            guard let version = try VersionRecord.fetchOne(db, key: id),
                  let image = try ImageRecord.fetchOne(db, key: version.imageId),
                  let volume = try VolumeRecord.fetchOne(db, key: image.volumeId)
            else { return nil }
            return VersionDetails(version: version, image: image, volume: volume)
        }
    }

    public func setRating(_ rating: Rating, forVersions ids: some Collection<Int64>, at date: Date = Date()) async throws {
        try await update(ids, VersionRecord.Columns.rating, to: rating.databaseValue, at: date)
    }

    public func setFlag(_ flag: Flag, forVersions ids: some Collection<Int64>, at date: Date = Date()) async throws {
        try await update(ids, VersionRecord.Columns.flag, to: flag.databaseValue, at: date)
    }

    public func setColorLabel(_ label: ColorLabel, forVersions ids: some Collection<Int64>, at date: Date = Date()) async throws {
        try await update(ids, VersionRecord.Columns.colorLabel, to: label.databaseValue, at: date)
    }

    /// Sets all three culling values at once (used to restore them on undo).
    public func setCulling(rating: Rating, flag: Flag, colorLabel: ColorLabel, forVersions ids: some Collection<Int64>,
                           at date: Date = Date()) async throws {
        guard !ids.isEmpty else { return }
        let keys = Array(ids)
        try await database.write { db in
            let targets = keys + (try ImagePairing.partnerVersionIDs(db, of: keys))
            for chunk in targets.chunked(into: 10_000) {
                _ = try VersionRecord.filter(keys: chunk).updateAll(db, [
                    VersionRecord.Columns.rating.set(to: rating.databaseValue),
                    VersionRecord.Columns.flag.set(to: flag.databaseValue),
                    VersionRecord.Columns.colorLabel.set(to: colorLabel.databaseValue),
                    VersionRecord.Columns.modifiedAt.set(to: date),
                ])
            }
        }
    }

    private func update(_ ids: some Collection<Int64>, _ column: Column, to value: DatabaseValue, at date: Date) async throws {
        guard !ids.isEmpty else { return }
        let keys = Array(ids)
        try await database.write { db in
            let targets = keys + (try ImagePairing.partnerVersionIDs(db, of: keys))
            for chunk in targets.chunked(into: 10_000) {
                _ = try VersionRecord.filter(keys: chunk).updateAll(db, [
                    column.set(to: value),
                    VersionRecord.Columns.modifiedAt.set(to: date),
                ])
            }
        }
    }

    /// Replaces a version's edit stack and its render hash together.
    public func setEditStack(_ stack: EditStack, forVersion id: Int64, at date: Date = Date()) async throws {
        let json = try stack.jsonString()
        let hash = stack.renderHash
        try await database.write { db in
            _ = try VersionRecord.filter(key: id).updateAll(db, [
                VersionRecord.Columns.editStack.set(to: json),
                VersionRecord.Columns.editStackHash.set(to: hash),
                VersionRecord.Columns.modifiedAt.set(to: date),
            ])
        }
    }

    /// Creates a new version of the same master with a copy of `id`'s edit stack
    /// and culling state.
    public func duplicateVersion(id: Int64, at date: Date = Date()) async throws -> VersionRecord {
        try await database.write { db in
            guard var copy = try VersionRecord.fetchOne(db, key: id) else {
                throw RecordError.recordNotFound(databaseTableName: VersionRecord.databaseTableName,
                                                 key: ["id": id.databaseValue])
            }
            let highest = try Int.fetchOne(db, VersionRecord
                .select(max(VersionRecord.Columns.versionNumber))
                .filter(VersionRecord.Columns.imageId == copy.imageId)) ?? 0
            copy.id = nil
            copy.uuid = UUID().uuidString
            copy.versionNumber = highest + 1
            copy.name = nil
            copy.isDefault = false
            copy.createdAt = date
            copy.modifiedAt = date
            try copy.insert(db)
            return copy
        }
    }
}

// MARK: - Albums, stacks, keywords

extension Catalog {
    public func createAlbum(name: String, projectID: Int64? = nil, createdAt: Date = Date()) async throws -> AlbumRecord {
        try await database.write { db in
            var album = AlbumRecord(id: nil, uuid: UUID().uuidString, name: name, projectId: projectID, createdAt: createdAt)
            try album.insert(db)
            return album
        }
    }

    public func versionIDs(inAlbum albumID: Int64) async throws -> [Int64] {
        try await database.read { db in
            try Int64.fetchAll(db, AlbumMemberRecord
                .select(AlbumMemberRecord.Columns.versionId)
                .filter(AlbumMemberRecord.Columns.albumId == albumID)
                .order(AlbumMemberRecord.Columns.position))
        }
    }

    /// Stacks the versions in the given order; the first is the pick unless
    /// `pick` says otherwise. Fails if any version is already stacked.
    public func createStack(versionIDs: [Int64], pick: Int64? = nil, createdAt: Date = Date()) async throws -> StackRecord {
        try await database.write { db in
            var stack = StackRecord(id: nil, uuid: UUID().uuidString, pickVersionId: pick ?? versionIDs.first,
                                    createdAt: createdAt)
            try stack.insert(db)
            guard let stackID = stack.id else { return stack }
            for (position, versionID) in versionIDs.enumerated() {
                try StackMemberRecord(stackId: stackID, versionId: versionID, position: position).insert(db)
            }
            return stack
        }
    }

    public func versionIDs(inStack stackID: Int64) async throws -> [Int64] {
        try await database.read { db in
            try Int64.fetchAll(db, sql: "SELECT versionId FROM stackMember WHERE stackId = ? ORDER BY position",
                               arguments: [stackID])
        }
    }

    /// Returns the keyword with this name under `parentID`, creating it if needed.
    /// Names compare case-insensitively.
    public func keyword(named name: String, parentID: Int64? = nil) async throws -> KeywordRecord {
        try await database.write { db in
            let existing = try KeywordRecord.fetchOne(db, sql: """
                SELECT * FROM keyword WHERE ifnull(parentId, 0) = ifnull(?, 0) AND name = ? COLLATE NOCASE
                """, arguments: [parentID, name])
            if let existing { return existing }
            var keyword = KeywordRecord(id: nil, name: name, parentId: parentID)
            try keyword.insert(db)
            return keyword
        }
    }

    public func assignKeyword(_ keywordID: Int64, toVersions versionIDs: [Int64]) async throws {
        try await database.write { db in
            for versionID in versionIDs + (try ImagePairing.partnerVersionIDs(db, of: versionIDs)) {
                try VersionKeywordRecord(versionId: versionID, keywordId: keywordID).insert(db, onConflict: .ignore)
            }
        }
    }

    public func keywords(forVersion versionID: Int64) async throws -> [KeywordRecord] {
        try await database.read { db in
            try KeywordRecord.fetchAll(db, sql: """
                SELECT keyword.* FROM keyword
                JOIN versionKeyword ON versionKeyword.keywordId = keyword.id
                WHERE versionKeyword.versionId = ?
                ORDER BY keyword.name COLLATE NOCASE
                """, arguments: [versionID])
        }
    }
}
