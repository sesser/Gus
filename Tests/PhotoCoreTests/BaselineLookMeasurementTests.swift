import CoreImage
import Foundation
import Testing
@testable import PhotoCore

/// Where `BaselineLook`'s numbers come from (issue #170, R6): measured
/// against the system's RAW decoder on raws both decoders read.
///
/// `RAW_LOOK_SAMPLES=a.RAF:b.ARW:c.CR2 swift test --filter BaselineLookMeasurementTests`
///
/// The first file is the one the look's exposure and black offset are taken
/// from: a Fujifilm X-E3's that the system decoder reads (an uncompressed
/// one: raw.pixls.us has `DSCF2175.RAF`; it gives no image for the camera's
/// lossless-compressed files, which is why LibRaw decodes them). The tone
/// curve is the middle of all the files'. Run it on a new macOS: the system
/// decoder's look can change, and the test then says by how much the
/// built-in look is off.
///
/// Two measurements:
///
/// 1. **The boost curve.** The system decoder's default render against its
///    own render with `boostAmount` 0, pixel for pixel (the same decode, so
///    nothing has to be lined up), each channel of the working space, in
///    the sRGB encoding. One curve fits every camera tried between 0.25 and
///    0.62 to ±0.002; an Olympus has less shadow contrast and two files
///    differ in their highlights, which the middle of nine leaves out.
/// 2. **Exposure and black.** The system decoder's boost-0 render against
///    LibRaw's decode through the color step without a look: a straight
///    line, system = gain × LibRaw − offset. The gain differs by camera (the
///    system decoder has a baseline exposure for each); the offset is 0.0025
///    to 0.0046 for all.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RAW_LOOK_SAMPLES"] != nil,
                "Set RAW_LOOK_SAMPLES to raws both decoders read, separated by colons, and run this suite alone"))
