import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Distortion and Lens Vignetting (docs/features/lens-corrections, issue #87):
/// the modules and their stack, the plan each photo's file allows, the
/// renders against the CPU reference (`LensCorrectionReference`), and the
/// tables Auto reads.
@Suite("Lens corrections", .serialized)
struct LensCorrectionTests {
    static let width = TestScene.defaultWidth, height = TestScene.defaultHeight
    static let frame = CGRect(x: 0, y: 0, width: width, height: height)
    static let grid = TestScene.lensGrid.image(width: width, height: height)

    static func values(distortion: LensDistortion = LensDistortion(), vignetting: LensVignetting = LensVignetting())
        -> Adjustments {
        var values = Adjustments()
        values.distortion = distortion
        values.lensVignetting = vignetting
        return values
    }

    // MARK: The modules (R1, R3, R14; AC1, AC3, AC12)

    @Test("Off by default and left out; turning a group on stores an explicit on (R1, AC1)")
    func explicitOn() {
        #expect(Adjustments().editStack == .identity)
        var values = Adjustments()
        values.setEnabled(.distortion, true)
        #expect(values.distortion.isOn && values.distortion.source == .auto)
        #expect(values.editStack.operations.map(\.kind) == [LensDistortion.kind])
        #expect(values.editStack.operations.first?.parameters == ["on": .bool(true)])
        values.setEnabled(.lensVignetting, true)
        #expect(values.lensVignetting.isOn)
        #expect(Adjustments(stack: values.editStack) == values)
        #expect(values.distortionApplies && values.lensVignettingApplies)
    }

    @Test("Turning a group off keeps its values and renders nothing; on again brings them back")
    func turnOffKeeps() {
        var values = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 30, constrain: false))
        values.setEnabled(.distortion, false)
        #expect(!values.isEnabled(.distortion) && !values.distortionApplies)
        #expect(values.distortion.amount == 30 && !values.distortion.constrain)
        #expect(LensCorrectionPlan(values.effective, lens: nil).isIdentity)
        values.setEnabled(.distortion, true)
        #expect(values.distortionApplies && values.distortion.amount == 30)
    }

    @Test("Changing Source, Amount or Constrain switches the group on (design §3.1)")
    func changingSwitchesOn() {
        let previous = Adjustments()
        for change: (inout Adjustments) -> Void in [{ $0.distortion.source = .manual }, { $0.distortion.setAmount(5) },
                                                     { $0.distortion.constrain = false }] {
            var next = previous
            change(&next)
            next.enableModules(changedFrom: previous)
            #expect(next.distortion.isOn)
        }
        var next = previous
        next.lensVignetting.setAmount(-20)
        next.enableModules(changedFrom: previous)
        #expect(next.lensVignetting.isOn)
        // Turned off with values: a change turns it back on, as every group.
        var off = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 10))
        off.setEnabled(.distortion, false)
        var changed = off
        changed.distortion.setAmount(12)
        changed.enableModules(changedFrom: off)
        #expect(changed.distortionApplies)
    }

    @Test("Amounts outside −100 … +100 or not numbers are refused")
    func amountRange() {
        var distortion = LensDistortion(amount: 40)
        for bad in [101, -100.5, .nan, .infinity] { distortion.setAmount(bad) }
        #expect(distortion.amount == 40)
        var vignetting = LensVignetting(amount: -100)
        vignetting.setAmount(250)
        #expect(vignetting.amount == -100)
    }

    @Test("Reset of the Lens heading gives the identity hash; every value round-trips (AC12)")
    func resetAndRoundTrip() {
        let values = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: -35, constrain: false),
                                 vignetting: LensVignetting(isOn: true, source: .manual, amount: 60))
        let read = Adjustments(stack: values.editStack)
        #expect(read == values)
        #expect(read.distortion.parameters == ["on": .bool(true), "source": .string("manual"), "amount": .number(-35),
                                               "constrain": .bool(false)])
        #expect(values.resetting(.lens).editStack.renderHash == EditStack.identity.renderHash)
        #expect(values.resettingAll().editStack.renderHash == EditStack.identity.renderHash)
    }

    @Test("The Lens heading and preset groups list Distortion and Lens Vignetting first (design §2, §9)")
    func groupsAndPresets() {
        #expect(Adjustments.Section.lens.groups == [.distortion, .lensVignetting, .colorFringes, .colorAlignment])
        let presetGroups = Adjustments.Group.presetGroups
        #expect(presetGroups.contains(.distortion) && presetGroups.contains(.lensVignetting))
        let lensGroups = presetGroups.filter { Adjustments.Section.lens.groups.contains($0) }
        #expect(lensGroups == [.distortion, .lensVignetting, .colorFringes, .colorAlignment])
        let values = Self.values(distortion: LensDistortion(isOn: true), vignetting: LensVignetting(source: .manual, amount: 3))
        #expect(values.modifiedGroups.isSuperset(of: [.distortion, .lensVignetting]))
        // Paste carries the groups whole; a source that never had them turns the target's off.
        let pasted = Adjustments().replacing([.distortion, .lensVignetting], from: values)
        #expect(pasted.distortion == values.distortion && pasted.lensVignetting == values.lensVignetting)
        #expect(values.replacing([.distortion], from: Adjustments()).distortion == LensDistortion())
    }

    @Test("A manual Amount saved while Source is Auto is kept and not applied (RI-5, AC3)")
    func manualAmountKeptInAuto() {
        let values = Self.values(distortion: LensDistortion(isOn: true, source: .auto, amount: 50),
                                 vignetting: LensVignetting(isOn: true, source: .auto, amount: -40))
        let read = Adjustments(stack: values.editStack)
        #expect(read.distortion.amount == 50 && read.lensVignetting.amount == -40)
        for lens in [nil, CameraLensState.notRaw, .tables(.none), .decoderCorrects] {
            #expect(LensCorrectionPlan(read.effective, lens: lens).isIdentity)
        }
        var manual = read
        manual.distortion.source = .manual
        #expect(LensCorrectionPlan(manual.effective, lens: nil).warp?.radial == .manual(amount: 50))
    }

    @Test("photocli develop: a value set switches the group on; on=false wins; the render says what applied")
    func commandLine() throws {
        let on = try EditStack.identity.applying([.set(kind: LensDistortion.kind, parameter: "source", value: "manual"),
                                                  .set(kind: LensDistortion.kind, parameter: "amount", value: "20")])
        #expect(Adjustments(stack: on).distortion == LensDistortion(isOn: true, source: .manual, amount: 20))
        let off = try EditStack.identity.applying([.set(kind: LensVignetting.kind, parameter: "amount", value: "-30"),
                                                   .set(kind: LensVignetting.kind, parameter: "on", value: "false")])
        #expect(Adjustments(stack: off).lensVignetting == LensVignetting(amount: -30))
        let json = RenderCommands.lensCorrectionsJSON(Adjustments(stack: on), lens: .decoderCorrects)
        #expect(json == ["distortion": ["status": "decoderCorrectsManual", "applied": true],
                         "vignetting": ["status": "decoderCorrectsAuto", "applied": false]])
    }

    @Test("A Source segment chosen while the group is off turns it on with that source; on, the selected one changes nothing (R15, AC14)")
    func choosingSource() throws {
        // Never on: Auto shows selected; choosing it, or Manual, turns the group on.
        let never = Adjustments()
        let auto = try #require(never.choosingLensSource(.distortion, .auto))
        #expect(auto.distortionApplies && auto.distortion.source == .auto)
        let manual = try #require(never.choosingLensSource(.lensVignetting, .manual))
        #expect(manual.lensVignettingApplies && manual.lensVignetting.source == .manual)
        // Unchecked with values kept: on again, the Amount kept.
        var unchecked = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 25))
        unchecked.setEnabled(.distortion, false)
        let back = try #require(unchecked.choosingLensSource(.distortion, .auto))
        #expect(back.distortionApplies && back.distortion.source == .auto && back.distortion.amount == 25)
        // One step: the values before are what an undo writes back, off with their source.
        let undone = Adjustments(stack: unchecked.editStack)
        #expect(!undone.distortionApplies && undone.distortion.source == .manual && undone.distortion.amount == 25)
        // On with that source already: nothing to record.
        #expect(auto.choosingLensSource(.distortion, .auto) == nil)
        #expect(auto.choosingLensSource(.distortion, .manual)?.distortion.source == .manual)
    }

    /// A real DNG with lens opcodes (opt-in: `DNG_OPCODE_SAMPLE=path`, never
    /// committed): the system decoder reads it and leaves its opcodes off
    /// (status.md Q1), and Auto takes the warp of its green plane only (L15).
    /// Adobe's sample `03_jxl_bayer_raw_integer.dng` has a three-plane warp
    /// whose green plane moves nothing (only red and blue are scaled, lateral
    /// color): Auto then finds no distortion table, as it should.
    @Test("A real DNG's WarpRectilinear: Auto takes its green plane", .enabled(if: ProcessInfo.processInfo.environment["DNG_OPCODE_SAMPLE"] != nil))
    func dngSample() throws {
        let url = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DNG_OPCODE_SAMPLE"]))
        let raw = try #require(CIRAWFilter(imageURL: url))
        RAWDecodeSettings.none.apply(to: raw)
        let corrects = raw.isLensCorrectionSupported && raw.isLensCorrectionEnabled
        #expect(!corrects)
        let state = CameraLensState.read(url, systemDecodes: true, decoderCorrects: corrects)
        let tables = try #require(state.tables)
        let values = Self.values(distortion: LensDistortion(isOn: true))
        let image = try #require(RAWDecodeGraph.output(of: raw)).scaledToFit(longEdge: 600)
        let corrected = AdjustmentRenderer.lensCorrected(values, image, context: RenderContext(isRaw: true, lens: state))
        if let warp = tables.distortion {
            #expect(!warp.isIdentity && corrected !== image && corrected.extent == image.extent)
        } else {
            #expect(corrected === image)
            #expect(LensCorrectionStatus(.distortion, values: values, lens: state, kernelsAvailable: true).caption == .noTable)
        }
    }

    // MARK: The plan (R3, R4, R9; AC3, AC4, AC9)

    static let tables = CameraLensTables(origin: .dng, distortion: LensWarp(radial: .polynomial([1, -0.04, 0, 0]), fills: true),
                                         vignetting: LensGain(model: .polynomial([0.5, 0, 0, 0, 0])))

    @Test("Auto applies the file's tables, and nothing where something else corrects or there is no table (R4, AC4)")
    func autoPlan() {
        let auto = Self.values(distortion: LensDistortion(isOn: true, constrain: false), vignetting: LensVignetting(isOn: true))
        let plan = LensCorrectionPlan(auto, lens: .tables(Self.tables))
        #expect(plan.warp?.radial == .polynomial([1, -0.04, 0, 0]) && plan.warp?.fills == false)
        #expect(plan.gain == Self.tables.vignetting)
        for inert in [CameraLensState.decoderCorrects, .builtInCorrection, .notRaw, .unreadable, .tables(.none)] {
            #expect(LensCorrectionPlan(auto, lens: inert).isIdentity, "\(inert)")
        }
        // Manual works everywhere, the corrected raws included (RI-1).
        let manual = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 20),
                                 vignetting: LensVignetting(isOn: true, source: .manual, amount: 20))
        for lens in [CameraLensState.decoderCorrects, .builtInCorrection, .notRaw, .tables(Self.tables)] {
            let plan = LensCorrectionPlan(manual, lens: lens)
            #expect(plan.warp?.radial == .manual(amount: 20) && plan.gain?.model == .manual(amount: 20))
        }
    }

    @Test("Only a change of the warp moves the frame (R6)")
    func movesFrame() {
        let off = LensCorrectionPlan()
        let manual = LensCorrectionPlan(Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 10)), lens: nil)
        let vignetting = LensCorrectionPlan(Self.values(vignetting: LensVignetting(isOn: true, source: .manual, amount: 30)), lens: nil)
        #expect(manual.movesFrame(comparedWith: off))
        #expect(!vignetting.movesFrame(comparedWith: off))
        // Auto where it is inert, or Amount 0, moves nothing.
        let inert = LensCorrectionPlan(Self.values(distortion: LensDistortion(isOn: true)), lens: .decoderCorrects)
        let zero = LensCorrectionPlan(Self.values(distortion: LensDistortion(isOn: true, source: .manual)), lens: nil)
        #expect(!inert.movesFrame(comparedWith: off) && !zero.movesFrame(comparedWith: off))
        var unconstrained = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 10))
        unconstrained.distortion.constrain = false
        #expect(LensCorrectionPlan(unconstrained, lens: nil).movesFrame(comparedWith: manual))
    }

    // MARK: What the group says (design §4, §5; R4, R9, R11, R12)

    @Test("Each state gives the caption row design §4 names, first row that applies")
    func captions() {
        typealias Status = LensCorrectionStatus
        let auto = Self.values(distortion: LensDistortion(isOn: true), vignetting: LensVignetting(isOn: true))
        let manual = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 20),
                                 vignetting: LensVignetting(isOn: true, source: .manual))
        func caption(_ values: Adjustments, _ lens: CameraLensState?, _ group: Status.Group = .distortion,
                     kernels: Bool = true) -> Status.Caption {
            Status(group, values: values, lens: lens, kernelsAvailable: kernels).caption
        }
        let distortionOnly = CameraLensTables(origin: .dng, distortion: Self.tables.distortion)
        #expect(caption(auto, .decoderCorrects) == .decoderCorrectsAuto)
        #expect(caption(manual, .decoderCorrects) == .decoderCorrectsManual)
        #expect(caption(Adjustments(), .decoderCorrects) == .decoderCorrectsAuto)
        #expect(caption(auto, .builtInCorrection) == .builtInAuto)
        #expect(caption(manual, .builtInCorrection) == .builtInManual)
        #expect(caption(manual, .builtInCorrection, kernels: false) == .kernelsUnavailable)
        // Auto is inert there, so the kernels are not needed and rows 1a, 2a stay.
        #expect(caption(auto, .decoderCorrects, kernels: false) == .decoderCorrectsAuto)
        #expect(caption(auto, .tables(Self.tables), kernels: false) == .kernelsUnavailable)
        #expect(caption(auto, .unreadable) == .tableUnreadable)
        #expect(caption(auto, .tables(Self.tables)) == .usingTable)
        #expect(caption(Adjustments(), .tables(Self.tables)) == .tableAvailable)
        #expect(caption(auto, .tables(.none)) == .noTable)
        // A file can carry one table and not the other.
        #expect(caption(auto, .tables(distortionOnly), .vignetting) == .noTable)
        #expect(caption(auto, .notRaw) == .autoUnavailableNotRaw)
        #expect(caption(manual, .notRaw) == .manual && caption(manual, .tables(.none)) == .manual)
        // Manual with Amount 0 needs no kernels.
        #expect(caption(manual, .notRaw, .vignetting, kernels: false) == .manual)
        #expect(Status.Caption.kernelsUnavailable.isWarning && Status.Caption.tableUnreadable.isWarning)
    }

    @Test("Auto is dimmed where it can't apply; a stored Auto there selects no segment; checking starts in Manual (L9)")
    func segments() {
        let auto = Self.values(distortion: LensDistortion(isOn: true))
        for lens in [CameraLensState.notRaw, .decoderCorrects, .builtInCorrection] {
            let status = LensCorrectionStatus(.distortion, values: auto, lens: lens, kernelsAvailable: true)
            #expect(status.autoUnavailable != nil && status.selectedSegment == nil && status.startsInManual)
            #expect(!status.showsAmount && status.isChecked)
        }
        let raw = LensCorrectionStatus(.distortion, values: Adjustments(), lens: .tables(.none), kernelsAvailable: true)
        #expect(raw.autoUnavailable == nil && raw.selectedSegment == 0 && !raw.startsInManual && !raw.isChecked)
        let manual = LensCorrectionStatus(.distortion, values: Self.values(distortion: LensDistortion(isOn: true, source: .manual)),
                                          lens: .decoderCorrects, kernelsAvailable: true)
        #expect(manual.selectedSegment == 1 && manual.showsAmount)
    }

    // MARK: Rendering against the reference (R2, R5, R7; AC2, AC5, AC7)

    /// The rendered and expected images agree within `bound` at every
    /// component, except where the reference takes a pixel from within
    /// 10⁻³ of a pixel of the recorded image's edge: there float rounding
    /// may put the kernel's sample on the other side (black or not).
    static func expectAgrees(_ rendered: LinearImage, _ expected: LinearImage, bound: Float, skipping: Set<Int> = [],
                             sourceLocation: SourceLocation = #_sourceLocation) {
        var worst: Float = 0, at = 0
        for index in rendered.pixels.indices where index % 4 != 3 && !skipping.contains(index / 4) {
            let error = abs(rendered.pixels[index] - expected.pixels[index])
            if error > worst { (worst, at) = (error, index) }
        }
        #expect(worst <= bound, """
            worst \(worst) at pixel \(at / 4 % rendered.width), row \(at / 4 / rendered.width): \
            \(rendered.pixels[at]) instead of \(expected.pixels[at]); bound \(bound)
            """, sourceLocation: sourceLocation)
    }

    static func nearEdge(_ warp: LensWarp, width: Int, height: Int, frame: CGRect) -> Set<Int> {
        let scale = warp.scale(in: frame)
        var near = Set<Int>()
        for row in 0..<height {
            for column in 0..<width {
                let p = warp.source(of: CGPoint(x: Double(column) + 0.5, y: Double(height - 1 - row) + 0.5), in: frame, scale: scale)
                let distances = [p.x, p.y, Double(width) - p.x, Double(height) - p.y].map(abs)
                if distances.contains(where: { $0 < 1e-3 }) { near.insert(row * width + column) }
            }
        }
        return near
    }

    /// Coordinates up to 256 pixels carry single precision's 2⁻²⁴ relative
    /// error through about a dozen operations (2⁻²⁰ × 256 ≈ 2.4 × 10⁻⁴ of a
    /// pixel); the table read between its entries adds under 10⁻⁷ of the
    /// radius for these models (h²/8 times the ratio's second derivative,
    /// h = reach / 1023). A sample read between pixels moves by at most the
    /// largest step between neighbors (the grid's lines: 0.63) times that,
    /// plus a few roundings of values below 1.
    static let warpBound: Float = 0x1p-20 * 256 * 1.1 * 0.63 + 1e-6

    @Test("Distortion moves the grid's lines as the reference predicts (AC2)",
          arguments: [(30.0, true), (100.0, true), (-60.0, true), (60.0, false), (-60.0, false)])
    func distortionMatchesReference(amount: Double, constrain: Bool) throws {
        let warp = LensWarp(radial: .manual(amount: amount), fills: constrain)
        let applied = try #require(AdjustmentRenderer.applyWarp(Self.grid.ciImage, warp, frame: Self.frame))
        #expect(applied.extent == Self.frame)
        let rendered = LensRenderingTests.renderFloat(applied)
        let expected = LensCorrectionReference.warp(warp, Self.grid, frame: Self.frame)
        Self.expectAgrees(rendered, expected, bound: Self.warpBound,
                          skipping: Self.nearEdge(warp, width: Self.width, height: Self.height, frame: Self.frame))
        // And it moves something: the corner is not where it was.
        Self.expectDiffers(rendered, Self.grid)
    }

    static func expectDiffers(_ a: LinearImage, _ b: LinearImage, sourceLocation: SourceLocation = #_sourceLocation) {
        let differ = zip(a.pixels, b.pixels).contains { abs($0 - $1) > 0.05 }
        #expect(differ, sourceLocation: sourceLocation)
    }

    @Test("Lens Vignetting changes the corners as the reference predicts (AC2)", arguments: [100.0, 35.0, -50.0])
    func vignettingMatchesReference(amount: Double) throws {
        let gain = LensGain(model: .manual(amount: amount))
        let source = TestScene.grayRamp.image(width: Self.width, height: Self.height)
        let applied = try #require(AdjustmentRenderer.applyGain(source.ciImage, gain, frame: Self.frame))
        let rendered = LensRenderingTests.renderFloat(applied)
        let expected = LensCorrectionReference.gain(gain, source, frame: Self.frame)
        // The gain read between table entries is within 5 × 10⁻⁶ of the model
        // ((1 + ρ²)^2 has a second derivative under 24 to ρ = 1.3), times
        // values up to 4 (the ramp's two stops over white), plus float roundings.
        Self.expectAgrees(rendered, expected, bound: 4 * (5e-6 + 0x1p-20) + 1e-6)
        let corner = (Self.height - 1) * Self.width * 4 + (Self.width - 1) * 4 - 0
        if amount > 0 {
            #expect(rendered.pixels[4 + 1] >= source.pixels[4 + 1])
        } else {
            #expect(rendered.pixels[corner + 1] < source.pixels[corner + 1] || source.pixels[corner + 1] == 0)
        }
    }

    @Test("±100 is ±2 EV at the corner, nothing at the center")
    func vignettingScale() {
        #expect(abs(LensGainModel.manual(amount: 100).gain(1) - 4) < 1e-12)
        #expect(abs(LensGainModel.manual(amount: -100).gain(1) - 0.25) < 1e-12)
        #expect(LensGainModel.manual(amount: 70).gain(0) == 1)
        // A value the gain lifts past white stops at white; one above it stays.
        #expect(LensGain.apply(2, to: 0.8) == 1 && LensGain.apply(2, to: 1.5) == 1.5 && LensGain.apply(0.5, to: 1.5) == 0.75)
    }

    @Test("With Constrain to image the corrected grid has no empty pixel at its edge; without, pincushion has (AC7)",
          arguments: [100.0, 40.0, -40.0, -100.0])
    func constrainFills(amount: Double) throws {
        let constrained = LensWarp(radial: .manual(amount: amount), fills: true)
        let rendered = LensRenderingTests.renderFloat(try #require(AdjustmentRenderer.applyWarp(Self.grid.ciImage, constrained, frame: Self.frame)))
        let black = stride(from: 0, to: rendered.pixels.count, by: 4).filter { rendered.pixels[$0 + 1] == 0 }
        #expect(black.isEmpty, "\(black.count) empty pixels")
        // The scale fills the frame: a little more of the frame is lost at a slightly larger scale.
        let scale = constrained.scale(in: Self.frame)
        #expect(amount > 0 ? scale < 1 : scale > 1)
        if amount < 0 {
            let free = LensWarp(radial: .manual(amount: amount), fills: false)
            let open = LensRenderingTests.renderFloat(try #require(AdjustmentRenderer.applyWarp(Self.grid.ciImage, free, frame: Self.frame)))
            #expect(open.pixels[1] == 0, "the top left corner is empty without Constrain to image")
        }
    }

    @Test("The crop still applies after the correction (AC7)")
    func cropAfterCorrection() {
        var values = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 50))
        values.crop = Crop(rect: CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let renderer = AdjustmentRenderer()
        let rendered = LensRenderingTests.renderFloat(renderer.render(values, to: Self.grid.ciImage, context: RenderContext()))
        var uncropped = values
        uncropped.crop = Crop()
        let whole = renderer.render(uncropped, to: Self.grid.ciImage, context: RenderContext())
        let expected = LensRenderingTests.renderFloat(values.crop.apply(to: whole))
        #expect(rendered.width == Self.width / 2 && rendered == expected)
    }

    @Test("Lens vignetting renders before Exposure: the gain's white limit comes first (R5, AC5)")
    func vignettingBeforeExposure() throws {
        var values = Self.values(vignetting: LensVignetting(isOn: true, source: .manual, amount: 80))
        values.exposure.ev = -1
        let source = TestScene.grayRamp.image(width: Self.width, height: Self.height)
        let rendered = LensRenderingTests.renderFloat(AdjustmentRenderer().render(values, to: source.ciImage, context: RenderContext()))
        // The reference's order: the gain (with its white limit), then half the light.
        var expected = LensCorrectionReference.gain(LensGain(model: .manual(amount: 80)), source, frame: Self.frame)
        for index in expected.pixels.indices where index % 4 != 3 { expected.pixels[index] *= 0.5 }
        Self.expectAgrees(rendered, expected, bound: 4 * (5e-6 + 0x1p-20) + 1e-5)
        // The other order would differ where the ramp is near white in the corners.
        var other = source
        for index in other.pixels.indices where index % 4 != 3 { other.pixels[index] *= 0.5 }
        other = LensCorrectionReference.gain(LensGain(model: .manual(amount: 80)), other, frame: Self.frame)
        #expect(zip(other.pixels, expected.pixels).contains { abs($0 - $1) > 0.01 })
    }

    @Test("The fringe picker and Color Alignment's measurement see the corrected image (AC5)")
    func pickerSeesCorrectedImage() {
        let values = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 70),
                                 vignetting: LensVignetting(isOn: true, source: .manual, amount: 40))
        let context = RenderContext()
        let input = Self.grid.ciImage
        let picked = LensRenderingTests.renderFloat(AdjustmentRenderer().fringeInput(values, to: input, context: context))
        let corrected = LensRenderingTests.renderFloat(AdjustmentRenderer.lensCorrected(values, input, context: context))
        #expect(picked == corrected)
        Self.expectDiffers(picked, Self.grid)
        #expect(ColorAlignmentMeasurement.measuredImage(values, input, context: context).extent == input.extent)
        #expect(LensRenderingTests.renderFloat(ColorAlignmentMeasurement.measuredImage(values, input, context: context)) == corrected)
    }

    @Test("A stack without the groups, or with Auto where it can't apply, leaves the decoded image as it is (AC1, AC4)")
    func untouched() {
        let input = Self.grid.ciImage
        let auto = Self.values(distortion: LensDistortion(isOn: true), vignetting: LensVignetting(isOn: true))
        for (values, lens) in [(Adjustments(), CameraLensState?.none), (auto, .decoderCorrects), (auto, .builtInCorrection),
                               (auto, .notRaw), (auto, .tables(.none)), (auto, .unreadable)] {
            let context = RenderContext(lens: lens)
            #expect(AdjustmentRenderer.lensCorrected(values, input, context: context) === input)
        }
        // On a raw the decoder corrects, Auto renders as off; Manual adds its correction (RI-1, AC4).
        let off = Adjustments()
        let context = RenderContext(isRaw: true, lens: .decoderCorrects)
        let renderer = AdjustmentRenderer()
        #expect(LensRenderingTests.renderFloat(renderer.render(auto, to: input, context: context))
                == LensRenderingTests.renderFloat(renderer.render(off, to: input, context: context)))
        let manual = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 40))
        let warp = LensWarp(radial: .manual(amount: 40), fills: true)
        let rendered = LensRenderingTests.renderFloat(renderer.render(manual, to: input, context: context))
        Self.expectAgrees(rendered, LensCorrectionReference.warp(warp, Self.grid, frame: Self.frame), bound: Self.warpBound,
                          skipping: Self.nearEdge(warp, width: Self.width, height: Self.height, frame: Self.frame))
    }

    @Test("With the kernels forced to fail nothing is applied (R11)")
    func kernelFailure() {
        let input = Self.grid.ciImage
        let manual = Self.values(distortion: LensDistortion(isOn: true, source: .manual, amount: 40))
        LensCorrectionDebug.fault = .kernelFailure
        defer { LensCorrectionDebug.fault = nil }
        #expect(AdjustmentRenderer.lensCorrected(manual, input, context: RenderContext()) === input)
    }

    // MARK: Tables (R3; AC3, AC11)

    /// A DNG warp with tangential terms, an optical center off the middle,
    /// and a turned picture, against the reference, which takes the same
    /// model through `LensWarp.source` (DNG specification: corrected to recorded).
    @Test("A DNG warp matches the reference in every orientation", arguments: [1, 3, 6, 8])
    func dngWarp(orientation: UInt32) throws {
        let geometry = LensFrameGeometry(centerOffset: SIMD2(0.03, -0.02), radiusUnit: 1.05,
                                         orientation: CGImagePropertyOrientation(rawValue: orientation)!)
        let warp = LensWarp(radial: .polynomial([0.98, 0.03, -0.01, 0.002]), tangential: SIMD2(0.001, -0.0015),
                            geometry: geometry, fills: true)
        let applied = try #require(AdjustmentRenderer.applyWarp(Self.grid.ciImage, warp, frame: Self.frame))
        let rendered = LensRenderingTests.renderFloat(applied)
        let expected = LensCorrectionReference.warp(warp, Self.grid, frame: Self.frame)
        Self.expectAgrees(rendered, expected, bound: Self.warpBound,
                          skipping: Self.nearEdge(warp, width: Self.width, height: Self.height, frame: Self.frame))
    }

    @Test("A Fujifilm table's distortion matches the reference; the scale fills the frame as the built-in step's does")
    func fujifilmWarp() throws {
        let warp = LensWarp(radial: .fujifilm(knots: SyntheticRAF.knots11, distortion: SyntheticRAF.distortion35), fills: true)
        let rendered = LensRenderingTests.renderFloat(try #require(AdjustmentRenderer.applyWarp(Self.grid.ciImage, warp, frame: Self.frame)))
        // Piecewise linear tables: the lookup is off by at most 10⁻⁵ of the
        // radius at a knot (`EmbeddedLensCorrection.tableCount`), 0.0016 pixels here.
        Self.expectAgrees(rendered, LensCorrectionReference.warp(warp, Self.grid, frame: Self.frame),
                          bound: Self.warpBound + 0.0016 * 0.63,
                          skipping: Self.nearEdge(warp, width: Self.width, height: Self.height, frame: Self.frame))
        // The camera's step scales by its largest multiplier between the short side and the corner.
        let tables = FujifilmRAF.LensTables(knots: SyntheticRAF.knots11, distortion: SyntheticRAF.distortion35,
                                            red: [Double](repeating: 0, count: 11), blue: [Double](repeating: 0, count: 11),
                                            vignetting: [Double](repeating: 100, count: 11))
        let builtIn = EmbeddedLensCorrection.outputScale(tables, shortSideRadius: Double(Self.height) / hypot(Double(Self.width), Double(Self.height)))
        #expect(abs(warp.scale(in: Self.frame) - builtIn) < 1e-9)
    }

    static func write(_ data: Data, _ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lens-corrections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    @Test("A RAF's tables: green distortion and vignetting for Auto, built in when LibRaw decodes, damaged ones reported")
    func rafState() throws {
        let url = try Self.write(SyntheticRAF.xe3(), "DSCF0001.RAF")
        guard case .tables(let tables) = CameraLensState.read(url, systemDecodes: true, decoderCorrects: false) else {
            Issue.record("no tables")
            return
        }
        let lens = try #require(FujifilmRAF(data: SyntheticRAF.xe3())?.lens)
        #expect(tables.origin == .fujifilm)
        #expect(tables.distortion?.radial == .fujifilm(knots: lens.knots, distortion: lens.distortion))
        #expect(tables.vignetting?.model == .fujifilm(knots: lens.knots, vignetting: lens.vignetting))
        #expect(CameraLensState.read(url, systemDecodes: true, decoderCorrects: true) == .decoderCorrects)
        #expect(CameraLensState.read(url, systemDecodes: false, decoderCorrects: false) == .builtInCorrection)
        // A lens with no distortion (zeros) has no distortion table; its vignetting stays.
        let flat = try Self.write(SyntheticRAF.xe3(tags: SyntheticRAF.elevenKnotTags(distortion: [Double](repeating: 0, count: 11))),
                                  "DSCF0002.RAF")
        #expect(CameraLensState.read(flat, systemDecodes: true, decoderCorrects: false).tables?.distortion == nil)
        #expect(CameraLensState.read(flat, systemDecodes: true, decoderCorrects: false).tables?.vignetting != nil)
        // Values no lens has: damaged (AC11).
        let damaged = try Self.write(SyntheticRAF.xe3(tags: SyntheticRAF.elevenKnotTags(vignetting: [Double](repeating: 1, count: 11))),
                                     "DSCF0003.RAF")
        #expect(CameraLensState.read(damaged, systemDecodes: true, decoderCorrects: false) == .unreadable)
        // The 1.25x crop mode: not this frame's tables.
        let cropped = try Self.write(SyntheticRAF.xe3(cropMode: 2), "DSCF0004.RAF")
        #expect(CameraLensState.read(cropped, systemDecodes: true, decoderCorrects: false) == .unreadable)
    }

    @Test("Not a raw, and raws with no table we read")
    func otherStates() throws {
        #expect(CameraLensState.read(URL(fileURLWithPath: "/tmp/a.jpg"), systemDecodes: false, decoderCorrects: false) == .notRaw)
        #expect(CameraLensState.read(URL(fileURLWithPath: "/tmp/a.RW2"), systemDecodes: true, decoderCorrects: false)
                == .tables(.none))
        #expect(CameraLensState.read(URL(fileURLWithPath: "/tmp/a.ORF"), systemDecodes: true, decoderCorrects: true)
                == .decoderCorrects)
    }

    @Test("The debug switch reads every usable table as damaged (AC11)")
    func corruptSwitch() throws {
        let url = try Self.write(SyntheticRAF.xe3(), "DSCF0005.RAF")
        LensCorrectionDebug.fault = .tableCorrupt
        defer { LensCorrectionDebug.fault = nil }
        #expect(CameraLensState.read(url, systemDecodes: true, decoderCorrects: false) == .unreadable)
        #expect(CameraLensState.read(url, systemDecodes: true, decoderCorrects: true) == .decoderCorrects)
    }

    @Test("DNG opcode lists: the green plane's warp and the radial vignetting; damaged lists throw")
    func dngOpcodeParsing() throws {
        let three = DNGOpcodes.list([
            .fixVignetteRadial([0.4, -0.1, 0, 0, 0], center: (0.52, 0.48)),
            .warpRectilinear(planes: [[1.01, 0, 0, 0, 0, 0], [0.97, 0.02, 0, 0, 0.001, 0], [0.99, 0, 0, 0, 0, 0]],
                             center: (0.5, 0.5)),
        ])
        let parsed = try DNGLensOpcodes.parse(three)
        #expect(parsed.warp == [0.97, 0.02, 0, 0, 0.001, 0, 0.5, 0.5])
        #expect(parsed.vignette == [0.4, -0.1, 0, 0, 0, 0.52, 0.48])
        let one = try DNGLensOpcodes.parse(DNGOpcodes.list([.warpRectilinear(planes: [[0.95, 0.05, 0, 0, 0, 0]])]))
        #expect(one.warp?.prefix(2) == [0.95, 0.05])
        // An unknown opcode is skipped by its length.
        let other = DNGOpcodes.list([DNGOpcodes.Opcode(identifier: 9, parameters: Data(count: 12), flags: 1)])
        #expect(try DNGLensOpcodes.parse(other) == DNGLensOpcodes.Parsed())
        for bad in [three.prefix(30), DNGOpcodes.list([.warpRectilinear(planes: [[7, 0, 0, 0, 0, 0]])]),
                    DNGOpcodes.list([.warpRectilinear(planes: [[1, 0, 0, 0, 0, 0]], center: (2, 0.5))]),
                    DNGOpcodes.list([.fixVignetteRadial([.nan, 0, 0, 0, 0])])] {
            #expect(throws: DNGLensOpcodes.ReadError.self) { try DNGLensOpcodes.parse(Data(bad)) }
        }
    }

    @Test("A DNG file's opcodes become Auto's tables, centered and scaled to its default crop")
    func dngFile() throws {
        var options = SyntheticDNG.Options(width: 400, height: 300, seed: 4, defaultCrop: CGRect(x: 10, y: 10, width: 380, height: 280))
        options.opcodeList3 = DNGOpcodes.list([
            .warpRectilinear(planes: [[0.97, 0.02, 0, 0, 0.001, 0]], center: (0.5, 0.5)),
            .fixVignetteRadial([0.4, 0, 0, 0, 0], center: (0.6, 0.5)),
        ])
        let url = try Self.write(try SyntheticDNG.data(options: options), "IMG_0001.dng")
        guard case .tables(let tables) = CameraLensState.read(url, systemDecodes: true, decoderCorrects: false) else {
            Issue.record("no tables")
            return
        }
        #expect(tables.origin == .dng)
        let warp = try #require(tables.distortion)
        #expect(warp.radial == .polynomial([0.97, 0.02, 0, 0]) && warp.tangential == SIMD2(0.001, 0))
        // The active area's corner is 250 pixels from its middle; the crop's half diagonal 236.2.
        #expect(abs(warp.geometry.radiusUnit - 250 / hypot(190.0, 140)) < 1e-9)
        #expect(warp.geometry.centerOffset == .zero)
        let gain = try #require(tables.vignetting)
        // Its center 40 pixels right of the crop's (y down), in units of the half diagonal.
        #expect(abs(gain.geometry.centerOffset.x - 40 / hypot(190.0, 140)) < 1e-9 && gain.geometry.centerOffset.y == 0)
        // A list that can't be read is reported (AC11); no list is no table.
        options.opcodeList3 = DNGOpcodes.list([.warpRectilinear(planes: [[9, 0, 0, 0, 0, 0]])])
        let damaged = try Self.write(try SyntheticDNG.data(options: options), "IMG_0002.dng")
        #expect(CameraLensState.read(damaged, systemDecodes: true, decoderCorrects: false) == .unreadable)
        options.opcodeList3 = nil
        let none = try Self.write(try SyntheticDNG.data(options: options), "IMG_0003.dng")
        #expect(CameraLensState.read(none, systemDecodes: true, decoderCorrects: false) == .tables(.none))
    }
}
