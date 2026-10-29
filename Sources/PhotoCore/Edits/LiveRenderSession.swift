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
        public let histogram: Histogram?
        public let adjustments: Adjustments
    }

    public let source: URL
    public let longEdge: Int
    private let generator: PreviewGenerator
    private let colorSpace: CGColorSpace?
    private var bases: [BaseKey: Base] = [:]
    private var baseOrder: [BaseKey] = []

    private struct BaseKey: Hashable {
        var settings: RAWDecodeSettings
        var draft: Bool
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
    public func render(_ adjustments: Adjustments, interactive: Bool = false) throws -> Frame {
        let stack = adjustments.editStack
        let renderer = generator.renderer
        let isRaw = SupportedFormats.isRaw(pathExtension: source.pathExtension)
        let settings = isRaw ? renderer.decodeSettings(for: stack) : .none
        let base = try self.base(for: BaseKey(settings: settings, draft: interactive))
        var image = try renderer.apply(stack, to: CIImage(cgImage: base.image), context: base.context)
        image = image.scaledToFit(longEdge: longEdge)
        guard let rendered = generator.engine.makeCGImage(image, colorSpace: colorSpace) else {
            throw PreviewGenerator.Failure.renderFailed
        }
        return Frame(image: DecodedImage(cgImage: rendered), histogram: Histogram(image: rendered),
                     adjustments: adjustments)
    }

    /// Renders the base for `key`, or reuses one: a full decode serves a draft
    /// request too.
    private func base(for key: BaseKey) throws -> Base {
        if let base = bases[key] { return touch(key, base) }
        if key.draft, let full = bases[BaseKey(settings: key.settings, draft: false)] {
            return full
        }
        let size = key.draft ? longEdge / 2 : longEdge
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
