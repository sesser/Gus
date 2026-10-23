import CoreGraphics
import Foundation
import ImageIO
import os

/// Rendered previews on the local disk, keyed by `PreviewCacheKey`.
///
/// Everything here can be regenerated from the masters, so the whole directory may
/// be deleted at any time (by the user, by the system under storage pressure, or
/// by `removeAll()`); callers treat a missing file as a cache miss.
public final class PreviewDiskCache: Sendable {
    public let root: URL
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "preview-cache")

    public init(root: URL) {
        self.root = root
    }

    public func url(for key: PreviewCacheKey) -> URL {
        root.appending(path: key.relativePath, directoryHint: .notDirectory)
    }

    public func contains(_ key: PreviewCacheKey) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key).path)
    }

    /// Writes atomically, so readers never see a partial file.
    public func store(_ data: Data, for key: PreviewCacheKey) throws {
        let destination = url(for: key)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    /// Decodes a cached rendition, downsampled to `maxPixelSize` if given. The
    /// image is fully decoded before returning so that drawing it never decodes on
    /// the main thread.
    public func loadImage(for key: PreviewCacheKey, maxPixelSize: Int? = nil) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url(for: key) as CFURL, options) else { return nil }
        if let maxPixelSize, maxPixelSize < key.tier.longEdge {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        }
        let decodeOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, decodeOptions)
    }

    public func remove(_ key: PreviewCacheKey) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    /// Deletes every cached rendition.
    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for item in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)
        }
    }

    /// Deletes renditions written by older pipeline versions.
    public func removeObsoletePipelineVersions(current: Int = PreviewCacheKey.currentPipelineVersion) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for name in items where name.hasPrefix("v") && name != "v\(current)" {
            do {
                try FileManager.default.removeItem(at: root.appending(path: name))
            } catch {
                Self.log.error("Could not remove \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Bytes used on disk.
    public func diskUsage() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
