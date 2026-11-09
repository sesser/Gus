import CoreImage
import Foundation
import Metal
import Synchronization
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The Lens heading's rendering (docs/features/chromatic-aberration): color
/// fringes and color alignment against their CPU references
/// (`LensReference`) and the PRD's acceptance criteria on scenes (a)–(c).
@Suite("Lens rendering", .serialized)
struct LensRenderingTests {
    static func render(_ values: Adjustments, _ image: LinearImage, scale: Double = 1) -> LinearImage {
        ReferenceTests.renderLinear(AdjustmentRenderer().render(values, to: image.ciImage,
                                                                context: RenderContext(scale: scale)))
    }

    static func listed(_ purple: Bool = true, _ green: Bool = true) -> Adjustments {
        var values = Adjustments()
        if purple { values.colorFringes.slot1 = CommonFringeColor.purple.slot }
        if green { values.colorFringes.slot2 = CommonFringeColor.green.slot }
        return values
    }

    static func rgb(_ image: LinearImage, _ x: Int, _ y: Int) -> SIMD3<Float> {
        let p = image[x, y]
        return SIMD3(p.x, p.y, p.z)
    }

    static func okLab(_ rgb: SIMD3<Float>) -> SIMD3<Double> {
        FringeColorMath.okLab(linearRec2020: SIMD3(Double(rgb.x), Double(rgb.y), Double(rgb.z)))
    }

    static func chroma(_ rgb: SIMD3<Float>) -> Double {
        let lab = okLab(rgb)
        return (lab.y * lab.y + lab.z * lab.z).squareRoot()
    }

    static func luminance(_ rgb: SIMD3<Float>) -> Float { (rgb * LensReference.lumaWeights).sum() }

    /// Two half-float roundings of a value of `magnitude`, and the smallest steps near zero.
    static func halfFloat(_ magnitude: Float) -> Float { abs(magnitude) * 0x1p-10 + 0x1p-24 }

    /// After graying, a pixel's color is its luminance times (1 − w) of its
    /// own chroma; rounded to half float, each channel is off by at most two
    /// roundings of the luminance, which bounds its OkLab chroma by about
    /// the cube root's slope there times that: 0.002 for the fringes' lightness.
    static let grayChroma = 0.002

    @Test("The kernels compile from Metal source")
    func kernelsCompile() throws {
        #expect(try LensKernels.compile() == 7)
    }

