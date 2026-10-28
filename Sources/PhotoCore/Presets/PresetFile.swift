import Foundation

/// Presets written to a file to share them: each preset's settings as edit
/// stack JSON, and the look-up tables they use embedded, so the file renders
/// the same in any library. One file holds one preset or a whole collection.
/// Files are JSON compressed as xz (`xz -d` reads them); plain JSON files are
/// read too.
public struct PresetFile: Codable, Sendable {
    /// The extension written; it carries the product name (see `AppBranding`).
    public static var fileExtension: String { AppBranding.presetFileExtension }
    /// Every extension read: the current one, then earlier ones.
    public static var fileExtensions: [String] {
        [AppBranding.presetFileExtension] + AppBranding.previousPresetFileExtensions
    }
    static let formatName = "adjustmentPresets"
    public static let currentFormatVersion = 1

    public enum Failure: Error, Equatable {
        case notAPresetFile
        /// Written by a newer build than this one understands.
        case unsupportedFormatVersion(Int)
    }

    public struct Preset: Codable, Sendable {
        public var name: String
        public var collection: String?
        /// `Adjustments.Group` names; nil for every group.
        public var groups: [String]?
        public var settings: EditStack
    }

    /// A `.cube` file, as it was imported.
    public struct Table: Codable, Sendable {
        /// SHA-256 of `data`, as the presets' settings refer to it.
        public var identifier: String
        public var name: String
        public var fileName: String
        public var colorSpace: String
        public var data: Data
    }

    public var format: String
    public var formatVersion: Int
    public var presets: [Preset]
    public var lookTables: [Table]

    /// A file for `presets`, with the tables they apply read from `store`.
    /// Tables missing from the store are left out (the presets keep naming them).
    public init(presets: [AdjustmentPreset], store: LookTableStore) {
        format = Self.formatName
        formatVersion = Self.currentFormatVersion
        self.presets = presets.map { preset in
            Preset(name: preset.name, collection: preset.collection.isEmpty ? nil : preset.collection,
                   groups: AdjustmentPreset.encodeGroups(preset.groups).map { $0.split(separator: ",").map(String.init) },
                   settings: preset.adjustments.editStack)
        }
        var tables: [Table] = []
        var seen = Set<String>()
        for preset in presets where preset.groups.contains(.lookTable) {
            let table = preset.adjustments.lookTable
            guard let identifier = table.identifier, seen.insert(identifier).inserted,
                  let data = store.fileData(for: identifier) else { continue }
            tables.append(Table(identifier: identifier, name: table.name, fileName: "\(table.name).cube",
                                colorSpace: table.colorSpace.rawValue, data: data))
        }
        lookTables = tables
    }

    public init(data: Data) throws {
        let data = try Self.decompressed(data)
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == Self.formatName else {
            throw Failure.notAPresetFile
        }
        guard header.formatVersion <= Self.currentFormatVersion else {
            throw Failure.unsupportedFormatVersion(header.formatVersion)
        }
        self = try JSONDecoder().decode(PresetFile.self, from: data)
    }

    private struct Header: Decodable {
        var format: String
        var formatVersion: Int
    }

    /// The file's contents: sorted JSON, compressed. Embedded tables are text
    /// in base64, so they shrink by about seven times.
    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try (encoder.encode(self) as NSData).compressed(using: .lzma) as Data
    }

    /// The xz stream header; Foundation's LZMA writes and reads xz.
    private static let xzMagic: [UInt8] = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]

    /// `data` decompressed when it is xz, otherwise as it is.
    static func decompressed(_ data: Data) throws -> Data {
        guard data.starts(with: xzMagic) else { return data }
        do {
            return try (data as NSData).decompressed(using: .lzma) as Data
        } catch {
            throw Failure.notAPresetFile
        }
    }

    /// Copies the embedded tables into `store` (each is checked and named by
    /// its contents, whatever the file claims). Returns the identifiers the
    /// presets use mapped to the ones installed; unreadable tables are left out.
    public func installTables(into store: LookTableStore) -> [String: String] {
        var installed: [String: String] = [:]
        for table in lookTables {
            guard (try? CubeLUT(parsing: String(decoding: table.data, as: UTF8.self))) != nil,
                  let identifier = try? store.install(table.data) else { continue }
            installed[table.identifier] = identifier
        }
        return installed
    }

    /// The presets, with table identifiers replaced through `tables`.
    public func adjustmentPresets(tables: [String: String] = [:]) -> [AdjustmentPreset] {
        presets.map { preset in
            var adjustments = Adjustments(stack: preset.settings)
            if let identifier = adjustments.lookTable.identifier, let installed = tables[identifier] {
                adjustments.lookTable.identifier = installed
            }
            let groups = preset.groups.map { names in Set(names.compactMap(Adjustments.Group.init(rawValue:))) }
            return AdjustmentPreset(name: preset.name, collection: preset.collection ?? "",
                                    groups: groups ?? Set(Adjustments.Group.allCases), adjustments: adjustments)
        }
    }
}
