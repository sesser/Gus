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
/// that first draw showed (docs/features/full-render-main-thread-stall/status.md,
/// issue #65).
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

    /// Rows of differing bytes between two BGRA buffers of `width` pixels.
    static func differingRows(_ lhs: [UInt8], _ rhs: [UInt8], width: Int) -> Int {
        let rowBytes = width * 4
        guard lhs.count == rhs.count else { return Int.max }
        return lhs.withUnsafeBytes { l in
            rhs.withUnsafeBytes { r in
                (0..<lhs.count / rowBytes).filter { memcmp(l.baseAddress! + $0 * rowBytes, r.baseAddress! + $0 * rowBytes, rowBytes) != 0 }.count
            }
        }
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
    /// image itself when it draws it (the old stall), and does not render one
    /// again whose pixels were read first. The second is why the HDR rendition,
    /// whose headroom is read off the main thread (`makeHDRCGImage`), keeps its
    /// deferred call.
    @Test("Core Animation renders an unread deferred image when it draws it, and only then")
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

        let read = CountingProvider()
        let readImage = Self.counted(read)
        let early = try #require(engine.withContext {
            $0.createCGImage(readImage, from: readImage.extent, format: .BGRA8, colorSpace: RenderEngine.outputColorSpace)
        })
        _ = early.dataProvider?.data
        let pulled = read.calls.withLock { $0 }
        #expect(pulled > 0)
        _ = try Self.drawnByCoreAnimation(early)
        #expect(read.calls.withLock { $0 } == pulled, "Core Animation rendered an image again whose pixels were read")

        // The HDR rendition itself, tagged copy included.
        let extended = CountingProvider()
        let hdr = try #require(engine.makeHDRCGImage(Self.counted(extended)))
        let hdrPulled = extended.calls.withLock { $0 }
        #expect(hdrPulled > 0)
        _ = try Self.drawnByCoreAnimation(hdr)
        #expect(extended.calls.withLock { $0 } == hdrPulled, "Core Animation rendered the HDR rendition again")
    }

    /// The pixels on screen are the ones Core Animation's own render of the
    /// deferred image gave: a 24 MP raw with a typical stack, a mask and a
    /// vignette, drawn both ways through Core Animation. At this size a render
    /// into a bitmap (`deferred: false`) differs from Core Animation's in
    /// about 3,100 of the 4,000 rows, so the test tells the two routes apart;
    /// at 4400 × 2934 it did not.
    @Test("The rendition shows what Core Animation's render of the deferred image showed")
    func matchesCoreAnimationsRender() async throws {
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
            let engine = RenderEngine(contextCount: 1, name: "deferred-test")
            let generator = PreviewGenerator(engine: engine)
            for colorSpace in [RenderEngine.outputColorSpace] {
                let name = colorSpace.name.map { $0 as String } ?? "?"
                let image = try generator.image(source: url, stack: values.editStack, longEdge: nil)
                #expect(max(image.extent.width, image.extent.height) > 4096)
                let deferred = try #require(engine.withContext {
                    $0.createCGImage(image, from: image.extent.integral, format: .BGRA8, colorSpace: colorSpace)
                })
                let before = try Self.drawnByCoreAnimation(deferred)
                let rendition = try generator.cgImage(source: url, stack: values.editStack, colorSpace: colorSpace)
                #expect(rendition.width == deferred.width && rendition.height == deferred.height)
                let after = try Self.drawnByCoreAnimation(rendition)
                let rows = Self.differingRows(before, after, width: rendition.width)
                #expect(rows == 0, "\(name): \(rows) rows differ from Core Animation's render of the deferred image")

                // Core Animation passes the rendition's own pixels through
                // unchanged (its rows top to bottom, the texture's bottom to top).
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
                #expect(Self.differingRows(own, after, width: rendition.width) == 0, "\(name): not drawn as rendered")
            }
        }
    }
}
