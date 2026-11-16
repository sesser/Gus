// SPIKE for issue #194 (question 3): throwaway. COPIED from the #89 spike (branch
// feature/dcp-profiles, Sources/PhotoBench/DCPSpike/SpikeColor.swift, our own code), types renamed
// (Spike… → Profile…) so the two spikes can live in one target. Delete with the spike.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PhotoCore

// SPIKE for issue #89 (R1): throwaway. The profile's tables and curve on the
// CPU, from the DNG Specification 1.7.1.0 ("Applying the Hue/Saturation/Value
// Mapping Table", ProfileHueSatMapEncoding, ProfileLookTableEncoding,
// ProfileToneCurve, ProfileDynamicRange), and the images the comparison needs.

/// Linear RGB pixels, row by row from the top.
struct ProfileImage {
    var width: Int
    var height: Int
    var pixels: [SIMD3<Float>]

    func map(_ body: (SIMD3<Float>) -> SIMD3<Float>) -> ProfileImage {
        ProfileImage(width: width, height: height, pixels: pixels.map(body))
    }

    func scaled(by gain: Float) -> ProfileImage { map { $0 * gain } }

    /// Box average by an integer factor.
    func boxed(_ factor: Int) -> ProfileImage {
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
        return ProfileImage(width: w, height: h, pixels: out)
    }

    /// Bilinear resampling: output pixel (x, y) reads the source at
    /// center + (x - center) * (scale + k1 * r²) + (dx, dy), r the distance
    /// from the center as a part of the half diagonal, clamped to the edge.
    func warped(scale: Double, k1: Double = 0, dx: Double, dy: Double) -> ProfileImage {
        let cx = Double(width - 1) / 2, cy = Double(height - 1) / 2
        let norm = 1 / (cx * cx + cy * cy)
        var out = pixels
        for y in 0..<height {
            for x in 0..<width {
                let ux = Double(x) - cx, uy = Double(y) - cy
                let factor = scale + k1 * (ux * ux + uy * uy) * norm
                let sx = min(max(cx + ux * factor + dx, 0), Double(width - 1))
                let sy = min(max(cy + uy * factor + dy, 0), Double(height - 1))
                let x0 = Int(sx), y0 = Int(sy), x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
                let fx = Float(sx - Double(x0)), fy = Float(sy - Double(y0))
                let top = pixels[y0 * width + x0] * (1 - fx) + pixels[y0 * width + x1] * fx
                let bottom = pixels[y1 * width + x0] * (1 - fx) + pixels[y1 * width + x1] * fx
                out[y * width + x] = top * (1 - fy) + bottom * fy
            }
        }
        return ProfileImage(width: width, height: height, pixels: out)
    }
}

enum ProfileColor {
    static func rgbToXYZ(_ r: (Double, Double), _ g: (Double, Double), _ b: (Double, Double), white: Chromaticity) -> Matrix3x3 {
        func xyz(_ p: (Double, Double)) -> SIMD3<Double> { Chromaticity(x: p.0, y: p.1).xyz }
        let primaries = Matrix3x3(columns: xyz(r), xyz(g), xyz(b))
        let scale = (primaries.inverse ?? .identity) * white.xyz
        return primaries * Matrix3x3.diagonal(scale)
    }

    /// ProPhoto (RIMM) primaries with a D50 white.
    static let proPhotoToXYZD50 = rgbToXYZ((0.7347, 0.2653), (0.1596, 0.8404), (0.0366, 0.0001), white: .d50)
    static let sRGBToXYZD65 = rgbToXYZ((0.64, 0.33), (0.30, 0.60), (0.15, 0.06), white: .d65)

    static let d65ToD50 = ChromaticAdaptation.bradford(from: Chromaticity.d65.xyz, to: Chromaticity.d50.xyz)
    /// Working space (linear Rec. 2020, D65) to linear ProPhoto (D50), and back.
    static let workingToProPhoto = proPhotoToXYZD50.inverse! * d65ToD50 * WorkingSpace.toXYZ
    static let proPhotoToWorking = workingToProPhoto.inverse!
    static let workingToSRGB = sRGBToXYZD65.inverse! * WorkingSpace.toXYZ

