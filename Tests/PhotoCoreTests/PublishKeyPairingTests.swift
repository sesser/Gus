import Foundation
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

/// Security review N7 (issue #28): publishing never pairs a key saved for a
/// new address with the previous address, neither from a record held since
/// before a Save nor between a Save's key write and its row write.
@Suite("Publishing: a server's key with its saved row")
struct PublishKeyPairingTests {
    static let newKey = "new-key-for-the-new-address"

    /// The fixture's server (the previous address) with the valid key stored.
    static func keys(for service: RemoteServiceRecord) throws -> InMemoryKeyStore {
        let keys = InMemoryKeyStore()
        try keys.setKey(FakeImmichServer.validKey, account: service.uuid)
        return keys
    }

    @Test("A record held since before a Save: the new key never goes to the previous address (N7)")
    func staleRecordNeverPaired() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await PublishJobTests.fixture(root, files: ["a.jpg"])
            let keys = try Self.keys(for: f.service)
            let held = f.service

            // A rename alone still connects to the address as saved.
            var renamed = held
            renamed.name = "Cellar"
            guard case .saved = await f.catalog.saveRemoteService(renamed, key: nil, keys: keys) else {
                Issue.record("not renamed")
                return
            }
            guard case .ready = await PublishConnection.connect(held, catalog: f.catalog, keys: keys, readsAccount: false) else {
                Issue.record("a rename stopped the check")
                return
            }

            // The other window saves a new address with a new key.
            var moved = renamed
            moved.address = "https://photos.example.com"
            moved.allowsUnencrypted = false
            guard case .saved = await f.catalog.saveRemoteService(moved, key: Self.newKey, keys: keys) else {
                Issue.record("not saved")
                return
            }
            let before = f.server.requests.count
            let outcome = await PublishConnection.connect(held, catalog: f.catalog, keys: keys, readsAccount: false)
            guard case .changed(.connectionChanged(let now)) = outcome else {
                Issue.record("paired: \(outcome)")
                return
            }
            #expect(now.address == moved.address)
            #expect(f.server.requests.count == before, "the previous address was contacted")

            // A trusted certificate saved alone is a change too.
            var pinned = held
            pinned.certificateFingerprint = String(repeating: "e", count: 64)
            _ = try await f.catalog.saveRemoteService(pinned)
            guard case .changed(.connectionChanged) = await PublishConnection.connect(held, catalog: f.catalog, keys: keys,
                                                                                      readsAccount: false) else {
                Issue.record("a changed certificate was not refused")
                return
            }

            // Removed: nothing is read or sent.
            #expect(try await f.catalog.removeRemoteService(moved, keys: keys) == nil)
            guard case .changed(.removed) = await PublishConnection.connect(held, catalog: f.catalog, keys: keys,
                                                                            readsAccount: false) else {
                Issue.record("a removed server was contacted")
                return
            }
            #expect(f.server.requests.count == before)
        }
    }

    @Test("A Save between its key write and its row write: the check waits for the row and contacts nothing (N7)")
    func waitsForTheRow() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await PublishJobTests.fixture(root, files: ["a.jpg"])
            let keys = try Self.keys(for: f.service)
            let held = f.service
            let account = held.uuid
            let catalog = f.catalog
            let before = f.server.requests.count
            let finished = Flag()
            var moved = held
            moved.address = "https://photos.example.com"
            moved.allowsUnencrypted = false
            var check: Task<PublishConnection, Never>?
            // As a Save does: the new key is in the store, the row not yet written.
            try await RemoteKeyGate.shared.holding(account) { () async throws in
                try keys.setKey(Self.newKey, account: account)
                check = Task {
                    let outcome = await PublishConnection.connect(held, catalog: catalog, keys: keys, readsAccount: false)
                    finished.set()
                    return outcome
                }
                // The check either waits for the gate or has gone ahead.
                while RemoteKeyGate.shared.waiters(account) == 0, !finished.isSet { await Task.yield() }
                #expect(!finished.isSet, "the check read the key while the Save was between its two writes")
                #expect(f.server.requests.count == before)
                _ = try await catalog.saveRemoteService(moved)
            }
            let outcome = await check?.value
            guard case .changed(.connectionChanged(let now))? = outcome else {
                Issue.record("paired: \(String(describing: outcome))")
                return
            }
            #expect(now.address == moved.address)
            #expect(f.server.requests.count == before, "the previous address was contacted")
        }
    }

    @Test("A check started while a Save writes its key sees the Save whole, never the new key beside the previous row (N7)")
    func checkDuringSave() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await PublishJobTests.fixture(root, files: ["a.jpg"])
            let keys = SaveHookKeyStore()
            try keys.inner.setKey(FakeImmichServer.validKey, account: f.service.uuid)
            let held = f.service
            let catalog = f.catalog
            let checks = Mutex<[Task<PublishConnection, Never>]>([])
            // Publish pressed the moment the Save's key is in the store.
            keys.onSet = {
                let task = Task { await PublishConnection.connect(held, catalog: catalog, keys: keys, readsAccount: false) }
                checks.withLock { $0.append(task) }
            }
            var moved = held
            moved.address = "https://photos.example.com"
            moved.allowsUnencrypted = false
            let before = f.server.requests.count
            guard case .saved = await catalog.saveRemoteService(moved, key: Self.newKey, keys: keys) else {
                Issue.record("not saved")
                return
            }
            let check = try #require(checks.withLock { $0.first })
            guard case .changed(.connectionChanged) = await check.value else {
                Issue.record("paired")
                return
            }
            #expect(f.server.requests.count == before, "the previous address was contacted")
        }
    }

    @Test("A Save holds the account's gate across its key write and its row write (N7)")
    func saveHoldsTheGate() async throws {
        let catalog = try Catalog.makeInMemory()
        let keys = SaveHookKeyStore()
        let first = try await catalog.saveRemoteService(RemoteServiceRecord(name: "Home", address: "https://a.example"))
        let seen = Mutex<[Bool]>([])
        keys.onSet = { seen.withLock { $0.append(RemoteKeyGate.shared.isHeld(first.uuid)) } }
        var moved = first
        moved.address = "https://b.example"
        guard case .saved = await catalog.saveRemoteService(moved, key: "k", keys: keys) else {
            Issue.record("not saved")
            return
        }
        #expect(seen.withLock { $0 } == [true])
        #expect(!RemoteKeyGate.shared.isHeld(first.uuid))
    }
}

/// Set once, read from any task.
private final class Flag: Sendable {
    private let value = Mutex(false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}

/// A key store that runs a step right after a key is written.
private final class SaveHookKeyStore: RemoteKeyStore {
    let inner = InMemoryKeyStore()
    private let hook = Mutex<(@Sendable () -> Void)?>(nil)

    var onSet: (@Sendable () -> Void)? {
        get { hook.withLock { $0 } }
        set { hook.withLock { $0 = newValue } }
    }

    func key(account: String) throws(RemoteKeyStoreError) -> String? { try inner.key(account: account) }

    func setKey(_ key: String, account: String) throws(RemoteKeyStoreError) {
        try inner.setKey(key, account: account)
        onSet?()
    }

    func deleteKey(account: String) throws(RemoteKeyStoreError) { try inner.deleteKey(account: account) }
}
