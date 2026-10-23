import Foundation
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

/// Counts how many files get hashed.
final class CountingHasher: ContentHasher {
    let count = Mutex(0)
    let delay: Duration

    init(delay: Duration = .zero) { self.delay = delay }

    func contentHash(of url: URL) async throws -> String {
        count.withLock { $0 += 1 }
        if delay > .zero { try await Task.sleep(for: delay) }
        return try await SHA256ContentHasher().contentHash(of: url)
    }

    var hashed: Int { count.withLock { $0 } }
}

@Suite("Importer")
struct ImporterTests {
    private func writeJPEG(_ url: URL, seed: UInt64, date: String? = "2024:05:01 10:00:00") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SyntheticImages.writeJPEG(to: url, width: 64, height: 48, seed: seed,
                                      exif: .init(dateTimeOriginal: date))
    }

    private func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func makeImporter(hasher: any ContentHasher = SHA256ContentHasher()) throws -> Importer {
        Importer(catalog: try Catalog.makeInMemory(), metadataReader: ImageIOMetadataReader(), hasher: hasher)
    }

    @Test func importsSupportedFilesRecursivelyIntoAProjectNamedAfterTheFolder() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let shoot = root.appending(path: "Beach Day")
            try writeJPEG(shoot.appending(path: "a.jpg"), seed: 1, date: "2024:05:01 10:00:02")
            try writeJPEG(shoot.appending(path: "sub/b.JPG"), seed: 2, date: "2024:05:01 10:00:01")
            try writeJPEG(shoot.appending(path: "sub/deeper/c.jpeg"), seed: 3, date: nil)
            try writeJPEG(shoot.appending(path: ".hidden.jpg"), seed: 4)
            try writeJPEG(shoot.appending(path: "Other.app/Contents/inside.jpg"), seed: 5)
            try Data("not an image".utf8).write(to: shoot.appending(path: "notes.txt"))

            let importer = try makeImporter()
            let summary = try await importer.importFolder(shoot)
            #expect(summary.progress.filesFound == 3)
            #expect(summary.progress.imported == 3)
            #expect(summary.failures.isEmpty)
            let project = try #require(summary.project)
            #expect(project.name == "Beach Day")
            #expect(project.sourcePath == shoot.path)

            let items = try await importer.catalog.libraryItems(matching: LibraryFilter(scope: .project(project.id!)))
            #expect(items.count == 3)
            #expect(items.map(\.versionID).sorted() == summary.insertedVersionIDs.sorted())
            // b and a are ordered by capture date; c has none and sorts by file date (now).
            #expect(items.map(\.fileName) == ["b.JPG", "a.jpg", "c.jpeg"])

            let details = try #require(try await importer.catalog.details(forVersion: items[1].versionID))
            #expect(details.version.isDefault)
            #expect(details.image.pixelWidth == 64)
            #expect(details.image.pixelHeight == 48)
            #expect(details.image.cameraMake == "Synthetic")
            #expect(details.image.captureDate == ExifDate.parse("2024:05:01 10:00:02")?.date)
            #expect(details.volume.url(forRelativePath: details.image.relativePath).resolvingSymlinksInPath()
                == shoot.appending(path: "a.jpg").resolvingSymlinksInPath())
        }
    }

    @Test func identicalFilesInOneImportAreRegisteredOnce() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            try writeJPEG(root.appending(path: "a.jpg"), seed: 1)
            try copy(root.appending(path: "a.jpg"), to: root.appending(path: "copies/a copy.jpg"))
            try writeJPEG(root.appending(path: "b.jpg"), seed: 2)
            let summary = try await makeImporter().importFolder(root)
            #expect(summary.progress.imported == 2)
            #expect(summary.progress.duplicates == 1)
        }
    }

    @Test func reimportingAFolderSkipsKnownFilesWithoutHashing() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            for seed in 1...5 { try writeJPEG(root.appending(path: "img\(seed).jpg"), seed: UInt64(seed)) }
            let hasher = CountingHasher()
            let importer = try makeImporter(hasher: hasher)
            _ = try await importer.importFolder(root)
            #expect(hasher.hashed == 5)

            let again = try await importer.importFolder(root)
            #expect(again.progress.alreadyInCatalog == 5)
            #expect(again.progress.imported == 0)
            #expect(again.project == nil, "no empty project for an import that found nothing new")
            #expect(hasher.hashed == 5)
            #expect(try await importer.catalog.projectSummaries().count == 1)
        }
    }

    @Test func copiesInAnotherFolderAreDuplicates() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            try writeJPEG(root.appending(path: "card/a.jpg"), seed: 1)
            try writeJPEG(root.appending(path: "card/b.jpg"), seed: 2)
            try copy(root.appending(path: "card/a.jpg"), to: root.appending(path: "backup/a.jpg"))
            try copy(root.appending(path: "card/b.jpg"), to: root.appending(path: "backup/renamed.jpg"))
            try writeJPEG(root.appending(path: "backup/new.jpg"), seed: 3)

            let importer = try makeImporter()
            _ = try await importer.importFolder(root.appending(path: "card"))
            let second = try await importer.importFolder(root.appending(path: "backup"))
            #expect(second.progress.duplicates == 2)
            #expect(second.progress.imported == 1)
            #expect(second.project?.name == "backup")
            #expect(try await importer.catalog.versionCount() == 3)
        }
    }

    @Test func changedContentAtAKnownPathIsReportedNotImported() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let file = root.appending(path: "a.jpg")
            try writeJPEG(file, seed: 1)
            try writeJPEG(root.appending(path: "b.jpg"), seed: 2)
            let importer = try makeImporter()
            _ = try await importer.importFolder(root)

            // Rewritten with new pixels (another app edited the original)...
            try FileManager.default.removeItem(at: file)
            try writeJPEG(file, seed: 99)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(120)], ofItemAtPath: file.path)
            // ...and touched without a content change.
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(240)],
                                                  ofItemAtPath: root.appending(path: "b.jpg").path)

            let again = try await importer.importFolder(root)
            #expect(again.progress.changedOnDisk == 1)
            #expect(again.progress.alreadyInCatalog == 1)
            #expect(again.progress.imported == 0)
            #expect(try await importer.catalog.versionCount() == 2)
        }
    }

    @Test func unreadableFilesAreReportedAndSkipped() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            try writeJPEG(root.appending(path: "ok.jpg"), seed: 1)
            let locked = root.appending(path: "locked.jpg")
            try writeJPEG(locked, seed: 2)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

            let summary = try await makeImporter().importFolder(root)
            #expect(summary.progress.imported == 1)
            #expect(summary.progress.failed == 1)
            #expect(summary.failures.map { ($0.path as NSString).lastPathComponent } == ["locked.jpg"])
        }
    }

    @Test func originalsAreNeverModified() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let file = root.appending(path: "a.jpg")
            try writeJPEG(file, seed: 7)
            let before = try Data(contentsOf: file)
            let attributesBefore = try FileManager.default.attributesOfItem(atPath: file.path)
            _ = try await makeImporter().importFolder(root)
            #expect(try Data(contentsOf: file) == before)
            let attributesAfter = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect(attributesAfter[.modificationDate] as? Date == attributesBefore[.modificationDate] as? Date)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["a.jpg"])
        }
    }

    @Test func cancellationStopsAtAChunkBoundaryAndKeepsWholeChunks() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            for seed in 0..<40 { try writeJPEG(root.appending(path: String(format: "img%03d.jpg", seed)), seed: UInt64(seed)) }
            let hasher = CountingHasher(delay: .milliseconds(15))
            let importer = try makeImporter(hasher: hasher)
            let progressSeen = Mutex(0)
            let task = Task {
                try await importer.importFolder(root, options: ImportOptions(chunkSize: 8, hashingConcurrency: 2)) { progress in
                    if progress.filesProcessed > 0 { progressSeen.withLock { $0 = progress.filesProcessed } }
                }
            }
            while progressSeen.withLock({ $0 }) == 0 { try await Task.sleep(for: .milliseconds(5)) }
            task.cancel()
            await #expect(throws: CancellationError.self) { _ = try await task.value }
            let count = try await importer.catalog.versionCount()
            #expect(count > 0 && count < 40)
            #expect(count % 8 == 0, "only whole chunks are committed, got \(count)")
            #expect(hasher.hashed < 40)
        }
    }

    @Test func sha256MatchesKnownVectors() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let file = root.appending(path: "abc.bin")
            try Data("abc".utf8).write(to: file)
            let small = SHA256ContentHasher(chunkSize: 1)
            #expect(try await small.contentHash(of: file)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            let empty = root.appending(path: "empty.bin")
            try Data().write(to: empty)
            #expect(try await SHA256ContentHasher().contentHash(of: empty)
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        }
    }
}

