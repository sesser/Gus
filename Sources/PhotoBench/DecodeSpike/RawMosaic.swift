import CLibRaw
import Foundation
import ImageIO
import PhotoCore

// SPIKE for issue #194: throwaway, not part of the app. See
// docs/features/decode-pipeline-spike/spike.md.
//
// LibRaw's unpack only: the sensor's values over the visible area, the color
// filter pattern, black and white levels and the camera's color, with no
// demosaic. Our own kernels take it from here.

/// One raw's mosaic, as LibRaw unpacks it, before any of LibRaw's processing.
struct RawMosaic {
    var file: String
    var make: String
    var model: String
    var lens: String
    var focalLength: Double
    /// EXIF's 35 mm equivalent focal length (0 when not given).
    var focalLength35 = 0.0
    var aperture: Double
    /// The visible area, in sensor pixels (LibRaw's `width` x `height`).
    var width: Int
    var height: Int
    /// Sensor values of the visible area, row by row from the top.
    var values: [UInt16]
    /// The color of each site of the repeating pattern, 0 red, 1 green, 2 blue
    /// (LibRaw's second green folded into 1): `period` x `period`, rows first.
    var pattern: [Int32]
    var period: Int
    /// Black per pattern site (common black, the color's own black and a pattern
    /// black, as LibRaw adds them), and the white level less the common black.
    var blackPerSite: [Float]
    var whiteSpan: Float
    /// LibRaw's `maximum` and common black before the span.
    var maximum: Int
    var commonBlack: Int
    /// Our multipliers (the reciprocal of the as-shot neutral, the largest 1),
    /// the same as `LibRawDecoder` gives LibRaw (`user_mul`).
    var multipliers: SIMD3<Double>
    /// The camera's color with the built-in profile; nil when unusable.
    var color: CameraColor?
    /// `multipliers` x 0.99, `LibRawDecoder`'s channel scale.
    var channelScale: SIMD3<Double>
    var flip: Int
    var isXTrans: Bool
    /// Wall-clock times of LibRaw's open and unpack, and our copy, in ms.
    var openMs: Double
    var unpackMs: Double
    var copyMs: Double

    /// The pattern site's color at a visible pixel.
    @inline(__always) func color(row: Int, column: Int) -> Int {
        Int(pattern[(row % period) * period + column % period])
    }

    @inline(__always) func black(row: Int, column: Int) -> Float {
        blackPerSite[(row % period) * period + column % period]
    }

