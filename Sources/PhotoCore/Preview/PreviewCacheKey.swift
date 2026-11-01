import Foundation

/// Cached rendition sizes. Raw values are persisted in cache paths.
public enum PreviewTier: String, Sendable, Hashable, CaseIterable {
    /// Grid cells.
    case thumbnail = "thumb"
    /// Loupe at fit size.
    case preview = "preview"

    /// Long edge of the cached image in pixels.
    public var longEdge: Int {
        switch self {
        case .thumbnail: 512
        case .preview: 2560
        }
    }

    /// Thumbnails may use the RAW decoder's fast draft mode.
    var allowsDraftDecode: Bool { self == .thumbnail }
}

/// Identifies one cached rendition: which master, rendered with which edit stack,
/// at which tier, by which version of the pipeline.
///
/// Files live at `v<pipeline>/<tier>/<hash[0..<2]>/<contentHash>-<editHash[0..<16]>.jpg`,
/// so all renditions of a master sit next to each other, and bumping
/// `currentPipelineVersion` orphans every old file in one folder that can be deleted.
public struct PreviewCacheKey: Hashable, Sendable, CustomStringConvertible {
    /// Bump when rendering changes in a way that should invalidate cached previews.
    public static let currentPipelineVersion = 3

    public let contentHash: String
    public let editStackHash: String
    public let tier: PreviewTier
    public let pipelineVersion: Int

    /// Returns nil unless both hashes are lowercase hex, which also keeps the
    /// derived path inside the cache directory.
    public init?(contentHash: String, editStackHash: String, tier: PreviewTier,
                 pipelineVersion: Int = PreviewCacheKey.currentPipelineVersion) {
        guard Self.isHex(contentHash), contentHash.count >= 16,
              Self.isHex(editStackHash), editStackHash.count >= 16,
              pipelineVersion > 0
        else { return nil }
        self.contentHash = contentHash
        self.editStackHash = editStackHash
        self.tier = tier
        self.pipelineVersion = pipelineVersion
    }

    public init?(item: CatalogItem, tier: PreviewTier) {
        self.init(contentHash: item.contentHash, editStackHash: item.editStackHash, tier: tier)
    }

    /// Path relative to the cache root.
    public var relativePath: String {
        "v\(pipelineVersion)/\(tier.rawValue)/\(contentHash.prefix(2))/\(contentHash)-\(editStackHash.prefix(16)).jpg"
    }

    /// Stable string for in-memory maps.
    public var description: String { relativePath }

    static func isHex(_ string: String) -> Bool {
        !string.isEmpty && string.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