@Suite("Metadata")
struct MetadataTests {
    @Test func parsesExifDates() throws {
        let floating = try #require(ExifDate.parse("2024:05:01 10:00:00"))
        #expect(floating.offsetSeconds == nil)
        #expect(floating.date == Date(timeIntervalSince1970: 1_714_557_600))

        let withOffset = try #require(ExifDate.parse("2024:05:01 10:00:00", offset: "+02:00"))
        #expect(withOffset.offsetSeconds == 7_200)
        #expect(withOffset.date == Date(timeIntervalSince1970: 1_714_557_600 - 7_200))

        let inline = try #require(ExifDate.parse("2024:05:01 10:00:00.250-05:30"))
        #expect(inline.offsetSeconds == -(5 * 3_600 + 30 * 60))
        #expect(abs(inline.date.timeIntervalSince1970 - (1_714_557_600.25 + 19_800)) < 0.0001)

        let subSeconds = try #require(ExifDate.parse("2024:05:01 10:00:00", subSeconds: "050"))
        #expect(abs(subSeconds.date.timeIntervalSince1970 - 1_714_557_600.05) < 0.0001)

        #expect(ExifDate.parse("0000:00:00 00:00:00") == nil)
        #expect(ExifDate.parse("garbage") == nil)
        #expect(ExifDate.parse("1999:12:31 23:59:59")?.date == Date(timeIntervalSince1970: 946_684_799))
    }

