import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// What a photo's file says about correcting its lens (issue #87): whether
/// something else already corrects it, or which tables Auto can use. Read
/// when the photo is decoded (`PreviewGenerator.decode` puts it in
/// `RenderContext.lens`) and when the editor opens it, by the same rules, so
/// the Adjust tab's captions and every render agree (status.md, Q1 to Q3).
public enum CameraLensState: Hashable, Sendable {
    /// Not a raw: the camera made the picture and corrected it if it does.
    case notRaw
    /// The system's RAW decoder applies its own lens correction to this raw
    /// (`CIRAWFilter.isLensCorrectionSupported` and `isLensCorrectionEnabled`).
    case decoderCorrects
    /// A Fujifilm raw LibRaw decodes, corrected with the camera's own tables
    /// on the way (`EmbeddedLensCorrection`).
    case builtInCorrection
    /// The tables Auto can use; either may be missing (`CameraLensTables.none`: no table).
    case tables(CameraLensTables)
    /// The file has a table, but it is damaged, not understood, or not for
    /// this frame.
    case unreadable

    /// Auto may apply here: a raw nothing else corrects.
    public var autoCanApply: Bool {
        if case .tables = self { return true }
        if case .unreadable = self { return true }
        return false
    }

    /// The tables for Auto, nil where Auto does not apply.
    public var tables: CameraLensTables? {
        if case .tables(let tables) = self { return tables }
        return nil
    }
}

/// The lens tables of one file that Auto applies, green only (design L15).
public struct CameraLensTables: Hashable, Sendable {
    public enum Origin: String, Sendable {
        case fujifilm, dng
    }

    public var origin: Origin?
    /// The distortion correction (its `fills` is set by the group's
    /// Constrain to image when it applies).
    public var distortion: LensWarp?
    public var vignetting: LensGain?

    public init(origin: Origin? = nil, distortion: LensWarp? = nil, vignetting: LensGain? = nil) {
        self.origin = origin
        self.distortion = distortion
        self.vignetting = vignetting
    }

    /// No table.
    public static let none = CameraLensTables()
}

extension CameraLensState {
    /// The state of `url` read on its own, with one look at the file by the
    /// system decoder (which decoder reads it, and whether it corrects the
    /// lens), set up as for an untouched photo: what a paste or preset asks
    /// of photos that are not open (code review C2).
    public static func read(_ url: URL) -> CameraLensState {
        guard SupportedFormats.isRaw(pathExtension: url.pathExtension) else { return .notRaw }
        if let raw = CIRAWFilter(imageURL: url), SystemRAWDecoder.givesImageUntouched(raw) {
            return read(url, systemDecodes: true, decoderCorrects: raw.isLensCorrectionSupported && raw.isLensCorrectionEnabled)
        }
        return read(url, systemDecodes: false, decoderCorrects: false)
    }

    /// The state of `url` as it decodes: `systemDecodes` when the system's
    /// RAW decoder reads it (`SystemRAWDecoder.reads`), `decoderCorrects`
    /// read from the filter that decodes it.
    public static func read(_ url: URL, systemDecodes: Bool, decoderCorrects: Bool) -> CameraLensState {
        let state = readFile(url, systemDecodes: systemDecodes, decoderCorrects: decoderCorrects)
        if LensCorrectionDebug.fault == .tableCorrupt, state.autoCanApply { return .unreadable }
        return state
    }

    private static func readFile(_ url: URL, systemDecodes: Bool, decoderCorrects: Bool) -> CameraLensState {
        guard SupportedFormats.isRaw(pathExtension: url.pathExtension) else { return .notRaw }
        if systemDecodes {
            if decoderCorrects { return .decoderCorrects }
            switch url.pathExtension.lowercased() {
            case "raf": return fujifilm(FujifilmRAF(contentsOf: url))
            case "dng": return DNGLensOpcodes.read(url)
            default: return .tables(.none)
            }
        }
        // LibRaw: a Fujifilm raw whose tables it applies itself, as
        // `LibRawDecoder.lensTables` decides (its frame is the camera's).
        guard url.pathExtension.lowercased() == "raf", let raf = FujifilmRAF(contentsOf: url) else { return .tables(.none) }
        if raf.lensTablesDamaged { return .unreadable }
        guard let lens = raf.lens, !lens.isIdentity, let frame = raf.cameraFrame else { return .tables(.none) }
        return raf.lensTables(for: frame).tables != nil ? .builtInCorrection : .unreadable
    }

