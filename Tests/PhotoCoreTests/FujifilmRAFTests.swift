import CoreGraphics
import Foundation
import ImageIO
import PhotoFixtures
import Testing
@testable import PhotoCore

/// A RAF container made of bytes, enough for `FujifilmRAF` to parse: the
/// header, an embedded "JPEG", the CFA header's records and a raw data
/// section that starts with the little-endian TIFF structure holding
/// Fujifilm's IFD.
enum SyntheticRAF {
    struct Rational {
        var numerator: Int32
        var denominator: Int32
        var value: Double { Double(numerator) / Double(denominator) }
    }

    /// `value` as a rational with six decimals.
    static func rational(_ value: Double) -> Rational {
        Rational(numerator: Int32((value * 1_000_000).rounded()), denominator: 1_000_000)
    }

    static func bigEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// The raw data section: a TIFF header, an IFD whose one entry (0xF000)
    /// points at Fujifilm's IFD, that IFD's entries and their values.
    static func rawSection(tags: [(tag: UInt16, values: [Rational])], pointerTag: UInt16 = 0xF000) -> Data {
        var data = Data([0x49, 0x49, 0x2A, 0x00]) + littleEndian(UInt32(8))
        data += littleEndian(UInt16(1)) + littleEndian(pointerTag) + littleEndian(UInt16(13)) + littleEndian(UInt32(1))
            + littleEndian(UInt32(26)) + littleEndian(UInt32(0))
        precondition(data.count == 26)
        // A width first, as cameras write, then the tables.
        let entryCount = tags.count + 1
        var valueOffset = 26 + 2 + entryCount * 12 + 4
        var entries = littleEndian(UInt16(entryCount))
        entries += littleEndian(UInt16(0xF001)) + littleEndian(UInt16(4)) + littleEndian(UInt32(1)) + littleEndian(UInt32(6048))
        var values = Data()
        for (tag, rationals) in tags {
            entries += littleEndian(tag) + littleEndian(UInt16(10)) + littleEndian(UInt32(rationals.count))
                + littleEndian(UInt32(valueOffset))
            for rational in rationals { values += littleEndian(rational.numerator) + littleEndian(rational.denominator) }
            valueOffset += rationals.count * 8
        }
        return data + entries + littleEndian(UInt32(0)) + values
    }

    static func records(fullSize: (width: Int, height: Int)?, cropOrigin: (left: Int, top: Int)?,
                        cropSize: (width: Int, height: Int)?) -> Data {
        var list: [(UInt16, Data)] = []
        if let fullSize { list.append((0x100, bigEndian(UInt16(fullSize.height)) + bigEndian(UInt16(fullSize.width)))) }
        if let cropOrigin { list.append((0x110, bigEndian(UInt16(cropOrigin.top)) + bigEndian(UInt16(cropOrigin.left)))) }
        if let cropSize { list.append((0x111, bigEndian(UInt16(cropSize.height)) + bigEndian(UInt16(cropSize.width)))) }
        // A record the parser has no use for, with an odd length.
        list.append((0x9650, Data([0xFF, 0x54, 0x00])))
        var data = bigEndian(UInt32(list.count))
        for (tag, payload) in list { data += bigEndian(tag) + bigEndian(UInt16(payload.count)) + payload }
        return data
    }

    static func file(jpeg: Data = Data([0xFF, 0xD8, 0xFF, 0xD9]), records: Data, raw: Data) -> Data {
        var header = Data("FUJIFILMCCD-RAW 0201FF129505X-E3".utf8)
        header += Data(count: 84 - header.count)
        let jpegOffset = 160, recordsOffset = jpegOffset + jpeg.count, rawOffset = recordsOffset + records.count
        for (offset, length) in [(jpegOffset, jpeg.count), (recordsOffset, records.count), (rawOffset, raw.count)] {
            header += bigEndian(UInt32(offset)) + bigEndian(UInt32(length))
        }
        header += Data(count: 160 - header.count)
        return header + jpeg + records + raw
    }

    /// The Fujifilm XF 35mm f/2's tables at f/2 as an X-E3 writes them
    /// (11 knots; the leading value is the frame's half diagonal in pixels
    /// over the number of knots).
    static let distortion35 = [0, -0.027, -0.11, -0.302, -0.656, -1.191, -1.898, -2.816, -3.999, -5.575, -7.568]
    static let red35 = [1.8e-05, 4.5e-05, 8.8e-05, 0.000155, 0.000183, 0.000123, 0.000178, 0.000216, 0.000261, 0.000274]
    static let blue35 = [-5.7e-05, -0.000112, -0.00016, -0.0002, -0.000244, -0.0003, -0.000331, -0.0004, -0.000383, -0.000335]
    static let vignetting35 = [100, 97.69, 95.09, 91.87, 87.77, 83.13, 78.63, 73.69, 68.55, 62.96, 52.15]
    static let knots11 = (0...10).map { Double($0) / 10 }

