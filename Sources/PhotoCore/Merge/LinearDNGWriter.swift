import Foundation

/// Writes a scene-referred linear DNG: three 16-bit (IEEE half)
/// floating-point samples a pixel (`PhotometricInterpretation` LinearRaw,
/// `SampleFormat` IEEE float, `WhiteLevel` 1),
/// uncompressed, from the DNG Specification 1.4 and later (Adobe, published:
/// floating-point image data needs a reader of 1.4). The merge's DNG
/// (PRD Open question 1): the merged light, not tone mapped, which the
/// app's own loupe renders and edits as it does any floating-point DNG.
/// Half floats because the system's RAW decoder (macOS 27.2) reads no
/// 32-bit floating-point DNG (status.md Spike 1, ruling D-H4); they hold
/// about 30 stops at 11 bits of precision.
///
/// The color tags say the samples are linear Rec. 2020 under D65:
/// `ColorMatrix1` maps XYZ to the camera's RGB, which here is Rec. 2020
/// itself, with `CalibrationIlluminant1` D65 and a neutral as-shot white.
/// Camera and capture metadata go in an EXIF IFD and a GPS IFD, the
/// library's values in an XMP packet (tag 700).
///
/// The image is written in strips as rows are given, so the whole file is
/// never held in memory: the caller hands rows of RGBA floats (`write(rows:)`)
/// in order.
public struct LinearDNGWriter {
    public struct Metadata: Sendable {
        public var make: String?
        public var model: String?
        /// "yyyy:MM:dd HH:mm:ss" and its offset ("+02:00"), from the capture.
        public var dateTimeOriginal: String?
        public var offsetTimeOriginal: String?
        public var exposureTime: Double?
        public var fNumber: Double?
        public var iso: Int?
        public var exposureBias: Double?
        public var focalLength: Double?
        public var lensModel: String?
        public var latitude: Double?
        public var longitude: Double?
        public var artist: String?
        public var copyright: String?
        public var caption: String?
        /// An XMP packet (x:xmpmeta), written as tag 700.
        public var xmp: Data?
        /// Stops the reader brightens the samples by (`BaselineExposure`).
        public var baselineExposure: Double = 0

        public init() {}
    }

    /// XYZ (D65) to linear Rec. 2020, row by row (ITU-R BT.2020 primaries).
    public static let rec2020FromXYZ: [Double] = [
        1.7166512, -0.3556708, -0.2533663,
        -0.6666844, 1.6164812, 0.0157685,
        0.0176399, -0.0427706, 0.9421031,
    ]

    public let width: Int
    public let height: Int
    /// Bits a sample: IEEE half floats.
    public static let bitsPerSample = 16
    private let handle: FileHandle
    private let rowsPerStrip: Int
    private var rowsWritten = 0
    private var scratch: [Float]

    /// Starts the file at `url` (which must not exist), writing every tag and
    /// leaving room for the pixels.
    public init(url: URL, width: Int, height: Int, metadata: Metadata) throws {
        guard width > 0, height > 0 else { throw CocoaError(.fileWriteUnknown) }
        self.width = width
        self.height = height
        rowsPerStrip = max(1, min(height, (1 << 20) / (width * 3 * Self.bitsPerSample / 8)))
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
        handle = try FileHandle(forWritingTo: url)
        scratch = []
        let header = Self.header(width: width, height: height, rowsPerStrip: rowsPerStrip, metadata: metadata)
        try handle.write(contentsOf: header)
    }

    /// Writes `count` rows of RGBA floats (alpha is dropped), top row first.
    public mutating func write(rows rgba: UnsafeBufferPointer<Float>, count: Int) throws {
        precondition(rgba.count >= count * width * 4)
        precondition(rowsWritten + count <= height)
        scratch.removeAll(keepingCapacity: true)
        scratch.reserveCapacity(count * width * 3)
        for index in 0..<(count * width) {
            scratch.append(rgba[index * 4])
            scratch.append(rgba[index * 4 + 1])
            scratch.append(rgba[index * 4 + 2])
        }
        // Little-endian on every Mac this runs on.
        let halves = scratch.map { Float16($0) }
        try halves.withUnsafeBytes { try handle.write(contentsOf: Data($0)) }
        rowsWritten += count
    }