    /// A RAF's tables for its camera frame, green only: a table that
    /// corrects nothing counts as none (Fujifilm writes zeros for a lens it
    /// has no table for).
    static func fujifilm(_ raf: FujifilmRAF?) -> CameraLensState {
        guard let raf else { return .tables(.none) }
        if raf.lensTablesDamaged { return .unreadable }
        guard raf.lens != nil else { return .tables(.none) }
        let frame = raf.cameraFrame ?? FujifilmRAF.PixelRect(left: 0, top: 0, width: raf.fullWidth, height: raf.fullHeight)
        let usable = raf.lensTables(for: frame)
        guard let tables = usable.tables else { return usable.refusal == nil ? .tables(.none) : .unreadable }
        let warp = tables.distortion.allSatisfy { $0 == 0 } ? nil
            : LensWarp(radial: .fujifilm(knots: tables.knots, distortion: tables.distortion), fills: true)
        let gain = tables.vignetting.allSatisfy { $0 == 100 } ? nil
            : LensGain(model: .fujifilm(knots: tables.knots, vignetting: tables.vignetting))
        return .tables(CameraLensTables(origin: warp == nil && gain == nil ? nil : .fujifilm, distortion: warp, vignetting: gain))
    }
}

/// A DNG's lens opcodes (DNG specification 1.3 and later, "Opcode List
/// Processing"): `WarpRectilinear` and `FixVignetteRadial` in `OpcodeList3`,
/// which the system's RAW decoder does not apply by default (status.md Q1).
/// Lists are big-endian: a count, then each opcode's identifier, the DNG
/// version it needs, its flags, the length of its parameters and those.
enum DNGLensOpcodes {
    static let warpRectilinear: UInt32 = 1
    static let fixVignetteRadial: UInt32 = 3
    /// A list longer than this is not read.
    static let maximumListLength = 1 << 20

    /// The opcodes' parameters as read: the warp of the green plane (kr0 …
    /// kr3, kt0, kt1, cx, cy) and the vignetting (k0 … k4, cx, cy). Nil for
    /// a list without either; throws for one that can't be read.
    struct Parsed: Equatable {
        var warp: [Double]?
        var vignette: [Double]?
    }

    enum ReadError: Error { case damaged }

    static func parse(_ data: Data) throws -> Parsed {
        var reader = BigEndianReader(data: data)
        let count = try reader.uint32()
        guard count <= 256 else { throw ReadError.damaged }
        var parsed = Parsed()
        for _ in 0..<count {
            let identifier = try reader.uint32()
            _ = try reader.uint32() // DNG version
            _ = try reader.uint32() // flags
            let length = Int(try reader.uint32())
            var parameters = BigEndianReader(data: try reader.bytes(length))
            switch identifier {
            case warpRectilinear where parsed.warp == nil:
                let planes = Int(try parameters.uint32())
                guard (1...4).contains(planes), length == 4 + planes * 48 + 16 else { throw ReadError.damaged }
                var sets: [[Double]] = []
                for _ in 0..<planes { sets.append(try (0..<6).map { _ in try parameters.double() }) }
                let center = [try parameters.double(), try parameters.double()]
                // The green plane's (design L15): plane 1 of three, the one set of one.
                parsed.warp = sets[planes >= 2 ? 1 : 0] + center
            case fixVignetteRadial where parsed.vignette == nil:
                guard length == 56 else { throw ReadError.damaged }
                parsed.vignette = try (0..<7).map { _ in try parameters.double() }
            default:
                break
            }
        }
        for values in [parsed.warp, parsed.vignette].compactMap(\.self) {
            guard values.allSatisfy(\.isFinite), values.suffix(2).allSatisfy({ (0...1).contains($0) }) else {
                throw ReadError.damaged
            }
        }
        // A warp no lens has: the center's scale far from 1, or terms that fold the image.
        if let warp = parsed.warp, !(0.5...2).contains(warp[0]) || warp[1..<6].contains(where: { abs($0) > 2 }) {
            throw ReadError.damaged
        }
        if let vignette = parsed.vignette, vignette[0..<5].contains(where: { abs($0) > 16 }) {
            throw ReadError.damaged
        }
        return parsed
    }

    /// The state of a DNG the system decoder reads and does not correct.
    static func read(_ url: URL) -> CameraLensState {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .tables(.none) }
        defer { try? handle.close() }
        guard let reader = TIFFReader(handle: handle), let ifd0 = reader.entries(at: reader.firstIFDOffset) else {
            return .tables(.none)
        }
        let subIFDs = ifd0.first { $0.tag == Tag.subIFDs }.map { reader.values($0) } ?? []
        let images = [ifd0] + subIFDs.prefix(64).compactMap { reader.entries(at: $0) }
        guard let raw = images.first(where: { entries in
            (entries.first { $0.tag == Tag.newSubfileType }.flatMap { reader.values($0).first } ?? 0) == 0
        }), let list = raw.first(where: { $0.tag == Tag.opcodeList3 }) else { return .tables(.none) }
        // A value of 4 bytes or fewer is held in the entry's own field (code review C6).
        guard [1, 7].contains(list.type), list.count >= 4, Int(list.count) <= maximumListLength,
              let data = list.count <= 4 ? list.field : reader.read(Int(list.count), at: reader.valueOffset(list)),
              let parsed = try? parse(data) else { return .unreadable }
        guard parsed.warp != nil || parsed.vignette != nil else { return .tables(.none) }

