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

    // MARK: Clarity

    /// Core Image's Gaussian, measured: a one-pixel impulse blurred with
    /// `sigma`, read back along its row (taps −reach … reach around it).
    static func measuredGaussian(sigma: Double, reach: Int) -> [Double] {
        let width = 2 * reach + 1
        var pixels = [Float](repeating: 0, count: width * 4)
        for x in 0..<width { pixels[x * 4 + 3] = 1 }
        pixels[reach * 4] = 1
        let impulse = LinearImage(width: width, height: 1, pixels: pixels).ciImage
        let blurred = impulse.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: impulse.extent)
        let row = renderLinear(blurred)
        return (0..<width).map { Double(row.pixels[$0 * 4]) }
    }

    /// Positive clarity is Core Image's unsharp mask; negative clarity (a
    /// blend toward the blur) is our own. Both are checked in the perceptual
    /// encoding against p + i · (p − G(p)).
    ///
    /// Tolerance, derived: Core Image's blur is not the reference's Gaussian.
    /// Its kernel is measured here (half-float weights, a slightly different
    /// reach, a sum just under one), and |G_CI(p) − G(p)| ≤ R · ‖k_CI − k‖₁
    /// per pass, where R is the largest encoded value; two passes double it,
    /// and the mask scales it by |i|. Half-float rounding adds at most 2⁻¹¹
    /// relative for each of the encoded input, the blur and the result
    /// (scaled by 1 + |i|, |i| and 1), so (2 + 2|i|) · 2⁻¹¹ · R. A further
    /// 2⁻¹¹ · R covers the encode and decode around the step.
    @Test("Clarity is an unsharp mask in the perceptual encoding",
          arguments: [(TestScene.hazyLandscape, 60.0), (.edgeTarget, 60.0)])
    func clarityMatchesReference(scene: TestScene, amount: Double) {
        let input = scene.image()
        var adjustments = Adjustments()
        adjustments.presence.clarity = amount
        let rendered = Self.renderLinear(AdjustmentRenderer().render(adjustments, to: input.ciImage,
                                                                     context: RenderContext()))
        let expected = ClarityReference.apply(input, amount: amount)

        let sigma = ClarityReference.sigma(width: input.width, height: input.height)
        let reach = Int((ClarityReference.reach * sigma).rounded(.up))
        let measured = Self.measuredGaussian(sigma: sigma, reach: reach)
        let reference = BlurReference.weights(sigma: sigma, reach: ClarityReference.reach)
        let kernelL1 = zip(measured, reference).map { abs($0 - $1) }.reduce(0, +)
        let range = expected.pixels.enumerated().filter { $0.offset % 4 != 3 }
            .map { abs(Double($0.element)) }.max() ?? 1
        let intensity = abs(amount / 100 * 0.6)
        let tolerance = range * (intensity * 2 * kernelL1 + (3 + 2 * intensity) * 0x1p-11)

        var worst = 0.0
        for i in rendered.pixels.indices where i % 4 != 3 {
            let actual = ColorMath.encode(Double(rendered.pixels[i]))
            worst = max(worst, abs(actual - Double(expected.pixels[i])))
        }
        #expect(worst <= tolerance, "largest difference \(worst), tolerance \(tolerance) (kernel L1 \(kernelL1))")
        // The step did something: more than twice what the comparison forgives.
        let change = zip(input.pixels, expected.pixels).enumerated().filter { $0.offset % 4 != 3 }
            .map { abs(ColorMath.encode(Double($0.element.0)) - Double($0.element.1)) }.max() ?? 0
        #expect(change > 2 * tolerance, "change \(change), tolerance \(tolerance)")
    }
}
