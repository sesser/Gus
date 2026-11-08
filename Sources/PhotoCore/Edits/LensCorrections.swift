import Foundation

/// Up to two picked fringe colors, each turned gray near high-contrast edges
/// (docs/features/chromatic-aberration: the Color Fringes group).
///
/// A slot holds a color as OkLab (L, a, b) of the linear Rec. 2020 pixel it
/// came from (`ColorRange.okLab`, as a color range mask stores its samples),
/// and a Tolerance. A slot filled from the list of common fringe colors
/// (`CommonFringeColor`) holds exactly the same two values: nothing records
/// how it was filled (R1b). A slot's Tolerance is left out of the stack
/// while it is the starting Tolerance for its color (`startingTolerance`),
/// so two slots holding the same values store the same bytes.
public struct ColorFringes: AdjustmentModule {
    public static let kind: EditOperationKind = "colorFringes"

    public static let toleranceRange: ClosedRange<Double> = 0...100

    /// One filled slot.
    public struct Slot: Hashable, Sendable {
        /// OkLab (L, a, b): L 0 … 1, a and b −0.5 … 0.5.
        public var color: SIMD3<Double>
        /// 0 … 100: how far from the color's hue the graying reaches.
        public var tolerance: Double

        public init(color: SIMD3<Double>, tolerance: Double? = nil) {
            let clamped = Self.clamped(color)
            self.color = clamped
            self.tolerance = tolerance.map(ColorFringes.clampedTolerance) ?? ColorFringes.startingTolerance(for: clamped)
        }

        static func clamped(_ color: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(min(max(color.x, 0), 1), min(max(color.y, -0.5), 0.5), min(max(color.z, -0.5), 0.5))
        }

        /// The hue the slot grays, in radians (OkLab's atan2(b, a)).
        public var hue: Double { atan2(color.z, color.y) }

        /// OkLab chroma √(a² + b²).
        public var chroma: Double { (color.y * color.y + color.z * color.z).squareRoot() }
    }

    public var slot1: Slot?
    public var slot2: Slot?

    public init(slot1: Slot? = nil, slot2: Slot? = nil) {
        self.slot1 = slot1
        self.slot2 = slot2
    }

    /// The slot with that number (1 or 2).
    public subscript(slot number: Int) -> Slot? {
        get { number == 1 ? slot1 : slot2 }
        set {
            if number == 1 { slot1 = newValue } else { slot2 = newValue }
        }
    }

    /// The filled slots, in order.
    public var slots: [Slot] { [slot1, slot2].compactMap(\.self) }

    /// Nothing to gray.
    public var isIdentity: Bool { slot1 == nil && slot2 == nil }

    init(_ values: ParameterValues) {
        slot1 = Self.slot(values, 1)
        slot2 = Self.slot(values, 2)
    }

    private static func slot(_ values: ParameterValues, _ number: Int) -> Slot? {
        guard let color = values.color("color\(number)") else { return nil }
        return Slot(color: color, tolerance: values.optionalNumber("tolerance\(number)"))
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        for (number, slot) in [(1, slot1), (2, slot2)] {
            guard let slot else { continue }
            out.values["color\(number)"] = .list([.number(slot.color.x), .number(slot.color.y), .number(slot.color.z)])
            out.set("tolerance\(number)", slot.tolerance, default: Self.startingTolerance(for: slot.color))
        }
        return out.values
    }

    static func clampedTolerance(_ value: Double) -> Double {
        min(max(value, toleranceRange.lowerBound), toleranceRange.upperBound)
    }

    // MARK: Starting tolerance

    /// The Tolerance a color gets when it fills a slot, and what a reset of
    /// the slot's Tolerance gives back: the listed color's own when the
    /// slot holds exactly a listed color's value, otherwise a pick's. It
    /// follows the stored color alone, never how it got there (R1b).
    public static func startingTolerance(for color: SIMD3<Double>) -> Double {
        CommonFringeColor.allCases.first { $0.color == color }?.startingTolerance ?? pickStartingTolerance
    }

    /// The starting Tolerance of a color picked from the photo (prd OQ5,
    /// derived from scene (a) in `FringeToleranceDerivationTests`): its
    /// full-gray core reaches every fringe of the picked fringe's kind in
    /// the scene, whichever of them was picked, and stops before the sky.
    public static let pickStartingTolerance: Double = 55

    // MARK: Hue range

    /// Half the width of a slot's range of hues, in degrees: colors within
    /// half of it go fully gray, then less and less to none at this angle
    /// (R4). Grows with Tolerance, so widening never leaves fewer pixels
    /// affected (R3). At 0, only hues within 3° are fully grayed.
    public static func hueReach(tolerance: Double) -> Double {
        6 + 0.84 * clampedTolerance(tolerance)
    }

