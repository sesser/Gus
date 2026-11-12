import Foundation
import GRDB
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Renaming an album in place in the sidebar
/// (docs/features/rename-albums-in-place/prd.md, AC1–AC9): the rules behind
/// it and what the catalog keeps. The routes, the field and undo are checked
/// in the app with the debug script (`status.md`).
@Suite("Album rename")
struct AlbumRenameTests {
    // MARK: Helpers

    private static func count(_ catalog: Catalog, _ table: String) async throws -> Int {
        try await catalog.database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM " + table) ?? 0 }
    }

    /// Rows per table, to compare a catalog before and after.
    private static func rowCounts(_ catalog: Catalog) async throws -> [String: Int] {
        let tables = ["project", "image", "version", "album", "albumMember", "smartAlbum", "keyword", "versionKeyword",
                      "metadataSync", "sidecarQueue", "editHistory"]
        var counts: [String: Int] = [:]
        for table in tables { counts[table] = try await count(catalog, table) }
        return counts
    }

    /// A file's content hash and modification date.
    private struct FileState: Equatable {
        var hash: String
        var modified: Date

        init(_ url: URL) async throws {
            hash = try await SHA256ContentHasher().contentHash(of: url)
            modified = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        }
    }

    private static func files(in folder: URL) async throws -> [String: FileState] {
        var states: [String: FileState] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
            states[name] = try await FileState(folder.appending(path: name))
        }
        return states
    }

    // MARK: AC3: the name rule, shared with projects

    @Test("AC3: a typed album name is trimmed, an empty one refused, the same one a no-op")
    func albumNameRule() {
        #expect(InPlaceRename.resolve(typed: "Iceland best of", current: "Best of") == .rename("Iceland best of"))
        #expect(InPlaceRename.resolve(typed: "  Trip  ", current: "Best of") == .rename("Trip"))
        #expect(InPlaceRename.resolve(typed: "\tTrip\n", current: "Best of") == .rename("Trip"))
        // Refused: the old name stays.
        #expect(InPlaceRename.resolve(typed: "", current: "Best of") == .refused)
        #expect(InPlaceRename.resolve(typed: " \t\n ", current: "Best of") == .refused)
        // The name it has, with or without white space around it: no undo step.
        #expect(InPlaceRename.resolve(typed: "Best of", current: "Best of") == .unchanged)
        #expect(InPlaceRename.resolve(typed: "  Best of ", current: "Best of") == .unchanged)
        // Only the case differs: that is a change.
        #expect(InPlaceRename.resolve(typed: "best of", current: "Best of") == .rename("best of"))
    }

    @Test("A3: white space inside a name is kept, for an album as for a project; the New Album sheet's rule collapses it")
    func innerWhiteSpaceIsKept() {
        #expect(InPlaceRename.resolve(typed: " Best   of ", current: "Trip") == .rename("Best   of"))
        // What the removed Rename sheet did, and New Album still does.
        #expect(Catalog.normalizedKeywordName(" Best   of ") == "Best of")
    }

    // MARK: AC1, AC3: what the catalog keeps

    @Test("AC1, AC3: an album's new name is stored, in a project or the library; two albums may share a name")
    func renamingAnAlbum() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "catalog.sqlite")
            let libraryAlbum: Int64
            let projectAlbum: Int64
            do {
                let catalog = try Catalog.open(at: url)
                let project = try #require(try await catalog.createProject(name: "Iceland").id)
                libraryAlbum = try #require(try await catalog.createAlbum(name: "Best of").id)
                projectAlbum = try #require(try await catalog.createAlbum(name: "Selects", projectID: project).id)
                _ = try await catalog.createAlbum(name: "Iceland best of")
                try await catalog.renameAlbum(id: libraryAlbum, to: "Iceland best of")
                try await catalog.renameAlbum(id: projectAlbum, to: "Iceland best of")
            }
            // After a relaunch.
            let albums = try await Catalog.open(at: url).albumSummaries()
            #expect(albums.map(\.album.name) == ["Iceland best of", "Iceland best of", "Iceland best of"])
            #expect(albums.first { $0.id == libraryAlbum }?.album.projectId == nil)
            #expect(albums.first { $0.id == projectAlbum }?.album.projectId != nil)
        }
    }

    // MARK: AC7: the catalog only

    @Test("AC7: renaming an album keeps its photos and count, changes no other row, queues no sidecar write and touches no file")
    func renamingAnAlbumChangesOnlyItsName() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "Shoot")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, name) in ["a.jpg", "b.jpg", "c.jpg"].enumerated() {
                try SyntheticImages.writeJPEG(to: folder.appending(path: name), width: 64, height: 48, seed: UInt64(index + 1),
                                              exif: .init(dateTimeOriginal: "2024:05:01 10:00:0\(index)"))
            }
            _ = try SidecarFiles.write(SidecarValues(rating: Rating(clamping: 3), keywords: ["dog"]), previous: nil,
                                       to: folder.appending(path: "a.xmp"))
            let catalog = try Catalog.makeInMemory()
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(folder)
            let sync = SidecarSync(catalog: catalog, metadataReader: ImageIOMetadataReader())
            let mounted = Set(try await catalog.volumes().compactMap(\.id))
            let items = try await catalog.libraryItems(matching: LibraryFilter(groupsPairs: false))
            let members = items.filter { $0.fileName != "c.jpg" }.map(\.versionID)

            let id = try #require(try await catalog.createAlbum(name: "Best of").id)
            try await catalog.addVersions(members, toAlbum: id)
            let stored = try #require(try await catalog.albumSummaries().first)
            // Nothing is waiting to be written when the rename starts.
            _ = try await sync.processQueue(mountedVolumes: mounted)
            #expect(try await Self.count(catalog, "sidecarQueue") == 0)
            let counts = try await Self.rowCounts(catalog)
            let before = try await Self.files(in: folder)
            let memberRows = try await catalog.database.read { db in
                try AlbumMemberRecord.filter(AlbumMemberRecord.Columns.albumId == id).fetchSet(db)
            }

            try await catalog.renameAlbum(id: id, to: "Iceland best of")

            let renamed = try #require(try await catalog.albumSummaries().first)
            #expect(renamed.album.name == "Iceland best of")
            #expect(renamed.count == 2)
            // The same album: only its name differs.
            var expected = stored
            expected.album.name = "Iceland best of"
            #expect(renamed == expected)
            #expect(Set(try await catalog.versionIDs(inAlbum: id)) == Set(members))
            #expect(try await catalog.database.read { db in
                try AlbumMemberRecord.filter(AlbumMemberRecord.Columns.albumId == id).fetchSet(db)
            } == memberRows)
            #expect(try await Self.rowCounts(catalog) == counts)
            #expect(try await Self.count(catalog, "sidecarQueue") == 0)
            _ = try await sync.processQueue(mountedVolumes: mounted)
            #expect(try await Self.files(in: folder) == before)
        }
    }

    // MARK: AC9: the row's place after a rename

    @Test("AC9: albums sorted in memory are in the catalog's order, so a renamed album moves to its place at once")
    func renamedAlbumTakesItsPlaceInTheList() async throws {
        let catalog = try Catalog.makeInMemory()
        // Case, digits, a name that begins another, names that differ only in
        // case (by id then), and letters outside ASCII (compared byte by byte).
        let names = ["beach", "Alps", "alps", "ALPS", "Alpine", "Alp", "Zoo", "Ärger", "ärger", "été", "10 best", "2 best", "_drafts", "a b", "ab"]
        for name in names { _ = try await catalog.createAlbum(name: name) }
        let listed = try await catalog.albumSummaries()
        #expect(listed.reversed().sorted(by: AlbumSummary.isListedBefore) == listed)
        #expect(listed.shuffled().sorted(by: AlbumSummary.isListedBefore) == listed)

        // "Alps" to "Zebra": the model changes the name and sorts; the catalog agrees once the write lands.
        let moved = try #require(listed.first { $0.album.name == "Alps" })
        var inMemory = listed
        inMemory[try #require(inMemory.firstIndex(of: moved))].album.name = "Zebra"
        inMemory.sort(by: AlbumSummary.isListedBefore)
        try await catalog.renameAlbum(id: moved.id, to: "Zebra")
        let after = try await catalog.albumSummaries()
        #expect(inMemory == after)
        #expect(after.firstIndex { $0.id == moved.id } != listed.firstIndex { $0.id == moved.id })
    }

    @Test("AC9: File ▸ Rename shows the row where it lives: the Albums section, or the album's project in Projects")
    func rowPlace() {
        #expect(SidebarRowPlace.album(inProject: nil) == .albums)
        #expect(SidebarRowPlace.album(inProject: 7) == .projects(expanding: 7))
        #expect(SidebarRowPlace.project == .projects(expanding: nil))
    }

    // MARK: AC5, AC6: which items rename in place

    @Test("AC5, AC6: projects and albums rename in place with no ellipsis; a keyword keeps its sheet; a smart album has no Rename")
    func renameRoutes() {
        #expect(SidebarRenameRoute.route(for: .album) == .inPlace)
        #expect(SidebarRenameRoute.route(for: .project) == .inPlace)
        #expect(SidebarRenameRoute.route(for: .keyword) == .sheet)
        #expect(SidebarRenameRoute.route(for: .smartAlbum) == nil)
        // The ellipsis says more input follows: only the keyword's sheet.
        #expect(!SidebarRenameRoute.inPlace.titleHasEllipsis)
        #expect(SidebarRenameRoute.sheet.titleHasEllipsis)
        #expect(SidebarRenameRoute.Item.allCases.filter { SidebarRenameRoute.route(for: $0) == .inPlace } == [.project, .album])
    }
}
