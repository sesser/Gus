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
        /// IPTC Keywords.
        public var keywords: [String]
        /// XMP values, written the way other photo apps embed them.
        public var xmpRating: Int?
        public var xmpLabel: String?
        public var xmpSubject: [String]
        public var artist: String?
        public var copyright: String?
        public var serialNumber: String?
        /// Degrees; south and west negative.
        public var latitude: Double?
        public var longitude: Double?
        /// EXIF Flash value (bit 0: fired).
        public var flash: Int?
        public var exposureBias: Double?
        public var whiteBalance: Int?

        public init(dateTimeOriginal: String? = nil, offsetTimeOriginal: String? = nil,
                    make: String? = "Synthetic", model: String? = "Generator", orientation: Int = 1,
                    keywords: [String] = [], xmpRating: Int? = nil, xmpLabel: String? = nil,
                    xmpSubject: [String] = []) {
            self.dateTimeOriginal = dateTimeOriginal
            self.offsetTimeOriginal = offsetTimeOriginal
            self.make = make
            self.model = model
            self.orientation = orientation
            self.keywords = keywords
            self.xmpRating = xmpRating
            self.xmpLabel = xmpLabel
            self.xmpSubject = xmpSubject
        }

        var hasXMP: Bool { xmpRating != nil || xmpLabel != nil || !xmpSubject.isEmpty }
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
        exifDictionary[kCGImagePropertyExifBodySerialNumber] = exif.serialNumber
        exifDictionary[kCGImagePropertyExifFlash] = exif.flash
        exifDictionary[kCGImagePropertyExifExposureBiasValue] = exif.exposureBias
        exifDictionary[kCGImagePropertyExifWhiteBalance] = exif.whiteBalance
        var tiffDictionary: [CFString: Any] = [:]
        tiffDictionary[kCGImagePropertyTIFFMake] = exif.make
        tiffDictionary[kCGImagePropertyTIFFModel] = exif.model
        tiffDictionary[kCGImagePropertyTIFFArtist] = exif.artist
        tiffDictionary[kCGImagePropertyTIFFCopyright] = exif.copyright
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: exif.orientation,
            kCGImagePropertyExifDictionary: exifDictionary,
            kCGImagePropertyTIFFDictionary: tiffDictionary,
        ]
        if !exif.keywords.isEmpty {
            properties[kCGImagePropertyIPTCDictionary] = [kCGImagePropertyIPTCKeywords: exif.keywords]
        }
        if let latitude = exif.latitude, let longitude = exif.longitude {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: abs(latitude), kCGImagePropertyGPSLatitudeRef: latitude < 0 ? "S" : "N",
                kCGImagePropertyGPSLongitude: abs(longitude), kCGImagePropertyGPSLongitudeRef: longitude < 0 ? "W" : "E",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        if exif.hasXMP { try addXMP(exif, to: url, type: type) }
    }

    /// Merges XMP into the written file without re-encoding the image.
    private static func addXMP(_ exif: Exif, to url: URL, type: UTType) throws {
        let metadata = CGImageMetadataCreateMutable()
        if let rating = exif.xmpRating {
            CGImageMetadataSetValueWithPath(metadata, nil, "xmp:Rating" as CFString, String(rating) as CFString)
        }
        if let label = exif.xmpLabel {
            CGImageMetadataSetValueWithPath(metadata, nil, "xmp:Label" as CFString, label as CFString)
        }
        if !exif.xmpSubject.isEmpty,
           let tag = CGImageMetadataTagCreate(kCGImageMetadataNamespaceDublinCore, kCGImageMetadataPrefixDublinCore,
                                              "subject" as CFString, .arrayUnordered, exif.xmpSubject as CFArray) {
            CGImageMetadataSetTagWithPath(metadata, nil, "dc:subject" as CFString, tag)
        }
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let options: [CFString: Any] = [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: true]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? CocoaError(.fileWriteUnknown)
        }
        try (output as Data).write(to: url)
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
