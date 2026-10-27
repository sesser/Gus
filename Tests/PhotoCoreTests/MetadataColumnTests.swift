import Foundation
import GRDB
import PhotoFixtures
import Testing
@testable import PhotoCore

@Suite("Metadata columns")
struct MetadataColumnTests {
    @Test func localDatesUseTheCapturesOwnTimeZone() {
        // 2024-05-01 23:30 at +02:00 is 21:30 UTC, still May 1st where it was taken.
        let instant = ExifDate.parse("2024:05:01 23:30:00", offset: "+02:00")!
        #expect(LocalDate.string(captureDate: instant.date, offset: instant.offsetSeconds, fallback: .distantPast) == "2024-05-01")
        // 00:30 at -05:00 is 05:30 UTC on the same day; it is still May 1st there.
        let west = ExifDate.parse("2024:05:01 00:30:00", offset: "-05:00")!
        #expect(LocalDate.string(captureDate: west.date, offset: west.offsetSeconds, fallback: .distantPast) == "2024-05-01")
        // Floating local times are stored as UTC wall-clock times.
        let floating = ExifDate.parse("2024:12:31 23:59:00")!
        #expect(LocalDate.string(captureDate: floating.date, offset: nil, fallback: .distantPast) == "2024-12-31")
        // Without a capture date, the file date in the given zone.
        let mtime = Date(timeIntervalSince1970: 1_714_604_400) // 2024-05-01 23:00 UTC
        #expect(LocalDate.string(captureDate: nil, offset: nil, fallback: mtime, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
            == "2024-05-02")
    }

    private func writeTagged(_ url: URL) throws {
        try SyntheticImages.writeJPEG(to: url, width: 64, height: 48, seed: 9, exif: {
            var exif = SyntheticImages.Exif(dateTimeOriginal: "2024:05:01 10:00:00")
            exif.artist = "Pat Doe"
            exif.copyright = "© 2024 Pat Doe"
            exif.serialNumber = "123456"
            exif.latitude = -33.8568
            exif.longitude = 151.2153
            exif.flash = 1
            exif.exposureBias = -0.7
            exif.whiteBalance = 1
            return exif
        }())
    }

    private func expectTagged(_ metadata: ImageMetadata?) throws {
        let metadata = try #require(metadata)
        #expect(metadata.artist == "Pat Doe")
        #expect(metadata.copyright == "© 2024 Pat Doe")
        #expect(metadata.cameraSerial == "123456")
        #expect(abs((metadata.latitude ?? 0) + 33.8568) < 0.0001)
        #expect(abs((metadata.longitude ?? 0) - 151.2153) < 0.0001)
        #expect(metadata.flashFired == true)
        #expect(abs((metadata.exposureCompensation ?? 0) + 0.7) < 0.01)
        #expect(metadata.whiteBalance == 1)
    }

    @Test func imageIOReadsTheExtendedFields() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let file = root.appending(path: "tagged.jpg")
            try writeTagged(file)
            try expectTagged(ImageIOMetadataReader.read(file))
        }
    }

    @Test(.enabled(if: ExifToolMetadataReader.locateExecutable() != nil, "ExifTool is not installed"))
    func exifToolReadsTheExtendedFields() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let file = root.appending(path: "tagged.jpg")
            try writeTagged(file)
            let reader = ExifToolMetadataReader(executableURL: ExifToolMetadataReader.locateExecutable()!)
            let result = try await reader.metadata(for: [file])
            await reader.shutdown()
            try expectTagged(result[file])
        }
    }

    @Test func flashCompensationComesFromTheMakerNotes() {
        #expect(ExifToolMetadataReader.metadata(from: ["FlashExposureComp": -0.3333333]).flashCompensation == -0.3333333)
        #expect(ExifToolMetadataReader.metadata(from: ["FlashBias": 0.7]).flashCompensation == 0.7)
        #expect(ExifToolMetadataReader.metadata(from: ["Flash": 16]).flashCompensation == nil)
    }

    @Test func lensFallsBackToTheNameExifToolGivesMakerNoteCodes() {
        let panasonic = "Lumix G Vario 12-32mm F3.5-5.6 Asph. Mega OIS"
        #expect(ExifToolMetadataReader.metadata(from: ["LensID": panasonic]).lensModel == panasonic)
        #expect(ExifToolMetadataReader.metadata(from: ["LensModel": "FE 35mm F2.8 ZA", "LensID": "Sony FE 35mm"])
            .lensModel == "FE 35mm F2.8 ZA")
        #expect(ExifToolMetadataReader.metadata(from: ["LensID": "2 20 10"]).lensModel == nil)
        #expect(ExifToolMetadataReader.metadata(from: ["LensID": "Unknown (12 34)"]).lensModel == nil)
        #expect(ExifToolMetadataReader.metadata(from: ["LensID": "None"]).lensModel == nil)
    }

    @Test func importsRecordTheirRunAndColumns() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "Shoot")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeTagged(folder.appending(path: "a.jpg"))
            let catalog = try Catalog.makeInMemory()
            let importer = Importer(catalog: catalog, metadataReader: ImageIOMetadataReader())
            let summary = try await importer.importFolder(folder)
            let run = try #require(try await catalog.lastImportRun())
            #expect(run.projectId == summary.project?.id)
            let image = try #require(try await catalog.allImages().first)
            #expect(image.importRunId == run.id)
            #expect(image.localDate == "2024-05-01")
            #expect(image.artist == "Pat Doe")
            #expect(image.metadataRevision == ImageMetadata.revision)
            #expect(try await catalog.staleMetadata(onVolumes: [image.volumeId]).isEmpty)
        }
    }

    @Test func olderMastersAreReadAgain() async throws {
        let fixture = try await CatalogFixture.make()
        try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        let catalog = fixture.catalog
        try await catalog.database.write { db in try db.execute(sql: "UPDATE image SET metadataRevision = 1") }
        let stale = try await catalog.staleMetadata(onVolumes: [fixture.volume.id!])
        #expect(stale.map(\.url.path) == ["/Volumes/Test/shoot/IMG_0001.CR3", "/Volumes/Test/shoot/IMG_0002.CR3"])
        #expect(try await catalog.staleMetadata(onVolumes: [999]).isEmpty)

        var fresh = ImageMetadata()
        fresh.artist = "Someone"
        fresh.flashCompensation = -0.7
        fresh.lensModel = "Lumix G Vario 12-32mm"
        try await catalog.refreshMetadata([stale[0].imageID: fresh], checked: stale.map(\.imageID))
        #expect(try await catalog.staleMetadata(onVolumes: [fixture.volume.id!]).isEmpty)
        let images = try await catalog.allImages().sorted { $0.id! < $1.id! }
        #expect(images.map(\.artist) == ["Someone", nil])
        #expect(images.map(\.flashCompensation) == [-0.7, nil])
        // A lens found on a later read fills in; an unreadable master keeps its own.
        #expect(images[0].lensModel == "Lumix G Vario 12-32mm")
        // The capture date and size are not touched by a refresh.
        #expect(images[0].pixelWidth == 6000)
    }

    @Test func migrationGivesExistingMastersARunAndALocalDay() async throws {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue, upTo: "v3")
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO volume (id, identity, name, mountPath) VALUES (1, 'V', 'V', '/Volumes/V')")
            try db.execute(sql: "INSERT INTO project (id, uuid, name, sourcePath, createdAt) VALUES (1, 'a', 'A', '/a', '2024-01-01 00:00:00.000'), (2, 'b', 'B', '/b', '2024-02-01 00:00:00.000')")
            try db.execute(sql: """
                INSERT INTO image (id, volumeId, projectId, relativePath, fileName, fileSize, modifiedAt, contentHash,
                                   format, captureDate, captureOffsetSeconds, sortDate, importedAt)
                VALUES (1, 1, 1, 'a/1.jpg', '1.jpg', 1, '2024-01-01 00:00:00.000', 'h1', 'jpg',
                        '2023-12-31 23:30:00.000', 3600, '2023-12-31 23:30:00.000', '2024-01-01 00:00:00.000'),
                       (2, 1, 2, 'b/2.jpg', '2.jpg', 1, '2024-01-01 00:00:00.000', 'h2', 'jpg',
                        '2024-03-05 10:00:00.000', NULL, '2024-03-05 10:00:00.000', '2024-02-01 00:00:00.000')
                """)
        }
        let catalog = try Catalog(database: queue)
        let images = try await catalog.allImages().sorted { $0.id! < $1.id! }
        #expect(images.map(\.localDate) == ["2024-01-01", "2024-03-05"])
        #expect(images.map(\.metadataRevision) == [1, 1])
        let last = try #require(try await catalog.lastImportRun())
        #expect(last.projectId == 2)
        #expect(images[1].importRunId == last.id)
    }
}