    /// Ends the file; fails unless every row was written.
    public func finish() throws {
        defer { try? handle.close() }
        guard rowsWritten == height else { throw CocoaError(.fileWriteUnknown) }
        try handle.synchronize()
    }

    /// Closes the file without finishing it (the caller removes it).
    public func abandon() {
        try? handle.close()
    }

    // MARK: Layout

    /// The TIFF header, IFD0 with its sub-IFDs and values, padded so the
    /// pixels start right after it, with strip offsets pointing at them.
    static func header(width: Int, height: Int, rowsPerStrip: Int, metadata: Metadata) -> Data {
        let stripCount = (height + rowsPerStrip - 1) / rowsPerStrip
        let rowBytes = width * 3 * bitsPerSample / 8
        var exif = IFD()
        exif.ascii(36867, metadata.dateTimeOriginal)        // DateTimeOriginal
        exif.ascii(36868, metadata.dateTimeOriginal)        // DateTimeDigitized
        exif.ascii(36881, metadata.offsetTimeOriginal)      // OffsetTimeOriginal
        exif.rational(33434, metadata.exposureTime)         // ExposureTime
        exif.rational(33437, metadata.fNumber)              // FNumber
        if let iso = metadata.iso { exif.short(34855, [UInt16(clamping: iso)]) } // ISOSpeedRatings
        exif.srational(37380, metadata.exposureBias)        // ExposureBiasValue
        exif.rational(37386, metadata.focalLength)          // FocalLength
        exif.ascii(42036, metadata.lensModel)               // LensModel
        var gps = IFD()
        if let latitude = metadata.latitude, let longitude = metadata.longitude {
            gps.bytes(0, [2, 3, 0, 0])                      // GPSVersionID
            gps.ascii(1, latitude < 0 ? "S" : "N")
            gps.rationals(2, degreesMinutesSeconds(abs(latitude)))
            gps.ascii(3, longitude < 0 ? "W" : "E")
            gps.rationals(4, degreesMinutesSeconds(abs(longitude)))
        }

        var ifd = IFD()
        ifd.long(254, [0])                                  // NewSubfileType: the main image
        ifd.long(256, [UInt32(width)])
        ifd.long(257, [UInt32(height)])
        ifd.short(258, [UInt16](repeating: UInt16(bitsPerSample), count: 3)) // BitsPerSample
        ifd.short(259, [1])                                 // Compression: none
        ifd.short(262, [34892])                             // PhotometricInterpretation: LinearRaw
        ifd.ascii(270, metadata.caption)                    // ImageDescription
        ifd.ascii(271, metadata.make)
        ifd.ascii(272, metadata.model)
        ifd.placeholder(273, count: stripCount)             // StripOffsets
        ifd.short(274, [1])                                 // Orientation: the pixels are upright
        ifd.short(277, [3])                                 // SamplesPerPixel
        ifd.long(278, [UInt32(rowsPerStrip)])               // RowsPerStrip
        ifd.long(279, (0..<stripCount).map { strip in       // StripByteCounts
            UInt32(min(rowsPerStrip, height - strip * rowsPerStrip) * rowBytes)
        })
        ifd.short(284, [1])                                 // PlanarConfiguration: chunky
        ifd.ascii(315, metadata.artist)                     // Artist
        ifd.short(339, [3, 3, 3])                           // SampleFormat: IEEE floating point
        if let xmp = metadata.xmp { ifd.undefined(700, xmp) } // XMP
        ifd.ascii(33432, metadata.copyright)                // Copyright
        ifd.subIFD(34665, exif)                             // ExifIFD
        if !gps.entries.isEmpty { ifd.subIFD(34853, gps) }  // GPSInfo
        ifd.bytes(50706, [1, 4, 0, 0])                      // DNGVersion
        ifd.bytes(50707, [1, 4, 0, 0])                      // DNGBackwardVersion: floats need 1.4
        let camera = [metadata.make, metadata.model].compactMap { $0 }.joined(separator: " ")
        ifd.ascii(50708, camera.isEmpty ? "Merged" : camera + " (merged)") // UniqueCameraModel
        ifd.long(50717, [1, 1, 1])                          // WhiteLevel: 1.0, as floating-point data has it
        ifd.srationals(50721, rec2020FromXYZ)               // ColorMatrix1: XYZ to linear Rec. 2020
        ifd.rationals(50728, [1, 1, 1])                     // AsShotNeutral
        ifd.srationals(50730, [metadata.baselineExposure])  // BaselineExposure
        ifd.short(50778, [21])                              // CalibrationIlluminant1: D65

        var layout = Layout()
        let data = layout.write(ifd, stripRows: (0..<stripCount).map { $0 * rowsPerStrip }, rowBytes: rowBytes)
        return data
    }

