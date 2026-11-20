import CoreGraphics
import CoreImage
import Foundation
import Metal
import PhotoFixtures
import QuartzCore
import Synchronization
import Testing
@testable import PhotoCore

/// The loupe's full-resolution rendition is rendered where it is made, not by
/// Core Animation at its first draw on the main thread, and shows the pixels
/// that first draw showed, within one level (docs/features/full-render-main-thread-stall/status.md,
/// issue #65). The HDR rendition holds its own pixels, so Core Animation never
/// renders it again (docs/features/deferred-render-flake/status.md, issue #229).
///
/// Core Image's short `createCGImage` defers an image with a side over 4096
/// pixels (measured on macOS 27.2, not documented), so the sizes here are over
/// that. Core Animation is driven headless through `CARenderer`, which renders
/// a layer's contents the way a window's commit does, including the deferred
/// render through Core Image.
@Suite("Deferred renders", .serialized)
struct DeferredRenderTests {
    /// Counts how often Core Image asks for pixels; the image is mid-grey.
    private final class CountingProvider: NSObject, Sendable {
        let calls = Mutex(0)

        override func provideImageData(_ data: UnsafeMutableRawPointer, bytesPerRow rowBytes: Int, origin x: Int, _ y: Int,
                                       size width: Int, _ height: Int, userInfo info: Any?) {
            calls.withLock { $0 += 1 }
            for row in 0..<height { memset(data + row * rowBytes, 0x80, width * 4) }
        }
    }

    private static func counted(_ provider: CountingProvider) -> CIImage {
        CIImage(imageProvider: provider, size: 5472, 3648, format: .BGRA8, colorSpace: RenderEngine.outputColorSpace,
                options: nil)
    }

    /// Draws `image` as a layer's contents through Core Animation into a BGRA
    /// texture in the image's own color space (so it passes pixels through
    /// unchanged) and returns the texture's bytes, rows bottom to top.
    static func drawnByCoreAnimation(_ image: CGImage) throws -> [UInt8] {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let width = image.width, height = image.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        // Our own queue: Core Animation only commits its work on it, and an
        // empty buffer committed after it completes after it.
        let queue = try #require(device.makeCommandQueue())
        let renderer = CARenderer(mtlTexture: texture, options: [
            kCARendererColorSpace as String: try #require(image.colorSpace),
            kCARendererMetalCommandQueue as String: queue,
        ])
        CATransaction.begin()
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        layer.contentsGravity = .resize
        layer.contents = image
        renderer.layer = layer
        renderer.bounds = layer.bounds
        CATransaction.commit()
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        let fence = try #require(queue.makeCommandBuffer())
        fence.commit()
        fence.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return bytes
    }

    /// The largest per-byte difference between two BGRA buffers of `width`
    /// pixels, and how many rows differ at all. Only differing rows are read
    /// byte by byte; with `stopAbove`, the scan ends at the first byte over it.
    static func difference(_ lhs: [UInt8], _ rhs: [UInt8], width: Int, stopAbove: Int? = nil) -> (worst: Int, rows: Int) {
        let rowBytes = width * 4
        guard lhs.count == rhs.count else { return (Int.max, Int.max) }
        var worst = 0, rows = 0
        lhs.withUnsafeBytes { l in
            rhs.withUnsafeBytes { r in
                for row in 0..<lhs.count / rowBytes
                where memcmp(l.baseAddress! + row * rowBytes, r.baseAddress! + row * rowBytes, rowBytes) != 0 {
                    rows += 1
                    for offset in row * rowBytes..<(row + 1) * rowBytes {
                        worst = max(worst, abs(Int(l[offset]) - Int(r[offset])))
                        if let stopAbove, worst > stopAbove { return }
                    }
                }
            }
        }
        return (worst, rows)
    }

