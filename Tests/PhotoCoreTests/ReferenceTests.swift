import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The renderer against plain Swift implementations of the same math
/// (`Tests/PhotoCoreTests/Reference`), in the same working space. Where a
/// golden only pins today's output, these say whether it is right.
@Suite("CPU references")
struct ReferenceTests {
    static let engine = RenderEngine(contextCount: 1, name: "reference")

    /// Renders `image` (extent at the origin) as float RGBA in the working space.
    static func renderLinear(_ image: CIImage) -> LinearImage {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            engine.withContext {
                $0.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: image.extent,
                          format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
            }
        }
        return LinearImage(width: width, height: height, pixels: pixels)
    }

    /// The working format is half float (`CIFormat.RGBAh`): an 11-bit
    /// significand, so each rounding is off by at most 2⁻¹¹ relative. The
    /// input is rounded once into the working format and the result once
    /// more, so twice that bounds the error, plus the spacing of the
    /// smallest half-float values (2⁻²⁴) near zero.
    static func withinHalfFloat(_ actual: Float, _ expected: Float) -> Bool {
        abs(actual - expected) <= abs(expected) * 0x1p-10 + 0x1p-24
    }

    @Test("Exposure is input × 2^EV in linear Rec. 2020",
          arguments: [(TestScene.grayRamp, -1.0), (.grayRamp, 1.5), (.hueRamp, 1.0), (.hueRamp, -2.5),
                      (.patchChart, 0.5)])
    func exposureMatchesReference(scene: TestScene, ev: Double) {
        let input = scene.image()
        var adjustments = Adjustments()
        adjustments.exposure.ev = ev
        let rendered = Self.renderLinear(AdjustmentRenderer().render(adjustments, to: input.ciImage,
                                                                     context: RenderContext()))
        let expected = ExposureReference.apply(input, ev: ev)
        var worst: (index: Int, error: Float) = (0, 0)
        var failures = 0
        for i in rendered.pixels.indices where !Self.withinHalfFloat(rendered.pixels[i], expected.pixels[i]) {
            failures += 1
            let error = abs(rendered.pixels[i] - expected.pixels[i])
            if error > worst.error { worst = (i, error) }
        }
        #expect(failures == 0, """
            \(failures) components off by more than two half-float roundings; worst at component \(worst.index): \
            \(rendered.pixels[worst.index]) instead of \(expected.pixels[worst.index])
            """)
    }

    /// Output is the working space's linear Rec. 2020 converted by a matrix to
    /// Display P3 primaries and encoded with the sRGB curve. 16-bit output
    /// adds a step of 1/65535; half-float input adds at most 2⁻¹¹ relative in
    /// linear light, which the curve (slope ≤ 1/2.4 of the value, relative)
    /// shrinks. 0.001 covers both several times over and is a quarter of an
    /// 8-bit step.
    @Test("Output is a matrix to Display P3 primaries, then the sRGB curve",
          arguments: [TestScene.grayRamp, .patchChart, .hueRamp])
    func outputChainMatchesReference(scene: TestScene) throws {
        let input = scene.image()
        let cgImage = try #require(Self.engine.makeCGImage(input.ciImage, colorSpace: RenderEngine.outputColorSpace,
                                                           bitsPerComponent: 16))
        #expect(cgImage.colorSpace?.name == CGColorSpace.displayP3)
        let data = try #require(cgImage.dataProvider?.data as Data?)
        let littleEndian = cgImage.byteOrderInfo == .order16Little
        var worst = 0.0
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: UInt16.self)
            let rowSamples = cgImage.bytesPerRow / 2
            for y in 0..<input.height {
                for x in 0..<input.width {
                    let pixel = input[x, y]
                    let expected = OutputReference.displayP3(linearRec2020: SIMD3(Double(pixel.x), Double(pixel.y),
                                                                                  Double(pixel.z)))
                    for c in 0..<3 {
                        // 16-bit integer output clips to 0 … 1.
                        let clipped = min(max(expected[c], 0), 1)
                        let sample = samples[y * rowSamples + x * 4 + c]
                        let actual = Double(littleEndian ? UInt16(littleEndian: sample) : UInt16(bigEndian: sample)) / 65535
                        worst = max(worst, abs(actual - clipped))
                    }
                }
            }
        }
        #expect(worst <= 0.001, "largest difference \(worst)")
    }

    /// The perceptual encoding used for clarity, sharpening and grain is Core
    /// Image's sRGB tone curve applied to Rec. 2020 values: exactly the sRGB
    /// curve, both ways, within half-float rounding of the encoded value.
    @Test("Core Image's sRGB tone curve is the sRGB transfer function")
    func perceptualEncodingMatchesReference() {
        let input = TestScene.grayRamp.image()
        let encode = CIFilter(name: "CILinearToSRGBToneCurve", parameters: [kCIInputImageKey: input.ciImage])!
        let encoded = Self.renderLinear(encode.outputImage!)
        var worst: Float = 0
        for i in stride(from: 0, to: input.pixels.count, by: 4) {
            let expected = Float(ColorMath.encode(Double(input.pixels[i])))
            if !Self.withinHalfFloat(encoded.pixels[i], expected) {
                worst = max(worst, abs(encoded.pixels[i] - expected))
            }
        }
        #expect(worst == 0, "largest error beyond half-float rounding: \(worst)")
    }
}
