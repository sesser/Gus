import Foundation

/// Plain Swift color math, without Core Image: the reference the renderer's
/// color handling is checked against.
///
/// The pipeline works in extended linear Rec. 2020 (`RenderEngine.workingColorSpace`).
/// Curves, cubes, clarity, sharpening and grain encode with the sRGB transfer
/// curve over the same Rec. 2020 primaries (`AdjustmentRenderer.perceptualSpace`).
enum ColorMath {
    /// sRGB transfer curve, linear to encoded. Odd-symmetric, so negative
    /// (out of gamut) values keep their sign.
    static func encode(_ linear: Double) -> Double {
        let magnitude = abs(linear)
        let encoded = magnitude <= 0.0031308 ? magnitude * 12.92 : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
        return linear < 0 ? -encoded : encoded
    }

    /// sRGB transfer curve, encoded to linear.
    static func decode(_ encoded: Double) -> Double {
        let magnitude = abs(encoded)
        let linear = magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
        return encoded < 0 ? -linear : linear
    }

    /// Linear Rec. 2020 to CIE XYZ (D65), from ITU-R BT.2020's primaries.
    static let rec2020ToXYZ: [[Double]] = [
        [0.636_958_048_301_291, 0.144_616_903_586_208, 0.168_880_975_164_172],
        [0.262_700_212_011_267, 0.677_998_071_518_871, 0.059_301_716_469_862],
        [0.000_000_000_000_000, 0.028_072_693_049_087, 1.060_985_057_710_791],
    ]

    /// OkLab from CIE XYZ (D65): Björn Ottosson's published definition
    /// ("A perceptual color space for image processing", 2020). L is 0 … 1.
    static func okLab(xyz: SIMD3<Double>) -> SIMD3<Double> {
        let l = 0.818_933_010_1 * xyz.x + 0.361_866_742_4 * xyz.y - 0.128_859_713_7 * xyz.z
        let m = 0.032_984_543_6 * xyz.x + 0.929_311_871_5 * xyz.y + 0.036_145_638_7 * xyz.z
        let s = 0.048_200_301_8 * xyz.x + 0.264_366_269_1 * xyz.y + 0.633_851_707_0 * xyz.z
        let l3 = cbrt(l), m3 = cbrt(m), s3 = cbrt(s)
        return SIMD3(0.210_454_255_3 * l3 + 0.793_617_785_0 * m3 - 0.004_072_046_8 * s3,
                     1.977_998_495_1 * l3 - 2.428_592_205_0 * m3 + 0.450_593_709_9 * s3,
                     0.025_904_037_1 * l3 + 0.782_771_766_2 * m3 - 0.808_675_766_0 * s3)
    }

    static func okLab(linearRec2020 rgb: SIMD3<Double>) -> SIMD3<Double> {
        let m = rec2020ToXYZ
        return okLab(xyz: SIMD3(m[0][0] * rgb.x + m[0][1] * rgb.y + m[0][2] * rgb.z,
                                m[1][0] * rgb.x + m[1][1] * rgb.y + m[1][2] * rgb.z,
                                m[2][0] * rgb.x + m[2][1] * rgb.y + m[2][2] * rgb.z))
    }

    /// OkLab of a color in the perceptual encoding (Rec. 2020, sRGB curve).
    static func okLab(perceptualRec2020 rgb: SIMD3<Double>) -> SIMD3<Double> {
        okLab(linearRec2020: SIMD3(decode(rgb.x), decode(rgb.y), decode(rgb.z)))
    }
}
