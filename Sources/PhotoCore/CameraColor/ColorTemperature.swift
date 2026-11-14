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
/// **Where this comes from** (`THIRD_PARTY_NOTICES.md`). Three published
/// sources and one measurement; no other program's source:
///
/// - *Reading a temperature* is Robertson's method (A. R. Robertson,
///   "Computation of Correlated Color Temperature and Distribution
///   Temperature", J. Opt. Soc. Am. 58 (11), 1528–1535, 1968): 31 lines of
///   constant temperature in the CIE 1960 (u, v) diagram, each given by its
///   reciprocal temperature, the black body's color there and its slope. A
///   color lies between the two neighboring lines whose distances from it,
///   dᵢ = ((v − vᵢ) − mᵢ (u − uᵢ)) / √(1 + mᵢ²), differ in sign, and its
///   reciprocal temperature is read between theirs in the proportion
///   dᵢ / (dᵢ − dᵢ₊₁).
/// - *(u, v) against (x, y)* is the CIE 1960 uniform chromaticity scale:
///   u = 4x / (−2x + 12y + 3), v = 6y / (−2x + 12y + 3), and solved for x and
///   y: x = 3u / (2u − 8v + 4), y = 2v / (2u − 8v + 4).
/// - *Everything the paper leaves open is measured against the system's RAW
///   decoder*, so that one stored Kelvin and tint means the same light to
///   both decoders: `CIRAWFilter` was given temperatures and tints and
///   asked for `neutralChromaticity`, and given chromaticities and asked for
///   `neutralTemperature` and `neutralTint`. What it showed, to the single
///   precision of its properties:
///   - the figures of the 31 lines (`lines`);
///   - a tint of 1 is 1/3000 of the (u, v) diagram's unit, along the line of
///     constant temperature, positive toward green (`tintPerDistance`);
///   - between two lines the black body's color is read in proportion to
///     reciprocal temperature, and so is the line's direction (the two
///     directions as vectors of length one, the result brought back to
///     length one); below the coolest line the last two are continued;
///   - a chromaticity's tint is its distance from that black body's color
///     along that direction, and nothing reads hotter than the second line
///     (100,000 K) or cooler than the last (1667 K).
///
///   `ColorTemperatureTests` repeats the measurement wherever the system
///   decoder reads the test file.
public struct ColorTemperature: Sendable, Hashable {
    public var kelvin: Double
    public var tint: Double

    public init(kelvin: Double, tint: Double = 0) {
        self.kelvin = kelvin
        self.tint = tint
    }

    // MARK: The lines of constant temperature

    /// Tint per unit of distance in the (u, v) diagram. Measured against
    /// the system decoder: 3000 at every line's temperature, to six figures.
    static let tintPerDistance = 3000.0

    /// A line of constant correlated color temperature in the (u, v) diagram.
    struct Line {
        /// Reciprocal temperature, 10⁶ / Kelvin (mired; Robertson's µrd).
        var mired: Double
        /// Where the line meets the black body's colors.
        var locus: SIMD2<Double>
        /// Along the line toward green, of length one.
        var green: SIMD2<Double>

        init(mired: Double, locus: SIMD2<Double>, green: SIMD2<Double>) {
            self.mired = mired
            self.locus = locus
            self.green = green
        }

        /// A line as a table gives it. Every slope of the table is negative,
        /// and green lies above the black body's colors (v rising), so
        /// toward green u falls.
        init(_ mired: Double, u: Double, v: Double, slope: Double) {
            self.init(mired: mired, locus: SIMD2(u, v), green: SIMD2(-1, -slope) / (1 + slope * slope).squareRoot())
        }

        /// Robertson's dᵢ: how far `point` lies from the line, positive on
        /// the side of the lower temperatures.
        func distance(to point: SIMD2<Double>) -> Double {
            let from = point - locus
            // The line's normal toward lower temperatures is its direction turned a quarter: (green.y, −green.x).
            return from.x * green.y - from.y * green.x
        }

        /// How far `point` lies from the black body's color along the line, toward green.
        func height(of point: SIMD2<Double>) -> Double {
            let from = point - locus
            return from.x * green.x + from.y * green.y
        }

        /// The line a `part` of the way from this one to `other`, as the
        /// system decoder reads between two lines (measured): reciprocal
        /// temperature and the black body's color in proportion, and the
        /// direction the two directions in proportion, at length one.
        /// `part` may pass 1: the pair is continued.
        func toward(_ other: Line, _ part: Double) -> Line {
            let direction = green + (other.green - green) * part
            return Line(mired: mired + (other.mired - mired) * part, locus: locus + (other.locus - locus) * part,
                        green: direction / (direction * direction).sum().squareRoot())
        }
    }

