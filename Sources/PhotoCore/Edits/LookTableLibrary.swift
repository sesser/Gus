import Foundation
import GRDB

/// One look-up table in a collection. The file itself is in the library's
/// `LookTableStore`, named by `identifier`.
public struct LookTableEntry: Hashable, Sendable, Identifiable {
    /// Row id; nil for built-in tables.
    public var rowID: Int64?
    /// SHA-256 of the `.cube` file.
    public var identifier: String
    public var name: String
    /// The color space the table is applied in unless an edit picks another.
    public var colorSpace: LookTable.ColorSpace
    /// The imported file's name, for reference.
    public var fileName: String
    /// Built-in tables only: a stable key for their localized name.
    public var builtInKey: String?

    public var id: String { identifier }

    public init(rowID: Int64? = nil, identifier: String, name: String, colorSpace: LookTable.ColorSpace = .sRGB,
                fileName: String = "", builtInKey: String? = nil) {
        self.rowID = rowID
        self.identifier = identifier
        self.name = name
        self.colorSpace = colorSpace
        self.fileName = fileName
        self.builtInKey = builtInKey
    }

    /// The operation that applies this table.
    public func lookTable(intensity: Double = 100) -> LookTable {
        LookTable(identifier: identifier, name: name, intensity: intensity, colorSpace: colorSpace)
    }
}

/// A named list of look-up tables: the built-in one, or one the person imported.
public struct LookTableCollection: Hashable, Sendable, Identifiable {
    /// Row id; nil for the built-in collection.
    public var rowID: Int64?
    public var uuid: String
    public var name: String
    public var entries: [LookTableEntry]

    public var id: String { uuid }
    public var isBuiltIn: Bool { rowID == nil }

    public init(rowID: Int64? = nil, uuid: String = UUID().uuidString, name: String, entries: [LookTableEntry] = []) {
        self.rowID = rowID
        self.uuid = uuid
        self.name = name
        self.entries = entries
    }
}

struct LookTableCollectionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "lookTableCollection"

    var id: Int64?
    var uuid: String
    var name: String
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

struct LookTableEntryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "lookTableEntry"

    var id: Int64?
    var collectionId: Int64
    var identifier: String
    var name: String
    var colorSpace: String
    var fileName: String
    var position: Int
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

extension Catalog {
    /// Imported collections by name, each with its tables in order.
    public func lookTableCollections() async throws -> [LookTableCollection] {
        try await database.read { db in
            let collections = try LookTableCollectionRecord.fetchAll(
                db, sql: "SELECT * FROM lookTableCollection ORDER BY name COLLATE NOCASE")
            let entries = try LookTableEntryRecord.fetchAll(
                db, sql: "SELECT * FROM lookTableEntry ORDER BY collectionId, position, id")
            let grouped = Dictionary(grouping: entries, by: \.collectionId)
            return collections.map { record in
                LookTableCollection(rowID: record.id, uuid: record.uuid, name: record.name,
                                    entries: (grouped[record.id ?? -1] ?? []).map { entry in
                    LookTableEntry(rowID: entry.id, identifier: entry.identifier, name: entry.name,
                                   colorSpace: LookTable.ColorSpace(rawValue: entry.colorSpace) ?? .sRGB,
                                   fileName: entry.fileName)
                })
            }
        }
    }

    /// Creates an empty collection and returns its row id.
    public func createLookTableCollection(named name: String, at date: Date = Date()) async throws -> Int64 {
        try await database.write { db in
            var record = LookTableCollectionRecord(id: nil, uuid: UUID().uuidString, name: name, createdAt: date)
            try record.insert(db)
            return record.id ?? 0
        }
    }

    /// Appends tables to a collection, skipping ones it already has. Returns how many were added.
    @discardableResult
    public func addLookTables(_ entries: [LookTableEntry], toCollection collectionID: Int64,
                              at date: Date = Date()) async throws -> Int {
        try await database.write { db in
            let existing = Set(try String.fetchAll(
                db, sql: "SELECT identifier FROM lookTableEntry WHERE collectionId = ?", arguments: [collectionID]))
            var position = try Int.fetchOne(
                db, sql: "SELECT MAX(position) FROM lookTableEntry WHERE collectionId = ?", arguments: [collectionID]) ?? -1
            var added = 0
            var seen = existing
            for entry in entries where !seen.contains(entry.identifier) {
                seen.insert(entry.identifier)
                position += 1
                var record = LookTableEntryRecord(id: nil, collectionId: collectionID, identifier: entry.identifier,
                                                  name: entry.name, colorSpace: entry.colorSpace.rawValue,
                                                  fileName: entry.fileName, position: position, createdAt: date)
                try record.insert(db)
                added += 1
            }
            return added
        }
    }

    public func renameLookTableCollection(id: Int64, to name: String) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE lookTableCollection SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    /// Removes a collection and its entries. The table files stay in the store,
    /// so edits that use them keep rendering.
    public func deleteLookTableCollection(id: Int64) async throws {
        _ = try await database.write { db in try LookTableCollectionRecord.deleteOne(db, key: id) }
    }

    public func renameLookTableEntry(id: Int64, to name: String) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE lookTableEntry SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    public func setLookTableColorSpace(_ colorSpace: LookTable.ColorSpace, forEntry id: Int64) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE lookTableEntry SET colorSpace = ? WHERE id = ?",
                           arguments: [colorSpace.rawValue, id])
        }
    }

    /// Removes one table from its collection (the file stays, as above).
    public func deleteLookTableEntry(id: Int64) async throws {
        _ = try await database.write { db in try LookTableEntryRecord.deleteOne(db, key: id) }
    }
}

