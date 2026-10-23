import Foundation
import GRDB

/// A file on a card or in a folder being imported by copying.
public struct SourceFile: Hashable, Sendable {
    public var url: URL
    public var size: Int64
    public var modifiedAt: Date
    public var kind: FileKind
    public var metadata: ImageMetadata
    /// Already in the library (same content), so it is not copied.
    public var isDuplicate = false

    public var name: String { url.lastPathComponent }
}

/// One shot: a single file, or a RAW with the JPEG or HEIC taken with it.
/// Shots are what the import window shows and selects.
public struct SourceShot: Hashable, Sendable, Identifiable {
    /// RAW first when there is one.
    public var files: [SourceFile]

    public var id: URL { files[0].url }
    public var primary: SourceFile { files[0] }
    /// Capture date, or the file date, for sorting and templates.
    public var date: Date { primary.metadata.captureDate ?? primary.modifiedAt }
    public var isDuplicate: Bool { files.allSatisfy(\.isDuplicate) }
    public var byteCount: Int64 { files.filter { !$0.isDuplicate }.map(\.size).reduce(0, +) }
}

public enum SourceScanner {
    /// Every supported file under `root`, grouped into shots in capture order,
    /// with embedded metadata read (for templates and sorting).
    public static func scan(_ root: URL, reader: any MetadataReader, includingVideos: Bool = true) async throws -> [SourceShot] {
        let scanned = try FileScanner.scan(root, includingVideos: includingVideos)
        let metadata = try await reader.metadata(for: scanned.map(\.url))
        let files = scanned.compactMap { file -> SourceFile? in
            guard let kind = FileKind(pathExtension: file.url.pathExtension) else { return nil }
            return SourceFile(url: file.url, size: file.fileSize, modifiedAt: file.modifiedAt, kind: kind,
                              metadata: metadata[file.url] ?? .empty)
        }
        return shots(from: files)
    }

    /// Groups files into shots: a RAW pairs with a JPEG (or else a HEIC) of the
    /// same name in the same folder, as in the catalog.
    static func shots(from files: [SourceFile]) -> [SourceShot] {
        let groups = Dictionary(grouping: files) { ImagePairing.key(forRelativePath: $0.url.path) }
        var shots: [SourceShot] = []
        for members in groups.values {
            var remaining = members.sorted { $0.name < $1.name }
            if let raw = remaining.firstIndex(where: { $0.kind == .raw }),
               let companion = remaining.firstIndex(where: { $0.kind == .jpeg }) ?? remaining.firstIndex(where: { $0.kind == .heic }) {
                shots.append(SourceShot(files: [remaining[raw], remaining[companion]]))
                remaining = remaining.enumerated().filter { $0.offset != raw && $0.offset != companion }.map(\.element)
            }
            shots += remaining.map { SourceShot(files: [$0]) }
        }
        return shots.sorted { ($0.date, $0.primary.name) < ($1.date, $1.primary.name) }
    }

    /// Marks files whose content is already in the library. Only a file whose
    /// size equals a master's can be a duplicate, so only those are hashed
    /// (usually a handful, not the whole card).
    public static func markDuplicates(in shots: [SourceShot], catalog: Catalog,
                                      hasher: any ContentHasher = SHA256ContentHasher()) async throws -> [SourceShot] {
        let sizes = Set(shots.flatMap(\.files).map(\.size))
        let known = try await catalog.contentHashes(forSizes: sizes)
        var result = shots
        for shotIndex in result.indices {
            for fileIndex in result[shotIndex].files.indices {
                let file = result[shotIndex].files[fileIndex]
                guard let candidates = known[file.size] else { continue }
                try Task.checkCancellation()
                let hash = try await hasher.contentHash(of: file.url)
                result[shotIndex].files[fileIndex].isDuplicate = candidates.contains(hash)
            }
        }
        return result
    }
}

extension Catalog {
    /// Content hashes of masters with each of the given sizes.
    public func contentHashes(forSizes sizes: Set<Int64>) async throws -> [Int64: Set<String>] {
        guard !sizes.isEmpty else { return [:] }
        return try await database.read { db in
            var result: [Int64: Set<String>] = [:]
            for chunk in Array(sizes).chunked(into: 10_000) {
                let rows = try Row.fetchCursor(db, sql: """
                    SELECT fileSize, contentHash FROM image WHERE fileSize IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments(Array(chunk)))
                while let row = try rows.next() { result[row[0], default: []].insert(row[1]) }
            }
            return result
        }
    }
}
