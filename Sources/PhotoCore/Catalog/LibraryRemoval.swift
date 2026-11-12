import Foundation
import GRDB

/// What removing photos from the library would take, read before the person
/// is asked (docs/features/library-ops; copies: docs/features/virtual-copies
/// R6). Removal only ever changes the catalog: masters and sidecar files are
/// never touched.
///
/// An original (a master's default version) takes its master with it:
/// every version of it, so its copies too, and for a RAW+JPEG pair the
/// partner's master. A copy takes only itself, unless its original goes.
public struct PhotoRemovalPlan: Hashable, Sendable {
    /// The versions the person chose.
    public var versionIDs: [Int64]
    /// Every master that goes: those of the chosen originals and, for a
    /// RAW+JPEG pair, the partner too (library-ops R7).
    public var imageIDs: [Int64]
    /// The chosen copies that go alone: their masters stay.
    public var copyVersionIDs: [Int64]
    /// How many of the chosen versions are originals.
    public var originalCount: Int
    /// Copies that go with their masters and were not chosen themselves,
    /// for the confirmation ("Its 2 copies are removed with it.").
    public var extraCopyCount: Int

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
    /// The masters removed, with every version of them.
    public var imageIDs: [Int64] = []
    /// Copies removed alone, their masters staying.
    public var copyVersionIDs: [Int64] = []
    /// Every version removed: those of the masters and the copies.
    public var versionCount = 0
    /// Albums and smart albums deleted with a project.
    public var albumCount = 0
}

extension Catalog {
    // MARK: Photos

    /// What a removal of `versionIDs` would take: masters (pair partners
    /// included) and copies that go alone.
    public func photoRemovalPlan(forVersions versionIDs: [Int64]) async throws -> PhotoRemovalPlan {
        try await database.read { db in try Self.removalPlan(db, versionIDs: versionIDs) }
    }

    /// Removes the photos of `versionIDs` from the catalog. For an original:
    /// its master, every version of it (its copies too), and for a RAW+JPEG
    /// pair both files, with everything that hangs on them (edits, edit
    /// history, culling values, keyword links, album memberships, stack and
    /// pair links, suggestions, sidecar bookkeeping and queued sidecar
    /// writes). For a copy whose original stays: that version only, with its
    /// edits, history, culling values, keyword and album links; the master,
    /// the original and what is queued for its sidecar stay. Keywords and
    /// albums stay. One transaction: it happens whole or not at all (R13).
    @discardableResult
    public func removePhotos(versionIDs: [Int64]) async throws -> RemovalResult {
        try await database.write { db in
            let plan = try Self.removalPlan(db, versionIDs: versionIDs)
            var result = try Self.removeImages(db, imageIDs: plan.imageIDs)
            result.versionCount += try Self.deleteCopies(db, versionIDs: plan.copyVersionIDs)
            result.copyVersionIDs = plan.copyVersionIDs
            return result
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

    /// Sorts `versionIDs` into originals, whose masters go (with their pair
    /// partners), and copies. A copy whose master goes anyway is not listed
    /// on its own.
    static func removalPlan(_ db: Database, versionIDs: [Int64]) throws -> PhotoRemovalPlan {
        var images: Set<Int64> = []
        var copies: [(id: Int64, imageID: Int64)] = []
        var originalCount = 0
        for chunk in versionIDs.chunked(into: 10_000) {
            let rows = try Row.fetchCursor(db, sql: """
                SELECT id, imageId, isDefault FROM version WHERE id IN (\(databaseQuestionMarks(count: chunk.count)))
                ORDER BY id
                """, arguments: StatementArguments(Array(chunk)))
            while let row = try rows.next() {
                if row[2] as Bool {
                    images.insert(row[1])
                    originalCount += 1
                } else {
                    copies.append((row[0], row[1]))
                }
            }
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
        let going = images.union(partners)
        var copiesOfGoing = 0
        for chunk in Array(going).chunked(into: 10_000) {
            copiesOfGoing += try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM version WHERE NOT isDefault AND imageId IN (\(databaseQuestionMarks(count: chunk.count)))
                """, arguments: StatementArguments(Array(chunk))) ?? 0
        }
        let chosenWithMaster = copies.filter { going.contains($0.imageID) }.count
        return PhotoRemovalPlan(versionIDs: versionIDs, imageIDs: going.sorted(),
                                copyVersionIDs: copies.filter { !going.contains($0.imageID) }.map(\.id),
                                originalCount: originalCount, extraCopyCount: copiesOfGoing - chosenWithMaster)
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
        try deleteEmptyStacks(db, among: emptiedStacks)
        return result
    }
}