    @Test func imageIOReadsGeneratedJPEG() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let file = root.appending(path: "a.jpg")
            try SyntheticImages.writeJPEG(to: file, width: 120, height: 80, seed: 3,
                                          exif: .init(dateTimeOriginal: "2023:01:02 03:04:05", offsetTimeOriginal: "+01:00",
                                                      make: "Maker", model: "Model X", orientation: 6))
            let metadata = try #require(try await ImageIOMetadataReader().metadata(for: [file])[file])
            #expect(metadata.pixelWidth == 120)
            #expect(metadata.pixelHeight == 80)
            #expect(metadata.orientation == 6)
            #expect(metadata.cameraMake == "Maker")
            #expect(metadata.cameraModel == "Model X")
            #expect(metadata.captureOffsetSeconds == 3_600)
            #expect(metadata.captureDate == ExifDate.parse("2023:01:02 03:04:05+01:00")?.date)
        }
    }

    @Test(.enabled(if: ExifToolMetadataReader.locateExecutable() != nil, "ExifTool is not installed"))
    func exifToolAgreesWithImageIO() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            var files: [URL] = []
            for seed in 0..<5 {
                let file = root.appending(path: "img \(seed).jpg")
                try SyntheticImages.writeJPEG(to: file, width: 100 + seed, height: 60, seed: UInt64(seed),
                                              exif: .init(dateTimeOriginal: "2022:06:0\(seed + 1) 12:00:00", orientation: 1 + seed))
                files.append(file)
            }
            let missing = root.appending(path: "missing.jpg")
            let reader = ExifToolMetadataReader(executableURL: ExifToolMetadataReader.locateExecutable()!)
            // Many overlapping calls must each get their own answer.
            let batches = (0..<12).map { index in [files[index % files.count], missing] }
            let combined = try await withThrowingTaskGroup(of: [URL: ImageMetadata].self) { group in
                for batch in batches {
                    group.addTask {
                        let result = try await reader.metadata(for: batch)
                        #expect(Set(result.keys) == [batch[0]])
                        return result
                    }
                }
                var all: [URL: ImageMetadata] = [:]
                for try await result in group { all.merge(result) { a, _ in a } }
                return all
            }
            await reader.shutdown()

            #expect(combined[missing] == nil)
            let reference = try await ImageIOMetadataReader().metadata(for: files)
            for file in files {
                let fromExifTool = try #require(combined[file], "no metadata for \(file.lastPathComponent)")
                let fromImageIO = try #require(reference[file])
                #expect(fromExifTool.captureDate == fromImageIO.captureDate)
                #expect(fromExifTool.pixelWidth == fromImageIO.pixelWidth)
                #expect(fromExifTool.pixelHeight == fromImageIO.pixelHeight)
                #expect(fromExifTool.orientation == fromImageIO.orientation)
                #expect(fromExifTool.cameraModel == "Generator")
            }
        }
    }

    @Test func fallbackFillsGapsFromTheSecondReader() async throws {
        struct Fixed: MetadataReader {
            let answers: [URL: ImageMetadata]
            func metadata(for urls: [URL]) async throws -> [URL: ImageMetadata] { answers.filter { urls.contains($0.key) } }
        }
        let a = URL(fileURLWithPath: "/a.jpg")
        let b = URL(fileURLWithPath: "/b.jpg")
        let reader = FallbackMetadataReader(
            primary: Fixed(answers: [a: ImageMetadata(iso: 100)]),
            fallback: Fixed(answers: [a: ImageMetadata(iso: 1), b: ImageMetadata(iso: 200)]))
        let result = try await reader.metadata(for: [a, b])
        #expect(result[a]?.iso == 100)
        #expect(result[b]?.iso == 200)
    }
}

