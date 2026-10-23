import Foundation
import GRDB
import Testing
@testable import PhotoCore

@Suite("Catalog")
struct CatalogTests {
    // MARK: Schema

    @Test func migrationsCreateTheExpectedTables() async throws {
        let catalog = try Catalog.makeInMemory()
        let tables = try await catalog.database.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'")
        }
        #expect(tables == ["volume", "project", "image", "version", "album", "albumMember",
                           "stack", "stackMember", "keyword", "versionKeyword", "imagePair", "keywordSuggestion",
                           "importRun", "smartAlbum", "metadataSync", "sidecarQueue", "importPreset"])
        let applied = try await catalog.database.read { db in try CatalogSchema.migrator.appliedMigrations(db) }
        #expect(applied == ["v1", "v2", "v3", "v4", "v5", "v6"])
    }

    @Test func schemaNamesDoNotEmbedTheProductName() async throws {
        let catalog = try Catalog.makeInMemory()
        let schema = try await catalog.database.read { db in
            try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL")
        }
        let hits = BrandScanner.current.hits(in: schema.joined(separator: "\n"), file: "schema")
        #expect(hits.isEmpty, "\(hits)")
    }

    @Test func fileBackedCatalogPersistsAcrossReopen() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "nested/catalog.sqlite")
            do {
                let catalog = try Catalog.open(at: url)
                _ = try await catalog.createProject(name: "Persisted")
            }
            let reopened = try Catalog.open(at: url)
            let projects = try await reopened.projectSummaries()
            #expect(projects.map(\.project.name) == ["Persisted"])
            let journal = try await reopened.database.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
            #expect(journal == "wal")
        }
    }

    // MARK: Masters and versions

    @Test func insertingAMasterCreatesOneDefaultVersion() async throws {
        let fixture = try await CatalogFixture.make()
        let versionIDs = try await fixture.addMasters([CatalogFixture.master(1)])
        let version = try #require(try await fixture.catalog.version(id: versionIDs[0]))
        #expect(version.isDefault)
        #expect(version.versionNumber == 1)
        #expect(version.rating == .unrated)
        #expect(version.flag == .none)
        #expect(version.colorLabel == .none)
        #expect(try version.decodedEditStack() == .identity)
        #expect(version.editStackHash == EditStack.identity.renderHash)

        let details = try #require(try await fixture.catalog.details(forVersion: versionIDs[0]))
        #expect(details.image.fileName == "IMG_0001.CR3")
        #expect(details.image.format == "cr3")
        #expect(details.image.pixelWidth == 6000)
        #expect(details.volume.identity == "TEST-VOLUME")
        #expect(details.volume.url(forRelativePath: details.image.relativePath).path
            == "/Volumes/Test/shoot/IMG_0001.CR3")
    }

    @Test func duplicateHashesAndPathsAreSkippedNotFatal() async throws {
        let fixture = try await CatalogFixture.make()
        try await fixture.addMasters([CatalogFixture.master(1, hash: "aaa")])
        let result = try await fixture.catalog.insertMasters([
            CatalogFixture.master(2, hash: "aaa"),                              // same content elsewhere
            CatalogFixture.master(3, hash: "bbb", path: "shoot/IMG_0001.CR3"),  // same path, new content
            CatalogFixture.master(4, hash: "ccc"),
        ], volumeID: fixture.volume.id!, projectID: fixture.project.id!)
        #expect(result.duplicateHashes == ["aaa"])
        #expect(result.conflictingPaths == ["shoot/IMG_0001.CR3"])
        #expect(result.insertedImageIDs.count == 1)
        #expect(try await fixture.catalog.versionCount() == 2)
        #expect(try await fixture.catalog.existingContentHashes(["aaa", "bbb", "ccc"]) == ["aaa", "ccc"])
    }

    @Test func knownFilesAreReportedByPath() async throws {
        let fixture = try await CatalogFixture.make()
        try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        let known = try await fixture.catalog.knownFiles(
            volumeID: fixture.volume.id!, relativePaths: ["shoot/IMG_0002.CR3", "shoot/missing.CR3"])
        #expect(Array(known.keys) == ["shoot/IMG_0002.CR3"])
        #expect(known["shoot/IMG_0002.CR3"]?.fileSize == 1002)
    }

    @Test func aMasterCanHaveManyVersionsButOneDefault() async throws {
        let fixture = try await CatalogFixture.make()
        let original = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        try await fixture.catalog.setRating(Rating(clamping: 4), forVersions: [original])
        let copy = try await fixture.catalog.duplicateVersion(id: original)
        #expect(copy.versionNumber == 2)
        #expect(!copy.isDefault)
        #expect(copy.rating == Rating(clamping: 4))
        let all = try await fixture.catalog.versions(ofImage: copy.imageId)
        #expect(all.map(\.versionNumber) == [1, 2])

        await #expect(throws: DatabaseError.self) {
            try await fixture.catalog.database.write { db in
                try db.execute(sql: "UPDATE version SET isDefault = 1 WHERE id = ?", arguments: [copy.id])
            }
        }
    }

    @Test func editStackAndHashAreWrittenTogether() async throws {
        let fixture = try await CatalogFixture.make()
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        let stack = EditStack(operations: [EditOperation(kind: "exposure", parameters: ["ev": .number(0.7)])])
        try await fixture.catalog.setEditStack(stack, forVersion: id)
        let version = try #require(try await fixture.catalog.version(id: id))
        #expect(try version.decodedEditStack() == stack)
        #expect(version.editStackHash == stack.renderHash)
    }

    // MARK: Culling

    @Test func cullingValuesPersistImmediately() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        try await fixture.catalog.setRating(Rating(clamping: 5), forVersions: [ids[0], ids[1]])
        try await fixture.catalog.setFlag(.picked, forVersions: [ids[0]])
        try await fixture.catalog.setFlag(.rejected, forVersions: [ids[2]])
        try await fixture.catalog.setColorLabel(.purple, forVersions: [ids[1]])

        let versions = try await ids.asyncMap { try await fixture.catalog.version(id: $0)! }
        #expect(versions.map(\.rating.rawValue) == [5, 5, 0])
        #expect(versions.map(\.flag) == [.picked, .none, .rejected])
        #expect(versions.map(\.colorLabel) == [.none, .purple, .none])
    }

    @Test func databaseRejectsOutOfRangeCullingValues() async throws {
        let fixture = try await CatalogFixture.make()
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        #expect(Rating(rawValue: 6) == nil)
        #expect(Rating(clamping: 9).rawValue == 5)
        for sql in ["UPDATE version SET rating = 6 WHERE id = ?",
                    "UPDATE version SET flag = 2 WHERE id = ?",
                    "UPDATE version SET colorLabel = 8 WHERE id = ?"] {
            await #expect(throws: DatabaseError.self) {
                try await fixture.catalog.database.write { db in try db.execute(sql: sql, arguments: [id]) }
            }
        }
    }

    // MARK: Library queries

    @Test func libraryItemsFollowCaptureOrderAndFilters() async throws {
        let fixture = try await CatalogFixture.make()
        let other = try await fixture.catalog.createProject(name: "Other")
        let base = Date(timeIntervalSince1970: 1_650_000_000)
        // Inserted out of capture order on purpose.
        let ids = try await fixture.addMasters([
            CatalogFixture.master(1, captureDate: base.addingTimeInterval(30)),
            CatalogFixture.master(2, captureDate: base.addingTimeInterval(10)),
            CatalogFixture.master(3, captureDate: base.addingTimeInterval(20)),
        ])
        let otherIDs = try await fixture.addMasters([CatalogFixture.master(4, captureDate: base)], project: other)
        try await fixture.catalog.setRating(Rating(clamping: 3), forVersions: [ids[0]])
        try await fixture.catalog.setRating(Rating(clamping: 1), forVersions: [ids[1]])
        try await fixture.catalog.setFlag(.picked, forVersions: [ids[1]])
        try await fixture.catalog.setFlag(.rejected, forVersions: [ids[2]])

        func query(_ filter: LibraryFilter) async throws -> [Int64] {
            try await fixture.catalog.libraryItems(matching: filter).map(\.versionID)
        }
        let project = LibraryFilter.Scope.project(fixture.project.id!)
        #expect(try await query(LibraryFilter()) == [otherIDs[0], ids[1], ids[2], ids[0]])
        #expect(try await query(LibraryFilter(scope: project)) == [ids[1], ids[2], ids[0]])
        #expect(try await query(LibraryFilter(scope: .project(other.id!))) == otherIDs)
        #expect(try await query(LibraryFilter(scope: project, rating: .atLeast(Rating(clamping: 2)))) == [ids[0]])
        #expect(try await query(LibraryFilter(scope: project, rating: .atLeast(Rating(clamping: 1)))) == [ids[1], ids[0]])
        #expect(try await query(LibraryFilter(scope: project, rating: .exactly(Rating(clamping: 1)))) == [ids[1]])
        #expect(try await query(LibraryFilter(scope: project, rating: .unrated)) == [ids[2]])
        #expect(try await query(LibraryFilter(scope: project, flag: .picked)) == [ids[1]])
        #expect(try await query(LibraryFilter(scope: project, flag: .rejected)) == [ids[2]])
        #expect(try await query(LibraryFilter(scope: project, flag: .notRejected)) == [ids[1], ids[0]])
        #expect(try await query(LibraryFilter(scope: project, flag: .unflagged)) == [ids[0]])
        #expect(try await query(LibraryFilter(scope: project, rating: .atLeast(Rating(clamping: 1)), flag: .picked)) == [ids[1]])

        let item = try #require(try await fixture.catalog.libraryItems(matching: LibraryFilter(scope: project)).first)
        #expect(item.rating == Rating(clamping: 1))
        #expect(item.flag == .picked)
        #expect(item.fileName == "IMG_0002.CR3")
        #expect(item.orientedSize == CGSize(width: 6000, height: 4000))
        #expect(LibraryFilter(rating: .atLeast(Rating(clamping: 1)), flag: .picked).matchesCulling(item))
        #expect(!LibraryFilter(flag: .rejected).matchesCulling(item))
    }

    @Test func projectSummariesCountVersions() async throws {
        let fixture = try await CatalogFixture.make(projectName: "First")
        let empty = try await fixture.catalog.createProject(name: "Empty", createdAt: Date().addingTimeInterval(60))
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        _ = try await fixture.catalog.duplicateVersion(id: ids[0])
        let summaries = try await fixture.catalog.projectSummaries()
        #expect(summaries.map(\.project.name) == ["Empty", "First"])
        #expect(summaries.map(\.versionCount) == [0, 3])
        #expect(summaries.first?.id == empty.id)
    }

    // MARK: Organization

    @Test func albumsKeepOrderAndIgnoreRepeats() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let album = try await fixture.catalog.createAlbum(name: "Selects", projectID: fixture.project.id)
        try await fixture.catalog.addVersions([ids[2], ids[0]], toAlbum: album.id!)
        try await fixture.catalog.addVersions([ids[0], ids[1]], toAlbum: album.id!)
        #expect(try await fixture.catalog.versionIDs(inAlbum: album.id!) == [ids[2], ids[0], ids[1]])
        let filtered = try await fixture.catalog.libraryItems(matching: LibraryFilter(scope: .album(album.id!)))
        #expect(Set(filtered.map(\.versionID)) == Set(ids))
    }

    @Test func aVersionBelongsToAtMostOneStack() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let stack = try await fixture.catalog.createStack(versionIDs: [ids[1], ids[0]])
        #expect(stack.pickVersionId == ids[1])
        #expect(try await fixture.catalog.versionIDs(inStack: stack.id!) == [ids[1], ids[0]])
        await #expect(throws: DatabaseError.self) {
            _ = try await fixture.catalog.createStack(versionIDs: [ids[0], ids[2]])
        }
    }

    @Test func keywordsAreHierarchicalAndCaseInsensitive() async throws {
        let fixture = try await CatalogFixture.make()
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        let places = try await fixture.catalog.keyword(named: "Places")
        let again = try await fixture.catalog.keyword(named: "places")
        #expect(again.id == places.id)
        let paris = try await fixture.catalog.keyword(named: "Paris", parentID: places.id)
        let rootParis = try await fixture.catalog.keyword(named: "Paris")
        #expect(paris.id != rootParis.id)
        try await fixture.catalog.assignKeyword(paris.id!, toVersions: [id])
        try await fixture.catalog.assignKeyword(paris.id!, toVersions: [id])
        try await fixture.catalog.assignKeyword(places.id!, toVersions: [id])
        #expect(try await fixture.catalog.keywords(forVersion: id).map(\.name) == ["Paris", "Places"])
    }

    @Test func deletingAProjectCascadesToItsCatalogRowsOnly() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...2).map { CatalogFixture.master($0) })
        let album = try await fixture.catalog.createAlbum(name: "Library album")
        try await fixture.catalog.addVersions(ids, toAlbum: album.id!)
        try await fixture.catalog.deleteProject(id: fixture.project.id!)
        #expect(try await fixture.catalog.versionCount() == 0)
        #expect(try await fixture.catalog.versionIDs(inAlbum: album.id!).isEmpty)
        #expect(try await fixture.catalog.volumes().count == 1)
    }

    // MARK: Volumes

    @Test func volumesAreMatchedByIdentityAndNeverDeletedWithImages() async throws {
        let fixture = try await CatalogFixture.make()
        try await fixture.addMasters([CatalogFixture.master(1)])
        let remounted = try await fixture.catalog.registerVolume(
            VolumeDescriptor(identity: "TEST-VOLUME", name: "Test", mountPath: "/Volumes/Test 1", isRemovable: true))
        #expect(remounted.id == fixture.volume.id)
        #expect(try await fixture.catalog.volumes().map(\.mountPath) == ["/Volumes/Test 1"])
        await #expect(throws: DatabaseError.self) {
            _ = try await fixture.catalog.database.write { db in try VolumeRecord.deleteOne(db, key: fixture.volume.id) }
        }
    }
}

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
