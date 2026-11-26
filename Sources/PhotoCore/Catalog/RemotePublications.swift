import Foundation
import GRDB

/// One upload a server accepted, as the library records it (issue #28, R17).
public struct RemotePublicationRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord,
    MutablePersistableRecord {
    public static let databaseTableName = "remotePublication"

    public enum Answer: String, Codable, Hashable, Sendable {
        /// A new asset (201).
        case created
        /// The server already had the file (R19).
        case duplicate
    }

    public var id: Int64?
    public var provider: RemoteProvider
    /// The server's normalized address.
    public var address: String
    public var remoteId: String
    public var versionId: Int64
    /// The connection it went through, while that row exists. Display only.
    public var serviceId: Int64?
    public var answer: Answer
    /// What decided the pixels: the master's content, the edit stack, the
    /// render settings and the pipeline version (`PublishDigests`).
    public var pictureDigest: String
    /// The values sent with the picture: the library's fields as the level
    /// keeps them, the typed description, name, date and visibility.
    public var metadataDigest: String
    /// SHA-256 of the file uploaded.
    public var fileDigest: String
    public var publishedAt: Date

    public init(id: Int64? = nil, provider: RemoteProvider = .immich, address: String, remoteId: String,
                versionId: Int64, serviceId: Int64?, answer: Answer, pictureDigest: String, metadataDigest: String,
                fileDigest: String, publishedAt: Date = Date()) {
        self.id = id
        self.provider = provider
        self.address = address
        self.remoteId = remoteId
        self.versionId = versionId
        self.serviceId = serviceId
        self.answer = answer
        self.pictureDigest = pictureDigest
        self.metadataDigest = metadataDigest
        self.fileDigest = fileDigest
        self.publishedAt = publishedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// A connection's remembered choices and folder map (R7, R12).
public struct RemotePublishSettings: Hashable, Sendable {
    public var choices: PublishChoices?
    public var folderMap: [PublishFolderMapping]

    public init(choices: PublishChoices? = nil, folderMap: [PublishFolderMapping] = []) {
        self.choices = choices
        self.folderMap = folderMap
    }
}

extension Catalog {
    // MARK: Records (R17)

    /// Records an accepted upload at once (R17). A connection removed while
    /// the run went is no longer named.
    @discardableResult
    public func recordPublication(_ record: RemotePublicationRecord) async throws -> RemotePublicationRecord {
        try await database.write { db in
            var record = record
            record.serviceId = try record.serviceId.flatMap { try RemoteServiceRecord.exists(db, key: $0) ? $0 : nil }
            try record.insert(db)
            return record
        }
    }

    /// The records of `versionIDs` for the server at `address`, by version.
    public func publications(provider: RemoteProvider = .immich, address: String, versionIDs: [Int64]) async throws
        -> [Int64: [RemotePublicationRecord]] {
        guard !versionIDs.isEmpty else { return [:] }
        return try await database.read { db in
            var found: [Int64: [RemotePublicationRecord]] = [:]
            for chunk in versionIDs.chunked(into: 10_000) {
                let records = try RemotePublicationRecord.fetchAll(db, sql: """
                    SELECT * FROM remotePublication WHERE provider = ? AND address = ?
                    AND versionId IN (\(databaseQuestionMarks(count: chunk.count))) ORDER BY id
                    """, arguments: StatementArguments([provider.rawValue, address] as [any DatabaseValueConvertible]
                                                       + chunk.map { $0 as any DatabaseValueConvertible }))
                for record in records { found[record.versionId, default: []].append(record) }
            }
            return found
        }
    }

    /// Which of `remoteIDs` this library published to the server at
    /// `address` (R13, R20).
    public func publishedRemoteIDs(provider: RemoteProvider = .immich, address: String, among remoteIDs: [String])
        async throws -> Set<String> {
        guard !remoteIDs.isEmpty else { return [] }
        return try await database.read { db in
            var published: Set<String> = []
            for chunk in remoteIDs.chunked(into: 10_000) {
                published.formUnion(try String.fetchAll(db, sql: """
                    SELECT remoteId FROM remotePublication WHERE provider = ? AND address = ?
                    AND remoteId IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments([provider.rawValue, address] + chunk)))
            }
            return published
        }
    }

    /// Which of `versionIDs` have a record for the server at `address` made
    /// after `date` (R23: a later run published them).
    public func versionsPublished(provider: RemoteProvider = .immich, address: String, after date: Date,
                                  among versionIDs: [Int64]) async throws -> Set<Int64> {
        guard !versionIDs.isEmpty else { return [] }
        return try await database.read { db in
            var published: Set<Int64> = []
            for chunk in versionIDs.chunked(into: 10_000) {
                published.formUnion(try Int64.fetchAll(db, sql: """
                    SELECT versionId FROM remotePublication WHERE provider = ? AND address = ? AND publishedAt > ?
                    AND versionId IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments([provider.rawValue, address, date] as [any DatabaseValueConvertible]
                                                       + chunk.map { $0 as any DatabaseValueConvertible })))
            }
            return published
        }
    }

    /// The library holds publish records or import links for the server at
    /// `address` (R26: changing the address warns).
    public func hasRecordsOrLinks(provider: RemoteProvider = .immich, address: String) async throws -> Bool {
        try await database.read { db in
            let records = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM remotePublication WHERE provider = ? AND address = ?)
                OR EXISTS(SELECT 1 FROM remoteLink WHERE provider = ? AND address = ?)
                """, arguments: [provider.rawValue, address, provider.rawValue, address])
            return records ?? false
        }
    }

    // MARK: Remembered choices and the folder map (R7, R12)

    public func publishSettings(serviceID: Int64) async throws -> RemotePublishSettings {
        try await database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT choices, folderMap FROM remotePublishSettings WHERE serviceId = ?",
                                             arguments: [serviceID]) else { return RemotePublishSettings() }
            let decoder = JSONDecoder()
            let choices = (row["choices"] as String?).flatMap { try? decoder.decode(PublishChoices.self, from: Data($0.utf8)) }
            let map = (row["folderMap"] as String?).flatMap {
                try? decoder.decode([PublishFolderMapping].self, from: Data($0.utf8))
            } ?? []
            return RemotePublishSettings(choices: choices, folderMap: map)
        }
    }

    /// The choices a run starts with (design §3.7).
    public func savePublishChoices(_ choices: PublishChoices, serviceID: Int64) async throws {
        let json = try Self.json(choices)
        try await database.write { db in
            guard try RemoteServiceRecord.exists(db, key: serviceID) else { return }
            try db.execute(sql: """
                INSERT INTO remotePublishSettings (serviceId, choices) VALUES (?, ?)
                ON CONFLICT(serviceId) DO UPDATE SET choices = excluded.choices
                """, arguments: [serviceID, json])
        }
    }

    /// The folder map, saved on Done (design §6).
    public func saveFolderMap(_ map: [PublishFolderMapping], serviceID: Int64) async throws {
        let json = try Self.json(map)
        try await database.write { db in
            guard try RemoteServiceRecord.exists(db, key: serviceID) else { return }
            try db.execute(sql: """
                INSERT INTO remotePublishSettings (serviceId, folderMap) VALUES (?, ?)
                ON CONFLICT(serviceId) DO UPDATE SET folderMap = excluded.folderMap
                """, arguments: [serviceID, json])
        }
    }

    private static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
