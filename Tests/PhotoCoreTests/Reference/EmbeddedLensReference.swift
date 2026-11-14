import CoreGraphics
import Foundation
import PhotoFixtures
@testable import PhotoCore

/// `EmbeddedLensCorrection.apply` in plain Swift, in single precision as the
/// kernel (`LensKernels`, "embeddedLens") computes: each output pixel's
/// channels are taken from their own places in the source, interpolated
/// between the four nearest pixel centers (edges repeat), and multiplied by
/// the gain of the place they were taken from, up to white (1). The tables are the
/// correction's own; the kernel only reads between their entries.
enum EmbeddedLensReference {
    /// - Parameter frame: The camera's frame in `source`, in Core Image's
    ///   coordinates (from the bottom left).
    static func apply(_ correction: EmbeddedLensCorrection, to source: LinearImage, frame: CGRect) -> LinearImage {
        let width = Int(frame.width.rounded()), height = Int(frame.height.rounded())
        let last = Double(EmbeddedLensCorrection.tableCount - 1)
        let radius = Double(hypot(frame.width, frame.height)) / 2
        let perDestination = Float(last / radius), perSource = Float(last / (radius * correction.sourceReach))
        let lastIndex = Float(last)
        let sourceCenter = SIMD2(Float(frame.midX), Float(frame.midY))
        let outputCenter = SIMD2(Float(width) / 2, Float(height) / 2)
        let multipliers = correction.multiplierOffsets.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }
        let gains = correction.gainOffsets.map { Float($0) }

        func between<T: SIMD>(_ values: [T], _ position: Float) -> T where T.Scalar == Float {
            let i = position.rounded(.down)
            let a = values[Int(i)]
            // Past the last entry the kernel reads nothing, with no weight.
            let b = Int(i) + 1 < values.count ? values[Int(i) + 1] : T.zero
            return a + (b - a) * (position - i)
        }
        func gain(_ position: Float) -> Float {
            between(gains.map { SIMD2($0, 0) }, position).x
        }
        /// One channel of the source at a point in Core Image's coordinates.
        func sample(_ channel: Int, at point: SIMD2<Float>) -> Float {
            let p = point - 0.5
            let fx = p.x.rounded(.down), fy = p.y.rounded(.down)
            let tx = p.x - fx, ty = p.y - fy
            func value(_ ix: Int, _ iy: Int) -> Float {
                let column = min(max(ix, 0), source.width - 1)
                // Rows are stored from the top; Core Image counts from the bottom.
                let row = source.height - 1 - min(max(iy, 0), source.height - 1)
                return source.pixels[(row * source.width + column) * 4 + channel]
            }
            let ix = Int(fx), iy = Int(fy)
            let lower = value(ix, iy) + (value(ix + 1, iy) - value(ix, iy)) * tx
            let upper = value(ix, iy + 1) + (value(ix + 1, iy + 1) - value(ix, iy + 1)) * tx
            return lower + (upper - lower) * ty
        }

        let gainRow = gains.map { SIMD2($0, 0) }
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let d = SIMD2(Float(column) + 0.5, Float(height - 1 - row) + 0.5) - outputCenter
                let length = (d.x * d.x + d.y * d.y).squareRoot()
                let m = 1 + between(multipliers, min(length * perDestination, lastIndex))
                for channel in 0..<3 {
                    let factor = m[channel]
                    let value = sample(channel, at: sourceCenter + d * factor)
                    let position = min(length * factor * perSource, lastIndex)
                    // Up to the decode's white: a clipped value stays white.
                    pixels[(row * width + column) * 4 + channel] = min(value * (1 + between(gainRow, position).x), 1)
                }
            }
        }
        return LinearImage(width: width, height: height, pixels: pixels)
    }
}
