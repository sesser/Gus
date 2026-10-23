import Foundation
import Testing
@testable import PhotoCore

@Suite("Smart albums and albums")
struct SmartAlbumTests {
    static let today = LocalDate.format(Date(), in: .current)
    static let lastWeek = LocalDate.format(Date().addingTimeInterval(-6 * 86_400), in: .current)
    static let lastMonth = LocalDate.format(Date().addingTimeInterval(-40 * 86_400), in: .current)

    /// Capture date for a local day at noon, floating (no offset), as cameras write it.
    static func noon(_ day: String) -> Date {
        ExifDate.parse(day.replacingOccurrences(of: "-", with: ":") + " 12:00:00")!.date
    }

    struct Photo: Sendable {
        var path: String
        var day: String
        var configure: @Sendable (inout ImageMetadata) -> Void = { _ in }
    }

    /// a.NEF: Nikon, 35mm lens, ISO 100, ƒ/2.8, today, GPS, flash, manual WB, artist
    /// b.JPG: Canon, ISO 400, ƒ/8, last week
    /// c.CR3: Canon, ISO 3200, 100% crop_shot name, last month
    /// d.HEIC: no camera, today
    static let photos: [Photo] = [
        Photo(path: "s/a.NEF", day: today) {
            $0.cameraMake = "NIKON CORPORATION"; $0.cameraModel = "Z 6"; $0.lensModel = "NIKKOR Z 35mm f/1.8 S"
            $0.iso = 100; $0.fNumber = 2.8000001; $0.exposureTime = 1.0 / 250
            $0.latitude = 1; $0.longitude = 2; $0.flashFired = true; $0.whiteBalance = 1; $0.artist = "Pat Doe"
        },
        Photo(path: "s/b.JPG", day: lastWeek) {
            $0.cameraMake = "Canon"; $0.cameraModel = "EOS R5"; $0.iso = 400; $0.fNumber = 8; $0.flashFired = false
        },
        Photo(path: "s/100%_crop_shot.CR3", day: lastMonth) {
            $0.cameraMake = "Canon"; $0.cameraModel = "EOS R5"; $0.iso = 3200
        },
        Photo(path: "s/d.HEIC", day: today),
    ]

    private func makeLibrary() async throws -> (CatalogFixture, [Int64]) {
        let fixture = try await CatalogFixture.make()
        let masters = Self.photos.enumerated().map { index, photo in
            var metadata = ImageMetadata(captureDate: Self.noon(photo.day))
            photo.configure(&metadata)
            return NewMaster(relativePath: photo.path, fileSize: 100 + Int64(index),
                             modifiedAt: Self.noon(photo.day), contentHash: String(format: "%064x", index + 1),
                             metadata: metadata)
        }
        let ids = try await fixture.addMasters(masters)
        return (fixture, ids)
    }

    private func names(_ catalog: Catalog, _ rules: SmartAlbumRules, project: Int64? = nil) async throws -> [String] {
        try await catalog.libraryItems(matching: LibraryFilter(scope: .rules(rules, projectID: project)))
            .map(\.baseName).sorted()
    }

    private func match(_ rules: SmartRule..., any: Bool = false) -> SmartAlbumRules {
        SmartAlbumRules(match: any ? .any : .all, rules: rules)
    }

    @Test func rulesRoundTripThroughJSONWithGenericKeys() throws {
        let rules = match(SmartRule(field: .rating, comparison: .atLeast, value: RuleValue(number: 3)),
                          SmartRule(field: .keyword, comparison: .has, value: RuleValue(id: 7)))
        let json = try rules.jsonString()
        #expect(json.contains(#""field":"rating""#) && json.contains(#""comparison":"atLeast""#))
        #expect(json.contains(#""match":"all""#))
        #expect(try SmartAlbumRules.decode(from: json) == rules)
        #expect(SmartRule(field: .lens).comparison == .contains)
    }

