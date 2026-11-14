import Foundation

/// What a Fujifilm RAF file says about its frame and its lens, read from the
/// file's container without decoding anything.
///
/// A RAF starts with a big-endian header that points at three sections: the
/// camera's embedded JPEG, a list of records (the "CFA header": the sensor's
/// size and the frame the camera keeps of it), and the raw data. In files of
/// the X-Trans generations the raw data section starts with a small
/// little-endian TIFF structure whose one entry (0xF000) points at an IFD of
/// Fujifilm's own tags; three of them are the camera's lens correction tables
/// (`LensTables`). Layout and tag numbers as ExifTool documents them
/// (FujiFilm RAF and FujiIFD tags) and as LibRaw and darktable read them.
///
/// The system's RAW decoder applies these corrections itself. LibRaw does
/// not, so for the raws it decodes (`LibRawDecoder`) they are read here.
public struct FujifilmRAF: Sendable, Equatable {
    /// The camera's lens correction tables: values at radii across the frame,
    /// from its center (0) to its corner (1, half the frame's diagonal), on
    /// the image as the sensor recorded it.
    public struct LensTables: Sendable, Equatable {
        /// The radii the values are given at, ascending, the first one 0 (a
        /// file whose knots start further out gets one at 0 where nothing is
        /// corrected, as darktable adds it).
        public var knots: [Double]
        /// Geometric distortion in percent of the radius: where a point at
        /// this radius of the recorded image belongs, relative to it
        /// (negative for barrel distortion: the point belongs further out).
        public var distortion: [Double]
        /// Lateral chromatic aberration: how much further out (as a fraction
        /// of the radius) red and blue are recorded than green.
        public var red: [Double]
        public var blue: [Double]
        /// The light reaching the sensor at this radius, in percent of the
        /// center's.
        public var vignetting: [Double]
        /// Half the diagonal, in pixels, of the frame the tables are for: the
        /// tags' leading value (that over the number of knots, in every file
        /// seen: 3605 / 11 for an X-E3's 6000 x 4000) times the knots. Nil
        /// for tables that did not come from a file.
        public var frameRadius: Double?

        public init(knots: [Double], distortion: [Double], red: [Double], blue: [Double], vignetting: [Double],
                    frameRadius: Double? = nil) {
            self.knots = knots
            self.distortion = distortion
            self.red = red
            self.blue = blue
            self.vignetting = vignetting
            self.frameRadius = frameRadius
        }

        /// The three tags' values, in either of the two layouts cameras write
        /// (as darktable's `exif.cc` tells them apart, by their counts):
        ///
        /// - 23, 31 and 23 values (X-Trans I to III, the X-E3 among them): a
        ///   leading value, then 11 knots and 11 values; the chromatic
        ///   aberration tag has 10 knots (no 0) and 10 values each for red
        ///   and blue.
        /// - 19, 29 and 19 values (X-Trans IV and V): a leading value, then 9
        ///   knots and 9 values; chromatic aberration has 9 knots, 9 red, 9
        ///   blue and a trailing value. These knots start away from the
        ///   center (0.35 in an X-T3's file): a knot at 0 with no distortion,
        ///   no shift and all the light is put before them, as darktable's
        ///   correction does ("add a knot with no corrections at 0"), so the
        ///   corrections fade to nothing toward the center instead of
        ///   holding the first knot's value there.
        ///
        /// Nil for any other count, for knots that differ between the tags,
        /// that do not ascend or leave 0 … 1.25, and for values no lens has
        /// (a table that would fold the image over itself).
        public init?(distortion d: [Double], chromaticAberration c: [Double], vignetting v: [Double]) {
            let count: Int
            let caKnots: [Double], red: [Double], blue: [Double]
            switch (d.count, c.count, v.count) {
            case (23, 31, 23):
                count = 11
                // No knot at 0: nothing is shifted at the center.
                caKnots = [0] + c[1...10]
                red = [0] + c[11...20]
                blue = [0] + c[21...30]
            case (19, 29, 19):
                count = 9
                caKnots = Array(c[1...9])
                red = Array(c[10...18])
                blue = Array(c[19...27])
            default:
                return nil
            }
            let knots = Array(d[1...count])
            guard knots == Array(v[1...count]), knots == caKnots else { return nil }
            self.init(knots: knots, distortion: Array(d[(count + 1)...(2 * count)]), red: red, blue: blue,
                      vignetting: Array(v[(count + 1)...(2 * count)]), frameRadius: d[0] * Double(count))
            if let first = knots.first, first > 0 {
                self.knots.insert(0, at: 0)
                distortion.insert(0, at: 0)
                self.red.insert(0, at: 0)
                self.blue.insert(0, at: 0)
                vignetting.insert(100, at: 0)
            }
            guard isPlausible, frameRadius?.isFinite == true else { return nil }
        }

