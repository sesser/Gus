import CoreImage
import Foundation
import PhotoFixtures
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

/// Color Fringes against the PRD's acceptance criteria on scenes (a) and (b)
/// (docs/features/chromatic-aberration/prd.md AC1–AC4, AC10, AC12; R11).
@Suite("Color fringes")
struct ColorFringesTests {
    typealias T = LensRenderingTests

    static let sceneA = TestScene.fringes.image()

    /// What a click on (x, y) of scene (a) picks: `FringePicker`'s snap and refusal.
    static func pick(_ x: Int, _ y: Int, in image: LinearImage = sceneA, radius: Double = 3) -> ColorFringes.Slot? {
        let picked = FringePicker.pick(center: CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5), radius: radius) { px, py in
            guard px >= 0, py >= 0, px < image.width, py < image.height else { return nil }
            let p = image[px, py]
            return SIMD3(Double(p.x), Double(p.y), Double(p.z))
        }
        guard let picked else { return nil }
        let chroma = (picked.color.y * picked.color.y + picked.color.z * picked.color.z).squareRoot()
        return chroma < ColorFringes.neutralChroma ? nil : ColorFringes.Slot(color: picked.color)
    }

    static func values(_ slot1: ColorFringes.Slot?, _ slot2: ColorFringes.Slot? = nil) -> Adjustments {
        var values = Adjustments()
        values.colorFringes = ColorFringes(slot1: slot1, slot2: slot2)
        return values
    }

    static func pixels(_ fringes: [FringeScene.Fringe]) -> [(x: Int, y: Int)] {
        fringes.flatMap { FringeScene.pixels(of: $0) }
    }

    static let purples: [FringeScene.Fringe] = [.purple1, .purple2, .discRim]
    static let greens: [FringeScene.Fringe] = [.green1, .green2]

    /// Fully grayed: weight ≥ 0.9986 for these pixels (each lies within three
    /// pixels of a high-contrast edge, inside the edge rule's window of 24,
    /// where its Gaussian of σ 6 leaves Φ(3.5) of the plateau), so at most
    /// 0.0014 of the pixel's chroma stays, plus a half-float gray's 0.002
    /// (`LensRenderingTests.grayChroma`); luminance is kept to two roundings.
    static func expectGrayed(_ after: LinearImage, _ before: LinearImage, _ where: [(x: Int, y: Int)],
                             sourceLocation: SourceLocation = #_sourceLocation) {
        var colored = 0, darker = 0
        for (x, y) in `where` {
            let a = T.rgb(after, x, y), b = T.rgb(before, x, y)
            if T.chroma(a) > 0.0014 * T.chroma(b) + T.grayChroma { colored += 1 }
            if abs(T.luminance(a) - T.luminance(b)) > T.halfFloat(T.luminance(b)) * 2 + 1e-5 { darker += 1 }
        }
        #expect(colored == 0, "\(colored) of \(`where`.count) pixels keep color", sourceLocation: sourceLocation)
        #expect(darker == 0, "\(darker) pixels changed luminance", sourceLocation: sourceLocation)
    }

    /// Unchanged: within two half-float roundings of the render without the feature.
    static func expectUnchanged(_ after: LinearImage, _ before: LinearImage, _ where: [(x: Int, y: Int)],
                                sourceLocation: SourceLocation = #_sourceLocation) {
        let changed = `where`.filter { x, y in
            let a = T.rgb(after, x, y), b = T.rgb(before, x, y)
            return (0..<3).contains { abs(a[$0] - b[$0]) > T.halfFloat(b[$0]) * 2 }
        }.count
        #expect(changed == 0, "\(changed) of \(`where`.count) pixels changed", sourceLocation: sourceLocation)
    }

    static let plain = T.render(Adjustments(), sceneA)

    // MARK: AC1

    @Test("AC1: picking the purple grays the purple fringes and the disc's rim, the green a second pick; clearing restores one")
    func picksGrayTheirFringes() throws {
        let purple = try #require(Self.pick(30, 60))
        let green = try #require(Self.pick(49, 60))
        #expect(FringeHueName.band(of: purple.color) == .purple)
        #expect(FringeHueName.band(of: green.color) == .green)

        let purpleOnly = T.render(Self.values(purple), Self.sceneA)
        Self.expectGrayed(purpleOnly, Self.plain, Self.pixels(Self.purples))
        Self.expectUnchanged(purpleOnly, Self.plain, Self.pixels(Self.greens))

        let both = T.render(Self.values(purple, green), Self.sceneA)
        Self.expectGrayed(both, Self.plain, Self.pixels(Self.purples + Self.greens))

        let greenOnly = T.render(Self.values(nil, green), Self.sceneA)
        Self.expectUnchanged(greenOnly, Self.plain, Self.pixels(Self.purples))
        Self.expectGrayed(greenOnly, Self.plain, Self.pixels(Self.greens))
    }

    @Test("A click within 2 pixels of a thin fringe picks the fringe, a neutral spot is refused")
    func pickSnapsAndRefuses() throws {
        // Bar 1's purple fringe is x 29 … 31, strongest at 31. A click on the
        // light ground one pixel from it reaches the strongest pixel; two
        // pixels from it, a paler pixel of the same fringe (the same hue).
        let on = try #require(Self.pick(31, 60, radius: 0.5))
        #expect(try #require(Self.pick(28, 60)).color == on.color)
        let near = try #require(Self.pick(27, 60))
        #expect(FringeToleranceDerivationTests.hueDistance(near.hue * 180 / .pi, on.hue * 180 / .pi) < 1)
        // The middle of the light ground and of a dark bar: no color.
        #expect(Self.pick(10, 60) == nil)
        #expect(Self.pick(40, 60) == nil)
    }

    // MARK: AC1a, AC1b

    @Test("AC1a: the listed purple and green, at their starting Tolerances, gray every fringe of scene (a)")
    func listedColorsGrayEveryFringe() {
        let rendered = T.render(T.listed(), Self.sceneA)
        Self.expectGrayed(rendered, Self.plain, Self.pixels(Self.purples + Self.greens))
    }

    @Test("AC1b: a listed color is stored as a pick is, and renders identically to a pick of the same value")
    func listedColorIsAPick() {
        let listed = CommonFringeColor.purple.slot
        let picked = ColorFringes.Slot(color: CommonFringeColor.purple.color)
        #expect(listed == picked)
        let a = Self.values(listed), b = Self.values(picked)
        #expect(a.editStack.operations.map(\.parameters) == b.editStack.operations.map(\.parameters))
        #expect(a.editStack.renderHash == b.editStack.renderHash)
        // A listed color's Tolerance is left out of the stack: it is its color's starting value.
        #expect(a.editStack.operations.first?.parameters.keys.sorted() == ["color1"])
        #expect(T.render(a, Self.sceneA) == T.render(b, Self.sceneA))
        // Its range widens and narrows like any pick's.
        var narrower = a
        narrower.colorFringes.slot1?.tolerance = 0
        #expect(T.render(narrower, Self.sceneA) != T.render(a, Self.sceneA))
    }

    // MARK: AC2

    /// Hue (degrees) of scene (a)'s pixel.
    static func hue(_ x: Int, _ y: Int) -> Double {
        let lab = T.okLab(T.rgb(sceneA, x, y))
        return atan2(lab.z, lab.y) * 180 / .pi
    }

    @Test("AC2: a fringe a known hue away is untouched at Tolerance 0 and gray when wider; widening never shrinks the set; slots are independent")
    func toleranceWidens() throws {
        let bluest = try #require(Self.pick(30, 60))
        // Bar 2's purple, a known distance from bar 1's.
        let other = FringeScene.pixels(of: .purple2)
        let distance = FringeToleranceDerivationTests.hueDistance(Self.hue(other[0].x, other[0].y),
                                                                  bluest.hue * 180 / .pi)
        #expect(distance > ColorFringes.hueReach(tolerance: 0))
        var narrow = bluest
        narrow.tolerance = 0
        Self.expectUnchanged(T.render(Self.values(narrow), Self.sceneA), Self.plain, other)
        var wide = bluest
        wide.tolerance = Double(try #require((0...100).first { ColorFringes.hueReach(tolerance: Double($0)) / 2 >= distance + 1 }))
        Self.expectGrayed(T.render(Self.values(wide), Self.sceneA), Self.plain, other)

        // Over widening steps, the changed pixels never shrink.
        var previous: Set<Int> = []
        let green = CommonFringeColor.green.slot
        var greenEffect: LinearImage?
        for tolerance in stride(from: 0.0, through: 100, by: 10) {
            var slot = bluest
            slot.tolerance = tolerance
            let rendered = T.render(Self.values(slot, green), Self.sceneA)
            var changed: Set<Int> = []
            for y in 0..<rendered.height {
                for x in 0..<rendered.width {
                    let a = T.rgb(rendered, x, y), b = T.rgb(Self.plain, x, y)
                    if (0..<3).contains(where: { abs(a[$0] - b[$0]) > T.halfFloat(b[$0]) * 2 }) {
                        changed.insert(y * rendered.width + x)
                    }
                }
            }
            #expect(previous.isSubset(of: changed), "Tolerance \(tolerance) dropped \(previous.subtracting(changed).count)")
            previous = changed
            // Changing Color 1's Tolerance leaves Color 2's effect alone.
            let greens = Self.pixels(Self.greens)
            if let greenEffect { Self.expectUnchanged(rendered, greenEffect, greens) }
            greenEffect = rendered
        }
    }

    // MARK: AC3

    @Test("AC3: from the middle of a range to its edge, the color removed falls without a step")
    func falloffIsSoft() throws {
        let (x, y) = (30, 60)
        let base = try #require(Self.pick(x, y))
        let before = T.chroma(T.rgb(Self.plain, x, y))
        let reach = ColorFringes.hueReach(tolerance: base.tolerance)
        let steps = 40
        var removed: [Double] = []
        for step in 0...(steps + 4) {
            // The slot's hue turned away from the pixel's, chroma and lightness kept.
            let angle = base.hue + Double(step) / Double(steps) * reach * .pi / 180
            let c = base.chroma
            var slot = base
            slot.color = SIMD3(base.color.x, c * cos(angle), c * sin(angle))
            let after = T.chroma(T.rgb(T.render(Self.values(slot), Self.sceneA), x, y))
            removed.append(1 - after / before)
        }
        #expect(removed[0] > 0.998, "at the middle: \(removed[0])")
        #expect(removed[steps...].allSatisfy { abs($0) < 1e-3 }, "at the edge and beyond: \(removed[steps...])")
        // smoothstep's steepest slope is 1.5 per half reach: 0.075 per step of a fortieth.
        for i in 1..<removed.count {
            #expect(removed[i] <= removed[i - 1] + 1e-3, "rises at step \(i)")
            #expect(removed[i - 1] - removed[i] <= 0.075 + 2e-3, "a step of \(removed[i - 1] - removed[i]) at \(i)")
        }
    }

    // MARK: AC4

    @Test("AC4: purple and green subjects away from edges keep their color while inside a range")
    func subjectsKeepTheirColor() {
        let scene = TestScene.fringeSubjects.image()
        let values = T.listed()
        let plain = T.render(Adjustments(), scene)
        let rendered = T.render(values, scene)
        // Away from edges: where no high-contrast edge is within the rule's reach.
        let edges = LensReference.edgeWeight(scene, scale: 1)
        for (purple, slot) in [(true, CommonFringeColor.purple.slot), (false, CommonFringeColor.green.slot)] {
            let patch = FringeScene.patch(purple: purple)
            let lab = T.okLab(T.rgb(scene, patch[0].x, patch[0].y))
            // Inside the range: the hue alone would gray it fully.
            #expect(ColorFringes.colorWeight(a: lab.y, b: lab.z, slot: slot) == 1)
            let away = patch.filter { edges[$0.y * scene.width + $0.x] == 0 }
            #expect(away.count > patch.count / 3, "\(away.count) of \(patch.count) patch pixels away from edges")
            Self.expectUnchanged(rendered, plain, away)
        }
        // The sky beside the ridge's high-contrast edge stays blue.
        Self.expectUnchanged(rendered, plain, FringeScene.skyByRidge())
    }

    @Test("AC4: pixels whose colors are outside every range match the render without the feature",
          arguments: [TestScene.fringes, .fringeSubjects])
    func colorsOutsideEveryRangeAreUnchanged(scene: TestScene) {
        let image = scene.image()
        let values = T.listed()
        let plain = T.render(Adjustments(), image)
        let rendered = T.render(values, image)
        var outside: [(x: Int, y: Int)] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let lab = T.okLab(T.rgb(image, x, y))
                if values.colorFringes.slots.allSatisfy({ ColorFringes.colorWeight(a: lab.y, b: lab.z, slot: $0) == 0 }) {
                    outside.append((x, y))
                }
            }
        }
        #expect(outside.count > image.width * image.height / 2)
        Self.expectUnchanged(rendered, plain, outside)
    }

    // MARK: AC10

    /// The loupe's fit render of a 1024 × 768 master is 256 × 192 at scale
    /// ¼: the edge rule's window becomes 6 pixels for 24, its blur σ 1.5 for
    /// 6. One fit pixel covers 4 × 4 master pixels, so where the map falls
    /// from gray to black the two can disagree within a fit pixel either
    /// side of the boundary: 8 master pixels, plus the window's rounding.
    @Test("AC10: the fit render scaled to full size and a full-size render agree on what is grayed")
    func fitAndFullSizeAgree() {
        let values = T.listed()
        let full = TestScene.fringes.image(width: 1024, height: 768)
        let fit = Self.sceneA
        let fullMap = LensRenderingTests.renderFloat(AdjustmentRenderer().fringeMap(values, to: full.ciImage,
                                                                                     context: RenderContext(scale: 1)))
        let fitMap = LensRenderingTests.renderFloat(AdjustmentRenderer().fringeMap(values, to: fit.ciImage,
                                                                                    context: RenderContext(scale: 0.25)))
        func grayed(_ map: LinearImage, _ x: Int, _ y: Int) -> Bool { map[x, y].x > 0.5 }
        var disagree = 0, far = 0, grayedPixels = 0
        for y in 0..<768 {
            for x in 0..<1024 {
                let a = grayed(fullMap, x, y), b = grayed(fitMap, x / 4, y / 4)
                if a { grayedPixels += 1 }
                guard a != b else { continue }
                disagree += 1
                // The other answer must be within 8 master pixels.
                var near = false
                search: for dy in -8...8 {
                    for dx in -8...8 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < 1024, ny < 768 else { continue }
                        if grayed(fullMap, nx, ny) == b { near = true; break search }
                    }
                }
                if !near { far += 1 }
            }
        }
        #expect(grayedPixels > 0)
        #expect(far == 0, "\(far) of \(disagree) disagreeing pixels are away from a boundary")
    }

    // MARK: AC12

    @Test("AC12: the listed colors gray scene (a)'s fringes in a DNG, a JPEG, a HEIC and a TIFF")
    func everyPhotoFormat() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let image = try #require(Self.sceneA.cgImage(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
            var files: [(url: URL, width: Int, height: Int)] = []
            for (name, type) in [("a.jpg", UTType.jpeg), ("a.heic", .heic), ("a.tif", .tiff)] {
                let url = folder.appending(path: name)
                try SyntheticImages.write(image, to: url, type: type, quality: 0.9)
                files.append((url, 256, 192))
            }
            // 320 × 240: the RAW decoder gives no image for the synthetic DNG at 256 × 192
            // (docs/archive/PHASE6_PLAN.md, finding 4).
            let dng = folder.appending(path: "a.dng")
            try SyntheticDNG.write(to: dng, options: .init(width: 320, height: 240, seed: 1, scene: .testScene(.fringes)))
            files.append((dng, 320, 240))
            let generator = PreviewGenerator(engine: ReferenceTests.engine)
            for (url, width, height) in files {
                let plain = ReferenceTests.renderLinear(try generator.image(source: url, stack: .identity, longEdge: nil))
                let grayed = ReferenceTests.renderLinear(try generator.image(source: url, stack: T.listed().editStack,
                                                                             longEdge: nil))
                #expect(plain.width == width, "\(url.lastPathComponent)")
                // Lossy files and the RAW decoder blur and shift a fringe's
                // color a little; most of it still has to go.
                for fringes in [Self.purples, Self.greens] {
                    let pixels = fringes.flatMap { FringeScene.pixels(of: $0, width: width, height: height) }
                    let before = pixels.map { T.chroma(T.rgb(plain, $0.x, $0.y)) }.reduce(0, +)
                    let after = pixels.map { T.chroma(T.rgb(grayed, $0.x, $0.y)) }.reduce(0, +)
                    #expect(after < 0.2 * before, "\(url.lastPathComponent): \(after / before) of the chroma stays")
                }
            }
        }
    }

    // MARK: R11

    @Test("R11: without the Lens groups, nothing in the pipeline changes")
    func identityWithoutTheFeature() {
        var values = Adjustments()
        values.exposure.ev = 0.5
        let input = Self.sceneA.ciImage
        #expect(AdjustmentRenderer.lens(values, input, context: RenderContext()) === input)
        #expect(values.decodeSettings == RAWDecodeSettings())
        // Turned off, the groups render as if absent; the values are kept.
        var off = values
        off.colorFringes = T.listed().colorFringes
        off.colorAlignment = ColorAlignment(red: 20)
        off.setEnabled(.colorFringes, false)
        off.setEnabled(.colorAlignment, false)
        #expect(off.effective.colorFringes.isIdentity && off.colorFringes.slot1 != nil)
        #expect(T.render(off, Self.sceneA) == T.render(values, Self.sceneA))
        #expect(off.decodeSettings == values.decodeSettings)
    }
}