    /// The 31 lines: every 10 mired from 0 (infinite temperature) to 100,
    /// then every 25 to 600 (1667 K), the spacing of Robertson's Table II.
    ///
    /// **The figures are the system decoder's**, measured as described
    /// above: its black body colors at these temperatures come out as
    /// five-decimal numbers, and the slopes of its tint direction to five
    /// figures. They are the table as it is reprinted in the literature
    /// (cited there as Wyszecki and Stiles, "Color Science", 2nd edition,
    /// Table 1(3.11); the book was not at hand, the decoder was), which
    /// differs from Robertson's own Table II in the last figures. One figure
    /// of the reprint is known to be a misprint: u at 325 mired, 0.24702,
    /// where its neighbors put the black body near 0.2479. The system
    /// decoder has the misprint, so it stays: with it corrected, one Kelvin
    /// between 2857 and 3333 would be two different lights to the two
    /// decoders (`ColorTemperatureTests.matchesTheSystemDecoder`).
    static let lines: [Line] = [
        Line(0, u: 0.18006, v: 0.26352, slope: -0.24341),
        Line(10, u: 0.18066, v: 0.26589, slope: -0.25479),
        Line(20, u: 0.18133, v: 0.26846, slope: -0.26876),
        Line(30, u: 0.18208, v: 0.27119, slope: -0.28539),
        Line(40, u: 0.18293, v: 0.27407, slope: -0.30470),
        Line(50, u: 0.18388, v: 0.27709, slope: -0.32675),
        Line(60, u: 0.18494, v: 0.28021, slope: -0.35156),
        Line(70, u: 0.18611, v: 0.28342, slope: -0.37915),
        Line(80, u: 0.18740, v: 0.28668, slope: -0.40955),
        Line(90, u: 0.18880, v: 0.28997, slope: -0.44278),
        Line(100, u: 0.19032, v: 0.29326, slope: -0.47888),
        Line(125, u: 0.19462, v: 0.30141, slope: -0.58204),
        Line(150, u: 0.19962, v: 0.30921, slope: -0.70471),
        Line(175, u: 0.20525, v: 0.31647, slope: -0.84901),
        Line(200, u: 0.21142, v: 0.32312, slope: -1.0182),
        Line(225, u: 0.21807, v: 0.32909, slope: -1.2168),
        Line(250, u: 0.22511, v: 0.33439, slope: -1.4512),
        Line(275, u: 0.23247, v: 0.33904, slope: -1.7298),
        Line(300, u: 0.24010, v: 0.34308, slope: -2.0637),
        Line(325, u: 0.24702, v: 0.34655, slope: -2.4681),
        Line(350, u: 0.25591, v: 0.34951, slope: -2.9641),
        Line(375, u: 0.26400, v: 0.35200, slope: -3.5814),
        Line(400, u: 0.27218, v: 0.35407, slope: -4.3633),
        Line(425, u: 0.28039, v: 0.35577, slope: -5.3762),
        Line(450, u: 0.28863, v: 0.35714, slope: -6.7262),
        Line(475, u: 0.29685, v: 0.35823, slope: -8.5955),
        Line(500, u: 0.30505, v: 0.35907, slope: -11.324),
        Line(525, u: 0.31320, v: 0.35968, slope: -15.628),
        Line(550, u: 0.32129, v: 0.36011, slope: -23.325),
        Line(575, u: 0.32931, v: 0.36038, slope: -40.770),
        Line(600, u: 0.33724, v: 0.36051, slope: -116.45),
    ]

    /// The lines a chromaticity is read between: all but the first. The
    /// system decoder reads no light as hotter than 100,000 K (measured).
    static let readingLines = Array(lines.dropFirst())

    // MARK: Chromaticity to temperature and back

    /// The temperature and tint of a chromaticity. One that has no place in
    /// the (u, v) diagram (not finite) reads as 6500 K without a tint.
    public init(_ white: Chromaticity) {
        let scale = -2 * white.x + 12 * white.y + 3
        let point = SIMD2(4 * white.x, 6 * white.y) / scale
        guard point.x.isFinite, point.y.isFinite else {
            self.init(kelvin: 6500)
            return
        }
        let lines = Self.readingLines
        let distances = lines.map { $0.distance(to: point) }
        // The first line that has the point on its hotter side, and the line before it, have it between them.
        let line: Line = switch distances.firstIndex(where: { $0 < 0 }) {
        case 0?: lines[0]
        case let cooler?: lines[cooler - 1].toward(lines[cooler], distances[cooler - 1] / (distances[cooler - 1] - distances[cooler]))
        case nil: lines[lines.count - 1]
        }
        self.init(kelvin: 1_000_000 / line.mired, tint: Self.tintPerDistance * line.height(of: point))
    }

    /// The chromaticity of this temperature and tint.
    public var chromaticity: Chromaticity {
        // No light is colder than 1 K here: the reciprocal stays finite.
        let mired = 1_000_000 / (kelvin >= 1 ? kelvin : 1)
        let lines = Self.lines
        let cooler = lines.dropFirst().firstIndex { $0.mired >= mired } ?? lines.count - 1
        let hotter = lines[cooler - 1]
        let line = hotter.toward(lines[cooler], (mired - hotter.mired) / (lines[cooler].mired - hotter.mired))
        let point = line.locus + line.green * (tint / Self.tintPerDistance)
        let scale = 2 * point.x - 8 * point.y + 4
        return Chromaticity(x: 3 * point.x / scale, y: 2 * point.y / scale)
    }
}