        /// Knots that ascend within 0 … 1.25, and values a lens could have:
        /// distortion within ±30%, color shifts within ±2%, vignetting from
        /// 5% to 200% of the center's light, all finite.
        var isPlausible: Bool {
            let n = knots.count
            guard n >= 2, distortion.count == n, red.count == n, blue.count == n, vignetting.count == n else { return false }
            guard (knots + distortion + red + blue + vignetting).allSatisfy(\.isFinite) else { return false }
            guard knots[0] >= 0, knots[n - 1] <= 1.25, zip(knots, knots.dropFirst()).allSatisfy({ $0 < $1 }) else { return false }
            return distortion.allSatisfy { abs($0) <= 30 } && (red + blue).allSatisfy { abs($0) <= 0.02 }
                && vignetting.allSatisfy { (5...200).contains($0) }
        }

        /// Tables that correct nothing.
        public static let none = LensTables(knots: [0, 1], distortion: [0, 0], red: [0, 0], blue: [0, 0],
                                            vignetting: [100, 100])

        /// The tables correct nothing: no file needs resampling for them.
        public var isIdentity: Bool {
            distortion.allSatisfy { $0 == 0 } && red.allSatisfy { $0 == 0 } && blue.allSatisfy { $0 == 0 }
                && vignetting.allSatisfy { $0 == 100 }
        }
    }

    /// A rectangle of the sensor, in its pixels, from its top left.
    public struct PixelRect: Sendable, Equatable {
        public var left: Int, top: Int, width: Int, height: Int

        public init(left: Int, top: Int, width: Int, height: Int) {
            self.left = left
            self.top = top
            self.width = width
            self.height = height
        }
    }

    /// The whole sensor as the file stores it (`RawImageFullSize`).
    public var fullWidth: Int
    public var fullHeight: Int
    /// The part of it the camera makes its own pictures from
    /// (`RawImageCropTopLeft`, `RawImageCroppedSize`): 6000 x 4000 at
    /// (16, 21) on an X-E3. Nil when the file does not say or the rectangle
    /// does not fit the sensor.
    public var cameraFrame: PixelRect?
    /// Where the camera's embedded JPEG is in the file.
    public var embeddedJPEG: Range<UInt64>?
    public var lens: LensTables?
    /// The maker note's `CropMode` (0x104D) from the embedded JPEG's Exif,
    /// nil when it has none: 2 and 4 are the 1.25x crops some cameras offer,
    /// for which the tables' radii are of another frame (darktable multiplies
    /// the knots by 1.25 then).
    public var cropMode: Int?

    /// The camera's tables, when they can be applied to `frame` as they are:
    /// not in a 1.25x crop mode, and made for a frame of this size (the
    /// tables' own radius is this frame's half diagonal, to its rounding).
    /// Otherwise nil with the reason, for the log: no file of either kind
    /// was at hand to check a correction against, so such a file is shown
    /// uncorrected rather than corrected at the wrong radii.
    public func lensTables(for frame: PixelRect) -> (tables: LensTables?, refusal: String?) {
        guard let lens else { return (nil, nil) }
        if let cropMode, cropMode == 2 || cropMode == 4 {
            return (nil, "the camera's crop mode \(cropMode) (1.25x)")
        }
        let halfDiagonal = hypot(Double(frame.width), Double(frame.height)) / 2
        if let radius = lens.frameRadius, abs(radius - halfDiagonal) > 2 {
            return (nil, "tables made for a frame of half diagonal \(radius), not this one's \(halfDiagonal)")
        }
        return (lens, nil)
    }

    static let magic = Data("FUJIFILMCCD-RAW ".utf8)
    /// The header: the magic, the camera, and at 84 the three sections'
    /// offsets and lengths, big-endian.
    static let headerLength = 108
    /// Records of the CFA header are small; a section claiming more is not read.
    static let maximumRecordsLength = 1 << 20
    /// The Fujifilm IFD and its values sit before the raw data, in the first
    /// kilobyte or two of the section.
    static let maximumIFDLength = 1 << 16

