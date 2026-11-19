import Foundation

/// DNG opcode lists for synthetic files (DNG specification 1.3 and later,
/// chapter 7 "Opcode List Processing"): big-endian, a count, then each
/// opcode's identifier, the DNG version it was written for, its flags, the
/// length of its parameters and the parameters.
public enum DNGOpcodes {
    /// One opcode of a list.
    public struct Opcode: Sendable {
        public var identifier: UInt32
        public var parameters: Data
        /// Bit 0: a reader that does not know the opcode may skip it.
        public var flags: UInt32

        public init(identifier: UInt32, parameters: Data, flags: UInt32 = 0) {
            self.identifier = identifier
            self.parameters = parameters
            self.flags = flags
        }

        /// WarpRectilinear (1): per plane `kr0 … kr3, kt0, kt1`, then the
        /// optical center as fractions of the image's width and height.
        public static func warpRectilinear(planes: [[Double]], center: (x: Double, y: Double) = (0.5, 0.5),
                                           flags: UInt32 = 0) -> Opcode {
            var data = Data()
            data.appendBigEndian(UInt32(planes.count))
            for plane in planes {
                for index in 0..<6 { data.appendBigEndian(index < plane.count ? plane[index] : 0) }
            }
            data.appendBigEndian(center.x)
            data.appendBigEndian(center.y)
            return Opcode(identifier: 1, parameters: data, flags: flags)
        }

        /// FixVignetteRadial (3): gain `1 + k0 r² + k1 r⁴ + k2 r⁶ + k3 r⁸ + k4 r¹⁰`,
        /// then the optical center as fractions of the image's width and height.
        public static func fixVignetteRadial(_ k: [Double], center: (x: Double, y: Double) = (0.5, 0.5),
                                             flags: UInt32 = 0) -> Opcode {
            var data = Data()
            for index in 0..<5 { data.appendBigEndian(index < k.count ? k[index] : 0) }
            data.appendBigEndian(center.x)
            data.appendBigEndian(center.y)
            return Opcode(identifier: 3, parameters: data, flags: flags)
        }
    }

    /// The list's bytes.
    public static func list(_ opcodes: [Opcode]) -> Data {
        var data = Data()
        data.appendBigEndian(UInt32(opcodes.count))
        for opcode in opcodes {
            data.appendBigEndian(opcode.identifier)
            data.appendBigEndian(UInt32(0x0103_0000))
            data.appendBigEndian(opcode.flags)
            data.appendBigEndian(UInt32(opcode.parameters.count))
            data.append(opcode.parameters)
        }
        return data
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: Double) {
        appendBigEndian64(value.bitPattern)
    }

    mutating func appendBigEndian64(_ value: UInt64) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
