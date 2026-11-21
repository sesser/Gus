import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The file a merge writes (PRD R5): a tone-mapped 16-bit TIFF in Display P3,
/// or a linear 16-bit floating-point DNG of the merged light (ruling D-H4).
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
        /// The file would be larger than its format can hold (a DNG past 4 GiB).
        case tooLarge
    }

    /// What the result carries of the reference photo (R7).
    public struct Metadata: Sendable {
        /// The reference master's ImageIO properties (EXIF, TIFF, GPS, IPTC).
        public var sourceProperties: [String: any Sendable]
        /// The library's values for the reference: rating, flag, label,
        /// keywords and the descriptive fields.
        public var values: SidecarValues
        /// This merge's own: a new document id (`xmpMM:DocumentID` and
        /// `InstanceID`) and the time it was made (`xmp:CreateDate`), so two
        /// merges of the same frames are two files, never one content the
        /// catalog takes once (code review C1).
        public var documentID: UUID
        public var created: Date

        public init(sourceProperties: [String: any Sendable], values: SidecarValues, documentID: UUID = UUID(),
                    created: Date = Date()) {
            self.sourceProperties = sourceProperties
            self.values = values
            self.documentID = documentID
            self.created = created
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
    /// Display P3 TIFF at `url`. The encoder reads the pixels from a
    /// sequential provider that renders a band of rows at a time
    /// (`BandProvider`), so no whole-image buffer is held (security review M1).
    /// Returns the written file's identity.
    @discardableResult
    public static func writeTIFF(_ image: CIImage, context: CIContext, metadata: Metadata, to url: URL) throws
        -> FileIdentity {
        let extent = image.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        let space = RenderEngine.outputColorSpace
        let source = BandProvider(image: image, context: context, extent: extent, colorSpace: space)
        guard let provider = source.makeProvider(),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
                                    bytesPerRow: source.rowBytes, space: space,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
                                        | CGImageByteOrderInfo.order16Little.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw Failure.renderFailed }
        let (properties, xmp) = tiffMetadata(metadata)
        return try writeInPlace(url) { temporary in
            guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.tiff.identifier as CFString,
                                                                    1, nil)
            else { throw Failure.writeFailed("") }
            CGImageDestinationAddImageAndMetadata(destination, cgImage, xmp, properties as CFDictionary)
            let finished = CGImageDestinationFinalize(destination)
            try Task.checkCancellation()
            guard finished, !source.failed else { throw Failure.writeFailed("") }
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
    @discardableResult
    public static func writeDNG(_ radiance: CIImage, context: CIContext, metadata: Metadata, to url: URL,
                                brightest: Double = 1, exposure: Double = 0) throws -> FileIdentity {
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
        return try writeInPlace(url) { temporary in
            var writer = try LinearDNGWriter(url: temporary, width: width, height: height, metadata: dngMetadata)
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

    /// A file as the file system knows it, whatever its name: for removing
    /// only the file the merge wrote (security review L2).
    public struct FileIdentity: Hashable, Sendable {
        public var device: Int64
        public var inode: UInt64

        /// The identity of what is at `url` now (links not followed), nil when nothing is.
        public static func of(_ url: URL) -> FileIdentity? {
            var info = stat()
            let result = url.withUnsafeFileSystemRepresentation { path in path.map { lstat($0, &info) } ?? -1 }
            guard result == 0 else { return nil }
            return FileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
        }
    }

    /// Writes through `body` to a hidden file beside `url`, then puts it at
    /// `url` without replacing anything there, and returns its identity. The
    /// hidden file is removed whatever happens.
    ///
    /// The hidden name is short and fixed (`.merge-<UUID>.partial`), so any
    /// result name that fits the file system fits it too (security review L1).
    /// The file is put in place with `link(2)`, which fails rather than
    /// replace (a file that appeared since the name was chosen, a dangling
    /// link); only where the file system has no hard links (`ENOTSUP`,
    /// `EOPNOTSUPP`, `EPERM`) it is renamed with `RENAME_EXCL`, which also
    /// never replaces. Any other error is a failure to write (L7).
    /// `linkFile` is `link(2)` (tests stand in for it).
    @discardableResult
    static func writeInPlace(_ url: URL,
                             linkFile: (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32 = { link($0, $1) },
                             _ body: (URL) throws -> Void) throws -> FileIdentity {
        let fileManager = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".merge-\(UUID().uuidString).partial", directoryHint: .notDirectory)
        defer { try? fileManager.removeItem(at: temporary) }
        do {
            try body(temporary)
            try Task.checkCancellation()
        } catch let failure as Failure {
            throw spaceAware(failure, at: url)
        } catch LinearDNGWriter.Failure.tooLarge {
            throw Failure.tooLarge
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw spaceAware(.writeFailed(error.localizedDescription), at: url, underlying: error)
        }
        guard let identity = FileIdentity.of(temporary) else { throw Failure.writeFailed("") }
        let linked = temporary.withUnsafeFileSystemRepresentation { from in
            url.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return Int32(-1) }
                return linkFile(from, to) == 0 ? 0 : errno
            }
        }
        switch linked {
        case 0:
            return identity
        case EEXIST:
            throw Failure.nameTaken
        case ENOTSUP, EOPNOTSUPP, EPERM:
            let renamed = temporary.withUnsafeFileSystemRepresentation { from in
                url.withUnsafeFileSystemRepresentation { to in
                    guard let from, let to else { return Int32(-1) }
                    return renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
                }
            }
            if renamed == 0 { return identity }
            if renamed == EEXIST { throw Failure.nameTaken }
            throw writeFailure(renamed, at: url)
        default:
            throw writeFailure(linked, at: url)
        }
    }

    static func writeFailure(_ code: Int32, at url: URL) -> Failure {
        let error = POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        return code == ENOSPC ? .noSpace : spaceAware(.writeFailed(error.localizedDescription), at: url)
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

    // MARK: Rendering in bands

    /// Pixels for the TIFF encoder, rendered a band at a time as it reads
    /// them: one band's buffer instead of the whole image. Returns no bytes
    /// (and so stops the encoder) once its task is cancelled.
    final class BandProvider: @unchecked Sendable {
        // @unchecked: used by one encoder on one thread, the job's.
        let image: CIImage
        let context: CIContext
        let extent: CGRect
        let colorSpace: CGColorSpace
        let rowBytes: Int
        let height: Int
        private var band: [UInt8]
        private var bandFirstRow = -1
        private var bandRows = 0
        private var position = 0
        private(set) var failed = false

        init(image: CIImage, context: CIContext, extent: CGRect, colorSpace: CGColorSpace) {
            self.image = image
            self.context = context
            self.extent = extent
            self.colorSpace = colorSpace
            rowBytes = Int(extent.width) * 8
            height = Int(extent.height)
            band = [UInt8](repeating: 0, count: rowBytes * min(MergeOutput.bandHeight, max(1, Int(extent.height))))
        }

        func makeProvider() -> CGDataProvider? {
            var callbacks = CGDataProviderSequentialCallbacks(
                version: 0,
                getBytes: { info, buffer, count in
                    guard let info else { return 0 }
                    return Unmanaged<BandProvider>.fromOpaque(info).takeUnretainedValue().read(into: buffer, count: count)
                },
                skipForward: { info, count in
                    guard let info else { return 0 }
                    return Unmanaged<BandProvider>.fromOpaque(info).takeUnretainedValue().skip(count)
                },
                rewind: { info in
                    guard let info else { return }
                    Unmanaged<BandProvider>.fromOpaque(info).takeUnretainedValue().position = 0
                },
                releaseInfo: { info in
                    guard let info else { return }
                    Unmanaged<BandProvider>.fromOpaque(info).release()
                })
            let info = Unmanaged.passRetained(self).toOpaque()
            guard let provider = CGDataProvider(sequentialInfo: info, callbacks: &callbacks) else {
                Unmanaged<BandProvider>.fromOpaque(info).release()
                return nil
            }
            return provider
        }

        private var total: Int { rowBytes * height }

        func skip(_ count: off_t) -> off_t {
            let step = min(Int(count), total - position)
            position += step
            return off_t(step)
        }

        func read(into buffer: UnsafeMutableRawPointer, count: Int) -> Int {
            guard !failed else { return 0 }
            if Task.isCancelled {
                failed = true
                return 0
            }
            var copied = 0
            while copied < count, position < total {
                let row = position / rowBytes
                if row < bandFirstRow || row >= bandFirstRow + bandRows { render(from: row) }
                let bandEnd = (bandFirstRow + bandRows) * rowBytes
                let length = min(count - copied, bandEnd - position)
                band.withUnsafeBytes { bytes in
                    (buffer + copied).copyMemory(from: bytes.baseAddress! + (position - bandFirstRow * rowBytes),
                                                 byteCount: length)
                }
                copied += length
                position += length
            }
            return copied
        }

        private func render(from row: Int) {
            let first = row / MergeOutput.bandHeight * MergeOutput.bandHeight
            let rows = min(MergeOutput.bandHeight, height - first)
            // Core Image's rows count from the bottom.
            let bounds = CGRect(x: extent.minX, y: extent.maxY - CGFloat(first + rows), width: extent.width,
                                height: CGFloat(rows))
            autoreleasepool {
                band.withUnsafeMutableBytes { bytes in
                    context.render(image, toBitmap: bytes.baseAddress!, rowBytes: rowBytes, bounds: bounds,
                                   format: .RGBA16, colorSpace: colorSpace)
                }
            }
            bandFirstRow = first
            bandRows = rows
        }
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
        return (export.properties, xmp(metadata))
    }

    /// Every library value as XMP, as a sidecar holds them, with the merge's
    /// document id and creation time.
    static func xmp(_ metadata: Metadata) -> CGImageMetadata {
        let document = XMPDocument.empty()
        document.apply(metadata.values, previous: nil)
        let base = document.hasProperties ? CGImageMetadataCreateFromXMPData(document.rootElementData() as CFData) : nil
        let xmp = base.flatMap { CGImageMetadataCreateMutableCopy($0) } ?? CGImageMetadataCreateMutable()
        let mediaManagement = "http://ns.adobe.com/xap/1.0/mm/" as CFString
        CGImageMetadataRegisterNamespaceForPrefix(xmp, mediaManagement, "xmpMM" as CFString, nil)
        let id = "xmp.did:" + metadata.documentID.uuidString.lowercased()
        CGImageMetadataSetValueWithPath(xmp, nil, "xmpMM:DocumentID" as CFString, id as CFString)
        CGImageMetadataSetValueWithPath(xmp, nil, "xmpMM:InstanceID" as CFString,
                                        ("xmp.iid:" + metadata.documentID.uuidString.lowercased()) as CFString)
        let date = ISO8601DateFormatter().string(from: metadata.created)
        CGImageMetadataSetValueWithPath(xmp, nil, "xmp:CreateDate" as CFString, date as CFString)
        return xmp
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
        result.xmp = CGImageMetadataCreateXMPData(xmp(metadata), nil) as Data?
        return result
    }
}
