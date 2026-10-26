import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

@Suite("Adjustments model")
struct AdjustmentsModelTests {
    private func full() -> Adjustments {
        var adjustments = Adjustments()
        adjustments.decode = RawDecode(look: .neutral, decoderVersion: "8.dng")
        adjustments.whiteBalance = .raw(.tungsten)
        adjustments.exposure.ev = 0.5
        adjustments.tone = Tone(contrast: 10, highlights: -20, shadows: 30, whites: 5, blacks: -5)
        adjustments.presence = Presence(clarity: 15, dehaze: 10, vibrance: 20, saturation: -10)
        adjustments.toneCurve[.rgb] = [CurvePoint(x: 0, y: 0.05), CurvePoint(x: 0.5, y: 0.55), CurvePoint(x: 1, y: 1)]
        adjustments.toneCurve[.blue] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 0.9)]
        adjustments.colorGrade.shadows = GradeWheel(hue: 210, amount: 20, luminance: -5)
        adjustments.colorGrade.balance = 10
        adjustments.lookTable = LookTable(identifier: String(repeating: "ab", count: 32), name: "Film", intensity: 70)
        adjustments.noiseReduction = NoiseReduction(luminance: 20, color: 40)
        adjustments.sharpen = Sharpen(amount: 40, radius: 1.2, detail: 30, masking: 10)
        return adjustments
    }

    @Test func defaultsAreTheIdentityStack() {
        #expect(Adjustments().editStack == .identity)
        #expect(Adjustments().editStack.renderHash == EditStack.identity.renderHash)
        #expect(Adjustments(stack: .identity) == .none)
    }

    @Test func roundTripsEveryModule() throws {
        let adjustments = full()
        let stack = adjustments.editStack
        #expect(stack.operations.map(\.kind.rawValue) == [
            "rawDecode", "whiteBalance", "exposure", "tone", "presence", "toneCurve",
            "colorGrade", "lookTable", "noiseReduction", "sharpen",
        ])
        let decoded = Adjustments(stack: try EditStack.decode(from: try stack.jsonData()))
        #expect(decoded == adjustments)
    }

    @Test func leavesOutParametersAtTheirDefaults() throws {
        var adjustments = Adjustments()
        adjustments.tone.contrast = 25
        adjustments.sharpen.amount = 40
        let stack = adjustments.editStack
        #expect(stack.operations.map(\.parameters) == [["contrast": .number(25)], ["amount": .number(40)]])
    }

    @Test func renderHashIsStableForTheSameValues() {
        // New operation ids every time, same pixels: the hash must not move.
        #expect(full().editStack.renderHash == full().editStack.renderHash)
        #expect(full().editStack.renderHash == "6e656c4d1f25efd0fd2183c62b54f930f7f780cf2ced05b0dd6c51af2795bd76")
        // Golden value: changing the persisted form of adjustments invalidates
        // every cached preview of an edited photo.
        var adjustments = Adjustments()
        adjustments.exposure.ev = 1
        #expect(adjustments.editStack.renderHash == EditStack(operations: [
            EditOperation(kind: "exposure", parameters: ["ev": .number(1)]),
        ]).renderHash)
    }

    @Test func resettingEverySectionGivesBackTheIdentity() {
        var adjustments = full()
        for section in Adjustments.Section.allCases {
            #expect(adjustments.isModified(section))
            adjustments = adjustments.resetting(section)
            #expect(!adjustments.isModified(section))
        }
        #expect(adjustments.editStack.renderHash == EditStack.identity.renderHash)
    }

    @Test func keepsUnknownAndDisabledOperations() {
        let future = EditOperation(kind: "brush", parameters: ["size": .number(3)])
        let newer = EditOperation(kind: "exposure", kindVersion: 2, parameters: ["ev": .number(1)])
        let disabled = EditOperation(kind: "tone", isEnabled: false, parameters: ["contrast": .number(50)])
        var adjustments = Adjustments(stack: EditStack(operations: [future, newer, disabled]))
        #expect(adjustments.exposure.ev == 0)
        #expect(adjustments.tone.contrast == 0)
        #expect(adjustments.preserved == [future, newer, disabled])
        adjustments.presence.vibrance = 10
        #expect(adjustments.editStack.operations.map(\.kind.rawValue) == ["presence", "brush", "exposure", "tone"])
    }

    @Test func toleratesMistypedParameters() {
        let stack = EditStack(operations: [
            EditOperation(kind: "exposure", parameters: ["ev": .string("lots")]),
            EditOperation(kind: "toneCurve", parameters: ["rgb": .list([.number(0), .bool(true)])]),
            EditOperation(kind: "rawDecode", parameters: ["look": .string("sepia")]),
        ])
        let adjustments = Adjustments(stack: stack)
        #expect(adjustments.exposure.ev == 0)
        #expect(adjustments.toneCurve.isIdentity)
        #expect(adjustments.decode.look == .standard)
    }

    @Test func curvePointsAreSortedAndClamped() {
        var curve = ToneCurve()
        curve[.red] = [CurvePoint(x: 1.2, y: 0.9), CurvePoint(x: -0.1, y: 0.2), CurvePoint(x: 0.5, y: 0.4)]
        #expect(curve.red == [CurvePoint(x: 0, y: 0.2), CurvePoint(x: 0.5, y: 0.4), CurvePoint(x: 1, y: 0.9)])
        curve[.green] = [CurvePoint(x: 0.5, y: 0.5)]
        #expect(curve.green == ToneCurve.identityPoints)
    }

    @Test func decodeSettingsComeOnlyFromChangedModules() {
        #expect(Adjustments().decodeSettings == .none)
        var adjustments = Adjustments()
        adjustments.whiteBalance = .raw(.daylight)
        adjustments.decode.look = .flat
        adjustments.noiseReduction.color = 30
        let settings = adjustments.decodeSettings
        #expect(settings.temperature == 5500)
        #expect(settings.tint == 0)
        #expect(settings.boostAmount == 0)
        #expect(settings.colorNoiseReduction == 0.3)
        #expect(settings.luminanceNoiseReduction == nil)
    }

    @Test func extendedRangeOnlyWithoutClampingTables() {
        var adjustments = Adjustments()
        adjustments.exposure.ev = 1
        adjustments.presence.saturation = 20
        #expect(adjustments.preservesExtendedRange)
        adjustments.tone.contrast = 10
        #expect(!adjustments.preservesExtendedRange)
    }
}

