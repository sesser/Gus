import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// One module rendered over one scene with representative values.
struct GoldenCase: Sendable, CustomTestStringConvertible {
    var name: String
    var scene: TestScene
    var adjustments: Adjustments

    var testDescription: String { name }

    init(_ name: String, _ scene: TestScene, _ edit: (inout Adjustments) -> Void) {
        self.name = name
        self.scene = scene
        var adjustments = Adjustments()
        edit(&adjustments)
        self.adjustments = adjustments
    }

    /// Built-in look-up tables are installed here on first use.
    static let lookTables = LookTableStore(directory: FileManager.default.temporaryDirectory
        .appending(path: "golden-look-tables-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory))

    /// The identifier of the built-in table `key` (`BuiltInLookTables`).
    static func builtInTable(_ key: String) -> String {
        BuiltInLookTables.all.first { $0.key == key }?.identifier ?? ""
    }

    func render() -> CIImage {
        AdjustmentRenderer(lookTables: Self.lookTables).render(adjustments, to: scene.image().ciImage,
                                                              context: RenderContext())
    }
}

/// Settings the RAW decoder applies, over the synthetic Bayer DNG
/// (`SyntheticDNG`, seed 7). Decoded at full size through `PreviewGenerator`,
/// as previews and exports are. 320 × 240, not the scenes' 256 × 192: the
/// decoder returns an empty image for that DNG (and for 258 × 194), while
/// 300 × 200 and larger decode.
struct RAWGoldenCase: Sendable, CustomTestStringConvertible {
    var name: String
    var adjustments: Adjustments

    var testDescription: String { name }

    init(_ name: String, _ edit: (inout Adjustments) -> Void) {
        self.name = name
        var adjustments = Adjustments()
        edit(&adjustments)
        self.adjustments = adjustments
    }

    static let master: URL = {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "golden-bayer-\(ProcessInfo.processInfo.processIdentifier).dng", directoryHint: .notDirectory)
        try? SyntheticDNG.write(to: url, options: .init(width: 320, height: 240, seed: 7))
        return url
    }()

    func render() throws -> CIImage {
        try PreviewGenerator(engine: Goldens.engine).image(source: Self.master, stack: adjustments.editStack,
                                                           longEdge: nil)
    }
}

/// Characterization goldens: today's rendering of every adjustment module,
/// pinned so that a change shows up. They make no claim that the rendering
/// is right; the CPU references in `ReferenceTests` do that, module by module.
@Suite("Goldens")
struct GoldenTests {
    /// The machine that made the goldens reproduces them bit for bit. Two Metal
    /// contexts with different priorities on the same Mac differed by up to
    /// 0.0005 (dehaze, whose airlight is a reduction), so the tolerance is four
    /// times that, for another GPU or macOS release. It stays under one 8-bit
    /// step (1/255 ≈ 0.0039) and far under a visible OkLab difference (about
    /// 0.02), so a change to a module's math or constants still fails.
    static let tolerance = GoldenTolerance(
        maxChannel: 0.002, minimumPSNR: 60, meanDeltaE: 0.0005, maxDeltaE: 0.004,
        reason: "GPU floating-point noise between Macs or macOS releases only")