@Suite("Volumes")
struct VolumeTests {
    @Test func relativePathsRoundTripThroughTheVolume() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let file = root.appending(path: "x/y.jpg")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: file)
            let scanned = try #require(try FileScanner.scan(root).first)
            let descriptor = try VolumeResolver.descriptor(forVolumeAt: scanned.volumeURL)
            #expect(descriptor.identity.hasPrefix("uuid:"))
            let relative = try #require(VolumeResolver.relativePath(of: scanned.url, inVolumeAt: descriptor.mountPath))
            #expect(!relative.hasPrefix("/"))
            let volume = VolumeRecord(id: 1, identity: descriptor.identity, name: descriptor.name,
                                      mountPath: descriptor.mountPath, isRemovable: false, isNetwork: false)
            #expect(FileManager.default.contentsEqual(atPath: volume.url(forRelativePath: relative).path, andPath: file.path))
        }
        #expect(VolumeResolver.relativePath(of: URL(fileURLWithPath: "/Volumes/Card/DCIM/a.jpg"), inVolumeAt: "/Volumes/Card") == "DCIM/a.jpg")
        #expect(VolumeResolver.relativePath(of: URL(fileURLWithPath: "/Volumes/Card2/a.jpg"), inVolumeAt: "/Volumes/Card") == nil)
        #expect(VolumeResolver.relativePath(of: URL(fileURLWithPath: "/Users/me/a.jpg"), inVolumeAt: "/") == "Users/me/a.jpg")
    }

    @Test func offlineVolumesStayInTheCatalogAndRemountsAreFollowed() async throws {
        let fixture = try await CatalogFixture.make()
        try await fixture.addMasters([CatalogFixture.master(1)])
        let other = try await fixture.catalog.registerVolume(
            VolumeDescriptor(identity: "uuid:OTHER", name: "Archive", mountPath: "/Volumes/Archive", isRemovable: true))

        // Only "Archive" is mounted, and at a new path.
        let online = try await fixture.catalog.refreshVolumeAvailability(mounted: [
            VolumeDescriptor(identity: "uuid:OTHER", name: "Archive", mountPath: "/Volumes/Archive 1"),
            VolumeDescriptor(identity: "uuid:UNRELATED", name: "Scratch", mountPath: "/Volumes/Scratch"),
        ])
        #expect(online == [other.id!])
        let volumes = try await fixture.catalog.volumes()
        #expect(volumes.count == 2)
        #expect(volumes.first { $0.id == other.id }?.mountPath == "/Volumes/Archive 1")
        #expect(try await fixture.catalog.versionCount() == 1, "items on the offline volume remain")
    }

    @Test func theBootVolumeIsReportedAsMounted() {
        let mounted = VolumeAvailability.mountedVolumes()
        #expect(mounted.contains { $0.mountPath == "/" })
    }
}
