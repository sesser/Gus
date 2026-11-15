import CoreGraphics
import CoreImage
import Foundation
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

/// A linear DNG's decode is rendered whole before anything reads it, so a
/// render of one is the same every time (issue #181,
/// docs/features/hdr-dng-render-nondeterministic/status.md).
@Suite("Linear DNG decodes")
struct LinearRawDecodeTests {
    /// The decode as 32-bit float RGBA in the working space, row by row.
    static func pixels(_ image: CIImage, engine: RenderEngine) -> [Float] {
        let extent = image.extent
        let width = Int(extent.width), height = Int(extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            engine.withContext {
                $0.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: extent, format: .RGBAf,
                          colorSpace: RenderEngine.workingColorSpace)
            }
        }
        return pixels
    }

    @Test func linearDNGDecodeIsRenderedWhole() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "merge.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 640, height: 480, seed: 7, noise: 0.01,
                                                           scene: .testScene(.hazyLandscape), linearRaw: true))
            #expect(DNGLayout(contentsOf: url)?.hasLinearRaw == true)

            let decoded = try PreviewGenerator.decode(url, longEdge: nil, draft: false)
            #expect(decoded.decoder == .systemRAW && decoded.context.isRaw)
            // Backed by a bitmap already rendered: nothing downstream reads the decoder.
            let bitmap = try #require(decoded.image.cgImage, "the decode is still the decoder's lazy image")
            #expect((bitmap.width, bitmap.height) == (640, 480))
            #expect(decoded.image.extent == CGRect(x: 0, y: 0, width: 640, height: 480))
            #expect(decoded.context.scale == 1)

            // The same pixels as the decoder's own image, to the half floats
            // involved: the bitmap's rounding of the decode's last step, and
            // the half float that step may already have written its result in
            // (the decoder's kernels have `outputFormat=RGBAh` in
            // CI_PRINT_TREE), each at most 2⁻¹¹ of the value: 2⁻¹⁰ in all.
            // Measured: 0.000975. Values under 2⁻¹⁰ are judged against 2⁻¹⁰.
            let engine = RenderEngine(contextCount: 1)
            let raw = try #require(CIRAWFilter(imageURL: url))
            let lazy = try #require(RAWDecodeGraph.output(of: raw))
            let expected = Self.pixels(lazy, engine: engine)
            let actual = Self.pixels(decoded.image, engine: engine)
            #expect(actual.count == expected.count)
            var worst: Float = 0
            for (a, e) in zip(actual, expected) {
                worst = max(worst, abs(a - e) / max(abs(e), Float(1.0 / 1024)))
            }
            #expect(worst <= 1.0 / 1024, "largest relative difference \(worst)")
        }
    }

    /// Camera raws keep the decoder's lazy image: no render before the render.
    @Test func cameraRawDecodeStaysLazy() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "camera.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 640, height: 480, seed: 7))
            #expect(DNGLayout(contentsOf: url)?.hasLinearRaw == false)
            let decoded = try PreviewGenerator.decode(url, longEdge: nil, draft: false)
            #expect(decoded.decoder == .systemRAW)
            #expect(decoded.image.cgImage == nil)
        }
    }

    /// A reduced decode of a linear DNG is rendered whole too (linear DNGs
    /// with reduced copies decode at full size; one without them may not).
    @Test func reducedLinearDecodeIsRenderedWhole() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "merge.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 640, height: 480, seed: 7, linearRaw: true))
            let decoded = try PreviewGenerator.decode(url, longEdge: 200, draft: true)
            let bitmap = try #require(decoded.image.cgImage)
            #expect(CGFloat(bitmap.width) == decoded.image.extent.width)
            #expect(CGFloat(bitmap.height) == decoded.image.extent.height)
        }
    }

    @Test func emptyAndInfiniteImagesAreNotRendered() {
        #expect(LinearRawDecode.rendered(CIImage.empty()) == nil)
        #expect(LinearRawDecode.rendered(CIImage(color: .red)) == nil)
        let offset = CIImage(color: .red).cropped(to: CGRect(x: 10, y: 20, width: 30, height: 40))
        #expect(LinearRawDecode.rendered(offset)?.extent == CGRect(x: 10, y: 20, width: 30, height: 40))
    }
}

/// The file in issue #181, or another HDR merge: rendered many times, at
/// once on several engines (as previews and exports run), with sharpening at
/// Detail under 100, every render the same. Before the fix about one render
/// in four differed in a quarter of the frame.
///
/// `LINEAR_DNG_SAMPLE=path/to/merge-HDR.dng swift test --filter LinearDNGRenderSoakTests`
@Suite("Linear DNG rendered again and again",
       .enabled(if: ProcessInfo.processInfo.environment["LINEAR_DNG_SAMPLE"] != nil,
                "Set LINEAR_DNG_SAMPLE to a linear DNG, such as a Lightroom HDR merge"))
struct LinearDNGRenderSoakTests {
    static var sample: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["LINEAR_DNG_SAMPLE"] ?? "") }
    static let rounds = 4
    static let atOnce = 6

    /// The issue's stack: Tungsten 2850/0, +0.5 EV, Sharpening 60.
    static func stack() throws -> EditStack {
        try EditStack.identity.applying([
            "whiteBalance.preset=tungsten", "whiteBalance.temperature=2850", "whiteBalance.tint=0",
            "exposure.ev=0.5", "sharpen.amount=60",
        ].map { try AdjustmentEdit.parseSet($0) })
    }

    /// Renders `rounds` × `atOnce` times, each on an engine of its own, and
    /// counts the different results.
    static func distinct(_ render: @Sendable @escaping (PreviewGenerator) throws -> Data) throws -> [Data: Int] {
        let results = Mutex<[Data: Int]>([:])
        let failures = Mutex(0)
        for _ in 0..<rounds {
            DispatchQueue.concurrentPerform(iterations: atOnce) { _ in
                let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "linear-dng-soak"))
                guard let data = try? render(generator) else {
                    failures.withLock { $0 += 1 }
                    return
                }
                results.withLock { $0[data, default: 0] += 1 }
            }
        }
        #expect(failures.withLock { $0 } == 0)
        return results.withLock { $0 }
    }

    @Test func rendersAreTheSame() throws {
        #expect(DNGLayout(contentsOf: Self.sample)?.hasLinearRaw == true, "not a linear DNG")
        let stack = try Self.stack()
        let url = Self.sample
        let results = try Self.distinct { generator in
            let image = try generator.image(source: url, stack: stack, longEdge: 800)
            guard let rendered = generator.engine.makeCGImage(image, colorSpace: RenderEngine.outputColorSpace,
                                                              bitsPerComponent: 16),
                  let data = rendered.dataProvider?.data as Data?
            else { throw PreviewGenerator.Failure.renderFailed }
            return data
        }
        #expect(results.count == 1, "\(results.count) different renders: \(results.values.sorted())")
    }

    @Test func hdrRendersAreTheSame() throws {
        let stack = try Self.stack()
        let url = Self.sample
        let results = try Self.distinct { generator in
            guard let image = try generator.hdrImage(source: url, stack: stack, longEdge: 800),
                  let data = image.dataProvider?.data as Data?
            else { throw PreviewGenerator.Failure.renderFailed }
            return data
        }
        #expect(results.count == 1, "\(results.count) different HDR renders: \(results.values.sorted())")
    }
}
