import CoreImage
import Foundation
import Metal
import PhotoFixtures
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

/// Heal and clone spots (docs/features/healing): the stored operation, its
/// group, paste and presets, the geometry rules and the limit.
@Suite("Spots: model")
struct SpotModelTests {
    static func spot(_ index: Int = 0, x: Double = 0.3, y: Double = 0.4, size: Double = 0.02, sourceX: Double = 0.5,
                     sourceY: Double = 0.4, mode: SpotMode = .heal) -> Spot {
        Spot(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!, mode: mode,
             center: MaskPoint(x: x, y: y), size: size, source: MaskPoint(x: sourceX, y: sourceY))
    }

    static func values(_ spots: [Spot]) -> Adjustments {
        var values = Adjustments()
        values.spots.spots = spots
        return values
    }

    @Test("Spots are one operation of kind spots, stored before white balance, and read back exactly")
    func roundTrip() throws {
        var values = Self.values([Self.spot(0), Self.spot(1, x: 0.7, mode: .clone)])
        values.spots.spots[1].feather = 20
        values.spots.spots[1].opacity = 60
        values.exposure.ev = 0.5
        values.colorAlignment = ColorAlignment(red: 10)
        let stack = values.editStack
        let kinds = stack.operations.map(\.kind)
        #expect(kinds.filter { $0 == Spots.kind }.count == 1)
        let spotIndex = try #require(kinds.firstIndex(of: Spots.kind))
        #expect(spotIndex > kinds.firstIndex(of: ColorAlignment.kind)!)
        #expect(spotIndex < kinds.firstIndex(of: Exposure.kind)!)
        #expect(stack.schemaVersion == 2)
        let decoded = try EditStack.decode(from: stack.jsonData())
        #expect(Adjustments(stack: decoded) == values)
        // Defaults are left out: a heal at feather 50 and opacity 100 stores neither.
        guard case .list(let list)? = stack.operations[spotIndex].parameters["spots"],
              case .object(let first)? = list.first, case .object(let second)? = list.last else {
            Issue.record("spots are not a list of objects")
            return
        }
        #expect(Set(first.keys) == ["id", "x", "y", "size", "sourceX", "sourceY"])
        #expect(second["mode"] == .string("clone") && second["feather"] == .number(20) && second["opacity"] == .number(60))
    }

    @Test("No spots adds nothing to the stack: an untouched photo's stack and hash are as before (R6, AC5)")
    func noSpotsChangesNothing() {
        #expect(Adjustments().editStack == .identity)
        var values = Adjustments()
        values.exposure.ev = 1
        var withEmpty = values
        withEmpty.spots = Spots()
        #expect(withEmpty.editStack.renderHash == values.editStack.renderHash)
        #expect(withEmpty.editStack.operations.map(\.kind) == values.editStack.operations.map(\.kind))
        #expect(!values.editStack.operations.contains { $0.kind == Spots.kind })
        #expect(values.decodeSettings == withEmpty.decodeSettings)
    }

    static func stack(_ spotObjects: [[String: EditParameter]]) -> Data {
        let operation = EditOperation(kind: Spots.kind, parameters: ["spots": .list(spotObjects.map(EditParameter.object))])
        return (try? EditStack(operations: [operation]).jsonData()) ?? Data()
    }