    static let cases: [GoldenCase] = [
        GoldenCase("exposure-minus1-grayRamp", .grayRamp) { $0.exposure.ev = -1 },
        GoldenCase("exposure-plus1-hueRamp", .hueRamp) { $0.exposure.ev = 1 },
        GoldenCase("exposure-plus0.5-patchChart", .patchChart) { $0.exposure.ev = 0.5 },

        GoldenCase("whiteBalance-warmer-patchChart", .patchChart) { $0.whiteBalance.relativeTemperature = 50 },
        GoldenCase("whiteBalance-magenta-patchChart", .patchChart) { $0.whiteBalance.relativeTint = 40 },
        GoldenCase("whiteBalance-coolerGreener-hazyLandscape", .hazyLandscape) {
            $0.whiteBalance.relativeTemperature = -40
            $0.whiteBalance.relativeTint = -30
        },

        GoldenCase("tone-contrast-grayRamp", .grayRamp) { $0.tone.contrast = 50 },
        GoldenCase("tone-lessContrast-patchChart", .patchChart) { $0.tone.contrast = -40 },
        GoldenCase("tone-recoverHighlights-grayRamp", .grayRamp) { $0.tone.highlights = -70 },
        GoldenCase("tone-brighterHighlights-hazyLandscape", .hazyLandscape) { $0.tone.highlights = 40 },
        GoldenCase("tone-shadows-hazyLandscape", .hazyLandscape) { $0.tone.shadows = 60 },
        GoldenCase("tone-whitesBlacks-grayRamp", .grayRamp) {
            $0.tone.whites = 40
            $0.tone.blacks = -30
        },

        GoldenCase("clarity-plus60-edgeTarget", .edgeTarget) { $0.presence.clarity = 60 },
        GoldenCase("clarity-minus40-hazyLandscape", .hazyLandscape) { $0.presence.clarity = -40 },
        GoldenCase("dehaze-plus60-hazyLandscape", .hazyLandscape) { $0.presence.dehaze = 60 },
        GoldenCase("dehaze-minus40-hazyLandscape", .hazyLandscape) { $0.presence.dehaze = -40 },
        GoldenCase("vibrance-plus60-hueRamp", .hueRamp) { $0.presence.vibrance = 60 },
        GoldenCase("vibrance-minus50-patchChart", .patchChart) { $0.presence.vibrance = -50 },
        GoldenCase("saturation-minus50-hueRamp", .hueRamp) { $0.presence.saturation = -50 },
        GoldenCase("saturation-plus40-patchChart", .patchChart) { $0.presence.saturation = 40 },

        GoldenCase("toneCurve-sCurve-grayRamp", .grayRamp) {
            $0.toneCurve.rgb = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.18),
                                CurvePoint(x: 0.75, y: 0.85), CurvePoint(x: 1, y: 1)]
        },
        GoldenCase("toneCurve-red-patchChart", .patchChart) {
            $0.toneCurve.red = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.6), CurvePoint(x: 1, y: 1)]
            $0.toneCurve.blue = [CurvePoint(x: 0, y: 0.08), CurvePoint(x: 1, y: 0.92)]
        },

        GoldenCase("colorMixer-hueRamp", .hueRamp) {
            $0.colorMixer[.orange] = ColorMixer.Shift(hue: 40)
            $0.colorMixer[.blue] = ColorMixer.Shift(saturation: -60)
            $0.colorMixer[.green] = ColorMixer.Shift(luminance: 50)
        },
        GoldenCase("colorMixer-patchChart", .patchChart) {
            $0.colorMixer[.red] = ColorMixer.Shift(hue: -30, saturation: 30, luminance: -20)
            $0.colorMixer[.aqua] = ColorMixer.Shift(hue: 50, saturation: 40)
        },

        GoldenCase("colorGrade-splitTone-grayRamp", .grayRamp) {
            $0.colorGrade.shadows = GradeWheel(hue: 200, amount: 40)
            $0.colorGrade.highlights = GradeWheel(hue: 40, amount: 30)
        },
        GoldenCase("colorGrade-midtones-patchChart", .patchChart) {
            $0.colorGrade.midtones = GradeWheel(hue: 300, amount: 25, luminance: 20)
            $0.colorGrade.balance = 30
            $0.colorGrade.blending = 70
        },

        GoldenCase("vignette-dark-hazyLandscape", .hazyLandscape) { $0.vignette.amount = -60 },
        GoldenCase("vignette-lightRound-patchChart", .patchChart) {
            $0.vignette = Vignette(amount: 40, size: 30, roundness: 100)
        },
        GoldenCase("vignette-rectangle-grayRamp", .grayRamp) {
            $0.vignette = Vignette(amount: -80, size: 70, roundness: -100)
        },

        GoldenCase("sharpen-default-edgeTarget", .edgeTarget) { $0.sharpen.amount = 100 },
        GoldenCase("sharpen-detailMasking-edgeTarget", .edgeTarget) {
            $0.sharpen = Sharpen(amount: 120, radius: 1.5, detail: 80, masking: 60)
        },

        // Grain's noise comes from CIRandomGenerator, which is a fixed pattern:
        // renders repeat exactly (`GoldenHarnessTests.rendersAreRepeatable`).
        GoldenCase("grain-default-grayRamp", .grayRamp) { $0.grain.strength = 100 },
        GoldenCase("grain-coarseColor-patchChart", .patchChart) {
            $0.grain = Grain(strength: 150, roughness: 20, color: 80, size: 3)
        },

        GoldenCase("lookTable-tealOrange-hueRamp", .hueRamp) {
            $0.lookTable = LookTable(identifier: GoldenCase.builtInTable("tealOrange"))
        },
        GoldenCase("lookTable-fadeHalf-patchChart", .patchChart) {
            $0.lookTable = LookTable(identifier: GoldenCase.builtInTable("fade"), intensity: 50)
        },
        GoldenCase("lookTable-crossProcessProPhoto-grayRamp", .grayRamp) {
            $0.lookTable = LookTable(identifier: GoldenCase.builtInTable("crossProcess"), colorSpace: .proPhoto)
        },

        // Files that are not RAW: Core Image's noise reduction (`CoreImageDenoiser`).
        GoldenCase("noiseReduction-60-hazyLandscape", .hazyLandscape) { $0.noiseReduction.luminance = 60 },
        GoldenCase("noiseReduction-100-edgeTarget", .edgeTarget) { $0.noiseReduction.luminance = 100 },

        GoldenCase("crop-straighten-patchChart", .patchChart) {
            $0.crop = Crop(rect: CropRect(x: 0.1, y: 0.1, width: 0.8, height: 0.75), angle: 5)
        },
        GoldenCase("crop-turnStraighten-edgeTarget", .edgeTarget) {
            $0.crop = Crop(rect: CropRect(x: 0.05, y: 0.2, width: 0.9, height: 0.6), quarterTurns: 1, angle: -3)
        },
    ]

    /// The decoder's own settings: Kelvin white balance, the base look (its
    /// boost), extended range (asked for by negative exposure), and its noise
    /// reduction. Not covered: `decoderVersion` (the versions offered depend on
    /// the macOS release) and the whole-sensor decode (`CameraFrame`, which
    /// only Olympus, OM System and Panasonic files have).
    static let rawCases: [RAWGoldenCase] = [
        RAWGoldenCase("raw-asShot") { _ in },
        RAWGoldenCase("raw-kelvin3200") { $0.whiteBalance = WhiteBalance(preset: .custom, temperature: 3200, tint: 0) },
        RAWGoldenCase("raw-kelvin8000-tint30") {
            $0.whiteBalance = WhiteBalance(preset: .custom, temperature: 8000, tint: 30)
        },
        RAWGoldenCase("raw-tungstenPreset") { $0.whiteBalance = .raw(.tungsten) },
        RAWGoldenCase("raw-lookFlat") { $0.decode.look = .flat },
        RAWGoldenCase("raw-lookNeutral") { $0.decode.look = .neutral },
        RAWGoldenCase("raw-extendedRange-exposureMinus1") { $0.exposure.ev = -1 },
        RAWGoldenCase("raw-noiseReduction") { $0.noiseReduction = NoiseReduction(luminance: 80, color: 80) },
    ]

    @Test("Module renders match their goldens", arguments: cases)
    func moduleMatchesGolden(_ golden: GoldenCase) throws {
        try Goldens.check(golden.name, golden.render(), tolerance: Self.tolerance)
    }

    @Test("RAW decode settings match their goldens", arguments: rawCases)
    func rawDecodeMatchesGolden(_ golden: RAWGoldenCase) throws {
        try Goldens.check(golden.name, golden.render(), tolerance: Self.tolerance)
    }

    /// A setting the decoder ignored would pin the as-shot render under another
    /// name: each case must change the image.
    @Test("Every RAW decode setting changes the decode")
    func rawSettingsTakeEffect() throws {
        let engine = Goldens.engine
        let asShot = try EncodedImage(rendering: Self.rawCases[0].render(), engine: engine)
        for golden in Self.rawCases.dropFirst() {
            let rendered = try EncodedImage(rendering: golden.render(), engine: engine)
            #expect(rendered != asShot, "\(golden.name) renders as shot")
        }
    }
}
