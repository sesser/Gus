import Foundation
import PhotoFixtures
@testable import PhotoCore

/// Heal and clone spots in plain Swift (`SpotRenderer`, `SpotKernels`), in
/// single precision as the GPU computes, in Core Image's coordinates (y up,
/// pixel centers at half pixels). Pixels beyond the image repeat its edge.
enum SpotReference {
    /// A float RGB image with edge-repeating reads in Core Image's coordinates.
    struct Image {
        var width: Int, height: Int
        /// Rows from the top, RGB.
        var pixels: [SIMD3<Float>]

        init(_ image: LinearImage) {
            width = image.width
            height = image.height
            pixels = (0..<(width * height)).map { index in
                SIMD3(image.pixels[index * 4], image.pixels[index * 4 + 1], image.pixels[index * 4 + 2])
            }
        }

        /// The pixel whose lower left corner is (x, y), y up; clamped to the image.
        func texel(_ x: Int, _ y: Int) -> SIMD3<Float> {
            let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
            return pixels[(height - 1 - cy) * width + cx]
        }

        /// The value at a point, between the four nearest pixel centers (`spotBilinear`).
        func bilinear(_ x: Float, _ y: Float) -> SIMD3<Float> {
            let px = x - 0.5, py = y - 0.5
            let fx = px.rounded(.down), fy = py.rounded(.down)
            let tx = px - fx, ty = py - fy
            let ix = Int(fx), iy = Int(fy)
            let a = texel(ix, iy), b = texel(ix + 1, iy), c = texel(ix, iy + 1), d = texel(ix + 1, iy + 1)
            let bottom = a + (b - a) * tx
            let top = c + (d - c) * tx
            return bottom + (top - bottom) * ty
        }

        func linearImage() -> LinearImage {
            var out = [Float](repeating: 1, count: width * height * 4)
            for index in pixels.indices {
                out[index * 4] = pixels[index].x
                out[index * 4 + 1] = pixels[index].y
                out[index * 4 + 2] = pixels[index].z
            }
            return LinearImage(width: width, height: height, pixels: out)
        }
    }

    static func ringPoint(_ center: SIMD2<Float>, _ radius: Float, _ i: Int, _ count: Int) -> SIMD2<Float> {
        let angle = Float(6.283185307179586) * (Float(i) + 0.5) / Float(count)
        return center + radius * SIMD2(cos(angle), sin(angle))
    }

    /// `spots` over `input`, each reading what the ones before it left.
    static func apply(_ spots: [Spot], to input: LinearImage) -> LinearImage {
        var image = Image(input)
        let extent = CGRect(x: 0, y: 0, width: input.width, height: input.height)
        let count = SpotRenderer.boundarySamples
        for spot in spots where spot.opacity > 0 {
            let placed = SpotRenderer.Placement(spot, extent: extent)
            let center = SIMD2(Float(placed.center.x), Float(placed.center.y))
            let radius = Float(placed.radius), inner = Float(placed.inner)
            let offset = SIMD2(Float(placed.offset.dx), Float(placed.offset.dy))
            let opacity = Float(spot.opacity / 100)
            var boundary: [SIMD3<Float>] = []
            if spot.mode == .heal {
                boundary = (0..<count).map { i in
                    let b = ringPoint(center, radius + 1, i, count)
                    var sum = SIMD3<Float>(repeating: 0)
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let p = b + SIMD2(Float(dx), Float(dy))
                            sum += image.bilinear(p.x, p.y) - image.bilinear(p.x + offset.x, p.y + offset.y)
                        }
                    }
                    return sum / 9
                }
            }
            let rect = placed.rect.intersection(extent)
            guard !rect.isNull, !rect.isEmpty else { continue }
            var next = image
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let p = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                    let r = ((p.x - center.x) * (p.x - center.x) + (p.y - center.y) * (p.y - center.y)).squareRoot()
                    let t = min(max((radius - r) / max(radius - inner, 1), 0), 1)
                    let alpha = t * t * (3 - 2 * t) * opacity
                    guard alpha > 0 else { continue }
                    let base = image.texel(x, y)
                    var fill = image.texel(x + Int(offset.x), y + Int(offset.y))
                    if spot.mode == .heal {
                        var sum = SIMD3<Float>(repeating: 0)
                        var weights: Float = 0
                        for i in 0..<count {
                            let b = ringPoint(center, radius + 1, i, count)
                            let d = p - b
                            let w = 1 / max((d * d).sum(), 1e-4)
                            sum += w * boundary[i]
                            weights += w
                        }
                        fill += sum / weights
                    }
                    next.pixels[(image.height - 1 - y) * image.width + x] = base + (fill - base) * alpha
                }
            }
            image = next
        }
        return image.linearImage()
    }
}