    /// A context whose intermediates are 32-bit float: the renderer's math
    /// without the app's half-float storage, to compare with the reference.
    static let floatContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [
        .workingColorSpace: RenderEngine.workingColorSpace, .workingFormat: CIFormat.RGBAf,
        .cacheIntermediates: false,
    ])

    /// One render at a time: concurrent renders through one context gave wrong pixels.
    static let floatLock = Mutex(())

    static func renderFloat(_ image: CIImage) -> LinearImage {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        floatLock.withLock { _ in
            pixels.withUnsafeMutableBytes { buffer in
                floatContext.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: image.extent,
                                    format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
            }
        }
        return LinearImage(width: width, height: height, pixels: pixels)
    }

    /// Single precision differs from the reference's double-precision OkLab
    /// in the order of operations and in Metal's powr and acos (a few float
    /// steps each). OkLab's a and b are differences of terms near 1 with
    /// weights up to 2.4, so they are off by about 5 × 10⁻⁷; through the
    /// steepest slope the weight has, the chroma gate's 1.5 / 0.008 per unit
    /// of chroma, that is 10⁻⁴ of weight. The hue falloff (1.5 / 9.3° at
    /// the listed colors' Tolerance) and the edge smoothstep (1.5 / 0.2 per
    /// unit of range, over float luminance) add an order of magnitude less.
    /// Twice that.
    static let floatWeight: Float = 2e-4

    @Test("Fringe removal matches its CPU reference", arguments: [TestScene.fringes, .fringeSubjects, .hueRamp])
    func fringeRemovalMatchesReference(scene: TestScene) {
        let input = scene.image()
        var values = Self.listed()
        values.colorFringes.slot2?.tolerance = 60
        let rendered = Self.renderFloat(AdjustmentRenderer().render(values, to: input.ciImage, context: RenderContext()))
        let expected = LensReference.removeFringes(input, values.colorFringes, scale: 1)
        var failures = 0, worst: Float = 0
        for i in rendered.pixels.indices where i % 4 != 3 {
            let error = abs(rendered.pixels[i] - expected.pixels[i])
            let gray = abs(input.pixels[i] - expected.pixels[i]) + 0.5
            if error > Self.floatWeight * gray + 1e-6 {
                failures += 1
                worst = max(worst, error)
            }
        }
        #expect(failures == 0, "\(failures) components off; worst \(worst)")
    }

    @Test("The fringe map is the weight fringe removal uses", arguments: [TestScene.fringes, .hueRamp])
    func fringeMapMatchesReference(scene: TestScene) {
        let input = scene.image()
        let values = Self.listed()
        let rendered = Self.renderFloat(AdjustmentRenderer().fringeMap(values, to: input.ciImage, context: RenderContext()))
        let expected = LensReference.fringeWeight(input, values.colorFringes, scale: 1)
        let worst = (0..<expected.count).map { abs(rendered.pixels[$0 * 4] - expected[$0]) }.max() ?? 0
        #expect(worst <= Self.floatWeight, "worst \(worst)")
    }

    /// The app's context stores intermediates as half float (`RGBAh`):
    /// the input, the luminance, the edge weight and the two blur passes
    /// are each rounded (2⁻¹¹ relative, or toward zero, 2⁻¹⁰). Luminance
    /// below 1 is then off by 2 × 2⁻¹⁰, a window's range by twice that,
    /// the edge weight by the smoothstep's slope (1.5 / 0.2) times it plus
    /// three roundings of a weight below 1: 7.5 × 2⁻⁸ + 3 × 2⁻¹⁰ ≈ 0.032.
    /// A pixel's hue moves with its rounded input by about 2⁻¹⁰ / chroma
    /// radians; at the scenes' fringe chroma (above 0.05) and Tolerance 60
    /// (a falloff 28° wide, slope 1.5 / 28° = 0.0536 per degree), 0.06
    /// of weight. A component then is off by Δw × |c − Y| plus two
    /// roundings of itself.
    @Test("In the app's half-float context, fringe removal stays within its derived bound")
    func halfFloatPipelineStaysNearReference() {
        let input = TestScene.fringes.image()
        var values = Self.listed()
        values.colorFringes.slot2?.tolerance = 60
        let rendered = Self.render(values, input)
        let expected = LensReference.removeFringes(input, values.colorFringes, scale: 1)
        let weightBound: Float = 0.032 + 0.06
        var failures = 0
        for i in rendered.pixels.indices where i % 4 != 3 {
            let gray = abs(input.pixels[i] - expected.pixels[i])
            let error = abs(rendered.pixels[i] - expected.pixels[i])
            if error > weightBound * max(gray, 0) + Self.halfFloat(expected.pixels[i]) * 2 + 1e-4 {
                failures += 1
            }
        }
        #expect(failures == 0)
    }

    /// Two kernels of one run-time compiled library with the same signature
    /// were run as one: after the photo, the map came back as the photo.
    @Test("The fringe map and fringe removal never stand in for each other in one context")
    func mapAndRemovalStayApart() {
        let input = TestScene.fringes.image()
        let values = Self.listed()
        let engine = RenderEngine(contextCount: 1, name: "lens-order")
        func render(_ image: CIImage) -> [Float] {
            let width = Int(image.extent.width), height = Int(image.extent.height)
            var pixels = [Float](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes { buffer in
                engine.withContext {
                    $0.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: image.extent,
                              format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
                }
            }
            return pixels
        }
        let renderer = AdjustmentRenderer()
        let photo = render(renderer.render(values, to: input.ciImage, context: RenderContext()))
        let map = render(renderer.fringeMap(values, to: input.ciImage, context: RenderContext()))
        let photoAgain = render(renderer.render(values, to: input.ciImage, context: RenderContext()))
        #expect(photo != map)
        #expect(photo == photoAgain)
        #expect(map == render(renderer.fringeMap(values, to: input.ciImage, context: RenderContext())))
    }

    @Test("Color alignment matches its CPU reference")
    func alignmentMatchesReference() {
        let input = TestScene.lateralColor.image()
        var values = Adjustments()
        values.colorAlignment = ColorAlignment(red: 40, blue: -30)
        let rendered = Self.renderFloat(AdjustmentRenderer().render(values, to: input.ciImage, context: RenderContext()))
        let expected = LensReference.align(input, values.colorAlignment)
        let worst = rendered.pixels.indices.filter { $0 % 4 != 3 }.map { abs(rendered.pixels[$0] - expected.pixels[$0]) }.max() ?? 0
        // Interpolation in float between float inputs: a few float steps.
        #expect(worst <= 1e-5, "worst \(worst)")
    }
}
