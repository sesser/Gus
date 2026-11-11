import Foundation
import Testing
@testable import PhotoCore

/// The rules behind Rename, Show in Finder and the removal confirmations
/// (docs/features/library-ops/design.md §12, L3–L8).
@Suite("Library operations rules")
struct LibraryOpsRuleTests {
    // MARK: L5: the project name rule

    @Test("L5: a typed project name is trimmed, an empty one refused, the same one a no-op")
    func projectNameRule() {
        #expect(ProjectRename.resolve(typed: "Iceland 2026", current: "100OLYMP") == .rename("Iceland 2026"))
        #expect(ProjectRename.resolve(typed: "  Iceland  2026 \n", current: "100OLYMP") == .rename("Iceland  2026"))
        #expect(ProjectRename.resolve(typed: "", current: "100OLYMP") == .refused)
        #expect(ProjectRename.resolve(typed: " \t\n ", current: "100OLYMP") == .refused)
        #expect(ProjectRename.resolve(typed: "100OLYMP", current: "100OLYMP") == .unchanged)
        #expect(ProjectRename.resolve(typed: " 100OLYMP ", current: "100OLYMP") == .unchanged)
        // Only the case differs: that is a change.
        #expect(ProjectRename.resolve(typed: "100olymp", current: "100OLYMP") == .rename("100olymp"))
    }

    // MARK: L3: which files Show in Finder reveals

    private static func master(_ path: String, _ index: Int) -> NewMaster {
        CatalogFixture.master(index, hash: String(format: "%064x", index), path: path)
    }

    @Test("L3 / AC11: a grouped pair reveals its RAW whichever file it shows; an ungrouped JPEG cell reveals the JPEG")
    func revealList() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([Self.master("a/IMG_1.NEF", 1), Self.master("a/IMG_1.JPG", 2),
                                                Self.master("a/IMG_2.JPG", 3)])
        let (raw, jpeg, single) = (ids[0], ids[1], ids[2])
        func items(grouped: Bool) async throws -> [CatalogItem] {
            try await fixture.catalog.libraryItems(matching: LibraryFilter(sort: LibrarySort(key: .fileName), groupsPairs: grouped))
        }

        // Grouped, the cell shows the RAW.
        var grouped = try await items(grouped: true)
        #expect(grouped.map(\.fileName) == ["IMG_1.NEF", "IMG_2.JPG"])
        #expect(FinderReveal.versionIDs(for: grouped) == [raw, single])

        // Grouped, the cell shows the JPEG: still the RAW.
        try await fixture.catalog.setPairsShowCompanion(true, forVersions: [raw])
        grouped = try await items(grouped: true)
        #expect(grouped.map(\.fileName) == ["IMG_1.JPG", "IMG_2.JPG"])
        #expect(FinderReveal.versionIDs(for: grouped) == [raw, single])

        // Ungrouped: each cell its own file.
        let separate = try await items(grouped: false)
        #expect(separate.map(\.fileName) == ["IMG_1.JPG", "IMG_1.NEF", "IMG_2.JPG"])
        #expect(FinderReveal.versionIDs(for: separate) == [jpeg, raw, single])
        let jpegCell = try #require(separate.first { $0.versionID == jpeg })
        #expect(FinderReveal.versionIDs(for: [jpegCell]) == [jpeg])

