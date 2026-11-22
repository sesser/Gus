import Foundation
@testable import PhotoCore

/// The guided filter of detection masks (issue #88, R7) in plain Swift, in
/// double precision: He, Sun and Tang, "Guided Image Filtering" (TPAMI
/// 35(6), 2013), eqs. 6 to 8, gray guide, (2r+1)² windows with the edge
/// pixels repeated, then q clamped to 0 … 1. The stretch before it is
/// bilinear with pixel centers aligned and edges repeated. Images are
/// row-major, top row first.
///
/// `GuidedMaskFilter` must agree with it within `tolerance`, a first-order
/// bound on what the GPU's half-float intermediates can change: every value
/// the GPU stores between passes is off by at most 2⁻¹¹ of itself (the unit
/// roundoff of an 11-bit significand), propagated through the formulas
/// below to q. Float arithmetic inside the kernels adds `floatSlack`.
enum GuidedFilterReference {
    /// The unit roundoff of half float.
    static let u = 0x1p-11
    /// Float evaluation inside the kernels (24-bit significand, sums of up to a few hundred terms).
    static let floatSlack = 0x1p-16

    /// `pixels` stretched over `width` × `height`.
    static func stretch(_ pixels: MaskRaster.Pixels, width: Int, height: Int) -> [Double] {
        let w = pixels.width, h = pixels.height
        let sx = Double(w) / Double(width), sy = Double(h) / Double(height)
        var out = [Double](repeating: 0, count: width * height)
        func level(_ x: Int, _ y: Int) -> Double { Double(pixels.levels[y * w + x]) / 255 }
        for y in 0..<height {
            let fy = min(max((Double(y) + 0.5) * sy - 0.5, 0), Double(h - 1))
            let y0 = Int(fy), y1 = min(y0 + 1, h - 1), ty = fy - Double(y0)
            for x in 0..<width {
                let fx = min(max((Double(x) + 0.5) * sx - 0.5, 0), Double(w - 1))
                let x0 = Int(fx), x1 = min(x0 + 1, w - 1), tx = fx - Double(x0)
                let top = level(x0, y0) * (1 - tx) + level(x1, y0) * tx
                let bottom = level(x0, y1) * (1 - tx) + level(x1, y1) * tx
                out[y * width + x] = top * (1 - ty) + bottom * ty
            }
        }
        return out
    }

    /// Means over (2r+1)² windows, edge pixels repeated: rows, then columns.
    static func box(_ values: [Double], _ width: Int, _ height: Int, _ r: Int) -> [Double] {
        rows(columns(values, width, height, r), width, height, r)
    }

