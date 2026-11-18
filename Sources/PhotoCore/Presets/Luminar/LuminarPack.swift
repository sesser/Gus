import Foundation

/// A preset pack (`.lnpc`): a zip archive holding `Config/config.json` and a
/// folder per pack with its `config.json` (name, and presets in order, as keys
/// that `localizations/<language>.strings` translate) and one `<uuid>.lnp/`
/// folder per preset (`template.lmps`, `resources/` with its look-up table,
/// `localizations/` for its name). Read in memory, never extracted; nothing
/// is written anywhere.
public struct LuminarPack: Sendable {
    public static let fileExtension = "lnpc"
    /// Files larger than this are refused before they are read.
    public static let maximumFileSize = 256 * 1024 * 1024
    /// At most this much is decompressed from one file.
    public static let maximumReadSize = 512 * 1024 * 1024
    /// At most this many presets in one file, listed or found (packs hold about ten).
    public static let maximumPresetCount = 1000

    /// Why a file was refused. Each case has its own wording in the app.
    public enum Failure: Error, Equatable, Sendable {
        /// Not a zip archive.
        case notAZip
        /// A zip archive without `Config/config.json`: not a pack.
        case missingConfig
        /// Cut short, or its structure or a member's checksum is broken.
        case damaged
        /// The pack's settings (its configuration, or every preset's) can't be read.
        case unreadableSettings
        /// A pack with no presets in it.
        case noPresets
        /// Over `maximumFileSize`, `maximumReadSize` or the archive's limits.
        case tooLarge
    }

    public struct Preset: Sendable {
        public var name: String
        public var uuid: String
        public var template: LuminarTemplate
        /// Files of the preset's `resources/` folder, by file name.
        public var resources: [String: Data]
    }

    /// One place in the pack's order: a preset, or one that could not be read.
    public enum Entry: Sendable {
        case preset(Preset)
        /// Listed but missing, or its settings can't be read; its name when known.
        case unreadable(name: String?)
    }

    /// The pack's name, in the chosen language when the pack has it.
    public var name: String
    public var entries: [Entry]

    public var presets: [Preset] {
        entries.compactMap { if case .preset(let preset) = $0 { preset } else { nil } }
    }

    static let configPath = "Config/config.json"
    static let templateName = "template.lmps"
    static let presetSuffix = ".lnp"
    /// Keys the pack's `config.json` uses for its texts, meaningless untranslated.
    static let placeholderKeys: Set<String> = ["Pack Name", "Short Description", "Detailed Description"]

    /// The packs of the file at `url` (usually one), names in `language`
    /// (a language code such as "de") when the pack has it, English otherwise.
    public static func read(contentsOf url: URL, language: String) throws -> [LuminarPack] {
        try read(Self.contents(of: url, limit: maximumFileSize), fileName: url.lastPathComponent, language: language)
    }

    /// The file's bytes: a regular file (a symbolic link is followed first,
    /// anything else is not a pack), read through a handle that never takes
    /// more than `limit` bytes, whatever the file's size says or becomes.
    static func contents(of url: URL, limit: Int) throws -> Data {
        let resolved = url.resolvingSymlinksInPath()
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw Failure.notAZip }
        guard (values.fileSize ?? 0) <= limit else { throw Failure.tooLarge }
        let handle = try FileHandle(forReadingFrom: resolved)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw Failure.tooLarge }
        return data
    }

    static func read(_ data: Data, fileName: String, language: String,
                     readBudget: Int = maximumReadSize) throws -> [LuminarPack] {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(data: data)
        } catch let failure as ZipArchive.Failure {
            throw Failure(failure)
        }
        var reader = Reader(archive: archive, readBudget: readBudget)
        return try reader.packs(fallbackName: LookTableNaming.cleanedFileName(fileName), language: language)
    }
}

extension LuminarPack.Failure {
    init(_ failure: ZipArchive.Failure) {
        switch failure {
        case .notAZip: self = .notAZip
        case .damaged, .unsupported: self = .damaged
        case .tooLarge: self = .tooLarge
        }
    }
}

