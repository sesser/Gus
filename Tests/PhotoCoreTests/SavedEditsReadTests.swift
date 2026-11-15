import Foundation
import Testing
@testable import PhotoCore

/// Opens once: everything waiting goes on, and later waits return at once.
@MainActor
private final class SaveGate {
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

/// The reads that take a photo's saved edits for a command or a display
/// (reads-beside-write-chain, issue #64): Copy Adjustments and Save as
/// Preset from the grid (`savedAdjustments`), batch Auto Exposure's and a
/// measuring paste's measurement (`savedEditStacks`), the preset previews'
/// base and the offline machine learning badge (`savedAdjustments`).
///
/// Each test queues a change behind a held write, as a batch paste waits
/// behind an earlier save, then starts the read and lets the writes go. The
/// tests are deterministic without sleeps: a task runs on the main actor
/// until it suspends, so when a test resumes from `started` the read has
/// either been sent to the catalog (beside the chain: it can only see the
/// row from before the held change) or is waiting for the chain (it sees the
/// change). Only a read beside the chain fails them.
@MainActor
@Suite("Saved edits read after pending saves")
struct SavedEditsReadTests {
    private static func stored(_ catalog: Catalog, _ versionID: Int64) async throws -> Adjustments {
        Adjustments(stack: try await catalog.version(id: versionID)?.decodedEditStack() ?? .identity)
    }

    /// Queues `transform` of each version's adjustments on `chain`, as
    /// `LibraryModel.changeAdjustments` does (paste, a preset).
    private static func change(_ ids: [Int64], in catalog: Catalog, on chain: WriteChain,
                               _ transform: @escaping @Sendable (Adjustments) -> Adjustments) {
        chain.enqueue {
            do {
                _ = try await catalog.changeEditStacks(ofVersions: ids, historyLabel: "Test", transform)
            } catch {
                Issue.record(error)
            }
        }
    }

    @Test("Copy right after a paste copies the pasted values, and the next paste gives them on")
    func copyAfterPasteCopiesThePaste() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let (source, target) = (ids[0], ids[2])
        let chain = WriteChain()
        let slow = SaveGate()
        let started = SaveGate()
        var clipboard = Adjustments()
        clipboard.exposure.ev = 1.5
        clipboard.tone.contrast = 20
        let pasted = clipboard
        // Paste onto the source photo, its write behind a slower one.
        chain.enqueue { await slow.wait() }
        Self.change([source], in: catalog, on: chain) { pasted.pasted(onto: $0) }
        // Copy Adjustments from it before the paste's write lands (`copyAdjustments`).
        let copy = Task {
            started.open()
            return try await chain.savedAdjustments(ofVersion: source, in: catalog)
        }
        await started.wait()
        slow.open()
        let copied = try await copy.value
        #expect(copied.exposure.ev == 1.5)
        #expect(copied.tone.contrast == 20)
        // The next paste gives another photo the values the person saw.
        Self.change([target], in: catalog, on: chain) { copied.pasted(onto: $0) }
        _ = await chain.settled()
        let result = try await Self.stored(catalog, target)
        #expect(result.exposure.ev == 1.5)
        #expect(result.tone.contrast == 20)
    }

