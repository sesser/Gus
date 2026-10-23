import Foundation
import GRDB

/// An album with the number of photos in it.
public struct AlbumSummary: Hashable, Sendable, Identifiable {
    public var album: AlbumRecord
    public var count: Int
    public var id: Int64 { album.id ?? 0 }
}

/// A smart album, with its rules decoded.
public struct SmartAlbum: Hashable, Sendable, Identifiable {
    public var id: Int64
    public var uuid: String
    public var name: String
    /// Limits the album to one project; nil for the whole library.
    public var projectID: Int64?
    public var rules: SmartAlbumRules
    public var createdAt: Date

    init(_ record: SmartAlbumRecord) {
        id = record.id ?? 0
        uuid = record.uuid
        name = record.name
        projectID = record.projectId
        rules = (try? SmartAlbumRules.decode(from: record.rules)) ?? SmartAlbumRules()
        createdAt = record.createdAt
    }

    func record() throws -> SmartAlbumRecord {
        SmartAlbumRecord(id: id, uuid: uuid, name: name, projectId: projectID, rules: try rules.jsonString(),
                         createdAt: createdAt)
    }

    public var scope: LibraryFilter.Scope { .rules(rules, projectID: projectID) }
}

/// A deleted album, with enough to put it back.
public struct DeletedAlbum: Hashable, Sendable {
    public var album: AlbumRecord
    public var members: [AlbumMemberRecord]
}

/// Photos in one calendar month, by capture date.
public struct CaptureMonth: Hashable, Sendable, Identifiable {
    public var year: Int
    public var month: Int
    public var count: Int
    public var id: String { String(format: "%04d-%02d", year, month) }

    /// The month's first day and the next month's, as `captureDays` bounds.
    public var days: (start: String, end: String) {
        let next = month == 12 ? (year + 1, 1) : (year, month + 1)
        return (String(format: "%04d-%02d-01", year, month), String(format: "%04d-%02d-01", next.0, next.1))
    }
}

extension Catalog {
    // MARK: Albums

    /// Albums (library-wide and in projects) by name, with photo counts. With
    /// `groupingPairs` a pair whose halves are both in an album counts once.
    public func albumSummaries(groupingPairs: Bool = true) async throws -> [AlbumSummary] {
        try await database.read { db in
            let albums = try AlbumRecord.fetchAll(db, sql: "SELECT * FROM album ORDER BY name COLLATE NOCASE, id")
            var counts: [Int64: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT albumId, COUNT(*) FROM albumMember GROUP BY albumId") {
                counts[row[0]] = row[1]
            }
            if groupingPairs {
                for row in try Row.fetchAll(db, sql: """
                    SELECT rawMember.albumId, COUNT(*) FROM imagePair
                    JOIN version rawVersion ON rawVersion.imageId = imagePair.rawImageId AND rawVersion.isDefault
                    JOIN version companionVersion ON companionVersion.imageId = imagePair.companionImageId
                        AND companionVersion.isDefault
                    JOIN albumMember rawMember ON rawMember.versionId = rawVersion.id
                    JOIN albumMember companionMember ON companionMember.versionId = companionVersion.id
                        AND companionMember.albumId = rawMember.albumId
                    GROUP BY rawMember.albumId
                    """) {
                    counts[row[0], default: 0] -= row[1]
                }
            }
            return albums.map { AlbumSummary(album: $0, count: counts[$0.id ?? 0] ?? 0) }
        }
    }

    public func renameAlbum(id: Int64, to name: String) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE album SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    public func deleteAlbum(id: Int64) async throws -> DeletedAlbum? {
        try await database.write { db in
            guard let album = try AlbumRecord.fetchOne(db, key: id) else { return nil }
            let members = try AlbumMemberRecord.filter(AlbumMemberRecord.Columns.albumId == id).fetchAll(db)
            try album.delete(db)
            return DeletedAlbum(album: album, members: members)
        }
    }

    public func restoreAlbum(_ deleted: DeletedAlbum) async throws {
        try await database.write { db in
            var album = deleted.album
            try album.insert(db, onConflict: .ignore)
            try Self.insertMembers(db, deleted.members)
        }
    }

    /// Adds versions (and their pair partners) to an album. Returns the
    /// memberships that are new, for undo.
    @discardableResult
    public func addVersions(_ versionIDs: [Int64], toAlbum albumID: Int64) async throws -> [AlbumMemberRecord] {
        try await database.write { db in
            var position = try Int.fetchOne(db, AlbumMemberRecord
                .select(max(AlbumMemberRecord.Columns.position))
                .filter(AlbumMemberRecord.Columns.albumId == albumID)) ?? -1
            var added: [AlbumMemberRecord] = []
            for versionID in versionIDs + (try ImagePairing.partnerVersionIDs(db, of: versionIDs)) {
                let member = AlbumMemberRecord(albumId: albumID, versionId: versionID, position: position + 1)
                try member.insert(db, onConflict: .ignore)
                if db.changesCount > 0 {
                    position += 1
                    added.append(member)
                }
            }
            return added
        }
    }

