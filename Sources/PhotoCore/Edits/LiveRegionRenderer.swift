import CoreImage
import Foundation
import Metal

/// Renders the visible part of a photo at full resolution while its
/// adjustments change: at 100% and above, the loupe's frames are made of the
/// photo's own pixels with the current values applied, not an enlarged
/// whole-photo frame (docs/features/viewport-render-1to1/prd.md).
///
/// The decoded master is rendered once, for one set of RAW decode settings,
/// into a GPU-private half-float texture and every frame reads it directly.
/// Reading a half-float `CGImage` instead would cost several times more per
/// frame: its pixels are uploaded for each render and, with `createCGImage`'s
/// deferred rendering (its default), even decoded again (`PROFILING.md`,
/// viewport-render-1to1).
///
/// Every frame renders the whole adjustment graph, for the whole photo, and
/// Core Image evaluates only the region asked for, so whatever depends on the
/// whole photo (the estimates of local tone and dehaze, masks, Color Alignment,
/// the vignette, grain) comes out as in a full-resolution render.
///
/// A separate actor from `LiveRenderSession`, whose whole-photo frames keep
/// flowing while this one decodes.
public actor LiveRegionRenderer {
    public struct Frame: Sendable {
        public let image: DecodedImage
        public let adjustments: Adjustments
        /// The part of the output the frame shows, in output pixels, origin
        /// at the top left.
        public let region: CGRect
        /// The output frame's size in pixels (after turns, straightening and crop).
        public let outputSize: CGSize
        /// The mask whose overlay is drawn over the photo, nil without one.
        public let overlayMask: UUID?
        public var hasOverlay: Bool { overlayMask != nil }
        public let seconds: Double
        public let machineLearning: MachineLearningNoiseReduction.Outcome
    }

    public enum Failure: Error, Equatable {
        /// `prepare` has not decoded these values' RAW settings yet.
        case notReady
        /// The master doesn't fit one GPU texture (`maximumTextureDimension`).
        case tooLarge
        case renderFailed
    }

    /// Apple GPUs' largest texture dimension (MTLGPUFamily.apple3 and later).
    static let maximumTextureDimension = 16384

    public let source: URL
    private let generator: PreviewGenerator
    private let colorSpace: CGColorSpace?
    private var base: Base?
    private var decoder: SystemRAWDecoder.Memo
    /// A decode under way: reentrant calls join it instead of starting another.
    private var decoding: (settings: RAWDecodeSettings, task: Task<Base, Error>)?

    /// One decoded master at full resolution, in a GPU texture.
    struct Base: @unchecked Sendable {
        // @unchecked: CIImage is an immutable recipe, and the texture is only
        // read after the render into it has finished.
        var settings: RAWDecodeSettings
        var image: CIImage
        var context: RenderContext
        /// Keeps the texture the image reads for as long as it is shown.
        var texture: any MTLTexture
        var machineLearning: MachineLearningNoiseReduction.Outcome
    }

    /// - Parameters:
    ///   - colorSpace: The display's color space, so frames need no conversion on screen.
    ///   - systemDecodesRaw: `SystemRAWDecoder.reads(source)` when the caller knows it; else the file is asked once.
    public init(source: URL, generator: PreviewGenerator, colorSpace: CGColorSpace?, systemDecodesRaw: Bool? = nil) {
        self.source = source
        self.generator = generator
        self.colorSpace = colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        self.decoder = SystemRAWDecoder.Memo(source, known: systemDecodesRaw)
    }

    /// The decode settings that reach this master's decode: none for a file
    /// the system RAW decoder does not read (a raw LibRaw decodes among
    /// them), so no change of values asks for the same decode again.
    private func settings(for values: Adjustments) -> RAWDecodeSettings {
        decoder.decodeSettings(generator.renderer.decodeSettings(for: values.editStack))
    }

    /// Whether `render` can draw `values` now, without a decode.
    public func isReady(for values: Adjustments) -> Bool {
        base?.settings == settings(for: values)
    }

    /// Whether a decode for `values`' settings is under way, or has just
    /// landed (the frame that asks may have started before it did).
    public func isDecodingOrHolding(_ values: Adjustments) -> Bool {
        let wanted = settings(for: values)
        return decoding?.settings == wanted || base?.settings == wanted
    }

    /// The decode settings of the last moving frame `shouldDecode` was asked about.
    private var lastMovingSettings: RAWDecodeSettings?

    /// Whether a frame of a change under way, for settings the texture doesn't
    /// hold, should start a decode now: when its settings are the same as the
    /// previous moving frame's. Controls that change the decode with every
    /// frame (White Balance, Profile, Noise Reduction: R4) never settle while
    /// they move, so they wait for the pause. Everything else (Highlights
    /// below 0, Exposure crossing 0, the first mask) changes the settings once,
    /// so one decode lands and the rest of the drag is sharp (R1, R2).
    public func shouldDecode(whileMoving values: Adjustments) -> Bool {
        let wanted = settings(for: values)
        defer { lastMovingSettings = wanted }
        guard base?.settings != wanted, decoding?.settings != wanted else { return false }
        return lastMovingSettings == wanted
    }

    /// Decodes the master at full resolution for `values`' RAW settings and
    /// renders it to a texture: the slow step, a raw decode with new settings
    /// or a machine learning one. Runs off the actor, so `isReady` and
    /// `render` keep answering meanwhile (not ready, for any other settings:
    /// the texture held for the previous ones is released first, so only one
    /// is ever held). A new set of settings replaces the decode under way,
    /// whose result is then dropped.
    public func prepare(_ values: Adjustments, cancellation: RenderCancellation? = nil) async throws {
        let wanted = settings(for: values)
        if base?.settings == wanted { return }
        try cancellation?.check()
        let task: Task<Base, Error>
        if let decoding, decoding.settings == wanted {
            task = decoding.task
        } else {
            base = nil
            let source = source
            let generator = generator
            task = Task.detached(priority: .userInitiated) {
                try Self.decode(source, settings: wanted, generator: generator, cancellation: cancellation)
            }
            decoding = (wanted, task)
        }
        do {
            let made = try await task.value
            // A newer request took over while this one decoded.
            guard decoding?.settings == wanted else { return }
            decoding = nil
            base = made
        } catch {
            if decoding?.settings == wanted { decoding = nil }
            throw error
        }
    }

    private static func decode(_ source: URL, settings: RAWDecodeSettings, generator: PreviewGenerator,
                               cancellation: RenderCancellation?) throws -> Base {
        let decoded = try PreviewGenerator.decode(source, longEdge: nil, draft: false, settings: settings)
        try cancellation?.check()
        let extent = decoded.image.extent.integral
        guard extent.width <= Double(Self.maximumTextureDimension), extent.height <= Double(Self.maximumTextureDimension) else {
            throw Failure.tooLarge
        }
        let (image, texture) = try materialize(decoded.image, extent: extent, generator: generator)
        return Base(settings: settings, image: image, context: decoded.context, texture: texture,
                    machineLearning: decoded.machineLearning)
    }

    /// Renders `image` over `extent` into a GPU-private half-float texture
    /// and returns an image that reads it directly.
    private static func materialize(_ image: CIImage, extent: CGRect,
                                    generator: PreviewGenerator) throws -> (CIImage, any MTLTexture) {
        guard let device = generator.engine.device else { throw PreviewGenerator.Failure.renderFailed }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: Int(extent.width),
                                                                  height: Int(extent.height), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Failure.renderFailed
        }
        let destination = CIRenderDestination(mtlTexture: texture, commandBuffer: nil)
        destination.colorSpace = RenderEngine.workingColorSpace
        destination.isFlipped = true
        try generator.engine.withContext {
            _ = try $0.startTask(toRender: image, from: extent, to: destination, at: .zero).waitUntilCompleted()
        }
        guard let read = CIImage(mtlTexture: texture, options: [.colorSpace: RenderEngine.workingColorSpace]) else {
            throw Failure.renderFailed
        }
        // A texture's first row is its top; Core Image's y axis points up.
        let flipped = read.transformed(by: CGAffineTransform(scaleX: 1, y: -1)
            .translatedBy(x: 0, y: -read.extent.height)
            .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY)))
        return (flipped, texture)
    }

    /// Frees the full-resolution texture (the loupe left 100%, or the photo changed).
    public func purge() {
        base = nil
        decoding = nil
    }

    /// Whether the full-resolution texture is held: for tests and the debug script.
    public var isHoldingBase: Bool { base != nil }

    /// Bytes held by the full-resolution texture: for tests and the benchmark.
    public var baseByteCount: Int {
        guard let base else { return 0 }
        return base.texture.width * base.texture.height * 8
    }

    /// The adjustments of `values` over the region `unit` of the output
    /// (unit coordinates of the output frame, origin at the top left).
    ///
    /// Throws `Failure.notReady` when `prepare` has not decoded these values'
    /// RAW settings. Cancellation is checked before the render; work already
    /// on the GPU finishes.
    public func render(_ values: Adjustments, unit: CGRect, overlayMask: UUID? = nil,
                       cancellation: RenderCancellation? = nil) throws -> Frame {
        let clock = ContinuousClock()
        let started = clock.now
        try cancellation?.check()
        guard let base, base.settings == settings(for: values) else { throw Failure.notReady }
        var image = try generator.renderer.apply(values.editStack, to: base.image, context: base.context)
        let extent = image.extent.integral
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1 else { throw Failure.renderFailed }
        var overlaid: UUID?
        if let overlayMask, let adjusting = generator.renderer as? AdjustmentRenderer,
           let alpha = adjusting.maskAlpha(values, id: overlayMask, to: base.image, context: base.context) {
            image = LiveRenderSession.withOverlay(image, alpha: alpha)
            overlaid = overlayMask
        }
        let region = Self.region(of: unit, in: extent.size)
        // Core Image's y axis points up.
        let rect = CGRect(x: extent.minX + region.minX, y: extent.minY + extent.height - region.maxY,
                          width: region.width, height: region.height)
        try cancellation?.check()
        let space = colorSpace ?? RenderEngine.outputColorSpace
        guard let rendered = generator.engine.withContext({
            $0.createCGImage(image, from: rect, format: .BGRA8, colorSpace: space, deferred: false)
        }) else { throw Failure.renderFailed }
        let elapsed = (clock.now - started).components
        return Frame(image: DecodedImage(cgImage: rendered), adjustments: values, region: region, outputSize: extent.size,
                     overlayMask: overlaid, seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                     machineLearning: base.machineLearning)
    }

    /// `unit` in whole output pixels, inside the frame: rounded outward so
    /// the region covers everything asked for.
    static func region(of unit: CGRect, in size: CGSize) -> CGRect {
        let left = max(0, floor(unit.minX * size.width))
        let top = max(0, floor(unit.minY * size.height))
        let right = min(size.width, ceil(unit.maxX * size.width))
        let bottom = min(size.height, ceil(unit.maxY * size.height))
        return CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }
}

