import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

@Suite("Keywords")
struct KeywordTests {
    private func names(_ catalog: Catalog, _ versionID: Int64) async throws -> [String] {
        try await catalog.keywords(forVersion: versionID).map(\.name)
    }

    @Test func namesAreTrimmedAndMatchedIgnoringCase() {
        #expect(Catalog.normalizedKeywordName("  golden   hour \n") == "golden hour")
        #expect(Catalog.normalizedKeywordName(" \t ") == nil)
    }

    @Test func addingAndRemovingReportsExactlyWhatChanged() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let catalog = fixture.catalog

        let added = try await catalog.addKeywords(named: ["Dog", " dog ", "beach"], toVersions: [ids[0], ids[1]])
        #expect(added.assignments.count == 4)
        #expect(added.createdKeywords.map(\.name) == ["Dog", "beach"])
        #expect(try await names(catalog, ids[0]) == ["beach", "Dog"])
        let again = try await catalog.addKeywords(named: ["DOG"], toVersions: ids)
        #expect(again.assignments.count == 1) // only ids[2] is new
        #expect(again.createdKeywords.isEmpty)
        #expect(try await catalog.keywordSummaries().map(\.name) == ["beach", "Dog"])

        let dog = try #require(try await catalog.keywordSummaries().first { $0.name == "Dog" })
        let removed = try await catalog.removeKeywords([dog.id], fromVersions: [ids[0], ids[2]])
        #expect(Set(removed.map(\.versionId)) == [ids[0], ids[2]])
        #expect(try await names(catalog, ids[0]) == ["beach"])

