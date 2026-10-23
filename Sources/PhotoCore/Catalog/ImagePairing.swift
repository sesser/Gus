import Foundation
import GRDB

/// RAW+JPEG pairs: a RAW master and a JPEG or HEIC master on the same volume,
/// in the same folder and project, with the same file name apart from the
/// extension (compared case-insensitively).
///
/// The two halves share culling values, keywords and albums. Every catalog
/// write on a pair's default version also goes to the partner's default
/// version, in the same transaction, so they cannot drift apart whether the
/// browser shows them grouped or separately.
///
/// The v2 migration calls `pairAll` and must keep working on a v2 schema, so
/// these queries only use tables and columns that exist as of v2.
enum ImagePairing {
    /// `relativePath` lowercased, without its extension.
    static func key(forRelativePath relativePath: String) -> String {
        (relativePath as NSString).deletingPathExtension.lowercased()
    }

    /// Number of pairs in each project, keyed by project id.
    static func pairCountsByProject(_ db: Database) throws -> [Int64: Int] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT image.projectId, COUNT(*) FROM imagePair
            JOIN image ON image.id = imagePair.rawImageId
            GROUP BY image.projectId
            """)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0[0] as Int64, $0[1] as Int) })
    }

    /// Pairs unpaired masters with the given keys in one project. Returns the
    /// companions of the pairs created.
    static func pair(_ db: Database, volumeID: Int64, projectID: Int64, keys: Set<String>) throws -> [Int64] {
        var created: [Int64] = []
        for chunk in Array(keys).chunked(into: 500) {
            let placeholders = databaseQuestionMarks(count: chunk.count)
            var values: [(any DatabaseValueConvertible)?] = [volumeID, projectID]
            values += chunk.map { $0 }
            let candidates = try Candidate.fetchAll(db, sql: """
                SELECT id, volumeId, projectId, pairingKey, relativePath FROM image
                WHERE volumeId = ? AND projectId = ? AND pairingKey IN (\(placeholders))
                  AND id NOT IN (SELECT rawImageId FROM imagePair)
                  AND id NOT IN (SELECT companionImageId FROM imagePair)
                ORDER BY id
                """, arguments: StatementArguments(values))
            created += try makePairs(db, from: candidates)
        }
        return created
    }

    /// Pairs every unpaired master in the catalog that has a partner.
    @discardableResult
    static func pairAll(_ db: Database) throws -> Int {
        let candidates = try Candidate.fetchAll(db, sql: """
            SELECT id, volumeId, projectId, pairingKey, relativePath FROM image
            WHERE pairingKey IS NOT NULL
              AND (volumeId, projectId, pairingKey) IN (
                  SELECT volumeId, projectId, pairingKey FROM image
                  WHERE pairingKey IS NOT NULL
                  GROUP BY volumeId, projectId, pairingKey HAVING COUNT(*) > 1)
              AND id NOT IN (SELECT rawImageId FROM imagePair)
              AND id NOT IN (SELECT companionImageId FROM imagePair)
            ORDER BY id
            """)
        return try makePairs(db, from: candidates).count
    }

    /// Default versions of the partners of `versionIDs` (default versions only),
    /// excluding versions already in `versionIDs`.
    static func partnerVersionIDs(_ db: Database, of versionIDs: [Int64]) throws -> [Int64] {
        guard !versionIDs.isEmpty, try ImagePairRecord.fetchCount(db) > 0 else { return [] }
        var partners: [Int64] = []
        for chunk in versionIDs.chunked(into: 10_000) {
            let placeholders = databaseQuestionMarks(count: chunk.count)
            let arguments = StatementArguments(Array(chunk) + Array(chunk))
            partners += try Int64.fetchAll(db, sql: """
                SELECT partner.id FROM version source
                JOIN imagePair ON imagePair.rawImageId = source.imageId
                JOIN version partner ON partner.imageId = imagePair.companionImageId AND partner.isDefault
                WHERE source.isDefault AND source.id IN (\(placeholders))
                UNION
                SELECT partner.id FROM version source
                JOIN imagePair ON imagePair.companionImageId = source.imageId
                JOIN version partner ON partner.imageId = imagePair.rawImageId AND partner.isDefault
                WHERE source.isDefault AND source.id IN (\(placeholders))
                """, arguments: arguments)
        }
        let given = Set(versionIDs)
        return partners.filter { !given.contains($0) }
    }

    // MARK: Forming pairs

    private struct Candidate: FetchableRecord, Decodable {
        var id: Int64
        var volumeId: Int64
        var projectId: Int64
        var pairingKey: String
        var relativePath: String

        var kind: FileKind? { FileKind(pathExtension: (relativePath as NSString).pathExtension) }
    }

    private struct GroupKey: Hashable {
        var volumeId: Int64
        var projectId: Int64
        var pairingKey: String
    }

    /// Candidates are in id order, so the earliest RAW pairs with the earliest JPEG
    /// (or HEIC when there is no JPEG).
    private static func makePairs(_ db: Database, from candidates: [Candidate]) throws -> [Int64] {
        let groups = Dictionary(grouping: candidates) {
            GroupKey(volumeId: $0.volumeId, projectId: $0.projectId, pairingKey: $0.pairingKey)
        }
        var created: [Int64] = []
        for members in groups.values where members.count > 1 {
            guard let raw = members.first(where: { $0.kind == .raw }),
                  let companion = members.first(where: { $0.kind == .jpeg }) ?? members.first(where: { $0.kind == .heic })
            else { continue }
            var pair = ImagePairRecord(id: nil, rawImageId: raw.id, companionImageId: companion.id, showsCompanion: false)
            try pair.insert(db)
            try mergeDefaultVersions(db, raw: raw.id, companion: companion.id)
            created.append(companion.id)
        }
        return created
    }

    /// Makes the two default versions agree: for each culling value the RAW's wins
    /// unless it is unset; keywords and album memberships are combined.
    private static func mergeDefaultVersions(_ db: Database, raw rawImageID: Int64, companion companionImageID: Int64) throws {
        func defaultVersion(_ imageID: Int64) throws -> VersionRecord? {
            try VersionRecord.filter(VersionRecord.Columns.imageId == imageID && Column("isDefault") == true).fetchOne(db)
        }
        guard let raw = try defaultVersion(rawImageID), let companion = try defaultVersion(companionImageID),
              let rawID = raw.id, let companionID = companion.id
        else { return }
        let rating = raw.rating != .unrated ? raw.rating : companion.rating
        let flag = raw.flag != .none ? raw.flag : companion.flag
        let label = raw.colorLabel != .none ? raw.colorLabel : companion.colorLabel
        for version in [raw, companion] where version.rating != rating || version.flag != flag || version.colorLabel != label {
            _ = try VersionRecord.filter(key: version.id).updateAll(db, [
                VersionRecord.Columns.rating.set(to: rating.databaseValue),
                VersionRecord.Columns.flag.set(to: flag.databaseValue),
                VersionRecord.Columns.colorLabel.set(to: label.databaseValue),
            ])
        }
        for (target, source) in [(rawID, companionID), (companionID, rawID)] {
            try db.execute(sql: """
                INSERT OR IGNORE INTO versionKeyword (versionId, keywordId)
                SELECT ?, keywordId FROM versionKeyword WHERE versionId = ?
                """, arguments: [target, source])
            try db.execute(sql: """
                INSERT OR IGNORE INTO albumMember (albumId, versionId, position)
                SELECT albumId, ?, position FROM albumMember WHERE versionId = ?
                """, arguments: [target, source])
        }
    }
}

extension Array {
    /// Consecutive slices of at most `size` elements, for statements that would
    /// otherwise exceed SQLite's limit on bound variables.
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