extension LuminarPack {
    private struct Reader {
        let archive: ZipArchive
        /// Members by normalized path; directories, hidden files and paths leaving the archive left out.
        let files: [String: ZipArchive.Entry]
        /// Every member's path, sorted once.
        let sortedPaths: [String]
        /// The files directly in each preset folder's `resources/`, by the preset folder, sorted.
        let resources: [String: [String]]
        let readBudget: Int
        var bytesRead = 0

        init(archive: ZipArchive, readBudget: Int) {
            self.archive = archive
            self.readBudget = readBudget
            var files: [String: ZipArchive.Entry] = [:]
            for entry in archive.entries where !entry.isDirectory {
                guard let path = Self.normalized(entry.path) else { continue }
                files[path] = entry
            }
            self.files = files
            sortedPaths = files.keys.sorted()
            var resources: [String: [String]] = [:]
            for path in sortedPaths {
                let folder = Self.folder(of: path)
                guard Self.lastComponent(folder) == "resources" else { continue }
                resources[Self.folder(of: folder), default: []].append(path)
            }
            self.resources = resources
        }

        /// The path without `.` parts or repeated slashes; nil when it is
        /// absolute, leaves the archive, or names a hidden or resource-fork file.
        static func normalized(_ path: String) -> String? {
            guard !path.hasPrefix("/") else { return nil }
            var parts: [Substring] = []
            for part in path.split(separator: "/", omittingEmptySubsequences: true) where part != "." {
                if part == ".." || part.hasPrefix(".") { return nil }
                parts.append(part)
            }
            guard let first = parts.first, first != "__MACOSX" else { return nil }
            return parts.joined(separator: "/")
        }

        mutating func read(_ path: String) throws -> Data {
            guard let entry = files[path] else { throw LuminarPack.Failure.damaged }
            bytesRead += entry.uncompressedSize
            guard bytesRead <= readBudget else { throw LuminarPack.Failure.tooLarge }
            do {
                return try archive.contents(of: entry)
            } catch let failure as ZipArchive.Failure {
                throw LuminarPack.Failure(failure)
            }
        }

