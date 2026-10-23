import Foundation
import GRDB

/// A keyword with the number of photos that have it.
public struct KeywordSummary: Hashable, Sendable, Identifiable {
    public var keyword: KeywordRecord
    /// Versions with the keyword; with pairs grouped, a pair counts once.
    public var count: Int
    public var id: Int64 { keyword.id ?? 0 }
    public var name: String { keyword.name }
}

/// How many of a set of versions have a keyword (for the inspector).
public struct KeywordUsage: Hashable, Sendable, Identifiable {
    public var keyword: KeywordRecord
    public var count: Int
    public var id: Int64 { keyword.id ?? 0 }
}

/// A keyword removed from the catalog, with enough to put it back.
public struct DeletedKeyword: Hashable, Sendable {
    public var keyword: KeywordRecord
    public var versionIDs: [Int64]
}

/// The result of renaming a keyword onto the name of another one.
public struct KeywordMerge: Hashable, Sendable {
    /// The keyword that went away, with its former assignments.
    public var source: DeletedKeyword
    public var target: KeywordRecord
    /// Assignments of `target` that the merge added (versions that only had the source).
    public var addedToTarget: [VersionKeywordRecord]
}

/// What adding keywords changed: new assignments, and keywords that did not
/// exist before.
public struct KeywordAddition: Hashable, Sendable {
    public var assignments: [VersionKeywordRecord] = []
    public var createdKeywords: [KeywordRecord] = []
}

public enum KeywordRename: Hashable, Sendable {
    case renamed(from: String)
    case merged(KeywordMerge)
    case unchanged
}

/// Keywords are flat in phase 2: every keyword created here has no parent.
/// Names compare case-insensitively; the first spelling used is kept.
extension Catalog {
    /// Trims and collapses whitespace; nil when nothing is left.
    public static func normalizedKeywordName(_ name: String) -> String? {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let joined = words.joined(separator: " ")
        return joined.isEmpty ? nil : String(joined.prefix(200))
    }

