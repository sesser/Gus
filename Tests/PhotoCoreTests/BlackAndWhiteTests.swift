import CoreImage
import Foundation
import PhotoFixtures
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

/// The Black & White module (docs/features/bw-module, issue #218): the model
/// and its stack, the render against the CPU reference
/// (`BlackAndWhiteReference`), and the group's place among presets, paste,
/// copies and batches.
@Suite("Black & White")
struct BlackAndWhiteTests {
    typealias Filter = BlackAndWhite.Filter

    static func converted(_ amounts: [Filter: Double] = [:]) -> Adjustments {
        var values = Adjustments()
        values.blackAndWhite = BlackAndWhite(isOn: true, amounts)
        return values
    }

    static func render(_ values: Adjustments, _ input: LinearImage, context: RenderContext = RenderContext()) -> LinearImage {
        ReferenceTests.renderLinear(AdjustmentRenderer().render(values, to: input.ciImage, context: context))
    }

    /// The input is rounded once into the half-float working format and the
    /// gray once more (2⁻¹¹ relative each; the weights are positive and sum
    /// to 1, so the input's rounding stays relative to the gray for inputs
    /// that are not negative), plus float arithmetic for three products, two
    /// sums and the weights' own rounding to float (8 × 2⁻²⁴ < 2⁻²⁰), plus
    /// the spacing of the smallest half floats near 0.
    static func withinTolerance(_ actual: Float, _ expected: Float) -> Bool {
        abs(actual - expected) <= abs(expected) * (0x1p-10 + 0x1p-20) + 0x1p-24
    }

