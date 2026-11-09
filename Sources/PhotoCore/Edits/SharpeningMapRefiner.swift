import CoreImage
import Foundation

/// Renders the sharpening map from the full-resolution master, once input
/// pauses (docs/features/sharpen-mask-preview/prd.md R6): the map a
/// full-size export's sharpening blends with, scaled to the loupe's zoom.
///
/// The live frames' map (`LiveRenderSession`, content `.sharpeningMap`) is
/// computed on a reduced decode, where resampling has already averaged noise
/// away; this one is not. A separate actor from the live session, so a slow
/// first refinement never holds up the live frames of a drag that starts
/// meanwhile.
///
/// The full-resolution image entering the sharpening step is rendered once
/// to a half-float image and kept while only Sharpening's values change (a
/// Masking drag), so a refinement then costs only the mask. That image is
/// the master's pixel count × 8 bytes (192 MB for 24 MP); `purge` frees it.
public actor SharpeningMapRefiner {
    public let source: URL
    private let generator: PreviewGenerator
    private let colorSpace: CGColorSpace?
    private var input: Input?

    private struct Key: Equatable {
        var settings: RAWDecodeSettings
        /// Everything before the sharpening step.
        var renderHash: String
    }

    private struct Input {
        var key: Key
        var image: CIImage
        var context: RenderContext
        /// The decoded master's size, before turns and crop.
        var maskFrameSize: CGSize
        var machineLearning: MachineLearningNoiseReduction.Outcome
    }

    /// - Parameter colorSpace: The display's color space, so frames need no conversion on screen.
    public init(source: URL, generator: PreviewGenerator, colorSpace: CGColorSpace?) {
        self.source = source
        self.generator = generator
        self.colorSpace = colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
    }

    /// The map of `adjustments` at full resolution, reduced to fit `longEdge`
    /// (the loupe's frame size at fit), or whole when `longEdge` is nil
    /// (zoomed in). Cancellable before and after the expensive stage; an
    /// input rendered before a cancellation is kept for the next request.
    public func render(_ adjustments: Adjustments, longEdge: Int?, content: LiveRenderSession.Content = .sharpeningMap,
                       cancellation: RenderCancellation? = nil) throws -> LiveRenderSession.Frame {
        if content != .sharpeningMap {
            return try renderWhole(adjustments, longEdge: longEdge, content: content, cancellation: cancellation)
        }
        let clock = ContinuousClock()
        let started = clock.now
        guard let renderer = generator.renderer as? AdjustmentRenderer else { throw PreviewGenerator.Failure.renderFailed }
        try cancellation?.check()
        let stack = adjustments.editStack
        let isRaw = SupportedFormats.isRaw(pathExtension: source.pathExtension)
        let settings = isRaw ? renderer.decodeSettings(for: stack) : .none
        // Sharpening and grain come after the map's input: changing them keeps it.
        var before = adjustments
        before.sharpen = Sharpen()
        before.grain = Grain()
        let key = Key(settings: settings, renderHash: before.editStack.renderHash)
        let filled = input?.key != key
        if filled {
            input = nil
            let decoded = try PreviewGenerator.decode(source, longEdge: nil, draft: false, settings: settings)
            let image = renderer.sharpeningInput(adjustments, to: decoded.image, context: decoded.context)
            input = Input(key: key, image: try materialize(image), context: decoded.context,
                          maskFrameSize: decoded.image.extent.size, machineLearning: decoded.machineLearning)
        }
        guard let entering = input else { throw PreviewGenerator.Failure.renderFailed }
        try cancellation?.check()
        var mask = AdjustmentRenderer.sharpeningMask(entering.image, adjustments.sharpen, scale: entering.context.scale)
        if let longEdge { mask = mask.scaledToFit(longEdge: longEdge) }
        guard let rendered = generator.engine.makeCGImage(AdjustmentRenderer.sharpeningMapDisplay(mask),
                                                          colorSpace: colorSpace)
        else { throw PreviewGenerator.Failure.renderFailed }
        let elapsed = (clock.now - started).components
        return LiveRenderSession.Frame(image: DecodedImage(cgImage: rendered), histogram: nil, content: .sharpeningMap,
                                       hasOverlay: false, adjustments: adjustments,
                                       maskFrameSize: entering.maskFrameSize, scale: 1,
                                       seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                                       filledCache: filled, machineLearning: entering.machineLearning)
    }

    /// The fringe map, or the photo itself (a replaced slot's preview while
    /// picking, chromatic-aberration design §4), from the full-resolution
    /// master: rendered whole each time, nothing kept.
    private func renderWhole(_ adjustments: Adjustments, longEdge: Int?, content: LiveRenderSession.Content,
                             cancellation: RenderCancellation?) throws -> LiveRenderSession.Frame {
        let clock = ContinuousClock()
        let started = clock.now
        guard let renderer = generator.renderer as? AdjustmentRenderer else { throw PreviewGenerator.Failure.renderFailed }
        try cancellation?.check()
        let isRaw = SupportedFormats.isRaw(pathExtension: source.pathExtension)
        let settings = isRaw ? renderer.decodeSettings(for: adjustments.editStack) : .none
        let decoded = try PreviewGenerator.decode(source, longEdge: nil, draft: false, settings: settings)
        var image = content == .fringeMap
            ? AdjustmentRenderer.sharpeningMapDisplay(renderer.fringeMap(adjustments, to: decoded.image, context: decoded.context))
            : renderer.render(adjustments, to: decoded.image, context: decoded.context)
        if let longEdge { image = image.scaledToFit(longEdge: longEdge) }
        try cancellation?.check()
        guard let rendered = generator.engine.makeCGImage(image, colorSpace: colorSpace) else {
            throw PreviewGenerator.Failure.renderFailed
        }
        let elapsed = (clock.now - started).components
        return LiveRenderSession.Frame(image: DecodedImage(cgImage: rendered), histogram: nil, content: content,
                                       hasOverlay: false, adjustments: adjustments,
                                       maskFrameSize: decoded.image.extent.size, scale: 1,
                                       seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                                       filledCache: true, machineLearning: decoded.machineLearning)
    }

    /// Frees the full-resolution input (the map was hidden).
    public func purge() {
        input = nil
    }

    /// Whether the full-resolution input is held: for tests.
    var holdsInput: Bool { input != nil }

    /// Renders `image` once to a half-float image in the working space.
    ///
    /// `deferred: false`, so what is kept is pixels. Core Image's default
    /// keeps a large image lazy (measured: a side over 4096 pixels), to be
    /// pulled in tiles when something reads it; when the mask graph read such
    /// an input of a real camera raw, cells of the map came back flipped or
    /// misplaced (docs/features/sharpening-map-tiles/status.md).
    func materialize(_ image: CIImage) throws -> CIImage {
        let extent = image.extent.integral
        guard !extent.isInfinite, !extent.isEmpty,
              let rendered = generator.engine.withContext({
                  $0.createCGImage(image, from: extent, format: .RGBAh, colorSpace: RenderEngine.workingColorSpace,
                                   deferred: false)
              })
        else { throw PreviewGenerator.Failure.renderFailed }
        return CIImage(cgImage: rendered).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }
}
