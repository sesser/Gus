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
