import Foundation

/// Reading preset files (this app's, `.lrtemplate`, `.xmp`, `.dng` and preset
/// packs, `.lnpc`) and adding them to the catalog.
public enum PresetImport {
    /// At most this many files are read from one folder.
    public static let fileLimit = 2000

    public static let fileExtensions = PresetFile.fileExtensions + [CameraRawSettings.templateExtension,
                                                                    CameraRawSettings.xmpExtension,
                                                                    CameraRawSettings.dngExtension,
                                                                    LuminarPack.fileExtension]

    /// The system's language code, for the names of preset packs.
    public static var systemLanguage: String {
        Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
    }

    /// A preset read from a file.
    public struct Item: Sendable {
        public var preset: AdjustmentPreset
        /// Settings it changes that could not be carried over exactly.
        public var unsupported: Set<CameraRawFeature>
        public var source: URL
        /// The collection of the folder it was found in, which copies of one
        /// preset in several formats share even when one names its own.
        var folderCollection = ""
        /// For a preset of a pack: the pack's index in `Scan.packs` and its place in the pack.
        var pack: (index: Int, position: Int)?
    }

    public struct Failure: Sendable, Hashable {
        public var url: URL
        /// What went wrong, in English (files other than packs, and files that can't be opened).
        public var reason: String
        /// Why a preset pack was refused; nil for other files.
        public var packFailure: LuminarPack.Failure?

        public init(url: URL, reason: String, packFailure: LuminarPack.Failure? = nil) {
            self.url = url
            self.reason = reason
            self.packFailure = packFailure
        }
    }

    /// What became of one preset of a pack.
    public struct PackPresetReport: Sendable, Identifiable {
        /// Its place in the pack, from 0.
        public var id: Int
        /// Nil for a preset that could not be read and has no name.
        public var name: String?
        /// Listed but missing, or its settings could not be read: skipped.
        public var isUnreadable: Bool
        public var tools: [LuminarToolReport]

        /// How many tools have `status`; tools not recognized count as left out.
        public func count(_ status: LuminarToolReport.Status) -> Int {
            tools.filter { $0.status == status }.count
        }

        /// Known tools mapped, approximated (with their controls) and left out, then the identifiers of
        /// tools not recognized, each in tool order: the report's lines (design §2.3).
        public var mapped: [LuminarTool] { known(.mapped).map(\.0) }
        public var approximated: [(LuminarTool, [PresetControl])] { known(.approximated) }
        public var leftOut: [LuminarTool] { known(.leftOut).map(\.0) }
        public var unrecognized: [String] {
            tools.compactMap { if case .unknown(let identifier) = $0.tool { identifier } else { nil } }
        }

        private func known(_ status: LuminarToolReport.Status) -> [(LuminarTool, [PresetControl])] {
            tools.compactMap { report in
                guard report.status == status, case .known(let tool) = report.tool else { return nil }
                return (tool, report.controls)
            }
        }
    }

    /// What became of one pack: a preset collection and a look-up table collection of its name.
    public struct PackReport: Sendable, Identifiable {
        public var id: Int
        public var source: URL
        /// The collection's name.
        public var name: String
        public var presets: [PackPresetReport]
        /// Look-up tables its presets use.
        public var tableCount: Int
        /// The identifiers of the tables its presets use, before installing.
        var tables: Set<String> = []
        /// Presets that replaced one of the same name already in the collection, and presets added.
        public var replaced = 0
        public var added = 0
        /// Its look-up tables the library did not list before.
        public var addedTables = 0

        public var importedCount: Int { presets.filter { !$0.isUnreadable }.count }
    }

    /// What a set of files holds.
    public struct Scan: Sendable {
        public var items: [Item] = []
        /// Look-up tables embedded in preset files, by the identifiers their presets use.
        public var tables: [PresetFile.Table] = []
        public var failures: [Failure] = []
        /// Preset packs read, in the order their files were chosen.
        public var packs: [PackReport] = []
    }