@Suite("Tone tables")
struct ToneTableTests {
    @Test func splinePassesThroughItsPointsAndStaysMonotone() {
        let points = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.4), CurvePoint(x: 0.6, y: 0.65), CurvePoint(x: 1, y: 1)]
        let spline = MonotoneSpline(points)
        for point in points {
            #expect(abs(spline.value(at: point.x) - point.y) < 1e-9)
        }
        var previous = -Double.infinity
        for i in 0...200 {
            let value = spline.value(at: Double(i) / 200)
            #expect(value >= previous - 1e-12)
            previous = value
        }
    }

    @Test func identityTableIsIdentityAndPassesValuesAboveWhite() {
        let table = ToneTable().rgbTable()
        #expect(table.count == ToneTable.entryCount * 3)
        for i in stride(from: 0, to: ToneTable.entryCount, by: 97) {
            let x = Float(ToneTable.domainMaximum * Double(i) / Double(ToneTable.entryCount - 1))
            #expect(abs(table[i * 3] - x) < 1e-5)
        }
    }

    @Test func contrastKeepsEndpointsAndPivot() {
        for amount in [-1.0, -0.4, 0.5, 1] {
            #expect(abs(ToneTable.contrastCurve(0, amount: amount)) < 1e-12)
            #expect(abs(ToneTable.contrastCurve(1, amount: amount) - 1) < 1e-12)
            #expect(abs(ToneTable.contrastCurve(ToneTable.pivot, amount: amount) - ToneTable.pivot) < 1e-12)
        }
        // More contrast darkens below the pivot and brightens above it.
        #expect(ToneTable.contrastCurve(0.25, amount: 0.5) < 0.25)
        #expect(ToneTable.contrastCurve(0.75, amount: 0.5) > 0.75)
    }

    @Test func everyControlGivesAMonotoneTable() {
        let curves: [ToneTable] = [
            ToneTable(contrast: 1), ToneTable(contrast: -1), ToneTable(highlights: 1),
            ToneTable(whites: 1, blacks: -1), ToneTable(whites: -1, blacks: 1),
        ]
        for curve in curves {
            let table = curve.rgbTable()
            for i in 1..<ToneTable.entryCount {
                #expect(table[i * 3] >= table[(i - 1) * 3])
            }
            #expect(table[0] >= 0)
        }
        #expect(ToneTable(blacks: 1).tone(0) > 0.1)
        #expect(ToneTable(blacks: -1).tone(0.05) == 0)
        #expect(ToneTable(whites: -1).tone(1) < 0.9)
    }
}

