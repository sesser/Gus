import Foundation
import Testing
@testable import PhotoCore

/// Opens once: everything waiting goes on, and later waits return at once.
@MainActor
private final class Latch {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        let resumed = waiting
        waiting = []
        for continuation in resumed { continuation.resume() }
    }
}

/// What the catalog holds and what the window shows, for the model tests.
@MainActor
private final class Store {
    var saved: Set<String> = []
    var savedHash = "old"
    var shownHash = "old"
    var savedRating = 0
    var shownRating = 0
    var fetches = 0
    var order: [Int] = []
}

/// The ordering rule for reads beside the window's write chain
/// (editor-follow-edit-drop, reload-items-stale-hash).
///
/// The tests are deterministic without sleeps: a task runs on the main actor
/// until it suspends, so when a test resumes from a gate the task that opened
/// it has either finished its read or is waiting for the chain. Each test
/// passes whichever of those happened; only a read that ignores the chain
/// can fail it.
@MainActor
@Suite("Reads ordered with the write chain")
struct WriteChainTests {
    @Test("Writes run in the order they were queued, each after the last has finished")
    func writesRunInOrder() async {
        let chain = WriteChain()
        let store = Store()
        let gate = Latch()
        chain.enqueue { await gate.wait(); store.order.append(1) }
        chain.enqueue { store.order.append(2) }
        chain.enqueue { store.order.append(3) }
        #expect(chain.queuedCount == 3)
        #expect(store.order.isEmpty)
        gate.open()
        _ = await chain.settled()
        #expect(store.order == [1, 2, 3])
    }

    @Test("A read started while a save is queued sees that save (editor-follow-edit-drop)")
    func readWaitsForQueuedWrites() async throws {
        let chain = WriteChain()
        let store = Store()
        let slow = Latch()
        let started = Latch()
        // The save made before leaving the photo, queued behind a slower write.
        chain.enqueue { await slow.wait() }
        chain.enqueue { store.saved = ["exposure"] }
        // Back on the photo: the editor loads its stack.
        let load = Task { () throws -> Set<String> in
            started.open()
            return try await chain.read({ store.saved }, apply: { _ in })
        }
        await started.wait()
        slow.open()
        let loaded = try await load.value
        #expect(loaded == ["exposure"])
        // The next change is saved on top of what was loaded.
        chain.enqueue { store.saved = loaded.union(["contrast"]) }
        _ = await chain.settled()
        #expect(store.saved == ["exposure", "contrast"])
    }

    @Test("A reload that read before an edit's save lands reads again (reload-items-stale-hash)")
    func readOvertakenByAWriteReadsAgain() async throws {
        let chain = WriteChain()
        let store = Store()
        let fetched = Latch()
        let resume = Latch()
        let landed = Latch()
        let reload = Task {
            try await chain.read({ () async -> String in
                let hash = store.savedHash
                store.fetches += 1
                fetched.open()
                await resume.wait()
                return hash
            }, apply: { store.shownHash = $0 })
        }
        await fetched.wait()
        // The editor saves; the new hash is shown once the write has landed.
        chain.enqueue {
            store.savedHash = "new"
            store.shownHash = "new"
            landed.open()
        }
        await landed.wait()
        resume.open()
        _ = try await reload.value
        #expect(store.shownHash == "new")
        #expect(store.fetches == 2)
    }

    @Test("A change shown before its write survives a read already in flight")
    func optimisticChangeSurvivesARead() async throws {
        let chain = WriteChain()
        let store = Store()
        let fetched = Latch()
        let resume = Latch()
        let reload = Task {
            try await chain.read({ () async -> Int in
                let rating = store.savedRating
                fetched.open()
                await resume.wait()
                return rating
            }, apply: { store.shownRating = $0 })
        }
        await fetched.wait()
        // Culling: shown at once, then saved.
        store.shownRating = 3
        chain.enqueue { store.savedRating = 3 }
        resume.open()
        _ = try await reload.value
        #expect(store.shownRating == 3)
    }

