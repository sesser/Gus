import Foundation
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

/// Security review N7 on the import side (issue #28, publishing design D-18
/// and D-19): the import window's check and the Server sheet never pair a key
/// saved for a new address with the previous address, and a sheet behind the
/// saved server writes nothing.
@Suite("Import window and Server sheet: a server's key with its saved row")
struct ServerKeyPairingTests {
    static let newKey = "new-key-for-the-new-address"

    struct Fixture {
        var catalog: Catalog
        var server: FakeImmichServer
        var service: RemoteServiceRecord
        var keys: InMemoryKeyStore

        /// The other window's Save: a new address (not the fake's) and a new key.
        @discardableResult
        func saveElsewhere(name: String? = nil, address: String = "https://photos.example.com",
                           key: String? = ServerKeyPairingTests.newKey) async throws -> RemoteServiceRecord {
            let id = try #require(service.id)
            var moved = try #require(try await catalog.remoteService(id: id))
            if let name { moved.name = name }
            moved.address = address
            moved.allowsUnencrypted = address.hasPrefix("http://")
            guard case .saved(let saved) = await catalog.saveRemoteService(moved, key: key, keys: keys) else {
                Issue.record("the other window's Save failed")
                return moved
            }
            return saved
        }
    }

    /// Home at the fake server's address (plain http on the loopback,
    /// confirmed), with the fake's key stored.
    static func fixture() async throws -> Fixture {
        let catalog = try Catalog.makeInMemory()
        let server = try await FakeImmichServer()
        let address = try RemoteConnectionTests.address(server.address)
        let service = try await catalog.saveRemoteService(RemoteServiceRecord(name: "Home", address: address.normalized,
                                                                              allowsUnencrypted: true))
        let keys = InMemoryKeyStore()
        try keys.setKey(FakeImmichServer.validKey, account: service.uuid)
        return Fixture(catalog: catalog, server: server, service: service, keys: keys)
    }

    // MARK: The import window (D-18)

    @Test("The import window's check: a rename connects and is taken; a new address, a certificate or a removal sends nothing (D-18)")
    func importCheckWithSavedRow() async throws {
        let f = try await Self.fixture()
        let held = f.service

        // A rename alone connects, and gives the row as saved.
        var renamed = held
        renamed.name = "Cellar"
        _ = try await f.catalog.saveRemoteService(renamed)
        guard case .ready(_, _, let saved) = await RemoteImportConnection.connect(held, catalog: f.catalog, keys: f.keys)
        else {
            Issue.record("a rename stopped the check")
            return
        }
        #expect(saved.name == "Cellar")
        #expect(saved.address == held.address)

        // The publish sheet's Edit Server… saves a new address with a new key.
        let moved = try await f.saveElsewhere()
        let before = f.server.requests.count
        let outcome = await RemoteImportConnection.connect(held, catalog: f.catalog, keys: f.keys)
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
        guard case .changed(.connectionChanged) = await RemoteImportConnection.connect(held, catalog: f.catalog,
                                                                                       keys: f.keys) else {
            Issue.record("a changed certificate was not refused")
            return
        }

        // Removed: nothing is sent.
        #expect(try await f.catalog.removeRemoteService(moved, keys: f.keys) == nil)
        guard case .changed(.removed) = await RemoteImportConnection.connect(held, catalog: f.catalog, keys: f.keys) else {
            Issue.record("a removed server was contacted")
            return
        }
        #expect(f.server.requests.count == before)
    }

    @Test("The import window's check waits for a Save's row and contacts nothing (D-18)")
    func importCheckWaitsForTheRow() async throws {
        let f = try await Self.fixture()
        let held = f.service
        let account = held.uuid
        let catalog = f.catalog
        let keys = f.keys
        let before = f.server.requests.count
        let finished = Flag()
        var moved = held
        moved.address = "https://photos.example.com"
        moved.allowsUnencrypted = false
        var check: Task<RemoteImportConnection, Never>?
        // As a Save does: the new key is in the store, the row not yet written.
        try await RemoteKeyGate.shared.holding(account) { () async throws in
            try keys.setKey(Self.newKey, account: account)
            check = Task {
                let outcome = await RemoteImportConnection.connect(held, catalog: catalog, keys: keys)
                finished.set()
                return outcome
            }
            while RemoteKeyGate.shared.waiters(account) == 0, !finished.isSet { await Task.yield() }
            #expect(!finished.isSet, "the check read the key while the Save was between its two writes")
            _ = try await catalog.saveRemoteService(moved)
        }
        guard case .changed(.connectionChanged)? = await check?.value else {
            Issue.record("paired")
            return
        }
        #expect(f.server.requests.count == before, "the previous address was contacted")
    }

