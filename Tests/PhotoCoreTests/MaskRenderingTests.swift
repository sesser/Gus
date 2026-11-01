import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Local adjustments through the whole renderer (docs/PHASE6_PLAN.md, "Verification").
@Suite("Mask rendering")
struct MaskRenderingTests {
    static let halfRounding = MaskReferenceTests.halfRounding

    static func mask(_ shape: MaskShape, _ values: (inout LocalValues) -> Void) -> Mask {
        GoldenCase.mask([shape], values)
    }

    static func render(_ adjustments: Adjustments, _ input: LinearImage) -> LinearImage {
        ReferenceTests.renderLinear(AdjustmentRenderer().render(adjustments, to: input.ciImage, context: RenderContext()))
    }

    static let radial = RadialGradient(center: MaskPoint(x: 0.45, y: 0.5), radiusX: 0.3, radiusY: 0.2, rotation: 15,
                                       feather: 70)

    /// Local exposure is exact: B · 2^(EV · α). α is off by at most one
    /// half-float rounding plus the table's input rounding (2 · 2⁻¹²), which
    /// moves the gain by EV · ln 2 · that, relative; the gain and the result
    /// are each rounded once more (2⁻¹¹ relative each).
    @Test("Local exposure is the input times 2^(EV · α)", arguments: [2.0, -1.5])
    func exactExposure(ev: Double) {
        let input = TestScene.hueRamp.image()
        var adjustments = Adjustments()
        adjustments.local.masks = [Self.mask(.radial(Self.radial)) { $0.exposure = ev }]
        let rendered = Self.render(adjustments, input)
        let alpha = MaskReference.radial(Self.radial, width: input.width, height: input.height)
        let relative = abs(ev) * log(2) * 2 * Self.halfRounding + 2 * 0x1p-11
        var worst = 0.0
        for i in rendered.pixels.indices where i % 4 != 3 {
            let expected = Double(input.pixels[i]) * pow(2, ev * alpha[i / 4])
            let excess = abs(Double(rendered.pixels[i]) - expected) - (abs(expected) * relative + 0x1p-24)
            worst = max(worst, excess)
        }
        #expect(worst <= 0, "beyond the tolerance by \(worst)")
    }

    /// Other controls blend: B + α · (M − B), M the module at the local value
    /// over the whole image. α's error (one rounding, float) scales |M − B|;
    /// the result is rounded once (2⁻¹¹ relative).
    @Test("Local values other than exposure blend the module's result by α")
    func blendedModule() {
        let input = TestScene.patchChart.image()
        let gradient = LinearGradient(start: MaskPoint(x: 0.2, y: 0.2), end: MaskPoint(x: 0.8, y: 0.7))
        var adjustments = Adjustments()
        adjustments.local.masks = [Self.mask(.linear(gradient)) {
            $0.saturation = 60
            $0.contrast = 25
        }]
        let rendered = Self.render(adjustments, input)
        var global = Adjustments()
        global.presence.saturation = 60
        global.tone.contrast = 25
        let module = Self.render(global, input)
        let alpha = MaskReference.linear(gradient, width: input.width, height: input.height)
        var worst = 0.0
        for i in rendered.pixels.indices where i % 4 != 3 {
            let base = Double(input.pixels[i]), adjusted = Double(module.pixels[i])
            let expected = base + alpha[i / 4] * (adjusted - base)
            let tolerance = abs(adjusted - base) * (Self.halfRounding + MaskReferenceTests.floatEvaluation)
                + max(abs(base), abs(adjusted)) * 2 * 0x1p-11 + 0x1p-24
            worst = max(worst, abs(Double(rendered.pixels[i]) - expected) - tolerance)
        }
        #expect(worst <= 0, "beyond the tolerance by \(worst)")
    }

