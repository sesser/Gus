import CoreImage
import Foundation

/// Measures how much larger the red and blue images of a photo are than the
/// green (lateral color, design §7), for Align automatically (R7). The
/// result is stored in the stack (R8), so this runs only when the setting is
/// turned on, or pasted or applied with a preset (R16), never per render.
///
/// The model is the one `LensRenderer` corrects: each channel scaled about
/// the middle of the whole sensor. The master is decoded whole (a raw's
/// camera crop undone, `RAWDecodeSettings.fullFrame`), so a crop never
/// changes what is measured (R9), at up to `measureSize` pixels; the scale
/// it finds is a fraction, the same at every size.
///
/// For each of red and blue: the magnification m that best lines its
/// image, sampled at c + (p − c)(1 + m), up with the green at p, over the
/// pixels on edges. Channels differ in level and contrast where the scene
/// is colored, so within each tile of the image the green is first fitted
/// to the other channel (gain and offset, least squares). A coarse search
/// over the range finds the basin (steps of half a pixel at the corner),
/// then Gauss–Newton refines m.
public enum ColorAlignmentMeasurement {
    /// Long edge of the decode that is measured: a corner of a 24-megapixel
    /// photo is then 1,230 pixels from the center, so a magnification is
    /// found to well under a pixel of the full-size photo.
    public static let measureSize = 2048

    /// Pixels on edges are those whose green gradient (perceptual, per
    /// pixel) is at least this; others carry no information about position.
    static let edgeGradient: Float = 0.02
    /// Fewer edge pixels than this: nothing to measure (a flat or blank photo).
    static let minimumEdgePixels = 200
    /// Measured values (ten-thousandths) closer to zero than this are none:
    /// 0.05 is under 0.02 of a pixel at a 24-megapixel corner.
    static let noneBelow = 0.05

    public enum Failure: Error, Equatable {
        case unreadable
    }

    /// The values Align automatically stores for the master at `source`
    /// decoded with `adjustments`' decode settings.
    public static func measure(source: URL, adjustments: Adjustments, generator: PreviewGenerator) throws -> ColorAlignment {
        // A raw LibRaw decodes takes no decode settings and has one frame only.
        let isRaw = SystemRAWDecoder.reads(source)
        var settings = isRaw ? adjustments.decodeSettings : .none
        settings.fullFrame = isRaw
        let decoded: PreviewGenerator.Decoded
        do {
            decoded = try PreviewGenerator.decode(source, longEdge: measureSize, draft: false, settings: settings)
        } catch {
            throw Failure.unreadable
        }
        var image = decoded.image
        let extent = image.extent.integral
        guard !extent.isInfinite, !extent.isEmpty else { throw Failure.unreadable }
        let longest = max(extent.width, extent.height)
        if longest > CGFloat(measureSize) {
            image = image.scaledToFit(longEdge: measureSize)
        }
        let bounds = image.extent.integral
        let width = Int(bounds.width), height = Int(bounds.height)
        var rgba = [Float](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            generator.engine.withContext {
                $0.render(image, toBitmap: bytes.baseAddress!, rowBytes: width * 16, bounds: bounds, format: .RGBAf,
                          colorSpace: RenderEngine.workingColorSpace)
            }
        }
        let scales = measure(rgba: rgba, width: width, height: height)
        return ColorAlignment(automatic: true, red: units(scales.red), blue: units(scales.blue))
    }

    /// Ten-thousandths, to a hundredth of one, with tiny values as none.
    static func units(_ scale: Double) -> Double {
        let value = (scale / ColorAlignment.unit * 100).rounded() / 100
        return abs(value) < noneBelow ? 0 : min(max(value, ColorAlignment.range.lowerBound), ColorAlignment.range.upperBound)
    }

    /// The red and blue magnifications (fractions) of linear RGBA pixels, rows from the top.
    public static func measure(rgba: [Float], width: Int, height: Int) -> (red: Double, blue: Double) {
        guard width > 8, height > 8 else { return (0, 0) }
        func plane(_ channel: Int) -> [Float] {
            (0..<(width * height)).map { encode(rgba[$0 * 4 + channel]) }
        }
        let green = plane(1)
        let image = Planes(width: width, height: height, green: green)
        guard image.edges.count >= minimumEdgePixels else { return (0, 0) }
        return (image.magnification(of: plane(0)), image.magnification(of: plane(2)))
    }