    @Test("Following the saved server: a rename in place, another address or certificate chosen again, a removal left, nothing during an import (D-18)")
    func sourceFollowRule() {
        let held = RemoteServiceRecord(id: 1, name: "Home", address: "http://192.168.1.2:2283", allowsUnencrypted: true)
        #expect(RemoteSourceFollow.after(held: held, now: held, importing: false) == .none)
        #expect(RemoteSourceFollow.after(held: held, now: held, importing: true) == .none)

        var renamed = held
        renamed.name = "Cellar"
        #expect(RemoteSourceFollow.after(held: held, now: renamed, importing: false) == .takeSaved(renamed))

        var moved = held
        moved.address = "http://192.168.1.3:2283"
        #expect(RemoteSourceFollow.after(held: held, now: moved, importing: false) == .chooseAgain(moved))
        moved.name = "Cellar"
        #expect(RemoteSourceFollow.after(held: held, now: moved, importing: false) == .chooseAgain(moved))

        var pinned = held
        pinned.certificateFingerprint = String(repeating: "a", count: 64)
        pinned.certificateTrustedAt = Date(timeIntervalSince1970: 1)
        #expect(RemoteSourceFollow.after(held: held, now: pinned, importing: false) == .chooseAgain(pinned))

        #expect(RemoteSourceFollow.after(held: held, now: nil, importing: false) == .leave)

        for now in [renamed, moved, pinned] {
            #expect(RemoteSourceFollow.after(held: held, now: now, importing: true) == .afterImport)
        }
        #expect(RemoteSourceFollow.after(held: held, now: nil, importing: true) == .afterImport)
    }

    @Test("A rename taken while the import window's check is out is not undone by the check's older row (F30)")
    func checkKeepsARenameTakenMeanwhile() async throws {
        let f = try await Self.fixture()
        var shown = RemoteSourceRecord(f.service)
        let id = try #require(f.service.id)

        // The check begins: it notes the record and reads the row ("Home").
        let began = shown.revision
        guard case .ready(_, _, let checked) = await RemoteImportConnection.connect(shown.service, catalog: f.catalog,
                                                                                   keys: f.keys) else {
            Issue.record("the check failed")
            return
        }
        #expect(checked.name == "Home")

        // While it is out, Publish's Edit Server… saves a new name, and the
        // window takes it in place (`loadServersAfterPublish`).
        var renamed = try #require(try await f.catalog.remoteService(id: id))
        renamed.name = "Cellar"
        let cellar = try await f.catalog.saveRemoteService(renamed)
        #expect(RemoteSourceFollow.after(held: shown.service, now: cellar, importing: false) == .takeSaved(cellar))
        let tookCellar = shown.take(cellar)
        #expect(tookCellar)

        // The check returns with the row it read: the window keeps "Cellar".
        #expect(shown.afterCheck(began: began, saved: checked, importing: false) == .none)
        #expect(shown.service.name == "Cellar")

        // Renamed back to "Home" as well, and a check that began before both
        // read "Cellar" between them: the window's "Home" is newer and stays.
        var back = shown
        let tookBack = back.take(checked)
        #expect(tookBack)
        #expect(back.afterCheck(began: began, saved: cellar, importing: false) == .none)
        #expect(back.service.name == "Home")

        // No rename taken since the check began: a row read with a new name
        // is taken (the reconnect after an import), the same name is nothing,
        // and nothing is taken while an import runs.
        let now = shown.revision
        var other = renamed
        other.name = "Attic"
        #expect(shown.afterCheck(began: now, saved: other, importing: false) == .takeSaved(other))
        #expect(shown.afterCheck(began: now, saved: cellar, importing: false) == .none)
        #expect(shown.afterCheck(began: now, saved: other, importing: true) == .none)
        let tookOther = shown.take(other)
        #expect(tookOther)
        #expect(shown.revision == now + 1)
        let tookAgain = shown.take(other)
        #expect(!tookAgain, "the same name is no rename")
    }

