import Foundation
import PhotoFixtures

/// A Gaussian blur without Core Image or Metal: taps exp(−i² / 2σ²) for
/// |i| ≤ ceil(3σ), normalized to sum to one, applied along rows then
/// columns, with edge pixels repeated beyond the image. Sums in Double.
enum BlurReference {
    static func weights(sigma: Double) -> [Double] {
        let radius = Int((3 * sigma).rounded(.up))
        let raw = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let sum = raw.reduce(0, +)
        return raw.map { $0 / sum }
    }

    static func apply(_ image: LinearImage, sigma: Double) -> LinearImage {
        let weights = weights(sigma: sigma)
        let radius = weights.count / 2
        let width = image.width, height = image.height
        // Tests are built without optimization: buffer pointers keep this fast enough.
        func pass(_ input: [Double], horizontal: Bool) -> [Double] {
            var output = input
            input.withUnsafeBufferPointer { source in
                output.withUnsafeMutableBufferPointer { destination in
                    for y in 0..<height {
                        for x in 0..<width {
                            var sum = SIMD3<Double>.zero
                            for i in -radius...radius {
                                let sx = horizontal ? min(max(x + i, 0), width - 1) : x
                                let sy = horizontal ? y : min(max(y + i, 0), height - 1)
                                let index = (sy * width + sx) * 4
                                sum += SIMD3(source[index], source[index + 1], source[index + 2]) * weights[i + radius]
                            }
                            let index = (y * width + x) * 4
                            destination[index] = sum.x
                            destination[index + 1] = sum.y
                            destination[index + 2] = sum.z
                        }
                    }
                }
            }
            return output
        }
        let blurred = pass(pass(image.pixels.map(Double.init), horizontal: true), horizontal: false)
        return LinearImage(width: width, height: height, pixels: blurred.map(Float.init))
    }
}
