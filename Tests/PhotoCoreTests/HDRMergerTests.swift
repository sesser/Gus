import CoreImage
import Foundation
import PhotoFixtures
import Testing
import simd
@testable import PhotoCore

extension MemoryHeavy {
    /// The merge's core on synthetic brackets (issue #150): radiance, ghosts and
    /// tone mapping, without files.
    @Suite("HDR merge core")
    struct HDRMergerTests {
        static let width = 600
        static let height = 400

        static func frames(_ frames: [HDRBracket.Frame], width: Int = width, height: Int = height) -> [CIImage] {
            frames.map { HDRBracket.image($0, width: width, height: height).ciImage }
        }

        static func merge(_ bracket: [HDRBracket.Frame], reference: Int, width: Int = width, height: Int = height)
            throws -> (HDRMerger, HDRMerger.Plan, CIImage) {
            let merger = HDRMerger()
            let images = frames(bracket, width: width, height: height)
            let copies = images.map { MergeBitmap.render($0, context: merger.context)! }
            let plan = try merger.plan(measuring: copies, reference: reference, metadataExposures: bracket.map { _ in nil })
            return (merger, plan, try merger.radiance(plan, frames: images))
        }

        @Test("Three exposures merge to the scene's light, measured exposures within 1% of the truth")
        func recoversRadiance() throws {
            let bracket = [HDRBracket.Frame(ev: -2), HDRBracket.Frame(ev: 0), HDRBracket.Frame(ev: 2)]
            let (merger, plan, radiance) = try Self.merge(bracket, reference: 1)
            for (index, frame) in bracket.enumerated() {
                let truth = pow(2, frame.ev)
                print("exposure \(index): \(plan.frames[index].exposure) truth \(truth) clip \(plan.frames[index].clip)")
                #expect(abs(plan.frames[index].exposure / truth - 1) < 0.01)
            }
            let merged = try #require(MergeBitmap.render(radiance, context: merger.context))
            let truth = HDRBracket.radianceImage(width: Self.width, height: Self.height)
            // Away from edges: next to one, a fraction of a pixel of alignment
            // error mixes in a neighbor up to 3,600 times brighter.
            var worst: Float = 0
            var compared = 0
            for y in 1..<(Self.height - 1) {
                for x in 1..<(Self.width - 1) {
                    var low = Float.infinity, high: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let p = truth[x + dx, y + dy]
                            let l = MergeBitmap.luminance(SIMD3(p.x, p.y, p.z))
                            low = min(low, l)
                            high = max(high, l)
                        }
                    }
                    guard high < low * 1.25 else { continue }
                    compared += 1
                    let m = merged.rgb(x: x, y: y), p = truth[x, y], t = SIMD3(p.x, p.y, p.z)
                    worst = max(worst, simd_reduce_max(abs(m - t) / t))
                }
            }
            print("compared \(compared) pixels")
            print("worst relative radiance error \(worst)")

            #expect(worst < 0.02)
        }
    }
}

