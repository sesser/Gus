import Foundation
@testable import PhotoCore

/// The CPU reference of the demosaic kernels (`DemosaicKernels.source`):
/// the same arithmetic in Float, in the same order, written out plainly (no
/// SIMD, no Core Image), so the GPU's output can be checked against it with
/// a bound derived from float rounding (`DemosaicKernelTests`).
enum DemosaicReference {
    /// RGB per pixel, three values each, rows from the top.
    struct Picture {
        var width: Int
        var height: Int
        var values: [Float]
        subscript(x: Int, y: Int, c: Int) -> Float { values[(y * width + x) * 3 + c] }
    }

    struct Input {
        let mosaic: SensorMosaic
        let normalized: [Float]
        let width: Int
        let height: Int
        let pattern: CFAPattern

        init(_ mosaic: SensorMosaic) {
            self.mosaic = mosaic
            normalized = mosaic.normalized()
            width = mosaic.width
            height = mosaic.height
            pattern = mosaic.pattern
        }

        @inline(__always) func value(_ x: Int, _ y: Int) -> Float { normalized[y * width + x] }
        @inline(__always) func sample(_ x: Int, _ y: Int) -> Float {
            value(DemosaicReference.mirror(x, width), DemosaicReference.mirror(y, height))
        }
        @inline(__always) func color(_ x: Int, _ y: Int) -> Int { pattern.color(x: x, y: y) }

        func windowMean(_ x: Int, _ y: Int, _ c: Int) -> Float {
            if color(x, y) == c { return value(x, y) }
            var sum: Float = 0, count: Float = 0
            for dy in -1...1 {
                for dx in -1...1 where !(dx == 0 && dy == 0) {
                    let mx = mirror(x + dx, width), my = mirror(y + dy, height)
                    guard color(mx, my) == c else { continue }
                    sum = sum + value(mx, my)
                    count = count + 1
                }
            }
            if count > 0 { return sum / count }
            for dy in -2...2 {
                for dx in -2...2 where !(abs(dx) < 2 && abs(dy) < 2) {
                    let mx = mirror(x + dx, width), my = mirror(y + dy, height)
                    guard color(mx, my) == c else { continue }
                    sum = sum + value(mx, my)
                    count = count + 1
                }
            }
            return count > 0 ? sum / count : 0
        }
    }

    @inline(__always) static func mirror(_ i: Int, _ n: Int) -> Int {
        var i = i
        if i < 0 { i = -i }
        if i >= n { i = 2 * n - 2 - i }
        return min(max(i, 0), n - 1)
    }

    static func demosaic(_ mosaic: SensorMosaic, epsilon: Float = GPUDemosaic.epsilon) -> Picture {
        let input = Input(mosaic)
        switch mosaic.pattern.kind {
        case .bayer: return bayer(input, epsilon: epsilon)
        case .xTrans: return xTrans(input, epsilon: epsilon)
        }
    }

    // MARK: X-Trans

