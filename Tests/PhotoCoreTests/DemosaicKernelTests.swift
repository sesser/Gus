import Foundation
import Metal
import Testing
@testable import PhotoCore

/// A small full-color picture with what demosaics get wrong: hard edges in
/// every direction, saturated colors, fine stripes, thin colored lines, a
/// smooth gradient and (optionally) noise. Linear, 0 … 1.
enum DemosaicScene {
    static func truth(width: Int, height: Int, noise: Float = 0, seed: UInt64 = 1) -> [SIMD3<Float>] {
        var random = seed
        func uniform() -> Float {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            return Float(random >> 40) / Float(1 << 24)
        }
        func gaussian() -> Float {
            let u = max(uniform(), 1e-7), v = uniform()
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
        var pixels = [SIMD3<Float>](repeating: .zero, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let fx = Float(x) / Float(width), fy = Float(y) / Float(height)
                // A smooth gradient behind everything.
                let r0: Float = 0.15 + 0.3 * fx, g0: Float = 0.2 + 0.25 * fy, b0: Float = 0.35 - 0.2 * fx
                var c = SIMD3<Float>(r0, g0, b0)
                // A saturated red disk and a blue square: edges in every direction.
                let dx = Float(x) - Float(width) * 0.3, dy = Float(y) - Float(height) * 0.35
                let radiusSquared: Float = Float(width * width) * 0.03
                if dx * dx + dy * dy < radiusSquared { c = SIMD3<Float>(0.8, 0.08, 0.05) }
                let squareLeft: Int = width * 6 / 10, squareRight: Int = width * 9 / 10
                let squareTop: Int = height / 10, squareBottom: Int = height * 4 / 10
                if x > squareLeft, x < squareRight, y > squareTop, y < squareBottom { c = SIMD3<Float>(0.05, 0.1, 0.7) }
                // Fine vertical stripes, two pixels wide, and a diagonal edge.
                let lowerTop: Int = height * 6 / 10, middle: Int = width / 2
                if y > lowerTop, x < middle { c = (x / 2) % 2 == 0 ? SIMD3<Float>(0.7, 0.7, 0.7) : SIMD3<Float>(0.1, 0.1, 0.1) }
                if y > lowerTop, x >= middle, x - middle > y - lowerTop { c = SIMD3<Float>(0.6, 0.5, 0.1) }
                // Thin colored lines: one pixel green, two pixels magenta.
                if x == middle + 3, y < height / 2 { c = SIMD3<Float>(0.1, 0.6, 0.1) }
                if y == height / 2 || y == height / 2 + 1 { c = SIMD3<Float>(0.6, 0.1, 0.55) }
                if noise > 0 {
                    let deviates = SIMD3<Float>(gaussian(), gaussian(), gaussian())
                    c += deviates * noise
                }
                pixels[y * width + x] = c
            }
        }
        return pixels
    }

    /// The picture sampled through `pattern` into 16-bit sensor values with a
    /// black level of `black` and a white level of `white`, each channel
    /// divided by its multiplier first (so the demosaic's multipliers give the
    /// picture back).
    static func mosaic(_ truth: [SIMD3<Float>], width: Int, height: Int, pattern: CFAPattern,
                       black: Float = 0, white: Float = 65535, multipliers: SIMD3<Float> = SIMD3(1, 1, 1)) -> SensorMosaic {
        let span = white - black
        var values = [UInt16](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let c = pattern.color(x: x, y: y)
                let v = truth[y * width + x][c] / multipliers[c]
                let level: Float = v * span + black
                let clipped: Float = min(max(level, 0), 65535)
                values[y * width + x] = UInt16(clipped.rounded())
            }
        }
        return SensorMosaic(width: width, height: height, pattern: pattern, values: values,
                            blackPerSite: [Float](repeating: black, count: pattern.period * pattern.period),
                            whiteSpan: span, multipliers: multipliers)!
    }
}

/// The demosaic kernels against their CPU reference (R10, AC8a), on small
/// mosaics that run on every Mac, CI's included.
/// Whether there is a Metal device to run the kernels on (CI's virtual
/// GPUs have one); without one the GPU suites are skipped, saying so.
let hasMetalDevice = MTLCreateSystemDefaultDevice() != nil

