import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The sharpening map's live frames and its full-resolution refinement
/// (docs/features/sharpen-mask-preview/prd.md R2, R5, R6, R7).
@Suite("Sharpening map frames")
struct SharpeningMapSessionTests {
    static func values(masking: Double = 50) -> Adjustments {
        var values = LiveSessionTests.masked()
        values.sharpen = Sharpen(amount: 40, radius: 1.2, detail: 25, masking: masking)
        return values
    }

    /// The gain from a relative error in the encoded image entering the
    /// sharpening step to the mask: its range (high − low) doubles it, and
    /// the ramp multiplies it by 1 / threshold (`edgeMask`).
    static func maskGain(_ masking: Double) -> Double {
        2 / max(AdjustmentRenderer.maskingThreshold(masking / 100), 0.005)
    }

    /// 8-bit steps two renders of the map may differ by when one has
    /// `roundings` more half-float roundings (2⁻¹¹ relative each) of the
    /// linear image, enlarged by `upstream` before the sharpening step: a
    /// 2.4th of that relative in the sRGB encoding (values at most 1),
    /// times `maskGain`, times 255, rounded up, plus one step where 8-bit
    /// quantization tips over. The display encoding maps mask v to 8-bit v.
    static func allowedSteps(roundings: Double, upstream: Double, masking: Double) -> Int {
        Int((roundings * 0x1p-11 * upstream / 2.4 * maskGain(masking) * 255).rounded(.up)) + 1
    }

    /// The largest difference between two BGRA8 images of one size, and the mean.
    static func difference(_ a: CGImage, _ b: CGImage) throws -> (worst: Int, mean: Double) {
        #expect(a.width == b.width && a.height == b.height)
        let da = try #require(a.dataProvider?.data as Data?)
        let db = try #require(b.dataProvider?.data as Data?)
        var worst = 0
        var sum = 0
        for y in 0..<min(a.height, b.height) {
            for x in 0..<(min(a.width, b.width) * 4) where x % 4 != 3 {
                let difference = abs(Int(da[y * a.bytesPerRow + x]) - Int(db[y * b.bytesPerRow + x]))
                worst = max(worst, difference)
                sum += difference
            }
        }
        return (worst, Double(sum) / Double(a.width * a.height * 3))
    }

