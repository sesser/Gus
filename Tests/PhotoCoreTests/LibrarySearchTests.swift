import Foundation
import Testing
@testable import PhotoCore

@Suite("Browser search and sort")
struct LibrarySearchTests {
    /// a.ORF: OM System, 12-40mm lens, earliest
    /// b.ARW: Sony ILCE-7RM5, keyword "Beach"
    /// c.JPG: Sony ILCE-7RM5, latest
    /// 50%_off.heic: no camera
    static let photos: [(path: String, configure: @Sendable (inout ImageMetadata) -> Void)] = [
        ("s/a.ORF", { $0.cameraMake = "OM Digital Solutions"; $0.cameraModel = "OM-1"; $0.lensModel = "M.12-40mm F2.8" }),
        ("s/b.ARW", { $0.cameraMake = "SONY"; $0.cameraModel = "ILCE-7RM5" }),
        ("s/c.JPG", { $0.cameraMake = "SONY"; $0.cameraModel = "ILCE-7RM5" }),
        ("s/50%_off.heic", { _ in }),
    ]

    private func makeLibrary() async throws -> (Catalog, [Int64]) {
        let fixture = try await CatalogFixture.make()
        let masters = Self.photos.enumerated().map { index, photo in
            let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600)
            var metadata = ImageMetadata(captureDate: date)
            photo.configure(&metadata)
            return NewMaster(relativePath: photo.path, fileSize: 100 + Int64(index), modifiedAt: date,
                             contentHash: String(format: "%064x", index + 1), metadata: metadata)
        }
        let ids = try await fixture.addMasters(masters)
        _ = try await fixture.catalog.addKeywords(named: ["Beach"], toVersions: [ids[1]])
        return (fixture.catalog, ids)
    }

    private func names(_ catalog: Catalog, search: String = "", sort: LibrarySort = LibrarySort(),
                       rating: LibraryFilter.RatingRule = .any) async throws -> [String] {
        try await catalog.libraryItems(matching: LibraryFilter(rating: rating, search: search, sort: sort))
            .map(\.baseName)
    }

    @Test func searchTermsSplitAtCommasThenWhitespace() {
        #expect(LibraryFilter(search: "orf, sony  a7 ,, ").searchTerms == [["orf"], ["sony", "a7"]])
        #expect(LibraryFilter(search: "  ").searchTerms.isEmpty)
    }

    @Test func searchMatchesExtensionCameraLensAndKeyword() async throws {
        let (catalog, _) = try await makeLibrary()
        #expect(try await names(catalog, search: "orf") == ["a"])
        #expect(try await names(catalog, search: "ORF, arw") == ["a", "b"])
        #expect(try await names(catalog, search: "sony") == ["b", "c"])
        #expect(try await names(catalog, search: "7rm5") == ["b", "c"])
        #expect(try await names(catalog, search: "12-40") == ["a"])
        #expect(try await names(catalog, search: "beach") == ["b"])
        #expect(try await names(catalog, search: "") == ["a", "b", "c", "50%_off"])
    }

    @Test func wordsInOneAlternativeMustAllMatch() async throws {
        let (catalog, _) = try await makeLibrary()
        #expect(try await names(catalog, search: "sony jpg") == ["c"])
        #expect(try await names(catalog, search: "sony orf") == [])
        #expect(try await names(catalog, search: "sony jpg, om-1") == ["a", "c"])
    }

    @Test func wildcardCharactersMatchLiterally() async throws {
        let (catalog, _) = try await makeLibrary()
        #expect(try await names(catalog, search: "50%") == ["50%_off"])
        #expect(try await names(catalog, search: "_") == ["50%_off"])
    }

    @Test func searchCombinesWithRating() async throws {
        let (catalog, ids) = try await makeLibrary()
        try await catalog.setRating(Rating(clamping: 3), forVersions: [ids[2]])
        #expect(try await names(catalog, search: "sony", rating: .atLeast(Rating(clamping: 1))) == ["c"])
    }

    @Test func sortsByCaptureDateRatingAndFileName() async throws {
        let (catalog, ids) = try await makeLibrary()
        try await catalog.setRating(Rating(clamping: 2), forVersions: [ids[0], ids[3]])
        try await catalog.setRating(Rating(clamping: 5), forVersions: [ids[2]])
        #expect(try await names(catalog, sort: LibrarySort(key: .captureDate, ascending: false))
            == ["50%_off", "c", "b", "a"])
        // Equal ratings stay in capture order either way.
        #expect(try await names(catalog, sort: LibrarySort(key: .rating, ascending: false))
            == ["c", "a", "50%_off", "b"])
        #expect(try await names(catalog, sort: LibrarySort(key: .rating)) == ["b", "a", "50%_off", "c"])
        #expect(try await names(catalog, sort: LibrarySort(key: .fileName)) == ["50%_off", "a", "b", "c"])
        #expect(try await names(catalog, sort: LibrarySort(key: .fileName, ascending: false))
            == ["c", "b", "a", "50%_off"])
    }

    @Test func groupedPairsKeepTheSortOrder() async throws {
        let fixture = try await CatalogFixture.make()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let masters = ["p/z.ORF", "p/z.JPG", "p/m.ORF"].enumerated().map { index, path in
            NewMaster(relativePath: path, fileSize: 100, modifiedAt: date,
                      contentHash: String(format: "%064x", index + 1),
                      metadata: ImageMetadata(captureDate: date.addingTimeInterval(Double(index))))
        }
        try await fixture.addMasters(masters)
        let items = try await fixture.catalog.libraryItems(matching: LibraryFilter(sort: LibrarySort(key: .fileName)))
        #expect(items.map(\.baseName) == ["m", "z"])
        #expect(items[1].representsPair)
    }
}

@Suite("Filter bar stars")
struct FilterStarTests {
    typealias Rule = LibraryFilter.RatingRule

    @Test func clickingAStarFiltersOnAtLeastThatMany() {
        #expect(Rule.any.clickingStar(3) == .atLeast(Rating(clamping: 3)))
        #expect(Rule.atLeast(Rating(clamping: 3)).clickingStar(1) == .atLeast(Rating(clamping: 1)))
        #expect(Rule.atLeast(Rating(clamping: 1)).clickingStar(5) == .atLeast(Rating(clamping: 5)))
        #expect(Rule.unrated.clickingStar(2) == .atLeast(Rating(clamping: 2)))
    }

    @Test func clickingTheHighestLitStarClears() {
        #expect(Rule.atLeast(Rating(clamping: 4)).clickingStar(4) == .any)
        #expect(Rule.atLeast(Rating(clamping: 4)).litStars == 4)
        #expect(Rule.any.litStars == 0)
        #expect(Rule.exactly(Rating(clamping: 2)).litStars == 0)
    }
}
