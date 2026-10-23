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

        return ImageMetadata(
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
            focalLength: (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue)
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return trimmed.isEmpty ? nil : trimmed
    }
}