    @Test("A cancelled read applies nothing")
    func cancelledReadAppliesNothing() async {
        let chain = WriteChain()
        let store = Store()
        let fetched = Latch()
        let resume = Latch()
        let reload = Task {
            try await chain.read({ () async -> String in
                fetched.open()
                await resume.wait()
                return "new"
            }, apply: { store.shownHash = $0 })
        }
        await fetched.wait()
        reload.cancel()
        resume.open()
        await #expect(throws: CancellationError.self) { try await reload.value }
        #expect(store.shownHash == "old")
    }

    @Test("A failed read applies nothing and passes the error on")
    func failedReadAppliesNothing() async {
        struct Failure: Error {}
        let chain = WriteChain()
        let store = Store()
        await #expect(throws: Failure.self) {
            try await chain.read({ () throws -> String in throw Failure() }, apply: { store.shownHash = $0 })
        }
        #expect(store.shownHash == "old")
    }

    // MARK: With a catalog

    private static func values(_ catalog: Catalog, _ versionID: Int64) async throws -> Adjustments {
        Adjustments(stack: try await catalog.version(id: versionID)?.decodedEditStack() ?? .identity)
    }

    @Test("Coming back to a photo before its save lands keeps that edit (editor-follow-edit-drop)")
    func returningBeforeTheSaveLandsKeepsTheEdit() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let versionID = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        let chain = WriteChain()
        let slow = Latch()
        let started = Latch()
        var first = Adjustments()
        first.exposure.ev = 1
        let firstStack = first.editStack
        // The commit made before leaving the photo, behind a slower write.
        chain.enqueue { await slow.wait() }
        chain.enqueue {
            do { try await catalog.setEditStack(firstStack, forVersion: versionID) } catch { Issue.record(error) }
        }
        // Back on the photo: the editor loads its stack (`AdjustmentEditor.follow`).
        let load = Task {
            started.open()
            return try await chain.read({ try await Self.values(catalog, versionID) }, apply: { _ in })
        }
        await started.wait()
        slow.open()
        var next = try await load.value
        #expect(next.exposure.ev == 1)
        // A change made then is saved on top of what was loaded.
        next.tone.contrast = 20
        let nextStack = next.editStack
        chain.enqueue {
            do { try await catalog.setEditStack(nextStack, forVersion: versionID) } catch { Issue.record(error) }
        }
        _ = await chain.settled()
        let saved = try await Self.values(catalog, versionID)
        #expect(saved.exposure.ev == 1)
        #expect(saved.tone.contrast == 20)
    }

    @Test("A reload that read the row before an edit's save does not show the old hash (reload-items-stale-hash)")
    func reloadDoesNotPutTheOldHashBack() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let versionID = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        let chain = WriteChain()
        let store = Store()
        store.shownHash = EditStack.identity.renderHash
        let fetched = Latch()
        let resume = Latch()
        let landed = Latch()
        var edit = Adjustments()
        edit.exposure.ev = 1.5
        let editStack = edit.editStack
        // `LibraryModel.reloadItems`: the rows are read, then shown.
        let reload = Task {
            try await chain.read({ () async throws -> [CatalogItem] in
                let items = try await catalog.libraryItems(matching: LibraryFilter())
                fetched.open()
                await resume.wait()
                return items
            }, apply: { items in
                if let item = items.first(where: { $0.versionID == versionID }) { store.shownHash = item.editStackHash }
            })
        }
        await fetched.wait()
        // The editor commits; its hash is shown once the write has landed (`showSaved`).
        chain.enqueue {
            do {
                try await catalog.setEditStack(editStack, forVersion: versionID)
                store.shownHash = editStack.renderHash
            } catch {
                Issue.record(error)
            }
            landed.open()
        }
        await landed.wait()
        #expect(store.shownHash == editStack.renderHash)
        resume.open()
        _ = try await reload.value
        #expect(store.shownHash == editStack.renderHash)
    }
}
