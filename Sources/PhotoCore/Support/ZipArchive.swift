import Compression
import Foundation

/// A zip archive read from memory: its central directory, and members
/// decompressed on demand (stored, or deflated through Apple's Compression
/// framework) and checked against their CRC-32. Nothing is written to disk.
///
/// Only what preset packs need: one disk, no ZIP64, no encryption. Members
/// that use anything else are refused when read, not when listed.
public struct ZipArchive: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// Not a zip archive at all.
        case notAZip
        /// A zip archive that is cut short or whose structure is broken, or a
        /// member whose data does not match its checksum.
        case damaged
        /// Over `maximumMemberSize`, `maximumEntryCount`, or ZIP64.
        case tooLarge
        /// Encrypted, or compressed with a method other than stored or deflate.
        case unsupported
    }

    public struct Entry: Sendable, Hashable {
        /// The path as stored, with `/` separators.
        public var path: String
        public var compressedSize: Int
        public var uncompressedSize: Int
        var method: UInt16
        var flags: UInt16
        var crc32: UInt32
        var localHeaderOffset: Int

        public var isDirectory: Bool { path.hasSuffix("/") }
    }

    /// Members larger than this, uncompressed, are refused (look-up tables are about 1 MB).
    public static let maximumMemberSize = 64 * 1024 * 1024
    /// Archives with more members than this are refused.
    public static let maximumEntryCount = 10_000

    public let entries: [Entry]
    private let data: Data

    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    private static let centralHeaderSignature: UInt32 = 0x0201_4B50
    private static let endSignature: UInt32 = 0x0605_4B50
    /// The end record is 22 bytes, followed by a comment of at most 65535.
    private static let endRecordSize = 22

    public init(data: Data) throws {
        // A Data slice's indices need not start at 0.
        let data = Data(data)
        self.data = data
        guard let end = Self.endRecordOffset(in: data) else {
            throw data.count >= 4 && Self.uint32(data, at: 0) == Self.localHeaderSignature
                ? Failure.damaged : Failure.notAZip
        }
        let disk = Self.uint16(data, at: end + 4), directoryDisk = Self.uint16(data, at: end + 6)
        let count = Int(Self.uint16(data, at: end + 10))
        let directorySize = Int(Self.uint32(data, at: end + 12))
        let directoryOffset = Int(Self.uint32(data, at: end + 16))
        if count == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            throw Failure.tooLarge
        }
        guard disk == 0, directoryDisk == 0, directoryOffset + directorySize <= end else { throw Failure.damaged }
        guard count <= Self.maximumEntryCount else { throw Failure.tooLarge }

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var offset = directoryOffset
        for _ in 0..<count {
            guard offset + 46 <= end, Self.uint32(data, at: offset) == Self.centralHeaderSignature else {
                throw Failure.damaged
            }
            let nameLength = Int(Self.uint16(data, at: offset + 28))
            let extraLength = Int(Self.uint16(data, at: offset + 30))
            let commentLength = Int(Self.uint16(data, at: offset + 32))
            let nameStart = offset + 46
            guard nameStart + nameLength <= end else { throw Failure.damaged }
            let compressedSize = Self.uint32(data, at: offset + 20)
            let uncompressedSize = Self.uint32(data, at: offset + 24)
            let localOffset = Self.uint32(data, at: offset + 42)
            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                throw Failure.tooLarge
            }
            let name = String(decoding: data[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            entries.append(Entry(path: name, compressedSize: Int(compressedSize),
                                 uncompressedSize: Int(uncompressedSize),
                                 method: Self.uint16(data, at: offset + 10), flags: Self.uint16(data, at: offset + 8),
                                 crc32: Self.uint32(data, at: offset + 16), localHeaderOffset: Int(localOffset)))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    /// The member's contents, decompressed and checked.
    public func contents(of entry: Entry) throws -> Data {
        guard entry.flags & 0x1 == 0 else { throw Failure.unsupported }
        guard entry.uncompressedSize <= Self.maximumMemberSize else { throw Failure.tooLarge }
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, Self.uint32(data, at: header) == Self.localHeaderSignature else {
            throw Failure.damaged
        }
        let start = header + 30 + Int(Self.uint16(data, at: header + 26)) + Int(Self.uint16(data, at: header + 28))
        guard start + entry.compressedSize <= data.count else { throw Failure.damaged }
        let stored = data[start..<(start + entry.compressedSize)]
        let contents: Data
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.uncompressedSize else { throw Failure.damaged }
            contents = Data(stored)
        case 8:
            contents = try Self.inflate(stored, size: entry.uncompressedSize)
        default:
            throw Failure.unsupported
        }
        guard CRC32.checksum(contents) == entry.crc32 else { throw Failure.damaged }
        return contents
    }

    /// Raw deflate (RFC 1951), which the Compression framework calls ZLIB.
    private static func inflate(_ input: Data, size: Int) throws -> Data {
        if size == 0 { return Data() }
        guard !input.isEmpty else { throw Failure.damaged }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let destination = out.bindMemory(to: UInt8.self).baseAddress,
                      let bytes = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destination, size, bytes, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure.damaged }
        return output
    }

    /// The offset of the end-of-central-directory record, searched from the end.
    private static func endRecordOffset(in data: Data) -> Int? {
        guard data.count >= endRecordSize else { return nil }
        let lowest = max(0, data.count - endRecordSize - 0xFFFF)
        var offset = data.count - endRecordSize
        while offset >= lowest {
            if uint32(data, at: offset) == endSignature {
                let commentLength = Int(uint16(data, at: offset + 20))
                if offset + endRecordSize + commentLength <= data.count { return offset }
            }
            offset -= 1
        }
        return nil
    }

    private static func uint16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}

/// CRC-32 as zip uses it (IEEE 802.3, reflected, polynomial 0xEDB88320).
enum CRC32 {
    private static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
            }
            table[index] = value
        }
        return table
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
