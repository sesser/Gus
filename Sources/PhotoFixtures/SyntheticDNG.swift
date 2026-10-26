import CoreGraphics
import Foundation

/// Writes minimal uncompressed Bayer (RGGB) DNG files, so the RAW decode path
/// (`CIRAWFilter` demosaic, white balance, color matrix) can be tested and
/// profiled without real camera files.
///
/// The fictitious camera has linear sRGB primaries: `ColorMatrix1` is the D65
/// XYZ→linear-sRGB matrix and `AsShotNeutral` is (1, 1, 1).
public enum SyntheticDNG {
    public struct Options: Sendable {
        public var width: Int
        public var height: Int
        public var seed: UInt64
        /// "yyyy:MM:dd HH:mm:ss"
        public var dateTimeOriginal: String?
        public var orientation: Int

        public init(width: Int, height: Int, seed: UInt64, dateTimeOriginal: String? = nil, orientation: Int = 1) {
            self.width = width
            self.height = height
            self.seed = seed
            self.dateTimeOriginal = dateTimeOriginal
            self.orientation = orientation
        }
    }

    public static func write(to url: URL, options: Options) throws {
        try data(options: options).write(to: url)
    }

    public static func data(options: Options) throws -> Data {
        let width = options.width & ~1
        let height = options.height & ~1
        guard width >= 16, height >= 16,
              let scene = SyntheticImages.makeImage(width: width, height: height, seed: options.seed)
        else { throw CocoaError(.fileWriteInvalidFileName) }
        let mosaic = try mosaic(scene, width: width, height: height)

        var tiff = TIFFWriter()
        let date = options.dateTimeOriginal ?? "2024:01:01 00:00:00"
        var exif = TIFFWriter.IFD()
        exif.ascii(36867, date) // DateTimeOriginal
        exif.ascii(36868, date) // DateTimeDigitized

        var ifd = TIFFWriter.IFD()
        ifd.long(254, [0])                         // NewSubfileType: main image
        ifd.long(256, [UInt32(width)])
        ifd.long(257, [UInt32(height)])
        ifd.short(258, [16])                       // BitsPerSample
        ifd.short(259, [1])                        // Compression: none
        ifd.short(262, [32803])                    // PhotometricInterpretation: CFA
        ifd.ascii(271, "Synthetic")                // Make
        ifd.ascii(272, "Bayer Generator")          // Model
        ifd.imageData(273, 279, mosaic)            // StripOffsets / StripByteCounts
        ifd.short(274, [UInt16(options.orientation)])
        ifd.short(277, [1])                        // SamplesPerPixel
        ifd.long(278, [UInt32(height)])            // RowsPerStrip
        ifd.short(284, [1])                        // PlanarConfiguration
        ifd.ascii(306, date)                       // DateTime
        ifd.short(33421, [2, 2])                   // CFARepeatPatternDim
        ifd.bytes(33422, [0, 1, 1, 2])             // CFAPattern: RGGB
        ifd.subIFD(34665, exif)                    // ExifIFD
        ifd.bytes(50706, [1, 4, 0, 0])             // DNGVersion
        ifd.bytes(50707, [1, 1, 0, 0])             // DNGBackwardVersion
        ifd.ascii(50708, "Synthetic Bayer Generator") // UniqueCameraModel
        ifd.long(50714, [0])                       // BlackLevel
        ifd.long(50717, [65535])                   // WhiteLevel
        ifd.srational(50721, [                     // ColorMatrix1: XYZ (D65) -> camera (= linear sRGB)
            3.2406, -1.5372, -0.4986,
            -0.9689, 1.8758, 0.0415,
            0.0557, -0.2040, 1.0570,
        ])
        ifd.rational(50728, [1, 1, 1])             // AsShotNeutral
        ifd.short(50778, [21])                     // CalibrationIlluminant1: D65
        return tiff.write(ifd)
    }

    /// One image of `structureData`.
    public struct SubImage: Sendable {
        public var subfileType: UInt32
        /// 34892 is linear raw, 32803 a color filter array, 2 RGB.
        public var photometric: UInt16
        /// 1 unsigned integer, 3 floating point.
        public var sampleFormat: UInt16

