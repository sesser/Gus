import Foundation
import PhotoFixtures
@testable import PhotoCore

/// The HDR merge's per-pixel math in plain Swift (issue #150, AC10), written
/// from the published methods `MergeMath` and `MergeToneMap` cite, not from
/// the kernels: the merge of the frames with their measured exposures,
/// clipping levels, movements and ghost masks, and the tone mapping with the
/// measured key, white and guide coefficients. Rows from the top, as
/// `LinearImage`; the kernels' coordinates (y up, pixel centers at .5) are
/// converted where they matter.
enum MergeReference {
    /// The broad hat of Reinhard et al. 2005, flat on the open half for the
    /// darkest and brightest frames.
    static func hat(_ z: Double, openTop: Bool, openBottom: Bool) -> Double {
        if openTop, z >= 0.5 { return 1 }
        if openBottom, z <= 0.5 { return 1 }
        guard z > 0, z < 1 else { return 0 }
        return 1 - pow(2 * z - 1, 12)
    }

    /// The merged light at every pixel of the reference, and whether the pixel
    /// is well conditioned: no weight is within float rounding of a
    /// decision (a tap's share at `MergeMath.tapShare`) or on the steep
    /// shoulders of the hat, where `1 - t^12` loses its digits to
    /// cancellation and float rounding is amplified by up to 1/hat.
    static func radiance(frames: [LinearImage], plan: HDRMerger.Plan) -> [SIMD3<Double>] {
        radianceAndConditioning(frames: frames, plan: plan).map(\.0)
    }

    /// Hat values below this are steep enough that float rounding in them
    /// moves the result by more than 2^-17 (12 · 2^-24 / 0.01 ≈ 7e-5 of a weight).
    static let conditionedHat = 0.01

    /// With each pixel's value: whether it is conditioned, and the relative
    /// error the float sample positions alone can put on it (each frame's
    /// samples' spread times its position's rounding, weighted as the merge
    /// weighs the frame).
    static func radianceAndConditioning(frames: [LinearImage], plan: HDRMerger.Plan) -> [(SIMD3<Double>, Bool, Double)] {
        let width = frames[plan.reference].width, height = frames[plan.reference].height
        let exposures = plan.frames.map(\.exposure)
        let darkest = exposures.indices.min { exposures[$0] < exposures[$1] }
        let brightest = exposures.indices.max { exposures[$0] < exposures[$1] }
        var result = [(SIMD3<Double>, Bool, Double)](repeating: (.zero, true, 0), count: width * height)
        for row in 0..<height {
            for x in 0..<width {
                // The pixel's center in Core Image's coordinates.
                let d = SIMD2(Double(x) + 0.5, Double(height - 1 - row) + 0.5)
                var sum = SIMD3<Double>.zero
                var weights = 0.0
                var conditioned = true
                var sampleErrors = 0.0
                for (index, frame) in frames.enumerated() {
                    let framePlan = plan.frames[index]
                    let p = framePlan.homography.inverse.apply(d)
                    guard p.x >= 0.5, p.y >= 0.5, p.x <= Double(frame.width) - 0.5,
                          p.y <= Double(frame.height) - 0.5 else { continue }
                    let b = p - 0.5
                    let f = SIMD2(b.x.rounded(.down), b.y.rounded(.down))
                    let t = b - f
                    func tap(_ dx: Double, _ dy: Double) -> SIMD3<Double> {
                        // Core Image row (from the bottom) to LinearImage row (from the top).
                        // Clamped to the frame, as the kernel's sampler is (such a
                        // sample has no weight).
                        let cx = min(Int(f.x + dx), frame.width - 1), cy = min(Int(f.y + dy), frame.height - 1)
                        let pixel = frame[cx, frame.height - 1 - cy]
                        return SIMD3(Double(pixel.x), Double(pixel.y), Double(pixel.z))
                    }
                    let c00 = tap(0, 0), c10 = tap(1, 0), c01 = tap(0, 1), c11 = tap(1, 1)
                    let rgb = (c00 * (1 - t.x) + c10 * t.x) * (1 - t.y) + (c01 * (1 - t.x) + c11 * t.x) * t.y
                    let share = MergeMath.tapShare
                    var peak = c00.max()
                    if t.x >= share { peak = max(peak, c10.max()) }
                    if t.y >= share { peak = max(peak, c01.max()) }
                    if t.x >= share, t.y >= share { peak = max(peak, c11.max()) }
                    if abs(t.x - share) < 1e-4 || abs(t.y - share) < 1e-4 { conditioned = false }
                    // The kernel's sample position is a float: the inverse
                    // homography's entries rounded to float, three products and
                    // two sums per coordinate and a division, each within 2^-24
                    // of the coordinate's magnitude: about 2^-20 of it in all.
                    // Across a steep edge that moves the mix by spread × error.
                    let peaks = [c00, c10, c01, c11].map { $0.max() }
                    let positionError = max(p.x, p.y) * pow(2, -20)
                    let sampleError = (peaks.max()! - peaks.min()!) * positionError
                    let ghost = min(max(Double(plan.ghosts[index][x, row]), 0), 1)
                    let h = hat(peak / framePlan.clip, openTop: index == darkest, openBottom: index == brightest)
                    if h > 0, h < conditionedHat { conditioned = false }
                    var w = h * framePlan.exposure * (1 - ghost)
                    if index == plan.reference { w = max(w, Double(MergeMath.referenceFloorWeight)) }
                    sum += w / framePlan.exposure * rgb
                    weights += w
                    sampleErrors += w / framePlan.exposure * sampleError
                }
                let value = weights > 0 ? sum / weights : .zero
                let tolerance = weights > 0 ? sampleErrors / weights / max(value.max(), 1e-12) : 0
                result[row * width + x] = (value, conditioned, tolerance)
            }
        }
        return result
    }

    /// Durand and Dorsey's base and detail: the base's log range scaled so
    /// the brightest light is just below white, the detail added back, a
    /// shoulder above the knee, colors kept in
    /// proportion and pulled into the unit cube.
    static func toneMapped(_ radiance: [SIMD3<Double>], plan: MergeToneMap, width: Int) -> [SIMD3<Double>] {
        let luma = SIMD3(0.2627, 0.6780, 0.0593)
        return radiance.enumerated().map { index, e in
            let e = SIMD3(max(e.x, 0), max(e.y, 0), max(e.z, 0))
            let l = (e * luma).sum()
            guard l > 0 else { return .zero }
            let logL = log(max(l, Double(MergeToneMap.floorLuminance)))
            let x = index % width, y = index / width
            let base = Double(plan.guideA[x, y]) * logL + Double(plan.guideB[x, y])
            var ld = exp(plan.compression * (base - plan.top) + (logL - base) * plan.detail)
            // The shoulder: an exponential roll-off above the knee, slope 1 there.
            let knee = Double(MergeToneMap.knee)
            if ld > knee { ld = knee + (1 - knee) * (1 - exp(-(ld - knee) / (1 - knee))) }
            var rgb = e * (ld / l)
            let m = rgb.max()
            if m > 1 {
                rgb = ld >= 1 ? SIMD3(repeating: 1) : ld + (rgb - ld) * ((1 - ld) / (m - ld))
            }
            return rgb
        }
    }
}
