import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PhotoCore

// SPIKE for issue #194: throwaway. Plain RGB pictures and the measures the
// spike reports on them.

/// Linear RGB pixels, row by row from the top.
struct RGBPicture {
    var width: Int
    var height: Int
    var pixels: [SIMD3<Float>]

    init(width: Int, height: Int, pixels: [SIMD3<Float>]) {
        self.width = width; self.height = height; self.pixels = pixels
    }

    /// From RGBA floats (a texture read).
    init(rgba: [Float], width: Int, height: Int) {
        self.width = width; self.height = height
        pixels = (0..<(width * height)).map { SIMD3(rgba[$0 * 4], rgba[$0 * 4 + 1], rgba[$0 * 4 + 2]) }
    }

    subscript(x: Int, y: Int) -> SIMD3<Float> { pixels[y * width + x] }

    func map(_ body: (SIMD3<Float>) -> SIMD3<Float>) -> RGBPicture {
        RGBPicture(width: width, height: height, pixels: pixels.map(body))
    }

    func cropped(x: Int, y: Int, width w: Int, height h: Int) -> RGBPicture {
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(w * h)
        for row in y..<(y + h) { out.append(contentsOf: pixels[(row * width + x)..<(row * width + x + w)]) }
        return RGBPicture(width: w, height: h, pixels: out)
    }

    /// Box average by an integer factor.
    func boxed(_ factor: Int) -> RGBPicture {
        let w = width / factor, h = height / factor
        var out = [SIMD3<Float>](repeating: .zero, count: w * h)
        let norm = 1 / Float(factor * factor)
        for y in 0..<h {
            for x in 0..<w {
                var sum = SIMD3<Float>.zero
                for dy in 0..<factor {
                    let row = (y * factor + dy) * width + x * factor
                    for dx in 0..<factor { sum += pixels[row + dx] }
                }
                out[y * w + x] = sum * norm
            }
        }
        return RGBPicture(width: w, height: h, pixels: out)
    }

    /// Turned and mirrored as LibRaw's flip says (1 mirrors columns, 2 rows, 4 swaps first).
    func flipped(_ flip: Int) -> RGBPicture {
        guard flip != 0 else { return self }
        let turned = flip & 4 != 0
        let w = turned ? height : width, h = turned ? width : height
        var out = [SIMD3<Float>](repeating: .zero, count: w * h)
        // Output (row, column) reads the source at: swapped when turned, then rows and columns mirrored.
        for y in 0..<h {
            for x in 0..<w {
                var sourceRow = turned ? x : y, sourceColumn = turned ? y : x
                if flip & 2 != 0 { sourceRow = height - 1 - sourceRow }
                if flip & 1 != 0 { sourceColumn = width - 1 - sourceColumn }
                out[y * w + x] = pixels[sourceRow * width + sourceColumn]
            }
        }
        return RGBPicture(width: w, height: h, pixels: out)
    }
}

enum Measure {
    static let working = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!

    static func context() -> CIContext {
        CIContext(options: [.workingColorSpace: working, .workingFormat: CIFormat.RGBAh])
    }