    /// The same stack with two crops that overlap, at one straighten angle
    /// (rectangles a whole number of pixels apart).
    ///
    /// The mask's alpha must agree on the overlap within two half-float
    /// roundings: it stayed on its content. The photo itself does not repeat
    /// exactly there: two crops' renders differed by up to 2.9 × 10⁻³ at patch
    /// edges without any mask (the GPU's bilinear weights, it seems, depend on
    /// each render's region), so the full render is allowed the photo's own
    /// difference, times the mask's largest gain, plus roundings: Core Image
    /// picks its half-float intermediates per render, so each pointwise step
    /// after the crop (the gain table, the multiply, the saturation, the blend:
    /// four) may be rounded (2⁻¹¹ relative) in one render and not the other,
    /// and the gain table's input α may be rounded (2⁻¹², carried by the gain's
    /// slope ln 2 · 2^EV per unit α) on top of the measured α difference.
    @Test("A mask stays on the same content under two crops")
    func maskFollowsContentAcrossCrops() {
        let input = TestScene.patchChart.image()
        let width = Double(input.width), height = Double(input.height)
        func crop(left: Double, top: Double) -> Crop {
            Crop(rect: CropRect(x: left / width, y: top / height, width: 200 / width, height: 150 / height), angle: 5)
        }
        let crops = [crop(left: 20, top: 16), crop(left: 36, top: 24)]
        let ev = 1.0
        func render(_ crop: Crop, masked: Bool) -> LinearImage {
            var adjustments = Adjustments()
            adjustments.crop = crop
            if masked {
                adjustments.local.masks = [Self.mask(.radial(Self.radial)) {
                    $0.exposure = ev
                    $0.saturation = -40
                }]
            }
            return Self.render(adjustments, input)
        }
        func alpha(_ crop: Crop) -> LinearImage {
            let renderer = MaskRenderer(maskFrame: input.ciImage.extent, crop: crop, selection: crop.apply(to: input.ciImage))
            return ReferenceTests.renderLinear(renderer.alpha(Mask(components: [MaskComponent(.radial(Self.radial))])))
        }
        /// Pairs of pixel offsets in the two renders that show the same content.
        func overlap(_ body: (Int, Int) -> Void) {
            for y in 8..<150 {
                for x in 16..<200 { body((y * 200 + x) * 4, ((y - 8) * 200 + (x - 16)) * 4) }
            }
        }
        let (alphaA, alphaB) = (alpha(crops[0]), alpha(crops[1]))
        var alphaWorst: Float = 0
        overlap { i, j in alphaWorst = max(alphaWorst, abs(alphaA.pixels[i] - alphaB.pixels[j])) }
        #expect(Double(alphaWorst) <= 2 * Self.halfRounding, "alpha differs by \(alphaWorst)")

        let (a, b) = (render(crops[0], masked: true), render(crops[1], masked: true))
        let (plainA, plainB) = (render(crops[0], masked: false), render(crops[1], masked: false))
        let gain = pow(2, ev)
        let steps = 4.0
        let gainDifference = log(2) * gain * (2 * Self.halfRounding + Double(alphaWorst))
        var worst = 0.0
        overlap { i, j in
            let photo = (0..<3).map { abs(Double(plainA.pixels[i + $0]) - Double(plainB.pixels[j + $0])) }.max() ?? 0
            let plain = (0..<3).map { max(abs(Double(plainA.pixels[i + $0])), abs(Double(plainB.pixels[j + $0]))) }.max() ?? 0
            for c in 0..<3 {
                let pa = Double(a.pixels[i + c]), pb = Double(b.pixels[j + c])
                let tolerance = gain * photo + plain * gainDifference
                    + steps * 2 * max(abs(pa), abs(pb)) * 0x1p-11 + 0x1p-24
                worst = max(worst, abs(pa - pb) - tolerance)
            }
        }
        #expect(worst <= 0, "overlap differs beyond the photo's own difference by \(worst)")
        // The mask's edge is far steeper than these tolerances: a mask that did
        // not move with the crop would fail.
        #expect(zip(b.pixels, plainB.pixels).map { abs($0 - $1) }.max() ?? 0 > 0.1)
    }