extension MemoryHeavy.HDRMergerTests {
    /// The frames' tone-mapped merge rendered on the GPU, and the CPU
    /// reference's, with the same plan.
    @Test("AC10: the merge and tone mapping match their CPU reference")
    func matchesReference() throws {
        let bracket = [HDRBracket.Frame(ev: -2, shift: SIMD2(3.25, -2.5), rotationDegrees: 0.3), HDRBracket.Frame(ev: 0),
                       HDRBracket.Frame(ev: 2, shift: SIMD2(-2, 1.75))]
        let linear = bracket.map { HDRBracket.image($0, width: Self.width, height: Self.height) }
        let merger = HDRMerger()
        let copies = linear.map { MergeBitmap(width: $0.width, height: $0.height, pixels: $0.pixels) }
        let plan = try merger.plan(measuring: copies, reference: 1, metadataExposures: [nil, nil, nil])
        let radiance = try merger.radiance(plan, frames: linear.map(\.ciImage))
        let mapped = try merger.toneMapped(plan, radiance: radiance)
        let gpuRadiance = try #require(MergeBitmap.render(radiance, context: merger.context))
        let gpu = try #require(MergeBitmap.render(mapped, context: merger.context))
        let conditioned = MergeReference.radianceAndConditioning(frames: linear, plan: plan)
        let cpuRadiance = conditioned.map(\.0)
        let cpu = MergeReference.toneMapped(cpuRadiance, plan: plan.toneMap, width: Self.width)
        let compared = conditioned.indices.filter { conditioned[$0].1 }
        print("compared \(compared.count) of \(conditioned.count) pixels")
        // Most pixels are well conditioned; the rest sit on a clipping edge.
        #expect(compared.count >= conditioned.count * 95 / 100)
        // Float32 on the GPU against Double here: about 20 roundings of 2^-24
        // each, and Metal's log and exp within 4 ulp (2^-21 relative) on the
        // tone-mapping path: a relative tolerance of 2^-17 (7.6e-6) covers
        // both with room, plus 2^-24 absolute near black. On top of it, each
        // pixel's own share from the float sample positions (a coordinate of
        // a few hundred pixels carries about 2^-22 of itself), which an edge
        // turns into a change of value; the tone mapping's slope in log terms
        // is at most 1, so the same relative tolerance holds after it.
        let relative = pow(2.0, -17.0), absolute = pow(2.0, -24.0)
        var worstRadiance = 0.0, worstMapped = 0.0, worstAt = 0
        for index in compared {
            let g = gpuRadiance.rgb(index), m = gpu.rgb(index)
            let allowed = relative + conditioned[index].2
            for c in 0..<3 {
                let r = cpuRadiance[index][c], t = cpu[index][c]
                let e = abs(Double(g[c]) - r) / (abs(r) + absolute / relative) / allowed
                if e > worstRadiance { worstRadiance = e; worstAt = index }
                worstMapped = max(worstMapped, abs(Double(m[c]) - t) / (abs(t) + absolute / relative) / allowed)
            }
        }
        print("worst (as a share of each pixel's tolerance) radiance at \(worstAt % Self.width),\(worstAt / Self.width): \(gpuRadiance.rgb(worstAt)) vs \(cpuRadiance[worstAt]); ghosts \(plan.ghosts.map { $0[worstAt % Self.width, worstAt / Self.width] })")
        print("worst relative difference: radiance \(worstRadiance), tone mapped \(worstMapped)")
        #expect(worstRadiance <= 1)
        #expect(worstMapped <= 1)
    }

    /// Next to an edge: the 3 x 3 neighborhood's luminance varies by more
    /// than 25%, where a fraction of a pixel of difference in the measured
    /// movement (Vision's answer depends on the content) changes the value.
    static func isEdge(_ image: MergeBitmap, _ x: Int, _ y: Int) -> Bool {
        var low = Float.infinity, high: Float = 0
        for dy in -1...1 {
            for dx in -1...1 {
                let l = MergeBitmap.luminance(image.rgb(x: min(max(x + dx, 0), image.width - 1),
                                                        y: min(max(y + dy, 0), image.height - 1)))
                low = min(low, l)
                high = max(high, l)
            }
        }
        return high > low * 1.25
    }

    /// Distinct 8-bit codes for each step of a row, encoded with the sRGB curve.
    static func codes(_ values: [Double]) -> [Int] {
        values.map { v in
            let c = min(max(v, 0), 1)
            let e = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
            return Int((e * 255).rounded())
        }
    }