    @Test("Save as Preset right after a change saves the changed values")
    func saveAsPresetAfterAChangeSavesIt() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let versionID = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        let chain = WriteChain()
        let slow = SaveGate()
        let started = SaveGate()
        chain.enqueue { await slow.wait() }
        Self.change([versionID], in: catalog, on: chain) { values in
            var values = values
            values.exposure.ev = -0.7
            return values
        }
        // Save Adjustments as Preset… from the grid (`focusedAdjustments`).
        let read = Task {
            started.open()
            return try await chain.savedAdjustments(ofVersion: versionID, in: catalog)
        }
        await started.wait()
        slow.open()
        let values = try await read.value
        let preset = AdjustmentPreset(name: "Test", groups: values.modifiedGroups, adjustments: values)
        _ = try await catalog.saveAdjustmentPreset(preset)
        let saved = try #require(try await catalog.adjustmentPresets().first)
        #expect(saved.adjustments.exposure.ev == -0.7)
        #expect(saved.groups.contains(.light))
    }

    @Test("A batch measurement reads every photo's stack after a pending change")
    func batchMeasurementReadsAfterAPendingChange() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let chain = WriteChain()
        let slow = SaveGate()
        let started = SaveGate()
        chain.enqueue { await slow.wait() }
        Self.change(ids, in: catalog, on: chain) { values in
            var values = values
            values.tone.highlights = -40
            return values
        }
        // Auto Exposure (or a measuring paste) on the selection, before the change lands.
        let read = Task {
            started.open()
            return try await chain.savedEditStacks(forVersions: ids, in: catalog)
        }
        await started.wait()
        slow.open()
        let stored = try await read.value
        #expect(stored.stacks.count == 3)
        #expect(stored.unreadable.isEmpty)
        for id in ids {
            let stack = try #require(stored.stacks[id])
            #expect(Adjustments(stack: stack).tone.highlights == -40)
        }
    }

    @Test("The offline badge reads machine learning from a stack whose save is pending")
    func offlineBadgeReadsAPendingSave() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let versionID = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        let chain = WriteChain()
        let slow = SaveGate()
        let started = SaveGate()
        chain.enqueue { await slow.wait() }
        Self.change([versionID], in: catalog, on: chain) { values in
            var values = values
            values.noiseReduction.machineLearning = true
            return values
        }
        // `AdjustmentEditor.loadOfflineMachineLearning`, and the preset previews' base.
        let read = Task {
            started.open()
            return try await chain.savedAdjustments(ofVersion: versionID, in: catalog)
        }
        await started.wait()
        slow.open()
        let values = try await read.value
        #expect(values.asksForMachineLearning)
    }

    @Test("A read waits for a change queued while it waits, and reads it")
    func readWaitsForChangesQueuedWhileWaiting() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let versionID = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        let chain = WriteChain()
        let slow = SaveGate()
        let started = SaveGate()
        chain.enqueue { await slow.wait() }
        let read = Task {
            started.open()
            return try await chain.savedAdjustments(ofVersion: versionID, in: catalog)
        }
        await started.wait()
        // Queued after the read started, while it waits behind the held write.
        Self.change([versionID], in: catalog, on: chain) { values in
            var values = values
            values.exposure.ev = 2
            return values
        }
        slow.open()
        #expect(try await read.value.exposure.ev == 2)
    }

    @Test("Stacks this build can't read are reported, not read as the defaults")
    func unreadableStacksAreReported() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters((1...2).map { CatalogFixture.master($0) })
        try await catalog.database.write { db in
            try db.execute(sql: "UPDATE version SET editStack = ? WHERE id = ?",
                           arguments: [#"{"operations":[{"future":true}],"schemaVersion":99}"#, ids[0]])
        }
        let chain = WriteChain()
        await #expect(throws: (any Error).self) {
            _ = try await chain.savedAdjustments(ofVersion: ids[0], in: catalog)
        }
        let stored = try await chain.savedEditStacks(forVersions: ids, in: catalog)
        #expect(stored.unreadable.keys.sorted() == [ids[0]])
        #expect(stored.stacks.keys.sorted() == [ids[1]])
    }

    @Test("A cancelled read throws and returns nothing")
    func cancelledReadThrows() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let versionID = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        let chain = WriteChain()
        let slow = SaveGate()
        let started = SaveGate()
        chain.enqueue { await slow.wait() }
        let read = Task {
            started.open()
            return try await chain.savedAdjustments(ofVersion: versionID, in: catalog)
        }
        await started.wait()
        read.cancel()
        slow.open()
        await #expect(throws: CancellationError.self) { _ = try await read.value }
    }
}
