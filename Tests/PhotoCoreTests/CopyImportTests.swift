import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

@Suite("Copying imports")
struct CopyImportTests {
    /// A card: DCIM/100TEST with a.JPG, b.DNG + b.JPG, c.HEIC, taken on 2024-05-01.
    /// (ImageIO does not open synthetic DNGs much smaller than 400 × 300.)
    private func makeCard(_ root: URL) throws -> URL {
        let folder = root.appending(path: "CARD/DCIM/100TEST")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let date = "2024:05:01 10:00:00"
        try SyntheticImages.writeJPEG(to: folder.appending(path: "a.JPG"), width: 64, height: 48, seed: 1,
                                      exif: .init(dateTimeOriginal: date))
        try SyntheticDNG.write(to: folder.appending(path: "b.DNG"), options: .init(width: 400, height: 300, seed: 2,
                                                                                   dateTimeOriginal: date))
        try SyntheticImages.writeJPEG(to: folder.appending(path: "b.JPG"), width: 64, height: 48, seed: 3,
                                      exif: .init(dateTimeOriginal: date))
        guard let image = SyntheticImages.makeImage(width: 64, height: 48, seed: 4) else { throw CocoaError(.fileWriteUnknown) }
        try SyntheticImages.write(image, to: folder.appending(path: "c.HEIC"), type: .heic, exif: .init(dateTimeOriginal: date))
        return root.appending(path: "CARD")
    }

    private func scan(_ card: URL, _ catalog: Catalog, hasher: any ContentHasher = SHA256ContentHasher()) async throws -> [SourceShot] {
        let shots = try await SourceScanner.scan(card, reader: ImageIOMetadataReader())
        return try await SourceScanner.markDuplicates(in: shots, catalog: catalog, hasher: hasher)
    }

