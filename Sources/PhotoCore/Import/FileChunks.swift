import CryptoKit
import Darwin
import Foundation

/// Reads an open file front to back through one buffer that is used again for
/// every chunk, so reading holds one chunk however large the file is.
///
/// `FileHandle.read(upToCount:)` hands back autoreleased `Data`. In a loop with
/// no autorelease pool of its own, every chunk stayed in memory at least until
/// the call returned: hashing a 2 GiB file held 2 GiB, and a verified copy
/// held twice the file (#160 C6, #164). `read(2)` into a buffer allocated once
/// creates nothing to autorelease.
enum FileChunks {
    /// Calls `body` with each chunk of the file open at `descriptor`, in order,
    /// from its current offset to its end. The buffer is valid only during the
    /// call and is overwritten by the next chunk. With `checksCancellation`, a
    /// cancelled task stops before each read with `CancellationError`.
    static func forEach(in descriptor: Int32, chunkSize: Int, checksCancellation: Bool = true,
                        _ body: (UnsafeRawBufferPointer) throws -> Void) throws {
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: max(chunkSize, 1), alignment: 16)
        defer { buffer.deallocate() }
        while true {
            if checksCancellation { try Task.checkCancellation() }
            let count = read(descriptor, buffer.baseAddress, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { return }
            try body(UnsafeRawBufferPointer(rebasing: buffer[..<count]))
        }
    }

    /// SHA-256 of the rest of the file open at `descriptor`, lowercase hex: the
    /// catalog's content hash. The digest does not depend on `chunkSize`.
    static func sha256(of descriptor: Int32, chunkSize: Int, checksCancellation: Bool = true) throws -> String {
        var hasher = SHA256()
        try forEach(in: descriptor, chunkSize: chunkSize, checksCancellation: checksCancellation) {
            hasher.update(bufferPointer: $0)
        }
        return hasher.finalize().hexString
    }

    /// Writes all of `bytes` to `descriptor` (`write(2)` may take part of them).
    static func write(_ bytes: UnsafeRawBufferPointer, to descriptor: Int32) throws {
        var offset = 0
        while offset < bytes.count {
            let written = Darwin.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
            if written < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            offset += written
        }
    }
}
