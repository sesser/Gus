import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The crop a camera records for a raw file shot at an aspect ratio other than
/// its sensor's (1:1, 3:2 or 16:9 on a 4:3 sensor), which the RAW decoder
/// applies. A photo without a crop of its own shows that frame; cropping
/// starts from it, over the whole sensor.
///
/// Both formats read here keep the whole sensor in the file and the frame in a
/// few tags, so decoding a copy with those tags set to the whole image gets
/// the whole sensor back:
/// - Olympus and OM System (ORF): `AspectFrame` in the maker notes' image
///   processing IFD, inclusive edges in pixels of `CropWidth` × `CropHeight`.
/// - Panasonic (RW2): `CropTop`, `CropLeft`, `CropBottom`, `CropRight` in IFD0,
///   within the sensor borders (`SensorTopBorder` …), bottom and right exclusive.
///
/// Other formats are decoded as their decoder frames them.
public struct CameraFrame: Equatable, Sendable {
    /// The kept pixels, in pixels of the whole image and the sensor's orientation.
    var kept: CGRect
    /// Size of the whole image.
    var size: CGSize
    var orientation: CGImagePropertyOrientation
    /// The values that, written over the file's own, make the decoder give the
    /// whole image.
    var patches: [Patch]
    var bigEndian: Bool

    struct Patch: Equatable, Sendable {
        /// Where the values go in the file.
        var offset: UInt64
        var values: [UInt32]
        /// Bytes per value: 2 for SHORT, 4 for LONG.
        var width: Int
    }

    private enum Tag {
        static let orientation: UInt16 = 0x0112
        static let exifIFD: UInt16 = 0x8769
        static let makerNote: UInt16 = 0x927C
        static let imageProcessing: UInt16 = 0x2040
        static let cropWidth: UInt16 = 0x0614
        static let cropHeight: UInt16 = 0x0615
        static let aspectFrame: UInt16 = 0x1113
        static let sensorTopBorder: UInt16 = 0x0004
        static let sensorLeftBorder: UInt16 = 0x0005
        static let sensorBottomBorder: UInt16 = 0x0006
        static let sensorRightBorder: UInt16 = 0x0007
        static let cropTop: UInt16 = 0x002F
        static let cropLeft: UInt16 = 0x0030
        static let cropBottom: UInt16 = 0x0031
        static let cropRight: UInt16 = 0x0032
    }

    /// Nil unless `url` is an Olympus, OM System or Panasonic raw file with a
    /// readable frame.
    public init?(contentsOf url: URL) {
        let format = url.pathExtension.lowercased()
        guard ["orf", "ori", "rw2"].contains(format),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let reader = TIFFReader(handle: handle),
              let ifd0 = reader.entries(at: reader.firstIFDOffset) else { return nil }
        let read = format == "rw2" ? Self.panasonic(reader, ifd0: ifd0) : Self.olympus(reader, ifd0: ifd0)
        guard let (kept, size, patches) = read,
              kept.minX >= 0, kept.minY >= 0, kept.width > 0, kept.height > 0,
              kept.maxX <= size.width, kept.maxY <= size.height
        else { return nil }
        self.kept = kept
        self.size = size
        self.patches = patches
        bigEndian = reader.bigEndian
        // IFD0 holds it in ORF files; RW2 files keep it in their Exif, which ImageIO reads.
        let orientationValue = ifd0.first { $0.tag == Tag.orientation }.flatMap { reader.values($0).first }
            ?? Self.imageIOOrientation(url) ?? 1
        orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
    }

    private static func olympus(_ reader: TIFFReader, ifd0: [TIFFReader.Entry]) -> (CGRect, CGSize, [Patch])? {
        guard let exifOffset = ifd0.first(where: { $0.tag == Tag.exifIFD }).flatMap({ reader.values($0).first }),
              let exif = reader.entries(at: exifOffset),
              let makerNote = exif.first(where: { $0.tag == Tag.makerNote }), makerNote.count > 16
        else { return nil }
        // Offsets inside these maker notes count from the maker note's start.
        let base = reader.valueOffset(makerNote)
        guard let header = reader.read(16, at: base) else { return nil }
        let ifdOffset: UInt32
        let byteOrder: Data
        if header.starts(with: Data("OLYMPUS\0".utf8)) {
            ifdOffset = 12
            byteOrder = header[header.startIndex + 8 ..< header.startIndex + 10]
        } else if header.starts(with: Data("OM SYSTEM\0".utf8)) {
            ifdOffset = 16
            byteOrder = header[header.startIndex + 12 ..< header.startIndex + 14]
        } else {
            return nil
        }
        guard byteOrder == Data(reader.bigEndian ? "MM".utf8 : "II".utf8),
              let maker = reader.entries(at: ifdOffset, base: base),
              let processingOffset = maker.first(where: { $0.tag == Tag.imageProcessing })
                  .flatMap({ reader.values($0, base: base).first }),
              let processing = reader.entries(at: processingOffset, base: base)
        else { return nil }
        func first(_ tag: UInt16) -> UInt32? {
            processing.first { $0.tag == tag }.flatMap { reader.values($0, base: base).first }
        }
        guard let width = first(Tag.cropWidth), let height = first(Tag.cropHeight), width > 0, height > 0,
              let frameEntry = processing.first(where: { $0.tag == Tag.aspectFrame }),
              frameEntry.type == 3, frameEntry.count == 4
        else { return nil }
        let frame = reader.values(frameEntry, base: base)
        guard frame.count == 4, frame[0] <= frame[2], frame[1] <= frame[3] else { return nil }
        let kept = CGRect(x: Double(frame[0]), y: Double(frame[1]),
                          width: Double(frame[2] - frame[0] + 1), height: Double(frame[3] - frame[1] + 1))
        let patch = Patch(offset: reader.valueOffset(frameEntry, base: base), values: [0, 0, width - 1, height - 1],
                          width: 2)
        return (kept, CGSize(width: Double(width), height: Double(height)), [patch])
    }

