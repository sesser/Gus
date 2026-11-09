import Foundation
import PhotoFixtures
@testable import PhotoCore

/// The Lens heading's steps in plain Swift (`LensRenderer.swift`,
/// `LensKernels`), in single precision as the GPU computes. The renderer is
/// checked against it through a context whose intermediates are 32-bit
/// float, where the two agree to float rounding; the app's half-float
/// context adds the roundings `LensRenderingTests` bounds. Pixels beyond
/// the image repeat its edge.
enum LensReference {
    static let lumaWeights = SIMD3<Float>(0.2627, 0.6780, 0.0593)

    static func encodeSRGB(_ v: Float) -> Float {
        let c = min(max(v, 0), 1)
        return c <= 0.003_130_8 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// OkLab a and b of a linear Rec. 2020 color clamped to 0 … 1.
    static func okLabAB(_ rgb: SIMD3<Float>) -> SIMD2<Float> {
        let lab = ColorRange.okLab(linearRec2020: SIMD3(Double(rgb.x), Double(rgb.y), Double(rgb.z)))
        return SIMD2(Float(lab.y), Float(lab.z))
    }

    static func colorWeight(_ ab: SIMD2<Float>, _ slot: ColorFringes.Slot?) -> Float {
        guard let slot else { return 0 }
        return Float(ColorFringes.colorWeight(a: Double(ab.x), b: Double(ab.y), slot: slot))
    }

    /// A grey field over a padded frame, so passes can read past the image's edges.
    struct Field {
        var width: Int, height: Int, pad: Int
        var values: [Float]

        init(width: Int, height: Int, pad: Int, _ value: (Int, Int) -> Float) {
            self.width = width
            self.height = height
            self.pad = pad
            values = [Float](repeating: 0, count: (width + 2 * pad) * (height + 2 * pad))
            for y in -pad..<(height + pad) {
                for x in -pad..<(width + pad) { values[index(x, y)] = value(x, y) }
            }
        }

        func index(_ x: Int, _ y: Int) -> Int { (y + pad) * (width + 2 * pad) + (x + pad) }

        subscript(x: Int, y: Int) -> Float {
            values[index(min(max(x, -pad), width + pad - 1), min(max(y, -pad), height + pad - 1))]
        }
    }

    /// The edge rule's weight for every pixel of `image` at `scale`.
    static func edgeWeight(_ image: LinearImage, scale: Double) -> [Float] {
        let w = image.width, h = image.height
        let radius = AdjustmentRenderer.edgeRadius(scale: scale)
        let sigma = Float(radius) / 4
        let blurRadius = Int((3 * sigma).rounded(.up))
        let pad = radius + blurRadius + 1
        func pixel(_ x: Int, _ y: Int) -> SIMD3<Float> {
            let p = image[min(max(x, 0), w - 1), min(max(y, 0), h - 1)]
            return SIMD3(p.x, p.y, p.z)
        }
        let luma = Field(width: w, height: h, pad: pad) { x, y in encodeSRGB((pixel(x, y) * lumaWeights).sum()) }
        // Horizontal then vertical window: maximum and minimum.
        var high1 = Field(width: w, height: h, pad: pad) { _, _ in 0 }
        var low1 = high1
        for y in -pad..<(h + pad) {
            for x in -pad..<(w + pad) {
                var high: Float = -65504, low: Float = 65504
                for i in -radius...radius {
                    let v = luma[x + i, y]
                    high = max(high, v)
                    low = min(low, v)
                }
                high1.values[high1.index(x, y)] = high
                low1.values[low1.index(x, y)] = low
            }
        }
        let contrast = AdjustmentRenderer.fringeEdgeContrast
        var edge = Field(width: w, height: h, pad: pad) { _, _ in 0 }
        for y in -blurRadius..<(h + blurRadius) {
            for x in -blurRadius..<(w + blurRadius) {
                var high: Float = -65504, low: Float = 65504
                for i in -radius...radius {
                    high = max(high, high1[x, y + i])
                    low = min(low, low1[x, y + i])
                }
                edge.values[edge.index(x, y)] = smoothstep(Float(contrast.lowerBound), Float(contrast.upperBound),
                                                           high - low)
            }
        }
        var weights = (-blurRadius...blurRadius).map { Float(exp(-Double($0 * $0) / (2 * Double(sigma * sigma)))) }
        let total = weights.reduce(0, +)
        weights = weights.map { $0 / total }
        var horizontal = Field(width: w, height: h, pad: pad) { _, _ in 0 }
        for y in -blurRadius..<(h + blurRadius) {
            for x in 0..<w {
                var sum: Float = 0
                for i in -blurRadius...blurRadius { sum += edge[x + i, y] * weights[i + blurRadius] }
                horizontal.values[horizontal.index(x, y)] = sum
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var sum: Float = 0
                for i in -blurRadius...blurRadius { sum += horizontal[x, y + i] * weights[i + blurRadius] }
                out[y * w + x] = sum
            }
        }
        return out
    }

    /// How much of its color each pixel loses (the fringe map).
    static func fringeWeight(_ image: LinearImage, _ fringes: ColorFringes, scale: Double) -> [Float] {
        let edge = edgeWeight(image, scale: scale)
        return (0..<(image.width * image.height)).map { i in
            let p = SIMD3(image.pixels[i * 4], image.pixels[i * 4 + 1], image.pixels[i * 4 + 2])
            let ab = okLabAB(p)
            return edge[i] * max(colorWeight(ab, fringes.slot1), colorWeight(ab, fringes.slot2))
        }
    }

    /// `image` with its fringes turned toward the gray of the same luminance.
    static func removeFringes(_ image: LinearImage, _ fringes: ColorFringes, scale: Double) -> LinearImage {
        let weight = fringeWeight(image, fringes, scale: scale)
        var out = image
        for i in 0..<(image.width * image.height) {
            let p = SIMD3(image.pixels[i * 4], image.pixels[i * 4 + 1], image.pixels[i * 4 + 2])
            let y = (p * lumaWeights).sum()
            let mixed = p + (SIMD3(repeating: y) - p) * weight[i]
            out.pixels[i * 4] = mixed.x
            out.pixels[i * 4 + 1] = mixed.y
            out.pixels[i * 4 + 2] = mixed.z
        }
        return out
    }

    /// Red and blue scaled about the frame's center by their magnifications,
    /// interpolated between the four nearest pixel centers; edges repeat.
    static func align(_ image: LinearImage, _ alignment: ColorAlignment) -> LinearImage {
        let w = image.width, h = image.height
        let cx = Float(w) / 2, cy = Float(h) / 2
        func channel(_ c: Int, at px: Float, _ py: Float) -> Float {
            let x = px - 0.5, y = py - 0.5
            let fx = x.rounded(.down), fy = y.rounded(.down)
            let tx = x - fx, ty = y - fy
            func v(_ ix: Int, _ iy: Int) -> Float {
                image.pixels[(min(max(iy, 0), h - 1) * w + min(max(ix, 0), w - 1)) * 4 + c]
            }
            let ix = Int(fx), iy = Int(fy)
            let top = v(ix, iy) + (v(ix + 1, iy) - v(ix, iy)) * tx
            let bottom = v(ix, iy + 1) + (v(ix + 1, iy + 1) - v(ix, iy + 1)) * tx
            return top + (bottom - top) * ty
        }
        var out = image
        let red = Float(alignment.redScale), blue = Float(alignment.blueScale)
        for y in 0..<h {
            for x in 0..<w {
                let px = Float(x) + 0.5, py = Float(y) + 0.5
                let i = (y * w + x) * 4
                out.pixels[i] = channel(0, at: cx + (px - cx) * (1 + red), cy + (py - cy) * (1 + red))
                out.pixels[i + 2] = channel(2, at: cx + (px - cx) * (1 + blue), cy + (py - cy) * (1 + blue))
            }
        }
        return out
    }
}
