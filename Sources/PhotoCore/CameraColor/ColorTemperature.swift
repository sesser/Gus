import Foundation

/// A white point as CIE 1931 chromaticity coordinates.
public struct Chromaticity: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// The white of the profile connection space (and of a DNG's forward matrices).
    public static let d50 = Chromaticity(x: 0.3457, y: 0.3585)
    /// The white of the working space (Rec. 2020).
    public static let d65 = Chromaticity(x: 0.3127, y: 0.3290)

    /// XYZ with Y = 1.
    public var xyz: SIMD3<Double> {
        SIMD3(x / y, 1, (1 - x - y) / y)
    }

    /// Nil for a color without a chromaticity (no light, or values that are not finite).
    public init?(xyz: SIMD3<Double>) {
        let sum = xyz.sum()
        guard sum.isFinite, sum > 0 else { return nil }
        self.init(x: xyz.x / sum, y: xyz.y / sum)
    }
}

/// A white point as a correlated color temperature and a tint, the two
/// numbers of the White Balance group: Kelvin of the black body the light is
/// nearest to, and how far it lies from that body's color toward green (+)
/// or magenta (−).
///
/// Robertson's method (A. R. Robertson, "Computation of Correlated Color
/// Temperature and Distribution Temperature", J. Opt. Soc. Am. 58, 1968; the
/// isotherms as tabulated in Wyszecki and Stiles, "Color Science", 2nd
/// edition): 31 lines of constant temperature in the CIE 1960 (u, v) diagram,
/// a color's temperature read between the two lines it lies between. The tint
/// is the color's distance from the black body's along the line, times 3000,
/// the scale of the Adobe DNG SDK (`dng_temperature`), written again here.
/// It is also the scale of the system's RAW decoder: for a raw it reads,
/// `CIRAWFilter` reports the same numbers for the same chromaticity
/// (`ColorTemperatureTests` compares them), so one stored Kelvin and tint
/// means the same light to both decoders (`THIRD_PARTY_NOTICES.md`).
public struct ColorTemperature: Sendable, Hashable {
    public var kelvin: Double
    public var tint: Double

    public init(kelvin: Double, tint: Double = 0) {
        self.kelvin = kelvin
        self.tint = tint
    }

    /// uv distance per unit of tint; a positive tint is toward green.
    static let tintScale = -3000.0

    /// One isotherm: reciprocal temperature in mired, the black body's
    /// (u, v) there and the line's slope.
    struct Isotherm {
        var mired: Double
        var u: Double
        var v: Double
        var slope: Double

        /// The line's direction, of length one.
        var direction: SIMD2<Double> {
            let length = (1 + slope * slope).squareRoot()
            return SIMD2(1 / length, slope / length)
        }
    }

