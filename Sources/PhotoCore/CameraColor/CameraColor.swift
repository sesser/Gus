import Foundation

/// A camera's color as one file gives it: the profile, the neutral the
/// camera chose for the shot, and the per-camera calibration. Turns a white
/// balance (Kelvin and tint) into what the color step applies to LibRaw's
/// camera-space image (`CameraColorTransform`).
///
/// The method is the DNG specification's (Adobe DNG Specification 1.7.1,
/// chapter 6, "Mapping Camera Color Space to CIE XYZ Space"), written from
/// the specification (`THIRD_PARTY_NOTICES.md`):
///
/// - a white point's camera neutral is XYZtoCamera × its XYZ, with
///   XYZtoCamera = calibration × ColorMatrix read between the profile's two
///   lights by the white point's temperature;
/// - a camera neutral's white point is found by repeating that backwards
///   until it settles (the matrix depends on the answer);
/// - camera values are divided by the neutral (the largest component of
///   which is 1, so no channel is reduced), clipped at white, and taken to
///   XYZ with a D50 white either by the forward matrix or by the inverse of
///   XYZtoCamera followed by a linear Bradford adaptation from the white
///   point to D50.
///
/// **Accuracy with one calibration.** A file that is not a DNG has one
/// matrix, LibRaw's for the camera under D65. It is used at every
/// temperature, so the white point is exact (a neutral comes out neutral at
/// any Kelvin) but colors away from neutral drift the further the light is
/// from daylight: under tungsten, the reds and oranges a second (tungsten)
/// matrix would correct stay as the daylight matrix renders them. A DNG
/// read through LibRaw brings both of its matrices and has no such limit.
public struct CameraColor: Sendable, Hashable {
    public var profile: CameraProfile
    /// Camera RGB of a neutral under the light the camera chose for the
    /// shot, its largest component 1 (a DNG's `AsShotNeutral`; for other
    /// files the reciprocal of the camera's white balance coefficients).
    public var asShotNeutral: SIMD3<Double>
    /// `AnalogBalance` × `CameraCalibration`, per calibration of the profile
    /// or one for all; identity for files without them.
    public var calibration: [Matrix3x3]
    /// The file's own baseline exposure in stops (a DNG's `BaselineExposure`; 0 otherwise).
    public var baselineExposure: Double

    public init(profile: CameraProfile, asShotNeutral: SIMD3<Double>, calibration: [Matrix3x3] = [],
                baselineExposure: Double = 0) {
        self.profile = profile
        let largest = asShotNeutral.max()
        self.asShotNeutral = largest > 0 ? asShotNeutral / largest : asShotNeutral
        self.calibration = calibration
        self.baselineExposure = baselineExposure
    }

    /// The same camera and shot rendered through another profile (#89's seam).
    public func with(profile: CameraProfile) -> CameraColor {
        var copy = self
        copy.profile = profile
        return copy
    }

    /// White balance can be worked out for this file: the profile is usable
    /// and the neutral is a color (every component above 0, finite) that
    /// has a white point.
    public var isUsable: Bool {
        profile.isUsable && asShotNeutral.min() > 0 && asShotNeutral.max().isFinite && asShotWhite != nil
    }

    // MARK: Matrices

    /// `AnalogBalance` × `CameraCalibration` for a white point of `kelvin`.
    func calibration(at kelvin: Double) -> Matrix3x3 {
        guard let first = calibration.first else { return .identity }
        guard calibration.count >= 2, profile.calibrations.count >= 2, let last = calibration.last else { return first }
        let weight = profile.weightOfFirst(at: kelvin)
        return weight * first + (1 - weight) * last
    }

    /// XYZ to this camera's RGB for a white point of `kelvin`.
    func xyzToCamera(at kelvin: Double) -> Matrix3x3 {
        calibration(at: kelvin) * profile.colorMatrix(at: kelvin)
    }

    // MARK: White points and neutrals

    /// Camera RGB of a neutral under `white`, its largest component 1. A
    /// light of which the matrix says the camera records nothing in a
    /// channel, or less than nothing (far from any real light), has that
    /// component at a thousandth, so every white balance renders. Nil only
    /// when no channel records it.
    public func neutral(for white: Chromaticity) -> SIMD3<Double>? {
        let neutral = xyzToCamera(at: ColorTemperature(white).kelvin) * white.xyz
        let largest = neutral.max()
        guard largest.isFinite, largest > 0 else { return nil }
        return (neutral / largest).clamped(lowerBound: SIMD3(repeating: 0.001), upperBound: SIMD3(repeating: 1))
    }

