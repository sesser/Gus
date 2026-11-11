import Foundation
import GRDB

/// What removing photos from the library would take, read before the person
/// is asked (docs/features/library-ops). Removal only ever changes the
/// catalog: masters and sidecar files are never touched.
public struct PhotoRemovalPlan: Hashable, Sendable {
    /// The versions the person chose.
    public var versionIDs: [Int64]
    /// Every master that goes: those of the chosen versions and, for a
    /// RAW+JPEG pair, the partner too (R7).
    public var imageIDs: [Int64]

    public var fileCount: Int { imageIDs.count }
}

/// What removing a project from the library would take.
public struct ProjectRemovalPlan: Hashable, Sendable {
    public var project: ProjectRecord
    /// Its photos as the sidebar counts them (a grouped pair once).
    public var photoCount: Int
    /// Its masters: both files of every pair.
    public var fileCount: Int
    /// Its own albums and smart albums, which go with it (R8).
    public var albumCount: Int
}

/// What a removal took out of the catalog.
public struct RemovalResult: Hashable, Sendable {
    public var imageIDs: [Int64] = []
    public var versionCount = 0
    /// Albums and smart albums deleted with a project.
    public var albumCount = 0
}

extension Catalog {
    // MARK: Photos

    /// The masters a removal of `versionIDs` would take, pair partners included.
    public func photoRemovalPlan(forVersions versionIDs: [Int64]) async throws -> PhotoRemovalPlan {
        try await database.read { db in
            PhotoRemovalPlan(versionIDs: versionIDs, imageIDs: try Self.removalImageIDs(db, versionIDs: versionIDs))
        }
    }

    /// Removes the photos of `versionIDs` from the catalog: their masters,
    /// every version of them, and for a RAW+JPEG pair both files, with
    /// everything that hangs on them (edits, edit history, culling values,
    /// keyword links, album memberships, stack and pair links, suggestions,
    /// sidecar bookkeeping and queued sidecar writes). Keywords and albums
    /// stay. One transaction: it happens whole or not at all (R13).
    @discardableResult
    public func removePhotos(versionIDs: [Int64]) async throws -> RemovalResult {
        try await database.write { db in
            try Self.removeImages(db, imageIDs: try Self.removalImageIDs(db, versionIDs: versionIDs))
        }
    }

    // MARK: Projects

    /// Nil when the project is gone.
    public func projectRemovalPlan(id: Int64, groupingPairs: Bool = true) async throws -> ProjectRemovalPlan? {
        try await database.read { db in
            guard let project = try ProjectRecord.fetchOne(db, key: id) else { return nil }
            let files = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM image WHERE projectId = ?", arguments: [id]) ?? 0
            let versions = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM version JOIN image ON image.id = version.imageId WHERE image.projectId = ?
                """, arguments: [id]) ?? 0
            let pairs = groupingPairs ? try ImagePairing.pairCountsByProject(db)[id] ?? 0 : 0
            return ProjectRemovalPlan(project: project, photoCount: versions - pairs, fileCount: files,
                                      albumCount: try Self.ownAlbumCount(db, projectID: id))
        }
    }

    /// Removes the project, its photos (as `removePhotos` does) and its own
    /// albums and smart albums, in one transaction. Albums of the library and
    /// of other projects stay, without the photos that are gone. Files and
    /// folders on disk are never touched.
    @discardableResult
    public func removeProject(id: Int64) async throws -> RemovalResult {
        try await database.write { db in
            let images = try Int64.fetchAll(db, sql: "SELECT id FROM image WHERE projectId = ? ORDER BY id", arguments: [id])
            var result = try Self.removeImages(db, imageIDs: images)
            result.albumCount = try Self.ownAlbumCount(db, projectID: id)
            // Its albums and smart albums cascade from the project.
            try ProjectRecord.deleteOne(db, key: id)
            return result
        }
    }

    // MARK: In a transaction

    private static func ownAlbumCount(_ db: Database, projectID: Int64) throws -> Int {
        try Int.fetchOne(db, sql: """
            SELECT (SELECT COUNT(*) FROM album WHERE projectId = ?) + (SELECT COUNT(*) FROM smartAlbum WHERE projectId = ?)
            """, arguments: [projectID, projectID]) ?? 0
    }

    /// The masters of `versionIDs` and their pair partners, in id order.
    static func removalImageIDs(_ db: Database, versionIDs: [Int64]) throws -> [Int64] {
        var images: Set<Int64> = []
        for chunk in versionIDs.chunked(into: 10_000) {
            images.formUnion(try Int64.fetchAll(db, sql: """
                SELECT DISTINCT imageId FROM version WHERE id IN (\(databaseQuestionMarks(count: chunk.count)))
                """, arguments: StatementArguments(Array(chunk))))
        }
        var partners: Set<Int64> = []
        for chunk in Array(images).chunked(into: 10_000) {
            let list = databaseQuestionMarks(count: chunk.count)
            partners.formUnion(try Int64.fetchAll(db, sql: """
                SELECT companionImageId FROM imagePair WHERE rawImageId IN (\(list))
                UNION
                SELECT rawImageId FROM imagePair WHERE companionImageId IN (\(list))
                """, arguments: StatementArguments(Array(chunk) + Array(chunk))))
        }
        return images.union(partners).sorted()
    }

    /// Deletes the masters. Versions, edit history, keyword links, album
    /// memberships, stack members, pair links, suggestions and sidecar
    /// bookkeeping cascade from them (see `CatalogSchema`). Two things do
    /// not, and are done here: `sidecarQueue` has no foreign key, and a stack
    /// outlives its members.
    static func removeImages(_ db: Database, imageIDs: [Int64]) throws -> RemovalResult {
        var result = RemovalResult(imageIDs: imageIDs)
        var emptiedStacks: Set<Int64> = []
        for chunk in imageIDs.chunked(into: 10_000) {
            let list = databaseQuestionMarks(count: chunk.count)
            let arguments = StatementArguments(Array(chunk))
            result.versionCount += try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM version WHERE imageId IN (\(list))",
                                                    arguments: arguments) ?? 0
            emptiedStacks.formUnion(try Int64.fetchAll(db, sql: """
                SELECT DISTINCT stackId FROM stackMember
                WHERE versionId IN (SELECT id FROM version WHERE imageId IN (\(list)))
                """, arguments: arguments))
            try db.execute(sql: "DELETE FROM image WHERE id IN (\(list))", arguments: arguments)
        }
        // After the masters: a write queued for a photo that is gone must
        // never reach its sidecar (R5, R6), whatever the delete's own
        // triggers queued on the way.
        for chunk in imageIDs.chunked(into: 10_000) {
            try db.execute(sql: "DELETE FROM sidecarQueue WHERE imageId IN (\(databaseQuestionMarks(count: chunk.count)))",
                           arguments: StatementArguments(Array(chunk)))
        }
        // A stack that lost every member is nothing; one that keeps some stays.
        for chunk in Array(emptiedStacks).chunked(into: 10_000) {
            try db.execute(sql: """
                DELETE FROM stack WHERE id IN (\(databaseQuestionMarks(count: chunk.count)))
                  AND NOT EXISTS (SELECT 1 FROM stackMember WHERE stackMember.stackId = stack.id)
                """, arguments: StatementArguments(Array(chunk)))
        }
        return result
    }
}