    @Test func numberRules() async throws {
        let (fixture, ids) = try await makeLibrary()
        let catalog = fixture.catalog
        try await catalog.setRating(Rating(clamping: 4), forVersions: [ids[0], ids[1]])
        #expect(try await names(catalog, match(SmartRule(field: .rating, comparison: .atLeast, value: RuleValue(number: 4))))
            == ["a", "b"])
        #expect(try await names(catalog, match(SmartRule(field: .iso, comparison: .between,
                                                         value: RuleValue(number: 400, upperNumber: 100)))) == ["a", "b"])
        #expect(try await names(catalog, match(SmartRule(field: .aperture, comparison: .equals, value: RuleValue(number: 2.8))))
            == ["a"])
        // "Is not" includes photos without the value.
        #expect(try await names(catalog, match(SmartRule(field: .aperture, comparison: .notEquals, value: RuleValue(number: 2.8))))
            == ["100%_crop_shot", "b", "d"])
        #expect(try await names(catalog, match(SmartRule(field: .shutterSpeed, comparison: .atMost,
                                                         value: RuleValue(number: 1.0 / 250)))) == ["a"])
    }

    @Test func textRules() async throws {
        let (fixture, _) = try await makeLibrary()
        let catalog = fixture.catalog
        #expect(try await names(catalog, match(SmartRule(field: .camera, comparison: .contains, value: RuleValue(text: "nikon"))))
            == ["a"])
        #expect(try await names(catalog, match(SmartRule(field: .camera, comparison: .equals,
                                                         value: RuleValue(text: "canon eos r5")))) == ["100%_crop_shot", "b"])
        #expect(try await names(catalog, match(SmartRule(field: .lens, comparison: .beginsWith, value: RuleValue(text: "NIKKOR")))) == ["a"])
        #expect(try await names(catalog, match(SmartRule(field: .lens, comparison: .isEmpty))) == ["100%_crop_shot", "b", "d"])
        #expect(try await names(catalog, match(SmartRule(field: .artist, comparison: .doesNotContain, value: RuleValue(text: "pat"))))
            == ["100%_crop_shot", "b", "d"])
        // % and _ are literal characters, not wildcards.
        #expect(try await names(catalog, match(SmartRule(field: .fileName, comparison: .contains, value: RuleValue(text: "0%_c"))))
            == ["100%_crop_shot"])
        #expect(try await names(catalog, match(SmartRule(field: .fileName, comparison: .contains, value: RuleValue(text: "_")))) == ["100%_crop_shot"])
    }

    @Test func dateRules() async throws {
        let (fixture, _) = try await makeLibrary()
        let catalog = fixture.catalog
        func dates(_ comparison: SmartRule.Comparison, _ value: RuleValue) async throws -> [String] {
            try await names(catalog, match(SmartRule(field: .captureDate, comparison: comparison, value: value)))
        }
        #expect(try await dates(.on, RuleValue(text: Self.today)) == ["a", "d"])
        #expect(try await dates(.inLastDays, RuleValue(number: 7)) == ["a", "b", "d"])
        #expect(try await dates(.inLastDays, RuleValue(number: 1)) == ["a", "d"])
        #expect(try await dates(.notInLastDays, RuleValue(number: 7)) == ["100%_crop_shot"])
        #expect(try await dates(.before, RuleValue(text: Self.lastWeek)) == ["100%_crop_shot"])
        #expect(try await dates(.after, RuleValue(text: Self.lastWeek)) == ["a", "d"])
        #expect(try await dates(.between, RuleValue(text: Self.lastMonth, upperText: Self.lastWeek)) == ["100%_crop_shot", "b"])
        // Everything was imported now.
        let imported = try await names(catalog, match(SmartRule(field: .importDate, comparison: .on, value: RuleValue(text: Self.today))))
        #expect(imported.count == 4)
    }

    @Test func choiceKeywordAndFlagRules() async throws {
        let (fixture, ids) = try await makeLibrary()
        let catalog = fixture.catalog
        try await catalog.setFlag(.picked, forVersions: [ids[1]])
        try await catalog.setColorLabel(.red, forVersions: [ids[3]])
        let dog = try await catalog.addKeywords(named: ["dog"], toVersions: [ids[0], ids[3]]).createdKeywords[0]

        #expect(try await names(catalog, match(SmartRule(field: .flag, comparison: .equals, value: RuleValue(text: "picked"))))
            == ["b"])
        #expect(try await names(catalog, match(SmartRule(field: .colorLabel, value: RuleValue(text: "1")))) == ["d"])
        #expect(try await names(catalog, match(SmartRule(field: .fileType, value: RuleValue(text: "raw"))))
            == ["100%_crop_shot", "a"])
        #expect(try await names(catalog, match(SmartRule(field: .fileType, comparison: .notEquals, value: RuleValue(text: "raw"))))
            == ["b", "d"])
        #expect(try await names(catalog, match(SmartRule(field: .whiteBalance, value: RuleValue(text: "manual")))) == ["a"])
        #expect(try await names(catalog, match(SmartRule(field: .keyword, comparison: .has, value: RuleValue(id: dog.id)))) == ["a", "d"])
        #expect(try await names(catalog, match(SmartRule(field: .keyword, comparison: .doesNotHave, value: RuleValue(id: dog.id))))
            == ["100%_crop_shot", "b"])
        #expect(try await names(catalog, match(SmartRule(field: .hasKeywords, comparison: .isFalse))) == ["100%_crop_shot", "b"])
        #expect(try await names(catalog, match(SmartRule(field: .flash, comparison: .isTrue))) == ["a"])
        #expect(try await names(catalog, match(SmartRule(field: .flash, comparison: .isFalse))) == ["100%_crop_shot", "b", "d"])
        #expect(try await names(catalog, match(SmartRule(field: .hasLocation, comparison: .isTrue))) == ["a"])
    }

    @Test func allAnyEmptyAndIncompleteRules() async throws {
        let (fixture, _) = try await makeLibrary()
        let catalog = fixture.catalog
        let canon = SmartRule(field: .camera, comparison: .contains, value: RuleValue(text: "canon"))
        let today = SmartRule(field: .captureDate, comparison: .on, value: RuleValue(text: Self.today))
        #expect(try await names(catalog, match(canon, today)).isEmpty)
        #expect(try await names(catalog, match(canon, today, any: true)) == ["100%_crop_shot", "a", "b", "d"])
        #expect(try await names(catalog, SmartAlbumRules()).count == 4)
        // A rule still being edited (no value) does not change the result.
        #expect(try await names(catalog, match(canon, SmartRule(field: .iso))) == ["100%_crop_shot", "b"])
    }

    @Test func smartAlbumsCanBeLimitedToAProject() async throws {
        let (fixture, _) = try await makeLibrary()
        let catalog = fixture.catalog
        let other = try await catalog.createProject(name: "Other")
        try await catalog.insertMasters([CatalogFixture.master(50, path: "o/e.NEF")], volumeID: fixture.volume.id!,
                                        projectID: other.id!)
        let raw = match(SmartRule(field: .fileType, value: RuleValue(text: "raw")))
        #expect(try await names(catalog, raw) == ["100%_crop_shot", "a", "e"])
        #expect(try await names(catalog, raw, project: other.id) == ["e"])
        #expect(try await names(catalog, match(SmartRule(field: .project, value: RuleValue(id: other.id)))) == ["e"])

        // A whole-second date: the catalog keeps milliseconds.
        let album = try await catalog.createSmartAlbum(name: "RAW", projectID: nil, rules: raw,
                                                       createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        var renamed = album
        renamed.name = "Raw files"
        renamed.rules.match = .any
        try await catalog.saveSmartAlbum(renamed)
        #expect(try await catalog.smartAlbums() == [renamed])
        let deleted = try #require(try await catalog.deleteSmartAlbum(id: album.id))
        #expect(try await catalog.smartAlbums().isEmpty)
        try await catalog.saveSmartAlbum(deleted)
        #expect(try await catalog.smartAlbums().map(\.id) == [album.id])
    }

    @Test func countsMatchTheListWithPairsGrouped() async throws {
        let fixture = try await CatalogFixture.make()
        try await fixture.addMasters([
            CatalogFixture.master(1, path: "p/IMG_1.CR3"), CatalogFixture.master(2, path: "p/IMG_1.JPG"),
            CatalogFixture.master(3, path: "p/IMG_2.JPG"),
        ])
        let catalog = fixture.catalog
        for rules in [SmartAlbumRules(), match(SmartRule(field: .fileType, value: RuleValue(text: "jpeg")))] {
            for grouped in [true, false] {
                let filter = LibraryFilter(scope: .rules(rules, projectID: nil), groupsPairs: grouped)
                #expect(try await catalog.itemCount(matching: filter) == (try await catalog.libraryItems(matching: filter)).count)
            }
        }
        #expect(try await catalog.itemCount(matching: LibraryFilter()) == 2)
    }

    @Test func monthsCountPairsOnce() async throws {
        let fixture = try await CatalogFixture.make()
        let may = Self.noon("2024-05-03")
        try await fixture.addMasters([
            CatalogFixture.master(1, captureDate: may, path: "p/IMG_1.CR3"),
            CatalogFixture.master(2, captureDate: may, path: "p/IMG_1.JPG"),
            CatalogFixture.master(3, captureDate: Self.noon("2024-05-31"), path: "p/IMG_2.JPG"),
            CatalogFixture.master(4, captureDate: Self.noon("2023-12-25"), path: "p/IMG_3.JPG"),
        ])
        let months = try await fixture.catalog.captureMonths()
        #expect(months.map { "\($0.id) \($0.count)" } == ["2024-05 2", "2023-12 1"])
        #expect(try await fixture.catalog.captureMonths(groupingPairs: false).first?.count == 3)
        let december = try #require(months.last).days
        #expect(december.start == "2023-12-01" && december.end == "2024-01-01")
        let filter = LibraryFilter(scope: .captureDays(start: december.start, end: december.end))
        #expect(try await fixture.catalog.libraryItems(matching: filter).map(\.fileName) == ["IMG_3.JPG"])
    }

    @Test func albumMembershipChangesAreReversible() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([
            CatalogFixture.master(1, path: "p/IMG_1.CR3"), CatalogFixture.master(2, path: "p/IMG_1.JPG"),
            CatalogFixture.master(3, path: "p/IMG_2.JPG"),
        ])
        let catalog = fixture.catalog
        let album = try await catalog.createAlbum(name: "Best", projectID: fixture.project.id)
        let added = try await catalog.addVersions([ids[0], ids[2]], toAlbum: album.id!)
        #expect(Set(added.map(\.versionId)) == Set(ids))
        #expect(try await catalog.addVersions([ids[1]], toAlbum: album.id!).isEmpty)
        #expect(try await catalog.albumSummaries().map(\.count) == [2])
        #expect(try await catalog.albumSummaries(groupingPairs: false).map(\.count) == [3])

        let removed = try await catalog.removeVersions([ids[1]], fromAlbum: album.id!)
        #expect(Set(removed.map(\.versionId)) == [ids[0], ids[1]])
        #expect(try await catalog.versionIDs(inAlbum: album.id!) == [ids[2]])
        try await catalog.insertAlbumMembers(removed)
        #expect(Set(try await catalog.versionIDs(inAlbum: album.id!)) == Set(ids))

        try await catalog.renameAlbum(id: album.id!, to: "Keepers")
        let deleted = try #require(try await catalog.deleteAlbum(id: album.id!))
        #expect(try await catalog.albumSummaries().isEmpty)
        try await catalog.restoreAlbum(deleted)
        let restored = try #require(try await catalog.albumSummaries().first)
        #expect(restored.album.name == "Keepers" && restored.count == 2)
        #expect(Set(try await catalog.versionIDs(inAlbum: album.id!)) == Set(ids))
    }
}