    static func encode(_ v: Float) -> Float {
        let c = min(max(v, 0), 1)
        return c <= 0.003_130_8 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    /// The green plane, its edge pixels and their tiles.
    struct Planes {
        let width: Int, height: Int
        let green: [Float]
        let center: SIMD2<Double>
        /// Edge pixels: index, offset from the center, tile.
        var edges: [(index: Int, offset: SIMD2<Double>, tile: Int)] = []
        var tileCount = 0

        init(width: Int, height: Int, green: [Float]) {
            self.width = width
            self.height = height
            self.green = green
            center = SIMD2(Double(width) / 2, Double(height) / 2)
            let tile = max(16, max(width, height) / 16)
            let columns = (width + tile - 1) / tile
            tileCount = columns * ((height + tile - 1) / tile)
            for y in 2..<(height - 2) {
                for x in 2..<(width - 2) {
                    let i = y * width + x
                    let gx = (green[i + 1] - green[i - 1]) / 2, gy = (green[i + width] - green[i - width]) / 2
                    guard gx * gx + gy * gy >= edgeGradient * edgeGradient else { continue }
                    edges.append((i, SIMD2(Double(x) + 0.5, Double(y) + 0.5) - center, (y / tile) * columns + x / tile))
                }
            }
        }

        var halfDiagonal: Double { (center * center).sum().squareRoot() }

        /// `plane` at `point` (pixel coordinates, y down), between the four nearest pixel centers; edges repeat.
        func sample(_ plane: [Float], _ point: SIMD2<Double>) -> (value: Double, gradient: SIMD2<Double>) {
            let p = point - 0.5
            let fx = p.x.rounded(.down), fy = p.y.rounded(.down)
            let tx = p.x - fx, ty = p.y - fy
            func v(_ x: Int, _ y: Int) -> Double {
                Double(plane[min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)])
            }
            let x0 = Int(fx), y0 = Int(fy)
            let a = v(x0, y0), b = v(x0 + 1, y0), c = v(x0, y0 + 1), d = v(x0 + 1, y0 + 1)
            let top = a + (b - a) * tx, bottom = c + (d - c) * tx
            let gx = (b - a) * (1 - ty) + (d - c) * ty
            let gy = bottom - top
            return (top + (bottom - top) * ty, SIMD2(gx, gy))
        }

        /// Sum of squared differences between `plane` at magnification `m` and
        /// the green fitted per tile, and the Gauss–Newton step that lowers it.
        func evaluate(_ plane: [Float], _ m: Double) -> (cost: Double, step: Double) {
            var samples = [(value: Double, slope: Double)](repeating: (0, 0), count: edges.count)
            // Per tile sums for fitting value ≈ α·green + β.
            var sums = [SIMD4<Double>](repeating: .zero, count: tileCount)   // Σg, Σv, Σg², Σgv
            var counts = [Double](repeating: 0, count: tileCount)
            for (n, edge) in edges.enumerated() {
                let point = center + edge.offset * (1 + m)
                let s = sample(plane, point)
                samples[n] = (s.value, (s.gradient * edge.offset).sum())
                let g = Double(green[edge.index])
                sums[edge.tile] += SIMD4(g, s.value, g * g, g * s.value)
                counts[edge.tile] += 1
            }
            var fits = [(alpha: Double, beta: Double)?](repeating: nil, count: tileCount)
            for t in 0..<tileCount where counts[t] >= 8 {
                let n = counts[t], s = sums[t]
                let variance = s.z - s.x * s.x / n
                guard variance > 1e-6 else { continue }
                let alpha = (s.w - s.x * s.y / n) / variance
                fits[t] = (alpha, (s.y - alpha * s.x) / n)
            }
            var cost = 0.0, numerator = 0.0, denominator = 0.0
            for (n, edge) in edges.enumerated() {
                guard let fit = fits[edge.tile] else { continue }
                let e = samples[n].value - (fit.alpha * Double(green[edge.index]) + fit.beta)
                cost += e * e
                numerator += e * samples[n].slope
                denominator += samples[n].slope * samples[n].slope
            }
            return (cost, denominator > 0 ? -numerator / denominator : 0)
        }

        /// The magnification of `plane` relative to the green.
        func magnification(of plane: [Float]) -> Double {
            let limit = ColorAlignment.range.upperBound * ColorAlignment.unit
            // Steps of half a pixel at the corner.
            let step = 0.5 / max(halfDiagonal, 1)
            var best = (m: 0.0, cost: evaluate(plane, 0).cost)
            var m = -limit
            while m <= limit {
                let cost = evaluate(plane, m).cost
                if cost < best.cost { best = (m, cost) }
                m += step
            }
            var current = best.m
            for _ in 0..<20 {
                let delta = evaluate(plane, current).step
                // Within the basin the coarse search found.
                current = min(max(current + delta, best.m - step), best.m + step)
                if abs(delta) < 1e-8 { break }
            }
            return current
        }
    }
}
