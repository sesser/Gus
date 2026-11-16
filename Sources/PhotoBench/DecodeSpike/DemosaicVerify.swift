import Foundation
import Metal

// SPIKE for issue #194 (question 2): throwaway. The Metal demosaic against its
// CPU reference (`DemosaicReference`) on a crop of each real mosaic, borders
// included (the crop is demosaiced as an image of its own).
//
// The bound (CLAUDE.md, "Checking image code": derived, never tuned): both
// sides compute in Float32 with the same operations in the same order, fp
// contraction off on the GPU. Additions, subtractions and multiplications are
// correctly rounded on both, so they agree exactly unless an operation is
// rounded differently; the Metal specification allows division and the
// reciprocal up to 2.5 ULP in Float32 (Metal Shading Language Specification,
// "Accuracy of Single-Precision Floating-Point Operations"), where the CPU's are
// correctly rounded (0.5 ULP). Each kernel's bound is therefore:
//
// - bilinear (one division of a sum by a count): 3 ULP of the result;
// - mhc (one division by 8, exact in binary: both exact, so 0): 1 ULP of the
//   result, allowing for one rounding difference;
// - ha: the green blend divides three times (two reciprocals, one quotient):
//   each 3 ULP of its value; the blend's result moves at most by
//   |gh − gv| times the relative error of its weights, (3 + 3 + 3) x 2⁻²³,
//   carried into red and blue unchanged; plus 1 ULP for the final roundings.
//
// The 16-bit output of the pipeline then adds one conversion to half float,
// checked against the Float32 GPU output: Metal's texture writes were measured
// to round toward zero, so less than one ULP of half, 2⁻¹⁰ relative (not the
// 2⁻¹¹ of round-to-nearest).
enum DemosaicVerify {
    static func ulp(_ v: Float) -> Float { max(abs(v).ulp, Float.leastNonzeroMagnitude) }

    static func run(_ arguments: Arguments, files: [URL]) throws -> [String: any Sendable] {
        let demosaicer = try MetalDemosaicer()
        let size = arguments.int("crop", default: 768)
        var failures = 0
        for url in files {
            let full = try RawMosaic(url)
            // A crop from the middle, starting on the pattern.
            let x0 = (full.width / 2 - size / 2) / full.period * full.period
            let y0 = (full.height / 2 - size / 2) / full.period * full.period
            var crop = full
            crop.width = size; crop.height = size
            crop.values = (0..<size).flatMap { row in full.values[((y0 + row) * full.width + x0)..<((y0 + row) * full.width + x0 + size)] }
            // The pattern at the crop's origin is the full mosaic's at (x0, y0): both multiples of the period.
            let cfa = DemosaicReference.Plane(width: size, height: size, values: crop.normalized())
            let pattern = DemosaicReference.Pattern(colors: crop.pattern, period: crop.period)
            print("\(url.lastPathComponent) (\(full.isXTrans ? "X-Trans" : "Bayer") \(crop.patternDescription)), crop \(size)x\(size) at (\(x0), \(y0))")
            let algorithms: [DemosaicAlgorithm] = full.isXTrans ? [.bilinear] : DemosaicAlgorithm.allCases
            for algorithm in algorithms {
                let gpu = try demosaicer.read(try demosaicer.run(crop, algorithm: algorithm, format: .rgba32Float).output)
                let gpuHalf = try demosaicer.read(try demosaicer.run(crop, algorithm: algorithm, format: .rgba16Float).output)
                let cpu = DemosaicReference.run(algorithm, cfa, pattern)
                // For ha, the blend's sensitivity: |gh − gv| at each pixel, from the reference's own terms.
                var spread = [Float](repeating: 0, count: size * size)
                if algorithm == .ha {
                    for y in 0..<size {
                        for x in 0..<size where pattern.color(x, y) != 1 {
                            let c0 = cfa.at(x, y)
                            let gh = (cfa.at(x - 1, y) + cfa.at(x + 1, y)) * 0.5 + ((2 * c0 - cfa.at(x - 2, y)) - cfa.at(x + 2, y)) * 0.25
                            let gv = (cfa.at(x, y - 1) + cfa.at(x, y + 1)) * 0.5 + ((2 * c0 - cfa.at(x, y - 2)) - cfa.at(x, y + 2)) * 0.25
                            spread[y * size + x] = abs(gh - gv)
                        }
                    }
                }
                // Red and blue at a pixel read the green of its 3x3 neighbours.
                func neighbourhoodSpread(_ x: Int, _ y: Int) -> Float {
                    var m: Float = 0
                    for dy in -1...1 { for dx in -1...1 { m = max(m, spread[DemosaicReference.mirror(y + dy, size) * size + DemosaicReference.mirror(x + dx, size)]) } }
                    return m
                }
                var exact = 0, over = 0, overHalf = 0, halfAbove = 0, halfBelow = 0, halfNearestMiss = 0
                var worst: Float = 0, worstHalf: Float = 0
                for y in 0..<size {
                    for x in 0..<size {
                        for c in 0..<3 {
                            let a = gpu[(y * size + x) * 4 + c], b = cpu[(y * size + x) * 3 + c]
                            let difference = abs(a - b)
                            if difference == 0 { exact += 1 }
                            let bound: Float
                            switch algorithm {
                            case .bilinear: bound = 3 * ulp(b)
                            case .mhc: bound = ulp(b)
                            case .ha: bound = neighbourhoodSpread(x, y) * 9 * pow(2, -23) + ulp(b)
                            }
                            if difference > bound { over += 1 }
                            if bound > 0 { worst = max(worst, difference / bound) }
                            // Half output against the Float32 GPU output: one conversion. Measured here, Metal's
                            // writes to a half-float texture round toward zero (every inexact value lands below,
                            // none above), so one conversion is off by less than one ULP of half: 2⁻¹⁰ relative,
                            // not round-to-nearest's 2⁻¹¹ (subnormals: 2⁻²⁴ absolute).
                            let h = gpuHalf[(y * size + x) * 4 + c]
                            let halfBound = max(abs(a) * pow(2, -10), pow(2, -24))
                            if abs(h) > abs(a) { halfAbove += 1 } else if abs(h) < abs(a) { halfBelow += 1 }
                            if h != Float(Float16(a)) { halfNearestMiss += 1 }
                            if abs(h - a) > halfBound { overHalf += 1 }
                            worstHalf = max(worstHalf, abs(h - a) / halfBound)
                        }
                    }
                }
                let total = size * size * 3
                failures += over + overHalf
                print("    half writes: \(halfAbove) rounded away from zero, \(halfBelow) toward zero, \(halfNearestMiss) differ from round-to-nearest-even")
                print(String(format: "  %-8@ GPU vs CPU: %d of %d values identical, %d over the bound (largest %.2f of it); "
                             + "half output vs Float32 GPU: %d over 2⁻¹⁰ (largest %.2f of it)",
                             algorithm.rawValue as NSString, exact, total, over, worst, overHalf, worstHalf))
            }
        }
        print(failures == 0 ? "verify: PASS" : "verify: FAIL (\(failures) values over their bound)")
        return ["failures": failures]
    }
}
