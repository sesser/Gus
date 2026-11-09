import CoreImage
import Foundation
import Synchronization

/// Renders one master again and again while its adjustments change.
///
/// The decoded master (after the RAW decoder's settings) is rendered once into a
/// half-float image in the working space and reused for every frame, so a frame
/// only costs the adjustments. Changing a decode setting (white balance, look or
/// noise reduction of a RAW file) decodes again, at half size in draft mode while
/// a control is being dragged.
public actor LiveRenderSession {
    /// What a frame shows.
    public enum Content: Sendable, Equatable {
        case photo
        /// The sharpening map in place of the photo (`AdjustmentRenderer.sharpeningMask`).
        case sharpeningMap
        /// The fringe map in place of the photo (`AdjustmentRenderer.fringeMap`).
        case fringeMap

        /// One of the maps, shown in place of the photo.
        public var isMap: Bool { self != .photo }
    }

    /// One rendered frame, ready for a layer.
    public struct Frame: Sendable {
        public let image: DecodedImage
        /// Nil while a mask overlay is drawn over the frame, and for the maps.
        public let histogram: Histogram?
        public let content: Content
        /// The mask overlay is drawn over the photo.
        public let hasOverlay: Bool
        public let adjustments: Adjustments
        /// The mask frame's size in pixels (the decoded image before turns,
        /// straightening and crop): its proportions place masks on screen.
        public let maskFrameSize: CGSize
        /// 1 for a full frame; ½ or ¼ for a draft rendered smaller while dragging.
        public let scale: Double
        /// From the start of the render to the histogram: GPU work and read-back included.
        public let seconds: Double
        /// The render stored something in the stage cache (a slower frame, once).
        public let filledCache: Bool
        /// What the decode did with the values' machine learning request:
        /// the loupe's not-applied state follows the frame on screen.
        public let machineLearning: MachineLearningNoiseReduction.Outcome

        /// The frame shows the photo as it is (no overlay, not the map): only
        /// such a frame may give the histogram or become a cached preview.
        public var showsPhoto: Bool { content == .photo && !hasOverlay }
    }

    /// An interactive frame slower than this (seconds) makes the next one a
    /// smaller draft. Frames that filled the stage cache do not count.
    public static let draftDropThreshold = 0.1
    /// A draft steps back up when the next larger frame (four times the
    /// pixels) would take less than this (seconds): lower than the drop
    /// threshold, so the level does not flip every frame.
    public static let draftRaiseThreshold = 0.06
    /// Draft scales, from full size down.
    public static let draftScales = [1.0, 0.5, 0.25]
    /// The scale interactive frames render at now (`nextDraftLevel`).
    public private(set) var draftLevel = 0
    private var draftBases: [String: (image: CIImage, context: RenderContext)] = [:]
    private var stageCaches: [Int: StageCache] = [:]
    private var nextSerial = 0
    /// The render under way stored something in the stage cache.
    private var filledCache = false

    public let source: URL
    public nonisolated let longEdge: Int
    private let generator: PreviewGenerator
    private let colorSpace: CGColorSpace?
    private var bases: [BaseKey: Base] = [:]
    private var baseOrder: [BaseKey] = []
    /// The master's size, read once a crop needs it.
    private var nativeSize: CGSize??
    /// Keeps what a drag of a mask control does not change (`StageCache`);
    /// false renders every frame whole, for comparison.
    public let cachesStages: Bool
    private var stages = StageCache()

    private struct BaseKey: Hashable {
        var settings: RAWDecodeSettings
        var draft: Bool
        /// Long edge of the decode: larger than the frames' when cropped.
        var longEdge: Int
    }

    private struct Base {
        var image: CGImage
        var context: RenderContext
        /// Distinguishes decodes, so the stage caches never mix two.
        var serial = 0
        var machineLearning = MachineLearningNoiseReduction.Outcome.notRequested
        var longEdge: Int { max(image.width, image.height) }
    }

    // MARK: Stages

    /// What the last frames' masks had in common with the next: the image
    /// entering the mask step, the whole-frame estimates, and the result of
    /// the masks before the one being changed, each rendered once to a
    /// half-float image (one rounding, as an intermediate of Core Image's own).
    private struct StageCache {
        /// The base and the global modules before the masks.
        var upstreamKey: String?
        var selection: CIImage?
        var estimatesKey: String?
        var estimates: LocalEstimates?
        /// The result after the masks `prefix.masks`, the ones before the mask being changed.
        var prefix: (masks: [Mask], image: CIImage, sharpening: [MaskSharpening])?
        var lastMasks: [Mask] = []
    }

    /// `adjustments` through `AdjustmentRenderer`'s stages, reusing `stages`.
    ///
    /// With `prefill`, only fills the cache for a coming drag of the mask at
    /// that index of the rendered masks, and returns once it is filled.
    ///
    /// With `untilSharpening`, returns the image entering the sharpening
    /// step instead of the frame (for the sharpening map).
    private func staged(_ adjustments: Adjustments, renderer: AdjustmentRenderer, source: CIImage,
                        context: RenderContext, baseKey: String, cancellation: RenderCancellation?,
                        prefill: Int? = nil, untilSharpening: Bool = false) throws -> CIImage {
        let values = adjustments.effective
        let masks = values.local.renderedMasks
        guard !values.isDefault, !masks.isEmpty else {
            stages = StageCache()
            return untilSharpening ? renderer.sharpeningInput(values, to: source, context: context)
                                   : renderer.render(values, to: source, context: context)
        }
        let crop = AdjustmentRenderer.crop(values, context: context)
        var upstream = values
        upstream.local = LocalAdjustments()
        upstream.lookTable = LookTable()
        upstream.vignette = Vignette()
        upstream.noiseReduction = NoiseReduction()
        upstream.sharpen = Sharpen()
        upstream.grain = Grain()
        let upstreamKey = "\(baseKey)|\(context.scale)|\(upstream.editStack.renderHash)"
        if stages.upstreamKey != upstreamKey {
            stages = StageCache()
            stages.upstreamKey = upstreamKey
        }
        let selection: CIImage
        if let cached = stages.selection {
            selection = cached
        } else {
            selection = try materialize(renderer.upstream(values, to: source, crop: crop, context: context))
            stages.selection = selection
        }
        try cancellation?.check()

        let wanted = renderer.localEstimates(masks, over: selection)
        let estimatesKey = "\(wanted.luminance != nil)|\(wanted.haze != nil)"
        let estimates: LocalEstimates
        if stages.estimatesKey == estimatesKey, let cached = stages.estimates {
            estimates = cached
        } else {
            var made = LocalEstimates()
            if let luminance = wanted.luminance { made.luminance = try materialize(luminance) }
            if let haze = wanted.haze {
                // The airlight is one value over an infinite image: render its one pixel.
                let airlight = try materialize(haze.airlight.cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
                made.haze = (try materialize(haze.map.cropped(to: selection.extent)), airlight.clampedToExtent())
            }
            estimates = made
            stages.estimates = made
            stages.estimatesKey = estimatesKey
        }
        try cancellation?.check()

        // The first mask that differs from the last frame's: the one being changed.
        let changed = prefill ?? masks.indices.first { $0 >= stages.lastMasks.count || masks[$0] != stages.lastMasks[$0] }
            ?? masks.count
        stages.lastMasks = masks
        var start = 0
        var image = selection
        var sharpening: [MaskSharpening] = []
        if let prefix = stages.prefix, prefix.masks.count <= masks.count,
           masks.prefix(prefix.masks.count).elementsEqual(prefix.masks) {
            (image, sharpening, start) = (prefix.image, prefix.sharpening, prefix.masks.count)
        }
        if let prefill, prefill <= start { return image }
        for index in start..<masks.count {
            if index == changed, index > start {
                // Keep the masks before the one being changed for the next frames.
                image = try materialize(image)
                stages.prefix = (Array(masks.prefix(index)), image, sharpening)
            }
            if let prefill, index == prefill { return image }
            let step = renderer.applyMask(masks[index], to: image, selection: selection, estimates: estimates,
                                          maskFrame: source.extent, crop: crop, context: context)
            image = step.image
            sharpening += step.sharpening
            try cancellation?.check()
        }
        if untilSharpening { return renderer.beforeSharpening(values, image, context: context) }
        return renderer.downstream(values, image, sharpening: sharpening, context: context)
    }

    /// Renders `image` once to a half-float image in the working space.
    private func materialize(_ image: CIImage) throws -> CIImage {
        filledCache = true
        let extent = image.extent.integral
        guard !extent.isInfinite, !extent.isEmpty,
              let rendered = generator.engine.withContext({
                  $0.createCGImage(image, from: extent, format: .RGBAh, colorSpace: RenderEngine.workingColorSpace)
              })
        else { throw PreviewGenerator.Failure.renderFailed }
        return CIImage(cgImage: rendered).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// - Parameters:
    ///   - longEdge: Size of the frames (the loupe's fit size).
    ///   - colorSpace: The display's color space, so frames need no conversion on screen.
    public init(source: URL, generator: PreviewGenerator, longEdge: Int = PreviewTier.preview.longEdge,
                colorSpace: CGColorSpace?, cachesStages: Bool = true) {
        self.cachesStages = cachesStages
        self.source = source
        self.generator = generator
        self.longEdge = longEdge
        self.colorSpace = colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
    }

    /// Renders `adjustments`. `interactive` allows a faster, rougher decode when a
    /// RAW decode setting changed.
    ///
    /// Interactive frames may be drafts (`draftLevel`): the same render over a
    /// reduced copy of the decoded master, with `RenderContext.scale` reduced
    /// to match, so radii keep their size relative to the photo. Other frames
    /// are always full size.
    ///
    /// With `content` `.sharpeningMap` the frame shows the sharpening map of
    /// `adjustments` at the frame's scale (an estimate of the full-resolution
    /// map, `SharpeningMapRefiner`), with no overlay and no histogram.
    public func render(_ adjustments: Adjustments, interactive: Bool = false, allowsDrafts: Bool = true,
                       overlayMask: UUID? = nil, content: Content = .photo,
                       cancellation: RenderCancellation? = nil) throws -> Frame {
        let clock = ContinuousClock()
        let started = clock.now
        let drafting = interactive && allowsDrafts
        filledCache = false
        let level = drafting ? draftLevel : 0
        let factor = Self.draftScales[level]
        let stack = adjustments.editStack
        let renderer = generator.renderer
        let isRaw = SupportedFormats.isRaw(pathExtension: source.pathExtension)
        let settings = isRaw ? renderer.decodeSettings(for: stack) : .none
        let base = try self.base(for: BaseKey(settings: settings, draft: interactive,
                                              longEdge: decodeLongEdge(renderer.geometry(for: stack))))
        // The decode itself identifies what the stages start from: a draft
        // decode request served by the full decode shares its caches.
        let baseKey = "\(base.serial)"
        var source = CIImage(cgImage: base.image)
        var context = base.context
        if level > 0 {
            (source, context) = try draft(of: base, key: baseKey, factor: factor)
        }
        var image: CIImage
        if content == .fringeMap {
            // The fringe map needs only the decoded image (chromatic-aberration design §6).
            guard let adjusting = renderer as? AdjustmentRenderer else { throw PreviewGenerator.Failure.renderFailed }
            image = AdjustmentRenderer.sharpeningMapDisplay(adjusting.fringeMap(adjustments, to: source, context: context))
        } else {
            image = try linear(adjustments, source: source, context: context, level: level, baseKey: baseKey,
                               cancellation: cancellation, untilSharpening: content == .sharpeningMap)
        }
        try cancellation?.check()
        if content == .sharpeningMap {
            // The stored Sharpening values, also while the group is turned off (design §11).
            image = AdjustmentRenderer.sharpeningMapDisplay(
                AdjustmentRenderer.sharpeningMask(image, adjustments.sharpen, scale: context.scale))
        }
        var overlaid = false
        if content == .photo, let overlayMask, let adjusting = renderer as? AdjustmentRenderer,
           let alpha = adjusting.maskAlpha(adjustments, id: overlayMask, to: source, context: context) {
            image = Self.withOverlay(image, alpha: alpha)
            overlaid = true
        }
        image = image.scaledToFit(longEdge: Int((Double(longEdge) * factor).rounded()))
        guard let rendered = generator.engine.makeCGImage(image, colorSpace: colorSpace) else {
            throw PreviewGenerator.Failure.renderFailed
        }
        let histogram = overlaid || content != .photo ? nil : Histogram(image: rendered)
        let elapsed = (clock.now - started).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        // A frame that filled the stage cache is slow once; it says nothing about the next.
        if drafting, !filledCache { adapt(level: level, seconds: seconds) }
        return Frame(image: DecodedImage(cgImage: rendered), histogram: histogram, content: content,
                     hasOverlay: overlaid, adjustments: adjustments,
                     maskFrameSize: CGSize(width: base.image.width, height: base.image.height),
                     scale: factor, seconds: seconds, filledCache: filledCache, machineLearning: base.machineLearning)
    }

    /// Red at half the mask's alpha over the photo.
    static func withOverlay(_ image: CIImage, alpha: CIImage) -> CIImage {
        let red = CIImage(color: CIColor(red: 1, green: 0.1, blue: 0.1)).cropped(to: image.extent)
        let blend = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: red, kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: MaskRenderer.scaled(alpha, by: 0.5),
        ])
        return blend?.outputImage?.cropped(to: image.extent) ?? image
    }

    /// The render in the working space before output (cached stages or whole).
    /// With `untilSharpening`, the image entering the sharpening step instead.
    private func linear(_ adjustments: Adjustments, source: CIImage, context: RenderContext, level: Int,
                        baseKey: String, cancellation: RenderCancellation?, untilSharpening: Bool = false) throws -> CIImage {
        let renderer = generator.renderer
        if untilSharpening, !cachesStages {
            // The map is the adjustment renderer's sharpening step; no other renderer has one.
            guard let adjusting = renderer as? AdjustmentRenderer else { throw PreviewGenerator.Failure.renderFailed }
            return adjusting.sharpeningInput(adjustments, to: source, context: context)
        }
        guard cachesStages, let adjusting = renderer as? AdjustmentRenderer else {
            if untilSharpening { throw PreviewGenerator.Failure.renderFailed }
            return try renderer.apply(adjustments.editStack, to: source, context: context)
        }
        stages = stageCaches[level] ?? StageCache()
        defer { stageCaches[level] = stages }
        return try staged(adjustments, renderer: adjusting, source: source, context: context, baseKey: baseKey,
                          cancellation: cancellation, untilSharpening: untilSharpening)
    }

    /// A full-size frame in the extended linear working space, as 32-bit
    /// float, with values above white kept: for tests of the stages.
    func linearFrame(_ adjustments: Adjustments) throws -> CGImage {
        let stack = adjustments.editStack
        let renderer = generator.renderer
        let isRaw = SupportedFormats.isRaw(pathExtension: source.pathExtension)
        let settings = isRaw ? renderer.decodeSettings(for: stack) : .none
        let base = try self.base(for: BaseKey(settings: settings, draft: false,
                                              longEdge: decodeLongEdge(renderer.geometry(for: stack))))
        let image = try linear(adjustments, source: CIImage(cgImage: base.image), context: base.context, level: 0,
                               baseKey: "\(base.serial)", cancellation: nil)
        guard let rendered = generator.engine.withContext({
            $0.createCGImage(image, from: image.extent, format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
        }) else { throw PreviewGenerator.Failure.renderFailed }
        return rendered
    }

    /// Fills the stage cache for a coming drag of mask `id` (the image entering
    /// the mask step, the estimates, the masks before it) without making a
    /// frame: called on idle so a drag's first frame is cheap. Cancellable
    /// between stages.
    public func prepare(_ adjustments: Adjustments, editing id: UUID?, allowsDrafts: Bool = true,
                        cancellation: RenderCancellation? = nil) throws {
        guard cachesStages, let renderer = generator.renderer as? AdjustmentRenderer else { return }
        let values = adjustments.effective
        let rendered = values.local.renderedMasks
        guard !rendered.isEmpty else { return }
        // Where the mask sits among the rendered ones (a mask with no values yet renders nothing).
        let index = values.local.masks.prefix { $0.id != id }.filter { rendered.contains($0) }.count
        let stack = adjustments.editStack
        let isRaw = SupportedFormats.isRaw(pathExtension: source.pathExtension)
        let settings = isRaw ? renderer.decodeSettings(for: stack) : .none
        let base = try self.base(for: BaseKey(settings: settings, draft: false,
                                              longEdge: decodeLongEdge(renderer.geometry(for: stack))))
        let level = allowsDrafts ? draftLevel : 0
        let baseKey = "\(base.serial)"
        var input = CIImage(cgImage: base.image)
        var context = base.context
        if level > 0 {
            (input, context) = try draft(of: base, key: baseKey, factor: Self.draftScales[level])
        }
        stages = stageCaches[level] ?? StageCache()
        defer { stageCaches[level] = stages }
        _ = try staged(adjustments, renderer: renderer, source: input, context: context, baseKey: baseKey,
                       cancellation: cancellation, prefill: index)
    }

    /// Steps the draft level down after a frame over `draftDropThreshold`, and
    /// back up only when the next larger frame would take under
    /// `draftRaiseThreshold`.
    private func adapt(level: Int, seconds: Double) {
        guard level == draftLevel else { return }
        draftLevel = Self.nextDraftLevel(after: level, seconds: seconds)
    }

    static func nextDraftLevel(after level: Int, seconds: Double) -> Int {
        if seconds > draftDropThreshold, level < draftScales.count - 1 { return level + 1 }
        if level > 0, seconds * 4 < draftRaiseThreshold { return level - 1 }
        return level
    }

    /// The decoded master reduced by `factor`, rendered once per base.
    private func draft(of base: Base, key: String, factor: Double) throws -> (CIImage, RenderContext) {
        let name = "\(key)|\(factor)"
        if let cached = draftBases[name] { return cached }
        let full = CIImage(cgImage: base.image)
        let reduced = try materialize(full.scaledToFit(longEdge: Int((Double(base.longEdge) * factor).rounded())))
        var context = base.context
        context.scale *= factor
        draftBases = [name: (reduced, context)]
        return (reduced, context)
    }

    /// Restarts the adaptive drafts at full size (a new photo, or a gesture's end).
    public func resetDrafts() {
        draftLevel = 0
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
        nextSerial += 1
        return touch(key, Base(image: image, context: decoded.context, serial: nextSerial,
                               machineLearning: decoded.machineLearning))
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

/// What the full-resolution refinement after a pause (or a zoom) renders:
/// the map on screen, or the photo without the slot being picked again
/// (chromatic-aberration design §4, zoomed in only). Nil for neither.
public enum LoupeRefinement: Equatable, Sendable {
    case map, photoWithoutSlot

    public static func wanted(content: LiveRenderSession.Content, replacesSlot: Bool, isZoomed: Bool) -> LoupeRefinement? {
        if content.isMap { return .map }
        return replacesSlot && isZoomed ? .photoWithoutSlot : nil
    }
}

/// Lets a caller abandon a render between its stages (work already sent to
/// the GPU finishes, but nothing more starts and no frame is made).
public final class RenderCancellation: Sendable {
    private let cancelled = Mutex(false)

    public init() {}

    public func cancel() { cancelled.withLock { $0 = true } }

    public var isCancelled: Bool { cancelled.withLock { $0 } }

    func check() throws {
        if isCancelled { throw CancellationError() }
    }
}