@Suite("Look-up tables")
struct CubeLUTTests {
    static func identityCube(size: Int, title: String = "Identity") -> String {
        var lines = ["# generated", "TITLE \"\(title)\"", "LUT_3D_SIZE \(size)"]
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let s = Double(size - 1)
                    lines.append("\(Double(r) / s) \(Double(g) / s) \(Double(b) / s)")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Swaps red and blue: easy to detect after rendering.
    static func swapCube(size: Int = 2) -> String {
        var lines = ["LUT_3D_SIZE \(size)"]
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let s = Double(size - 1)
                    lines.append("\(Double(b) / s) \(Double(g) / s) \(Double(r) / s)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    @Test func parsesThreeDimensionalTables() throws {
        let lut = try CubeLUT(parsing: Self.identityCube(size: 3))
        #expect(lut.title == "Identity")
        #expect(lut.size == 3)
        #expect(lut.isThreeDimensional)
        #expect(lut.entries.count == 27)
        let cube = lut.colorCube()
        #expect(cube.dimension == 3)
        #expect(cube.data.count == 27 * 4 * 4)
    }

    @Test func resamplesOneDimensionalTablesAndOtherDomains() throws {
        let oneD = try CubeLUT(parsing: "LUT_1D_SIZE 2\n0 0 0\n1 1 1\n")
        #expect(!oneD.isThreeDimensional)
        #expect(oneD.colorCube().dimension == 33)
        #expect(oneD.sample1D(SIMD3(0.25, 0.5, 0.75)) == SIMD3(0.25, 0.5, 0.75))

        let wide = try CubeLUT(parsing: "LUT_3D_SIZE 2\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n"
            + "0 0 0\n2 0 0\n0 2 0\n2 2 0\n0 0 2\n2 0 2\n0 2 2\n2 2 2\n")
        #expect(wide.sample3D(SIMD3(0.5, 0.5, 0.5)) == SIMD3(1, 1, 1))
        #expect(wide.colorCube().dimension == 2)
    }

    @Test func rejectsMalformedFiles() {
        #expect(throws: CubeLUT.Failure.missingSize) { try CubeLUT(parsing: "0 0 0\n") }
        #expect(throws: CubeLUT.Failure.unsupportedSize(200)) { try CubeLUT(parsing: "LUT_3D_SIZE 200\n") }
        #expect(throws: CubeLUT.Failure.wrongEntryCount(expected: 8, found: 1)) {
            try CubeLUT(parsing: "LUT_3D_SIZE 2\n0 0 0\n")
        }
        #expect(throws: CubeLUT.Failure.malformedLine(2)) { try CubeLUT(parsing: "LUT_3D_SIZE 2\n0 0\n") }
        #expect(throws: CubeLUT.Failure.invalidDomain) {
            try CubeLUT(parsing: "LUT_1D_SIZE 2\nDOMAIN_MIN 1 1 1\nDOMAIN_MAX 0 0 0\n0 0 0\n1 1 1\n")
        }
    }

