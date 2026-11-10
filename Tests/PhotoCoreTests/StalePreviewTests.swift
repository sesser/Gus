import CoreGraphics
import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// A rendition is cached only under the render hash of the stack it was
/// rendered from (stale-preview-after-save). The catalog read that gives the
/// stack can lag the hash the app shows: here the loader still returns the
/// stack saved before the edit while the request's key names the edit.
@Suite("Previews of a stack not saved yet")
struct StalePreviewTests {
    private let contentHash = String(repeating: "ab", count: 32)

    private static func edited(ev: Double) -> EditStack {
        var values = Adjustments()
        values.exposure.ev = ev
        return values.editStack
    }

    /// Mean 8-bit level of `image` drawn small into sRGB.
    private static func meanLevel(_ image: CGImage) throws -> Double {
        let side = 16
        let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let data = try #require(context.data)
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var sum = 0
        for pixel in 0..<(side * side) {
            sum += Int(bytes[pixel * 4]) + Int(bytes[pixel * 4 + 1]) + Int(bytes[pixel * 4 + 2])
        }
        return Double(sum) / Double(side * side * 3)
    }

    @Test("The disk tiers and the 1:1 render are not cached under a hash the loaded stack does not have")
    func sdrRenditionsWaitForTheSavedStack() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let source = root.appending(path: "a.jpg")
            try SyntheticImages.writeJPEG(to: source, width: 800, height: 600, seed: 3,
                                          exif: .init(dateTimeOriginal: "2024:01:01 00:00:00", orientation: 1))
            let edit = Self.edited(ev: 1.5)
            let saved = Locked(EditStack.identity)
            let service = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "cache")),
                                         editStack: { _ in saved.withLock { $0 } })
            let key = try #require(PreviewCacheKey(contentHash: contentHash, editStackHash: edit.renderHash, tier: .preview))
            let thumbnailKey = try #require(PreviewCacheKey(contentHash: contentHash, editStackHash: edit.renderHash,
                                                            tier: .thumbnail))
            let request = PreviewRequest(versionID: 1, key: key, sourceURL: source)
            let thumbnailRequest = PreviewRequest(versionID: 1, key: thumbnailKey, sourceURL: source)

            // The edit's hash is shown before its write lands.
            await #expect(throws: PreviewService.Failure.staleEditStack) {
                try await service.prepare(request, priority: .visible)
            }
            await #expect(throws: PreviewService.Failure.staleEditStack) {
                _ = try await service.image(for: thumbnailRequest, priority: .visible)
            }
            await #expect(throws: PreviewService.Failure.staleEditStack) {
                _ = try await service.fullResolutionImage(for: request)
            }
            #expect(!service.cache.contains(key))
            #expect(!service.cache.contains(thumbnailKey))
            #expect(service.memoryCachedImage(for: request) == nil)
            #expect(service.memoryCachedImage(for: thumbnailRequest) == nil)

            // Once it has landed, the same requests render the edit.
            saved.withLock { $0 = edit }
            let original = try Self.meanLevel(service.generator.cgImage(source: source, stack: .identity, longEdge: 512))
            let thumbnail = try await service.image(for: thumbnailRequest, priority: .visible)
            let preview = try await service.image(for: request, priority: .visible)
            let full = try await service.fullResolutionImage(for: request)
            for image in [thumbnail, preview, full] {
                #expect(try Self.meanLevel(image) > original + 20)
            }
            #expect(service.cache.contains(key) && service.cache.contains(thumbnailKey))
        }
    }

    @Test("The HDR rendition is not kept under a hash the loaded stack does not have")
    func hdrRenditionsWaitForTheSavedStack() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let service = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "cache")),
                                         editStack: { _ in .identity })
            // A JPEG with a gain map: its HDR rendition has a patch at four times SDR white.
            let plain = root.appending(path: "plain.jpg")
            try SyntheticImages.writeJPEG(to: plain, width: 800, height: 600, seed: 4,
                                          exif: .init(dateTimeOriginal: "2024:01:01 00:00:00", orientation: 1))
            let sdr = try #require(CIImage(contentsOf: plain))
            let patch = CIImage(color: CIColor(red: 4, green: 4, blue: 4, colorSpace: RenderEngine.hdrColorSpace)!)
                .cropped(to: CGRect(x: 100, y: 100, width: 200, height: 150))
            let data = try #require(service.generator.engine.withContext {
                $0.jpegRepresentation(of: sdr, colorSpace: RenderEngine.outputColorSpace,
                                      options: [.hdrImage: patch.composited(over: sdr)])
            })
            let source = root.appending(path: "gain-map.jpg")
            try data.write(to: source)

            let edit = Self.edited(ev: -2)
            let saved = Locked(EditStack.identity)
            let lagging = PreviewService(cache: PreviewDiskCache(root: root.appending(path: "cache")),
                                         editStack: { _ in saved.withLock { $0 } })
            let key = try #require(PreviewCacheKey(contentHash: contentHash, editStackHash: edit.renderHash, tier: .preview))
            let request = PreviewRequest(versionID: 1, key: key, sourceURL: source)

            await #expect(throws: PreviewService.Failure.staleEditStack) {
                _ = try await lagging.hdrImage(for: request)
            }
            await #expect(throws: PreviewService.Failure.staleEditStack) {
                _ = try await lagging.hdrImage(for: request, fullResolution: true)
            }
            #expect(lagging.memoryCachedHDRImage(for: request) == nil)

            saved.withLock { $0 = edit }
            let original = try #require(try service.generator.hdrImage(source: source, stack: .identity, longEdge: 512))
            let fitted = try #require(try await lagging.hdrImage(for: request))
            let full = try #require(try await lagging.hdrImage(for: request, fullResolution: true))
            for image in [fitted, full] {
                #expect(try Self.meanLevel(image) < Self.meanLevel(original) - 20)
            }
        }
    }

    @Test("A catalog-backed service renders an edit once its write lands, and the original again after an undo")
    func catalogWritesDecideWhatRenders() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "Shoot")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let source = folder.appending(path: "IMG_0003.jpg")
            try SyntheticImages.writeJPEG(to: source, width: 800, height: 600, seed: 5,
                                          exif: .init(dateTimeOriginal: "2024:05:01 10:00:00", orientation: 1))
            let catalog = try Catalog.makeInMemory()
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(folder)
            let unedited = try #require(try await catalog.libraryItems(matching: LibraryFilter()).first)
            #expect(unedited.editStackHash == EditStack.identity.renderHash)
            let previews = PreviewService(cacheDirectory: root.appending(path: "cache"), catalog: catalog)
            func request(_ hash: String, tier: PreviewTier = .thumbnail) throws -> PreviewRequest {
                let key = try #require(PreviewCacheKey(contentHash: unedited.contentHash, editStackHash: hash, tier: tier))
                return PreviewRequest(versionID: unedited.versionID, key: key, sourceURL: source)
            }
            let original = try Self.meanLevel(try await previews.image(for: try request(unedited.editStackHash)))

            // The app knows the edit's hash before the catalog has it.
            let edit = Self.edited(ev: 1.5)
            await #expect(throws: PreviewService.Failure.staleEditStack) {
                _ = try await previews.image(for: try request(edit.renderHash))
            }
            try await catalog.setEditStack(edit, forVersion: unedited.versionID, historyLabel: "Test")
            let edited = try #require(try await catalog.libraryItems(matching: LibraryFilter()).first)
            #expect(edited.editStackHash == edit.renderHash)
            let editedLevel = try Self.meanLevel(try await previews.image(for: try request(edited.editStackHash)))
            #expect(editedLevel > original + 20)

            // Undo back to no edits, with the identity hash known before its write
            // lands. The loupe tier of the identity hash is not cached yet, so it
            // has to render: from the edit, which must not be kept under that hash.
            let undoneRequest = try request(EditStack.identity.renderHash, tier: .preview)
            #expect(!previews.cache.contains(undoneRequest.key))
            await #expect(throws: PreviewService.Failure.staleEditStack) {
                _ = try await previews.image(for: undoneRequest)
            }
            #expect(!previews.cache.contains(undoneRequest.key))
            try await catalog.setEditStack(.identity, forVersion: unedited.versionID, historyLabel: "Test")
            let undone = try Self.meanLevel(try await previews.image(for: undoneRequest))
            #expect(abs(undone - original) < 3)
            #expect(undone < editedLevel - 20)
        }
    }
}
