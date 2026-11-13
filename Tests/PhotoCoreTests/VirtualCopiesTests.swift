import CoreGraphics
import Foundation
import GRDB
import ImageIO
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Copies of a photo made with File ▸ Duplicate
/// (docs/features/virtual-copies/prd.md, AC1–AC9; design.md §12, V3–V10).
@Suite("Virtual copies")
struct VirtualCopiesTests {
    // MARK: Helpers

    private static func stack(exposure: Double) -> EditStack {
        var values = Adjustments()
        values.exposure.ev = exposure
        return values.editStack
    }

    private static func count(_ catalog: Catalog, _ sql: String, _ arguments: StatementArguments = []) async throws -> Int {
        try await catalog.database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM " + sql, arguments: arguments) ?? 0 }
    }

    private static func master(_ path: String, _ index: Int) -> NewMaster {
        CatalogFixture.master(index, hash: String(format: "%064x", index), path: path)
    }

    private static func items(_ catalog: Catalog, sort: LibrarySort = LibrarySort(), grouped: Bool = true) async throws -> [CatalogItem] {
        try await catalog.libraryItems(matching: LibraryFilter(sort: sort, groupsPairs: grouped))
    }

    /// What the catalog holds for a version, to compare before and after.
    private struct Snapshot: Equatable {
        var record: VersionRecord?
        var keywords: [String]
        var albums: [Int64]
        var history: [EditHistoryEntry]
        var historyStacks: [Data]

        init(_ catalog: Catalog, versionID: Int64) async throws {
            record = try await catalog.version(id: versionID)
            keywords = try await catalog.keywords(forVersion: versionID).map(\.name)
            (albums, historyStacks) = try await catalog.database.read { db in
                (try Int64.fetchAll(db, sql: "SELECT albumId FROM albumMember WHERE versionId = ? ORDER BY albumId",
                                    arguments: [versionID]),
                 try Data.fetchAll(db, sql: "SELECT stack FROM editHistory WHERE versionId = ? ORDER BY id",
                                   arguments: [versionID]))
            }
            history = try await catalog.editHistory(forVersion: versionID)
        }
    }

    // MARK: AC1: one more version, undo, redo

    @Test("AC1: Duplicate adds one version of the master with an equal stack; the original is unchanged")
    func duplicateAddsAVersionWithAnEqualStack() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        try await fixture.catalog.setEditStack(Self.stack(exposure: 1), forVersion: ids[0], historyLabel: "Exposure")
        let before = try await Snapshot(fixture.catalog, versionID: ids[0])
        let original = try #require(before.record)

