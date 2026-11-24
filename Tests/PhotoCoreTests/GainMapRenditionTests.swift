import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #277: a gain-map HEIC looks a stop brighter in the loupe than in
/// Quick Look, and a slider edit seems to snap back on release.
///
/// These tests record the cause as the code behaves today (status.md, Bug):
/// on a display with extended dynamic range the loupe shows `hdrImage`, the
/// gain map's HDR rendition, which for an iPhone-style gain map is brighter
/// than the SDR rendition below SDR white too, while live frames, previews,
/// exports and stacks `preservesExtendedRange` turns away are the SDR one.
/// The fix waits on the ruling in status.md (RI-1); these expectations
/// change with it.
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
            var luminance = (0..<(width * height)).map {
                0.2290 * pixels[$0 * 4] + 0.6917 * pixels[$0 * 4 + 1] + 0.0793 * pixels[$0 * 4 + 2]
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

    /// One stop of gain: the HDR rendition is twice the SDR one's light everywhere.
    static let gain = 2.0

    @Test("A gain map that lifts the whole picture makes the loupe's HDR rendition brighter below white too",
          arguments: [GainMapImages.Container.heic, .jpeg])
    func hdrRenditionIsBrighterBelowWhite(container: GainMapImages.Container) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: container == .heic ? "lifted.heic" : "lifted.jpg")
            try GainMapImages.write(to: url, width: 800, height: 600, seed: 277, gain: Self.gain, container: container)
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            #expect([kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeHDRGainMap].contains {
                CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil
            })

            let generator = PreviewGenerator()
            // The SDR rendition is the system's own SDR decode (what previews,
            // exports, live frames and an unfocused Quick Look show).
            let system = Light(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
            let sdr = Light(try generator.cgImage(source: url, stack: .identity, longEdge: 800))
            #expect(abs(sdr.stops(over: system)) < 0.05)

            // The loupe's HDR rendition: about a stop brighter, mid-tones included.
            let hdr = Light(try #require(try generator.hdrImage(source: url, stack: .identity, longEdge: 800)))
            #expect(hdr.stops(over: sdr) > 0.8)
            #expect(hdr.median > sdr.median * 1.7)
        }
    }

    @Test("The rendition after a slider's release is not the one its live frames showed")
    func editsSwitchBetweenRenditions() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "lifted.heic")
            try GainMapImages.write(to: url, width: 800, height: 600, seed: 278, gain: Self.gain)
            let generator = PreviewGenerator()
            // Exposure keeps the HDR rendition (while something stays above
            // white): after release the loupe shows it, a stop brighter than
            // the SDR live frames of the same value.
            let live = Light(try generator.cgImage(source: url, stack: Self.exposure(-0.5), longEdge: 800))
            let settled = Light(try #require(try generator.hdrImage(source: url, stack: Self.exposure(-0.5), longEdge: 800)))
            #expect(settled.stops(over: live) > 0.8)
            // Contrast turns it away: the loupe drops to the SDR rendition, a
            // stop darker than the unedited photo it showed before.
            #expect(try generator.hdrImage(source: url, stack: Self.contrast, longEdge: 800) == nil)
        }
    }

    /// The owner's file (never committed): `HEIC_GAINMAP_SAMPLE=path/to/IMG.HEIC`.
    /// Prints what status.md records; checks only that the file has a gain
    /// map and both renditions render.
    @Test("A real gain-map HEIC's renditions, measured",
          .enabled(if: ProcessInfo.processInfo.environment["HEIC_GAINMAP_SAMPLE"] != nil))
    func sampleRenditions() throws {
        let url = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HEIC_GAINMAP_SAMPLE"]))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let kinds = [("ISO", kCGImageAuxiliaryDataTypeISOGainMap), ("Apple", kCGImageAuxiliaryDataTypeHDRGainMap)]
            .filter { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0.1) != nil }.map(\.0)
        #expect(!kinds.isEmpty)
        print("sample: gain maps \(kinds.joined(separator: ", "))")
        let generator = PreviewGenerator()
        let system = Light(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
        for (name, stack) in [("identity", EditStack.identity), ("exposure -1", Self.exposure(-1)),
                              ("contrast +20", Self.contrast)] {
            let sdr = Light(try generator.cgImage(source: url, stack: stack, longEdge: 2560))
            let hdrImage = try generator.hdrImage(source: url, stack: stack, longEdge: 2560)
            let line = String(format: "sample: %@ SDR mean %.3f median %.3f p90 %.3f (%+.2f stops over the system's SDR)",
                              name, sdr.mean, sdr.median, sdr.p90, sdr.stops(over: system))
            if let hdrImage {
                let hdr = Light(hdrImage)
                print(line + String(format: "; HDR mean %.3f median %.3f p90 %.3f headroom %.2f (%+.2f stops over SDR)",
                                    hdr.mean, hdr.median, hdr.p90, hdrImage.contentHeadroom, hdr.stops(over: sdr)))
            } else {
                print(line + "; no HDR rendition")
            }
        }
    }
}