    @Test("Reading is strict: an unknown key, mode or type, or a missing position, makes the stack unreadable")
    func strictRead() throws {
        let good = Self.spot().parametersForTest
        #expect(throws: Never.self) { try EditStack.decode(from: Self.stack([good])) }
        var unknownKey = good
        unknownKey["radius"] = .number(0.1)
        var unknownMode = good
        unknownMode["mode"] = .string("smudge")
        var wrongType = good
        wrongType["x"] = .string("0.5")
        var missing = good
        missing["sourceY"] = nil
        var noID = good
        noID["id"] = nil
        for bad in [unknownKey, unknownMode, wrongType, missing, noID] {
            #expect {
                try EditStack.decode(from: Self.stack([bad]))
            } throws: { error in
                guard case .invalidOperation = error as? EditStack.DecodingFailure else { return false }
                return EditStack.ReadFailure(error) == .damaged
            }
        }
        // Numbers out of range are clamped, as the modules do.
        var outside = good
        outside["size"] = .number(4)
        outside["opacity"] = .number(-3)
        let read = Adjustments(stack: try EditStack.decode(from: Self.stack([outside]))).spots.spots[0]
        #expect(read.size == Spot.sizeRange.upperBound && read.opacity == 0)
    }

    @Test("100 spots are allowed; a stack of 101 is unreadable and never written over (R10, AC9)")
    func limit() throws {
        let hundred = (0..<SpotLimits.spots).map { Self.spot($0).parametersForTest }
        #expect(throws: Never.self) { try EditStack.decode(from: Self.stack(hundred)) }
        let over = hundred + [Self.spot(SpotLimits.spots).parametersForTest]
        #expect {
            try EditStack.decode(from: Self.stack(over))
        } throws: { error in
            EditStack.ReadFailure(error) == .exceedsLimits
        }
        let full = Spots(spots: (0..<SpotLimits.spots).map { Self.spot($0) })
        #expect(!SpotLimits.canAddSpot(to: full))
        #expect(SpotLimits.canAddSpot(to: Spots(spots: Array(full.spots.dropLast()))))
        #expect(SpotLimits.allows(full))
        #expect(!SpotLimits.allows(Spots(spots: full.spots + [Self.spot(500)])))
    }

    @Test("A newer kind version of spots is kept as it is, unread")
    func newerKindVersionIsPreserved() throws {
        let operation = EditOperation(kind: Spots.kind, kindVersion: 2, parameters: ["spots": .list([.object(["shape": .string("lasso")])])])
        let stack = EditStack(operations: [operation])
        let decoded = try EditStack.decode(from: stack.jsonData())
        let values = Adjustments(stack: decoded)
        #expect(values.spots.isIdentity)
        #expect(values.editStack.operations == [operation])
    }

    @Test("The check box turns spots off without losing them; off renders as none, by hash (R18, AC15)")
    func groupTurnsSpotsOff() throws {
        var values = Self.values([Self.spot()])
        values.exposure.ev = 0.3
        var none = values
        none.spots = Spots()
        values.setEnabled(.spots, false)
        #expect(!values.isEnabled(.spots))
        #expect(values.spots.spots.count == 1)
        #expect(values.effective.spots.isIdentity)
        // What renders is the same (byte for byte: `SpotRenderingTests.offRendersAsNone`). The hash still
        // differs, as for masks turned off: the stack keeps schema version 2 while it holds objects.
        #expect(values.effective == none.effective)
        #expect(values.decodeSettings == none.decodeSettings)
        let stored = try EditStack.decode(from: values.editStack.jsonData())
        #expect(stored.operations.first { $0.kind == Spots.kind }?.isEnabled == false)
        var back = Adjustments(stack: stored)
        #expect(back.spots == values.spots && !back.isEnabled(.spots))
        back.setEnabled(.spots, true)
        #expect(back.effective != none.effective)
        #expect(AdjustmentPreset.decodeGroups("spots,exposure").isEmpty)
        #expect(Adjustments.Section.spots.groups == [.spots])
    }

    @Test("Paste and presets leave the target's spots and their on/off state, and never carry the source's (R11, AC10)")
    func pasteAndPresetsLeaveSpots() {
        var source = Self.values([Self.spot(0), Self.spot(1)])
        source.exposure.ev = 1
        var target = Self.values([Self.spot(7, x: 0.8)])
        target.setEnabled(.spots, false)

        let pasted = source.pasted(onto: target)
        #expect(pasted.exposure.ev == 1)
        #expect(pasted.spots == target.spots && !pasted.isEnabled(.spots))
        #expect(source.pasted(onto: Adjustments()).spots.isIdentity)

        // Every group, as a preset saved with "all settings" would hold them.
        let preset = AdjustmentPreset(name: "All", groups: Set(Adjustments.Group.allCases), adjustments: source)
        #expect(!preset.groups.contains(.spots))
        #expect(preset.adjustments.spots.isIdentity)
        #expect(preset.includesEveryGroup)
        let applied = preset.applied(onto: target)
        #expect(applied.exposure.ev == 1)
        #expect(applied.spots == target.spots && !applied.isEnabled(.spots))
        #expect(Adjustments().replacing(Set(Adjustments.Group.allCases), from: source).spots.isIdentity)
        #expect(!source.modifiedGroups.contains(.spots))
        #expect(!Adjustments.Group.presetGroups.contains(.spots))
        #expect(AdjustmentPreset.encodeGroups(Set(Adjustments.Group.presetGroups)) == nil)
    }

    @Test("Reset All clears spots; a raw with spots decodes its whole sensor, as with masks")
    func resetAllAndFullFrame() {
        let values = Self.values([Self.spot()])
        #expect(values.decodeSettings.fullFrame)
        #expect(Adjustments(stack: EditStack(operations: values.preserved)).spots.isIdentity)
        var off = values
        off.setEnabled(.spots, false)
        #expect(!off.decodeSettings.fullFrame)
        #expect(values.resetting(.spots).spots.isIdentity)
    }

    @Test("A source is kept inside the photo and clear of its own spot")
    func sourceRules() {
        let geometry = SpotGeometry(frameSize: CGSize(width: 400, height: 200))
        // Radius 8 px. A source overlapping the spot is pushed out along the same line.
        let overlapping = geometry.constrainedSource(CGPoint(x: 105, y: 100), center: CGPoint(x: 100, y: 100), radius: 8)
        #expect(abs(overlapping.x - 116) < 1e-9 && overlapping.y == 100)
        // Coinciding centers go to the right.
        #expect(geometry.constrainedSource(CGPoint(x: 100, y: 100), center: CGPoint(x: 100, y: 100), radius: 8)
            == CGPoint(x: 116, y: 100))
        // Held inside the frame.
        #expect(geometry.constrainedSource(CGPoint(x: 395, y: -20), center: CGPoint(x: 200, y: 100), radius: 8)
            == CGPoint(x: 392, y: 8))

        let spot = Spot(center: MaskPoint(x: 0.25, y: 0.5), size: 0.02, source: MaskPoint(x: 0.35, y: 0.5))
        // Moving keeps the offset.
        let moved = geometry.moving(spot, to: MaskPoint(x: 0.5, y: 0.25))
        #expect(abs(moved.source.x - 0.6) < 1e-6 && abs(moved.source.y - 0.25) < 1e-6)
        // Near the right edge the source stops at the edge.
        let atEdge = geometry.moving(spot, to: MaskPoint(x: 0.9, y: 0.5))
        #expect(abs(atEdge.source.x * 400 - 392) < 1e-3)
        // Growing pushes the source out until the circles touch (radius 24 px, 48 px apart).
        let grown = geometry.resizing(spot, to: 0.06)
        #expect(abs((grown.source.x - grown.center.x) * 400 - 48) < 1e-3)
        // A dragged source stops at its own spot.
        let dragged = geometry.sourcing(spot, from: MaskPoint(x: 0.26, y: 0.5))
        #expect(abs((dragged.source.x - dragged.center.x) * 400 - 16) < 1e-3)

        #expect(SpotGeometry.direction(from: .zero, to: CGPoint(x: -5, y: 0)) == .left)
        #expect(SpotGeometry.direction(from: .zero, to: CGPoint(x: 5, y: -5)) == .upperRight)
        #expect(SpotGeometry.direction(from: .zero, to: CGPoint(x: 0, y: 5)) == .below)
    }
}