    static func elevenKnotTags(distortion: [Double] = distortion35, red: [Double] = red35, blue: [Double] = blue35,
                               vignetting: [Double] = vignetting35, knots: [Double] = knots11)
        -> [(tag: UInt16, values: [Rational])] {
        let lead = Rational(numerator: 3605, denominator: 11), caLead = Rational(numerator: 3605, denominator: 10)
        return [
            (0xF00B, [lead] + knots.map(rational) + distortion.map(rational)),
            (0xF00F, [caLead] + knots.dropFirst().map(rational) + red.map(rational) + blue.map(rational)),
            (0xF010, [lead] + knots.map(rational) + vignetting.map(rational)),
        ]
    }

    /// A JPEG that is only its Exif segment: IFD0, the Exif IFD, and Fujifilm's
    /// maker note with `CropMode` (0x104D), or without it.
    static func exifJPEG(cropMode: UInt16?) -> Data {
        func entry(_ tag: UInt16, _ type: UInt16, _ count: UInt32, _ value: UInt32) -> Data {
            littleEndian(tag) + littleEndian(type) + littleEndian(count) + littleEndian(value)
        }
        // The note's offsets count from its own start: its IFD is 12 bytes in.
        var note = Data("FUJIFILM".utf8) + littleEndian(UInt32(12)) + littleEndian(UInt16(1))
        note += entry(cropMode == nil ? 0x1000 : 0x104D, 3, 1, UInt32(cropMode ?? 0)) + littleEndian(UInt32(0))
        var tiff = Data([0x49, 0x49, 0x2A, 0x00]) + littleEndian(UInt32(8))
        tiff += littleEndian(UInt16(1)) + entry(0x8769, 4, 1, 26) + littleEndian(UInt32(0))
        tiff += littleEndian(UInt16(1)) + entry(0x927C, 7, UInt32(note.count), 44) + littleEndian(UInt32(0))
        precondition(tiff.count == 44)
        tiff += note
        let payload = Data("Exif\0\0".utf8) + tiff
        return Data([0xFF, 0xD8, 0xFF, 0xE1]) + bigEndian(UInt16(payload.count + 2)) + payload + Data([0xFF, 0xD9])
    }

    static func xe3(cropMode: UInt16? = nil, tags: [(tag: UInt16, values: [Rational])]? = nil) -> Data {
        file(jpeg: exifJPEG(cropMode: cropMode),
             records: records(fullSize: (6048, 4038), cropOrigin: (16, 21), cropSize: (6000, 4000)),
             raw: rawSection(tags: tags ?? elevenKnotTags()))
    }

    /// An X-T3's tables with the XF 23mm f/1.4 (nine knots, the first at 0.35 of the radius;
    /// `DSCF4583.RAF` as ExifTool prints it, to six decimals). The leading value is 3749 / 9.
    static let knots9 = [0.353521, 0.5, 0.612676, 0.707042, 0.790845, 0.866197, 0.935211, 1, 1.060563]
    static let red9 = [0.000366, 0.000336, 0.000336, 0.000305, 0.000244, 0.000214, 0.000214, 0.000214, 0.000214]
    static let blue9 = [-0.000244, -0.000122, -0.000061, 0, 0.000061, 0.000092, 0.000122, 0.000122, 0.000122]
    static let vignetting9 = [98.461426, 97.663086, 96.512695, 95.700684, 94.902344, 93.729492, 92.168945, 90.619141, 89.120605]

    static func xt3(distortion: [Double] = [Double](repeating: 0, count: 9)) -> Data {
        let lead = Rational(numerator: 3749, denominator: 9)
        let raw = rawSection(tags: [
            (0xF00B, [lead] + knots9.map(rational) + distortion.map(rational)),
            (0xF00F, [lead] + knots9.map(rational) + red9.map(rational) + blue9.map(rational) + [lead]),
            (0xF010, [lead] + knots9.map(rational) + vignetting9.map(rational)),
        ])
        return file(jpeg: exifJPEG(cropMode: 0),
                    records: records(fullSize: (6384, 4182), cropOrigin: (6, 13), cropSize: (6240, 4160)), raw: raw)
    }
}

