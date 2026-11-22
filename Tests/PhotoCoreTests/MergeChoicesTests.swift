import CoreImage
import Foundation
import PhotoFixtures
import Testing
import simd
@testable import PhotoCore

extension MemoryHeavy.HDRMergerTests {
    // MARK: The reference (R3, AC3b)

    /// The worst relative difference between a merged radiance (divided by
    /// `scale`) and the scene's light as `frame` saw it, where the light
    /// varies by less than 25% over the 5 x 5 pixels around (a moved frame is
    /// resampled: its 2 x 2-sample pixels, bilinear sampling and half a
    /// pixel of alignment error mix in light from up to two pixels away), and
    /// how many pixels count. Within that, the error is under the 25% plus
    /// the measured exposure's 1%.
    static func radianceError(_ merged: MergeBitmap, scale: Float, against frame: HDRBracket.Frame) -> (Float, Int) {
        let truth = HDRBracket.radianceImage(width: Self.width, height: Self.height, as: frame)
        // Each pixel's luminance, once: every window below reads 25 of them.
        var luminance = [Float](repeating: 0, count: Self.width * Self.height)
        for y in 0..<Self.height {
            for x in 0..<Self.width {
                let p = truth[x, y]
                luminance[y * Self.width + x] = MergeBitmap.luminance(SIMD3(p.x, p.y, p.z))
            }
        }
        var worst: Float = 0
        var worstAt = (0, 0, SIMD3<Float>.zero, SIMD3<Float>.zero)
        var compared = 0
        // Away from the borders too: a moved frame leaves a strip the others don't cover.
        let margin = 12
        for y in margin..<(Self.height - margin) {
            for x in margin..<(Self.width - margin) {
                var low = Float.infinity, high: Float = 0
                // `while`, not ranges: unoptimized, the 25 steps of two range
                // loops were most of this function's time (5.4 million a call).
                var dy = -2
                while dy <= 2 {
                    var dx = -2
                    while dx <= 2 {
                        let l = luminance[(y + dy) * Self.width + x + dx]
                        low = min(low, l)
                        high = max(high, l)
                        dx += 1
                    }
                    dy += 1
                }
                guard high < low * 1.25 else { continue }
                compared += 1
                let m = merged.rgb(x: x, y: y) / scale, p = truth[x, y], t = SIMD3(p.x, p.y, p.z)
                let e = simd_reduce_max(abs(m - t) / t)
                if e > worst { worst = e; worstAt = (x, y, m, t) }
            }
        }
        print("worst against the light at \(worstAt.0),\(worstAt.1): \(worstAt.2) vs \(worstAt.3)")
        return (worst, compared)
    }

    @Test("AC3b: the frames are lined up to the chosen reference, whichever it is")
    func alignmentFollowsTheReference() async throws {
        try await offCooperativePool {
            let bracket = [HDRBracket.Frame(ev: -2, shift: SIMD2(3.25, -2.5), rotationDegrees: 0.3), HDRBracket.Frame(ev: 0),
                           HDRBracket.Frame(ev: 2, shift: SIMD2(-5, 4), rotationDegrees: -0.25)]
            // De-ghost off: where a fraction of a pixel of alignment error makes an
            // edge disagree, masks would hand the area to the reference (clipped in
            // the window), which is de-ghosting's doing, not alignment's.
            for reference in [1, 2] {
                let (merger, plan, radiance) = try Self.merge(bracket, reference: reference,
                                                              options: MergeOptions(deghost: false))
                #expect(plan.reference == reference)
                #expect(plan.frames[reference].homography == .identity)
                // Each frame onto the chosen one, within AC7's derived half pixel
                // (the measuring copy is the image itself at this size).
                for (index, frame) in bracket.enumerated() {
                    let error = Self.alignmentError(plan.frames[index].homography, frame: frame, onto: bracket[reference])
                    print("reference \(reference), frame \(index): worst \(error) px")
                    #expect(error < 0.5, "reference \(reference), frame \(index)")
                }
                let merged = try #require(MergeBitmap.render(radiance, context: merger.context))
                // The merge is in the reference's exposure: the scene's light times its gain.
                let scale = Float(pow(2, bracket[reference].ev))
                let (own, compared) = Self.radianceError(merged, scale: scale, against: bracket[reference])
                let other = bracket[reference == 1 ? 2 : 1]
                let (elsewhere, _) = Self.radianceError(merged, scale: scale, against: other)
                print("reference \(reference): against its own frame \(own) over \(compared) pixels; against frame of the other \(elsewhere)")
                // The light the reference saw, at its place…
                #expect(own < 0.26, "reference \(reference)")
                // …and not the light the other frame saw at its place.
                #expect(elsewhere > 1, "reference \(reference)")
            }
        }
    }