    static func degreesMinutesSeconds(_ value: Double) -> [Double] {
        let degrees = value.rounded(.down)
        let minutes = ((value - degrees) * 60).rounded(.down)
        let seconds = ((value - degrees) * 60 - minutes) * 60
        return [degrees, minutes, seconds]
    }

    enum FieldType: UInt16 {
        case byte = 1, ascii = 2, short = 3, long = 4, rational = 5, undefined = 7, srational = 10
    }

    struct Entry {
        var tag: UInt16
        var type: FieldType
        var count: Int
        var value: Data
        var subIFD: IFD?
        /// Strip offsets, filled once the layout is known.
        var isPlaceholder = false
    }

    struct IFD {
        var entries: [Entry] = []

        mutating func add(_ tag: UInt16, _ type: FieldType, _ count: Int, _ value: Data) {
            entries.append(Entry(tag: tag, type: type, count: count, value: value))
        }

        mutating func bytes(_ tag: UInt16, _ values: [UInt8]) { add(tag, .byte, values.count, Data(values)) }

        mutating func ascii(_ tag: UInt16, _ text: String?) {
            guard let text, !text.isEmpty else { return }
            // TIFF ASCII is 7-bit; other characters become "?".
            let bytes = text.unicodeScalars.map { $0.isASCII ? UInt8($0.value) : UInt8(ascii: "?") } + [0]
            add(tag, .ascii, bytes.count, Data(bytes))
        }

        mutating func short(_ tag: UInt16, _ values: [UInt16]) {
            var data = Data()
            for value in values { data.appendLittleEndian(value) }
            add(tag, .short, values.count, data)
        }

        mutating func long(_ tag: UInt16, _ values: [UInt32]) {
            var data = Data()
            for value in values { data.appendLittleEndian(value) }
            add(tag, .long, values.count, data)
        }

        mutating func rational(_ tag: UInt16, _ value: Double?) {
            guard let value, value.isFinite, value >= 0 else { return }
            rationals(tag, [value])
        }

        mutating func rationals(_ tag: UInt16, _ values: [Double]) {
            var data = Data()
            for value in values {
                let (numerator, denominator) = LinearDNGWriter.fraction(value, signed: false)
                data.appendLittleEndian(UInt32(numerator))
                data.appendLittleEndian(UInt32(denominator))
            }
            add(tag, .rational, values.count, data)
        }

        mutating func srational(_ tag: UInt16, _ value: Double?) {
            guard let value, value.isFinite else { return }
            srationals(tag, [value])
        }

