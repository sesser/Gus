import CLibRaw
import Foundation

/// Memory for a decode's large buffers, page-aligned so that Metal can use
/// it in place (`makeBuffer(bytesNoCopy:)`), with no copy, and freed when
/// the last owner lets go of it.
///
/// `@unchecked Sendable`: the bytes are written once, by the thread that
/// fills them, before the storage is handed to anything else; after that
/// they are only read (by the GPU, then by Core Image).
final class PageAlignedStorage: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
    /// The bytes asked for.
    let count: Int
    /// The allocation's length, a whole number of pages.
    let allocatedCount: Int

    init?(count: Int) {
        let page = Int(getpagesize())
        let length = max(page, (count + page - 1) / page * page)
        var raw: UnsafeMutableRawPointer?
        guard posix_memalign(&raw, page, length) == 0, let raw else { return nil }
        pointer = raw
        self.count = count
        allocatedCount = length
    }

    deinit { free(pointer) }

    /// Clears the bytes past `used` in each row: rows padded for the GPU's
    /// alignment are never written there, and an image's data should not
    /// depend on what the heap held (code review C8).
    func zeroPadding(rows: Int, bytesPerRow: Int, used: Int) {
        guard bytesPerRow > used else { return }
        for row in 0..<rows { (pointer + row * bytesPerRow + used).initializeMemory(as: UInt8.self, repeating: 0, count: bytesPerRow - used) }
    }
}

/// A raw's sensor values as LibRaw unpacks them, before any of LibRaw's own
/// processing: the visible area (`sizes.width` x `sizes.height` at the
/// margins), the color filter pattern from its top left, the black level of
/// each pattern site, the white level, and the multipliers that balance the
/// channels for the camera's neutral (the same ones `LibRawDecoder` gives
/// LibRaw, so the demosaic's output has the scale of LibRaw's own).
public struct SensorMosaic: Sendable {
    public var width: Int
    public var height: Int
    public var pattern: CFAPattern
    /// Black per pattern site, in sensor units (LibRaw's common black, the
    /// site color's own and a repeating black pattern, added as LibRaw adds
    /// them).
    public var blackPerSite: [Float]
    /// The white level less the smallest black: the value that is 1 after
    /// normalizing.
    public var whiteSpan: Float
    /// What each color is multiplied by after normalizing, the largest 1.
    public var multipliers: SIMD3<Float>
    /// The values, `width` x `height` 16-bit samples, rows from the top.
    let storage: PageAlignedStorage

