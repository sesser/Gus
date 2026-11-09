import CoreImage
import Foundation
import PhotoFixtures
import Synchronization
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

    @Test("A cancelled request keeps the input already rendered for the next one")
    func cancelledRefinementKeepsTheInput() async throws {
        try await Self.withPhoto { url, generator in
            let refiner = SharpeningMapRefiner(source: url, generator: generator, colorSpace: nil)
            let values = Self.values(masking: 30)
            let first = try await refiner.render(values, longEdge: 300)
            #expect(first.filledCache)
            let token = RenderCancellation()
            token.cancel()
            await #expect(throws: CancellationError.self) {
                try await refiner.render(values, longEdge: 300, cancellation: token)
            }
            #expect(await refiner.holdsInput)
            let next = try await refiner.render(values, longEdge: 300)
            #expect(!next.filledCache)
        }
    }

    // MARK: The kept input

    /// Counts how often Core Image asks for pixels; the image is mid-grey.
    private final class CountingProvider: NSObject, Sendable {
        let calls = Mutex(0)

        override func provideImageData(_ data: UnsafeMutableRawPointer, bytesPerRow rowBytes: Int, origin x: Int, _ y: Int,
                                       size width: Int, _ height: Int, userInfo info: Any?) {
            calls.withLock { $0 += 1 }
            for row in 0..<height { memset(data + row * rowBytes, 0x80, width * 4) }
        }
    }

    /// The mechanism behind the wrong cells (docs/features/sharpening-map-tiles/status.md):
    /// a deferred render asks its source for nothing until something reads
    /// the result, so a lazy input fails the last two expectations here. The
    /// size is the real file's: Core Image defers only an image with a side
    /// over 4096, and `CIImage(cgImage:)` reads a deferred half-float image
    /// at once up to about 17 MP, so anything smaller passes with or without
    /// `deferred: false`.
    ///
    /// Those limits are measured, not documented, so a later macOS can move
    /// them and leave this test passing without testing anything. The control
    /// makes that a failure: the same image through the call `materialize`
    /// used before the fix must still be asked for nothing. If it fails, this
    /// guard no longer detects a lazy input: find a size that still defers, or
    /// replace the test. The artifact itself needs a real camera raw:
    /// `SharpeningMapRawFileTests`.
    @Test("The kept input holds pixels when it is made, so reading it renders nothing again")
    func keptInputIsRendered() async throws {
        let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "map-test"))
        let refiner = SharpeningMapRefiner(source: URL(filePath: "/unused.jpg"), generator: generator, colorSpace: nil)
        func image(from provider: CountingProvider) -> CIImage {
            CIImage(imageProvider: provider, size: 5472, 3648, format: .BGRA8,
                    colorSpace: RenderEngine.outputColorSpace, options: nil)
        }

        let control = CountingProvider()
        let controlImage = image(from: control)
        let deferred = try #require(generator.engine.withContext {
            $0.createCGImage(controlImage, from: controlImage.extent, format: .RGBAh, colorSpace: RenderEngine.workingColorSpace)
        })
        _ = CIImage(cgImage: deferred)
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        #expect(control.calls.withLock { $0 } == 0,
                "Core Image no longer defers this image on \(system): this test can't detect a lazy input here and needs revisiting (see its comment)")

        let provider = CountingProvider()
        let kept = try await refiner.materialize(image(from: provider))
        let pulled = provider.calls.withLock { $0 }
        #expect(pulled > 0, "materialize returned without rendering: the input it keeps is lazy")
        for _ in 0..<2 {
            let read = try #require(generator.engine.makeCGImage(kept))
            _ = read.dataProvider?.data
        }
        #expect(provider.calls.withLock { $0 } == pulled, "reading the kept input went back to its source")
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

