import Foundation
import GRDB

/// A suggested keyword across a set of versions (for the inspector).
public struct SuggestionUsage: Hashable, Sendable, Identifiable {
    public var name: String
    /// Versions the suggestion applies to and that do not have the keyword yet.
    public var count: Int
    public var confidence: Double
    public var id: String { name }
}

/// Suggestions for a set of versions, plus how many of them were never analyzed.
public struct SuggestionSummary: Hashable, Sendable {
    public var suggestions: [SuggestionUsage] = []
    public var unanalyzedCount = 0

    public init() {}
}

/// What accepting a suggestion changed, for undo.
public struct SuggestionAcceptance: Hashable, Sendable {
    public var addition: KeywordAddition
    public var imageIDs: [Int64]
}

enum SuggestionState: Int {
    case open = 0
    case accepted = 1
    case dismissed = 2
}

/// Suggestions belong to the master that was analyzed. A RAW+JPEG pair is
/// analyzed once, through its JPEG or HEIC (quicker to decode, same picture),
/// and both halves see the result.
extension Catalog {
    /// Default-version items of the masters to analyze for `versionIDs`, skipping
    /// masters already analyzed with `analysisVersion` or later.
    public func analysisTargets(forVersions versionIDs: [Int64], analysisVersion: Int) async throws -> [CatalogItem] {
        let targetVersions: [Int64] = try await database.read { db in
            let images = try Self.analysisImages(db, forVersions: versionIDs)
            var result: [Int64] = []
            for chunk in Array(Set(images.values)).chunked(into: 10_000) {
                result += try Int64.fetchAll(db, sql: """
                    SELECT version.id FROM version JOIN image ON image.id = version.imageId
                    WHERE version.isDefault AND image.id IN (\(databaseQuestionMarks(count: chunk.count)))
                      AND (image.analysisVersion IS NULL OR image.analysisVersion < ?)
                    """, arguments: StatementArguments(Array(chunk) + [Int64(analysisVersion)]))
            }
            return result
        }
        return try await libraryItems(versionIDs: targetVersions)
    }

