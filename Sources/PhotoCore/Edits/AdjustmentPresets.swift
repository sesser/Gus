import Foundation
import GRDB

/// Named adjustments that can be applied to other photos.
public struct AdjustmentPreset: Hashable, Sendable, Identifiable {
    public var id: Int64?
    public var uuid: String
    public var name: String
    public var adjustments: Adjustments

    public init(id: Int64? = nil, uuid: String = UUID().uuidString, name: String, adjustments: Adjustments) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.adjustments = adjustments
    }
}

struct AdjustmentPresetRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "adjustmentPreset"

    var id: Int64?
    var uuid: String
    var name: String
    /// Edit stack JSON, without operations this build does not know.
    var settings: String
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension Adjustments {
    /// These adjustments applied over `target`'s: everything is replaced except
    /// the target's operations this build does not understand.
    public func pasted(onto target: Adjustments) -> Adjustments {
        var result = self
        result.preserved = target.preserved
        return result
    }
}

extension Catalog {
    public func adjustmentPresets() async throws -> [AdjustmentPreset] {
        try await database.read { db in
            try AdjustmentPresetRecord.fetchAll(db, sql: "SELECT * FROM adjustmentPreset ORDER BY name COLLATE NOCASE")
                .compactMap { record in
                    guard let stack = try? EditStack.decode(from: record.settings) else { return nil }
                    return AdjustmentPreset(id: record.id, uuid: record.uuid, name: record.name,
                                            adjustments: Adjustments(stack: stack))
                }
        }
    }

    /// Creates a preset, or replaces the one with the same name; returns it with its id.
    public func saveAdjustmentPreset(_ preset: AdjustmentPreset) async throws -> AdjustmentPreset {
        var cleaned = preset.adjustments
        cleaned.preserved = []
        let stored = cleaned
        let settings = try stored.editStack.jsonString()
        return try await database.write { db in
            var record = AdjustmentPresetRecord(id: preset.id, uuid: preset.uuid, name: preset.name,
                                                settings: settings, createdAt: Date())
            if record.id == nil, let existing = try AdjustmentPresetRecord
                .filter(Column("name") == preset.name).fetchOne(db) {
                record.id = existing.id
                record.uuid = existing.uuid
            }
            try record.save(db)
            var saved = preset
            saved.id = record.id
            saved.uuid = record.uuid
            saved.adjustments = stored
            return saved
        }
    }

    public func deleteAdjustmentPreset(id: Int64) async throws {
        _ = try await database.write { db in try AdjustmentPresetRecord.deleteOne(db, key: id) }
    }

    /// The edit stacks of several versions (identity for unreadable ones).
    public func editStacks(forVersions ids: [Int64]) async throws -> [Int64: EditStack] {
        try await database.read { db in
            var stacks: [Int64: EditStack] = [:]
            for chunk in ids.chunked(into: 10_000) {
                for version in try VersionRecord.filter(keys: chunk).fetchAll(db) {
                    guard let id = version.id else { continue }
                    stacks[id] = (try? version.decodedEditStack()) ?? .identity
                }
            }
            return stacks
        }
    }

    /// Replaces several versions' edit stacks in one transaction.
    public func setEditStacks(_ stacks: [Int64: EditStack], at date: Date = Date()) async throws {
        let rows = try stacks.map { ($0.key, try $0.value.jsonString(), $0.value.renderHash) }
        try await database.write { db in
            for (id, json, hash) in rows {
                _ = try VersionRecord.filter(key: id).updateAll(db, [
                    VersionRecord.Columns.editStack.set(to: json),
                    VersionRecord.Columns.editStackHash.set(to: hash),
                    VersionRecord.Columns.modifiedAt.set(to: date),
                ])
            }
        }
    }
}
