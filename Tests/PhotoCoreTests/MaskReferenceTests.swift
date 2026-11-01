import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Each mask shape's alpha, rendered alone by `MaskRenderer`, against its
/// formula in plain Swift (`Reference/MaskReference.swift`).
///
/// Half-float rounding: a value v ≤ 1 rounds by at most 2⁻¹² (the spacing
/// is 2⁻¹¹ from ½ to 1, less below), so `halfRounding` bounds one rounding
/// of an alpha, or of a position ramp that runs 0 … 1. Smoothstep's slope is
/// at most 1.5 per unit of its input.
@Suite("Mask references")
struct MaskReferenceTests {
    static let halfRounding = 0x1p-12
    /// Float arithmetic in Core Image's generators and in the CPU rasterizer.
    static let floatEvaluation = 1e-6
    static let width = 160, height = 120

    static func renderer(_ scene: LinearImage? = nil) -> MaskRenderer {
        let image = scene ?? LinearImage(width: width, height: height,
                                         pixels: [Float](repeating: 0.5, count: width * height * 4))
        return MaskRenderer(maskFrame: image.ciImage.extent, crop: Crop(), selection: image.ciImage)
    }

    static func render(_ image: CIImage) -> [Double] {
        let linear = ReferenceTests.renderLinear(image)
        return stride(from: 0, to: linear.pixels.count, by: 4).map { Double(linear.pixels[$0]) }
    }