    static let isotherms: [Isotherm] = [
        Isotherm(mired: 0, u: 0.18006, v: 0.26352, slope: -0.24341),
        Isotherm(mired: 10, u: 0.18066, v: 0.26589, slope: -0.25479),
        Isotherm(mired: 20, u: 0.18133, v: 0.26846, slope: -0.26876),
        Isotherm(mired: 30, u: 0.18208, v: 0.27119, slope: -0.28539),
        Isotherm(mired: 40, u: 0.18293, v: 0.27407, slope: -0.30470),
        Isotherm(mired: 50, u: 0.18388, v: 0.27709, slope: -0.32675),
        Isotherm(mired: 60, u: 0.18494, v: 0.28021, slope: -0.35156),
        Isotherm(mired: 70, u: 0.18611, v: 0.28342, slope: -0.37915),
        Isotherm(mired: 80, u: 0.18740, v: 0.28668, slope: -0.40955),
        Isotherm(mired: 90, u: 0.18880, v: 0.28997, slope: -0.44278),
        Isotherm(mired: 100, u: 0.19032, v: 0.29326, slope: -0.47888),
        Isotherm(mired: 125, u: 0.19462, v: 0.30141, slope: -0.58204),
        Isotherm(mired: 150, u: 0.19962, v: 0.30921, slope: -0.70471),
        Isotherm(mired: 175, u: 0.20525, v: 0.31647, slope: -0.84901),
        Isotherm(mired: 200, u: 0.21142, v: 0.32312, slope: -1.0182),
        Isotherm(mired: 225, u: 0.21807, v: 0.32909, slope: -1.2168),
        Isotherm(mired: 250, u: 0.22511, v: 0.33439, slope: -1.4512),
        Isotherm(mired: 275, u: 0.23247, v: 0.33904, slope: -1.7298),
        Isotherm(mired: 300, u: 0.24010, v: 0.34308, slope: -2.0637),
        Isotherm(mired: 325, u: 0.24702, v: 0.34655, slope: -2.4681),
        Isotherm(mired: 350, u: 0.25591, v: 0.34951, slope: -2.9641),
        Isotherm(mired: 375, u: 0.26400, v: 0.35200, slope: -3.5814),
        Isotherm(mired: 400, u: 0.27218, v: 0.35407, slope: -4.3633),
        Isotherm(mired: 425, u: 0.28039, v: 0.35577, slope: -5.3762),
        Isotherm(mired: 450, u: 0.28863, v: 0.35714, slope: -6.7262),
        Isotherm(mired: 475, u: 0.29685, v: 0.35823, slope: -8.5955),
        Isotherm(mired: 500, u: 0.30505, v: 0.35907, slope: -11.324),
        Isotherm(mired: 525, u: 0.31320, v: 0.35968, slope: -15.628),
        Isotherm(mired: 550, u: 0.32129, v: 0.36011, slope: -23.325),
        Isotherm(mired: 575, u: 0.32931, v: 0.36038, slope: -40.770),
        Isotherm(mired: 600, u: 0.33724, v: 0.36051, slope: -116.45),
    ]

    /// The temperature and tint of a chromaticity.
    public init(_ white: Chromaticity) {
        let lines = Self.isotherms
        // CIE 1960 (u, v).
        let denominator = 1.5 - white.x + 6 * white.y
        let point = SIMD2(2 * white.x / denominator, 3 * white.y / denominator)
        var previous = (distance: 0.0, direction: SIMD2<Double>(0, 0))
        var result = ColorTemperature(kelvin: 1_000_000 / lines[lines.count - 1].mired, tint: 0)
        for index in 1..<lines.count {
            let line = lines[index]
            let direction = line.direction
            let offset = point - SIMD2(line.u, line.v)
            // How far the point is above (+) or below the line.
            var distance = -offset.x * direction.y + offset.y * direction.x
            if distance <= 0 || index == lines.count - 1 {
                // Between this line and the one before: the weight of the one before.
                distance = max(-distance, 0)
                let weight = index == 1 ? 0 : distance / (previous.distance + distance)
                let before = lines[index - 1]
                result.kelvin = 1_000_000 / (before.mired * weight + line.mired * (1 - weight))
                let body = SIMD2(before.u * weight + line.u * (1 - weight), before.v * weight + line.v * (1 - weight))
                var along = direction * (1 - weight) + previous.direction * weight
                along /= (along * along).sum().squareRoot()
                result.tint = ((point - body) * along).sum() * Self.tintScale
                break
            }
            previous = (distance, direction)
        }
        self = result
    }

    /// The chromaticity of this temperature and tint.
    public var chromaticity: Chromaticity {
        let lines = Self.isotherms
        let mired = 1_000_000 / kelvin
        let offset = tint / Self.tintScale
        var index = 0
        while index < lines.count - 2, mired >= lines[index + 1].mired { index += 1 }
        let low = lines[index], high = lines[index + 1]
        // The weight of the first of the two lines the temperature lies between.
        let weight = (high.mired - mired) / (high.mired - low.mired)
        var along = low.direction * weight + high.direction * (1 - weight)
        along /= (along * along).sum().squareRoot()
        let u = low.u * weight + high.u * (1 - weight) + along.x * offset
        let v = low.v * weight + high.v * (1 - weight) + along.y * offset
        return Chromaticity(x: 1.5 * u / (u - 4 * v + 2), y: v / (u - 4 * v + 2))
    }
}