    /// A step's mean luminance over its rectangle's middle.
    static func stepValue(_ rect: CGRect, width: Int, height: Int, value: (Int, Int) -> Double) -> Double {
        let inner = rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.25)
        var sum = 0.0, n = 0.0
        for y in Int(inner.minY * Double(height))..<Int(inner.maxY * Double(height)) {
            for x in Int(inner.minX * Double(width))..<Int(inner.maxX * Double(width)) {
                sum += value(x, y)
                n += 1
            }
        }
        return sum / n
    }

    @Test("AC10: the result holds shadow and highlight steps no single frame holds in 8 bits, without clipping")
    func holdsTheRange() throws {
        let bracket = [HDRBracket.Frame(ev: -2), HDRBracket.Frame(ev: 0), HDRBracket.Frame(ev: 2)]
        let linear = bracket.map { HDRBracket.image($0, width: Self.width, height: Self.height) }
        let luma = SIMD3<Float>(0.2627, 0.6780, 0.0593)
        func rows(_ value: (Int, Int) -> Double) -> (shadows: [Int], highlights: [Int]) {
            (Self.codes(HDRBracket.shadowSteps.indices.map {
                Self.stepValue(HDRBracket.shadowStepRect($0), width: Self.width, height: Self.height, value: value)
            }), Self.codes(HDRBracket.highlightSteps.indices.map {
                Self.stepValue(HDRBracket.highlightStepRect($0), width: Self.width, height: Self.height, value: value)
            }))
        }
        func distinct(_ codes: [Int]) -> Bool { Set(codes).count == codes.count && codes.allSatisfy { $0 > 0 && $0 < 255 } }
        for (index, frame) in linear.enumerated() {
            let (shadows, highlights) = rows { x, y in
                let p = frame[x, y]
                return Double((SIMD3(p.x, p.y, p.z) * luma).sum())
            }
            print("frame \(index): shadows \(shadows) highlights \(highlights)")
            #expect(!(distinct(shadows) && distinct(highlights)), "frame \(index) holds both")
        }
        let merger = HDRMerger()
        let copies = linear.map { MergeBitmap(width: $0.width, height: $0.height, pixels: $0.pixels) }
        let plan = try merger.plan(measuring: copies, reference: 1, metadataExposures: [nil, nil, nil])
        let radiance = try merger.radiance(plan, frames: linear.map(\.ciImage))
        let mapped = try #require(MergeBitmap.render(try merger.toneMapped(plan, radiance: radiance),
                                                      context: merger.context))
        let (shadows, highlights) = rows { x, y in Double((mapped.rgb(x: x, y: y) * luma).sum()) }
        print("merged: shadows \(shadows) highlights \(highlights)")
        #expect(distinct(shadows))
        #expect(distinct(highlights))
        // Clipping: the white point is the light's 99.99th percentile, so the
        // base layer reaches white on at most 0.01% of the pixels; this scene's
        // bright areas are flat, so the detail adds none. Black: only black light
        // maps to black, and the scene has none.
        let total = mapped.count
        let white = (0..<total).count { (mapped.rgb($0) * luma).sum() >= 0.999 }
        let black = (0..<total).count { (mapped.rgb($0) * luma).sum() <= 0 }
        print("clipped at white \(white), at black \(black) of \(total)")
        var rows = [Int](repeating: 0, count: 10), cols = [Int](repeating: 0, count: 10)
        for i in 0..<total where (mapped.rgb(i) * luma).sum() >= 0.999 {
            rows[(i / Self.width) * 10 / Self.height] += 1
            cols[(i % Self.width) * 10 / Self.width] += 1
        }
        print("white by tenth: rows \(rows) columns \(cols)")
        #expect(Double(white) <= Double(total) * 0.0001)
        #expect(black == 0)
    }

    @Test("AC8: a moving object shows once, from the reference, and the rest matches a merge with nothing moving")
    func ghostFree() throws {
        // Apart by more than two radii and the masks' growth, on the wall.
        let a = SIMD2(0.13, 0.42), b = SIMD2(0.27, 0.42), c = SIMD2(0.41, 0.42)
        let moving = [HDRBracket.Frame(ev: -2, object: a), HDRBracket.Frame(ev: 0, object: b),
                      HDRBracket.Frame(ev: 2, object: c)]
        let still = moving.map { HDRBracket.Frame(ev: $0.ev) }
        let (merger, plan, radiance) = try Self.merge(moving, reference: 1)
        // The same measurements, no ghosts, frames where nothing moved: what the
        // merge gives where its masks are empty.
        var stillPlan = plan
        stillPlan.ghosts = plan.ghosts.map { MergePlane(width: $0.width, height: $0.height) }
        let stillRadiance = try merger.radiance(stillPlan, frames: Self.frames(still))
        let merged = try #require(MergeBitmap.render(radiance, context: merger.context))
        let clean = try #require(MergeBitmap.render(stillRadiance, context: merger.context))
        let withObject = HDRBracket.image(HDRBracket.Frame(ev: 0, object: b), width: Self.width, height: Self.height)
        let radius = HDRBracket.movingObjectRadius * Double(Self.width)
        let grow = Double(max(2, Self.width / 256) * 2 + 4)
        var objectWorst: Float = 0, cleanWorst: Float = 0, compared = 0
        var cleanAt: (Int, Int, SIMD3<Float>, SIMD3<Float>) = (0, 0, .zero, .zero)
        for y in 0..<Self.height {
            for x in 0..<Self.width {
                let p = SIMD2(Double(x) + 0.5, Double(y) + 0.5)
                let distances = [a, b, c].map { simd_distance(p, $0 * SIMD2(Double(Self.width), Double(Self.height))) }
                let m = merged.rgb(x: x, y: y)
                if distances[1] < radius - 1.5 {
                    // Inside the object at the reference's place: the object, not a blend.
                    let t = withObject[x, y]
                    objectWorst = max(objectWorst, simd_reduce_max(abs(m - SIMD3(t.x, t.y, t.z)) / SIMD3(t.x, t.y, t.z)))
                } else if distances.allSatisfy({ $0 > radius + grow }) {
                    compared += 1
                    let t = clean.rgb(x: x, y: y)
                    let e = simd_reduce_max(abs(m - t) / (t + 1e-4))
                    if e > cleanWorst { cleanWorst = e; cleanAt = (x, y, m, t) }
                }
            }
        }
        // Where the other frames' objects were, the wall, as without them.
        var ghostWorst: Float = 0
        for center in [a, c] {
            let cx = Int(center.x * Double(Self.width)), cy = Int(center.y * Double(Self.height))
            for y in (cy - 5)...(cy + 5) {
                for x in (cx - 5)...(cx + 5) {
                    let m = merged.rgb(x: x, y: y), t = clean.rgb(x: x, y: y)
                    ghostWorst = max(ghostWorst, simd_reduce_max(abs(m - t) / (t + 1e-4)))
                }
            }
        }
        print("clean worst at \(cleanAt); exposures \(plan.frames.map(\.exposure))")
        print("ghost masks \(plan.ghosts.map { $0.values.reduce(0, +) }); object \(objectWorst), ghosts \(ghostWorst), elsewhere \(cleanWorst) over \(compared)")
        #expect(objectWorst < 0.05)
        #expect(ghostWorst < 0.05)
        // The same math on the same pixels: float rounding only.
        #expect(cleanWorst < 1e-5)
    }
}