    /// Compares with `expected`, skipping pixels `skip` says sit on a hard edge.
    static func check(_ actual: [Double], _ expected: [Double], tolerance: Double, skip: (Int) -> Bool = { _ in false },
                      sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(actual.count == expected.count, sourceLocation: sourceLocation)
        var worst = 0.0, worstIndex = 0, compared = 0
        for i in expected.indices where !skip(i) {
            compared += 1
            let difference = abs(actual[i] - expected[i])
            if difference > worst { (worst, worstIndex) = (difference, i) }
        }
        #expect(worst <= tolerance, """
            largest difference \(worst) at pixel \(worstIndex % width), \(worstIndex / width) \
            (\(actual[worstIndex]) for \(expected[worstIndex])); tolerance \(tolerance)
            """, sourceLocation: sourceLocation)
        #expect(compared > expected.count / 2, "too few pixels compared", sourceLocation: sourceLocation)
        // The shape is not flat: it would compare equal to a wrong constant too.
        #expect((expected.max() ?? 0) - (expected.min() ?? 0) > 0.5, sourceLocation: sourceLocation)
    }

    // MARK: Gradients

    static let linearCases: [LinearGradient] = [
        LinearGradient(start: MaskPoint(x: 0.2, y: 0.3), end: MaskPoint(x: 0.8, y: 0.6)),
        LinearGradient(start: MaskPoint(x: 0.5, y: 0.9), end: MaskPoint(x: 0.45, y: 0.2), feather: 30),
        LinearGradient(start: MaskPoint(x: 0.1, y: 0.1), end: MaskPoint(x: 0.9, y: 0.9), feather: 0),
    ]

    /// `CISmoothLinearGradient` between the transition's ends is smoothstep:
    /// float evaluation plus one half-float rounding of α. A hard edge (feather
    /// 0) compares exactly, away from pixels within 10⁻⁴ of t = ½, where float
    /// evaluation of t decides.
    @Test("Linear gradient", arguments: linearCases)
    func linear(gradient: LinearGradient) {
        let actual = Self.render(Self.renderer().linear(gradient).cropped(to: CGRect(x: 0, y: 0, width: Self.width,
                                                                                   height: Self.height)))
        let expected = MaskReference.linear(gradient, width: Self.width, height: Self.height)
        let hard = gradient.feather == 0
        Self.check(actual, expected, tolerance: hard ? 0 : Self.halfRounding + Self.floatEvaluation) { i in
            hard && abs(MaskReference.linearPosition(gradient, Double(i % Self.width) + 0.5,
                                                     Double(i / Self.width) + 0.5,
                                                     width: Self.width, height: Self.height) - 0.5) < 1e-4
        }
    }

    static let radialCases: [RadialGradient] = [
        RadialGradient(center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.3, radiusY: 0.3),
        RadialGradient(center: MaskPoint(x: 0.4, y: 0.55), radiusX: 0.35, radiusY: 0.15, rotation: 30, feather: 80),
        RadialGradient(center: MaskPoint(x: 0.6, y: 0.4), radiusX: 0.2, radiusY: 0.32, rotation: -50, feather: 0),
    ]

    /// The ramp across the transition and smoothstep (pointwise arithmetic) are
    /// evaluated in float; α is rounded once. A hard edge compares exactly away
    /// from pixels within 2⁻¹⁰ (relative) of the ellipse.
    @Test("Radial gradient", arguments: radialCases)
    func radial(gradient: RadialGradient) {
        let actual = Self.render(Self.renderer().radial(gradient).cropped(to: CGRect(x: 0, y: 0, width: Self.width,
                                                                                   height: Self.height)))
        let expected = MaskReference.radial(gradient, width: Self.width, height: Self.height)
        let hard = gradient.feather == 0
        let tolerance = hard ? 0 : Self.halfRounding + Self.floatEvaluation
        Self.check(actual, expected, tolerance: tolerance) { i in
            hard && abs(MaskReference.radialDistance(gradient, Double(i % Self.width) + 0.5, Double(i / Self.width) + 0.5,
                                                     width: Self.width, height: Self.height) - 1) < 0x1p-10
        }
    }

    // MARK: Brush

    static let brushCases: [Brush] = [
        Brush(strokes: [BrushStroke(points: [MaskPoint(x: 0.2, y: 0.3), MaskPoint(x: 0.7, y: 0.5),
                                             MaskPoint(x: 0.7, y: 0.5), MaskPoint(x: 0.8, y: 0.8)],
                                    size: 0.06, feather: 60, flow: 40, density: 80)]),
        Brush(strokes: [
            BrushStroke(points: [MaskPoint(x: 0.1, y: 0.5), MaskPoint(x: 0.9, y: 0.5)], size: 0.1, feather: 100),
            BrushStroke(points: [MaskPoint(x: 0.5, y: 0.1), MaskPoint(x: 0.5, y: 0.9)], size: 0.04, feather: 0,
                        erase: true),
            BrushStroke(points: [MaskPoint(x: 0.3, y: 0.2)], size: 0.08, flow: 70),
        ]),
    ]

    /// The CPU rasterizer sums in Double like the reference, in the same dab
    /// order; the plane reaches Core Image as half float: one rounding.
    @Test("Brush", arguments: brushCases)
    func brush(brush: Brush) throws {
        let image = try #require(BrushRasterizer.image(brush, extent: CGRect(x: 0, y: 0, width: Self.width,
                                                                            height: Self.height)))
        Self.check(Self.render(image), MaskReference.brush(brush, width: Self.width, height: Self.height),
                   tolerance: Self.halfRounding + Self.floatEvaluation)
        // The CPU plane itself, before half float, is the reference to float precision.
        let plane = BrushRasterizer.rasterize(brush, width: Self.width, height: Self.height)
        Self.check(plane.map(Double.init), MaskReference.brush(brush, width: Self.width, height: Self.height),
                   tolerance: Self.floatEvaluation)
    }

    @Test("Brush dabs fall on the same scene points at every resolution")
    func brushDabsScale() {
        let stroke = BrushStroke(points: [MaskPoint(x: 0.1, y: 0.2), MaskPoint(x: 0.6, y: 0.7)], size: 0.05)
        let small = BrushRasterizer.dabs(stroke, width: 400, height: 300)
        let large = BrushRasterizer.dabs(stroke, width: 6000, height: 4500)
        #expect(small.count == large.count)
        for (a, b) in zip(small, large) {
            #expect(abs(a.x * 15 - b.x) < 1e-9 && abs(a.y * 15 - b.y) < 1e-9)
        }
    }

    // MARK: Ranges

    /// Half-float rounding of each input channel (2⁻¹¹ relative), of Y and of
    /// the encoded value move y by at most 3 · 2⁻¹¹ relative; the expected α
    /// is the reference's range over that interval, ± one rounding of α.
    static let rangeInputError = 3 * 0x1p-11

    static let luminanceCases: [(TestScene, LuminanceRange)] = [
        (.grayRamp, LuminanceRange(lower: 0.3, upper: 0.7, smoothness: 0.15)),
        (.hazyLandscape, LuminanceRange(lower: 0.55, upper: 1, smoothness: 0.05)),
        (.grayRamp, LuminanceRange(lower: 0.2, upper: 0.6, smoothness: 0)),
    ]

    @Test("Luminance range", arguments: luminanceCases)
    func luminance(scene: TestScene, range: LuminanceRange) {
        let image = scene.image(width: Self.width, height: Self.height)
        let actual = Self.render(Self.renderer(image).luminance(range))
        var worst = 0.0
        for i in actual.indices {
            let rgb = SIMD3(Double(image.pixels[i * 4]), Double(image.pixels[i * 4 + 1]), Double(image.pixels[i * 4 + 2]))
            let y = MaskReference.perceptualLuminance(rgb)
            let candidates = [y * (1 - Self.rangeInputError), y, y * (1 + Self.rangeInputError)]
                .map { MaskReference.luminance(range, y: $0) }
            let low = candidates.min()! - Self.halfRounding, high = candidates.max()! + Self.halfRounding
            worst = max(worst, actual[i] < low ? low - actual[i] : (actual[i] > high ? actual[i] - high : 0))
        }
        #expect(worst == 0, "\(worst) outside the reference's interval")
        #expect((actual.max() ?? 0) - (actual.min() ?? 0) > 0.5)
    }

    /// Samples taken from the scenes themselves, so the ranges select something.
    static func sampled(_ scene: TestScene, at points: [(Int, Int)]) -> [SIMD3<Double>] {
        let image = scene.image(width: width, height: height)
        return points.map { x, y in
            let i = (y * width + x) * 4
            return ColorMath.okLab(linearRec2020: SIMD3(Double(image.pixels[i]), Double(image.pixels[i + 1]),
                                                        Double(image.pixels[i + 2])))
        }
    }

    static let colorCases: [(TestScene, ColorRange)] = [
        (.hueRamp, ColorRange(samples: sampled(.hueRamp, at: [(30, 20)]), tolerance: 60)),
        (.patchChart, ColorRange(samples: sampled(.patchChart, at: [(20, 70), (130, 100)]), tolerance: 30)),
    ]

    /// The OkLab chain is pointwise, so Core Image runs it as one kernel in
    /// float: what is rounded to half float is the input color (2⁻¹¹ relative
    /// per channel) and α. The expected α is the reference's range over the
    /// eight colors one rounding away in each channel, ± one rounding of α.
    @Test("Color range", arguments: colorCases)
    func color(scene: TestScene, range: ColorRange) {
        let image = scene.image(width: Self.width, height: Self.height)
        let actual = Self.render(Self.renderer(image).color(range))
        var worst = 0.0
        for i in actual.indices {
            let rgb = SIMD3(Double(image.pixels[i * 4]), Double(image.pixels[i * 4 + 1]), Double(image.pixels[i * 4 + 2]))
            var candidates: [Double] = []
            for signs in 0..<8 {
                let e = 0x1p-11
                let factor = SIMD3(signs & 1 == 0 ? 1 - e : 1 + e, signs & 2 == 0 ? 1 - e : 1 + e,
                                   signs & 4 == 0 ? 1 - e : 1 + e)
                candidates.append(MaskReference.color(range, d: MaskReference.colorDistance(range.samples, rgb * factor)))
            }
            candidates.append(MaskReference.color(range, d: MaskReference.colorDistance(range.samples, rgb)))
            let low = candidates.min()! - Self.halfRounding, high = candidates.max()! + Self.halfRounding
            worst = max(worst, actual[i] < low ? low - actual[i] : (actual[i] > high ? actual[i] - high : 0))
        }
        #expect(worst <= Self.floatEvaluation, "\(worst) outside the reference's interval")
        #expect((actual.max() ?? 0) - (actual.min() ?? 0) > 0.5)
    }

    // MARK: Combining

    /// Values exact in half float, so the results are exact too.
    @Test("Combining: exact values on small planes")
    func combining() {
        let extent = CGRect(x: 0, y: 0, width: 4, height: 1)
        func plane(_ values: [Float]) -> CIImage {
            LinearImage(width: 4, height: 1, pixels: values.flatMap { [$0, $0, $0, 1] }).ciImage
        }
        func run(_ components: [(alpha: CIImage, operation: MaskOperation, invert: Bool)], amount: Double = 100) -> [Double] {
            let linear = ReferenceTests.renderLinear(MaskRenderer.combine(components, amount: amount, extent: extent))
            return (0..<4).map { Double(linear.pixels[$0 * 4]) }
        }
        let a = plane([0, 0.25, 0.75, 1]), c = plane([0.5, 0.5, 0.5, 0.5])
        #expect(run([(a, .add, false), (c, .add, false)]) == [0.5, 0.5, 0.75, 1])
        #expect(run([(a, .add, false), (c, .subtract, false)]) == [0, 0.125, 0.375, 0.5])
        #expect(run([(a, .add, false), (c, .intersect, false)]) == [0, 0.125, 0.375, 0.5])
        #expect(run([(a, .add, true)]) == [1, 0.75, 0.25, 0])
        // Subtracting the inverse is a · a.
        #expect(run([(a, .add, false), (a, .subtract, true)]) == [0, 0.0625, 0.5625, 1])
        // The first component starts from its operation's identity.
        #expect(run([(a, .subtract, false)]) == [1, 0.75, 0.25, 0])
        #expect(run([(a, .intersect, false)]) == [0, 0.25, 0.75, 1])
        // Amount scales the result.
        #expect(run([(a, .add, false)], amount: 50) == [0, 0.125, 0.375, 0.5])
        #expect(run([], amount: 100) == [0, 0, 0, 0])
    }
}
