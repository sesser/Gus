import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The baseline color noise reduction after our demosaic (R9, R10, AC6,
/// AC7, AC8a): its kernel against the CPU reference, its bands, its
/// half-float write, what it keeps (thin colored lines, edges) and what it
/// removes (color noise in flat areas, against LibRaw's own decode).
@Suite("Color noise reduction", .enabled(if: hasMetalDevice, "No Metal device: the noise reduction kernel needs one"))
struct ColorNoiseReductionTests {
    static let size = 96
    static let u: Float = 0x1p-23

    static func ulp(_ v: Float) -> Float { max(abs(v).ulp, .leastNonzeroMagnitude) }

    /// A demosaiced noisy picture (32-bit floats, no noise reduction) and its model.
    static func input(_ pattern: CFAPattern = .xTransSample, noise: Float = 0.02) throws -> (GPUDemosaic, GPUDemosaic.Image) {
        let engine = try DemosaicKernelTests.engine()
        let truth = DemosaicScene.truth(width: size, height: size, noise: noise)
        let mosaic = DemosaicScene.mosaic(truth, width: size, height: size, pattern: pattern)
        return (engine, try engine.run(mosaic, precision: .float, noiseReduction: nil))
    }

    /// A model for noise of standard deviation 0.02 (normalized, multipliers 1).
    static let channels = (a: SIMD3<Float>(repeating: 1e-3), b: SIMD3<Float>(repeating: 4e-4))

    /// The bound (derived; CLAUDE.md "Checking image code"). Both sides do
    /// the same operations in the same order; +, −, × are correctly rounded
    /// on both, a division may differ by 3 ULP (δ = 3u, Metal's 2.5 ULP and
    /// the CPU's 0.5). The three reciprocals (luminance and two color
    /// scales) are each off by δ; a squared difference times one is then
    /// off by δ + u, 1 + it by δ + 2u (luminance) or δ + 3u (color, two
    /// terms), each squared and multiplied by 2 × that plus u, and the
    /// weight's division adds δ: each weight is off by at most
    /// 5δ + 13u = 28u relative. A mean whose weights are off by ε relative
    /// moves by at most 2ε times the spread of what it averages; its two
    /// sums of 25 terms add up to 25u of the largest term each, and its
    /// division δ. Green is luminance less a quarter of the two color
    /// differences, red and blue green plus theirs, each with one rounding.
    static func bound(_ input: [Float], width w: Int, height h: Int, step: Int, at x: Int, _ y: Int, out: [Float]) -> SIMD3<Float> {
        var low1 = Float.infinity, high1 = -Float.infinity, low2 = Float.infinity, high2 = -Float.infinity
        var largest: Float = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let j = (DemosaicReference.mirror(y + dy * step, h) * w + DemosaicReference.mirror(x + dx * step, w)) * 4
                let q1 = input[j] - input[j + 1], q2 = input[j + 2] - input[j + 1]
                low1 = min(low1, q1); high1 = max(high1, q1); low2 = min(low2, q2); high2 = max(high2, q2)
                largest = max(largest, abs(q1), abs(q2))
            }
        }
        let i = (y * w + x) * 4
        let weightError = 28 * u
        let c1 = 2 * weightError * (high1 - low1) + 50 * u * largest + 3 * u * largest + ulp(largest)
        let c2 = 2 * weightError * (high2 - low2) + 50 * u * largest + 3 * u * largest + ulp(largest)
        let g = 0.25 * (c1 + c2) + ulp(out[i + 1]) + ulp(input[i] + input[i + 1] + input[i + 2])
        return SIMD3(g + c1 + ulp(out[i]), g, g + c2 + ulp(out[i + 2]))
    }

    @Test("One level of the kernel is its CPU reference's within the derived bound", arguments: [1, 2, 4])
    func levelMatchesReference(step: Int) throws {
        let (engine, image) = try Self.input()
        let reduction = GPUDemosaic.ColorNoiseReduction(luminanceStrength: 2, colorStrength: 3, steps: [step])
        let gpu = try engine.denoise(image, channels: Self.channels, reduction: reduction, precision: .float).floats()
        let source = image.floats()
        let cpu = DemosaicReference.denoiseLevel(source, width: Self.size, height: Self.size, a: Self.channels.a,
                                                 b: Self.channels.b, luminanceStrength: 2, colorStrength: 3, step: step)
        var identical = 0, over = 0
        for y in 0..<Self.size {
            for x in 0..<Self.size {
                let limits = Self.bound(source, width: Self.size, height: Self.size, step: step, at: x, y, out: cpu)
                for c in 0..<3 {
                    let i = (y * Self.size + x) * 4 + c
                    if gpu[i] == cpu[i] { identical += 1 }
                    if abs(gpu[i] - cpu[i]) > limits[c] { over += 1 }
                }
            }
        }
        print("Noise reduction, step \(step): \(identical) of \(Self.size * Self.size * 3) values identical to the reference")
        #expect(over == 0)
        // And it did something: the noisy picture's color differences moved.
        #expect(zip(gpu, source).contains { $0 != $1 })
    }

    @Test("Bands give the same image as one pass over the whole picture, in place or not")
    func bandsAreInvisible() throws {
        let (engine, image) = try Self.input()
        let reduction = GPUDemosaic.ColorNoiseReduction(luminanceStrength: 2, colorStrength: 3)
        let whole = try engine.denoise(image, channels: Self.channels, reduction: reduction, precision: .float,
                                       bandHeight: 4096).floats()
        let banded = try engine.denoise(image, channels: Self.channels, reduction: reduction, precision: .float,
                                        bandHeight: 16).floats()
        #expect(whole == banded)
        // The levels one at a time, each over the whole picture, with the color strength halved per level.
        var chained = image
        for (level, step) in [1, 2, 4].enumerated() {
            let one = GPUDemosaic.ColorNoiseReduction(luminanceStrength: 2, colorStrength: 3 / Float(1 << level), steps: [step])
            chained = try engine.denoise(chained, channels: Self.channels, reduction: one, precision: .float)
        }
        #expect(chained.floats() == whole)
        // In place, as decodes run it: the demosaic's own pipeline with the model given.
        let truth = DemosaicScene.truth(width: Self.size, height: Self.size, noise: 0.02)
        let mosaic = DemosaicScene.mosaic(truth, width: Self.size, height: Self.size, pattern: .xTransSample)
        let model = GPUDemosaic.ColorNoiseReduction(luminanceStrength: 2, colorStrength: 3,
                                                    model: NoiseModel(a: 1e-3, b: 4e-4))
        let inPlace = try engine.run(mosaic, precision: .float, noiseReduction: model, bandHeight: 16).floats()
        #expect(inPlace == whole)
    }

    /// R10's half-float rule for this kernel: from the same input, its half
    /// output is its Float32 output with one write, 2⁻¹⁰ relative.
    @Test("The half-float output is the Float32 output within one half-float write (2⁻¹⁰)")
    func halfOutput() throws {
        let (engine, image) = try Self.input()
        let reduction = GPUDemosaic.ColorNoiseReduction(luminanceStrength: 2, colorStrength: 3)
        let float = try engine.denoise(image, channels: Self.channels, reduction: reduction, precision: .float).floats()
        let half = try engine.denoise(image, channels: Self.channels, reduction: reduction, precision: .half).floats()
        var over = 0
        for (a, h) in zip(float, half) where abs(h - a) > max(abs(a) * 0x1p-10, 0x1p-24) { over += 1 }
        #expect(over == 0)
    }

    // MARK: What it keeps and removes

    /// CIELAB of linear sRGB (the synthetic camera's space).
    static func lab(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let p = pointwiseMax(c, .zero)
        let x = (0.4124 * p.x + 0.3576 * p.y + 0.1805 * p.z) / 0.95047
        let y = 0.2126 * p.x + 0.7152 * p.y + 0.0722 * p.z
        let z = (0.0193 * p.x + 0.1192 * p.y + 0.9505 * p.z) / 1.08883
        func f(_ t: Float) -> Float { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        return SIMD3(116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    static func pixel(_ rgba: [Float], _ x: Int, _ y: Int, width: Int) -> SIMD3<Float> {
        let i = (y * width + x) * 4
        return SIMD3(rgba[i], rgba[i + 1], rgba[i + 2])
    }

    /// AC7. On the scene's thin colored lines (one pixel green, two pixels
    /// magenta) and saturated edges, with noise of a high-ISO file's level
    /// and the model that noise has: the lines keep 85% or more of their
    /// color contrast against the background beside them, and at edges the
    /// noise reduction moves the picture by at most ΔE76 3 in the median (as
    /// the PRD asks) against the same scene without noise; on the scene
    /// without noise, the step (with the noisy file's model) moves its edges
    /// by at most 3 at the 95th percentile.
    @Test("Thin colored lines keep their color and edges stay put", arguments: ["RGGB", "X-Trans"])
    func keepsLinesAndEdges(name: String) throws {
        let engine = try DemosaicKernelTests.engine()
        let pattern: CFAPattern = name == "RGGB" ? .rggb : .xTransSample
        let n = 192
        let sigma: Float = 0.015
        let reduction = GPUDemosaic.ColorNoiseReduction(luminanceStrength: GPUDemosaic.ColorNoiseReduction.baseline.luminanceStrength,
                                                        colorStrength: GPUDemosaic.ColorNoiseReduction.baseline.colorStrength,
                                                        model: NoiseModel(a: 0, b: Double(sigma * sigma)))
        func demosaic(noise: Float, _ step: GPUDemosaic.ColorNoiseReduction?) throws -> [Float] {
            let truth = DemosaicScene.truth(width: n, height: n, noise: noise, seed: 3)
            return try engine.run(DemosaicScene.mosaic(truth, width: n, height: n, pattern: pattern), precision: .float,
                                  noiseReduction: step).floats()
        }
        let clean = try demosaic(noise: 0, nil), cleanReduced = try demosaic(noise: 0, reduction)
        let noisy = try demosaic(noise: sigma, nil), reduced = try demosaic(noise: sigma, reduction)
        // Edges: the clean picture's top 10% of L* gradient, 8 pixels from the border.
        let cleanLab = (0..<(n * n)).map { Self.lab(Self.pixel(clean, $0 % n, $0 / n, width: n)) }
        var gradients: [(Float, Int)] = []
        for y in 8..<(n - 8) {
            for x in 8..<(n - 8) {
                let gx = cleanLab[y * n + x + 1].x - cleanLab[y * n + x - 1].x
                let gy = cleanLab[(y + 1) * n + x].x - cleanLab[(y - 1) * n + x].x
                gradients.append(((gx * gx + gy * gy).squareRoot(), y * n + x))
            }
        }
        gradients.sort { $0.0 > $1.0 }
        let edges = gradients.prefix(gradients.count / 10).map(\.1)
        func deltaE(_ a: [Float], _ i: Int) -> Float {
            let d = Self.lab(Self.pixel(a, i % n, i / n, width: n)) - cleanLab[i]
            return (d * d).sum().squareRoot()
        }
        let noisyEdges = edges.map { deltaE(reduced, $0) }.sorted()
        let cleanEdges = edges.map { deltaE(cleanReduced, $0) }.sorted()
        let beforeEdges = edges.map { deltaE(noisy, $0) }.sorted()
        // Line contrast: the line's a*, b* against the mean of the pixels three to the side.
        func contrast(_ a: [Float], line: [(Int, Int)], side: (Int, Int)) -> Float {
            var total: Float = 0
            for (x, y) in line {
                let l = Self.lab(Self.pixel(a, x, y, width: n))
                let s1 = Self.lab(Self.pixel(a, x - side.0, y - side.1, width: n))
                let s2 = Self.lab(Self.pixel(a, x + side.0, y + side.1, width: n))
                let ab = SIMD2(l.y, l.z) - (SIMD2(s1.y, s1.z) + SIMD2(s2.y, s2.z)) / 2
                total += (ab * ab).sum().squareRoot()
            }
            return total / Float(line.count)
        }
        // The scene's lines: x = n/2 + 3 for y < n/2 (green, one pixel); y = n/2 and n/2 + 1 (magenta, two pixels).
        let green = (12..<(n / 2 - 12)).map { (n / 2 + 3, $0) }.filter { abs($0.1 - Int(Double(n) * 0.35)) > 30 }
        let magenta = stride(from: 12, to: n - 12, by: 1).map { ($0, n / 2) }
        for (label, line, side) in [("green 1 px", green, (3, 0)), ("magenta 2 px", magenta, (0, 3))] {
            let before = contrast(noisy, line: line, side: side), after = contrast(reduced, line: line, side: side)
            let cleanBefore = contrast(clean, line: line, side: side), cleanAfter = contrast(cleanReduced, line: line, side: side)
            print(String(format: "%@ %@: line contrast %.2f → %.2f (%.0f%%), without noise %.2f → %.2f (%.0f%%)", name, label,
                         before, after, after / before * 100, cleanBefore, cleanAfter, cleanAfter / cleanBefore * 100))
            #expect(after >= 0.85 * before, "\(label)")
            #expect(cleanAfter >= 0.85 * cleanBefore, "\(label), without noise")
        }
        print(String(format: "%@: edge ΔE against the clean demosaic, median before %.2f, after %.2f; without noise p95 %.2f",
                     name, beforeEdges[beforeEdges.count / 2], noisyEdges[noisyEdges.count / 2],
                     cleanEdges[cleanEdges.count * 95 / 100]))
        #expect(noisyEdges[noisyEdges.count / 2] <= 3)
        #expect(cleanEdges[cleanEdges.count * 95 / 100] <= 3)
    }

    /// AC6's flat patches: a grey ramp with noise of a known level, as a DNG,
    /// through our decode and LibRaw's: the color difference noise of ours,
    /// in the flat interior, is at most LibRaw's. The model is estimated
    /// from the file, as for a real raw.
    @Test("Color noise in flat areas is at most LibRaw's, and a decode runs the baseline step", arguments: ["RGGB", "X-Trans"])
    func flatColorNoise(name: String) async throws {
        _ = try DemosaicKernelTests.engine()
        let pattern: CFAPattern = name == "RGGB" ? .rggb : .xTransSample
        let n = 516
        let sigma = 0.01
        var random = SplitMixRandom(seed: 9)
        var values = Data(count: n * n * 2)
        values.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt16.self)
            for y in 0..<n {
                for x in 0..<n {
                    let level = 0.05 + 0.5 * Double(x) / Double(n)
                    let v = level + random.gaussian() * sigma
                    out[y * n + x] = UInt16(min(max(v * 65535, 0), 65535).rounded()).littleEndian
                }
            }
        }
        _ = pattern.color(x: 0, y: 0)
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "flat-\(name).dng")
            var options = SyntheticDNG.Options(width: n, height: n, seed: 1)
            options.cfaPeriod = pattern.period
            options.cfaColors = pattern.colors.map(UInt8.init)
            try SyntheticDNG.write(to: url, options: options, mosaic: values)
            func spread(_ choice: LibRawDecoder.DemosaicChoice, stepOff: Bool = false) throws -> (Float, LibRawDecoder.Demosaic) {
                let output = try stepOff
                    ? GPUDemosaic.$decodeNoiseReduction.withValue(nil) {
                        try LibRawDecoder.decode(url, lensCorrections: false, demosaic: choice)
                    }
                    : LibRawDecoder.decode(url, lensCorrections: false, demosaic: choice)
                let rgba = ReferenceTests.renderLinear(output.linear).pixels
                // Each 16-pixel column of the interior is close to one level: its color differences' deviation.
                var total: Float = 0, count: Float = 0
                for left in stride(from: 32, to: n - 48, by: 16) {
                    var c1: [Float] = [], c2: [Float] = []
                    for y in 32..<(n - 32) {
                        for x in left..<(left + 16) {
                            let i = (y * n + x) * 4
                            c1.append(rgba[i] - rgba[i + 1])
                            c2.append(rgba[i + 2] - rgba[i + 1])
                        }
                    }
                    for c in [c1, c2] {
                        let mean = c.reduce(0, +) / Float(c.count)
                        total += (c.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(c.count)).squareRoot()
                        count += 1
                    }
                }
                return (total / count, output.demosaic)
            }
            let (ours, method) = try spread(.automatic)
            let (libRaw, _) = try spread(.libRaw)
            let (kernelAlone, _) = try spread(.automatic, stepOff: true)
            print(String(format: "%@: color difference noise, ours (%@) %.5f, kernel alone %.5f, LibRaw's %.5f (%.2fx, %.2fx)",
                         name, "\(method)" as NSString, ours, kernelAlone, libRaw, ours / libRaw, kernelAlone / libRaw))
            #expect(method == .gpu(pattern.kind))
            // AC6's flat patches: at most LibRaw's.
            #expect(ours <= libRaw)
            // And the decode runs the baseline step (R9; QA Q1): the kernel alone measures 0.85x (RGGB) and
            // 0.69x (X-Trans) of LibRaw's here, with the step 0.25x and 0.20x, so a decode without it can't
            // reach half of LibRaw's, and the default decode is quieter than one with the step off.
            #expect(ours <= 0.5 * libRaw)
            #expect(ours < kernelAlone)
        }
    }
}

/// A seeded generator of normal deviates (Box–Muller over SplitMix64), for test pictures.
struct SplitMixRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func gaussian() -> Double {
        let u = (Double(next() >> 11) + 0.5) / Double(1 << 53)
        let v = Double(next() >> 11) / Double(1 << 53)
        return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
    }
}