    static func xTransGreen(_ input: Input, tables: DemosaicTables, epsilon: Float) -> [Float] {
        let w = input.width, h = input.height, p = input.pattern.period
        let border = GPUDemosaic.border(of: tables)
        var green = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let site = (y % p) * p + x % p
                if input.color(x, y) == 1 { green[y * w + x] = input.value(x, y); continue }
                if x < border || y < border || x >= w - border || y >= h - border {
                    green[y * w + x] = input.windowMean(x, y, 1)
                    continue
                }
                var num: Float = 0, den: Float = 0
                for d in 0..<4 {
                    let taps = tables.greenTaps[site][d]
                    if taps.isEmpty { continue }
                    var g: Float = 0
                    for t in taps { g = g + t.weight * input.value(x + Int(t.dx), y + Int(t.dy)) }
                    var v: Float = 0
                    for q in tables.variationPairs[site][d] {
                        v = v + q.weight * abs(input.value(x + Int(q.ax), y + Int(q.ay)) - input.value(x + Int(q.bx), y + Int(q.by)))
                    }
                    let e = epsilon + v
                    let weight = 1 / (e * e)
                    num = num + weight * g
                    den = den + weight
                }
                green[y * w + x] = max(num / den, 0)
            }
        }
        return green
    }

    static func xTrans(_ input: Input, epsilon: Float) -> Picture {
        let tables = DemosaicTables(input.pattern)!
        let w = input.width, h = input.height, p = input.pattern.period
        let border = GPUDemosaic.border(of: tables)
        let green = xTransGreen(input, tables: tables, epsilon: epsilon)
        var out = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let site = (y % p) * p + x % p
                let own = input.color(x, y)
                let g = green[y * w + x]
                var rgb: [Float] = [0, g, 0]
                let inBorder = x < border || y < border || x >= w - border || y >= h - border
                for c in [0, 2] {
                    if c == own { rgb[c] = input.value(x, y); continue }
                    if inBorder { rgb[c] = input.windowMean(x, y, c); continue }
                    var num: Float = 0, den: Float = 0
                    for t in tables.neighbours[site][c] {
                        let qx = x + Int(t.dx), qy = y + Int(t.dy)
                        let gq = green[qy * w + qx]
                        let k = gq - input.value(qx, qy)
                        let e = epsilon + abs(gq - g)
                        let weight = t.weight / (e * e)
                        num = num + weight * k
                        den = den + weight
                    }
                    rgb[c] = max(g - num / den, 0)
                }
                for c in 0..<3 { out[(y * w + x) * 3 + c] = rgb[c] }
            }
        }
        return Picture(width: w, height: h, values: out)
    }

    // MARK: Bayer

    static func bayerGreen(_ input: Input, epsilon: Float) -> [Float] {
        let w = input.width, h = input.height
        var green = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let c0 = input.sample(x, y)
                if input.color(x, y) == 1 { green[y * w + x] = c0; continue }
                let gl = input.sample(x - 1, y), gr = input.sample(x + 1, y)
                let gu = input.sample(x, y - 1), gd = input.sample(x, y + 1)
                let lapH = (2 * c0 - input.sample(x - 2, y)) - input.sample(x + 2, y)
                let lapV = (2 * c0 - input.sample(x, y - 2)) - input.sample(x, y + 2)
                let gh = (gl + gr) * 0.5 + lapH * 0.25
                let gv = (gu + gd) * 0.5 + lapV * 0.25
                let dh = epsilon + (abs(gl - gr) + abs(lapH))
                let dv = epsilon + (abs(gu - gd) + abs(lapV))
                let wh = 1 / (dh * dh), wv = 1 / (dv * dv)
                let g = (wh * gh + wv * gv) / (wh + wv)
                green[y * w + x] = max(g, 0)
            }
        }
        return green
    }

    static func bayer(_ input: Input, epsilon: Float) -> Picture {
        let w = input.width, h = input.height
        let green = bayerGreen(input, epsilon: epsilon)
        func g(_ x: Int, _ y: Int) -> Float { green[mirror(y, h) * w + mirror(x, w)] }
        var out = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let gc = g(x, y)
                let own = input.color(x, y)
                var rgb: [Float] = [0, gc, 0]
                if own == 1 {
                    let across = input.color(mirror(x + 1, w), y)
                    let horizontal = ((input.sample(x - 1, y) - g(x - 1, y)) + (input.sample(x + 1, y) - g(x + 1, y))) * 0.5
                    let vertical = ((input.sample(x, y - 1) - g(x, y - 1)) + (input.sample(x, y + 1) - g(x, y + 1))) * 0.5
                    rgb[across] = gc + horizontal
                    rgb[2 - across] = gc + vertical
                } else {
                    let a = input.sample(x - 1, y - 1) - g(x - 1, y - 1)
                    let b = input.sample(x + 1, y - 1) - g(x + 1, y - 1)
                    let c = input.sample(x - 1, y + 1) - g(x - 1, y + 1)
                    let d = input.sample(x + 1, y + 1) - g(x + 1, y + 1)
                    let diagonal = (((a + b) + c) + d) * 0.25
                    rgb[own] = input.sample(x, y)
                    rgb[2 - own] = gc + diagonal
                }
                for k in 0..<3 { out[(y * w + x) * 3 + k] = max(rgb[k], 0) }
            }
        }
        return Picture(width: w, height: h, values: out)
    }

    // MARK: Half size

    static func binHalf(_ mosaic: SensorMosaic) -> Picture {
        let input = Input(mosaic)
        let (low, high) = mosaic.pattern.kind == .xTrans ? (-1, 2) : (0, 1)
        let w = input.width, h = input.height
        let ow = w / 2, oh = h / 2
        var out = [Float](repeating: 0, count: ow * oh * 3)
        for gy in 0..<oh {
            for gx in 0..<ow {
                let ox = gx * 2, oy = gy * 2
                var sum: [Float] = [0, 0, 0], count: [Float] = [0, 0, 0]
                for dy in low...high {
                    for dx in low...high {
                        let mx = mirror(ox + dx, w), my = mirror(oy + dy, h)
                        let c = input.color(mx, my)
                        sum[c] = sum[c] + input.value(mx, my)
                        count[c] = count[c] + 1
                    }
                }
                for c in 0..<3 {
                    out[(gy * ow + gx) * 3 + c] = count[c] > 0 ? sum[c] / count[c] : input.windowMean(ox, oy, c)
                }
            }
        }
        return Picture(width: ow, height: oh, values: out)
    }
}

