import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Testing
@testable import PhotoCore

/// The sharpening map (docs/features/sharpen-mask-preview): the mask the
/// sharpening step blends with, shown in place of the photo.
@Suite("Sharpening map")
struct SharpeningMapTests {
    /// SharpenTests' scene: low-contrast noisy texture in columns 8 ..< 120
    /// (a smooth noisy region), flat bands, and a step at x = 192 from 0.735
    /// to 0.25 (encoded). Its texture gives partial mask values.
    static let scene = SharpenTests.scene
    static let size = SharpenTests.size

    /// The same noisy region beside a strong step at x = 192, 0.9 to 0.1
    /// (encoded): a range of 0.8, past the 0.5 where Masking 100 lets all
    /// sharpening through.
    static let strongEdgeScene: CIImage = {
        let original = green(scene)
        var data = [Float](repeating: 1, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let linear = x < 128 ? Float(original[y * size + x]) : Float(ColorMath.decode(x < 192 ? 0.9 : 0.1))
                for channel in 0..<3 { data[(y * size + x) * 4 + channel] = linear }
            }
        }
        return CIImage(bitmapData: data.withUnsafeBytes { Data($0) }, bytesPerRow: size * 16,
                       size: CGSize(width: size, height: size), format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
    }()
    /// Inside the texture, away from the bands' influence (widening and blur
    /// reach at most a few pixels).
    static let smooth = 16..<110
    /// Columns on the step.
    static let edge = 190..<194
    static let rows = 16..<240

    /// A float context, so that comparisons see the math and not half-float
    /// rounding of intermediates.
    static let floatContext = CIContext(options: [
        .workingColorSpace: RenderEngine.workingColorSpace,
        .workingFormat: CIFormat.RGBAf,
        .cacheIntermediates: false,
    ])

