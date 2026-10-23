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
    ///
    /// With `displayColorSpace`, the pixels are also converted to that space in
    /// Core Animation's native layout (8-bit BGRA, premultiplied). Otherwise Core
    /// Animation converts each new image itself while committing, on the main
    /// thread, which is what made fast scrolling stutter.
    public func loadImage(for key: PreviewCacheKey, maxPixelSize: Int? = nil,
                          displayColorSpace: CGColorSpace? = nil) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url(for: key) as CFURL, options) else { return nil }
        let decoded: CGImage?
        if let maxPixelSize, maxPixelSize < key.tier.longEdge {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        } else {
            let decodeOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            decoded = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions)
        }
        guard let decoded, let displayColorSpace else { return decoded }
        return Self.converted(decoded, to: displayColorSpace) ?? decoded
    }

    /// Redraws `image` into a BGRA bitmap in `colorSpace`.
    static func converted(_ image: CGImage, to colorSpace: CGColorSpace) -> CGImage? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard colorSpace.model == .rgb,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
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