        mutating func srationals(_ tag: UInt16, _ values: [Double]) {
            var data = Data()
            for value in values {
                let (numerator, denominator) = LinearDNGWriter.fraction(value, signed: true)
                data.appendLittleEndian(UInt32(bitPattern: Int32(numerator)))
                data.appendLittleEndian(UInt32(denominator))
            }
            add(tag, .srational, values.count, data)
        }

        mutating func undefined(_ tag: UInt16, _ data: Data) { add(tag, .undefined, data.count, data) }

        mutating func subIFD(_ tag: UInt16, _ ifd: IFD) {
            entries.append(Entry(tag: tag, type: .long, count: 1, value: Data(count: 4), subIFD: ifd))
        }

        mutating func placeholder(_ tag: UInt16, count: Int) {
            entries.append(Entry(tag: tag, type: .long, count: count, value: Data(count: count * 4), isPlaceholder: true))
        }
    }

    /// A value as a fraction: the denominator a power of ten as large as fits.
    static func fraction(_ value: Double, signed: Bool) -> (Int64, Int64) {
        let limit = signed ? Double(Int32.max) : Double(UInt32.max)
        var denominator: Int64 = 1_000_000
        while denominator > 1, abs(value) * Double(denominator) > limit { denominator /= 10 }
        let numerator = (value * Double(denominator)).rounded()
        return (Int64(max(-limit, min(limit, numerator))), denominator)
    }

    /// Places IFDs and their values one after the other after the header.
    struct Layout {
        var data = Data()

        mutating func write(_ ifd: IFD, stripRows: [Int], rowBytes: Int) -> Data {
            data = Data([0x49, 0x49, 42, 0])       // "II", 42
            data.appendLittleEndian(UInt32(8))     // IFD0 at 8
            var stripOffsetsAt: Int?
            place(ifd, stripOffsetsAt: &stripOffsetsAt)
            // Pixels start at the next multiple of 16.
            while data.count % 16 != 0 { data.append(0) }
            let start = data.count
            if let at = stripOffsetsAt {
                for (index, row) in stripRows.enumerated() {
                    data.replaceLittleEndian(UInt32(start + row * rowBytes), at: at + index * 4)
                }
            }
            return data
        }

        /// Writes `ifd` at the end of the data; returns its offset.
        @discardableResult
        mutating func place(_ ifd: IFD, stripOffsetsAt: inout Int?) -> Int {
            if data.count % 2 != 0 { data.append(0) }
            let entries = ifd.entries.sorted { $0.tag < $1.tag }
            let offset = data.count
            data.appendLittleEndian(UInt16(entries.count))
            let entriesStart = data.count
            data.append(Data(count: entries.count * 12))
            data.appendLittleEndian(UInt32(0))     // no next IFD
            for (index, entry) in entries.enumerated() {
                let at = entriesStart + index * 12
                data.replaceLittleEndian(entry.tag, at: at)
                data.replaceLittleEndian(entry.type.rawValue, at: at + 2)
                data.replaceLittleEndian(UInt32(entry.count), at: at + 4)
                if let sub = entry.subIFD {
                    let subOffset = place(sub, stripOffsetsAt: &stripOffsetsAt)
                    data.replaceLittleEndian(UInt32(subOffset), at: at + 8)
                } else if entry.value.count <= 4 {
                    data.replaceSubrange((at + 8)..<(at + 8 + entry.value.count), with: entry.value)
                } else {
                    if data.count % 2 != 0 { data.append(0) }
                    let valueOffset = data.count
                    data.append(entry.value)
                    data.replaceLittleEndian(UInt32(valueOffset), at: at + 8)
                    if entry.isPlaceholder { stripOffsetsAt = valueOffset }
                }
                if entry.isPlaceholder, entry.value.count <= 4 { stripOffsetsAt = at + 8 }
            }
            return offset
        }
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func replaceLittleEndian<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        Swift.withUnsafeBytes(of: value.littleEndian) { replaceSubrange(offset..<(offset + MemoryLayout<T>.size), with: $0) }
    }
}
