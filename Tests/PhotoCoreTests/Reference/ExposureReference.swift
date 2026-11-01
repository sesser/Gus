import Foundation
import PhotoFixtures

/// Exposure without Core Image: every component times 2^EV, in linear light
/// in the working space (extended linear Rec. 2020). Nothing is clipped;
/// alpha is kept.
enum ExposureReference {
    static func apply(_ image: LinearImage, ev: Double) -> LinearImage {
        let gain = Float(pow(2, ev))
        var pixels = image.pixels
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] *= gain
            pixels[i + 1] *= gain
            pixels[i + 2] *= gain
        }
        return LinearImage(width: image.width, height: image.height, pixels: pixels)
    }
}

/// Converting linear Rec. 2020 for output, without Core Image: a 3 × 3 matrix
/// to the output primaries (both D65, through CIE XYZ), then the output's
/// transfer curve. Display P3 and sRGB both use the sRGB curve.
enum OutputReference {
    /// Display P3 (D65) to CIE XYZ, from its primaries.
    static let displayP3ToXYZ: [[Double]] = [
        [0.486_570_948_648_216, 0.265_667_693_169_093, 0.198_217_285_234_363],
        [0.228_974_564_069_749, 0.691_738_521_836_506, 0.079_286_914_093_745],
        [0.000_000_000_000_000, 0.045_113_381_858_903, 1.043_944_368_900_976],
    ]

    static let rec2020ToDisplayP3 = multiply(invert(displayP3ToXYZ), ColorMath.rec2020ToXYZ)

    /// Encoded Display P3 for a linear Rec. 2020 color.
    static func displayP3(linearRec2020 rgb: SIMD3<Double>) -> SIMD3<Double> {
        let m = rec2020ToDisplayP3
        let linear = SIMD3(m[0][0] * rgb.x + m[0][1] * rgb.y + m[0][2] * rgb.z,
                           m[1][0] * rgb.x + m[1][1] * rgb.y + m[1][2] * rgb.z,
                           m[2][0] * rgb.x + m[2][1] * rgb.y + m[2][2] * rgb.z)
        return SIMD3(ColorMath.encode(linear.x), ColorMath.encode(linear.y), ColorMath.encode(linear.z))
    }

    static func multiply(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        (0..<3).map { r in (0..<3).map { c in (0..<3).reduce(0) { $0 + a[r][$1] * b[$1][c] } } }
    }

    static func invert(_ m: [[Double]]) -> [[Double]] {
        let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        let cofactors: [[Double]] = [
            [m[1][1] * m[2][2] - m[1][2] * m[2][1], m[0][2] * m[2][1] - m[0][1] * m[2][2], m[0][1] * m[1][2] - m[0][2] * m[1][1]],
            [m[1][2] * m[2][0] - m[1][0] * m[2][2], m[0][0] * m[2][2] - m[0][2] * m[2][0], m[0][2] * m[1][0] - m[0][0] * m[1][2]],
            [m[1][0] * m[2][1] - m[1][1] * m[2][0], m[0][1] * m[2][0] - m[0][0] * m[2][1], m[0][0] * m[1][1] - m[0][1] * m[1][0]],
        ]
        return cofactors.map { $0.map { $0 / det } }
    }
}
