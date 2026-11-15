import CoreImage
import Foundation

/// The color step of one LibRaw decode: what turns its linear image into
/// the photo for a white balance. Kept with the decode, so a new white
/// balance is a new graph over the same pixels, never a new decode.
public struct CameraColorStep: Sendable, Hashable {
    /// The camera's color for the file; nil when it cannot be used, and the
    /// decode is LibRaw's own rendering in the working space with the
    /// camera's white balance: white balance cannot be changed then (R14).
    public var color: CameraColor?
    /// What LibRaw multiplied each channel's sensor values by, as the part
    /// of a channel's saturation level that is 1 in the decode's values.
    public var channelScale: SIMD3<Double>
    /// The file's own exposure in stops (a DNG's baseline exposure, what a
    /// Fujifilm camera held back), for a file whose color data cannot be
    /// used: it still opens as bright as the file asks. With color data it
    /// is `color.baselineExposure`, the same number, and that is used.
    public var fileExposure: Double

    public init(color: CameraColor?, channelScale: SIMD3<Double> = SIMD3(1, 1, 1), fileExposure: Double = 0) {
        self.color = color
        self.channelScale = channelScale
        self.fileExposure = fileExposure
    }

    /// As Shot for the White Balance group; nil when white balance cannot be changed.
    public var asShot: ColorTemperature? { color?.asShot }

    /// A Kelvin and tint as the step renders them: each within
    /// `WhiteBalance`'s ranges (2000 to 50000 K, ±150), the ranges of the
    /// sliders. A number past an end renders as the end. The White Balance
    /// group shows and stores a LibRaw photo's as-shot values through this
    /// (`WhiteBalanceControls`), so the sliders and the render agree for a
    /// camera white outside the ranges too.
    public static func rendered(_ balance: ColorTemperature) -> ColorTemperature {
        ColorTemperature(
            kelvin: min(max(balance.kelvin, WhiteBalance.temperatureRange.lowerBound), WhiteBalance.temperatureRange.upperBound),
            tint: min(max(balance.tint, WhiteBalance.tintRange.lowerBound), WhiteBalance.tintRange.upperBound))
    }

    /// The transform for a stack's Kelvin and tint (`RAWDecodeSettings`'s:
    /// nil for the camera's own; one of them alone takes the other from
    /// the camera's), each kept within `WhiteBalance`'s ranges (`rendered`).
    /// Only with neither is the camera's own neutral used as it is: As Shot
    /// is never moved into the ranges.
    public func transform(temperature: Double?, tint: Double?) -> CameraColorTransform {
        guard let color, let asShot = color.asShot else {
            return .baseline(of: .builtIn(calibrations: []), fileExposure: color?.baselineExposure ?? fileExposure)
        }
        var balance: ColorTemperature?
        if temperature != nil || tint != nil {
            balance = Self.rendered(ColorTemperature(kelvin: temperature ?? asShot.kelvin, tint: tint ?? asShot.tint))
        }
        // A white balance the camera's matrix has no answer for renders as shot.
        return color.transform(for: balance, channelScale: channelScale)
            ?? color.transform(for: nil, channelScale: channelScale)
            ?? .baseline(of: color.profile, fileExposure: color.baselineExposure)
    }

    public func apply(to linear: CIImage, temperature: Double?, tint: Double?) -> CIImage {
        transform(temperature: temperature, tint: tint).apply(to: linear)
    }

    /// With the white balance of a stack's decode settings; the other settings are the system decoder's.
    public func apply(to linear: CIImage, settings: RAWDecodeSettings) -> CIImage {
        apply(to: linear, temperature: settings.temperature.map(Double.init), tint: settings.tint.map(Double.init))
    }
}

/// The look a LibRaw photo starts from: a baseline exposure and tone curve
/// close to what the system's RAW decoder gives the raws it reads, so photos
/// of the two decoders sit near each other in one library (issue #170, R6;
/// the owner's ruling: match the system decoder's look). Part of the decode,
/// not a stored edit: Exposure and Tone start at their defaults on top of it.
///
/// **Measured, not designed** (`BaselineLookMeasurementTests`, on macOS
/// 27.2 with decoder version 8, 2026-11-14, on nine raws both decoders
/// read: a public uncompressed Fujifilm X-E3 file, four X-T3 files, and one
/// each of a Sony ILCE-7M3, a Canon EOS 5D Mark II, an Olympus E-M5 Mark III
/// and a Panasonic DMC-ZS100):
///
/// - The system decoder's default render is its render with `boostAmount`
///   0 through one tone curve, the same for every camera tried between
///   0.25 and 0.62 of the sRGB-encoded range to ±0.002 (the Olympus has
///   less shadow contrast; two files differ in their highlights). The curve
///   here is the middle of the nine.
/// - Its boost-0 render is LibRaw's linear image times a gain, less a small
///   offset: system = gain × LibRaw − offset. For the X-E3 file: 1.050
///   (0.070 EV) and 0.0027. The four X-T3 files: 0.98 to 1.10 (0.063 EV in
///   the mean) and 0.0028 to 0.0032. The offset is folded into the curve
///   below, which is why it reaches 0 just above black.
///
/// **One look for every camera.** The gain is the system decoder's own
/// baseline exposure for each camera, which no file states: 0.07 EV for the
/// X-E3 and the Panasonic, 0.33 for the Sony, 0.42 for the Olympus and 0.52
/// for the Canon. With the X-E3's, a LibRaw photo from one of the last
/// three would open a quarter to half a stop darker than the system
/// decoder would show it. What a file does state is added: a DNG's baseline
/// exposure, and the exposure a Fujifilm camera held back for its dynamic
/// range setting (`CameraColor.baselineExposure`).
public enum BaselineLook {
    /// Stops.
    public static let exposure = 0.07

    /// The tone curve's knots in the sRGB encoding, input then output.
    static let encodedKnots: [(Double, Double)] = [
        (0.00000, 0.0000), (0.03125, 0.0000), (0.06250, 0.0247), (0.09375, 0.0645), (0.12500, 0.1052),
        (0.15625, 0.1480), (0.18750, 0.1939), (0.21875, 0.2429), (0.25000, 0.2953), (0.28125, 0.3495),
        (0.31250, 0.4053), (0.34375, 0.4613), (0.37500, 0.5156), (0.40625, 0.5670), (0.43750, 0.6154),
        (0.46875, 0.6600), (0.50000, 0.7002), (0.53125, 0.7378), (0.56250, 0.7716), (0.59375, 0.8023),
        (0.62500, 0.8292), (0.65625, 0.8538), (0.68750, 0.8763), (0.71875, 0.8967), (0.75000, 0.9147),
        (0.78125, 0.9318), (0.81250, 0.9464), (0.84375, 0.9596), (0.87500, 0.9706), (0.90625, 0.9801),
        (0.93750, 0.9879), (0.96875, 0.9943), (1.00000, 1.0000),
    ]

    public static let toneCurve: [CameraProfile.TonePoint]? = encodedKnots.map {
        CameraProfile.TonePoint(CameraColorTransform.linear($0.0), CameraColorTransform.linear($0.1))
    }
}

extension CameraProfile {
    /// The one profile this build has: the given calibrations (LibRaw's
    /// matrix for the camera, or a DNG's own) with `BaselineLook`.
    public static func builtIn(calibrations: [Calibration]) -> CameraProfile {
        CameraProfile(name: "Built-in", calibrations: calibrations, toneCurve: BaselineLook.toneCurve,
                      baselineExposure: BaselineLook.exposure)
    }
}
