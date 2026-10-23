import CryptoKit
import Foundation

public enum Digest {
    /// Lowercase hex SHA-256 of `data`.
    public static func sha256Hex(_ data: some DataProtocol) -> String {
        SHA256.hash(data: data).hexString
    }

    public static func sha256Hex(_ string: String) -> String {
        sha256Hex(Data(string.utf8))
    }
}

extension SHA256Digest {
    var hexString: String {
        var result = ""
        result.reserveCapacity(Self.byteCount * 2)
        let digits = Array("0123456789abcdef".utf8)
        for byte in self {
            result.unicodeScalars.append(Unicode.Scalar(digits[Int(byte >> 4)]))
            result.unicodeScalars.append(Unicode.Scalar(digits[Int(byte & 0x0F)]))
        }
        return result
    }
}