    /// Means along rows of 2r+1 (edges repeated).
    static func rows(_ values: [Double], _ width: Int, _ height: Int, _ r: Int) -> [Double] {
        var out = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for k in -r...r { sum += values[y * width + min(max(x + k, 0), width - 1)] }
                out[y * width + x] = sum / Double(2 * r + 1)
            }
        }
        return out
    }

    /// Means down columns of 2r+1 (edges repeated).
    static func columns(_ values: [Double], _ width: Int, _ height: Int, _ r: Int) -> [Double] {
        var out = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for k in -r...r { sum += values[min(max(y + k, 0), height - 1) * width + x] }
                out[y * width + x] = sum / Double(2 * r + 1)
            }
        }
        return out
    }

    struct Result {
        var q: [Double]
        /// Per pixel: how far the GPU may be from `q`.
        var tolerance: [Double]
    }

    /// q for input `p` and guide `guide`, with the tolerance for the GPU.
    static func filter(p: [Double], guide: [Double], width: Int, height: Int, radius r: Int,
                       epsilon: Double = GuidedMaskFilter.epsilon) -> Result {
        let n = width * height
        let product = { (a: [Double], b: [Double]) in zip(a, b).map(*) }
        let meanI = box(guide, width, height, r), meanP = box(p, width, height, r)
        let variance = zip(box(product(guide, guide), width, height, r), meanI).map { $0 - $1 * $1 }
        let meanIP = box(product(guide, p), width, height, r)
        var a = [Double](repeating: 0, count: n), b = a
        for i in 0..<n {
            let c = meanIP[i] - meanI[i] * meanP[i]
            a[i] = c / (variance[i] + epsilon)
            b[i] = meanP[i] - a[i] * meanI[i]
        }
        let meanA = box(a, width, height, r), meanB = box(b, width, height, r)
        var q = [Double](repeating: 0, count: n)
        for i in 0..<n { q[i] = min(max(meanA[i] * guide[i] + meanB[i], 0), 1) }

        // The bound. What the GPU stores between its passes, as the reference
        // has it: the rows pass's means and moments (along rows of 2r+1).
        let rowI = rows(guide, width, height, r), rowP = rows(p, width, height, r)
        let rowVar = zip(rows(product(guide, guide), width, height, r), rowI).map { $0 - $1 * $1 }
        let rowIP = rows(product(guide, p), width, height, r)
        let rowC = (0..<n).map { rowIP[$0] - rowI[$0] * rowP[$0] }
        let rowAB = (rows(a, width, height, r), rows(b, width, height, r))
        let columnsMax = { (values: [Double]) in columnMaximum(values, width, height, r) }
        let windowMax = { (values: [Double]) in columnsMax(rowMaximum(values, width, height, r)) }
        // Over each window: the largest error of a stored row value (u of
        // it), and of the inputs (p, stored by the stretch pass; the guide,
        // by the step before).
        let mIErr = columnsMax(rowI.map { u * abs($0) }), mPErr = columnsMax(rowP.map { u * abs($0) })
        let vErr = columnsMax(rowVar.map { u * abs($0) }), cErr = columnsMax(rowC.map { u * abs($0) })
        let inputP = windowMax(p.map { u * abs($0) }), inputI = windowMax(guide.map { u * abs($0) })
        let spreadI = windowMax(zip(guide, meanI).map { abs($0 - $1) })
        let spreadP = windowMax(zip(p, meanP).map { abs($0 - $1) })
        // a_k's error from the moments it is computed from. A row mean's error
        // enters the between-rows terms against the window's mean, itself off
        // by as much: twice. The inputs' errors move the moments by at most
        // their size times the other's spread (first order).
        var aError = [Double](repeating: 0, count: n), meanError = aError
        for k in 0..<n {
            let dV = vErr[k] + 2 * spreadI[k] * (2 * mIErr[k] + inputI[k])
            let dC = cErr[k] + spreadP[k] * (2 * mIErr[k] + inputI[k]) + spreadI[k] * (2 * mPErr[k] + inputP[k])
            aError[k] = (dC + abs(a[k]) * dV) / (variance[k] + epsilon)
            // b_k = p̄_k − a_k μ_k with the GPU's own a_k: the means' errors.
            meanError[k] = mPErr[k] + inputP[k] + abs(a[k]) * (mIErr[k] + inputI[k])
        }
        // q_i = mean over k ∋ i of a_k (I_i − μ_k) + p̄_k, so a_k's error
        // counts against I_i − μ_k, not I_i and μ_k apart.
        var aTerm = [Double](repeating: 0, count: n)
        let count = Double((2 * r + 1) * (2 * r + 1))
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                var sum = 0.0
                for dy in -r...r {
                    let ky = min(max(y + dy, 0), height - 1)
                    for dx in -r...r {
                        let k = ky * width + min(max(x + dx, 0), width - 1)
                        sum += aError[k] * abs(guide[i] - meanI[k])
                    }
                }
                aTerm[i] = sum / count
            }
        }
        let meansTerm = box(meanError, width, height, r)
        // Storage: a and b, then their row means.
        let storedA = box(a.map { u * abs($0) }, width, height, r), storedB = box(b.map { u * abs($0) }, width, height, r)
        let rowsA = columnsMax(rowAB.0.map { u * abs($0) }), rowsB = columnsMax(rowAB.1.map { u * abs($0) })
        var tolerance = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let g = abs(guide[i])
            tolerance[i] = aTerm[i] + meansTerm[i] + (storedA[i] + rowsA[i]) * g + storedB[i] + rowsB[i]
                + abs(meanA[i]) * u * g + u * q[i] + floatSlack * (1 + abs(meanA[i]) + abs(meanB[i]))
        }
        return Result(q: q, tolerance: tolerance)
    }

    static func rowMaximum(_ values: [Double], _ width: Int, _ height: Int, _ r: Int) -> [Double] {
        var out = values
        for y in 0..<height {
            for x in 0..<width {
                var m = 0.0
                for k in -r...r { m = max(m, values[y * width + min(max(x + k, 0), width - 1)]) }
                out[y * width + x] = m
            }
        }
        return out
    }

    static func columnMaximum(_ values: [Double], _ width: Int, _ height: Int, _ r: Int) -> [Double] {
        var out = values
        for y in 0..<height {
            for x in 0..<width {
                var m = 0.0
                for k in -r...r { m = max(m, values[min(max(y + k, 0), height - 1) * width + x]) }
                out[y * width + x] = m
            }
        }
        return out
    }
}