extension Spot {
    var parametersForTest: [String: EditParameter] { parameters }
}

/// The spot kernels against `SpotReference`, the automatic source, and the
/// render's place in the pipeline.
@Suite("Spots: rendering")
struct SpotRenderingTests {
    static let floatContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [
        .workingColorSpace: RenderEngine.workingColorSpace, .workingFormat: CIFormat.RGBAf, .cacheIntermediates: false,
    ])
    static let floatLock = Mutex(())
    static let engine = RenderEngine(contextCount: 1, name: "spots")

    static func renderFloat(_ image: CIImage) -> LinearImage {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        floatLock.withLock { _ in
            pixels.withUnsafeMutableBytes { buffer in
                floatContext.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: image.extent,
                                    format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
            }
        }
        return LinearImage(width: width, height: height, pixels: pixels)
    }

    /// Through the app's half-float context.
    static func renderHalf(_ image: CIImage) -> LinearImage {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            engine.withContext {
                $0.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: image.extent,
                          format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
            }
        }
        return LinearImage(width: width, height: height, pixels: pixels)
    }

    static func maximumDifference(_ a: LinearImage, _ b: LinearImage) -> Float {
        zip(a.pixels, b.pixels).enumerated().reduce(0) { $1.offset % 4 == 3 ? $0 : max($0, abs($1.element.0 - $1.element.1)) }
    }

    static let cases: [[Spot]] = [
        [GoldenCase.spot(0, x: 80, y: 60, radius: 9, sourceX: 110, sourceY: 60)],
        [GoldenCase.spot(0, x: 170, y: 100, radius: 11, sourceX: 170, sourceY: 140, feather: 0)],
        [GoldenCase.spot(0, x: 40, y: 150, radius: 8, sourceX: 70, sourceY: 150, mode: .clone, opacity: 80)],
        // Overlapping spots, each reading what the one before left; one near the edge, one sourced past it.
        [GoldenCase.spot(0, x: 80, y: 60, radius: 9, sourceX: 105, sourceY: 70),
         GoldenCase.spot(1, x: 92, y: 64, radius: 12, sourceX: 92, sourceY: 100, feather: 80, opacity: 70),
         GoldenCase.spot(2, x: 4, y: 188, radius: 6, sourceX: 30, sourceY: 180)],
    ]

    /// Float context: the kernels' arithmetic in single precision against the
    /// reference's. Every sample sits on a pixel center or is interpolated by
    /// hand, so they differ only by the order of float operations and by
    /// Metal's cos, sin and division (a few units in the last place, 2⁻²⁴
    /// relative each) in the 64-point membrane sum: under 10⁻⁵ of the values
    /// involved, which stay under 1.5 here. Twice that.
    static let floatTolerance: Float = 3e-5

    @Test("Heal and clone match their CPU reference (AC13)", arguments: cases.indices)
    func matchesReference(_ index: Int) {
        let input = TestScene.dustySky.image()
        let expected = SpotReference.apply(Self.cases[index], to: input)
        let actual = Self.renderFloat(SpotRenderer.apply(Self.cases[index], to: input.ciImage))
        let difference = Self.maximumDifference(actual, expected)
        print("SpotRenderingTests: case \(index) largest difference \(difference), \(difference / Self.floatTolerance) of the derived tolerance")
        #expect(difference <= Self.floatTolerance, "case \(index): \(difference)")
        // The spots changed something: the reference is not the input.
        #expect(Self.maximumDifference(expected, input) > 0.01)
    }

    /// In the app's half-float context: the input is rounded once into half
    /// float (2⁻¹¹ relative), and a heal's value is a combination of input
    /// values whose coefficients' magnitudes sum to at most 3 (the base, the
    /// source and the membrane's averaged differences of two values), so that
    /// rounding moves it by 3 · 2⁻¹¹ of the largest value; the boundary
    /// differences are stored once (2⁻¹¹ of their size, at most the largest
    /// value) and the result once more. 5 · 2⁻¹¹ of the largest value.
    @Test("In the app's half-float context, spots stay within their derived bound")
    func halfFloatBound() {
        let input = TestScene.dustySky.image()
        let largest = input.pixels.enumerated().filter { $0.offset % 4 != 3 }.map(\.element).max() ?? 1
        for spots in Self.cases {
            let expected = SpotReference.apply(spots, to: input)
            let actual = Self.renderHalf(SpotRenderer.apply(spots, to: input.ciImage))
            let difference = Self.maximumDifference(actual, expected), bound = 5 * 0x1p-11 * largest + Self.floatTolerance
            print("SpotRenderingTests: half float largest difference \(difference), \(difference / bound) of the derived bound")
            #expect(difference <= bound)
        }
    }

    @Test("The kernels compile from Metal source")
    func kernelsCompile() throws {
        #expect(try SpotKernels.compile() == 2)
    }

    /// The sky without its specks, perceptual, at a pixel.
    static func clearSky(_ x: Int, _ y: Int, image: LinearImage) -> SIMD3<Double> {
        let pixel = image[x, y]
        return SIMD3(Double(pixel.x), Double(pixel.y), Double(pixel.z))
    }

    static func encode(_ v: Float) -> Double { LuminanceWindow.encodeSRGB(Double(v)) }

    /// The automatic source over the dusty sky, as placement finds it.
    static func autoSpot(_ speck: (x: Double, y: Double, radius: Double), others: [Spot] = [], crop: Crop = Crop(),
                         image: CIImage) -> Spot? {
        let width = Double(TestScene.defaultWidth), height = Double(TestScene.defaultHeight)
        let center = MaskPoint(x: speck.x / width, y: speck.y / height)
        let size = (speck.radius + 3) / width
        guard let source = SpotSourceFinder.source(for: center, size: size, others: others, crop: crop, image: image,
                                                   engine: engine) else { return nil }
        return Spot(center: center, size: size, source: source)
    }

    /// The sky's grain is ±1 % of its perceptual value (about 0.6 to 0.9):
    /// the spot's and the source's grain differ by at most 2 % of it, 0.018,
    /// and the membrane's boundary differences carry the same grain averaged
    /// over nine samples and many boundary points, at most a third of that.
    /// The gradient's curvature over a 30-pixel circle is under 10⁻⁴. 0.025
    /// bounds a heal that lands on clean sky; the specks themselves are 0.2
    /// darker in the middle.
    static let healTolerance = 0.025

    @Test("The automatic source heals each speck to the clean sky, inside the image and clear of its spot (AC2)")
    func automaticSourceHealsDust() throws {
        let scene = TestScene.dustySky.image()
        let geometry = SpotGeometry(frameSize: CGSize(width: scene.width, height: scene.height))
        var spots: [Spot] = []
        for speck in TestScene.dustSpecks {
            let spot = try #require(Self.autoSpot(speck, others: spots, image: scene.ciImage))
            let center = geometry.pixels(spot.center), source = geometry.pixels(spot.source)
            let radius = geometry.radius(spot.size)
            #expect(hypot(source.x - center.x, source.y - center.y) >= 2 * radius - 1e-6)
            #expect(source.x - radius >= 0 && source.y - radius >= 0)
            #expect(source.x + radius <= CGFloat(scene.width) && source.y + radius <= CGFloat(scene.height))
            for other in spots {
                #expect(hypot(source.x - geometry.pixels(other.center).x, source.y - geometry.pixels(other.center).y)
                    >= radius + geometry.radius(other.size) - 1e-6)
            }
            spots.append(spot)
        }
        let healed = SpotReference.apply(spots, to: scene)
        let rendered = Self.renderFloat(SpotRenderer.apply(spots, to: scene.ciImage))
        #expect(Self.maximumDifference(rendered, healed) <= Self.floatTolerance)
        // The truth: the same sky drawn without specks, at the speck's centers and around.
        for speck in TestScene.dustSpecks {
            var worstHealed = 0.0, worstBefore = 0.0
            for dy in -Int(speck.radius)...Int(speck.radius) {
                for dx in -Int(speck.radius)...Int(speck.radius) where dx * dx + dy * dy <= Int(speck.radius * speck.radius) {
                    let x = Int(speck.x) + dx, y = Int(speck.y) + dy
                    let truth = TestScene.clearSky(x: Double(x) + 0.5, y: Double(y) + 0.5, width: scene.width,
                                                   height: scene.height, grain: 0)
                    for channel in 0..<3 {
                        let after = Self.encode(rendered[x, y][channel])
                        let before = Self.encode(scene[x, y][channel])
                        worstHealed = max(worstHealed, abs(after - truth[channel]))
                        worstBefore = max(worstBefore, abs(before - truth[channel]))
                    }
                }
            }
            print("SpotRenderingTests: speck at \(speck.x), \(speck.y) healed to \(worstHealed) of the clean sky (before: \(worstBefore))")
            #expect(worstHealed <= Self.healTolerance, "speck at \(speck.x), \(speck.y): \(worstHealed)")
            #expect(worstBefore > 0.1)
        }
    }

    @Test("Dragging the source changes the result (AC2)")
    func movingTheSourceChangesTheResult() {
        let scene = TestScene.dustySky.image()
        let clean = [GoldenCase.spot(0, x: 80, y: 60, radius: 9, sourceX: 110, sourceY: 60)]
        // Onto another speck: the dust is copied in.
        let dusty = [GoldenCase.spot(0, x: 80, y: 60, radius: 9, sourceX: 170, sourceY: 100)]
        let a = Self.renderFloat(SpotRenderer.apply(clean, to: scene.ciImage))
        let b = Self.renderFloat(SpotRenderer.apply(dusty, to: scene.ciImage))
        #expect(Self.maximumDifference(a, b) > 0.05)
    }

    @Test("Placement is deterministic and Choose Source Automatically gives what placement gives (AC14)")
    func sourceIsDeterministic() throws {
        let scene = TestScene.dustySky.image().ciImage
        let first = try #require(Self.autoSpot(TestScene.dustSpecks[1], image: scene))
        let again = try #require(Self.autoSpot(TestScene.dustSpecks[1], image: scene))
        #expect(first.source == again.source)
        // Another spot overlapping the chosen source: the next choice avoids it.
        let blocker = Spot(center: first.source, size: first.size, source: first.center)
        let avoided = try #require(Self.autoSpot(TestScene.dustSpecks[1], others: [blocker], image: scene))
        #expect(avoided.source != first.source)
    }

    @Test("In the editor's session, Choose Source Automatically answers what placement answered (AC14)")
    func sessionSourceMatchesPlacement() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "spots-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "dusty.png")
        let image = try #require(TestScene.dustySky.image(width: 512, height: 384)
            .cgImage(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        try SyntheticImages.write(image, to: url, type: .png)
        let session = LiveRenderSession(source: url, generator: PreviewGenerator(engine: Self.engine), longEdge: 512,
                                        colorSpace: nil)
        let speck = TestScene.dustSpecks[0]
        let placed = Spot(center: MaskPoint(x: speck.x / 256, y: speck.y / 192), size: 9.0 / 256,
                          source: MaskPoint(x: speck.x / 256, y: speck.y / 192))
        let other = GoldenCase.spot(9, x: 170, y: 100, radius: 11, sourceX: 140, sourceY: 100)
        var values = Adjustments()
        values.spots.spots = [other, placed]
        let atPlacement = try #require(try await session.spotSource(for: placed.id, in: values))
        // Later: the spot moved away and back, its source left elsewhere, the check box off.
        values.spots.spots[1].source = MaskPoint(x: 0.9, y: 0.9)
        values.setEnabled(.spots, false)
        let chosenAgain = try await session.spotSource(for: placed.id, in: values)
        #expect(chosenAgain == atPlacement)
    }

    @Test("No source when the spot is too large for the photo")
    func noSourceForAHugeSpot() {
        let scene = TestScene.dustySky.image().ciImage
        #expect(SpotSourceFinder.source(for: MaskPoint(x: 0.5, y: 0.5), size: 0.3, others: [], crop: Crop(),
                                        image: scene, engine: Self.engine) == nil)
    }

    @Test("The source prefers the visible crop and quieter ground")
    func prefersCropAndQuietArea() throws {
        // Left half flat, right half busy stripes: a spot near the middle on the flat side is sourced from the flat side.
        let width = 256, height = 192
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let busy = x >= 140 && (x / 2 + y / 3).isMultiple(of: 2)
                let value: Float = busy ? 0.9 : 0.35
                for c in 0..<3 { pixels[(y * width + x) * 4 + c] = value }
            }
        }
        let image = LinearImage(width: width, height: height, pixels: pixels).ciImage
        let center = MaskPoint(x: 120.0 / 256, y: 96.0 / 192)
        let size = 8.0 / 256
        let source = try #require(SpotSourceFinder.source(for: center, size: size, others: [], crop: Crop(),
                                                          image: image, engine: Self.engine))
        #expect(source.x * 256 + 8 <= 140)
        // A crop keeping the top half: the source lies inside it when it can.
        let crop = Crop(rect: CropRect(x: 0, y: 0, width: 1, height: 0.5))
        let top = try #require(SpotSourceFinder.source(for: MaskPoint(x: 60.0 / 256, y: 60.0 / 192), size: size,
                                                       others: [], crop: crop, image: image, engine: Self.engine))
        #expect(top.y * 192 + 8 <= 96)
    }

    @Test("A stack with spots turned off renders byte for byte as the same stack without them (AC15, AC5)")
    func offRendersAsNone() throws {
        let scene = TestScene.dustySky.image().ciImage
        var values = Adjustments()
        values.exposure.ev = 0.4
        var none = values
        values.spots.spots = Self.cases[0]
        values.setEnabled(.spots, false)
        let renderer = AdjustmentRenderer()
        let off = try EncodedImage(rendering: renderer.render(values, to: scene, context: RenderContext()), engine: Self.engine)
        let without = try EncodedImage(rendering: renderer.render(none, to: scene, context: RenderContext()), engine: Self.engine)
        #expect(off == without)
        none.spots.spots = Self.cases[0]
        let on = try EncodedImage(rendering: renderer.render(none, to: scene, context: RenderContext()), engine: Self.engine)
        #expect(on != without)
    }

    @Test("Spots render before the crop: a turn and crop afterwards leave the heal on the same content (R5, AC4)")
    func spotsStayOnContentUnderCrop() {
        let scene = TestScene.dustySky.image().ciImage
        let renderer = AdjustmentRenderer()
        var healed = Adjustments()
        healed.spots.spots = Self.cases[1]
        var cropped = healed
        cropped.crop = Crop(rect: CropRect(x: 0.1, y: 0.1, width: 0.8, height: 0.75), quarterTurns: 1, angle: 6)
        let expected = Self.renderFloat(cropped.crop.apply(to: renderer.render(healed, to: scene, context: RenderContext())))
        let actual = Self.renderFloat(renderer.render(cropped, to: scene, context: RenderContext()))
        #expect(expected.width == actual.width && expected.height == actual.height)
        #expect(Self.maximumDifference(expected, actual) <= Self.floatTolerance)
    }

    @Test("A system-decoded raw, a LibRaw-decoded raw and a JPEG heal the same blemish with one stored shape (R9, AC8)")
    func everyDecoderHeals() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "spots-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let dng = folder.appending(path: "dusty.dng")
        try SyntheticDNG.write(to: dng, options: .init(width: 320, height: 240, seed: 3, scene: .testScene(.dustySky)))
        let jpeg = folder.appending(path: "dusty.jpg")
        let image = try #require(TestScene.dustySky.image(width: 320, height: 240)
            .cgImage(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        try SyntheticImages.write(image, to: jpeg, type: .jpeg)

        // The speck at (170, 100) of the default size, in unit coordinates.
        let speck = TestScene.dustSpecks[1]
        var values = Adjustments()
        values.spots.spots = [Spot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                                   center: MaskPoint(x: speck.x / 256, y: speck.y / 192), size: 12.0 / 256,
                                   source: MaskPoint(x: speck.x / 256, y: (speck.y + 40) / 192))]
        let stack = values.editStack
        let generator = PreviewGenerator(engine: Self.engine)
        let renderer = AdjustmentRenderer()

        var outputs: [String: (healed: LinearImage, plain: LinearImage)] = [:]
        // The system decoder (the DNG) and ImageIO (the JPEG), through the preview pipeline.
        for (name, url) in [("system", dng), ("jpeg", jpeg)] {
            let healed = try generator.image(source: url, stack: stack, longEdge: nil)
            let plain = try generator.image(source: url, stack: .identity, longEdge: nil)
            outputs[name] = (Self.renderHalf(healed.cropped(to: plain.extent)), Self.renderHalf(plain))
        }
        // LibRaw's decode with its color step, through the same renderer.
        let libRaw = try LibRawDecoder.decode(dng)
        let decoded = libRaw.step.apply(to: libRaw.linear, settings: .none)
        let context = RenderContext(isRaw: false, balancedByDecoder: true)
        outputs["libRaw"] = (Self.renderHalf(renderer.render(values, to: decoded, context: context)),
                             Self.renderHalf(decoded))

        for (name, output) in outputs {
            #expect(output.healed.width == output.plain.width, "\(name)")
            // The speck's middle gets brighter; far from it nothing moves.
            let w = output.plain.width, h = output.plain.height
            let x = Int(speck.x / 256 * Double(w)), y = Int(speck.y / 192 * Double(h))
            let before = output.plain[x, y], after = output.healed[x, y]
            #expect(after.y > before.y * 1.15, "\(name): \(before) → \(after)")
            // Far from it, the same up to the intermediate the step adds: one half-float rounding.
            let far = output.healed[5, 5] - output.plain[5, 5]
            #expect([far.x, far.y, far.z].allSatisfy { abs($0) <= 0x1p-10 }, "\(name): \(far)")
        }
        // One stored shape for every file: the stack does not depend on the decoder.
        #expect(stack.operations.map(\.kind) == [Spots.kind])
    }
}


