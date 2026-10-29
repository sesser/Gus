import Foundation

/// Monotone cubic interpolation through curve points (Fritsch–Carlson), so a
/// curve never overshoots between its points and stays monotone where its
/// points are.
public struct MonotoneSpline: Sendable {
    private let xs: [Double]
    private let ys: [Double]
    private let slopes: [Double]

    public init(_ points: [CurvePoint]) {
        let sorted = ToneCurve.normalized(points)
        // Points sharing an x keep the last one.
        var xs: [Double] = []
        var ys: [Double] = []
        for point in sorted {
            if let last = xs.last, point.x - last < 1e-6 {
                ys[ys.count - 1] = point.y
            } else {
                xs.append(point.x)
                ys.append(point.y)
            }
        }
        if xs.count < 2 {
            xs = [0, 1]
            ys = [ys.first ?? 0, ys.first ?? 1]
        }
        let n = xs.count
        var secants = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            secants[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i])
        }
        var slopes = [Double](repeating: 0, count: n)
        slopes[0] = secants[0]
        slopes[n - 1] = secants[n - 2]
        for i in 1..<(n - 1) {
            slopes[i] = secants[i - 1] * secants[i] <= 0 ? 0 : (secants[i - 1] + secants[i]) / 2
        }
        for i in 0..<(n - 1) {
            if secants[i] == 0 {
                slopes[i] = 0
                slopes[i + 1] = 0
                continue
            }
            let a = slopes[i] / secants[i]
            let b = slopes[i + 1] / secants[i]
            let magnitude = a * a + b * b
            if magnitude > 9 {
                let t = 3 / magnitude.squareRoot()
                slopes[i] = t * a * secants[i]
                slopes[i + 1] = t * b * secants[i]
            }
        }
        self.xs = xs
        self.ys = ys
        self.slopes = slopes
    }

    /// The curve at `x`; flat beyond the first and last points.
    public func value(at x: Double) -> Double {
        if x <= xs[0] { return ys[0] }
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] }
        var low = 0
        var high = xs.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if xs[mid] <= x { low = mid } else { high = mid }
        }
        let h = xs[high] - xs[low]
        let t = (x - xs[low]) / h
        let t2 = t * t
        let t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * ys[low] + (t3 - 2 * t2 + t) * h * slopes[low]
            + (-2 * t3 + 3 * t2) * ys[high] + (t3 - t2) * h * slopes[high]
    }
}

/// The global tone controls and the point curves, folded into one table per
/// channel for `CIColorCurves`.
///
/// Values are in a perceptual encoding (Rec. 2020 primaries, sRGB transfer
/// curve). The table spans 0 … `domainMaximum` so values above SDR white pass
/// through: every control is defined on 0 … 1 and continues with slope one above.
public struct ToneTable: Sendable {
    public static let domainMaximum = 2.0
    public static let entryCount = 2048

    /// Pivot of the contrast curve: 18 % grey in the sRGB encoding.
    static let pivot = 0.4613561

    public var contrast: Double
    public var highlights: Double
    public var whites: Double
    public var blacks: Double
    public var curve: ToneCurve

    /// - Parameters: tone controls in −1 … 1 (the UI's −100 … 100 scaled).
    public init(contrast: Double = 0, highlights: Double = 0, whites: Double = 0, blacks: Double = 0,
                curve: ToneCurve = ToneCurve()) {
        self.contrast = contrast
        self.highlights = highlights
        self.whites = whites
        self.blacks = blacks
        self.curve = curve
    }

    public var isIdentity: Bool {
        contrast == 0 && highlights == 0 && whites == 0 && blacks == 0 && curve.isIdentity
    }

    /// `entryCount` RGB triplets over 0 … `domainMaximum`, monotone per channel.
    public func rgbTable() -> [Float] {
        let composite = MonotoneSpline(curve.rgb)
        let channels = [curve.red, curve.green, curve.blue].map { points in
            ToneCurve.isIdentity(points) ? nil : MonotoneSpline(points)
        }
        let compositeIsIdentity = ToneCurve.isIdentity(curve.rgb)
        var table = [Float](repeating: 0, count: Self.entryCount * 3)
        var previous = [Double](repeating: -.infinity, count: 3)
        for i in 0..<Self.entryCount {
            let x = Self.domainMaximum * Double(i) / Double(Self.entryCount - 1)
            let toned = tone(x)
            let shaped = compositeIsIdentity ? toned : Self.extend(toned) { composite.value(at: $0) }
            for c in 0..<3 {
                var value = channels[c].map { spline in Self.extend(shaped) { spline.value(at: $0) } } ?? shaped
                // Keep every channel monotone: running maximum.
                value = max(value, previous[c])
                previous[c] = value
                table[i * 3 + c] = Float(value)
            }
        }
        return table
    }

