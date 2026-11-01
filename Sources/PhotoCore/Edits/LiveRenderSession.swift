import CoreImage
import Foundation

/// Renders one master again and again while its adjustments change.
///
/// The decoded master (after the RAW decoder's settings) is rendered once into a
/// half-float image in the working space and reused for every frame, so a frame
/// only costs the adjustments. Changing a decode setting (white balance, look or
/// noise reduction of a RAW file) decodes again, at half size in draft mode while
/// a control is being dragged.
public actor LiveRenderSession {
    /// One rendered frame, ready for a layer.
    public struct Frame: Sendable {
        public let image: DecodedImage
        /// Nil while a mask overlay is drawn over the frame.
        public let histogram: Histogram?
        public let adjustments: Adjustments
        /// The mask frame's size in pixels (the decoded image before turns,
        /// straightening and crop): its proportions place masks on screen.
        public let maskFrameSize: CGSize
    }

    public let source: URL
    public let longEdge: Int
    private let generator: PreviewGenerator
    private let colorSpace: CGColorSpace?
    private var bases: [BaseKey: Base] = [:]
    private var baseOrder: [BaseKey] = []
    /// The master's size, read once a crop needs it.
    private var nativeSize: CGSize??

    private struct BaseKey: Hashable {
        var settings: RAWDecodeSettings
        var draft: Bool
        /// Long edge of the decode: larger than the frames' when cropped.
        var longEdge: Int
    }

    private struct Base {
        var image: CGImage
        var context: RenderContext
    }

    /// - Parameters:
    ///   - longEdge: Size of the frames (the loupe's fit size).
    ///   - colorSpace: The display's color space, so frames need no conversion on screen.
    public init(source: URL, generator: PreviewGenerator, longEdge: Int = PreviewTier.preview.longEdge,
                colorSpace: CGColorSpace?) {
        self.source = source
        self.generator = generator
        self.longEdge = longEdge
        self.colorSpace = colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
    }

    /// Renders `adjustments`. `interactive` allows a faster, rougher decode when a
    /// RAW decode setting changed.
    public func render(_ adjustments: Adjustments, interactive: Bool = false, overlayMask: UUID? = nil) throws -> Frame {
        let stack = adjustments.editStack
        let renderer = generator.renderer
        let isRaw = SupportedFormats.isRaw(pathExtension: source.pathExtension)
        let settings = isRaw ? renderer.decodeSettings(for: stack) : .none
        let base = try self.base(for: BaseKey(settings: settings, draft: interactive,
                                              longEdge: decodeLongEdge(renderer.geometry(for: stack))))
        let source = CIImage(cgImage: base.image)
        var image = try renderer.apply(stack, to: source, context: base.context)
        var overlaid = false
        if let overlayMask, let adjusting = renderer as? AdjustmentRenderer,
           let alpha = adjusting.maskAlpha(adjustments, id: overlayMask, to: source, context: base.context) {
            // Red at half the mask's alpha over the photo.
            let red = CIImage(color: CIColor(red: 1, green: 0.1, blue: 0.1)).cropped(to: image.extent)
            let blend = CIFilter(name: "CIBlendWithMask", parameters: [
                kCIInputImageKey: red, kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: MaskRenderer.scaled(alpha, by: 0.5),
            ])
            image = blend?.outputImage?.cropped(to: image.extent) ?? image
            overlaid = true
        }
        image = image.scaledToFit(longEdge: longEdge)
        guard let rendered = generator.engine.makeCGImage(image, colorSpace: colorSpace) else {
            throw PreviewGenerator.Failure.renderFailed
        }
        return Frame(image: DecodedImage(cgImage: rendered), histogram: overlaid ? nil : Histogram(image: rendered),
                     adjustments: adjustments, maskFrameSize: source.extent.size)
    }

    /// The frames' long edge, enlarged by what the crop leaves out (in steps,
    /// so small changes to a crop reuse the base).
    private func decodeLongEdge(_ crop: Crop) -> Int {
        guard !crop.isIdentity else { return longEdge }
        if nativeSize == nil { nativeSize = .some(PreviewGenerator.nativeSize(source)) }
        guard let size = nativeSize ?? nil else { return longEdge }
        let zoom = (crop.sourceZoom(sourceSize: size) * 4).rounded(.up) / 4
        return min(Int(Double(longEdge) * zoom), Int(max(size.width, size.height)))
    }

    /// Renders the base for `key`, or reuses one: a full decode serves a draft
    /// request too.
    private func base(for key: BaseKey) throws -> Base {
        if let base = bases[key] { return touch(key, base) }
        if key.draft, let full = bases[BaseKey(settings: key.settings, draft: false, longEdge: key.longEdge)] {
            return full
        }
        let size = key.draft ? key.longEdge / 2 : key.longEdge
        let decoded = try PreviewGenerator.decode(source, longEdge: size, draft: key.draft, settings: key.settings)
        let extent = decoded.image.extent.integral
        guard !extent.isInfinite,
              let image = generator.engine.withContext({
                  $0.createCGImage(decoded.image, from: extent, format: .RGBAh, colorSpace: RenderEngine.workingColorSpace)
              })
        else { throw PreviewGenerator.Failure.renderFailed }
        return touch(key, Base(image: image, context: decoded.context))
    }

    /// Keeps the three most recently used bases (current settings, the original,
    /// and one draft).
    private func touch(_ key: BaseKey, _ base: Base) -> Base {
        bases[key] = base
        baseOrder.removeAll { $0 == key }
        baseOrder.append(key)
        while baseOrder.count > 3 {
            bases[baseOrder.removeFirst()] = nil
        }
        return base
    }
}
