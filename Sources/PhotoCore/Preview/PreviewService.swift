import CoreGraphics
import Foundation
import Synchronization
import os

/// `CGImage` is immutable and thread-safe; this box makes that explicit for
/// crossing concurrency domains.
public struct DecodedImage: @unchecked Sendable {
    public let cgImage: CGImage
    public var byteCount: Int { cgImage.bytesPerRow * cgImage.height }
}

/// What the preview pipeline needs to know about one version.
public struct PreviewRequest: Hashable, Sendable {
    public var versionID: Int64
    public var key: PreviewCacheKey
    /// Location of the master, or nil when its volume is offline. Cached
    /// renditions are still served without it.
    public var sourceURL: URL?

    public init(versionID: Int64, key: PreviewCacheKey, sourceURL: URL?) {
        self.versionID = versionID
        self.key = key
        self.sourceURL = sourceURL
    }
}

/// Serves rendered previews: memory cache, then disk cache, then generation from
/// the master.
///
/// Loading cached files and generating new ones run in separate lanes with their
/// own concurrency limits, so scrolling over already-cached thumbnails never waits
/// behind slow RAW decodes. All decoding happens off the main thread; returned
/// images are fully decoded.
public final class PreviewService: Sendable {
    public enum Priority: Int, Sendable, Comparable {
        /// Warming the cache after an import.
        case background = 0
        /// Just outside the visible area, or loupe neighbors.
        case prefetch = 1
        /// On screen now.
        case visible = 2

        public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

        var taskPriority: TaskPriority {
            switch self {
            // Background QoS is throttled hard on macOS; utility still yields to the UI.
            case .background: .utility
            case .prefetch: .utility
            case .visible: .userInitiated
            }
        }
    }

    public enum Failure: Error, Equatable {
        /// Not cached, and the master's volume is offline.
        case sourceUnavailable
        case decodeFailed
    }

