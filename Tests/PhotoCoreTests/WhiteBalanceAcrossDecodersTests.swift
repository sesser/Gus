import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// White balance and the baseline look across the two raw decoders (issue
/// #170): the acceptance criteria that can be checked without a camera's
/// file, on synthetic DNGs. The 256 x 192 one is decoded by LibRaw on macOS
/// 27.2.1 (the system decoder gives no image for it) and the 1536 x 1152 one
/// by the system decoder; where a test needs LibRaw whatever the macOS, it
/// calls `LibRawDecoder` itself. A camera's own files: `LibRawAgainstSystemTests`
/// (AC5, AC6) and `LibRawFallbackTests`.
@Suite("White balance across decoders")
struct WhiteBalanceAcrossDecodersTests {
    static let generator = PreviewGenerator(engine: ReferenceTests.engine)

    /// A raw LibRaw decodes here, with a camera's matrix and a neutral that is not 1, 1, 1.
    static func libRawDNG(in folder: URL, _ name: String = "libraw", color: SyntheticDNG.Color = CameraColorTests.Kind.single.tags,
                          mosaic: Data? = nil) throws -> URL {
        let url = folder.appending(path: "\(name).dng")
        try SyntheticDNG.write(to: url, options: .init(width: 256, height: 192, seed: 7, color: color), mosaic: mosaic)
        return url
    }

    /// A raw the system decoder reads here.
    static func systemDNG(in folder: URL) throws -> URL {
        try LibRawDecoderTests.dng(in: folder, "system", width: 1536, height: 1152)
    }

    static func jpeg(in folder: URL) throws -> URL {
        let url = folder.appending(path: "photo.jpg")
        try SyntheticImages.writeJPEG(to: url, width: 320, height: 240, seed: 5)
        return url
    }

    /// A render through the whole pipeline, as its pixels.
    static func pixels(_ url: URL, _ values: Adjustments, longEdge: Int = 200) throws -> Data {
        let image = try generator.cgImage(source: url, stack: values.editStack, longEdge: longEdge)
        return try #require(image.dataProvider?.data as Data?)
    }

    /// Mean red over mean blue of a render in the working space: higher is a warmer picture.
    static func warmth(_ url: URL, _ values: Adjustments) throws -> Double {
        let image = try generator.image(source: url, stack: values.editStack, longEdge: 200)
        let means = LibRawFallbackPipelineTests.means(image)
        return means.x / means.z
    }

    static func balanced(_ balance: WhiteBalance) -> Adjustments {
        var values = Adjustments()
        values.whiteBalance = balance
        return values
    }

    static func controls(for url: URL) -> WhiteBalanceControls {
        // As the editor loads them: the system decoder's defaults, else LibRaw's read of the header.
        let defaults = RawDefaults(source: url)
        let isRaw = SupportedFormats.isRaw(pathExtension: url.pathExtension)
        let fallback = isRaw && defaults == nil
        return WhiteBalanceControls(systemDefaults: defaults, usesFallbackDecoder: fallback,
                                    fallbackColor: fallback ? LibRawDecoder.cameraColor(url) : nil)
    }

    // MARK: The mode shown (design §5)

    /// The designer's six cases, and the rest of the rule.
    @Test("The white balance mode shown for a raw is the stored one with Kelvin values or a named light, Custom when chosen, else As Shot")
    func kelvinModeShown() {
        // 1. A stored Tungsten shows Tungsten.
        #expect(WhiteBalance.raw(.tungsten).kelvinDisplayPreset == .tungsten)
        // 2. Custom with Kelvin values shows Custom.
        #expect(WhiteBalance(preset: .custom, temperature: 4200, tint: 12).kelvinDisplayPreset == .custom)
        // 3. Custom at 0 / 0 with no Kelvin values shows Custom: chosen from the pop-up, it sticks.
        #expect(WhiteBalance(preset: .custom).kelvinDisplayPreset == .custom)
        // 4. Custom with relative 60 / 30 (a build that gave LibRaw's photos relative values) shows As Shot (AC10).
        #expect(WhiteBalance(preset: .custom, relativeTemperature: 60, relativeTint: 30).kelvinDisplayPreset == .asShot)
        // 5. A relative Auto shows As Shot.
        #expect(WhiteBalance(preset: .auto, relativeTemperature: 16, relativeTint: -22).kelvinDisplayPreset == .asShot)
        #expect(WhiteBalance(preset: .auto).kelvinDisplayPreset == .asShot)
        // 6. As Shot shows As Shot.
        #expect(WhiteBalance().kelvinDisplayPreset == .asShot)

        // Every mode this build writes on a raw shows as itself.
        for preset in WhiteBalance.Preset.allCases where preset != .auto {
            #expect(WhiteBalance.raw(preset).kelvinDisplayPreset == preset, "\(preset)")
        }
        #expect(WhiteBalance(preset: .auto, temperature: 5886, tint: 7).kelvinDisplayPreset == .auto)
        // One Kelvin value is enough; leftover relative values beside Kelvin values change nothing (RI-W1).
        #expect(WhiteBalance(preset: .custom, tint: 10).kelvinDisplayPreset == .custom)
        #expect(WhiteBalance(preset: .custom, temperature: 5000, tint: 0, relativeTemperature: 60).kelvinDisplayPreset == .custom)
        #expect(WhiteBalance(preset: .daylight, temperature: 5500, tint: 0, relativeTint: 30).kelvinDisplayPreset == .daylight)
        // A single relative value is enough for As Shot.
        #expect(WhiteBalance(preset: .custom, relativeTint: -5).kelvinDisplayPreset == .asShot)
        // Display only: the stack keeps what it held.
        let stored = WhiteBalance(preset: .custom, relativeTemperature: 60, relativeTint: 30)
        _ = stored.kelvinDisplayPreset
        #expect(stored.preset == .custom && stored.relativeTemperature == 60 && stored.relativeTint == 30)
        // What shows As Shot renders as shot: no Kelvin reaches the decode.
        for balance in [stored, WhiteBalance(preset: .auto, relativeTemperature: 16), WhiteBalance()] {
            let settings = Self.balanced(balance).decodeSettings
            #expect(settings.temperature == nil && settings.tint == nil)
        }
    }

    // MARK: The White Balance group's model (AC1, AC10, AC14)

