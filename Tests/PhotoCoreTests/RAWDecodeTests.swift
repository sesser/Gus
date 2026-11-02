import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// What each RAW decode setting does, checked against the as-shot decode of
/// the same synthetic DNG instead of stored images, so they hold on every
/// macOS release whatever its decoder (the RAW goldens are compared only
/// where they were made; see `DecoderFingerprint`). Each check is a direction
/// or an order, not an amount: the amounts are the decoder's own.
@Suite("RAW decode settings")
struct RAWDecodeTests {
    /// The goldens' DNG (`RAWGoldenCase.master`) with Gaussian noise of 2 % of
    /// white per photosite, for the decoder's noise reduction to remove.
    static let noisyMaster: URL = {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "noisy-bayer-\(ProcessInfo.processInfo.processIdentifier).dng", directoryHint: .notDirectory)
        try? SyntheticDNG.write(to: url, options: .init(width: 320, height: 240, seed: 7, noise: 0.02))
        return url
    }()

    static func render(_ edit: (inout Adjustments) -> Void, source: URL = RAWGoldenCase.master) throws -> Statistics {
        var adjustments = Adjustments()
        edit(&adjustments)
        let image = try PreviewGenerator(engine: Goldens.engine).image(source: source, stack: adjustments.editStack,
                                                                       longEdge: nil)
        return Statistics(ReferenceTests.renderLinear(image))
    }

    /// Simple measures of a linear render.
    struct Statistics {
        var mean: SIMD3<Double>
        var maximum: Float
        /// Standard deviation of luma in the perceptual encoding (sRGB curve): contrast.
        var lumaDeviation: Double
        /// Mean square of each pixel's luma minus the mean of its four
        /// neighbours: high-frequency energy, which noise adds to.
        var highFrequency: Double

        init(_ image: LinearImage) {
            var sum = SIMD3<Double>.zero
            var maximum: Float = -.infinity
            var luma = [Double](repeating: 0, count: image.width * image.height)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let p = image[x, y]
                    sum += SIMD3(Double(p.x), Double(p.y), Double(p.z))
                    maximum = max(maximum, p.x, p.y, p.z)
                    let linear = max(0, 0.2627 * Double(p.x) + 0.6780 * Double(p.y) + 0.0593 * Double(p.z))
                    luma[y * image.width + x] = linear <= 0.0031308 ? linear * 12.92
                        : 1.055 * pow(linear, 1 / 2.4) - 0.055
                }
            }
            let count = Double(luma.count)
            mean = sum / count
            self.maximum = maximum
            let average = luma.reduce(0, +) / count
            lumaDeviation = (luma.map { ($0 - average) * ($0 - average) }.reduce(0, +) / count).squareRoot()
            var energy = 0.0
            let w = image.width
            for y in 1..<(image.height - 1) {
                for x in 1..<(w - 1) {
                    let i = y * w + x
                    let difference = luma[i] - (luma[i - 1] + luma[i + 1] + luma[i - w] + luma[i + w]) / 4
                    energy += difference * difference
                }
            }
            highFrequency = energy / Double((image.width - 2) * (image.height - 2))
        }

        var redOverBlue: Double { mean.x / mean.z }
    }

    /// Setting a lower color temperature than the light's says the light was
    /// warmer, so the decoder cools the image (less red against blue); a higher
    /// one warms it. The DNG's as-shot neutral is D65 (about 6500 K), between
    /// the two.
    @Test("Kelvin white balance moves red against blue the expected way")
    func kelvinDirection() throws {
        let asShotTemperature = try #require(CIRAWFilter(imageURL: RAWGoldenCase.master)).neutralTemperature
        #expect(asShotTemperature > 3200 && asShotTemperature < 8000, "as shot: \(asShotTemperature) K")
        let asShot = try Self.render { _ in }
        let tungsten = try Self.render { $0.whiteBalance = WhiteBalance(preset: .custom, temperature: 3200, tint: 0) }
        let shade = try Self.render { $0.whiteBalance = WhiteBalance(preset: .custom, temperature: 8000, tint: 0) }
        #expect(tungsten.redOverBlue < asShot.redOverBlue,
                "3200 K: red/blue \(tungsten.redOverBlue), as shot \(asShot.redOverBlue)")
        #expect(shade.redOverBlue > asShot.redOverBlue,
                "8000 K: red/blue \(shade.redOverBlue), as shot \(asShot.redOverBlue)")
    }

    /// Flat has no base boost, neutral half of it, standard all of it.
    @Test("Flat, neutral and standard looks are ordered by contrast")
    func looksOrderedByContrast() throws {
        let flat = try Self.render { $0.decode.look = .flat }.lumaDeviation
        let neutral = try Self.render { $0.decode.look = .neutral }.lumaDeviation
        let standard = try Self.render { _ in }.lumaDeviation
        #expect(flat < neutral && neutral < standard, "luma deviation: flat \(flat), neutral \(neutral), standard \(standard)")
    }

    /// Negative exposure asks the decoder for extended range: highlights it
    /// would roll off at white come out above 1.0 instead. The plain decode
    /// stays within white (plus one half-float rounding).
    @Test("Extended range keeps values above 1.0")
    func extendedRangeKeepsAboveWhite() throws {
        var adjustments = Adjustments()
        adjustments.exposure.ev = -1
        #expect(adjustments.decodeSettings.extendedDynamicRange == 1)
        func decodedMaximum(_ settings: RAWDecodeSettings) throws -> Float {
            let image = try PreviewGenerator.decode(RAWGoldenCase.master, longEdge: nil, draft: false,
                                                    settings: settings).image
            return Statistics(ReferenceTests.renderLinear(image)).maximum
        }
        let extended = try decodedMaximum(adjustments.decodeSettings)
        let standard = try decodedMaximum(.none)
        #expect(extended > 1, "extended range: largest value \(extended)")
        #expect(standard <= 1 + 0x1p-11, "standard decode: largest value \(standard)")
    }

    @Test("Decoder noise reduction lowers noise")
    func noiseReductionLowersNoise() throws {
        let filter = try #require(CIRAWFilter(imageURL: Self.noisyMaster))
        #expect(filter.isLuminanceNoiseReductionSupported && filter.isColorNoiseReductionSupported)
        let noisy = try Self.render({ $0.noiseReduction = NoiseReduction(luminance: 0, color: 0) },
                                    source: Self.noisyMaster).highFrequency
        let reduced = try Self.render({ $0.noiseReduction = NoiseReduction(luminance: 80, color: 80) },
                                      source: Self.noisyMaster).highFrequency
        #expect(reduced < noisy, "high-frequency energy: \(reduced) with noise reduction, \(noisy) without")
    }
}