        // Undo puts back exactly what was removed.
        try await catalog.insertKeywordAssignments(removed)
        #expect(try await names(catalog, ids[0]) == ["beach", "Dog"])
        #expect(try await names(catalog, ids[2]) == ["Dog"])
        try await catalog.deleteKeywordAssignments(added.assignments)
        #expect(try await names(catalog, ids[0]).isEmpty)
        #expect(try await names(catalog, ids[2]) == ["Dog"])
    }

    @Test func undoingAnAdditionRemovesTheKeywordsItCreated() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...2).map { CatalogFixture.master($0) })
        let catalog = fixture.catalog
        try await catalog.addKeywords(named: ["beach"], toVersions: [ids[1]])
        let addition = try await catalog.addKeywords(named: ["beach", "sunset"], toVersions: [ids[0]])
        try await catalog.undoKeywordAddition(addition)
        #expect(try await catalog.keywordSummaries().map { "\($0.name) \($0.count)" } == ["beach 1"])
        try await catalog.redoKeywordAddition(addition)
        #expect(try await catalog.keywordSummaries().map { "\($0.name) \($0.count)" } == ["beach 2", "sunset 1"])
        #expect(try await catalog.keywordSummaries().last?.id == addition.createdKeywords.first?.id)
    }

    @Test func usageCountsTheGivenVersions() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...4).map { CatalogFixture.master($0) })
        try await fixture.catalog.addKeywords(named: ["dog"], toVersions: Array(ids[0...2]))
        try await fixture.catalog.addKeywords(named: ["cat"], toVersions: [ids[3]])
        let usage = try await fixture.catalog.keywordUsage(forVersions: [ids[0], ids[1], ids[3]])
        #expect(usage.map { "\($0.keyword.name) \($0.count)" } == ["cat 1", "dog 2"])
        #expect(try await fixture.catalog.keywordUsage(forVersions: []).isEmpty)
    }

    @Test func pairsShareKeywordsAndCountOnceWhenGrouped() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([
            CatalogFixture.master(1, path: "a/IMG_1.CR3"), CatalogFixture.master(2, path: "a/IMG_1.JPG"),
            CatalogFixture.master(3, path: "a/IMG_2.JPG"),
        ])
        let catalog = fixture.catalog
        let added = try await catalog.addKeywords(named: ["dog"], toVersions: [ids[0], ids[2]])
        #expect(added.assignments.count == 3)
        #expect(try await names(catalog, ids[1]) == ["dog"])
        #expect(try await catalog.keywordSummaries(groupingPairs: true).first?.count == 2)
        #expect(try await catalog.keywordSummaries(groupingPairs: false).first?.count == 3)

        let dog = try #require(try await catalog.keywordSummaries().first)
        try await catalog.removeKeywords([dog.id], fromVersions: [ids[1]])
        #expect(try await names(catalog, ids[0]).isEmpty)

        let shown = try await catalog.libraryItems(matching: LibraryFilter(scope: .keyword(dog.id)))
        #expect(shown.map(\.fileName) == ["IMG_2.JPG"])
    }

    @Test func renamingOntoAnotherKeywordMergesAndCanBeUndone() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...3).map { CatalogFixture.master($0) })
        let catalog = fixture.catalog
        try await catalog.addKeywords(named: ["puppy"], toVersions: [ids[0], ids[1]])
        try await catalog.addKeywords(named: ["Dog"], toVersions: [ids[1], ids[2]])
        let puppy = try #require(try await catalog.keywordSummaries().first { $0.name == "puppy" })

        #expect(try await catalog.renameKeyword(id: puppy.id, to: "puppy") == .unchanged)
        #expect(try await catalog.renameKeyword(id: puppy.id, to: "Puppies") == .renamed(from: "puppy"))
        guard case .merged(let merge) = try await catalog.renameKeyword(id: puppy.id, to: "dog") else {
            Issue.record("expected a merge")
            return
        }
        #expect(merge.target.name == "Dog")
        #expect(merge.addedToTarget.map(\.versionId) == [ids[0]])
        #expect(try await catalog.keywordSummaries().map { "\($0.name) \($0.count)" } == ["Dog 3"])

        try await catalog.undoKeywordMerge(merge)
        #expect(try await catalog.keywordSummaries().map { "\($0.name) \($0.count)" } == ["Dog 2", "Puppies 2"])
        #expect(try await names(catalog, ids[0]) == ["Puppies"])
    }

    @Test func deletedKeywordsCanBeRestored() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters((1...2).map { CatalogFixture.master($0) })
        let catalog = fixture.catalog
        try await catalog.addKeywords(named: ["sunset"], toVersions: ids)
        let sunset = try #require(try await catalog.keywordSummaries().first)
        let deleted = try #require(try await catalog.deleteKeyword(id: sunset.id))
        #expect(deleted.versionIDs == ids)
        #expect(try await catalog.keywordSummaries().isEmpty)
        try await catalog.restoreKeyword(deleted)
        #expect(try await catalog.keywordSummaries().map { "\($0.id) \($0.count)" } == ["\(sunset.id) 2"])
    }

    // MARK: Values embedded by other apps

    /// a.jpg has IPTC keywords; b.jpg XMP keywords, rating and label; c.jpg is
    /// rejected with a label outside the color set. (ImageIO rewrites IPTC
    /// keywords when it merges XMP, so the two kinds go in separate files.)
    private func importTagged(reader: any MetadataReader) async throws -> (Catalog, [Int64]) {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "Tagged")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let files: [(String, SyntheticImages.Exif)] = [
                ("a.jpg", .init(dateTimeOriginal: "2024:05:01 10:00:00", keywords: ["Dog", "beach", "dog"])),
                ("b.jpg", .init(dateTimeOriginal: "2024:05:01 10:00:01", xmpRating: 4, xmpLabel: "Green",
                                xmpSubject: ["dog", "sunset"])),
                ("c.jpg", .init(dateTimeOriginal: "2024:05:01 10:00:02", xmpRating: -1, xmpLabel: "Custom")),
            ]
            for (index, (name, exif)) in files.enumerated() {
                try SyntheticImages.writeJPEG(to: folder.appending(path: name), width: 64, height: 48,
                                              seed: UInt64(index + 1), exif: exif)
            }
            let catalog = try Catalog.makeInMemory()
            let summary = try await Importer(catalog: catalog, metadataReader: reader).importFolder(folder)
            return (catalog, summary.insertedVersionIDs)
        }
    }

    private func expectEmbeddedValues(_ catalog: Catalog, _ ids: [Int64]) async throws {
        try #require(ids.count == 3)
        let iptc = try await names(catalog, ids[0])
        #expect(iptc == ["beach", "Dog"])
        // "dog" matches the keyword a.jpg created, which keeps its first spelling.
        let xmp = try await names(catalog, ids[1])
        #expect(xmp == ["Dog", "sunset"])
        let tagged = try #require(try await catalog.version(id: ids[1]))
        #expect(tagged.rating == Rating(clamping: 4))
        #expect(tagged.colorLabel == .green)
        #expect(tagged.flag == .none)
        let rejected = try #require(try await catalog.version(id: ids[2]))
        #expect(rejected.flag == .rejected)
        #expect(rejected.rating == .unrated)
        #expect(rejected.colorLabel == .none)
    }

    @Test func importReadsEmbeddedKeywordsRatingAndLabelWithImageIO() async throws {
        let (catalog, ids) = try await importTagged(reader: ImageIOMetadataReader())
        try await expectEmbeddedValues(catalog, ids)
    }

    @Test(.enabled(if: ExifToolMetadataReader.locateExecutable() != nil, "ExifTool is not installed"))
    func importReadsEmbeddedKeywordsRatingAndLabelWithExifTool() async throws {
        let reader = ExifToolMetadataReader(executableURL: ExifToolMetadataReader.locateExecutable()!)
        let (catalog, ids) = try await importTagged(reader: reader)
        await reader.shutdown()
        try await expectEmbeddedValues(catalog, ids)
    }
}

@Suite("Keyword completion")
struct KeywordCompletionTests {
    let names = ["beach", "Dog", "dog park", "hot dog", "Sunset", "underdog", "Doge"]

    @Test func suggestsPrefixThenWordThenSubstringMatches() {
        #expect(KeywordCompletion.suggestions(for: "do", from: names) == ["Dog", "Doge", "dog park", "hot dog", "underdog"])
        #expect(KeywordCompletion.suggestions(for: "SUN", from: names) == ["Sunset"])
        #expect(KeywordCompletion.suggestions(for: "", from: names).isEmpty)
        #expect(KeywordCompletion.suggestions(for: "do", from: names, limit: 2) == ["Dog", "Doge"])
    }

    @Test func completesTheLastWordAndSkipsKeywordsAlreadyTyped() {
        #expect(KeywordCompletion.suggestions(for: "dog, beach, do", from: names) == ["Doge", "dog park", "hot dog", "underdog"])
        #expect(KeywordCompletion.completing("beach,  do", with: "Dog") == "beach, Dog, ")
        #expect(KeywordCompletion.completing("do", with: "Dog") == "Dog, ")
    }

    @Test func readsEveryKeywordInTheField() {
        #expect(KeywordCompletion.keywords(in: "beach, Dog ,, dog,  sunset glow ") == ["beach", "Dog", "sunset glow"])
        #expect(KeywordCompletion.keywords(in: "  ").isEmpty)
    }
}