    @Test("A raw LibRaw decodes is offered the nine modes with Kelvin and tint, and Tungsten is 2850 K, tint 0 (AC1)")
    func libRawPhotoHasARawsWhiteBalance() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.libRawDNG(in: folder)
            let systemReads = SystemRAWDecoder.reads(url)
            if systemReads { print("WhiteBalanceAcrossDecodersTests: the system RAW decoder reads the 256 x 192 DNG here") }
            let controls = Self.controls(for: url)
            let asShot = try #require(controls.asShot, "no Kelvin white balance for a raw")
            // A believable light for As Shot (R4): this neutral is daylight to the camera's matrix.
            #expect((4500...7000).contains(asShot.kelvin) && abs(asShot.tint) < 40, "\(asShot)")
            if !systemReads {
                // It is the color step's own as-shot value, read from the header alone.
                #expect(try LibRawDecoder.decode(url).step.asShot == asShot)
            }
            guard case .offered(let modes, let selected) = controls.mode(for: WhiteBalance()) else {
                Issue.record("the Mode pop-up is not offered")
                return
            }
            #expect(modes == [.asShot, .auto, .daylight, .cloudy, .shade, .tungsten, .fluorescent, .flash, .custom])
            #expect(selected == .asShot)
            // Choosing Tungsten stores 2850 K, tint 0, shows Tungsten and changes the render.
            let tungsten = try #require(controls.picking(.tungsten, from: WhiteBalance()))
            #expect(tungsten == WhiteBalance(preset: .tungsten, temperature: 2850, tint: 0))
            #expect(controls.mode(for: tungsten) == .offered(modes, selected: .tungsten))
            #expect(try Self.pixels(url, Self.balanced(tungsten)) != (try Self.pixels(url, .none)))
            // Tungsten light is warmer than this photo's: the picture is rendered bluer.
            #expect(try Self.warmth(url, Self.balanced(tungsten)) < (try Self.warmth(url, .none)) * 0.8)
            // As Shot clears the white balance; Custom stores the numbers shown and sticks
            // (`customStoresTheNumbersShown`); Auto measures.
            #expect(controls.picking(.asShot, from: tungsten) == WhiteBalance())
            let custom = try #require(controls.picking(.custom, from: WhiteBalance()))
            #expect(custom == WhiteBalance(preset: .custom, temperature: asShot.kelvin, tint: asShot.tint))
            #expect(controls.mode(for: custom) == .offered(modes, selected: .custom))
            #expect(controls.picking(.auto, from: WhiteBalance()) == nil)
            // Every named light source means the same Kelvin and tint as on any raw (R2).
            for preset in [WhiteBalance.Preset.daylight, .cloudy, .shade, .tungsten, .fluorescent, .flash] {
                let neutral = try #require(preset.neutral)
                #expect(controls.picking(preset, from: WhiteBalance())
                    == WhiteBalance(preset: preset, temperature: neutral.temperature, tint: neutral.tint))
            }
        }
    }

    @Test("A file that is not a raw keeps three modes and relative values")
    func renderedImageKeepsRelativeWhiteBalance() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let controls = Self.controls(for: try Self.jpeg(in: folder))
            #expect(controls == .relative && controls.asShot == nil)
            #expect(controls.mode(for: WhiteBalance()) == .offered([.asShot, .auto, .custom], selected: .asShot))
            // A pasted Daylight is not among its modes and renders as shot (#161's D5).
            #expect(controls.mode(for: .raw(.daylight)) == .offered([.asShot, .auto, .custom], selected: .asShot))
            #expect(controls.picking(.daylight, from: WhiteBalance()) == nil)
            #expect(controls.picking(.custom, from: WhiteBalance()) == WhiteBalance(preset: .custom))
            #expect(controls.picking(.asShot, from: WhiteBalance(preset: .custom, relativeTemperature: 20)) == WhiteBalance())
        }
    }

    /// AC14: LibRaw reads the file, but it has no color matrix (or no
    /// as-shot neutral), so there is no white point to work from.
    @Test("A raw without usable color data renders as shot at the baseline, and white balance is unavailable (AC14)",
          arguments: ["no matrix", "no neutral"])
    func unusableColorData(what: String) async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let tags = what == "no matrix" ? SyntheticDNG.Color(matrix1: nil)
                                           : SyntheticDNG.Color(matrix1: SyntheticDNG.Color.sRGBMatrix, asShotNeutral: nil)
            let url = try Self.libRawDNG(in: folder, "colorless", color: tags)
            #expect(LibRawDecoder.cameraColor(url) == nil)
            let output = try LibRawDecoder.decode(url)
            #expect(output.step.color == nil && output.step.asShot == nil)
            // The baseline look and nothing else: no white balance, no matrix.
            let transform = output.step.transform(temperature: 2500, tint: 40)
            #expect(transform == output.step.transform(temperature: nil, tint: nil))
            #expect(transform.gain == nil && transform.matrix == nil)
            #expect(transform.exposure == pow(2, BaselineLook.exposure) && transform.toneCurve == BaselineLook.toneCurve)
            let asShot = ReferenceTests.renderLinear(output.image()).pixels
            #expect(ReferenceTests.renderLinear(output.image(whiteBalance: ColorTemperature(kelvin: 2500, tint: 40))).pixels == asShot)
            #expect(ReferenceTests.renderLinear(output.linear).pixels != asShot)
            #expect(!asShot.contains { !$0.isFinite })

            // The Adjust tab: a dimmed Mode pop-up on As Shot when nothing is stored (W1) …
            let fallback = !SystemRAWDecoder.reads(url)
            let controls = WhiteBalanceControls(systemDefaults: nil, usesFallbackDecoder: true, fallbackColor: LibRawDecoder.cameraColor(url))
            #expect(controls == .unavailable && controls.asShot == nil)
            #expect(controls.mode(for: WhiteBalance()) == .unavailable)
            #expect(controls.picking(.daylight, from: WhiteBalance()) == nil)
            #expect(controls.picking(.auto, from: WhiteBalance()) == nil)
            // … and, when a white balance was pasted or came from a preset, that mode and As Shot (W2).
            let pasted = WhiteBalance.raw(.daylight)
            #expect(controls.mode(for: pasted) == .notApplied(stored: .daylight))
            #expect(controls.mode(for: WhiteBalance(preset: .custom, temperature: 4000, tint: 3)) == .notApplied(stored: .custom))
            #expect(controls.picking(.daylight, from: pasted) == nil)
            #expect(controls.picking(.custom, from: pasted) == nil)
            #expect(controls.picking(.asShot, from: pasted) == WhiteBalance())
            // Relative values left by an earlier build are As Shot here too.
            #expect(controls.mode(for: WhiteBalance(preset: .custom, relativeTemperature: 60)) == .unavailable)

            guard fallback else { return }
            #expect(Self.controls(for: url) == .unavailable)
            // Through the pipeline: the stored white balance changes nothing, of either kind, and nothing fails.
            let plain = try Self.pixels(url, .none)
            #expect(try Self.pixels(url, Self.balanced(pasted)) == plain)
            #expect(try Self.pixels(url, Self.balanced(WhiteBalance(preset: .custom, relativeTemperature: 60, relativeTint: 30))) == plain)
            // The rest of the stack still renders.
            var brighter = Adjustments()
            brighter.exposure.ev = 1
            #expect(try Self.pixels(url, brighter) != plain)
            // Auto has nothing to measure and stores nothing.
            #expect(throws: AutoAdjuster.Failure.whiteBalanceUnavailable) {
                _ = try AutoAdjuster(generator: Self.generator).whiteBalance(source: url, adjustments: .none)
            }
        }
    }

    // MARK: Custom (design §17.1)

    /// The designer's ruling on DQ-1: Custom means "these numbers". On a
    /// raw by either decoder it stores the Kelvin and tint the sliders show.
    @Test("Choosing Custom on a raw stores the Kelvin and tint it shows; on other files Custom alone")
    func customStoresTheNumbersShown() async throws {
        let asShot = ColorTemperature(kelvin: 5318.442815396026, tint: 1.740704475662509)
        let raw = WhiteBalanceControls.kelvin(asShot: asShot)
        // From As Shot: the as-shot Kelvin and tint, unrounded, so each slider stays on its default.
        #expect(raw.picking(.custom, from: WhiteBalance())
            == WhiteBalance(preset: .custom, temperature: 5318.442815396026, tint: 1.740704475662509))
        // From Tungsten: its 2850 K and 0 are kept.
        #expect(raw.picking(.custom, from: .raw(.tungsten)) == WhiteBalance(preset: .custom, temperature: 2850, tint: 0))
        // A Kelvin stored without a tint (`photocli --set`) gets the as-shot tint, as the sliders show it; and the reverse.
        #expect(raw.picking(.custom, from: WhiteBalance(preset: .asShot, temperature: 4100))
            == WhiteBalance(preset: .custom, temperature: 4100, tint: 1.740704475662509))
        #expect(raw.picking(.custom, from: WhiteBalance(preset: .auto, tint: -8))
            == WhiteBalance(preset: .custom, temperature: 5318.442815396026, tint: -8))
        // Relative values are left as stored; a Custom stored without numbers by an earlier build gets them.
        #expect(raw.picking(.custom, from: WhiteBalance(preset: .custom, relativeTemperature: 60, relativeTint: 30))
            == WhiteBalance(preset: .custom, temperature: asShot.kelvin, tint: asShot.tint, relativeTemperature: 60, relativeTint: 30))
        // A Custom that holds both numbers is what it was: nothing to record.
        let held = WhiteBalance(preset: .custom, temperature: 4000, tint: 12)
        #expect(raw.picking(.custom, from: held) == held)
        // Every result shows Custom.
        for stored in [WhiteBalance(), .raw(.shade), WhiteBalance(preset: .auto, relativeTemperature: 16)] {
            #expect(raw.picking(.custom, from: stored)?.kelvinDisplayPreset == .custom)
        }
        // A file that is not a raw: Custom alone, beside what is stored (#161's D5).
        #expect(WhiteBalanceControls.relative.picking(.custom, from: WhiteBalance()) == WhiteBalance(preset: .custom))
        #expect(WhiteBalanceControls.relative.picking(.custom, from: WhiteBalance(relativeTemperature: 20))
            == WhiteBalance(preset: .custom, relativeTemperature: 20))
        // A raw without color data: nothing.
        #expect(WhiteBalanceControls.unavailable.picking(.custom, from: WhiteBalance()) == nil)
        #expect(WhiteBalanceControls.unavailable.picking(.custom, from: .raw(.daylight)) == nil)

        // On files: the stored numbers are the as-shot ones, and the photo does not visibly change.
        try await RepositoryFiles.withTemporaryDirectory { folder in
            for url in [try Self.libRawDNG(in: folder), try Self.systemDNG(in: folder)] {
                let controls = Self.controls(for: url)
                guard let shown = controls.asShot else { continue }
                let custom = try #require(controls.picking(.custom, from: WhiteBalance()))
                #expect(custom.temperature == shown.kelvin && custom.tint == shown.tint)
                // As shot renders the camera's own neutral, Custom the same light as numbers: equal to
                // within rounding (a level of 255 here and there), not always to the byte.
                let before = try Self.pixels(url, .none), after = try Self.pixels(url, Self.balanced(custom))
                #expect(before.count == after.count)
                let largest = zip(before, after).map { abs(Int($0) - Int($1)) }.max() ?? 0
                #expect(largest <= 1, "\(url.lastPathComponent): a sample moved by \(largest) of 255")
                // Pasted onto another photo, Custom carries its numbers.
                #expect(Adjustments().replacing([.whiteBalance], from: Self.balanced(custom)).decodeSettings.temperature
                    == Float(shown.kelvin))
            }
        }
    }

    /// The color step keeps a Kelvin within 2000 to 50000 and a tint
    /// within ±150, the sliders' ranges. A camera's own white outside them
    /// (candle light here) is shown and stored at the range's end, so the
    /// sliders, Custom and the render are one number; As Shot itself still
    /// renders the camera's neutral. Picking Custom on such a photo changes
    /// it, to the number the slider shows.
    @Test("An as-shot white beyond the sliders' ranges is shown, stored and rendered at the range's end",
          arguments: [ColorTemperature(kelvin: 1750, tint: 0), ColorTemperature(kelvin: 5200, tint: 190)])
    func asShotBeyondTheRanges(light: ColorTemperature) async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            // The neutral this camera records for that light, as the file's as-shot neutral.
            let camera = CameraColorTests.Kind.single.color
            let neutral = try #require(camera.neutral(for: light.chromaticity))
            var tags = CameraColorTests.Kind.single.tags
            tags.asShotNeutral = [neutral.x, neutral.y, neutral.z]
            let url = try Self.libRawDNG(in: folder, "beyond", color: tags)
            let color = try #require(LibRawDecoder.cameraColor(url))
            let own = try #require(color.asShot)
            // The premise: the camera's own white is outside a range (to the file's four decimals).
            #expect(abs(own.kelvin / light.kelvin - 1) < 0.02 && abs(own.tint - light.tint) < 3, "\(own)")
            #expect(!WhiteBalance.temperatureRange.contains(own.kelvin) || !WhiteBalance.tintRange.contains(own.tint))
            // Shown at the range's end; the other number as it is.
            let controls = WhiteBalanceControls(systemDefaults: nil, usesFallbackDecoder: true, fallbackColor: color)
            let shown = try #require(controls.asShot)
            #expect(shown == CameraColorStep.rendered(own))
            #expect(shown.kelvin == max(own.kelvin, 2000) && shown.tint == min(own.tint, 150))
            #expect(WhiteBalance.temperatureRange.contains(shown.kelvin) && WhiteBalance.tintRange.contains(shown.tint))
            // Custom stores what is shown, and that is what renders: the stored numbers, not moved again.
            let custom = try #require(controls.picking(.custom, from: WhiteBalance()))
            #expect(custom.temperature == shown.kelvin && custom.tint == shown.tint)
            let step = try LibRawDecoder.decode(url, halfSize: true).step
            let stored = step.transform(temperature: custom.temperature, tint: custom.tint)
            #expect(stored == color.transform(for: shown, channelScale: step.channelScale))
            // Numbers beyond the ranges (a stack from elsewhere) render as the range's end too.
            #expect(step.transform(temperature: own.kelvin, tint: own.tint) == stored)
            // As Shot is the camera's own neutral, not the range's end: Custom changes this photo.
            let asShot = step.transform(temperature: nil, tint: nil)
            #expect(asShot != stored)
            let ownGain = try #require(asShot.gain), storedGain = try #require(stored.gain)
            #expect(abs(ownGain.x / ownGain.z - storedGain.x / storedGain.z) > 0.01 * (ownGain.x / ownGain.z)
                || abs(ownGain.y / ownGain.x - storedGain.y / storedGain.x) > 0.01 * (ownGain.y / ownGain.x))
        }
    }

    // MARK: One Kelvin on both decoders (AC2, AC9, AC13)

    @Test("A Kelvin white balance changes a raw by either decoder, the same way (AC2)")
    func kelvinAppliesOnBothDecoders() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            for url in [try Self.libRawDNG(in: folder), try Self.systemDNG(in: folder)] {
                let asShot = try Self.pixels(url, .none)
                // Daylight (5500, 0), and what `photocli render --set whiteBalance.temperature=2500` stores.
                let daylight = Self.balanced(.raw(.daylight))
                var kelvin = Adjustments()
                kelvin.whiteBalance.preset = .custom
                kelvin.whiteBalance.temperature = 2500
                #expect(daylight.decodeSettings.temperature == 5500 && daylight.decodeSettings.tint == 0)
                #expect(try Self.pixels(url, daylight) != asShot, "\(url.lastPathComponent)")
                #expect(try Self.pixels(url, kelvin) != asShot, "\(url.lastPathComponent)")
                // 2500 K says the light was very warm: the picture is rendered bluer. 9000 K: warmer.
                let neutral = try Self.warmth(url, .none)
                #expect(try Self.warmth(url, kelvin) < neutral * 0.7, "\(url.lastPathComponent)")
                #expect(try Self.warmth(url, Self.balanced(WhiteBalance(preset: .custom, temperature: 9000, tint: 0))) > neutral,
                        "\(url.lastPathComponent)")
                print("WhiteBalanceAcrossDecodersTests: \(url.lastPathComponent) is decoded by",
                      SystemRAWDecoder.reads(url) ? "the system RAW decoder" : "LibRaw")
            }
        }
    }

    /// AC9. One file the system decoder reads, decoded by each decoder in
    /// turn, as a later macOS would move a photo from LibRaw to the system
    /// decoder: the stack is what it was, and its white balance applies
    /// under both, in the same direction.
    @Test("A stored white balance applies whichever decoder reads the file, and the stack is not rewritten (AC9)")
    func decoderSwap() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.systemDNG(in: folder)
            let stack = Self.balanced(WhiteBalance(preset: .custom, temperature: 4000, tint: 10)).editStack
            let before = try stack.jsonData()
            let settings = AdjustmentRenderer().decodeSettings(for: stack)
            func warmth(_ image: CIImage) -> Double {
                let means = LibRawFallbackPipelineTests.means(image.scaledToFit(longEdge: 200))
                return means.x / means.z
            }
            // As LibRaw.
            let output = try LibRawDecoder.decode(url, halfSize: true)
            let libRawAsShot = warmth(output.step.apply(to: output.linear, settings: .none))
            let libRawBalanced = warmth(output.step.apply(to: output.linear, settings: settings))
            #expect(libRawBalanced < libRawAsShot * 0.9)
            // As the system decoder, where it reads the file.
            if SystemRAWDecoder.reads(url) {
                let systemAsShot = warmth(try PreviewGenerator.decode(url, longEdge: 768, draft: false).image)
                let systemBalanced = warmth(try PreviewGenerator.decode(url, longEdge: 768, draft: false, settings: settings).image)
                #expect(systemBalanced < systemAsShot * 0.9)
                // The same light for both: the camera's as-shot white (D65 for this camera) reads the same.
                let defaults = try #require(RawDefaults(source: url))
                let asShot = try #require(output.step.asShot)
                #expect(abs(asShot.kelvin / defaults.temperature - 1) < 0.01, "\(asShot.kelvin) K against \(defaults.temperature) K")
                #expect(abs(asShot.tint - defaults.tint) < 2, "tint \(asShot.tint) against \(defaults.tint)")
                // And the same Kelvin and tint give nearly the same color: a grey picture in linear
                // light (the system decoder without its boost, LibRaw's color step without its look),
                // where the camera's matrix is the file's for both decoders. Not the same: this far
                // from the camera's own white (D65 against 4000 K) the system decoder's blue is 12%
                // over the DNG specification's and its red 4% under, measured here on macOS 27.2. The
                // specification adapts the white point in a cone space (Bradford); the system
                // decoder's method is its own. At As Shot the two agree (above).
                let greys = folder.appending(path: "greys.dng")
                try SyntheticDNG.write(to: greys, options: .init(width: 1536, height: 1152, seed: 3, scene: .stripes(period: 96)))
                if SystemRAWDecoder.reads(greys) {
                    var flat = settings
                    flat.boostAmount = 0
                    let system = LibRawFallbackPipelineTests.means(
                        try PreviewGenerator.decode(greys, longEdge: 768, draft: false, settings: flat).image.scaledToFit(longEdge: 200))
                    let decoded = try LibRawDecoder.decode(greys, halfSize: true)
                    var transform = decoded.step.transform(temperature: 4000, tint: 10)
                    transform.exposure = 1
                    transform.toneCurve = nil
                    let libRaw = LibRawFallbackPipelineTests.means(transform.apply(to: decoded.linear).scaledToFit(longEdge: 200))
                    #expect(abs((libRaw.x / libRaw.y) / (system.x / system.y) - 1) < 0.06, "red: \(libRaw) against \(system)")
                    #expect(abs((libRaw.z / libRaw.y) / (system.z / system.y) - 1) < 0.15, "blue: \(libRaw) against \(system)")
                    // 4000 K is far from this camera's as-shot D65: blue is well over red.
                    #expect(libRaw.z / libRaw.x > 1.5)
                }
            } else {
                print("WhiteBalanceAcrossDecodersTests: the system RAW decoder does not read the 1536 x 1152 DNG here")
            }
            // Rendering wrote nothing into the stack, and a stack read back is the same bytes.
            #expect(try stack.jsonData() == before)
            let reread = Adjustments(stack: try EditStack.decode(from: before)).editStack
            #expect(try EditStackCorpusTests.fixingIDs(reread).jsonData() == EditStackCorpusTests.fixingIDs(stack).jsonData())

            // A file that is not a raw: Kelvin values stay inert, relative values still apply.
            let jpeg = try Self.jpeg(in: folder)
            let plain = try Self.pixels(jpeg, .none)
            #expect(try Self.pixels(jpeg, Self.balanced(WhiteBalance(preset: .custom, temperature: 4000, tint: 10))) == plain)
            #expect(try Self.pixels(jpeg, Self.balanced(.raw(.tungsten))) == plain)
            #expect(try Self.pixels(jpeg, Self.balanced(WhiteBalance(preset: .custom, relativeTemperature: 60, relativeTint: 30))) != plain)
        }
    }

    /// AC10 (R10). A stack as a build that gave LibRaw's photos relative
    /// values wrote it.
    @Test("Relative values stored on a raw stay in the stack, render as shot and show As Shot (AC10)")
    func relativeValuesOnARaw() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let json = #"{"operations":[{"id":"00000000-0000-4000-8000-000000000000","isEnabled":true,"kind":"whiteBalance","kindVersion":1,"parameters":{"preset":"custom","relativeTemperature":60,"relativeTint":30}}],"schemaVersion":1}"#
            let stack = try EditStack.decode(from: json)
            let values = Adjustments(stack: stack)
            #expect(values.whiteBalance == WhiteBalance(preset: .custom, relativeTemperature: 60, relativeTint: 30))
            // Not rewritten: read and written back, the same bytes.
            var rewritten = values.editStack
            rewritten.operations[0].id = stack.operations[0].id
            #expect(try rewritten.jsonString() == json)
            for url in [try Self.libRawDNG(in: folder), try Self.systemDNG(in: folder)] {
                // Renders as As Shot, by either decoder.
                #expect(try Self.pixels(url, values) == (try Self.pixels(url, .none)), "\(url.lastPathComponent)")
                let controls = Self.controls(for: url)
                guard case .offered(let modes, let selected) = controls.mode(for: values.whiteBalance) else {
                    Issue.record("the Mode pop-up is not offered for \(url.lastPathComponent)")
                    continue
                }
                #expect(modes.count == 9 && selected == .asShot, "\(url.lastPathComponent)")
                // Choosing Custom stores the as-shot Kelvin and tint beside the relative values, which
                // are not rewritten (R10), so it shows Custom (design §17.1, rule 1) and sticks.
                let asShot = try #require(controls.asShot)
                let leftover = try #require(controls.picking(.custom, from: values.whiteBalance))
                #expect(leftover == WhiteBalance(preset: .custom, temperature: asShot.kelvin, tint: asShot.tint,
                                                 relativeTemperature: 60, relativeTint: 30), "\(url.lastPathComponent)")
                #expect(controls.mode(for: leftover) == .offered(modes, selected: .custom))
            }
            // The same values on a file that is not a raw still change it, and show Custom.
            let jpeg = try Self.jpeg(in: folder)
            #expect(try Self.pixels(jpeg, values) != (try Self.pixels(jpeg, .none)))
            #expect(Self.controls(for: jpeg).mode(for: values.whiteBalance) == .offered([.asShot, .auto, .custom], selected: .custom))
        }
    }

    /// AC13, as far as it is the stack's and the renderer's: Copy
    /// Adjustments and a preset both come down to taking the White Balance
    /// group from other values. (The paste's one undo step is the app's:
    /// the debug script checks it.)
    @Test("A pasted or preset Kelvin white balance changes the receiving raw, from either decoder to the other (AC13)")
    func pasteBetweenDecoders() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let libRaw = try Self.libRawDNG(in: folder), system = try Self.systemDNG(in: folder)
            // Set on one, pasted onto the other, both ways.
            for (source, target) in [(system, libRaw), (libRaw, system)] {
                var edited = Adjustments()
                edited.exposure.ev = 0.3
                let picked = try #require(Self.controls(for: source).picking(.daylight, from: WhiteBalance()))
                edited.whiteBalance = picked
                var receiving = Adjustments()
                receiving.tone.contrast = 10
                let before = try Self.pixels(target, receiving)
                let pasted = receiving.replacing([.whiteBalance], from: edited)
                #expect(pasted.whiteBalance == WhiteBalance(preset: .daylight, temperature: 5500, tint: 0))
                #expect(pasted.tone.contrast == 10 && pasted.exposure.ev == 0)
                #expect(try Self.pixels(target, pasted) != before, "\(target.lastPathComponent)")
                #expect(Self.controls(for: target).mode(for: pasted.whiteBalance)
                    == .offered(WhiteBalance.Preset.allCases, selected: .daylight), "\(target.lastPathComponent)")
                // Undone, the receiving photo's stack and render are what they were.
                #expect(try Self.pixels(target, receiving) == before)
            }
            // A preset saved with a Kelvin white balance, as its stored stack.
            let preset = Adjustments(presetStack: Self.balanced(WhiteBalance(preset: .custom, temperature: 3200, tint: 5)).editStack)
            for url in [libRaw, system] {
                let applied = Adjustments().replacing([.whiteBalance], from: preset)
                #expect(try Self.pixels(url, applied) != (try Self.pixels(url, .none)), "\(url.lastPathComponent)")
            }
        }
    }

    // MARK: The profile value and the stack's reference to one (AC8)

    @Test("A stand-in profile given through the profile value changes the render accordingly (AC8)")
    func standInProfile() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let output = try LibRawDecoder.decode(try Self.libRawDNG(in: folder))
            let color = try #require(output.step.color)
            // Other matrices for two lights, forward matrices, a tone curve and a baseline exposure.
            let curve = [CameraProfile.TonePoint(0, 0), CameraProfile.TonePoint(0.2, 0.35), CameraProfile.TonePoint(1, 1)]
            let standIn = CameraProfile(name: "stand-in", calibrations: CameraColorTests.Kind.forward.color.profile.calibrations,
                                        toneCurve: curve, baselineExposure: 0.5)
            let step = CameraColorStep(color: color.with(profile: standIn), channelScale: output.step.channelScale)
            #expect(step.color?.asShotNeutral == color.asShotNeutral)
            let balance = ColorTemperature(kelvin: 4000, tint: -30)
            let rendered = ReferenceTests.renderLinear(step.apply(to: output.linear, temperature: balance.kelvin, tint: balance.tint))
            let builtIn = ReferenceTests.renderLinear(output.image(whiteBalance: balance))
            #expect(rendered.pixels != builtIn.pixels)
            // It is the stand-in's render: the reference with its matrices, exposure and curve.
            let reference = CameraColorTests.reference(kind: .forward, balance: balance, exposure: 0.5)
            let function: (Double) -> Double = { CameraColorTransform.toneValue(curve, at: $0) }
            let decoded = LibRawDecoderTests.samples(output)
            var failures = 0, difference = 0.0
            for pixel in stride(from: 0, to: rendered.width * rendered.height, by: 37) {
                let values = (0..<3).map { Double(decoded[pixel * 4 + $0]) / 65535 }
                let expected = reference.render(values, curve: function)
                // The table's reading error is the built-in curve's; this curve bends less.
                let allowed = CameraColorStepTests.tolerance(values, reference: reference, curve: function)
                for channel in 0..<3 {
                    if abs(Double(rendered.pixels[pixel * 4 + channel]) - expected[channel]) > allowed[channel] { failures += 1 }
                    difference = max(difference, abs(Double(builtIn.pixels[pixel * 4 + channel]) - expected[channel]))
                }
            }
            #expect(failures == 0)
            // Far from the built-in profile's render of the same decode.
            #expect(difference > 0.1)
        }
    }

    /// AC8, the second half. A stack as a later build with profiles (#89)
    /// might write it: a reference this build cannot resolve, with a
    /// parameter it has no name for.
    @Test("A stack with a camera profile reference loads, renders with the built-in profile and keeps the reference (AC8)")
    func unknownProfileReference() async throws {
        let reference = #"{"id":"00000000-0000-4000-8000-000000000000","isEnabled":true,"kind":"cameraProfile","kindVersion":1,"parameters":{"identifier":"9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08","later":[1,"x"],"name":"Camera Standard"}}"#
        let exposure = #"{"id":"00000000-0000-4000-8000-000000000001","isEnabled":true,"kind":"exposure","kindVersion":1,"parameters":{"ev":0.5}}"#
        let json = #"{"operations":["# + reference + "," + exposure + #"],"schemaVersion":1}"#
        let stack = try EditStack.decode(from: json)
        var values = Adjustments(stack: stack)
        // Read as the reference, not as an operation of an unknown kind.
        #expect(values.cameraProfile.identifier == "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
        #expect(values.preserved.isEmpty && !values.isDefault)
        // Written back as it was, the parameters this build does not know included.
        #expect(try EditStackCorpusTests.fixingIDs(values.editStack).jsonString() == json)
        // An edit keeps it.
        values.exposure.ev = 1
        values.whiteBalance = .raw(.shade)
        let edited = values.editStack
        #expect(edited.operations.first { $0.kind == CameraProfileReference.kind }?.parameters == stack.operations[0].parameters)
        // No group carries it: a paste or a preset neither brings nor removes one.
        #expect(Adjustments.Group.allCases.allSatisfy { !$0.kinds.contains(CameraProfileReference.kind) })
        #expect(Adjustments().replacing(Set(Adjustments.Group.allCases), from: values).cameraProfile == CameraProfileReference())
        // A version of the operation this build does not know is kept as any unknown operation is.
        let newer = try EditStack.decode(from: json.replacingOccurrences(of: #""kind":"cameraProfile","kindVersion":1"#,
                                                                         with: #""kind":"cameraProfile","kindVersion":2"#))
        let kept = Adjustments(stack: newer)
        #expect(kept.cameraProfile == CameraProfileReference() && kept.preserved.count == 1)
        #expect(kept.editStack.operations.contains { $0.kind == CameraProfileReference.kind && $0.kindVersion == 2 })
        // Without a reference nothing is written: every stack from before keeps its bytes.
        #expect(Adjustments().editStack == .identity)

        try await RepositoryFiles.withTemporaryDirectory { folder in
            // It renders with the built-in profile: as the same stack without the reference.
            let plain = Adjustments(stack: try EditStack.decode(from: #"{"operations":["# + exposure + #"],"schemaVersion":1}"#))
            for url in [try Self.libRawDNG(in: folder), try Self.systemDNG(in: folder)] {
                #expect(try Self.pixels(url, Adjustments(stack: stack)) == (try Self.pixels(url, plain)), "\(url.lastPathComponent)")
            }
        }
        // Its previews are keyed apart from the stack without it.
        #expect(stack.renderHash != Adjustments(stack: stack).resettingProfile.editStack.renderHash)
    }

    // MARK: Previews cached before the change (AC12)

    /// AC12 (R12), with R11's "their cached previews stay valid": a cache
    /// key cannot say which decoder a file gets, so the version is bumped
    /// for everything, and the earlier version's previews that cannot be
    /// LibRaw's (written before LibRaw decoded anything) are carried over.
    @Test("A preview cached since LibRaw decoding existed is made again; an older one is kept (AC12)")
    func cachedPreviewsAreRegenerated() async throws {
        // 8 was the version of the builds that showed LibRaw's photos without a color step or a look.
        #expect(PreviewCacheKey.currentPipelineVersion == 9 && PreviewCacheKey.versionCarriedOver == 8)
        let edits = EditStack.identity.renderHash
        func key(_ byte: String, _ tier: PreviewTier, version: Int = PreviewCacheKey.currentPipelineVersion) throws -> PreviewCacheKey {
            try #require(PreviewCacheKey(contentHash: String(repeating: byte, count: 32), editStackHash: edits, tier: tier,
                                         pipelineVersion: version))
        }
        let current = try key("ab", .preview), earlier = try key("ab", .preview, version: 8)
        #expect(current.pipelineVersion == 9 && current != earlier && current.relativePath != earlier.relativePath)
        #expect(current.relativePath.hasPrefix("v9/") && earlier.relativePath.hasPrefix("v8/"))
        // 2026-11-13, midnight UTC: the day LibRaw decoding first existed in a build (#161).
        let cutoff = PreviewCacheKey.libRawDecodingSince
        #expect(cutoff == ISO8601DateFormatter().date(from: "2026-11-13T00:00:00Z"))
        func setDate(_ cache: PreviewDiskCache, _ key: PreviewCacheKey, _ date: Date) throws {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: cache.url(for: key).path)
        }

        try await RepositoryFiles.withTemporaryDirectory { folder in
            let cache = PreviewDiskCache(root: folder)
            // Without the carry-over a version 8 preview is simply not found: a miss, rendered again.
            try cache.store(Data([1, 2, 3]), for: earlier)
            #expect(cache.contains(earlier) && !cache.contains(current))
            #expect(cache.loadImage(for: current) == nil)

            // Three photos' previews under version 8: one from before LibRaw decoded anything (a
            // JPEG's, a raw's the system decoder read), with its thumbnail; one from the day after
            // (possibly a LibRaw photo's old look); one written just now.
            let old = try key("ab", .preview, version: 8), oldThumbnail = try key("ab", .thumbnail, version: 8)
            let recent = try key("cd", .preview, version: 8), now = try key("ef", .thumbnail, version: 8)
            try cache.store(Data([4, 5, 6]), for: oldThumbnail)
            try cache.store(Data([7, 8]), for: recent)
            try cache.store(Data([9]), for: now)
            try setDate(cache, old, cutoff.addingTimeInterval(-1))
            try setDate(cache, oldThumbnail, cutoff.addingTimeInterval(-90 * 86_400))
            try setDate(cache, recent, cutoff.addingTimeInterval(86_400))
            let moved = cache.carryOver()
            #expect(moved.kept == 2 && moved.deleted == 2)
            // The old ones are found under today's keys, byte for byte.
            let carried = try key("ab", .preview), carriedThumbnail = try key("ab", .thumbnail)
            #expect(cache.contains(carried) && cache.contains(carriedThumbnail))
            #expect(try Data(contentsOf: cache.url(for: carried)) == Data([1, 2, 3]))
            #expect(try Data(contentsOf: cache.url(for: carriedThumbnail)) == Data([4, 5, 6]))
            // The ones a LibRaw photo's old look could be in are gone: made again on demand.
            let dropped = try key("cd", .preview), droppedThumbnail = try key("ef", .thumbnail)
            #expect(!cache.contains(dropped) && !cache.contains(droppedThumbnail))
            #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "v8").path))
            // Once only: with version 9 in place, a version 8 folder that turns up later (an
            // earlier build was run again) is not merged in, and goes with the obsolete versions.
            let late = try key("12", .preview, version: 8), lateToday = try key("12", .preview)
            try cache.store(Data([1]), for: late)
            try setDate(cache, late, cutoff.addingTimeInterval(-1))
            #expect(cache.carryOver() == (0, 0))
            #expect(!cache.contains(lateToday))
            cache.removeObsoletePipelineVersions()
            #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "v8").path))
            #expect(cache.contains(carried))
        }
        // A new library, or a cache that was deleted: nothing to carry.
        try await RepositoryFiles.withTemporaryDirectory { folder in
            #expect(PreviewDiskCache(root: folder).carryOver() == (0, 0))
            #expect(PreviewDiskCache(root: folder.appending(path: "missing")).carryOver() == (0, 0))
        }
    }

    // MARK: The exposure a Fujifilm camera held back

    @Test("A Fujifilm raw's exposure bias beyond the normal one is added to the baseline")
    func fujifilmExposure() throws {
        // 100% dynamic range: nothing held back.
        #expect(LibRawDecoder.fujifilmExposure(rawExposureBias: -0.72) == 0)
        // 200% and 400%: one stop and two.
        #expect(abs(try #require(LibRawDecoder.fujifilmExposure(rawExposureBias: -1.72)) - 1) < 1e-9)
        #expect(abs(try #require(LibRawDecoder.fujifilmExposure(rawExposureBias: -2.72)) - 2) < 1e-9)
        // A file exposed above the normal amount is never darkened.
        #expect(LibRawDecoder.fujifilmExposure(rawExposureBias: -0.3) == 0)
        // LibRaw's "not in the file", and values no camera writes.
        #expect(LibRawDecoder.fujifilmExposure(rawExposureBias: -999) == nil)
        #expect(LibRawDecoder.fujifilmExposure(rawExposureBias: 1.5) == nil)
        #expect(LibRawDecoder.fujifilmExposure(rawExposureBias: .nan) == nil)
        // It reaches the look as a file's own baseline exposure does.
        var color = CameraColorTests.Kind.single.color
        color.baselineExposure = 1
        let scale = SIMD3<Double>(repeating: 1)
        let held = try #require(color.transform(for: nil, channelScale: scale))
        let normal = try #require(CameraColorTests.Kind.single.color.transform(for: nil, channelScale: scale))
        #expect(abs(held.exposure / normal.exposure - 2) < 1e-12)
    }

    /// A DNG states its own baseline exposure, which LibRaw reads. The value
    /// is a file's, so it is used only within four stops either way (code
    /// review C6: 5000 stops was a factor of infinity and a frame of values
    /// that are not numbers).
    @Test("A DNG's baseline exposure is added to the look's, within four stops")
    func dngBaselineExposure() async throws {
        for kept in [0.5, -1.5, 4, -4, 0] {
            #expect(LibRawDecoder.dngExposure(baselineExposure: kept) == kept)
        }
        // LibRaw's "not in the file" among them.
        for refused in [4.01, -4.01, 200, 5000, -999, Double.nan, .infinity, -.infinity] {
            #expect(LibRawDecoder.dngExposure(baselineExposure: refused) == nil, "\(refused)")
        }
        try await RepositoryFiles.withTemporaryDirectory { folder in
            // One picture, written with different tags.
            let mosaic = try SyntheticDNG.mosaic(options: .init(width: 256, height: 192, seed: 7))
            func tags(_ exposure: Double?) -> SyntheticDNG.Color {
                var tags = CameraColorTests.Kind.single.tags
                tags.baselineExposure = exposure
                return tags
            }
            let plainURL = try Self.libRawDNG(in: folder, "plain", mosaic: mosaic)
            let plain = try #require(LibRawDecoder.cameraColor(plainURL))
            #expect(plain.baselineExposure == 0)
            let color = try #require(LibRawDecoder.cameraColor(try Self.libRawDNG(in: folder, "exposed", color: tags(0.5), mosaic: mosaic)))
            #expect(color.baselineExposure == 0.5)
            #expect(color.profile.baselineExposure == BaselineLook.exposure && color.profile.toneCurve == BaselineLook.toneCurve)
            let transform = try #require(color.transform(for: nil, channelScale: SIMD3(repeating: 1)))
            #expect(abs(transform.exposure - pow(2, 0.5 + BaselineLook.exposure)) < 1e-12)
            // A file that states a number no file means: rendered without it, every value a number.
            let plainPixels = ReferenceTests.renderLinear(try LibRawDecoder.decode(plainURL).image()).pixels
            for absurd in [5000.0, 200, -50] {
                let url = try Self.libRawDNG(in: folder, "absurd", color: tags(absurd), mosaic: mosaic)
                #expect(try #require(LibRawDecoder.cameraColor(url)).baselineExposure == 0, "\(absurd)")
                let output = try LibRawDecoder.decode(url)
                #expect(output.step.fileExposure == 0)
                let pixels = ReferenceTests.renderLinear(output.image()).pixels
                #expect(!pixels.contains { !$0.isFinite }, "\(absurd)")
                #expect(pixels == plainPixels, "\(absurd)")
            }
        }
    }

    /// Code review C5. A file whose color data cannot be used has no
    /// `CameraColor` for its exposure to ride on; the step keeps it.
    @Test("A file without usable color data keeps its own exposure")
    func exposureWithoutColorData() async throws {
        // The step alone: a Fujifilm raw's held-back stop, with no camera color.
        let held = CameraColorStep(color: nil, fileExposure: 1).transform(temperature: nil, tint: nil)
        #expect(held.gain == nil && held.matrix == nil && held.toneCurve == BaselineLook.toneCurve)
        #expect(abs(held.exposure - pow(2, 1 + BaselineLook.exposure)) < 1e-12)
        #expect(held == CameraColorStep(color: nil, fileExposure: 1).transform(temperature: 3000, tint: 20))
        #expect(CameraColorStep(color: nil).transform(temperature: nil, tint: nil).exposure == pow(2, BaselineLook.exposure))
        try await RepositoryFiles.withTemporaryDirectory { folder in
            // Through the decoder: a DNG with no color matrix that states a baseline exposure.
            let mosaic = try SyntheticDNG.mosaic(options: .init(width: 256, height: 192, seed: 7))
            let exposed = try LibRawDecoder.decode(try Self.libRawDNG(
                in: folder, "exposed", color: SyntheticDNG.Color(matrix1: nil, baselineExposure: 1), mosaic: mosaic))
            let plain = try LibRawDecoder.decode(try Self.libRawDNG(in: folder, "plain", color: SyntheticDNG.Color(matrix1: nil),
                                                                    mosaic: mosaic))
            #expect(exposed.step.color == nil && plain.step.color == nil)
            #expect(exposed.step.fileExposure == 1 && plain.step.fileExposure == 0)
            let transform = exposed.step.transform(temperature: nil, tint: nil)
            #expect(abs(transform.exposure - pow(2, 1 + BaselineLook.exposure)) < 1e-12)
            // The same decode, a stop brighter before the tone curve: a brighter picture.
            #expect(LibRawDecoderTests.samples(exposed) == LibRawDecoderTests.samples(plain))
            let brighter = LibRawFallbackPipelineTests.means(exposed.image()), normal = LibRawFallbackPipelineTests.means(plain.image())
            #expect(brighter.y > normal.y * 1.2)
            // With color data the exposure is the camera color's, the same number.
            var tags = CameraColorTests.Kind.single.tags
            tags.baselineExposure = 1
            let colored = try LibRawDecoder.decode(try Self.libRawDNG(in: folder, "colored", color: tags, mosaic: mosaic))
            #expect(colored.step.color?.baselineExposure == 1 && colored.step.fileExposure == 1)
        }
    }

    /// Code review C7. One rendition written since the cutoff that cannot
    /// be removed must not cost the older ones, which for an offline master
    /// could not be made again, and must not come under the current version.
    @Test("A rendition that cannot be removed does not stop the older ones from being carried over")
    func carryOverSurvivesAFailedRemoval() async throws {
        let edits = EditStack.identity.renderHash
        func key(_ byte: String, _ tier: PreviewTier, version: Int = PreviewCacheKey.currentPipelineVersion) throws -> PreviewCacheKey {
            try #require(PreviewCacheKey(contentHash: String(repeating: byte, count: 32), editStackHash: edits, tier: tier,
                                         pipelineVersion: version))
        }
        let cutoff = PreviewCacheKey.libRawDecodingSince
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let cache = PreviewDiskCache(root: folder)
            // "ab" and "ac" share a folder ("a…"); "cd" has its own.
            let old = try key("ab", .preview, version: 8), stuck = try key("ac", .preview, version: 8)
            let oldElsewhere = try key("cd", .thumbnail, version: 8), recent = try key("ef", .preview, version: 8)
            try cache.store(Data([1, 2, 3]), for: old)
            try cache.store(Data([4]), for: stuck)
            try cache.store(Data([5, 6]), for: oldElsewhere)
            try cache.store(Data([7]), for: recent)
            let manager = FileManager.default
            try manager.setAttributes([.modificationDate: cutoff.addingTimeInterval(-3600)], ofItemAtPath: cache.url(for: old).path)
            try manager.setAttributes([.modificationDate: cutoff.addingTimeInterval(-3600)], ofItemAtPath: cache.url(for: oldElsewhere).path)
            try manager.setAttributes([.modificationDate: cutoff.addingTimeInterval(3600)], ofItemAtPath: cache.url(for: stuck).path)
            // The folder that holds "ab" and "ac" cannot be written to: nothing in it can be removed or moved out.
            let locked = cache.url(for: stuck).deletingLastPathComponent()
            try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
            defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
            try #require(!manager.isDeletableFile(atPath: cache.url(for: stuck).path), "the test cannot make a file unremovable here")

            let moved = cache.carryOver()
            // Both older renditions arrived (one copied out of the locked folder); the removable recent one is gone.
            #expect(moved.kept == 2 && moved.deleted == 1)
            let carried = try key("ab", .preview), carriedElsewhere = try key("cd", .thumbnail)
            #expect(try Data(contentsOf: cache.url(for: carried)) == Data([1, 2, 3]))
            #expect(try Data(contentsOf: cache.url(for: carriedElsewhere)) == Data([5, 6]))
            // The one that could not be removed is not found under the current version, nor is the recent one.
            let stuckToday = try key("ac", .preview), recentToday = try key("ef", .preview)
            #expect(!cache.contains(stuckToday) && !cache.contains(recentToday))
            // What follows at launch leaves the carried ones alone.
            cache.removeObsoletePipelineVersions()
            #expect(cache.contains(carried) && cache.contains(carriedElsewhere))
            #expect(!cache.contains(stuckToday))
        }
    }
}

private extension Adjustments {
    /// These values without a camera profile reference.
    var resettingProfile: Adjustments {
        var copy = self
        copy.cameraProfile = CameraProfileReference()
        return copy
    }
}
