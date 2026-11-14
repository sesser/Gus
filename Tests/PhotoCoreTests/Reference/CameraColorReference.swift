import Foundation

/// The color step after a LibRaw decode, without Core Image and without
/// PhotoCore's camera color types: one pixel at a time, in double precision,
/// written from the Adobe DNG Specification 1.7.1, chapter 6 ("Mapping
/// Camera Color Space to CIE XYZ Space"), with plain arrays.
///
/// What the reference is given from outside: a white point's chromaticity
/// and its correlated color temperature (`ColorTemperature`, checked on its
/// own against known illuminants and the system's RAW decoder), and the
/// tone curve as a function.
enum CameraColorReference {
    typealias Matrix = [[Double]]

    /// A camera as a DNG describes it.
    struct Camera {
        /// One or two calibrations, by rising temperature of their light.
        var calibrations: [(kelvin: Double, colorMatrix: Matrix, forwardMatrix: Matrix?)]
        /// `AsShotNeutral`.
        var asShotNeutral: [Double]
        /// `BaselineExposure` plus the profile's, in stops.
        var exposure: Double = 0
    }

    /// The part of the white level at which the decoder counts a channel as saturated (`LibRawDecoder.whiteMargin`).
    static let whiteMargin = 0.99

    // MARK: Small matrix arithmetic

    static func times(_ m: Matrix, _ v: [Double]) -> [Double] {
        m.map { row in zip(row, v).map(*).reduce(0, +) }
    }

    static func mix(_ a: Matrix, _ b: Matrix, weightOfFirst g: Double) -> Matrix {
        zip(a, b).map { rowA, rowB in zip(rowA, rowB).map { g * $0 + (1 - g) * $1 } }
    }

    static func diagonal(_ d: [Double]) -> Matrix {
        [[d[0], 0, 0], [0, d[1], 0], [0, 0, d[2]]]
    }

    static func xyz(x: Double, y: Double) -> [Double] {
        [x / y, 1, (1 - x - y) / y]
    }

    // MARK: The specification's steps

    /// "If the white balance color temperature is between the two
    /// calibration illuminants, the weight is by inverse correlated color
    /// temperature; outside them, the nearer calibration is used."
    static func weightOfFirst(_ camera: Camera, kelvin: Double) -> Double {
        guard camera.calibrations.count == 2 else { return 1 }
        let low = camera.calibrations[0].kelvin, high = camera.calibrations[1].kelvin
        if kelvin <= low { return 1 }
        if kelvin >= high { return 0 }
        return (1 / kelvin - 1 / high) / (1 / low - 1 / high)
    }

    /// XYZtoCamera = AB × CC × CM, with AB and CC identity here.
    static func xyzToCamera(_ camera: Camera, kelvin: Double) -> Matrix {
        guard camera.calibrations.count == 2 else { return camera.calibrations[0].colorMatrix }
        return mix(camera.calibrations[0].colorMatrix, camera.calibrations[1].colorMatrix,
                   weightOfFirst: weightOfFirst(camera, kelvin: kelvin))
    }

    /// "Translating White Balance xy Coordinates to Camera Neutral
    /// Coordinates": CameraNeutral = XYZtoCamera × XYZ, here scaled so its
    /// largest component is 1.
    static func neutral(_ camera: Camera, white: (x: Double, y: Double), kelvin: Double) -> [Double] {
        let neutral = times(xyzToCamera(camera, kelvin: kelvin), xyz(x: white.x, y: white.y))
        let largest = neutral.max() ?? 1
        return neutral.map { $0 / largest }
    }

    /// "Translating Camera Neutral Coordinates to White Balance xy
    /// Coordinates": guess a white point, invert the matrix for its
    /// temperature, and repeat until the white point settles.
    static func white(_ camera: Camera, ofNeutral neutral: [Double],
                      kelvinOf: ((x: Double, y: Double)) -> Double) -> (x: Double, y: Double) {
        var white = (x: 0.3457, y: 0.3585)
        for _ in 0..<60 {
            let xyz = times(OutputReference.invert(xyzToCamera(camera, kelvin: kelvinOf(white))), neutral)
            let sum = xyz.reduce(0, +)
            let next = (x: xyz[0] / sum, y: xyz[1] / sum)
            let moved = abs(next.x - white.x) + abs(next.y - white.y)
            white = next
            if moved < 1e-12 { break }
        }
        return white
    }

    /// The linear Bradford adaptation between two whites given as XYZ.
    static func bradford(from source: [Double], to destination: [Double]) -> Matrix {
        let cone: Matrix = [[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367], [0.0389, -0.0685, 1.0296]]
        let a = times(cone, source), b = times(cone, destination)
        return OutputReference.multiply(OutputReference.invert(cone),
                                        OutputReference.multiply(diagonal([b[0] / a[0], b[1] / a[1], b[2] / a[2]]), cone))
    }

