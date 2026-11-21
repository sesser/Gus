import Foundation
import simd

/// The fixed tone mapping that turns the merged light into a picture any
/// viewer shows normally (R12; PRD Open question 3: one global-plus-local
/// operator, no controls).
///
/// **Global** (Reinhard, Stark, Shirley and Ferwerda 2002, "Photographic tone
/// reproduction for digital images", eq. 2 to 4): the luminance is scaled so
/// its log-average lands on the key, then compressed by
/// `L (1 + L / Lwhite²) / (1 + L)`, with the white at the scene's brightest
/// light (its 99.99th percentile). The key is chosen from the scene's range
/// as in Reinhard 2002, "Parameter estimation for photographic tone
/// reproduction" (JGT 7(1)): `0.18 · 4^((2 log2 Lavg − log2 Lmin − log2 Lmax) / (log2 Lmax − log2 Lmin))`.
///
/// **Local**: the compression is applied to a base layer, an edge-preserving
/// smoothing of the log luminance, and the detail (log luminance minus base)
/// is added back unchanged, so local contrast survives the compression
/// (the base/detail split of Durand and Dorsey 2002, "Fast bilateral
/// filtering for the display of high-dynamic-range images"). The smoothing
/// is the guided filter (He, Sun and Tang 2010, "Guided image filtering"),
/// computed on the reduced copy and applied at full resolution as He and Sun
/// 2015 describe ("Fast guided filter"): the filter's coefficients `a` and
/// `b` are averaged on the copy, enlarged, and the base is `a · log L + b`
/// with the full-resolution log luminance, so it keeps its edges.
///
/// **Color**: each pixel's color keeps its ratios to its luminance; one that
/// would leave the unit cube is pulled toward its gray of the same
/// luminance until its brightest channel is 1.
public struct MergeToneMap: Sendable, Equatable {
    /// Multiplies the luminance before compression (key / log-average).
    public var scale: Double
    /// The white's square, after scaling.
    public var white2: Double
    /// The guided filter's averaged coefficients on the reduced copy:
    /// `a` in `guideA`, `b` in `guideB`.
    public var guideA: MergePlane
    public var guideB: MergePlane
    /// How much of the detail is added back (1: all of it).
    public var detail: Double = 1

    /// Luminance below this (after scaling) is taken as this, so log stays finite.
    public static let floorLuminance: Float = 1e-6
    /// The guided filter's window radius, as a part of the copy's long edge,
    /// and its edge threshold on natural log luminance (a standard deviation of
    /// 0.5, about 0.7 stop: edges stronger than that are kept in the base).
    public static let radiusFraction = 0.02
    public static let epsilon: Float = 0.25

    /// The tone mapping for `radiance`, the merged light on the reduced copy.
    public static func plan(for radiance: MergeBitmap) -> MergeToneMap {
        var luminances = [Float]()
        luminances.reserveCapacity(radiance.count)
        for index in 0..<radiance.count {
            let l = MergeBitmap.luminance(radiance.rgb(index))
            if l > 0 { luminances.append(l) }
        }
        guard !luminances.isEmpty else {
            let plane = MergePlane(width: radiance.width, height: radiance.height)
            return MergeToneMap(scale: 1, white2: 1, guideA: plane, guideB: plane)
        }
        var logSum = 0.0
        for l in luminances { logSum += log(Double(l) + 1e-6) }
        let average = exp(logSum / Double(luminances.count))
        luminances.sort()
        let low = Double(luminances[min(luminances.count - 1, Int(Double(luminances.count) * 0.01))])
        let high = Double(luminances[min(luminances.count - 1, Int(Double(luminances.count) * 0.9999))])
        let key = Self.key(average: average, low: low, high: high)
        let scale = key / average
        let white = max(high * scale, 1)

        let width = radiance.width, height = radiance.height
        var logs = MergePlane(width: width, height: height)
        for index in 0..<radiance.count {
            let l = MergeBitmap.luminance(radiance.rgb(index))
            logs.values[index] = log(max(l * Float(scale), floorLuminance))
        }
        let (a, b) = guidedCoefficients(logs, radius: max(1, Int(Double(max(width, height)) * radiusFraction)),
                                        epsilon: epsilon)
        return MergeToneMap(scale: scale, white2: white * white, guideA: a, guideB: b)
    }

    /// Reinhard's automatic key for a scene's log-average, darkest and brightest luminance.
    public static func key(average: Double, low: Double, high: Double) -> Double {
        let l2min = log2(max(low, 1e-9)), l2max = log2(max(high, 1e-9)), l2avg = log2(max(average, 1e-9))
        guard l2max - l2min > 1e-6 else { return 0.18 }
        return 0.18 * pow(4, (2 * l2avg - l2min - l2max) / (l2max - l2min))
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
        let ls = max(l * Float(scale), Self.floorLuminance)
        let logL = log(ls)
        let base = a * logL + b
        let bs = exp(base)
        let bd = bs * (1 + bs / Float(white2)) / (1 + bs)
        let ld = bd * exp((logL - base) * Float(detail))
        var rgb = e * (ld / l)
        let m = max(rgb.x, rgb.y, rgb.z)
        if m > 1 {
            rgb = ld >= 1 ? SIMD3(repeating: 1) : ld + (rgb - ld) * ((1 - ld) / (m - ld))
        }
        return rgb
    }
}
