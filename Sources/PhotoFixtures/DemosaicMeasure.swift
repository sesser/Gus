import CoreImage
import Foundation
import PhotoCore

// Shared by `photobench demosaic` and the tests. The measures of the #194 spike (`spike.md`, Question 2), used by name in
// issue #196's acceptance criteria: false color and detail, block and edge
// ΔE76, CPSNR and edge chroma error against a known truth. Taken over from
// the spike's own measurement code (ours), tidied.

/// Linear RGB pixels, row by row from the top.
public struct RGBPicture: Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [SIMD3<Float>]

    public init(width: Int, height: Int, pixels: [SIMD3<Float>]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// From RGBA floats.
    public init(rgba: [Float], width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = (0..<(width * height)).map { SIMD3(rgba[$0 * 4], rgba[$0 * 4 + 1], rgba[$0 * 4 + 2]) }
    }

    public subscript(x: Int, y: Int) -> SIMD3<Float> { pixels[y * width + x] }

    public func map(_ body: (SIMD3<Float>) -> SIMD3<Float>) -> RGBPicture {
        RGBPicture(width: width, height: height, pixels: pixels.map(body))
    }

    public func cropped(x: Int, y: Int, width w: Int, height h: Int) -> RGBPicture {
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(w * h)
        for row in y..<(y + h) { out.append(contentsOf: pixels[(row * width + x)..<(row * width + x + w)]) }
        return RGBPicture(width: w, height: h, pixels: out)
    }

    /// The middle `size` x `size` (or less, if the picture is smaller).
    public func middle(_ size: Int) -> RGBPicture {
        let w = min(size, width), h = min(size, height)
        return cropped(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
    }
}

public enum Measure {
    public static let working = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!

    /// A 32-bit float context in the working space: renders a decode's
    /// values as they are (half floats exactly, 16-bit integers to Float).
    public static let context = CIContext(options: [.workingColorSpace: working, .workingFormat: CIFormat.RGBAf,
                                             .cacheIntermediates: false])

    public static func render(_ image: CIImage) -> RGBPicture {
        let extent = image.extent.integral
        let w = Int(extent.width), h = Int(extent.height)
        var floats = [Float](repeating: 0, count: w * h * 4)
        floats.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: w * 16, bounds: extent, format: .RGBAf,
                           colorSpace: working)
        }
        return RGBPicture(rgba: floats, width: w, height: h)
    }

    // MARK: Color

    public static let rec2020ToXYZ: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = {
        let m = WorkingSpace.toXYZ
        return (SIMD3<Float>(m.r0), SIMD3<Float>(m.r1), SIMD3<Float>(m.r2))
    }()
    public static let d65 = SIMD3<Float>(Chromaticity.d65.xyz)

    /// CIELAB (D65 white) of linear Rec. 2020, negative values clipped to 0.
    @inline(__always) public static func lab(_ c: SIMD3<Float>) -> SIMD3<Float> {
        labOf(c, rec2020ToXYZ)
    }

    public static let srgbToXYZ: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = (
        SIMD3(0.4124, 0.3576, 0.1805), SIMD3(0.2126, 0.7152, 0.0722), SIMD3(0.0193, 0.1192, 0.9505))

    /// CIELAB of linear sRGB (a synthetic truth's camera space).
    @inline(__always) public static func labSRGB(_ c: SIMD3<Float>) -> SIMD3<Float> {
        labOf(c, srgbToXYZ)
    }

    @inline(__always) public static func labOf(_ c: SIMD3<Float>, _ m: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)) -> SIMD3<Float> {
        let p = pointwiseMax(c, .zero)
        let xyz = SIMD3((p * m.0).sum(), (p * m.1).sum(), (p * m.2).sum()) / d65
        @inline(__always) func f(_ t: Float) -> Float { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let fx = f(xyz.x), fy = f(xyz.y), fz = f(xyz.z)
        return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    public static func encode(_ v: Float) -> Float {
        let x = min(max(v, 0), 1)
        return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
    }

    /// The camera RGB of a decode through the color step's numbers on the
    /// CPU (white balance gain, clip, matrix and exposure, the tone curve
    /// by table), so a ΔE is of the photo as it is shown.
    public struct ColorStep {
        var gain: SIMD3<Float>
        var rows: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
        var curve: [Float]

        public init?(_ step: CameraColorStep, temperature: Double? = nil) {
            let transform = step.transform(temperature: temperature, tint: nil)
            guard let gain = transform.gain, let matrix = transform.matrix else { return nil }
            self.gain = SIMD3<Float>(gain)
            let m = transform.exposure * matrix
            rows = (SIMD3<Float>(m.r0), SIMD3<Float>(m.r1), SIMD3<Float>(m.r2))
            let points = transform.toneCurve ?? []
            curve = (0..<4096).map {
                Float(points.isEmpty ? Double($0) / 4095 : CameraColorTransform.toneValue(points, at: Double($0) / 4095))
            }
        }

        @inline(__always) public func apply(_ camera: SIMD3<Float>) -> SIMD3<Float> {
            let balanced = pointwiseMin(pointwiseMax(camera * gain, .zero), SIMD3(repeating: 1))
            let (a, b, c) = rows
            let linear = SIMD3((balanced * a).sum(), (balanced * b).sum(), (balanced * c).sum())
            @inline(__always) func tone(_ v: Float) -> Float {
                let p = min(max(v, 0), 1) * 4095
                let i = min(Int(p), 4094), f = p - Float(i)
                return curve[i] * (1 - f) + curve[i + 1] * f
            }
            return SIMD3(tone(linear.x), tone(linear.y), tone(linear.z))
        }
    }

    // MARK: Differences

    public struct Summary: CustomStringConvertible, Sendable {
        public var median: Double, p95: Double, p99: Double, mean: Double, count: Int
        public init(_ values: [Float]) {
            let s = values.sorted()
            count = s.count
            func q(_ p: Double) -> Double { s.isEmpty ? .nan : Double(s[min(s.count - 1, Int(Double(s.count) * p))]) }
            median = q(0.5)
            p95 = q(0.95)
            p99 = q(0.99)
            mean = s.isEmpty ? .nan : Double(s.reduce(0, +)) / Double(s.count)
        }
        public var description: String { String(format: "median %.2f, p95 %.2f, p99 %.2f (mean %.2f, n %d)", median, p95, p99, mean, count) }
    }

    /// Lab of each 16-pixel block's mean (a `border` left out).
    public static func blockLab(_ p: RGBPicture, block: Int = 16, border: Int = 16) -> [SIMD3<Float>] {
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

    public static func deltaE(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>]) -> [Float] {
        zip(a, b).map { (($0 - $1) * ($0 - $1)).sum().squareRoot() }
    }

    /// Edge pixels: the top `fraction` of the L* gradient (central differences), a border left out.
    public static func edgeMask(_ labs: [SIMD3<Float>], width: Int, height: Int, fraction: Double = 0.1, border: Int = 8) -> [Bool] {
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

    /// Per pixel ΔE76 of `a` against `reference`, over all pixels, at edges,
    /// the edges' chroma part (Δa, Δb) and away from edges.
    public struct PixelComparison: CustomStringConvertible, Sendable {
        public var all: Summary, edges: Summary, edgeChroma: Summary, flat: Summary
        public var description: String {
            String(format: "ΔE all %.2f/%.2f, flat %.2f/%.2f, edges %.2f/%.2f; edge chroma %.2f/%.2f (median/p95)",
                   all.median, all.p95, flat.median, flat.p95, edges.median, edges.p95, edgeChroma.median, edgeChroma.p95)
        }
    }

    public static func compare(_ a: [SIMD3<Float>], _ reference: [SIMD3<Float>], edges: [Bool], width: Int, height: Int,
                        border: Int = 8) -> PixelComparison {
        var all: [Float] = [], edge: [Float] = [], chroma: [Float] = [], flat: [Float] = []
        for y in border..<(height - border) {
            for x in border..<(width - border) {
                let i = y * width + x
                let d = a[i] - reference[i]
                let e = (d * d).sum().squareRoot()
                all.append(e)
                if edges[i] {
                    edge.append(e)
                    chroma.append((d.y * d.y + d.z * d.z).squareRoot())
                } else {
                    flat.append(e)
                }
            }
        }
        return PixelComparison(all: Summary(all), edges: Summary(edge), edgeChroma: Summary(chroma), flat: Summary(flat))
    }

    /// No-reference measures of one picture at its edges: the high-pass of
    /// a* and b* (the picture less its 5 x 5 box mean; false color) and of
    /// L* (detail, which blur lowers). Means over the edge pixels.
    public static func falseColor(_ labs: [SIMD3<Float>], edges: [Bool], width: Int, height: Int) -> (chroma: Double, detail: Double) {
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

    /// Color PSNR over the sRGB-encoded values (dB), a border left out.
    public static func cpsnr(_ a: RGBPicture, _ truth: RGBPicture, border: Int = 8) -> Double {
        var sum = 0.0, n = 0.0
        for y in border..<(truth.height - border) {
            for x in border..<(truth.width - border) {
                let p = a[x, y], q = truth[x, y]
                for c in 0..<3 {
                    let d = Double(encode(p[c]) - encode(q[c]))
                    sum += d * d
                    n += 1
                }
            }
        }
        return 10 * log10(1 / (sum / n))
    }
}
