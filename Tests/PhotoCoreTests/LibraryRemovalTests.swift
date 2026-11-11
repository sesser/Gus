import Foundation
import GRDB
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Removing photos and projects from the library, and renaming a project
/// (docs/features/library-ops/prd.md, AC1–AC10): the catalog changes, the
/// files never do.
@Suite("Library removal")
struct LibraryRemovalTests {
    // MARK: Helpers

    private static func master(_ path: String, _ index: Int) -> NewMaster {
        CatalogFixture.master(index, hash: String(format: "%064x", index), path: path)
    }

    private static func count(_ catalog: Catalog, _ sql: String, _ arguments: StatementArguments = []) async throws -> Int {
        try await catalog.database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM " + sql, arguments: arguments) ?? 0 }
    }

    /// Rows per table, to compare a catalog before and after.
    private static func rowCounts(_ catalog: Catalog) async throws -> [String: Int] {
        let tables = ["project", "image", "version", "album", "albumMember", "smartAlbum", "stack", "stackMember",
                      "keyword", "versionKeyword", "keywordSuggestion", "imagePair", "importRun", "metadataSync",
                      "sidecarQueue", "editHistory"]
        var counts: [String: Int] = [:]
        for table in tables { counts[table] = try await count(catalog, table) }
        return counts
    }

    /// Everything the catalog could hold for a master and its versions.
    private static func references(_ catalog: Catalog, imageID: Int64, versionIDs: [Int64]) async throws -> [String: Int] {
        let versions = versionIDs.map(String.init).joined(separator: ",")
        var found: [String: Int] = [:]
        for table in ["keywordSuggestion", "metadataSync", "sidecarQueue"] {
            found[table] = try await count(catalog, "\(table) WHERE imageId = ?", [imageID])
        }
        found["image"] = try await count(catalog, "image WHERE id = ?", [imageID])
        found["version"] = try await count(catalog, "version WHERE imageId = ?", [imageID])
        found["imagePair"] = try await count(catalog, "imagePair WHERE rawImageId = ? OR companionImageId = ?", [imageID, imageID])
        for table in ["versionKeyword", "albumMember", "stackMember", "editHistory"] {
            found[table] = try await count(catalog, "\(table) WHERE versionId IN (\(versions))")
        }
        found["stack"] = try await count(catalog, "stack WHERE pickVersionId IN (\(versions))")
        return found.filter { $0.value > 0 }
    }

    private static let edit = EditStack(operations: [EditOperation(kind: "exposure", parameters: ["ev": .number(0.7)])])

    /// A file's content hash and modification date.
    private struct FileState: Equatable {
        var hash: String
        var modified: Date

        init(_ url: URL) async throws {
            hash = try await SHA256ContentHasher().contentHash(of: url)
            modified = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        }
    }

    /// A folder of real files, imported in place.
    private struct Library {
        let folder: URL
        let catalog: Catalog
        let importer: Importer
        let sync: SidecarSync
        let mounted: Set<Int64>
        let project: ProjectRecord

        func item(_ name: String) async throws -> CatalogItem {
            try #require(try await catalog.libraryItems(matching: LibraryFilter(groupsPairs: false)).first { $0.fileName == name })
        }