/// Display names for imported tables.
public enum LookTableNaming {
    /// Lines read at the top of a file for a descriptive name.
    static let headerLineLimit = 20

    /// A name from the file's header (its `TITLE`, or a comment such as
    /// `# Title: …` or a short first-line comment), or nil.
    public static func descriptiveName(in text: String) -> String? {
        var lineNumber = 0
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            lineNumber += 1
            guard lineNumber <= headerLineLimit else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.uppercased().hasPrefix("TITLE") {
                let title = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if let name = usable(title) { return name }
                continue
            }
            guard trimmed.hasPrefix("#") else {
                // Keywords come before data; the first number ends the header.
                if let first = trimmed.first, first.isNumber || first == "-" || first == "." { break }
                continue
            }
            let comment = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            if let colon = comment.firstIndex(of: ":") {
                let key = comment[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = comment[comment.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if ["title", "name", "lut name", "look", "description"].contains(key), let name = usable(value) {
                    return name
                }
            } else if lineNumber == 1, let name = usable(comment), !looksLikeCredit(comment) {
                return name
            }
        }
        return nil
    }

    /// A file name made readable: no extension, separators as spaces, words
    /// capitalized when the name was all lowercase.
    public static func cleanedFileName(_ fileName: String) -> String {
        var base = (fileName as NSString).deletingPathExtension
        for separator in ["_", "-", "."] {
            base = base.replacingOccurrences(of: separator, with: " ")
        }
        let name = capitalizedIfLowercase(base.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        return name.isEmpty ? fileName : name
    }

    /// "blue hour" becomes "Blue Hour"; names with any capital stay as they are.
    static func capitalizedIfLowercase(_ name: String) -> String {
        name == name.lowercased() ? name.capitalized : name
    }

    /// Leading words every name shares (such as a pack's name in every file),
    /// removed when at least two names remain distinct and none becomes empty.
    public static func removingCommonPrefix(_ names: [String]) -> [String] {
        guard names.count >= 2 else { return names }
        let split = names.map { $0.split(separator: " ").map(String.init) }
        var shared = 0
        while split.allSatisfy({ $0.count > shared + 1 }),
              Set(split.map { $0[shared].lowercased() }).count == 1 {
            shared += 1
        }
        guard shared > 0 else { return names }
        return split.map { capitalizedIfLowercase($0.dropFirst(shared).joined(separator: " ")) }
    }

    private static func usable(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 64, trimmed.contains(where: \.isLetter) else { return nil }
        return trimmed
    }

    /// Comments tools write about themselves rather than the look.
    private static func looksLikeCredit(_ comment: String) -> Bool {
        let lowered = comment.lowercased()
        return ["created", "generated", "copyright", "exported", "http", "www.", "©", "version", "lut size"]
            .contains { lowered.contains($0) }
    }
}

/// Reading a folder of `.cube` files and adding them to a collection.
public enum LookTableImport {
    /// A file found for import, with the name it will get.
    public struct Candidate: Hashable, Sendable, Identifiable {
        public let url: URL
        public var name: String
        /// Why the file cannot be imported, or nil when it can.
        public let failure: String?

        public var id: URL { url }
    }

    public enum Destination: Hashable, Sendable {
        case existing(Int64)
        case new(String)
    }

    public enum Failure: Error, Equatable {
        /// None of the files could be read or copied.
        case nothingToImport
    }

    public struct Result: Sendable {
        public var collectionID: Int64
        public var added: Int
        public var failed: [URL]
    }

    /// The `.cube` files in `folder` (and its subfolders), checked and named.
    public static func candidates(in folder: URL) -> [Candidate] {
        candidates(for: LookTableBrowsing.files(in: folder))
    }

    /// Checks and names `urls`. Names come from each file's header when it has
    /// one, otherwise from the file name, without a prefix every file shares.
    public static func candidates(for urls: [URL]) -> [Candidate] {
        var found: [(url: URL, title: String?, failure: String?)] = []
        for url in urls {
            do {
                let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
                _ = try CubeLUT(parsing: text)
                found.append((url, LookTableNaming.descriptiveName(in: text), nil))
            } catch {
                found.append((url, nil, String(describing: error)))
            }
        }
        let fileNames = LookTableNaming.removingCommonPrefix(found.map {
            LookTableNaming.cleanedFileName($0.url.lastPathComponent)
        })
        return zip(found, fileNames).map { item, fileName in
            Candidate(url: item.url, name: item.title ?? fileName, failure: item.failure)
        }
    }

    /// Copies the readable candidates into `store` and lists them in the
    /// destination collection. Creates no collection when nothing can be imported.
    public static func run(_ candidates: [Candidate], into destination: Destination,
                           colorSpace: LookTable.ColorSpace, store: LookTableStore,
                           catalog: Catalog) async throws -> Result {
        var entries: [LookTableEntry] = []
        var failed: [URL] = []
        for candidate in candidates where candidate.failure == nil {
            do {
                let table = try store.importFile(at: candidate.url)
                guard let identifier = table.identifier else { continue }
                entries.append(LookTableEntry(identifier: identifier, name: candidate.name, colorSpace: colorSpace,
                                              fileName: candidate.url.lastPathComponent))
            } catch {
                failed.append(candidate.url)
            }
        }
        guard !entries.isEmpty else { throw Failure.nothingToImport }
        let collectionID: Int64
        switch destination {
        case .existing(let id): collectionID = id
        case .new(let name): collectionID = try await catalog.createLookTableCollection(named: name)
        }
        let added = try await catalog.addLookTables(entries, toCollection: collectionID)
        return Result(collectionID: collectionID, added: added, failed: failed)
    }
}