    /// Reads the file's header and the two small parts of it that are
    /// parsed. Nil when it is not a RAF.
    public init?(contentsOf url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        self.init { offset, count in
            guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
            return try? handle.read(upToCount: count)
        }
    }

    /// A RAF held in memory (tests).
    public init?(data: Data) {
        self.init { offset, count in
            guard offset <= UInt64(data.count) else { return nil }
            let start = data.startIndex + Int(offset)
            return data.subdata(in: start..<min(start + count, data.endIndex))
        }
    }

    /// - Parameter read: Up to `count` bytes of the file at `offset`, or nil.
    init?(read: (_ offset: UInt64, _ count: Int) -> Data?) {
        guard let header = read(0, Self.headerLength), header.count == Self.headerLength,
              header.prefix(Self.magic.count) == Self.magic else { return nil }
        func section(_ at: Int) -> (offset: UInt64, length: Int) {
            (UInt64(Self.bigEndian32(header, at)), Int(Self.bigEndian32(header, at + 4)))
        }
        let jpeg = section(84), records = section(92), raw = section(100)
        fullWidth = 0
        fullHeight = 0
        if jpeg.offset > 0, jpeg.length > 0 {
            embeddedJPEG = jpeg.offset..<(jpeg.offset + UInt64(jpeg.length))
            // The Exif segment is at the JPEG's start and at most 64 KiB long.
            if let start = read(jpeg.offset, min(jpeg.length, Self.maximumIFDLength + 16)) {
                cropMode = Self.cropMode(inJPEG: start)
            }
        }
        if records.offset > 0, records.length >= 4,
           let data = read(records.offset, min(records.length, Self.maximumRecordsLength)) {
            parseRecords(data)
        }
        if raw.offset > 0, raw.length >= 8, let data = read(raw.offset, min(raw.length, Self.maximumIFDLength)) {
            lens = Self.lensTables(inRawSection: data)
        }
    }

    // MARK: The CFA header's records

    /// A count, then records of a tag, a length and that many bytes, all
    /// big-endian. Sizes are a height and a width, 16 bits each.
    private mutating func parseRecords(_ data: Data) {
        // A file cut short gives fewer bytes than its header promised.
        guard data.count >= 4 else { return }
        let count = Int(Self.bigEndian32(data, 0))
        var position = 4
        var origin: (top: Int, left: Int)?
        var size: (height: Int, width: Int)?
        for _ in 0..<min(count, 4096) {
            guard position + 4 <= data.count else { break }
            let tag = Self.bigEndian16(data, position), length = Int(Self.bigEndian16(data, position + 2))
            position += 4
            guard position + length <= data.count else { break }
            if length >= 4 {
                let first = Int(Self.bigEndian16(data, position)), second = Int(Self.bigEndian16(data, position + 2))
                switch tag {
                case 0x100: (fullHeight, fullWidth) = (first, second)
                case 0x110: origin = (first, second)
                case 0x111: size = (first, second)
                default: break
                }
            }
            position += length
        }
        if let origin, let size, size.width > 0, size.height > 0,
           origin.left + size.width <= fullWidth, origin.top + size.height <= fullHeight {
            cameraFrame = PixelRect(left: origin.left, top: origin.top, width: size.width, height: size.height)
        }
    }

    // MARK: The Fujifilm IFD

    private enum Tag {
        static let fujiIFD: UInt16 = 0xF000
        static let geometricDistortion: UInt16 = 0xF00B
        static let chromaticAberration: UInt16 = 0xF00F
        static let vignetting: UInt16 = 0xF010
    }

    /// The lens tables of a raw data section that starts with a
    /// little-endian TIFF header; nil for one that starts with raw data (older
    /// cameras), or without all three tables.
    static func lensTables(inRawSection data: Data) -> LensTables? {
        guard data.count >= 8, data.prefix(4) == Data([0x49, 0x49, 0x2A, 0x00]) else { return nil }
        guard let root = entries(data, at: Int(littleEndian32(data, 4))),
              let pointer = root.first(where: { $0.tag == Tag.fujiIFD }),
              let tags = entries(data, at: Int(pointer.value)) else { return nil }
        func rationals(_ tag: UInt16) -> [Double]? {
            // SRATIONAL: two signed 32-bit values each, at an offset from the header.
            guard let entry = tags.first(where: { $0.tag == tag }), entry.type == 10, (1...64).contains(entry.count),
                  Int(entry.value) + entry.count * 8 <= data.count else { return nil }
            return (0..<entry.count).map { index in
                let at = Int(entry.value) + index * 8
                let numerator = Int32(bitPattern: littleEndian32(data, at))
                let denominator = Int32(bitPattern: littleEndian32(data, at + 4))
                return denominator == 0 ? .nan : Double(numerator) / Double(denominator)
            }
        }
        guard let distortion = rationals(Tag.geometricDistortion), let aberration = rationals(Tag.chromaticAberration),
              let vignetting = rationals(Tag.vignetting) else { return nil }
        return LensTables(distortion: distortion, chromaticAberration: aberration, vignetting: vignetting)
    }

