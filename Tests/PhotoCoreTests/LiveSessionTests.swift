import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The live session's stage cache against rendering every frame whole.
@Suite("Live render session")
struct LiveSessionTests {
    static func masked() -> Adjustments {
        var adjustments = Adjustments()
        adjustments.exposure.ev = 0.2
        adjustments.presence.vibrance = 20
        adjustments.sharpen.amount = 40
        adjustments.local.masks = [
            GoldenCase.mask([.linear(LinearGradient(start: MaskPoint(x: 0.5, y: 0), end: MaskPoint(x: 0.5, y: 0.6)))]) {
                $0.exposure = -0.6
                $0.dehaze = 30
            },
            GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: 0.4, y: 0.6), radiusX: 0.25, radiusY: 0.2))]) {
                $0.shadows = 40
                $0.clarity = 30
            },
            GoldenCase.mask([.brush(Brush(strokes: [BrushStroke(points: [MaskPoint(x: 0.2, y: 0.7),
                                                                           MaskPoint(x: 0.8, y: 0.3)], size: 0.05)]))]) {
                $0.contrast = 25
                $0.sharpen = 50
            },
        ]
        for index in adjustments.local.masks.indices { adjustments.local.masks[index].id = UUID() }
        return adjustments
    }

    /// How much the stages after the cached ones can enlarge a relative
    /// difference: local clarity 1 + 2i (i = 0.6 × amount, its unsharp
    /// intensity), global and local sharpening 1 + 2 × amount each, and each
    /// local contrast curve's largest relative slope x·y′/y (read from its
    /// table; relative error is the same in linear light and in the sRGB
    /// encoding, a power law).
    static func gain(after values: Adjustments) -> Double {
        var gain = 1 + 2 * values.sharpen.amount / 100
        for mask in values.local.renderedMasks {
            let local = mask.adjustments
            gain *= (1 + 2 * 0.6 * local.clarity / 100) * (1 + 2 * local.sharpen / 100)
            guard local.contrast != 0 else { continue }
            let table = ToneTable(contrast: local.contrast / 100).rgbTable()
            let step = ToneTable.domainMaximum / Double(table.count / 3 - 1)
            var curve = 1.0
            for i in 1..<(table.count / 3 - 1) {
                let x = Double(i) * step, y = Double(table[i * 3])
                let slope = Double(table[(i + 1) * 3] - table[(i - 1) * 3]) / (2 * step)
                if y > 0.01 { curve = max(curve, x * slope / y) }
            }
            gain *= curve
        }
        return gain
    }

    /// 8-bit steps a cached frame may differ from a whole one: three cached
    /// stages each rounded once more (2⁻¹¹ relative), enlarged by `gain`, is
    /// about a 2.4th of that relative in the sRGB encoding, times 255, rounded
    /// up, plus one step where 8-bit quantization tips over.
    static func allowedSteps(_ values: Adjustments) -> Int {
        Int((3 * 0x1p-11 * gain(after: values) / 2.4 * 255).rounded(.up)) + 1
    }

    static func bytes(_ frame: LiveRenderSession.Frame) -> [UInt8] {
        let data = frame.image.cgImage.dataProvider?.data as Data? ?? Data()
        return [UInt8](data)
    }

    /// A cached frame may differ from a whole one by `allowedSteps`.
    @Test("Cached stages give the frames a whole render gives")
    func cachedMatchesWhole() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "photo.jpg")
            try SyntheticImages.writeJPEG(to: url, width: 1200, height: 900, seed: 21)
            let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "live-test"))
            let cached = LiveRenderSession(source: url, generator: generator, longEdge: 800, colorSpace: nil)
            let whole = LiveRenderSession(source: url, generator: generator, longEdge: 800, colorSpace: nil,
                                          cachesStages: false)
            var values = Self.masked()
            var sequence: [(String, Adjustments)] = [("first", values)]
            for step in 1...2 {
                values.local.masks[2].adjustments.contrast = 25 + Double(step) * 10
                sequence.append(("last mask, step \(step)", values))
            }
            values.local.masks[0].adjustments.exposure = -0.3
            sequence.append(("first mask", values))
            values.local.masks[2].adjustments.contrast = 5
            sequence.append(("last mask again", values))
            values.exposure.ev = 0.5
            sequence.append(("global exposure", values))
            for (name, adjustments) in sequence {
                // Full-quality frames: interactive ones may become drafts, depending on timing.
                let a = Self.bytes(try await cached.render(adjustments))
                let b = Self.bytes(try await whole.render(adjustments))
                #expect(a.count == b.count && !a.isEmpty, "\(name)")
                let worst = zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
                let allowed = Self.allowedSteps(adjustments)
                #expect(worst <= allowed, "\(name): differs by \(worst) steps (allowed \(allowed))")
            }
        }
    }

    @Test("A cancelled render makes no frame")
    func cancellation() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "photo.jpg")
            try SyntheticImages.writeJPEG(to: url, width: 400, height: 300, seed: 3)
            let session = LiveRenderSession(source: url, generator: PreviewGenerator(), longEdge: 300, colorSpace: nil)
            let token = RenderCancellation()
            token.cancel()
            await #expect(throws: CancellationError.self) {
                _ = try await session.render(Self.masked(), cancellation: token)
            }
        }
    }

    // MARK: Drafts

    static let draftControls: [(name: String, set: @Sendable (inout LocalValues) -> Void)] = [
        ("exposure", { $0.exposure = 1.5 }), ("contrast", { $0.contrast = 60 }),
        ("highlights", { $0.highlights = -60 }), ("shadows", { $0.shadows = 60 }),
        ("whites", { $0.whites = 60 }), ("blacks", { $0.blacks = -60 }),
        ("temperature", { $0.temperature = 60 }), ("tint", { $0.tint = 60 }),
        ("vibrance", { $0.vibrance = 60 }), ("saturation", { $0.saturation = -60 }),
        ("clarity", { $0.clarity = 60 }), ("dehaze", { $0.dehaze = 60 }),
        ("sharpen", { $0.sharpen = 80 }),
    ]

    /// A draft is the same render over the master reduced 2× with
    /// `RenderContext.scale` ½, against the full render reduced 2× by the same
    /// Lanczos filter, for each local control in a feathered radial mask.
    @Test("A draft matches the full render reduced 2×", arguments: draftControls.map(\.name))
    func draftMatchesReducedFull(control: String) throws {
        let scene = TestScene.hazyLandscape.image(width: 512, height: 384).ciImage
        var adjustments = Adjustments()
        adjustments.sharpen.amount = 40
        adjustments.local.masks = [GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: 0.45, y: 0.55),
                                                                           radiusX: 0.3, radiusY: 0.22, feather: 60))],
                                                   Self.draftControls.first { $0.name == control }!.set)]
        let renderer = AdjustmentRenderer()
        let full = renderer.render(adjustments, to: scene, context: RenderContext()).scaledToFit(longEdge: 256)
        let draft = renderer.render(adjustments, to: scene.scaledToFit(longEdge: 256), context: RenderContext(scale: 0.5))
        let a = try EncodedImage(rendering: full, engine: Goldens.engine)
        let b = try EncodedImage(rendering: draft, engine: Goldens.engine)
        let difference = ImageDifference(expected: a, actual: b)
        print("draft \(control): \(difference)")
        // RMS under one 8-bit step (PSNR ≥ 20 log₁₀ 255 = 48.1 dB) and mean ΔE under a
        // tenth of a just-noticeable OkLab difference (about 0.02). Single pixels are not
        // bounded: resampling before or after the render differs at edges and above white
        // (Lanczos lobes on values over 1; local exposure +1.5 reached ΔE 0.033 at a few).
        #expect(difference.psnr >= 48.1 && difference.meanDeltaE <= 0.002, "\(control): \(difference)")
    }

    @Test("Drafts step down over the drop threshold and back up below the raise threshold")
    func draftHysteresis() {
        let next = LiveRenderSession.nextDraftLevel
        let drop = LiveRenderSession.draftDropThreshold, raise = LiveRenderSession.draftRaiseThreshold
        #expect(raise < drop)
        #expect(next(0, drop * 0.9) == 0)
        #expect(next(0, drop * 1.1) == 1)
        #expect(next(1, drop * 1.1) == 2)
        #expect(next(2, drop * 3) == 2)
        // A smaller frame predicting a full one just over the raise threshold stays small.
        #expect(next(1, raise / 4 * 1.1) == 1)
        #expect(next(1, raise / 4 * 0.9) == 0)
        #expect(next(2, raise / 4 * 0.9) == 1)
    }

    static func floats(_ image: CGImage) -> [Float] {
        let data = image.dataProvider?.data as Data? ?? Data()
        let rowFloats = image.bytesPerRow / 4
        return data.withUnsafeBytes { raw in
            let all = raw.bindMemory(to: Float.self)
            return (0..<image.height).flatMap { y in (0..<image.width * 4).map { all[y * rowFloats + $0] } }
        }
    }

    @Test("Prefilling the cache makes a drag's first frame a cached one")
    func prefill() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "photo.jpg")
            try SyntheticImages.writeJPEG(to: url, width: 1200, height: 900, seed: 21)
            let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "prefill-test"))
            let session = LiveRenderSession(source: url, generator: generator, longEdge: 800, colorSpace: nil)
            let whole = LiveRenderSession(source: url, generator: generator, longEdge: 800, colorSpace: nil,
                                          cachesStages: false)
            var values = Self.masked()
            #expect(try await session.render(values).filledCache)
            try await session.prepare(values, editing: values.local.masks[2].id, allowsDrafts: false)
            values.local.masks[2].adjustments.contrast = 45
            let first = try await session.render(values, interactive: true, allowsDrafts: false)
            #expect(!first.filledCache, "the drag's first frame filled the cache")
            let a = Self.bytes(first), b = Self.bytes(try await whole.render(values))
            #expect((zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 99) <= Self.allowedSteps(values))
        }
    }

    /// The synthetic Bayer DNG decoded with extended range (negative highlights
    /// ask for it) and lifted 1.5 EV: much of it lies above white (up to 2.9)
    /// entering the mask step. The cached stages are half-float images in the
    /// extended working space, so values above 1.0 must survive them, and
    /// cached and whole renders must agree. Tolerance: each of the three cached
    /// stages may round once more (2⁻¹¹ relative), which the stages after them
    /// enlarge by at most `gain(after:)`. Plus 2⁻²⁴ near zero.
    ///
    /// Known issue (docs/PHASE6_PLAN.md, finding 4): with masks that use
    /// whole-frame estimates (dehaze, local tone) they do not agree. On
    /// above-white input dehaze's haze estimate moved by up to 0.09, and local
    /// tone's by 0.067, when their input moved by 0.002, so a different split of
    /// the render into passes changes them (0.107 on the macOS 26 runner).
    ///
    /// Known issue on macOS 26 only (finding 6): there Core Image's Gaussian blur
    /// over above-white values depends on how the render is split into passes
    /// (clarity and sharpening, both unsharp masks, moved by 0.11 in linear light;
    /// macOS 15 and 27: 0.0006), so even the strict case differs.
    @Test("Values above white survive the cached stages", arguments: [false, true])
    func aboveWhite(withEstimates: Bool) async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "bright.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 640, height: 480, seed: 7))
            let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "hdr-test"))
            let cached = LiveRenderSession(source: url, generator: generator, longEdge: 640, colorSpace: nil)
            let whole = LiveRenderSession(source: url, generator: generator, longEdge: 640, colorSpace: nil,
                                          cachesStages: false)
            var values = Self.masked()
            values.exposure.ev = 1.5
            values.tone.highlights = -20
            if !withEstimates {
                values.local.masks[0].adjustments.dehaze = 0
                values.local.masks[1].adjustments.shadows = 0
            }
            #expect(values.decodeSettings.extendedDynamicRange == 1)
            var entering = values
            entering.local = LocalAdjustments()
            let input = Self.floats(try await whole.linearFrame(entering))
            #expect((input.max() ?? 0) > 1.5, "the decode does not reach above white: \(input.max() ?? 0)")

            _ = try await cached.render(values)
            values.local.masks[2].adjustments.contrast = 40
            _ = try await cached.render(values, interactive: true, allowsDrafts: false)
            values.local.masks[2].adjustments.contrast = 50
            let a = Self.floats(try await cached.linearFrame(values))
            let b = Self.floats(try await whole.linearFrame(values))
            let relative = 3 * 0x1p-11 * Self.gain(after: values)
            #expect(a.count == b.count)
            #expect((a.max() ?? 0) > 1 && (b.max() ?? 0) > 1, "above white: cached \(a.max() ?? 0), whole \(b.max() ?? 0)")
            var worst: Float = 0
            for i in a.indices where i % 4 != 3 {
                worst = max(worst, abs(a[i] - b[i]) - (max(abs(a[i]), abs(b[i])) * Float(relative) + 0x1p-24))
            }
            if withEstimates {
                withKnownIssue("Dehaze's and local tone's estimates are unstable on above-white input") {
                    #expect(worst <= 0, "cached and whole differ beyond the tolerance by \(worst)")
                }
            } else if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 {
                withKnownIssue("macOS 26: Gaussian blur above white depends on how the render is split") {
                    #expect(worst <= 0, "cached and whole differ beyond the tolerance by \(worst)")
                }
            } else {
                #expect(worst <= 0, "cached and whole differ beyond the tolerance by \(worst)")
            }
        }
    }
}
