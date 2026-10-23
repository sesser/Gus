import Foundation
import ImageIO

/// In-process metadata reader built on ImageIO. Reads headers only.
public struct ImageIOMetadataReader: MetadataReader {
    public var concurrency: Int

    public init(concurrency: Int = 4) {
        self.concurrency = max(1, concurrency)
    }

    public func metadata(for urls: [URL]) async throws -> [URL: ImageMetadata] {
        try await withThrowingTaskGroup(of: (URL, ImageMetadata?).self) { group in
            var result: [URL: ImageMetadata] = [:]
            var iterator = urls.makeIterator()
            for _ in 0..<concurrency {
                guard let url = iterator.next() else { break }
                group.addTask { (url, Self.read(url)) }
            }
            while let (url, metadata) = try await group.next() {
                try Task.checkCancellation()
                result[url] = metadata
                if let next = iterator.next() {
                    group.addTask { (next, Self.read(next)) }
                }
            }
            return result
        }
    }

    public static func read(_ url: URL) -> ImageMetadata? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]
        else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exifAux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        let dateText = (exif[kCGImagePropertyExifDateTimeOriginal] ?? exif[kCGImagePropertyExifDateTimeDigitized]
            ?? tiff[kCGImagePropertyTIFFDateTime]) as? String
        let parsedDate = dateText.flatMap {
            ExifDate.parse($0, subSeconds: exif[kCGImagePropertyExifSubsecTimeOriginal] as? String,
                           offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
        }
        let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        var keywords = (iptc[kCGImagePropertyIPTCKeywords] as? [String]) ?? []
        var rating: Int?
        var label: String?
        let xmp = CGImageSourceCopyMetadataAtIndex(source, 0, options)
        if let xmp {
            keywords += xmpStrings(xmp, "dc:subject")
            rating = (CGImageMetadataCopyStringValueWithPath(xmp, nil, "xmp:Rating" as CFString) as String?)
                .flatMap { Double($0) }.map { Int($0) }
            label = CGImageMetadataCopyStringValueWithPath(xmp, nil, "xmp:Label" as CFString) as String?
        }

        var metadata = ImageMetadata(
            captureDate: parsedDate?.date,
            captureOffsetSeconds: parsedDate?.offsetSeconds,
            pixelWidth: (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            pixelHeight: (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            orientation: (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1,
            cameraMake: (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmedNonEmpty,
            cameraModel: (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmedNonEmpty,
            lensModel: ((exif[kCGImagePropertyExifLensModel] ?? exifAux[kCGImagePropertyExifAuxLensModel]) as? String)?.trimmedNonEmpty,
            iso: iso,
            exposureTime: (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue,
            fNumber: (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue,
            focalLength: (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue,
            keywords: keywords, rating: rating, label: label)

        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        func coordinate(_ value: CFString, _ reference: CFString, negative: String) -> Double? {
            guard let degrees = (gps[value] as? NSNumber)?.doubleValue else { return nil }
            return (gps[reference] as? String)?.uppercased() == negative ? -degrees : degrees
        }
        func xmpText(_ path: String) -> String? {
            guard let xmp else { return nil }
            return xmpStrings(xmp, path).joined(separator: ", ").trimmedNonEmpty
        }
        metadata.artist = (tiff[kCGImagePropertyTIFFArtist] as? String)?.trimmedNonEmpty
            ?? (iptc[kCGImagePropertyIPTCByline] as? [String])?.joined(separator: ", ").trimmedNonEmpty
            ?? xmpText("dc:creator")
        metadata.copyright = (tiff[kCGImagePropertyTIFFCopyright] as? String)?.trimmedNonEmpty
            ?? (iptc[kCGImagePropertyIPTCCopyrightNotice] as? String)?.trimmedNonEmpty
            ?? xmpText("dc:rights")
        metadata.caption = xmpText("dc:description")
            ?? (iptc[kCGImagePropertyIPTCCaptionAbstract] as? String)?.trimmedNonEmpty
            ?? (tiff[kCGImagePropertyTIFFImageDescription] as? String)?.trimmedNonEmpty
        metadata.cameraSerial = (exif[kCGImagePropertyExifBodySerialNumber] as? String)?.trimmedNonEmpty
        metadata.latitude = coordinate(kCGImagePropertyGPSLatitude, kCGImagePropertyGPSLatitudeRef, negative: "S")
        metadata.longitude = coordinate(kCGImagePropertyGPSLongitude, kCGImagePropertyGPSLongitudeRef, negative: "W")
        metadata.flashFired = (exif[kCGImagePropertyExifFlash] as? NSNumber).map { $0.intValue & 1 == 1 }
        metadata.exposureCompensation = (exif[kCGImagePropertyExifExposureBiasValue] as? NSNumber)?.doubleValue
        metadata.whiteBalance = (exif[kCGImagePropertyExifWhiteBalance] as? NSNumber)?.intValue
        metadata.exposureProgram = (exif[kCGImagePropertyExifExposureProgram] as? NSNumber)?.intValue
        metadata.meteringMode = (exif[kCGImagePropertyExifMeteringMode] as? NSNumber)?.intValue
        metadata.focalLength35mm = (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.doubleValue
        metadata.usageTerms = xmpText("xmpRights:UsageTerms")
        return metadata
    }

    /// The items of an XMP array (bag or sequence) of text values.
    static func xmpStrings(_ metadata: CGImageMetadata, _ path: String) -> [String] {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
              let value = CGImageMetadataTagCopyValue(tag) else { return [] }
        if let items = value as? [CGImageMetadataTag] {
            return items.compactMap { CGImageMetadataTagCopyValue($0) as? String }
        }
        return (value as? String).map { [$0] } ?? []
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return trimmed.isEmpty ? nil : trimmed
    }
}