    /// The parametric controls at `x`.
    func tone(_ x: Double) -> Double {
        var v = Self.extend(x) { v in
            var v = v
            // Blacks lift or crush the low end, whites push or hold the top.
            v += blacks * 0.15 * pow(1 - v, 4)
            v += whites * 0.15 * pow(v, 4)
            return v
        }
        if highlights > 0 {
            v = Self.extend(v) { v in
                let weight = Self.smoothstep(0.45, 1, v)
                return v + highlights * 0.25 * weight * (1 - v) * 2
            }
        }
        if contrast != 0 {
            v = Self.extend(v) { Self.contrastCurve($0, amount: contrast) }
        }
        return max(v, 0)
    }

    /// An S-curve around `pivot` that keeps 0 and 1 fixed.
    static func contrastCurve(_ x: Double, amount: Double) -> Double {
        let gamma = exp(amount * 0.9)
        let p = pivot
        let clamped = min(max(x, 0), 1)
        if clamped < p {
            return p * pow(clamped / p, gamma)
        }
        return 1 - (1 - p) * pow((1 - clamped) / (1 - p), gamma)
    }

    /// Applies `f`, defined on 0 … 1, and continues it with slope one above 1.
    static func extend(_ x: Double, _ f: (Double) -> Double) -> Double {
        x <= 1 ? f(x) : f(1) + (x - 1)
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Gain for the Shadows slider and for negative Highlights, as a function of
/// the local (smoothed) linear luminance.
///
/// Both work in stops around 18 % grey. Recovering highlights lowers the slope
/// of tones above a knee a stop over mid grey, so values well above white (kept
/// by the RAW decoder) come back into range; shadows lift tones below a knee
/// half a stop under mid grey, by at most `maximumShadowStops`. The slope never
/// drops below 0.3, so the mapping stays monotone.
public struct LocalToneCurve: Sendable, Hashable {
    /// −1 … 1 (lift or deepen).
    public var shadows: Double
    /// 0 … 1, how much to recover (the slider's negative values).
    public var recovery: Double

    static let middleGrey = 0.18
    static let highlightKnee = 1.0
    static let shadowKnee = -0.5
    static let strength = 0.7
    static let maximumShadowStops = 3.0
    /// Gain table input is luminance to this power, for even resolution in the shadows.
    public static let encodingPower = 0.25
    public static let domainMaximum = 2.0
    public static let entryCount = 1024

    public init(shadows: Double, recovery: Double) {
        self.shadows = shadows
        self.recovery = recovery
    }

    public var isIdentity: Bool { shadows == 0 && recovery == 0 }

    /// Change in stops for a local luminance (linear).
    public func stops(luminance: Double) -> Double {
        let s = log2(max(luminance, 1e-6) / Self.middleGrey)
        var stops = -recovery * Self.strength * Self.softplus(s - Self.highlightKnee)
        if shadows != 0 {
            let lift = Self.strength * Self.softplus(Self.shadowKnee - s)
            stops += shadows * Self.maximumShadowStops * tanh(lift / Self.maximumShadowStops)
        }
        return stops
    }

    public func gain(luminance: Double) -> Double {
        exp2(stops(luminance: luminance))
    }

    /// `entryCount` RGB triplets of gain over encoded luminance 0 … `domainMaximum`.
    public func gainTable() -> [Float] {
        var table = [Float](repeating: 0, count: Self.entryCount * 3)
        for i in 0..<Self.entryCount {
            let encoded = Self.domainMaximum * Double(i) / Double(Self.entryCount - 1)
            let value = Float(gain(luminance: pow(encoded, 1 / Self.encodingPower)))
            table[i * 3] = value
            table[i * 3 + 1] = value
            table[i * 3 + 2] = value
        }
        return table
    }

    /// ln(1 + eˣ), in stops: a smooth ramp from 0 to x.
    static func softplus(_ x: Double) -> Double {
        x > 30 ? x : log1p(exp(x))
    }
}

/// Dehaze's per-pixel gain g = 1/t and offset g − 1, over the dark channel
/// relative to the airlight (0 … 1), with transmission t = 1 − ω·haze.
struct DehazeTables {
    /// ω at the slider's maximum: t stays above 1 − this.
    static let strength = 0.9
    /// ω rises faster over the first half of the slider.
    static let response = 0.75
    static let entryCount = 256

    let gain: [Float]
    let offset: [Float]

    init(amount: Double) {
        let omega = pow(min(max(amount, 0), 1), Self.response) * Self.strength
        var gain = [Float](repeating: 0, count: Self.entryCount * 3)
        var offset = gain
        for i in 0..<Self.entryCount {
            let haze = Double(i) / Double(Self.entryCount - 1)
            let g = 1 / (1 - omega * haze)
            for c in 0..<3 {
                gain[i * 3 + c] = Float(g)
                offset[i * 3 + c] = Float(g - 1)
            }
        }
        self.gain = gain
        self.offset = offset
    }
}
