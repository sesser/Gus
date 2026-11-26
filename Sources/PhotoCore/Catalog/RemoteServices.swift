import Foundation
import GRDB

/// Who a server is (R22): a value, so a later source adds rows, not tables.
public enum RemoteProvider: String, Codable, Hashable, Sendable {
    case immich
}

/// A saved server connection (issue #271, R1, R22). The key is never here: it
/// is in the Keychain under `uuid`.
public struct RemoteServiceRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "remoteService"

    public var id: Int64?
    /// The Keychain account of its key.
    public var uuid: String
    public var provider: RemoteProvider
    public var name: String
    /// Normalized (`ServerAddress.normalized`).
    public var address: String
    /// The certificate the person trusted (R6), 64 hexadecimal digits; nil
    /// when the system's trust decides.
    public var certificateFingerprint: String?
    public var certificateTrustedAt: Date?
    /// The person confirmed plain http to this local address (R5).
    public var allowsUnencrypted: Bool
    public var createdAt: Date

    public init(id: Int64? = nil, uuid: String = UUID().uuidString, provider: RemoteProvider = .immich, name: String,
                address: String, certificateFingerprint: String? = nil, certificateTrustedAt: Date? = nil,
                allowsUnencrypted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.uuid = uuid
        self.provider = provider
        self.name = name
        self.address = address
        self.certificateFingerprint = certificateFingerprint
        self.certificateTrustedAt = certificateTrustedAt
        self.allowsUnencrypted = allowsUnencrypted
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public var serverAddress: ServerAddress? { ServerAddress(normalized: address) }

    public var pinnedFingerprint: CertificateFingerprint? { certificateFingerprint.flatMap(CertificateFingerprint.init(hex:)) }
}

/// A cataloged version's link to the remote asset it came from (R15, R16).
public struct RemoteLinkRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "remoteLink"

    public var id: Int64?
    public var provider: RemoteProvider
    /// The server's normalized address: the link's server, whatever
    /// connection row names it now.
    public var address: String
    public var remoteId: String
    /// The asset's checksum as the server gave it (Immich: base64 SHA-1).
    public var fingerprint: String
    public var versionId: Int64
    /// The connection it was imported through, while that row exists. For
    /// display only; matching never uses it.
    public var serviceId: Int64?
    public var createdAt: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// What the importer links a new photo to.
public struct RemoteLinkTarget: Hashable, Sendable {
    public var provider: RemoteProvider
    public var address: String
    public var serviceID: Int64?

    public init(provider: RemoteProvider, address: String, serviceID: Int64?) {
        self.provider = provider
        self.address = address
        self.serviceID = serviceID
    }
}

/// What cataloging one downloaded photo came to.
public enum RemoteInsertOutcome: Hashable, Sendable {
    /// A new master and default version, linked.
    case inserted(imageID: Int64, versionID: Int64)
    /// The content was already in the catalog: nothing inserted; the existing
    /// master's default version was linked when it had no link to this server
    /// yet (R15b).
    case duplicate(linkedVersionID: Int64?)
    /// The asset is already linked to a version (it was imported since it was
    /// listed).
    case alreadyLinked
    /// The relative path is already a different master's.
    case pathTaken
}

extension Catalog {
    // MARK: Connections

    /// Saved connections, by name.
    public func remoteServices() async throws -> [RemoteServiceRecord] {
        try await database.read { db in
            try RemoteServiceRecord.order(sql: "name COLLATE NOCASE, id").fetchAll(db)
        }
    }

    /// The connection with this id as saved now; nil when it was removed.
    public func remoteService(id: Int64) async throws -> RemoteServiceRecord? {
        try await database.read { db in try RemoteServiceRecord.fetchOne(db, key: id) }
    }

    /// Inserts a new connection (no id) or updates an existing one. An
    /// existing connection is never recreated: when its row is gone (removed
    /// in another window), nothing is written and `RecordError.recordNotFound`
    /// is thrown (publishing design D-16).
    @discardableResult
    public func saveRemoteService(_ service: RemoteServiceRecord) async throws -> RemoteServiceRecord {
        try await database.write { db in
            var record = service
            if record.id == nil {
                try record.insert(db)
            } else {
                try record.update(db)
            }
            return record
        }
    }

    /// A name-only Save (publishing design D-16): only the name of the row as
    /// saved now changes, so an address or certificate another window saved
    /// since the sheet opened is never written back. Nil when the row is gone;
    /// nothing is written then.
    public func renameRemoteService(id: Int64, to name: String) async throws -> RemoteServiceRecord? {
        try await database.write { db in
            try db.execute(sql: "UPDATE remoteService SET name = ? WHERE id = ?", arguments: [name, id])
            guard db.changesCount > 0 else { return nil }
            return try RemoteServiceRecord.fetchOne(db, key: id)
        }
    }