    @Test("The full-resolution rendition is rendered before it is returned")
    func renderedWhereMade() throws {
        let engine = RenderEngine(contextCount: 1, name: "deferred-test")
        // The control: the short call still defers this image, so the test
        // can tell. A macOS that stops deferring it fails here instead of
        // passing without testing anything.
        let control = CountingProvider()
        let controlImage = Self.counted(control)
        _ = try #require(engine.withContext {
            $0.createCGImage(controlImage, from: controlImage.extent, format: .BGRA8, colorSpace: RenderEngine.outputColorSpace)
        })
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        #expect(control.calls.withLock { $0 } == 0,
                "Core Image no longer defers this image on \(system): this test can't tell a deferred render here and needs revisiting")

        let provider = CountingProvider()
        let rendered = try #require(engine.makeSurfaceImage(Self.counted(provider)))
        let pulled = provider.calls.withLock { $0 }
        #expect(pulled > 0, "makeSurfaceImage returned without rendering: Core Animation would render it on the main thread")
        _ = rendered.dataProvider?.data
        _ = try Self.drawnByCoreAnimation(rendered)
        #expect(provider.calls.withLock { $0 } == pulled, "reading or drawing the image went back to its source")
    }

    /// What `drawnByCoreAnimation` stands for: Core Animation renders a deferred
    /// image itself when it draws it (the old stall).
    @Test("Core Animation renders an unread deferred image when it draws it")
    func coreAnimationRendersDeferredImages() throws {
        let engine = RenderEngine(contextCount: 1, name: "deferred-test")
        let unread = CountingProvider()
        let unreadImage = Self.counted(unread)
        let lazy = try #require(engine.withContext {
            $0.createCGImage(unreadImage, from: unreadImage.extent, format: .BGRA8, colorSpace: RenderEngine.outputColorSpace)
        })
        #expect(unread.calls.withLock { $0 } == 0)
        _ = try Self.drawnByCoreAnimation(lazy)
        #expect(unread.calls.withLock { $0 } > 0, "Core Animation drew a deferred image without rendering it")
    }

    /// Other large renders, in a context of their own, each read once: what
    /// the rest of the app (or of a parallel test run) does to Core Image's
    /// process-wide surfaces meanwhile. 96 renders of the test's size made
    /// Core Image render a read deferred image again in every run measured
    /// (docs/features/deferred-render-flake/status.md); 8 never did.
    static func renderOthers(count: Int = 96) throws {
        let other = RenderEngine(contextCount: 1, name: "deferred-test-other")
        for _ in 0..<count {
            let image = counted(CountingProvider())
            let rendered = try #require(other.withContext {
                $0.createCGImage(image, from: image.extent, format: .BGRA8, colorSpace: RenderEngine.outputColorSpace)
            })
            _ = rendered.dataProvider?.data
        }
    }

    /// The HDR rendition (`makeHDRCGImage`, tagged copy included) is rendered
    /// before it is returned, off the main thread, and nothing goes back to its
    /// source afterwards, however long it waits in the memory cache. Reading a
    /// deferred image's pixels is not enough for that: Core Image keeps them in
    /// a purgeable surface of its process-wide pool, which other renders take
    /// back, and the next reader (Core Animation's commit, on the main thread)
    /// renders the image again. The control shows that still happens, so the
    /// test can tell.
    @Test("The HDR rendition is rendered before it is returned, and never again")
    func hdrRenditionOwnsItsPixels() throws {
        let engine = RenderEngine(contextCount: 1, name: "deferred-test")
        let control = CountingProvider()
        let controlImage = Self.counted(control)
        let read = try #require(engine.withContext {
            $0.createCGImage(controlImage, from: controlImage.extent, format: .BGRA8, colorSpace: RenderEngine.outputColorSpace)
        })
        _ = read.dataProvider?.data
        let controlPulled = control.calls.withLock { $0 }
        #expect(controlPulled > 0)

        let extended = CountingProvider()
        let hdr = try #require(engine.makeHDRCGImage(Self.counted(extended)))
        let hdrPulled = extended.calls.withLock { $0 }
        #expect(hdrPulled > 0, "makeHDRCGImage returned without rendering")

        try Self.renderOthers()
        _ = read.dataProvider?.data
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        #expect(control.calls.withLock { $0 } > controlPulled,
                "Core Image kept a read deferred image's pixels through other renders on \(system): this test can't tell whether the HDR rendition holds its own and needs revisiting")

        _ = hdr.dataProvider?.data
        _ = try Self.drawnByCoreAnimation(hdr)
        #expect(extended.calls.withLock { $0 } == hdrPulled, "reading or drawing the HDR rendition went back to its source")
    }

    /// Whether a run asked for the large renders (`LARGE_RENDER_TESTS=1`), as
    /// `LargeRenderTests` does: the CI runners' paravirtual GPU fails the
    /// 24 MP render below ("command buffer exited with error status").
    static let largeRenders = ProcessInfo.processInfo.environment["LARGE_RENDER_TESTS"] == "1"

    /// Core Animation's render of the deferred image (the old screen) against
    /// its draw of the rendition, within one level per byte, and the
    /// rendition's own pixels passed through unchanged. With `control`, a
    /// render into a bitmap (`deferred: false`) must differ by more than one
    /// level, so the comparison can tell the routes apart.
    ///
    /// Within one level, not byte for byte: Core Image's 8-bit output varies by
    /// one level between two renders of the same graph on either route (code
    /// review C1: up to 486 rows, never more than 1).
    static func expectRenditionMatchesCoreAnimation(_ url: URL, stack: EditStack, control: Bool) throws {
        let engine = RenderEngine(contextCount: 1, name: "deferred-test")
        let generator = PreviewGenerator(engine: engine)
        let colorSpace = RenderEngine.outputColorSpace
        let image = try generator.image(source: url, stack: stack, longEdge: nil)
        // Over 4096 on a side, so the short call defers and Core Animation renders it.
        #expect(max(image.extent.width, image.extent.height) > 4096)
        let deferred = try #require(engine.withContext {
            $0.createCGImage(image, from: image.extent.integral, format: .BGRA8, colorSpace: colorSpace)
        })
        let before = try drawnByCoreAnimation(deferred)
        let rendition = try generator.cgImage(source: url, stack: stack, colorSpace: colorSpace)
        #expect(rendition.width == deferred.width && rendition.height == deferred.height)
        let after = try drawnByCoreAnimation(rendition)
        let drawn = difference(before, after, width: rendition.width)
        #expect(drawn.worst <= 1,
                "\(drawn.rows) rows differ from Core Animation's render of the deferred image, by up to \(drawn.worst) levels")

        if control {
            let bitmap = try #require(engine.withContext {
                $0.createCGImage(image, from: image.extent.integral, format: .BGRA8, colorSpace: colorSpace, deferred: false)
            })
            let bitmapDrawn = difference(before, try drawnByCoreAnimation(bitmap), width: rendition.width, stopAbove: 1)
            #expect(bitmapDrawn.worst > 1,
                    "a bitmap render now matches Core Animation's within one level: this test can't tell the routes apart and needs revisiting")
        }

        // Core Animation passes the rendition's own pixels through unchanged
        // (its rows top to bottom, the texture's bottom to top).
        let data = try #require(rendition.dataProvider?.data as Data?)
        let rowBytes = rendition.width * 4
        var own = [UInt8](repeating: 0, count: rowBytes * rendition.height)
        data.withUnsafeBytes { source in
            own.withUnsafeMutableBytes { destination in
                for row in 0..<rendition.height {
                    memcpy(destination.baseAddress! + (rendition.height - 1 - row) * rowBytes,
                           source.baseAddress! + row * rendition.bytesPerRow, rowBytes)
                }
            }
        }
        #expect(difference(own, after, width: rendition.width).rows == 0, "not drawn as rendered")
    }

    /// At a size and stack the CI runners' GPU renders: one side over 4096,
    /// so the old route was Core Animation's own deferred render, but about
    /// 5 MP, with pointwise adjustments only. Runs everywhere; the stack is too
    /// light for the bitmap route to differ, so it has no control (the 24 MP
    /// test has it).
    @Test("The rendition shows what Core Animation's render of the deferred image showed, within one level (4400 x 1100)")
    func matchesCoreAnimationsRender() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "wide.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 4400, height: 1100, seed: 65, noise: 0.01))
            var values = Adjustments()
            values.exposure.ev = 0.4
            values.vignette.amount = -30
            try Self.expectRenditionMatchesCoreAnimation(url, stack: values.editStack, control: false)
        }
    }

    /// A 24 MP raw with a typical stack, a mask and a vignette: there a bitmap
    /// render differs from Core Animation's (up to 52 levels), so the control
    /// shows the comparison tells the routes apart; at 4400 x 2934 it did not.
    /// Gated like `LargeRenderTests`: the CI runners' paravirtual GPU can't
    /// render it (`renderFailed`, run 43807422336).
    /// `LARGE_RENDER_TESTS=1 swift test --filter DeferredRenderTests`.
    @Test("At 24 MP with a typical stack, the rendition shows Core Animation's render and the bitmap route is told apart",
          .enabled(if: largeRenders, "Set LARGE_RENDER_TESTS=1 to run: a 24 MP render the CI runners' GPU can't do"))
    func matchesCoreAnimationsRenderLarge() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "wide.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 6000, height: 4000, seed: 65, noise: 0.01))
            var values = LiveRegionRendererTests.typical
            values.local.masks = [
                GoldenCase.mask([.radial(RadialGradient(center: MaskPoint(x: 0.4, y: 0.6), radiusX: 0.3, radiusY: 0.2))]) {
                    $0.exposure = 0.7
                    $0.clarity = 25
                },
            ]
            values.vignette.amount = -30
            try Self.expectRenditionMatchesCoreAnimation(url, stack: values.editStack, control: true)
        }
    }

    /// The product path when the GPU can't render: no image, so the preview
    /// service throws `renderFailed` and the loupe keeps the preview it shows
    /// (`LoupeView.loadFullResolution`). Runs everywhere.
    @Test("A surface render that can't be made gives no image, and the generator throws")
    func failedSurfaceRenderGivesNoImage() throws {
        let engine = RenderEngine(contextCount: 1, name: "deferred-test")
        #expect(engine.makeSurfaceImage(CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))) == nil, "infinite extent")
        #expect(engine.makeSurfaceImage(CIImage.empty()) == nil, "empty extent")
        let small = try #require(engine.makeSurfaceImage(
            CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))))
        #expect(small.width == 64 && small.height == 48)
        #expect(throws: PreviewGenerator.Failure.undecodable(URL(fileURLWithPath: "/nonexistent/photo.jpg"))) {
            try PreviewGenerator(engine: engine).cgImage(source: URL(fileURLWithPath: "/nonexistent/photo.jpg"), stack: .identity)
        }
    }
}