    /// Every keyword with its photo count, alphabetically.
    public func keywordSummaries(groupingPairs: Bool = true) async throws -> [KeywordSummary] {
        try await database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT keyword.*, COUNT(versionKeyword.versionId) AS usage
                FROM keyword
                LEFT JOIN versionKeyword ON versionKeyword.keywordId = keyword.id
                GROUP BY keyword.id
                ORDER BY keyword.name COLLATE NOCASE
                """)
            // Pair halves share keywords; the hidden half is not counted.
            var hidden: [Int64: Int] = [:]
            if groupingPairs {
                for row in try Row.fetchAll(db, sql: """
                    SELECT versionKeyword.keywordId, COUNT(*) FROM imagePair
                    JOIN version ON version.isDefault AND version.imageId =
                        CASE WHEN imagePair.showsCompanion THEN imagePair.rawImageId ELSE imagePair.companionImageId END
                    JOIN versionKeyword ON versionKeyword.versionId = version.id
                    GROUP BY versionKeyword.keywordId
                    """) {
                    hidden[row[0]] = row[1]
                }
            }
            return try rows.map { row in
                let keyword = try KeywordRecord(row: row)
                let usage: Int = row["usage"]
                return KeywordSummary(keyword: keyword, count: usage - (hidden[keyword.id ?? 0] ?? 0))
            }
        }
    }

    /// Keywords used by any of `versionIDs`, with how many of them use each.
    public func keywordUsage(forVersions versionIDs: [Int64]) async throws -> [KeywordUsage] {
        guard !versionIDs.isEmpty else { return [] }
        return try await database.read { db in
            var counts: [Int64: Int] = [:]
            for chunk in versionIDs.chunked(into: 10_000) {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT keywordId, COUNT(*) FROM versionKeyword
                    WHERE versionId IN (\(databaseQuestionMarks(count: chunk.count)))
                    GROUP BY keywordId
                    """, arguments: StatementArguments(Array(chunk)))
                for row in rows { counts[row[0], default: 0] += row[1] }
            }
            let keywords = try KeywordRecord.fetchAll(db, keys: Array(counts.keys))
            return keywords
                .map { KeywordUsage(keyword: $0, count: counts[$0.id ?? 0] ?? 0) }
                .sorted { $0.keyword.name.localizedCaseInsensitiveCompare($1.keyword.name) == .orderedAscending }
        }
    }

    /// Adds keywords (created when new) to the versions and their pair partners.
    /// Returns exactly what changed, for undo.
    @discardableResult
    public func addKeywords(named names: [String], toVersions versionIDs: [Int64]) async throws -> KeywordAddition {
        let names = names.compactMap(Self.normalizedKeywordName)
        guard !names.isEmpty, !versionIDs.isEmpty else { return KeywordAddition() }
        return try await database.write { db in
            let targets = versionIDs + (try ImagePairing.partnerVersionIDs(db, of: versionIDs))
            var addition = KeywordAddition()
            for name in names {
                let existing = try Self.existingKeyword(db, name: name)
                let keyword = try existing ?? Self.findOrCreateKeyword(db, name: name)
                guard let keywordID = keyword.id else { continue }
                if existing == nil { addition.createdKeywords.append(keyword) }
                for versionID in targets {
                    let assignment = VersionKeywordRecord(versionId: versionID, keywordId: keywordID)
                    try assignment.insert(db, onConflict: .ignore)
                    if db.changesCount > 0 { addition.assignments.append(assignment) }
                }
            }
            return addition
        }
    }

    /// Reverses `addKeywords`: removes its assignments, and the keywords it
    /// created unless something else uses them by now.
    public func undoKeywordAddition(_ addition: KeywordAddition) async throws {
        try await deleteKeywordAssignments(addition.assignments)
        try await database.write { db in
            for keyword in addition.createdKeywords {
                try db.execute(sql: """
                    DELETE FROM keyword WHERE id = ?
                      AND NOT EXISTS (SELECT 1 FROM versionKeyword WHERE keywordId = ?)
                    """, arguments: [keyword.id, keyword.id])
            }
        }
    }

    /// Repeats an addition that `undoKeywordAddition` reversed, keeping keyword ids.
    public func redoKeywordAddition(_ addition: KeywordAddition) async throws {
        try await database.write { db in
            for var keyword in addition.createdKeywords {
                try keyword.insert(db, onConflict: .ignore)
            }
        }
        try await insertKeywordAssignments(addition.assignments)
    }

    /// Removes keywords from the versions and their pair partners. Returns the
    /// assignments that were removed, for undo.
    @discardableResult
    public func removeKeywords(_ keywordIDs: [Int64], fromVersions versionIDs: [Int64]) async throws -> [VersionKeywordRecord] {
        guard !keywordIDs.isEmpty, !versionIDs.isEmpty else { return [] }
        return try await database.write { db in
            let targets = versionIDs + (try ImagePairing.partnerVersionIDs(db, of: versionIDs))
            var removed: [VersionKeywordRecord] = []
            for keywordID in keywordIDs {
                for chunk in targets.chunked(into: 10_000) {
                    let existing = try Int64.fetchAll(db, sql: """
                        SELECT versionId FROM versionKeyword
                        WHERE keywordId = ? AND versionId IN (\(databaseQuestionMarks(count: chunk.count)))
                        """, arguments: StatementArguments([keywordID] + Array(chunk)))
                    try db.execute(sql: """
                        DELETE FROM versionKeyword
                        WHERE keywordId = ? AND versionId IN (\(databaseQuestionMarks(count: chunk.count)))
                        """, arguments: StatementArguments([keywordID] + Array(chunk)))
                    removed += existing.map { VersionKeywordRecord(versionId: $0, keywordId: keywordID) }
                }
            }
            return removed
        }
    }

    /// Restores assignments returned by `removeKeywords` (or re-applies ones from
    /// `addKeywords`). Assignments whose keyword or version is gone are skipped.
    public func insertKeywordAssignments(_ assignments: [VersionKeywordRecord]) async throws {
        guard !assignments.isEmpty else { return }
        try await database.write { db in
            for assignment in assignments {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO versionKeyword (versionId, keywordId)
                    SELECT ?, ? WHERE EXISTS (SELECT 1 FROM keyword WHERE id = ?)
                      AND EXISTS (SELECT 1 FROM version WHERE id = ?)
                    """, arguments: [assignment.versionId, assignment.keywordId, assignment.keywordId, assignment.versionId])
            }
        }
    }

    public func deleteKeywordAssignments(_ assignments: [VersionKeywordRecord]) async throws {
        guard !assignments.isEmpty else { return }
        try await database.write { db in
            for assignment in assignments {
                try db.execute(sql: "DELETE FROM versionKeyword WHERE versionId = ? AND keywordId = ?",
                               arguments: [assignment.versionId, assignment.keywordId])
            }
        }
    }

    /// Renames a keyword. Renaming onto another keyword's name (ignoring case)
    /// merges the two: the other keyword stays and gains this one's photos.
    public func renameKeyword(id: Int64, to newName: String) async throws -> KeywordRename {
        guard let name = Self.normalizedKeywordName(newName) else { return .unchanged }
        return try await database.write { db in
            guard var keyword = try KeywordRecord.fetchOne(db, key: id) else { return .unchanged }
            if keyword.name == name { return .unchanged }
            if let target = try Self.existingKeyword(db, name: name), target.id != id, let targetID = target.id {
                let versionIDs = try Self.versionIDs(db, keywordID: id)
                var added: [VersionKeywordRecord] = []
                for versionID in versionIDs {
                    let assignment = VersionKeywordRecord(versionId: versionID, keywordId: targetID)
                    try assignment.insert(db, onConflict: .ignore)
                    if db.changesCount > 0 { added.append(assignment) }
                }
                try keyword.delete(db)
                return .merged(KeywordMerge(source: DeletedKeyword(keyword: keyword, versionIDs: versionIDs),
                                            target: target, addedToTarget: added))
            }
            let previous = keyword.name
            keyword.name = name
            try keyword.update(db)
            return .renamed(from: previous)
        }
    }

    /// Undoes a merge: the source keyword comes back with its photos, and the
    /// target loses the photos the merge gave it.
    public func undoKeywordMerge(_ merge: KeywordMerge) async throws {
        try await deleteKeywordAssignments(merge.addedToTarget)
        try await restoreKeyword(merge.source)
    }

    /// Deletes a keyword and its assignments; photos are not affected otherwise.
    public func deleteKeyword(id: Int64) async throws -> DeletedKeyword? {
        try await database.write { db in
            guard let keyword = try KeywordRecord.fetchOne(db, key: id) else { return nil }
            let versionIDs = try Self.versionIDs(db, keywordID: id)
            try keyword.delete(db)
            return DeletedKeyword(keyword: keyword, versionIDs: versionIDs)
        }
    }

    /// Puts back a deleted keyword under its old id, with its assignments.
    public func restoreKeyword(_ deleted: DeletedKeyword) async throws {
        try await database.write { db in
            var keyword = deleted.keyword
            try keyword.insert(db, onConflict: .ignore)
            guard let keywordID = keyword.id else { return }
            for versionID in deleted.versionIDs {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO versionKeyword (versionId, keywordId)
                    SELECT ?, ? WHERE EXISTS (SELECT 1 FROM version WHERE id = ?)
                    """, arguments: [versionID, keywordID, versionID])
            }
        }
    }

    // MARK: Helpers

    static func existingKeyword(_ db: Database, name: String) throws -> KeywordRecord? {
        try KeywordRecord.fetchOne(db, sql: "SELECT * FROM keyword WHERE parentId IS NULL AND name = ? COLLATE NOCASE",
                                   arguments: [name])
    }

    static func findOrCreateKeyword(_ db: Database, name: String) throws -> KeywordRecord {
        if let existing = try existingKeyword(db, name: name) { return existing }
        var keyword = KeywordRecord(id: nil, name: name, parentId: nil)
        try keyword.insert(db)
        return keyword
    }

    private static func versionIDs(_ db: Database, keywordID: Int64) throws -> [Int64] {
        try Int64.fetchAll(db, sql: "SELECT versionId FROM versionKeyword WHERE keywordId = ? ORDER BY versionId",
                           arguments: [keywordID])
    }
}