    // MARK: The Server sheet (D-19)

    /// A sheet opened on `opened` and submitted with the key field empty: its
    /// form shows `opened`'s address, with a name typed.
    static func sheetRecord(_ opened: RemoteServiceRecord) -> RemoteServiceRecord {
        var record = opened
        record.name = "From the stale sheet"
        return record
    }

    static func runSheet(_ f: Fixture, opened: RemoteServiceRecord, enteredKey: String? = nil) async throws
        -> RemoteServerSheetCheck.Outcome {
        await RemoteServerSheetCheck.run(sheetRecord(opened), address: try #require(opened.serverAddress),
                                         enteredKey: enteredKey, pinned: opened.pinnedFingerprint,
                                         unencryptedConfirmed: true, requiring: ImmichClient.neededPermissions,
                                         readsAccount: true, opened: opened, catalog: f.catalog, keys: f.keys)
    }

    @Test("A sheet behind the saved server, key field empty: at the press the stored key is sent nowhere and nothing is written (D-19)")
    func sheetBehindAtPress() async throws {
        let f = try await Self.fixture()
        let opened = f.service
        let id = try #require(opened.id)
        let moved = try await f.saveElsewhere()
        let before = f.server.requests.count

        let outcome = try await Self.runSheet(f, opened: opened)
        guard case .changed(let now) = outcome else {
            Issue.record("not given up: \(outcome)")
            return
        }
        #expect(now.address == moved.address)
        #expect(f.server.requests.count == before, "the stored key went to the sheet's address")
        #expect(try await f.catalog.remoteService(id: id) == moved, "the sheet wrote its row")
        #expect(try f.keys.key(account: opened.uuid) == Self.newKey)

        // A certificate trusted in the other window alone is the same.
        var pinned = moved
        pinned.address = opened.address
        pinned.allowsUnencrypted = true
        pinned.certificateFingerprint = String(repeating: "c", count: 64)
        _ = try await f.catalog.saveRemoteService(pinned)
        guard case .changed = try await Self.runSheet(f, opened: opened) else {
            Issue.record("a changed certificate was not given up")
            return
        }
        #expect(f.server.requests.count == before)
        #expect(try await f.catalog.remoteService(id: id) == pinned)
    }

    @Test("A Save landing during the sheet's check: the row is not written over (D-19)")
    func sheetBehindAtSave() async throws {
        let f = try await Self.fixture()
        let opened = f.service
        let id = try #require(opened.id)
        let address = try #require(opened.serverAddress)
        guard case .key(let key) = await RemoteServerSheetCheck.key(entered: nil, opened: opened, catalog: f.catalog,
                                                                    keys: f.keys) else {
            Issue.record("no key")
            return
        }
        #expect(key == FakeImmichServer.validKey)
        let check = await RemoteServerSheetCheck.check(address: address, key: key, pinned: nil, unencryptedConfirmed: true,
                                                       requiring: ImmichClient.neededPermissions, readsAccount: true)
        guard case .passed = check.result else {
            Issue.record("the check failed: \(check.result)")
            return
        }
        // The other window's Save lands during the check.
        let moved = try await f.saveElsewhere()
        let outcome = await RemoteServerSheetCheck.save(Self.sheetRecord(opened), enteredKey: nil, checkedKey: key,
                                                        opened: opened, catalog: f.catalog, keys: f.keys)
        guard case .changed(let now) = outcome else {
            Issue.record("written: \(outcome)")
            return
        }
        #expect(now == moved)
        #expect(try await f.catalog.remoteService(id: id) == moved, "the sheet wrote its row")
        #expect(try f.keys.key(account: opened.uuid) == Self.newKey)
    }

