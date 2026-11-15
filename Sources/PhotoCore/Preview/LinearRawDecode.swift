import CoreImage
import os

/// Renders the system RAW decoder's image of a linear DNG whole, once, so
/// that nothing downstream reads the decoder itself (issue #181).
///
/// **The fault this works around** (macOS 27.2; Lightroom HDR merges: a
/// half-float linear raw, JPEG XL compressed in tiles;
/// docs/features/hdr-dng-render-nondeterministic/status.md). When Core Image
/// splits a large render into parts and the graph reads the decoder's image
/// in more than one program (sharpening with Detail under 100 does: the
/// unsharp mask, its blur, the neighborhood's minimum and maximum), now and
/// then one part comes out slightly different: in the file of the issue a
/// quarter of the frame, darker by about 0.3% with different fine texture.
/// Which render gets it is timing: about one process in three, and one
/// render in four when several run at once, as previews and exports do; the
/// HDR rendition too. What was ruled out by measurement: the decoder's own
/// image is the same whatever region is asked for and when regions are
/// asked for at once; the same graph over a bitmap, or over a tiled image
/// provider, never varied; camera raws and an uncompressed 16-bit linear
/// DNG never varied; with Core Image dumping its intermediates (which
/// serializes the render) the fault did not show. So the fault is inside
/// Core Image's rendering of the decoder's lazy image, and not ours to fix.
///
/// **The workaround.** The decoder's image is rendered whole into a
/// half-float bitmap in the working space, and the rest of the graph reads
/// that: a decode read whole, by one program, was the same every time. Half
/// float is the precision the loupe keeps a decode in already
/// (`LiveRenderSession`, `LiveRegionRenderer`). Measured on the file of the
/// issue: unedited and white-balance-only renders are unchanged bit for bit;
/// other edits change slightly (a mean of 1 to 38 levels of 65535 over the
/// stacks measured, a dozen pixels up to 4750 with Sharpening at 60), each
/// now always the same.
///
/// **What it costs.** One more render of the whole decode, and 8 bytes per
/// pixel held while the image is in use: for a 16-megapixel merge about
/// 0.03 s and 130 MB, for linear DNGs only. They are decoded at full size
/// already (`DNGLayout.hasReducedLinearRaw`), so no render got larger.
enum LinearRawDecode {
    /// One context: linear DNGs are rare, and one at a time bounds the
    /// memory their bitmaps take while they are made.
    static let engine = RenderEngine(contextCount: 1, name: "linear-raw-decode")

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "decode")

    /// `image` rendered into a half-float bitmap, as an image over the same
    /// extent backed by it (`CIImage.cgImage` is that bitmap when the
    /// extent starts at the origin, as a decode's does). Nil, logged, when
    /// the extent is not a finite whole-pixel rectangle or the render fails.
    static func rendered(_ image: CIImage) -> CIImage? {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite, extent == extent.integral,
              let bitmap = engine.withContext({
                  $0.createCGImage(image, from: extent, format: .RGBAh, colorSpace: RenderEngine.workingColorSpace)
              })
        else {
            log.error("A linear DNG's decode could not be rendered whole (extent \(String(describing: extent), privacy: .public))")
            return nil
        }
        let whole = CIImage(cgImage: bitmap)
        guard extent.origin != .zero else { return whole }
        return whole.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }
}
