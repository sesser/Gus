import Foundation
import GRDB

/// A merged photo as the catalog holds it after a merge (issue #150).
public struct MergedMaster: Hashable, Sendable {
    public var imageID: Int64
    public var versionID: Int64
}

/// A merged photo taken out of the library by Undo, as the rows were, so
/// Redo can put back the same photo (R15).
public struct RemovedMaster: Hashable, Sendable {
    public var image: ImageRecord
    public var versions: [VersionRecord]
    var keywords: [VersionKeywordRecord]
    var sync: MetadataSyncRecord?
    var history: [RemovedCopy.HistoryRow]
    var historyVersions: [Int64]

    public var imageID: Int64 { image.id ?? 0 }
    public var defaultVersionID: Int64? { versions.first(where: \.isDefault)?.id }
}

public enum MergeCatalogFailure: Error, Equatable, Sendable {
    /// The file's path or content is already in the catalog (another import
    /// took it meanwhile); the id of that photo's default version, when found.
    case alreadyInLibrary(versionID: Int64?)
}

extension Catalog {
    /// Catalogues a merge's file as a new master in `projectID` (R6), as an
    /// import would (hash, size, date, the file's metadata), and gives it the
    /// reference's library values (R7): rating, flag, label, keywords and
    /// descriptive fields. One transaction: all of it or nothing.
    public func insertMergedMaster(_ master: NewMaster, volumeID: Int64, projectID: Int64, values: SidecarValues,
                                   importedAt: Date = Date()) async throws -> MergedMaster {
        try await database.write { db in
            var result = MasterInsertionResult()
            try Self.insertMaster(db, master, volumeID: volumeID, projectID: projectID, importRunID: nil,
                                  importedAt: importedAt, into: &result)
            guard let imageID = result.insertedImageIDs.first, let versionID = result.insertedVersionIDs.first else {
                let existing = try Int64.fetchOne(db, sql: """
                    SELECT version.id FROM version JOIN image ON image.id = version.imageId
                    WHERE version.isDefault AND ((image.volumeId = ? AND image.relativePath = ?) OR image.contentHash = ?)
                    """, arguments: [volumeID, master.relativePath, master.contentHash])
                throw MergeCatalogFailure.alreadyInLibrary(versionID: existing)
            }
            try db.execute(sql: "UPDATE version SET rating = ?, flag = ?, colorLabel = ? WHERE id = ?",
                           arguments: [values.rating.rawValue, values.flag.rawValue, values.colorLabel.rawValue, versionID])
            try db.execute(sql: "DELETE FROM versionKeyword WHERE versionId = ?", arguments: [versionID])
            for name in values.keywords {
                if let keywordID = try Self.findOrCreateKeyword(db, name: name).id {
                    try VersionKeywordRecord(versionId: versionID, keywordId: keywordID).insert(db, onConflict: .ignore)
                }
            }
            if var image = try ImageRecord.fetchOne(db, key: imageID) {
                image.artist = values.creator
                image.copyright = values.rights
                image.caption = values.caption
                image.usageTerms = values.usageTerms
                image.creatorContact = values.contact.flatMap(ImageRecord.contactJSON)
                image.title = values.title
                image.altText = values.altText
                image.extendedDescription = values.extendedDescription
                image.jobTitle = values.jobTitle
                try image.update(db)
            }
            let companions = try ImagePairing.pair(db, volumeID: volumeID, projectID: projectID,
                                                   keys: [ImagePairing.key(forRelativePath: master.relativePath)])
            for chunk in companions.chunked(into: 10_000) {
                try db.execute(sql: "DELETE FROM metadataSync WHERE imageId IN (\(databaseQuestionMarks(count: chunk.count)))",
                               arguments: StatementArguments(Array(chunk)))
            }
            return MergedMaster(imageID: imageID, versionID: versionID)
        }
    }

    /// Takes a merged photo out of the library (Undo, R15): its master and
    /// every row that hangs from it, kept for `restoreMergedMaster`. The
    /// file stays where it is. Nil when the photo is no longer there.
    public func removeMergedMaster(imageID: Int64) async throws -> RemovedMaster? {
        try await database.write { db in
            guard let image = try ImageRecord.fetchOne(db, key: imageID) else { return nil }
            let versions = try VersionRecord.filter(Column("imageId") == imageID).order(Column("id")).fetchAll(db)
            let ids = versions.compactMap(\.id)
            let keywords = try VersionKeywordRecord.filter(ids.contains(Column("versionId"))).fetchAll(db)
            let sync = try MetadataSyncRecord.filter(Column("imageId") == imageID).fetchOne(db)
            let historyRows = try Row.fetchAll(db, sql: """
                SELECT id, versionId, label, createdAt, stack FROM editHistory
                WHERE versionId IN (SELECT id FROM version WHERE imageId = ?) ORDER BY id
                """, arguments: [imageID])
            let history = historyRows.map {
                RemovedCopy.HistoryRow(id: $0["id"], label: $0["label"], createdAt: $0["createdAt"], stack: $0["stack"])
            }
            let historyVersions: [Int64] = historyRows.map { $0["versionId"] }
            _ = try Self.removeImages(db, imageIDs: [imageID])
            return RemovedMaster(image: image, versions: versions, keywords: keywords, sync: sync, history: history,
                                 historyVersions: historyVersions)
        }
    }

    /// Puts back a merged photo `removeMergedMaster` took out (Redo), with
    /// the same ids, when its file at `url` still has the size and date the
    /// catalog recorded; false (and nothing written) when it doesn't, or when
    /// its path or content is in the catalog again.
    public func restoreMergedMaster(_ removed: RemovedMaster, fileAt url: URL) async throws -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value, size == removed.image.fileSize,
              let modified = attributes[.modificationDate] as? Date,
              abs(modified.timeIntervalSince(removed.image.modifiedAt)) < 0.001
        else { return false }
        return try await database.write { db in
            let taken = try ImageRecord.filter(
                (Column("volumeId") == removed.image.volumeId && Column("relativePath") == removed.image.relativePath)
                    || Column("contentHash") == removed.image.contentHash).fetchCount(db)
            guard taken == 0, try ProjectRecord.fetchOne(db, key: removed.image.projectId) != nil else { return false }
            var image = removed.image
            try image.insert(db)
            for var version in removed.versions { try version.insert(db) }
            for keyword in removed.keywords { try keyword.insert(db, onConflict: .ignore) }
            if let sync = removed.sync { try sync.insert(db) }
            for (row, versionID) in zip(removed.history, removed.historyVersions) {
                try db.execute(sql: """
                    INSERT INTO editHistory (id, versionId, label, createdAt, stack) VALUES (?, ?, ?, ?, ?)
                    """, arguments: [row.id, versionID, row.label, row.createdAt, row.stack])
            }
            return true
        }
    }
}