    static func float(_ m: Matrix3x3) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        (SIMD3<Float>(m.r0), SIMD3<Float>(m.r1), SIMD3<Float>(m.r2))
    }

    static func apply(_ m: Matrix3x3, _ image: ProfileImage) -> ProfileImage {
        let (a, b, c) = float(m)
        return image.map { SIMD3(($0 * a).sum(), ($0 * b).sum(), ($0 * c).sum()) }
    }

    // MARK: sRGB transfer, HDR encoding

    static func srgbEncode(_ x: Float) -> Float { x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
    static func srgbDecode(_ x: Float) -> Float { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }

    /// ProfileDynamicRange's encoding function f(x) = x(256 + x) / (256(1 + x)) and its inverse.
    static func hdrEncode(_ x: Float) -> Float { x * (256 + x) / (256 * (1 + x)) }
    static func hdrDecode(_ y: Float) -> Float { 16 * (8 * y - 8 + (64 * y * y - 127 * y + 64).squareRoot()) }

    // MARK: HSV

    /// Hue in sixths (0 ..< 6), saturation, value.
    static func hsv(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let v = c.max(), mn = c.min(), delta = v - mn
        guard v > 0, delta > 0 else { return SIMD3(0, 0, max(v, 0)) }
        let s = delta / v
        var h: Float
        if c.x == v { h = (c.y - c.z) / delta } else if c.y == v { h = 2 + (c.z - c.x) / delta } else { h = 4 + (c.x - c.y) / delta }
        if h < 0 { h += 6 }
        if h >= 6 { h -= 6 }
        return SIMD3(h, s, v)
    }

    static func rgb(_ hsv: SIMD3<Float>) -> SIMD3<Float> {
        var h = hsv.x.truncatingRemainder(dividingBy: 6)
        if h < 0 { h += 6 }
        let s = hsv.y, v = hsv.z
        let i = min(Int(h), 5), f = h - Float(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return SIMD3(v, t, p)
        case 1: return SIMD3(q, v, p)
        case 2: return SIMD3(p, v, t)
        case 3: return SIMD3(p, q, v)
        case 4: return SIMD3(t, p, v)
        default: return SIMD3(v, p, q)
        }
    }

    /// The table's hue shift (degrees), saturation scale and value scale at
    /// a hue (sixths), saturation and (possibly encoded) value: wrap-around
    /// in hue, tri-linear, a dimension of one division constant.
    static func lookup(_ t: ProfileHSVTable, h: Float, s: Float, v: Float) -> SIMD3<Float> {
        let hs = h * Float(t.hue) / 6
        var h0 = Int(hs.rounded(.down)), hf = hs - Float(h0)
        h0 %= t.hue; if h0 < 0 { h0 += t.hue }
        let h1 = (h0 + 1) % t.hue
        if t.hue == 1 { hf = 0 }
        let ss = min(max(s, 0), 1) * Float(t.sat - 1)
        let s0 = min(Int(ss), t.sat - 1), s1 = min(s0 + 1, t.sat - 1), sf = ss - Float(s0)
        let vs = t.val > 1 ? min(max(v, 0), 1) * Float(t.val - 1) : 0
        let v0 = min(Int(vs), t.val - 1), v1 = min(v0 + 1, t.val - 1), vf = vs - Float(v0)
        func cell(_ vi: Int, _ hi: Int, _ si: Int) -> SIMD3<Float> {
            let i = ((vi * t.hue + hi) * t.sat + si) * 3
            return SIMD3(t.data[i], t.data[i + 1], t.data[i + 2])
        }
        func plane(_ vi: Int) -> SIMD3<Float> {
            let a = cell(vi, h0, s0) * (1 - sf) + cell(vi, h0, s1) * sf
            let b = cell(vi, h1, s0) * (1 - sf) + cell(vi, h1, s1) * sf
            return a * (1 - hf) + b * hf
        }
        return plane(v0) * (1 - vf) + plane(v1) * vf
    }

    /// One hue/saturation/value table on linear ProPhoto RGB.
    static func applyTable(_ t: ProfileHSVTable, to c: SIMD3<Float>, hdr: Bool) -> SIMD3<Float> {
        let threeD = t.val > 1
        var input = pointwiseMax(c, .zero)
        if hdr && threeD { input = SIMD3(hdrEncode(input.x), hdrEncode(input.y), hdrEncode(input.z)) }
        var hsv = Self.hsv(input)
        let encodeV = threeD && t.sRGBEncoded
        if encodeV { hsv.z = srgbEncode(hsv.z) }
        let m = lookup(t, h: hsv.x, s: hsv.y, v: hsv.z)
        hsv.x += m.x / 60
        hsv.y = min(hsv.y * m.y, 1)
        hsv.z *= m.z
        if !hdr { hsv.z = min(hsv.z, 1) }
        if encodeV { hsv.z = srgbDecode(hsv.z) }
        var out = Self.rgb(hsv)
        if hdr && threeD { out = SIMD3(hdrDecode(out.x), hdrDecode(out.y), hdrDecode(out.z)) }
        return out
    }

    // MARK: Tone curve

    /// A natural cubic spline through the points (the specification asks
    /// for "a cubic spline" and names no kind), as a 4096-entry table over 0 … 1.
    static func curveTable(_ points: [(Double, Double)], entries: Int = 4096) -> [Float] {
        let n = points.count
        let x = points.map(\.0), y = points.map(\.1)
        var second = [Double](repeating: 0, count: n)
        if n > 2 {
            var u = [Double](repeating: 0, count: n)
            for i in 1..<(n - 1) {
                let sig = (x[i] - x[i - 1]) / (x[i + 1] - x[i - 1])
                let p = sig * second[i - 1] + 2
                second[i] = (sig - 1) / p
                u[i] = (y[i + 1] - y[i]) / (x[i + 1] - x[i]) - (y[i] - y[i - 1]) / (x[i] - x[i - 1])
                u[i] = (6 * u[i] / (x[i + 1] - x[i - 1]) - sig * u[i - 1]) / p
            }
            for k in stride(from: n - 2, through: 0, by: -1) { second[k] = second[k] * second[k + 1] + u[k] }
        }
        var table = [Float](repeating: 0, count: entries)
        var segment = 0
        for index in 0..<entries {
            let t = Double(index) / Double(entries - 1)
            while segment < n - 2 && t > x[segment + 1] { segment += 1 }
            let h = x[segment + 1] - x[segment]
            let a = (x[segment + 1] - t) / h, b = (t - x[segment]) / h
            let value = a * y[segment] + b * y[segment + 1]
                + ((a * a * a - a) * second[segment] + (b * b * b - b) * second[segment + 1]) * h * h / 6
            table[index] = Float(min(max(value, 0), 1))
        }
        return table
    }

    static func curve(_ table: [Float], _ v: Float) -> Float {
        let p = min(max(v, 0), 1) * Float(table.count - 1)
        let i = min(Int(p), table.count - 2), f = p - Float(i)
        return table[i] * (1 - f) + table[i + 1] * f
    }

    enum CurveMethod: String, CaseIterable { case perChannel = "per-channel", huePreserving = "hue-preserving" }

    /// The curve on each channel, or on the largest and smallest with the
    /// middle one kept at the same place between them (hue kept).
    static func applyCurve(_ table: [Float], _ c: SIMD3<Float>, _ method: CurveMethod) -> SIMD3<Float> {
        switch method {
        case .perChannel:
            return SIMD3(curve(table, c.x), curve(table, c.y), curve(table, c.z))
        case .huePreserving:
            let mx = c.max(), mn = c.min()
            let newMax = curve(table, mx), newMin = curve(table, mn)
            guard mx > mn else { return SIMD3(repeating: newMax) }
            func mid(_ v: Float) -> Float { newMin + (newMax - newMin) * (v - mn) / (mx - mn) }
            return SIMD3(mid(c.x), mid(c.y), mid(c.z))
        }
    }

    // MARK: Lab and the measure

    static func lab(linearSRGB c: SIMD3<Float>) -> SIMD3<Double> {
        let xyz = sRGBToXYZD65 * SIMD3<Double>(c) / Chromaticity.d65.xyz
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let fx = f(max(xyz.x, 0)), fy = f(max(xyz.y, 0)), fz = f(max(xyz.z, 0))
        return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Lab of the mean of each 16-pixel block, skipping a 16-pixel border, as
    /// `LibRawAgainstSystemTests.Picture.blockLab` does, of a picture 320 pixels
    /// on its long edge in linear sRGB, clipped to 0 … 1 (what an sRGB export holds).
    static func blockLab(_ picture: ProfileImage) -> [SIMD3<Double>] {
        var result: [SIMD3<Double>] = []
        for top in stride(from: 16, to: picture.height - 31, by: 16) {
            for left in stride(from: 16, to: picture.width - 31, by: 16) {
                var sum = SIMD3<Float>.zero
                for y in top..<(top + 16) {
                    for x in left..<(left + 16) { sum += picture.pixels[y * picture.width + x] }
                }
                result.append(lab(linearSRGB: sum / 256))
            }
        }
        return result
    }

    struct Difference { var median: Double; var p95: Double; var blocks: Int }

    static func difference(_ a: [SIMD3<Double>], _ b: [SIMD3<Double>]) -> Difference {
        let d = zip(a, b).map { (($0 - $1) * ($0 - $1)).sum().squareRoot() }.sorted()
        guard !d.isEmpty else { return Difference(median: .nan, p95: .nan, blocks: 0) }
        return Difference(median: d[d.count / 2], p95: d[min(d.count - 1, Int(Double(d.count) * 0.95))], blocks: d.count)
    }
}

/// Renders Core Image images into `ProfileImage`s in the working space.
enum ProfileRender {
    static let working = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!

    static func context() -> CIContext {
        CIContext(options: [.workingColorSpace: working, .workingFormat: CIFormat.RGBAh])
    }

    /// The image resampled (Lanczos) to exactly `width` × `height` and rendered in the working space.
    static func render(_ image: CIImage, width: Int, height: Int, context: CIContext = context()) -> ProfileImage {
        let extent = image.extent
        let scale = Double(height) / extent.height
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .clampedToExtent()
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = Float((Double(width) / extent.width) / scale)
        let output = lanczos.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        var floats = [Float](repeating: 0, count: width * height * 4)
        floats.withUnsafeMutableBytes { buffer in
            context.render(output, toBitmap: buffer.baseAddress!, rowBytes: width * 16,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: working)
        }
        var pixels = [SIMD3<Float>](repeating: .zero, count: width * height)
        for i in 0..<(width * height) { pixels[i] = SIMD3(floats[i * 4], floats[i * 4 + 1], floats[i * 4 + 2]) }
        return ProfileImage(width: width, height: height, pixels: pixels)
    }
}