    @Test("A new key alone saved during the sheet's check: the row is not written (D-19)")
    func sheetKeyChangedAtSave() async throws {
        let f = try await Self.fixture()
        let opened = f.service
        let id = try #require(opened.id)
        // The other window keeps the address and saves another key.
        try await f.saveElsewhere(address: opened.address, key: Self.newKey)
        let outcome = await RemoteServerSheetCheck.save(Self.sheetRecord(opened), enteredKey: nil,
                                                        checkedKey: FakeImmichServer.validKey, opened: opened,
                                                        catalog: f.catalog, keys: f.keys)
        guard case .changed(let now) = outcome else {
            Issue.record("written: \(outcome)")
            return
        }
        #expect(now.name == opened.name)
        #expect(try await f.catalog.remoteService(id: id)?.name == opened.name)
    }

    @Test("A sheet that is not behind saves as before; a typed key is saved with what the form shows (D-19)")
    func sheetUpToDateAndTypedKey() async throws {
        let f = try await Self.fixture()
        let opened = f.service
        guard case .saved(let saved) = try await Self.runSheet(f, opened: opened) else {
            Issue.record("not saved")
            return
        }
        #expect(saved.name == "From the stale sheet")
        #expect(try f.keys.key(account: opened.uuid) == FakeImmichServer.validKey)

        // A typed key: the key and what the form shows are saved together,
        // whatever the other window saved meanwhile (the last save wins).
        _ = try await f.saveElsewhere()
        guard case .saved(let typed) = try await Self.runSheet(f, opened: opened, enteredKey: FakeImmichServer.validKey) else {
            Issue.record("a typed key was not saved")
            return
        }
        #expect(typed.address == opened.address)
        #expect(try f.keys.key(account: opened.uuid) == FakeImmichServer.validKey)
    }

    @Test("Removed during the sheet's check: nothing is written and no key is left (D-16, D-19)")
    func sheetRemovedAtSave() async throws {
        let f = try await Self.fixture()
        let opened = f.service
        #expect(try await f.catalog.removeRemoteService(opened, keys: f.keys) == nil)
        guard case .removed = await RemoteServerSheetCheck.save(Self.sheetRecord(opened), enteredKey: nil,
                                                                checkedKey: FakeImmichServer.validKey, opened: opened,
                                                                catalog: f.catalog, keys: f.keys) else {
            Issue.record("not removed")
            return
        }
        #expect(try await f.catalog.remoteServices().isEmpty)
        #expect(try f.keys.key(account: opened.uuid) == nil)
    }

    @Test("The sheet's guarded save reads the key and writes the row with the account's gate held (D-19)")
    func sheetSaveHoldsTheGate() async throws {
        let catalog = try Catalog.makeInMemory()
        let keys = ReadHookKeyStore()
        let opened = try await catalog.saveRemoteService(RemoteServiceRecord(name: "Home", address: "https://a.example"))
        try keys.inner.setKey("k", account: opened.uuid)
        let seen = Mutex<[Bool]>([])
        keys.onRead = { seen.withLock { $0.append(RemoteKeyGate.shared.isHeld(opened.uuid)) } }
        var record = opened
        record.name = "Renamed"
        guard case .saved = await catalog.saveRemoteService(record, checkedWith: "k", opened: opened, keys: keys) else {
            Issue.record("not saved")
            return
        }
        #expect(seen.withLock { $0 } == [true])
        #expect(!RemoteKeyGate.shared.isHeld(opened.uuid))
    }
}

/// Set once, read from any task.
private final class Flag: Sendable {
    private let value = Mutex(false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}

/// A key store that runs a step as a key is read.
private final class ReadHookKeyStore: RemoteKeyStore {
    let inner = InMemoryKeyStore()
    private let hook = Mutex<(@Sendable () -> Void)?>(nil)

    var onRead: (@Sendable () -> Void)? {
        get { hook.withLock { $0 } }
        set { hook.withLock { $0 = newValue } }
    }

    func key(account: String) throws(RemoteKeyStoreError) -> String? {
        onRead?()
        return try inner.key(account: account)
    }

    func setKey(_ key: String, account: String) throws(RemoteKeyStoreError) { try inner.setKey(key, account: account) }

    func deleteKey(account: String) throws(RemoteKeyStoreError) { try inner.deleteKey(account: account) }
}