extension MemoryHeavy {
    @Suite("HDR merge DNG")
    struct MergeDNGTests {
        @Test("The 16-bit linear DNG decodes in the system RAW decoder with the light it was given (Spike 1)")
        func dngRoundTrip() throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: "merge-dng-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let radiance = HDRBracket.radianceImage(width: 400, height: 300)
            let url = folder.appending(path: "a_HDR.dng")
            let merger = HDRMerger()
            try MergeOutput.writeDNG(radiance.ciImage, context: merger.context,
                                     metadata: MergeOutput.Metadata(sourceProperties: [:], values: SidecarValues()), to: url,
                                     brightest: 3.6)
            #expect(SystemRAWDecoder.reads(url))
            #expect(DNGLayout(contentsOf: url)?.hasFloatingPointRaw == true)
            // The linear decode leaves out BaselineExposure: the samples, the light over 3.6.
            let decoded = try MergeDecoder.linearImage(url, source: .systemRAW, longEdge: nil)
            let bitmap = try #require(MergeBitmap.render(decoded, context: merger.context))
            for (x, y) in [(50, 50), (300, 80), (200, 250)] {
                let written = radiance[x, y], read = bitmap.rgb(x: x, y: y) * 3.6
                // Half floats round by 2^-11; the system decoder's own highlight
                // handling moved the brightest by up to 1.5% when measured.
                for c in 0..<3 {
                    #expect(abs(read[c] - written[c]) <= 0.03 * written[c], "at \(x),\(y) channel \(c): \(read) vs \(written)")
                }
            }
        }
    }
}
