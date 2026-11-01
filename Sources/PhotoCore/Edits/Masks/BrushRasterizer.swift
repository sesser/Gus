import Accelerate
import CoreImage
import Foundation
import Synchronization

/// Brush strokes rasterized on the CPU, in plain Swift, at the size of the
/// mask frame being rendered: never a stored bitmap scaled up or down.
///
/// Dabs are a quarter of the radius apart along each segment (a sample that
/// does not move lays none) and paint 1 inside their hard core
/// (radius × (1 − feather)) and 1 − smoothstep(core, radius, d) outside it.
/// Within a stroke coverage builds as v ← v + a · flow · (density − v), so it
/// approaches Density without passing it; strokes combine with max, and an
/// erasing stroke multiplies by 1 − v. The dab profile and the quarter-radius
/// spacing follow LightCraft's (`crates/pipeline/src/masks.rs`, MIT or
/// Apache-2.0; see THIRD_PARTY_NOTICES.md); the accumulation toward Density
/// is our own.
public enum BrushRasterizer {
    /// One dab: center in pixels of the frame (y down), radius and hard core in pixels.
    struct Dab: Equatable {
        var x: Double
        var y: Double
    }

    /// Dab centers of a stroke over a `width` × `height` frame.
    static func dabs(_ stroke: BrushStroke, width: Int, height: Int) -> [Dab] {
        let longEdge = Double(max(width, height))
        let spacing = stroke.size * longEdge / 4
        var dabs: [Dab] = []
        var previous: Dab?
        for point in stroke.points {
            let next = Dab(x: point.x * Double(width), y: point.y * Double(height))
            guard let last = previous else {
                dabs.append(next)
                previous = next
                continue
            }
            let distance = hypot(next.x - last.x, next.y - last.y)
            guard distance > 0, spacing > 0 else { continue }
            let count = Int((distance / spacing).rounded(.up))
            for step in 1...count {
                let t = Double(step) / Double(count)
                dabs.append(Dab(x: last.x + (next.x - last.x) * t, y: last.y + (next.y - last.y) * t))
            }
            previous = next
        }
        return dabs
    }

    /// How much one dab paints at distance `d` from its center.
    static func dabAlpha(_ d: Double, radius: Double, core: Double) -> Double {
        if d > radius { return 0 }
        if d <= core { return 1 }
        let t = (d - core) / (radius - core)
        return 1 - t * t * (3 - 2 * t)
    }