    /// Replaces the open suggestions of a master with a new analysis. Keywords
    /// accepted or dismissed before are not offered again.
    public func storeSuggestions(_ suggestions: [SuggestedKeyword], forImage imageID: Int64,
                                 analysisVersion: Int) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM keywordSuggestion WHERE imageId = ? AND state = ?",
                           arguments: [imageID, SuggestionState.open.rawValue])
            for suggestion in suggestions {
                guard let name = Self.normalizedKeywordName(suggestion.name) else { continue }
                try db.execute(sql: """
                    INSERT OR IGNORE INTO keywordSuggestion (imageId, name, confidence, state) VALUES (?, ?, ?, ?)
                    """, arguments: [imageID, name, suggestion.confidence, SuggestionState.open.rawValue])
            }
            try db.execute(sql: "UPDATE image SET analysisVersion = ? WHERE id = ?", arguments: [analysisVersion, imageID])
        }
    }

    /// Open suggestions for the versions, leaving out keywords a version already has.
    public func suggestionSummary(forVersions versionIDs: [Int64]) async throws -> SuggestionSummary {
        guard !versionIDs.isEmpty else { return SuggestionSummary() }
        return try await database.read { db in
            let images = try Self.analysisImages(db, forVersions: versionIDs)
            var summary = SuggestionSummary()
            var usage: [String: SuggestionUsage] = [:]
            let suggestionsByImage = try Self.openSuggestions(db, images: Array(Set(images.values)))
            let keywordsByVersion = try Self.keywordNames(db, versions: versionIDs)
            let analyzed = try Self.analyzedImages(db, images: Array(Set(images.values)))
            for versionID in versionIDs {
                guard let imageID = images[versionID] else { continue }
                if !analyzed.contains(imageID) { summary.unanalyzedCount += 1 }
                let has = keywordsByVersion[versionID] ?? []
                for (name, confidence) in suggestionsByImage[imageID] ?? [] where !has.contains(name.lowercased()) {
                    var entry = usage[name] ?? SuggestionUsage(name: name, count: 0, confidence: 0)
                    entry.count += 1
                    entry.confidence = max(entry.confidence, confidence)
                    usage[name] = entry
                }
            }
            summary.suggestions = usage.values.sorted {
                ($0.count, $0.confidence) > ($1.count, $1.confidence)
            }
            return summary
        }
    }

    /// Adds the suggested keyword to those of `versionIDs` it was suggested for,
    /// and marks it accepted there.
    public func acceptSuggestion(_ name: String, forVersions versionIDs: [Int64]) async throws -> SuggestionAcceptance {
        try await database.write { db in
            let (versions, images) = try Self.versionsWithOpenSuggestion(db, name: name, among: versionIDs)
            let addition = try Self.addKeywords(db, names: [name], toVersions: versions)
            try Self.setSuggestionState(db, .accepted, name: name, images: images)
            return SuggestionAcceptance(addition: addition, imageIDs: images)
        }
    }

    /// Hides the suggestion for those of `versionIDs` it was suggested for.
    /// Returns the masters affected, for undo.
    public func dismissSuggestion(_ name: String, forVersions versionIDs: [Int64]) async throws -> [Int64] {
        try await database.write { db in
            let (_, images) = try Self.versionsWithOpenSuggestion(db, name: name, among: versionIDs)
            try Self.setSuggestionState(db, .dismissed, name: name, images: images)
            return images
        }
    }

    /// Offers a suggestion again (undo of accept or dismiss).
    public func reopenSuggestion(_ name: String, images: [Int64]) async throws {
        try await database.write { db in try Self.setSuggestionState(db, .open, name: name, images: images) }
    }

    public func undoSuggestionAcceptance(_ acceptance: SuggestionAcceptance, name: String) async throws {
        try await undoKeywordAddition(acceptance.addition)
        try await reopenSuggestion(name, images: acceptance.imageIDs)
    }

    public func redoSuggestionAcceptance(_ acceptance: SuggestionAcceptance, name: String) async throws {
        try await redoKeywordAddition(acceptance.addition)
        try await database.write { db in
            try Self.setSuggestionState(db, .accepted, name: name, images: acceptance.imageIDs)
        }
    }

    // MARK: Helpers

    /// The master each version's suggestions come from: its own, or for the RAW
    /// half of a pair, the companion's.
    static func analysisImages(_ db: Database, forVersions versionIDs: [Int64]) throws -> [Int64: Int64] {
        var result: [Int64: Int64] = [:]
        for chunk in versionIDs.chunked(into: 10_000) {
            let rows = try Row.fetchCursor(db, sql: """
                SELECT version.id, coalesce(imagePair.companionImageId, version.imageId)
                FROM version
                LEFT JOIN imagePair ON imagePair.rawImageId = version.imageId AND version.isDefault
                WHERE version.id IN (\(databaseQuestionMarks(count: chunk.count)))
                """, arguments: StatementArguments(Array(chunk)))
            while let row = try rows.next() { result[row[0]] = row[1] }
        }
        return result
    }

    private static func openSuggestions(_ db: Database, images: [Int64]) throws -> [Int64: [(String, Double)]] {
        var result: [Int64: [(String, Double)]] = [:]
        for chunk in images.chunked(into: 10_000) {
            let rows = try Row.fetchCursor(db, sql: """
                SELECT imageId, name, confidence FROM keywordSuggestion
                WHERE state = 0 AND imageId IN (\(databaseQuestionMarks(count: chunk.count)))
                """, arguments: StatementArguments(Array(chunk)))
            while let row = try rows.next() { result[row[0], default: []].append((row[1], row[2])) }
        }
        return result
    }

    private static func analyzedImages(_ db: Database, images: [Int64]) throws -> Set<Int64> {
        var result: Set<Int64> = []
        for chunk in images.chunked(into: 10_000) {
            result.formUnion(try Int64.fetchAll(db, sql: """
                SELECT id FROM image WHERE analysisVersion IS NOT NULL AND id IN (\(databaseQuestionMarks(count: chunk.count)))
                """, arguments: StatementArguments(Array(chunk))))
        }
        return result
    }

    /// Lowercased keyword names per version.
    private static func keywordNames(_ db: Database, versions: [Int64]) throws -> [Int64: Set<String>] {
        var result: [Int64: Set<String>] = [:]
        for chunk in versions.chunked(into: 10_000) {
            let rows = try Row.fetchCursor(db, sql: """
                SELECT versionKeyword.versionId, keyword.name FROM versionKeyword
                JOIN keyword ON keyword.id = versionKeyword.keywordId
                WHERE versionKeyword.versionId IN (\(databaseQuestionMarks(count: chunk.count)))
                """, arguments: StatementArguments(Array(chunk)))
            while let row = try rows.next() {
                let name: String = row[1]
                result[row[0], default: []].insert(name.lowercased())
            }
        }
        return result
    }

    private static func versionsWithOpenSuggestion(_ db: Database, name: String,
                                                   among versionIDs: [Int64]) throws -> (versions: [Int64], images: [Int64]) {
        let images = try analysisImages(db, forVersions: versionIDs)
        let suggested = Set(try openSuggestions(db, images: Array(Set(images.values)))
            .filter { $0.value.contains { $0.0 == name } }.keys)
        let versions = versionIDs.filter { images[$0].map(suggested.contains) ?? false }
        return (versions, Array(suggested))
    }

    private static func setSuggestionState(_ db: Database, _ state: SuggestionState, name: String, images: [Int64]) throws {
        for chunk in images.chunked(into: 10_000) {
            try db.execute(sql: """
                UPDATE keywordSuggestion SET state = ?
                WHERE name = ? AND imageId IN (\(databaseQuestionMarks(count: chunk.count)))
                """, arguments: StatementArguments([state.rawValue as (any DatabaseValueConvertible)?, name]
                                                    + Array(chunk).map { $0 }))
        }
    }
}