    static func withPhoto(_ body: (URL, PreviewGenerator) async throws -> Void) async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "photo.jpg")
            try SyntheticImages.writeJPEG(to: url, width: 1200, height: 900, seed: 21)
            try await body(url, PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "map-test")))
        }
    }

    // MARK: Live frames

    @Test("Map frames never give a histogram and never count as the photo (R7, AC8)")
    func mapFramesAreNotThePhoto() async throws {
        try await Self.withPhoto { url, generator in
            let session = LiveRenderSession(source: url, generator: generator, longEdge: 600, colorSpace: nil)
            let values = Self.values()
            let photo = try await session.render(values)
            #expect(photo.content == .photo && photo.showsPhoto && photo.histogram != nil)
            for interactive in [false, true] {
                let map = try await session.render(values, interactive: interactive, content: .sharpeningMap)
                #expect(map.content == .sharpeningMap)
                #expect(map.histogram == nil)
                #expect(!map.showsPhoto)
            }
            // An overlay request is ignored for the map: one alternate view at a time.
            let id = values.local.masks[0].id
            let overlaid = try await session.render(values, overlayMask: id, content: .sharpeningMap)
            #expect(!overlaid.hasOverlay && overlaid.content == .sharpeningMap)
            let photoWithOverlay = try await session.render(values, overlayMask: id)
            #expect(photoWithOverlay.hasOverlay && !photoWithOverlay.showsPhoto && photoWithOverlay.histogram == nil)
        }
    }

    /// The stage cache rounds three stages once more (as LiveSessionTests);
    /// the error they make is enlarged by the masks' local values before the
    /// sharpening step, then by the mask's ramp.
    @Test("Cached stages give the map a whole render gives", arguments: [25.0, 50, 100])
    func cachedMapMatchesWhole(masking: Double) async throws {
        try await Self.withPhoto { url, generator in
            let values = Self.values(masking: masking)
            let cached = LiveRenderSession(source: url, generator: generator, longEdge: 600, colorSpace: nil)
            let whole = LiveRenderSession(source: url, generator: generator, longEdge: 600, colorSpace: nil,
                                          cachesStages: false)
            // A frame first, so the second one comes from the cache.
            _ = try await cached.render(values, content: .sharpeningMap)
            var moved = values
            moved.local.masks[1].adjustments.shadows = 55
            for frameValues in [values, moved] {
                let a = try await cached.render(frameValues, content: .sharpeningMap)
                let b = try await whole.render(frameValues, content: .sharpeningMap)
                var upstreamValues = frameValues
                upstreamValues.sharpen.amount = 0
                for index in upstreamValues.local.masks.indices { upstreamValues.local.masks[index].adjustments.sharpen = 0 }
                let allowed = Self.allowedSteps(roundings: 3, upstream: LiveSessionTests.gain(after: upstreamValues),
                                                masking: masking)
                let difference = try Self.difference(a.image.cgImage, b.image.cgImage)
                #expect(difference.worst <= allowed, "worst \(difference.worst), allowed \(allowed)")
            }
        }
    }

    // MARK: Refinement (R6, AC7)

    /// The refined map against the map computed directly on the full
    /// decode, at 1:1 (`longEdge` nil) and downscaled to the frame size at
    /// fit. The refiner rounds the image entering the sharpening step to
    /// half float once more than the direct graph: `allowedSteps` with one
    /// rounding and no upstream gain (stated per value below).
    @Test("After a pause the map is the full-resolution map, at 1:1 and downscaled at fit (AC7)",
          arguments: [25.0, 50, 100])
    func refinedIsFullResolution(masking: Double) async throws {
        try await Self.withPhoto { url, generator in
            let values = Self.values(masking: masking)
            let renderer = AdjustmentRenderer()
            let decoded = try PreviewGenerator.decode(url, longEdge: nil, draft: false)
            let full = renderer.sharpeningMap(values, to: decoded.image, context: decoded.context)
            #expect(decoded.context.scale == 1)
            let refiner = SharpeningMapRefiner(source: url, generator: generator, colorSpace: nil)
            let upstream = LiveSessionTests.gain(after: {
                var copy = values
                copy.sharpen.amount = 0
                for index in copy.local.masks.indices { copy.local.masks[index].adjustments.sharpen = 0 }
                return copy
            }())
            let allowed = Self.allowedSteps(roundings: 1, upstream: upstream, masking: masking)
            for longEdge in [nil, 600] as [Int?] {
                var expected = full
                if let longEdge { expected = expected.scaledToFit(longEdge: longEdge) }
                let direct = try #require(generator.engine.makeCGImage(AdjustmentRenderer.sharpeningMapDisplay(expected)))
                let refined = try await refiner.render(values, longEdge: longEdge)
                #expect(refined.content == .sharpeningMap && refined.histogram == nil)
                #expect(refined.image.cgImage.width == (longEdge == nil ? 1200 : 600))
                let difference = try Self.difference(refined.image.cgImage, direct)
                #expect(difference.worst <= allowed, "longEdge \(String(describing: longEdge)): worst \(difference.worst), allowed \(allowed)")
                #expect(difference.mean < 0.5)
            }
        }
    }

    @Test("Changing only Sharpening reuses the full-resolution input; other values and purge drop it")
    func refinerKeepsItsInput() async throws {
        try await Self.withPhoto { url, generator in
            let refiner = SharpeningMapRefiner(source: url, generator: generator, colorSpace: nil)
            func fills(_ values: Adjustments, longEdge: Int? = 300) async throws -> Bool {
                try await refiner.render(values, longEdge: longEdge).filledCache
            }
            var values = Self.values(masking: 30)
            let first = try await fills(values)
            values.sharpen.masking = 70
            values.sharpen.radius = 2
            values.sharpen.amount = 0
            let sharpeningChanged = try await fills(values)
            values.setEnabled(.sharpening, false)
            let turnedOff = try await fills(values, longEdge: nil)
            values.exposure.ev = 0.5
            let exposureChanged = try await fills(values)
            #expect(first && !sharpeningChanged && !turnedOff && exposureChanged)
            #expect(await refiner.holdsInput)
            await refiner.purge()
            #expect(await !refiner.holdsInput)
        }
    }

    @Test("A refinement cancelled before it starts makes no frame and renders nothing")
    func cancelledRefinement() async throws {
        try await Self.withPhoto { url, generator in
            let refiner = SharpeningMapRefiner(source: url, generator: generator, colorSpace: nil)
            let token = RenderCancellation()
            token.cancel()
            await #expect(throws: CancellationError.self) {
                try await refiner.render(Self.values(), longEdge: 300, cancellation: token)
            }
            #expect(await !refiner.holdsInput)
        }
    }
}

