import Foundation
import Security

/// The import window's check of its server (issue #271, R2), with the key
/// read with its row as saved now (publishing design D-18, security review
/// N7): only a row with the address and trusted certificate the window holds
/// is contacted, so a key saved for a new address never reaches the previous
/// one.
public enum RemoteImportConnection: Sendable {
    /// The check passed. The row as saved now: the same address and
    /// certificate as the window's, its other values (the name) perhaps not.
    case ready(ImmichClient, RemoteServerInfo, RemoteServiceRecord)
    /// The check failed, or the key could not be read. A catalog that could
    /// not be read is `.keychain` with the catalog's message, as the Server
    /// sheet shows it.
    case failed(ConnectionCheckResult)
    /// The server as saved now is not the window's: removed, or its address
    /// or trusted certificate changed. Nothing was sent. Never `.unchanged`.
    case changed(PublishServerChange)

    /// Off the main actor: the Keychain may ask the person (code review C8).
    public static func connect(_ service: RemoteServiceRecord, catalog: Catalog, keys: any RemoteKeyStore) async
        -> RemoteImportConnection {
        guard service.serverAddress != nil else { return .failed(.notImmich) }
        let key: String
        let saved: RemoteServiceRecord
        switch await RemoteSavedKey.read(for: service, in: catalog, keys: keys) {
        case .key(let stored, let record):
            key = stored
            saved = record
        case .changed(let change):
            return .changed(change)
        case .keychain(let error):
            return .failed(.keychain(error.message))
        case .catalog(let message):
            return .failed(.keychain(message))
        }
        guard let address = saved.serverAddress else { return .failed(.notImmich) }
        let connection = RemoteConnection(address: address, key: key, pinned: saved.pinnedFingerprint,
                                          unencryptedConfirmed: saved.allowsUnencrypted)
        guard let client = try? ImmichClient(connection: connection) else {
            return .failed(.unreachable(reason: "", isLocalHost: address.isLocalNetworkHost))
        }
        let result = await client.check()
        guard case .passed(let info) = result else { return .failed(result) }
        return .ready(client, info, saved)
    }
}

/// What the import window does when the server it shows was saved again,
/// in the other window or from a check (publishing design D-18, §11.1).
public enum RemoteSourceFollow: Equatable, Sendable {
    /// Nothing the window shows changed (a new key alone is not seen here;
    /// the next check reads it).
    case none
    /// The same address and trusted certificate, another name: taken in
    /// place, nothing contacted or reloaded (D-18's rename).
    case takeSaved(RemoteServiceRecord)
    /// Another address or trusted certificate: the server is chosen again
    /// as saved now (the selection, pages, album and range go).
    case chooseAgain(RemoteServiceRecord)
    /// No longer saved: as after Remove Server….
    case leave
    /// An import from the server is running: nothing in the window changes,
    /// and the reconnect after it follows the server as saved then.
    case afterImport

    /// `held` is the record the window shows, `now` the row as saved now
    /// (nil when removed).
    public static func after(held: RemoteServiceRecord, now: RemoteServiceRecord?, importing: Bool) -> RemoteSourceFollow {
        let follow: RemoteSourceFollow
        if let now {
            if now.address != held.address || now.certificateFingerprint != held.certificateFingerprint {
                follow = .chooseAgain(now)
            } else {
                // With the same address and certificate only the name can
                // differ in what the window shows (whether plain http is
                // allowed follows the address). Not the whole record: a record
                // kept in memory since a Save has a finer creation time than
                // its row read back.
                follow = now.name == held.name ? .none : .takeSaved(now)
            }
        } else {
            follow = .leave
        }
        return importing && follow != .none ? .afterImport : follow
    }
}

/// The Server sheet's check and save (issue #271; publishing design D-16,
/// D-19), from either host. With the key field empty the stored key is read
/// with its row, and the row is written only if the server is still saved as
/// the sheet opened on it, so a key saved in the other window never goes to
/// this sheet's address and this sheet never writes over that Save.
public enum RemoteServerSheetCheck {
    public enum Outcome: Sendable {
        case saved(RemoteServiceRecord)
        /// The server being edited is no longer saved: nothing was read,
        /// sent or written (D-16).
        case removed
        /// The sheet is behind the saved server (another address, trusted
        /// certificate or, at the save, key): the stored key was sent
        /// nowhere it wasn't saved for and nothing was written. The server as
        /// saved now (D-19).
        case changed(RemoteServiceRecord)
        /// No pin, and the system does not trust the certificate: page 2.
        case untrustedCertificate(CertificateSummary)
        /// A failed check, a Keychain refusal, or a catalog that could not
        /// be read (`.keychain` with its message). `permissions` when the
        /// server listed the key's.
        case failed(ConnectionCheckResult, permissions: [String]?)
        /// The sheet was cancelled during the check: nothing written.
        case cancelled
    }

