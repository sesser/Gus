import Foundation
import GRDB

/// Rules of a version's edit history: one entry per saved change to its edit
/// stack, newest last in the table and first in what the loupe shows.
public enum EditHistory {
    /// Entries kept per version; adding one past this drops the oldest.
    public static let maxEntries = 100

    /// Stored (compressed) snapshot bytes kept per version, on top of the entry
    /// cap: 4 MiB. 100 typical stacks are under 100 KB, and 100 snapshots of a
    /// tidy 5,000-dab brush path about 1.8 MB, so ordinary work never meets it.
    /// Scribbled brush work of 50,000 dabs (about 380 KB a snapshot, measured)
    /// keeps about 10 entries instead of filling the catalog. The newest entry
    /// always stays, whatever its size.
    public static let maxBytes = 4 * 1024 * 1024

    /// A snapshot as stored: the stack's JSON, LZFSE compressed.
    static func compress(_ json: String) throws -> Data {
        try (Data(json.utf8) as NSData).compressed(using: .lzfse) as Data
    }

    static func decompress(_ data: Data) throws -> Data {
        try (data as NSData).decompressed(using: .lzfse) as Data
    }

    /// Labels for changes made outside the app, where nothing names an undo
    /// step. Plain English: `photocli` has no String Catalog.
    public static let developCommandLabel = "Develop (command line)"
    public static let maskCommandLabel = "Mask (command line)"
}

/// One row of a version's history, as the list shows it. The stack snapshot
/// stays in the catalog until a revert asks for it by `id`.
public struct EditHistoryEntry: Sendable, Equatable, Identifiable {
    public var id: Int64
    /// The undo action name of the change ("Exposure", "Undo Crop", …).
    public var label: String
    public var createdAt: Date

    public init(id: Int64, label: String, createdAt: Date) {
        self.id = id
        self.label = label
        self.createdAt = createdAt
    }
}

extension Catalog {
    /// A version's entries, newest first. Reads no stack snapshots, so the
    /// cost does not depend on how large the stacks are.
    public func editHistory(forVersion id: Int64) async throws -> [EditHistoryEntry] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, label, createdAt FROM editHistory WHERE versionId = ? ORDER BY id DESC",
                             arguments: [id]).map {
                EditHistoryEntry(id: $0["id"], label: $0["label"], createdAt: $0["createdAt"])
            }
        }
    }

    /// The stack `entryID` of `versionID` recorded, or nil when that entry is not
    /// (or no longer) there.
    public func editHistoryStack(entryID: Int64, forVersion versionID: Int64) async throws -> EditStack? {
        try await database.read { db in
            guard let stored = try Data.fetchOne(db, sql: "SELECT stack FROM editHistory WHERE id = ? AND versionId = ?",
                                                 arguments: [entryID, versionID]) else { return nil }
            return try EditStack.decode(from: EditHistory.decompress(stored))
        }
    }

    /// Adds an entry for `versionID` and trims the version's history, inside
    /// the caller's write so an entry is saved with its edit: to the newest
    /// `maxEntries`, then to `byteBudget` stored bytes, dropping the oldest. The
    /// entry just added is never trimmed.
    static func recordHistory(_ db: Database, versionID: Int64, label: String, stackJSON: String, at date: Date,
                              byteBudget: Int = EditHistory.maxBytes) throws {
        try db.execute(sql: "INSERT INTO editHistory (versionId, label, createdAt, stack) VALUES (?, ?, ?, ?)",
                       arguments: [versionID, label, date, try EditHistory.compress(stackJSON)])
        let rows = try Row.fetchAll(db, sql: "SELECT id, length(stack) FROM editHistory WHERE versionId = ? ORDER BY id DESC",
                                    arguments: [versionID])
        var total = 0
        var oldestKept: Int64?
        for (index, row) in rows.enumerated() {
            let size: Int = row[1]
            total += size
            guard index == 0 || (index < EditHistory.maxEntries && total <= byteBudget) else { break }
            oldestKept = row[0]
        }
        if let oldestKept {
            try db.execute(sql: "DELETE FROM editHistory WHERE versionId = ? AND id < ?", arguments: [versionID, oldestKept])
        }
    }
}

extension EditStack {
    /// Whether `other` holds the same operations with the same settings, in the
    /// same order. Operation ids are left out: building a stack from the same
    /// values mints new ones, and such a write changed nothing (R10).
    public func hasSameContent(as other: EditStack) -> Bool {
        guard operations.count == other.operations.count else { return false }
        return zip(operations, other.operations).allSatisfy { lhs, rhs in
            lhs.kind == rhs.kind && lhs.kindVersion == rhs.kindVersion && lhs.isEnabled == rhs.isEnabled
                && lhs.parameters == rhs.parameters
        }
    }
}
