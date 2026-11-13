import CoreImage
import Foundation
import Testing
@testable import PhotoCore

/// The fallback on a real file: a raw the system's RAW decoder gives no image
/// for is decoded by LibRaw (issue #161).
/// `RAF_SAMPLE=path/to/DSCF5123.RAF swift test --filter LibRawFallbackTests`
/// with a Fujifilm X-E3 file on macOS 27.2.1. `LibRawDecoderTests` and
/// `LibRawFallbackPipelineTests` cover the same code on synthetic files in
/// every run; this suite checks a camera's own file (its compressed loader,
/// its inset crop, its size and speed).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RAF_SAMPLE"] != nil,
                "Set RAF_SAMPLE to a raw the system decoder cannot read and run this suite alone"))
struct LibRawFallbackTests {
    private var url: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAF_SAMPLE"] ?? "") }

    @Test func theSystemDecoderGivesNoImage() {
        // The premise: with an image from the system decoder, nothing below goes through LibRaw.
        #expect(!SystemRAWDecoder.reads(url), "the system RAW decoder reads this file: pick another sample")
        #expect(RawDefaults(source: url) == nil)
    }

    @Test func decodesAtFullAndSmallSizes() throws {
        let full = try PreviewGenerator.decode(url, longEdge: nil, draft: false)
        let fullEdge = max(full.image.extent.width, full.image.extent.height)
        // Whichever way the camera was held.
        #expect(fullEdge > 4000)
        #expect(!full.context.isRaw)
        #expect(full.context.scale == 1)
        let size = try #require(PreviewGenerator.nativeSize(url))
        #expect(size == full.image.extent.size)
        let small = try PreviewGenerator.decode(url, longEdge: 800, draft: false)
        #expect(max(small.image.extent.width, small.image.extent.height) < fullEdge)
        #expect(small.context.scale <= 0.5)
    }

    @Test func rendersThroughThePipeline() throws {
        let image = try PreviewGenerator().cgImage(source: url, stack: .identity, longEdge: 1000)
        #expect(max(image.width, image.height) == 1000)
    }

    /// Code review C4: 900 x 600 before, from a half-size decode chosen for the uncropped target.
    @Test func aCropDecodesLargeEnough() throws {
        var cropped = Adjustments()
        cropped.crop = Crop(rect: CropRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3))
        let size = try #require(PreviewGenerator.nativeSize(url))
        let image = try PreviewGenerator().image(source: url, stack: cropped.editStack, longEdge: 2560)
        // Three tenths of the frame, which is under the 2560 asked for: every pixel the file holds there.
        let expected = (max(size.width, size.height) * 0.3).rounded()
        #expect(abs(max(image.extent.width, image.extent.height) - expected) <= 1)
    }

    /// The owner's ruling (code review Q3): the photo can be adjusted after decoding.
    @Test func adjustmentsChangeTheRender() throws {
        let generator = PreviewGenerator()
        func render(_ edit: (inout Adjustments) -> Void) throws -> Data {
            var values = Adjustments()
            edit(&values)
            let image = try generator.cgImage(source: url, stack: values.editStack, longEdge: 400)
            return try #require(image.dataProvider?.data as Data?)
        }
        let plain = try render { _ in }
        #expect(try render { $0.whiteBalance = WhiteBalance(preset: .custom, relativeTemperature: 60, relativeTint: 30) } != plain)
        #expect(try render { $0.exposure.ev = 1 } != plain)
        #expect(try render { $0.tone.highlights = -80 } != plain)
        #expect(try render { $0.noiseReduction.luminance = 80 } != plain)
        let balance = try AutoAdjuster(generator: generator).whiteBalance(source: url, adjustments: .none)
        #expect(balance.preset == .auto)
        #expect(balance.temperature == nil)
    }
}