    /// Takes versions (and their pair partners) out of an album; the photos stay
    /// in the library. Returns the memberships removed, for undo.
    @discardableResult
    public func removeVersions(_ versionIDs: [Int64], fromAlbum albumID: Int64) async throws -> [AlbumMemberRecord] {
        try await database.write { db in
            let targets = versionIDs + (try ImagePairing.partnerVersionIDs(db, of: versionIDs))
            var removed: [AlbumMemberRecord] = []
            for chunk in targets.chunked(into: 10_000) {
                let list = databaseQuestionMarks(count: chunk.count)
                var values: [(any DatabaseValueConvertible)?] = [albumID]
                values += chunk.map { $0 }
                removed += try AlbumMemberRecord.fetchAll(db, sql: """
                    SELECT * FROM albumMember WHERE albumId = ? AND versionId IN (\(list))
                    """, arguments: StatementArguments(values))
                try db.execute(sql: "DELETE FROM albumMember WHERE albumId = ? AND versionId IN (\(list))",
                               arguments: StatementArguments(values))
            }
            return removed
        }
    }

    public func insertAlbumMembers(_ members: [AlbumMemberRecord]) async throws {
        try await database.write { db in try Self.insertMembers(db, members) }
    }

    public func deleteAlbumMembers(_ members: [AlbumMemberRecord]) async throws {
        try await database.write { db in
            for member in members {
                try db.execute(sql: "DELETE FROM albumMember WHERE albumId = ? AND versionId = ?",
                               arguments: [member.albumId, member.versionId])
            }
        }
    }

    private static func insertMembers(_ db: Database, _ members: [AlbumMemberRecord]) throws {
        for member in members {
            try db.execute(sql: """
                INSERT OR IGNORE INTO albumMember (albumId, versionId, position)
                SELECT ?, ?, ? WHERE EXISTS (SELECT 1 FROM album WHERE id = ?)
                  AND EXISTS (SELECT 1 FROM version WHERE id = ?)
                """, arguments: [member.albumId, member.versionId, member.position, member.albumId, member.versionId])
        }
    }

    // MARK: Smart albums

    public func smartAlbums() async throws -> [SmartAlbum] {
        try await database.read { db in
            try SmartAlbumRecord.fetchAll(db, sql: "SELECT * FROM smartAlbum ORDER BY name COLLATE NOCASE, id")
                .map(SmartAlbum.init)
        }
    }

    public func createSmartAlbum(name: String, projectID: Int64?, rules: SmartAlbumRules,
                                 createdAt: Date = Date()) async throws -> SmartAlbum {
        let json = try rules.jsonString()
        return try await database.write { db in
            var record = SmartAlbumRecord(id: nil, uuid: UUID().uuidString, name: name, projectId: projectID,
                                          rules: json, createdAt: createdAt)
            try record.insert(db)
            return SmartAlbum(record)
        }
    }

    /// Saves a smart album's name, scope and rules (creating it again under its
    /// old id when it was deleted, as an undo of a deletion does).
    public func saveSmartAlbum(_ album: SmartAlbum) async throws {
        let saved = try album.record()
        try await database.write { db in
            var record = saved
            try record.upsert(db)
        }
    }

    public func deleteSmartAlbum(id: Int64) async throws -> SmartAlbum? {
        try await database.write { db in
            guard let record = try SmartAlbumRecord.fetchOne(db, key: id) else { return nil }
            try record.delete(db)
            return SmartAlbum(record)
        }
    }

    // MARK: Dates

    /// Months that have photos, newest first, by capture day.
    public func captureMonths(groupingPairs: Bool = true) async throws -> [CaptureMonth] {
        try await database.read { db in
            var counts: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT substr(image.localDate, 1, 7), COUNT(*) FROM version JOIN image ON image.id = version.imageId
                WHERE image.localDate IS NOT NULL GROUP BY 1
                """) {
                counts[row[0]] = row[1]
            }
            if groupingPairs {
                for row in try Row.fetchAll(db, sql: """
                    SELECT substr(image.localDate, 1, 7), COUNT(*) FROM imagePair
                    JOIN image ON image.id = imagePair.rawImageId
                    WHERE image.localDate IS NOT NULL GROUP BY 1
                    """) {
                    counts[row[0], default: 0] -= row[1]
                }
            }
            return counts.compactMap { key, count -> CaptureMonth? in
                let parts = key.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 2, count > 0 else { return nil }
                return CaptureMonth(year: parts[0], month: parts[1], count: count)
            }
            .sorted { ($0.year, $0.month) > ($1.year, $1.month) }
        }
    }
}