    /// Every pixel gray (R = G = B exactly) and equal to the reference.
    static func expectMatchesReference(_ rendered: LinearImage, _ expected: LinearImage,
                                       sourceLocation: SourceLocation = #_sourceLocation) {
        var failures = 0, unequal = 0
        var worst: (index: Int, error: Float) = (0, 0)
        for i in stride(from: 0, to: rendered.pixels.count, by: 4) {
            if rendered.pixels[i] != rendered.pixels[i + 1] || rendered.pixels[i] != rendered.pixels[i + 2] { unequal += 1 }
            for c in 0..<3 where !withinTolerance(rendered.pixels[i + c], expected.pixels[i + c]) {
                failures += 1
                let error = abs(rendered.pixels[i + c] - expected.pixels[i + c])
                if error > worst.error { worst = (i + c, error) }
            }
        }
        #expect(unequal == 0, "\(unequal) pixels with unequal channels", sourceLocation: sourceLocation)
        #expect(failures == 0, """
            \(failures) components outside the tolerance; worst at component \(worst.index): \
            \(rendered.pixels[worst.index]) instead of \(expected.pixels[worst.index])
            """, sourceLocation: sourceLocation)
    }

    static func atOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    /// The patch chart's patch at `column`, `row` (its center, away from the border).
    static func patch(_ image: LinearImage, column: Int, row: Int) -> SIMD4<Float> {
        image[(column * 2 + 1) * image.width / 12, (row * 2 + 1) * image.height / 8]
    }

    // MARK: Model and stack (R1, R2, R12, R13, AC5, AC12)

    @Test("Off and at 0 it is left out of the stack; on, even with every filter at 0, it is an edit (R1, AC12)")
    func stackRepresentation() throws {
        #expect(Adjustments().editStack == .identity)
        var values = Adjustments()
        values.blackAndWhite[.red] = 0
        #expect(values.editStack == .identity)

        let on = Self.converted()
        let operation = try #require(on.editStack.operations.first { $0.kind == BlackAndWhite.kind })
        #expect(operation.parameters == ["on": .bool(true)])
        #expect(on.editStack.renderHash != EditStack.identity.renderHash)
        #expect(on.isModified(Adjustments.Group.blackAndWhite) && on.blackAndWhiteApplies)

        // Read back exactly, values and on state.
        let mixed = Self.converted([.yellow: 40, .green: 30])
        #expect(Adjustments(stack: mixed.editStack) == mixed)
        #expect(mixed.editStack.operations.first?.parameters == ["on": .bool(true), "yellow": .number(40), "green": .number(30)])
    }

    @Test("A filter takes 0 to 100 and refuses anything else; stored values read back unchanged (AC5)")
    func amountsAreRangeChecked() throws {
        var module = BlackAndWhite()
        for filter in Filter.allCases {
            module[filter] = 0
            module[filter] = 100
            #expect(module[filter] == 100)
            module[filter] = 100.5
            module[filter] = -1
            module[filter] = .nan
            module[filter] = .infinity
            #expect(module[filter] == 100, "\(filter)")
            module[filter] = 37.5
            #expect(module[filter] == 37.5)
        }
        let stored = try EditStack.decode(from: try Self.converted([.orange: 63, .blue: 12.5]).editStack.jsonString())
        let read = Adjustments(stack: stored).blackAndWhite
        #expect(read[.orange] == 63 && read[.blue] == 12.5 && read.isOn)

        // As scripts set it (`photocli develop --set`): checked against the described range.
        #expect(throws: AdjustmentEdit.Failure.self) {
            try EditStack.identity.applying([.set(kind: BlackAndWhite.kind, parameter: "red", value: "150")])
        }
        #expect(throws: AdjustmentEdit.Failure.self) {
            try EditStack.identity.applying([.set(kind: BlackAndWhite.kind, parameter: "red", value: "-5")])
        }
        let edited = try EditStack.identity.applying([.set(kind: BlackAndWhite.kind, parameter: "red", value: "40")])
        // Setting a filter switches the conversion on, as in the app (design B10).
        #expect(Adjustments(stack: edited).blackAndWhite == BlackAndWhite(isOn: true, [.red: 40]))
        // Unless the same edit says otherwise.
        let kept = try EditStack.identity.applying([.set(kind: BlackAndWhite.kind, parameter: "red", value: "40"),
                                                    .set(kind: BlackAndWhite.kind, parameter: "on", value: "false")])
        #expect(Adjustments(stack: kept).blackAndWhite == BlackAndWhite(isOn: false, [.red: 40]))
    }

    @Test("The check box: on from nothing switches the conversion on; off keeps the values; on again brings them back (R1)")
    func checkBox() {
        var values = Adjustments()
        #expect(!values.blackAndWhiteApplies && !values.isModified(Adjustments.Group.blackAndWhite))
        values.setEnabled(.blackAndWhite, true)
        #expect(values.blackAndWhite == BlackAndWhite(isOn: true))
        #expect(values.blackAndWhiteApplies)

        values.blackAndWhite[.red] = 70
        values.setEnabled(.blackAndWhite, false)
        #expect(!values.blackAndWhiteApplies)
        #expect(values.blackAndWhite[.red] == 70 && values.isModified(Adjustments.Group.blackAndWhite))
        #expect(values.effective.blackAndWhite == BlackAndWhite())
        #expect(values.editStack.operations.first { $0.kind == BlackAndWhite.kind }?.isEnabled == false)

        values.setEnabled(.blackAndWhite, true)
        #expect(values.blackAndWhiteApplies && values.blackAndWhite[.red] == 70)

        // Turning off a group that was never used changes nothing.
        var fresh = Adjustments()
        fresh.setEnabled(.blackAndWhite, false)
        #expect(fresh == Adjustments())
    }

    @Test("Changing a filter while the group does not apply switches it on, in the same change (B10)")
    func changingAFilterSwitchesItOn() {
        // Never used.
        let before = Adjustments()
        var next = before
        next.blackAndWhite[.green] = 25
        next.enableModules(changedFrom: before)
        #expect(next.blackAndWhite == BlackAndWhite(isOn: true, [.green: 25]))

        // Turned off.
        var off = Self.converted([.red: 50])
        off.setEnabled(.blackAndWhite, false)
        var changed = off
        changed.blackAndWhite[.red] = 60
        changed.enableModules(changedFrom: off)
        #expect(changed.blackAndWhiteApplies && changed.blackAndWhite[.red] == 60)

        // Another group's change leaves it alone.
        var other = off
        other.exposure.ev = 1
        other.enableModules(changedFrom: off)
        #expect(!other.blackAndWhiteApplies)
    }

    @Test("A quick-set is one filter at 100 and the rest at 0, compared as the sliders round them (R6)")
    func quickSets() {
        for filter in Filter.allCases {
            var module = BlackAndWhite(isOn: false, [.yellow: 30, .blue: 80])
            module.choose(filter)
            #expect(module.isOn)
            #expect(module.quickSet == filter)
            for other in Filter.allCases {
                #expect(module[other] == (other == filter ? BlackAndWhite.quickSetAmount : 0))
            }
        }
        #expect(BlackAndWhite.quickSetAmount == 100)
        #expect(BlackAndWhite(isOn: true, [.red: 99.6]).quickSet == .red)
        #expect(BlackAndWhite(isOn: true, [.red: 99]).quickSet == nil)
        #expect(BlackAndWhite(isOn: true, [.red: 100, .green: 1]).quickSet == nil)
        #expect(BlackAndWhite(isOn: true).quickSet == nil)
        var cleared = BlackAndWhite(isOn: false, [.red: 100])
        cleared.clearFilters()
        #expect(cleared == BlackAndWhite(isOn: true) && cleared.hasNoFilter)
    }

    @Test("Reset gives back the stack of a photo that never had the group (R12, AC12)")
    func resetIsIdentity() {
        var values = Self.converted([.red: 100])
        values.exposure.ev = 0.5
        let reset = values.resetting(.blackAndWhite)
        var plain = Adjustments()
        plain.exposure.ev = 0.5
        #expect(reset == plain)
        #expect(reset.editStack.renderHash == plain.editStack.renderHash)
        #expect(Self.converted().resetting(.blackAndWhite).editStack.renderHash == EditStack.identity.renderHash)
        // Turned off, it is still reset.
        var off = Self.converted([.blue: 10])
        off.setEnabled(.blackAndWhite, false)
        #expect(off.isModified(Adjustments.Group.blackAndWhite))
        #expect(off.resetting(.blackAndWhite).editStack == .identity)
    }

    @Test("The group sits after Color Mixer and before Color Grading, in groups, headings and render order")
    func placement() throws {
        let groups = Adjustments.Group.presetGroups
        let mixer = try #require(groups.firstIndex(of: .colorMixer))
        #expect(groups[mixer + 1] == .blackAndWhite && groups[mixer + 2] == .colorGrade)
        let sections = Adjustments.Section.allCases
        let mixerSection = try #require(sections.firstIndex(of: .colorMixer))
        #expect(sections[mixerSection + 1] == .blackAndWhite && sections[mixerSection + 2] == .colorGrading)
        #expect(Adjustments.Section.blackAndWhite.groups == [.blackAndWhite])
        #expect(Adjustments.Group.blackAndWhite.kinds == [BlackAndWhite.kind])

        var values = Self.converted([.red: 10])
        values.colorMixer[.red] = .init(luminance: -10)
        values.colorGrade.midtones = GradeWheel(hue: 30, amount: 10)
        let kinds = values.editStack.operations.map(\.kind)
        #expect(kinds == [ColorMixer.kind, BlackAndWhite.kind, ColorGrade.kind])
        let modules = Adjustments.moduleDescriptions.map(\.kind)
        let described = try #require(modules.firstIndex(of: BlackAndWhite.kind))
        #expect(modules[described - 1] == ColorMixer.kind && modules[described + 1] == ColorGrade.kind)
        #expect(Adjustments.moduleDescription(BlackAndWhite.kind)?.group == .blackAndWhite)
    }

    @Test("The mask panel has no Black & White: local values carry none of its controls (R10)")
    func notALocalControl() {
        let names = Set(LocalValues.controls.map(\.name))
        #expect(!names.contains(BlackAndWhite.kind.rawValue))
        #expect(names.isDisjoint(with: BlackAndWhite.parameterDescriptions.map(\.name)))
        #expect(LocalValues().modules.blackAndWhite == BlackAndWhite())
    }

    // MARK: Render (R3, R4, R5, R8, AC1–AC4, AC8)

    @Test("Off, never used, or turned off: the render is the input's, byte for byte (R13, AC1)",
          arguments: [TestScene.patchChart, .hueRamp, .grayRamp])
    func offRendersNothing(scene: TestScene) {
        let input = scene.image()
        var notOn = Adjustments()
        notOn.blackAndWhite = BlackAndWhite(isOn: false, [.red: 80])
        var turnedOff = Self.converted([.blue: 100])
        turnedOff.setEnabled(.blackAndWhite, false)
        #expect(Self.render(notOn, input) == Self.render(Adjustments(), input))
        #expect(Self.render(turnedOff, input) == Self.render(Adjustments(), input))

        // With other edits: the same with or without a Black & White that does not apply.
        var edited = Adjustments()
        edited.exposure.ev = 0.4
        edited.colorMixer[.green] = .init(hue: 20)
        var editedOff = edited
        editedOff.blackAndWhite = turnedOff.blackAndWhite
        editedOff.setEnabled(.blackAndWhite, false)
        #expect(Self.render(editedOff, input) == Self.render(edited, input))
    }

    @Test("On with every filter at 0: the Rec. 709 luminance as gray, R = G = B, nothing clipped (R3, R8, AC2, AC8)",
          arguments: [TestScene.patchChart, .hueRamp, .grayRamp, .hazyLandscape])
    func luminanceMix(scene: TestScene) {
        let input = scene.image()
        let rendered = Self.render(Self.converted(), input)
        Self.expectMatchesReference(rendered, BlackAndWhiteReference.apply(input, [:]))
        // The gray ramp's bottom quarter runs to 4, two stops over white: kept.
        if scene == .grayRamp {
            let brightest = rendered[input.width - 1, input.height - 1]
            #expect(brightest.x > 3.9, "\(brightest)")
        }
    }

    static let mixes: [[Filter: Double]] = [
        [.yellow: 100], [.orange: 100], [.red: 100], [.green: 100], [.blue: 100],
        [.red: 35], [.yellow: 40, .green: 30], [.orange: 70, .blue: 20],
        [.yellow: 100, .orange: 100, .red: 100, .green: 100, .blue: 100],
    ]

    @Test("Any mix matches the reference, gray and unclipped (R4, R8, AC4, AC8)",
          arguments: mixes, [TestScene.patchChart, .hueRamp, .grayRamp])
    func mixesMatchReference(amounts: [Filter: Double], scene: TestScene) {
        let input = scene.image()
        Self.expectMatchesReference(Self.render(Self.converted(amounts), input),
                                    BlackAndWhiteReference.apply(input, amounts))
    }

    @Test("A neutral gray keeps its level whatever the filters say (R4, AC3)", arguments: mixes)
    func neutralsKeepTheirLevel(amounts: [Filter: Double]) {
        // The chart's six neutrals (top row) and the gray ramp, extended range included.
        for scene in [TestScene.patchChart, .grayRamp] {
            let input = scene.image()
            let plain = Self.render(Self.converted(), input)
            let filtered = Self.render(Self.converted(amounts), input)
            let rows = scene == .patchChart ? 0..<1 : 0..<4
            for column in 0..<(scene == .patchChart ? 6 : 16) {
                for row in rows {
                    let (x, y) = scene == .patchChart
                        ? ((column * 2 + 1) * input.width / 12, (row * 2 + 1) * input.height / 8)
                        : ((column * 2 + 1) * input.width / 32, (row * 2 + 1) * input.height / 8)
                    let neutral = input[x, y].x
                    #expect(Self.withinTolerance(filtered[x, y].x, neutral), "\(scene) at \(x), \(y): \(filtered[x, y].x) for \(neutral)")
                    #expect(filtered[x, y].x == plain[x, y].x || Self.withinTolerance(filtered[x, y].x, plain[x, y].x))
                }
            }
        }
        let weights = BlackAndWhite(isOn: true, amounts).weights
        #expect(abs(weights.x + weights.y + weights.z - 1) < 1e-12)
    }

    @Test("Each filter's direction: what lightens and darkens the red, green, blue and yellow patches (R5, AC4)")
    func directions() {
        let input = TestScene.patchChart.image()
        func grays(_ amounts: [Filter: Double]) -> (red: Float, green: Float, blue: Float, yellow: Float) {
            let rendered = Self.render(Self.converted(amounts), input)
            return (Self.patch(rendered, column: 0, row: 2).x, Self.patch(rendered, column: 1, row: 2).x,
                    Self.patch(rendered, column: 2, row: 2).x, Self.patch(rendered, column: 5, row: 2).x)
        }
        let plain = grays([:])
        let yellow = grays([.yellow: 100]), orange = grays([.orange: 100]), red = grays([.red: 100])
        let green = grays([.green: 100]), blue = grays([.blue: 100])
        // Yellow, Orange and Red: blue darker, red and yellow lighter; Orange and Red: green darker too.
        for (name, warm) in [("yellow", yellow), ("orange", orange), ("red", red)] {
            #expect(warm.blue < plain.blue, "\(name)")
            #expect(warm.red > plain.red, "\(name)")
            #expect(warm.yellow > plain.yellow || name == "red", "\(name)")
        }
        #expect(orange.green < plain.green && red.green < plain.green)
        // Red darkens blue more than Yellow does, Orange between them.
        #expect(red.blue < orange.blue && orange.blue < yellow.blue)
        // Green: green lighter, red darker. Blue: blue lighter, red and yellow darker.
        #expect(green.green > plain.green && green.red < plain.red)
        #expect(blue.blue > plain.blue && blue.red < plain.red && blue.yellow < plain.yellow)
        // The PRD's scene: a blue sky (the chart's sky patch) darker under Red than at 0.
        let rendered = Self.render(Self.converted([.red: 100]), input)
        let plainRendered = Self.render(Self.converted(), input)
        #expect(Self.patch(rendered, column: 5, row: 1).x < Self.patch(plainRendered, column: 5, row: 1).x * 0.8)
        // And the module's weights say the same as the reference's.
        for amounts in Self.mixes {
            let module = BlackAndWhite(isOn: true, amounts).weights
            let reference = BlackAndWhiteReference.weights(amounts)
            #expect(abs(module.x - reference.r) < 1e-12 && abs(module.y - reference.g) < 1e-12
                && abs(module.z - reference.b) < 1e-12)
        }
    }

    // MARK: Order (R7, R10, R14, AC7, AC10, AC14)

    @Test("The Color Mixer's luminance moves the grays; turned off, the color photo keeps that edit (R7, AC7)")
    func colorMixerFeedsTheMix() {
        let input = TestScene.patchChart.image()
        var mixed = Self.converted()
        mixed.colorMixer[.red] = .init(luminance: -60)
        let plain = Self.render(Self.converted(), input)
        let darker = Self.render(mixed, input)
        #expect(Self.patch(darker, column: 0, row: 2).x < Self.patch(plain, column: 0, row: 2).x * 0.95)

        var off = mixed
        off.setEnabled(.blackAndWhite, false)
        var colorOnly = Adjustments()
        colorOnly.colorMixer[.red] = .init(luminance: -60)
        let color = Self.render(colorOnly, input)
        #expect(Self.render(off, input) == color)
        // The conversion takes the mixer's result as its input.
        Self.expectMatchesReference(darker, BlackAndWhiteReference.apply(color, [:]))
        let red = Self.patch(Self.render(off, input), column: 0, row: 2)
        #expect(red.x > red.y * 2, "the red patch is red again: \(red)")
    }

    @Test("Color Grading after it tints the gray; Saturation and Vibrance after it do nothing to it (R7)")
    func stepsAfterIt() {
        let input = TestScene.patchChart.image()
        var graded = Self.converted()
        graded.colorGrade.midtones = GradeWheel(hue: 30, amount: 40)
        let tinted = Self.patch(Self.render(graded, input), column: 3, row: 0)
        #expect(tinted.x > tinted.z, "a warm tint over the gray: \(tinted)")

        var saturated = Self.converted([.red: 50])
        saturated.presence.saturation = 60
        saturated.presence.vibrance = 40
        let rendered = Self.render(saturated, input)
        // AC7: the gray values are those without Saturation and Vibrance.
        let unsaturated = Self.render(Self.converted([.red: 50]), input)
        for i in stride(from: 0, to: rendered.pixels.count, by: 4) {
            #expect(Self.withinTolerance(rendered.pixels[i], unsaturated.pixels[i]),
                    "\(rendered.pixels[i]) against \(unsaturated.pixels[i])")
            #expect(abs(rendered.pixels[i] - rendered.pixels[i + 1]) <= abs(rendered.pixels[i]) * 0x1p-9 + 0x1p-20)
            #expect(abs(rendered.pixels[i] - rendered.pixels[i + 2]) <= abs(rendered.pixels[i]) * 0x1p-9 + 0x1p-20)
        }
    }

    @Test("A stack with masks renders the global conversion under them (R10, AC10)")
    func masksWorkOnTheGray() {
        let input = TestScene.hazyLandscape.image()
        var values = Self.converted([.red: 100])
        values.local.masks = [GoldenCase.mask([.linear(LinearGradient(start: MaskPoint(x: 0.5, y: 0),
                                                                       end: MaskPoint(x: 0.5, y: 0.55)))]) {
            $0.exposure = -1
            $0.contrast = 20
        }]
        let rendered = Self.render(values, input)
        // The mask's exposure and contrast keep the gray gray, and change it.
        var unequal = 0
        for i in stride(from: 0, to: rendered.pixels.count, by: 4)
        where abs(rendered.pixels[i] - rendered.pixels[i + 1]) > abs(rendered.pixels[i]) * 0x1p-9 + 0x1p-20
            || abs(rendered.pixels[i] - rendered.pixels[i + 2]) > abs(rendered.pixels[i]) * 0x1p-9 + 0x1p-20 {
            unequal += 1
        }
        #expect(unequal == 0)
        #expect(rendered != Self.render(Self.converted([.red: 100]), input))
        // Below the mask (alpha 0) the global conversion alone.
        let x = input.width / 2, y = input.height - 2
        #expect(Self.withinTolerance(rendered[x, y].x, Self.render(Self.converted([.red: 100]), input)[x, y].x))
    }

    @Test("A mask's White Balance comes after the conversion, so it tints the gray where it applies (user guide)")
    func maskWhiteBalanceTints() {
        let input = TestScene.patchChart.image()
        var values = Self.converted()
        values.local.masks = [GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: 0.5, y: 0.5), radiusX: 2,
                                                                       radiusY: 2))]) {
            $0.temperature = 60
        }]
        let pixel = Self.patch(Self.render(values, input), column: 3, row: 0)
        #expect(pixel.x > pixel.z * 1.02, "a warm tint over the neutral patch: \(pixel)")
    }

    @Test("Grain after it stays gray: equal red, green and blue (R14, AC14)",
          arguments: [Grain(strength: 100), Grain(strength: 200, roughness: 10, size: 2)])
    func grainStaysGray(grain: Grain) {
        let input = TestScene.patchChart.image()
        var values = Self.converted([.orange: 60])
        values.grain = grain
        values.vignette = Vignette(amount: -40)
        let rendered = Self.render(values, input)
        #expect(rendered != Self.render(Self.converted([.orange: 60]), input))
        var unequal = 0
        for i in stride(from: 0, to: rendered.pixels.count, by: 4)
        where rendered.pixels[i] != rendered.pixels[i + 1] || rendered.pixels[i] != rendered.pixels[i + 2] {
            unequal += 1
        }
        #expect(unequal == 0, "\(unequal) pixels with unequal channels")
    }

    // MARK: Decoders (R9, AC9)

    @Test("The conversion is the same on every decoder's image: JPEG, raws by LibRaw or the system decoder (R9, AC9)")
    func everyDecoder() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let generator = WhiteBalanceAcrossDecodersTests.generator
            var files = [try WhiteBalanceAcrossDecodersTests.jpeg(in: folder),
                         try WhiteBalanceAcrossDecodersTests.libRawDNG(in: folder)]
            let system = try WhiteBalanceAcrossDecodersTests.systemDNG(in: folder)
            if SystemRAWDecoder.reads(system) { files.append(system) }
            #expect(!SystemRAWDecoder.reads(files[1]), "the small DNG is LibRaw's")
            let amounts: [Filter: Double] = [.red: 70, .yellow: 20]
            for url in files {
                // At full size: a resampling between the two would round at different points.
                let color = try generator.image(source: url, stack: .identity, longEdge: nil)
                let gray = try generator.image(source: url, stack: Self.converted(amounts).editStack, longEdge: nil)
                let colorPixels = ReferenceTests.renderLinear(Self.atOrigin(color))
                let grayPixels = ReferenceTests.renderLinear(Self.atOrigin(gray))
                Self.expectMatchesReference(grayPixels, BlackAndWhiteReference.apply(colorPixels, amounts))
            }
            // Contexts for each kind of file give one result over one image.
            let input = TestScene.hueRamp.image()
            let values = Self.converted(amounts)
            let jpegLike = Self.render(values, input, context: RenderContext(isRaw: false))
            #expect(Self.render(values, input, context: RenderContext(isRaw: true)) == jpegLike)
            #expect(Self.render(values, input, context: RenderContext(isRaw: false, balancedByDecoder: true)) == jpegLike)
        }
    }

    // MARK: Presets, paste, copies, batches (R11, AC11, AC13)

    @Test("A preset of only Black & White applies it and nothing else; one of every group switches it off (R11, AC11)")
    func presets() {
        var source = Self.converted([.red: 100])
        source.exposure.ev = 1
        let preset = AdjustmentPreset(name: "Red filter", groups: [.blackAndWhite], adjustments: source)
        #expect(preset.adjustments.exposure.ev == 0)
        var target = Adjustments()
        target.tone.contrast = 30
        let applied = preset.applied(onto: target)
        #expect(applied.blackAndWhite == source.blackAndWhite && applied.tone.contrast == 30 && applied.exposure.ev == 0)
        #expect(AdjustmentPreset.encodeGroups([.blackAndWhite]) == "blackAndWhite")
        #expect(AdjustmentPreset.decodeGroups("blackAndWhite,colorMixer") == [.blackAndWhite, .colorMixer])

        // A turned-off group travels turned off.
        var off = source
        off.setEnabled(.blackAndWhite, false)
        let appliedOff = AdjustmentPreset(name: "Off", groups: [.blackAndWhite], adjustments: off).applied(onto: target)
        #expect(!appliedOff.blackAndWhiteApplies && appliedOff.blackAndWhite[.red] == 100)

        // "All settings", saved before this group existed (stored as nil): it replaces the group too.
        #expect(AdjustmentPreset.decodeGroups(nil).contains(.blackAndWhite))
        let everything = AdjustmentPreset(name: "All", adjustments: Adjustments())
        #expect(everything.applied(onto: source).blackAndWhite == BlackAndWhite())
        #expect(source.modifiedGroups.contains(.blackAndWhite))
    }

    @Test("Paste carries the group; a source without it switches the target's off (R11, AC11)")
    func paste() {
        var copied = Self.converted([.green: 45])
        copied.setEnabled(.blackAndWhite, false)
        var target = Self.converted([.blue: 100])
        target.preserved = [EditOperation(kind: "futureThing")]
        let pasted = copied.pasted(onto: target)
        #expect(pasted.blackAndWhite == copied.blackAndWhite && !pasted.blackAndWhiteApplies)
        #expect(Adjustments().pasted(onto: target).blackAndWhite == BlackAndWhite())
    }

    @Test("A virtual copy starts with the original's conversion, then changes on its own; a batch is one write (R11, AC11)")
    func copiesAndBatches() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2), CatalogFixture.master(3)])
        let red = Self.converted([.red: 100])
        try await catalog.setEditStack(red.editStack, forVersion: ids[0], historyLabel: "Black & White Filter")
        let copyID = try await catalog.duplicateVersions(ids: [ids[0]])[0].copyVersionID
        let copied = try #require(try await catalog.version(id: copyID))
        #expect(Adjustments(stack: try copied.decodedEditStack()).blackAndWhite == red.blackAndWhite)
        try await catalog.setEditStack(Self.converted([.blue: 100]).editStack, forVersion: copyID,
                                       historyLabel: "Black & White Filter")
        let original = try #require(try await catalog.version(id: ids[0]))
        #expect(Adjustments(stack: try original.decodedEditStack()).blackAndWhite == red.blackAndWhite)

        // A preset over several photos: one write with one label for each.
        let preset = AdjustmentPreset(name: "Gray", groups: [.blackAndWhite], adjustments: Self.converted([.yellow: 50]))
        let stacks = Dictionary(uniqueKeysWithValues: ids.dropFirst().map { ($0, preset.applied(onto: Adjustments()).editStack) })
        try await catalog.setEditStacks(stacks, historyLabel: "Apply Preset")
        let stored = try await catalog.editStacks(forVersions: Array(ids.dropFirst()))
        for id in ids.dropFirst() {
            #expect(Adjustments(stack: try #require(stored.stacks[id])).blackAndWhite == BlackAndWhite(isOn: true, [.yellow: 50]))
            #expect(try await catalog.editHistory(forVersion: id).map(\.label) == ["Apply Preset"])
        }
    }

    @Test("A file is called monochrome only when its color model is gray; never a raw (design §6)")
    func monochromeFiles() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let gray = folder.appending(path: "gray.jpg")
            let context = try #require(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.setFillColor(gray: 0.4, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            try SyntheticImages.write(try #require(context.makeImage()), to: gray, type: .jpeg)
            #expect(SourceColorModel.isMonochrome(gray))
            #expect(!SourceColorModel.isMonochrome(try WhiteBalanceAcrossDecodersTests.jpeg(in: folder)))
            #expect(!SourceColorModel.isMonochrome(try WhiteBalanceAcrossDecodersTests.libRawDNG(in: folder)))
            #expect(!SourceColorModel.isMonochrome(folder.appending(path: "missing.jpg")))
        }
    }

    @Test("No pipeline version bump (R13, AC13)")
    func pipelineVersionUnchanged() {
        #expect(PreviewCacheKey.currentPipelineVersion == 12)
    }
}
