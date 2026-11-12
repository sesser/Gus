import Foundation
import GRDB

/// Copies of a photo (docs/features/virtual-copies): further versions of one
/// master, each with its own edits, edit history, rating, flag, label,
/// keywords and albums. The original is the master's default version; a copy
/// is any other version of it. Copies live in the catalog only: the sidecar
/// triggers fire for default versions, so nothing a copy holds reaches a
/// sidecar, and `ImagePairing` works on default versions, so a copy is never
/// half of a RAW+JPEG pair.

/// A copy's name. It has no file of its own, so it is named after its
/// original, the way the Finder names duplicates: "IMG_0412 copy", then
/// "IMG_0412 copy 2", "copy 3"… (design §5.1). The number comes from
/// `versionNumber`, which never changes, so removing "copy" does not rename
/// "copy 2".
///
/// This is the one place a copy's name is made. The words are the caller's:
/// the app passes localized ones, tools without a String Catalog use `plain`.
public struct CopyNaming: Sendable {
    /// The name of copy `number` (from 1) of the photo called `baseName`.
    public var name: @Sendable (_ baseName: String, _ number: Int) -> String

    public init(name: @escaping @Sendable (_ baseName: String, _ number: Int) -> String) {
        self.name = name
    }

    /// Plain English, as `photocli` writes it.
    public static let plain = CopyNaming { baseName, number in
        number <= 1 ? "\(baseName) copy" : "\(baseName) copy \(number)"
    }

    /// Which copy a version is, from 1; nil for an original. Version 2 is
    /// the first copy.
    public static func copyNumber(versionNumber: Int, isCopy: Bool) -> Int? {
        isCopy ? max(versionNumber - 1, 1) : nil
    }

    /// `baseName` for an original, the copy's name otherwise.
    public func displayName(baseName: String, copyNumber: Int?) -> String {
        copyNumber.map { name(baseName, $0) } ?? baseName
    }

    /// The name the grid shows under `item`: its file name without the
    /// extension, and for a copy which copy it is.
    public func displayName(of item: CatalogItem) -> String {
        displayName(baseName: item.baseName, copyNumber: item.copyNumber)
    }

    /// A copy's name, nil for an original.
    public func copyName(of version: VersionRecord, fileName: String) -> String? {
        CopyNaming.copyNumber(versionNumber: version.versionNumber, isCopy: !version.isDefault).map {
            name((fileName as NSString).deletingPathExtension, $0)
        }
    }
}

/// What File ▸ Duplicate acts on (design §4.1).
public enum DuplicateTargets {
    /// Whether videos are duplicated. Proposed default P1 of the PRD, pending
    /// the owner: a video has no adjustments, so its copy could differ only in
    /// culling, keywords and albums. Nothing else decides this.
    public static let includesVideos = false

    /// The versions to duplicate among `targets`, in their order, and how many
    /// videos were left out.
    public static func resolve(_ targets: some Sequence<CatalogItem>) -> (versionIDs: [Int64], skippedVideos: Int) {
        var ids: [Int64] = []
        var videos = 0
        for item in targets {
            if item.isVideo && !includesVideos {
                videos += 1
            } else {
                ids.append(item.versionID)
            }
        }
        return (ids, videos)
    }

    /// Duplicate has something to act on.
    public static func canDuplicate(_ targets: some Sequence<CatalogItem>) -> Bool {
        targets.contains { includesVideos || !$0.isVideo }
    }
}

/// Where a new copy goes in the browser's list (design §4.2): after its
/// master's other items, which is where `LibrarySort.orderTerms` puts it. The
/// list is changed in place rather than read again so that photos which no
/// longer match the filter, but stay on screen until it changes, stay.
public enum DuplicatePlacement {
    /// The index to insert `copy` at. `copy` has the highest version number
    /// of its master, so it follows every item of that master it sorts with:
    /// all of them by capture date and file name, those with its rating by
    /// rating. With none on screen it goes to the end.
    public static func insertionIndex(for copy: CatalogItem, in items: [CatalogItem], sort: LibrarySort) -> Int {
        let last = items.lastIndex { item in
            item.imageID == copy.imageID && (sort.key != .rating || item.rating == copy.rating)
        } ?? items.lastIndex { $0.imageID == copy.imageID }
        return last.map { $0 + 1 } ?? items.count
    }

