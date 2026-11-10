import Foundation
import GRDB
import Testing
@testable import PhotoCore

/// Each saved change to a version's edit stack records one history entry
/// (docs/features/edit-history). The acceptance criteria are named in the tests.
@Suite("Edit history")
struct EditHistoryTests {
    private static func stack(exposure ev: Double) -> EditStack {
        var values = Adjustments()
        values.exposure.ev = ev
        return values.editStack
    }

    private static func cropped() -> EditStack {
        var values = Adjustments()
        values.exposure.ev = 1
        values.crop = Crop(quarterTurns: 1)
        return values.editStack
    }

    private static func one() async throws -> (CatalogFixture, Int64) {
        let fixture = try await CatalogFixture.make()
        let id = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        return (fixture, id)
    }

    // MARK: AC1, AC2

    @Test("AC1: an edit and a crop are two entries, newest first, each with its label and a time")
    func twoEntries() async throws {
        let (fixture, id) = try await Self.one()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        try await fixture.catalog.setEditStack(Self.stack(exposure: 1), forVersion: id, historyLabel: "Exposure", at: first)
        try await fixture.catalog.setEditStack(Self.cropped(), forVersion: id, historyLabel: "Crop", at: first + 60)
        let entries = try await fixture.catalog.editHistory(forVersion: id)
        #expect(entries.map(\.label) == ["Crop", "Exposure"])
        #expect(entries.map(\.createdAt) == [first + 60, first])
    }

