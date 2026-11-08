import Foundation
import PhotoCore

/// Chromatic aberration scenes (a) and (b) (`TestScene.fringes`,
/// `.fringeSubjects`), and where their fringes are, for the Color Fringes
/// tests (docs/features/chromatic-aberration/prd.md, acceptance criteria).
///
/// Laid out at the default 256 × 192 (other sizes draw it scaled), y down:
///
/// - Top left (x < 128, y < 120): a light neutral ground (0.85) with two dark
///   bars (0.18), x 32 … 48 and 80 … 96, y 16 … 104. Each has a purple fringe
///   three pixels wide on its left and a green one on its right, fading from
///   the bar outward. The first bar's purple is bluer and its green
///   yellower; the second's purple redder and its green bluer: the range real
///   fringes of one kind show.
/// - Top right: a dark ground (0.12) with a defocused bright disc (center
///   192, 60, radius 30, an edge ten pixels soft) whose rim is purple.
/// - Bottom (y ≥ 120): a blue sky, as bright as the light ground, meeting a
///   dark ridge (0.20) at y 150 right of x 176, with no fringe: sky beside a
///   high-contrast edge.
/// - Scene (b) adds a purple patch (x 12 … 60) and a green patch (x 68 … 116),
///   y 132 … 184, on the sky and as bright as it, so no high-contrast edge is near.
///
/// Colors are in the perceptual encoding (Rec. 2020 primaries, sRGB curve).
public enum FringeScene {
    public enum Fringe: String, CaseIterable, Sendable {
        /// The first bar's purple (bluer) and the second's (redder).
        case purple1, purple2
        /// The disc's rim.
        case discRim
        /// The first bar's green (yellower) and the second's (bluer).
        case green1, green2

        public var isPurple: Bool { self != .green1 && self != .green2 }

        /// The fringe's color at full strength, perceptual.
        public var color: SIMD3<Double> {
            switch self {
            case .purple1: SIMD3(0.56, 0.32, 0.92)
            case .purple2: SIMD3(0.74, 0.30, 0.86)
            case .discRim: SIMD3(0.66, 0.30, 0.90)
            case .green1: SIMD3(0.52, 0.80, 0.26)
            case .green2: SIMD3(0.30, 0.78, 0.48)
            }
        }
    }

    static let light = 0.85, dark = 0.18, ground = 0.12, ridge = 0.20
    /// The sky, perceptual: as bright as the light ground within 0.1 of
    /// perceptual luminance, so their meeting is no high-contrast edge.
    public static let sky = SIMD3(0.62, 0.78, 0.97)
    /// The patches' hues, scaled in linear light to the sky's luminance.
    public static let purplePatchBase = SIMD3(0.70, 0.38, 0.88)
    public static let greenPatchBase = SIMD3(0.40, 0.70, 0.30)

    static let bars: [(left: Double, purple: Fringe, green: Fringe)] = [(32, .purple1, .green1), (80, .purple2, .green2)]
    static let barWidth = 16.0, barTop = 16.0, barBottom = 104.0, fringeWidth = 3.0
    static let discCenter = (x: 192.0, y: 60.0), discRadius = 30.0
    /// Where the ridge starts: farther from the patches than the edge rule reaches.
    static let ridgeLeft = 176.0

