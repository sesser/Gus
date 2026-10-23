import Foundation
import GRDB
import Testing
@testable import PhotoCore

@Suite("RAW+JPEG pairs")
struct PairingTests {
    private func master(_ path: String, _ index: Int) -> NewMaster {
        CatalogFixture.master(index, hash: String(format: "%064x", index), path: path)
    }

    private func items(_ catalog: Catalog, grouped: Bool, scope: LibraryFilter.Scope = .allPhotos) async throws -> [CatalogItem] {
        try await catalog.libraryItems(matching: LibraryFilter(scope: scope, groupsPairs: grouped))
    }

    @Test func rawAndJpegWithTheSameNameInOneFolderPair() async throws {
        let fixture = try await CatalogFixture.make()
        let result = try await fixture.catalog.insertMasters([
            master("shoot/IMG_0001.CR3", 1),
            master("shoot/IMG_0001.JPG", 2),
            master("shoot/IMG_0002.CR3", 3),        // no partner
            master("other/IMG_0002.JPG", 4),        // other folder
            master("shoot/IMG_0003.JPG", 5),        // two non-RAW files do not pair
            master("shoot/IMG_0003.HEIC", 6),
            master("shoot/img_0004.cr3", 7),        // case-insensitive, HEIC companion
            master("shoot/IMG_0004.heic", 8),
            master("shoot/IMG_0005.CR3", 9),        // JPEG preferred over HEIC
            master("shoot/IMG_0005.HEIC", 10),
            master("shoot/IMG_0005.JPG", 11),
        ], volumeID: fixture.volume.id!, projectID: fixture.project.id!)
        #expect(result.pairsCreated == 3)

        let separate = try await items(fixture.catalog, grouped: false)
        #expect(separate.count == 11)
        let grouped = try await items(fixture.catalog, grouped: true)
        #expect(grouped.count == 8)
        let pairs = grouped.filter(\.representsPair)
        #expect(pairs.map(\.fileName).sorted() == ["IMG_0001.CR3", "IMG_0005.CR3", "img_0004.cr3"])
        #expect(Set(pairs.compactMap(\.partnerKind)) == [.jpeg, .heic])
        // The HEIC that lost to a JPEG stays a photo of its own.
        #expect(grouped.contains { $0.fileName == "IMG_0005.HEIC" && $0.partnerVersionID == nil })
        // Ungrouped, both halves know their partner but stand alone.
        let raw = try #require(separate.first { $0.fileName == "IMG_0001.CR3" })
        let jpeg = try #require(separate.first { $0.fileName == "IMG_0001.JPG" })
        #expect(raw.partnerVersionID == jpeg.versionID)
        #expect(jpeg.partnerVersionID == raw.versionID)
        #expect(!raw.representsPair && !jpeg.representsPair)
    }

    @Test func partnersPairAcrossBatchesButNotAcrossProjects() async throws {
        let fixture = try await CatalogFixture.make()
        try await fixture.addMasters([master("shoot/IMG_0001.CR3", 1), master("shoot/IMG_0002.CR3", 2)])
        let second = try await fixture.catalog.insertMasters([master("shoot/IMG_0001.JPG", 3)],
                                                             volumeID: fixture.volume.id!, projectID: fixture.project.id!)
        #expect(second.pairsCreated == 1)

        let elsewhere = try await fixture.catalog.createProject(name: "Elsewhere")
        let third = try await fixture.catalog.insertMasters([master("shoot/IMG_0002.JPG", 4)],
                                                            volumeID: fixture.volume.id!, projectID: elsewhere.id!)
        #expect(third.pairsCreated == 0)
        #expect(try await items(fixture.catalog, grouped: true).count == 3)
    }

    @Test func cullingKeywordsAndAlbumsReachBothHalves() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([master("a/IMG_1.NEF", 1), master("a/IMG_1.JPG", 2), master("a/IMG_2.NEF", 3)])
        let (raw, jpeg, single) = (ids[0], ids[1], ids[2])
        let catalog = fixture.catalog

        try await catalog.setRating(Rating(clamping: 4), forVersions: [raw])
        try await catalog.setFlag(.picked, forVersions: [jpeg])
        try await catalog.setColorLabel(.blue, forVersions: [raw, single])
        for id in [raw, jpeg] {
            let version = try #require(try await catalog.version(id: id))
            #expect(version.rating == Rating(clamping: 4))
            #expect(version.flag == .picked)
            #expect(version.colorLabel == .blue)
        }
        #expect(try await catalog.version(id: single)?.rating == .unrated)

        let keyword = try await catalog.keyword(named: "dog")
        try await catalog.assignKeyword(keyword.id!, toVersions: [jpeg])
        #expect(try await catalog.keywords(forVersion: raw).map(\.name) == ["dog"])