    static let d50 = xyz(x: 0.3457, y: 0.3585)
    static let d65 = xyz(x: 0.3127, y: 0.3290)

    /// "Camera to XYZ (D50) Transform", for camera values already divided
    /// by the neutral (white-balanced, a neutral is 1, 1, 1):
    ///
    /// - with forward matrices: CameraToXYZ_D50 = FM × D × Inverse(AB × CC),
    ///   D the inverse of the reference neutral as a diagonal matrix. On
    ///   white-balanced values, with AB and CC identity, that is FM itself;
    /// - otherwise CameraToXYZ_D50 = CA × Inverse(XYZtoCamera), CA the
    ///   Bradford adaptation from the white point to D50; scaled so that a
    ///   saturated neutral is the connection space's white (Y = 1).
    static func balancedCameraToD50(_ camera: Camera, white: (x: Double, y: Double), kelvin: Double) -> Matrix {
        if camera.calibrations.allSatisfy({ $0.forwardMatrix != nil }) {
            let first = camera.calibrations[0].forwardMatrix!
            guard camera.calibrations.count == 2 else { return first }
            return mix(first, camera.calibrations[1].forwardMatrix!, weightOfFirst: weightOfFirst(camera, kelvin: kelvin))
        }
        let neutral = neutral(camera, white: white, kelvin: kelvin)
        let cameraToXYZ = OutputReference.invert(xyzToCamera(camera, kelvin: kelvin))
        let adapted = OutputReference.multiply(bradford(from: xyz(x: white.x, y: white.y), to: d50),
                                               OutputReference.multiply(cameraToXYZ, diagonal(neutral)))
        let luminance = times(adapted, [1, 1, 1])[1]
        return adapted.map { $0.map { $0 / luminance } }
    }

    /// XYZ with a D50 white to the working space: adapted to D65, then to
    /// linear Rec. 2020 (`ColorMath.rec2020ToXYZ`, from ITU-R BT.2020).
    static let d50ToWorking = OutputReference.multiply(OutputReference.invert(ColorMath.rec2020ToXYZ),
                                                       bradford(from: d50, to: d65))

    /// What is the same for every pixel of one decode and one white balance.
    struct Prepared {
        /// What LibRaw multiplied each channel's sensor value by.
        var decodeMultipliers: [Double]
        /// The camera neutral to balance for.
        var neutral: [Double]
        /// White-balanced, clipped camera values to the working space.
        var matrix: Matrix
        /// 2 to the power of the exposure in stops.
        var gain: Double

        /// One pixel of the decode in the working space.
        ///
        /// - Parameters:
        ///   - decoded: The decode's value, 0 … 1.
        ///   - curve: The tone curve, linear in and out; nil for none.
        func render(_ decoded: [Double], curve: ((Double) -> Double)? = nil) -> [Double] {
            // The sensor's values, 1 at the white level.
            let sensor = (0..<3).map { decoded[$0] / decodeMultipliers[$0] }
            // White balance, then clip at white: saturation is `whiteMargin` of the white level.
            let balanced = (0..<3).map { min(max(sensor[$0] / (neutral[$0] * CameraColorReference.whiteMargin), 0), 1) }
            return CameraColorReference.times(matrix, balanced).map { value in
                let exposed = value * gain
                return curve.map { $0(exposed) } ?? exposed
            }
        }
    }

    /// - Parameters:
    ///   - white: The white point to balance for, with its temperature.
    ///   - asShot: Balance for the camera's neutral itself (As Shot), `white` being its white point.
    ///
    /// LibRaw multiplied each channel's sensor value by the smallest
    /// component of the as-shot neutral over that channel's (so the as-shot
    /// white is equal in the three, and no channel passes its saturation).
    static func prepare(_ camera: Camera, white: (x: Double, y: Double), kelvin: Double, asShot: Bool = false) -> Prepared {
        let asShotLargest = camera.asShotNeutral.max() ?? 1
        let asShotNeutral = camera.asShotNeutral.map { $0 / asShotLargest }
        let smallest = asShotNeutral.min() ?? 1
        return Prepared(decodeMultipliers: asShotNeutral.map { smallest / $0 },
                        neutral: asShot ? asShotNeutral : neutral(camera, white: white, kelvin: kelvin),
                        matrix: OutputReference.multiply(d50ToWorking, balancedCameraToD50(camera, white: white, kelvin: kelvin)),
                        gain: pow(2, camera.exposure))
    }
}