        /// Every file in the folder with its state.
        func files() async throws -> [String: FileState] {
            var states: [String: FileState] = [:]
            for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
                states[name] = try await FileState(folder.appending(path: name))
            }
            return states
        }
    }

    private static func makeLibrary(_ root: URL, files: [String], sidecars: [String: SidecarValues] = [:]) async throws -> Library {
        let folder = root.appending(path: "Shoot")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, name) in files.enumerated() {
            let url = folder.appending(path: name)
            if FileKind(pathExtension: url.pathExtension) == .raw {
                try SyntheticDNG.write(to: url, options: .init(width: 400, height: 300, seed: UInt64(index + 1)))
            } else {
                try SyntheticImages.writeJPEG(to: url, width: 64, height: 48, seed: UInt64(index + 1),
                                              exif: .init(dateTimeOriginal: "2024:05:01 10:00:0\(index)"))
            }
        }
        for (name, values) in sidecars {
            _ = try SidecarFiles.write(values, previous: nil, to: folder.appending(path: name))
        }
        let catalog = try Catalog.makeInMemory()
        let importer = Importer(catalog: catalog, metadataReader: ImageIOMetadataReader())
        let summary = try await importer.importFolder(folder)
        return Library(folder: folder, catalog: catalog, importer: importer,
                       sync: SidecarSync(catalog: catalog, metadataReader: ImageIOMetadataReader()),
                       mounted: Set(try await catalog.volumes().compactMap(\.id)),
                       project: try #require(summary.project))
    }

    // MARK: AC4: one photo

    @Test("AC4: removing a photo leaves no catalog row for it; keywords, albums and its files stay")
    func removingAPhotoTakesItsRowsAndNothingElse() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let values = SidecarValues(rating: Rating(clamping: 2), keywords: ["dog"])
            let library = try await Self.makeLibrary(root, files: ["a.jpg", "b.jpg"], sidecars: ["a.xmp": values, "b.xmp": values])
            let catalog = library.catalog
            let a = try await library.item("a.jpg")
            let b = try await library.item("b.jpg")

            // Edits, a keyword, an album, a rating, a suggestion, and a second version.
            try await catalog.setEditStack(Self.edit, forVersion: a.versionID, historyLabel: "Exposure")
            _ = try await catalog.addKeywords(named: ["beach"], toVersions: [a.versionID, b.versionID])
            let album = try await catalog.createAlbum(name: "Best")
            try await catalog.addVersions([a.versionID, b.versionID], toAlbum: album.id!)
            try await catalog.setRating(Rating(clamping: 5), forVersions: [a.versionID, b.versionID])
            try await catalog.storeSuggestions([SuggestedKeyword(name: "sand", confidence: 0.9)], forImage: a.imageID,
                                               analysisVersion: 1)
            let copy = try #require(try await catalog.duplicateVersion(id: a.versionID).id)
            // The rating and keyword are waiting to be written to both sidecars.
            #expect(try await Self.count(catalog, "sidecarQueue") == 2)
            #expect(try await Self.references(catalog, imageID: a.imageID, versionIDs: [a.versionID, copy]).count >= 7)
            let before = try await library.files()

            let result = try await catalog.removePhotos(versionIDs: [a.versionID])
            #expect(result.imageIDs == [a.imageID])
            #expect(result.versionCount == 2)

            #expect(try await Self.references(catalog, imageID: a.imageID, versionIDs: [a.versionID, copy]) == [:])
            // Keywords and albums stay, and so does everything of the other photo.
            #expect(try await catalog.keywordSummaries().map(\.name).sorted() == ["beach", "dog"])
            #expect(try await catalog.versionIDs(inAlbum: album.id!) == [b.versionID])
            #expect(try await catalog.version(id: b.versionID)?.rating == Rating(clamping: 5))
            #expect(try await catalog.keywords(forVersion: b.versionID).map(\.name) == ["beach", "dog"])
            // b's write is still queued; a's is gone with it.
            let queued = try await catalog.database.read { db in try Int64.fetchAll(db, sql: "SELECT imageId FROM sidecarQueue") }
            #expect(queued == [b.imageID])

            // No file changed, and writing the queue never reaches the removed photo's sidecar.
            #expect(try await library.files() == before)
            let report = try await library.sync.processQueue(mountedVolumes: library.mounted)
            #expect(report.written == 1 && report.failed == 0)
            _ = try await library.sync.checkForChanges(mountedVolumes: library.mounted)
            let after = try await library.files()
            #expect(after["a.jpg"] == before["a.jpg"])
            #expect(after["a.xmp"] == before["a.xmp"])
            #expect(after["b.jpg"] == before["b.jpg"])
            #expect(after["b.xmp"] != before["b.xmp"])
            #expect(try SidecarFiles.read(library.folder.appending(path: "a.xmp")).values.rating == Rating(clamping: 2))
        }
    }

    @Test("R6: removing a version removes its master and every version of it")
    func everyVersionOfTheMasterGoes() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        let copy = try #require(try await fixture.catalog.duplicateVersion(id: ids[0]).id)
        let plan = try await fixture.catalog.photoRemovalPlan(forVersions: [copy])
        #expect(plan.fileCount == 1)
        let result = try await fixture.catalog.removePhotos(versionIDs: [copy])
        #expect(result.versionCount == 2)
        #expect(try await fixture.catalog.version(id: ids[0]) == nil)
        #expect(try await fixture.catalog.versionCount() == 1)
    }

    @Test("R6: stack links go; a stack that keeps a member stays, an emptied one goes")
    func stackLinks() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let stack = try await fixture.catalog.createStack(versionIDs: [ids[0], ids[1]])
        try await fixture.catalog.removePhotos(versionIDs: [ids[0]])
        #expect(try await fixture.catalog.versionIDs(inStack: stack.id!) == [ids[1]])
        let pick = try await fixture.catalog.database.read { db in
            try Int64.fetchOne(db, sql: "SELECT pickVersionId FROM stack WHERE id = ?", arguments: [stack.id])
        }
        #expect(pick == nil)
        try await fixture.catalog.removePhotos(versionIDs: [ids[1]])
        #expect(try await Self.count(fixture.catalog, "stack") == 0)
        #expect(try await fixture.catalog.versionCount() == 1)
    }

    @Test("R6: nothing is queued for a removed photo, whatever its keyword links queued on the way out")
    func cascadesQueueNothing() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([Self.master("a/IMG_1.NEF", 1), Self.master("a/IMG_1.JPG", 2),
                                                Self.master("a/IMG_2.NEF", 3)])
        _ = try await fixture.catalog.addKeywords(named: ["dog", "beach"], toVersions: ids)
        try await fixture.catalog.dequeueSidecarWork(try await fixture.catalog.allImages().compactMap(\.id))
        #expect(try await Self.count(fixture.catalog, "sidecarQueue") == 0)
        try await fixture.catalog.removePhotos(versionIDs: [ids[0]])
        #expect(try await Self.count(fixture.catalog, "sidecarQueue") == 0)
        #expect(try await Self.count(fixture.catalog, "versionKeyword") == 2)
    }

    // MARK: AC5: pairs

    @Test("AC5: removing either file of a RAW+JPEG pair removes both; the plan counts 2 files",
          arguments: [0, 1])
    func removingOneFileOfAPairRemovesBoth(chosen: Int) async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([Self.master("a/IMG_1.NEF", 1), Self.master("a/IMG_1.JPG", 2),
                                                Self.master("a/IMG_2.NEF", 3)])
        let plan = try await fixture.catalog.photoRemovalPlan(forVersions: [ids[chosen]])
        #expect(plan.fileCount == 2)
        #expect(RemovalConfirmation.photos(shown: 1, fileName: "IMG_1.JPG", fileCount: plan.fileCount).sentences
            == [.pairFiles(2), .photosConsequences])

        let result = try await fixture.catalog.removePhotos(versionIDs: [ids[chosen]])
        #expect(result.imageIDs.count == 2)
        #expect(try await fixture.catalog.version(id: ids[0]) == nil)
        #expect(try await fixture.catalog.version(id: ids[1]) == nil)
        #expect(try await fixture.catalog.version(id: ids[2]) != nil)
        #expect(try await Self.count(fixture.catalog, "imagePair") == 0)
        #expect(try await fixture.catalog.allImages().map(\.fileName) == ["IMG_2.NEF"])
    }

    @Test("AC5: both files of a pair chosen together are two files, not three")
    func bothHalvesChosen() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([Self.master("a/IMG_1.NEF", 1), Self.master("a/IMG_1.JPG", 2)])
        #expect(try await fixture.catalog.photoRemovalPlan(forVersions: ids).fileCount == 2)
        #expect(try await fixture.catalog.photoRemovalPlan(forVersions: []).fileCount == 0)
        #expect(try await fixture.catalog.removePhotos(versionIDs: []).imageIDs.isEmpty)
    }

    // MARK: AC6: projects

    @Test("AC6: removing a project takes its photos and its own albums; other albums and keywords stay")
    func removingAProject() async throws {
        let fixture = try await CatalogFixture.make(projectName: "Wrong Card")
        let catalog = fixture.catalog
        let other = try await catalog.createProject(name: "Keep")
        let mine = try await fixture.addMasters([Self.master("a/IMG_1.NEF", 1), Self.master("a/IMG_1.JPG", 2),
                                                 Self.master("a/IMG_2.NEF", 3)])
        let kept = try await fixture.addMasters([Self.master("b/IMG_9.NEF", 9)], project: other)
        _ = try await catalog.createImportRun(sourcePath: "/Volumes/Test/a", projectID: fixture.project.id)
        _ = try await catalog.addKeywords(named: ["dog"], toVersions: mine + kept)
        try await catalog.setEditStack(Self.edit, forVersion: mine[0], historyLabel: "Exposure")
        let own = try await catalog.createAlbum(name: "Own", projectID: fixture.project.id)
        _ = try await catalog.createSmartAlbum(name: "Own smart", projectID: fixture.project.id, rules: SmartAlbumRules())
        let libraryAlbum = try await catalog.createAlbum(name: "Library")
        let othersAlbum = try await catalog.createAlbum(name: "Other's", projectID: other.id)
        _ = try await catalog.createSmartAlbum(name: "Library smart", projectID: nil, rules: SmartAlbumRules())
        try await catalog.addVersions(mine, toAlbum: own.id!)
        try await catalog.addVersions(mine + kept, toAlbum: libraryAlbum.id!)
        try await catalog.addVersions(kept, toAlbum: othersAlbum.id!)

        let plan = try #require(try await catalog.projectRemovalPlan(id: fixture.project.id!))
        #expect(plan.photoCount == 2 && plan.fileCount == 3 && plan.albumCount == 2)
        #expect(try await catalog.projectRemovalPlan(id: fixture.project.id!, groupingPairs: false)?.photoCount == 3)
        #expect(try await catalog.projectRemovalPlan(id: other.id!)?.albumCount == 1)
        #expect(try await catalog.projectRemovalPlan(id: 999) == nil)

        let result = try await catalog.removeProject(id: fixture.project.id!)
        #expect(result.imageIDs.count == 3 && result.versionCount == 3 && result.albumCount == 2)

        #expect(try await catalog.projectSummaries().map(\.project.name) == ["Keep"])
        #expect(try await Self.count(catalog, "image WHERE projectId = ?", [fixture.project.id]) == 0)
        #expect(try await Self.count(catalog, "version") == 1)
        #expect(try await Self.count(catalog, "editHistory") == 0)
        #expect(try await Self.count(catalog, "imagePair") == 0)
        #expect(try await Self.count(catalog, "sidecarQueue WHERE imageId NOT IN (SELECT id FROM image)") == 0)
        #expect(try await catalog.albumSummaries().map(\.album.name) == ["Library", "Other's"])
        #expect(try await catalog.smartAlbums().map(\.name) == ["Library smart"])
        #expect(try await catalog.versionIDs(inAlbum: libraryAlbum.id!) == kept)
        #expect(try await catalog.versionIDs(inAlbum: othersAlbum.id!) == kept)
        #expect(try await catalog.keywordSummaries().map(\.name) == ["dog"])
        #expect(try await catalog.keywords(forVersion: kept[0]).map(\.name) == ["dog"])
        // The import run stays as a record; it points at no project and no photo.
        let runs = try await catalog.database.read { db in try Int64?.fetchAll(db, sql: "SELECT projectId FROM importRun") }
        #expect(runs == [nil])
        #expect(try await catalog.lastImportRun() == nil)
        #expect(try await catalog.volumes().count == 1)
    }

    @Test("AC6: an empty project is removed the same way")
    func removingAnEmptyProject() async throws {
        let fixture = try await CatalogFixture.make()
        let plan = try #require(try await fixture.catalog.projectRemovalPlan(id: fixture.project.id!))
        #expect(plan.photoCount == 0 && plan.fileCount == 0 && plan.albumCount == 0)
        let result = try await fixture.catalog.removeProject(id: fixture.project.id!)
        #expect(result.imageIDs.isEmpty)
        #expect(try await fixture.catalog.projectSummaries().isEmpty)
    }

    @Test("AC6: a project's folder, files and sidecars are untouched by its removal")
    func removingAProjectTouchesNoFile() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await Self.makeLibrary(root, files: ["a.jpg", "b.dng", "b.jpg"],
                                                     sidecars: ["a.xmp": SidecarValues(rating: Rating(clamping: 3))])
            try await library.catalog.setRating(Rating(clamping: 1), forVersions: [try await library.item("a.jpg").versionID])
            let before = try await library.files()
            try await library.catalog.removeProject(id: library.project.id!)
            _ = try await library.sync.processQueue(mountedVolumes: library.mounted)
            #expect(try await library.files() == before)
        }
    }

    // MARK: AC8: offline

    @Test("AC8: an offline photo is removed without reaching its volume")
    func removingAnOfflinePhoto() async throws {
        // The fixture's volume (/Volumes/Test) is not mounted, and no file exists.
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        #expect(try await fixture.catalog.refreshVolumeAvailability(mounted: []).isEmpty)
        try await fixture.catalog.setRating(Rating(clamping: 4), forVersions: [ids[0]])
        try await fixture.catalog.removePhotos(versionIDs: [ids[0]])
        #expect(try await fixture.catalog.version(id: ids[0]) == nil)
        #expect(try await fixture.catalog.versionCount() == 1)
        // Its volume row stays: other photos are on it.
        #expect(try await fixture.catalog.volumes().count == 1)
    }

    // MARK: AC9: importing again

    @Test("AC9: a removed project's folder imports again as new photos, with no edits")
    func reimportAfterRemovingAProject() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await Self.makeLibrary(root, files: ["a.jpg", "b.jpg"])
            let a = try await library.item("a.jpg")
            try await library.catalog.setEditStack(Self.edit, forVersion: a.versionID, historyLabel: "Exposure")
            try await library.catalog.setRating(Rating(clamping: 5), forVersions: [a.versionID])
            try await library.catalog.removeProject(id: library.project.id!)
            #expect(try await library.catalog.versionCount() == 0)

            let summary = try await library.importer.importFolder(library.folder)
            #expect(summary.progress.imported == 2)
            let again = try await library.item("a.jpg")
            #expect(again.versionID != a.versionID)
            #expect(again.contentHash == a.contentHash)
            #expect(again.rating == .unrated)
            let version = try #require(try await library.catalog.version(id: again.versionID))
            #expect(try version.decodedEditStack() == .identity)
            #expect(try await library.catalog.editHistory(forVersion: again.versionID).isEmpty)
        }
    }

    @Test("AC9: removed photos import again; the ones still in the library are not doubled")
    func reimportAfterRemovingPhotos() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await Self.makeLibrary(root, files: ["a.jpg", "b.jpg", "c.jpg"])
            let a = try await library.item("a.jpg")
            try await library.catalog.setEditStack(Self.edit, forVersion: a.versionID, historyLabel: "Exposure")
            try await library.catalog.removePhotos(versionIDs: [a.versionID])

            let summary = try await library.importer.importFolder(library.folder)
            #expect(summary.progress.imported == 1)
            #expect(try await library.catalog.versionCount() == 3)
            let again = try await library.item("a.jpg")
            #expect(again.versionID != a.versionID)
            #expect(again.editStackHash == EditStack.identity.renderHash)
        }
    }

    // MARK: AC10: all or nothing

    /// Makes the removal's second statement fail: the masters are deleted by
    /// then, so only the transaction can put them back.
    private static func failQueueDeletes(_ catalog: Catalog) async throws {
        try await catalog.database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER forced_failure BEFORE DELETE ON sidecarQueue
                BEGIN SELECT RAISE(ABORT, 'forced failure'); END
                """)
        }
    }

    @Test("AC10: a removal that fails part way leaves the catalog as it was")
    func aFailedRemovalChangesNothing() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([Self.master("a/IMG_1.NEF", 1), Self.master("a/IMG_1.JPG", 2),
                                                Self.master("a/IMG_2.NEF", 3)])
        _ = try await catalog.addKeywords(named: ["dog"], toVersions: ids)
        let album = try await catalog.createAlbum(name: "Own", projectID: fixture.project.id)
        try await catalog.addVersions(ids, toAlbum: album.id!)
        try await catalog.setEditStack(Self.edit, forVersion: ids[0], historyLabel: "Exposure")
        _ = try await catalog.createStack(versionIDs: [ids[0], ids[2]])
        let before = try await Self.rowCounts(catalog)
        #expect(before["sidecarQueue"] == 3)
        try await Self.failQueueDeletes(catalog)

        await #expect(throws: DatabaseError.self) { try await catalog.removePhotos(versionIDs: [ids[1]]) }
        #expect(try await Self.rowCounts(catalog) == before)
        await #expect(throws: DatabaseError.self) { try await catalog.removeProject(id: fixture.project.id!) }
        #expect(try await Self.rowCounts(catalog) == before)
        #expect(try await catalog.version(id: ids[0])?.editStackHash == Self.edit.renderHash)

        // Without the failure the same removal goes through.
        try await catalog.database.write { db in try db.execute(sql: "DROP TRIGGER forced_failure") }
        try await catalog.removeProject(id: fixture.project.id!)
        #expect(try await Self.count(catalog, "image") == 0)
    }

    // MARK: Design §8: beside running jobs

    @Test("§8: an import into a project that was removed under it fails, which is why a removal waits for imports")
    func importIntoARemovedProjectFails() async throws {
        let fixture = try await CatalogFixture.make()
        try await fixture.addMasters([CatalogFixture.master(1)])
        try await fixture.catalog.removeProject(id: fixture.project.id!)
        await #expect(throws: DatabaseError.self) {
            try await fixture.addMasters([CatalogFixture.master(2)])
        }
        #expect(try await Self.count(fixture.catalog, "image") == 0)
    }

    @Test("§8: a batch edit that ends after some of its photos were removed changes the rest and nothing else")
    func batchEditAfterARemoval() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        try await fixture.catalog.removePhotos(versionIDs: [ids[1]])
        let change = try await fixture.catalog.changeEditStacks(ofVersions: ids, historyLabel: "Auto Exposure") { values in
            var values = values
            values.exposure.ev = 0.5
            return values
        }
        #expect(Set(change.after.keys) == [ids[0], ids[2]])
        #expect(try await Self.count(fixture.catalog, "version") == 2)
        #expect(try await Self.count(fixture.catalog, "editHistory") == 2)
        // Its undo writes back what it read: the same two photos.
        try await fixture.catalog.setEditStacks(change.before, historyLabel: "Undo Auto Exposure")
        #expect(try await fixture.catalog.version(id: ids[0])?.editStackHash == EditStack.identity.renderHash)
    }

    // MARK: Sidecar checks beside a removal

    @Test("A sidecar check that ends after its photo was removed records nothing and does not fail")
    func savingSyncForARemovedMaster() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1)])
        let image = try #require(try await fixture.catalog.details(forVersion: ids[0])?.image.id)
        let record = try #require(try await fixture.catalog.sidecarTargets(owners: [image]).first?.sync)
        try await fixture.catalog.removePhotos(versionIDs: ids)
        try await fixture.catalog.saveSync(record)
        #expect(try await Self.count(fixture.catalog, "metadataSync") == 0)
    }

    @Test("A cancelled sidecar run stops before the next file and keeps the rest queued")
    func cancelledQueueRunStops() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await Self.makeLibrary(root, files: ["a.jpg", "b.jpg"])
            let ids = [try await library.item("a.jpg").versionID, try await library.item("b.jpg").versionID]
            try await library.catalog.setRating(Rating(clamping: 4), forVersions: ids)
            let before = try await library.files()
            let run = Task { try await library.sync.processQueue(mountedVolumes: library.mounted) }
            run.cancel()
            await #expect(throws: CancellationError.self) { try await run.value }
            #expect(try await library.files() == before)
            #expect(try await Self.count(library.catalog, "sidecarQueue") == 2)
        }
    }

    // MARK: AC1–AC3: renaming a project

    @Test("AC1: a project's new name is stored; two projects may share a name")
    func renamingAProject() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "catalog.sqlite")
            let first: Int64
            do {
                let catalog = try Catalog.open(at: url)
                first = try #require(try await catalog.createProject(name: "100OLYMP", sourcePath: "/Volumes/Card/DCIM/100OLYMP").id)
                _ = try await catalog.createProject(name: "Iceland 2026")
                try await catalog.renameProject(id: first, to: "Iceland 2026")
            }
            // After a relaunch.
            let reopened = try Catalog.open(at: url)
            let projects = try await reopened.projectSummaries()
            #expect(projects.map(\.project.name) == ["Iceland 2026", "Iceland 2026"])
            // The folder it came from is recorded as before.
            #expect(projects.first { $0.id == first }?.project.sourcePath == "/Volumes/Card/DCIM/100OLYMP")
        }
    }

    @Test("AC3: renaming a project changes no folder, no file and no sidecar, and queues no sidecar write")
    func renamingAProjectTouchesNoFile() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await Self.makeLibrary(root, files: ["a.jpg", "b.jpg"],
                                                     sidecars: ["a.xmp": SidecarValues(rating: Rating(clamping: 3))])
            let before = try await library.files()
            let counts = try await Self.rowCounts(library.catalog)
            try await library.catalog.renameProject(id: library.project.id!, to: "Iceland 2026")
            #expect(try await library.catalog.projectSummaries().first?.project.name == "Iceland 2026")
            #expect(try await Self.rowCounts(library.catalog) == counts)
            _ = try await library.sync.processQueue(mountedVolumes: library.mounted)
            #expect(try await library.files() == before)
            #expect(FileManager.default.fileExists(atPath: library.folder.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["Shoot"])
            #expect(try await library.catalog.projectSummaries().first?.project.sourcePath == library.folder.path)
        }
    }
}