    /// Removes the connection. Its links stay (R16): they belong to the
    /// server's address, and only lose their display reference.
    public func deleteRemoteService(id: Int64) async throws {
        _ = try await database.write { db in try RemoteServiceRecord.deleteOne(db, key: id) }
    }

    /// What saving a connection with its key came to.
    public enum ServiceSaveOutcome: Sendable {
        case saved(RemoteServiceRecord)
        /// The key store refused the new key: nothing changed.
        case keychainRefused(RemoteKeyStoreError)
        /// The row could not be saved: the key store holds what it held
        /// before (the previous key, or none for a new connection).
        case catalogFailed(String)
        /// The connection was removed (in another window) before its row was
        /// written: nothing was written, and no key, typed or earlier, is left
        /// for it (publishing design D-16).
        case removed
    }

    /// Saves `service` and, when `key` is given, its key, as one change
    /// (security review F2): the previous key is read first, the new one
    /// written, then the row; if the row fails, the previous key is put back
    /// (or the new one deleted when there was none). The key store is called
    /// off the main actor.
    ///
    /// An existing connection whose row is gone is never recreated (publishing
    /// design D-16): checked before the key store is touched, and again by
    /// the row's update; either way nothing is written and the account's key
    /// is deleted, so none is left for a server that is no longer saved.
    public func saveRemoteService(_ service: RemoteServiceRecord, key: String?, keys: any RemoteKeyStore) async
        -> ServiceSaveOutcome {
        let account = service.uuid
        if let id = service.id {
            do {
                if try await remoteService(id: id) == nil {
                    try? keys.deleteKey(account: account)
                    return .removed
                }
            } catch {
                return .catalogFailed(error.localizedDescription)
            }
        }
        var previous: String?
        if let key {
            do throws(RemoteKeyStoreError) {
                previous = try keys.key(account: account)
                try keys.setKey(key, account: account)
            } catch {
                return .keychainRefused(error)
            }
        }
        do {
            return .saved(try await saveRemoteService(service))
        } catch RecordError.recordNotFound {
            // Removed while the key was written: neither stays.
            try? keys.deleteKey(account: account)
            return .removed
        } catch {
            if key != nil {
                if let previous {
                    try? keys.setKey(previous, account: account)
                } else {
                    try? keys.deleteKey(account: account)
                }
            }
            return .catalogFailed(error.localizedDescription)
        }
    }

    /// Remove Server… (R4, design §3.7 and §15 DQ-5): the key leaves the key
    /// store first, then the row. If the store refuses, nothing is removed and
    /// the refusal is returned; a key already gone counts as removed. Links
    /// stay (R16).
    ///
    /// The key is deleted once more after the row: a Save in another window's
    /// Server sheet that wrote its key between the two, and its row before
    /// the row went, leaves no key behind (publishing design D-16; a Save
    /// whose row comes after finds none and deletes its own).
    public func removeRemoteService(_ service: RemoteServiceRecord, keys: any RemoteKeyStore) async throws
        -> RemoteKeyStoreError? {
        do throws(RemoteKeyStoreError) {
            try keys.deleteKey(account: service.uuid)
        } catch {
            return error
        }
        if let id = service.id {
            try await deleteRemoteService(id: id)
            try? keys.deleteKey(account: service.uuid)
        }
        return nil
    }

    // MARK: Links