    /// Largest distance, over a grid of points, between where `homography`
    /// puts a pixel of `frame` in `reference` and where the fixture says it is.
    static func alignmentError(_ homography: MergeAlignment.Homography, frame: HDRBracket.Frame,
                               onto reference: HDRBracket.Frame) -> Double {
        let center = SIMD2(Double(Self.width) / 2, Double(Self.height) / 2)
        let angle = reference.rotationDegrees * .pi / 180
        var worst = 0.0
        for gy in 1..<8 {
            for gx in 1..<8 {
                let top = SIMD2(Double(Self.width) * Double(gx) / 8, Double(Self.height) * Double(gy) / 8)
                // The scene point the frame's pixel sees, then the reference's
                // pixel that sees it (the inverse of the reference's movement).
                let scene = HDRBracket.positionInReference(top, frame: frame, width: Self.width, height: Self.height)
                let d = scene - center - reference.shift
                let truth = center + SIMD2(cos(angle) * d.x + sin(angle) * d.y, -sin(angle) * d.x + cos(angle) * d.y)
                // Core Image coordinates: y up.
                let measured = homography.apply(SIMD2(top.x, Double(Self.height) - top.y))
                worst = max(worst, simd_distance(SIMD2(measured.x, Double(Self.height) - measured.y), truth))
            }
        }
        return worst
    }

    @Test("AC3b: what moved is taken from the chosen reference, at its place there")
    func ghostsFollowTheReference() async throws {
        try await offCooperativePool {
            // A gentle bracket, where no frame clips the object or loses the wall
            // in black, so every reference can be compared the same way.
            for reference in [0, 2] {
                let check = try Self.ghostCheck(evs: [-1, 0, 1], reference: reference)
                #expect(check.object < 0.05, "reference \(reference)")
                #expect(check.ghosts < 0.05, "reference \(reference)")
                #expect(check.rimOver == 0, "reference \(reference)")
                #expect(check.elsewhere < 1e-5, "reference \(reference)")
            }
        }
    }

    @Test("A13 measured: the darkest or brightest frame of a ±2 EV bracket as the reference")
    func extremeReferences() async throws {
        try await offCooperativePool {
            // A record, not a pass mark beyond the one AC8 sets: the owner asked
            // whether an extreme reference makes de-ghosting visibly worse.
            for reference in [0, 2] {
                let check = try Self.ghostCheck(evs: [-2, 0, 2], reference: reference)
                #expect(check.object < 0.05, "reference \(reference)")
                #expect(check.ghosts < 0.05, "reference \(reference)")
                #expect(check.rimOver == 0, "reference \(reference)")
            }
        }
    }

    @Test("AC8, A13: with Auto-align off too, a moved object's outline is taken out whole, whichever frame is the reference")
    func outlinesWithoutAlignment() async throws {
        try await offCooperativePool {
            // C18 (code review, seventh pass): with the frame-bound tests cleaned
            // apart from the others, a few pixels of a ghost's rim got through
            // (up to 21 times the clean value at ±1 EV), measured over the whole
            // disc and its margin rather than the 11 x 11 core.
            for evs in [[-1.0, 0, 1], [-2.0, 0, 2]] {
                for reference in evs.indices {
                    let check = try Self.ghostCheck(evs: evs, reference: reference, options: MergeOptions(align: false))
                    #expect(check.object < 0.05, "\(evs) reference \(reference)")
                    #expect(check.ghosts < 0.05, "\(evs) reference \(reference)")
                    #expect(check.rimOver == 0, "\(evs) reference \(reference)")
                }
            }
        }
    }