    /// `items` with `copies` inserted, each at its place, in the order given
    /// (the order they were made in).
    public static func inserting(_ copies: [CatalogItem], into items: [CatalogItem], sort: LibrarySort) -> [CatalogItem] {
        var result = items
        for copy in copies {
            result.insert(copy, at: insertionIndex(for: copy, in: result, sort: sort))
        }
        return result
    }
}

/// A copy Duplicate made, and the version it was made from.
public struct DuplicatedVersion: Hashable, Sendable {
    public var sourceVersionID: Int64
    public var copy: VersionRecord

    public var copyVersionID: Int64 { copy.id ?? 0 }
}

/// A copy as Undo Duplicate took it out of the catalog: everything the
/// catalog held for it, so Redo puts the same copy back, ids included (later
/// undo steps name the copy by its version id).
public struct RemovedCopy: Hashable, Sendable {
    struct HistoryRow: Hashable, Sendable {
        var id: Int64
        var label: String
        var createdAt: Date
        var stack: Data
    }

    public var version: VersionRecord
    var keywordIDs: [Int64]
    var albumMembers: [AlbumMemberRecord]
    var history: [HistoryRow]

    public var versionID: Int64 { version.id ?? 0 }
}

extension Catalog {
    /// Makes a copy of each of `ids`, in order: a new version of the same
    /// master with the source's edit stack and its culling values, keywords
    /// and album memberships as they are now. Each then changes on its own.
    /// One transaction: every copy is made or none is.
    ///
    /// - The stack is copied as stored, never decoded, so a stack this build
    ///   cannot read is copied unchanged; the copy is then as uneditable as
    ///   its source (`setEditStacks` refuses to write over it).
    /// - Edit history starts empty, and a copy joins no stack.
    /// - Nothing is queued for a sidecar: the triggers fire for default
    ///   versions only, and a copy is never one.
    /// - A copy takes the highest version number of its master plus one, so
    ///   a number freed by removing the newest copy is used again.
    @discardableResult
    public func duplicateVersions(ids: [Int64], at date: Date = Date()) async throws -> [DuplicatedVersion] {
        guard !ids.isEmpty else { return [] }
        return try await database.write { db in
            var highest: [Int64: Int] = [:]
            var made: [DuplicatedVersion] = []
            made.reserveCapacity(ids.count)
            let copyKeywords = try db.makeStatement(sql: """
                INSERT INTO versionKeyword (versionId, keywordId)
                SELECT ?, keywordId FROM versionKeyword WHERE versionId = ?
                """)
            let copyAlbums = try db.makeStatement(sql: """
                INSERT INTO albumMember (albumId, versionId, position)
                SELECT albumId, ?, position FROM albumMember WHERE versionId = ?
                """)
            for id in ids {
                guard var copy = try VersionRecord.fetchOne(db, key: id) else {
                    throw RecordError.recordNotFound(databaseTableName: VersionRecord.databaseTableName,
                                                     key: ["id": id.databaseValue])
                }
                let number: Int
                if let known = highest[copy.imageId] {
                    number = known + 1
                } else {
                    number = (try Int.fetchOne(db, VersionRecord
                        .select(max(VersionRecord.Columns.versionNumber))
                        .filter(VersionRecord.Columns.imageId == copy.imageId)) ?? 0) + 1
                }
                highest[copy.imageId] = number
                copy.id = nil
                copy.uuid = UUID().uuidString
                copy.versionNumber = number
                copy.name = nil
                copy.isDefault = false
                copy.createdAt = date
                copy.modifiedAt = date
                try copy.insert(db)
                guard let copyID = copy.id else { continue }
                try copyKeywords.execute(arguments: [copyID, id])
                try copyAlbums.execute(arguments: [copyID, id])
                made.append(DuplicatedVersion(sourceVersionID: id, copy: copy))
            }
            return made
        }
    }

    /// Makes one copy (`duplicateVersions`).
    public func duplicateVersion(id: Int64, at date: Date = Date()) async throws -> VersionRecord {
        guard let made = try await duplicateVersions(ids: [id], at: date).first else {
            throw RecordError.recordNotFound(databaseTableName: VersionRecord.databaseTableName,
                                             key: ["id": id.databaseValue])
        }
        return made.copy
    }

