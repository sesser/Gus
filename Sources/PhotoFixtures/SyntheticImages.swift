import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deterministic generated images for tests and benchmarks. Every seed produces
/// different pixels (the seed is drawn into the image as a bar code), so files
/// written with different seeds never share a content hash.
public enum SyntheticImages {
    public struct Exif: Sendable {
        /// "yyyy:MM:dd HH:mm:ss"
        public var dateTimeOriginal: String?
        public var offsetTimeOriginal: String?
        public var make: String?
        public var model: String?
        public var orientation: Int

        public init(dateTimeOriginal: String? = nil, offsetTimeOriginal: String? = nil,
                    make: String? = "Synthetic", model: String? = "Generator", orientation: Int = 1) {
            self.dateTimeOriginal = dateTimeOriginal
            self.offsetTimeOriginal = offsetTimeOriginal
            self.make = make
            self.model = model
            self.orientation = orientation
        }
    }

    /// Renders the test pattern for `seed` as an sRGB image.
    public static func makeImage(width: Int, height: Int, seed: UInt64) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        var random = SplitMix64(seed: seed)
        let hue = Double(random.next() % 360) / 360
        let top = color(hue: hue, saturation: 0.55, brightness: 0.85)
        let bottom = color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.35)
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [top, bottom] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])

        for _ in 0..<12 {
            let w = Double(random.next() % UInt64(max(width / 3, 1))) + 4
            let h = Double(random.next() % UInt64(max(height / 3, 1))) + 4
            let x = Double(random.next() % UInt64(max(width, 1)))
            let y = Double(random.next() % UInt64(max(height, 1)))
            context.setFillColor(color(hue: Double(random.next() % 360) / 360, saturation: 0.6,
                                       brightness: Double(random.next() % 100) / 100, alpha: 0.6))
            context.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
        }

        // 64-bit bar code of the seed along the bottom edge.
        let cell = max(2, width / 80)
        for bit in 0..<64 {
            let on = (seed >> UInt64(bit)) & 1 == 1
            context.setFillColor(on ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: cell * (bit + 4), y: cell, width: cell, height: cell * 2))
        }
        return context.makeImage()
    }

    /// Writes a JPEG with EXIF capture date, camera and orientation tags.
    public static func writeJPEG(to url: URL, width: Int, height: Int, seed: UInt64,
                                 exif: Exif = Exif(), quality: Double = 0.8) throws {
        guard let image = makeImage(width: width, height: height, seed: seed) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try write(image, to: url, type: .jpeg, exif: exif, quality: quality)
    }

    public static func write(_ image: CGImage, to url: URL, type: UTType, exif: Exif = Exif(),
                             quality: Double = 0.8) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var exifDictionary: [CFString: Any] = [:]
        exifDictionary[kCGImagePropertyExifDateTimeOriginal] = exif.dateTimeOriginal
        exifDictionary[kCGImagePropertyExifOffsetTimeOriginal] = exif.offsetTimeOriginal
        var tiffDictionary: [CFString: Any] = [:]
        tiffDictionary[kCGImagePropertyTIFFMake] = exif.make
        tiffDictionary[kCGImagePropertyTIFFModel] = exif.model
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: exif.orientation,
            kCGImagePropertyExifDictionary: exifDictionary,
            kCGImagePropertyTIFFDictionary: tiffDictionary,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func color(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) -> CGColor {
        let h = hue * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) % 6 {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return CGColor(srgbRed: r + m, green: g + m, blue: b + m, alpha: alpha)
    }
}

/// Small, fast, seedable PRNG.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
