import Foundation

/// Computes the content hash that identifies a master for de-duplication and
/// preview caching.
public protocol ContentHasher: Sendable {
    func contentHash(of url: URL) async throws -> String
}

/// Streaming SHA-256 of the whole file, read in fixed-size chunks with a
/// cancellation check between chunks. Holds one chunk at a time (`FileChunks`).
public struct SHA256ContentHasher: ContentHasher {
    public var chunkSize: Int

    public init(chunkSize: Int = 4 << 20) {
        self.chunkSize = chunkSize
    }

    public func contentHash(of url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try FileChunks.sha256(of: handle.fileDescriptor, chunkSize: chunkSize)
    }
}
