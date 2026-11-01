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

    static func bytes(_ frame: LiveRenderSession.Frame) -> [UInt8] {
        let data = frame.image.cgImage.dataProvider?.data as Data? ?? Data()
        return [UInt8](data)
    }

    /// Each cached stage is one more half-float rounding (2⁻¹¹ relative, under
    /// a twentieth of an 8-bit step at any level of the 8-bit output), so a
    /// cached frame may differ from a whole one by at most one step.
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
                #expect(worst <= 1, "\(name): differs by \(worst) steps")
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

    @Test("Drafts step down over the budget and back up only with room to spare")
    func draftHysteresis() {
        let next = LiveRenderSession.nextDraftLevel
        #expect(next(0, 0.09) == 0)
        #expect(next(0, 0.12) == 1)
        #expect(next(1, 0.12) == 2)
        #expect(next(2, 0.30) == 2)
        // A half-size frame of 20 ms predicts 80 ms at full size: over 60 % of the budget, stay.
        #expect(next(1, 0.020) == 1)
        #expect(next(1, 0.014) == 0)
        #expect(next(2, 0.010) == 1)
    }
}

