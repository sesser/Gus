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

    /// - Parameter keepingStoredDecode: Keep `adjustments`' stored decode (a
    ///   Look or decoder an older build's Profile group saved), as a preset read
    ///   from the catalog or a preset file does: it stays in the preset's stored
    ///   data and applies nothing, except a legacy machine learning decoder,
    ///   which still turns machine learning on (`Adjustments.replacing`; issue
    ///   #219, R6). A new preset never carries one.
    public init(id: Int64? = nil, uuid: String = UUID().uuidString, name: String, collection: String = "",
                groups: Set<Adjustments.Group> = Set(Adjustments.Group.presetGroups), adjustments: Adjustments,
                keepingStoredDecode: Bool = false) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.collection = collection
        self.groups = groups.subtracting([.spots])
        let values = Adjustments.none.copying(groups, from: adjustments)
        self.adjustments = keepingStoredDecode ? values.keepingDecode(of: adjustments) : values
    }

    public var includesEveryGroup: Bool { groups == Set(Adjustments.Group.presetGroups) }

    /// `target` with this preset's groups replaced (its unknown operations kept).
    public func applied(onto target: Adjustments) -> Adjustments {
        target.replacing(groups, from: adjustments)
    }

    /// Stored group names: nil for every group, so presets saved before a group
    /// existed keep replacing everything.
    static func encodeGroups(_ groups: Set<Adjustments.Group>) -> String? {
        guard groups != Set(Adjustments.Group.presetGroups) else { return nil }
        return groups.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// Names this build does not know are ignored.
    static func decodeGroups(_ text: String?) -> Set<Adjustments.Group> {
        guard let text else { return Set(Adjustments.Group.presetGroups) }
        return Set(text.split(separator: ",").compactMap { Adjustments.Group(rawValue: String($0)) }).subtracting([.spots])
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
    /// These adjustments applied over `target`'s as Copy Adjustments with
    /// every item but Spots checked would (`CopiedAdjustments`): every group
    /// and the crop replaced; the target's masks, spots, stored decode and
    /// operations this build does not understand kept.
    public func pasted(onto target: Adjustments) -> Adjustments {
        CopiedAdjustments(self, items: Set(CopyItem.all).subtracting([.group(.spots)])).pasted(onto: target)
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
                                            adjustments: Adjustments(presetStack: stack), keepingStoredDecode: true)
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
    /// stacks before and after, for undo, and the versions left alone. Each
    /// version the change alters gets one history entry named `historyLabel`.
    public func changeEditStacks(ofVersions ids: [Int64], historyLabel: String,
                                 _ transform: (Adjustments) -> Adjustments) async throws -> EditStackChange {
        try await changeEditStacks(ofVersions: ids, historyLabel: historyLabel) { _, values in transform(values) }
    }

    /// As above, with each version's id, for changes that differ per photo
    /// (a measured exposure, a raw's camera frame).
    public func changeEditStacks(ofVersions ids: [Int64], historyLabel: String,
                                 _ transform: (Int64, Adjustments) -> Adjustments) async throws -> EditStackChange {
        let stored = try await editStacks(forVersions: ids)
        var after: [Int64: EditStack] = [:]
        for (id, stack) in stored.stacks {
            after[id] = transform(id, Adjustments(stack: stack)).editStack
        }
        try await setEditStacks(after, historyLabel: historyLabel)
        return EditStackChange(before: stored.stacks, after: after, unreadable: stored.unreadable)
    }

    /// Replaces several versions' edit stacks in one transaction, with one
    /// history entry named `historyLabel` for each whose stack changed. Throws
    /// `UnreadableEditStacks`, writing nothing, when any stored stack among
    /// them cannot be read.
    public func setEditStacks(_ stacks: [Int64: EditStack], historyLabel: String,
                              at date: Date = Date()) async throws {
        try await setEditStacks(stacks, historyLabel: historyLabel, at: date, byteBudget: EditHistory.maxBytes)
    }

    /// As above, with the history's byte budget (tests use a small one), and
    /// stored detection results the stacks name, written in the same
    /// transaction (`photocli mask add`).
    func setEditStacks(_ stacks: [Int64: EditStack], historyLabel: String, at date: Date, byteBudget: Int,
                       storing rasters: [MaskRaster] = []) async throws {
        let rows = try stacks.map { ($0.key, $0.value, try $0.value.jsonString(), $0.value.renderHash) }
        try await database.write { db in
            for raster in rasters { try Self.insertMaskRaster(db, raster, at: date) }
            var previous: [Int64: EditStack] = [:]
            var failures: [Int64: EditStack.ReadFailure] = [:]
            for chunk in Array(stacks.keys).chunked(into: 10_000) {
                for version in try VersionRecord.filter(keys: chunk).fetchAll(db) {
                    guard let id = version.id else { continue }
                    do { previous[id] = try version.decodedEditStack() } catch { failures[id] = EditStack.ReadFailure(error) }
                }
            }
            if !failures.isEmpty { throw UnreadableEditStacks(failures: failures) }
            for (id, stack, json, hash) in rows {
                _ = try VersionRecord.filter(key: id).updateAll(db, [
                    VersionRecord.Columns.editStack.set(to: json),
                    VersionRecord.Columns.editStackHash.set(to: hash),
                    VersionRecord.Columns.hdr.set(to: stack.hdrChoice),
                    VersionRecord.Columns.modifiedAt.set(to: date),
                ])
                // A change that leaves the stack as it was has nothing to record (R10).
                if let before = previous[id], !before.hasSameContent(as: stack) {
                    try Self.recordHistory(db, versionID: id, label: historyLabel, stackJSON: json, at: date,
                                           byteBudget: byteBudget)
                }
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
