import Foundation

/// Facts about a DNG's TIFF structure that ImageIO does not report: what each
/// image in IFD0 and its SubIFDs is.
struct DNGLayout {
    struct Image: Equatable {
        /// NewSubfileType: 0 for the main image, bit 0 set for a reduced-resolution copy.
        var subfileType: UInt32
        var photometric: UInt32?
        /// SampleFormat: 1 unsigned integer, 3 floating point.
        var sampleFormat: UInt32
    }

    var images: [Image]

    /// Nil unless `url` is a readable DNG.
    init?(contentsOf url: URL) {
        guard url.pathExtension.lowercased() == "dng",
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let reader = TIFFReader(handle: handle),
              let ifd0 = reader.entries(at: reader.firstIFDOffset) else { return nil }
        func image(_ entries: [TIFFReader.Entry]) -> Image {
            func first(_ tag: UInt16) -> UInt32? { entries.first { $0.tag == tag }.flatMap { reader.values($0).first } }
            return Image(subfileType: first(Tag.newSubfileType) ?? 0, photometric: first(Tag.photometricInterpretation),
                         sampleFormat: first(Tag.sampleFormat) ?? 1)
        }
        let subIFDs = ifd0.first { $0.tag == Tag.subIFDs }.map(reader.values) ?? []
        images = [image(ifd0)] + subIFDs.prefix(64).compactMap { reader.entries(at: $0).map(image) }
    }

    /// Reduced-resolution copies of a linear (demosaiced) raw image next to the
    /// full one, as Lightroom's HDR merges keep.
    ///
    /// `CIRAWFilter` decodes from such a copy when asked for a small scale and
    /// renders it with almost no red, so these files are decoded at full size.
    var hasReducedLinearRaw: Bool {
        images.dropFirst().contains { $0.subfileType & 1 != 0 && $0.photometric == Tag.linearRaw }
    }

    /// The main raw image holds floating-point samples: an HDR merge, whose
    /// highlights are meant to go above white, unlike a camera's integer raw.
    var hasFloatingPointRaw: Bool {
        images.contains { image in
            image.subfileType == 0 && image.sampleFormat == Tag.floatingPoint
                && (image.photometric == Tag.linearRaw || image.photometric == Tag.colorFilterArray)
        }
    }

    private enum Tag {
        static let newSubfileType: UInt16 = 254
        static let photometricInterpretation: UInt16 = 262
        static let subIFDs: UInt16 = 330
        static let sampleFormat: UInt16 = 339
        /// PhotometricInterpretation of demosaiced DNG raw data.
        static let linearRaw: UInt32 = 34892
        /// PhotometricInterpretation of mosaiced (Bayer) raw data.
        static let colorFilterArray: UInt32 = 32803
        /// SampleFormat of IEEE floating-point samples.
        static let floatingPoint: UInt32 = 3
    }
}

/// Reads IFD entries of a classic (32-bit offset) TIFF file in either byte order.
private struct TIFFReader {
    struct Entry {
        var tag: UInt16
        var type: UInt16
        var count: UInt32
        /// The 4-byte value or offset field, in file byte order.
        var field: Data
    }

    let handle: FileHandle
    let bigEndian: Bool
    let firstIFDOffset: UInt32

    init?(handle: FileHandle) {
        self.handle = handle
        guard let header = Self.read(handle, 8, at: 0) else { return nil }
        switch (header[0], header[1]) {
        case (0x49, 0x49): bigEndian = false
        case (0x4D, 0x4D): bigEndian = true
        default: return nil
        }
        guard Self.integer(header, at: 2, as: UInt16.self, bigEndian: bigEndian) == 42 else { return nil }
        firstIFDOffset = Self.integer(header, at: 4, as: UInt32.self, bigEndian: bigEndian)
    }

    func entries(at offset: UInt32) -> [Entry]? {
        guard offset >= 8, let countData = Self.read(handle, 2, at: UInt64(offset)) else { return nil }
        let count = Int(integer(countData, at: 0, as: UInt16.self))
        guard count > 0, count <= 1024, let table = Self.read(handle, count * 12, at: UInt64(offset) + 2) else { return nil }
        return (0..<count).map { index in
            let base = index * 12
            return Entry(tag: integer(table, at: base, as: UInt16.self), type: integer(table, at: base + 2, as: UInt16.self),
                         count: integer(table, at: base + 4, as: UInt32.self),
                         field: table.subdata(in: (base + 8)..<(base + 12)))
        }
    }

    /// The values of a SHORT, LONG or IFD entry (at most 256 of them).
    func values(_ entry: Entry) -> [UInt32] {
        let size: Int
        switch entry.type {
        case 3: size = 2 // SHORT
        case 4, 13: size = 4 // LONG, IFD
        default: return []
        }
        let count = Int(min(entry.count, 256))
        let length = count * size
        guard count > 0,
              let data = length <= 4 ? entry.field
                  : Self.read(handle, length, at: UInt64(integer(entry.field, at: 0, as: UInt32.self)))
        else { return [] }
        return (0..<count).map { index in
            size == 2 ? UInt32(integer(data, at: index * 2, as: UInt16.self)) : integer(data, at: index * 4, as: UInt32.self)
        }
    }

    private func integer<T: FixedWidthInteger>(_ data: Data, at index: Int, as type: T.Type) -> T {
        Self.integer(data, at: index, as: type, bigEndian: bigEndian)
    }

    private static func integer<T: FixedWidthInteger>(_ data: Data, at index: Int, as type: T.Type, bigEndian: Bool) -> T {
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { buffer in
            buffer.copyBytes(from: data[(data.startIndex + index)..<(data.startIndex + index + MemoryLayout<T>.size)])
        }
        return bigEndian ? T(bigEndian: value) : T(littleEndian: value)
    }

    private static func read(_ handle: FileHandle, _ count: Int, at offset: UInt64) -> Data? {
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return data
    }
}
