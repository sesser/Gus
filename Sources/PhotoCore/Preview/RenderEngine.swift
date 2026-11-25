import Accelerate
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import ImageIO
import IOSurface
import Metal
import Synchronization

/// The Core Image contexts everything renders through.
///
/// Metal-backed, working in extended linear Rec. 2020 at half float so that edits
/// operate on linear light with headroom and a gamut wide enough for camera
/// colors. Output is converted to Display P3 when encoded or turned into a
/// `CGImage`; Core Animation color-matches that to the actual display.
///
/// A `CIContext` runs one render at a time, and a camera RAW file is decoded
/// lazily inside the render that first needs its pixels, so one context would
/// run every RAW decode one after the other. An engine keeps a pool of
/// contexts and gives each render the least busy one.
public final class RenderEngine: @unchecked Sendable {
    // @unchecked: CIContext is documented as thread-safe; the contexts are
    // immutable here and the busy counts are guarded by a mutex.

    public static let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    public static let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    /// HDR renditions keep values above 1.0, SDR white, in extended linear Display P3.
    public static let hdrColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    /// Renditions whose brightest component stays below this are treated as SDR.
    public static let minimumHDRHeadroom: Float = 1.05

    public let device: (any MTLDevice)?
    /// Core Image's software renderer, on the CPU.
    public let isSoftwareRenderer: Bool
    private let contexts: [CIContext]
    /// Renders in progress per context.
    private let busy: Mutex<[Int]>

    /// - Parameter contextCount: Renders that can run at once; one context each.
    /// - Parameter softwareRenderer: Ask for Core Image's software renderer (on
    ///   the CPU) instead of the GPU. Core Image ignores the request where there
    ///   is no OpenCL, which includes Apple silicon: check
    ///   `softwareRendererIsAvailable` first.
    public init(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice(),
                contextCount: Int = PreviewService.defaultGenerateConcurrency, name: String = "preview-pipeline",
                softwareRenderer: Bool = false) {
        self.device = softwareRenderer ? nil : device
        isSoftwareRenderer = softwareRenderer
        let device = self.device
        contexts = (0..<max(1, contextCount)).map { index in
            var options: [CIContextOption: Any] = [
                .workingColorSpace: Self.workingColorSpace,
                .workingFormat: CIFormat.RGBAh,
                // Previews are rendered once each; caching intermediates only costs memory.
                .cacheIntermediates: false,
                .name: "\(name)-\(index)",
            ]
            if softwareRenderer {
                options[.useSoftwareRenderer] = true
            }
            if let device {
                return CIContext(mtlDevice: device, options: options)
            }
            return CIContext(options: options)
        }
        busy = Mutex([Int](repeating: 0, count: contexts.count))
    }

    /// For the renders a person waits on (live edits, the loupe's 1:1 and HDR
    /// renditions), so they never queue behind background previews.
    public static func interactive() -> RenderEngine {
        RenderEngine(contextCount: 2, name: "interactive")
    }

    public var contextCount: Int { contexts.count }

    /// Runs `body` with the least busy context.
    public func withContext<T>(_ body: (CIContext) throws -> T) rethrows -> T {
        let index = busy.withLock { counts in
            let index = counts.indices.min { counts[$0] < counts[$1] } ?? 0
            counts[index] += 1
            return index
        }
        defer { busy.withLock { $0[index] -= 1 } }
        return try body(contexts[index])
    }

    public var isMetalBacked: Bool { device != nil }

    /// Whether Core Image can render on the CPU here. Its documentation says the
    /// software renderer option "has no effect if the platform does not support
    /// OpenCL"; on Apple silicon a context created with it is still a Metal
    /// context. Core Image has no API for the backend, so this reads the
    /// context's description, which names it ("metal").
    public static let softwareRendererIsAvailable: Bool = {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        return !String(describing: context).lowercased().contains("metal")
    }()

    /// Renders to an 8-bit `CGImage` in `colorSpace` (Display P3 by default). Pass
    /// the screen's color space for images headed straight to a layer, so Core
    /// Animation does not have to convert them on the main thread.
    public func makeCGImage(_ image: CIImage, colorSpace: CGColorSpace? = nil) -> CGImage? {
        let space = colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? Self.outputColorSpace
        return withContext { $0.createCGImage(image, from: image.extent.integral, format: .BGRA8, colorSpace: space) }
    }

