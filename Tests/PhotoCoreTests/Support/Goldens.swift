import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

/// A rendered image as 16-bit RGB in the renderer's perceptual encoding
/// (Rec. 2020 primaries, sRGB transfer curve): the format goldens are stored
/// in. Values outside 0 … 1 are clipped by the encoding, the same way for the
/// golden and for the render it is compared with.
struct EncodedImage: Equatable {
    static let colorSpace = AdjustmentRenderer.perceptualSpace

    var width: Int
    var height: Int
    /// Red, green, blue and an unused fourth value per pixel.
    var samples: [UInt16]

    init(width: Int, height: Int, samples: [UInt16]) {
        self.width = width
        self.height = height
        self.samples = samples
    }

    /// Renders `image` (its extent at the origin) through `engine`, as export does.
    init(rendering image: CIImage, engine: RenderEngine) throws {
        guard let cgImage = engine.makeCGImage(image, colorSpace: Self.colorSpace, bitsPerComponent: 16),
              let encoded = EncodedImage(cgImage: cgImage)
        else { throw GoldenError.renderFailed }
        self = encoded
    }

    /// Draws `cgImage` into a 16-bit context in the golden color space. A PNG
    /// written by `writePNG` comes back unchanged (checked by `GoldenHarnessTests`).
    init?(cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height
        samples = [UInt16](repeating: 0, count: width * height * 4)
        let drawn = samples.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = Self.context(buffer.baseAddress, width: cgImage.width, height: cgImage.height)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            return true
        }
        guard drawn else { return nil }
    }

    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        self.init(cgImage: image)
    }

    private static func context(_ data: UnsafeMutableRawPointer?, width: Int, height: Int) -> CGContext? {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 16, bytesPerRow: width * 8,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
    }

    func cgImage() -> CGImage? {
        var copy = samples
        return copy.withUnsafeMutableBytes { Self.context($0.baseAddress, width: width, height: height)?.makeImage() }
    }

    /// Writes a 16-bit PNG tagged with the golden color space.
    func writePNG(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let image = cgImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw GoldenError.writeFailed(url) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GoldenError.writeFailed(url) }
    }

    /// Channel `channel` (0 red, 1 green, 2 blue) of a pixel, 0 … 1.
    func value(_ x: Int, _ y: Int, _ channel: Int) -> Double {
        Double(samples[(y * width + x) * 4 + channel]) / 65535
    }

    func color(_ x: Int, _ y: Int) -> SIMD3<Double> {
        SIMD3(value(x, y, 0), value(x, y, 1), value(x, y, 2))
    }

    /// Expected, actual and their absolute difference times `gain`, side by side.
    static func sideBySide(expected: EncodedImage, actual: EncodedImage, gain: Double = 8) -> EncodedImage {
        let width = max(expected.width, actual.width)
        let height = max(expected.height, actual.height)
        var samples = [UInt16](repeating: 0, count: width * 3 * height * 4)
        func put(_ image: EncodedImage, column: Int) {
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let from = (y * image.width + x) * 4
                    let to = (y * width * 3 + column * width + x) * 4
                    samples.replaceSubrange(to..<(to + 4), with: image.samples[from..<(from + 4)])
                }
            }
        }
        put(expected, column: 0)
        put(actual, column: 1)
        for y in 0..<min(expected.height, actual.height) {
            for x in 0..<min(expected.width, actual.width) {
                let to = (y * width * 3 + 2 * width + x) * 4
                for c in 0..<3 {
                    let difference = abs(expected.value(x, y, c) - actual.value(x, y, c)) * gain
                    samples[to + c] = UInt16(min(difference, 1) * 65535)
                }
            }
        }
        return EncodedImage(width: width * 3, height: height, samples: samples)
    }
}

enum GoldenError: Error {
    case renderFailed
    case writeFailed(URL)
}

/// How two encoded images differ.
struct ImageDifference: CustomStringConvertible {
    /// Largest absolute difference per channel (red, green, blue), in encoded units 0 … 1.
    var maxChannel: SIMD3<Double>
    /// Peak signal-to-noise ratio over the three channels, peak 1; infinite when identical.
    var psnr: Double
    /// Color difference in OkLab (Euclidean; L runs 0 … 1), mean and largest.
    var meanDeltaE: Double
    var maxDeltaE: Double
    var sizesMatch: Bool