    @Test func browsingListsCubeFilesAndPreviewsThem() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "LUTs")
            try FileManager.default.createDirectory(at: folder.appending(path: "Film"), withIntermediateDirectories: true)
            try Self.swapCube().write(to: folder.appending(path: "b swap.cube"), atomically: true, encoding: .utf8)
            try Self.identityCube(size: 2).write(to: folder.appending(path: "Film/a.CUBE"), atomically: true, encoding: .utf8)
            try "x".write(to: folder.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
            let files = LookTableBrowsing.files(in: folder)
            #expect(files.map(\.lastPathComponent) == ["a.CUBE", "b swap.cube"])

            let base = try #require(SyntheticImages.makeImage(width: 400, height: 200, seed: 1))
            let cube = try CubeLUT(contentsOf: files[1]).colorCube()
            let preview = try #require(LookTableBrowsing.preview(of: base, with: cube, engine: RenderEngine()))
            #expect(max(preview.width, preview.height) == 192)
        }
    }

    @Test func storeCopiesTablesByContent() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let source = root.appending(path: "Warm Film.cube")
            try Self.swapCube().write(to: source, atomically: true, encoding: .utf8)
            let store = LookTableStore(directory: root.appending(path: "Library/LUTs"))
            let table = try store.importFile(at: source)
            #expect(table.name == "Warm Film")
            let identifier = try #require(table.identifier)
            #expect(store.contains(identifier))
            try FileManager.default.removeItem(at: source)

            // A fresh store reads the copy.
            let reopened = LookTableStore(directory: root.appending(path: "Library/LUTs"))
            #expect(reopened.cube(for: identifier)?.dimension == 2)
            #expect(reopened.cube(for: "../../etc/passwd") == nil)
            #expect(reopened.cube(for: String(repeating: "0", count: 64)) == nil)

            let bad = root.appending(path: "bad.cube")
            try "nonsense".write(to: bad, atomically: true, encoding: .utf8)
            #expect(throws: CubeLUT.Failure.self) { try store.importFile(at: bad) }
        }
    }
}

@Suite("Adjustment rendering")
struct AdjustmentRendererTests {
    let engine = RenderEngine()