    /// How much of its color a pixel of OkLab (a, b) loses to `slot`, away
    /// from any edge rule: 1 within half the reach of the slot's hue, 0
    /// beyond it, smoothstep between; times `chromaGate`, since a pixel
    /// with almost no chroma has no hue to match (and is gray already).
    public static func colorWeight(a: Double, b: Double, slot: Slot) -> Double {
        let chroma = (a * a + b * b).squareRoot()
        let cosine = chroma > 1e-8 ? (a * cos(slot.hue) + b * sin(slot.hue)) / chroma : 0
        let distance = acos(min(max(cosine, -1), 1)) * 180 / .pi
        let reach = hueReach(tolerance: slot.tolerance)
        return (1 - smoothstep(reach / 2, reach, distance)) * smoothstep(chromaGate.lowerBound, chromaGate.upperBound, chroma)
    }

    /// Below the lower OkLab chroma a pixel counts as gray, and is matched
    /// in full above the upper: float rounding gives a gray a chroma near
    /// 10⁻⁶ and a random hue, and the fringe map must not show grays as
    /// affected. Both are well under a just noticeable difference (0.02).
    public static let chromaGate: ClosedRange<Double> = 0.002...0.01

    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: Picking

    /// Below this OkLab chroma a picked spot has "almost no color" and is
    /// refused (design §4): about one just noticeable OkLab difference
    /// (0.02) away from gray, with a little room for noise.
    public static let neutralChroma = 0.025
}

/// The short list a fringe slot can be filled from without pointing at the
/// photo (R1a, design §3 "The slot menu"). Each holds a color of exactly the
/// kind a pick stores, and the Tolerance it starts with (prd OQ5: derived
/// from scene (a), `FringeToleranceDerivationTests`).
public enum CommonFringeColor: String, CaseIterable, Sendable {
    case purple, green

    /// OkLab of the middle of scene (a)'s purple, or green, fringes
    /// (`FringeScene`): the hue halfway between the bluest and reddest purple
    /// (the yellowest and bluest green), at their mean lightness and chroma.
    public var color: SIMD3<Double> {
        switch self {
        case .purple: SIMD3(0.684, 0.1255, -0.1287)
        case .green: SIMD3(0.7917, -0.1264, 0.0662)
        }
    }

    /// Its full-gray core covers every fringe of its kind in scene (a), and
    /// its reach stops short of the scene's sky.
    public var startingTolerance: Double {
        switch self {
        case .purple: 25
        case .green: 20
        }
    }

    /// Its slot fills from this list item: a slot holds exactly this.
    public var slot: ColorFringes.Slot { ColorFringes.Slot(color: color, tolerance: startingTolerance) }

    public init?(name: String) {
        self.init(rawValue: name.lowercased())
    }
}

/// The name of a picked color's hue: the Color Mixer band whose center is
/// nearest (design §3 "Name"), for the slot row, VoiceOver and the debug
/// script.
public enum FringeHueName {
    /// The band nearest the color's hue, measured as the Color Mixer
    /// measures it (HSV hue of the color in the perceptual encoding, Rec.
    /// 2020 primaries with the sRGB curve, `ColorMixerCube.hue`).
    public static func band(of okLab: SIMD3<Double>) -> ColorMixer.Band {
        let rgb = FringeColorMath.perceptualRec2020(okLab: okLab)
        let high = max(rgb.x, rgb.y, rgb.z)
        let chroma = high - min(rgb.x, rgb.y, rgb.z)
        let hue = ColorMixerCube.hue(of: rgb, high: high, chroma: chroma)
        return ColorMixer.Band.allCases.min { distance($0.centerHue, hue) < distance($1.centerHue, hue) } ?? .red
    }

    static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }
}

/// OkLab and the working space, as the fringe step and picking use them.
public enum FringeColorMath {
    /// Linear Rec. 2020 (unclamped) of an OkLab color.
    public static func linearRec2020(okLab: SIMD3<Double>) -> SIMD3<Double> {
        let labToLMS = inverse(MaskRenderer.lmsToLab)
        let lmsToRGB = inverse(MaskRenderer.rec2020ToLMS)
        let root = multiply(labToLMS, okLab)
        let lms = SIMD3(root.x * root.x * root.x, root.y * root.y * root.y, root.z * root.z * root.z)
        return multiply(lmsToRGB, lms)
    }

    /// The color in the perceptual encoding (Rec. 2020 primaries, sRGB curve), clamped 0 … 1.
    public static func perceptualRec2020(okLab: SIMD3<Double>) -> SIMD3<Double> {
        let linear = linearRec2020(okLab: okLab)
        func encode(_ v: Double) -> Double {
            let c = min(max(v, 0), 1)
            return c <= 0.003_130_8 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        return SIMD3(encode(linear.x), encode(linear.y), encode(linear.z))
    }

    /// OkLab of a linear Rec. 2020 color, unclamped (cube roots keep their sign).
    public static func okLab(linearRec2020 rgb: SIMD3<Double>) -> SIMD3<Double> {
        let lms = multiply(MaskRenderer.rec2020ToLMS, rgb)
        return multiply(MaskRenderer.lmsToLab, SIMD3(cbrt(lms.x), cbrt(lms.y), cbrt(lms.z)))
    }

    static func multiply(_ m: [[Double]], _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
              m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
              m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z)
    }