    public let cache: PreviewDiskCache
    public let generator: PreviewGenerator
    private let editStack: @Sendable (Int64) async throws -> EditStack
    private let memory: MemoryCache
    private let display = DisplayColorSpace()
    private let loadLane: WorkLane<DecodedImage>
    private let generateLane: WorkLane<Bool>
    private let fullLane: WorkLane<DecodedImage>
    private let hdrLane: WorkLane<DecodedImage?>
    /// HDR requests whose master turned out to have no HDR content.
    private let standardRange = Mutex<Set<String>>([])
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "previews")

    /// - Parameters:
    ///   - editStack: Loads a version's edit stack when a rendition has to be generated.
    ///   - memoryLimit: Bytes of decoded images kept in memory.
    public init(cache: PreviewDiskCache, generator: PreviewGenerator = PreviewGenerator(),
                editStack: @escaping @Sendable (Int64) async throws -> EditStack,
                memoryLimit: Int = 512 << 20, loadConcurrency: Int = 6,
                generateConcurrency: Int = PreviewService.defaultGenerateConcurrency) {
        self.cache = cache
        self.generator = generator
        self.editStack = editStack
        self.memory = MemoryCache(limit: memoryLimit)
        self.loadLane = WorkLane(concurrency: loadConcurrency)
        self.generateLane = WorkLane(concurrency: generateConcurrency)
        self.fullLane = WorkLane(concurrency: 1)
        self.hdrLane = WorkLane(concurrency: 2)
    }

    /// Rendering scales with cores up to about eight jobs (RAW decodes measured on
    /// Apple silicon); beyond that jobs mostly wait on each other.
    public static var defaultGenerateConcurrency: Int {
        min(8, max(4, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    /// Convenience for a catalog-backed service.
    public convenience init(cacheDirectory: URL, catalog: Catalog, generator: PreviewGenerator = PreviewGenerator(),
                            memoryLimit: Int = 512 << 20) {
        self.init(cache: PreviewDiskCache(root: cacheDirectory), generator: generator, editStack: { versionID in
            try await catalog.version(id: versionID)?.decodedEditStack() ?? .identity
        }, memoryLimit: memoryLimit)
    }

    /// Color space of the screen showing the images. Decoded images are converted
    /// to it off the main thread; changing it empties the memory cache.
    public var displayColorSpace: CGColorSpace? {
        get { display.value }
        set {
            if display.exchange(newValue) { memory.removeAll() }
        }
    }

    /// Thumbnail decode sizes. Decoding at the cell's size keeps memory small.
    static func bucket(for maxPixelSize: Int?, tier: PreviewTier) -> Int {
        guard let maxPixelSize else { return tier.longEdge }
        for size in [128, 256, 384, 512, 1024, 2048] where maxPixelSize <= size {
            return min(size, tier.longEdge)
        }
        return tier.longEdge
    }

    /// An already-decoded image, if one is in memory. Never does I/O; meant for
    /// configuring a cell synchronously.
    public func memoryCachedImage(for request: PreviewRequest, maxPixelSize: Int? = nil) -> CGImage? {
        memory.image(forKey: Self.memoryKey(request.key, bucket: Self.bucket(for: maxPixelSize, tier: request.key.tier)))
    }

    /// The rendition for `request`, generating it if needed.
    public func image(for request: PreviewRequest, maxPixelSize: Int? = nil,
                      priority: Priority = .visible) async throws -> CGImage {
        let bucket = Self.bucket(for: maxPixelSize, tier: request.key.tier)
        let memoryKey = Self.memoryKey(request.key, bucket: bucket)
        if let image = memory.image(forKey: memoryKey) { return image }
        if !cache.contains(request.key) {
            try await prepare(request, priority: priority)
        }
        let cache = self.cache
        let key = request.key
        let colorSpace = display.value
        let decoded = try await loadLane.run(key: memoryKey, priority: priority.rawValue,
                                             taskPriority: priority.taskPriority) {
            guard let image = cache.loadImage(for: key, maxPixelSize: bucket, displayColorSpace: colorSpace) else {
                throw Failure.decodeFailed
            }
            return DecodedImage(cgImage: image)
        }
        memory.insert(decoded, forKey: memoryKey)
        return decoded.cgImage
    }

    /// Makes sure the rendition exists on disk, without decoding it for display.
    /// Generating the loupe tier also writes the grid thumbnail from the same decode.
    public func prepare(_ request: PreviewRequest, priority: Priority = .background) async throws {
        if cache.contains(request.key) { return }
        guard let source = request.sourceURL else { throw Failure.sourceUnavailable }
        let cache = self.cache
        let generator = self.generator
        let loadStack = self.editStack
        let key = request.key
        let versionID = request.versionID
        _ = try await generateLane.run(key: key.relativePath, priority: priority.rawValue,
                                       taskPriority: priority.taskPriority) {
            if cache.contains(key) { return true }
            let stack = try await loadStack(versionID)
            try Task.checkCancellation()
            var keys = [key.tier: key]
            if key.tier == .preview,
               let thumbnail = PreviewCacheKey(contentHash: key.contentHash, editStackHash: key.editStackHash,
                                               tier: .thumbnail, pipelineVersion: key.pipelineVersion),
               !cache.contains(thumbnail) {
                keys[.thumbnail] = thumbnail
            }
            let tiers = Set(keys.keys)
            let encoded: [PreviewTier: Data]
            if FileKind(pathExtension: source.pathExtension) == .video {
                let poster = try await VideoFrames.poster(of: source, longEdge: tiers.map(\.longEdge).max())
                encoded = try generator.jpegData(decoded: poster, stack: stack, tiers: tiers)
            } else {
                encoded = try generator.jpegData(source: source, stack: stack, tiers: tiers)
            }
            for (tier, data) in encoded {
                if let tierKey = keys[tier] { try cache.store(data, for: tierKey) }
            }
            return true
        }
    }

    /// Renders the master at full resolution for 1:1 viewing. Not cached on disk;
    /// only the most recent result is kept in memory.
    public func fullResolutionImage(for request: PreviewRequest) async throws -> CGImage {
        let memoryKey = Self.memoryKey(request.key, bucket: 0) + "#full"
        if let image = memory.image(forKey: memoryKey) { return image }
        guard let source = request.sourceURL else { throw Failure.sourceUnavailable }
        let generator = self.generator
        let loadStack = self.editStack
        let versionID = request.versionID
        let colorSpace = display.value
        let decoded = try await fullLane.run(key: memoryKey, priority: Priority.visible.rawValue,
                                             taskPriority: .userInitiated) {
            let stack = try await loadStack(versionID)
            try Task.checkCancellation()
            if FileKind(pathExtension: source.pathExtension) == .video {
                return DecodedImage(cgImage: try await VideoFrames.poster(of: source, longEdge: nil))
            }
            let image = try generator.cgImage(source: source, stack: stack, colorSpace: colorSpace)
            return DecodedImage(cgImage: image)
        }
        memory.insertFullResolution(decoded, forKey: memoryKey)
        return decoded.cgImage
    }

    /// The HDR rendition at the request's tier size, if one is in memory.
    public func memoryCachedHDRImage(for request: PreviewRequest) -> CGImage? {
        memory.image(forKey: Self.memoryKey(request.key, bucket: request.key.tier.longEdge) + "#hdr")
    }

    /// An HDR rendition of the master at the request's tier size (full resolution
    /// with `fullResolution`), for displays with extended dynamic range. Nil when
    /// the master has nothing above SDR white, is a video, or is offline.
    /// Rendered from the master each time it is not in memory; never cached on disk.
    public func hdrImage(for request: PreviewRequest, fullResolution: Bool = false,
                         priority: Priority = .visible) async throws -> CGImage? {
        let memoryKey = Self.memoryKey(request.key, bucket: fullResolution ? 0 : request.key.tier.longEdge) + "#hdr"
        if let image = memory.image(forKey: memoryKey) { return image }
        if standardRange.withLock({ $0.contains(memoryKey) }) { return nil }
        guard let source = request.sourceURL else { return nil }
        let generator = self.generator
        let loadStack = self.editStack
        let versionID = request.versionID
        let longEdge = fullResolution ? nil : request.key.tier.longEdge
        let decoded = try await hdrLane.run(key: memoryKey, priority: priority.rawValue,
                                            taskPriority: priority.taskPriority) {
            let stack = try await loadStack(versionID)
            try Task.checkCancellation()
            return try generator.hdrImage(source: source, stack: stack, longEdge: longEdge).map(DecodedImage.init)
        }
        guard let decoded else {
            standardRange.withLock { _ = $0.insert(memoryKey) }
            return nil
        }
        if fullResolution {
            memory.insertFullResolution(decoded, forKey: memoryKey)
        } else {
            memory.insert(decoded, forKey: memoryKey)
        }
        return decoded.cgImage
    }

    public func clearMemory() {
        memory.removeAll()
    }

    static func memoryKey(_ key: PreviewCacheKey, bucket: Int) -> String {
        "\(key.relativePath)@\(bucket)"
    }
}

/// The display color space, readable from any thread.
final class DisplayColorSpace: @unchecked Sendable {
    // @unchecked: guarded by `lock`; CGColorSpace itself is immutable.
    private let lock = NSLock()
    private var space: CGColorSpace?

    var value: CGColorSpace? {
        lock.lock()
        defer { lock.unlock() }
        return space
    }

    /// Stores `newValue` and returns whether it differs from the old one.
    func exchange(_ newValue: CGColorSpace?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let changed = space != newValue
        space = newValue
        return changed
    }
}

/// Byte-limited LRU of decoded images, safe from any thread.
final class MemoryCache: @unchecked Sendable {
    // @unchecked: all state is guarded by `lock`.
    private let lock = NSLock()
    private let cache = NSCache<NSString, Box>()
    private var fullResolutionKey: NSString?

    private final class Box {
        let image: DecodedImage
        init(_ image: DecodedImage) { self.image = image }
    }

    init(limit: Int) {
        cache.totalCostLimit = limit
    }

    func image(forKey key: String) -> CGImage? {
        cache.object(forKey: key as NSString)?.image.cgImage
    }

    func insert(_ image: DecodedImage, forKey key: String) {
        cache.setObject(Box(image), forKey: key as NSString, cost: image.byteCount)
    }

    /// Full-resolution renders are large; keep only one.
    func insertFullResolution(_ image: DecodedImage, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let previous = fullResolutionKey, previous as String != key {
            cache.removeObject(forKey: previous)
        }
        fullResolutionKey = key as NSString
        cache.setObject(Box(image), forKey: key as NSString, cost: image.byteCount)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
