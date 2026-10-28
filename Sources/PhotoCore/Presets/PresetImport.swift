import Foundation

/// Reading preset files (this app's, `.lrtemplate`, `.xmp` and `.dng`) and adding
/// them to the catalog.
public enum PresetImport {
    /// At most this many files are read from one folder.
    public static let fileLimit = 2000

    public static let fileExtensions = PresetFile.fileExtensions + [CameraRawSettings.templateExtension,
                                                                    CameraRawSettings.xmpExtension,
                                                                    CameraRawSettings.dngExtension]

    /// A preset read from a file.
    public struct Item: Sendable {
        public var preset: AdjustmentPreset
        /// Settings it changes that could not be carried over exactly.
        public var unsupported: Set<CameraRawFeature>
        public var source: URL
        /// The collection of the folder it was found in, which copies of one
        /// preset in several formats share even when one names its own.
        var folderCollection = ""
    }

    public struct Failure: Sendable, Hashable {
        public var url: URL
        public var reason: String
    }

    /// What a set of files holds.
    public struct Scan: Sendable {
        public var items: [Item] = []
        /// Look-up tables embedded in preset files, by the identifiers their presets use.
        public var tables: [PresetFile.Table] = []
        public var failures: [Failure] = []
    }

    public struct Result: Sendable {
        public var imported: [AdjustmentPreset]
        /// How many presets each kind of setting left out or approximated.
        public var unsupported: [CameraRawFeature: Int]
        public var failures: [Failure]
        /// Embedded tables added to the library's look-up table collections.
        public var addedTables: Int
    }

