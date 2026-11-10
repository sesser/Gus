import CoreImage
import CoreImage.CIFilterBuiltins
import Synchronization

/// Gives every RAW decode a render graph of its own, so that a Core Image
/// context never uses for one decode what it prepared for another.
///
/// **The fault this works around** (macOS 27.2, Panasonic RW2; issue #55,
/// docs/features/raw-edge-smear/status.md). The RAW decoder's lens
/// correction takes a table from the file, and how much of the image the
/// correction reads depends on that table. A `CIContext` reuses what it
/// prepared for an earlier render whose graph has the same digest, and the
/// table is not in the digest: two raws of one camera with the same settings
/// have the same graph, so the second is corrected from the area the first
/// needed. Where it needs more, its outermost pixels are repeated to the
/// edge.
///
/// **The workaround.** The decoder's image goes through a clamp to bounds no
/// pixel reaches, different for every decode (`Key`). The clamp changes no
/// pixel, but its bounds are arguments of a kernel, and a kernel's arguments
/// are part of the graph's digest, so no two decodes have the same digest.
///
/// **What this rests on, none of it documented by Apple:**
/// - that the context keys what it reuses on the digest of the whole graph
///   being rendered (observed: any change after the decode that changes the
///   digest stops the fault; `CI_PRINT_TREE` prints the digests);
/// - that a kernel's arguments are in that digest (they have to be for any
///   filter parameter to take effect, and Core Image cannot drop a kernel as
///   it can a crop larger than the image, which did not stop the fault).
///
/// If a later macOS reuses state by something else, the smear can come back
/// without any error. Only real files show it: `RAWEdgeSmearTests` and
/// `RAWContextSoakTests` (`RAW_EDGE_SAMPLES`) are the guard, to be run on
/// every new macOS. The alternative that needs neither assumption, a context
/// to itself for every decode (new, or emptied with `clearCaches()`), was
/// built first and left about 50 KB behind per decode for the life of the
/// process (status.md, "C1").
///
/// Every `CIRAWFilter` whose image is rendered must get its image from
/// `output(of:)`. `RAWDecodeGraphTests` fails when a new file makes a filter.
enum RAWDecodeGraph {
    /// What makes one decode's graph differ from every other's: the bounds of
    /// its clamp.
    struct Key: Hashable, Sendable {
        /// Far beyond any pixel value (extended range reaches a few times
        /// white), and finite.
        static let base: Float = 1e30

        let low: Float
        let high: Float

        init(low: Float, high: Float) {
            self.low = low
            self.high = high
        }

        /// The serial as two 22-bit digits, each as that many steps of
        /// `Float` above `base`: every serial below 2⁴⁴ has bounds of its own,
        /// and they stay below 4 × 10³⁰.
        init(serial: UInt64) {
            func bound(_ digit: UInt64) -> Float {
                Float(bitPattern: Self.base.bitPattern + UInt32(digit & 0x3F_FFFF))
            }
            self.init(low: bound(serial), high: bound(serial >> 22))
        }
    }

    private static let serial = Atomic<UInt64>(0)

    /// A key no other decode in this process has.
    static func nextKey() -> Key {
        Key(serial: serial.wrappingAdd(1, ordering: .relaxed).newValue)
    }

    /// The decoder's image for `raw` as it is set up now, with a graph of its
    /// own. Nil when the decoder gives no image.
    ///
    /// - Parameter key: Left out everywhere but in tests, which pass bounds
    ///   low enough to see.
    static func output(of raw: CIRAWFilter, key: Key = nextKey()) -> CIImage? {
        raw.outputImage.map { keyed($0, with: key) }
    }

    /// `image` through a clamp to `key`'s bounds: the same pixels (to the
    /// last bit or the one before it: the GPU may compile the arithmetic
    /// before the clamp differently) and the same extent. The clamp works on
    /// values that are not premultiplied; a decoder's image is opaque, so
    /// that divides and multiplies by one.
    static func keyed(_ image: CIImage, with key: Key) -> CIImage {
        // An empty image has nothing to render, and must stay empty for its caller.
        guard !image.extent.isEmpty else { return image }
        let low = CGFloat(key.low), high = CGFloat(key.high)
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = image
        clamp.minComponents = CIVector(x: -low, y: -high, z: -low, w: -high)
        clamp.maxComponents = CIVector(x: low, y: high, z: low, w: high)
        return clamp.outputImage ?? image
    }
}