    static func image(_ width: Int, _ height: Int, subjects: Bool) -> LinearImage {
        let scale = Double(width) / Double(TestScene.defaultWidth)
        let lightLinear = SIMD3(repeating: TestScene.decode(light))
        let skyLinear = TestScene.decode(sky)
        let skyLuminance = luminance(skyLinear)
        func matched(_ base: SIMD3<Double>) -> SIMD3<Double> {
            let linear = TestScene.decode(base)
            return linear * (skyLuminance / luminance(linear))
        }
        let purplePatch = matched(purplePatchBase), greenPatch = matched(greenPatchBase)
        return TestScene.fill(width, height, supersample: 4) { u, v in
            let x = u / scale, y = v / scale
            if y >= 120 {
                if subjects, y >= 132, y < 184 {
                    if x >= 12, x < 60 { return purplePatch }
                    if x >= 68, x < 116 { return greenPatch }
                }
                return x >= ridgeLeft && y >= 150 ? SIMD3(repeating: TestScene.decode(ridge)) : skyLinear
            }
            if x < 128 {
                guard y >= barTop, y < barBottom else { return lightLinear }
                for bar in bars {
                    if x >= bar.left, x < bar.left + barWidth { return SIMD3(repeating: TestScene.decode(dark)) }
                    // Full strength against the bar, gone three pixels out.
                    let outLeft = bar.left - x, outRight = x - (bar.left + barWidth)
                    if outLeft > 0, outLeft < fringeWidth {
                        return mix(lightLinear, TestScene.decode(bar.purple.color), 1 - outLeft / fringeWidth)
                    }
                    if outRight >= 0, outRight < fringeWidth {
                        return mix(lightLinear, TestScene.decode(bar.green.color), 1 - outRight / fringeWidth)
                    }
                }
                return lightLinear
            }
            let distance = hypot(x - discCenter.x, y - discCenter.y)
            // The disc's brightness falls over ten pixels around its radius.
            let t = 1 - smoothstep(discRadius - 5, discRadius + 5, distance)
            let base = SIMD3(repeating: TestScene.decode(ground) + (0.95 - TestScene.decode(ground)) * t)
            // Its rim is purple where the brightness falls.
            let rim = exp(-pow((distance - discRadius) / 3, 2))
            return mix(base, TestScene.decode(Fringe.discRim.color), 0.85 * rim)
        }
    }

    // MARK: Where things are

    /// Pixels (x, y from the top) of a scene `width` wide where `fringe`
    /// is at least a third of its strength (the inner two columns of a bar's
    /// fringe away from the bar's ends, the disc's rim within two pixels of
    /// its radius).
    public static func pixels(of fringe: Fringe, width: Int = TestScene.defaultWidth,
                              height: Int = TestScene.defaultHeight) -> [(x: Int, y: Int)] {
        let scale = Double(width) / Double(TestScene.defaultWidth)
        var out: [(x: Int, y: Int)] = []
        if fringe == .discRim {
            for y in 0..<height {
                for x in 0..<width {
                    let d = hypot((Double(x) + 0.5) / scale - discCenter.x, (Double(y) + 0.5) / scale - discCenter.y)
                    if abs(d - discRadius) <= 2 { out.append((x, y)) }
                }
            }
            return out
        }
        guard let bar = bars.first(where: { $0.purple == fringe || $0.green == fringe }) else { return [] }
        let columns: [Double] = fringe.isPurple ? [bar.left - 1, bar.left - 2] : [bar.left + barWidth, bar.left + barWidth + 1]
        for column in columns {
            let x0 = Int((column * scale).rounded(.down)), x1 = Int(((column + 1) * scale).rounded(.down))
            for x in x0..<x1 {
                for y in Int((barTop + 4) * scale)..<Int((barBottom - 4) * scale) { out.append((x, y)) }
            }
        }
        return out
    }

    /// Sky pixels within `reach` default pixels above the ridge (and away from
    /// the frame's and the regions' borders): beside a high-contrast edge.
    public static func skyByRidge(reach: Double = 8, width: Int = TestScene.defaultWidth) -> [(x: Int, y: Int)] {
        let scale = Double(width) / Double(TestScene.defaultWidth)
        var out: [(x: Int, y: Int)] = []
        for y in Int((150 - reach) * scale)..<Int(150 * scale) {
            for x in Int(188 * scale)..<Int(244 * scale) { out.append((x, y)) }
        }
        return out
    }

    /// The inner part of a patch of scene (b): `inset` default pixels in from its border.
    public static func patch(purple: Bool, inset: Double = 6, width: Int = TestScene.defaultWidth) -> [(x: Int, y: Int)] {
        let scale = Double(width) / Double(TestScene.defaultWidth)
        let left = purple ? 12.0 : 68.0
        var out: [(x: Int, y: Int)] = []
        for y in Int((132 + inset) * scale)..<Int((184 - inset) * scale) {
            for x in Int((left + inset) * scale)..<Int((left + 48 - inset) * scale) { out.append((x, y)) }
        }
        return out
    }

    // MARK: Helpers

    static func luminance(_ linear: SIMD3<Double>) -> Double {
        0.2627 * linear.x + 0.6780 * linear.y + 0.0593 * linear.z
    }

    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
        a + (b - a) * t
    }

    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
