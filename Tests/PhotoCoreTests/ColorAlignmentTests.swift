import CoreImage
import Foundation
import PhotoFixtures
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

/// Color Alignment against the PRD's acceptance criteria on scene (c)
/// (docs/features/chromatic-aberration/prd.md AC5–AC7, AC13).
@Suite("Color alignment")
struct ColorAlignmentTests {
    typealias T = LensRenderingTests

    /// Scene (c) at 1024 × 768: a corner 640 pixels from the center, so the
    /// default magnifications move red by 2.6 pixels there and blue by 1.9.
    static let size = (width: 1024, height: 768)
    static var halfDiagonal: Double { (Double(size.width * size.width + size.height * size.height)).squareRoot() / 2 }

    static func scene(red: Double = TestScene.lateralRed, blue: Double = TestScene.lateralBlue) -> LinearImage {
        TestScene.lateralColor(width: size.width, height: size.height, red: red, blue: blue)
    }

    static func measure(_ image: LinearImage) -> (red: Double, blue: Double) {
        ColorAlignmentMeasurement.measure(rgba: image.pixels, width: image.width, height: image.height)
    }

    /// "Well under a pixel at full size" (AC5): a tenth of a pixel at the
    /// corner, below what anyone sees at 100 % and five times the storage's
    /// rounding (0.01 of a ten-thousandth is 0.0006 pixels here).
    static let residualPixels = 0.1

    @Test("AC5: the measurement finds scene (c)'s magnifications to a tenth of a pixel at the corner",
          arguments: [(0.004, -0.003), (-0.002, 0.0015), (0.0, 0.0)])
    func measuresKnownMagnifications(red: Double, blue: Double) {
        let measured = Self.measure(Self.scene(red: red, blue: blue))
        #expect(abs(measured.red - red) * Self.halfDiagonal < Self.residualPixels, "red \(measured.red)")
        #expect(abs(measured.blue - blue) * Self.halfDiagonal < Self.residualPixels, "blue \(measured.blue)")
    }

    /// The correction moves each channel exactly by the stored values (the
    /// renderer against `LensReference.align`), so what is left is the
    /// measurement's error, checked above. Measuring a corrected image again
    /// is no check of it: one interpolation softens red and blue against
    /// green, and the estimator then reads 0.1 pixel less at this corner
    /// (it reads discs as smaller when softer), whatever the alignment.
    @Test("AC5: the measured values are stored and every render, at full and at preview size, applies them")
    func everyRenderAppliesTheStoredCorrection() {
        let scene = Self.scene()
        let measured = Self.measure(scene)
        var values = Adjustments()
        values.colorAlignment = ColorAlignment(automatic: true, red: ColorAlignmentMeasurement.units(measured.red),
                                               blue: ColorAlignmentMeasurement.units(measured.blue))
        let stored = Adjustments(stack: values.editStack)
        #expect(stored.colorAlignment == values.colorAlignment)
        let full = T.render(stored, scene)
        #expect(T.render(stored, scene) == full)
        let half = TestScene.lateralColor(width: Self.size.width / 2, height: Self.size.height / 2)
        for (image, rendered) in [(scene, full), (half, T.render(stored, half, scale: 0.5))] {
            let expected = LensReference.align(image, stored.colorAlignment)
            let worst = rendered.pixels.indices.filter { $0 % 4 != 3 }
                .map { abs(rendered.pixels[$0] - expected.pixels[$0]) }.max() ?? 0
            #expect(worst <= T.halfFloat(1) * 2 + 1e-5, "\(image.width) wide: \(worst)")
        }
        // Red and blue now line up with green: what differs is mostly the
        // interpolation, under half of the misregistration before.
        func misfit(_ image: LinearImage, _ channel: Int) -> Float {
            var sum: Float = 0
            for pixel in 0..<(image.width * image.height) {
                sum += abs(image.pixels[pixel * 4 + channel] - image.pixels[pixel * 4 + 1])
            }
            return sum
        }
        #expect(misfit(full, 0) < 0.5 * misfit(scene, 0))
        #expect(misfit(full, 2) < 0.5 * misfit(scene, 2))
    }

    @Test("A photo without lateral color measures none, and a gray one too")
    func nothingToMeasure() {
        let gray = TestScene.edgeTarget.image(width: 512, height: 384)
        let measured = Self.measure(gray)
        #expect(ColorAlignmentMeasurement.units(measured.red) == 0 && ColorAlignmentMeasurement.units(measured.blue) == 0)
        let flat = LinearImage(width: 64, height: 48, pixels: [Float](repeating: 0.5, count: 64 * 48 * 4))
        #expect(Self.measure(flat) == (0, 0))
    }

    // MARK: AC6

