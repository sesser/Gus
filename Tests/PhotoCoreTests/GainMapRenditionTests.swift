import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #277: a gain-map HEIC looked about a stop brighter in the loupe
/// than in Quick Look, and a slider edit seemed to snap back on release.
///
/// The cause (status.md, Bug): on a display with extended dynamic range the
/// loupe showed `hdrImage`, the gain map's HDR rendition, which for an
/// iPhone-style gain map is brighter than the SDR rendition below SDR white
/// too, while live frames, previews, exports and stacks
/// `preservesExtendedRange` turns away are the SDR one. Ruled (RI-1, option
/// A): a gain map alone is not HDR content, so the loupe shows the SDR
/// rendition throughout. HLG and PQ files keep their HDR rendition.
@Suite("Gain-map renditions (issue #277)")
struct GainMapRenditionTests {
    /// Luminance statistics in linear Display P3 relative to SDR white, of
    /// an 800-pixel reduction.
    struct Light {
        var mean: Float
        var median: Float
        var p90: Float

        init(_ image: CGImage) {
            let scale = 800 / Double(max(image.width, image.height))
            let reduced = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: min(scale, 1), y: min(scale, 1)))
            let bounds = reduced.extent.integral
            let width = Int(bounds.width), height = Int(bounds.height)
            var pixels = [Float](repeating: 0, count: width * height * 4)
            let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
            CIContext(options: [.workingFormat: CIFormat.RGBAf])
                .render(reduced, toBitmap: &pixels, rowBytes: width * 16, bounds: bounds, format: .RGBAf, colorSpace: space)
            var luminance = [Float](repeating: 0, count: width * height)
            for index in luminance.indices {
                let red: Float = 0.2290 * pixels[index * 4]
                let green: Float = 0.6917 * pixels[index * 4 + 1]
                let blue: Float = 0.0793 * pixels[index * 4 + 2]
                luminance[index] = red + green + blue
            }
            mean = luminance.reduce(0, +) / Float(luminance.count)
            luminance.sort()
            median = luminance[luminance.count / 2]
            p90 = luminance[luminance.count * 9 / 10]
        }

        /// Stops brighter than `other`, by the mean.
        func stops(over other: Light) -> Float { log2(mean / other.mean) }
    }

    static func exposure(_ ev: Double) -> EditStack {
        EditStack(operations: [EditOperation(kind: "exposure", parameters: ["ev": .number(ev)])])
    }

    static let contrast = EditStack(operations: [EditOperation(kind: "tone", parameters: ["contrast": .number(20)])])

    /// One stop of gain: the HDR picture is twice the SDR one's light everywhere.
    static let gain = 2.0

    static func hasGainMap(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return [kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeHDRGainMap].contains {
            CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil
        }
    }

    @Test("A gain map alone gets no HDR rendition: the loupe shows the system's SDR rendition",
          arguments: [HDRTestImages.Container.heic, .jpeg])
    func gainMapStaysSDR(container: HDRTestImages.Container) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: container == .heic ? "lifted.heic" : "lifted.jpg")
            try HDRTestImages.writeGainMap(to: url, width: 800, height: 600, seed: 277, gain: Self.gain, container: container)
            #expect(Self.hasGainMap(url))
            let generator = PreviewGenerator()
            // Before the fix: a rendition a stop brighter, mid-tones included.
            #expect(try generator.hdrImage(source: url, stack: .identity, longEdge: 800) == nil)
            #expect(try generator.hdrImage(source: url, stack: .identity, longEdge: nil) == nil)

            // What the loupe shows instead is the system's own SDR decode.
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let system = Light(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
            let sdr = Light(try generator.cgImage(source: url, stack: .identity, longEdge: 800))
            #expect(abs(sdr.stops(over: system)) < 0.05)
        }
    }

    @Test("A slider's release lands on the rendition its live frames showed")
    func editsStayOnOneRendition() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "lifted.heic")
            try HDRTestImages.writeGainMap(to: url, width: 800, height: 600, seed: 278, gain: Self.gain)
            let generator = PreviewGenerator()
            // Before the fix, Exposure kept the HDR rendition, a stop brighter
            // than the SDR live frames of the same value, and Contrast dropped
            // to SDR: the loupe jumped on release either way. Now every stack
            // settles on the SDR rendition, the one live frames render.
            for stack in [EditStack.identity, Self.exposure(-0.5), Self.exposure(1), Self.contrast] {
                #expect(try generator.hdrImage(source: url, stack: stack, longEdge: 800) == nil)
            }
        }
    }

    @Test("An HLG or PQ HEIC keeps its HDR rendition, with or without a gain map",
          arguments: [HDRTestImages.Transfer.pq, .hlg], [false, true])
    func hdrEncodingStaysHDR(transfer: HDRTestImages.Transfer, gainMap: Bool) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "encoded.heic")
            try HDRTestImages.writeHDREncoded(to: url, width: 800, height: 600, seed: 279, gain: Self.gain,
                                              transfer: transfer, gainMap: gainMap)
            // The encoder may leave the gain map out; then the case would
            // test a plain PQ or HLG file under the wrong name.
            #expect(Self.hasGainMap(url) == gainMap)
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            #expect(PreviewGenerator.hasHDREncoding(source))
            let image = try #require(try PreviewGenerator().hdrImage(source: url, stack: .identity, longEdge: 800))
            #expect(image.contentHeadroom >= RenderEngine.minimumHDRHeadroom)
        }
    }

    /// The owner's file (never committed): `HEIC_GAINMAP_SAMPLE=path/to/IMG.HEIC`.
    /// It gets no HDR rendition, and its unedited SDR render matches the
    /// system's SDR decode within 0.05 stops; prints the SDR measurements
    /// status.md records.
    @Test("A real gain-map HEIC gets no HDR rendition",
          .enabled(if: ProcessInfo.processInfo.environment["HEIC_GAINMAP_SAMPLE"] != nil))
    func sampleStaysSDR() throws {
        let url = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HEIC_GAINMAP_SAMPLE"]))
        #expect(Self.hasGainMap(url))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let generator = PreviewGenerator()
        let system = Light(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
        for (name, stack) in [("identity", EditStack.identity), ("exposure -1", Self.exposure(-1)),
                              ("contrast +20", Self.contrast)] {
            #expect(try generator.hdrImage(source: url, stack: stack, longEdge: 2560) == nil)
            let sdr = Light(try generator.cgImage(source: url, stack: stack, longEdge: 2560))
            print(String(format: "sample: %@ SDR mean %.3f median %.3f p90 %.3f (%+.2f stops over the system's SDR)",
                         name, sdr.mean, sdr.median, sdr.p90, sdr.stops(over: system)))
            if name == "identity" {
                #expect(abs(sdr.stops(over: system)) < 0.05)
            }
        }
    }
}
