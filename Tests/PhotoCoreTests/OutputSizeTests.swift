import CoreGraphics
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The loupe sizes a photo on arrival from the size its full-resolution
/// rendition will have, so the photo doesn't move when the rendition replaces
/// the preview (docs/features/full-render-main-thread-stall/status.md, the
/// owner's jump). The catalog's size, from the file's metadata, left out the
/// decoder's frame and the crop: an Olympus ORF is 4640 x 3472 there and
/// renders at 4608 x 3072.
@Suite("Full rendition size before rendering")
struct OutputSizeTests {
    private let contentHash = String(repeating: "cd", count: 32)

    /// What the loupe sized the photo from before the fix: the catalog's
    /// pixel size, from the metadata reader, after the EXIF orientation.
    static func catalogSize(_ url: URL, reader: any MetadataReader = ImageIOMetadataReader()) async throws -> CGSize {
        let metadata = try #require(try await reader.metadata(for: [url])[url])
        let width = try #require(metadata.pixelWidth), height = try #require(metadata.pixelHeight)
        return ImageMetadata.swapsDimensions(metadata.orientation)
            ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// `outputSize(for:)` gives the full rendition's size before rendering it,
    /// keeps it, and the rendition records its own size too.
    static func expectSizeBeforeRendering(_ source: URL, stack: EditStack, root: URL, hash: String,
                                          reader: any MetadataReader = ImageIOMetadataReader()) async throws
        -> (predicted: CGSize, rendered: CGSize) {
        let key = try #require(PreviewCacheKey(contentHash: hash, editStackHash: stack.renderHash, tier: .preview))
        let request = PreviewRequest(versionID: 1, key: key, sourceURL: source)
        let service = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "cache-\(hash.prefix(4))")),
                                     editStack: { _ in stack })
        #expect(service.memoryCachedOutputSize(for: request) == nil)
        let predicted = try #require(await service.outputSize(for: request))
        #expect(service.memoryCachedOutputSize(for: request) == predicted)
        let full = try await service.fullResolutionImage(for: request)
        let rendered = CGSize(width: full.width, height: full.height)
        #expect(predicted == rendered, "\(source.lastPathComponent): predicted \(predicted), rendered \(rendered)")

        // What the loupe sizes the photo to on arrival once the size was asked
        // ahead (a neighbor), against the catalog's size.
        let catalog = try await catalogSize(source, reader: reader)
        let arrival = LoupeArrivalSize.size(knownOutput: service.memoryCachedOutputSize(for: request), catalog: catalog)
        #expect(arrival == rendered, "\(source.lastPathComponent): arrives at \(String(describing: arrival)), renders at \(rendered)")

        let fresh = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "fresh-\(hash.prefix(4))")),
                                   editStack: { _ in stack })
        _ = try await fresh.fullResolutionImage(for: request)
        #expect(fresh.memoryCachedOutputSize(for: request) == rendered)
        return (predicted, rendered)
    }

    @Test("A cropped, turned raw is sized as it renders, not as its file says")
    func croppedRaw() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "photo.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 1200, height: 800, seed: 9))
            var values = Adjustments()
            values.crop = Crop(rect: CropRect(x: 0.1, y: 0.15, width: 0.6, height: 0.5), quarterTurns: 1)
            let sizes = try await Self.expectSizeBeforeRendering(url, stack: values.editStack, root: root, hash: contentHash)
            let catalog = try await Self.catalogSize(url)
            #expect(catalog != sizes.rendered, "the catalog's size would have been right here; the case tests nothing")
        }
    }

    @Test("A rotated JPEG and an untouched raw are sized as they render")
    func plainFiles() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let jpeg = root.appending(path: "turned.jpg")
            try SyntheticImages.writeJPEG(to: jpeg, width: 800, height: 600, seed: 5,
                                          exif: .init(dateTimeOriginal: "2024:01:01 00:00:00", orientation: 6))
            let sizes = try await Self.expectSizeBeforeRendering(jpeg, stack: .identity, root: root,
                                                                 hash: String(repeating: "ef", count: 32))
            #expect(sizes.rendered == CGSize(width: 600, height: 800))
            #expect(try await Self.catalogSize(jpeg) == sizes.rendered)

            let raw = root.appending(path: "plain.dng")
            try SyntheticDNG.write(to: raw, options: .init(width: 1200, height: 800, seed: 2))
            _ = try await Self.expectSizeBeforeRendering(raw, stack: .identity, root: root,
                                                         hash: String(repeating: "12", count: 32))
        }
    }

    /// A real camera raw (`CAMERA_RAW_SAMPLE`). The catalog's size comes from
    /// the importer's reader, ExifTool when it is installed, whose
    /// `ImageWidth` for a raw is its raw data's: a Sony ARW is 6048 x 4024
    /// there and renders at 6000 x 4000, an Olympus ORF 4640 x 3472 against
    /// 4608 x 3072. The size compared is the rendition's; the catalog's is
    /// printed.
    @Test("A real camera raw is sized as it renders",
          .enabled(if: ProcessInfo.processInfo.environment["CAMERA_RAW_SAMPLE"] != nil, "Set CAMERA_RAW_SAMPLE to run"))
    func cameraRaw() async throws {
        let url = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CAMERA_RAW_SAMPLE"]))
        try await RepositoryFiles.withTemporaryDirectory { root in
            let reader = MetadataReaders.makeDefault()
            let sizes = try await Self.expectSizeBeforeRendering(url, stack: .identity, root: root, hash: contentHash,
                                                                 reader: reader)
            let catalog = try await Self.catalogSize(url, reader: reader)
            print("\(url.lastPathComponent): catalog \(catalog), rendered \(sizes.rendered)")
        }
    }

    /// A held arrow key cancels each neighbor's prefetch: a cancelled caller
    /// gets nil and starts no read (code review C3). The read's first step
    /// loads the version's stack, so the loader's calls count the reads.
    @Test("A cancelled caller starts no size read")
    func cancelledCallerStartsNoRead() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "photo.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 1200, height: 800, seed: 4))
            let loads = Locked(0)
            let service = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "cache")),
                                         editStack: { _ in loads.withLock { $0 += 1 }; return .identity })
            let key = try #require(PreviewCacheKey(contentHash: contentHash, editStackHash: EditStack.identity.renderHash,
                                                   tier: .preview))
            let request = PreviewRequest(versionID: 1, key: key, sourceURL: url)

            let cancelled = await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await service.outputSize(for: request)
            }.value
            #expect(cancelled == nil)
            #expect(loads.withLock { $0 } == 0, "a cancelled caller started a size read")
            #expect(service.memoryCachedOutputSize(for: request) == nil)

            let size = await service.outputSize(for: request)
            #expect(size == CGSize(width: 1200, height: 800))
            #expect(loads.withLock { $0 } == 1)
        }
    }

    @Test("No size is promised where only a decode would tell")
    func noSizeForVideos() throws {
        let generator = PreviewGenerator()
        #expect(try generator.outputSize(source: URL(fileURLWithPath: "/nonexistent/clip.mov"), stack: .identity) == nil)
    }
}