    /// A mosaic of given values (tests, synthetic truths).
    public init?(width: Int, height: Int, pattern: CFAPattern, values: [UInt16], blackPerSite: [Float]? = nil,
                 whiteSpan: Float = 65535, multipliers: SIMD3<Float> = SIMD3(1, 1, 1)) {
        guard width > 0, height > 0, values.count == width * height,
              let storage = PageAlignedStorage(count: values.count * 2) else { return nil }
        values.withUnsafeBytes { storage.pointer.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        self.init(width: width, height: height, pattern: pattern,
                  blackPerSite: blackPerSite ?? [Float](repeating: 0, count: pattern.period * pattern.period),
                  whiteSpan: whiteSpan, multipliers: multipliers, storage: storage)
    }

    init(width: Int, height: Int, pattern: CFAPattern, blackPerSite: [Float], whiteSpan: Float,
         multipliers: SIMD3<Float>, storage: PageAlignedStorage) {
        self.width = width
        self.height = height
        self.pattern = pattern
        self.blackPerSite = blackPerSite
        self.whiteSpan = whiteSpan
        self.multipliers = multipliers
        self.storage = storage
    }

    /// The 16-bit samples, rows from the top.
    public var values: UnsafeBufferPointer<UInt16> {
        UnsafeBufferPointer(start: storage.pointer.assumingMemoryBound(to: UInt16.self), count: width * height)
    }

    /// What each pattern site's value is multiplied by after its black is
    /// taken off and it is clipped to the white span: its color's
    /// multiplier over the span.
    public var scalePerSite: [Float] {
        pattern.colors.map { multipliers[Int($0)] / whiteSpan }
    }

    /// The mosaic normalized as the kernels read it: (value − black),
    /// clipped to 0 … span, times multiplier / span. The same operations in
    /// the same order as `normalized` in the Metal source.
    public func normalized() -> [Float] {
        let scale = scalePerSite
        let p = pattern.period
        var out = [Float](repeating: 0, count: width * height)
        let source = values
        for y in 0..<height {
            let row = (y % p) * p
            for x in 0..<width {
                let site = row + x % p
                let v = min(max(Float(source[y * width + x]) - blackPerSite[site], 0), whiteSpan)
                out[y * width + x] = v * scale[site]
            }
        }
        return out
    }

    /// A part of the mosaic, starting on any pixel (its pattern shifted).
    public func cropped(x: Int, y: Int, width w: Int, height h: Int) -> SensorMosaic? {
        guard x >= 0, y >= 0, w > 0, h > 0, x + w <= width, y + h <= height,
              let storage = PageAlignedStorage(count: w * h * 2) else { return nil }
        let target = storage.pointer.assumingMemoryBound(to: UInt16.self)
        let source = values
        for row in 0..<h {
            for column in 0..<w { target[row * w + column] = source[(y + row) * width + x + column] }
        }
        let p = pattern.period
        let black = (0..<(p * p)).map { blackPerSite[((($0 / p) + y) % p) * p + (($0 % p) + x) % p] }
        return SensorMosaic(width: w, height: h, pattern: pattern.shifted(x: x, y: y), blackPerSite: black,
                            whiteSpan: whiteSpan, multipliers: multipliers, storage: storage)
    }
}

extension SensorMosaic {
    /// Why LibRaw's unpacked data can't go to our kernels (the decode then
    /// uses LibRaw's own demosaic, R4).
    public enum Unsupported: Error, Equatable, CustomStringConvertible {
        /// Not a mosaic of three colors (a linear raw, Foveon, four colors, monochrome).
        case notAThreeColorMosaic
        /// A Fujifilm Super CCD, which LibRaw reads turned 45 degrees.
        case diagonalSensor
        /// A mosaic whose pattern is neither Bayer nor X-Trans.
        case pattern(String)
        case noSensorData
        /// The vendored LibRaw no longer lays its black levels out as read here (`blackLayoutHolds`).
        case blackLayout

        public var description: String {
            switch self {
            case .notAThreeColorMosaic: "not a mosaic of three colors"
            case .diagonalSensor: "a Super CCD sensor"
            case .pattern(let pattern): "a color filter pattern the kernels do not demosaic (\(pattern))"
            case .noSensorData: "LibRaw gave no sensor data"
            case .blackLayout: "LibRaw's black levels are not where this build reads them"
            }
        }
    }

    /// The pattern of an opened file at its visible area's origin, read
    /// from the header (nothing unpacked), or why it is not one our kernels
    /// demosaic. Checked over a 12 x 12 area: a pattern LibRaw describes
    /// with another period (some cameras' 2 x 8) is not taken for Bayer.
    static func pattern(of processor: UnsafeMutablePointer<libraw_data_t>) -> Result<CFAPattern, Unsupported> {
        let colors = processor.pointee.idata.colors, filters = processor.pointee.idata.filters
        guard colors == 3, filters > 1, processor.pointee.idata.is_foveon == 0 else { return .failure(.notAThreeColorMosaic) }
        guard processor.pointee.rawdata.ioparams.fuji_width == 0 else { return .failure(.diagonalSensor) }
        let period = filters == 9 ? 6 : 2
        var grid: [Int32] = []
        var seen = Set<Int32>()
        for row in 0..<12 {
            for column in 0..<12 {
                let c = libraw_COLOR(processor, Int32(row), Int32(column))
                // LibRaw's second green (3) is green.
                let color: Int32 = c == 3 ? 1 : c
                seen.insert(color)
                grid.append(color)
            }
        }
        let text = (0..<period).map { r in (0..<period).map { String(grid[r * 12 + $0]) }.joined() }.joined(separator: "/")
        guard seen == [0, 1, 2] else { return .failure(.pattern(text)) }
        for row in 0..<12 {
            for column in 0..<12 where grid[row * 12 + column] != grid[(row % period) * 12 + column % period] {
                return .failure(.pattern(text))
            }
        }
        let tile = (0..<(period * period)).map { grid[($0 / period) * 12 + $0 % period] }
        guard let pattern = CFAPattern(period: period, colors: tile) else { return .failure(.pattern(text)) }
        return .success(pattern)
    }

