import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

@Suite("Folder drops")
struct FolderImportQueueTests {
    private func makeFolder(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeJPEG(_ url: URL, seed: UInt64) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SyntheticImages.writeJPEG(to: url, width: 64, height: 48, seed: seed,
                                      exif: .init(dateTimeOriginal: "2024:05:01 10:00:00"))
    }

    @Test func keepsFoldersInDropOrderAndIgnoresEverythingElse() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let beach = try makeFolder(root.appending(path: "Beach"))
            let city = try makeFolder(root.appending(path: "City"))
            let package = try makeFolder(root.appending(path: "Other.app"))
            let file = root.appending(path: "loose.jpg")
            try writeJPEG(file, seed: 1)
            let missing = root.appending(path: "Gone")
            let web = try #require(URL(string: "https://example.com/photos"))

            let dropped = DroppedFolders([city, file, package, beach, missing, web])
            #expect(dropped.folders == [city, beach])
            #expect(dropped.ignored == [file, package, missing, web])
        }
    }

    @Test func dropsRepeatsAndFoldersInsideAnotherDroppedFolder() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let trip = try makeFolder(root.appending(path: "Trip"))
            let day1 = try makeFolder(trip.appending(path: "Day 1"))
            // A sibling whose name starts like the folder is not inside it.
            let tripExtras = try makeFolder(root.appending(path: "Trip Extras"))

            let dropped = DroppedFolders([day1, trip, tripExtras, trip.appending(path: "./"), trip])
            #expect(dropped.folders == [trip, tripExtras])
            #expect(dropped.ignored.isEmpty)
        }
    }

    @Test func followsLinksAndAliasesToFolders() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let target = try makeFolder(root.appending(path: "Shoots/Wedding"))
            let link = root.appending(path: "Wedding Link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let alias = root.appending(path: "Wedding Alias")
            let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile)
            try URL.writeBookmarkData(bookmark, to: alias)

            // The link keeps its name; the alias stands for its target, which
            // the link already covers.
            #expect(DroppedFolders([link, alias]).folders == [link])
            #expect(DroppedFolders([alias]).folders.map(\.lastPathComponent) == ["Wedding"])
        }
    }

    @Test func queueSkipsFoldersTheBatchAlreadyCovers() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let a = try makeFolder(root.appending(path: "A"))
            let aInner = try makeFolder(a.appending(path: "Inner"))
            let b = try makeFolder(root.appending(path: "B"))
            let c = try makeFolder(root.appending(path: "C"))

            var queue = FolderImportQueue()
            #expect(!queue.isRunning)
            #expect(queue.enqueue([a, b]) == [a, b])
            #expect(queue.next() == a)
            #expect(queue.isRunning)
            // A second drop while A imports: A's subfolder and B are covered.
            #expect(queue.enqueue([aInner, b, c]) == [c])
            #expect(queue.count == 3)
            #expect(queue.next() == b)
            #expect(queue.next() == c)
            #expect(queue.started == 3)
            #expect(queue.next() == nil)
            #expect(!queue.isRunning)
        }
    }

    @Test func importsEachFolderAsItsOwnProjectAndAddsUpTheBatch() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let beach = root.appending(path: "Beach")
            try writeJPEG(beach.appending(path: "a.jpg"), seed: 1)
            try writeJPEG(beach.appending(path: "sub/b.jpg"), seed: 2)
            let city = root.appending(path: "City")
            try writeJPEG(city.appending(path: "c.jpg"), seed: 3)
            // Same content as a.jpg: already in the library once Beach is in.
            try FileManager.default.copyItem(at: beach.appending(path: "a.jpg"), to: city.appending(path: "copy.jpg"))
            let empty = try makeFolder(root.appending(path: "Empty"))

            let catalog = try Catalog.makeInMemory()
            let existing = try await catalog.createProject(name: "City")
            let importer = Importer(catalog: catalog, metadataReader: ImageIOMetadataReader())

            var queue = FolderImportQueue()
            queue.enqueue(DroppedFolders([beach, city, empty]).folders)
            while let folder = queue.next() {
                queue.record(try await importer.importFolder(folder))
            }
            let totals = queue.finish()
            #expect(totals.folders == 3)
            #expect(totals.imported == 3)
            #expect(totals.alreadyInLibrary == 1)
            #expect(totals.failed == 0)
            // The empty folder makes no project.
            #expect(totals.projectIDs.count == 2)
            #expect(queue.started == 0)

            let projects = try await catalog.projectSummaries()
            let byID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
            #expect(totals.projectIDs.compactMap { byID[$0]?.project.name } == ["Beach", "City"])
            #expect(totals.projectIDs.compactMap { byID[$0]?.versionCount } == [2, 1])
            #expect(byID[existing.id!]?.versionCount == 0)
            #expect(byID[totals.projectIDs[0]]?.project.sourcePath == beach.path)
        }
    }
}