/// R6's cost on a 24 MP raw and the PRD's scale assumption (Q5): measured,
/// not asserted. `LARGE_RENDER_TESTS=1 swift test --filter LargeSharpeningMapTests`.
@Suite("Large sharpening map",
       .enabled(if: ProcessInfo.processInfo.environment["LARGE_RENDER_TESTS"] == "1",
                "Set LARGE_RENDER_TESTS=1 to run"))
struct LargeSharpeningMapTests {
    static func seconds(_ duration: Duration) -> String {
        let parts = duration.components
        return String(format: "%.3f s", Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }

    /// Mean of a BGRA8 image's green channel in a centered box (0 … 1).
    static func mean(_ image: CGImage, box: Double = 0.2) throws -> Double {
        let data = try #require(image.dataProvider?.data as Data?)
        let w = image.width, h = image.height
        let x0 = Int(Double(w) * (0.5 - box / 2)), x1 = Int(Double(w) * (0.5 + box / 2))
        let y0 = Int(Double(h) * (0.5 - box / 2)), y1 = Int(Double(h) * (0.5 + box / 2))
        var sum = 0.0
        for y in y0..<y1 { for x in x0..<x1 { sum += Double(data[y * image.bytesPerRow + x * 4 + 1]) } }
        return sum / Double((x1 - x0) * (y1 - y0)) / 255
    }

    @Test func refinementCostAndScale() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "large.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 6000, height: 4000, seed: 3, noise: 0.01))
            let generator = PreviewGenerator(engine: RenderEngine.interactive())
            let session = LiveRenderSession(source: url, generator: generator, longEdge: 2560, colorSpace: nil)
            let refiner = SharpeningMapRefiner(source: url, generator: generator, colorSpace: nil)
            let clock = ContinuousClock()
            for masking in [10.0, 30, 60] {
                var values = Adjustments()
                values.sharpen = Sharpen(amount: 60, radius: 1, detail: 25, masking: masking)
                // Timed through reading the pixels back: Core Image may finish the GPU work only then.
                var start = clock.now
                let live = try await session.render(values, content: .sharpeningMap)
                _ = live.image.cgImage.dataProvider?.data
                let liveTime = clock.now - start
                start = clock.now
                let fit = try await refiner.render(values, longEdge: 2560)
                _ = fit.image.cgImage.dataProvider?.data
                let fitTime = clock.now - start
                start = clock.now
                let whole = try await refiner.render(values, longEdge: nil)
                _ = whole.image.cgImage.dataProvider?.data
                let wholeTime = clock.now - start
                print("""
                    large map, masking \(masking): live (2560 px) \(Self.seconds(liveTime)), \
                    refined at fit \(Self.seconds(fitTime)) (filled \(fit.filledCache)), \
                    refined whole \(Self.seconds(wholeTime)); \
                    mean mask in the center: live \(String(format: "%.3f", try Self.mean(live.image.cgImage))), \
                    refined at fit \(String(format: "%.3f", try Self.mean(fit.image.cgImage))), \
                    whole \(String(format: "%.3f", try Self.mean(whole.image.cgImage)))
                    """)
            }
        }
    }
}
