import CoreImage
import Metal
import os

/// Copies a full-size decode that Core Image would read from the CPU (an
/// ImageIO file: JPEG, HEIC, PNG, TIFF) into a GPU texture once, a band of
/// rows at a time, so no later render reads the file itself.
///
/// **The fault this works around** (macOS 27.2; bug #253,
/// docs/features/core-image-split-render/status.md). When Core Image
/// splits a large render to a GPU destination (an IOSurface or a texture)
/// into parts, it copies each part's share of a CPU-side image into a pooled
/// texture, and the parts are encoded one after the other without waiting.
/// Now and then a later part's copy lands before an earlier part's programs
/// have read theirs: a 5472 × 3648 photo with Shadows or negative Highlights
/// came out with its left half showing the right half's pixels (one render in
/// three in tests, at 4592 × 3448 too; in the app, every zoom to 100% on the
/// owner's 16-bit TIFF), so the loupe at 100% showed two halves that didn't line
/// up. The same graph over a texture is still split into parts and never
/// showed it. Neither rendering in bands nor a larger `memoryTarget` stops
/// the split: graphs that need the whole photo (the masks' estimates) are
/// split inside a band and with 2 GB.
///
/// **The copy** is the decode in the working space (linear), 32-bit float:
/// the values Core Image computes when it reads the file, so unedited renders
/// are the same bit for bit. Resampling now interpolates linear light, as it
/// already does for raws (whose decode is linear) and for the loupe's live
/// frames at 100% (`LiveRegionRenderer`'s base): reading the file, Core Image
/// interpolated its encoded values before linearizing them. That changes
/// straightened or rotated full-size renders of these files slightly
/// (status.md). Half float would hold half the memory but changed about a
/// third of an edited render's values.
///
/// **The copy itself** is a render of the CPU-side image, which Core Image
/// would split the same way at this size (`render_to_texture … /2`): it runs
/// in bands of at most `bandPixels`, each finished before the next starts, so
/// none is split and no copy races a read. It is not flipped: read through a
/// flip transform, a texture was sampled one row off by run-time kernels (the
/// spots').
///
/// **What it costs.** One more pass over the photo, and 16 bytes per pixel of
/// GPU memory while the decode is in use (320 MB for 20 megapixels), released
/// with it. Full-size decodes only: previews and thumbnails are decoded
/// smaller by ImageIO and never read here.
enum ResidentDecode {
    /// One context of its own, so these copies don't queue behind previews.
    static let engine = RenderEngine(contextCount: 1, name: "resident-decode")

    /// Pixels per band: a 32 MB copy of 16-bit pixels at most, far under the
    /// intermediates Core Image allows one render before splitting it.
    static let bandPixels = 1 << 22

    /// The largest side a texture can have on every Apple GPU the app runs on.
    static let maximumDimension = 16384

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "decode")

    /// `image` copied into a float texture, as an image over the same extent
    /// that reads it. Nil, logged, when the extent is not a finite whole-pixel
    /// rectangle within `maximumDimension`, there is no Metal device, or the
    /// texture can't be made or filled: the caller keeps `image`.
    static func resident(_ image: CIImage, engine: RenderEngine = engine) -> CIImage? {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite, extent == extent.integral else {
            log.error("A full-size decode was left lazy: extent \(String(describing: extent), privacy: .public)")
            return nil
        }
        let width = Int(extent.width), height = Int(extent.height)
        guard width <= maximumDimension, height <= maximumDimension else {
            log.notice("A \(width) × \(height) decode is larger than one texture; it is read lazily")
            return nil
        }
        guard let device = engine.device else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            log.error("No texture for a \(width) × \(height) decode; it is read lazily")
            return nil
        }
        let destination = CIRenderDestination(mtlTexture: texture, commandBuffer: nil)
        destination.colorSpace = RenderEngine.workingColorSpace
        do {
            for band in bands(of: extent) {
                _ = try engine.withContext {
                    try $0.startTask(toRender: image, from: band.rect, to: destination, at: band.origin).waitUntilCompleted()
                }
            }
        } catch {
            log.error("A \(width) × \(height) decode could not be copied to the GPU (\(String(describing: error), privacy: .public)); it is read lazily")
            return nil
        }
        guard let read = CIImage(mtlTexture: texture, options: [.colorSpace: RenderEngine.workingColorSpace]) else {
            return nil
        }
        // Rendered and read unflipped, the texture's coordinates are Core Image's.
        guard extent.origin != .zero else { return read }
        return read.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// The bands that cover `extent`, top first: each one's rectangle in the
    /// image and where it lands in a destination as large as the extent (whose
    /// coordinates, like the image's, count from the bottom).
    static func bands(of extent: CGRect) -> [(rect: CGRect, origin: CGPoint)] {
        let width = Int(extent.width), height = Int(extent.height)
        guard width > 0, height > 0 else { return [] }
        let rows = max(1, bandPixels / width)
        return stride(from: 0, to: height, by: rows).map { top in
            let count = min(rows, height - top)
            let bottom = height - top - count
            return (CGRect(x: extent.minX, y: extent.minY + CGFloat(bottom), width: extent.width, height: CGFloat(count)),
                    CGPoint(x: 0, y: bottom))
        }
    }
}
