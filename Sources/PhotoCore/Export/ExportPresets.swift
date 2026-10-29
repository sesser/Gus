import Foundation
import GRDB

/// Named export settings.
public struct ExportPreset: Codable, Hashable, Sendable, Identifiable {
    public var id: Int64?
    public var uuid: String
    public var name: String
    public var settings: ExportSettings

    public init(id: Int64? = nil, uuid: String = UUID().uuidString, name: String, settings: ExportSettings) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.settings = settings
    }
}

struct ExportPresetRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "exportPreset"

    var id: Int64?
    var uuid: String
    var name: String
    var settings: String
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension Catalog {
    public func exportPresets() async throws -> [ExportPreset] {
        try await database.read { db in
            try ExportPresetRecord.fetchAll(db, sql: "SELECT * FROM exportPreset ORDER BY name COLLATE NOCASE")
                .compactMap { record in
                    guard let settings = try? ExportSettings.decode(from: record.settings) else { return nil }
                    return ExportPreset(id: record.id, uuid: record.uuid, name: record.name, settings: settings)
                }
        }
    }

    /// Creates or updates a preset; returns it with its id.
    public func saveExportPreset(_ preset: ExportPreset) async throws -> ExportPreset {
        let settings = try preset.settings.jsonString()
        return try await database.write { db in
            var record = ExportPresetRecord(id: preset.id, uuid: preset.uuid, name: preset.name, settings: settings,
                                            createdAt: Date())
            if let id = preset.id, let existing = try ExportPresetRecord.fetchOne(db, key: id) {
                record.createdAt = existing.createdAt
            }
            try record.save(db)
            var saved = preset
            saved.id = record.id
            return saved
        }
    }

    public func deleteExportPreset(id: Int64) async throws {
        _ = try await database.write { db in try ExportPresetRecord.deleteOne(db, key: id) }
    }
}

/// Which versions an export writes for a selection in the grid.
public enum ExportTargets {
    /// A RAW+JPEG pair exports once, from its RAW, whichever half is selected
    /// (or both); videos are left out and counted. Order follows `items`.
    public static func resolve(_ items: [CatalogItem]) -> (versionIDs: [Int64], videos: Int) {
        var seen = Set<Int64>()
        var ids: [Int64] = []
        var videos = 0
        for item in items {
            if item.isVideo {
                videos += 1
                continue
            }
            var id = item.versionID
            if let partner = item.partnerVersionID, item.fileKind != .raw, item.partnerKind == .raw {
                id = partner
            }
            if seen.insert(id).inserted { ids.append(id) }
        }
        return (ids, videos)
    }
}
