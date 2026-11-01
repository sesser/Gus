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
                let a = Self.bytes(try await cached.render(adjustments, interactive: true))
                let b = Self.bytes(try await whole.render(adjustments, interactive: true))
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
}