    /// Takes copies out of the catalog and returns what it held for them, for
    /// `restoreCopies` (Undo Duplicate). An original among `versionIDs` is
    /// left alone: this never removes a master's default version. Masters,
    /// originals, files and sidecars are untouched, and nothing is queued for
    /// a sidecar.
    @discardableResult
    public func removeCopies(versionIDs: [Int64]) async throws -> [RemovedCopy] {
        guard !versionIDs.isEmpty else { return [] }
        return try await database.write { db in
            var removed: [RemovedCopy] = []
            for id in versionIDs {
                guard let version = try VersionRecord.fetchOne(db, key: id), !version.isDefault else { continue }
                let keywords = try Int64.fetchAll(db, sql: """
                    SELECT keywordId FROM versionKeyword WHERE versionId = ? ORDER BY keywordId
                    """, arguments: [id])
                let albums = try AlbumMemberRecord.fetchAll(db, sql: """
                    SELECT * FROM albumMember WHERE versionId = ? ORDER BY albumId
                    """, arguments: [id])
                let history = try Row.fetchAll(db, sql: """
                    SELECT id, label, createdAt, stack FROM editHistory WHERE versionId = ? ORDER BY id
                    """, arguments: [id]).map {
                    RemovedCopy.HistoryRow(id: $0["id"], label: $0["label"], createdAt: $0["createdAt"], stack: $0["stack"])
                }
                removed.append(RemovedCopy(version: version, keywordIDs: keywords, albumMembers: albums, history: history))
            }
            try Self.deleteCopies(db, versionIDs: removed.map(\.versionID))
            return removed
        }
    }

    /// Puts copies back as `removeCopies` took them: the same version ids and
    /// numbers, with their keywords, albums and edit history. A keyword or an
    /// album deleted meanwhile is skipped. One transaction.
    public func restoreCopies(_ copies: [RemovedCopy]) async throws {
        guard !copies.isEmpty else { return }
        try await database.write { db in
            for copy in copies {
                var version = copy.version
                try version.insert(db)
                for keywordID in copy.keywordIDs {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO versionKeyword (versionId, keywordId)
                        SELECT ?, id FROM keyword WHERE id = ?
                        """, arguments: [copy.versionID, keywordID])
                }
                for member in copy.albumMembers {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO albumMember (albumId, versionId, position)
                        SELECT id, ?, ? FROM album WHERE id = ?
                        """, arguments: [member.versionId, member.position, member.albumId])
                }
                for row in copy.history {
                    try db.execute(sql: """
                        INSERT INTO editHistory (id, versionId, label, createdAt, stack) VALUES (?, ?, ?, ?, ?)
                        """, arguments: [row.id, copy.versionID, row.label, row.createdAt, row.stack])
                }
            }
        }
    }

    /// Deletes copies (never a default version). Their edit history, keyword
    /// links, album memberships and stack links cascade (`CatalogSchema`); a
    /// stack left without members goes too. Returns how many were deleted.
    @discardableResult
    static func deleteCopies(_ db: Database, versionIDs: [Int64]) throws -> Int {
        var deleted = 0
        var emptiedStacks: Set<Int64> = []
        for chunk in versionIDs.chunked(into: 10_000) {
            let list = databaseQuestionMarks(count: chunk.count)
            let arguments = StatementArguments(Array(chunk))
            emptiedStacks.formUnion(try Int64.fetchAll(db, sql: """
                SELECT DISTINCT stackId FROM stackMember WHERE versionId IN (\(list))
                """, arguments: arguments))
            try db.execute(sql: "DELETE FROM version WHERE NOT isDefault AND id IN (\(list))", arguments: arguments)
            deleted += db.changesCount
        }
        try deleteEmptyStacks(db, among: emptiedStacks)
        return deleted
    }

    /// A stack that lost every member is nothing; one that keeps some stays.
    static func deleteEmptyStacks(_ db: Database, among stackIDs: Set<Int64>) throws {
        for chunk in Array(stackIDs).chunked(into: 10_000) {
            try db.execute(sql: """
                DELETE FROM stack WHERE id IN (\(databaseQuestionMarks(count: chunk.count)))
                  AND NOT EXISTS (SELECT 1 FROM stackMember WHERE stackMember.stackId = stack.id)
                """, arguments: StatementArguments(Array(chunk)))
        }
    }
}
