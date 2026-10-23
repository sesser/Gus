import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Metal

/// The single Core Image context everything renders through.
///
/// Metal-backed, working in extended linear Rec. 2020 at half float so that edits
/// operate on linear light with headroom and a gamut wide enough for camera
/// colors. Output is converted to Display P3 when encoded or turned into a
/// `CGImage`; Core Animation color-matches that to the actual display.
public final class RenderEngine: @unchecked Sendable {
    // @unchecked: CIContext is documented as thread-safe and is immutable here.

    public static let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    public static let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

    public let context: CIContext
    public let device: (any MTLDevice)?

    public init(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) {
        self.device = device
        let options: [CIContextOption: Any] = [
            .workingColorSpace: Self.workingColorSpace,
            .workingFormat: CIFormat.RGBAh,
            // Previews are rendered once each; caching intermediates only costs memory.
            .cacheIntermediates: false,
            .name: "preview-pipeline",
        ]
        if let device {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    public var isMetalBacked: Bool { device != nil }

    /// Renders to an 8-bit Display P3 `CGImage`.
    public func makeCGImage(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent.integral, format: .RGBA8,
                              colorSpace: Self.outputColorSpace)
    }

    /// Renders and encodes as JPEG with an embedded Display P3 profile.
    public func jpegData(_ image: CIImage, quality: Double) -> Data? {
        let key = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return context.jpegRepresentation(of: image, colorSpace: Self.outputColorSpace, options: [key: quality])
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
