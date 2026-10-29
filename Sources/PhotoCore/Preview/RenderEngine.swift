import Accelerate
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
    /// HDR renditions keep values above 1.0, SDR white, in extended linear Display P3.
    public static let hdrColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    /// Renditions whose brightest component stays below this are treated as SDR.
    public static let minimumHDRHeadroom: Float = 1.05

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

    /// Renders to an 8-bit `CGImage` in `colorSpace` (Display P3 by default). Pass
    /// the screen's color space for images headed straight to a layer, so Core
    /// Animation does not have to convert them on the main thread.
    public func makeCGImage(_ image: CIImage, colorSpace: CGColorSpace? = nil) -> CGImage? {
        let space = colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? Self.outputColorSpace
        return context.createCGImage(image, from: image.extent.integral, format: .BGRA8, colorSpace: space)
    }

    /// Renders to an RGBA `CGImage` with 8 or 16 bits per component in
    /// `colorSpace`, for writing to a file.
    public func makeCGImage(_ image: CIImage, colorSpace: CGColorSpace, bitsPerComponent: Int) -> CGImage? {
        context.createCGImage(image, from: image.extent.integral, format: bitsPerComponent == 16 ? .RGBA16 : .RGBA8,
                              colorSpace: colorSpace)
    }

    /// Renders to a half-float `CGImage` in extended linear Display P3, tagged with
    /// its content headroom: the brightest component relative to SDR white, which
    /// Core Animation needs to tone map the image to what the display can show.
    public func makeHDRCGImage(_ image: CIImage) -> CGImage? {
        guard let rendered = context.createCGImage(image, from: image.extent.integral, format: .RGBAh,
                                                   colorSpace: Self.hdrColorSpace),
              let headroom = Self.maximumComponent(of: rendered)
        else { return nil }
        return CGImageCreateCopyWithContentHeadroom(max(headroom, 1), rendered) ?? rendered
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
