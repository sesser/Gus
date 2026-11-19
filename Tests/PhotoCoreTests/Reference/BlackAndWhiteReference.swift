import Foundation
import PhotoFixtures
@testable import PhotoCore

/// The Black & White conversion without Core Image (issue #218), in the
/// working space (extended linear Rec. 2020):
///
/// 1. each filter's transmittance per channel (the module's table, data)
///    raised to its amount / 100, filters multiplied together;
/// 2. the Rec. 709 luminance weights times that, normalized to sum to 1;
/// 3. every channel of the output the weighted sum of the input's red, green
///    and blue. Nothing is clipped; alpha is kept.
///
/// Written apart from `BlackAndWhite.weights`, so the module's math is
/// checked, not repeated.
enum BlackAndWhiteReference {
    static let rec709 = (r: 0.2126, g: 0.7152, b: 0.0722)

    static func weights(_ amounts: [BlackAndWhite.Filter: Double]) -> (r: Double, g: Double, b: Double) {
        var t = (r: 1.0, g: 1.0, b: 1.0)
        for (filter, amount) in amounts {
            let strength = amount / 100
            let filterT = filter.transmittance
            t.r *= exp(strength * log(filterT.x))
            t.g *= exp(strength * log(filterT.y))
            t.b *= exp(strength * log(filterT.z))
        }
        let r = rec709.r * t.r, g = rec709.g * t.g, b = rec709.b * t.b
        let sum = r + g + b
        return (r / sum, g / sum, b / sum)
    }

    static func gray(_ rgb: SIMD3<Double>, _ amounts: [BlackAndWhite.Filter: Double]) -> Double {
        let w = weights(amounts)
        return w.r * rgb.x + w.g * rgb.y + w.b * rgb.z
    }

    static func apply(_ image: LinearImage, _ amounts: [BlackAndWhite.Filter: Double]) -> LinearImage {
        let w = weights(amounts)
        var pixels = image.pixels
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let y = Float(w.r * Double(pixels[i]) + w.g * Double(pixels[i + 1]) + w.b * Double(pixels[i + 2]))
            pixels[i] = y
            pixels[i + 1] = y
            pixels[i + 2] = y
        }
        return LinearImage(width: image.width, height: image.height, pixels: pixels)
    }
}
