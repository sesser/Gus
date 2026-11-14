import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// What the color step does to one decode for one white balance: numbers
/// only, worked out in double precision by `CameraColor.transform`, applied
/// by `apply(to:)` with built-in Core Image filters and checked against a
/// CPU reference (`CameraColorReference` in the tests).
///
/// In order, for each pixel of the decode:
///
/// 1. each channel is multiplied by its `gain` (the white balance) and
///    clipped to 0 … 1, where 1 is the level at which every channel of the
///    sensor has saturated, so a blown highlight is neutral at any white
///    balance;
/// 2. `matrix` takes the result to the working space;
/// 3. the image is multiplied by `exposure` (the baseline exposure);
/// 4. `toneCurve` is applied to each channel (the baseline tone).
///
/// Steps 1 and 2 are absent (`gain` and `matrix` nil) for a decode that is
/// already in the working space: a file whose color data cannot be used,
/// which LibRaw renders with the camera's white balance itself.
///
/// A profile's hue, saturation and look tables are not applied
/// (`CameraProfile.HueSaturationTable`).
public struct CameraColorTransform: Sendable, Hashable {
    public var gain: SIMD3<Double>?
    public var matrix: Matrix3x3?
    public var exposure: Double
    public var toneCurve: [CameraProfile.TonePoint]?

    public init(gain: SIMD3<Double>? = nil, matrix: Matrix3x3? = nil, exposure: Double = 1,
                toneCurve: [CameraProfile.TonePoint]? = nil) {
        self.gain = gain
        self.matrix = matrix
        self.exposure = exposure
        self.toneCurve = toneCurve
    }

    /// The baseline look alone, for a decode already in the working space.
    public static func baseline(of profile: CameraProfile, fileExposure: Double = 0) -> CameraColorTransform {
        CameraColorTransform(exposure: pow(2, fileExposure + profile.baselineExposure), toneCurve: profile.toneCurve)
    }

    // MARK: The tone curve as a table

    /// The curve's table covers encoded values 0 … this (linear 4.95), as `ToneTable`'s does.
    static let curveDomainMaximum = 2.0
    static let curveEntryCount = 2048

    /// The sRGB transfer curve, continued above 1 with its own formula: the
    /// encoding of `AdjustmentRenderer.perceptualSpace`, in which curves are sampled.
    static func encoded(_ linear: Double) -> Double {
        linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }

    static func linear(_ encoded: Double) -> Double {
        encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }

    /// The tone curve at one linear value. Between its points the curve is
    /// a monotone cubic through the points' sRGB-encoded values (so its
    /// points are spaced as tones are seen); below 0 it is 0, and above 1
    /// it continues with slope one in the encoding, as `ToneTable` does.
    public static func toneValue(_ points: [CameraProfile.TonePoint], at value: Double) -> Double {
        linear(encodedToneValue(spline(points), at: encoded(max(value, 0))))
    }

    private static func spline(_ points: [CameraProfile.TonePoint]) -> MonotoneSpline {
        MonotoneSpline(points.map { CurvePoint(x: encoded(min(max($0.input, 0), 1)), y: encoded(min(max($0.output, 0), 1))) })
    }

    private static func encodedToneValue(_ spline: MonotoneSpline, at encoded: Double) -> Double {
        ToneTable.extend(encoded) { spline.value(at: $0) }
    }

    /// The curve sampled over the encoded domain, the same for the three channels.
    static func curveTable(_ points: [CameraProfile.TonePoint]) -> [Float] {
        let spline = spline(points)
        var table = [Float](repeating: 0, count: curveEntryCount * 3)
        var previous = -Double.infinity
        for index in 0..<curveEntryCount {
            let x = curveDomainMaximum * Double(index) / Double(curveEntryCount - 1)
            // Monotone, whatever the points.
            let value = max(encodedToneValue(spline, at: x), previous)
            previous = value
            for channel in 0..<3 { table[index * 3 + channel] = Float(value) }
        }
        return table
    }

    // MARK: Core Image

    /// The lazy graph of the transform over a decode.
    public func apply(to input: CIImage) -> CIImage {
        var image = input
        let extent = input.extent
        if let gain, let matrix {
            let balance = CIFilter.colorMatrix()
            balance.inputImage = image
            balance.rVector = CIVector(x: gain.x, y: 0, z: 0, w: 0)
            balance.gVector = CIVector(x: 0, y: gain.y, z: 0, w: 0)
            balance.bVector = CIVector(x: 0, y: 0, z: gain.z, w: 0)
            let clip = CIFilter.colorClamp()
            clip.inputImage = balance.outputImage
            clip.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
            clip.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
            let convert = CIFilter.colorMatrix()
            convert.inputImage = clip.outputImage
            let scaled = exposure * matrix
            convert.rVector = CIVector(x: scaled.r0.x, y: scaled.r0.y, z: scaled.r0.z, w: 0)
            convert.gVector = CIVector(x: scaled.r1.x, y: scaled.r1.y, z: scaled.r1.z, w: 0)
            convert.bVector = CIVector(x: scaled.r2.x, y: scaled.r2.y, z: scaled.r2.z, w: 0)
            image = convert.outputImage ?? image
        } else if exposure != 1 {
            let scale = CIFilter.colorMatrix()
            scale.inputImage = image
            scale.rVector = CIVector(x: exposure, y: 0, z: 0, w: 0)
            scale.gVector = CIVector(x: 0, y: exposure, z: 0, w: 0)
            scale.bVector = CIVector(x: 0, y: 0, z: exposure, w: 0)
            image = scale.outputImage ?? image
        }
        if let toneCurve, !toneCurve.isEmpty {
            let curve = CIFilter.colorCurves()
            curve.inputImage = image
            curve.curvesData = Self.curveTable(toneCurve).withUnsafeBytes { Data($0) }
            curve.curvesDomain = CIVector(x: 0, y: Self.curveDomainMaximum)
            curve.colorSpace = AdjustmentRenderer.perceptualSpace
            image = curve.outputImage ?? image
        }
        return extent.isInfinite ? image : image.cropped(to: extent)
    }
}

extension CameraColor {
    /// The transform for a decode whose channels LibRaw scaled by
    /// `channelScale` (the fraction of a channel's saturation level that is
    /// 1 in the decode's values; `LibRawDecoder.channelScale`), rendered
    /// with `balance`, or with the camera's own choice when it is nil.
    ///
    /// Nil when this file's color data cannot be used (`isUsable`).
    public func transform(for balance: ColorTemperature?, channelScale: SIMD3<Double>) -> CameraColorTransform? {
        guard isUsable, let asShotWhite, channelScale.min() > 0 else { return nil }
        let white = balance?.chromaticity ?? asShotWhite
        // As Shot is the camera's neutral itself, not its white point's round trip.
        guard let neutral = balance == nil ? asShotNeutral : neutral(for: white),
              let matrix = cameraToWorking(white: white) else { return nil }
        // The decode holds sensor values × channelScale; white-balanced values are sensor values / neutral.
        return CameraColorTransform(gain: SIMD3(1, 1, 1) / (channelScale * neutral), matrix: matrix,
                                    exposure: pow(2, baselineExposure + profile.baselineExposure),
                                    toneCurve: profile.toneCurve)
    }
}
