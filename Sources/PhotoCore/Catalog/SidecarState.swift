import Foundation
import GRDB

/// What sidecar sync needs to know about one master that owns a sidecar.
public struct SidecarTarget: Hashable, Sendable {
    public var imageID: Int64
    public var volumeID: Int64
    public var masterURL: URL
    public var masterSize: Int64
    public var masterModifiedAt: Date
    public var contentHash: String
    /// The file name the app writes (see `SidecarFiles`).
    public var sidecarName: String
    /// The library's values now.
    public var values: SidecarValues
    public var sync: MetadataSyncRecord?

    public var folder: URL { masterURL.deletingLastPathComponent() }

    public var baseline: SidecarValues? {
        sync.flatMap { try? SidecarValues.decode(from: $0.baseline) }
    }
}

/// A photo whose sidecar or master another app changed, for review.
public struct DiskChange: Hashable, Sendable, Identifiable {
    public var imageID: Int64
    public var fileName: String
    public var library: SidecarValues
    public var disk: SidecarValues
    public var baseline: SidecarValues
    public var source: MetadataSyncRecord.Source
    public var id: Int64 { imageID }

    /// Fields the other app changed.
    public var changedFields: [SidecarValues.Field] { disk.differingFields(from: library) }
}

extension Catalog {
    // MARK: Owners

    /// The master that owns each image's sidecar: a pair's RAW, otherwise itself.
    static func sidecarOwners(_ db: Database, images: [Int64]) throws -> [Int64: Int64] {
        var owners = Dictionary(uniqueKeysWithValues: images.map { ($0, $0) })
        for chunk in images.chunked(into: 10_000) {
            let rows = try Row.fetchCursor(db, sql: """
                SELECT companionImageId, rawImageId FROM imagePair
                WHERE companionImageId IN (\(databaseQuestionMarks(count: chunk.count)))
                """, arguments: StatementArguments(Array(chunk)))
            while let row = try rows.next() { owners[row[0]] = row[1] }
        }
        return owners
    }

    /// Sidecar owners on the given volumes, for a full check.
    public func sidecarOwners(onVolumes volumeIDs: Set<Int64>) async throws -> [Int64] {
        guard !volumeIDs.isEmpty else { return [] }
        return try await database.read { db in
            try Int64.fetchAll(db, sql: """
                SELECT id FROM image
                WHERE volumeId IN (\(databaseQuestionMarks(count: volumeIDs.count)))
                  AND id NOT IN (SELECT companionImageId FROM imagePair)
                ORDER BY id
                """, arguments: StatementArguments(Array(volumeIDs)))
        }
    }

    // MARK: Queue

    /// Owners of up to `limit` queued masters.
    public func queuedSidecarOwners(limit: Int = 256) async throws -> [Int64] {
        try await database.read { db in
            let queued = try Int64.fetchAll(db, sql: "SELECT imageId FROM sidecarQueue ORDER BY imageId LIMIT ?",
                                            arguments: [limit])
            return Array(Set(try Self.sidecarOwners(db, images: queued).values)).sorted()
        }
    }

    public func hasQueuedSidecarWork() async throws -> Bool {
        try await database.read { db in try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM sidecarQueue)") ?? false }
    }

    /// Takes owners (and their pair partners) off the queue.
    public func dequeueSidecarWork(_ owners: [Int64]) async throws {
        try await database.write { db in
            for chunk in owners.chunked(into: 10_000) {
                let list = databaseQuestionMarks(count: chunk.count)
                try db.execute(sql: """
                    DELETE FROM sidecarQueue WHERE imageId IN (\(list))
                       OR imageId IN (SELECT companionImageId FROM imagePair WHERE rawImageId IN (\(list)))
                    """, arguments: StatementArguments(Array(chunk) + Array(chunk)))
            }
        }
    }

    // MARK: Targets

    public func sidecarTargets(owners: [Int64]) async throws -> [SidecarTarget] {
        guard !owners.isEmpty else { return [] }
        return try await database.read { db in
            var targets: [SidecarTarget] = []
            for chunk in owners.chunked(into: 2_000) {
                let images = try ImageRecord.fetchAll(db, keys: Array(chunk))
                let volumes = Dictionary(uniqueKeysWithValues: try VolumeRecord.fetchAll(db, keys: Set(images.map(\.volumeId)))
                    .compactMap { volume in volume.id.map { ($0, volume) } })
                let syncs = Dictionary(uniqueKeysWithValues: try MetadataSyncRecord.fetchAll(db, keys: Array(chunk))
                    .map { ($0.imageId, $0) })
                for image in images {
                    guard let id = image.id, let volume = volumes[image.volumeId] else { continue }
                    targets.append(SidecarTarget(
                        imageID: id, volumeID: image.volumeId,
                        masterURL: volume.url(forRelativePath: image.relativePath),
                        masterSize: image.fileSize, masterModifiedAt: image.modifiedAt, contentHash: image.contentHash,
                        sidecarName: SidecarFiles.preferredName(forMaster: image.fileName,
                                                                stemIsShared: try Self.stemIsShared(db, image)),
                        values: try Self.sidecarValues(db, image: image), sync: syncs[id]))
                }
            }
            return targets
        }
    }

    /// Another master in the folder, other than a pair partner, has the same stem.
    private static func stemIsShared(_ db: Database, _ image: ImageRecord) throws -> Bool {
        guard let key = image.pairingKey, let id = image.id else { return false }
        return try Bool.fetchOne(db, sql: """
            SELECT EXISTS (SELECT 1 FROM image WHERE volumeId = ? AND pairingKey = ? AND id <> ?
              AND id NOT IN (SELECT companionImageId FROM imagePair WHERE rawImageId = ?)
              AND id NOT IN (SELECT rawImageId FROM imagePair WHERE companionImageId = ?))
            """, arguments: [image.volumeId, key, id, id, id]) ?? false
    }