    /// The image (its extent) rendered in the working space as floats.
    static func render(_ image: CIImage, context: CIContext = context()) -> RGBPicture {
        let extent = image.extent.integral
        let w = Int(extent.width), h = Int(extent.height)
        var floats = [Float](repeating: 0, count: w * h * 4)
        floats.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: w * 16, bounds: extent, format: .RGBAf, colorSpace: working)
        }
        return RGBPicture(rgba: floats, width: w, height: h)
    }

    /// Resampled (Lanczos) to exactly `width` x `height`, in the working space.
    static func render(_ image: CIImage, width: Int, height: Int, context: CIContext = context()) -> RGBPicture {
        let extent = image.extent
        let scale = Double(height) / extent.height
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)).clampedToExtent()
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = Float((Double(width) / extent.width) / scale)
        return render(lanczos.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: width, height: height)), context: context)
    }

    // MARK: Color

    static let rec2020ToXYZ: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = {
        let m = WorkingSpace.toXYZ
        return (SIMD3<Float>(m.r0), SIMD3<Float>(m.r1), SIMD3<Float>(m.r2))
    }()
    static let d65 = SIMD3<Float>(Chromaticity.d65.xyz)

    /// CIELAB (D65 white) of linear Rec. 2020, negative values clipped to 0.
    @inline(__always) static func lab(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let p = pointwiseMax(c, .zero)
        let (a, b, d) = rec2020ToXYZ
        let xyz = SIMD3((p * a).sum(), (p * b).sum(), (p * d).sum()) / d65
        @inline(__always) func f(_ t: Float) -> Float { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let fx = f(xyz.x), fy = f(xyz.y), fz = f(xyz.z)
        return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// The camera RGB of a LibRaw-style decode (balanced by the multipliers)
    /// through the color step's numbers, on the CPU: the white balance gain,
    /// the clip, the matrix and the baseline exposure, and the tone curve's
    /// table, so that a ΔE is of the photo as it is shown.
    struct ColorStep {
        var gain: SIMD3<Float>
        var rows: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
        var curve: [Float]

        init?(_ step: CameraColorStep) {
            let transform = step.transform(temperature: nil, tint: nil)
            guard let gain = transform.gain, let matrix = transform.matrix else { return nil }
            self.gain = SIMD3<Float>(gain)
            let m = transform.exposure * matrix
            rows = (SIMD3<Float>(m.r0), SIMD3<Float>(m.r1), SIMD3<Float>(m.r2))
            let points = transform.toneCurve ?? []
            curve = (0..<4096).map { Float(points.isEmpty ? Double($0) / 4095 : CameraColorTransform.toneValue(points, at: Double($0) / 4095)) }
        }

        @inline(__always) func apply(_ camera: SIMD3<Float>) -> SIMD3<Float> {
            let balanced = pointwiseMin(pointwiseMax(camera * gain, .zero), SIMD3(repeating: 1))
            let (a, b, c) = rows
            let linear = SIMD3((balanced * a).sum(), (balanced * b).sum(), (balanced * c).sum())
            func tone(_ v: Float) -> Float {
                let p = min(max(v, 0), 1) * 4095
                let i = min(Int(p), 4094), f = p - Float(i)
                return curve[i] * (1 - f) + curve[i + 1] * f
            }
            return SIMD3(tone(linear.x), tone(linear.y), tone(linear.z))
        }
    }

    // MARK: Differences

    struct Summary: CustomStringConvertible {
        var median: Double, p95: Double, p99: Double, mean: Double, count: Int
        init(_ values: [Float]) {
            let s = values.sorted()
            count = s.count
            func q(_ p: Double) -> Double { s.isEmpty ? .nan : Double(s[min(s.count - 1, Int(Double(s.count) * p))]) }
            median = q(0.5); p95 = q(0.95); p99 = q(0.99)
            mean = s.isEmpty ? .nan : Double(s.reduce(0, +)) / Double(s.count)
        }
        var description: String { String(format: "median %.2f, p95 %.2f, p99 %.2f (mean %.2f, n %d)", median, p95, p99, mean, count) }
    }

    /// Lab of each 16-pixel block's mean (a `border` left out), as `LibRawAgainstSystemTests` measures.
    static func blockLab(_ p: RGBPicture, block: Int = 16, border: Int = 16) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        for top in stride(from: border, through: p.height - border - block, by: block) {
            for left in stride(from: border, through: p.width - border - block, by: block) {
                var sum = SIMD3<Float>.zero
                for y in top..<(top + block) { for x in left..<(left + block) { sum += p.pixels[y * p.width + x] } }
                out.append(lab(sum / Float(block * block)))
            }
        }
        return out
    }

    static func deltaE(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>]) -> [Float] {
        zip(a, b).map { (($0 - $1) * ($0 - $1)).sum().squareRoot() }
    }

    /// Edge pixels: the top `fraction` of the luminance gradient (central differences) of `p`, a border left out.
    static func edgeMask(_ labs: [SIMD3<Float>], width: Int, height: Int, fraction: Double = 0.1, border: Int = 8) -> [Bool] {
        var gradient = [Float](repeating: -1, count: width * height)
        for y in border..<(height - border) {
            for x in border..<(width - border) {
                let gx = labs[y * width + x + 1].x - labs[y * width + x - 1].x
                let gy = labs[(y + 1) * width + x].x - labs[(y - 1) * width + x].x
                gradient[y * width + x] = (gx * gx + gy * gy).squareRoot()
            }
        }
        let valid = gradient.filter { $0 >= 0 }.sorted()
        let threshold = valid[Int(Double(valid.count) * (1 - fraction))]
        return gradient.map { $0 >= threshold }
    }

    /// Per-pixel differences of two pictures in Lab, overall and at `edges`:
    /// ΔE76, the chroma part (Δa, Δb: false color) and ΔL* (zipper, blur).
    struct PixelComparison: CustomStringConvertible {
        var all: Summary, edges: Summary, edgeChroma: Summary, edgeLightness: Summary, flat: Summary
        var description: String {
            String(format: "ΔE all %.2f/%.2f/%.2f, flat %.2f/%.2f, edges %.2f/%.2f/%.2f; edge chroma %.2f/%.2f/%.2f; edge ΔL %.2f/%.2f/%.2f (median/p95/p99)",
                   all.median, all.p95, all.p99, flat.median, flat.p95, edges.median, edges.p95, edges.p99,
                   edgeChroma.median, edgeChroma.p95, edgeChroma.p99, edgeLightness.median, edgeLightness.p95, edgeLightness.p99)
        }
    }

    static func compare(_ a: [SIMD3<Float>], _ reference: [SIMD3<Float>], edges: [Bool], width: Int, height: Int, border: Int = 8) -> PixelComparison {
        var all: [Float] = [], edge: [Float] = [], chroma: [Float] = [], lightness: [Float] = [], flat: [Float] = []
        for y in border..<(height - border) {
            for x in border..<(width - border) {
                let i = y * width + x
                let d = a[i] - reference[i]
                let e = (d * d).sum().squareRoot()
                all.append(e)
                if edges[i] {
                    edge.append(e)
                    chroma.append((d.y * d.y + d.z * d.z).squareRoot())
                    lightness.append(abs(d.x))
                } else {
                    flat.append(e)
                }
            }
        }
        return PixelComparison(all: Summary(all), edges: Summary(edge), edgeChroma: Summary(chroma),
                               edgeLightness: Summary(lightness), flat: Summary(flat))
    }

    /// No-reference measures of one picture's edges: the high-pass of a* and
    /// b* (the picture less its 5x5 box mean) at edge pixels, which a
    /// demosaic's false color raises, and the same of L* (detail, which
    /// sharpening raises and blur lowers). Both are means over the edges.
    static func falseColor(_ labs: [SIMD3<Float>], edges: [Bool], width: Int, height: Int) -> (chroma: Double, detail: Double) {
        var chroma = 0.0, detail = 0.0, n = 0.0
        for y in 8..<(height - 8) {
            for x in 8..<(width - 8) where edges[y * width + x] {
                var mean = SIMD3<Float>.zero
                for dy in -2...2 { for dx in -2...2 { mean += labs[(y + dy) * width + x + dx] } }
                let high = labs[y * width + x] - mean / 25
                chroma += Double((high.y * high.y + high.z * high.z).squareRoot())
                detail += Double(abs(high.x))
                n += 1
            }
        }
        return (chroma / n, detail / n)
    }
}