    /// Renders on the GPU into an IOSurface, here and now, and returns an 8-bit
    /// BGRA `CGImage` over the surface's pixels in `colorSpace` (Display P3 by
    /// default): for an image larger than 4096 pixels headed to a layer (the
    /// loupe's full-resolution rendition). Nil if the render fails.
    ///
    /// `makeCGImage` would hand Core Animation a deferred image, which it then
    /// renders at its first commit on the main thread, through Core Image into
    /// an IOSurface: the loupe froze for the whole render
    /// (docs/features/full-render-main-thread-stall/status.md). This makes the
    /// same render into a surface of its own, on the caller's thread, so the
    /// pixels are the ones Core Animation made before, within the one level
    /// Core Image varies by between renders (`DeferredRenderTests`), and arrive
    /// as fast. Rendering into a bitmap instead (`deferred: false`)
    /// took about 2.5 times as long for a typical stack and gave other values.
    public func makeSurfaceImage(_ image: CIImage, colorSpace: CGColorSpace? = nil) -> CGImage? {
        let space = colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? Self.outputColorSpace
        let extent = image.extent.integral
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1,
              let surface = IOSurface(properties: [
                  .width: Int(extent.width), .height: Int(extent.height), .bytesPerElement: 4,
                  .pixelFormat: kCVPixelFormatType_32BGRA,
              ])
        else { return nil }
        let destination = CIRenderDestination(ioSurface: surface)
        destination.colorSpace = space
        do {
            _ = try withContext { try $0.startTask(toRender: image, from: extent, to: destination, at: .zero).waitUntilCompleted() }
        } catch {
            return nil
        }
        // Locked for reading for as long as the image lives, so the CPU sees the
        // GPU's writes; the provider's release unlocks and lets the surface go.
        guard surface.lock(options: .readOnly, seed: nil) == KERN_SUCCESS else { return nil }
        let info = Unmanaged.passRetained(surface).toOpaque()
        guard let provider = CGDataProvider(dataInfo: info, data: surface.baseAddress,
                                            size: surface.bytesPerRow * surface.height,
                                            releaseData: { info, _, _ in
                                                guard let info else { return }
                                                let surface = Unmanaged<IOSurface>.fromOpaque(info).takeRetainedValue()
                                                surface.unlock(options: .readOnly, seed: nil)
                                            })
        else {
            let surface = Unmanaged<IOSurface>.fromOpaque(info).takeRetainedValue()
            surface.unlock(options: .readOnly, seed: nil)
            return nil
        }
        return CGImage(width: surface.width, height: surface.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: surface.bytesPerRow, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                           | CGImageByteOrderInfo.order32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Renders to an RGBA `CGImage` with 8 or 16 bits per component in
    /// `colorSpace`, for writing to a file.
    public func makeCGImage(_ image: CIImage, colorSpace: CGColorSpace, bitsPerComponent: Int) -> CGImage? {
        withContext {
            $0.createCGImage(image, from: image.extent.integral, format: bitsPerComponent == 16 ? .RGBA16 : .RGBA8,
                             colorSpace: colorSpace)
        }
    }

    /// Renders to a half-float `CGImage` in extended linear Display P3, tagged with
    /// its content headroom: the brightest component relative to SDR white, which
    /// Core Animation needs to tone map the image to what the display can show.
    ///
    /// Rendered here and now, and the returned image holds its own pixels. The
    /// short `createCGImage` defers an image with a side over 4096 pixels, and
    /// reading its pixels once is not enough: Core Image keeps them in a
    /// purgeable surface of its process-wide pool, which later renders (in any
    /// context) take back, and the next reader renders the image again. For a
    /// rendition waiting in the memory cache that reader is Core Animation's
    /// commit on the main thread (`DeferredRenderTests`,
    /// docs/features/deferred-render-flake/status.md). So the pixels read for
    /// the headroom become the image's own; the deferred image, and its claim
    /// on the pool, go when this returns.
    public func makeHDRCGImage(_ image: CIImage) -> CGImage? {
        guard let rendered = ownedHDRPixels(image), let headroom = Self.maximumComponent(of: rendered) else { return nil }
        return CGImageCreateCopyWithContentHeadroom(max(headroom, 1), rendered) ?? rendered
    }

    /// As `makeHDRCGImage(_:)`, tagged with `contentHeadroom` instead of the
    /// brightest value found: for a gain-map photo's HDR version (issue
    /// #282), whose values the render keeps within that headroom, so every
    /// frame of a visit carries the same tag whatever an edit does to its
    /// brightest pixel, and no scan of the pixels is needed.
    public func makeHDRCGImage(_ image: CIImage, contentHeadroom: Float) -> CGImage? {
        guard let rendered = ownedHDRPixels(image) else { return nil }
        return CGImageCreateCopyWithContentHeadroom(max(contentHeadroom, 1), rendered) ?? rendered
    }

    /// `image` rendered now, once, to half float in the working space, as an
    /// image over those pixels with `image`'s extent: for several renders of
    /// one frame (a gain-map photo's HDR frame and its two histograms, issue
    /// #282, R11) that would each evaluate the whole graph again. Values
    /// above white and below black are kept.
    public func materialized(_ image: CIImage) -> CIImage? {
        let extent = image.extent.integral
        // Kept on the GPU: an IOSurface of half floats, read by the renders that follow.
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1,
              let surface = IOSurface(properties: [
                  .width: Int(extent.width), .height: Int(extent.height), .bytesPerElement: 8,
                  .pixelFormat: kCVPixelFormatType_64RGBAHalf,
              ])
        else { return nil }
        let destination = CIRenderDestination(ioSurface: surface)
        destination.colorSpace = Self.workingColorSpace
        do {
            _ = try withContext { try $0.startTask(toRender: image, from: extent, to: destination, at: .zero).waitUntilCompleted() }
        } catch {
            return nil
        }
        return CIImage(ioSurface: surface, options: [.colorSpace: Self.workingColorSpace])
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// `image` rendered now to half float in `hdrColorSpace`, holding its own pixels.
    private func ownedHDRPixels(_ image: CIImage) -> CGImage? {
        guard let deferred = withContext({
                  $0.createCGImage(image, from: image.extent.integral, format: .RGBAh, colorSpace: Self.hdrColorSpace)
              }),
              let pixels = deferred.dataProvider?.data,
              let provider = CGDataProvider(data: pixels)
        else { return nil }
        return CGImage(width: deferred.width, height: deferred.height,
                       bitsPerComponent: deferred.bitsPerComponent, bitsPerPixel: deferred.bitsPerPixel,
                       bytesPerRow: deferred.bytesPerRow, space: deferred.colorSpace ?? Self.hdrColorSpace,
                       bitmapInfo: deferred.bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: deferred.shouldInterpolate, intent: deferred.renderingIntent)
    }

    /// The largest component (alpha included, which is at most 1) of a
    /// half-float image, scanned row by row.
    static func maximumComponent(of image: CGImage) -> Float? {
        guard image.bitsPerComponent == 16, image.bitsPerPixel == 64,
              image.bitmapInfo.contains(.floatComponents),
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data)
        else { return nil }
        let count = image.width * 4
        var row = [Float](repeating: 0, count: count)
        var maximum: Float = 0
        for y in 0..<image.height {
            var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: bytes + y * image.bytesPerRow),
                                       height: 1, width: vImagePixelCount(count), rowBytes: count * 2)
            let rowMaximum = row.withUnsafeMutableBufferPointer { buffer -> Float in
                var destination = vImage_Buffer(data: buffer.baseAddress, height: 1, width: vImagePixelCount(count),
                                                rowBytes: count * 4)
                vImageConvert_Planar16FtoPlanarF(&source, &destination, vImage_Flags(kvImageNoFlags))
                return vDSP.maximum(buffer)
            }
            maximum = max(maximum, rowMaximum)
        }
        return maximum
    }

    /// Renders and encodes as JPEG with an embedded Display P3 profile.
    public func jpegData(_ image: CIImage, quality: Double) -> Data? {
        let key = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return withContext { $0.jpegRepresentation(of: image, colorSpace: Self.outputColorSpace, options: [key: quality]) }
    }
}

extension CIImage {
    /// Scales down (never up) so the long edge is at most `longEdge` pixels, with the
    /// result snapped to whole pixels at the origin.
    func scaledToFit(longEdge: Int) -> CIImage {
        let extent = self.extent
        let longest = max(extent.width, extent.height)
        guard longest > 0, extent.isInfinite == false else { return self }
        var image = self.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let scale = Double(longEdge) / longest
        if scale < 1 {
            let filter = CIFilter.lanczosScaleTransform()
            filter.inputImage = image
            filter.scale = Float(scale)
            filter.aspectRatio = 1
            image = filter.outputImage ?? image
        }
        let size = CGSize(width: (extent.width * min(scale, 1)).rounded(), height: (extent.height * min(scale, 1)).rounded())
        return image.cropped(to: CGRect(origin: .zero, size: size))
    }
}