@Suite("Demosaic kernels", .enabled(if: hasMetalDevice, "No Metal device: the demosaic kernels need one"))
struct DemosaicKernelTests {
    static let size = 96
    static let u: Float = 0x1p-23

    /// The engine; a compile failure fails the test that asks.
    static func engine() throws -> GPUDemosaic { try GPUDemosaic.shared() }

    static func ulp(_ v: Float) -> Float { max(abs(v).ulp, .leastNonzeroMagnitude) }

    static let patterns: [(String, CFAPattern)] = [
        ("RGGB", .rggb),
        ("GBRG", CFAPattern(period: 2, colors: [1, 2, 0, 1])!),
        ("X-Trans", .xTransSample),
        ("X-Trans, shifted 1 x 2", CFAPattern.xTransSample.shifted(x: 1, y: 2)),
        ("X-Trans, shifted 3 x 5", CFAPattern.xTransSample.shifted(x: 3, y: 5)),
    ]

    static func mosaic(_ pattern: CFAPattern, noise: Float = 0.01) -> SensorMosaic {
        let truth = DemosaicScene.truth(width: size, height: size, noise: noise)
        return DemosaicScene.mosaic(truth, width: size, height: size, pattern: pattern, black: 1022, white: 16383,
                                    multipliers: SIMD3(0.55, 1, 0.72))
    }

    /// The bound (derived, never tuned; CLAUDE.md "Checking image code").
    /// Both sides compute in Float32 with the same operations in the same
    /// order, fp contraction off on the GPU, so +, −, × agree exactly; the
    /// Metal specification allows a division up to 2.5 ULP where the CPU's is
    /// correctly rounded, so a quotient may differ by 3 ULP (δ = 3u).
    ///
    /// - X-Trans green: four weights 1/e², each off by δ relative, blended:
    ///   the blend moves by at most 2δ times the spread of the four estimates;
    ///   the sums of up to four terms add up to 8u relative and the final
    ///   division 3u, so 12u of the result besides. Green sites copy their value.
    /// - X-Trans red and blue: the same for the color difference's blend over
    ///   its neighbours (2δ times their spread, 12u of the color difference and
    ///   of the green); plus what the greens it reads were off by (Gb, the 5 x 5
    ///   window's largest green bound): once through the green itself, once
    ///   through each difference, and through the weights 1/(ε + |Δg|)²,
    ///   whose relative change is at most 2 × 2Gb / ε, times the spread.
    /// - Bayer (the #194 spike's derivation): the green blend's weights each
    ///   3 ULP off: |gh − gv| × 9u, carried into red and blue; plus 1 ULP.
    /// - Half size: one division, 3 ULP.
    @Test("Each kernel's Float32 output is its CPU reference's within the derived bound", arguments: patterns.map(\.0))
    func matchesReference(name: String) throws {
        let engine = try Self.engine()
        let pattern = Self.patterns.first { $0.0 == name }!.1
        let mosaic = Self.mosaic(pattern)
        let gpu = try engine.run(mosaic, precision: .float).floats()
        let cpu = DemosaicReference.demosaic(mosaic)
        let n = Self.size
        let input = DemosaicReference.Input(mosaic)
        let bounds = Self.bounds(input, cpu: cpu)
        var over = 0, identical = 0, worst: Float = 0
        for y in 0..<n {
            for x in 0..<n {
                for c in 0..<3 {
                    let a = gpu[(y * n + x) * 4 + c], b = cpu[x, y, c]
                    let d = abs(a - b)
                    if d == 0 { identical += 1 }
                    let bound = bounds[(y * n + x) * 3 + c]
                    if d > bound { over += 1 }
                    if bound > 0 { worst = max(worst, d / bound) }
                }
                #expect(gpu[(y * n + x) * 4 + 3] == 1)
            }
        }
        print("\(name): \(identical) of \(n * n * 3) values identical to the reference; largest difference \(worst) of its bound")
        #expect(over == 0, "\(over) values over their bound")
    }