        let made = try await fixture.catalog.duplicateVersions(ids: [ids[0]])
        #expect(made.count == 1)
        #expect(made[0].sourceVersionID == ids[0])
        let copy = try #require(try await fixture.catalog.version(id: made[0].copyVersionID))
        #expect(copy.imageId == original.imageId)
        #expect(copy.editStack == original.editStack)
        #expect(copy.editStackHash == original.editStackHash)
        #expect(try copy.decodedEditStack() == original.decodedEditStack())
        #expect(!copy.isDefault)
        #expect(copy.versionNumber == 2)
        #expect(copy.uuid != original.uuid)
        #expect(try await fixture.catalog.versions(ofImage: original.imageId).count == 2)
        #expect(try await fixture.catalog.versionCount() == 3)
        // The original: the same row, keywords, albums and history as before.
        #expect(try await Snapshot(fixture.catalog, versionID: ids[0]) == before)
    }

    @Test("AC1: undo removes the copy and redo restores the same one, with what it held")
    func undoRemovesAndRedoRestoresTheSameCopy() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        _ = try await catalog.addKeywords(named: ["dog"], toVersions: [id])
        let album = try #require(try await catalog.createAlbum(name: "Best").id)
        try await catalog.addVersions([id], toAlbum: album)
        let original = try await Snapshot(catalog, versionID: id)

        let copyID = try await catalog.duplicateVersions(ids: [id])[0].copyVersionID
        // The copy is worked on before the undo: an edit, a rating, a keyword.
        try await catalog.setEditStack(Self.stack(exposure: 2), forVersion: copyID, historyLabel: "Exposure")
        try await catalog.setRating(Rating(clamping: 3), forVersions: [copyID])
        _ = try await catalog.addKeywords(named: ["beach"], toVersions: [copyID])
        let held = try await Snapshot(catalog, versionID: copyID)
        #expect(held.history.count == 1)

        let removed = try await catalog.removeCopies(versionIDs: [copyID])
        #expect(removed.map(\.versionID) == [copyID])
        #expect(try await catalog.version(id: copyID) == nil)
        #expect(try await Self.count(catalog, "versionKeyword WHERE versionId = ?", [copyID]) == 0)
        #expect(try await Self.count(catalog, "albumMember WHERE versionId = ?", [copyID]) == 0)
        #expect(try await Self.count(catalog, "editHistory WHERE versionId = ?", [copyID]) == 0)
        #expect(try await Snapshot(catalog, versionID: id) == original)

        try await catalog.restoreCopies(removed)
        #expect(try await Snapshot(catalog, versionID: copyID) == held)
        #expect(try await Snapshot(catalog, versionID: id) == original)
        // Again: an undo after the redo takes the same copy.
        #expect(try await catalog.removeCopies(versionIDs: [copyID]) == removed)
    }

    @Test("Undo never removes an original, whatever it is handed")
    func removeCopiesLeavesOriginals() async throws {
        let fixture = try await CatalogFixture.make()
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        #expect(try await fixture.catalog.removeCopies(versionIDs: [id]).isEmpty)
        #expect(try await fixture.catalog.version(id: id) != nil)
    }

    @Test("R1: several photos are duplicated in one transaction, all or none")
    func aBatchIsAllOrNothing() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let made = try await fixture.catalog.duplicateVersions(ids: ids)
        #expect(made.map(\.sourceVersionID) == ids)
        #expect(made.map(\.copy.versionNumber) == [2, 2, 2])
        #expect(try await fixture.catalog.versionCount() == 6)
        // One id that is not there: nothing is made.
        await #expect(throws: (any Error).self) {
            try await fixture.catalog.duplicateVersions(ids: [ids[0], 9_999, ids[1]])
        }
        #expect(try await fixture.catalog.versionCount() == 6)
    }

    // MARK: AC2: independent edits

    @Test("AC2: editing the copy leaves the original's stack, render hash and history byte-identical")
    func editingTheCopyLeavesTheOriginal() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        try await catalog.setEditStack(Self.stack(exposure: 1), forVersion: id, historyLabel: "Exposure")
        let copyID = try await catalog.duplicateVersions(ids: [id])[0].copyVersionID
        // The copy's history starts empty (R2).
        #expect(try await catalog.editHistory(forVersion: copyID).isEmpty)
        let before = try await Snapshot(catalog, versionID: id)

        try await catalog.setEditStack(Self.stack(exposure: -2), forVersion: copyID, historyLabel: "Exposure")
        let copy = try #require(try await catalog.version(id: copyID))
        #expect(copy.editStackHash != before.record?.editStackHash)
        #expect(try await catalog.editHistory(forVersion: copyID).map(\.label) == ["Exposure"])
        #expect(try await Snapshot(catalog, versionID: id) == before)

        // And the reverse: the original edited, the copy as it was.
        let copyBefore = try await Snapshot(catalog, versionID: copyID)
        try await catalog.setEditStack(Self.stack(exposure: 3), forVersion: id, historyLabel: "Exposure")
        #expect(try await Snapshot(catalog, versionID: copyID) == copyBefore)
    }

    @Test("R2: a copy's preview is cached under its own key once its edits differ")
    func previewKeysFollowEachStack() async throws {
        let fixture = try await CatalogFixture.make()
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        let copyID = try await fixture.catalog.duplicateVersions(ids: [id])[0].copyVersionID
        func keys() async throws -> [Int64: PreviewCacheKey] {
            var keys: [Int64: PreviewCacheKey] = [:]
            for item in try await Self.items(fixture.catalog) {
                keys[item.versionID] = try #require(PreviewCacheKey(item: item, tier: .preview))
            }
            return keys
        }
        // The same picture until one is edited: the copy shows the cached preview at once.
        var both = try await keys()
        #expect(both[id] == both[copyID])
        try await fixture.catalog.setEditStack(Self.stack(exposure: 1), forVersion: copyID, historyLabel: "Exposure")
        both = try await keys()
        #expect(both[id] != both[copyID])
    }

    // MARK: AC3: independent culling

    @Test("AC3: the copy starts with the original's rating, flag and label; then each keeps its own")
    func cullingIsPerCopy() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        try await catalog.setCulling(rating: Rating(clamping: 2), flag: .picked, colorLabel: .red, forVersions: [id])
        let copyID = try await catalog.duplicateVersions(ids: [id])[0].copyVersionID
        var copy = try #require(try await catalog.version(id: copyID))
        #expect(copy.rating == Rating(clamping: 2) && copy.flag == .picked && copy.colorLabel == .red)

        try await catalog.setRating(Rating(clamping: 5), forVersions: [copyID])
        #expect(try await catalog.version(id: id)?.rating == Rating(clamping: 2))
        try await catalog.setRating(Rating(clamping: 1), forVersions: [id])
        try await catalog.setFlag(.rejected, forVersions: [id])
        try await catalog.setColorLabel(.blue, forVersions: [id])
        copy = try #require(try await catalog.version(id: copyID))
        #expect(copy.rating == Rating(clamping: 5) && copy.flag == .picked && copy.colorLabel == .red)
    }

    // MARK: AC4: keywords and albums

    @Test("AC4: the copy starts with the original's keywords and albums; then each changes alone")
    func keywordsAndAlbumsAreSeededThenIndependent() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        _ = try await catalog.addKeywords(named: ["dog", "beach"], toVersions: [ids[0]])
        let best = try #require(try await catalog.createAlbum(name: "Best").id)
        let other = try #require(try await catalog.createAlbum(name: "Other").id)
        try await catalog.addVersions([ids[0], ids[1]], toAlbum: best)

        let copyID = try await catalog.duplicateVersions(ids: [ids[0]])[0].copyVersionID
        #expect(try await catalog.keywords(forVersion: copyID).map(\.name) == ["beach", "dog"])
        #expect(Set(try await catalog.versionIDs(inAlbum: best)) == [ids[0], ids[1], copyID])
        // In an album or keyword source the copy shows beside its original.
        let inAlbum = try await catalog.libraryItems(matching: LibraryFilter(scope: .album(best)))
        #expect(inAlbum.map(\.versionID) == [ids[0], copyID, ids[1]])

        _ = try await catalog.addKeywords(named: ["sand"], toVersions: [copyID])
        #expect(try await catalog.keywords(forVersion: ids[0]).map(\.name) == ["beach", "dog"])
        let dog = try #require(try await catalog.keywordSummaries().first { $0.name == "dog" }?.id)
        _ = try await catalog.removeKeywords([dog], fromVersions: [ids[0]])
        #expect(try await catalog.keywords(forVersion: copyID).map(\.name) == ["beach", "dog", "sand"])

        try await catalog.addVersions([copyID], toAlbum: other)
        #expect(try await catalog.versionIDs(inAlbum: other) == [copyID])
        try await catalog.removeVersions([ids[0]], fromAlbum: best)
        #expect(Set(try await catalog.versionIDs(inAlbum: best)) == [ids[1], copyID])
    }

    @Test("R5: a copy joins no stack, not even its original's")
    func copiesAreStackless() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        let stack = try #require(try await fixture.catalog.createStack(versionIDs: ids).id)
        let copyID = try await fixture.catalog.duplicateVersions(ids: [ids[0]])[0].copyVersionID
        #expect(try await fixture.catalog.versionIDs(inStack: stack) == ids)
        #expect(try await Self.count(fixture.catalog, "stackMember WHERE versionId = ?", [copyID]) == 0)
    }

    // MARK: AC5: its own item, marked, counted, beside its original

    @Test("AC5: the grid lists two items for the master, the copy marked, and every count includes it")
    func theCopyIsAnItemAndIsCounted() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        _ = try await catalog.addKeywords(named: ["dog"], toVersions: [ids[0]])
        let album = try #require(try await catalog.createAlbum(name: "Best").id)
        try await catalog.addVersions([ids[0]], toAlbum: album)
        let copyID = try await catalog.duplicateVersions(ids: [ids[0]])[0].copyVersionID

        let items = try await Self.items(catalog)
        #expect(items.map(\.versionID) == [ids[0], copyID, ids[1]])
        #expect(items.map(\.isCopy) == [false, true, false])
        #expect(items.map(\.versionNumber) == [1, 2, 1])
        #expect(items[0].imageID == items[1].imageID)
        // The item query by ids marks it too (what the browser inserts after Duplicate).
        let byID = try await catalog.libraryItems(versionIDs: [copyID, ids[0]])
        #expect(Set(byID.filter(\.isCopy).map(\.versionID)) == [copyID])

        // Window subtitle (the item count), the sidebar's library, project, album, keyword and month counts.
        #expect(try await catalog.itemCount(matching: LibraryFilter()) == 3)
        #expect(try await catalog.versionCount() == 3)
        #expect(try await catalog.projectSummaries().map(\.versionCount) == [3])
        #expect(try await catalog.albumSummaries().map(\.count) == [2])
        #expect(try await catalog.keywordSummaries().map(\.count) == [2])
        #expect(try await catalog.captureMonths().map(\.count).reduce(0, +) == 3)
        #expect(try await catalog.itemCount(matching: LibraryFilter(scope: .project(try #require(fixture.project.id)))) == 3)
    }

    @Test("AC5, V3: right after Duplicate the copy sits next to its original under every sort, and where the browser inserts it is where the catalog lists it",
          arguments: [LibrarySort(key: .captureDate), LibrarySort(key: .captureDate, ascending: false),
                      LibrarySort(key: .fileName), LibrarySort(key: .fileName, ascending: false),
                      LibrarySort(key: .rating), LibrarySort(key: .rating, ascending: false)])
    func theCopyIsPlacedAfterItsOriginal(sort: LibrarySort) async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters((1...5).map { CatalogFixture.master($0) })
        try await catalog.setRating(Rating(clamping: 4), forVersions: [ids[1]])
        try await catalog.setRating(Rating(clamping: 2), forVersions: [ids[3]])
        var shown = try await Self.items(catalog, sort: sort)

        // Three rounds: copies of originals, a second copy, and a copy of a copy.
        var copies: [Int64: [Int64]] = [:]
        for sources in [[ids[1], ids[3], ids[4]], [ids[1]], []] {
            let targets = sources.isEmpty ? [try #require(copies[ids[3]]?.first)] : sources
            let made = try await catalog.duplicateVersions(ids: targets)
            let madeItems = try await catalog.libraryItems(versionIDs: made.map(\.copyVersionID))
            let ordered = made.compactMap { copy in madeItems.first { $0.versionID == copy.copyVersionID } }
            shown = DuplicatePlacement.inserting(ordered, into: shown, sort: sort)
            let listed = try await Self.items(catalog, sort: sort)
            #expect(shown.map(\.versionID) == listed.map(\.versionID))
            for copy in ordered {
                let original = try #require(listed.first { $0.imageID == copy.imageID && !$0.isCopy })
                copies[original.versionID, default: []].append(copy.versionID)
            }
            // The original first, then its copies in the order they were made (A4), nothing between.
            for (original, made) in copies {
                let start = try #require(listed.firstIndex { $0.versionID == original })
                #expect(Array(listed[start...].prefix(made.count + 1)).map(\.versionID) == [original] + made)
            }
        }
        #expect(copies[ids[3]]?.count == 2)
    }

    @Test("R5: afterwards a copy sorts by its own values")
    func aCopySortsByItsOwnRating() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let copyID = try await fixture.catalog.duplicateVersions(ids: [ids[0]])[0].copyVersionID
        try await fixture.catalog.setRating(Rating(clamping: 5), forVersions: [copyID])
        let byRating = try await Self.items(fixture.catalog, sort: LibrarySort(key: .rating))
        #expect(byRating.map(\.versionID) == [ids[0], ids[1], ids[2], copyID])
        let byDate = try await Self.items(fixture.catalog)
        #expect(byDate.map(\.versionID) == [ids[0], copyID, ids[1], ids[2]])
    }

    @Test("Placement: a copy whose master is not on screen goes to the end; under a rating sort it follows its own rating's items")
    func placementEdges() {
        func item(_ version: Int64, image: Int64, rating: Int = 0, number: Int = 1) -> CatalogItem {
            var item = CatalogItem(versionID: version, imageID: image, volumeID: 1, rating: Rating(clamping: rating), flag: .none,
                                   colorLabel: .none, contentHash: "", editStackHash: "", relativePath: "a/\(image).jpg",
                                   pixelWidth: 10, pixelHeight: 10, orientation: 1)
            item.versionNumber = number
            item.isCopy = number > 1
            return item
        }
        let shown = [item(1, image: 1), item(2, image: 2), item(3, image: 3, rating: 4), item(4, image: 2, rating: 4, number: 2)]
        #expect(DuplicatePlacement.insertionIndex(for: item(9, image: 7, number: 2), in: shown, sort: LibrarySort()) == 4)
        // A copy of the 4-star copy of image 2: after that copy, not after the unrated original.
        #expect(DuplicatePlacement.insertionIndex(for: item(9, image: 2, rating: 4, number: 3), in: shown,
                                                  sort: LibrarySort(key: .rating)) == 4)
        #expect(DuplicatePlacement.insertionIndex(for: item(9, image: 2, number: 3), in: shown,
                                                  sort: LibrarySort(key: .rating)) == 2)
        // The original rated since it was shown (it stays on screen until the filter changes): after the master's last item.
        #expect(DuplicatePlacement.insertionIndex(for: item(9, image: 3, rating: 1, number: 2), in: shown,
                                                  sort: LibrarySort(key: .rating)) == 3)
    }

    /// A small seeded generator, so the random lists below are the same on every run.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test("C2: placing many copies in one pass gives the list that inserting them one at a time gives",
          arguments: [LibrarySort(key: .captureDate), LibrarySort(key: .fileName, ascending: false), LibrarySort(key: .rating)])
    func onePassPlacementMatchesOneAtATime(sort: LibrarySort) {
        func item(_ version: Int64, image: Int64, rating: Int, number: Int) -> CatalogItem {
            var item = CatalogItem(versionID: version, imageID: image, volumeID: 1, rating: Rating(clamping: rating), flag: .none,
                                   colorLabel: .none, contentHash: "", editStackHash: "", relativePath: "a/\(image).jpg",
                                   pixelWidth: 10, pixelHeight: 10, orientation: 1)
            item.versionNumber = number
            item.isCopy = number > 1
            return item
        }
        var generator = SeededGenerator(state: 62)
        for round in 0..<200 {
            // A list in any order (photos stay where they were when culled), several items of
            // some masters, a few ratings; copies of masters on screen and of masters that are not,
            // several of one master, with ratings the master's items have and ratings they lack.
            var next: Int64 = 1
            var shown: [CatalogItem] = []
            for _ in 0..<Int.random(in: 0...12, using: &generator) {
                shown.append(item(next, image: Int64.random(in: 1...5, using: &generator),
                                  rating: Int.random(in: 0...2, using: &generator), number: Int.random(in: 1...3, using: &generator)))
                next += 1
            }
            var copies: [CatalogItem] = []
            for _ in 0..<Int.random(in: 0...10, using: &generator) {
                copies.append(item(next, image: Int64.random(in: 1...7, using: &generator),
                                   rating: Int.random(in: 0...3, using: &generator), number: 9))
                next += 1
            }
            var oneAtATime = shown
            for copy in copies {
                oneAtATime.insert(copy, at: DuplicatePlacement.insertionIndex(for: copy, in: oneAtATime, sort: sort))
            }
            let onePass = DuplicatePlacement.inserting(copies, into: shown, sort: sort)
            #expect(onePass.map(\.versionID) == oneAtATime.map(\.versionID), "round \(round)")
        }
        // Nothing to place: the list as it was.
        let list = [item(1, image: 1, rating: 0, number: 1)]
        #expect(DuplicatePlacement.inserting([], into: list, sort: sort) == list)
    }

    @Test("C3: no removal is asked for while a Duplicate is writing its copies")
    func removalWaitsForARunningDuplicate() {
        #expect(RemovalAvailability.canStart(isRemoving: false, isAddingFolders: false, isCopying: false, isDuplicating: false))
        #expect(!RemovalAvailability.canStart(isRemoving: false, isAddingFolders: false, isCopying: false, isDuplicating: true))
    }

    // MARK: Names (design §5, V4)

    @Test("V4: version 1 is the base name, then copy, copy 2…; removing a middle copy renames nothing; the newest number is reused")
    func copyNames() async throws {
        let naming = CopyNaming.plain
        #expect(naming.displayName(baseName: "IMG_0412", copyNumber: nil) == "IMG_0412")
        #expect(CopyNaming.copyNumber(versionNumber: 1, isCopy: false) == nil)
        #expect(naming.displayName(baseName: "IMG_0412", copyNumber: CopyNaming.copyNumber(versionNumber: 2, isCopy: true)) == "IMG_0412 copy")
        #expect(naming.displayName(baseName: "IMG_0412", copyNumber: CopyNaming.copyNumber(versionNumber: 3, isCopy: true)) == "IMG_0412 copy 2")
        #expect(naming.displayName(baseName: "IMG_0412", copyNumber: CopyNaming.copyNumber(versionNumber: 12, isCopy: true)) == "IMG_0412 copy 11")

        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let id = try await fixture.addMasters([CatalogFixture.master(412)])[0]
        func names() async throws -> [String] { try await Self.items(catalog).map { naming.displayName(of: $0) } }
        let first = try await catalog.duplicateVersion(id: id)
        // A copy of a copy is another copy of the same master.
        let second = try await catalog.duplicateVersion(id: try #require(first.id))
        let third = try await catalog.duplicateVersion(id: id)
        #expect(try await names() == ["IMG_0412", "IMG_0412 copy", "IMG_0412 copy 2", "IMG_0412 copy 3"])

        try await catalog.removePhotos(versionIDs: [try #require(second.id)])
        #expect(try await names() == ["IMG_0412", "IMG_0412 copy", "IMG_0412 copy 3"])
        // A new copy takes the highest number plus one; one freed at the top is used again (A2).
        _ = try await catalog.duplicateVersion(id: id)
        #expect(try await names() == ["IMG_0412", "IMG_0412 copy", "IMG_0412 copy 3", "IMG_0412 copy 4"])
        try await catalog.removePhotos(versionIDs: [try #require(third.id)])
        let last = try #require(try await Self.items(catalog).last)
        try await catalog.removePhotos(versionIDs: [last.versionID])
        _ = try await catalog.duplicateVersion(id: id)
        #expect(try await names() == ["IMG_0412", "IMG_0412 copy", "IMG_0412 copy 2"])
    }

    @Test("The words of a copy's name are the caller's")
    func namingWordsAreInjected() {
        let naming = CopyNaming { base, number in "\(base) Kopie" + (number > 1 ? " \(number)" : "") }
        var item = CatalogItem(versionID: 1, imageID: 1, volumeID: 1, rating: .unrated, flag: .none, colorLabel: .none,
                               contentHash: "", editStackHash: "", relativePath: "a/IMG_1.RW2", pixelWidth: 1, pixelHeight: 1,
                               orientation: 1)
        #expect(naming.displayName(of: item) == "IMG_1")
        item.versionNumber = 3
        item.isCopy = true
        #expect(naming.displayName(of: item) == "IMG_1 Kopie 2")
    }

    // MARK: AC6: removing

    @Test("AC6: removing a copy removes only that version; the master, the original and its edits remain")
    func removingACopyLeavesTheOriginal() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        try await catalog.setEditStack(Self.stack(exposure: 1), forVersion: ids[0], historyLabel: "Exposure")
        _ = try await catalog.addKeywords(named: ["dog"], toVersions: [ids[0]])
        let album = try #require(try await catalog.createAlbum(name: "Best").id)
        try await catalog.addVersions([ids[0]], toAlbum: album)
        let copyID = try await catalog.duplicateVersions(ids: [ids[0]])[0].copyVersionID
        try await catalog.setEditStack(Self.stack(exposure: 2), forVersion: copyID, historyLabel: "Exposure")
        let original = try await Snapshot(catalog, versionID: ids[0])
        let image = try #require(original.record?.imageId)

        let plan = try await catalog.photoRemovalPlan(forVersions: [copyID])
        #expect(plan.imageIDs.isEmpty && plan.fileCount == 0)
        #expect(plan.copyVersionIDs == [copyID])
        #expect(plan.originalCount == 0 && plan.extraCopyCount == 0)

        let result = try await catalog.removePhotos(versionIDs: [copyID])
        #expect(result.imageIDs.isEmpty)
        #expect(result.copyVersionIDs == [copyID])
        #expect(result.versionCount == 1)
        #expect(try await catalog.version(id: copyID) == nil)
        for table in ["versionKeyword", "albumMember", "editHistory", "stackMember"] {
            #expect(try await Self.count(catalog, "\(table) WHERE versionId = ?", [copyID]) == 0)
        }
        #expect(try await Snapshot(catalog, versionID: ids[0]) == original)
        #expect(try await Self.count(catalog, "image WHERE id = ?", [image]) == 1)
        #expect(try await catalog.versionCount() == 2)
        #expect(try await catalog.keywordSummaries().map(\.name) == ["dog"])
    }

    @Test("AC6: removing the original takes its copies, and the plan counts the ones not chosen")
    func removingTheOriginalTakesItsCopies() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        let copies = try await catalog.duplicateVersions(ids: [ids[0], ids[0], ids[1]]).map(\.copyVersionID)

        // The original alone: both of its copies go with it.
        var plan = try await catalog.photoRemovalPlan(forVersions: [ids[0]])
        #expect(plan.fileCount == 1 && plan.originalCount == 1 && plan.extraCopyCount == 2 && plan.copyVersionIDs.isEmpty)
        // The original and one of its copies chosen: one more goes unasked.
        plan = try await catalog.photoRemovalPlan(forVersions: [ids[0], copies[0]])
        #expect(plan.fileCount == 1 && plan.originalCount == 1 && plan.extraCopyCount == 1 && plan.copyVersionIDs.isEmpty)
        // That, and the other photo's copy, which goes alone.
        plan = try await catalog.photoRemovalPlan(forVersions: [ids[0], copies[0], copies[2]])
        #expect(plan.fileCount == 1 && plan.extraCopyCount == 1 && plan.copyVersionIDs == [copies[2]])

        let result = try await catalog.removePhotos(versionIDs: [ids[0]])
        #expect(result.versionCount == 3)
        #expect(result.copyVersionIDs.isEmpty)
        for id in [ids[0], copies[0], copies[1]] { #expect(try await catalog.version(id: id) == nil) }
        #expect(try await catalog.versions(ofImage: try #require(try await catalog.version(id: ids[1])?.imageId)).count == 2)
    }

    @Test("AC6, V9: what the confirmation says for copies")
    func removalConfirmationForCopies() {
        typealias Sentence = RemovalConfirmation.Sentence
        // One copy: no file, sidecar or original is involved.
        var confirmation = RemovalConfirmation.photos(shown: 1, fileName: "IMG_0412 copy 2", fileCount: 0, originals: 0)
        #expect(confirmation.title == .photo(fileName: "IMG_0412 copy 2"))
        #expect(confirmation.sentences == [.copyConsequences])
        // Several copies.
        confirmation = RemovalConfirmation.photos(shown: 3, fileName: nil, fileCount: 0, originals: 0)
        #expect(confirmation.title == .photos(3))
        #expect(confirmation.sentences == [.copiesConsequences])
        // One original with two copies outside the targets.
        confirmation = RemovalConfirmation.photos(shown: 1, fileName: "IMG_0412.RW2", fileCount: 1, originals: 1, extraCopies: 2)
        #expect(confirmation.sentences == [.copiesOfPhoto(2), .photosConsequences])
        // Several originals with copies.
        confirmation = RemovalConfirmation.photos(shown: 4, fileName: nil, fileCount: 4, originals: 4, extraCopies: 3)
        #expect(confirmation.title == .photos(4))
        #expect(confirmation.sentences == [.copiesOfPhotos(3), .photosConsequences])
        // Mixed, the copies all chosen: the standard message, and the count includes them.
        confirmation = RemovalConfirmation.photos(shown: 3, fileName: nil, fileCount: 1, originals: 1, extraCopies: 0)
        #expect(confirmation.title == .photos(3))
        #expect(confirmation.sentences == [.photosConsequences])
        // A grouped pair with a copy: the pair sentence counts files, never copies.
        confirmation = RemovalConfirmation.photos(shown: 2, fileName: nil, fileCount: 2, originals: 1, extraCopies: 0)
        #expect(confirmation.sentences == [.pairFiles(2), .photosConsequences])
        confirmation = RemovalConfirmation.photos(shown: 1, fileName: "a.RW2", fileCount: 2, originals: 1, extraCopies: 1)
        #expect(confirmation.sentences == [.pairFiles(2), .copiesOfPhoto(1), .photosConsequences])
        // Without copies nothing changed.
        #expect(RemovalConfirmation.photos(shown: 2, fileName: nil, fileCount: 2).sentences == [.photosConsequences])
    }

    @Test("AC6, V9: a copy of a pair's RAW is removed alone, with no pair sentence")
    func removingACopyOfAPairsRAW() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([Self.master("a/IMG_1.NEF", 1), Self.master("a/IMG_1.JPG", 2)])
        let copyID = try await catalog.duplicateVersions(ids: [ids[0]])[0].copyVersionID
        let plan = try await catalog.photoRemovalPlan(forVersions: [copyID])
        #expect(plan.fileCount == 0 && plan.copyVersionIDs == [copyID])
        #expect(RemovalConfirmation.photos(plan, shown: 1, fileName: "IMG_1 copy").sentences == [.copyConsequences])
        try await catalog.removePhotos(versionIDs: [copyID])
        #expect(try await catalog.version(id: ids[0]) != nil)
        #expect(try await catalog.version(id: ids[1]) != nil)
        #expect(try await Self.count(catalog, "imagePair") == 1)

        // The pair's RAW itself: both files, and the JPEG's copy goes too.
        let jpegCopy = try await catalog.duplicateVersions(ids: [ids[1]])[0].copyVersionID
        let whole = try await catalog.photoRemovalPlan(forVersions: [ids[0]])
        #expect(whole.fileCount == 2 && whole.originalCount == 1 && whole.extraCopyCount == 1)
        #expect(RemovalConfirmation.photos(whole, shown: 1, fileName: "IMG_1.NEF").sentences
                == [.pairFiles(2), .copiesOfPhoto(1), .photosConsequences])
        try await catalog.removePhotos(versionIDs: [ids[0]])
        #expect(try await catalog.version(id: jpegCopy) == nil)
        #expect(try await catalog.versionCount(groupingPairs: false) == 0)
    }

    // MARK: AC7: sidecars

    @Test("AC7: duplicating, then editing, rating and keywording the copy queues nothing and writes or flags no sidecar")
    func copiesNeverReachASidecar() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "Shoot")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try SyntheticImages.writeJPEG(to: folder.appending(path: "a.jpg"), width: 64, height: 48, seed: 1)
            _ = try SidecarFiles.write(SidecarValues(rating: Rating(clamping: 2), keywords: ["dog"]), previous: nil,
                                       to: folder.appending(path: "a.xmp"))
            let catalog = try Catalog.makeInMemory()
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(folder)
            let sync = SidecarSync(catalog: catalog, metadataReader: ImageIOMetadataReader())
            let mounted = Set(try await catalog.volumes().compactMap(\.id))
            let original = try #require(try await Self.items(catalog).first)
            // What the import queued is settled first: the sidecar already holds these values.
            _ = try await sync.processQueue(mountedVolumes: mounted)
            #expect(try await Self.count(catalog, "sidecarQueue") == 0)
            func sidecar() throws -> (Data, Date?) {
                let url = folder.appending(path: "a.xmp")
                return (try Data(contentsOf: url),
                        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            }
            let before = try sidecar()
            func syncState() async throws -> [String] {
                try await catalog.database.read { db in
                    try Row.fetchAll(db, sql: "SELECT * FROM metadataSync ORDER BY imageId").map {
                        "\($0["imageId"] as Int64) \($0["status"] as Int) \($0["baseline"] as String) \(($0["sidecarDigest"] as String?) ?? "-")"
                    }
                }
            }
            let syncBefore = try await syncState()

            let copyID = try await catalog.duplicateVersions(ids: [original.versionID])[0].copyVersionID
            try await catalog.setEditStack(Self.stack(exposure: 1), forVersion: copyID, historyLabel: "Exposure")
            try await catalog.setCulling(rating: Rating(clamping: 5), flag: .rejected, colorLabel: .green, forVersions: [copyID])
            try await catalog.setRating(Rating(clamping: 4), forVersions: [copyID])
            try await catalog.setFlag(.picked, forVersions: [copyID])
            try await catalog.setColorLabel(.blue, forVersions: [copyID])
            let added = try await catalog.addKeywords(named: ["beach", "dog", "sand"], toVersions: [copyID])
            _ = try await catalog.removeKeywords(added.assignments.prefix(1).map(\.keywordId), fromVersions: [copyID])
            let second = try await catalog.duplicateVersions(ids: [copyID])[0].copyVersionID
            // Undo and redo of a Duplicate, and removing a copy.
            try await catalog.restoreCopies(try await catalog.removeCopies(versionIDs: [second]))
            try await catalog.removePhotos(versionIDs: [second])

            #expect(try await Self.count(catalog, "sidecarQueue") == 0)
            #expect(try await catalog.queuedSidecarOwners().isEmpty)
            let report = try await sync.processQueue(mountedVolumes: mounted)
            #expect(report.written == 0 && report.failed == 0 && report.changedOnDisk == 0)
            let check = try await sync.checkForChanges(mountedVolumes: mounted)
            #expect(check.changedOnDisk == 0)
            #expect(try sidecar() == before)
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["a.jpg", "a.xmp"])
            #expect(try await syncState() == syncBefore)
            // The original's values are what the sidecar holds, whatever the copy was given.
            #expect(try await catalog.version(id: original.versionID)?.rating == Rating(clamping: 2))
            #expect(try await catalog.keywords(forVersion: original.versionID).map(\.name) == ["dog"])

            // The triggers still fire for the original: one row, its own.
            try await catalog.setRating(Rating(clamping: 3), forVersions: [original.versionID])
            #expect(try await catalog.queuedSidecarOwners() == [original.imageID])
        }
    }

    @Test("AC7: renaming a keyword only a copy has queues nothing")
    func renamingACopysKeywordQueuesNothing() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        let copyID = try await catalog.duplicateVersions(ids: [id])[0].copyVersionID
        let added = try await catalog.addKeywords(named: ["beach"], toVersions: [copyID])
        try await catalog.database.write { db in
            try db.execute(sql: "UPDATE keyword SET name = 'shore' WHERE id = ?", arguments: [added.assignments[0].keywordId])
        }
        #expect(try await Self.count(catalog, "sidecarQueue") == 0)
    }

    // MARK: AC8: export

    private func context(_ name: String, copy: String? = nil, sequence: Int = 1) -> TemplateContext {
        TemplateContext(captureDate: nil, captureOffsetSeconds: nil, fileDate: Date(timeIntervalSince1970: 0),
                        importDate: Date(timeIntervalSince1970: 0), make: nil, model: nil, serial: nil, lens: nil,
                        originalName: name, sequence: sequence, counter: sequence, jobCode: "",
                        exportDate: Date(timeIntervalSince1970: 0), displayName: copy)
    }

    @Test("AC8, V5: an original and two copies get distinct names under Original Name, {name} templates and {seq}-only templates")
    func exportNamesForCopies() {
        let contexts = [context("IMG_0412.NEF", sequence: 1), context("IMG_0412.NEF", copy: "IMG_0412 copy", sequence: 2),
                        context("IMG_0412.NEF", copy: "IMG_0412 copy 2", sequence: 3)]
        let folder = URL(fileURLWithPath: "/tmp/out")
        func names(_ settings: ExportSettings) -> [String] {
            ExportNaming.plan(contexts, settings: settings, in: folder, policy: .keepBoth, masters: .none) { _ in false }.map(\.url.lastPathComponent)
        }
        var settings = ExportSettings()
        settings.format = .jpeg
        settings.naming = .original
        #expect(names(settings) == ["IMG_0412.jpg", "IMG_0412 copy.jpg", "IMG_0412 copy 2.jpg"])

        settings.naming = .template
        settings.fileNameTemplate = "{name}-web"
        #expect(names(settings) == ["IMG_0412-web.jpg", "IMG_0412 copy-web.jpg", "IMG_0412 copy 2-web.jpg"])
        settings.fileNameTemplate = "shoot-{seq:3}"
        #expect(names(settings) == ["shoot-001.jpg", "shoot-002.jpg", "shoot-003.jpg"])
        // No {name}: the copy gets no suffix, and the batch's numbering keeps the names apart.
        settings.fileNameTemplate = "{number}"
        #expect(names(settings) == ["0412.jpg", "0412-2.jpg", "0412-3.jpg"])
        #expect(Set(names(settings)).count == 3)
        // The other tokens still read the file's name.
        settings.fileNameTemplate = "{name}.{ext:lower}"
        #expect(names(settings)[1] == "IMG_0412 copy.nef.jpg")
    }

    @Test("{name} in an import template is the original name: imports never see a copy")
    func importTemplatesAreUnchanged() {
        let rendered = ImportTemplate(folder: "", fileName: "{name}").render(context("IMG_0412.NEF"))
        #expect(rendered.fileName == "IMG_0412.NEF")
    }

    /// The mean of an image file's 8-bit gray values.
    private func meanLevel(_ url: URL) throws -> Double {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height)
        let context = try #require(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                                             bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count)
    }

    @Test("AC8: exporting an original and its copy together gives two files, each with its own edits")
    func exportingOriginalAndCopyTogether() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "Shoot")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try SyntheticImages.writeJPEG(to: folder.appending(path: "b.jpg"), width: 320, height: 240, seed: 2)
            let catalog = try Catalog.makeInMemory()
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(folder)
            let original = try #require(try await Self.items(catalog).first)
            _ = try await catalog.addKeywords(named: ["dog"], toVersions: [original.versionID])
            let copyID = try await catalog.duplicateVersions(ids: [original.versionID])[0].copyVersionID
            // The copy two stops darker and with a keyword of its own; the original as shot.
            try await catalog.setEditStack(Self.stack(exposure: -2), forVersion: copyID, historyLabel: "Exposure")
            _ = try await catalog.addKeywords(named: ["sand"], toVersions: [copyID])

            let output = root.appending(path: "Out")
            let job = ExportJob(catalog: catalog,
                                renderer: ExportRenderer(generator: PreviewGenerator(),
                                                         watermarks: WatermarkStore(directory: root.appending(path: "Watermarks"))))
            let exported = try await job.items(for: [original.versionID, copyID])
            #expect(exported.map(\.copyName) == [nil, "b copy"])
            #expect(exported.map(\.reportName) == ["b.jpg", "b copy"])
            // Metadata: the image's fields, and each version's own keywords.
            #expect(exported.map(\.values.keywords) == [["dog"], ["dog", "sand"]])

            var settings = ExportSettings()
            settings.format = .jpeg
            settings.naming = .original
            let summary = await job.run(ExportRequest(versionIDs: [original.versionID, copyID], settings: settings,
                                                      destination: output))
            #expect(summary.failures.isEmpty)
            #expect(Set(summary.written.map(\.lastPathComponent)) == ["b.jpg", "b copy.jpg"])
            let plain = try meanLevel(output.appending(path: "b.jpg"))
            let darker = try meanLevel(output.appending(path: "b copy.jpg"))
            #expect(darker < plain * 0.7, "the copy's file shows the copy's edits (\(darker) against \(plain))")
            // The original's file is what the original alone exports to.
            let alone = root.appending(path: "Alone")
            _ = await job.run(ExportRequest(versionIDs: [original.versionID], settings: settings, destination: alone))
            #expect(abs(try meanLevel(alone.appending(path: "b.jpg")) - plain) < 0.5)
        }
    }

    // MARK: AC9: RAW+JPEG pairs

    @Test("AC9: duplicating a pair's RAW leaves the JPEG untouched and the copy unpaired; neither's rating reaches the other")
    func aPairsCopyIsUnpaired() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([Self.master("a/IMG_1.NEF", 1), Self.master("a/IMG_1.JPG", 2),
                                                Self.master("a/IMG_2.NEF", 3)])
        try await catalog.setRating(Rating(clamping: 2), forVersions: [ids[0]])
        try await catalog.setEditStack(Self.stack(exposure: 1), forVersion: ids[0], historyLabel: "Exposure")
        _ = try await catalog.addKeywords(named: ["dog"], toVersions: [ids[0]])
        let jpegBefore = try await Snapshot(catalog, versionID: ids[1])
        #expect(jpegBefore.record?.rating == Rating(clamping: 2))

        let copyID = try await catalog.duplicateVersions(ids: [ids[0]])[0].copyVersionID
        // Only the RAW's version was copied: the JPEG has one version, as before.
        #expect(try await Snapshot(catalog, versionID: ids[1]) == jpegBefore)
        #expect(try await catalog.versions(ofImage: try #require(jpegBefore.record?.imageId)).count == 1)
        #expect(try await Self.count(catalog, "imagePair") == 1)

        // Grouped: the pair once, then the copy as its own unpaired item.
        let grouped = try await Self.items(catalog)
        #expect(grouped.map(\.versionID) == [ids[0], copyID, ids[2]])
        #expect(grouped[0].representsPair && grouped[0].partnerVersionID == ids[1])
        let copy = grouped[1]
        #expect(copy.isCopy && !copy.representsPair && copy.partnerVersionID == nil && copy.partnerKind == nil)
        #expect(copy.fileKind == .raw)
        #expect(PairDisplay([copy]) == nil)
        #expect(try await catalog.itemCount(matching: LibraryFilter()) == 3)
        #expect(try await catalog.versionCount() == 3)
        #expect(try await catalog.projectSummaries().map(\.versionCount) == [3])
        // Ungrouped: RAW, its copy, the JPEG; the pair's halves still linked to each other.
        let separate = try await Self.items(catalog, grouped: false)
        #expect(Set(separate.map(\.versionID)) == Set(ids + [copyID]))
        #expect(separate.first { $0.versionID == ids[1] }?.partnerVersionID == ids[0])
        #expect(separate.first { $0.versionID == copyID }?.partnerVersionID == nil)

        // Culling, keywords and albums of the copy do not reach the JPEG (or the RAW).
        try await catalog.setRating(Rating(clamping: 5), forVersions: [copyID])
        try await catalog.setFlag(.rejected, forVersions: [copyID])
        _ = try await catalog.addKeywords(named: ["sand"], toVersions: [copyID])
        let album = try #require(try await catalog.createAlbum(name: "Best").id)
        try await catalog.addVersions([copyID], toAlbum: album)
        #expect(try await Snapshot(catalog, versionID: ids[1]) == jpegBefore)
        #expect(try await catalog.version(id: ids[0])?.rating == Rating(clamping: 2))
        #expect(try await catalog.versionIDs(inAlbum: album) == [copyID])
        // The pair still shares: rating the RAW reaches the JPEG, never the copy.
        try await catalog.setRating(Rating(clamping: 1), forVersions: [ids[0]])
        #expect(try await catalog.version(id: ids[1])?.rating == Rating(clamping: 1))
        #expect(try await catalog.version(id: copyID)?.rating == Rating(clamping: 5))
        // Switching the pair's file does not concern the copy.
        try await catalog.setPairsShowCompanion(true, forVersions: [copyID])
        #expect(try await Self.items(catalog).map(\.versionID) == [ids[0], copyID, ids[2]])
        let shown = try await catalog.database.read { db in try Bool.fetchOne(db, sql: "SELECT showsCompanion FROM imagePair") }
        #expect(shown == false)
    }

    // MARK: Videos, offline photos, unreadable stacks (design §4.1, §4.4)

    @Test("P1: videos are not duplicated; a mixed selection skips and counts them")
    func videosAreLeftOut() {
        func item(_ id: Int64, _ path: String) -> CatalogItem {
            CatalogItem(versionID: id, imageID: id, volumeID: 1, rating: .unrated, flag: .none, colorLabel: .none,
                        contentHash: "", editStackHash: "", relativePath: path, pixelWidth: 100, pixelHeight: 100,
                        orientation: 1)
        }
        let photo = item(1, "a/IMG_1.RW2")
        let clips = [item(2, "a/clip.mov"), item(3, "a/clip2.mp4")]
        // The one switch for the PRD's pending question P1.
        #expect(!DuplicateTargets.includesVideos)
        #expect(DuplicateTargets.canDuplicate([photo]))
        #expect(!DuplicateTargets.canDuplicate(clips))
        #expect(!DuplicateTargets.canDuplicate([CatalogItem]()))
        #expect(DuplicateTargets.canDuplicate(clips + [photo]))
        let resolved = DuplicateTargets.resolve([clips[0], photo, clips[1]])
        #expect(resolved.versionIDs == [1])
        #expect(resolved.skippedVideos == 2)
        #expect(DuplicateTargets.resolve([photo]).skippedVideos == 0)
    }

    @Test("A1: an offline photo is duplicated from the catalog alone, with the original's render hash")
    func offlinePhotosCanBeDuplicated() async throws {
        // The fixture's volume is not mounted and its files do not exist.
        let fixture = try await CatalogFixture.make()
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        #expect(!FileManager.default.fileExists(atPath: fixture.volume.mountPath))
        let copyID = try await fixture.catalog.duplicateVersions(ids: [id])[0].copyVersionID
        let items = try await Self.items(fixture.catalog)
        #expect(items.map(\.versionID) == [id, copyID])
        // The same cache key: the copy shows the original's cached preview, offline too.
        #expect(PreviewCacheKey(item: items[0], tier: .thumbnail) == PreviewCacheKey(item: items[1], tier: .thumbnail))
    }

    @Test("An unreadable stack is copied unchanged, and the copy is as protected as its original")
    func anUnreadableStackIsCopiedUnchanged() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        // A newer build's stack, and a damaged one.
        for stored in [#"{"operations":[{"future":true}],"schemaVersion":99}"#, "not json {"] {
            try await catalog.database.write { db in
                try db.execute(sql: "UPDATE version SET editStack = ?, editStackHash = 'newer-hash' WHERE id = ?",
                               arguments: [stored, id])
            }
            let copyID = try await catalog.duplicateVersions(ids: [id])[0].copyVersionID
            let copy = try #require(try await catalog.version(id: copyID))
            #expect(copy.editStack == stored)
            #expect(copy.editStackHash == "newer-hash")
            #expect(copy.editStackReadFailure != nil)
            // Nothing of the original was written over.
            #expect(try await catalog.version(id: id)?.editStack == stored)
            // The copy cannot be edited either: the catalog refuses, as for the original.
            await #expect(throws: UnreadableEditStacks.self) {
                try await catalog.setEditStack(Self.stack(exposure: 1), forVersion: copyID, historyLabel: "Exposure")
            }
            #expect(try await catalog.version(id: copyID)?.editStack == stored)
            #expect(try await catalog.editHistory(forVersion: copyID).isEmpty)
        }
    }

    // MARK: R11: "is a copy" smart-album rule (design §8, V10)

    @Test("R11, V10: the rule Photo is a copy / is not a copy")
    func smartAlbumRuleForCopies() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        let copyID = try await catalog.duplicateVersions(ids: [ids[0]])[0].copyVersionID
        #expect(SmartRule.Field.isCopy.kind.comparisons == [.isTrue, .isFalse])
        #expect(SmartRule.Field.allCases.last == .isCopy)
        func matching(_ comparison: SmartRule.Comparison) async throws -> [Int64] {
            let rules = SmartAlbumRules(match: .all, rules: [SmartRule(field: .isCopy, comparison: comparison)])
            #expect(rules.sqlCondition(now: Date())?.sql.contains("version.isDefault") == true)
            // Stored and read back, as a saved smart album is.
            let stored = try SmartAlbumRules.decode(from: try rules.jsonString())
            return try await catalog.libraryItems(matching: LibraryFilter(scope: .rules(stored, projectID: nil))).map(\.versionID)
        }
        #expect(try await matching(.isTrue) == [copyID])
        #expect(try await matching(.isFalse) == ids)
        let mixed = SmartAlbumRules(match: .all, rules: [SmartRule(field: .isCopy, comparison: .isTrue),
                                                         SmartRule(field: .rating, comparison: .atLeast, value: RuleValue(number: 3))])
        #expect(try await catalog.itemCount(matching: LibraryFilter(scope: .rules(mixed, projectID: nil))) == 0)
        try await catalog.setRating(Rating(clamping: 4), forVersions: [copyID])
        #expect(try await catalog.itemCount(matching: LibraryFilter(scope: .rules(mixed, projectID: nil))) == 1)
    }
}
