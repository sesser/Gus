import Foundation
import GRDB

/// Named adjustments that can be applied to other photos. A preset carries
/// some groups of controls (all of them unless it was saved with fewer):
/// applying it replaces those groups and leaves the photo's others alone.
public struct AdjustmentPreset: Hashable, Sendable, Identifiable {
    public var id: Int64?
    public var uuid: String
    public var name: String
    /// The collection it is listed in; empty for none.
    public var collection: String
    /// The groups applying it replaces.
    public var groups: Set<Adjustments.Group>
    /// Values for `groups`; the other groups are at their defaults.
    public var adjustments: Adjustments

    public init(id: Int64? = nil, uuid: String = UUID().uuidString, name: String, collection: String = "",
                groups: Set<Adjustments.Group> = Set(Adjustments.Group.allCases), adjustments: Adjustments) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.collection = collection
        self.groups = groups
        self.adjustments = Adjustments.none.replacing(groups, from: adjustments)
    }

    public var includesEveryGroup: Bool { groups == Set(Adjustments.Group.allCases) }

    /// `target` with this preset's groups replaced (its unknown operations kept).
    public func applied(onto target: Adjustments) -> Adjustments {
        target.replacing(groups, from: adjustments)
    }

    /// Stored group names: nil for every group, so presets saved before a group
    /// existed keep replacing everything.
    static func encodeGroups(_ groups: Set<Adjustments.Group>) -> String? {
        guard groups != Set(Adjustments.Group.allCases) else { return nil }
        return groups.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// Names this build does not know are ignored.
    static func decodeGroups(_ text: String?) -> Set<Adjustments.Group> {
        guard let text else { return Set(Adjustments.Group.allCases) }
        return Set(text.split(separator: ",").compactMap { Adjustments.Group(rawValue: String($0)) })
    }
}

/// Presets listed by collection, for menus.
public struct AdjustmentPresetCollection: Hashable, Sendable, Identifiable {
    /// Empty for presets in no collection.
    public var name: String
    public var presets: [AdjustmentPreset]

    public var id: String { name }

    /// Presets in no collection first, then collections by name.
    public static func grouping(_ presets: [AdjustmentPreset]) -> [AdjustmentPresetCollection] {
        Dictionary(grouping: presets, by: \.collection)
            .map { AdjustmentPresetCollection(name: $0.key, presets: $0.value) }
            .sorted { a, b in
                if a.name.isEmpty != b.name.isEmpty { return a.name.isEmpty }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }
}

struct AdjustmentPresetRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "adjustmentPreset"

    var id: Int64?
    var uuid: String
    var name: String
    var collection: String
    /// Comma-separated `Adjustments.Group` names; nil for all of them.
    var groups: String?
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
    /// Every preset, by collection then name.
    public func adjustmentPresets() async throws -> [AdjustmentPreset] {
        try await database.read { db in
            try AdjustmentPresetRecord.fetchAll(
                db, sql: "SELECT * FROM adjustmentPreset ORDER BY collection COLLATE NOCASE, name COLLATE NOCASE")
                .compactMap { record in
                    guard let stack = try? EditStack.decode(from: record.settings) else { return nil }
                    return AdjustmentPreset(id: record.id, uuid: record.uuid, name: record.name,
                                            collection: record.collection,
                                            groups: AdjustmentPreset.decodeGroups(record.groups),
                                            adjustments: Adjustments(stack: stack))
                }
        }
    }

    /// Creates a preset, or replaces the one with the same name in its
    /// collection; returns it with its id.
    public func saveAdjustmentPreset(_ preset: AdjustmentPreset) async throws -> AdjustmentPreset {
        try await saveAdjustmentPresets([preset])[0]
    }

    /// Saves several presets in one transaction, each as `saveAdjustmentPreset` does.
    public func saveAdjustmentPresets(_ presets: [AdjustmentPreset]) async throws -> [AdjustmentPreset] {
        let prepared = try presets.map { preset -> (AdjustmentPreset, String) in
            var cleaned = preset
            cleaned.adjustments.preserved = []
            return (cleaned, try cleaned.adjustments.editStack.jsonString())
        }
        return try await database.write { db in
            try prepared.map { preset, settings in
                var record = AdjustmentPresetRecord(id: preset.id, uuid: preset.uuid, name: preset.name,
                                                    collection: preset.collection,
                                                    groups: AdjustmentPreset.encodeGroups(preset.groups),
                                                    settings: settings, createdAt: Date())
                if record.id == nil, let existing = try AdjustmentPresetRecord
                    .filter(Column("name") == preset.name && Column("collection") == preset.collection)
                    .fetchOne(db) {
                    record.id = existing.id
                    record.uuid = existing.uuid
                    record.createdAt = existing.createdAt
                }
                try record.save(db)
                var saved = preset
                saved.id = record.id
                saved.uuid = record.uuid
                return saved
            }
        }
    }

    public func deleteAdjustmentPreset(id: Int64) async throws {
        _ = try await database.write { db in try AdjustmentPresetRecord.deleteOne(db, key: id) }
    }

    /// Removes every preset of a collection.
    public func deleteAdjustmentPresets(inCollection collection: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM adjustmentPreset WHERE collection = ?", arguments: [collection])
        }
    }

    /// Renames a collection, merging it into one that already has the new name.
    public func renameAdjustmentPresetCollection(_ collection: String, to name: String) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE adjustmentPreset SET collection = ? WHERE collection = ?",
                           arguments: [name, collection])
        }
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
