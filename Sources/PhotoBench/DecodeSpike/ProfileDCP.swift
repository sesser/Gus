// SPIKE for issue #194 (question 3): throwaway. COPIED from the #89 spike (branch
// feature/dcp-profiles, Sources/PhotoBench/DCPSpike/SpikeDCP.swift, our own code), types renamed
// (Spike… → Profile…) so the two spikes can live in one target. Delete with the spike.

import Foundation
import PhotoCore

// SPIKE for issue #89 (R1): throwaway code, not part of the app. Delete with
// the rest of `Sources/PhotoBench/DCPSpike/` once R2's reader exists
// (docs/features/dcp-profiles/status.md says what to keep).
//
// A minimal reader of DNG camera profile files (`.dcp`), written from the
// DNG Specification 1.7.1.0 (the header, the IFD layout of TIFF, and the
// camera profile tags of chapter 4; chapter 6 for how they are used). It
// checks offsets against the file's size but is not the hardened reader R11
// asks for.

struct ProfileDCP {
    struct Entry {
        var type: UInt16
        var count: UInt32
        var bytes: Data
    }

    enum Failure: Error, CustomStringConvertible {
        case header(String)
        case bounds(String)
        var description: String {
            switch self {
            case .header(let s): "header: \(s)"
            case .bounds(let s): "bounds: \(s)"
            }
        }
    }

    var littleEndian: Bool
    var entries: [UInt16: Entry] = [:]
    var entryCount = 0
    var fileSize = 0
    /// Offset of a second IFD after the first (0 when none).
    var nextIFD: UInt32 = 0

    static func typeSize(_ type: UInt16) -> Int? {
        switch type {
        case 1, 2, 6, 7: 1
        case 3, 8: 2
        case 4, 9, 11, 13: 4
        case 5, 10, 12: 8
        default: nil
        }
    }

