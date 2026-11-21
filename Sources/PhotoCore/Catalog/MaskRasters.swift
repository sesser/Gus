import Foundation
import GRDB

/// The catalog's stored detection results (issue #88, R5; `CatalogSchema.addMaskRasters`).
///
/// A row lives while any version's stack or any history entry names its
/// digest. Rows nothing names are deleted when the library opens
/// (`removeUnreferencedMaskRasters`), not by the write that stops naming
/// them: within a session the window's undo stack may still hold a stack
/// that names one (an Undo of a detection, then a history trimmed past it),
/// and a Redo must find its row. At launch no undo stack exists. Until then
/// an orphan costs its bytes (2 to 110 KB, status.md §5).
extension Catalog {
    /// Stores `raster` unless a row with its digest is there: rows are never
    /// updated, and the same bytes are the same result.
    public func storeMaskRaster(_ raster: MaskRaster, at date: Date = Date()) async throws {
        try await database.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO maskRaster
                  (digest, encoding, width, height, instances, data, request, revision, systemVersion, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [raster.digest, MaskRaster.encoding, raster.width, raster.height, raster.instances,
                                 raster.png, raster.request.rawValue, raster.revision, raster.systemVersion, date])
        }
    }

    /// The stored row `digest` names, or nil when there is none.
    public func maskRaster(digest: String) async throws -> MaskRaster? {
        try await database.read { db in try Self.maskRaster(db, digest: digest) }
    }

    /// The same, blocking: for `MaskRasterStore`, which the renderer calls off
    /// the main actor while it builds a graph. Never call it on the main actor.
    func maskRasterBlocking(digest: String) throws -> MaskRaster? {
        try database.read { db in try Self.maskRaster(db, digest: digest) }
    }

    static func maskRaster(_ db: Database, digest: String) throws -> MaskRaster? {
        guard MaskRaster.isDigest(digest), let row = try Row.fetchOne(db, sql: """
            SELECT encoding, width, height, instances, data, request, revision, systemVersion
            FROM maskRaster WHERE digest = ?
            """, arguments: [digest]) else { return nil }
        let encoding: String = row["encoding"]
        // An encoding or a request this build doesn't know is damaged: it selects nothing.
        guard encoding == MaskRaster.encoding, let request = MaskRaster.Request(rawValue: row["request"]) else {
            return nil
        }
        return MaskRaster(stored: row["data"], width: row["width"], height: row["height"], instances: row["instances"],
                          request: request, revision: row["revision"], systemVersion: row["systemVersion"])
    }

    /// Every stored digest (tests and the debug script).
    public func maskRasterDigests() async throws -> Set<String> {
        try await database.read { db in try String.fetchSet(db, sql: "SELECT digest FROM maskRaster") }
    }

    /// Deletes every row that no version's stack and no history entry names,
    /// in one transaction; returns how many went. Cheap when the table is
    /// empty; otherwise one pass over the stacks that hold a detection and
    /// over the history entries that name a row.
    @discardableResult
    public func removeUnreferencedMaskRasters() async throws -> Int {
        try await database.write { db in
            let stored = try String.fetchSet(db, sql: "SELECT digest FROM maskRaster")
            guard !stored.isEmpty else { return 0 }
            var referenced = Set<String>()
            // The stack's text, so a stack this build can't read still counts.
            let stacks = try String.fetchCursor(db, sql: """
                SELECT editStack FROM version WHERE instr(editStack, '"raster"') > 0
                """)
            while let json = try stacks.next() {
                referenced.formUnion(MaskRasterReferences.digests(inStackJSON: json))
            }
            let lists = try String.fetchCursor(db, sql: "SELECT maskRasters FROM editHistory WHERE maskRasters IS NOT NULL")
            while let list = try lists.next() {
                referenced.formUnion(MaskRasterReferences.decode(list))
            }
            let orphans = Array(stored.subtracting(referenced))
            for chunk in orphans.chunked(into: 10_000) {
                try db.execute(sql: "DELETE FROM maskRaster WHERE digest IN (\(databaseQuestionMarks(count: chunk.count)))",
                               arguments: StatementArguments(chunk))
            }
            return orphans.count
        }
    }

    // MARK: For checks only

    /// Deletes a row whatever names it: the debug script's way to show a
    /// missing result (AC13), and tests'. Nothing in the app calls it.
    public func deleteMaskRasterForChecks(digest: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM maskRaster WHERE digest = ?", arguments: [digest])
        }
    }

    /// Replaces a row's bytes with ones that are not a PNG: the debug script's
    /// way to show a damaged result. The only write that changes a row.
    public func damageMaskRasterForChecks(digest: String) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE maskRaster SET data = ? WHERE digest = ?",
                           arguments: [Data("damaged".utf8), digest])
        }
    }
}

/// Finding the digests a stored stack or history entry names.
enum MaskRasterReferences {
    private static let key = Array(#""raster":""#.utf8)

    /// Every `"raster":"<64 hex>"` in a stack's canonical JSON. Read from the
    /// text, so stacks this build can't decode still count as references.
    static func digests(inStackJSON json: String) -> Set<String> {
        var found = Set<String>()
        let bytes = Array(json.utf8)
        var index = 0
        while index + key.count + 64 <= bytes.count {
            if bytes[index] == key[0], Array(bytes[index..<(index + key.count)]) == key {
                let start = index + key.count
                let candidate = String(decoding: bytes[start..<(start + 64)], as: UTF8.self)
                if MaskRaster.isDigest(candidate) { found.insert(candidate) }
                index = start
            } else {
                index += 1
            }
        }
        return found
    }

    /// The `editHistory.maskRasters` value for a snapshot: a sorted JSON array, or nil when it names none.
    static func encode(_ digests: Set<String>) -> String? {
        guard !digests.isEmpty else { return nil }
        return "[" + digests.sorted().map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }

    static func decode(_ list: String) -> Set<String> {
        guard let array = try? JSONDecoder().decode([String].self, from: Data(list.utf8)) else { return [] }
        return Set(array.filter(MaskRaster.isDigest))
    }
}