    /// Per value bounds of `matchesReference`.
    static func bounds(_ input: DemosaicReference.Input, cpu: DemosaicReference.Picture) -> [Float] {
        let n = input.width, h = input.height
        let delta = 3 * u
        var out = [Float](repeating: 0, count: n * h * 3)
        switch input.pattern.kind {
        case .bayer:
            var spread = [Float](repeating: 0, count: n * h)
            for y in 0..<h {
                for x in 0..<n where input.color(x, y) != 1 {
                    let c0 = input.sample(x, y)
                    let gh = (input.sample(x - 1, y) + input.sample(x + 1, y)) * 0.5
                        + ((2 * c0 - input.sample(x - 2, y)) - input.sample(x + 2, y)) * 0.25
                    let gv = (input.sample(x, y - 1) + input.sample(x, y + 1)) * 0.5
                        + ((2 * c0 - input.sample(x, y - 2)) - input.sample(x, y + 2)) * 0.25
                    spread[y * n + x] = abs(gh - gv)
                }
            }
            for y in 0..<h {
                for x in 0..<n {
                    var m: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            m = max(m, spread[DemosaicReference.mirror(y + dy, h) * n + DemosaicReference.mirror(x + dx, n)])
                        }
                    }
                    for c in 0..<3 { out[(y * n + x) * 3 + c] = m * 9 * u + ulp(cpu[x, y, c]) }
                }
            }
        case .xTrans:
            let tables = DemosaicTables(input.pattern)!
            let border = GPUDemosaic.border(of: tables)
            let p = input.pattern.period
            let green = DemosaicReference.xTransGreen(input, tables: tables, epsilon: GPUDemosaic.epsilon)
            var greenBound = [Float](repeating: 0, count: n * h)
            for y in 0..<h {
                for x in 0..<n where input.color(x, y) != 1 {
                    let g = green[y * n + x]
                    if x < border || y < border || x >= n - border || y >= h - border {
                        greenBound[y * n + x] = 3 * ulp(g)
                        continue
                    }
                    let site = (y % p) * p + x % p
                    var estimates: [Float] = []
                    for taps in tables.greenTaps[site] where !taps.isEmpty {
                        var estimate: Float = 0
                        for tap in taps {
                            let value: Float = input.value(x + Int(tap.dx), y + Int(tap.dy))
                            estimate = estimate + tap.weight * value
                        }
                        estimates.append(estimate)
                    }
                    let spread: Float = (estimates.max() ?? 0) - (estimates.min() ?? 0)
                    let blend: Float = 2 * delta * spread
                    let sums: Float = 12 * u * abs(g)
                    greenBound[y * n + x] = blend + sums + ulp(g)
                }
            }
            for y in 0..<h {
                for x in 0..<n {
                    var gb: Float = 0
                    for dy in -2...2 {
                        for dx in -2...2 {
                            gb = max(gb, greenBound[DemosaicReference.mirror(y + dy, h) * n + DemosaicReference.mirror(x + dx, n)])
                        }
                    }
                    let site = (y % p) * p + x % p
                    let inBorder = x < border || y < border || x >= n - border || y >= h - border
                    out[(y * n + x) * 3 + 1] = greenBound[y * n + x]
                    for c in [0, 2] where c != input.color(x, y) {
                        if inBorder { out[(y * n + x) * 3 + c] = 3 * ulp(cpu[x, y, c]); continue }
                        var ks: [Float] = []
                        for tap in tables.neighbours[site][c] {
                            let qx: Int = x + Int(tap.dx), qy: Int = y + Int(tap.dy)
                            ks.append(green[qy * n + qx] - input.value(qx, qy))
                        }
                        let spread: Float = (ks.max() ?? 0) - (ks.min() ?? 0)
                        let g: Float = green[y * n + x]
                        let k: Float = g - cpu[x, y, c]
                        let throughGreen: Float = gb * (2 + 4 * spread / GPUDemosaic.epsilon)
                        let blend: Float = 2 * delta * spread
                        let sums: Float = 12 * u * (abs(k) + abs(g))
                        out[(y * n + x) * 3 + c] = throughGreen + blend + sums + ulp(cpu[x, y, c])
                    }
                }
            }
        }
        return out
    }

    /// R10's half-float rule: Metal rounds a write to a half-float texture
    /// toward zero (measured in the #194 spike: every inexact value landed
    /// below, none above), so one write is off by less than one half ULP,
    /// 2⁻¹⁰ relative, not round-to-nearest's 2⁻¹¹ (subnormals: 2⁻²⁴ absolute).
    @Test("The half-float output is the Float32 output within one half-float write (2⁻¹⁰)", arguments: patterns.map(\.0))
    func halfOutput(name: String) throws {
        let engine = try Self.engine()
        let pattern = Self.patterns.first { $0.0 == name }!.1
        let mosaic = Self.mosaic(pattern)
        for half in [false, true] {
            let float = try engine.run(mosaic, halfSize: half, precision: .float).floats()
            let halfFloat = try engine.run(mosaic, halfSize: half, precision: .half).floats()
            #expect(float.count == halfFloat.count)
            var over = 0
            for (a, h) in zip(float, halfFloat) where abs(h - a) > max(abs(a) * 0x1p-10, 0x1p-24) { over += 1 }
            #expect(over == 0, "\(over) values over 2⁻¹⁰ (half size \(half))")
        }
    }

    @Test("The half-size bins are their CPU reference's within 3 ULP", arguments: patterns.map(\.0))
    func halfSizeMatchesReference(name: String) throws {
        let engine = try Self.engine()
        let pattern = Self.patterns.first { $0.0 == name }!.1
        let mosaic = Self.mosaic(pattern)
        let image = try engine.run(mosaic, halfSize: true, precision: .float)
        #expect(image.width == Self.size / 2 && image.height == Self.size / 2)
        let gpu = image.floats()
        let cpu = DemosaicReference.binHalf(mosaic)
        var over = 0
        for i in 0..<(image.width * image.height) {
            for c in 0..<3 where abs(gpu[i * 4 + c] - cpu.values[i * 3 + c]) > 3 * Self.ulp(cpu.values[i * 3 + c]) {
                over += 1
            }
        }
        #expect(over == 0)
    }

    /// The kernels give the picture back where it is smooth: a check that
    /// the method is right, beside the reference's check that the kernels
    /// do what it says.
    @Test("Away from edges, a demosaic of a smooth picture gives it back", arguments: patterns.map(\.0))
    func smoothPictureComesBack(name: String) throws {
        let engine = try Self.engine()
        let pattern = Self.patterns.first { $0.0 == name }!.1
        let n = Self.size
        var truth = [SIMD3<Float>](repeating: .zero, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let r: Float = 0.1 + 0.003 * Float(x), g: Float = 0.3 + 0.002 * Float(y), b: Float = 0.25 + 0.001 * Float(x + y)
                truth[y * n + x] = SIMD3<Float>(r, g, b)
            }
        }
        let mosaic = DemosaicScene.mosaic(truth, width: n, height: n, pattern: pattern, multipliers: SIMD3(0.5, 1, 0.8))
        let out = try engine.run(mosaic, precision: .float).floats()
        var worst: Float = 0
        var perChannel: [Float] = [0, 0, 0]
        for y in 8..<(n - 8) {
            for x in 8..<(n - 8) {
                for c in 0..<3 {
                    let e = abs(out[(y * n + x) * 4 + c] - truth[y * n + x][c])
                    worst = max(worst, e)
                    perChannel[c] = max(perChannel[c], e)
                }
            }
        }
        print("\(name): per channel \(perChannel)")
        // The mosaic's 16-bit rounding is 1/65535 of the span, times the inverse multipliers: green
        // everywhere, and Bayer's red and blue (their color differences are averaged over sites placed
        // symmetrically about the pixel).
        #expect(perChannel[1] < 1e-4, "\(perChannel)")
        if pattern.kind == .bayer {
            #expect(worst < 1e-4, "\(worst)")
        } else {
            // X-Trans red and blue: a weighted mean of the color difference G − C over the color's sites
            // within two pixels. The weights favor sites whose green is nearer the center's, so on a
            // slope they lean to one side and the mean lies within the differences' spread over the
            // window: at most |∇(G − C)| times the farthest site, 2√2. A known bias of the method on
            // shaded surfaces, measured in status.md.
            let redSlope: Float = 0.002 * 0.002 + 0.003 * 0.003, blueSlope: Float = 0.001 * 0.001 + 0.001 * 0.001
            let gradients: [Float] = [redSlope.squareRoot(), blueSlope.squareRoot()]
            #expect(perChannel[0] <= gradients[0] * Float(8).squareRoot() + 1e-4, "\(perChannel)")
            #expect(perChannel[2] <= gradients[1] * Float(8).squareRoot() + 1e-4, "\(perChannel)")
        }
    }

    /// Code review C7: the per-color blacks are read at an offset in LibRaw's
    /// struct; this fails if a LibRaw update moves them.
    @Test("LibRaw's black levels are where the unpack reads them")
    func blackLayout() {
        #expect(SensorMosaic.blackLayoutHolds)
    }

    @Test("Half floats read back as their values")
    func halfFloats() {
        let cases: [(UInt16, Float)] = [(0x0000, 0), (0x3C00, 1), (0xC000, -2), (0x0001, 0x1p-24), (0x0400, 0x1p-14),
                                        (0x7BFF, 65504), (0x3555, 0.333251953125), (0x7C00, .infinity)]
        for (bits, value) in cases { #expect(GPUDemosaic.float(half: bits) == value, "\(bits)") }
        #expect(GPUDemosaic.float(half: 0x7E00).isNaN)
    }

    @Test("Floats convert to the nearest half float, as Swift's Float16 does")
    func halfBitsMatchFloat16() {
        for bits in UInt16.min...UInt16.max where bits & 0x7c00 != 0x7c00 {
            let value = GPUDemosaic.float(half: bits)
            #expect(GPUDemosaic.halfBits(value) == bits, "\(bits)")
        }
        var values: [Float] = [0, -0.0, 1e-9, 0x1p-25, 0x1p-25 * 1.5, 0x1p-24 * 1.5, 65504, 65519, 65520, 1e9, -1e9,
                               .infinity, -.infinity, 0.1, 1.0004883, 2049, 2051]
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for _ in 0..<20_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let bits = UInt32(truncatingIfNeeded: state >> 32)
            let value = Float(bitPattern: bits)
            if value.isFinite { values.append(value) }
        }
        for value in values {
            #expect(GPUDemosaic.halfBits(value) == Float16(value).bitPattern, "\(value)")
        }
        #expect(GPUDemosaic.halfBits(.nan) & 0x7c00 == 0x7c00 && GPUDemosaic.halfBits(.nan) & 0x3ff != 0)
    }

    @Test("The X-Trans tables exist for every phase of the pattern, and no other 6 x 6 is taken for X-Trans")
    func tablesForEveryPhase() {
        for y in 0..<6 {
            for x in 0..<6 {
                let shifted = CFAPattern.xTransSample.shifted(x: x, y: y)
                #expect(shifted.kind == .xTrans)
                #expect(DemosaicTables(shifted) != nil, "phase \(x), \(y)")
            }
        }
        // A 6 x 6 tiling of a Bayer pattern has the wrong counts.
        var bayer6: [Int32] = []
        for site in 0..<36 {
            let row = (site / 6) % 2, column = (site % 6) % 2
            bayer6.append(CFAPattern.rggb.colors[row * 2 + column])
        }
        #expect(CFAPattern(period: 6, colors: bayer6) == nil)
        // On a Bayer pattern the green estimate is Hamilton and Adams': the greens' mean plus half the second difference.
        let tables = DemosaicTables(.rggb)!
        let horizontal = tables.greenTaps[0][0].sorted { $0.dx < $1.dx }
        #expect(horizontal.map(\.dx) == [-2, -1, 0, 1, 2])
        #expect(horizontal.map(\.weight) == [-0.25, 0.5, 0.5, 0.5, -0.25])
    }
}