    private func solid(_ r: Double, _ g: Double, _ b: Double, size: Int = 32) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b, colorSpace: RenderEngine.workingColorSpace)!)
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    private func average(_ image: CIImage) throws -> SIMD3<Double> {
        try #require(PixelSample(image, engine: engine)).average
    }

    private func render(_ adjustments: Adjustments, _ image: CIImage, raw: Bool = false) -> CIImage {
        AdjustmentRenderer().render(adjustments, to: image, context: RenderContext(scale: 1, isRaw: raw))
    }

    @Test func defaultsReturnTheInput() {
        let image = solid(0.2, 0.3, 0.4)
        #expect(render(.none, image) === image)
    }

    @Test func exposureDoublesLinearValuesPerStop() throws {
        var adjustments = Adjustments()
        adjustments.exposure.ev = 1
        let out = try average(render(adjustments, solid(0.1, 0.2, 0.3)))
        #expect(abs(out.x - 0.2) < 0.003)
        #expect(abs(out.y - 0.4) < 0.003)
        #expect(abs(out.z - 0.6) < 0.003)
    }

    @Test func relativeWhiteBalanceWarmsAndTints() throws {
        var warm = Adjustments()
        warm.whiteBalance.relativeTemperature = 50
        let warmed = try average(render(warm, solid(0.2, 0.2, 0.2)))
        #expect(warmed.x / warmed.z > 1.1)
        var magenta = Adjustments()
        magenta.whiteBalance.relativeTint = 50
        let tinted = try average(render(magenta, solid(0.2, 0.2, 0.2)))
        #expect(tinted.y < tinted.x && tinted.y < tinted.z)
        // RAW files get white balance from the decoder, not here.
        #expect(try average(render(warm, solid(0.2, 0.2, 0.2), raw: true)).x - 0.2 < 0.002)
    }

    @Test func toneControlsMoveTonesTheRightWay() throws {
        let dark = solid(0.05, 0.05, 0.05)
        let bright = solid(0.7, 0.7, 0.7)
        func tone(_ change: (inout Tone) -> Void, _ image: CIImage) throws -> Double {
            var adjustments = Adjustments()
            change(&adjustments.tone)
            return try average(render(adjustments, image)).y
        }
        #expect(try tone({ $0.contrast = 50 }, dark) < 0.05)
        #expect(try tone({ $0.contrast = 50 }, bright) > 0.7)
        #expect(try tone({ $0.shadows = 50 }, dark) > 0.06)
        #expect(try tone({ $0.highlights = -50 }, bright) < 0.69)
        #expect(try tone({ $0.highlights = 50 }, bright) > 0.71)
        #expect(try tone({ $0.blacks = -50 }, dark) < 0.045)
        #expect(try tone({ $0.whites = 50 }, bright) > 0.71)
    }

    @Test func curvesAndColorControls() throws {
        var curve = Adjustments()
        curve.toneCurve[.red] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 0.5)]
        let red = try average(render(curve, solid(0.5, 0.5, 0.5)))
        #expect(red.x < 0.3)
        #expect(abs(red.y - 0.5) < 0.005)

        var grey = Adjustments()
        grey.presence.saturation = -100
        let desaturated = try average(render(grey, solid(0.6, 0.2, 0.1)))
        #expect(abs(desaturated.x - desaturated.z) < 0.01)

        var graded = Adjustments()
        graded.colorGrade.highlights = GradeWheel(hue: 240, amount: 100)
        let blue = try average(render(graded, solid(0.6, 0.6, 0.6)))
        #expect(blue.z > blue.x + 0.05)
    }

    @Test func dehazeRemovesAVeil() throws {
        // A gradient over a raised floor: dehaze should pull the floor down.
        let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 64, y: 0),
            "inputColor0": CIColor(red: 0.2, green: 0.2, blue: 0.2, colorSpace: RenderEngine.workingColorSpace)!,
            "inputColor1": CIColor(red: 0.8, green: 0.8, blue: 0.8, colorSpace: RenderEngine.workingColorSpace)!,
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 64, height: 8))
        var adjustments = Adjustments()
        adjustments.presence.dehaze = 100
        let before = try #require(PixelSample(gradient, engine: engine)).rgba[0]
        let after = try #require(PixelSample(render(adjustments, gradient), engine: engine)).rgba[0]
        #expect(after < before - 0.05)
    }

    @Test func sharpeningAddsEdgeContrast() throws {
        let half = solid(0.6, 0.6, 0.6).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 64))
            .composited(over: solid(0.2, 0.2, 0.2, size: 64))
        var adjustments = Adjustments()
        adjustments.sharpen = Sharpen(amount: 150, radius: 2, detail: 100)
        let sharpened = try #require(PixelSample(render(adjustments, half), engine: engine))
        let original = try #require(PixelSample(half, engine: engine))
        // The pixel just inside the bright half gets brighter.
        let index = (32 * 64 + 31) * 4
        #expect(sharpened.rgba[index] > original.rgba[index] + 0.01)
        // At thumbnail scale sharpening is skipped.
        let small = AdjustmentRenderer().render(adjustments, to: half, context: RenderContext(scale: 0.1))
        #expect(small.extent == half.extent)
    }

    @Test func lookTablesMixByIntensity() throws {
        let lut = try CubeLUT(parsing: CubeLUTTests.swapCube(size: 17))
        let image = solid(0.6, 0.2, 0.05)
        let full = try average(AdjustmentRenderer.lookTable(image, lut.colorCube(), intensity: 1))
        #expect(full.z > full.x)
        let none = try average(AdjustmentRenderer.lookTable(image, lut.colorCube(), intensity: 0))
        #expect(abs(none.x - 0.6) < 0.01)
    }

    @Test func rawDecodeSettingsReachTheDecoder() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let dng = root.appending(path: "a.dng")
            try SyntheticDNG.write(to: dng, options: .init(width: 400, height: 300, seed: 9))
            let generator = PreviewGenerator(engine: engine)
            func average(_ adjustments: Adjustments) throws -> SIMD3<Double> {
                let image = try generator.image(source: dng, stack: adjustments.editStack, longEdge: 128)
                return try #require(PixelSample(image, engine: engine)).average
            }
            let asShot = try average(.none)
            var warm = Adjustments()
            warm.whiteBalance = WhiteBalance(preset: .custom, temperature: 9000, tint: 0)
            let warmed = try average(warm)
            #expect(warmed.x / warmed.z > asShot.x / asShot.z * 1.05)
            var flat = Adjustments()
            flat.decode.look = .flat
            #expect(try average(flat).y < asShot.y)
        }
    }

    @Test func identityStackRendersAsBefore() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let jpeg = root.appending(path: "a.jpg")
            try SyntheticImages.writeJPEG(to: jpeg, width: 800, height: 600, seed: 3)
            let dng = root.appending(path: "b.dng")
            try SyntheticDNG.write(to: dng, options: .init(width: 400, height: 300, seed: 4))
            let adjusting = PreviewGenerator(engine: engine)
            let passing = PreviewGenerator(engine: engine, renderer: PassThroughRenderer())
            for source in [jpeg, dng] {
                #expect(try adjusting.jpegData(source: source, stack: .identity, tier: .thumbnail)
                    == passing.jpegData(source: source, stack: .identity, tier: .thumbnail))
            }
        }
    }

    @Test func noHDRRenditionWhileClampingTablesAreActive() {
        var adjustments = Adjustments()
        adjustments.toneCurve[.rgb] = [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 1, y: 1)]
        #expect(!AdjustmentRenderer().preservesExtendedRange(adjustments.editStack))
        #expect(AdjustmentRenderer().preservesExtendedRange(EditStack.identity))
    }
}