    /// The library's values for a master: its default version's culling and
    /// keywords, and its descriptive columns.
    static func sidecarValues(_ db: Database, image: ImageRecord) throws -> SidecarValues {
        var values = SidecarValues()
        if let version = try VersionRecord.filter(VersionRecord.Columns.imageId == image.id && Column("isDefault") == true)
            .fetchOne(db) {
            values.rating = version.rating
            values.flag = version.flag
            values.colorLabel = version.colorLabel
            values.keywords = try String.fetchAll(db, sql: """
                SELECT keyword.name FROM versionKeyword JOIN keyword ON keyword.id = versionKeyword.keywordId
                WHERE versionKeyword.versionId = ? ORDER BY keyword.name COLLATE NOCASE
                """, arguments: [version.id])
        }
        values.creator = image.artist
        values.rights = image.copyright
        values.caption = image.caption
        values.usageTerms = image.usageTerms
        values.contact = image.metadata.creatorContact
        return values
    }

    // MARK: Records

    public func saveSync(_ record: MetadataSyncRecord) async throws {
        try await database.write { db in try record.save(db) }
    }

    /// Updates a master whose file another app changed (embedded metadata, for
    /// instance). A new content hash means new previews.
    public func updateMasterFile(imageID: Int64, size: Int64, modifiedAt: Date, contentHash: String) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE image SET fileSize = ?, modifiedAt = ?, contentHash = ? WHERE id = ?",
                           arguments: [size, modifiedAt, contentHash, imageID])
        }
    }

    /// Sets the library's values for a master (and its pair partner) to
    /// `values`: culling, keywords (added and removed to match) and the
    /// descriptive fields.
    public func applySidecarValues(_ values: SidecarValues, toImage imageID: Int64) async throws {
        try await database.write { db in
            guard let image = try ImageRecord.fetchOne(db, key: imageID),
                  let version = try VersionRecord.filter(VersionRecord.Columns.imageId == imageID && Column("isDefault") == true)
                    .fetchOne(db), let versionID = version.id
            else { return }
            let targets = [versionID] + (try ImagePairing.partnerVersionIDs(db, of: [versionID]))
            for target in targets {
                try db.execute(sql: "UPDATE version SET rating = ?, flag = ?, colorLabel = ? WHERE id = ?",
                               arguments: [values.rating.rawValue, values.flag.rawValue, values.colorLabel.rawValue, target])
            }
            let current = try Self.sidecarValues(db, image: image).keywords
            let wanted = Set(values.keywords.map { $0.lowercased() })
            let missing = values.keywords.filter { name in !current.contains { $0.lowercased() == name.lowercased() } }
            _ = try Self.addKeywords(db, names: missing, toVersions: [versionID])
            for name in current where !wanted.contains(name.lowercased()) {
                guard let keyword = try Self.existingKeyword(db, name: name) else { continue }
                for target in targets {
                    try db.execute(sql: "DELETE FROM versionKeyword WHERE versionId = ? AND keywordId = ?",
                                   arguments: [target, keyword.id])
                }
            }
            let images = [imageID] + (try Int64.fetchAll(db, sql: "SELECT imageId FROM version WHERE id IN (\(databaseQuestionMarks(count: targets.count)))",
                                                         arguments: StatementArguments(targets)))
            for target in Set(images) {
                try db.execute(sql: """
                    UPDATE image SET artist = ?, copyright = ?, caption = ?, usageTerms = ?, creatorContact = ? WHERE id = ?
                    """, arguments: [values.creator, values.rights, values.caption, values.usageTerms,
                                     values.contact.flatMap(ImageRecord.contactJSON), target])
            }
        }
    }

    // MARK: Review

    public func diskChangeCount() async throws -> Int {
        try await database.read { db in
            try MetadataSyncRecord.filter(Column("status") == MetadataSyncRecord.Status.changedOnDisk.rawValue).fetchCount(db)
        }
    }

    /// Outside changes waiting for review among the masters of `versionIDs`.
    public func diskChanges(forVersions versionIDs: [Int64]) async throws -> [DiskChange] {
        guard !versionIDs.isEmpty else { return [] }
        return try await database.read { db in
            var images: [Int64] = []
            for chunk in versionIDs.chunked(into: 10_000) {
                images += try Int64.fetchAll(db, sql: """
                    SELECT imageId FROM version WHERE id IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments(Array(chunk)))
            }
            let owners = Array(Set(try Self.sidecarOwners(db, images: images).values)).sorted()
            var changes: [DiskChange] = []
            for chunk in owners.chunked(into: 2_000) {
                let records = try MetadataSyncRecord.fetchAll(db, keys: Array(chunk))
                for record in records where record.status == .changedOnDisk {
                    guard let image = try ImageRecord.fetchOne(db, key: record.imageId),
                          let disk = record.diskValues.flatMap({ try? SidecarValues.decode(from: $0) }),
                          let baseline = try? SidecarValues.decode(from: record.baseline)
                    else { continue }
                    changes.append(DiskChange(imageID: record.imageId, fileName: image.fileName,
                                              library: try Self.sidecarValues(db, image: image),
                                              disk: disk, baseline: baseline, source: record.diskSource))
                }
            }
            return changes
        }
    }
}
