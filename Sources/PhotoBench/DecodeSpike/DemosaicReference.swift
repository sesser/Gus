import Foundation

// SPIKE for issue #194 (question 2): throwaway. The CPU reference of the
// Metal demosaic kernels (`MetalDemosaicer.source`): the same arithmetic in
// Float, in the same order, written out plainly (no SIMD, no Core Image), so
// the GPU's output can be checked against it with a bound derived from float
// rounding (`DemosaicVerify`).
enum DemosaicReference {
    struct Plane {
        var width: Int
        var height: Int
        var values: [Float]
        @inline(__always) func at(_ x: Int, _ y: Int) -> Float { values[mirror(y, height) * width + mirror(x, width)] }
    }

    @inline(__always) static func mirror(_ i: Int, _ n: Int) -> Int {
        var i = i
        if i < 0 { i = -i }
        if i >= n { i = 2 * n - 2 - i }
        return min(max(i, 0), n - 1)
    }

    struct Pattern {
        var colors: [Int32]
        var period: Int
        @inline(__always) func color(_ x: Int, _ y: Int) -> Int { Int(colors[(y % period) * period + x % period]) }
    }

    /// RGB per pixel, row by row (3 values each).
    static func bilinear(_ cfa: Plane, _ p: Pattern) -> [Float] {
        let w = cfa.width, h = cfa.height
        var out = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                var sum: [Float] = [0, 0, 0], count: [Float] = [0, 0, 0]
                let own = p.color(x, y)
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let mx = mirror(x + dx, w), my = mirror(y + dy, h)
                        let c = p.color(mx, my)
                        sum[c] = sum[c] + cfa.values[my * w + mx]
                        count[c] = count[c] + 1
                    }
                }
                for c in 0..<3 where c != own && count[c] == 0 {
                    for dy in -2...2 {
                        for dx in -2...2 where !(abs(dx) < 2 && abs(dy) < 2) {
                            let mx = mirror(x + dx, w), my = mirror(y + dy, h)
                            guard p.color(mx, my) == c else { continue }
                            sum[c] = sum[c] + cfa.values[my * w + mx]
                            count[c] = count[c] + 1
                        }
                    }
                }
                for c in 0..<3 { out[(y * w + x) * 3 + c] = c == own ? cfa.values[y * w + x] : sum[c] / count[c] }
            }
        }
        return out
    }

    static func mhc(_ cfa: Plane, _ p: Pattern) -> [Float] {
        let w = cfa.width, h = cfa.height
        var out = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let c0 = cfa.at(x, y)
                let l1 = cfa.at(x - 1, y), r1 = cfa.at(x + 1, y), u1 = cfa.at(x, y - 1), d1 = cfa.at(x, y + 1)
                let l2 = cfa.at(x - 2, y), r2 = cfa.at(x + 2, y), u2 = cfa.at(x, y - 2), d2 = cfa.at(x, y + 2)
                let ul = cfa.at(x - 1, y - 1), ur = cfa.at(x + 1, y - 1), dl = cfa.at(x - 1, y + 1), dr = cfa.at(x + 1, y + 1)
                let orth1 = ((l1 + r1) + u1) + d1
                let orth2 = ((l2 + r2) + u2) + d2
                let diag = ((ul + ur) + dl) + dr
                let own = p.color(x, y)
                var rgb: [Float] = [0, 0, 0]
                if own == 1 {
                    let across = p.color(mirror(x + 1, w), y)
                    let rowColor = ((((5 * c0 + 4 * (l1 + r1)) - (l2 + r2)) - diag) + 0.5 * (u2 + d2)) / 8
                    let columnColor = ((((5 * c0 + 4 * (u1 + d1)) - (u2 + d2)) - diag) + 0.5 * (l2 + r2)) / 8
                    rgb[1] = c0; rgb[across] = rowColor; rgb[2 - across] = columnColor
                } else {
                    let green = ((4 * c0 + 2 * orth1) - orth2) / 8
                    let other = ((6 * c0 + 2 * diag) - 1.5 * orth2) / 8
                    rgb[own] = c0; rgb[1] = green; rgb[2 - own] = other
                }
                for c in 0..<3 { out[(y * w + x) * 3 + c] = max(rgb[c], 0) }
            }
        }
        return out
    }

    static func haGreen(_ cfa: Plane, _ p: Pattern, eps: Float) -> Plane {
        let w = cfa.width, h = cfa.height
        var green = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let c0 = cfa.at(x, y)
                if p.color(x, y) == 1 { green[y * w + x] = c0; continue }
                let gl = cfa.at(x - 1, y), gr = cfa.at(x + 1, y), gu = cfa.at(x, y - 1), gd = cfa.at(x, y + 1)
                let lapH = (2 * c0 - cfa.at(x - 2, y)) - cfa.at(x + 2, y)
                let lapV = (2 * c0 - cfa.at(x, y - 2)) - cfa.at(x, y + 2)
                let gh = (gl + gr) * 0.5 + lapH * 0.25
                let gv = (gu + gd) * 0.5 + lapV * 0.25
                let dh = eps + (abs(gl - gr) + abs(lapH))
                let dv = eps + (abs(gu - gd) + abs(lapV))
                let wh = 1 / (dh * dh), wv = 1 / (dv * dv)
                let g = (wh * gh + wv * gv) / (wh + wv)
                green[y * w + x] = max(g, 0)
            }
        }
        return Plane(width: w, height: h, values: green)
    }

    static func ha(_ cfa: Plane, _ p: Pattern, eps: Float) -> [Float] {
        let w = cfa.width, h = cfa.height
        let green = haGreen(cfa, p, eps: eps)
        var out = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let g = green.at(x, y)
                let own = p.color(x, y)
                var rgb: [Float] = [0, g, 0]
                if own == 1 {
                    let across = p.color(mirror(x + 1, w), y)
                    let horizontal = ((cfa.at(x - 1, y) - green.at(x - 1, y)) + (cfa.at(x + 1, y) - green.at(x + 1, y))) * 0.5
                    let vertical = ((cfa.at(x, y - 1) - green.at(x, y - 1)) + (cfa.at(x, y + 1) - green.at(x, y + 1))) * 0.5
                    rgb[across] = g + horizontal
                    rgb[2 - across] = g + vertical
                } else {
                    let a = cfa.at(x - 1, y - 1) - green.at(x - 1, y - 1)
                    let b = cfa.at(x + 1, y - 1) - green.at(x + 1, y - 1)
                    let c = cfa.at(x - 1, y + 1) - green.at(x - 1, y + 1)
                    let d = cfa.at(x + 1, y + 1) - green.at(x + 1, y + 1)
                    let diagonal = (((a + b) + c) + d) * 0.25
                    rgb[own] = cfa.at(x, y)
                    rgb[2 - own] = g + diagonal
                }
                for k in 0..<3 { out[(y * w + x) * 3 + k] = max(rgb[k], 0) }
            }
        }
        return out
    }

    static func run(_ algorithm: DemosaicAlgorithm, _ cfa: Plane, _ p: Pattern) -> [Float] {
        switch algorithm {
        case .bilinear: bilinear(cfa, p)
        case .mhc: mhc(cfa, p)
        case .ha: ha(cfa, p, eps: MetalDemosaicer.epsilon)
        }
    }

    /// The largest absolute input in each pixel's 5x5 window: the scale of
    /// the float rounding a kernel's sums can make there.
    static func windowMax(_ cfa: Plane) -> [Float] {
        let w = cfa.width, h = cfa.height
        var rows = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var m: Float = 0
                for dx in -2...2 { m = max(m, abs(cfa.at(x + dx, y))) }
                rows[y * w + x] = m
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var m: Float = 0
                for dy in -2...2 { m = max(m, rows[mirror(y + dy, h) * w + x]) }
                out[y * w + x] = m
            }
        }
        return out
    }
}