    // MARK: The crop mode

    /// `CropMode` from the Exif segment at the start of a JPEG: IFD0, the
    /// Exif IFD (0x8769), the maker note (0x927C, "FUJIFILM", then an IFD
    /// whose offsets count from the note's start), tag 0x104D. Little-endian
    /// Exif only, as Fujifilm writes it.
    static func cropMode(inJPEG data: Data) -> Int? {
        guard data.count >= 4, byte(data, 0) == 0xFF, byte(data, 1) == 0xD8 else { return nil }
        var position = 2
        while position + 4 <= data.count, byte(data, position) == 0xFF {
            let marker = byte(data, position + 1), length = Int(bigEndian16(data, position + 2))
            guard length >= 2, marker != 0xDA else { return nil }
            let end = min(position + 2 + length, data.count)
            if marker == 0xE1, position + 10 <= end,
               data.subdata(in: (data.startIndex + position + 4)..<(data.startIndex + position + 10)) == Data("Exif\0\0".utf8) {
                return cropMode(inExif: data.subdata(in: (data.startIndex + position + 10)..<(data.startIndex + end)))
            }
            position += 2 + length
        }
        return nil
    }

    private static func cropMode(inExif tiff: Data) -> Int? {
        guard tiff.count >= 8, tiff.prefix(4) == Data([0x49, 0x49, 0x2A, 0x00]),
              let root = entries(tiff, at: Int(littleEndian32(tiff, 4))),
              let exifPointer = root.first(where: { $0.tag == 0x8769 }),
              let exif = entries(tiff, at: Int(exifPointer.value)),
              let note = exif.first(where: { $0.tag == 0x927C }), note.count >= 12
        else { return nil }
        let start = Int(note.value)
        guard start >= 8, start + 12 <= tiff.count else { return nil }
        let maker = tiff.subdata(in: start..<min(start + note.count, tiff.count))
        guard maker.prefix(8) == Data("FUJIFILM".utf8), let tags = entries(maker, at: Int(littleEndian32(maker, 8))),
              let mode = tags.first(where: { $0.tag == 0x104D }), mode.type == 3, mode.count == 1
        else { return nil }
        return Int(mode.value & 0xFFFF)
    }

    private struct Entry {
        var tag: UInt16
        var type: UInt16
        var count: Int
        var value: UInt32
    }

    /// An IFD's entries: a 16-bit count, then twelve bytes each.
    private static func entries(_ data: Data, at offset: Int) -> [Entry]? {
        guard offset >= 8, offset + 2 <= data.count else { return nil }
        let count = Int(littleEndian16(data, offset))
        guard count <= 512, offset + 2 + count * 12 <= data.count else { return nil }
        return (0..<count).map { index in
            let at = offset + 2 + index * 12
            return Entry(tag: littleEndian16(data, at), type: littleEndian16(data, at + 2),
                         count: Int(littleEndian32(data, at + 4)), value: littleEndian32(data, at + 8))
        }
    }

    // MARK: Bytes

    private static func byte(_ data: Data, _ at: Int) -> UInt32 { UInt32(data[data.startIndex + at]) }

    static func bigEndian16(_ data: Data, _ at: Int) -> UInt16 {
        UInt16(byte(data, at) << 8 | byte(data, at + 1))
    }

    static func bigEndian32(_ data: Data, _ at: Int) -> UInt32 {
        byte(data, at) << 24 | byte(data, at + 1) << 16 | byte(data, at + 2) << 8 | byte(data, at + 3)
    }

    static func littleEndian16(_ data: Data, _ at: Int) -> UInt16 {
        UInt16(byte(data, at) | byte(data, at + 1) << 8)
    }

    static func littleEndian32(_ data: Data, _ at: Int) -> UInt32 {
        byte(data, at) | byte(data, at + 1) << 8 | byte(data, at + 2) << 16 | byte(data, at + 3) << 24
    }
}