    /// Coverage 0 … 1 of every pixel (row-major, top row first).
    public static func rasterize(_ brush: Brush, width: Int, height: Int) -> [Float] {
        var coverage = [Float](repeating: 0, count: width * height)
        guard width > 0, height > 0, !brush.strokes.isEmpty else { return coverage }
        let longEdge = Double(max(width, height))
        struct Prepared {
            var dabs: [Dab]
            var radius: Double
            var core: Double
            var flow: Double
            var density: Double
            var erase: Bool
        }
        let strokes = brush.strokes.map { stroke in
            let radius = stroke.size * longEdge
            return Prepared(dabs: dabs(stroke, width: width, height: height), radius: radius,
                            core: radius * (1 - stroke.feather / 100), flow: stroke.flow / 100,
                            density: stroke.density / 100, erase: stroke.erase)
        }
        // Bands of rows in parallel: each band draws every dab that reaches
        // it, in stroke order, so the result does not depend on the split.
        let bandHeight = max(16, height / (ProcessInfo.processInfo.activeProcessorCount * 4))
        let bands = (height + bandHeight - 1) / bandHeight
        coverage.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let output = buffer
            DispatchQueue.concurrentPerform(iterations: bands) { band in
                let top = band * bandHeight
                let bottom = min(height, top + bandHeight)
                var stroke = [Double](repeating: 0, count: (bottom - top) * width)
                for prepared in strokes {
                    for index in stroke.indices { stroke[index] = 0 }
                    var touched = false
                    for dab in prepared.dabs {
                        let y0 = max(top, Int((dab.y - prepared.radius).rounded(.down)))
                        let y1 = min(bottom, Int((dab.y + prepared.radius).rounded(.up)) + 1)
                        guard y0 < y1 else { continue }
                        let x0 = max(0, Int((dab.x - prepared.radius).rounded(.down)))
                        let x1 = min(width, Int((dab.x + prepared.radius).rounded(.up)) + 1)
                        guard x0 < x1 else { continue }
                        touched = true
                        for y in y0..<y1 {
                            let dy = Double(y) + 0.5 - dab.y
                            let row = (y - top) * width
                            for x in x0..<x1 {
                                let dx = Double(x) + 0.5 - dab.x
                                let a = dabAlpha((dx * dx + dy * dy).squareRoot(), radius: prepared.radius,
                                                 core: prepared.core)
                                guard a > 0 else { continue }
                                let v = stroke[row + x]
                                stroke[row + x] = v + a * prepared.flow * (prepared.density - v)
                            }
                        }
                    }
                    guard touched else { continue }
                    for y in top..<bottom {
                        let row = (y - top) * width
                        for x in 0..<width {
                            let v = Float(stroke[row + x])
                            let index = y * width + x
                            output[index] = prepared.erase ? output[index] * (1 - v) : max(output[index], v)
                        }
                    }
                }
            }
        }
        return coverage
    }

    /// The coverage as a grey Core Image image over `extent` (one channel, half
    /// float, not color managed), cached by brush and size.
    static func image(_ brush: Brush, extent: CGRect) -> CIImage? {
        let width = Int(extent.width.rounded()), height = Int(extent.height.rounded())
        guard width > 0, height > 0 else { return nil }
        let key = CacheKey(brush: brush, width: width, height: height)
        if let cached = cache.image(for: key) {
            return cached.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        }
        var coverage = rasterize(brush, width: width, height: height)
        var half = Data(count: width * height * 2)
        let converted = coverage.withUnsafeMutableBytes { source in
            half.withUnsafeMutableBytes { destination in
                var from = vImage_Buffer(data: source.baseAddress, height: vImagePixelCount(height),
                                         width: vImagePixelCount(width), rowBytes: width * 4)
                var to = vImage_Buffer(data: destination.baseAddress, height: vImagePixelCount(height),
                                       width: vImagePixelCount(width), rowBytes: width * 2)
                return vImageConvert_PlanarFtoPlanar16F(&from, &to, vImage_Flags(kvImageNoFlags))
            }
        }
        guard converted == kvImageNoError else { return nil }
        let image = CIImage(bitmapData: half, bytesPerRow: width * 2, size: CGSize(width: width, height: height),
                            format: .Lh, colorSpace: nil)
        cache.insert(image, for: key, bytes: half.count)
        return image.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    struct CacheKey: Hashable, Sendable {
        var brush: Brush
        var width: Int
        var height: Int
    }

    /// Rasterized brushes, least recently used out first, at most 256 MB.
    static let cache = RasterCache(limit: 256 << 20)

    final class RasterCache: Sendable {
        private struct Entry {
            var image: CIImage
            var bytes: Int
        }
        private struct State {
            var entries: [CacheKey: Entry] = [:]
            var order: [CacheKey] = []
            var bytes = 0
        }
        private let state = Mutex(State())
        let limit: Int

        init(limit: Int) {
            self.limit = limit
        }

        func image(for key: CacheKey) -> CIImage? {
            state.withLock { state in
                guard let entry = state.entries[key] else { return nil }
                state.order.removeAll { $0 == key }
                state.order.append(key)
                return entry.image
            }
        }

        func insert(_ image: CIImage, for key: CacheKey, bytes: Int) {
            state.withLock { state in
                if let old = state.entries[key] {
                    state.bytes -= old.bytes
                    state.order.removeAll { $0 == key }
                }
                state.entries[key] = Entry(image: image, bytes: bytes)
                state.order.append(key)
                state.bytes += bytes
                while state.bytes > limit, state.order.count > 1 {
                    let oldest = state.order.removeFirst()
                    state.bytes -= state.entries.removeValue(forKey: oldest)?.bytes ?? 0
                }
            }
        }

        var byteCount: Int { state.withLock { $0.bytes } }
    }
}
