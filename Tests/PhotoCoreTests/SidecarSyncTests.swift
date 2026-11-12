import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

@Suite("Sidecar sync")
struct SidecarSyncTests {
    struct Library {
        let root: URL
        let folder: URL
        let catalog: Catalog
        let sync: SidecarSync
        var mounted: Set<Int64> = []

        func version(named name: String) async throws -> CatalogItem {
            try #require(try await catalog.libraryItems(matching: LibraryFilter(groupsPairs: false)).first { $0.fileName == name })
        }

        func sidecar(_ name: String) throws -> SidecarValues {
            try SidecarFiles.read(folder.appending(path: name)).values
        }

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: folder.appending(path: name).path)
        }

        /// Another app edits a sidecar: the change lands with a later date.
        func editSidecar(_ name: String, _ change: (XMPDocument) -> Void) throws {
            let url = folder.appending(path: name)
            let document = try XMPDocument(data: Data(contentsOf: url))
            change(document)
            try document.data().write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        }
    }

    private func makeLibrary(_ root: URL, files: [String], sidecars: [String: SidecarValues] = [:]) async throws -> Library {
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
        _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(folder)
        var library = Library(root: root, folder: folder, catalog: catalog,
                              sync: SidecarSync(catalog: catalog, metadataReader: ImageIOMetadataReader()))
        library.mounted = Set(try await catalog.volumes().compactMap(\.id))
        return library
    }

    @Test func importTakesValuesFromSidecars() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let values = SidecarValues(rating: Rating(clamping: 3), flag: .rejected, colorLabel: .blue,
                                       keywords: ["dog", "beach"], creator: "Pat Doe", rights: "© Pat Doe")
            let library = try await makeLibrary(root, files: ["a.jpg", "b.jpg"], sidecars: ["a.xmp": values])
            let a = try await library.version(named: "a.jpg")
            #expect(a.rating == Rating(clamping: 3) && a.flag == .rejected && a.colorLabel == .blue)
            #expect(try await library.catalog.keywords(forVersion: a.versionID).map(\.name) == ["beach", "dog"])
            let image = try #require(try await library.catalog.allImages().first { $0.fileName == "a.jpg" })
            #expect(image.artist == "Pat Doe" && image.copyright == "© Pat Doe")

            // Nothing differs from the files, so nothing is written.
            let report = try await library.sync.processQueue(mountedVolumes: library.mounted)
            #expect(report.written == 0 && report.changedOnDisk == 0)
            #expect(!library.exists("b.xmp"))
            #expect(try await !library.catalog.hasQueuedSidecarWork())
        }
    }

    @Test func libraryChangesAreWrittenAndPairsShareOneSidecar() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root, files: ["IMG_1.DNG", "IMG_1.JPG", "IMG_2.JPG"])
            let catalog = library.catalog
            let jpeg = try await library.version(named: "IMG_1.JPG")
            try await catalog.setRating(Rating(clamping: 4), forVersions: [jpeg.versionID])
            try await catalog.addKeywords(named: ["sunset"], toVersions: [jpeg.versionID])
            let report = try await library.sync.processQueue(mountedVolumes: library.mounted)
            #expect(report.written == 1)
            #expect(try library.sidecar("IMG_1.xmp").rating == Rating(clamping: 4))
            #expect(try library.sidecar("IMG_1.xmp").keywords == ["sunset"])
            #expect(!library.exists("IMG_1.JPG.xmp") && !library.exists("IMG_1.DNG.xmp") && !library.exists("IMG_2.xmp"))

            // A second change edits the same file and keeps what other apps put in it.
            try library.editSidecar("IMG_1.xmp") { $0.setSimple("http://ns.example.com/other/", "Setting", "kept") }
            try await catalog.resolveTestBaseline(library)
            try await catalog.setColorLabel(.red, forVersions: [jpeg.versionID])
            #expect(try await library.sync.processQueue(mountedVolumes: library.mounted).written == 1)
            let document = try XMPDocument(data: Data(contentsOf: library.folder.appending(path: "IMG_1.xmp")))
            #expect(document.values().colorLabel == .red)
            #expect(document.simple("http://ns.example.com/other/", "Setting") == "kept")
        }
    }

    /// A photo with one copy whose sidecar another app changed, waiting for review.
    private func libraryWithAChangedSidecarAndACopy(_ root: URL, files: [String] = ["a.jpg"], sidecar: String = "a.xmp")
        async throws -> (library: Library, original: CatalogItem, copyID: Int64) {
        let library = try await makeLibrary(root, files: files, sidecars: [sidecar: SidecarValues(rating: Rating(clamping: 1))])
        _ = try await library.sync.processQueue(mountedVolumes: library.mounted)
        let original = try await library.version(named: files[0])
        let copyID = try await library.catalog.duplicateVersions(ids: [original.versionID])[0].copyVersionID
        try library.editSidecar(sidecar) { $0.setSimple(XMPDocument.Namespace.xmp, "Rating", "5") }
        let report = try await library.sync.checkForChanges(mountedVolumes: library.mounted)
        #expect(report.changedOnDisk == 1)
        return (library, original, copyID)
    }

    @Test("virtual-copies D-V1: the Changed on Disk source lists originals only, and a copy alone has no change to review")
    func copiesTakeNoPartInSidecarReview() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let (library, original, copyID) = try await libraryWithAChangedSidecarAndACopy(root)
            let catalog = library.catalog
            // The source: one item for the master, its original, and a count that matches the sidebar's.
            let listed = try await catalog.libraryItems(matching: LibraryFilter(scope: .changedOnDisk))
            #expect(listed.map(\.versionID) == [original.versionID])
            #expect(try await catalog.itemCount(matching: LibraryFilter(scope: .changedOnDisk)) == 1)
            #expect(try await catalog.diskChangeCount() == 1)
            // The inspector: nothing for the copy alone, the change for the original.
            #expect(try await catalog.diskChanges(forVersions: [copyID]).isEmpty)
            #expect(try await catalog.diskChanges(forVersions: [original.versionID]).map(\.imageID) == [original.imageID])
            // The copy is still in the library, beside its original.
            #expect(try await catalog.libraryItems(matching: LibraryFilter()).map(\.versionID) == [original.versionID, copyID])
        }
    }

    @Test("virtual-copies C1: two versions of one master in a selection list its change once (this trapped)")
    func twoVersionsOfOneMasterListItsChangeOnce() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let (library, original, copyID) = try await libraryWithAChangedSidecarAndACopy(root)
            let catalog = library.catalog
            let second = try await catalog.duplicateVersions(ids: [copyID])[0].copyVersionID
            // The original with its copies, in any order and named twice.
            for selection in [[original.versionID, copyID], [copyID, second, original.versionID],
                              [original.versionID, original.versionID, copyID]] {
                let changes = try await catalog.diskChanges(forVersions: selection)
                #expect(changes.map(\.imageID) == [original.imageID])
                #expect(changes.first?.disk.rating == Rating(clamping: 5))
            }
            // Two copies of one master, without their original: nothing to review.
            #expect(try await catalog.diskChanges(forVersions: [copyID, second]).isEmpty)
            // The owner lookup itself takes a master named more than once.
            let owners = try await catalog.database.read { db in
                try Catalog.sidecarOwners(db, images: [original.imageID, original.imageID])
            }
            #expect(owners == [original.imageID: original.imageID])
        }
    }

    @Test("virtual-copies D-V1: a pair's change is listed for its two files, not for a copy of either")
    func aPairsChangeIsNotListedForACopy() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let (library, raw, rawCopy) = try await libraryWithAChangedSidecarAndACopy(root, files: ["IMG_1.dng", "IMG_1.jpg"],
                                                                                        sidecar: "IMG_1.xmp")
            let catalog = library.catalog
            let jpeg = try await library.version(named: "IMG_1.jpg")
            let jpegCopy = try await catalog.duplicateVersions(ids: [jpeg.versionID])[0].copyVersionID
            let separate = try await catalog.libraryItems(matching: LibraryFilter(scope: .changedOnDisk, groupsPairs: false))
            #expect(Set(separate.map(\.versionID)) == [raw.versionID, jpeg.versionID])
            #expect(try await catalog.libraryItems(matching: LibraryFilter(scope: .changedOnDisk)).count == 1)
            #expect(try await catalog.diskChanges(forVersions: [rawCopy, jpegCopy]).isEmpty)
            // The JPEG's original still leads to the RAW's sidecar.
            #expect(try await catalog.diskChanges(forVersions: [jpeg.versionID, jpegCopy]).map(\.imageID) == [raw.imageID])
        }
    }

    @Test func outsideChangesAreFlaggedNotOverwritten() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root, files: ["a.jpg"],
                                                sidecars: ["a.xmp": SidecarValues(rating: Rating(clamping: 1))])
            let catalog = library.catalog
            let a = try await library.version(named: "a.jpg")
            // Another app gives it five stars and a keyword, then the library changes too.
            try library.editSidecar("a.xmp") { document in
                document.setSimple(XMPDocument.Namespace.xmp, "Rating", "5")
                document.setArray(XMPDocument.Namespace.dc, "subject", .bag, ["heeler"])
            }
            try await catalog.setRating(Rating(clamping: 2), forVersions: [a.versionID])
            try await catalog.addKeywords(named: ["dog"], toVersions: [a.versionID])
            let report = try await library.sync.processQueue(mountedVolumes: library.mounted)
            #expect(report.changedOnDisk == 1 && report.written == 0)
            #expect(try library.sidecar("a.xmp").rating == Rating(clamping: 5))

            let changes = try await catalog.diskChanges(forVersions: [a.versionID])
            let change = try #require(changes.first)
            #expect(change.library.rating == Rating(clamping: 2) && change.disk.rating == Rating(clamping: 5))
            #expect(Set(change.changedFields) == [.rating, .keywords])
            #expect(try await catalog.libraryItems(matching: LibraryFilter(scope: .changedOnDisk)).map(\.fileName) == ["a.jpg"])
            #expect(try await catalog.diskChangeCount() == 1)

            // Further library changes leave the file alone until someone decides.
            try await catalog.setFlag(.picked, forVersions: [a.versionID])
            _ = try await library.sync.processQueue(mountedVolumes: library.mounted)
            #expect(try library.sidecar("a.xmp").flag == .none)

            // Take the file's rating, keep both keywords.
            let fresh = try await catalog.diskChanges(forVersions: [a.versionID])
            try await library.sync.resolve(fresh, with: .fields([.rating], mergeKeywords: true), mountedVolumes: library.mounted)
            let resolved = try await library.version(named: "a.jpg")
            #expect(resolved.rating == Rating(clamping: 5) && resolved.flag == .picked)
            #expect(try await catalog.keywords(forVersion: a.versionID).map(\.name) == ["dog", "heeler"])
            let written = try library.sidecar("a.xmp")
            #expect(written.rating == Rating(clamping: 5) && written.flag == .picked && Set(written.keywords) == ["dog", "heeler"])
            #expect(try await catalog.diskChangeCount() == 0)
            #expect(try await !catalog.hasQueuedSidecarWork())
            #expect(try await library.sync.processQueue(mountedVolumes: library.mounted) == SidecarSync.Report())
        }
    }

    @Test func keepingLibraryValuesOrTakingTheFiles() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let start = SidecarValues(rating: Rating(clamping: 1))
            let library = try await makeLibrary(root, files: ["a.jpg", "b.jpg"], sidecars: ["a.xmp": start, "b.xmp": start])
            let catalog = library.catalog
            for name in ["a.xmp", "b.xmp"] {
                try library.editSidecar(name) { $0.setSimple(XMPDocument.Namespace.xmp, "Rating", "4") }
            }
            let report = try await library.sync.checkForChanges(mountedVolumes: library.mounted)
            #expect(report.changedOnDisk == 2 && report.checked == 2)
            let a = try await library.version(named: "a.jpg")
            let b = try await library.version(named: "b.jpg")

            try await library.sync.resolve(try await catalog.diskChanges(forVersions: [a.versionID]), with: .keepLibrary,
                                           mountedVolumes: library.mounted)
            #expect(try library.sidecar("a.xmp").rating == Rating(clamping: 1))
            try await library.sync.resolve(try await catalog.diskChanges(forVersions: [b.versionID]), with: .useFile,
                                           mountedVolumes: library.mounted)
            #expect(try await library.version(named: "b.jpg").rating == Rating(clamping: 4))
            #expect(try library.sidecar("b.xmp").rating == Rating(clamping: 4))
            #expect(try await library.sync.checkForChanges(mountedVolumes: library.mounted).changedOnDisk == 0)
        }
    }

    @Test func newSidecarsFromOtherAppsAreNoticed() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root, files: ["a.jpg", "b.jpg"])
            _ = try SidecarFiles.write(SidecarValues(keywords: ["from elsewhere"]), previous: nil,
                                       to: library.folder.appending(path: "a.jpg.xmp"))
            // Same values as the library: noted, not flagged.
            _ = try SidecarFiles.write(SidecarValues(), previous: nil, to: library.folder.appending(path: "b.xmp"))
            let report = try await library.sync.checkForChanges(mountedVolumes: library.mounted)
            #expect(report.changedOnDisk == 1)
            let a = try await library.version(named: "a.jpg")
            #expect(try await library.catalog.diskChanges(forVersions: [a.versionID]).first?.disk.keywords == ["from elsewhere"])
        }
    }

    @Test func mastersChangedByOtherAppsAreRehashedAndCompared() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root, files: ["a.jpg"])
            let before = try #require(try await library.catalog.allImages().first)
            // Another app embeds a rating in the JPEG itself.
            try SyntheticImages.writeJPEG(to: library.folder.appending(path: "a.jpg"), width: 64, height: 48, seed: 1,
                                          exif: .init(dateTimeOriginal: "2024:05:01 10:00:00", xmpRating: 5))
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)],
                                                  ofItemAtPath: library.folder.appending(path: "a.jpg").path)
            let report = try await library.sync.checkForChanges(mountedVolumes: library.mounted)
            #expect(report.changedOnDisk == 1)
            let after = try #require(try await library.catalog.allImages().first)
            #expect(after.contentHash != before.contentHash)
            let a = try await library.version(named: "a.jpg")
            let change = try #require(try await library.catalog.diskChanges(forVersions: [a.versionID]).first)
            #expect(change.source == .embedded && change.disk.rating == Rating(clamping: 5))
            // Keeping the library's values does not touch the original.
            let bytes = try Data(contentsOf: library.folder.appending(path: "a.jpg"))
            try await library.sync.resolve([change], with: .keepLibrary, mountedVolumes: library.mounted)
            #expect(try Data(contentsOf: library.folder.appending(path: "a.jpg")) == bytes)
            #expect(try await library.sync.checkForChanges(mountedVolumes: library.mounted).changedOnDisk == 0)
        }
    }

    @Test func offlineMastersWaitAndReadOnlyFoldersFail() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await makeLibrary(root, files: ["a.jpg"])
            let a = try await library.version(named: "a.jpg")
            try await library.catalog.setRating(Rating(clamping: 3), forVersions: [a.versionID])
            #expect(try await library.sync.processQueue(mountedVolumes: []).written == 0)
            #expect(try await library.catalog.hasQueuedSidecarWork())

            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: library.folder.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.folder.path) }
            let report = try await library.sync.processQueue(mountedVolumes: library.mounted)
            #expect(report.failed == 1 && report.written == 0)
            #expect(!library.exists("a.xmp"))
        }
    }
}

extension Catalog {
    /// Test helper: accept whatever the sidecars hold now as the baseline, as a
    /// check would after another app's harmless edit.
    func resolveTestBaseline(_ library: SidecarSyncTests.Library) async throws {
        for change in try await diskChanges(forVersions: libraryItems(matching: LibraryFilter(groupsPairs: false)).map(\.versionID)) {
            try await library.sync.resolve([change], with: .useFile, mountedVolumes: library.mounted)
        }
        _ = try await library.sync.checkForChanges(mountedVolumes: library.mounted)
        for change in try await diskChanges(forVersions: libraryItems(matching: LibraryFilter(groupsPairs: false)).map(\.versionID)) {
            try await library.sync.resolve([change], with: .useFile, mountedVolumes: library.mounted)
        }
    }
}
