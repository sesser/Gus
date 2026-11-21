import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #228: whether a context can render Color Alignment from the input
/// area an earlier render with other values needed. A context reuses what
/// it prepared for a graph with the same digest, and an area callback is not
/// in the digest (the fault `RAWDecodeGraph` and the distortion warp work
/// around). `lensAlign`'s callback reads only the input's extent and the
/// red and blue values, which the kernel also takes as arguments, so each
/// pair of values has a digest of its own. These tests pin that.
@Suite("Color alignment's input area", .serialized)
struct LensAlignStaleAreaTests {
    static let width = 2000, height = 1400

    /// A tile near the top right corner, about 1100 pixels from the center:
    /// ±50 moves red and blue by about 5.5 pixels there, past the callback's
    /// 2 pixel margin for values near 0.
    static let tile = CGRect(x: width - 96, y: height - 96, width: 64, height: 64)

    /// Scene pixels through a blur: an intermediate Core Image renders only
    /// for the area asked of it, so a render that reads beyond that area
    /// shows it (a bitmap's pixels are all there whatever is asked).
    static let input: CIImage = {
        let image = TestScene.pixelGrid.image(width: width, height: height).ciImage
        return image.applyingGaussianBlur(sigma: 1).cropped(to: image.extent)
    }()

    /// A drag of both sliders out to their ends and back, as a live edit renders it.
    static let drag: [(red: Double, blue: Double)] = [(1, -1), (8, -6), (20, -15), (35, -30), (50, -50), (-50, 50), (12, 3)]

    static func render(_ image: CIImage, _ engine: RenderEngine, bounds: CGRect) -> [Float] {
        let width = Int(bounds.width), height = Int(bounds.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            engine.withContext {
                $0.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: bounds,
                          format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
            }
        }
        return pixels
    }

    static func fresh() -> RenderEngine { RenderEngine(contextCount: 1, name: "align-fresh") }

    /// Runs `body` with a JPEG written for it, and removes the file after
    /// `body` returns or throws (the decoder reads it lazily, during renders).
    static func withJPEG<T>(_ body: (URL) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "align-stale-area-\(UUID().uuidString).jpg", directoryHint: .notDirectory)
        try SyntheticImages.writeJPEG(to: url, width: width, height: height, seed: 228)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }

    /// The tile's pixels depend on the area the kernel asks for: with an area
    /// that ignores the values (the identity's), the corner comes out wrong for
    /// the blurred scene, whose blur is rendered only for the area asked of it.
    /// Without this, the tests below could pass on an input that hides a stale area.
    ///
    /// A JPEG as the pipeline decodes it at full size no longer shows one: the
    /// decode is a GPU copy with every pixel there, as a bitmap's
    /// (`ResidentDecode`; docs/features/hdr-merge/status.md, "Bug: tiles at
    /// 100%"), so no area a kernel asks of it can be stale. That is pinned
    /// here: if the decode were read lazily again, the JPEG case would show an
    /// area again and `jpegDragInOneContext` would again guard it.
    @Test("The tile shows an input area too small for the values", arguments: [false, true])
    func tileSeesTheInputArea(jpeg: Bool) throws {
        if jpeg {
            try Self.withJPEG { url in
                try Self.expectTileSeesInputArea(PreviewGenerator(engine: Self.fresh()).image(source: url, stack: .identity,
                                                                                               longEdge: nil),
                                                 sees: false)
            }
        } else {
            try Self.expectTileSeesInputArea(Self.input, sees: true)
        }
    }

    static func expectTileSeesInputArea(_ input: CIImage, sees: Bool) throws {
        let kernel = try LensKernels.kernel("lensAlign")
        let extent = input.extent
        let center = CIVector(x: extent.midX, y: extent.midY)
        let alignment = ColorAlignment(red: 50, blue: -50)
        let tooSmall = try #require(kernel.apply(extent: extent, roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
                                                 arguments: [input.clampedToExtent(), center,
                                                             Float(alignment.redScale), Float(alignment.blueScale)]))
        let tile = Self.tile.offsetBy(dx: extent.minX, dy: extent.minY)
        let right = Self.render(AdjustmentRenderer.align(input, alignment), Self.fresh(), bounds: tile)
        let wrong = Self.render(tooSmall.cropped(to: extent), Self.fresh(), bounds: tile)
        #expect((right != wrong) == sees)
    }

    @Test("One context renders every value of a drag as a fresh context does")
    func dragInOneContext() {
        let shared = RenderEngine(contextCount: 1, name: "align-shared")
        for values in Self.drag {
            let image = AdjustmentRenderer.align(Self.input, ColorAlignment(red: values.red, blue: values.blue))
            let rendered = Self.render(image, shared, bounds: Self.tile)
            let expected = Self.render(image, Self.fresh(), bounds: Self.tile)
            let differing = zip(rendered, expected).filter { $0 != $1 }.count
            #expect(differing == 0, "\(values): \(differing) components differ from a fresh context's render")
        }
    }

    /// The issue's case: a live drag on a JPEG, at full size, through the
    /// whole pipeline, rendering the visible area as the loupe does at 100%.
    @Test("A JPEG's drag through the whole pipeline renders as a fresh context does")
    func jpegDragInOneContext() throws {
        let shared = RenderEngine(contextCount: 1, name: "align-shared")
        let generator = PreviewGenerator(engine: shared)
        try Self.withJPEG { url in
            for values in Self.drag {
                var adjustments = Adjustments()
                adjustments.colorAlignment = ColorAlignment(red: values.red, blue: values.blue)
                let image = try generator.image(source: url, stack: adjustments.editStack, longEdge: nil)
                let tile = Self.tile.offsetBy(dx: image.extent.minX, dy: image.extent.minY)
                let rendered = Self.render(image, shared, bounds: tile)
                let expected = Self.render(image, Self.fresh(), bounds: tile)
                let differing = zip(rendered, expected).filter { $0 != $1 }.count
                #expect(differing == 0, "\(values): \(differing) components differ from a fresh context's render")
            }
        }
    }
}