        // The stage the opcodes work on is the active area, in the sensor's
        // orientation; the decoder gives its default crop, oriented.
        func first(_ tag: UInt16) -> [UInt32] { raw.first { $0.tag == tag }.map { reader.values($0) } ?? [] }
        let width = Double(first(Tag.imageWidth).first ?? 0), height = Double(first(Tag.imageLength).first ?? 0)
        let active = first(Tag.activeArea)
        let area = active.count == 4
            ? CGRect(x: 0, y: 0, width: Double(active[3]) - Double(active[1]), height: Double(active[2]) - Double(active[0]))
            : CGRect(x: 0, y: 0, width: width, height: height)
        guard area.width > 0, area.height > 0 else { return .unreadable }
        let origin = reader.numbers(raw.first { $0.tag == Tag.defaultCropOrigin })
        let size = reader.numbers(raw.first { $0.tag == Tag.defaultCropSize })
        let crop = origin.count == 2 && size.count == 2 && size[0] > 0 && size[1] > 0
            ? CGRect(x: origin[0], y: origin[1], width: size[0], height: size[1]) : area
        let orientationValue = ifd0.first { $0.tag == Tag.orientation }.flatMap { reader.values($0).first } ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        func geometry(center cx: Double, _ cy: Double) -> LensFrameGeometry {
            let center = SIMD2(cx * Double(area.width), cy * Double(area.height))
            let corners = [SIMD2(0.0, 0.0), SIMD2(Double(area.width), 0), SIMD2(0, Double(area.height)),
                           SIMD2(Double(area.width), Double(area.height))]
            let reach = corners.map { (($0 - center) * ($0 - center)).sum().squareRoot() }.max() ?? 1
            let halfDiagonal = hypot(Double(crop.width), Double(crop.height)) / 2
            let frameCenter = SIMD2(Double(crop.midX), Double(crop.midY))
            return LensFrameGeometry(centerOffset: (center - frameCenter) / halfDiagonal, radiusUnit: reach / halfDiagonal,
                                     orientation: orientation)
        }
        var tables = CameraLensTables(origin: .dng)
        if let w = parsed.warp {
            let warp = LensWarp(radial: .polynomial(Array(w[0..<4])), tangential: SIMD2(w[4], w[5]),
                                geometry: geometry(center: w[6], w[7]), fills: true)
            tables.distortion = warp.isIdentity ? nil : warp
        }
        if let v = parsed.vignette {
            let gain = LensGain(model: .polynomial(Array(v[0..<5])), geometry: geometry(center: v[5], v[6]))
            tables.vignetting = gain.isIdentity ? nil : gain
        }
        if tables.distortion == nil, tables.vignetting == nil { tables.origin = nil }
        return .tables(tables)
    }

    private enum Tag {
        static let newSubfileType: UInt16 = 254
        static let imageWidth: UInt16 = 256
        static let imageLength: UInt16 = 257
        static let orientation: UInt16 = 274
        static let subIFDs: UInt16 = 330
        static let defaultCropOrigin: UInt16 = 50719
        static let defaultCropSize: UInt16 = 50720
        static let activeArea: UInt16 = 50829
        static let opcodeList3: UInt16 = 51022
    }
}

/// Reads big-endian values from the front of a buffer.
struct BigEndianReader {
    let data: Data
    var position = 0

    init(data: Data) { self.data = data }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, position + count <= data.count else { throw DNGLensOpcodes.ReadError.damaged }
        defer { position += count }
        return data.subdata(in: (data.startIndex + position)..<(data.startIndex + position + count))
    }

    mutating func uint32() throws -> UInt32 {
        try bytes(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func double() throws -> Double {
        Double(bitPattern: try bytes(8).reduce(0) { $0 << 8 | UInt64($1) })
    }
}

extension TIFFReader {
    /// The values of a SHORT, LONG or RATIONAL entry as numbers (at most 16).
    func numbers(_ entry: Entry?) -> [Double] {
        guard let entry else { return [] }
        guard entry.type == 5 else { return values(entry).map(Double.init) }
        let count = Int(min(entry.count, 16))
        guard count > 0, let data = read(count * 8, at: valueOffset(entry)) else { return [] }
        return (0..<count).map { index in
            let denominator = integer(data, at: index * 8 + 4, as: UInt32.self)
            return denominator == 0 ? 0 : Double(integer(data, at: index * 8, as: UInt32.self)) / Double(denominator)
        }
    }
}