    /// Preset files in `folder` and its subfolders, sorted by path.
    public static func files(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator where fileExtensions.contains(url.pathExtension.lowercased()) {
            found.append(url)
            if found.count >= fileLimit { break }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Reads `urls` (files, or folders searched recursively). Presets from a
    /// folder go in a collection named after it unless they name their own;
    /// files picked one by one keep theirs or none. When a pack holds the same
    /// preset in several formats, one copy is kept (this app's, then XMP, then
    /// templates, then DNG presets, whose photo may add its own settings).
    public static func scan(_ urls: [URL]) -> Scan {
        var scan = Scan()
        var seenTables = Set<String>()
        for url in urls {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let folderCollection = isFolder ? LookTableNaming.cleanedFileName(url.lastPathComponent) : ""
            for file in isFolder ? files(in: url) : [url] {
                do {
                    let read = try readFile(file, defaultCollection: folderCollection)
                    scan.items += read.items
                    for table in read.tables where seenTables.insert(table.identifier).inserted {
                        scan.tables.append(table)
                    }
                } catch {
                    scan.failures.append(Failure(url: file, reason: describe(error)))
                }
            }
        }
        scan.items = deduplicated(scan.items)
        return scan
    }

    /// The presets of one file.
    static func readFile(_ url: URL, defaultCollection: String) throws -> (items: [Item], tables: [PresetFile.Table]) {
        if PresetFile.fileExtensions.contains(url.pathExtension.lowercased()) {
            let file = try PresetFile(data: Data(contentsOf: url))
            let items = file.adjustmentPresets().map { preset in
                var preset = preset
                if preset.collection.isEmpty { preset.collection = defaultCollection }
                return Item(preset: preset, unsupported: [], source: url, folderCollection: defaultCollection)
            }
            return (items, file.lookTables)
        }
        let settings = try CameraRawSettings.read(contentsOf: url)
        let conversion = CameraRawMapping.convert(settings)
        let name = settings.name.flatMap { $0.isEmpty ? nil : $0 }
            ?? LookTableNaming.cleanedFileName(url.lastPathComponent)
        let preset = AdjustmentPreset(name: name, collection: settings.group ?? defaultCollection,
                                      groups: conversion.groups, adjustments: conversion.adjustments)
        return ([Item(preset: preset, unsupported: conversion.unsupported, source: url,
                      folderCollection: defaultCollection)], [])
    }

    /// One item per folder and name, by preference of format.
    static func deduplicated(_ items: [Item]) -> [Item] {
        func rank(_ item: Item) -> Int {
            switch item.source.pathExtension.lowercased() {
            case let ext where PresetFile.fileExtensions.contains(ext): 0
            case CameraRawSettings.xmpExtension: 1
            case CameraRawSettings.templateExtension: 2
            default: 3
            }
        }
        var kept: [String: Int] = [:]
        var result: [Item] = []
        for item in items {
            let key = item.folderCollection.lowercased() + "\u{0}" + item.preset.name.lowercased()
            if let index = kept[key] {
                if rank(item) < rank(result[index]) { result[index] = item }
            } else {
                kept[key] = result.count
                result.append(item)
            }
        }
        return result
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case CameraRawSettings.Failure.malformed(let line): line > 0 ? "malformed (line \(line))" : "malformed"
        case CameraRawSettings.Failure.notADevelopPreset: "not a develop preset"
        case CameraRawSettings.Failure.noSettings: "no preset settings"
        case CameraRawSettings.Failure.profile: "a profile, not a preset"
        case PresetFile.Failure.notAPresetFile: "not a preset file"
        case PresetFile.Failure.unsupportedFormatVersion: "made by a newer version"
        default: error.localizedDescription
        }
    }

    /// Installs the embedded tables, then saves the presets (replacing ones
    /// with the same name in the same collection). Tables the library does
    /// not list yet are added to a look-up table collection named after the
    /// presets' collection, so they can be picked on their own too.
    public static func run(_ scan: Scan, catalog: Catalog, store: LookTableStore) async throws -> Result {
        let installedFile = PresetFile(format: PresetFile.formatName, formatVersion: PresetFile.currentFormatVersion,
                                       presets: [], lookTables: scan.tables)
        let installed = installedFile.installTables(into: store)
        let presets = scan.items.map { item -> AdjustmentPreset in
            var preset = item.preset
            if let identifier = preset.adjustments.lookTable.identifier, let actual = installed[identifier] {
                preset.adjustments.lookTable.identifier = actual
            }
            return preset
        }
        let saved = try await catalog.saveAdjustmentPresets(presets)
        let addedTables = try await listNewTables(scan, installed: installed, presets: presets, catalog: catalog)
        var unsupported: [CameraRawFeature: Int] = [:]
        for item in scan.items {
            for feature in item.unsupported { unsupported[feature, default: 0] += 1 }
        }
        return Result(imported: saved, unsupported: unsupported, failures: scan.failures, addedTables: addedTables)
    }

    private static func listNewTables(_ scan: Scan, installed: [String: String], presets: [AdjustmentPreset],
                                      catalog: Catalog) async throws -> Int {
        let listed = Set(try await catalog.lookTableCollections().flatMap(\.entries).map(\.identifier))
        var byCollection: [String: [LookTableEntry]] = [:]
        for table in scan.tables {
            guard let identifier = installed[table.identifier], !listed.contains(identifier),
                  BuiltInLookTables.table(identifier: identifier) == nil else { continue }
            let owner = presets.first { $0.adjustments.lookTable.identifier == identifier }
            let name = owner?.collection.isEmpty == false ? owner!.collection : table.name
            byCollection[name, default: []].append(LookTableEntry(
                identifier: identifier, name: table.name,
                colorSpace: LookTable.ColorSpace(rawValue: table.colorSpace) ?? .sRGB, fileName: table.fileName))
        }
        guard !byCollection.isEmpty else { return 0 }
        let existing = try await catalog.lookTableCollections()
        var added = 0
        for (name, entries) in byCollection {
            let id: Int64
            if let collection = existing.first(where: { $0.name == name }), let rowID = collection.rowID {
                id = rowID
            } else {
                id = try await catalog.createLookTableCollection(named: name)
            }
            added += try await catalog.addLookTables(entries, toCollection: id)
        }
        return added
    }
}

extension PresetFile {
    init(format: String, formatVersion: Int, presets: [Preset], lookTables: [Table]) {
        self.format = format
        self.formatVersion = formatVersion
        self.presets = presets
        self.lookTables = lookTables
    }
}