    /// Which of `remoteIDs` are linked to a version, for the server at
    /// `address` (R11: those are marked and can't be checked).
    public func linkedRemoteIDs(provider: RemoteProvider, address: String, among remoteIDs: [String]) async throws
        -> Set<String> {
        guard !remoteIDs.isEmpty else { return [] }
        return try await database.read { db in
            var linked: Set<String> = []
            for chunk in remoteIDs.chunked(into: 10_000) {
                linked.formUnion(try String.fetchAll(db, sql: """
                    SELECT remoteId FROM remoteLink WHERE provider = ? AND address = ?
                    AND remoteId IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments([provider.rawValue, address] + chunk)))
            }
            return linked
        }
    }

    /// The links of a version (normally one per server).
    public func remoteLinks(versionID: Int64) async throws -> [RemoteLinkRecord] {
        try await database.read { db in
            try RemoteLinkRecord.filter(Column("versionId") == versionID).order(Column("id")).fetchAll(db)
        }
    }

    /// Catalogs one downloaded photo and links it, in one transaction (R13,
    /// R15, R17): skipped when the asset is already linked or its content is
    /// already in the catalog (then the existing photo is linked, R15b).
    /// The server's description and rating are written only where the
    /// library's own value is empty, by an update after the insert, so the
    /// existing sidecar triggers queue them like any other change (RI-6;
    /// status.md, "Sidecars").
    public func insertRemoteMaster(_ master: NewMaster, remoteID: String, fingerprint: String, link: RemoteLinkTarget,
                                   serverDescription: String?, serverRating: Int?, volumeID: Int64, projectID: Int64,
                                   importRunID: Int64?, importedAt: Date = Date()) async throws -> RemoteInsertOutcome {
        try await database.write { db in
            let linkedAlready = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM remoteLink WHERE provider = ? AND address = ? AND remoteId = ?
                """, arguments: [link.provider.rawValue, link.address, remoteID]) ?? 0
            guard linkedAlready == 0 else { return .alreadyLinked }
            if let existing = try Int64.fetchOne(db, sql: """
                SELECT version.id FROM image JOIN version ON version.imageId = image.id AND version.isDefault
                WHERE image.contentHash = ?
                """, arguments: [master.contentHash]) {
                let linked = try Self.insertLink(db, remoteID: remoteID, fingerprint: fingerprint, link: link,
                                                 versionID: existing, at: importedAt)
                return .duplicate(linkedVersionID: linked ? existing : nil)
            }
            var result = MasterInsertionResult()
            try Self.insertMasters(db, [master], volumeID: volumeID, projectID: projectID, importRunID: importRunID,
                                   importedAt: importedAt, into: &result)
            guard let imageID = result.insertedImageIDs.first, let versionID = result.insertedVersionIDs.first else {
                return result.duplicateHashes.isEmpty ? .pathTaken : .duplicate(linkedVersionID: nil)
            }
            try Self.insertLink(db, remoteID: remoteID, fingerprint: fingerprint, link: link, versionID: versionID,
                                at: importedAt)
            // The photo may have just been paired: the values reach its
            // partner too, as every write on a pair does (CLAUDE.md, RAW+JPEG
            // pairs; code review C2, C12), and only where the pair's own value
            // is empty. Pairing merged the two ratings, so one empty rating
            // means both are. Captions are not merged by pairing, so the pair
            // is treated as one here, in either listing order.
            try Self.fillPairCaption(db, versionID: versionID, serverDescription: serverDescription)
            if let rating = serverRating, Rating.range.contains(rating), rating > 0 {
                let versions = [versionID] + (try ImagePairing.partnerVersionIDs(db, of: [versionID]))
                let unrated = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM version WHERE id IN (\(databaseQuestionMarks(count: versions.count))) AND rating != 0
                    """, arguments: StatementArguments(versions)) == 0
                if unrated {
                    try db.execute(sql: "UPDATE version SET rating = ? WHERE id IN (\(databaseQuestionMarks(count: versions.count)))",
                                   arguments: StatementArguments([rating] + versions))
                }
            }
            return .inserted(imageID: imageID, versionID: versionID)
        }
    }

    /// The description of a photo just imported, with its pair as one (C12):
    /// when no image of the pair has one, the server's (if any) goes to all;
    /// when some have one, the empty ones take it (the first, by image id);
    /// images that already hold different ones keep theirs.
    static func fillPairCaption(_ db: Database, versionID: Int64, serverDescription: String?) throws {
        let images = try descriptiveImages(db, versions: [versionID])
        guard !images.isEmpty else { return }
        let captions = try Row.fetchAll(db, sql: """
            SELECT id, caption FROM image WHERE id IN (\(databaseQuestionMarks(count: images.count))) ORDER BY id
            """, arguments: StatementArguments(images)).map { (id: $0[0] as Int64, caption: ($0[1] as String?)?.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let empty = captions.filter { ($0.caption ?? "").isEmpty }.map(\.id)
        guard !empty.isEmpty else { return }
        let value: String
        if let held = captions.first(where: { !($0.caption ?? "").isEmpty }) {
            value = try String.fetchOne(db, sql: "SELECT caption FROM image WHERE id = ?", arguments: [held.id]) ?? ""
        } else if let server = serverDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !server.isEmpty {
            value = server
        } else {
            return
        }
        try db.execute(sql: "UPDATE image SET caption = ? WHERE id IN (\(databaseQuestionMarks(count: empty.count)))",
                       arguments: StatementArguments([value as (any DatabaseValueConvertible)?] + empty))
    }

    /// True when a link was made; false when the asset or the version already
    /// has one for this server.
    @discardableResult
    static func insertLink(_ db: Database, remoteID: String, fingerprint: String, link: RemoteLinkTarget,
                           versionID: Int64, at date: Date) throws -> Bool {
        // A connection removed while its import ran is no longer there to name.
        let serviceID = try link.serviceID.flatMap { try RemoteServiceRecord.exists(db, key: $0) ? $0 : nil }
        var record = RemoteLinkRecord(id: nil, provider: link.provider, address: link.address, remoteId: remoteID,
                                      fingerprint: fingerprint, versionId: versionID, serviceId: serviceID,
                                      createdAt: date)
        try record.insert(db, onConflict: .ignore)
        return db.changesCount > 0
    }
}