    init(data: Data) throws {
        fileSize = data.count
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { throw Failure.header("shorter than 8 bytes") }
        switch (bytes[0], bytes[1]) {
        case (0x49, 0x49): littleEndian = true
        case (0x4D, 0x4D): littleEndian = false
        default: throw Failure.header("byte order \(bytes[0]) \(bytes[1])")
        }
        let le = littleEndian
        func u16(_ at: Int) -> UInt16 {
            le ? UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8 : UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1])
        }
        func u32(_ at: Int) -> UInt32 {
            le ? UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
               : UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
        }
        guard u16(2) == 0x4352 else { throw Failure.header(String(format: "magic %04x", u16(2))) }
        let ifd = Int(u32(4))
        guard ifd + 2 <= bytes.count else { throw Failure.bounds("IFD offset \(ifd)") }
        let count = Int(u16(ifd))
        entryCount = count
        guard ifd + 2 + count * 12 + 4 <= bytes.count else { throw Failure.bounds("IFD of \(count) entries") }
        for index in 0..<count {
            let at = ifd + 2 + index * 12
            let tag = u16(at), type = u16(at + 2), n = u32(at + 4)
            guard let size = Self.typeSize(type) else { continue }
            let length = Int(n) * size
            let start = length <= 4 ? at + 8 : Int(u32(at + 8))
            guard length >= 0, start >= 0, start + length <= bytes.count else {
                throw Failure.bounds("tag \(tag): \(length) bytes at \(start)")
            }
            entries[tag] = Entry(type: type, count: n, bytes: Data(bytes[start..<(start + length)]))
        }
        nextIFD = u32(ifd + 2 + count * 12)
    }

    // MARK: Values

    private func u16(_ d: Data, _ i: Int) -> UInt16 {
        let b0 = UInt16(d[d.startIndex + i]), b1 = UInt16(d[d.startIndex + i + 1])
        return littleEndian ? b0 | b1 << 8 : b0 << 8 | b1
    }

    private func u32(_ d: Data, _ i: Int) -> UInt32 {
        let b = (0..<4).map { UInt32(d[d.startIndex + i + $0]) }
        return littleEndian ? b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24 : b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]
    }

    func numbers(_ tag: UInt16) -> [Double]? {
        guard let e = entries[tag] else { return nil }
        let n = Int(e.count)
        switch e.type {
        case 1, 7: return e.bytes.map { Double($0) }
        case 6: return e.bytes.map { Double(Int8(bitPattern: $0)) }
        case 3: return (0..<n).map { Double(u16(e.bytes, $0 * 2)) }
        case 8: return (0..<n).map { Double(Int16(bitPattern: u16(e.bytes, $0 * 2))) }
        case 4: return (0..<n).map { Double(u32(e.bytes, $0 * 4)) }
        case 9: return (0..<n).map { Double(Int32(bitPattern: u32(e.bytes, $0 * 4))) }
        case 11: return (0..<n).map { Double(Float(bitPattern: u32(e.bytes, $0 * 4))) }
        case 5:
            return (0..<n).map {
                let d = u32(e.bytes, $0 * 8 + 4)
                return d == 0 ? .nan : Double(u32(e.bytes, $0 * 8)) / Double(d)
            }
        case 10:
            return (0..<n).map {
                let d = Int32(bitPattern: u32(e.bytes, $0 * 8 + 4))
                return d == 0 ? .nan : Double(Int32(bitPattern: u32(e.bytes, $0 * 8))) / Double(d)
            }
        case 12:
            return (0..<n).map {
                let lo = UInt64(u32(e.bytes, $0 * 8)), hi = UInt64(u32(e.bytes, $0 * 8 + 4))
                return Double(bitPattern: littleEndian ? lo | hi << 32 : lo << 32 | hi)
            }
        default: return nil
        }
    }

    func string(_ tag: UInt16) -> String? {
        guard let e = entries[tag] else { return nil }
        let trimmed = e.bytes.prefix { $0 != 0 }
        return String(decoding: trimmed, as: UTF8.self)
    }

    func int(_ tag: UInt16) -> Int? { numbers(tag)?.first.map { Int($0) } }

    func matrix(_ tag: UInt16) -> Matrix3x3? {
        guard let v = numbers(tag), v.count == 9 else { return nil }
        return Matrix3x3(v)
    }

    // MARK: Profile tags (DNG Specification 1.7.1.0, chapter 4)

    enum Tag {
        static let uniqueCameraModel: UInt16 = 50708
        static let colorMatrix1: UInt16 = 50721, colorMatrix2: UInt16 = 50722, colorMatrix3: UInt16 = 52531
        static let illuminant1: UInt16 = 50778, illuminant2: UInt16 = 50779, illuminant3: UInt16 = 52529
        static let forwardMatrix1: UInt16 = 50964, forwardMatrix2: UInt16 = 50965, forwardMatrix3: UInt16 = 52532
        static let reductionMatrix1: UInt16 = 50725, reductionMatrix2: UInt16 = 50726
        static let profileCalibrationSignature: UInt16 = 50932
        static let profileName: UInt16 = 50936
        static let hueSatDims: UInt16 = 50937, hueSat1: UInt16 = 50938, hueSat2: UInt16 = 50939, hueSat3: UInt16 = 52537
        static let toneCurve: UInt16 = 50940
        static let embedPolicy: UInt16 = 50941
        static let copyright: UInt16 = 50942
        static let lookDims: UInt16 = 50981, lookData: UInt16 = 50982
        static let hueSatEncoding: UInt16 = 51107, lookEncoding: UInt16 = 51108
        static let baselineExposureOffset: UInt16 = 51109
        static let defaultBlackRender: UInt16 = 51110
        static let gainTableMap: UInt16 = 52525, gainTableMap2: UInt16 = 52544
        static let rgbTables: UInt16 = 52543
        static let illuminantData1: UInt16 = 52533, illuminantData2: UInt16 = 52534, illuminantData3: UInt16 = 52535
        static let dynamicRange: UInt16 = 52551
        static let groupName: UInt16 = 52552
    }

    static let tagNames: [UInt16: String] = [
        50708: "UniqueCameraModel", 50721: "ColorMatrix1", 50722: "ColorMatrix2", 52531: "ColorMatrix3",
        50778: "CalibrationIlluminant1", 50779: "CalibrationIlluminant2", 52529: "CalibrationIlluminant3",
        50964: "ForwardMatrix1", 50965: "ForwardMatrix2", 52532: "ForwardMatrix3",
        50725: "ReductionMatrix1", 50726: "ReductionMatrix2", 52538: "ReductionMatrix3",
        50932: "ProfileCalibrationSignature", 50936: "ProfileName", 50937: "ProfileHueSatMapDims",
        50938: "ProfileHueSatMapData1", 50939: "ProfileHueSatMapData2", 52537: "ProfileHueSatMapData3",
        50940: "ProfileToneCurve", 50941: "ProfileEmbedPolicy", 50942: "ProfileCopyright",
        50981: "ProfileLookTableDims", 50982: "ProfileLookTableData", 51107: "ProfileHueSatMapEncoding",
        51108: "ProfileLookTableEncoding", 51109: "BaselineExposureOffset", 51110: "DefaultBlackRender",
        52525: "ProfileGainTableMap", 52544: "ProfileGainTableMap2", 52543: "RGBTables",
        52533: "IlluminantData1", 52534: "IlluminantData2", 52535: "IlluminantData3",
        52551: "ProfileDynamicRange", 52552: "ProfileGroupName",
    ]

    var name: String? { string(Tag.profileName) }
    var camera: String? { string(Tag.uniqueCameraModel) }
    var embedPolicy: Int { int(Tag.embedPolicy) ?? 0 }
    var illuminants: [Int] {
        [Tag.illuminant1, Tag.illuminant2, Tag.illuminant3].compactMap { int($0) }
    }

    /// Hue, saturation and value divisions.
    func dims(_ tag: UInt16) -> (Int, Int, Int)? {
        guard let v = numbers(tag), v.count == 3 else { return nil }
        return (Int(v[0]), Int(v[1]), Int(v[2]))
    }

    func table(dims dimsTag: UInt16, data dataTag: UInt16, encoding encodingTag: UInt16) -> ProfileHSVTable? {
        guard let d = dims(dimsTag), let data = numbers(dataTag), data.count == d.0 * d.1 * d.2 * 3 else { return nil }
        return ProfileHSVTable(hue: d.0, sat: d.1, val: d.2, data: data.map(Float.init),
                             sRGBEncoded: (int(encodingTag) ?? 0) == 1)
    }

    var hueSatMaps: [ProfileHSVTable] {
        [Tag.hueSat1, Tag.hueSat2].compactMap { table(dims: Tag.hueSatDims, data: $0, encoding: Tag.hueSatEncoding) }
    }

    var lookTable: ProfileHSVTable? { table(dims: Tag.lookDims, data: Tag.lookData, encoding: Tag.lookEncoding) }

    var toneCurve: [(Double, Double)]? {
        guard let v = numbers(Tag.toneCurve), v.count >= 4, v.count % 2 == 0 else { return nil }
        return stride(from: 0, to: v.count, by: 2).map { (v[$0], v[$0 + 1]) }
    }

    var baselineExposureOffset: Double { numbers(Tag.baselineExposureOffset)?.first ?? 0 }
    var defaultBlackRender: Int { int(Tag.defaultBlackRender) ?? 0 }

    /// Version, dynamic range, hint (`ProfileDynamicRange`: SHORT, SHORT, FLOAT in the file's byte order).
    var dynamicRange: (version: Int, range: Int, hint: Float)? {
        guard let e = entries[Tag.dynamicRange], e.bytes.count == 8 else { return nil }
        return (Int(u16(e.bytes, 0)), Int(u16(e.bytes, 2)), Float(bitPattern: u32(e.bytes, 4)))
    }

    /// The profile's calibrations as PhotoCore's `CameraProfile` takes them
    /// (matrices and illuminants; the maps go separately).
    var calibrations: [CameraProfile.Calibration] {
        let pairs: [(UInt16, UInt16, UInt16)] = [(Tag.illuminant1, Tag.colorMatrix1, Tag.forwardMatrix1),
                                                 (Tag.illuminant2, Tag.colorMatrix2, Tag.forwardMatrix2)]
        return pairs.compactMap { light, color, forward in
            guard let code = int(light), let kelvin = CameraProfile.kelvin(ofLightSource: code),
                  let matrix = matrix(color) else { return nil }
            return CameraProfile.Calibration(illuminant: kelvin, colorMatrix: matrix, forwardMatrix: self.matrix(forward))
        }
    }
}

/// A hue, saturation and value table as a DNG stores it (value, then hue,
/// then saturation, three floats a cell).
struct ProfileHSVTable {
    var hue: Int
    var sat: Int
    var val: Int
    var data: [Float]
    var sRGBEncoded: Bool

    /// The two tables of a profile read between their lights with `weight` of the first.
    static func blend(_ a: ProfileHSVTable, _ b: ProfileHSVTable, weight: Double) -> ProfileHSVTable {
        var out = a
        let w = Float(weight)
        for i in 0..<a.data.count { out.data[i] = w * a.data[i] + (1 - w) * b.data[i] }
        return out
    }
}
