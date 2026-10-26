import Foundation
import GRDB

/// Named metadata applied to every photo of an import: creator, copyright,
/// usage terms, contact. Text may use template tokens ("© {capture:yyyy} Pat").
public struct MetadataPreset: Codable, Hashable, Sendable, Identifiable {
    public var id: Int64?
    public var uuid: String
    public var name: String
    public var values: SidecarValues

    public init(id: Int64? = nil, uuid: String = UUID().uuidString, name: String, values: SidecarValues) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.values = values
    }
}

/// Where metadata presets are kept: the catalog, or the preferences of an app
/// that imports without one.
public protocol MetadataPresetStore: Sendable {
    func metadataPresets() async throws -> [MetadataPreset]
    /// Creates or updates a preset; returns it with its id.
    func saveMetadataPreset(_ preset: MetadataPreset) async throws -> MetadataPreset
    func deleteMetadataPreset(id: Int64) async throws
}

extension Catalog: MetadataPresetStore {}

/// Presets kept as JSON in user defaults, for importing without a catalog.
public struct DefaultsMetadataPresetStore: MetadataPresetStore {
    public var suiteName: String?
    public var key: String

    /// `suiteName` nil: the app's standard defaults.
    public init(suiteName: String? = nil, key: String = "import.metadataPresets") {
        self.suiteName = suiteName
        self.key = key
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    public func metadataPresets() async throws -> [MetadataPreset] {
        load().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func saveMetadataPreset(_ preset: MetadataPreset) async throws -> MetadataPreset {
        var presets = load()
        var saved = preset
        if let index = presets.firstIndex(where: { $0.id != nil && $0.id == preset.id }) {
            presets[index] = saved
        } else {
            saved.id = (presets.compactMap(\.id).max() ?? 0) + 1
            presets.append(saved)
        }
        defaults.set(try JSONEncoder().encode(presets), forKey: key)
        return saved
    }

    public func deleteMetadataPreset(id: Int64) async throws {
        let presets = load().filter { $0.id != id }
        defaults.set(try JSONEncoder().encode(presets), forKey: key)
    }

    private func load() -> [MetadataPreset] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([MetadataPreset].self, from: $0) } ?? []
    }
}

struct ImportPresetRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "importPreset"
    static let metadataKind = "metadata"

    var id: Int64?
    var uuid: String
    var name: String
    var kind: String
    var settings: String
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension Catalog {
    public func metadataPresets() async throws -> [MetadataPreset] {
        try await database.read { db in
            try ImportPresetRecord.fetchAll(db, sql: "SELECT * FROM importPreset WHERE kind = ? ORDER BY name COLLATE NOCASE",
                                            arguments: [ImportPresetRecord.metadataKind])
                .compactMap { record in
                    guard let values = try? SidecarValues.decode(from: record.settings) else { return nil }
                    return MetadataPreset(id: record.id, uuid: record.uuid, name: record.name, values: values)
                }
        }
    }

    /// Creates or updates a preset; returns it with its id.
    public func saveMetadataPreset(_ preset: MetadataPreset) async throws -> MetadataPreset {
        let settings = try preset.values.jsonString()
        return try await database.write { db in
            var record = ImportPresetRecord(id: preset.id, uuid: preset.uuid, name: preset.name,
                                            kind: ImportPresetRecord.metadataKind, settings: settings, createdAt: Date())
            try record.save(db)
            var saved = preset
            saved.id = record.id
            return saved
        }
    }

    public func deleteMetadataPreset(id: Int64) async throws {
        _ = try await database.write { db in try ImportPresetRecord.deleteOne(db, key: id) }
    }
}