@Suite("Auto adjustments")
struct AutoAdjustTests {
    @Test func exposureAimsForMidGrey() {
        #expect(abs(AutoAdjuster.exposure(for: Array(repeating: 0.045, count: 100)) - 2) < 0.06)
        #expect(abs(AutoAdjuster.exposure(for: Array(repeating: 0.18, count: 100))) < 0.06)
        // A few bright pixels hold the exposure back, by a stop at most.
        let mixed = Array(repeating: 0.045, count: 990) + Array(repeating: 0.9, count: 10)
        let ev = AutoAdjuster.exposure(for: mixed)
        #expect(ev < 1.95)
        #expect(ev >= 0.9)
        #expect(AutoAdjuster.exposure(for: []) == 0)
    }

    @Test func autoExposureMeasuresTheRenderedImage() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "dark.jpg")
            let image = try #require(SyntheticImages.makeImage(width: 300, height: 200, seed: 1))
            // Darken by drawing at low opacity over black.
            let context = try #require(CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            context.setAlpha(0.25)
            context.draw(image, in: CGRect(x: 0, y: 0, width: 300, height: 200))
            try SyntheticImages.write(try #require(context.makeImage()), to: url, type: .jpeg)
            let adjuster = AutoAdjuster(generator: PreviewGenerator())
            #expect(try adjuster.exposure(source: url, adjustments: .none) > 1)
        }
    }

    @Test func autoWhiteBalanceNeutralizesACast() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "blue.jpg")
            let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 0.45, green: 0.5, blue: 0.62, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            try SyntheticImages.write(try #require(context.makeImage()), to: url, type: .jpeg)
            let generator = PreviewGenerator()
            let balance = try AutoAdjuster(generator: generator).whiteBalance(source: url, adjustments: .none)
            #expect(balance.preset == .auto)
            #expect(balance.relativeTemperature > 10)
            var adjustments = Adjustments()
            adjustments.whiteBalance = balance
            let rendered = try generator.image(source: url, stack: adjustments.editStack, longEdge: 64)
            let average = try #require(PixelSample(rendered, engine: generator.engine)).average
            #expect(abs(average.x / average.z - 1) < 0.08)
        }
    }

    @Test func autoWhiteBalanceForRawGivesKelvin() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let dng = root.appending(path: "a.dng")
            try SyntheticDNG.write(to: dng, options: .init(width: 400, height: 300, seed: 11))
            let balance = try AutoAdjuster(generator: PreviewGenerator()).whiteBalance(source: dng, adjustments: .none)
            #expect(balance.preset == .auto)
            let temperature = try #require(balance.temperature)
            #expect(WhiteBalance.temperatureRange.contains(temperature))
            #expect(balance.tint != nil)
            let defaults = try #require(RawDefaults(source: dng))
            #expect(defaults.decoderVersions.contains(defaults.defaultDecoderVersion))
        }
    }

    @Test func histogramCountsEveryPixel() throws {
        let image = try #require(SyntheticImages.makeImage(width: 100, height: 50, seed: 2))
        let histogram = try #require(Histogram(image: image))
        #expect(histogram.red.reduce(0, +) == 5000)
        #expect(histogram.luminance.reduce(0, +) == 5000)
        let reduced = try #require(Histogram(image: image, sampleSize: 20))
        #expect(reduced.green.reduce(0, +) == 200)
    }
}