    /// The green channel over the scene's extent, as stored (no encoding).
    static func green(_ image: CIImage) -> [Double] {
        let w = size, h = size
        var buffer = [Float](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { bytes in
            floatContext.render(image, toBitmap: bytes.baseAddress!, rowBytes: w * 16,
                                bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf,
                                colorSpace: RenderEngine.workingColorSpace)
        }
        return stride(from: 1, to: buffer.count, by: 4).map { Double(buffer[$0]) }
    }

    static func encoded(_ image: CIImage) -> CIImage {
        let encode = CIFilter.linearToSRGBToneCurve()
        encode.inputImage = image
        return encode.outputImage!.cropped(to: image.extent)
    }

    static func mask(_ settings: Sharpen, scale: Double = 1, in image: CIImage = scene) -> [Double] {
        green(AdjustmentRenderer.sharpeningMask(image, settings, scale: scale))
    }

    // MARK: AC1, AC3, AC6

    @Test("Masking 100 holds back the smooth region and keeps the edge; Masking 0 is full everywhere (AC1)")
    func noneOnSmoothFullOnEdge() {
        let strict = Self.mask(Sharpen(amount: 80, radius: 1, detail: 25, masking: 100), in: Self.strongEdgeScene)
        let open = Self.mask(Sharpen(amount: 80, radius: 1, detail: 25, masking: 0), in: Self.strongEdgeScene)
        for y in Self.rows {
            for x in Self.smooth { #expect(strict[y * Self.size + x] < 0.01, "smooth (\(x), \(y))") }
            for x in Self.edge { #expect(strict[y * Self.size + x] > 0.99, "edge (\(x), \(y))") }
        }
        #expect(open.allSatisfy { abs($0 - 1) < 1e-6 })
    }

    @Test("Raising Masking never raises a pixel's mask (AC3)", arguments: [1.0, 0.5])
    func maskingOnlyLowers(scale: Double) {
        var previous: [Double]?
        for masking in [0.0, 1, 5, 10, 25, 40, 60, 80, 100] {
            let current = Self.mask(Sharpen(amount: 80, radius: 1.4, detail: 25, masking: masking), scale: scale)
            if let previous {
                // Float rounding only: the ramp's threshold rises with Masking and its gain falls.
                for (now, before) in zip(current, previous) { #expect(now <= before + 1e-5) }
            }
            previous = current
        }
    }

    @Test("At render scale 0.1 the map still shows Masking, where the renderer skips sharpening (AC6)")
    func reducedScaleStillMasks() throws {
        let renderer = AdjustmentRenderer()
        var values = Adjustments()
        values.sharpen = Sharpen(amount: 80, radius: 1, detail: 25, masking: 100)
        let context = RenderContext(scale: 0.1, isRaw: false)
        // The renderer skips sharpening at this scale ...
        let scene = Self.strongEdgeScene
        let rendered = Self.green(renderer.render(values, to: scene, context: context))
        let original = Self.green(scene)
        #expect(zip(rendered, original).allSatisfy { abs($0 - $1) < 1e-6 })
        // ... and the map is neither full everywhere nor blank.
        let map = Self.green(renderer.sharpeningMap(values, to: scene, context: context))
        for y in Self.rows {
            for x in Self.smooth { #expect(map[y * Self.size + x] < 0.01, "smooth (\(x), \(y))") }
            // At this scale the neighborhood and its widening are one pixel: the two columns beside the step.
            for x in 191..<193 { #expect(map[y * Self.size + x] > 0.99, "edge (\(x), \(y))") }
        }
    }

    // MARK: AC2

    /// The sharpening step computes base + m · (sharpened − base) in the
    /// perceptual encoding. Rendering it with and without Masking recovers
    /// m wherever sharpening moves a pixel by at least 0.02; it must equal
    /// the map. In float, the recovery's error is a few float roundings
    /// (2⁻²⁴ relative) of encoded values below 1.2, divided by at least
    /// 0.02: under 1e-5. The bound allows 1e-4 for the GPU's pow in the two
    /// tone curves (a few ulps each).
    @Test("The map equals the mask the sharpening step blends with (AC2)",
          arguments: [(10.0, 0.7), (40, 1.5), (100, 3), (70, 1)], [1.0, 0.5])
    func mapIsTheBlendMask(_ values: (masking: Double, radius: Double), scale: Double) {
        let settings = Sharpen(amount: 150, radius: values.radius, detail: 60, masking: values.masking)
        var unmaskedSettings = settings
        unmaskedSettings.masking = 0
        let scene = Self.scene
        let extent = scene.extent
        let base = Self.green(Self.encoded(scene))
        let masked = Self.green(Self.encoded(AdjustmentRenderer.sharpen(scene, settings, scale: scale, extent: extent)))
        let unmasked = Self.green(Self.encoded(AdjustmentRenderer.sharpen(scene, unmaskedSettings, scale: scale,
                                                                         extent: extent)))
        let map = Self.mask(settings, scale: scale)
        var compared = 0
        var partial = 0
        var worst = 0.0
        for y in 8..<(Self.size - 8) {
            for x in 8..<(Self.size - 8) {
                let i = y * Self.size + x
                let moved = unmasked[i] - base[i]
                guard abs(moved) >= 0.02 else { continue }
                let recovered = (masked[i] - base[i]) / moved
                worst = max(worst, abs(recovered - map[i]))
                compared += 1
                if map[i] > 0.05, map[i] < 0.95 { partial += 1 }
            }
        }
        #expect(compared > 500)
        #expect(worst < 1e-4)
        // At Masking 10 the threshold (0.008) is below the texture's range, so
        // where sharpening moves pixels the mask is full; at 100 only edges move.
        if values.masking == 40 || values.masking == 70 { #expect(partial > 0) }
    }

    // MARK: AC11, first part

    @Test("Amount and the group's switch don't change the map (AC11)")
    func amountDoesNotChangeTheMap() {
        let renderer = AdjustmentRenderer()
        let context = RenderContext(scale: 1, isRaw: false)
        var fifty = Adjustments()
        fifty.exposure.ev = 0.3
        fifty.sharpen = Sharpen(amount: 50, radius: 1.2, detail: 40, masking: 45)
        var zero = fifty
        zero.sharpen.amount = 0
        var off = fifty
        off.setEnabled(.sharpening, false)
        let reference = Self.green(renderer.sharpeningMap(fifty, to: Self.scene, context: context))
        #expect(Self.green(renderer.sharpeningMap(zero, to: Self.scene, context: context)) == reference)
        // Turned off, the map uses the stored values (design §11), not the defaults (Masking 0, full).
        #expect(Self.green(renderer.sharpeningMap(off, to: Self.scene, context: context)) == reference)
        #expect(reference.contains { $0 < 0.5 })
    }

    @Test("The map's input is the image the sharpening step sees")
    func inputIsBeforeSharpening() {
        let renderer = AdjustmentRenderer()
        let context = RenderContext(scale: 1, isRaw: false)
        var values = Adjustments()
        values.exposure.ev = -0.4
        values.vignette.amount = -30
        // Without sharpening or grain, the render is the sharpening step's input.
        let input = Self.green(renderer.sharpeningInput(values, to: Self.scene, context: context))
        let rendered = Self.green(renderer.render(values, to: Self.scene, context: context))
        #expect(input == rendered)
        values.sharpen = Sharpen(amount: 100, radius: 1, detail: 25, masking: 30)
        values.grain.strength = 40
        #expect(Self.green(renderer.sharpeningInput(values, to: Self.scene, context: context)) == input)
    }

    // MARK: Display (design §11, DR6)

    @Test("Mask 0, 0.5 and 1 show as 0, the interface's middle grey and white")
    func displayEncoding() throws {
        let engine = RenderEngine(contextCount: 1, name: "map-test")
        for (value, expected) in [(0.0, 0.0), (0.5, 127.5), (1.0, 255.0)] {
            let grey = CIImage(color: CIColor(red: value, green: value, blue: value,
                                              colorSpace: RenderEngine.workingColorSpace)!)
                .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
            let image = try #require(engine.makeCGImage(AdjustmentRenderer.sharpeningMapDisplay(grey),
                                                        colorSpace: RenderEngine.outputColorSpace))
            let data = try #require(image.dataProvider?.data as Data?)
            // BGRA, every channel the same grey.
            for channel in 0..<3 {
                #expect(abs(Double(data[channel]) - expected) <= 1, "\(value) channel \(channel): \(data[channel])")
            }
        }
    }

    @Test("Values outside 0 … 1 (a resampled mask's ringing) show no brighter than white")
    func displayStaysStandardRange() throws {
        let engine = RenderEngine(contextCount: 1, name: "map-test")
        let bright = CIImage(color: CIColor(red: 1.3, green: 1.3, blue: 1.3, colorSpace: RenderEngine.workingColorSpace)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let rendered = try #require(engine.makeHDRCGImage(AdjustmentRenderer.sharpeningMapDisplay(bright)))
        #expect(rendered.contentHeadroom <= 1.001)
    }

    // MARK: Status (design §7, AC11)

    static func values(amount: Double, groupOn: Bool = true, maskSharpness: Double? = nil,
                       maskOn: Bool = true) -> Adjustments {
        var values = Adjustments()
        values.sharpen = Sharpen(amount: amount, radius: 1, detail: 25, masking: 40)
        if !groupOn { values.setEnabled(.sharpening, false) }
        if let maskSharpness {
            var mask = GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: 0.5, y: 0.5),
                                                               radiusX: 0.2, radiusY: 0.2))]) {
                $0.sharpen = maskSharpness
            }
            mask.isEnabled = maskOn
            values.local.masks = [mask]
        }
        return values
    }

    @Test("Not applied only when nothing at all is sharpened (AC11's four cases)")
    func notAppliedRule() {
        // Applied.
        #expect(SharpeningMapStatus(Self.values(amount: 40)) == SharpeningMapStatus(reason: nil, masksSharpen: false))
        #expect(!SharpeningMapStatus(Self.values(amount: 40)).isNotApplied)
        // (a) Amount 0, no mask with Sharpness.
        let a = SharpeningMapStatus(Self.values(amount: 0))
        #expect(a.reason == .amountZero && a.isNotApplied && !a.notesMaskSharpening)
        // (b) Group off, no mask with Sharpness; off wins over Amount 0.
        let b = SharpeningMapStatus(Self.values(amount: 40, groupOn: false))
        #expect(b.reason == .turnedOff && b.isNotApplied)
        #expect(SharpeningMapStatus(Self.values(amount: 0, groupOn: false)).reason == .turnedOff)
        // (c) Amount 0, and separately group off, each with a mask in effect at Sharpness 50.
        for status in [SharpeningMapStatus(Self.values(amount: 0, maskSharpness: 50)),
                       SharpeningMapStatus(Self.values(amount: 40, groupOn: false, maskSharpness: 50))] {
            #expect(!status.isNotApplied)
            #expect(status.notesMaskSharpening)
        }
        // (d) The same with that mask turned off.
        #expect(SharpeningMapStatus(Self.values(amount: 0, maskSharpness: 50, maskOn: false)).isNotApplied)
        #expect(SharpeningMapStatus(Self.values(amount: 40, groupOn: false, maskSharpness: 50, maskOn: false))
            .isNotApplied)
        // A mask in effect without Sharpness does not count; nor does the Masks group turned off.
        #expect(SharpeningMapStatus(Self.values(amount: 0, maskSharpness: 0)).isNotApplied)
        var stack = Self.values(amount: 0, maskSharpness: 50).editStack
        for index in stack.operations.indices where stack.operations[index].kind == LocalAdjustments.kind {
            stack.operations[index].isEnabled = false
        }
        #expect(SharpeningMapStatus(Adjustments(stack: stack)).isNotApplied)
        // Global sharpening with a sharpening mask: applied, no note.
        #expect(!SharpeningMapStatus(Self.values(amount: 40, maskSharpness: 50)).notesMaskSharpening)
    }

    // MARK: State (design §6)

    @Test("The map suspends the overlay and Show Original and gives them back")
    func suspendAndRestore() {
        var state = SharpeningMapState()
        state.show(overlay: true, original: true)
        #expect(state.isShown)
        #expect(state.hide() == SharpeningMapState.Restore(overlay: true, original: true))
        #expect(!state.isShown)

        state.show(overlay: false, original: true)
        state.valuesChanged()
        #expect(state.hide() == SharpeningMapState.Restore(overlay: false, original: false))

        // Ended by something that needs the photo: the overlay's preference only.
        state.show(overlay: true, original: true)
        #expect(state.end() == SharpeningMapState.Restore(overlay: true, original: false))
        #expect(state == SharpeningMapState())

        // Nothing to give back when it was not shown; showing twice keeps the first.
        #expect(state.hide() == SharpeningMapState.Restore(overlay: false, original: false))
        state.show(overlay: true, original: false)
        state.show(overlay: false, original: false)
        #expect(state.suspendedOverlay)
    }
}