    /// The key to check with, or how the press ends.
    public enum KeyStep: Sendable {
        case key(String)
        case ended(Outcome)
    }

    /// At the press: the server being edited still saved (D-16), then the
    /// typed key, or the stored key read with its row, only while that row
    /// still has `opened`'s address and trusted certificate (D-19).
    public static func key(entered: String?, opened: RemoteServiceRecord?, catalog: Catalog,
                           keys: any RemoteKeyStore) async -> KeyStep {
        if let opened {
            guard let id = opened.id else { return .ended(.removed) }
            do {
                guard try await catalog.remoteService(id: id) != nil else { return .ended(.removed) }
            } catch {
                return .ended(.failed(.keychain(error.localizedDescription), permissions: nil))
            }
            guard !Task.isCancelled else { return .ended(.cancelled) }
        }
        if let entered { return .key(entered) }
        guard let opened else { return .ended(.failed(.keychain(RemoteKeyStoreError.from(errSecItemNotFound).message),
                                                       permissions: nil)) }
        switch await RemoteSavedKey.read(for: opened, in: catalog, keys: keys) {
        case .key(let stored, _):
            return .key(stored)
        case .changed(.connectionChanged(let now)):
            return .ended(.changed(now))
        case .changed:
            return .ended(.removed)
        case .keychain(let error):
            return .ended(.failed(.keychain(error.message), permissions: nil))
        case .catalog(let message):
            return .ended(.failed(.keychain(message), permissions: nil))
        }
    }

    /// The check against what the form shows.
    public static func check(address: ServerAddress, key: String, pinned: CertificateFingerprint?,
                             unencryptedConfirmed: Bool, requiring: [String], readsAccount: Bool) async
        -> (result: ConnectionCheckResult, permissions: [String]?) {
        let connection = RemoteConnection(address: address, key: key, pinned: pinned,
                                          unencryptedConfirmed: unencryptedConfirmed)
        do {
            return await (try ImmichClient(connection: connection))
                .checkWithPermissions(requiring: requiring, readsAccount: readsAccount)
        } catch {
            return (.unreachable(reason: "", isLocalHost: address.isLocalNetworkHost), nil)
        }
    }

    /// After a passing check: a typed key is saved with the row, as before
    /// (security review F2: the last save wins); with the key field empty
    /// the row is written only if the stored key is still `checkedKey` and
    /// the row still `opened`'s (D-19).
    public static func save(_ record: RemoteServiceRecord, enteredKey: String?, checkedKey: String,
                            opened: RemoteServiceRecord?, catalog: Catalog, keys: any RemoteKeyStore) async -> Outcome {
        let outcome: Catalog.ServiceSaveOutcome
        if enteredKey == nil, let opened {
            outcome = await catalog.saveRemoteService(record, checkedWith: checkedKey, opened: opened, keys: keys)
        } else {
            outcome = await catalog.saveRemoteService(record, key: enteredKey, keys: keys)
        }
        switch outcome {
        case .saved(let saved): return .saved(saved)
        case .keychainRefused(let error): return .failed(.keychain(error.message), permissions: nil)
        case .catalogFailed(let message): return .failed(.keychain(message), permissions: nil)
        case .removed: return .removed
        case .changed(let now): return .changed(now)
        }
    }

    /// Add, Save or Trust Certificate with a check, whole. `record` is what
    /// a pass saves (the form's values on the opened server, or a new one);
    /// `opened` the server the sheet opened on (nil for Add). Off the main
    /// actor: the Keychain may ask the person (code review C8).
    public static func run(_ record: RemoteServiceRecord, address: ServerAddress, enteredKey: String?,
                           pinned: CertificateFingerprint?, unencryptedConfirmed: Bool, requiring: [String],
                           readsAccount: Bool, opened: RemoteServiceRecord?, catalog: Catalog,
                           keys: any RemoteKeyStore) async -> Outcome {
        let key: String
        switch await Self.key(entered: enteredKey, opened: opened, catalog: catalog, keys: keys) {
        case .key(let found): key = found
        case .ended(let outcome): return outcome
        }
        guard !Task.isCancelled else { return .cancelled }
        let (result, permissions) = await check(address: address, key: key, pinned: pinned,
                                                unencryptedConfirmed: unencryptedConfirmed, requiring: requiring,
                                                readsAccount: readsAccount)
        guard !Task.isCancelled else { return .cancelled }
        switch result {
        case .passed:
            return await save(record, enteredKey: enteredKey, checkedKey: key, opened: opened, catalog: catalog,
                              keys: keys)
        case .untrustedCertificate(let summary):
            return .untrustedCertificate(summary)
        default:
            return .failed(result, permissions: permissions)
        }
    }
}