        // Grouped, but a search shows the JPEG alone: it stands for itself.
        let alone = try await fixture.catalog.libraryItems(matching: LibraryFilter(search: "IMG_1.JPG", groupsPairs: true))
        #expect(alone.count == 1 && !alone[0].representsPair)
        #expect(FinderReveal.versionIDs(for: alone) == [jpeg])
    }

    @Test("L3: offline and missing photos are left out and counted; each file is listed once")
    func revealOutcome() {
        let a = URL(fileURLWithPath: "/Photos/a.jpg")
        let b = URL(fileURLWithPath: "/Photos/b.jpg")
        let gone = URL(fileURLWithPath: "/Photos/gone.jpg")
        let outcome = FinderReveal.outcome(of: [a, nil, b, gone, a, nil]) { $0 != gone }
        #expect(outcome.urls == [a, b])
        #expect(outcome.offline == 2 && outcome.missing == 1 && outcome.skipped == 3)

        let none = FinderReveal.outcome(of: [nil, gone]) { $0 != gone }
        #expect(none.urls.isEmpty && none.skipped == 2)
        #expect(FinderReveal.outcome(of: []) { _ in true } == FinderReveal.Outcome())
    }

    @Test("L3 / AC12: Show in Finder can act when any target's volume is online, without asking the disk")
    func canReveal() async throws {
        let fixture = try await CatalogFixture.make()
        try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        let items = try await fixture.catalog.libraryItems(matching: LibraryFilter())
        let volume = try #require(fixture.volume.id)
        #expect(FinderReveal.canReveal(items, onlineVolumes: [volume]))
        #expect(!FinderReveal.canReveal(items, onlineVolumes: []))
        #expect(!FinderReveal.canReveal(items, onlineVolumes: [volume + 1]))
        #expect(!FinderReveal.canReveal([CatalogItem](), onlineVolumes: [volume]))
    }

    // MARK: L4: a project's folder

    @Test("L4 / AC12: a project's folder can be revealed only when it has one, its volume is mounted, it exists and it is not a mount point")
    func projectFolderRule() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "Shoot", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = root.appending(path: "notes.txt")
            try Data("x".utf8).write(to: file)

            // No source folder.
            #expect(ProjectFolder.state(sourcePath: nil, volumesOnline: true) == .noFolder)
            #expect(ProjectFolder.state(sourcePath: "", volumesOnline: true) == .noFolder)
            // A mount point: the boot volume's, on the real file system.
            #expect(ProjectFolder.state(sourcePath: "/", volumesOnline: true) == .mountPoint)
            // Folder missing, or a file where the folder was.
            #expect(ProjectFolder.state(sourcePath: root.appending(path: "Gone").path, volumesOnline: true) == .missing)
            #expect(ProjectFolder.state(sourcePath: file.path, volumesOnline: true) == .missing)
            // Volume unmounted: the disk is not asked, even though the path exists.
            var asked = false
            let offline = ProjectFolder.state(sourcePath: folder.path, volumesOnline: false) { _ in
                asked = true
                return ProjectFolder.Probe(isDirectory: true, isVolume: false)
            }
            #expect(offline == .volumeOffline && !asked)
            // Folder present.
            let present = ProjectFolder.state(sourcePath: folder.path, volumesOnline: true)
            #expect(present.url?.standardizedFileURL == folder.standardizedFileURL)
            for state in [ProjectFolder.State.noFolder, .volumeOffline, .missing, .mountPoint] {
                #expect(state.url == nil)
            }
        }
    }

    @Test("L4: the volumes holding each project's photos")
    func projectVolumes() async throws {
        let fixture = try await CatalogFixture.make()
        let empty = try await fixture.catalog.createProject(name: "Empty")
        try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        let volumes = try await fixture.catalog.projectVolumeIDs()
        #expect(volumes[try #require(fixture.project.id)] == [try #require(fixture.volume.id)])
        #expect(volumes[try #require(empty.id)] == nil)
    }

    // MARK: L6: the photo confirmation

    @Test("L6 / AC5, AC7: what the photo confirmation says for one photo, several, a grouped pair and an ungrouped JPEG")
    func photoConfirmation() {
        // One photo.
        #expect(RemovalConfirmation.photos(shown: 1, fileName: "DSC00232.ARW", fileCount: 1)
            == RemovalConfirmation(title: .photo(fileName: "DSC00232.ARW"), sentences: [.photosConsequences]))
        // Several.
        #expect(RemovalConfirmation.photos(shown: 12, fileName: nil, fileCount: 12)
            == RemovalConfirmation(title: .photos(12), sentences: [.photosConsequences]))
        // One grouped pair: one photo, two files.
        #expect(RemovalConfirmation.photos(shown: 1, fileName: "P1000123.RW2", fileCount: 2)
            == RemovalConfirmation(title: .photo(fileName: "P1000123.RW2"), sentences: [.pairFiles(2), .photosConsequences]))
        // The JPEG of an ungrouped pair: its RAW goes too.
        #expect(RemovalConfirmation.photos(shown: 1, fileName: "P1000123.JPG", fileCount: 2)
            == RemovalConfirmation(title: .photo(fileName: "P1000123.JPG"), sentences: [.pairFiles(2), .photosConsequences]))
        // Both files of an ungrouped pair selected: nothing is added beyond what was chosen.
        #expect(RemovalConfirmation.photos(shown: 2, fileName: nil, fileCount: 2).sentences == [.photosConsequences])
        // Three grouped cells, two of them pairs.
        #expect(RemovalConfirmation.photos(shown: 3, fileName: nil, fileCount: 5)
            == RemovalConfirmation(title: .photos(3), sentences: [.pairFiles(5), .photosConsequences]))
        // The consequences are always last.
        #expect(RemovalConfirmation.photos(shown: 3, fileName: nil, fileCount: 5).sentences.last == .photosConsequences)
    }

    // MARK: L8: the project confirmation

    @Test("L8 / AC6: what the project confirmation says with photos, pairs, its own albums, and for an empty project")
    func projectConfirmation() {
        // Photos only.
        #expect(RemovalConfirmation.project(name: "100OLYMP", photoCount: 40, fileCount: 40, albumCount: 0)
            == RemovalConfirmation(title: .project(name: "100OLYMP"), sentences: [.projectPhotos(40), .projectConsequences]))
        // Pairs add files.
        #expect(RemovalConfirmation.project(name: "P", photoCount: 40, fileCount: 70, albumCount: 0).sentences
            == [.projectPhotos(40), .pairFiles(70), .projectConsequences])
        // Its own albums are named only when there are some.
        #expect(RemovalConfirmation.project(name: "P", photoCount: 40, fileCount: 70, albumCount: 3).sentences
            == [.projectPhotos(40), .pairFiles(70), .projectAlbums(3), .projectConsequences])
        #expect(RemovalConfirmation.project(name: "P", photoCount: 1, fileCount: 1, albumCount: 1).sentences
            == [.projectPhotos(1), .projectAlbums(1), .projectConsequences])
        // An empty project, with and without albums.
        #expect(RemovalConfirmation.project(name: "P", photoCount: 0, fileCount: 0, albumCount: 0).sentences
            == [.projectHasNoPhotos, .emptyProjectConsequences])
        #expect(RemovalConfirmation.project(name: "P", photoCount: 0, fileCount: 0, albumCount: 2).sentences
            == [.projectHasNoPhotos, .projectAlbums(2), .emptyProjectConsequences])
    }

    @Test("L8: the project confirmation is built from the catalog's plan")
    func projectConfirmationFromPlan() async throws {
        let fixture = try await CatalogFixture.make(projectName: "Wrong Card")
        try await fixture.addMasters([Self.master("a/IMG_1.NEF", 1), Self.master("a/IMG_1.JPG", 2)])
        _ = try await fixture.catalog.createAlbum(name: "Own", projectID: fixture.project.id)
        let plan = try #require(try await fixture.catalog.projectRemovalPlan(id: fixture.project.id!))
        #expect(RemovalConfirmation.project(plan)
            == RemovalConfirmation(title: .project(name: "Wrong Card"),
                                   sentences: [.projectPhotos(1), .pairFiles(2), .projectAlbums(1), .projectConsequences]))
    }

    // MARK: Design §6.3: focus after a removal

    @Test("§6.3: after a removal that took the focused photo, the focus goes to the photo after the last removed one, or the one before")
    func focusAfterRemoval() {
        // The focused photo is among the removed, as when photos are removed.
        func focus(_ count: Int, _ removed: Set<Int>) -> Int? {
            RemovalFocus.index(count: count, focus: removed.min(), isRemoved: removed.contains)
        }
        #expect(focus(5, [1]) == 2)
        #expect(focus(5, [1, 3]) == 4)
        // The last photo removed: the nearest one before it that stays.
        #expect(focus(5, [4]) == 3)
        #expect(focus(5, [2, 3, 4]) == 1)
        #expect(focus(5, [0, 4]) == 3)
        // Everything removed, or nothing.
        #expect(focus(3, [0, 1, 2]) == nil)
        #expect(focus(3, []) == nil)
        #expect(focus(0, []) == nil)
        // The same without a focused photo.
        #expect(RemovalFocus.index(count: 5, focus: nil, isRemoved: [1, 3].contains) == 4)
    }

    @Test("§7.3: a focused photo the removal did not take keeps the focus (a project removed while another source is shown)")
    func focusSurvivesARemovalElsewhere() {
        // All Photos: project B's photos are at 1, 2 and 4; the loupe is on a photo of project A.
        let removed: Set<Int> = [1, 2, 4]
        #expect(RemovalFocus.index(count: 6, focus: 0, isRemoved: removed.contains) == 0)
        #expect(RemovalFocus.index(count: 6, focus: 3, isRemoved: removed.contains) == 3)
        #expect(RemovalFocus.index(count: 6, focus: 5, isRemoved: removed.contains) == 5)
        // On one of B's photos: the rule for a removed focus.
        #expect(RemovalFocus.index(count: 6, focus: 2, isRemoved: removed.contains) == 5)
        // Nothing of the source on screen was removed: the focus stays where it is.
        #expect(RemovalFocus.index(count: 6, focus: 3, isRemoved: { _ in false }) == 3)
        // A focus index outside the list is no focus.
        #expect(RemovalFocus.index(count: 6, focus: 9, isRemoved: removed.contains) == 5)
    }

    // MARK: Design §8: beside running jobs

    @Test("§8: a removal starts only when no import and no other removal runs")
    func removalAvailability() {
        func can(removing: Bool = false, adding: Bool = false, copying: Bool = false) -> Bool {
            RemovalAvailability.canStart(isRemoving: removing, isAddingFolders: adding, isCopying: copying)
        }
        #expect(can())
        #expect(!can(removing: true))
        #expect(!can(adding: true))
        #expect(!can(copying: true))
    }
}
