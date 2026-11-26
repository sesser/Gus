import Foundation
import Security
import Synchronization

/// A saved server's key and its row as one pair (security review N7).
///
/// Saving writes the key, then the row (security review F2: a failed row
/// write puts the previous key back). Between the two the Keychain holds the
/// new key beside the previous address. Every write of a key with its row,
/// and every read of a key for publishing, holds this gate for the account,
/// so a reader never sees a key without the row saved with it. The gate is
/// per account and per process: only the library app saves or reads server
/// keys, and the library lock keeps a second copy off the same catalog.
///
/// It is held only around the Keychain and catalog calls, never across a
/// request. A Keychain access prompt holds it until answered; another Save of
/// the same server waits for it meanwhile.
public final class RemoteKeyGate: Sendable {
    public static let shared = RemoteKeyGate()

    private struct Accounts {
        var held: Set<String> = []
        var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
    }

    private let accounts = Mutex(Accounts())

    init() {}

    /// Runs `body` with `account`'s gate held, after whoever holds it now.
    public func holding<T, E: Error>(_ account: String, isolation: isolated (any Actor)? = #isolation,
                                     _ body: () async throws(E) -> T) async throws(E) -> T {
        await acquire(account)
        do {
            let value = try await body()
            release(account)
            return value
        } catch {
            release(account)
            throw error
        }
    }

    /// Whether the gate for `account` is held now (tests).
    func isHeld(_ account: String) -> Bool {
        accounts.withLock { $0.held.contains(account) }
    }

    /// How many wait for `account`'s gate now (tests).
    func waiters(_ account: String) -> Int {
        accounts.withLock { $0.waiting[account]?.count ?? 0 }
    }

    private func acquire(_ account: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let free = accounts.withLock { accounts in
                if accounts.held.insert(account).inserted { return true }
                accounts.waiting[account, default: []].append(continuation)
                return false
            }
            if free { continuation.resume() }
        }
    }

    /// Hands the gate to the next waiter, in order, or frees it.
    private func release(_ account: String) {
        let next = accounts.withLock { accounts -> CheckedContinuation<Void, Never>? in
            if var queue = accounts.waiting[account], !queue.isEmpty {
                let first = queue.removeFirst()
                accounts.waiting[account] = queue.isEmpty ? nil : queue
                return first
            }
            accounts.held.remove(account)
            return nil
        }
        next?.resume()
    }
}

/// A saved server's key read with its row as saved now (security review N7).
public enum RemoteSavedKey: Sendable {
    /// The row is the one asked about (same address and trusted
    /// certificate) and this is its key.
    case key(String, RemoteServiceRecord)
    /// The row is gone, or its address or trusted certificate is not the
    /// one asked about: no key is given, so none can reach the previous
    /// address. Never `.unchanged`.
    case changed(PublishServerChange)
    case keychain(RemoteKeyStoreError)
    /// The catalog could not be read.
    case catalog(String)

    /// The key of `service`, only if the row as saved now has `service`'s
    /// address and trusted certificate. The key and the row are read under
    /// the account's gate, so neither is half of a Save.
    public static func read(for service: RemoteServiceRecord, in catalog: Catalog, keys: any RemoteKeyStore) async
        -> RemoteSavedKey {
        guard let id = service.id else { return .changed(.removed) }
        let read: RemoteSavedKey = await RemoteKeyGate.shared.holding(service.uuid) {
            let key: String?
            do throws(RemoteKeyStoreError) {
                key = try keys.key(account: service.uuid)
            } catch {
                return .keychain(error)
            }
            let now: RemoteServiceRecord?
            do {
                now = try await catalog.remoteService(id: id)
            } catch {
                return .catalog(error.localizedDescription)
            }
            guard let now else { return .changed(.removed) }
            if case .connectionChanged(let changed) = PublishServerChange.after(reload: [now], chosenID: id, before: service) {
                return .changed(.connectionChanged(changed))
            }
            guard let key else { return .keychain(RemoteKeyStoreError.from(errSecItemNotFound)) }
            return .key(key, now)
        }
        return read
    }
}