struct BaselineLookMeasurementTests {
    static var files: [URL] {
        (ProcessInfo.processInfo.environment["RAW_LOOK_SAMPLES"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
    }

    static func pixels(_ image: CIImage, longEdge: Int? = nil) -> (width: Int, height: Int, values: [Float]) {
        let scaled = longEdge.map { image.scaledToFit(longEdge: $0) } ?? image
        let extent = scaled.extent.integral
        let moved = scaled.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let linear = ReferenceTests.renderLinear(moved.cropped(to: CGRect(origin: .zero, size: extent.size)))
        return (linear.width, linear.height, linear.pixels)
    }

    static func median(_ values: [Double]) -> Double {
        values.isEmpty ? .nan : values.sorted()[values.count / 2]
    }

    /// A LibRaw decode through the color step with no look: linear light.
    static func withoutLook(_ output: LibRawDecoder.Output) -> CIImage {
        var transform = output.step.transform(temperature: nil, tint: nil)
        transform.exposure = 1
        transform.toneCurve = nil
        return transform.apply(to: output.linear)
    }

    /// Bins a 128th of the encoded range wide, centered on the multiples of a 128th.
    static let bins = 128

    /// The boost curve of one file: the median encoded default value for each bin of the encoded boost-0 value.
    static func boostCurve(_ url: URL) throws -> [Double] {
        let standard = pixels(try PreviewGenerator.decode(url, longEdge: 1200, draft: false).image)
        let flat = pixels(try PreviewGenerator.decode(url, longEdge: 1200, draft: false,
                                                      settings: RAWDecodeSettings(boostAmount: 0)).image)
        var samples = [[Double]](repeating: [], count: bins + 1)
        for index in stride(from: 0, to: flat.values.count, by: 4) {
            for channel in 0..<3 {
                let x = Double(flat.values[index + channel]), y = Double(standard.values[index + channel])
                guard x >= 0, x <= 1, y >= 0 else { continue }
                let bin = Int((CameraColorTransform.encoded(x) * Double(bins)).rounded())
                samples[bin].append(CameraColorTransform.encoded(y))
            }
        }
        return samples.map { $0.count >= 200 ? median($0) : .nan }
    }

    /// flat = gain × linear − offset. Fitted as flat / linear = gain − offset / linear to the
    /// medians of half-stop classes of the LibRaw value between 0.004 and 0.3, each class
    /// counting the same: fitted to the values themselves, the brightest classes alone would
    /// decide both numbers, and the offset only shows in the dark ones. (Below 0.004 the system
    /// decoder's values reach 0; above 0.3 its highlights are no longer a straight line for
    /// every file.)
    static func exposureAndBlack(_ url: URL) throws -> (gain: Double, offset: Double) {
        let size = 300
        let libRaw = pixels(withoutLook(try LibRawDecoder.decode(url, longEdge: 1500)), longEdge: size)
        let flat = pixels(try PreviewGenerator.decode(url, longEdge: 1500, draft: false,
                                                      settings: RAWDecodeSettings(boostAmount: 0)).image, longEdge: size)
        guard libRaw.width == flat.width, libRaw.height == flat.height else { return (.nan, .nan) }
        var classes: [Int: [(Double, Double)]] = [:]
        for y in 10..<(libRaw.height - 10) {
            for x in 10..<(libRaw.width - 10) {
                // Green: the channel the two decoders' matrices agree on best.
                let index = (y * libRaw.width + x) * 4 + 1
                let a = Double(libRaw.values[index]), b = Double(flat.values[index])
                guard a > 0.004, a < 0.3 else { continue }
                classes[Int((log2(a) * 2).rounded(.down)), default: []].append((a, b))
            }
        }
        // x = 1 / linear, y = flat / linear: y = gain − offset × x.
        let points = classes.values.filter { $0.count > 100 }.map { values -> (Double, Double) in
            let a = median(values.map(\.0)), b = median(values.map(\.1))
            return (1 / a, b / a)
        }
        let n = Double(points.count), sx = points.map(\.0).reduce(0, +), sy = points.map(\.1).reduce(0, +)
        let sxx = points.map { $0.0 * $0.0 }.reduce(0, +), sxy = points.map { $0.0 * $0.1 }.reduce(0, +)
        let slope = (n * sxy - sx * sy) / (n * sxx - sx * sx)
        return ((sy - slope * sx) / n, -slope)
    }

    @Test("The system decoder's boost curve, its exposure and black against LibRaw's, and the look made of them")
    func measure() throws {
        let files = Self.files
        let curves = try files.map(Self.boostCurve)
        // The middle of the files for each bin.
        var boost = (0...Self.bins).map { bin in Self.median(curves.map { $0[bin] }.filter { !$0.isNaN }) }
        boost[0] = 0
        boost[Self.bins] = 1
        func boosted(_ encoded: Double) -> Double {
            let position = min(max(encoded, 0), 1) * Double(Self.bins)
            let low = Int(position.rounded(.down)), high = min(low + 1, Self.bins)
            let t = position - Double(low)
            return boost[low] * (1 - t) + boost[high] * t
        }
        print("BaselineLookMeasurementTests: boost curve (encoded boost-0 value, encoded default value, each file's)")
        for bin in stride(from: 0, through: Self.bins, by: 4) {
            let each = curves.map { $0[bin].isNaN ? "   -  " : String(format: "%.4f", $0[bin]) }.joined(separator: " ")
            print(String(format: "  %.5f  %.4f   | %@", Double(bin) / Double(Self.bins), boost[bin], each))
        }
        var first: (gain: Double, offset: Double)?
        for url in files {
            let fit = try Self.exposureAndBlack(url)
            if first == nil { first = fit }
            let raw = CIRAWFilter(imageURL: url)
            print(String(format: "BaselineLookMeasurementTests: %@: system = %.4f × LibRaw − %.5f (%.3f EV; the system decoder's baseline exposure %.2f)",
                         url.lastPathComponent, fit.gain, fit.offset, log2(fit.gain), raw?.baselineExposure ?? .nan))
        }
        let reference = try #require(first)
        // The look: the exposure of the first file, then its black offset and the boost curve as one tone curve.
        print(String(format: "BaselineLookMeasurementTests: exposure %.3f EV; tone curve knots (encoded in, encoded out):",
                     log2(reference.gain)))
        var worst = 0.0
        for knot in 0...32 {
            let input = Double(knot) / 32
            let linear = CameraColorTransform.linear(input) - reference.offset
            let output = linear <= 0 ? 0 : boosted(CameraColorTransform.encoded(linear))
            print(String(format: "    (%.5f, %.4f),", input, knot == 32 ? Double(1) : output))
            if let curve = BaselineLook.toneCurve {
                let built = CameraColorTransform.encoded(CameraColorTransform.toneValue(curve, at: CameraColorTransform.linear(input)))
                worst = max(worst, abs(built - (knot == 32 ? 1 : output)))
            }
        }
        // The built-in look against today's measurement.
        if BaselineLook.toneCurve != nil {
            print(String(format: "BaselineLookMeasurementTests: the built-in curve is within %.4f of this measurement at its knots; its exposure %.3f EV against %.3f",
                         worst, BaselineLook.exposure, log2(reference.gain)))
            // A hundredth of the encoded range is 2.5 levels of 8 bits; 0.05 EV is under a twentieth of a stop.
            #expect(worst < 0.01)
            #expect(abs(BaselineLook.exposure - log2(reference.gain)) < 0.05)
        }
    }
}