    private static func panasonic(_ reader: TIFFReader, ifd0: [TIFFReader.Entry]) -> (CGRect, CGSize, [Patch])? {
        /// A SHORT or LONG value and where its field is (entries hold one value in place).
        func entry(_ tag: UInt16) -> (value: UInt32, offset: UInt64, width: Int)? {
            guard let index = ifd0.firstIndex(where: { $0.tag == tag }), ifd0[index].count == 1,
                  [3, 4].contains(ifd0[index].type), let value = reader.values(ifd0[index]).first else { return nil }
            return (value, UInt64(reader.firstIFDOffset) + 2 + UInt64(index) * 12 + 8, ifd0[index].type == 3 ? 2 : 4)
        }
        guard let top = entry(Tag.sensorTopBorder), let left = entry(Tag.sensorLeftBorder),
              let bottom = entry(Tag.sensorBottomBorder), let right = entry(Tag.sensorRightBorder),
              let cropTop = entry(Tag.cropTop), let cropLeft = entry(Tag.cropLeft),
              let cropBottom = entry(Tag.cropBottom), let cropRight = entry(Tag.cropRight),
              right.value > left.value, bottom.value > top.value,
              cropLeft.value >= left.value, cropTop.value >= top.value, cropRight.value > cropLeft.value,
              cropBottom.value > cropTop.value
        else { return nil }
        let kept = CGRect(x: Double(cropLeft.value - left.value), y: Double(cropTop.value - top.value),
                          width: Double(cropRight.value - cropLeft.value), height: Double(cropBottom.value - cropTop.value))
        let size = CGSize(width: Double(right.value - left.value), height: Double(bottom.value - top.value))
        let patches = [(cropTop, top), (cropLeft, left), (cropBottom, bottom), (cropRight, right)].map { crop, border in
            Patch(offset: crop.offset, values: [border.value], width: crop.width)
        }
        return (kept, size, patches)
    }

    private static func imageIOOrientation(_ url: URL) -> UInt32? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value
    }

    /// True when the camera kept the whole image.
    public var isFullFrame: Bool { kept == CGRect(origin: .zero, size: size) }

    /// The kept part in unit coordinates of the whole image as displayed.
    public var rect: CropRect {
        CropRect(x: kept.minX / size.width, y: kept.minY / size.height,
                 width: kept.width / size.width, height: kept.height / size.height)
            .oriented(orientation)
    }

    /// The camera's crop of `url` in unit coordinates of the whole image, or nil
    /// when the decoder gives the whole image (or the file says nothing).
    public static func rect(of url: URL) -> CropRect? {
        guard let frame = CameraFrame(contentsOf: url), !frame.isFullFrame else { return nil }
        return frame.rect
    }

    /// The file's bytes with the frame set to the whole image. The file itself
    /// is only read.
    func fullFrameData(of url: URL) -> Data? {
        guard var data = try? Data(contentsOf: url) else { return nil }
        for patch in patches {
            var bytes = Data()
            for value in patch.values {
                if patch.width == 2 {
                    let short = UInt16(truncatingIfNeeded: value)
                    withUnsafeBytes(of: bigEndian ? short.bigEndian : short.littleEndian) { bytes.append(contentsOf: $0) }
                } else {
                    withUnsafeBytes(of: bigEndian ? value.bigEndian : value.littleEndian) { bytes.append(contentsOf: $0) }
                }
            }
            guard patch.offset + UInt64(bytes.count) <= UInt64(data.count) else { return nil }
            let start = data.startIndex + Int(patch.offset)
            data.replaceSubrange(start ..< start + bytes.count, with: bytes)
        }
        return data
    }

    /// A RAW decoder for the whole sensor of `url`, or nil when the decoder
    /// already gives it (no camera crop).
    static func fullFrameFilter(for url: URL) -> CIRAWFilter? {
        guard let frame = CameraFrame(contentsOf: url), !frame.isFullFrame,
              let data = frame.fullFrameData(of: url) else { return nil }
        return CIRAWFilter(imageData: data, identifierHint: UTType(filenameExtension: url.pathExtension)?.identifier)
    }
}