@Suite("Fujifilm RAF container")
struct FujifilmRAFTests {
    @Test("The frame, the embedded JPEG and the lens tables are read from an X-E3's layout")
    func readsElevenKnotLayout() throws {
        let raf = try #require(FujifilmRAF(data: SyntheticRAF.xe3()))
        #expect(raf.fullWidth == 6048 && raf.fullHeight == 4038)
        #expect(raf.cameraFrame == FujifilmRAF.PixelRect(left: 16, top: 21, width: 6000, height: 4000))
        #expect(raf.embeddedJPEG == 160..<UInt64(160 + SyntheticRAF.exifJPEG(cropMode: nil).count))
        #expect(raf.cropMode == nil)
        let lens = try #require(raf.lens)
        // The tags' leading value times the knots: the frame's half diagonal, rounded down.
        #expect(lens.frameRadius == 3605)
        #expect(raf.lensTables(for: try #require(raf.cameraFrame)).tables == lens)
        #expect(lens.knots == SyntheticRAF.knots11)
        #expect(lens.distortion == SyntheticRAF.distortion35)
        #expect(lens.vignetting == SyntheticRAF.vignetting35)
        // The chromatic aberration tag has no knot at the center: nothing is shifted there.
        #expect(lens.red == [0] + SyntheticRAF.red35)
        #expect(lens.blue == [0] + SyntheticRAF.blue35)
        #expect(!lens.isIdentity)
    }

    /// Code review C20: an X-T3's knots start at 0.35 of the radius. Held to
    /// the center, the first knot's values would shift the whole middle of
    /// the frame (and brighten it by 1.6% with these tables); darktable puts
    /// a knot at 0 where nothing is corrected.
    @Test("A later camera's nine knots start away from the center: one at 0 with no correction is put before them")
    func readsARealNineKnotLayout() throws {
        let raf = try #require(FujifilmRAF(data: SyntheticRAF.xt3()))
        #expect(raf.cameraFrame == FujifilmRAF.PixelRect(left: 6, top: 13, width: 6240, height: 4160))
        #expect(raf.cropMode == 0)
        let lens = try #require(raf.lens)
        #expect(lens.knots == [0] + SyntheticRAF.knots9)
        #expect(lens.distortion == [Double](repeating: 0, count: 10))
        #expect(lens.red == [0] + SyntheticRAF.red9 && lens.blue == [0] + SyntheticRAF.blue9)
        #expect(lens.vignetting == [100] + SyntheticRAF.vignetting9)
        #expect(lens.frameRadius == 3749)
        // Its own frame's half diagonal is 3749.9: the tables are for this frame.
        #expect(raf.lensTables(for: try #require(raf.cameraFrame)).tables == lens)
        // Nothing is corrected at the center, and the corrections grow in from there.
        #expect(EmbeddedLensCorrection.gain(lens, sourceRadius: 0) == 1)
        #expect(abs(EmbeddedLensCorrection.gain(lens, sourceRadius: 0.353521 / 2) - 100 / ((100 + 98.461426) / 2)) < 1e-12)
        let barrel = try #require(FujifilmRAF(data: SyntheticRAF.xt3(distortion: [-0.469, -1.1, -1.9, -2.8, -3.8, -4.9, -6.1, -7.4, -8.9])))
        let tables = try #require(barrel.lens)
        #expect(EmbeddedLensCorrection.multipliers(tables, destinationRadius: 0) == SIMD3(1, 1, 1))
        #expect(abs(EmbeddedLensCorrection.distortionFactor(tables, sourceRadius: 0.353521 / 2) - (1 - 0.00469 / 2)) < 1e-12)
    }

