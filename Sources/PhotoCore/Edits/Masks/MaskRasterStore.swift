import Foundation
import Synchronization

/// Stored detection results as the renderer reads them (issue #88, R5, R7):
/// from the catalog's `maskRaster` table on first use, then decoded in
/// memory, at most `capacity` of them (each at most 256 KB at Vision's
/// sizes), the least recently used dropped first.
///
/// `lookup` reads the catalog when the result is not in memory, so it blocks:
/// renderers call it off the main actor while they build a graph, as
/// `LookTableStore` reads its files. The main actor asks `cached` only.
public final class MaskRasterStore: Sendable {
    /// A stored result, or none: no row, or a row whose bytes can't be read
    /// (design §6: missing and damaged are one state).
    public enum Lookup: Sendable, Equatable {
        case stored(Entry)
        case missing
    }

    public struct Entry: Sendable, Equatable {
        public let pixels: MaskRaster.Pixels
        /// 0 for an empty result.
        public let instances: Int
    }

    public static let capacity = 48

    private let catalog: Catalog?
    private struct Cache {
        var entries: [String: Entry] = [:]
        /// Digests, least recently used first.
        var order: [String] = []
    }
    private let cache = Mutex(Cache())

    public init(catalog: Catalog) {
        self.catalog = catalog
    }

    /// A store with no catalog behind it, holding `rasters` (tests, references).
    public init(rasters: [MaskRaster]) {
        catalog = nil
        for raster in rasters { remember(raster) }
    }

    /// The result `digest` names. Reads the catalog when it is not in memory.
    public func lookup(_ digest: String) -> Lookup {
        if let lookup = cached(digest) { return lookup }
        guard let catalog else { return .missing }
        let stored: MaskRaster?
        do {
            stored = try catalog.maskRasterBlocking(digest: digest)
        } catch {
            // A failed read is not remembered: the next render asks again.
            return .missing
        }
        guard let stored, let entry = Self.entry(stored) else { return .missing }
        insert(entry, for: digest)
        return .stored(entry)
    }

    /// The result if it is in memory, else nil: never reads the catalog.
    public func cached(_ digest: String) -> Lookup? {
        cache.withLock { cache in
            guard let entry = cache.entries[digest] else { return nil }
            if let index = cache.order.firstIndex(of: digest) {
                cache.order.remove(at: index)
                cache.order.append(digest)
            }
            return .stored(entry)
        }
    }

    /// Keeps a result just made, so renders find it before its row is written.
    public func remember(_ raster: MaskRaster) {
        guard let entry = Self.entry(raster) else { return }
        insert(entry, for: raster.digest)
    }

    /// Drops a result from memory (after the debug script deletes or damages its row).
    public func forget(_ digest: String) {
        cache.withLock { cache in
            cache.entries[digest] = nil
            cache.order.removeAll { $0 == digest }
        }
    }

    private func insert(_ entry: Entry, for digest: String) {
        cache.withLock { cache in
            if cache.entries.updateValue(entry, forKey: digest) == nil {
                cache.order.append(digest)
            }
            while cache.order.count > Self.capacity {
                cache.entries[cache.order.removeFirst()] = nil
            }
        }
    }

    /// The decoded result, or nil when its bytes don't decode or disagree with its row.
    static func entry(_ raster: MaskRaster) -> Entry? {
        guard let pixels = try? MaskRaster.pixels(fromPNG: raster.png),
              pixels.width == raster.width, pixels.height == raster.height else { return nil }
        return Entry(pixels: pixels, instances: raster.instances)
    }
}
