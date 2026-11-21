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
        var worst: Float = 0
        var worstAt = (0, 0, SIMD3<Float>.zero, SIMD3<Float>.zero)
        var compared = 0
        // Away from the borders too: a moved frame leaves a strip the others don't cover.
        let margin = 12
        for y in margin..<(Self.height - margin) {
            for x in margin..<(Self.width - margin) {
                var low = Float.infinity, high: Float = 0
                for dy in -2...2 {
                    for dx in -2...2 {
                        let p = truth[x + dx, y + dy]
                        let l = MergeBitmap.luminance(SIMD3(p.x, p.y, p.z))
                        low = min(low, l)
                        high = max(high, l)
                    }
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
    func alignmentFollowsTheReference() throws {
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
    func ghostsFollowTheReference() throws {
        // A gentle bracket, where no frame clips the object or loses the wall
        // in black, so every reference can be compared the same way.
        for reference in [0, 2] {
            let check = try Self.ghostCheck(evs: [-1, 0, 1], reference: reference)
            #expect(check.object < 0.05, "reference \(reference)")
            #expect(check.ghosts < 0.05, "reference \(reference)")
            #expect(check.elsewhere < 1e-5, "reference \(reference)")
        }
    }

    @Test("A13 measured: the darkest or brightest frame of a ±2 EV bracket as the reference")
    func extremeReferences() throws {
        // A record, not a pass mark beyond the one AC8 sets: the owner asked
        // whether an extreme reference makes de-ghosting visibly worse.
        for reference in [0, 2] {
            let check = try Self.ghostCheck(evs: [-2, 0, 2], reference: reference)
            #expect(check.object < 0.05, "reference \(reference)")
            #expect(check.ghosts < 0.05, "reference \(reference)")
        }
    }

    // MARK: Auto-align off (R9, AC7a)

    @Test("AC7a: with Auto-align off nothing is measured or moved, and the merge is the CPU reference's without alignment")
    func withoutAlignment() throws {
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

    @Test("AC7a: with Auto-align off frames of another scene are merged as given, not refused")
    func unrelatedWithoutAlignment() throws {
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

    // MARK: De-ghost off (R10, AC8a)

    @Test("AC8a: with De-ghost off the moving object is blended, as the CPU reference's plain blend; elsewhere as with it on")
    func withoutDeghosting() throws {
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

    // MARK: Both boxes (AC9a)

    @Test("AC9a: each of the four combinations of Auto-align and De-ghost merges")
    func fourCombinations() throws {
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