        mutating func object(_ path: String) throws -> [String: Any] {
            var data = try read(path)
            if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = Data(data.dropFirst(3)) }
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw LuminarPack.Failure.unreadableSettings
            }
            return object
        }

        /// The texts of `<folder>/localizations/`, English overlaid with `language`.
        mutating func texts(in folder: String, language: String) throws -> [String: String] {
            var texts: [String: String] = [:]
            for candidate in language == "en" ? ["en"] : ["en", language] {
                let path = Self.join(folder, "localizations/\(candidate).strings")
                guard files[path] != nil else { continue }
                if let table = StringsTable.parse(try read(path)) { texts.merge(table) { $1 } }
            }
            return texts
        }

        static func join(_ folder: String, _ name: String) -> String {
            folder.isEmpty ? name : "\(folder)/\(name)"
        }

        static func folder(of path: String) -> String {
            guard let slash = path.lastIndex(of: "/") else { return "" }
            return String(path[..<slash])
        }

        static func lastComponent(_ path: String) -> String {
            path.split(separator: "/").last.map(String.init) ?? path
        }

        /// The translated text for `key`; the key itself when it is plain text, nil for an untranslated placeholder.
        static func text(_ texts: [String: String], _ key: Any?) -> String? {
            guard let key = key as? String, !key.isEmpty else { return nil }
            if let text = texts[key] { return text }
            return LuminarPack.placeholderKeys.contains(key) ? nil : key
        }

        mutating func packs(fallbackName: String, language: String) throws -> [LuminarPack] {
            guard files[LuminarPack.configPath] != nil else { throw LuminarPack.Failure.missingConfig }
            _ = try object(LuminarPack.configPath)
            // Preset folders, sorted, and grouped by the folder they are in.
            var templateFolders: [String] = []
            var templatesByParent: [String: [String]] = [:]
            for path in sortedPaths where Self.lastComponent(path) == LuminarPack.templateName {
                let folder = Self.folder(of: path)
                templateFolders.append(folder)
                templatesByParent[Self.folder(of: folder), default: []].append(folder)
            }
            guard templateFolders.count <= LuminarPack.maximumPresetCount else { throw LuminarPack.Failure.tooLarge }

            var configs: [(folder: String, templates: [Any], name: Any?)] = []
            var listedCount = 0
            for path in sortedPaths where Self.lastComponent(path) == "config.json" && path != LuminarPack.configPath {
                let config = try object(path)
                if let templates = config["templates"] as? [Any] {
                    // Counted before any row is made: a list can name far more presets than the archive holds.
                    listedCount += templates.count
                    guard listedCount <= LuminarPack.maximumPresetCount else { throw LuminarPack.Failure.tooLarge }
                    configs.append((Self.folder(of: path), templates, config["name"]))
                }
            }

            var packs: [LuminarPack] = []
            var claimed = Set<String>()
            for config in configs {
                let texts = try texts(in: config.folder, language: language)
                let name = Self.text(texts, config.name).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                var pack = LuminarPack(name: name.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName, entries: [])
                let listed = config.templates.map { Self.join(config.folder, LuminarTemplate.text($0)) }
                let listedSet = Set(listed)
                let unlisted = (templatesByParent[config.folder] ?? []).filter { !listedSet.contains($0) }
                for folder in listed + unlisted {
                    claimed.insert(folder)
                    pack.entries.append(try entry(folder, language: language))
                }
                packs.append(pack)
            }
            // Presets no pack lists (a lone preset folder, or one made by hand).
            let orphans = templateFolders.filter { !claimed.contains($0) }
            if !orphans.isEmpty {
                var pack = LuminarPack(name: fallbackName, entries: [])
                for folder in orphans { pack.entries.append(try entry(folder, language: language)) }
                packs.append(pack)
            }
            packs.removeAll { $0.entries.isEmpty }
            guard packs.contains(where: { !$0.presets.isEmpty }) else {
                throw packs.isEmpty ? LuminarPack.Failure.noPresets : LuminarPack.Failure.unreadableSettings
            }
            return packs
        }

        /// One preset folder; a missing or unreadable template gives an unreadable entry.
        mutating func entry(_ folder: String, language: String) throws -> LuminarPack.Entry {
            let templatePath = Self.join(folder, LuminarPack.templateName)
            guard files[templatePath] != nil else { return .unreadable(name: nil) }
            let template: LuminarTemplate
            do {
                template = try LuminarTemplate(data: try read(templatePath))
            } catch LuminarPack.Failure.tooLarge {
                throw LuminarPack.Failure.tooLarge
            } catch {
                return .unreadable(name: nil)
            }
            let texts = try texts(in: folder, language: language)
            var folderName = Self.lastComponent(folder)
            if folderName.lowercased().hasSuffix(LuminarPack.presetSuffix) { folderName.removeLast(LuminarPack.presetSuffix.count) }
            let translated = (texts[template.name] ?? template.name).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = translated.isEmpty ? folderName : translated
            var resources: [String: Data] = [:]
            for path in self.resources[folder] ?? [] {
                resources[Self.lastComponent(path)] = try read(path)
            }
            return .preset(LuminarPack.Preset(name: name, uuid: template.uuid.isEmpty ? folderName : template.uuid,
                                              template: template, resources: resources))
        }
    }
}

/// Apple `.strings` files (`"key" = "value";`), read with Foundation's property list parser.
enum StringsTable {
    /// The pairs, or nil when the data is not a strings table.
    static func parse(_ data: Data) -> [String: String]? {
        var data = data
        // UTF-16 without a byte order mark: the parser only recognizes it with one.
        if !data.starts(with: [0xFF, 0xFE]), !data.starts(with: [0xFE, 0xFF]), data.count >= 2, data.contains(0) {
            let encoding: String.Encoding = data[data.startIndex + 1] == 0 ? .utf16LittleEndian : .utf16BigEndian
            guard let text = String(data: data, encoding: encoding) else { return nil }
            data = Data(text.utf8)
        }
        let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil)
        guard let table = parsed as? [String: Any] else { return nil }
        return table.compactMapValues { $0 as? String }
    }
}
