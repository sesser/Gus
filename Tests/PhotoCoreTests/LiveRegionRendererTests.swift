import CoreGraphics
import CoreImage
import Foundation
import PhotoFixtures
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

/// Live frames at 100%: the region of a full-resolution render
/// (docs/features/viewport-render-1to1/prd.md R1, R12, AC1).
@Suite("Live region renderer")
struct LiveRegionRendererTests {
    /// A typical stack (as `photobench edits`): exposure, tone, presence,
    /// curve, grading and sharpening.
    static var typical: Adjustments {
        var adjustments = Adjustments()
        adjustments.exposure.ev = 0.4
        adjustments.tone = Tone(contrast: 15, highlights: -30, shadows: 25, whites: 10, blacks: -5)
        adjustments.presence = Presence(clarity: 20, dehaze: 10, vibrance: 15, saturation: 5)
        adjustments.toneCurve[.rgb] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.3, y: 0.25), CurvePoint(x: 0.7, y: 0.78),
                                       CurvePoint(x: 1, y: 1)]
        adjustments.colorGrade.shadows = GradeWheel(hue: 210, amount: 20)
        adjustments.colorGrade.highlights = GradeWheel(hue: 40, amount: 15)
        adjustments.sharpen = Sharpen(amount: 40, radius: 1, detail: 25, masking: 20)
        return adjustments
    }

    /// `image`'s bytes, BGRA8 top to bottom, as `withUnsafeBytes` expects.
    static func bytes(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var out = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &out, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: RenderEngine.outputColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGImageByteOrderInfo.order32Little.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return out
    }

    /// The largest per-channel difference between the frame and the same
    /// area of the whole render, against `allowed(wholeValue)`, per channel.
    static func compare(frame: CGImage, whole: [UInt8], wholeWidth: Int, region: CGRect, allowed: (UInt8) -> Int)
        -> (worst: Int, mean: Double, over: Int, overValues: [Int]) {
        let frameBytes = bytes(frame)
        let x0 = Int(region.minX), y0 = Int(region.minY)
        var worst = 0
        var sum = 0
        var over = 0
        var overValues: [Int] = []
        for row in 0..<frame.height {
            for col in 0..<frame.width {
                let wholeOffset = (y0 + row) * wholeWidth * 4 + (x0 + col) * 4
                let frameOffset = row * frame.width * 4 + col * 4
                for channel in 0..<3 {
                    let wholeValue = whole[wholeOffset + channel]
                    let difference = abs(Int(wholeValue) - Int(frameBytes[frameOffset + channel]))
                    worst = max(worst, difference)
                    sum += difference
                    if difference > allowed(wholeValue) {
                        over += 1
                        if overValues.count < 8 { overValues.append(difference) }
                    }
                }
            }
        }
        return (worst, Double(sum) / Double(frame.width * frame.height * 3), over, overValues)
    }

    /// 8-bit steps a frame may differ from the full-resolution render,
    /// derived from the pipeline's formats (status.md, "R12 tolerance"): one
    /// half-float rounding of the master texture is an absolute error of at
    /// most 2⁻¹¹ for a neighbor whose value is up to white, multiplied by
    /// the stack's `gain` (what the stages after the texture do to a
    /// difference), and shows through the display curve's slope at this
    /// pixel's own level (the sRGB transfer of Display P3: 12.92 below
    /// linear 0.0031, then 0.44 × L^−0.583), times 255, rounded up, plus one
    /// step where 8-bit quantization tips over.
    static func allowedSteps(gain: Double, encoded value: UInt8) -> Int {
        let v = Double(value) / 255
        let linear = v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        let slope = linear <= 0.0031308 ? 12.92 : 1.055 / 2.4 * pow(linear, 1 / 2.4 - 1)
        return Int((0x1p-11 * gain * slope * 255).rounded(.up)) + 1
    }

    /// The photo as a lossless file the generator reads with ImageIO.
    static func writePNG(_ scene: TestScene, width: Int, height: Int, to url: URL) throws {
        guard let image = scene.image(width: width, height: height).cgImage(colorSpace: RenderEngine.outputColorSpace) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try SyntheticImages.write(image, to: url, type: .png)
    }

    /// What region to test, and with which geometry.
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var unit: CGRect
        var crop = Crop()
        var testDescription: String { name }
    }

    static let cases = [
        Case(name: "center, uncropped", unit: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)),
        Case(name: "corner, uncropped", unit: CGRect(x: 0, y: 0, width: 0.25, height: 0.25)),
        Case(name: "center, crop and straighten", unit: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
             crop: Crop(rect: CropRect(x: 0.1, y: 0.1, width: 0.7, height: 0.75), angle: 2)),
        Case(name: "corner, crop and straighten", unit: CGRect(x: 0, y: 0, width: 0.25, height: 0.25),
             crop: Crop(rect: CropRect(x: 0.1, y: 0.1, width: 0.7, height: 0.75), angle: 2)),
    ]

    /// The gain after the texture for the typical stack, in the order the
    /// renderer applies it: the most Exposure (2^ev), local tone and Dehaze
    /// multiply a difference (their tables' largest gains), Clarity and
    /// Sharpening enlarge it 1 + 2 × strength each, and the tone table by its
    /// largest relative slope x·y′/y (as `LiveSessionTests.gain`).
    static let typicalGain: Double = {
        let values = typical
        let tone = values.tone
        let local = LocalToneCurve(shadows: tone.shadows / 100, recovery: max(-tone.highlights, 0) / 100)
        let localTone = Double(local.gainTable().max() ?? 1)
        let dehaze = Double(DehazeTables(amount: values.presence.dehaze / 100).gain.max() ?? 1)
        let table = ToneTable(contrast: tone.contrast / 100, highlights: max(tone.highlights, 0) / 100, whites: tone.whites / 100,
                              blacks: tone.blacks / 100, curve: values.toneCurve).rgbTable()
        let step = ToneTable.domainMaximum / Double(table.count / 3 - 1)
        var slope = 1.0
        for i in 1..<(table.count / 3 - 1) {
            let x = Double(i) * step, y = Double(table[i * 3])
            let rise = Double(table[(i + 1) * 3] - table[(i - 1) * 3]) / (2 * step)
            if y > 0.01 { slope = max(slope, x * rise / y) }
        }
        return pow(2, values.exposure.ev) * localTone * dehaze * (1 + 2 * 0.6 * values.presence.clarity / 100)
            * slope * (1 + 2 * values.sharpen.amount / 100)
    }()

    /// AC1's scene with one-pixel detail, a PNG so the generator decodes it
    /// without loss, written once per run. AC1's 6000 × 4000 with
    /// LARGE_RENDER_TESTS=1, 3000 × 2000 otherwise, so the default suite
    /// keeps its speed; the tolerance does not depend on the size.
    static let sceneFile: URL = {
        let folder = FileManager.default.temporaryDirectory.appending(path: "region-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "scene.png")
        let large = ProcessInfo.processInfo.environment["LARGE_RENDER_TESTS"] != nil
        // `pixelGrid`: every pixel differs from its neighbors at any size, unlike
        // `edgeTarget`, whose finest lines scale with the image (code review C10).
        try? writePNG(.pixelGrid, width: large ? 6000 : 3000, height: large ? 4000 : 2000, to: url)
        return url
    }()

    /// AC1 (R1, R12): a region of a 24-megapixel scene with one-pixel detail
    /// and a typical stack is the same area of the full-resolution render,
    /// within `allowedSteps`, at the center and at a corner, with and
    /// without a crop and straightening.
    @Test("A region is the same area of the full-resolution render", arguments: cases)
    func regionMatchesFullRender(test: Case) async throws {
        var values = Self.typical
        values.crop = test.crop
        let url = Self.sceneFile
        let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "region-test"))
        let renderer = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
        try await renderer.prepare(values)
        let frame = try await renderer.render(values, unit: test.unit)
        let whole = try generator.cgImage(source: url, stack: values.editStack)
        #expect(frame.outputSize == CGSize(width: whole.width, height: whole.height))
        let expectedRegion = LiveRegionRenderer.region(of: test.unit, in: frame.outputSize)
        #expect(frame.region == expectedRegion)
        #expect(frame.image.cgImage.width == Int(expectedRegion.width))
        #expect(frame.image.cgImage.height == Int(expectedRegion.height))
        let result = Self.compare(frame: frame.image.cgImage, whole: Self.bytes(whole), wholeWidth: whole.width,
                                  region: expectedRegion) { Self.allowedSteps(gain: Self.typicalGain, encoded: $0) }
        Self.report(test.name, result, pixels: frame.image.cgImage.width * frame.image.cgImage.height)
        print("[gain] \(String(format: "%.2f", Self.typicalGain)), near white \(Self.allowedSteps(gain: Self.typicalGain, encoded: 255)) steps, "
              + "at black \(Self.allowedSteps(gain: Self.typicalGain, encoded: 1))")
        #expect(result.over == 0, "\(test.name): \(result.overValues)")
    }

    /// Reports the difference between `whole` and the frame; printed for
    /// `status.md`'s record of the R12 tolerance.
    static func report(_ name: String, _ result: (worst: Int, mean: Double, over: Int, overValues: [Int]), pixels: Int) {
        print("[\(name)] worst \(result.worst) steps, mean \(String(format: "%.3f", result.mean)), "
              + "over the tolerance: \(result.over) of \(pixels * 3) channel values \(result.overValues)")
    }

    @Test("One-pixel detail survives in the region frame (AC1)")
    func onePixelDetailSurvives() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "grid.png")
            // Every pixel differs from its neighbors: any enlargement or
            // resampling of the frame would average them away.
            try Self.writePNG(.pixelGrid, width: 512, height: 384, to: url)
            let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "region-test"))
            let renderer = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
            try await renderer.prepare(Adjustments())
            let frame = try await renderer.render(Adjustments(), unit: CGRect(x: 0, y: 0, width: 1, height: 1))
            let whole = try generator.cgImage(source: url, stack: .identity)
            let result = Self.compare(frame: frame.image.cgImage, whole: Self.bytes(whole), wholeWidth: whole.width,
                                      region: frame.region) { Self.allowedSteps(gain: 1, encoded: $0) }
            #expect(result.over == 0, "\(result.overValues)")
        }
    }

    /// AC5: Show Original at 100%: the region of the render with no
    /// adjustments equals the same area of the full-resolution render with none.
    @Test("Show Original's region is the unedited photo (AC5)")
    func originalMatchesFullRender() async throws {
        let url = Self.sceneFile
        let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "region-test"))
        let renderer = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
        try await renderer.prepare(Adjustments())
        let frame = try await renderer.render(Adjustments(), unit: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3))
        let whole = try generator.cgImage(source: url, stack: .identity)
        let result = Self.compare(frame: frame.image.cgImage, whole: Self.bytes(whole), wholeWidth: whole.width,
                                  region: frame.region) { Self.allowedSteps(gain: 1, encoded: $0) }
        Self.report("original", result, pixels: frame.image.cgImage.width * frame.image.cgImage.height)
        #expect(result.over == 0, "\(result.overValues)")
    }

    @Test("A raw region is the same area of the full-resolution render")
    func rawRegionMatchesFullRender() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "bench.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 2000, height: 1500, seed: 5))
            let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "region-test"))
            let renderer = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
            let values = Self.typical
            try await renderer.prepare(values)
            let frame = try await renderer.render(values, unit: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
            let whole = try generator.cgImage(source: url, stack: values.editStack)
            let result = Self.compare(frame: frame.image.cgImage, whole: Self.bytes(whole), wholeWidth: whole.width,
                                      region: frame.region) { Self.allowedSteps(gain: Self.typicalGain, encoded: $0) }
            Self.report("raw", result, pixels: frame.image.cgImage.width * frame.image.cgImage.height)
            #expect(result.over == 0, "\(result.overValues)")
        }
    }

    // MARK: Behavior

    @Test("A region wider than the frame is clipped, and rounded outward")
    func regionRounding() {
        let size = CGSize(width: 100, height: 80)
        #expect(LiveRegionRenderer.region(of: CGRect(x: 0.101, y: 0.201, width: 0.3, height: 0.4), in: size)
            == CGRect(x: 10, y: 16, width: 31, height: 33))
        #expect(LiveRegionRenderer.region(of: CGRect(x: -0.1, y: -0.2, width: 1.4, height: 1.5), in: size)
            == CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    @Test("Render needs a prepared base; a settings change needs a new decode")
    func notReadyUntilPrepared() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "bench.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 512, height: 512, seed: 2))
            let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "region-test"))
            let renderer = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
            var values = Adjustments()
            await #expect(throws: LiveRegionRenderer.Failure.notReady) {
                _ = try await renderer.render(values, unit: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            try await renderer.prepare(values)
            #expect(await renderer.isReady(for: values))
            #expect(await renderer.baseByteCount == 512 * 512 * 8)
            values.sharpen.amount = 50
            // Sharpening is not a decode setting.
            #expect(await renderer.isReady(for: values))
            values.whiteBalance = WhiteBalance(preset: .custom, temperature: 7000, tint: 0)
            #expect(await !renderer.isReady(for: values))
            await #expect(throws: LiveRegionRenderer.Failure.notReady) {
                _ = try await renderer.render(values, unit: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            await renderer.purge()
            #expect(await !renderer.isHoldingBase)
        }
    }

    @Test("A frame of the overlay is the photo with the mask drawn")
    func overlayFrame() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "photo.jpg")
            try SyntheticImages.writeJPEG(to: url, width: 800, height: 600, seed: 9)
            var values = Adjustments()
            values.local.masks = [GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.4, radiusY: 0.4))]) {
                $0.exposure = 1
            }]
            let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "region-test"))
            let renderer = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
            try await renderer.prepare(values)
            let id = values.local.masks[0].id
            let unit = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
            let plain = try await renderer.render(values, unit: unit)
            let overlaid = try await renderer.render(values, unit: unit, overlayMask: id)
            #expect(!plain.hasOverlay && overlaid.hasOverlay)
            #expect(Self.bytes(plain.image.cgImage) != Self.bytes(overlaid.image.cgImage))
        }
    }

    /// C3: the overlay on a frame is which mask's, not only whether there is one.
    @Test("An overlay frame says whose mask it draws (code review C3)")
    func overlayFollowsTheMask() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "photo.jpg")
            try SyntheticImages.writeJPEG(to: url, width: 800, height: 600, seed: 9)
            var values = Adjustments()
            values.local.masks = [
                GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: 0.3, y: 0.3), radiusX: 0.2, radiusY: 0.2))]) { $0.exposure = 1 },
                GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: 0.7, y: 0.7), radiusX: 0.2, radiusY: 0.2))]) { $0.exposure = 1 },
            ]
            // `GoldenCase.mask` gives every mask the same id.
            for index in values.local.masks.indices { values.local.masks[index].id = UUID() }
            let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "region-test"))
            let renderer = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
            try await renderer.prepare(values)
            let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
            let first = try await renderer.render(values, unit: unit, overlayMask: values.local.masks[0].id)
            let second = try await renderer.render(values, unit: unit, overlayMask: values.local.masks[1].id)
            #expect(first.overlayMask == values.local.masks[0].id && second.overlayMask == values.local.masks[1].id)
            #expect(!LiveFrameRules.isCurrent(frameValues: first.adjustments, frameOverlay: first.overlayMask,
                                              wanted: values, overlay: values.local.masks[1].id))
            #expect(LiveFrameRules.isCurrent(frameValues: second.adjustments, frameOverlay: second.overlayMask,
                                             wanted: values, overlay: values.local.masks[1].id))
            #expect(Self.bytes(first.image.cgImage) != Self.bytes(second.image.cgImage))
        }
    }

    /// C4: a moving frame starts a decode once its settings have stopped
    /// changing, so one decode lands and the rest of the drag is sharp;
    /// a control that changes the decode every frame waits for the pause (R4).
    @Test("A moving frame decodes only once its settings stop changing (code review C4)")
    func decodeWhileMoving() async throws {
        let renderer = LiveRegionRenderer(source: URL(fileURLWithPath: "/nonexistent/photo.dng"), generator: PreviewGenerator(), colorSpace: nil)
        var values = Adjustments()
        // Highlights below 0 changes the settings once: extended range.
        values.tone.highlights = -5
        #expect(await !renderer.isDecodingOrHolding(values))
        #expect(await !renderer.shouldDecode(whileMoving: values))
        values.tone.highlights = -10
        #expect(await renderer.shouldDecode(whileMoving: values))
        // White balance changes them on every frame: never settled while it moves.
        var moving = Adjustments()
        for temperature in stride(from: 4000.0, through: 4080, by: 20) {
            moving.whiteBalance = WhiteBalance(preset: .custom, temperature: temperature, tint: 0)
            #expect(await !renderer.shouldDecode(whileMoving: moving))
        }
    }

    /// C2: a whole frame of other values never replaces a tile that is still
    /// the picture, and the editor takes the tile down itself when it can't be.
    @Test("A whole frame goes on the base under a tile only with the same values (code review C2)")
    func wholeFramesUnderATile() {
        var tile = Adjustments()
        tile.sharpen.amount = 40
        var whole = tile
        whole.sharpen.amount = 42
        #expect(LiveFrameRules.wholeFrameGoesOnBase(wholeValues: whole, tileValues: nil))
        #expect(!LiveFrameRules.wholeFrameGoesOnBase(wholeValues: whole, tileValues: tile))
        #expect(LiveFrameRules.wholeFrameGoesOnBase(wholeValues: tile, tileValues: tile))
    }

    /// Letting go at 100%: a frame of the saved values leaves the decode for after
    /// the full rendition, but a held control, the overlay, Show Original and a
    /// hover preview still need their sharp frame.
    @Test("Only a settled frame of the saved values leaves the decode for later")
    func decodeWaitsForTheFullRendition() {
        let wait = LiveFrameRules.decodeWaitsForFullRendition(valuesAreSaved:isChanging:hasOverlay:showsOriginal:isPreviewing:)
        #expect(wait(true, false, false, false, false))
        #expect(!wait(false, false, false, false, false))
        #expect(!wait(true, true, false, false, false))
        #expect(!wait(true, false, true, false, false))
        #expect(!wait(true, false, false, true, false))
        #expect(!wait(true, false, false, false, true))
    }

    /// C5/F3: real pixels and what keeps its shipped filtering enlarge with
    /// nearest-neighbor at 100% and above; anything soft enlarges smoothly.
    @Test("Nearest-neighbor only for real pixels and the shipped maps (code review C5)")
    func nearestFiltering() {
        #expect(LiveFrameRules.usesNearestFiltering(magnification: 2, showsRealPixels: true, keepsShippedFiltering: false))
        #expect(LiveFrameRules.usesNearestFiltering(magnification: 4, showsRealPixels: false, keepsShippedFiltering: true))
        #expect(!LiveFrameRules.usesNearestFiltering(magnification: 2, showsRealPixels: false, keepsShippedFiltering: false))
        #expect(!LiveFrameRules.usesNearestFiltering(magnification: 0.8, showsRealPixels: true, keepsShippedFiltering: true))
    }

    @Test("A cancelled render makes no frame")
    func cancellation() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "photo.jpg")
            try SyntheticImages.writeJPEG(to: url, width: 400, height: 300, seed: 3)
            let renderer = LiveRegionRenderer(source: url, generator: PreviewGenerator(), colorSpace: nil)
            try await renderer.prepare(Adjustments())
            let token = RenderCancellation()
            token.cancel()
            await #expect(throws: CancellationError.self) {
                _ = try await renderer.render(Adjustments(), unit: CGRect(x: 0, y: 0, width: 1, height: 1), cancellation: token)
            }
        }
    }
}
