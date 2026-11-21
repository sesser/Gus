import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The file a merge writes (PRD R5): a tone-mapped 16-bit TIFF in Display P3,
/// or a linear 32-bit floating-point DNG of the merged light.
public enum MergeFormat: String, Sendable, Hashable, CaseIterable, Codable {
    case tiff
    case dng

    public var fileExtension: String {
        switch self {
        case .tiff: "tif"
        case .dng: "dng"
        }
    }
}

/// Renders a merge and writes its file. The file is written under a hidden
/// temporary name in the destination folder and moved into place only when
/// it is complete; the move never replaces anything (R4, R11). A failure or
/// a cancellation removes the temporary file.
public enum MergeOutput {
    public enum Failure: Error, Equatable, Sendable {
        case renderFailed
        /// The file couldn't be written; the system's reason.
        case writeFailed(String)
        /// Not enough space on the destination's volume.
        case noSpace
        /// A file appeared under the chosen name meanwhile.
        case nameTaken
    }

    /// What the result carries of the reference photo (R7).
    public struct Metadata: Sendable {
        /// The reference master's ImageIO properties (EXIF, TIFF, GPS, IPTC).
        public var sourceProperties: [String: any Sendable]
        /// The library's values for the reference: rating, flag, label,
        /// keywords and the descriptive fields.
        public var values: SidecarValues

        public init(sourceProperties: [String: any Sendable], values: SidecarValues) {
            self.sourceProperties = sourceProperties
            self.values = values
        }

        /// The properties of `url`'s first image, as ImageIO reads them.
        public static func properties(of url: URL) -> [String: any Sendable] {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
            else { return [:] }
            return sendable(properties)
        }

        /// A property list's values, kept as the plist types they are
        /// (strings, numbers, dates, data, arrays and dictionaries of them).
        static func sendable(_ dictionary: [String: Any]) -> [String: any Sendable] {
            dictionary.compactMapValues(sendableValue)
        }

        private static func sendableValue(_ value: Any) -> (any Sendable)? {
            switch value {
            case let nested as [String: Any]: sendable(nested)
            case let array as [Any]: array.compactMap(sendableValue)
            case let string as String: string
            case let number as NSNumber: number.doubleValue == number.doubleValue.rounded() && !(number is Bool)
                ? (number.int64Value as any Sendable) : (number.doubleValue as any Sendable)
            case let date as Date: date
            case let data as Data: data
            default: nil
            }
        }

        var cfProperties: [CFString: Any] {
            Dictionary(uniqueKeysWithValues: sourceProperties.map { ($0.key as CFString, $0.value as Any) })
        }
    }

