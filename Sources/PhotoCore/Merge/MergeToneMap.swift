import Foundation
import simd

/// The fixed tone mapping that turns the merged light into a picture any
/// viewer shows normally (R12; PRD Open question 3: one global-plus-local
/// operator, no controls).
///
/// **Base and detail** (Durand and Dorsey 2002, "Fast bilateral filtering
/// for the display of high-dynamic-range images"): the log luminance is split
/// into a base layer, an edge-preserving smoothing of it, and the detail
/// (log luminance minus base). Only the base's range is compressed: it is
/// scaled in the log domain so that its range (its 1st to 99.99th
/// percentile) fits `targetStops`, with the brightest light just below
/// white (`whiteLevel`); the detail
/// is added back unchanged, so local contrast and texture survive in the
/// shadows and the highlights alike. A scene whose range already fits is not
/// compressed, only brought to white.
///
/// **The base layer** is the guided filter (He, Sun and Tang 2010, "Guided
/// image filtering") in place of the bilateral filter, computed on the
/// reduced copy and applied at full resolution as He and Sun 2015 describe
/// ("Fast guided filter"): the filter's coefficients `a` and `b` are
/// averaged on the copy, enlarged, and the base is `a · log L + b` with the
/// full-resolution log luminance, so it keeps its edges.
///
/// **Shoulder**: above `knee` the luminance rolls off smoothly toward white
/// (`knee + (1 - knee)(1 - e^(-(x - knee) / (1 - knee)))`, slope 1 at the
/// knee), so the detail on a bright area that the base smooths over (a
/// small bright patch, an edge's bright side) bends instead of clipping.
///
/// **Color**: each pixel's color keeps its ratios to its luminance; one that
/// would leave the unit cube is pulled toward its gray of the same
/// luminance until its brightest channel is 1.
public struct MergeToneMap: Sendable, Equatable {
    /// The factor the base's log range is scaled by (at most 1).
    public var compression: Double
    /// The natural log of the base that maps to white: set so the brightest
    /// light (its 99.99th percentile) maps to `whiteLevel`.
    public var top: Double
    /// The guided filter's averaged coefficients on the reduced copy:
    /// `a` in `guideA`, `b` in `guideB`.
    public var guideA: MergePlane
    public var guideB: MergePlane
    /// How much of the detail is added back (1: all of it).
    public var detail: Double = 1

    /// The base's range after compression, in stops: what a print or a
    /// screen shows as a scene's range of light with the detail on top
    /// (Durand and Dorsey compress to about this; status.md, "Tone mapping").
    public static let targetStops = 5.0
    /// The level the base's brightest maps to: a little below white, so the
    /// brightest flat areas keep their steps and the detail on them has room.
    public static let whiteLevel = 0.9
    /// Where the shoulder starts.
    public static let knee: Float = 0.8
    /// Luminance below this is taken as this, so log stays finite.
    public static let floorLuminance: Float = 1e-7
    /// The guided filter's window radius, as a part of the copy's long edge,
    /// and its edge threshold on natural log luminance (a standard deviation of
    /// 0.5, about 0.7 stop: edges stronger than that are kept in the base).
    public static let radiusFraction = 0.02
    public static let epsilon: Float = 0.25

    /// The tone mapping for `radiance`, the merged light on the reduced copy.
    public static func plan(for radiance: MergeBitmap) -> MergeToneMap {
        let width = radiance.width, height = radiance.height
        var logs = MergePlane(width: width, height: height)
        for index in 0..<radiance.count {
            logs.values[index] = log(max(MergeBitmap.luminance(radiance.rgb(index)), floorLuminance))
        }
        let (a, b) = guidedCoefficients(logs, radius: max(1, Int(Double(max(width, height)) * radiusFraction)),
                                        epsilon: epsilon)
        var base = (0..<logs.values.count).map { a.values[$0] * logs.values[$0] + b.values[$0] }
        guard !base.isEmpty else { return MergeToneMap(compression: 1, top: 0, guideA: a, guideB: b) }
        base.sort()
        func percentile(_ sorted: [Float], _ p: Double) -> Double {
            Double(sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))])
        }
        let range = percentile(base, 0.9999) - percentile(base, 0.01)
        let compression = range > 0 ? min(1, targetStops * log(2) / range) : 1
        // The anchor is the pixels' brightest, not the base's: a bright area
        // smaller than the filter's window is above its base, and would
        // otherwise go past white with its detail.
        let brightest = percentile(logs.values.sorted(), 0.9999)
        return MergeToneMap(compression: compression, top: brightest - log(whiteLevel) / compression,
                            guideA: a, guideB: b)
    }

    /// The highlight roll-off above `knee`.
    public static func shoulder(_ x: Float) -> Float {
        x <= knee ? x : knee + (1 - knee) * (1 - exp(-(x - knee) / (1 - knee)))
    }

    /// The guided filter's coefficients for `guide` filtering itself, averaged
    /// over each window (He et al. 2010, Algorithm 1): the base is
    /// `meanA · I + meanB`.
    public static func guidedCoefficients(_ guide: MergePlane, radius: Int, epsilon: Float) -> (MergePlane, MergePlane) {
        let mean = guide.boxMean(radius: radius)
        var squares = guide
        for i in squares.values.indices { squares.values[i] *= squares.values[i] }
        let meanSquares = squares.boxMean(radius: radius)
        var a = guide, b = guide
        for i in guide.values.indices {
            let variance = max(0, meanSquares.values[i] - mean.values[i] * mean.values[i])
            a.values[i] = variance / (variance + epsilon)
            b.values[i] = (1 - a.values[i]) * mean.values[i]
        }
        return (a.boxMean(radius: radius), b.boxMean(radius: radius))
    }

    /// One pixel's mapped color: the kernel `mergeToneMap`, in plain Swift,
    /// with the guide's coefficients at that pixel.
    public func map(_ radiance: SIMD3<Float>, a: Float, b: Float) -> SIMD3<Float> {
        let e = simd_max(radiance, .zero)
        let l = MergeBitmap.luminance(e)
        guard l > 0 else { return .zero }
        let logL = log(max(l, Self.floorLuminance))
        let base = a * logL + b
        let ld = Self.shoulder(exp(Float(compression) * (base - Float(top)) + (logL - base) * Float(detail)))
        var rgb = e * (ld / l)
        let m = max(rgb.x, rgb.y, rgb.z)
        if m > 1 {
            rgb = ld >= 1 ? SIMD3(repeating: 1) : ld + (rgb - ld) * ((1 - ld) / (m - ld))
        }
        return rgb
    }
}
