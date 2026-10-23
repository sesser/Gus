import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

@Suite("Videos")
struct VideoTests {
    static let options = SyntheticVideo.Options(width: 320, height: 240, seconds: 2, seed: 7,
                                                creationDate: "2024-05-01T10:00:00+02:00", make: "Canon", model: "EOS R5")

    @Test func readsDurationSizeDateAndCamera() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "clip.mov")
            try await SyntheticVideo.write(to: url, options: Self.options)
            let metadata = try #require(try await VideoMetadataReader().metadata(for: [url])[url])
            #expect(abs((metadata.duration ?? 0) - 2) < 0.2)
            #expect(metadata.pixelWidth == 320 && metadata.pixelHeight == 240)
            #expect(metadata.captureDate == ISO8601DateFormatter().date(from: "2024-05-01T08:00:00Z"))
            #expect(metadata.cameraMake == "Canon" && metadata.cameraModel == "EOS R5")
            #expect(VideoMetadataReader.coordinates(iso6709: "+37.3317-122.0302+012.000/") == (37.3317, -122.0302))
        }
    }

    @Test func posterFramesAreSmallAndUpright() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "clip.mp4")
            try await SyntheticVideo.write(to: url, options: Self.options)
            let poster = try await VideoFrames.poster(of: url, longEdge: 160)
            #expect(max(poster.width, poster.height) <= 160 && poster.width > poster.height)
        }
    }

    @Test func videosAreCataloguedPreviewedAndFound() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "Shoot")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await SyntheticVideo.write(to: folder.appending(path: "clip.mov"), options: Self.options)
            try SyntheticImages.writeJPEG(to: folder.appending(path: "clip.jpg"), width: 64, height: 48, seed: 1,
                                          exif: .init(dateTimeOriginal: "2024:05:01 10:00:00"))
            let catalog = try Catalog.makeInMemory()
            let reader = MediaMetadataReader(photos: ImageIOMetadataReader())
            let summary = try await Importer(catalog: catalog, metadataReader: reader).importFolder(folder)
            #expect(summary.progress.imported == 2)

            let items = try await catalog.libraryItems(matching: LibraryFilter())
            let video = try #require(items.first { $0.isVideo })
            #expect(abs((video.duration ?? 0) - 2) < 0.2)
            // A video and a JPEG with the same name are not a pair.
            #expect(items.allSatisfy { $0.partnerVersionID == nil })

            let videos = SmartAlbumRules(match: .all, rules: [SmartRule(field: .fileType, value: RuleValue(text: "video"))])
            #expect(try await catalog.libraryItems(matching: LibraryFilter(scope: .rules(videos, projectID: nil))).map(\.fileName)
                == ["clip.mov"])

            let previews = PreviewService(cacheDirectory: root.appending(path: "cache"), catalog: catalog)
            let key = try #require(PreviewCacheKey(item: video, tier: .thumbnail))
            let request = PreviewRequest(versionID: video.versionID, key: key, sourceURL: folder.appending(path: "clip.mov"))
            let image = try await previews.image(for: request, maxPixelSize: 256)
            #expect(image.width > 0 && previews.cache.contains(key))
        }
    }

    @Test func cardScansCanLeaveVideosOut() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            try await SyntheticVideo.write(to: root.appending(path: "MVI_0001.MP4"), options: Self.options)
            try SyntheticImages.writeJPEG(to: root.appending(path: "IMG_0001.JPG"), width: 64, height: 48, seed: 1)
            let reader = MediaMetadataReader(photos: ImageIOMetadataReader())
            #expect(try await SourceScanner.scan(root, reader: reader).count == 2)
            #expect(try await SourceScanner.scan(root, reader: reader, includingVideos: false).map(\.primary.name) == ["IMG_0001.JPG"])
        }
    }
}