    /// `cblack` (LibRaw's `unsigned cblack[LIBRAW_CBLACK_SIZE]`) is too large
    /// a C array for Swift to import, so it is read at its offset: right after
    /// `ushort curve[0x10000]`, the first member, and right before `black`.
    /// True while the vendored header lays `libraw_colordata_t` out that way
    /// (code review C7); a LibRaw that changes it makes every decode LibRaw's
    /// own (`Unsupported.blackLayout`) instead of reading wrong blacks.
    static let blackLayoutHolds: Bool = {
        // `curve` is not imported either (65,536 values); its size and `cblack`'s put `black` here, and
        // `data_maximum` follows it.
        let black = MemoryLayout<libraw_colordata_t>.offset(of: \.black)
        let next = MemoryLayout<libraw_colordata_t>.offset(of: \.data_maximum)
        return black == 0x10000 * MemoryLayout<UInt16>.size + Int(LIBRAW_CBLACK_SIZE) * MemoryLayout<UInt32>.size
            && next == black.map { $0 + MemoryLayout<UInt32>.size }
    }()

    /// The visible area of an unpacked file, copied out of LibRaw's buffer,
    /// with its pattern, levels and `multipliers`.
    static func unpacked(_ processor: UnsafeMutablePointer<libraw_data_t>, pattern: CFAPattern,
                         multipliers: SIMD3<Double>) throws -> SensorMosaic {
        guard blackLayoutHolds else { throw Unsupported.blackLayout }
        guard let raw = processor.pointee.rawdata.raw_image else { throw Unsupported.noSensorData }
        let sizes = processor.pointee.sizes
        let width = Int(sizes.width), height = Int(sizes.height)
        let pitch = Int(sizes.raw_pitch) / 2
        let left = Int(sizes.left_margin), top = Int(sizes.top_margin)
        guard width > 0, height > 0, left + width <= pitch, top + height <= Int(sizes.raw_height),
              let storage = PageAlignedStorage(count: width * height * 2) else { throw Unsupported.noSensorData }
        let target = storage.pointer.assumingMemoryBound(to: UInt16.self)
        for row in 0..<height {
            (target + row * width).update(from: raw + (row + top) * pitch + left, count: width)
        }
        // Black: LibRaw's common black, each color's own (cblack[0…3]) and a
        // repeating pattern (cblack[4] rows by cblack[5] columns from cblack[6]),
        // summed as LibRaw sums them. `cblack` (4104 values) is too large a C
        // array for Swift to import; it sits just before `black`.
        let blackOffset = MemoryLayout<libraw_data_t>.offset(of: \.color)! + MemoryLayout<libraw_colordata_t>.offset(of: \.black)!
        let cblack = UnsafeRawPointer(processor).advanced(by: blackOffset - Int(LIBRAW_CBLACK_SIZE) * 4)
            .assumingMemoryBound(to: UInt32.self)
        let p = pattern.period
        let blackRows = Int(cblack[4]), blackColumns = Int(cblack[5])
        // A black pattern that does not repeat with the color pattern can't be given per site.
        if blackRows > 0, blackColumns > 0, p % blackRows != 0 || p % blackColumns != 0 {
            throw Unsupported.pattern("black levels repeat every \(blackRows) x \(blackColumns) sites")
        }
        var sites: [Float] = []
        for row in 0..<p {
            for column in 0..<p {
                // The color index LibRaw keeps blacks by: its second green is 3.
                let index = Int(libraw_COLOR(processor, Int32(row), Int32(column)))
                var black = Double(processor.pointee.color.black) + Double(cblack[index])
                let rows = Int(cblack[4]), columns = Int(cblack[5])
                if rows > 0, columns > 0, 6 + rows * columns <= Int(LIBRAW_CBLACK_SIZE) {
                    black += Double(cblack[6 + (row % rows) * columns + column % columns])
                }
                sites.append(Float(black))
            }
        }
        // LibRaw takes the smallest black into its common one and off its maximum.
        let common = Float(Int(sites.min() ?? 0))
        let span = Float(processor.pointee.color.maximum) - common
        guard span > 0 else { throw Unsupported.noSensorData }
        return SensorMosaic(width: width, height: height, pattern: pattern, blackPerSite: sites, whiteSpan: span,
                            multipliers: SIMD3<Float>(multipliers), storage: storage)
    }
}
