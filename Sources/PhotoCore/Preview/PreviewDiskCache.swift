import CoreGraphics
import Foundation
import ImageIO
import os
import Synchronization

/// Rendered previews on the local disk, keyed by `PreviewCacheKey`.
///
/// Everything here can be regenerated from the masters, so the whole directory may
/// be deleted at any time (by the user, by the system under storage pressure, or
/// by `removeAll()`); callers treat a missing file as a cache miss.
public final class PreviewDiskCache: Sendable {
    public let root: URL
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "preview-cache")
    /// Renditions kept for this session only (`storeForSession`), oldest first.
    private let sessionOnly = Mutex<[(key: PreviewCacheKey, data: Data, reason: MachineLearningNoiseReduction.Reason?)]>([])
    /// Bytes of encoded renditions `sessionOnly` keeps at most.
    public let sessionOnlyLimit: Int

    public init(root: URL, sessionOnlyLimit: Int = 64 << 20) {
        self.root = root
        self.sessionOnlyLimit = sessionOnlyLimit
    }

    public func url(for key: PreviewCacheKey) -> URL {
        root.appending(path: key.relativePath, directoryHint: .notDirectory)
    }

    public func contains(_ key: PreviewCacheKey) -> Bool {
        sessionData(for: key) != nil || FileManager.default.fileExists(atPath: url(for: key).path)
    }

    /// Keeps a rendition in memory for this session instead of writing it:
    /// for a render that the same key may not give next time (a stack asking
    /// for machine learning noise reduction rendered without it, which a
    /// macOS update or a newly supported camera changes). The oldest are
    /// dropped past `sessionOnlyLimit` bytes.
    /// `reason` is why the rendition lacks machine learning noise
    /// reduction: the loupe shows that state with it (design §15, DQ-3).
    public func storeForSession(_ data: Data, for key: PreviewCacheKey,
                                reason: MachineLearningNoiseReduction.Reason? = nil) {
        let limit = sessionOnlyLimit
        sessionOnly.withLock { entries in
            entries.removeAll { $0.key == key }
            entries.append((key, data, reason))
            var total = entries.reduce(0) { $0 + $1.data.count }
            while total > limit, entries.count > 1 {
                total -= entries.removeFirst().data.count
            }
        }
    }

    private func sessionData(for key: PreviewCacheKey) -> Data? {
        sessionOnly.withLock { entries in entries.last { $0.key == key }?.data }
    }

    /// Drops the session-only rendition for `key` (its stack has since
    /// rendered with machine learning). Touches no file.
    public func removeSessionOnly(_ key: PreviewCacheKey) {
        sessionOnly.withLock { $0.removeAll { $0.key == key } }
    }

    /// Why the session-only rendition for `key` was rendered without the
    /// machine learning its stack asks for; nil when there is none.
    public func sessionOnlyReason(for key: PreviewCacheKey) -> MachineLearningNoiseReduction.Reason? {
        sessionOnly.withLock { entries in entries.last { $0.key == key }?.reason }
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
        let source = sessionData(for: key).flatMap { CGImageSourceCreateWithData($0 as CFData, options) }
            ?? CGImageSourceCreateWithURL(url(for: key) as CFURL, options)
        guard let source else { return nil }
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
    public static func converted(_ image: CGImage, to colorSpace: CGColorSpace) -> CGImage? {
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
        sessionOnly.withLock { $0.removeAll { $0.key == key } }
        try? FileManager.default.removeItem(at: url(for: key))
    }

    /// Deletes every cached rendition.
    public func removeAll() throws {
        sessionOnly.withLock { $0.removeAll() }
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for item in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)
        }
    }

    /// Brings an earlier pipeline version's renditions under the current
    /// version, for a bump that only renditions written since `cutoff` can
    /// need: those are deleted (and made again on demand), the older ones
    /// are kept, with one rename of the version's folder. Does nothing when
    /// there is no such folder or the current version already has one (the
    /// earlier one is then removed with the other obsolete versions).
    ///
    /// When a rendition written since `cutoff` cannot be deleted, the folder
    /// is not renamed (that would bring the rendition under the current
    /// version): the older ones are moved into the current version one by
    /// one instead (copied where a move is refused), and what stays behind
    /// is left to `removeObsoletePipelineVersions`. A rendition written
    /// since `cutoff` is never found under the current version, and one
    /// failure does not cost the older renditions, which for an offline
    /// master could not be made again (code review C7).
    ///
    /// Call before `removeObsoletePipelineVersions`, before anything reads
    /// or writes the cache.
    ///
    /// - Returns: How many renditions were kept and how many deleted.
    @discardableResult
    public func carryOver(fromVersion earlier: Int = PreviewCacheKey.versionCarriedOver,
                          toVersion current: Int = PreviewCacheKey.currentPipelineVersion,
                          writtenBefore cutoff: Date = PreviewCacheKey.libRawDecodingSince) -> (kept: Int, deleted: Int) {
        let manager = FileManager.default
        let from = root.appending(path: "v\(earlier)", directoryHint: .isDirectory)
        let to = root.appending(path: "v\(current)", directoryHint: .isDirectory)
        guard earlier != current, manager.fileExists(atPath: from.path), !manager.fileExists(atPath: to.path),
              let enumerator = manager.enumerator(at: from, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
        else { return (0, 0) }
        var old: [URL] = []
        var deleted = 0, undeleted = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            // A rendition whose date cannot be read is not known to be old enough.
            if let written = values.contentModificationDate, written < cutoff {
                old.append(file)
                continue
            }
            do {
                try manager.removeItem(at: file)
                deleted += 1
            } catch {
                undeleted += 1
                Self.log.error("Could not remove \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        var kept = 0
        if undeleted == 0 {
            do {
                try manager.moveItem(at: from, to: to)
                kept = old.count
            } catch {
                Self.log.error("Could not carry v\(earlier) over to v\(current): \(error.localizedDescription, privacy: .public)")
                kept = moveEach(old, from: from, to: to)
            }
        } else {
            kept = moveEach(old, from: from, to: to)
        }
        Self.log.notice("Carried \(kept) of \(old.count) renditions of pipeline version \(earlier) over to \(current); \(deleted) are made again, \(undeleted) could not be removed")
        return (kept, deleted)
    }

    /// Moves each of `files` from under `from` to the same place under
    /// `to`, copying where a move is refused (a folder that cannot be
    /// written to). Returns how many arrived.
    private func moveEach(_ files: [URL], from: URL, to: URL) -> Int {
        let manager = FileManager.default
        let prefix = from.standardizedFileURL.path + "/"
        var arrived = 0
        for file in files {
            let path = file.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            let destination = to.appending(path: String(path.dropFirst(prefix.count)), directoryHint: .notDirectory)
            do {
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                do {
                    try manager.moveItem(at: file, to: destination)
                } catch {
                    try manager.copyItem(at: file, to: destination)
                }
                arrived += 1
            } catch {
                Self.log.error("Could not carry \(file.lastPathComponent, privacy: .public) over: \(error.localizedDescription, privacy: .public)")
            }
        }
        return arrived
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