    @Test("The nine-knot layout is read as it is when its knots start at the center")
    func readsNineKnotLayout() throws {
        let knots = [0.0, 0.15, 0.3, 0.45, 0.6, 0.7, 0.8, 0.9, 1.0]
        let distortion = [0, 0.05, 0.2, 0.45, 0.8, 1.1, 1.4, 1.8, 2.3]
        let red = [0, 1e-05, 2e-05, 3e-05, 4e-05, 5e-05, 6e-05, 7e-05, 8e-05]
        let blue = red.map { -$0 }
        let vignetting = [100, 99, 97, 94, 90, 86, 81, 75, 68.5]
        let r = SyntheticRAF.rational
        let lead = SyntheticRAF.Rational(numerator: 4000, denominator: 9)
        let raw = SyntheticRAF.rawSection(tags: [
            (0xF00B, [lead] + knots.map(r) + distortion.map(r)),
            (0xF00F, [lead] + knots.map(r) + red.map(r) + blue.map(r) + [r(1)]),
            (0xF010, [lead] + knots.map(r) + vignetting.map(r)),
        ])
        let data = SyntheticRAF.file(records: SyntheticRAF.records(fullSize: (6384, 4182), cropOrigin: (72, 15), cropSize: (6240, 4160)),
                                     raw: raw)
        let raf = try #require(FujifilmRAF(data: data))
        #expect(raf.cameraFrame == FujifilmRAF.PixelRect(left: 72, top: 15, width: 6240, height: 4160))
        #expect(raf.lens == FujifilmRAF.LensTables(knots: knots, distortion: distortion, red: red, blue: blue, vignetting: vignetting,
                                                   frameRadius: 4000))
    }

    @Test("A file without the tables, or with tables no lens has, has no lens corrections and keeps its frame")
    func filesWithoutUsableTables() throws {
        let records = SyntheticRAF.records(fullSize: (6048, 4038), cropOrigin: (16, 21), cropSize: (6000, 4000))
        func lens(_ raw: Data) -> FujifilmRAF.LensTables? {
            let raf = FujifilmRAF(data: SyntheticRAF.file(records: records, raw: raw))
            #expect(raf?.cameraFrame?.width == 6000)
            return raf?.lens
        }
        // The premise: the same builder with the real tables gives them.
        #expect(lens(SyntheticRAF.rawSection(tags: SyntheticRAF.elevenKnotTags())) != nil)
        // An older camera: the section starts with raw data.
        #expect(lens(Data(repeating: 0x5A, count: 4096)) == nil)
        // A manual lens: no distortion tag; or no Fujifilm IFD at all.
        #expect(lens(SyntheticRAF.rawSection(tags: Array(SyntheticRAF.elevenKnotTags().dropFirst()))) == nil)
        #expect(lens(SyntheticRAF.rawSection(tags: SyntheticRAF.elevenKnotTags(), pointerTag: 0xF0F0)) == nil)
        // Knots that differ between the tags, or do not ascend.
        var tags = SyntheticRAF.elevenKnotTags()
        tags[2].values[3] = SyntheticRAF.rational(0.25)
        #expect(lens(SyntheticRAF.rawSection(tags: tags)) == nil)
        var descending = SyntheticRAF.knots11
        descending.swapAt(4, 5)
        #expect(lens(SyntheticRAF.rawSection(tags: SyntheticRAF.elevenKnotTags(knots: descending))) == nil)
        // A count neither layout has.
        tags = SyntheticRAF.elevenKnotTags()
        tags[0].values.removeLast()
        #expect(lens(SyntheticRAF.rawSection(tags: tags)) == nil)
        // Values no lens has: half the radius of distortion, no light at the corner, a zero denominator.
        var wild = SyntheticRAF.distortion35
        wild[10] = -50
        #expect(lens(SyntheticRAF.rawSection(tags: SyntheticRAF.elevenKnotTags(distortion: wild))) == nil)
        var dark = SyntheticRAF.vignetting35
        dark[10] = 0
        #expect(lens(SyntheticRAF.rawSection(tags: SyntheticRAF.elevenKnotTags(vignetting: dark))) == nil)
        tags = SyntheticRAF.elevenKnotTags()
        tags[0].values[15].denominator = 0
        #expect(lens(SyntheticRAF.rawSection(tags: tags)) == nil)
        // Tables that correct nothing are read, and say so.
        let flat = lens(SyntheticRAF.rawSection(tags: SyntheticRAF.elevenKnotTags(
            distortion: [Double](repeating: 0, count: 11), red: [Double](repeating: 0, count: 10),
            blue: [Double](repeating: 0, count: 10), vignetting: [Double](repeating: 100, count: 11))))
        #expect(flat?.isIdentity == true)
    }

    @Test("A frame that does not fit the sensor is left out; other files are not RAFs")
    func framesAndOtherFiles() throws {
        let raw = SyntheticRAF.rawSection(tags: SyntheticRAF.elevenKnotTags())
        let outside = SyntheticRAF.file(records: SyntheticRAF.records(fullSize: (6048, 4038), cropOrigin: (100, 21),
                                                                      cropSize: (6000, 4000)), raw: raw)
        let raf = try #require(FujifilmRAF(data: outside))
        #expect(raf.cameraFrame == nil)
        #expect(raf.lens != nil)
        let noOrigin = SyntheticRAF.file(records: SyntheticRAF.records(fullSize: (6048, 4038), cropOrigin: nil, cropSize: (6000, 4000)),
                                         raw: raw)
        #expect(FujifilmRAF(data: noOrigin)?.cameraFrame == nil)
        #expect(FujifilmRAF(data: Data()) == nil)
        #expect(FujifilmRAF(data: Data("FUJIFILMCCD-RAW ".utf8)) == nil)
        #expect(FujifilmRAF(data: Data(repeating: 0, count: 4096)) == nil)
        #expect(FujifilmRAF(contentsOf: URL(fileURLWithPath: "/nonexistent/photo.RAF")) == nil)
    }

    /// Code review Q11. In the 1.25x crop modes (2 and 4) the tables' radii are
    /// of another frame (darktable multiplies the knots by 1.25), and the
    /// tags' leading value says which frame the tables are for. No file of
    /// either kind was at hand, so such a file is left uncorrected.
    @Test("Tables are not used in a 1.25x crop mode, or when they are for another frame")
    func tablesForAnotherFrame() throws {
        let frame = FujifilmRAF.PixelRect(left: 16, top: 21, width: 6000, height: 4000)
        for (mode, usable) in [(nil, true), (0, true), (1, true), (2, false), (3, true), (4, false)] as [(UInt16?, Bool)] {
            let raf = try #require(FujifilmRAF(data: SyntheticRAF.xe3(cropMode: mode)))
            #expect(raf.cropMode == mode.map(Int.init))
            #expect(raf.lens != nil)
            let answer = raf.lensTables(for: frame)
            #expect((answer.tables != nil) == usable, "crop mode \(String(describing: mode))")
            #expect((answer.refusal != nil) == !usable)
        }
        // Tables whose leading value is another frame's half diagonal (4800 x 3200: 2884).
        var tags = SyntheticRAF.elevenKnotTags()
        tags[0].values[0] = SyntheticRAF.Rational(numerator: 2884, denominator: 11)
        let other = try #require(FujifilmRAF(data: SyntheticRAF.xe3(tags: tags)))
        #expect(other.lens?.frameRadius == 2884)
        #expect(other.lensTables(for: frame).tables == nil)
        #expect(other.lensTables(for: frame).refusal?.contains("2884") == true)
        #expect(other.lensTables(for: FujifilmRAF.PixelRect(left: 0, top: 0, width: 4800, height: 3200)).tables != nil)
        // A JPEG without Exif, with a big-endian one, or cut inside the maker note: no mode, no crash.
        #expect(FujifilmRAF.cropMode(inJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9])) == nil)
        let exif = SyntheticRAF.exifJPEG(cropMode: 4)
        #expect(FujifilmRAF.cropMode(inJPEG: exif) == 4)
        var bigEndian = exif
        bigEndian[12] = 0x4D
        bigEndian[13] = 0x4D
        #expect(FujifilmRAF.cropMode(inJPEG: bigEndian) == nil)
        for length in 0..<exif.count { _ = FujifilmRAF.cropMode(inJPEG: exif.prefix(length)) }
    }

    /// Offsets, counts and lengths come from the file: none may be trusted.
    @Test("Damaged files are read without a crash: cut short anywhere, or with any byte changed")
    func damagedFiles() {
        // With the Exif segment and a crop mode in it, so that parser is damaged too.
        let whole = SyntheticRAF.xe3(cropMode: 2)
        for length in 0..<whole.count {
            _ = FujifilmRAF(data: whole.prefix(length))
        }
        var random = SplitMix64(seed: 161)
        for _ in 0..<4000 {
            var damaged = whole
            // Mostly in the structures (the header's offsets, the records, the IFDs), with wild values.
            for _ in 0..<(1 + Int(random.next() % 3)) {
                let index = 84 + Int(random.next() % UInt64(damaged.count - 84))
                damaged[index] = UInt8(truncatingIfNeeded: random.next())
            }
            if let raf = FujifilmRAF(data: damaged), let lens = raf.lens {
                // Whatever is returned is usable.
                #expect(lens.isPlausible)
            }
        }
        // A slice of a larger buffer parses as the same file.
        let padded = Data(repeating: 0xEE, count: 37) + whole
        #expect(FujifilmRAF(data: padded.suffix(whole.count)) == FujifilmRAF(data: whole))
    }

    @Test("A file on disk is read through its header and two small parts")
    func readsFromDisk() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "synthetic.RAF")
            // Raw data after the tables, as in a camera's file: it is never read.
            try (SyntheticRAF.xe3() + Data(repeating: 0xAB, count: 300_000)).write(to: url)
            #expect(FujifilmRAF(contentsOf: url) == FujifilmRAF(data: SyntheticRAF.xe3()))
            // Not a raw LibRaw can decode: the decoder's frame logic is not reached, and nothing crashes.
            #expect(LibRawDecoder.frameSize(url) == nil)
            #expect(throws: LibRawDecoder.Failure.self) { _ = try LibRawDecoder.decode(url) }
        }
    }
}
