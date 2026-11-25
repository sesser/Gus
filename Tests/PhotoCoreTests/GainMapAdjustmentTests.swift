import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #282: every adjustment works in HDR (R7, AC6), and the HDR
/// brightening follows the picture under Distortion and spots (R19, AC17).
/// Synthetic gain-map files; the owner's photos run in the opt-in test of
/// `GainMapHDRTests` and below (Apple-only gain maps).
@Suite("Gain-map photos: every adjustment and the geometry (issue #282)")
struct GainMapAdjustmentTests {
    typealias Pixels = GainMapHDRTests.Pixels

    /// One adjustment at its smallest non-neutral value and at a strong one.
    struct Case: Sendable, CustomStringConvertible {
        var name: String
        var small: @Sendable (inout Adjustments) -> Void
        var strong: @Sendable (inout Adjustments) -> Void
        /// An on/off conversion (Black & White) has no small value: turned on with
        /// every filter at 0 it changes the picture, in both versions alike.
        var isSwitch = false
        var description: String { name }
    }

    static let table = BuiltInLookTables.all.first?.identifier ?? ""

    /// Every group and control of the Adjust tab that changes pixels, masks
    /// and spots included (crop, Distortion and spots move pixels: AC17 below).
    static let cases: [Case] = [
        Case(name: "white balance") { $0.whiteBalance.preset = .custom; $0.whiteBalance.relativeTemperature = 1 }
            strong: { $0.whiteBalance.preset = .custom; $0.whiteBalance.relativeTemperature = 60 },
        Case(name: "exposure") { $0.exposure.ev = 0.01 } strong: { $0.exposure.ev = 1.5 },
        Case(name: "contrast") { $0.tone.contrast = 1 } strong: { $0.tone.contrast = 80 },
        Case(name: "highlights") { $0.tone.highlights = -1 } strong: { $0.tone.highlights = -80 },
        Case(name: "highlights up") { $0.tone.highlights = 1 } strong: { $0.tone.highlights = 80 },
        Case(name: "shadows") { $0.tone.shadows = 1 } strong: { $0.tone.shadows = 80 },
        Case(name: "whites") { $0.tone.whites = 1 } strong: { $0.tone.whites = 80 },
        Case(name: "blacks") { $0.tone.blacks = 1 } strong: { $0.tone.blacks = 80 },
        Case(name: "clarity") { $0.presence.clarity = 1 } strong: { $0.presence.clarity = 80 },
        Case(name: "dehaze") { $0.presence.dehaze = 1 } strong: { $0.presence.dehaze = 60 },
        Case(name: "vibrance") { $0.presence.vibrance = 1 } strong: { $0.presence.vibrance = 80 },
        Case(name: "saturation") { $0.presence.saturation = 1 } strong: { $0.presence.saturation = 80 },
        Case(name: "tone curve") {
            $0.toneCurve[.rgb] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.502), CurvePoint(x: 1, y: 1)]
        } strong: {
            $0.toneCurve[.rgb] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.15),
                                  CurvePoint(x: 0.75, y: 0.85), CurvePoint(x: 1, y: 1)]
        },
        Case(name: "color mixer") { $0.colorMixer[.orange] = .init(saturation: 1) }
            strong: { $0.colorMixer[.orange] = .init(saturation: 80); $0.colorMixer[.blue] = .init(luminance: -60) },
        Case(name: "black and white", small: { $0.blackAndWhite.isOn = true },
             strong: { $0.blackAndWhite.isOn = true; $0.blackAndWhite[.red] = 100 }, isSwitch: true),
        Case(name: "color grading") { $0.colorGrade.highlights.amount = 1 }
            strong: { $0.colorGrade.highlights.hue = 40; $0.colorGrade.highlights.amount = 80 },
        // The smallest non-neutral look-up table: a built-in table at 1% (AC6 names an identity table; this is
        // the nearest a stack can hold without a table file).
        Case(name: "look-up table") { $0.lookTable.identifier = table; $0.lookTable.intensity = 1 }
            strong: { $0.lookTable.identifier = table; $0.lookTable.intensity = 100 },
        Case(name: "vignette") { $0.vignette.amount = -1 } strong: { $0.vignette.amount = -80 },
        Case(name: "grain") { $0.grain.strength = 1 } strong: { $0.grain.strength = 80 },
        Case(name: "sharpening") { $0.sharpen.amount = 1 } strong: { $0.sharpen.amount = 150 },
        Case(name: "noise reduction") { $0.noiseReduction.luminance = 1 } strong: { $0.noiseReduction.luminance = 80 },
        Case(name: "lens vignetting") { $0.lensVignetting = LensVignetting(isOn: true, source: .manual, amount: 1) }
            strong: { $0.lensVignetting = LensVignetting(isOn: true, source: .manual, amount: 80) },
        Case(name: "color alignment") { $0.colorAlignment.setByHand(red: 0.1) }
            strong: { $0.colorAlignment.setByHand(red: 20, blue: -20) },
        Case(name: "mask") {
            $0.local.masks = [GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: 0.4, y: 0.5), radiusX: 0.3,
                                                                      radiusY: 0.3))]) { $0.exposure = 0.01 }]
        } strong: {
            $0.local.masks = [GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: 0.4, y: 0.5), radiusX: 0.3,
                                                                      radiusY: 0.3))]) {
                $0.exposure = 1
                $0.contrast = 60
            }]
        },
    ]

    /// The HDR version at the file's full brightening and the SDR version as
    /// shown, both in linear Display P3, of `values` on `url`.
    static func pair(_ url: URL, _ values: Adjustments, generator: PreviewGenerator, longEdge: Int = 600)
        throws -> (hdr: Pixels, sdr: Pixels) {
        let hdr = try #require(try generator.gainMapHDRImage(source: url, stack: values.editStack, longEdge: longEdge,
                                                             displayHeadroom: 100))
        let sdr = try generator.image(source: url, stack: values.editStack, longEdge: longEdge)
        return (Pixels(hdr.image), Pixels(GainMap.clamped(sdr, maximum: 1)))
    }

    @Test("AC6: every adjustment keeps each point's brightening; its smallest value changes nothing visible",
          arguments: cases)
    func everyAdjustment(_ adjustment: Case) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "every.heic")
            try HDRTestImages.writePatternedGainMap(to: url, width: 600, height: 450, seed: 2840)
            let renderer = AdjustmentRenderer(lookTables: GoldenCase.lookTables)
            let generator = PreviewGenerator(renderer: renderer)
            let unedited = try Self.pair(url, Adjustments(), generator: generator)
            #expect(unedited.hdr.maximum > 2)

            var small = Adjustments()
            adjustment.small(&small)
            #expect(small != Adjustments(), "\(adjustment): the small value is not an edit")
            let nudged = try Self.pair(url, small, generator: generator)
            let shift = log2(Double(nudged.hdr.mean / unedited.hdr.mean))
            if adjustment.isSwitch {
                // The HDR version moves as the SDR one does, and stays above white.
                let sdrShift = log2(Double(nudged.sdr.mean / unedited.sdr.mean))
                #expect(abs(shift - sdrShift) < 0.05, "\(adjustment) on: HDR moved \(shift), SDR \(sdrShift) stops")
                #expect(nudged.hdr.maximum > 1, "\(adjustment) on: values above white are kept")
            } else {
                #expect(abs(shift) < 0.05, "\(adjustment) small: mean moved \(shift) stops")
                #expect(nudged.hdr.maximum > 2, "\(adjustment) small: values above white are kept")
            }

            var strong = Adjustments()
            adjustment.strong(&strong)
            let edited = try Self.pair(url, strong, generator: generator)
            let drift = GainMapHDRTests.drift(hdr: edited.hdr, sdr: edited.sdr, hdr0: unedited.hdr, sdr0: unedited.sdr)
            #expect(drift < 0.05, "\(adjustment) strong: \(drift) stops RMS")
            #expect(edited.hdr.maximum > 1, "\(adjustment) strong: not clipped to SDR white")
        }
    }

    /// `GAINMAP_SAMPLES=a.HEIC:b.HEIC` (the owner's files, never committed):
    /// AC6's strong values on real files, among them one that carries only
    /// Apple's kind of gain map. Prints each drift for status.md.
    @Test("AC6 on real files, Apple-only gain maps included",
          .enabled(if: ProcessInfo.processInfo.environment["GAINMAP_SAMPLES"] != nil))
    func everyAdjustmentOnRealFiles() async throws {
        let paths = ProcessInfo.processInfo.environment["GAINMAP_SAMPLES"]?.split(separator: ":").map(String.init) ?? []
        let renderer = AdjustmentRenderer(lookTables: GoldenCase.lookTables)
        let generator = PreviewGenerator(renderer: renderer)
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let iso = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
            let unedited = try Self.pair(url, Adjustments(), generator: generator, longEdge: 1024)
            for adjustment in Self.cases {
                var strong = Adjustments()
                adjustment.strong(&strong)
                let edited = try Self.pair(url, strong, generator: generator, longEdge: 1024)
                let drift = GainMapHDRTests.drift(hdr: edited.hdr, sdr: edited.sdr, hdr0: unedited.hdr, sdr0: unedited.sdr)
                print("gain-map sample \(url.lastPathComponent) \(iso ? "ISO" : "Apple-only") \(adjustment): \(String(format: "%.4f", drift)) stops RMS")
                #expect(drift < 0.05, "\(url.lastPathComponent) \(adjustment): \(drift) stops RMS")
            }
        }
    }

    // MARK: AC17: the brightening follows Distortion and spots

    /// The system's HDR decode (the gain map baked into the picture) taken
    /// through the same steps that move content: what our HDR version of a
    /// stack that only moves content must equal, cell by cell.
    static func reference(_ url: URL, _ values: Adjustments, longEdge: Int) throws -> Pixels {
        let expanded = try GainMapHDRTests.systemHDR(url)
        let moved = AdjustmentRenderer.gainMapGeometry(values, expanded, context: RenderContext())
        return Pixels(moved, size: try #require(try sizeOf(url, values, longEdge: longEdge)))
    }

    static func sizeOf(_ url: URL, _ values: Adjustments, longEdge: Int) throws -> CGSize? {
        let made = try PreviewGenerator().gainMapHDRImage(source: url, stack: values.editStack, longEdge: longEdge,
                                                          displayHeadroom: 100)
        return made.map { CGSize(width: $0.image.width, height: $0.image.height) }
    }

    @Test("AC17: under Distortion, with a crop and a turn, the brightening lands on the same picture content")
    func distortion() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "distort.heic")
            // A bright patch near a corner, where Distortion moves the picture most.
            try HDRTestImages.writePatternedGainMap(to: url, width: 800, height: 600, seed: 2841, orientation: 6,
                                                    brightRegion: CGRect(x: 0.04, y: 0.05, width: 0.12, height: 0.12))
            var values = Adjustments()
            values.distortion = LensDistortion(isOn: true, source: .manual, amount: 100, constrain: false)
            values.crop = Crop(rect: CropRect(x: 0.05, y: 0.1, width: 0.85, height: 0.8), quarterTurns: 1, angle: 2)
            let made = try #require(try PreviewGenerator().gainMapHDRImage(source: url, stack: values.editStack,
                                                                           longEdge: 800, displayHeadroom: 100))
            let ours = Pixels(made.image).cells(columns: 24, rows: 18)
            let theirs = try Self.reference(url, values, longEdge: 800).cells(columns: 24, rows: 18)
            let worst = zip(ours, theirs).map { abs(log2($0 / $1)) }.max() ?? .infinity
            #expect(worst < 0.05, "worst cell \(worst) stops")

            // Without the warp on the gain map (crop only), the bright part lands elsewhere.
            let map = try #require(GainMap.load(url))
            let decoded = try PreviewGenerator.decode(url, longEdge: 800, draft: false, settings: RAWDecodeSettings())
            let rendered = try AdjustmentRenderer().apply(values.editStack, to: decoded.image, context: decoded.context)
            let unwarped = map.hdr(rendered, placed: map.placed(over: decoded.image.extent, crop: values.effective.crop),
                                   displayHeadroom: 100).image
            let wrong = Pixels(unwarped, size: CGSize(width: made.image.width, height: made.image.height))
                .cells(columns: 24, rows: 18)
            let missed = zip(wrong, theirs).map { abs(log2($0 / $1)) }.max() ?? 0
            #expect(missed > 0.2 && missed > 4 * worst,
                    "the test can't tell: an unwarped gain map is \(missed) stops off, the warped one \(worst)")
        }
    }

    @Test("AC17: a healed or cloned spot over the bright part takes its source's brightening, no glow",
          arguments: [SpotMode.heal, .clone])
    func spotsTakeTheSourcesBrightening(_ mode: SpotMode) async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "spot.heic")
            // A small bright object (×4, 40 × 40 pixels) at (200, 90), ×1.5 around it: a light to heal away.
            try HDRTestImages.writePatternedGainMap(to: url, width: 800, height: 600, seed: 2842, bright: 4, dim: 1.5,
                                                    brightRegion: CGRect(x: 0.225, y: 0.1167, width: 0.05, height: 0.0667))
            var values = Adjustments()
            values.spots.spots = [Spot(mode: mode, center: MaskPoint(x: 0.25, y: 0.15), size: 0.06,
                                       source: MaskPoint(x: 0.25, y: 0.75), feather: 20, opacity: 100)]
            let generator = PreviewGenerator()
            let edited = try Self.pair(url, values, generator: generator, longEdge: 800)
            // The ratio at the spot's middle (a 20-pixel square): the source's ×1.5, not the ×4 it covers.
            func stops(_ pair: (hdr: Pixels, sdr: Pixels), x: Int, y: Int) -> Double {
                var sum = 0.0, count = 0.0
                for row in (y - 10)..<(y + 10) {
                    for column in (x - 10)..<(x + 10) {
                        let index = row * pair.hdr.width + column
                        guard pair.sdr.luminance[index] > 0.005 else { continue }
                        sum += log2(Double(pair.hdr.luminance[index] / pair.sdr.luminance[index]))
                        count += 1
                    }
                }
                return sum / max(count, 1)
            }
            let atSpot = stops(edited, x: 200, y: 90)
            let atSource = stops(edited, x: 200, y: 450)
            #expect(abs(atSpot - atSource) < 0.1, "\(mode): \(atSpot) stops at the spot, \(atSource) at its source")
            let unedited = try Self.pair(url, Adjustments(), generator: generator, longEdge: 800)
            #expect(stops(unedited, x: 200, y: 90) > atSource + 1, "the spot covers the bright part")
        }
    }
}
