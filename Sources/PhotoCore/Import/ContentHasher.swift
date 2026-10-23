import CryptoKit
import Foundation

/// Computes the content hash that identifies a master for de-duplication and
/// preview caching.
public protocol ContentHasher: Sendable {
    func contentHash(of url: URL) async throws -> String
}

/// Streaming SHA-256 of the whole file, read in fixed-size chunks with a
/// cancellation check between chunks.
public struct SHA256ContentHasher: ContentHasher {
    public var chunkSize: Int

    public init(chunkSize: Int = 4 << 20) {
        self.chunkSize = chunkSize
    }

    public func contentHash(of url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().hexString
    }
}