/// What the editor and the loupe decide about live frames at 100% and above,
/// kept apart so tests can reach it.
public enum LiveFrameRules {
    /// A frame on screen already shows `values` with `overlay`: comparing
    /// which mask's overlay, not only whether there is one.
    public static func isCurrent(frameValues: Adjustments?, frameOverlay: UUID?, wanted values: Adjustments,
                                 overlay: UUID?) -> Bool {
        frameValues == values && frameOverlay == overlay
    }

    /// A whole frame goes on the base under a tile only when it shows the
    /// tile's values (a pause's or a save's frame). An older whole frame must
    /// not stand in for the tile, and a tile that can't be current any more is
    /// taken down by the editor, not here.
    public static func wholeFrameGoesOnBase(wholeValues: Adjustments, tileValues: Adjustments?) -> Bool {
        tileValues == nil || tileValues == wholeValues
    }

    /// A non-interactive frame of the saved values, with nothing changing and
    /// nothing drawn over the photo, is followed by the full rendition: the
    /// decode for the next drag waits until that has landed, so it doesn't
    /// compete for the GPU with the rendition's first draw on the main thread.
    public static func decodeWaitsForFullRendition(valuesAreSaved: Bool, isChanging: Bool, hasOverlay: Bool,
                                                   showsOriginal: Bool, isPreviewing: Bool) -> Bool {
        valuesAreSaved && !isChanging && !hasOverlay && !showsOriginal && !isPreviewing
    }

    /// Nearest-neighbor enlargement is for the photo's real pixels above
    /// 100% (design §2.2), and for what keeps its shipped filtering: the maps
    /// and the replaced fringe slot's preview (A4).
    public static func usesNearestFiltering(magnification: Double, showsRealPixels: Bool,
                                            keepsShippedFiltering: Bool) -> Bool {
        magnification >= 1 && (showsRealPixels || keepsShippedFiltering)
    }
}
