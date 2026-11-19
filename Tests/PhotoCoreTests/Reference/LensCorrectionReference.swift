import CoreGraphics
import Foundation
import PhotoFixtures
@testable import PhotoCore

/// The Distortion and Lens Vignetting steps (issue #87) in plain Swift, in
/// double precision from the models themselves (not their lookup tables):
///
/// - Lens vignetting: each pixel times the model's gain at its distance from
///   the optical center over the unit radius, by `LensGain.apply` (lifted at
///   most to white, lowered without a limit).
/// - Distortion: each pixel of the corrected picture (its center) taken from
///   `LensWarp.source(of:in:scale:)` at the frame's scale (`LensWarp.scale`),
///   read between the four nearest pixel centers with the edges repeated; a
///   place beyond the recorded image is opaque black.
///
/// Coordinates are Core Image's (from the bottom left), as the kernels see them.
enum LensCorrectionReference {
    static func gain(_ gain: LensGain, _ source: LinearImage, frame: CGRect) -> LinearImage {
        var pixels = source.pixels
        for row in 0..<source.height {
            for column in 0..<source.width {
                let point = CGPoint(x: Double(column) + 0.5, y: Double(source.height - 1 - row) + 0.5)
                let g = gain.gain(at: point, in: frame)
                for channel in 0..<3 {
                    let index = (row * source.width + column) * 4 + channel
                    pixels[index] = Float(LensGain.apply(g, to: Double(source.pixels[index])))
                }
            }
        }
        return LinearImage(width: source.width, height: source.height, pixels: pixels)
    }

    static func warp(_ warp: LensWarp, _ source: LinearImage, frame: CGRect) -> LinearImage {
        let scale = warp.scale(in: frame)
        let width = source.width, height = source.height
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let point = CGPoint(x: Double(column) + 0.5, y: Double(height - 1 - row) + 0.5)
                let p = warp.source(of: point, in: frame, scale: scale)
                for channel in 0..<3 {
                    let x = Double(p.x), y = Double(p.y)
                    let inside: Bool = x >= 0 && y >= 0 && x <= Double(width) && y <= Double(height)
                    pixels[(row * width + column) * 4 + channel] = inside ? sample(source, channel, at: p) : 0
                }
            }
        }
        return LinearImage(width: width, height: height, pixels: pixels)
    }

    /// One channel of `image` at a point, between the four nearest pixel centers, edges repeated.
    static func sample(_ image: LinearImage, _ channel: Int, at point: CGPoint) -> Float {
        let px = Double(point.x) - 0.5, py = Double(point.y) - 0.5
        let fx = px.rounded(.down), fy = py.rounded(.down)
        let tx = Float(px - fx), ty = Float(py - fy)
        func value(_ ix: Int, _ iy: Int) -> Float {
            let column = min(max(ix, 0), image.width - 1)
            // Rows are stored from the top; Core Image counts from the bottom.
            let row = image.height - 1 - min(max(iy, 0), image.height - 1)
            return image.pixels[(row * image.width + column) * 4 + channel]
        }
        let ix = Int(fx), iy = Int(fy)
        let lower = value(ix, iy) + (value(ix + 1, iy) - value(ix, iy)) * tx
        let upper = value(ix, iy + 1) + (value(ix + 1, iy + 1) - value(ix, iy + 1)) * tx
        return lower + (upper - lower) * ty
    }
}