        public init(_ subfileType: UInt32, _ photometric: UInt16, sampleFormat: UInt16 = 1) {
            self.subfileType = subfileType
            self.photometric = photometric
            self.sampleFormat = sampleFormat
        }
    }

    /// The TIFF structure of a DNG without image data: an IFD0 preview and
    /// SubIFDs with the given NewSubfileType, PhotometricInterpretation and
    /// SampleFormat values.
    public static func structureData(subIFDs: [SubImage]) -> Data {
        var ifd = TIFFWriter.IFD()
        ifd.long(254, [1])                         // NewSubfileType: reduced-resolution preview
        ifd.short(262, [2])                        // PhotometricInterpretation: RGB
        ifd.bytes(50706, [1, 7, 0, 0])             // DNGVersion
        ifd.subIFDs(330, subIFDs.map { image in
            var sub = TIFFWriter.IFD()
            sub.long(254, [image.subfileType])
            sub.short(262, [image.photometric])
            sub.short(339, [image.sampleFormat, image.sampleFormat, image.sampleFormat])
            return sub
        })
        var tiff = TIFFWriter()
        return tiff.write(ifd)
    }

    /// Samples the scene through an RGGB color filter array as 16-bit linear values.
    static func mosaic(_ scene: CGImage, width: Int, height: Int) throws -> Data {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        context.draw(scene, in: CGRect(x: 0, y: 0, width: width, height: height))

        // sRGB transfer function to linear, scaled to 16 bits with some headroom.
        let linear: [UInt16] = (0..<256).map { value in
            let v = Double(value) / 255
            let l = v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            return UInt16(min(65535, l * 0.85 * 65535))
        }
        var output = Data(count: width * height * 2)
        output.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: UInt16.self)
            for y in 0..<height {
                for x in 0..<width {
                    let channel = (y & 1) == 0 ? ((x & 1) == 0 ? 0 : 1) : ((x & 1) == 0 ? 1 : 2)
                    samples[y * width + x] = linear[Int(rgba[(y * width + x) * 4 + channel])].littleEndian
                }
            }
        }
        return output
    }
}

/// Just enough of a little-endian TIFF writer for `SyntheticDNG`.
struct TIFFWriter {
    enum FieldType: UInt16 {
        case byte = 1, ascii = 2, short = 3, long = 4, rational = 5, srational = 10

        var size: Int {
            switch self {
            case .byte, .ascii: 1
            case .short: 2
            case .long: 4
            case .rational, .srational: 8
            }
        }
    }

    struct Entry {
        var tag: UInt16
        var type: FieldType
        var count: Int
        var payload: Payload
    }

    enum Payload {
        case value(Data)
        case image(Data, byteCountTag: UInt16)
        case ifd(IFD)
        case ifds([IFD])
    }

    struct IFD {
        var entries: [Entry] = []

        mutating func bytes(_ tag: UInt16, _ values: [UInt8]) {
            entries.append(Entry(tag: tag, type: .byte, count: values.count, payload: .value(Data(values))))
        }

        mutating func ascii(_ tag: UInt16, _ text: String) {
            let data = Data(text.utf8) + [0]
            entries.append(Entry(tag: tag, type: .ascii, count: data.count, payload: .value(data)))
        }

        mutating func short(_ tag: UInt16, _ values: [UInt16]) {
            var data = Data()
            for value in values { data.append(littleEndian: value) }
            entries.append(Entry(tag: tag, type: .short, count: values.count, payload: .value(data)))
        }

        mutating func long(_ tag: UInt16, _ values: [UInt32]) {
            var data = Data()
            for value in values { data.append(littleEndian: value) }
            entries.append(Entry(tag: tag, type: .long, count: values.count, payload: .value(data)))
        }