extension PixelSample {
    var average: SIMD3<Double> {
        var sum = SIMD3<Double>(0, 0, 0)
        let count = rgba.count / 4
        for i in stride(from: 0, to: rgba.count, by: 4) {
            sum += SIMD3(Double(rgba[i]), Double(rgba[i + 1]), Double(rgba[i + 2]))
        }
        return sum / Double(max(count, 1))
    }
}

@Suite("Adjustment presets and pasting")
struct AdjustmentPresetTests {
    @Test func presetsAreSavedReplacedByNameAndDeleted() async throws {
        let fixture = try await CatalogFixture.make()
        var warm = Adjustments()
        warm.whiteBalance.relativeTemperature = 30
        warm.preserved = [EditOperation(kind: "brush")]
        let saved = try await fixture.catalog.saveAdjustmentPreset(AdjustmentPreset(name: "Warm", adjustments: warm))
        #expect(saved.id != nil)
        #expect(saved.adjustments.preserved.isEmpty)

        var warmer = warm
        warmer.whiteBalance.relativeTemperature = 50
        _ = try await fixture.catalog.saveAdjustmentPreset(AdjustmentPreset(name: "Warm", adjustments: warmer))
        _ = try await fixture.catalog.saveAdjustmentPreset(AdjustmentPreset(name: "a cool one", adjustments: .none))
        let presets = try await fixture.catalog.adjustmentPresets()
        #expect(presets.map(\.name) == ["a cool one", "Warm"])
        #expect(presets[1].adjustments.whiteBalance.relativeTemperature == 50)
        #expect(presets[1].id == saved.id)

        try await fixture.catalog.deleteAdjustmentPreset(id: try #require(saved.id))
        #expect(try await fixture.catalog.adjustmentPresets().map(\.name) == ["a cool one"])
    }

    @Test func editStacksAreReadAndWrittenInBatches() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        var bright = Adjustments()
        bright.exposure.ev = 1
        try await fixture.catalog.setEditStacks([ids[0]: bright.editStack, ids[1]: .identity])
        let stacks = try await fixture.catalog.editStacks(forVersions: ids)
        #expect(Adjustments(stack: try #require(stacks[ids[0]])) == bright)
        #expect(stacks[ids[1]] == .identity)
        let version = try #require(try await fixture.catalog.version(id: ids[0]))
        #expect(version.editStackHash == bright.editStack.renderHash)
    }

    @Test func pastingKeepsTheTargetsUnknownOperations() {
        var copied = Adjustments()
        copied.tone.contrast = 20
        var target = Adjustments()
        target.exposure.ev = 2
        target.preserved = [EditOperation(kind: "brush")]
        let result = copied.pasted(onto: target)
        #expect(result.tone.contrast == 20)
        #expect(result.exposure.ev == 0)
        #expect(result.preserved.map(\.kind.rawValue) == ["brush"])
    }
}