extension DemosaicReference {
    /// One level of the color noise reduction (`denoise` in the Metal
    /// source), on an RGBA image (four values a pixel), over the whole image.
    static func denoiseLevel(_ rgba: [Float], width w: Int, height h: Int, a: SIMD3<Float>, b: SIMD3<Float>,
                             luminanceStrength: Float, colorStrength: Float, step: Int) -> [Float] {
        let taps = GPUDemosaic.ColorNoiseReduction.taps
        let floor = GPUDemosaic.ColorNoiseReduction.varianceFloor
        let hY2 = luminanceStrength * luminanceStrength, hC2 = colorStrength * colorStrength
        var out = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r0 = rgba[i], g0 = rgba[i + 1], b0 = rgba[i + 2]
                let y0 = ((r0 + 2 * g0) + b0) * 0.25
                let k1 = r0 - g0, k2 = b0 - g0
                let vr = max(a.x * max(r0, 0) + b.x, floor)
                let vg = max(a.y * max(g0, 0) + b.y, floor)
                let vb = max(a.z * max(b0, 0) + b.z, floor)
                let vy = ((vr + 4 * vg) + vb) * 0.0625
                let iy = 1 / ((2 * vy) * hY2)
                let i1 = 1 / ((2 * (vr + vg)) * hC2)
                let i2 = 1 / ((2 * (vb + vg)) * hC2)
                var n1: Float = 0, n2: Float = 0, den: Float = 0
                for dy in -2...2 {
                    let qy = mirror(y + dy * step, h)
                    for dx in -2...2 {
                        let qx = mirror(x + dx * step, w)
                        let j = (qy * w + qx) * 4
                        let yq = ((rgba[j] + 2 * rgba[j + 1]) + rgba[j + 2]) * 0.25
                        let q1 = rgba[j] - rgba[j + 1], q2 = rgba[j + 2] - rgba[j + 1]
                        let dl = yq - y0
                        let d1 = q1 - k1, d2 = q2 - k2
                        let ry = 1 + (dl * dl) * iy
                        let rc = 1 + ((d1 * d1) * i1 + (d2 * d2) * i2)
                        let weight = (taps[dy + 2] * taps[dx + 2]) / ((ry * ry) * (rc * rc))
                        n1 = n1 + weight * q1
                        n2 = n2 + weight * q2
                        den = den + weight
                    }
                }
                let c1 = n1 / den, c2 = n2 / den
                let g = y0 - (c1 + c2) * 0.25
                out[i] = max(g + c1, 0)
                out[i + 1] = max(g, 0)
                out[i + 2] = max(g + c2, 0)
                out[i + 3] = 1
            }
        }
        return out
    }
}