    public struct Result: Sendable {
        public var imported: [AdjustmentPreset]
        /// How many presets each kind of setting left out or approximated (files other than packs).
        public var unsupported: [CameraRawFeature: Int]
        public var failures: [Failure]
        /// Embedded tables added to the library's look-up table collections.
        public var addedTables: Int
        /// Preset packs imported, in the order their files were chosen.
        public var packs: [PackReport] = []

        public init(imported: [AdjustmentPreset], unsupported: [CameraRawFeature: Int], failures: [Failure],
                    addedTables: Int, packs: [PackReport] = []) {
            self.imported = imported
            self.unsupported = unsupported
            self.failures = failures
            self.addedTables = addedTables
            self.packs = packs
        }

        /// True when a preset pack was among the files, imported or refused.
        public var includesPacks: Bool {
            !packs.isEmpty || failures.contains { $0.packFailure != nil }
        }

        /// Imported presets that came from files other than packs.
        public var otherImported: [AdjustmentPreset] = []

        /// What the files other than packs gave, without failures (the report lists every file's).
        public var otherPresets: Result {
            let tablesFromPacks = packs.reduce(0) { $0 + $1.addedTables }
            return Result(imported: otherImported, unsupported: unsupported, failures: [],
                          addedTables: max(0, addedTables - tablesFromPacks))
        }
    }