/// Spots in the catalog: per file, copied by Duplicate, never a sidecar (R12, R14).
@Suite("Spots: catalog")
struct SpotCatalogTests {
    static func count(_ catalog: Catalog, _ table: String) async throws -> Int {
        try await catalog.database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
    }

    static func stack(_ spots: [Spot]) -> EditStack {
        var values = Adjustments()
        values.spots.spots = spots
        return values.editStack
    }

    @Test("A duplicate starts with the original's spots; edits to either leave the other (R12, AC10)")
    func duplicateCopiesSpots() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let id = try await fixture.addMasters([CatalogFixture.master(1)])[0]
        try await catalog.setEditStack(Self.stack([SpotModelTests.spot(0)]), forVersion: id, historyLabel: "Add Spot")
        let copyID = try await catalog.duplicateVersions(ids: [id])[0].copyVersionID
        let copy = try #require(try await catalog.version(id: copyID))
        #expect(Adjustments(stack: try copy.decodedEditStack()).spots.spots == [SpotModelTests.spot(0)])

        try await catalog.setEditStack(Self.stack([SpotModelTests.spot(0), SpotModelTests.spot(1, x: 0.7)]),
                                       forVersion: copyID, historyLabel: "Add Spot")
        let original = try #require(try await catalog.version(id: id))
        #expect(Adjustments(stack: try original.decodedEditStack()).spots.spots == [SpotModelTests.spot(0)])
        try await catalog.setEditStack(.identity, forVersion: id, historyLabel: "Delete All Spots")
        let copyAfter = try #require(try await catalog.version(id: copyID))
        #expect(Adjustments(stack: try copyAfter.decodedEditStack()).spots.spots.count == 2)
    }

    @Test("Spots are per file: a RAW+JPEG pair's other file keeps its stack, and no sidecar is queued (R12, R14, AC10, AC12)")
    func spotsArePerFileAndNeverSidecars() async throws {
        let fixture = try await CatalogFixture.make()
        let catalog = fixture.catalog
        let ids = try await fixture.addMasters([CatalogFixture.master(1, hash: String(repeating: "a", count: 64), path: "shoot/IMG_0001.CR3"),
                                                CatalogFixture.master(2, hash: String(repeating: "b", count: 64), path: "shoot/IMG_0001.JPG")])
        #expect(try await Self.count(catalog, "imagePair") == 1)
        let queued = try await Self.count(catalog, "sidecarQueue")
        try await catalog.setEditStack(Self.stack([SpotModelTests.spot(0)]), forVersion: ids[0], historyLabel: "Add Spot")
        let partner = try #require(try await catalog.version(id: ids[1]))
        #expect(try partner.decodedEditStack() == .identity)
        #expect(try await Self.count(catalog, "sidecarQueue") == queued)
    }
}