    /// Renders `image` (tone mapped, linear Rec. 2020, 0 to 1) to a 16-bit
    /// Display P3 TIFF at `url`.
    public static func writeTIFF(_ image: CIImage, context: CIContext, metadata: Metadata, to url: URL) throws {
        let extent = image.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        let space = RenderEngine.outputColorSpace
        let rowBytes = width * 8
        var data = Data(count: rowBytes * height)
        try data.withUnsafeMutableBytes { buffer in
            try renderInBands(image, extent: extent) { band, firstRow in
                context.render(image, toBitmap: buffer.baseAddress! + firstRow * rowBytes, rowBytes: rowBytes,
                               bounds: band, format: .RGBA16, colorSpace: space)
            }
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
                                    bytesPerRow: rowBytes, space: space,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
                                        | CGImageByteOrderInfo.order16Little.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw Failure.renderFailed }
        let (properties, xmp) = tiffMetadata(metadata)
        try writeInPlace(url) { temporary in
            guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.tiff.identifier as CFString,
                                                                    1, nil)
            else { throw Failure.writeFailed("") }
            CGImageDestinationAddImageAndMetadata(destination, cgImage, xmp, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw Failure.writeFailed("") }
        }
    }

    /// Renders `radiance` (the merged light, linear Rec. 2020, the
    /// reference's white at 1) to a linear floating-point DNG at `url`, a
    /// band of rows at a time.
    ///
    /// The values are divided by `brightest` (when above 1) so the brightest
    /// light is the file's white, and `BaselineExposure` brings the
    /// reference's exposure back: the system's RAW decoder cuts what is above
    /// a DNG's white (status.md, "Spike 1"), while it shows what is below
    /// white as bright as the file asks, with its extended range for the
    /// loupe's HDR view.
    /// `exposure` is added to it: the reference's own default exposure.
    public static func writeDNG(_ radiance: CIImage, context: CIContext, metadata: Metadata, to url: URL,
                                brightest: Double = 1, exposure: Double = 0,
                                bitsPerSample: Int = dngBitsPerSample) throws {
        let extent = radiance.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        let white = max(1, brightest.isFinite ? brightest : 1)
        var dngMetadata = dngMetadata(metadata)
        dngMetadata.baselineExposure = log2(white) + exposure
        let scaled = white > 1 ? radiance.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 / white, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1 / white, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1 / white, w: 0),
        ]) : radiance
        try writeInPlace(url) { temporary in
            var writer = try LinearDNGWriter(url: temporary, width: width, height: height, bitsPerSample: bitsPerSample,
                                             metadata: dngMetadata)
            do {
                var rows = [Float](repeating: 0, count: width * bandHeight * 4)
                try renderInBands(scaled, extent: extent) { band, _ in
                    let count = Int(band.height)
                    rows.withUnsafeMutableBytes { buffer in
                        context.render(scaled, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: band,
                                       format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
                    }
                    try rows.withUnsafeBufferPointer { try writer.write(rows: $0, count: count) }
                }
                try writer.finish()
            } catch {
                writer.abandon()
                throw error
            }
        }
    }

    /// The DNG's samples are half floats: the system's RAW decoder (macOS
    /// 27.2) gives no image for 32-bit floating-point DNGs, which the PRD
    /// asked for, and does for 16-bit ones, as Lightroom writes its HDR
    /// merges (status.md, "Spike 1"; Requirements issue RI-E1).
    public static let dngBitsPerSample = 16

    /// Rows rendered at a time: a band's intermediates are all Core Image
    /// holds, where a whole image would take several full-size buffers
    /// (status.md, "Spike 3").
    static let bandHeight = 512

    /// Calls `body` for each band of `extent`, top band first (with its
    /// first row counted from the top), checking for cancellation between bands.
    static func renderInBands(_ image: CIImage, extent: CGRect, _ body: (CGRect, Int) throws -> Void) throws {
        let height = Int(extent.height)
        var row = 0
        while row < height {
            try Task.checkCancellation()
            let count = min(bandHeight, height - row)
            // Core Image's rows count from the bottom.
            let band = CGRect(x: extent.minX, y: extent.maxY - CGFloat(row + count), width: extent.width,
                              height: CGFloat(count))
            try autoreleasepool { try body(band, row) }
            row += count
        }
    }

    /// Writes through `body` to a hidden file beside `url`, then moves it to
    /// `url` without replacing anything there. The hidden file is removed
    /// whatever happens.
    static func writeInPlace(_ url: URL, _ body: (URL) throws -> Void) throws {
        let fileManager = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).partial", directoryHint: .notDirectory)
        defer { try? fileManager.removeItem(at: temporary) }
        do {
            try body(temporary)
            try Task.checkCancellation()
        } catch let failure as Failure {
            throw spaceAware(failure, at: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw spaceAware(.writeFailed(error.localizedDescription), at: url, underlying: error)
        }
        // link(2) fails rather than replace: nothing can be written over, even a
        // file that appeared since the name was chosen.
        let linked = temporary.withUnsafeFileSystemRepresentation { from in
            url.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return Int32(-1) }
                return link(from, to)
            }
        }
        if linked != 0 {
            let code = errno
            if code == EEXIST { throw Failure.nameTaken }
            // A file system without hard links: a move, after checking the name is free.
            guard !fileManager.fileExists(atPath: url.path) else { throw Failure.nameTaken }
            do {
                try fileManager.moveItem(at: temporary, to: url)
            } catch {
                throw spaceAware(.writeFailed(error.localizedDescription), at: url, underlying: error)
            }
        }
    }

    static func spaceAware(_ failure: Failure, at url: URL, underlying: (any Error)? = nil) -> Failure {
        if let underlying = underlying as NSError?,
           underlying.code == NSFileWriteOutOfSpaceError || underlying.code == Int(ENOSPC) {
            return .noSpace
        }
        if case .writeFailed = failure, let free = try? url.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity, free < 1 << 20 {
            return .noSpace
        }
        return failure
    }

    // MARK: Metadata

    /// The TIFF's properties: the reference's camera and capture data (EXIF,
    /// GPS, TIFF), the library's descriptive fields and keywords (IPTC), and
    /// an XMP packet with every library value, rating, flag and label included.
    static func tiffMetadata(_ metadata: Metadata) -> ([CFString: Any], CGImageMetadata?) {
        var settings = ExportSettings()
        settings.metadata = .all
        var export = ExportMetadata.make(source: metadata.cfProperties, values: metadata.values, settings: settings)
        export.properties[kCGImagePropertyTIFFDictionary] = {
            var tiff = export.properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = 1
            return tiff
        }()
        return (export.properties, xmp(metadata.values))
    }

    /// Every library value as XMP, as a sidecar holds them.
    static func xmp(_ values: SidecarValues) -> CGImageMetadata? {
        let document = XMPDocument.empty()
        document.apply(values, previous: nil)
        guard document.hasProperties else { return nil }
        return CGImageMetadataCreateFromXMPData(document.rootElementData() as CFData)
    }

    static func dngMetadata(_ metadata: Metadata) -> LinearDNGWriter.Metadata {
        let properties = metadata.cfProperties
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        var result = LinearDNGWriter.Metadata()
        func text(_ value: Any?) -> String? {
            let trimmed = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        result.make = text(tiff[kCGImagePropertyTIFFMake])
        result.model = text(tiff[kCGImagePropertyTIFFModel])
        result.dateTimeOriginal = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        result.offsetTimeOriginal = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
        result.exposureTime = (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue
        result.fNumber = (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue
        result.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue
        result.exposureBias = (exif[kCGImagePropertyExifExposureBiasValue] as? NSNumber)?.doubleValue
        result.focalLength = (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue
        result.lensModel = text(exif[kCGImagePropertyExifLensModel])
        if let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
           let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue {
            result.latitude = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -latitude : latitude
            result.longitude = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -longitude : longitude
        }
        result.artist = metadata.values.creator
        result.copyright = metadata.values.rights
        result.caption = metadata.values.caption
        if let xmp = xmp(metadata.values) {
            result.xmp = CGImageMetadataCreateXMPData(xmp, nil) as Data?
        }
        return result
    }
}