    @Test func shotsGroupPairsAndOnlySizeMatchesAreHashed() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let card = try makeCard(root)
            let catalog = try Catalog.makeInMemory()
            // a.JPG is already in the library, imported from elsewhere.
            let elsewhere = root.appending(path: "Elsewhere")
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: card.appending(path: "DCIM/100TEST/a.JPG"), to: elsewhere.appending(path: "a.jpg"))
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(elsewhere)

            let hasher = CountingHasher()
            let shots = try await scan(card, catalog, hasher: hasher)
            #expect(shots.map { $0.files.map(\.name) } == [["a.JPG"], ["b.DNG", "b.JPG"], ["c.HEIC"]])
            #expect(shots.map(\.isDuplicate) == [true, false, false])
            #expect(hasher.hashed == 1)
        }
    }

    @Test func copiesVerifiesAndCatalogsWithTemplates() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let card = try makeCard(root)
            let library = root.appending(path: "Photos")
            let catalog = try Catalog.makeInMemory()
            let shots = try await scan(card, catalog)
            let options = CopyImportOptions(destination: library,
                                            template: ImportTemplate(folder: "{capture:yyyy}/{capture:yyyy-MM-dd} {job}",
                                                                     fileName: "{job}-{seq:3}"),
                                            jobCode: "Smith", firstCounter: 7)
            let result = try await CopyImporter(catalog: catalog).run(shots: shots, sourceRoot: card, options: options)
            #expect(result.failures.isEmpty)
            #expect(result.copied == 4 && result.alreadyAtDestination == 0)
            #expect(result.nextCounter == 10)
            #expect(result.project?.name == "2024-05-01 Smith")
            #expect(Set(result.verifiedSources.map(\.lastPathComponent)) == ["a.JPG", "b.DNG", "b.JPG", "c.HEIC"])

            let folder = library.appending(path: "2024/2024-05-01 Smith")
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            #expect(names == ["Smith-001.JPG", "Smith-002.DNG", "Smith-002.JPG", "Smith-003.HEIC"])
            // Copies are byte-identical, keep the original dates, and the pair pairs again.
            let original = card.appending(path: "DCIM/100TEST/b.DNG")
            let copy = folder.appending(path: "Smith-002.DNG")
            #expect(try Data(contentsOf: copy) == Data(contentsOf: original))
            let dates = try [original, copy].map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            #expect(abs(try #require(dates[0]).timeIntervalSince(try #require(dates[1]))) < 0.001)
            let items = try await catalog.libraryItems(matching: LibraryFilter(scope: .project(result.project!.id!)))
            #expect(items.map(\.fileName) == ["Smith-001.JPG", "Smith-002.DNG", "Smith-003.HEIC"])
            #expect(items[1].representsPair)
            #expect(try await catalog.lastImportRun()?.sourcePath == card.path)
            // The card is untouched.
            #expect(FileManager.default.fileExists(atPath: original.path))

            // Importing the card again finds everything in the library.
            #expect(try await scan(card, catalog).allSatisfy(\.isDuplicate))
        }
    }

    @Test func nameClashesGetSuffixesForTheWholeShot() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let card = try makeCard(root)
            let library = root.appending(path: "Photos")
            let folder = library.appending(path: "in")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // A different b.DNG is there already; an identical c.HEIC too.
            try Data("other".utf8).write(to: folder.appending(path: "b.DNG"))
            try FileManager.default.copyItem(at: card.appending(path: "DCIM/100TEST/c.HEIC"), to: folder.appending(path: "c.HEIC"))
            let catalog = try Catalog.makeInMemory()
            let result = try await CopyImporter(catalog: catalog).run(
                shots: try await scan(card, catalog), sourceRoot: card,
                options: CopyImportOptions(destination: library, template: ImportTemplate(folder: "in", fileName: "{name}")))
            #expect(result.copied == 3 && result.alreadyAtDestination == 1)
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            #expect(names == ["a.JPG", "b-1.DNG", "b-1.JPG", "b.DNG", "c.HEIC"])
            #expect(result.verifiedSources.count == 4)
        }
    }

    @Test func importMetadataExpandsTokensAndAlwaysWritesSidecars() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let card = try makeCard(root)
            let library = root.appending(path: "Photos")
            let catalog = try Catalog.makeInMemory()
            let sidecars = SidecarSync(catalog: catalog, metadataReader: ImageIOMetadataReader())
            let preset = SidecarValues(creator: "Pat Doe", rights: "© {capture:yyyy} Pat Doe", usageTerms: "Ask first",
                                       contact: CreatorContact(email: "pat@example.com"))
            let result = try await CopyImporter(catalog: catalog, sidecars: sidecars).run(
                shots: try await scan(card, catalog), sourceRoot: card,
                options: CopyImportOptions(destination: library, template: ImportTemplate(folder: "in", fileName: "{name}"),
                                           metadata: preset))
            let image = try #require(try await catalog.allImages().first { $0.fileName == "a.JPG" })
            #expect(image.artist == "Pat Doe" && image.copyright == "© 2024 Pat Doe" && image.usageTerms == "Ask first")
            #expect(result.insertedVersionIDs.count == 4)
            let folder = library.appending(path: "in")
            let sidecar = try SidecarFiles.read(folder.appending(path: "a.xmp")).values
            #expect(sidecar.rights == "© 2024 Pat Doe" && sidecar.contact?.email == "pat@example.com")
            // One sidecar for the pair.
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: "b.xmp").path))
            #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "b.JPG.xmp").path))
            #expect(try await !catalog.hasQueuedSidecarWork())
        }
    }

    @Test func onlyVerifiedSourcesAreDeleted() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let card = try makeCard(root)
            let catalog = try Catalog.makeInMemory()
            let shots = try await scan(card, catalog)
            let result = try await CopyImporter(catalog: catalog).run(
                shots: [shots[1]], sourceRoot: card, options: CopyImportOptions(destination: root.appending(path: "Photos")))
            #expect(CopyImporter.deleteSources(result.verifiedSources).isEmpty)
            let left = try FileManager.default.contentsOfDirectory(atPath: card.appending(path: "DCIM/100TEST").path).sorted()
            #expect(left == ["a.JPG", "c.HEIC"])
        }
    }

    @Test func cancellingLeavesNoPartialFiles() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let card = try makeCard(root)
            let library = root.appending(path: "Photos")
            let catalog = try Catalog.makeInMemory()
            let shots = try await scan(card, catalog)
            let task = Task {
                try await CopyImporter(catalog: catalog).run(shots: shots, sourceRoot: card,
                                                             options: CopyImportOptions(destination: library)) { progress in
                    if progress.filesDone == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
            await #expect(throws: CancellationError.self) { try await task.value }
            let leftovers = FileManager.default.enumerator(atPath: library.path)?.allObjects
                .compactMap { $0 as? String }.filter { $0.hasSuffix(".partial") } ?? []
            #expect(leftovers.isEmpty)
        }
    }
}

@Suite("Metadata presets")
struct MetadataPresetTests {
    @Test func presetsAreSavedUpdatedAndDeleted() async throws {
        let catalog = try Catalog.makeInMemory()
        var preset = try await catalog.saveMetadataPreset(
            MetadataPreset(name: "Studio", values: SidecarValues(creator: "Pat", rights: "© {capture:yyyy} Pat")))
        preset.values.usageTerms = "Editorial use"
        _ = try await catalog.saveMetadataPreset(preset)
        _ = try await catalog.saveMetadataPreset(MetadataPreset(name: "Agency", values: SidecarValues(creator: "Agency")))
        #expect(try await catalog.metadataPresets().map(\.name) == ["Agency", "Studio"])
        #expect(try await catalog.metadataPresets().last?.values.usageTerms == "Editorial use")
        try await catalog.deleteMetadataPreset(id: preset.id!)
        #expect(try await catalog.metadataPresets().map(\.name) == ["Agency"])
    }
}
