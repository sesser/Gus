import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The color step after a LibRaw decode, as rendered (issue #170, AC4): a
/// synthetic DNG with known matrices and a known neutral, decoded by LibRaw
/// and rendered by Core Image for a chosen Kelvin and tint, against the
/// DNG specification's math in plain Swift (`CameraColorReference`) on the
/// decode's own pixels. One matrix, two, and forward matrices.
@Suite("Camera color step")
struct CameraColorStepTests {
    typealias Kind = CameraColorTests.Kind

    static func dng(in folder: URL, _ name: String, color: SyntheticDNG.Color, width: Int = 256, height: Int = 192,
                    seed: UInt64 = 7, scene: SyntheticDNG.Scene = .pattern, defaultCrop: CGRect? = nil) throws -> URL {
        let url = folder.appending(path: "\(name).dng")
        try SyntheticDNG.write(to: url, options: .init(width: width, height: height, seed: seed, scene: scene,
                                                       defaultCrop: defaultCrop, color: color))
        return url
    }

    /// One rounding into the working format (half float): 2⁻¹¹ of the value.
    static let rounding = 0x1p-11

    /// The curve's table is read between entries a 2047th of two apart: a
    /// straight line between them is off by at most h² / 8 of the curve's
    /// second derivative there, taken here from the table's own second
    /// differences, and decoding the result multiplies it by the sRGB
    /// curve's slope, at most 5.8 below an encoded 2.
    static let tableReading: Double = {
        guard let points = BaselineLook.toneCurve else { return 0 }
        let table = CameraColorTransform.curveTable(points)
        var worst = 0.0
        for index in 1..<(CameraColorTransform.curveEntryCount - 1) {
            worst = max(worst, abs(Double(table[(index - 1) * 3]) - 2 * Double(table[index * 3]) + Double(table[(index + 1) * 3])))
        }
        return worst / 8 * 5.8
    }()

    /// How far a render may be from the reference for one pixel, derived
    /// from the formats: the working format is half float, and a value can
    /// be rounded into it where the decode enters, after the white balance,
    /// after the matrix, inside the curve's filter (in its encoding, before
    /// and after the table) and at the end. Each rounding's effect on the
    /// result is found by putting it through the reference itself.
    static func tolerance(_ decoded: [Double], reference: CameraColorReference.Prepared,
                          curve: ((Double) -> Double)?) -> [Double] {
        let exact = reference.render(decoded, curve: curve)
        let linear = reference.render(decoded)
        var entering = [0.0, 0.0, 0.0]
        for signs in 0..<8 {
            var rounded = decoded
            for channel in 0..<3 {
                let down = (signs >> channel) & 1 == 1
                let shift: Double = down ? -rounding : rounding
                rounded[channel] = decoded[channel] * (1 + shift)
            }
            let moved = reference.render(rounded, curve: curve)
            for channel in 0..<3 { entering[channel] = max(entering[channel], abs(moved[channel] - exact[channel])) }
        }
        return (0..<3).map { channel in
            var allowed = 2 * entering[channel]   // the decode entering, and again after the white balance
            if let curve {
                let value = linear[channel]
                // After the matrix, and in the curve's encoding before the table (a rounding of the
                // encoded value is at most one of the linear value, the encoding's slope being under 1 in ratio).
                let before = max(abs(curve(value * (1 + rounding)) - exact[channel]), abs(curve(value * (1 - rounding)) - exact[channel]))
                allowed += 2 * before
                // After the table, in the encoding: decoding multiplies a relative error by at most 2.4.
                allowed += 2.4 * rounding * abs(exact[channel]) + tableReading
            } else {
                allowed += rounding * abs(exact[channel])
            }
            // The result, read back.
            return allowed + rounding * abs(exact[channel]) + 0x1p-24
        }
    }

    @Test("A LibRaw decode's color step is the DNG specification's, as rendered", arguments: Kind.allCases)
    func stepMatchesReference(kind: Kind) async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.dng(in: folder, kind.rawValue, color: kind.tags)
            let output = try LibRawDecoder.decode(url)
            // What LibRaw read is what the tags say: the calibrations, their lights, the neutral.
            let color = try #require(output.step.color)
            #expect(color.profile.calibrations.map(\.illuminant) == kind.color.profile.calibrations.map(\.illuminant))
            #expect(color.profile.calibrations.map { $0.forwardMatrix != nil } == kind.color.profile.calibrations.map { $0.forwardMatrix != nil })
            for (read, written) in zip(color.profile.calibrations, kind.color.profile.calibrations) {
                // Four decimals in the file, single precision in LibRaw.
                #expect(zip(read.colorMatrix.values, written.colorMatrix.values).allSatisfy { abs($0 - $1) < 1e-6 })
            }
            #expect(abs(color.asShotNeutral.x - 0.5) < 1e-6 && color.asShotNeutral.y == 1 && abs(color.asShotNeutral.z - 0.6) < 1e-6)
            // The analog balance and each light's camera calibration, whichever light the file names
            // first (code review C3): identity for a file without the tags.
            #expect(color.calibration.count == color.profile.calibrations.count)
            for kelvin in [2500.0, 2850, 4000, 6500, 9000] {
                let read = color.calibration(at: kelvin), written = kind.color.calibration(at: kelvin)
                #expect(zip(read.values, written.values).allSatisfy { abs($0 - $1) < 1e-6 }, "\(kind) at \(kelvin) K: \(read)")
            }
            #expect((color.calibration(at: 2850) != color.calibration(at: 6500)) == kind.hasCalibration)
            let decoded = LibRawDecoderTests.samples(output)
            let width = Int(output.size.width), height = Int(output.size.height)
            let look = try #require(BaselineLook.toneCurve)
            for balance in CameraColorTests.balances {
                for withLook in [false, true] {
                    var transform = output.step.transform(temperature: balance?.kelvin, tint: balance?.tint)
                    let exposure = withLook ? BaselineLook.exposure : 0
                    if !withLook {
                        transform.exposure = 1
                        transform.toneCurve = nil
                    }
                    let curve: ((Double) -> Double)? = withLook ? { CameraColorTransform.toneValue(look, at: $0) } : nil
                    let rendered = ReferenceTests.renderLinear(transform.apply(to: output.linear))
                    #expect(rendered.width == width && rendered.height == height)
                    let reference = CameraColorTests.reference(kind: kind, balance: balance, exposure: exposure)
                    var failures = 0, worst = 0.0, worstOver = 0.0, changed = 0.0, nearest = 0.0
                    // Every 37th pixel: 1,329 of the picture's gradients, ellipses and edges.
                    for pixel in stride(from: 0, to: width * height, by: 37) {
                        let values = (0..<3).map { Double(decoded[pixel * 4 + $0]) / 65535 }
                        let expected = reference.render(values, curve: curve)
                        let allowed = Self.tolerance(values, reference: reference, curve: curve)
                        for channel in 0..<3 {
                            let error = abs(Double(rendered.pixels[pixel * 4 + channel]) - expected[channel])
                            worst = max(worst, error)
                            nearest = max(nearest, error / allowed[channel])
                            if error > allowed[channel] {
                                failures += 1
                                worstOver = max(worstOver, error / allowed[channel])
                            }
                            changed = max(changed, abs(expected[channel] - values[channel]))
                        }
                    }
                    #expect(failures == 0, """
                        \(kind) \(String(describing: balance)) look \(withLook): \(failures) components beyond the derived \
                        tolerance, the worst \(worstOver) times it; largest difference \(worst)
                        """)
                    // The step is not a pass-through: it moves values far more than the tolerance.
                    #expect(changed > 0.05)
                    print("CameraColorStepTests: \(kind) \(balance.map { "\(Int($0.kelvin)) K, tint \(Int($0.tint))" } ?? "as shot")",
                          "look \(withLook): largest difference \(worst), at most \(nearest) of the derived tolerance")
                }
            }
        }
    }
}