    init(expected: EncodedImage, actual: EncodedImage) {
        sizesMatch = expected.width == actual.width && expected.height == actual.height
        guard sizesMatch, expected.width > 0, expected.height > 0 else {
            maxChannel = SIMD3(repeating: 1)
            psnr = 0
            meanDeltaE = 1
            maxDeltaE = 1
            return
        }
        var maxChannel = SIMD3<Double>.zero
        var squares = 0.0
        var sumDeltaE = 0.0
        var maxDeltaE = 0.0
        for y in 0..<expected.height {
            for x in 0..<expected.width {
                let a = expected.color(x, y)
                let b = actual.color(x, y)
                let signed = a - b
                let difference = SIMD3(abs(signed.x), abs(signed.y), abs(signed.z))
                maxChannel = pointwiseMax(maxChannel, difference)
                squares += (difference * difference).sum()
                guard a != b else { continue }
                let deltaE = (ColorMath.okLab(perceptualRec2020: a) - ColorMath.okLab(perceptualRec2020: b))
                let distance = (deltaE * deltaE).sum().squareRoot()
                sumDeltaE += distance
                maxDeltaE = max(maxDeltaE, distance)
            }
        }
        let count = Double(expected.width * expected.height)
        self.maxChannel = maxChannel
        let meanSquare = squares / (count * 3)
        psnr = meanSquare == 0 ? .infinity : 10 * log10(1 / meanSquare)
        meanDeltaE = sumDeltaE / count
        self.maxDeltaE = maxDeltaE
    }

    var description: String {
        guard sizesMatch else { return "sizes differ" }
        let channels = [maxChannel.x, maxChannel.y, maxChannel.z].map { String(format: "%.5f", $0) }.joined(separator: "/")
        return "max |Δ| r/g/b \(channels), PSNR \(String(format: "%.1f", psnr)) dB, "
            + "OkLab ΔE mean \(String(format: "%.5f", meanDeltaE)) max \(String(format: "%.5f", maxDeltaE))"
    }
}

/// What a golden test accepts as "the same image", and why.
struct GoldenTolerance: Sendable {
    /// Largest absolute difference allowed in any channel, encoded units 0 … 1.
    var maxChannel: Double
    var minimumPSNR: Double
    var meanDeltaE: Double
    var maxDeltaE: Double
    var reason: String

    func accepts(_ difference: ImageDifference) -> Bool {
        difference.sizesMatch && difference.maxChannel.max() <= maxChannel && difference.psnr >= minimumPSNR
            && difference.meanDeltaE <= meanDeltaE && difference.maxDeltaE <= maxDeltaE
    }
}

/// Stored renders under `Tests/PhotoCoreTests/Goldens`, found from this file's
/// path so the test target needs no resources.
///
/// `UPDATE_GOLDENS=1 swift test` rewrites the goldens that changed and prints
/// each one. Otherwise a missing golden fails, and a mismatch writes expected,
/// actual and an 8× difference side by side into a temporary folder.
enum Goldens {
    static let directory = RepositoryFiles.url("Tests/PhotoCoreTests/Goldens")
    static let failureDirectory = FileManager.default.temporaryDirectory.appending(path: "golden-failures",
                                                                                     directoryHint: .isDirectory)

    static var isUpdating: Bool { ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" }

    /// Goldens render through a Metal context with the app's options. Core
    /// Image has no software renderer on Apple silicon (see docs/PHASE5_PLAN.md),
    /// so the tolerances allow for another GPU.
    static let engine = RenderEngine(contextCount: 2, name: "goldens")

    static func url(_ name: String) -> URL {
        directory.appending(path: "\(name).png", directoryHint: .notDirectory)
    }

    /// Renders `image` and compares it with the golden `name`.
    static func check(_ name: String, _ image: CIImage, tolerance: GoldenTolerance,
                      sourceLocation: SourceLocation = #_sourceLocation) throws {
        let actual = try EncodedImage(rendering: image, engine: engine)
        try check(name, actual, tolerance: tolerance, sourceLocation: sourceLocation)
    }

    static func check(_ name: String, _ actual: EncodedImage, tolerance: GoldenTolerance,
                      sourceLocation: SourceLocation = #_sourceLocation) throws {
        let url = url(name)
        let expected = EncodedImage(contentsOf: url)
        if isUpdating {
            if expected != actual {
                try actual.writePNG(to: url)
                print("golden updated: \(url.path)")
            }
            return
        }
        guard let expected else {
            Issue.record("Missing golden \(url.path). Run UPDATE_GOLDENS=1 swift test to create it.",
                         sourceLocation: sourceLocation)
            return
        }
        let difference = ImageDifference(expected: expected, actual: actual)
        if ProcessInfo.processInfo.environment["GOLDENS_REPORT"] == "1" {
            print("golden \(name): \(difference)")
        }
        guard !tolerance.accepts(difference) else { return }
        let failure = failureDirectory.appending(path: "\(name).png", directoryHint: .notDirectory)
        try EncodedImage.sideBySide(expected: expected, actual: actual).writePNG(to: failure)
        Issue.record("""
            Golden \(name) differs: \(difference). Tolerance (\(tolerance.reason)): max |Δ| \(tolerance.maxChannel), \
            PSNR ≥ \(tolerance.minimumPSNR) dB, ΔE mean ≤ \(tolerance.meanDeltaE) max ≤ \(tolerance.maxDeltaE). \
            Expected | actual | 8× difference: \(failure.path)
            """, sourceLocation: sourceLocation)
    }
}