    /// The mosaic normalized as LibRaw's `scale_colors` leaves it for its
    /// demosaic: (value − black) / span, clipped to 0 … 1, times the multiplier.
    func normalized() -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        let scale = (0..<pattern.count).map { Float(multipliers[Int(pattern[$0])]) / whiteSpan }
        values.withUnsafeBufferPointer { source in
            out.withUnsafeMutableBufferPointer { target in
                for row in 0..<height {
                    let base = row * width
                    let pr = (row % period) * period
                    for column in 0..<width {
                        let site = pr + column % period
                        let v = min(max(Float(source[base + column]) - blackPerSite[site], 0), whiteSpan)
                        target[base + column] = v * scale[site]
                    }
                }
            }
        }
        return out
    }

    enum Failure: Error, CustomStringConvertible {
        case libraw(String, Int32)
        case unsupported(String)
        var description: String {
            switch self {
            case .libraw(let step, let code): "LibRaw \(step): \(String(cString: libraw_strerror(code)))"
            case .unsupported(let reason): reason
            }
        }
    }

    /// The lens model as ImageIO reads it (EXIF or its auxiliary dictionary), for files whose lens LibRaw leaves empty.
    static func imageIOLens(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let aux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any]
        return (exif?[kCGImagePropertyExifLensModel] as? String) ?? (aux?[kCGImagePropertyExifAuxLensModel] as? String)
    }

    static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Opens and unpacks `url` (nothing else of LibRaw's runs).
    init(_ url: URL) throws {
        let clock = ContinuousClock()
        let t0 = clock.now
        guard let processor = libraw_init(0) else { throw Failure.unsupported("no memory") }
        defer { libraw_close(processor) }
        var code = libraw_open_file(processor, url.path)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("open", code) }
        let t1 = clock.now
        code = libraw_unpack(processor)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("unpack", code) }
        let t2 = clock.now
        file = url.lastPathComponent
        // Fields are read through the pointer: `libraw_data_t` is too large to copy onto a task's stack.
        make = Self.string(processor.pointee.idata.make)
        model = Self.string(processor.pointee.idata.model)
        // The lens name: EXIF's, else the maker notes' (a Panasonic RW2 has it only there).
        let exifLens = Self.string(processor.pointee.lens.Lens)
        let noteLens = Self.string(processor.pointee.lens.makernotes.Lens)
        lens = !exifLens.isEmpty ? exifLens : !noteLens.isEmpty ? noteLens : Self.imageIOLens(url) ?? ""
        focalLength35 = Double(processor.pointee.lens.FocalLengthIn35mmFormat)
        focalLength = Double(processor.pointee.other.focal_len)
        aperture = Double(processor.pointee.other.aperture)
        let colors = processor.pointee.idata.colors, filters = processor.pointee.idata.filters
        guard colors == 3, filters != 0, let raw = processor.pointee.rawdata.raw_image else {
            throw Failure.unsupported("not a three-color mosaic (colors \(colors), filters \(filters))")
        }
        let sizes = processor.pointee.sizes
        width = Int(sizes.width)
        height = Int(sizes.height)
        flip = Int(sizes.flip)
        isXTrans = filters == 9
        period = isXTrans ? 6 : 2
        var sitesColors: [Int32] = []
        var colorWithSecondGreen: [Int] = []
        for row in 0..<period {
            for column in 0..<period {
                let c = Int(libraw_COLOR(processor, Int32(row), Int32(column)))
                colorWithSecondGreen.append(c)
                sitesColors.append(Int32(c == 3 ? 1 : c))
            }
        }
        pattern = sitesColors
        guard Set(sitesColors) == [0, 1, 2] else { throw Failure.unsupported("pattern \(colorWithSecondGreen)") }

        // Black: LibRaw's common black, each color's own (cblack[0…3]) and a
        // repeating pattern (cblack[4] rows by cblack[5] columns from cblack[6]).
        // `cblack` (4104 values) is too large a C array for Swift to import: it sits just before `black`.
        var cblack = [UInt32](repeating: 0, count: 6 + 36)
        let cblackOffset = MemoryLayout<libraw_data_t>.offset(of: \.color)! + MemoryLayout<libraw_colordata_t>.offset(of: \.black)! - 4104 * 4
        let base = UnsafeRawPointer(processor)
        for i in 0..<cblack.count { cblack[i] = base.load(fromByteOffset: cblackOffset + i * 4, as: UInt32.self) }
        let commonBlackValue = processor.pointee.color.black, maximumValue = processor.pointee.color.maximum
        var sites: [Float] = []
        for row in 0..<period {
            for column in 0..<period {
                var b = Double(commonBlackValue) + Double(cblack[colorWithSecondGreen[row * period + column]])
                if cblack[4] > 0, cblack[5] > 0 {
                    b += Double(cblack[6 + (row % Int(cblack[4])) * Int(cblack[5]) + column % Int(cblack[5])])
                }
                sites.append(Float(b))
            }
        }
        blackPerSite = sites
        // LibRaw moves the smallest black into the common one and takes it off its maximum.
        let common = Int(sites.min() ?? 0)
        commonBlack = common
        maximum = Int(maximumValue)
        whiteSpan = Float(Int(maximumValue) - common)

        // White balance: what `LibRawDecoder` asks LibRaw for.
        let cameraColor = LibRawDecoder.cameraColor(url)
        self.color = cameraColor
        if let cameraColor {
            multipliers = cameraColor.asShotNeutral.min() / cameraColor.asShotNeutral
        } else {
            let m = processor.pointee.color.cam_mul
            let c = SIMD3(Double(m.0), Double(m.1), Double(m.2))
            multipliers = c / c.max()
        }
        channelScale = multipliers * 0.99

        // The visible area, copied out of LibRaw's buffer.
        let pitch = Int(sizes.raw_pitch) / 2
        let left = Int(sizes.left_margin), top = Int(sizes.top_margin)
        let w = width, h = height
        var copy = [UInt16](repeating: 0, count: w * h)
        copy.withUnsafeMutableBufferPointer { target in
            for row in 0..<h {
                (target.baseAddress! + row * w).update(from: raw + (row + top) * pitch + left, count: w)
            }
        }
        values = copy
        let t3 = clock.now
        openMs = (t1 - t0).milliseconds
        unpackMs = (t2 - t1).milliseconds
        copyMs = (t3 - t2).milliseconds
    }

    /// A mosaic made from a full-color picture (for tests against a known truth).
    init(truth: [SIMD3<Float>], width: Int, height: Int, pattern: [Int32], period: Int) {
        file = "synthetic"; make = "synthetic"; model = "truth"; lens = ""; focalLength = 0; aperture = 0
        self.width = width; self.height = height
        self.pattern = pattern; self.period = period
        blackPerSite = [Float](repeating: 0, count: period * period)
        whiteSpan = 65535; maximum = 65535; commonBlack = 0
        multipliers = SIMD3(1, 1, 1); color = nil; channelScale = SIMD3(1, 1, 1) * 0.99
        flip = 0; isXTrans = period == 6
        openMs = 0; unpackMs = 0; copyMs = 0
        var v = [UInt16](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let c = Int(pattern[(row % period) * period + column % period])
                v[row * width + column] = UInt16(min(max(truth[row * width + column][c] * 65535, 0), 65535).rounded())
            }
        }
        values = v
    }

    /// The X-Trans pattern of the Fujifilm X-E3 and X-T3 as LibRaw reports it
    /// at the visible origin is read from the file; this is only for tests.
    var patternDescription: String {
        (0..<period).map { r in (0..<period).map { "RGB"[String.Index(utf16Offset: Int(pattern[r * period + $0]), in: "RGB")] }.map(String.init).joined() }
            .joined(separator: "/")
    }
}