/// Wrong cells of the refined map on a real camera raw. Each refinement is
/// compared with the mask graph over the same input rendered to pixels here,
/// last: a full-resolution render earlier in the process hides the fault
/// (docs/features/sharpening-map-tiles/status.md). So run this suite alone:
/// `CAMERA_RAW_SAMPLE=path/to/file.RW2 swift test --filter SharpeningMapRawFileTests`.
/// The file is only read. A file that doesn't trigger the fault passes and
/// shows nothing; the synthetic DNG doesn't trigger it.
@Suite("Sharpening map on a camera RAW file",
       .enabled(if: ProcessInfo.processInfo.environment["CAMERA_RAW_SAMPLE"] != nil,
                "Set CAMERA_RAW_SAMPLE to a camera raw and run this suite alone"))
struct SharpeningMapRawFileTests {
    static func values(masking: Double) -> Adjustments {
        var values = Adjustments()
        values.sharpen = Sharpen(amount: 98, radius: 1.4, detail: 52, masking: masking)
        return values
    }

    /// Every run renders a first refinement, one from the input it kept, and
    /// a first refinement of another refiner: a first refinement can be the
    /// wrong one too. Each must equal, pixel for pixel, the same graph over
    /// the same pixels. Against the direct map the two sides would differ by
    /// the input's half-float rounding, and no bound on that has been derived
    /// that holds on real files (status.md, Code review C1); here rounding
    /// isn't part of the comparison, and a wrong cell differs by up to 255.
    @Test("Refined maps, first and from a kept input, equal the same graph over eagerly rendered pixels")
    func refinedMapsMatchRenderedPixels() async throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAMERA_RAW_SAMPLE"] ?? "")
        let longEdge = PreviewTier.preview.longEdge
        let generator = PreviewGenerator(engine: RenderEngine.interactive())

        func refined(_ refiner: SharpeningMapRefiner, masking: Double) async throws -> LiveRenderSession.Frame {
            let frame = try await refiner.render(Self.values(masking: masking), longEdge: longEdge)
            _ = frame.image.cgImage.dataProvider?.data
            return frame
        }
        var maps: [(label: String, masking: Double, image: CGImage)] = []
        for run in 1...5 {
            let refiner = SharpeningMapRefiner(source: url, generator: generator, colorSpace: nil)
            let first = try await refined(refiner, masking: 23)
            let kept = try await refined(refiner, masking: 30)
            let fresh = try await refined(SharpeningMapRefiner(source: url, generator: generator, colorSpace: nil), masking: 30)
            #expect(first.filledCache && !kept.filledCache && fresh.filledCache)
            maps += [("run \(run), first", 23, first.image.cgImage), ("run \(run), kept input", 30, kept.image.cgImage),
                     ("run \(run), first of another refiner", 30, fresh.image.cgImage)]
        }

        let renderer = AdjustmentRenderer()
        var eager: [Double: CGImage] = [:]
        for masking in [23.0, 30] {
            let values = Self.values(masking: masking)
            let decoded = try PreviewGenerator.decode(url, longEdge: nil, draft: false,
                                                      settings: renderer.decodeSettings(for: values.editStack))
            let input = renderer.sharpeningInput(values, to: decoded.image, context: decoded.context)
            let extent = input.extent.integral
            let pixels = try #require(generator.engine.withContext {
                $0.createCGImage(input, from: extent, format: .RGBAh, colorSpace: RenderEngine.workingColorSpace, deferred: false)
            })
            let kept = CIImage(cgImage: pixels).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            let mask = AdjustmentRenderer.sharpeningMask(kept, values.sharpen, scale: decoded.context.scale)
                .scaledToFit(longEdge: longEdge)
            let rendered = try #require(generator.engine.makeCGImage(AdjustmentRenderer.sharpeningMapDisplay(mask)))
            eager[masking] = rendered
        }
        for map in maps {
            let expected = try #require(eager[map.masking])
            let difference = try SharpeningMapSessionTests.difference(map.image, expected)
            #expect(difference.worst == 0, "\(map.label): worst \(difference.worst) against the same pixels")
        }
    }
}
