import CoreGraphics
import Foundation

/// Everything that decides what an export writes, apart from the destination
/// folder. Export presets store it as JSON, so its keys are generic and every
/// field decodes with a default when missing: presets saved by an earlier
/// build keep working.
///
/// The fields of every mode are kept side by side (the box size and the edge
/// length, for instance), so switching modes in the export window and back
/// does not lose what was typed.
public struct ExportSettings: Codable, Hashable, Sendable {
    public enum Naming: String, Codable, Hashable, Sendable, CaseIterable {
        /// The master's file name with the output extension.
        case original
        /// `fileNameTemplate`, with the tokens of `ImportTemplate`.
        case template
    }

    public enum FileFormat: String, Codable, Hashable, Sendable, CaseIterable {
        case jpeg
        case tiff

        public var fileExtension: String {
            switch self {
            case .jpeg: "jpg"
            case .tiff: "tif"
            }
        }
    }

    public enum TIFFCompression: String, Codable, Hashable, Sendable, CaseIterable {
        case none
        case lzw
        case zip

        /// The TIFF Compression tag value.
        var tagValue: Int {
            switch self {
            case .none: 1
            case .lzw: 5
            case .zip: 8
            }
        }
    }

    public enum ColorSpace: String, Codable, Hashable, Sendable, CaseIterable {
        case sRGB
        case displayP3
        case adobeRGB
        case proPhoto

        public var cgColorSpace: CGColorSpace {
            let name = switch self {
            case .sRGB: CGColorSpace.sRGB
            case .displayP3: CGColorSpace.displayP3
            case .adobeRGB: CGColorSpace.adobeRGB1998
            case .proPhoto: CGColorSpace.rommrgb
            }
            return CGColorSpace(name: name)!
        }

        /// Wide enough that 8 bits per channel can show banding in smooth gradients.
        public var prefersHighBitDepth: Bool { self == .proPhoto }
    }

    public enum Sizing: String, Codable, Hashable, Sendable, CaseIterable {
        /// The rendered master's own size.
        case full
        /// Fits inside `boxWidth` × `boxHeight`, keeping the aspect ratio.
        case fit
        case longEdge
        case shortEdge
        case percent
    }

    public enum SharpeningAmount: String, Codable, Hashable, Sendable, CaseIterable {
        case off
        case light
        case standard
        case strong
    }

    public enum SharpeningTarget: String, Codable, Hashable, Sendable, CaseIterable {
        case screen
        case print
    }

    public enum Metadata: String, Codable, Hashable, Sendable, CaseIterable {
        /// The master's metadata, with the library's keywords and descriptive fields.
        case all
        /// As `all`, without GPS coordinates or IPTC location fields.
        case noLocation
        /// Only the creator and their job title, copyright, usage terms and contact details.
        case copyright
        /// Nothing but the color profile and resolution.
        case none
    }

    public var naming: Naming = .original
    public var fileNameTemplate: String = "{name}"

    public var format: FileFormat = .jpeg
    /// 0 … 1.
    public var jpegQuality: Double = 0.9
    /// 8 or 16.
    public var tiffBitDepth: Int = 16
    public var tiffCompression: TIFFCompression = .zip
    public var colorSpace: ColorSpace = .sRGB

    public var sizing: Sizing = .full
    public var boxWidth: Int = 2048
    public var boxHeight: Int = 2048
    public var edgeLength: Int = 2048
    /// 1 … 100.
    public var percent: Double = 50
    /// Pixels per inch written to the file; only changes how big it prints.
    public var ppi: Int = 300

    /// Applied only when the export is smaller than the rendered master.
    public var sharpening: SharpeningAmount = .off
    public var sharpeningTarget: SharpeningTarget = .screen

    public var metadata: Metadata = .all

    public var watermarkEnabled = false
    /// Kept while the watermark is turned off, so turning it back on restores it.
    public var watermark: Watermark?

    public init() {}

    public var bitsPerComponent: Int {
        format == .tiff && tiffBitDepth == 16 ? 16 : 8
    }

    /// The watermark the export draws, if any.
    public var activeWatermark: Watermark? {
        watermarkEnabled ? watermark : nil
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case naming, fileNameTemplate, format, jpegQuality, tiffBitDepth, tiffCompression, colorSpace
        case sizing, boxWidth, boxHeight, edgeLength, percent, ppi, sharpening, sharpeningTarget, metadata
        case watermarkEnabled, watermark
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ExportSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            // An unknown enum case (from a later build) falls back too.
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        naming = value(.naming, defaults.naming)
        fileNameTemplate = value(.fileNameTemplate, defaults.fileNameTemplate)
        format = value(.format, defaults.format)
        jpegQuality = value(.jpegQuality, defaults.jpegQuality)
        tiffBitDepth = value(.tiffBitDepth, defaults.tiffBitDepth)
        tiffCompression = value(.tiffCompression, defaults.tiffCompression)
        colorSpace = value(.colorSpace, defaults.colorSpace)
        sizing = value(.sizing, defaults.sizing)
        boxWidth = value(.boxWidth, defaults.boxWidth)
        boxHeight = value(.boxHeight, defaults.boxHeight)
        edgeLength = value(.edgeLength, defaults.edgeLength)
        percent = value(.percent, defaults.percent)
        ppi = value(.ppi, defaults.ppi)
        sharpening = value(.sharpening, defaults.sharpening)
        sharpeningTarget = value(.sharpeningTarget, defaults.sharpeningTarget)
        metadata = value(.metadata, defaults.metadata)
        watermarkEnabled = value(.watermarkEnabled, defaults.watermarkEnabled)
        watermark = value(.watermark, defaults.watermark)
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func decode(from json: String) throws -> ExportSettings {
        try JSONDecoder().decode(ExportSettings.self, from: Data(json.utf8))
    }
}

/// A PNG (usually with transparency) drawn over every exported image.
public struct Watermark: Codable, Hashable, Sendable {
    /// Where the watermark sits; the margin keeps it off the edges it is
    /// anchored to.
    public enum Anchor: String, Codable, Hashable, Sendable, CaseIterable {
        case topLeft, top, topRight
        case left, center, right
        case bottomLeft, bottom, bottomRight
    }

    public static let sizeRange: ClosedRange<Double> = 2...100
    public static let marginRange: ClosedRange<Double> = 0...25

    /// The file's identifier in the `WatermarkStore` (its SHA-256).
    public var identifier: String
    /// The file name it was chosen from, for showing.
    public var name: String
    public var anchor: Anchor = .bottomRight
    /// Percent of the image's long edge between the watermark and the edges it is anchored to.
    public var margin: Double = 3
    /// The watermark's long side, in percent of the image's long edge.
    public var size: Double = 20
    /// 0 … 1.
    public var opacity: Double = 0.8

    public init(identifier: String, name: String, anchor: Anchor = .bottomRight, margin: Double = 3,
                size: Double = 20, opacity: Double = 0.8) {
        self.identifier = identifier
        self.name = name
        self.anchor = anchor
        self.margin = margin
        self.size = size
        self.opacity = opacity
    }
}