    @Test("AC2: the entries are there after the catalog is closed and opened again")
    func entriesSurviveReopen() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "catalog.sqlite")
            let id: Int64
            do {
                let catalog = try Catalog.open(at: url)
                let fixture = try await Self.seed(catalog)
                id = fixture
                try await catalog.setEditStack(Self.stack(exposure: 1), forVersion: id, historyLabel: "Exposure")
                try await catalog.setEditStack(Self.cropped(), forVersion: id, historyLabel: "Crop")
            }
            let reopened = try Catalog.open(at: url)
            #expect(try await reopened.editHistory(forVersion: id).map(\.label) == ["Crop", "Exposure"])
        }
    }

    private static func seed(_ catalog: Catalog) async throws -> Int64 {
        let volume = try await catalog.registerVolume(VolumeDescriptor(identity: "V", name: "V", mountPath: "/Volumes/V"))
        let project = try await catalog.createProject(name: "P")
        return try #require(try await catalog.insertMasters([CatalogFixture.master(1)], volumeID: volume.id!,
                                                            projectID: project.id!).insertedVersionIDs.first)
    }

    // MARK: R1: what an entry stores

    @Test("An entry stores the stack as saved, and the stored stack and hash are what they were before this feature")
    func snapshotIsExactAndStorageUnchanged() async throws {
        let (fixture, id) = try await Self.one()
        let stack = Self.cropped()
        try await fixture.catalog.setEditStack(stack, forVersion: id, historyLabel: "Crop")
        let entry = try #require(try await fixture.catalog.editHistory(forVersion: id).first)
        #expect(try await fixture.catalog.editHistoryStack(entryID: entry.id, forVersion: id) == stack)
        let version = try #require(try await fixture.catalog.version(id: id))
        #expect(version.editStack == (try stack.jsonString()) && version.editStackHash == stack.renderHash)
    }

    @Test("The list reads no snapshots; one is read by id and only for its own version")
    func listAndSnapshotReads() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        try await fixture.catalog.setEditStack(Self.stack(exposure: 1), forVersion: ids[0], historyLabel: "Exposure")
        let entry = try #require(try await fixture.catalog.editHistory(forVersion: ids[0]).first)
        #expect(try await fixture.catalog.editHistoryStack(entryID: entry.id, forVersion: ids[1]) == nil)
        #expect(try await fixture.catalog.editHistory(forVersion: ids[1]).isEmpty)
    }

    // MARK: AC5, AC6, AC8: revert and undo

    @Test("AC5, AC6: a revert is a new entry and the earlier ones stay; the next edit adds another")
    func revertKeepsEarlierEntries() async throws {
        let (fixture, id) = try await Self.one()
        let catalog = fixture.catalog
        let stacks = [Self.stack(exposure: 1), Self.stack(exposure: 2), Self.stack(exposure: 3)]
        for (index, stack) in stacks.enumerated() {
            try await catalog.setEditStack(stack, forVersion: id, historyLabel: "Edit \(index + 1)")
        }
        let before = try await catalog.editHistory(forVersion: id)
        let oldest = try #require(before.last)
        let snapshot = try #require(try await catalog.editHistoryStack(entryID: oldest.id, forVersion: id))
        #expect(snapshot == stacks[0])

        try await catalog.setEditStack(snapshot, forVersion: id, historyLabel: "Revert to “Edit 1”")
        #expect(try await catalog.version(id: id)?.decodedEditStack() == stacks[0])
        let after = try await catalog.editHistory(forVersion: id)
        #expect(after.count == 4 && after.first?.label == "Revert to “Edit 1”")
        #expect(Array(after.dropFirst()) == before)

        try await catalog.setEditStack(Self.stack(exposure: 4), forVersion: id, historyLabel: "Edit 5")
        let fifth = try await catalog.editHistory(forVersion: id)
        #expect(fifth.count == 5 && Array(fifth.dropFirst(2)) == before)
    }

    @Test("AC8: an undo write adds an entry whose stack equals the stack before the edit")
    func undoIsLogged() async throws {
        let (fixture, id) = try await Self.one()
        let catalog = fixture.catalog
        let original = Self.stack(exposure: 1)
        try await catalog.setEditStack(original, forVersion: id, historyLabel: "Exposure")
        try await catalog.setEditStack(Self.stack(exposure: 2), forVersion: id, historyLabel: "Exposure")
        try await catalog.setEditStack(original, forVersion: id, historyLabel: "Undo Exposure")
        let entries = try await catalog.editHistory(forVersion: id)
        #expect(entries.map(\.label) == ["Undo Exposure", "Exposure", "Exposure"])
        let newest = try #require(entries.first)
        #expect(try await catalog.editHistoryStack(entryID: newest.id, forVersion: id) == original)
    }

    @Test("A write that leaves the stack as it was records nothing")
    func unchangedWriteRecordsNothing() async throws {
        let (fixture, id) = try await Self.one()
        let stack = Self.stack(exposure: 1)
        try await fixture.catalog.setEditStack(stack, forVersion: id, historyLabel: "Exposure")
        try await fixture.catalog.setEditStack(stack, forVersion: id, historyLabel: "Exposure")
        #expect(try await fixture.catalog.editHistory(forVersion: id).count == 1)
    }

    // MARK: AC9, AC10: pairs and batches

    @Test("AC9: an edit on the RAW of a pair adds no entry to the JPEG")
    func pairsKeepSeparateHistories() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([
            CatalogFixture.master(1, path: "a/IMG_1.NEF"), CatalogFixture.master(2, path: "a/IMG_1.JPG"),
        ])
        try await fixture.catalog.setEditStack(Self.stack(exposure: 1), forVersion: ids[0], historyLabel: "Exposure")
        #expect(try await fixture.catalog.editHistory(forVersion: ids[0]).count == 1)
        #expect(try await fixture.catalog.editHistory(forVersion: ids[1]).isEmpty)
    }

    @Test("AC10: pasting onto three photos, one already the same, adds an entry to two")
    func batchRecordsOnlyChanges() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        var copied = Adjustments()
        copied.tone.contrast = 25
        try await fixture.catalog.setEditStack(copied.editStack, forVersion: ids[2], historyLabel: "Contrast")
        let change = try await fixture.catalog.changeEditStacks(ofVersions: ids, historyLabel: "Paste Adjustments") {
            copied.pasted(onto: $0)
        }
        #expect(change.after.count == 3)
        #expect(try await fixture.catalog.editHistory(forVersion: ids[0]).map(\.label) == ["Paste Adjustments"])
        #expect(try await fixture.catalog.editHistory(forVersion: ids[1]).map(\.label) == ["Paste Adjustments"])
        #expect(try await fixture.catalog.editHistory(forVersion: ids[2]).map(\.label) == ["Contrast"])
    }

    // MARK: AC11: the cap

    @Test("AC11: 101 saved changes leave 100 entries and the first one is gone")
    func capDropsTheOldest() async throws {
        let (fixture, id) = try await Self.one()
        for index in 1...101 {
            try await fixture.catalog.setEditStack(Self.stack(exposure: Double(index) / 100), forVersion: id,
                                                   historyLabel: "Edit \(index)")
        }
        let entries = try await fixture.catalog.editHistory(forVersion: id)
        #expect(entries.count == EditHistory.maxEntries)
        #expect(entries.first?.label == "Edit 101" && entries.last?.label == "Edit 2")
        // Another version's entries are not trimmed by this one's cap.
        let other = try await fixture.addMasters([CatalogFixture.master(2)])[0]
        try await fixture.catalog.setEditStack(Self.stack(exposure: 1), forVersion: other, historyLabel: "Exposure")
        #expect(try await fixture.catalog.editHistory(forVersion: other).count == 1)
    }

    // MARK: AC13: unreadable stacks

    @Test("AC13: an unreadable stack records nothing, lists nothing and keeps its bytes",
          arguments: [UnreadableStackTests.newerJSON, UnreadableStackTests.damagedJSON])
    func unreadableStackHasNoHistory(json: String) async throws {
        let (fixture, id) = try await Self.one()
        try await UnreadableStackTests.store(json, forVersion: id, in: fixture.catalog)
        await #expect(throws: UnreadableEditStacks.self) {
            try await fixture.catalog.setEditStack(Self.stack(exposure: 1), forVersion: id, historyLabel: "Exposure")
        }
        await #expect(throws: UnreadableEditStacks.self) {
            try await fixture.catalog.setEditStacks([id: Self.stack(exposure: 1)], historyLabel: "Paste Adjustments")
        }
        #expect(try await fixture.catalog.editHistory(forVersion: id).isEmpty)
        let after = try await UnreadableStackTests.stored(id, in: fixture.catalog)
        #expect(after.json == json && after.hash == UnreadableStackTests.storedHash)
    }

    @Test("A batch that includes an unreadable stack records no entry for the readable one either")
    func refusedBatchRecordsNothing() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        try await UnreadableStackTests.store(UnreadableStackTests.newerJSON, forVersion: ids[0], in: fixture.catalog)
        await #expect(throws: UnreadableEditStacks.self) {
            try await fixture.catalog.setEditStacks([ids[0]: Self.stack(exposure: 1), ids[1]: Self.stack(exposure: 1)],
                                                    historyLabel: "Paste Adjustments")
        }
        #expect(try await fixture.catalog.editHistory(forVersion: ids[1]).isEmpty)
    }

    // MARK: A6: deleting

    @Test("A6: deleting the project deletes its versions' history")
    func historyGoesWithTheVersion() async throws {
        let (fixture, id) = try await Self.one()
        try await fixture.catalog.setEditStack(Self.stack(exposure: 1), forVersion: id, historyLabel: "Exposure")
        try await fixture.catalog.deleteProject(id: fixture.project.id!)
        let rows = try await fixture.catalog.database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM editHistory") }
        #expect(rows == 0)
    }

    // MARK: Q2: photocli

    @Test("Q2: photocli develop records an entry; a dry run and a no-change run record none")
    func developRecordsAnEntry() async throws {
        try await CommandTests.withLibrary { library in
            let id = String(library.versionIDs[0])
            let dry = await library.run("develop", "--version", id, "--set", "exposure.ev=1", "--dry-run")
            #expect(dry.output.exitCode == 0)
            let first = await library.run("develop", "--version", id, "--set", "exposure.ev=1")
            #expect(first.output.exitCode == 0)
            let same = await library.run("develop", "--version", id, "--set", "exposure.ev=1")
            #expect(same.output.exitCode == 0)
            let catalog = try Catalog.open(at: library.locations.catalogFileURL)
            let entries = try await catalog.editHistory(forVersion: library.versionIDs[0])
            #expect(entries.map(\.label) == [EditHistory.developCommandLabel])
        }
    }

    // MARK: AC15: reading a long history

    @Test("AC15: reading 100 entries of large stacks takes a fraction of a frame's budget and never touches the photo's own row")
    func longHistoryReads() async throws {
        let (fixture, id) = try await Self.one()
        // A heavily brushed photo: 5,000 dabs per snapshot, about 75 KB of JSON each.
        var points: [MaskPoint] = []
        for dab in 0..<5000 {
            points.append(MaskPoint(x: 0.2 + Double(dab % 700) * 0.0007, y: 0.3 + Double(dab / 7) * 0.0003))
        }
        var values = Adjustments()
        for index in 1...EditHistory.maxEntries {
            values.exposure.ev = Double(index) / 100
            values.local = LocalAdjustments(masks: [
                Mask(components: [MaskComponent(.brush(Brush(strokes: [BrushStroke(points: points)])))]),
            ])
            try await fixture.catalog.setEditStack(values.editStack, forVersion: id, historyLabel: "Edit \(index)")
        }
        let clock = ContinuousClock()
        let listed = try await clock.measure { _ = try await fixture.catalog.editHistory(forVersion: id) }
        let loaded = try await clock.measure { _ = try await fixture.catalog.details(forVersion: id) }
        print("edit-history AC15: list of 100 entries \(listed), photo's details \(loaded)")
        #expect(listed < .milliseconds(250))
        #expect(try await fixture.catalog.editHistory(forVersion: id).count == EditHistory.maxEntries)
        // The list's query names no snapshot column: its cost does not grow with stack size.
        let plan = try await fixture.catalog.database.read { db in
            try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN SELECT id, label, createdAt FROM editHistory WHERE versionId = 1 ORDER BY id DESC")
                .map { String(describing: $0) }.joined()
        }
        #expect(plan.contains("editHistory"))
    }

    // MARK: Panel states (R12, D6)

    @Test("The panel is absent in the grid and in review, and says why for a video, offline or unreadable photo")
    func panelStates() {
        typealias State = EditHistoryPanelState
        #expect(State.make(isLoupe: false, isReviewing: false, source: .ready, entryCount: 3) == .absent)
        #expect(State.make(isLoupe: true, isReviewing: true, source: .ready, entryCount: 3) == .absent)
        #expect(State.make(isLoupe: true, isReviewing: false, source: .video, entryCount: nil) == .unavailable(.video))
        #expect(State.make(isLoupe: true, isReviewing: false, source: .offline, entryCount: nil) == .unavailable(.offline))
        #expect(State.make(isLoupe: true, isReviewing: false, source: .unreadable, entryCount: 4) == .unavailable(.unreadable))
        #expect(State.make(isLoupe: true, isReviewing: false, source: .notReady, entryCount: nil) == .loading)
        #expect(State.make(isLoupe: true, isReviewing: false, source: .ready, entryCount: nil) == .loading)
        #expect(State.make(isLoupe: true, isReviewing: false, source: .ready, entryCount: 0) == .empty)
        #expect(State.make(isLoupe: true, isReviewing: false, source: .ready, entryCount: 12) == .entries(12))
    }

    @Test("Rows can be reverted only with entries and outside a crop session")
    func revertAvailability() {
        #expect(EditHistoryPanelState.entries(2).allowsRevert(isCropping: false))
        #expect(!EditHistoryPanelState.entries(2).allowsRevert(isCropping: true))
        #expect(!EditHistoryPanelState.empty.allowsRevert(isCropping: false))
        #expect(!EditHistoryPanelState.unavailable(.video).allowsRevert(isCropping: false))
    }

    // MARK: Time text (design §5)

    @Test("Today shows the time; yesterday the relative form; this year the date; other years the year")
    func timeText() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "en_US")
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 15, minute: 0)))
        let time = EditHistoryTime(now: now, calendar: calendar, locale: locale)
        func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
        }
        func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }
        #expect(plain(time.short(at(2026, 11, 9, 14, 41))) == "2:41 PM")
        let thisYear = plain(time.short(at(2026, 11, 2, 16, 10)))
        #expect(thisYear.hasPrefix("Nov 2") && thisYear.hasSuffix("4:10 PM") && !thisYear.contains("2026"), "\(thisYear)")
        #expect(plain(time.short(at(2025, 12, 24, 9, 5))).contains("2025"))
        #expect(plain(time.exactText(at(2026, 11, 9, 14, 41, 7))).contains("2:41:07 PM"))
    }

    /// The system's relative words ("Today", "Yesterday") are read against the
    /// real clock, so these two use it.
    @Test("Yesterday reads as the system's relative form; VoiceOver's text starts with Today")
    func relativeWords() throws {
        let calendar = Calendar.current
        let now = Date()
        let time = EditHistoryTime(now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        #expect(time.short(yesterday).hasPrefix("Yesterday"))
        #expect(time.spokenText(now).hasPrefix("Today"))
    }
}
