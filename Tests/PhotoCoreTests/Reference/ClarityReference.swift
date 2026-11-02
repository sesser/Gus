import Foundation
import PhotoFixtures

/// Clarity without Core Image: an unsharp mask in the perceptual encoding
/// (Rec. 2020, sRGB curve), p + i · (p − G(p)), where G is a Gaussian of
/// standard deviation 1.2 % of the long edge, taken out to 6σ (its tails
/// below 10⁻⁸), edges repeated (`BlurReference`), and i = 0.6 × amount / 100.
/// Negative amounts blend toward the blur by the same formula. Alpha is kept.
/// `apply` returns the result in the perceptual encoding, where the
/// tolerance is stated.
enum ClarityReference {
    static func sigma(width: Int, height: Int) -> Double {
        Double(max(width, height)) * 0.012
    }

    static let reach = 6.0

    static func apply(_ image: LinearImage, amount: Double) -> LinearImage {
        let intensity = Float(amount / 100 * 0.6)
        var encoded = image.pixels
        for i in encoded.indices where i % 4 != 3 {
            encoded[i] = Float(ColorMath.encode(Double(encoded[i])))
        }
        let perceptual = LinearImage(width: image.width, height: image.height, pixels: encoded)
        let blurred = BlurReference.apply(perceptual, sigma: sigma(width: image.width, height: image.height),
                                          reach: reach)
        var pixels = image.pixels
        for i in pixels.indices where i % 4 != 3 {
            let p = encoded[i]
            pixels[i] = p + intensity * (p - blurred.pixels[i])
        }
        return LinearImage(width: image.width, height: image.height, pixels: pixels)
    }
}