    @Test("A13: a still linear bracket with noise is merged as with no masks, the default and the darkest reference")
    func stillNoisyBracket() async throws {
        try await offCooperativePool {
            // C17 (code review, seventh pass): noise drags a black frame's
            // neighborhood minimum under its black level where the light is above
            // it. C19 (eighth pass), the mirror: the darkest reference's own noise
            // reaches its black level, and the reference-black test compared the
            // brighter frames with that level. Each case: still frames, noise
            // σ 0.004, against the same plan with no masks; `allowed` pixels may
            // move by more than 1%.
            // The default reference on a tripod series (Auto-align off, no
            // sub-pixel resampling): nothing. The darkest at ±2 EV, aligned or
            // not: nothing (before C19, 769 and 767). The darkest at ±3 EV keeps a
            // residual, 1,870 aligned and 2,071 not (before C19, 12,163 and
            // 12,440): not the reference-black test (it fires nowhere there now)
            // but mostly the two-sided test reading the darkest frame's noise
            // where its light is only a few σ above its black level, which needs
            // a noise model (proposed follow-up). Bounded at 1% of the frame, the
            // residual's order; the rule before C19 moved 5%.
            let frameSize = Self.width * Self.height
            let cases: [(evs: [Double], reference: Int, align: Bool, allowed: Int)] = [
                ([-2, 0, 2], 1, false, 0),
                ([-2, 0, 2], 0, true, 0), ([-2, 0, 2], 0, false, 0),
                ([-3, 0, 3], 0, true, frameSize / 100), ([-3, 0, 3], 0, false, frameSize / 100),
            ]
            let merger = HDRMerger()
            for (evs, reference, align, allowed) in cases {
                let linear = evs.enumerated().map { index, ev in
                    HDRBracket.image(HDRBracket.Frame(ev: ev), width: Self.width, height: Self.height, noise: 0.004,
                                     seed: UInt64(index + 7))
                }
                let copies = linear.map { MergeBitmap(width: $0.width, height: $0.height, pixels: $0.pixels) }
                let frames = linear.map(\.ciImage)
                let plan = try merger.plan(measuring: copies, reference: reference, metadataExposures: evs.map { _ in nil },
                                           options: MergeOptions(align: align))
                var unmasked = plan
                unmasked.ghosts = plan.ghosts.map { MergePlane(width: $0.width, height: $0.height) }
                let merged = try #require(MergeBitmap.render(try merger.radiance(plan, frames: frames),
                                                             context: merger.context))
                let plain = try #require(MergeBitmap.render(try merger.radiance(unmasked, frames: frames),
                                                            context: merger.context))
                var moved = 0
                var worst: Float = 0
                for index in 0..<merged.count {
                    let difference = simd_reduce_max(abs(merged.rgb(index) - plain.rgb(index)) / (plain.rgb(index) + 1e-4))
                    worst = max(worst, difference)
                    if difference > 0.01 { moved += 1 }
                }
                print("still noisy \(evs), reference \(reference), align \(align): moved over 1% \(moved), worst \(worst)")
                #expect(moved <= allowed, "\(evs), reference \(reference), align \(align)")
            }
        }
    }

    /// A camera response that isn't proportional to the light, as a JPEG's is
    /// (R8 takes JPEG brackets; recovering the curve is a follow-up), applied
    /// to each channel of a frame already clipped at 1: a toe `L·L/(L + c)`
    /// that crushes the shadows below proportional, a shoulder
    /// `L·(1 + s)/(L + s)` that lifts the highlights above it, or both.
    /// Both at once (an S-curve) is left out: there the two-sided test
    /// itself sees frames disagree across the mid-tones, with any rule for
    /// black and clipped frames (status.md, C14).
    struct Response: CustomStringConvertible {
        var toe: Float?
        var shoulder: Float?

        func callAsFunction(_ value: Float) -> Float {
            var v = value
            if let toe { v = v * v / (v + toe) }
            if let shoulder { v = v * (1 + shoulder) / (v + shoulder) }
            return v
        }

        var description: String {
            [toe.map { "toe \($0)" }, shoulder.map { "shoulder \($0)" }].compactMap { $0 }.joined(separator: ", ")
        }
    }

    static let responses = [Response(toe: 0.01), Response(toe: 0.005), Response(shoulder: 1)]

    @Test("A13: a still bracket with a camera-like response is merged as with no masks, whichever frame is the reference")
    func stillNonLinearBracket() async throws {
        try await offCooperativePool {
            // C14 (code review, sixth pass): a black frame's crushed toe under-says
            // the light, so a test against its own values fired across a still
            // wall, and the masks' growth took the reference's clipped window.
            let merger = HDRMerger()
            let evs = [-2.0, 0, 2]
            for response in Self.responses {
                let linear = evs.map { ev -> LinearImage in
                    var image = HDRBracket.image(HDRBracket.Frame(ev: ev), width: Self.width, height: Self.height)
                    for index in image.pixels.indices where index % 4 != 3 { image.pixels[index] = response(image.pixels[index]) }
                    return image
                }
                let copies = linear.map { MergeBitmap(width: $0.width, height: $0.height, pixels: $0.pixels) }
                let frames = linear.map(\.ciImage)
                for reference in evs.indices {
                    let plan = try merger.plan(measuring: copies, reference: reference,
                                               metadataExposures: evs.map { _ in nil })
                    var unmasked = plan
                    unmasked.ghosts = plan.ghosts.map { MergePlane(width: $0.width, height: $0.height) }
                    let merged = try #require(MergeBitmap.render(try merger.radiance(plan, frames: frames),
                                                                 context: merger.context))
                    let plain = try #require(MergeBitmap.render(try merger.radiance(unmasked, frames: frames),
                                                                context: merger.context))
                    var moved = 0, movedClipped = 0
                    var worst: Float = 0
                    for y in 0..<Self.height {
                        for x in 0..<Self.width {
                            let a = merged.rgb(x: x, y: y), b = plain.rgb(x: x, y: y)
                            let difference = simd_reduce_max(abs(a - b) / (b + 1e-4))
                            worst = max(worst, difference)
                            guard difference > 0.01 else { continue }
                            moved += 1
                            // Where the reference itself is clipped (the window, at +2 EV).
                            if simd_reduce_max(copies[reference].rgb(x: x, y: y)) >= 0.9 * Float(plan.frames[reference].clip) {
                                movedClipped += 1
                            }
                        }
                    }
                    let masked = plan.ghosts.map { $0.values.filter { $0 > 0 }.count }
                    print("still \(response), reference \(reference): mask pixels \(masked); moved over 1% \(moved), where the reference clips \(movedClipped); worst \(worst)")
                    #expect(movedClipped == 0, "\(response), reference \(reference)")
                    #expect(moved == 0, "\(response), reference \(reference)")
                }
            }
        }
    }

    // MARK: Auto-align off (R9, AC7a)

    @Test("AC7a: with Auto-align off nothing is measured or moved, and the merge is the CPU reference's without alignment")
    func withoutAlignment() async throws {
        try await offCooperativePool {
            let bracket = [HDRBracket.Frame(ev: -2, shift: SIMD2(3.25, -2.5), rotationDegrees: 0.3), HDRBracket.Frame(ev: 0),
                           HDRBracket.Frame(ev: 2, shift: SIMD2(-2, 1.75))]
            let linear = bracket.map { HDRBracket.image($0, width: Self.width, height: Self.height) }
            let merger = HDRMerger()
            let copies = linear.map { MergeBitmap(width: $0.width, height: $0.height, pixels: $0.pixels) }
            var lined = 0
            let plan = try merger.plan(measuring: copies, reference: 1, metadataExposures: [nil, nil, nil],
                                       options: MergeOptions(align: false, deghost: false)) { _ in lined += 1 }
            // No shift or rotation measured or applied, and no alignment step reported.
            #expect(plan.frames.allSatisfy { $0.homography == .identity })
            #expect(lined == 0)
            // The kernels against the CPU reference, with the same identity movements.
            let agreement = try Self.referenceAgreement(linear, plan: plan, merger: merger)
            #expect(agreement.compared >= agreement.total * 95 / 100)
            #expect(agreement.radiance <= 1)
            #expect(agreement.mapped <= 1)
            // The edges are not lined up: the moved frames' pixels sit where they
            // were, so the light of the -2 EV frame's place is not the reference's.
            let aligned = try merger.plan(measuring: copies, reference: 1, metadataExposures: [nil, nil, nil],
                                          options: MergeOptions(deghost: false))
            let asTheyAre = try #require(MergeBitmap.render(try merger.radiance(plan, frames: linear.map(\.ciImage)),
                                                             context: merger.context))
            let lineUp = try #require(MergeBitmap.render(try merger.radiance(aligned, frames: linear.map(\.ciImage)),
                                                          context: merger.context))
            let (unaligned, _) = Self.radianceError(asTheyAre, scale: 1, against: bracket[1])
            let (alignedError, _) = Self.radianceError(lineUp, scale: 1, against: bracket[1])
            print("against the reference's light: aligned \(alignedError), as they are \(unaligned)")
            #expect(alignedError < 0.26)
            #expect(unaligned > 1)
        }
    }

    @Test("AC7a: with Auto-align off frames of another scene are merged as given, not refused")
    func unrelatedWithoutAlignment() async throws {
        try await offCooperativePool {
            let merger = HDRMerger()
            var linear = [HDRBracket.Frame(ev: -2), HDRBracket.Frame(ev: 0)].map {
                HDRBracket.image($0, width: Self.width, height: Self.height)
            }
            linear.append(TestScene.hazyLandscape.image(width: Self.width, height: Self.height))
            let copies = linear.map { MergeBitmap(width: $0.width, height: $0.height, pixels: $0.pixels) }
            #expect(throws: HDRMerger.Failure.misaligned(frame: 2)) {
                try merger.plan(measuring: copies, reference: 1, metadataExposures: [nil, nil, nil])
            }
            let plan = try merger.plan(measuring: copies, reference: 1, metadataExposures: [nil, nil, nil],
                                       options: MergeOptions(align: false))
            let mapped = try merger.toneMapped(plan, radiance: try merger.radiance(plan, frames: linear.map(\.ciImage)))
            #expect(MergeBitmap.render(mapped, context: merger.context) != nil)
        }
    }

    // MARK: De-ghost off (R10, AC8a)

    @Test("AC8a: with De-ghost off the moving object is blended, as the CPU reference's plain blend; elsewhere as with it on")
    func withoutDeghosting() async throws {
        try await offCooperativePool {
            let evs = [-2.0, 0, 2]
            let moving = zip(evs, Self.ghostPlaces).map { HDRBracket.Frame(ev: $0, object: $1) }
            let linear = moving.map { HDRBracket.image($0, width: Self.width, height: Self.height) }
            let merger = HDRMerger()
            let copies = linear.map { MergeBitmap(width: $0.width, height: $0.height, pixels: $0.pixels) }
            let plain = try merger.plan(measuring: copies, reference: 1, metadataExposures: [nil, nil, nil],
                                        options: MergeOptions(deghost: false))
            let checked = try merger.plan(measuring: copies, reference: 1, metadataExposures: [nil, nil, nil])
            // No region takes the reference alone: no masks at all.
            #expect(plain.ghosts.allSatisfy { $0.values.allSatisfy { $0 == 0 } })
            #expect(checked.ghosts.contains { $0.values.contains { $0 > 0 } })
            // The same movements, exposures and clipping: only the masks differ.
            #expect(plain.frames == checked.frames)
            // The plain blend against its CPU reference (no ghosts: no reference-pixel
            // rule), on the same walker held by hand: frames moved, so the kernels
            // sample between pixels, as in AC10's check.
            let handHeld = [HDRBracket.Frame(ev: -2, shift: SIMD2(3.25, -2.5), rotationDegrees: 0.3, object: Self.ghostPlaces[0]),
                            HDRBracket.Frame(ev: 0, object: Self.ghostPlaces[1]),
                            HDRBracket.Frame(ev: 2, shift: SIMD2(-2, 1.75), object: Self.ghostPlaces[2])]
            let held = handHeld.map { HDRBracket.image($0, width: Self.width, height: Self.height) }
            let heldPlan = try merger.plan(measuring: held.map { MergeBitmap(width: $0.width, height: $0.height, pixels: $0.pixels) },
                                           reference: 1, metadataExposures: [nil, nil, nil], options: MergeOptions(deghost: false))
            #expect(heldPlan.ghosts.allSatisfy { $0.values.allSatisfy { $0 == 0 } })
            let agreement = try Self.referenceAgreement(held, plan: heldPlan, merger: merger)
            #expect(agreement.compared >= agreement.total * 95 / 100)
            #expect(agreement.radiance <= 1)
            #expect(agreement.mapped <= 1)

            let frames = linear.map(\.ciImage)
            let blended = try #require(MergeBitmap.render(try merger.radiance(plain, frames: frames), context: merger.context))
            let deghosted = try #require(MergeBitmap.render(try merger.radiance(checked, frames: frames), context: merger.context))
            let radius = HDRBracket.movingObjectRadius * Double(Self.width)
            let grow = Double(max(2, Self.width / 256) * 2 + 4)
            var moved: Float = 0, still: Float = 0
            for y in 0..<Self.height {
                for x in 0..<Self.width {
                    let p = SIMD2(Double(x) + 0.5, Double(y) + 0.5)
                    let distances = Self.ghostPlaces.map {
                        simd_distance(p, $0 * SIMD2(Double(Self.width), Double(Self.height)))
                    }
                    let a = blended.rgb(x: x, y: y), b = deghosted.rgb(x: x, y: y)
                    let difference = simd_reduce_max(abs(a - b) / (b + 1e-4))
                    if distances.contains(where: { $0 < radius - 1.5 }) {
                        moved = max(moved, difference)
                    } else if distances.allSatisfy({ $0 > radius + grow }) {
                        still = max(still, difference)
                    }
                }
            }
            print("plain blend against de-ghosted: in the moving region \(moved), where nothing moved \(still)")
            // Where something moved, the blend differs (the object is mixed with the wall)…
            #expect(moved > 0.25)
            // …and where nothing moved it is the same merge: float rounding only, as AC8's.
            #expect(still < 1e-5)
        }
    }

    // MARK: Both boxes (AC9a)

    @Test("AC9a: each of the four combinations of Auto-align and De-ghost merges")
    func fourCombinations() async throws {
        try await offCooperativePool {
            let bracket = [HDRBracket.Frame(ev: -2, shift: SIMD2(2, -1.5), rotationDegrees: 0.2, object: SIMD2(0.13, 0.42)),
                           HDRBracket.Frame(ev: 0, object: SIMD2(0.27, 0.42)),
                           HDRBracket.Frame(ev: 2, shift: SIMD2(-1.5, 1), object: SIMD2(0.41, 0.42))]
            for align in [true, false] {
                for deghost in [true, false] {
                    let (merger, plan, radiance) = try Self.merge(bracket, reference: 1,
                                                                  options: MergeOptions(align: align, deghost: deghost))
                    let mapped = try #require(MergeBitmap.render(try merger.toneMapped(plan, radiance: radiance),
                                                                  context: merger.context))
                    let finite = mapped.pixels.allSatisfy { $0.isFinite }
                    #expect(finite, "align \(align) deghost \(deghost)")
                    #expect(plan.frames.allSatisfy { $0.homography == .identity } == !align)
                    #expect(plan.ghosts.allSatisfy { $0.values.allSatisfy { $0 == 0 } } == !deghost)
                }
            }
        }
    }
}