    /// Two crops of scene (c) with the correction on agree where they
    /// overlap as the uncorrected crops do (the GPU's own difference between
    /// two crops, docs/archive/PHASE6_PLAN.md finding 2), plus two half-float
    /// roundings of the extra step: the correction is centered on the
    /// frame, never on the crop. Centered on a crop, it would move the
    /// overlap's red by up to m × 160 pixels (a 320-pixel crop's center is
    /// that far from the frame's), 0.64 pixels, far beyond.
    @Test("AC6: two crops show the same correction where they overlap; a crop never changes what is measured")
    func cropsKeepTheCorrection() async throws {
        let scene = TestScene.lateralColor()
        let width = Double(scene.width), height = Double(scene.height)
        func crop(left: Double, top: Double) -> Crop {
            Crop(rect: CropRect(x: left / width, y: top / height, width: 160 / width, height: 120 / height))
        }
        let crops = [crop(left: 8, top: 8), crop(left: 88, top: 64)]
        func render(_ crop: Crop, aligned: Bool) -> LinearImage {
            var values = Adjustments()
            values.crop = crop
            if aligned { values.colorAlignment = ColorAlignment(red: 40, blue: -30) }
            return T.render(values, scene)
        }
        let (a, b) = (render(crops[0], aligned: true), render(crops[1], aligned: true))
        let (plainA, plainB) = (render(crops[0], aligned: false), render(crops[1], aligned: false))
        var worst: Float = 0
        for y in 56..<120 {
            for x in 80..<160 {
                for c in 0..<3 {
                    let i = (y * 160 + x) * 4 + c, j = ((y - 56) * 160 + (x - 80)) * 4 + c
                    let own = abs(plainA.pixels[i] - plainB.pixels[j])
                    let allowed = own + 2 * T.halfFloat(max(abs(a.pixels[i]), abs(b.pixels[j])))
                    worst = max(worst, abs(a.pixels[i] - b.pixels[j]) - allowed)
                }
            }
        }
        #expect(worst <= 0, "overlap differs beyond the crops' own difference by \(worst)")

        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "c.tif")
            let image = try #require(Self.scene().cgImage(colorSpace: RenderEngine.workingColorSpace))
            try SyntheticImages.write(image, to: url, type: .tiff)
            let generator = PreviewGenerator(engine: ReferenceTests.engine)
            var cropped = Adjustments()
            cropped.crop = Crop(rect: CropRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5), angle: 3)
            let whole = try ColorAlignmentMeasurement.measure(source: url, adjustments: Adjustments(), generator: generator)
            let withCrop = try ColorAlignmentMeasurement.measure(source: url, adjustments: cropped, generator: generator)
            #expect(whole == withCrop)
            #expect(whole.automatic)
        }
    }

    // MARK: AC7

    @Test("AC7: hand-set values move each channel as set; moving one after a measurement makes them hand-set")
    func handSetValues() {
        // The channels against the reference: `LensRenderingTests.alignmentMatchesReference`.
        let measured = ColorAlignment(automatic: true, red: 40, blue: -30)
        var tuned = measured
        tuned.setByHand(red: 42)
        #expect(tuned == ColorAlignment(automatic: false, red: 42, blue: -30))
        tuned = measured
        tuned.setByHand(blue: -25)
        #expect(tuned == ColorAlignment(automatic: false, red: 40, blue: -25))
        let scene = TestScene.lateralColor()
        var values = Adjustments()
        values.colorAlignment = ColorAlignment(red: 40)
        let rendered = T.render(values, scene)
        // Red moved as the reference moves it; green and blue are untouched.
        let expected = LensReference.align(scene, values.colorAlignment)
        for channel in 0..<3 {
            let reference = channel == 0 ? expected : scene
            var worst: Float = 0
            for pixel in 0..<(scene.width * scene.height) {
                let offset = pixel * 4 + channel
                worst = max(worst, abs(rendered.pixels[offset] - reference.pixels[offset]))
            }
            #expect(worst <= T.halfFloat(1) * 2 + 1e-5, "channel \(channel): \(worst)")
        }
    }

    // MARK: AC13

    @Test("AC13: automatic alignment is measured on each photo; hand-set values are copied as they are")
    func eachPhotoIsMeasured() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let generator = PreviewGenerator(engine: ReferenceTests.engine)
            var urls: [URL] = []
            for (name, red, blue) in [("one.tif", 0.004, -0.003), ("two.tif", -0.002, 0.0025)] {
                let url = folder.appending(path: name)
                let image = try #require(Self.scene(red: red, blue: blue).cgImage(colorSpace: RenderEngine.workingColorSpace))
                try SyntheticImages.write(image, to: url, type: .tiff)
                urls.append(url)
            }
            var source = Adjustments()
            source.colorAlignment = ColorAlignment(automatic: true, red: 40, blue: -30)
            source.exposure.ev = 0.3
            var measured: [ColorAlignment] = []
            for url in urls {
                let pasted = source.pasted(onto: Adjustments())
                #expect(pasted.needsAlignmentMeasurement)
                let alignment = try ColorAlignmentMeasurement.measure(source: url, adjustments: pasted, generator: generator)
                measured.append(pasted.measuringAlignment(alignment).colorAlignment)
            }
            #expect(abs(measured[0].redScale - 0.004) * Self.halfDiagonal < Self.residualPixels)
            #expect(abs(measured[0].blueScale + 0.003) * Self.halfDiagonal < Self.residualPixels)
            #expect(abs(measured[1].redScale + 0.002) * Self.halfDiagonal < Self.residualPixels)
            #expect(abs(measured[1].blueScale - 0.0025) * Self.halfDiagonal < Self.residualPixels)
            #expect(measured[0] != measured[1] && measured.allSatisfy(\.automatic))
            // Hand-set (or fine-tuned) values are copied as they are.
            var handSet = source
            handSet.colorAlignment.setByHand(red: 12)
            let pasted = handSet.pasted(onto: Adjustments())
            #expect(!pasted.needsAlignmentMeasurement)
            #expect(pasted.colorAlignment == ColorAlignment(red: 12, blue: -30))
            // A preset carries it the same way.
            let preset = AdjustmentPreset(name: "Align", adjustments: source)
            #expect(preset.applied(onto: Adjustments()).needsAlignmentMeasurement)
        }
    }

    @Test("An unreadable original can't be measured")
    func unreadableOriginal() {
        let generator = PreviewGenerator(engine: ReferenceTests.engine)
        #expect(throws: ColorAlignmentMeasurement.Failure.unreadable) {
            try ColorAlignmentMeasurement.measure(source: URL(fileURLWithPath: "/nonexistent/photo.jpg"),
                                                  adjustments: Adjustments(), generator: generator)
        }
    }
}