    /// The white point a camera neutral stands for.
    public func white(ofNeutral neutral: SIMD3<Double>) -> Chromaticity? {
        var white = Chromaticity.d50
        for pass in 0..<30 {
            guard let inverse = xyzToCamera(at: ColorTemperature(white).kelvin).inverse,
                  let next = Chromaticity(xyz: inverse * neutral), next.x.isFinite, next.y > 0 else { return nil }
            let moved = abs(next.x - white.x) + abs(next.y - white.y)
            // Two matrices can leave the answer alternating between two points: the last pass takes the middle.
            white = pass == 29 ? Chromaticity(x: (white.x + next.x) / 2, y: (white.y + next.y) / 2) : next
            if moved < 1e-7 { break }
        }
        return white
    }

    /// The white point of the camera's own choice for the shot.
    public var asShotWhite: Chromaticity? { white(ofNeutral: asShotNeutral) }

    /// As Shot as the White Balance group shows it. Nil when the file's
    /// color data gives none (`isUsable`).
    public var asShot: ColorTemperature? { asShotWhite.map(ColorTemperature.init) }

    /// White-balanced camera RGB (a neutral under `white` is 1, 1, 1) to
    /// the working space, in which that neutral is 1, 1, 1 too.
    public func cameraToWorking(white: Chromaticity) -> Matrix3x3? {
        let kelvin = ColorTemperature(white).kelvin
        guard let neutral = neutral(for: white) else { return nil }
        let toD50: Matrix3x3
        if let forward = profile.forwardMatrix(at: kelvin) {
            // Reference neutral = inverse(calibration) × neutral; D undoes it.
            guard let toReference = calibration(at: kelvin).inverse else { return nil }
            let reference = toReference * neutral
            guard reference.min() > 0 else { return nil }
            toD50 = forward * Matrix3x3.diagonal(SIMD3(1, 1, 1) / reference) * toReference * Matrix3x3.diagonal(neutral)
        } else {
            guard let toXYZ = xyzToCamera(at: kelvin).inverse else { return nil }
            let adapted = ChromaticAdaptation.bradford(from: white.xyz, to: Chromaticity.d50.xyz) * toXYZ * Matrix3x3.diagonal(neutral)
            // A saturated neutral is the white of the connection space: Y = 1.
            let luminance = (adapted * SIMD3(1, 1, 1)).y
            guard luminance.isFinite, luminance > 0 else { return nil }
            toD50 = (1 / luminance) * adapted
        }
        let matrix = WorkingSpace.fromD50 * toD50
        return matrix.isFinite ? matrix : nil
    }
}

/// Linear Bradford chromatic adaptation between two whites given as XYZ.
public enum ChromaticAdaptation {
    static let cone = Matrix3x3([0.8951, 0.2664, -0.1614,
                                 -0.7502, 1.7135, 0.0367,
                                 0.0389, -0.0685, 1.0296])

    public static func bradford(from source: SIMD3<Double>, to destination: SIMD3<Double>) -> Matrix3x3 {
        let from = cone * source, to = cone * destination
        // The cone matrix has an inverse; a white without light in a cone response has no adaptation.
        guard let back = cone.inverse, from.x != 0, from.y != 0, from.z != 0 else { return .identity }
        return back * Matrix3x3.diagonal(to / from) * cone
    }
}

/// The working space (linear Rec. 2020, D65 white) against XYZ.
public enum WorkingSpace {
    /// Linear Rec. 2020 to XYZ (D65), from the primaries and the white.
    public static let toXYZ: Matrix3x3 = {
        func xyz(_ x: Double, _ y: Double) -> SIMD3<Double> { Chromaticity(x: x, y: y).xyz }
        let primaries = Matrix3x3(columns: xyz(0.708, 0.292), xyz(0.170, 0.797), xyz(0.131, 0.046))
        // Scale each primary so that 1, 1, 1 is the white.
        let scale = (primaries.inverse ?? .identity) * Chromaticity.d65.xyz
        return primaries * Matrix3x3.diagonal(scale)
    }()

    /// XYZ with a D50 white to linear Rec. 2020: adapted to D65 first.
    public static let fromD50: Matrix3x3 = {
        (toXYZ.inverse ?? .identity) * ChromaticAdaptation.bradford(from: Chromaticity.d50.xyz, to: Chromaticity.d65.xyz)
    }()
}