        mutating func rational(_ tag: UInt16, _ values: [Double]) {
            var data = Data()
            for value in values {
                data.append(littleEndian: UInt32(max(0, (value * 10_000).rounded())))
                data.append(littleEndian: UInt32(10_000))
            }
            entries.append(Entry(tag: tag, type: .rational, count: values.count, payload: .value(data)))
        }

        mutating func srational(_ tag: UInt16, _ values: [Double]) {
            var data = Data()
            for value in values {
                data.append(littleEndian: UInt32(bitPattern: Int32((value * 10_000).rounded())))
                data.append(littleEndian: UInt32(10_000))
            }
            entries.append(Entry(tag: tag, type: .srational, count: values.count, payload: .value(data)))
        }

        /// One strip of image data; writes both the offset and the byte count tag.
        mutating func imageData(_ offsetTag: UInt16, _ byteCountTag: UInt16, _ data: Data) {
            entries.append(Entry(tag: offsetTag, type: .long, count: 1, payload: .image(data, byteCountTag: byteCountTag)))
            long(byteCountTag, [UInt32(data.count)])
        }

        mutating func subIFD(_ tag: UInt16, _ ifd: IFD) {
            entries.append(Entry(tag: tag, type: .long, count: 1, payload: .ifd(ifd)))
        }

        /// Several IFDs under one tag, such as SubIFDs.
        mutating func subIFDs(_ tag: UInt16, _ ifds: [IFD]) {
            let payload: Payload = ifds.count == 1 ? .ifd(ifds[0]) : .ifds(ifds)
            entries.append(Entry(tag: tag, type: .long, count: ifds.count, payload: payload))
        }
    }

    private var output = Data()

    mutating func write(_ ifd: IFD) -> Data {
        output = Data([0x49, 0x49]) // "II"
        output.append(littleEndian: UInt16(42))
        output.append(littleEndian: UInt32(8))
        writeIFD(ifd, nextOffset: 0)
        return output
    }

    /// Writes an IFD at the current end of the output, followed by its out-of-line
    /// values, and returns its offset.
    @discardableResult
    private mutating func writeIFD(_ ifd: IFD, nextOffset: UInt32) -> UInt32 {
        let entries = ifd.entries.sorted { $0.tag < $1.tag }
        let start = output.count
        let tableSize = 2 + entries.count * 12 + 4
        output.append(Data(count: tableSize))
        var deferred: [(slot: Int, payload: Payload)] = []

        var cursor = start
        output.replace(at: cursor, littleEndian: UInt16(entries.count))
        cursor += 2
        for entry in entries {
            output.replace(at: cursor, littleEndian: entry.tag)
            output.replace(at: cursor + 2, littleEndian: entry.type.rawValue)
            output.replace(at: cursor + 4, littleEndian: UInt32(entry.count))
            switch entry.payload {
            case .value(let data) where data.count <= 4:
                output.replaceSubrange((cursor + 8)..<(cursor + 8 + data.count), with: data)
            default:
                deferred.append((cursor + 8, entry.payload))
            }
            cursor += 12
        }
        output.replace(at: cursor, littleEndian: nextOffset)

        for (slot, payload) in deferred {
            if output.count % 2 == 1 { output.append(0) }
            switch payload {
            case .value(let data):
                output.replace(at: slot, littleEndian: UInt32(output.count))
                output.append(data)
            case .image(let data, _):
                output.replace(at: slot, littleEndian: UInt32(output.count))
                output.append(data)
            case .ifd(let subIFD):
                output.replace(at: slot, littleEndian: UInt32(output.count))
                writeIFD(subIFD, nextOffset: 0)
            case .ifds(let subIFDs):
                let table = output.count
                output.replace(at: slot, littleEndian: UInt32(table))
                output.append(Data(count: subIFDs.count * 4))
                for (index, subIFD) in subIFDs.enumerated() {
                    output.replace(at: table + index * 4, littleEndian: UInt32(output.count))
                    writeIFD(subIFD, nextOffset: 0)
                }
            }
        }
        return UInt32(start)
    }
}

extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func replace<T: FixedWidthInteger>(at offset: Int, littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { bytes in
            replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
    }
}