    /// Preset files in `folder` and its subfolders, sorted by path.
    public static func files(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator where fileExtensions.contains(url.pathExtension.lowercased()) {
            // A symbolic link counts only when it leads to a regular file (never a device or a folder).
            guard (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
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
    /// A preset pack is its own collection, whatever folder it is in, with
    /// names in `language` when the pack has it.
    public static func scan(_ urls: [URL], language: String = systemLanguage) -> Scan {
        var scan = Scan()
        var seenTables = Set<String>()
        for url in urls {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let folderCollection = isFolder ? LookTableNaming.cleanedFileName(url.lastPathComponent) : ""
            for file in isFolder ? files(in: url) : [url] {
                if file.pathExtension.lowercased() == LuminarPack.fileExtension {
                    readPacks(file, language: language, into: &scan, seenTables: &seenTables)
                    continue
                }
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

    /// The packs of one `.lnpc` file, each preset converted, or the file's refusal.
    static func readPacks(_ url: URL, language: String, into scan: inout Scan, seenTables: inout Set<String>) {
        let packs: [LuminarPack]
        do {
            packs = try LuminarPack.read(contentsOf: url, language: language)
        } catch let failure as LuminarPack.Failure {
            scan.failures.append(Failure(url: url, reason: "\(failure)", packFailure: failure))
            return
        } catch {
            scan.failures.append(Failure(url: url, reason: error.localizedDescription))
            return
        }
        for pack in packs {
            let index = scan.packs.count
            var report = PackReport(id: index, source: url, name: pack.name, presets: [], tableCount: 0)
            var packTables = Set<String>()
            for (position, entry) in pack.entries.enumerated() {
                guard case .preset(let source) = entry else {
                    if case .unreadable(let name) = entry {
                        report.presets.append(PackPresetReport(id: position, name: name, isUnreadable: true, tools: []))
                    }
                    continue
                }
                let conversion = LuminarMapping.convert(source.template, resources: source.resources)
                let preset = AdjustmentPreset(name: source.name, collection: pack.name, groups: conversion.groups,
                                              adjustments: conversion.adjustments)
                // A key of its own, so presets of different packs are never taken for copies of each other.
                scan.items.append(Item(preset: preset, unsupported: [], source: url, folderCollection: "\u{1}\(index)",
                                       pack: (index, position)))
                report.presets.append(PackPresetReport(id: position, name: source.name, isUnreadable: false,
                                                       tools: conversion.tools))
                if let table = conversion.lookTable {
                    packTables.insert(table.identifier)
                    if seenTables.insert(table.identifier).inserted { scan.tables.append(table) }
                }
            }
            report.tableCount = packTables.count
            report.tables = packTables
            scan.packs.append(report)
        }
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
    /// A preset of a pack whose table could not be installed (not a readable
    /// `.cube`) leaves the table out, and says so in its pack's report.
    /// Presets of packs are counted as replaced or added.
    public static func run(_ scan: Scan, catalog: Catalog, store: LookTableStore) async throws -> Result {
        let installedFile = PresetFile(format: PresetFile.formatName, formatVersion: PresetFile.currentFormatVersion,
                                       presets: [], lookTables: scan.tables)
        let installed = installedFile.installTables(into: store)
        var packs = scan.packs
        let existing = Set(try await catalog.adjustmentPresets().map { PresetKey(collection: $0.collection, name: $0.name) })
        let presets = scan.items.map { item -> AdjustmentPreset in
            var preset = item.preset
            if let identifier = preset.adjustments.lookTable.identifier {
                if let actual = installed[identifier] {
                    preset.adjustments.lookTable.identifier = actual
                } else if let (index, position) = item.pack {
                    preset.groups.remove(.lookTable)
                    preset.adjustments.lookTable = LookTable()
                    packs[index].presets[presetIndex(position, in: packs[index])].tools.leaveOutLookUpTable()
                }
            }
            if let (index, _) = item.pack {
                if existing.contains(PresetKey(collection: preset.collection, name: preset.name)) {
                    packs[index].replaced += 1
                } else {
                    packs[index].added += 1
                }
            }
            return preset
        }
        // A pack counts only the tables that installed.
        for index in packs.indices { packs[index].tableCount = packs[index].tables.filter { installed[$0] != nil }.count }
        let saved = try await catalog.saveAdjustmentPresets(presets)
        let added = try await listNewTables(scan, installed: installed, presets: presets, catalog: catalog)
        for index in packs.indices { packs[index].addedTables = added[packs[index].name] ?? 0 }
        var unsupported: [CameraRawFeature: Int] = [:]
        for item in scan.items {
            for feature in item.unsupported { unsupported[feature, default: 0] += 1 }
        }
        var result = Result(imported: saved, unsupported: unsupported, failures: scan.failures,
                            addedTables: added.values.reduce(0, +), packs: packs)
        result.otherImported = zip(scan.items, saved).filter { $0.0.pack == nil }.map(\.1)
        return result
    }

    private struct PresetKey: Hashable {
        var collection: String
        var name: String
    }

    private static func presetIndex(_ position: Int, in pack: PackReport) -> Int {
        pack.presets.firstIndex { $0.id == position } ?? 0
    }

    /// Tables added to the library's look-up table collections, by collection name.
    private static func listNewTables(_ scan: Scan, installed: [String: String], presets: [AdjustmentPreset],
                                      catalog: Catalog) async throws -> [String: Int] {
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
        guard !byCollection.isEmpty else { return [:] }
        let existing = try await catalog.lookTableCollections()
        var added: [String: Int] = [:]
        for (name, entries) in byCollection {
            let id: Int64
            if let collection = existing.first(where: { $0.name == name }), let rowID = collection.rowID {
                id = rowID
            } else {
                id = try await catalog.createLookTableCollection(named: name)
            }
            added[name, default: 0] += try await catalog.addLookTables(entries, toCollection: id)
        }
        return added
    }
}

extension [LuminarToolReport] {
    /// The pack's look-up table did not install: what was mapped is left out.
    mutating func leaveOutLookUpTable() {
        let table = LuminarToolReference.known(.lookUpTable)
        // Its contrast and saturation stay in the values: that row stays; only the table itself is left out.
        removeAll { $0.tool == table && $0.status == .mapped }
        let leftOut = LuminarToolReport(tool: table, status: .leftOut)
        if !contains(leftOut) { append(leftOut) }
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