        let album = try await catalog.createAlbum(name: "Best")
        try await catalog.addVersions([raw], toAlbum: album.id!)
        #expect(Set(try await catalog.versionIDs(inAlbum: album.id!)) == [raw, jpeg])
        #expect(try await items(catalog, grouped: true, scope: .album(album.id!)).map(\.versionID) == [raw])
    }

    @Test func eitherHalfCanRepresentThePair() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([master("a/IMG_1.ARW", 1), master("a/IMG_1.JPG", 2), master("a/IMG_2.JPG", 3)])
        let catalog = fixture.catalog
        #expect(try await items(catalog, grouped: true).map(\.fileName) == ["IMG_1.ARW", "IMG_2.JPG"])

        try await catalog.setPairsShowCompanion(true, forVersions: [ids[0]])
        let grouped = try await items(catalog, grouped: true)
        #expect(grouped.map(\.fileName) == ["IMG_1.JPG", "IMG_2.JPG"])
        #expect(grouped[0].representsPair && grouped[0].partnerKind == .raw)

        // Switching back works from either half.
        try await catalog.setPairsShowCompanion(false, forVersions: [ids[1]])
        #expect(try await items(catalog, grouped: true).map(\.fileName) == ["IMG_1.ARW", "IMG_2.JPG"])

        #expect(try await catalog.versionCount(groupingPairs: true) == 2)
        #expect(try await catalog.versionCount(groupingPairs: false) == 3)
        #expect(try await catalog.projectSummaries(groupingPairs: true).first?.versionCount == 2)
        #expect(try await catalog.projectSummaries(groupingPairs: false).first?.versionCount == 3)
    }

    @Test func aHalfWhosePartnerIsFilteredOutStillShows() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([master("a/IMG_1.CR3", 1), master("a/IMG_1.JPG", 2)])
        let album = try await fixture.catalog.createAlbum(name: "JPEG only")
        // Written directly: the catalog API would add the partner too.
        try await fixture.catalog.database.write { db in
            try AlbumMemberRecord(albumId: album.id!, versionId: ids[1], position: 0).insert(db)
        }
        let shown = try await items(fixture.catalog, grouped: true, scope: .album(album.id!))
        #expect(shown.map(\.fileName) == ["IMG_1.JPG"])
        #expect(shown.first?.representsPair == false)
    }

    @Test func selectingTheWholeLibraryStaysUnderTheVariableLimit() async throws {
        let fixture = try await CatalogFixture.make()
        let masters = (0..<20_000).map { index in
            master("big/IMG_\(index / 2).\(index.isMultiple(of: 2) ? "DNG" : "JPG")", index + 1)
        }
        let ids = try await fixture.addMasters(masters)
        #expect(try await items(fixture.catalog, grouped: true).count == 10_000)
        // 40k bound variables if sent as one statement; SQLite allows 32,766.
        try await fixture.catalog.setRating(Rating(clamping: 2), forVersions: ids)
        let rated = try await fixture.catalog.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM version WHERE rating = 2")
        }
        #expect(rated == 20_000)
    }

    @Test func migrationPairsExistingMastersAndMergesTheirValues() async throws {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue, upTo: "v1")
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO volume (id, identity, name, mountPath) VALUES (1, 'V', 'V', '/Volumes/V')")
            try db.execute(sql: "INSERT INTO project (id, uuid, name, createdAt) VALUES (1, 'p', 'P', '2024-01-01')")
            let files = ["s/A.CR2", "s/A.JPG", "s/B.CR2", "s/B.JPG", "s/C.JPG"]
            for (index, path) in files.enumerated() {
                let id = index + 1
                try db.execute(sql: """
                    INSERT INTO image (id, volumeId, projectId, relativePath, fileName, fileSize, modifiedAt,
                                       contentHash, format, sortDate, importedAt)
                    VALUES (?, 1, 1, ?, ?, 1, '2024-01-01', ?, ?, '2024-01-01', '2024-01-01')
                    """, arguments: [id, path, (path as NSString).lastPathComponent, "hash\(id)",
                                     (path as NSString).pathExtension.lowercased()])
            }
            // A: the RAW is unrated, the JPEG has 4 stars. B: both rated, the RAW wins.
            let culling: [(rating: Int, flag: Int)] = [(0, 1), (4, 0), (2, 0), (5, -1), (3, 0)]
            for (index, values) in culling.enumerated() {
                try db.execute(sql: """
                    INSERT INTO version (id, uuid, imageId, versionNumber, isDefault, rating, flag, colorLabel,
                                         editStack, editStackHash, createdAt, modifiedAt)
                    VALUES (?, ?, ?, 1, 1, ?, ?, 0, '{}', 'h', '2024-01-01', '2024-01-01')
                    """, arguments: [index + 1, "v\(index)", index + 1, values.rating, values.flag])
            }
            try db.execute(sql: "INSERT INTO keyword (id, name) VALUES (1, 'beach'), (2, 'dog')")
            try db.execute(sql: "INSERT INTO versionKeyword VALUES (1, 1), (2, 2)")
        }

        let catalog = try Catalog(database: queue)
        func version(_ id: Int64) async throws -> VersionRecord { try #require(try await catalog.version(id: id)) }
        #expect(try await version(1).rating == Rating(clamping: 4))
        #expect(try await version(2).rating == Rating(clamping: 4))
        #expect(try await version(2).flag == .picked)
        #expect(try await version(3).rating == Rating(clamping: 2))
        #expect(try await version(4).rating == Rating(clamping: 2))
        #expect(try await version(4).flag == .rejected)
        #expect(try await catalog.keywords(forVersion: 1).map(\.name) == ["beach", "dog"])
        #expect(try await catalog.keywords(forVersion: 2).map(\.name) == ["beach", "dog"])
        let grouped = try await catalog.libraryItems(matching: LibraryFilter())
        #expect(grouped.map(\.fileName) == ["A.CR2", "B.CR2", "C.JPG"])
    }
}