    /// With the angle changed the pixels differ, so the check is geometric: the
    /// centroid of a smooth radial mask lands where the mask-frame mapping puts
    /// its center. Bilinear resampling keeps the first moment, and the profile
    /// 1 − smoothstep(0, 1, r) sampled at 1 px moves it by far less than 0.01 px.
    @Test("A mask's center lands where the mapping says, straightened", arguments: [0.0, 12.0, -7.5])
    func maskCentroidUnderStraightening(angle: Double) {
        let input = TestScene.patchChart.image()
        let crop = Crop(rect: CropRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7), quarterTurns: 1, angle: angle)
        let gradient = RadialGradient(center: MaskPoint(x: 0.42, y: 0.47), radiusX: 0.06, radiusY: 0.06, feather: 100)
        let renderer = MaskRenderer(maskFrame: input.ciImage.extent, crop: crop, selection: crop.apply(to: input.ciImage))
        let alpha = ReferenceTests.renderLinear(renderer.alpha(Mask(components: [MaskComponent(.radial(gradient))])))
        var sum = 0.0, sx = 0.0, sy = 0.0
        for y in 0..<alpha.height {
            for x in 0..<alpha.width {
                let value = Double(alpha.pixels[(y * alpha.width + x) * 4])
                sum += value
                sx += value * (Double(x) + 0.5)
                sy += value * (Double(y) + 0.5)
            }
        }
        let expected = CropGeometry.maskToOutputPixel(CGPoint(x: 0.42, y: 0.47), crop: crop,
                                                      sourceSize: CGSize(width: input.width, height: input.height))
        #expect(abs(sx / sum - expected.x) < 0.01 && abs(sy / sum - expected.y) < 0.01,
                "centroid \(sx / sum), \(sy / sum); mapped \(expected)")
    }

    /// A brush mask made for a full-size export against the one made for a
    /// preview a third the size, scaled up bilinearly. Linear interpolation
    /// over a step of h is off by at most h²/8 · (|v_xx| + |v_yy|); the second
    /// differences of the full-size plane over 3 pixels give h² · v″ directly,
    /// so the tolerance is the largest of (|Δ²ₓ| + |Δ²ᵧ|) / 8 over the plane,
    /// plus one half-float rounding of each plane.
    @Test("A brush rasterized for export matches the preview's, scaled up")
    func brushAcrossResolutions() {
        let brush = Brush(strokes: [
            BrushStroke(points: [MaskPoint(x: 0.15, y: 0.3), MaskPoint(x: 0.5, y: 0.45), MaskPoint(x: 0.85, y: 0.7)],
                        size: 0.05, feather: 80, flow: 50, density: 90),
            BrushStroke(points: [MaskPoint(x: 0.4, y: 0.2), MaskPoint(x: 0.45, y: 0.8)], size: 0.04, feather: 90,
                        erase: true),
        ])
        let (small, large, factor) = ((400, 300), (1200, 900), 3)
        func plane(_ size: (Int, Int)) -> [Double] {
            let frame = CGRect(x: 0, y: 0, width: size.0, height: size.1)
            let renderer = MaskRenderer(maskFrame: frame, crop: Crop(), selection: CIImage(color: .black).cropped(to: frame))
            let linear = ReferenceTests.renderLinear(renderer.alpha(Mask(components: [MaskComponent(.brush(brush))])))
            return stride(from: 0, to: linear.pixels.count, by: 4).map { Double(linear.pixels[$0]) }
        }
        let preview = plane(small), export = plane(large)
        func p(_ x: Int, _ y: Int) -> Double { preview[min(max(y, 0), small.1 - 1) * small.0 + min(max(x, 0), small.0 - 1)] }
        var curvature = 0.0
        for y in factor..<(large.1 - factor) {
            for x in factor..<(large.0 - factor) {
                let v = export[y * large.0 + x]
                let dxx = export[y * large.0 + x + factor] - 2 * v + export[y * large.0 + x - factor]
                let dyy = export[(y + factor) * large.0 + x] - 2 * v + export[(y - factor) * large.0 + x]
                curvature = max(curvature, (abs(dxx) + abs(dyy)) / 8)
            }
        }
        let tolerance = curvature + 2 * Self.halfRounding
        var worst = 0.0
        for y in factor..<(large.1 - factor) {
            for x in factor..<(large.0 - factor) {
                // The preview pixel grid in the export's coordinates, sampled bilinearly.
                let sx = (Double(x) + 0.5) / Double(factor) - 0.5, sy = (Double(y) + 0.5) / Double(factor) - 0.5
                let x0 = Int(sx.rounded(.down)), y0 = Int(sy.rounded(.down))
                let fx = sx - Double(x0), fy = sy - Double(y0)
                let scaled = (p(x0, y0) * (1 - fx) + p(x0 + 1, y0) * fx) * (1 - fy)
                    + (p(x0, y0 + 1) * (1 - fx) + p(x0 + 1, y0 + 1) * fx) * fy
                worst = max(worst, abs(scaled - export[y * large.0 + x]))
            }
        }
        #expect(worst <= tolerance, "largest difference \(worst), tolerance \(tolerance)")
        #expect(tolerance < 0.02, "the stroke's falloff is too sharp for this comparison: \(tolerance)")
    }

    @Test("Masks decode RAW files whole; a stack without masks does not")
    func decodeSettings() {
        var adjustments = Adjustments()
        adjustments.local.masks = [Self.mask(.radial(Self.radial)) { $0.exposure = 1 }]
        #expect(adjustments.decodeSettings.fullFrame)
        adjustments.local.masks[0].isEnabled = false
        #expect(!adjustments.decodeSettings.fullFrame)
    }
}