    static func inverse(_ m: [[Double]]) -> [[Double]] {
        let a = m[0][0], b = m[0][1], c = m[0][2]
        let d = m[1][0], e = m[1][1], f = m[1][2]
        let g = m[2][0], h = m[2][1], i = m[2][2]
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        return [[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
                [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
                [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]]
    }
}

/// Lines the red and blue images up with the green (the Color Alignment
/// group): each is scaled about the lens's optical axis, the middle of the
/// whole sensor, before the crop, so a crop never changes how a scene point
/// is corrected (R9).
///
/// `red` and `blue` are how much larger that channel's image is than the
/// green's, in ten-thousandths: +10 means the red image is 0.1 % larger
/// and is shrunk by that much. They are stored whether measured
/// (`automatic`) or set by hand, so every render applies the same values
/// (R8); a measurement only ever runs when the values change.
public struct ColorAlignment: AdjustmentModule {
    public static let kind: EditOperationKind = "colorAlignment"

    /// −50 … +50 ten-thousandths: up to 18 pixels at a 24-megapixel corner.
    public static let range: ClosedRange<Double> = -50...50
    /// One ten-thousandth per unit.
    public static let unit = 1e-4

    /// The values were measured on this photo, and paste and presets
    /// measure each receiving photo again (R16).
    public var automatic = false
    public var red: Double = 0
    public var blue: Double = 0

    public init(automatic: Bool = false, red: Double = 0, blue: Double = 0) {
        self.automatic = automatic
        self.red = Self.clamped(red)
        self.blue = Self.clamped(blue)
    }

    init(_ values: ParameterValues) {
        automatic = values.bool("automatic", default: false)
        red = Self.clamped(values.number("red", default: 0))
        blue = Self.clamped(values.number("blue", default: 0))
    }

    static func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Nothing moves.
    public var isIdentity: Bool { red == 0 && blue == 0 }

    /// A slider moved: the values become hand-set, starting from the
    /// measured ones (R10, the RI-2 ruling: no longer automatic).
    public mutating func setByHand(red: Double? = nil, blue: Double? = nil) {
        automatic = false
        if let red { self.red = Self.clamped(red) }
        if let blue { self.blue = Self.clamped(blue) }
    }

    /// The red and blue magnifications as fractions (`red × unit`).
    public var redScale: Double { red * Self.unit }
    public var blueScale: Double { blue * Self.unit }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("automatic", automatic, default: false)
        out.set("red", red, default: 0)
        out.set("blue", blue, default: 0)
        return out.values
    }
}

extension ColorFringes {
    public static let parameterDescriptions: [AdjustmentParameter] = [1, 2].flatMap { number in
        [AdjustmentParameter("color\(number)", .okLabColor, default: nil),
         // Left out while it is the color's starting Tolerance (`startingTolerance`).
         .number("tolerance\(number)", toleranceRange, default: nil)]
    }
}

extension ColorAlignment {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        AdjustmentParameter("automatic", .boolean, default: .bool(false)),
        .number("red", range, default: 0), .number("blue", range, default: 0),
    ]
}

extension ParameterValues {
    /// An OkLab color stored as a list of three numbers.
    func color(_ key: String) -> SIMD3<Double>? {
        guard case .list(let list)? = raw[key], list.count == 3 else { return nil }
        let numbers = list.compactMap { item -> Double? in
            if case .number(let value) = item, value.isFinite { return value }
            return nil
        }
        guard numbers.count == 3 else { return nil }
        return SIMD3(numbers[0], numbers[1], numbers[2])
    }
}

extension Adjustments {
    /// These values ask for color alignment measured on the photo they are
    /// given to: paste, a preset or a batch measures each receiving photo
    /// (R16) rather than copying the values measured on another.
    public var needsAlignmentMeasurement: Bool { colorAlignment.automatic }

    /// These values with `measured` as their automatic alignment (its on/off
    /// state kept).
    public func measuringAlignment(_ measured: ColorAlignment) -> Adjustments {
        var copy = self
        copy.colorAlignment = ColorAlignment(automatic: true, red: measured.red, blue: measured.blue)
        return copy
    }
}

/// What the fringe map says beside the picture (design §6 "Caption badge and
/// legend"): whether the graying it maps is applied. One rule for the badge,
/// the legend, the loupe's VoiceOver value and the announcement.
public struct FringeMapStatus: Equatable, Sendable {
    /// Color Fringes is turned off: the map shows what would be removed.
    public var isNotApplied: Bool

    public init(isNotApplied: Bool) {
        self.isNotApplied = isNotApplied
    }

    public init(_ values: Adjustments) {
        isNotApplied = !values.isEnabled(.colorFringes)
    }
}

extension AdjustmentRenderer {
    /// Compiles the Lens kernels now (about 2 s on the first launch after a
    /// build, a few milliseconds after that), so a photo's first frame with
    /// fringes or alignment does not wait for it. Call off the main thread.
    public static func prepareLensKernels() {
        _ = try? LensKernels.compile()
    }
}
