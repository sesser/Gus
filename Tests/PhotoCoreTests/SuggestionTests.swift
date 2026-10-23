import Foundation
import ImageIO
import Testing
@testable import PhotoCore

@Suite("Keyword suggestions")
struct SuggestionTests {
    private func suggest(_ catalog: Catalog, image: Int64, _ names: [String], version: Int = 1) async throws {
        try await catalog.storeSuggestions(names.enumerated().map { SuggestedKeyword(name: $1, confidence: 0.9 - Double($0) / 10) },
                                           forImage: image, analysisVersion: version)
    }

    private func imageID(_ catalog: Catalog, version: Int64) async throws -> Int64 {
        try #require(try await catalog.version(id: version)).imageId
    }

    @Test func pairsAreAnalyzedOnceThroughTheirCompanion() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([
            CatalogFixture.master(1, path: "a/IMG_1.CR3"), CatalogFixture.master(2, path: "a/IMG_1.JPG"),
            CatalogFixture.master(3, path: "a/IMG_2.JPG"),
        ])
        let catalog = fixture.catalog
        let targets = try await catalog.analysisTargets(forVersions: ids, analysisVersion: 1)
        #expect(Set(targets.map(\.fileName)) == ["IMG_1.JPG", "IMG_2.JPG"])

        try await suggest(catalog, image: try await imageID(catalog, version: ids[1]), ["dog"])
        #expect(try await catalog.analysisTargets(forVersions: ids, analysisVersion: 1).map(\.fileName) == ["IMG_2.JPG"])
        // A newer analysis looks again.
        #expect(try await catalog.analysisTargets(forVersions: ids, analysisVersion: 2).count == 2)
        // The RAW half sees the companion's suggestions.
        let summary = try await catalog.suggestionSummary(forVersions: [ids[0]])
        #expect(summary.suggestions.map(\.name) == ["dog"])
        #expect(summary.unanalyzedCount == 0)
    }

    @Test func summaryCountsVersionsAndSkipsKeywordsTheyHave() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let catalog = fixture.catalog
        try await suggest(catalog, image: try await imageID(catalog, version: ids[0]), ["dog", "beach"])
        try await suggest(catalog, image: try await imageID(catalog, version: ids[1]), ["dog", "Sunset"])
        try await catalog.addKeywords(named: ["Beach"], toVersions: [ids[0]])

        let summary = try await catalog.suggestionSummary(forVersions: ids)
        #expect(summary.suggestions.map { "\($0.name) \($0.count)" } == ["dog 2", "Sunset 1"])
        #expect(summary.unanalyzedCount == 1)
    }

    @Test func acceptingTagsOnlyThePhotosItWasSuggestedFor() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let catalog = fixture.catalog
        let first = try await imageID(catalog, version: ids[0])
        try await suggest(catalog, image: first, ["dog"])
        try await suggest(catalog, image: try await imageID(catalog, version: ids[1]), ["dog"])

        let acceptance = try await catalog.acceptSuggestion("dog", forVersions: ids)
        #expect(Set(acceptance.addition.assignments.map(\.versionId)) == [ids[0], ids[1]])
        #expect(try await catalog.keywords(forVersion: ids[2]).isEmpty)
        #expect(try await catalog.suggestionSummary(forVersions: ids).suggestions.isEmpty)

        // Analyzing again does not bring back an accepted suggestion.
        try await suggest(catalog, image: first, ["dog", "grass"])
        #expect(try await catalog.suggestionSummary(forVersions: [ids[0]]).suggestions.map(\.name) == ["grass"])

        try await catalog.undoSuggestionAcceptance(acceptance, name: "dog")
        #expect(try await catalog.keywordSummaries().isEmpty)
        #expect(try await catalog.suggestionSummary(forVersions: ids).suggestions.map { "\($0.name) \($0.count)" }
            == ["dog 2", "grass 1"])
        try await catalog.redoSuggestionAcceptance(acceptance, name: "dog")
        #expect(try await catalog.keywordSummaries().map { "\($0.name) \($0.count)" } == ["dog 2"])

        // Accepting where nothing suggested it creates no keyword.
        let nothing = try await catalog.acceptSuggestion("cat", forVersions: ids)
        #expect(nothing.addition.assignments.isEmpty && nothing.addition.createdKeywords.isEmpty)
        #expect(try await catalog.keywordSummaries().map(\.name) == ["dog"])
    }

    @Test func dismissedSuggestionsStayHidden() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...2).map { CatalogFixture.master($0) })
        let catalog = fixture.catalog
        let image = try await imageID(catalog, version: ids[0])
        try await suggest(catalog, image: image, ["structure", "dog"])
        let dismissed = try await catalog.dismissSuggestion("structure", forVersions: ids)
        #expect(dismissed == [image])
        try await suggest(catalog, image: image, ["structure", "dog"])
        #expect(try await catalog.suggestionSummary(forVersions: ids).suggestions.map(\.name) == ["dog"])
        try await catalog.reopenSuggestion("structure", images: dismissed)
        #expect(try await catalog.suggestionSummary(forVersions: ids).suggestions.count == 2)
    }

    static let sample = URL(fileURLWithPath: "/Library/User Pictures/Animals/Zebra.heic")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: SuggestionTests.sample.path),
                   "the macOS sample picture is not installed"))
    func visionRecognizesASamplePhoto() async throws {
        let source = try #require(CGImageSourceCreateWithURL(Self.sample as CFURL, nil))
        let image = try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512,
        ] as CFDictionary))
        let suggester = VisionKeywordSuggester()
        let suggestions = try await suggester.suggestions(for: image)
        #expect(suggestions.contains { $0.name == "zebra" })
        #expect(suggestions.count <= suggester.maximumCount)
        #expect(suggestions.allSatisfy { $0.confidence >= Double(suggester.minimumConfidence) && !$0.name.contains("_") })
    }
}
