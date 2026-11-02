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
    /// the target's masks and its operations this build does not understand.
    public func pasted(onto target: Adjustments) -> Adjustments {
        var result = self
        result.preserved = target.preserved
        // Masks are drawn on one photo's content: paste leaves the target's.
        result.local = target.local
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

    /// The edit stacks of several versions, and the versions whose stacks
    /// cannot be read (which must be left alone).
    public func editStacks(forVersions ids: [Int64]) async throws -> StoredEditStacks {
        try await database.read { db in
            var stored = StoredEditStacks()
            for chunk in ids.chunked(into: 10_000) {
                for version in try VersionRecord.filter(keys: chunk).fetchAll(db) {
                    guard let id = version.id else { continue }
                    do {
                        stored.stacks[id] = try version.decodedEditStack()
                    } catch {
                        stored.unreadable[id] = EditStack.ReadFailure(error)
                    }
                }
            }
            return stored
        }
    }

    /// Gives each of `ids` `transform` of its adjustments (paste, a preset),
    /// leaving versions whose stacks cannot be read as they are. Returns the
    /// stacks before and after, for undo, and the versions left alone.
    public func changeEditStacks(ofVersions ids: [Int64],
                                 _ transform: (Adjustments) -> Adjustments) async throws -> EditStackChange {
        let stored = try await editStacks(forVersions: ids)
        let after = stored.stacks.mapValues { transform(Adjustments(stack: $0)).editStack }
        try await setEditStacks(after)
        return EditStackChange(before: stored.stacks, after: after, unreadable: stored.unreadable)
    }

    /// Replaces several versions' edit stacks in one transaction. Throws
    /// `UnreadableEditStacks`, writing nothing, when any stored stack among them
    /// cannot be read.
    public func setEditStacks(_ stacks: [Int64: EditStack], at date: Date = Date()) async throws {
        let rows = try stacks.map { ($0.key, try $0.value.jsonString(), $0.value.renderHash) }
        try await database.write { db in
            try Self.refuseUnreadableStacks(of: Array(stacks.keys), db)
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

/// Edit stacks read for a change to many versions.
public struct StoredEditStacks: Sendable, Equatable {
    public var stacks: [Int64: EditStack] = [:]
    /// Versions whose stored stack cannot be read, and why: never written over.
    public var unreadable: [Int64: EditStack.ReadFailure] = [:]

    public init(stacks: [Int64: EditStack] = [:], unreadable: [Int64: EditStack.ReadFailure] = [:]) {
        self.stacks = stacks
        self.unreadable = unreadable
    }
}

/// What `changeEditStacks` did.
public struct EditStackChange: Sendable, Equatable {
    public var before: [Int64: EditStack]
    public var after: [Int64: EditStack]
    /// Left unchanged: their stored stacks cannot be read.
    public var unreadable: [Int64: EditStack.ReadFailure]
}

/// A write would have replaced edit stacks this build cannot read (written by
/// a newer build, or damaged). Nothing was written.
public struct UnreadableEditStacks: Error, Equatable, Sendable {
    public var failures: [Int64: EditStack.ReadFailure]
}