/// On a real Panasonic RW2 shot at an aspect other than its sensor's: a mask
/// makes the decoder give the whole sensor and the renderer crop back to the
/// camera's frame, so a mask whose alpha is 0 everywhere should leave the
/// render as it is. The file is only read. `CAMERA_RAW_SAMPLE` names it.
///
/// Known issue (docs/PHASE6_PLAN.md): the decoder corrects lens distortion
/// relative to the frame it decodes, so the whole sensor cropped to the
/// camera's frame differs from the camera's own frame at every edge (P1190134,
/// 16:9 of 4:3: PSNR 40.6 dB with lens correction, 63.6 dB without). A crop
/// equal to the camera's frame did the same before masks existed. What does
/// hold: the masked stack renders like that explicit crop.
@Suite("Masks on a camera RAW file",
       .enabled(if: ProcessInfo.processInfo.environment["CAMERA_RAW_SAMPLE"] != nil,
                "Set CAMERA_RAW_SAMPLE to a Panasonic RW2 (or Olympus ORF) shot at a cropped aspect ratio"))
struct CameraRAWMaskTests {
    @Test("Masks with alpha 0 render the same as no masks")
    func zeroAlphaMasksChangeNothing() throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAMERA_RAW_SAMPLE"] ?? "")
        let cameraFrame = try #require(CameraFrame.rect(of: url), "\(url.lastPathComponent) has no camera crop")
        var plain = Adjustments()
        plain.exposure.ev = 0.3
        var masked = plain
        // Placed off the frame: alpha 0 everywhere, but rendered (and decoded whole).
        masked.local.masks = [GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: -1.5, y: -1.5),
                                                                       radiusX: 0.01, radiusY: 0.01))]) {
            $0.exposure = 2
        }]
        #expect(masked.decodeSettings.fullFrame && !plain.decodeSettings.fullFrame)
        let generator = PreviewGenerator(engine: Goldens.engine)
        for longEdge in [1024, nil] as [Int?] {
            let a = try EncodedImage(rendering: generator.image(source: url, stack: plain.editStack, longEdge: longEdge),
                                     engine: Goldens.engine)
            let b = try EncodedImage(rendering: generator.image(source: url, stack: masked.editStack, longEdge: longEdge),
                                     engine: Goldens.engine)
            let difference = ImageDifference(expected: a, actual: b)
            print("camera RAW \(url.lastPathComponent) (frame \(cameraFrame)), long edge \(longEdge.map(String.init) ?? "full"): "
                  + "\(a.width) × \(a.height) and \(b.width) × \(b.height), \(difference)")
            #expect(difference.sizesMatch, "\(a.width) × \(a.height) against \(b.width) × \(b.height)")
            if !GoldenTests.tolerance.accepts(difference) {
                let failure = Goldens.failureDirectory.appending(path: "camera-raw-\(longEdge.map(String.init) ?? "full").png")
                try EncodedImage.sideBySide(expected: a, actual: b).writePNG(to: failure)
                withKnownIssue("The decoder's lens correction depends on the decoded frame") {
                    Issue.record("\(difference). Without masks | with α = 0 masks | 8× difference: \(failure.path)")
                }
            }
            // At full size only: reduced, the explicit crop's decode size comes from
            // `Crop.sourceZoom` and can round to a pixel more or less.
            guard longEdge == nil else { continue }
            var cropped = plain
            cropped.crop = Crop(rect: cameraFrame)
            let explicit = try EncodedImage(rendering: generator.image(source: url, stack: cropped.editStack,
                                                                       longEdge: longEdge), engine: Goldens.engine)
            let againstCrop = ImageDifference(expected: explicit, actual: b)
            #expect(GoldenTests.tolerance.accepts(againstCrop), "against an explicit camera-frame crop: \(againstCrop)")
        }
    }
}
