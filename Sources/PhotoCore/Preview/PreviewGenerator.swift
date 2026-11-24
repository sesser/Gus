import CoreImage
import Foundation
import ImageIO
import os

/// Decodes masters and renders them through the edit stack.
public struct PreviewGenerator: Sendable {
    public enum Failure: Error, Equatable {
        case undecodable(URL)
        case renderFailed
    }

    public private(set) var engine: RenderEngine
    public let renderer: any EditStackRenderer
    public var jpegQuality: Double

    public init(engine: RenderEngine = RenderEngine(), renderer: any EditStackRenderer = AdjustmentRenderer(),
                jpegQuality: Double = 0.82) {
        self.engine = engine
        self.renderer = renderer
        self.jpegQuality = jpegQuality
    }

    /// The same renderer and quality, rendering through `engine`.
    public func withEngine(_ engine: RenderEngine) -> PreviewGenerator {
        var copy = self
        copy.engine = engine
        return copy
    }

    /// The lazy Core Image graph for `source` rendered with `stack`, no larger than
    /// `longEdge` pixels (nil for full resolution).
    public func image(source: URL, stack: EditStack, longEdge: Int?, draft: Bool = false) throws -> CIImage {
        try rendering(source: source, stack: stack, longEdge: longEdge, draft: draft).image
    }

    /// A lazy render and what the decoder did with the stack's machine learning request.
    public struct Rendering {
        public var image: CIImage
        public var machineLearning: MachineLearningNoiseReduction.Outcome
        /// Which decoder made the image, and for LibRaw's, which demosaic (R20).
        public var decoder: Decoder = .imageIO
        public var demosaic: LibRawDecoder.Demosaic?
        /// What the file says about correcting its lens (issue #87).
        public var lens: CameraLensState?
    }

    /// As `image`, with the machine learning outcome of the decode.
    public func rendering(source: URL, stack: EditStack, longEdge: Int?, draft: Bool = false) throws -> Rendering {
        try rendering(source: source, stack: stack, longEdge: longEdge, draft: draft, forSizeOnly: false)
    }

    /// `forSizeOnly`: the graph is only measured, never rendered, so a
    /// full-size decode stays lazy (`decode`).
    func rendering(source: URL, stack: EditStack, longEdge: Int?, draft: Bool, forSizeOnly: Bool) throws -> Rendering {
        let decoded = try Self.decode(source, longEdge: decodeLongEdge(source, stack: stack, longEdge: longEdge),
                                      draft: draft, settings: renderer.decodeSettings(for: stack), forSizeOnly: forSizeOnly)
        var image = try renderer.apply(stack, to: decoded.image, context: decoded.context)
        if let longEdge {
            image = image.scaledToFit(longEdge: longEdge)
        }
        return Rendering(image: image, machineLearning: decoded.machineLearning, decoder: decoded.decoder,
                         demosaic: decoded.demosaic, lens: decoded.context.lens)
    }

    /// Encoded rendition for the disk cache.
    public func jpegData(source: URL, stack: EditStack, tier: PreviewTier) throws -> Data {
        guard let data = try jpegData(source: source, stack: stack, tiers: [tier])[tier] else { throw Failure.renderFailed }
        return data
    }

    /// Several tiers from a single decode at the largest tier's size.
    public func jpegData(source: URL, stack: EditStack, tiers: Set<PreviewTier>) throws -> [PreviewTier: Data] {
        try encodedRendering(source: source, stack: stack, tiers: tiers).data
    }

    /// As `jpegData`, with the machine learning outcome of the decode.
    public func encodedRendering(source: URL, stack: EditStack, tiers: Set<PreviewTier>) throws
        -> (data: [PreviewTier: Data], machineLearning: MachineLearningNoiseReduction.Outcome) {
        guard let largest = tiers.max(by: { $0.longEdge < $1.longEdge }) else { return ([:], .notRequested) }
        let base = try rendering(source: source, stack: stack, longEdge: largest.longEdge,
                                 draft: tiers.allSatisfy(\.allowsDraftDecode))
        return (try encode(base.image, tiers: tiers), base.machineLearning)
    }

    /// Tiers from an already decoded frame (a video's poster frame).
    public func jpegData(decoded: CGImage, stack: EditStack, tiers: Set<PreviewTier>) throws -> [PreviewTier: Data] {
        guard let largest = tiers.max(by: { $0.longEdge < $1.longEdge }) else { return [:] }
        let base = try renderer.apply(stack, to: CIImage(cgImage: decoded), context: RenderContext())
            .scaledToFit(longEdge: largest.longEdge)
        return try encode(base, tiers: tiers)
    }

    private func encode(_ base: CIImage, tiers: Set<PreviewTier>) throws -> [PreviewTier: Data] {
        guard let largest = tiers.max(by: { $0.longEdge < $1.longEdge }) else { return [:] }
        var result: [PreviewTier: Data] = [:]
        for tier in tiers {
            let scaled = tier == largest ? base : base.scaledToFit(longEdge: tier.longEdge)
            guard let data = engine.jpegData(scaled, quality: jpegQuality) else { throw Failure.renderFailed }
            result[tier] = data
        }
        return result
    }

    /// An HDR rendition for displays with extended dynamic range, no larger than
    /// `longEdge` pixels (nil for full resolution): a half-float image in
    /// `RenderEngine.hdrColorSpace`, tagged with its content headroom. Nil when the
    /// master has nothing brighter than SDR white.
    ///
    /// Only HDR content counts: floating-point DNGs (HDR merges), decoded with the
    /// RAW decoder's standard amount of extended range, and images with HLG or PQ
    /// encoding. Camera raws stay SDR, although their highlights would also go
    /// above white with extended range. So do images whose HDR comes only from a
    /// gain map (issue #277): the gain map's HDR rendition is a different, often
    /// brighter picture, not the SDR one with highlights added (an iPhone HEIC's
    /// was 0.86 stops brighter on average), and live frames, previews and exports
    /// are the SDR one, so the loupe jumped between the two.
    public func hdrImage(source: URL, stack: EditStack, longEdge: Int?) throws -> CGImage? {
        guard renderer.preservesExtendedRange(stack),
              let decoded = try Self.decodeHDR(source, longEdge: decodeLongEdge(source, stack: stack, longEdge: longEdge),
                                               settings: renderer.decodeSettings(for: stack))
        else { return nil }
        var image = try renderer.apply(stack, to: decoded.image, context: decoded.context)
        if let longEdge {
            image = image.scaledToFit(longEdge: longEdge)
        }
        guard let rendered = engine.makeHDRCGImage(image) else { throw Failure.renderFailed }
        return rendered.contentHeadroom >= RenderEngine.minimumHDRHeadroom ? rendered : nil
    }

    /// Full-resolution (or capped) rendition for 1:1 viewing, in `colorSpace`
    /// (Display P3 when nil), rendered before it returns (`makeSurfaceImage`):
    /// never by its first draw on the main thread.
    public func cgImage(source: URL, stack: EditStack, longEdge: Int? = nil,
                        colorSpace: CGColorSpace? = nil) throws -> CGImage {
        let image = try image(source: source, stack: stack, longEdge: longEdge)
        guard let cgImage = engine.makeSurfaceImage(image, colorSpace: colorSpace) else { throw Failure.renderFailed }
        return cgImage
    }

    /// The size in pixels of `cgImage(source:stack:)`'s rendition, read from
    /// the same lazy graph with nothing decoded or rendered (a header read,
    /// 20 to 100 ms), so the loupe can take the photo's size before the
    /// rendition is there. Turns, straightening, the crop and the decoder's own
    /// frame (an in-camera aspect crop, a raw's active area) are all in it; the
    /// catalog's pixel size, read from the file's metadata, has none of them.
    ///
    /// Nil where only a decode would tell: a video, a raw only LibRaw decodes,
    /// a linear DNG (rendered whole as it decodes).
    public func outputSize(source: URL, stack: EditStack) throws -> CGSize? {
        if FileKind(pathExtension: source.pathExtension) == .video { return nil }
        if SupportedFormats.isRaw(pathExtension: source.pathExtension) {
            guard SystemRAWDecoder.reads(source), DNGLayout(contentsOf: source)?.hasLinearRaw != true else { return nil }
        }
        let extent = try rendering(source: source, stack: stack, longEdge: nil, draft: false, forSizeOnly: true)
            .image.extent.integral
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1 else { return nil }
        return extent.size
    }

    // MARK: Decoding

    /// The decode size for an output of `longEdge`: larger when the stack
    /// crops, so the kept part is not enlarged.
    func decodeLongEdge(_ source: URL, stack: EditStack, longEdge: Int?) -> Int? {
        let crop = renderer.geometry(for: stack)
        guard let longEdge, !crop.isIdentity, let size = Self.nativeSize(source) else { return longEdge }
        return Int((Double(longEdge) * crop.sourceZoom(sourceSize: size)).rounded(.up))
    }

    /// The master's size in pixels, before or after its orientation, from its header.
    /// For a raw the system's RAW decoder gives no image for, the frame LibRaw
    /// decodes (its header only, nothing unpacked).
    public static func nativeSize(_ url: URL) -> CGSize? {
        if SupportedFormats.isRaw(pathExtension: url.pathExtension) {
            if let raw = CIRAWFilter(imageURL: url), raw.nativeSize.width > 0 {
                return raw.nativeSize
            }
            if let size = LibRawDecoder.frameSize(url) { return size }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return pixelSize(source)
    }

    /// The size in pixels of the frame masks and spots are placed in for a
    /// photo with spots: the oriented decode of the whole sensor (a raw's
    /// camera crop undone, `CameraFrame`), before turns, straightening and
    /// crop. The Lens heading's corrections keep that frame's size
    /// (`LensCorrectionRenderer` crops its result to its input), so this is
    /// the size after any paste too. Nothing is decoded: only the decoder's
    /// output extent is asked for. Most files are read as far as their
    /// headers, but an Olympus, OM System or Panasonic raw with a camera
    /// crop is read whole into memory (`CameraFrame.fullFrameFilter` patches
    /// a copy of its bytes; tens of megabytes; code review C2). Nil when no
    /// decoder reads the file.
    public static func maskFrameSize(of url: URL) -> CGSize? {
        if SupportedFormats.isRaw(pathExtension: url.pathExtension) {
            // The decoders in `rawImage`'s order: the system's for the whole
            // sensor, the system's as the camera framed it, then LibRaw's.
            for raw in [CameraFrame.fullFrameFilter(for: url), CIRAWFilter(imageURL: url)].compactMap({ $0 }) {
                if let extent = RAWDecodeGraph.output(of: raw)?.extent, !extent.isEmpty, !extent.isInfinite {
                    return extent.size
                }
            }
            if let size = LibRawDecoder.frameSize(url) { return size }
        }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              !image.extent.isEmpty, !image.extent.isInfinite else { return nil }
        return image.extent.size
    }

    /// A decoded master and what the renderer needs to know about it.
    public struct Decoded {
        public var image: CIImage
        public var context: RenderContext
        public var machineLearning: MachineLearningNoiseReduction.Outcome = .notRequested
        /// Which decoder made the image.
        public var decoder = Decoder.imageIO
        /// LibRaw's decode before its color step, which `image` is the
        /// result of: a caller that keeps a decode while white balance
        /// changes keeps this, and makes each white balance's image from it.
        public var camera: CameraDecode?
        /// For LibRaw's decode, which demosaic made it.
        public var demosaic: LibRawDecoder.Demosaic?
    }

    /// LibRaw's linear image and the color step that turns it into the
    /// photo for a white balance (`CameraColorStep`).
    public struct CameraDecode: @unchecked Sendable {
        // @unchecked: CIImage is an immutable recipe, safe to share.
        public var linear: CIImage
        public var step: CameraColorStep

        public init(linear: CIImage, step: CameraColorStep) {
            self.linear = linear
            self.step = step
        }

        /// The photo for the white balance of `settings`, over `linear` or
        /// a copy of it the caller kept (rendered once, reduced).
        public func image(for settings: RAWDecodeSettings, over kept: CIImage? = nil) -> CIImage {
            step.apply(to: kept ?? linear, settings: settings)
        }
    }

    public enum Decoder: Sendable, Hashable {
        /// The system's RAW decoder: the stack's decode settings are applied (`context.isRaw`).
        case systemRAW
        /// LibRaw, for a raw the system decoder gives no image for: of the
        /// stack's decode settings its color step applies the white balance
        /// (`context.balancedByDecoder`), and nothing else.
        case libRaw
        case imageIO
    }

    /// Decodes a master into the working space, oriented, at roughly `longEdge`.
    ///
    /// RAW files go through `CIRAWFilter`, which can demosaic at a reduced scale
    /// (and in draft mode) for small targets, and applies the stack's decode
    /// settings. A raw it gives no image for goes to LibRaw, whose color step
    /// applies the settings' Kelvin and tint and none of the others:
    /// `context.isRaw` is false for its image, as `SystemRAWDecoder.reads`
    /// is for the file, and `context.balancedByDecoder` is true, as for any
    /// raw. Everything else is decoded by ImageIO, which downsamples
    /// during decode when a size is given.
    ///
    /// A machine learning request that cannot apply, or whose decode gives
    /// no image, decodes with the classical decoder instead and says why in
    /// `Decoded.machineLearning`.
    ///
    /// A full-size ImageIO decode is copied to the GPU first
    /// (`ResidentDecode`) unless `forSizeOnly`, for a graph that is only
    /// measured: then it stays a header read.
    static func decode(_ url: URL, longEdge: Int?, draft: Bool, extendedRange: Bool = false,
                       settings: RAWDecodeSettings = .none, forSizeOnly: Bool = false) throws -> Decoded {
        let isRaw = SupportedFormats.isRaw(pathExtension: url.pathExtension)
        if isRaw, settings.machineLearning {
            if let decoded = decodeRAW(url, longEdge: longEdge, draft: draft, extendedRange: extendedRange,
                                       settings: settings) {
                return decoded
            }
            // The machine learning decode gave no image: the classical one instead.
            var fallback = try decode(url, longEdge: longEdge, draft: draft, extendedRange: extendedRange,
                                      settings: settings.classical, forSizeOnly: forSizeOnly)
            // The system decoder read the file and its machine learning decode
            // failed; or it does not read the file at all, which is not a failure.
            fallback.machineLearning = .notApplied(
                fallback.context.isRaw ? .failed : MachineLearningNoiseReduction.reasonWithoutSystemDecoder)
            return fallback
        }
        if isRaw, let decoded = try rawImage(settings: settings, system: {
            decodeRAW(url, longEdge: longEdge, draft: draft, extendedRange: extendedRange, settings: $0)
        }, libRaw: {
            try decodeWithLibRaw(url, longEdge: longEdge, settings: settings)
        }, droppedChoices: {
            log.error("\(url.lastPathComponent, privacy: .private): no image for the stack's decoder choices; decoded without them")
        }) {
            return decoded
        }
        return try decodeWithImageIO(url, longEdge: longEdge, forSizeOnly: forSizeOnly)
    }

    /// Which decoder's image a raw gets, in order:
    ///
    /// 1. the system decoder's, with the stack's settings;
    /// 2. the system decoder's without the stack's own decoder choices (the
    ///    whole-sensor copy, a decoder version), where those left it without
    ///    an image. Which decoder a raw gets is one test, the one
    ///    `SystemRAWDecoder.reads` makes (the file as an untouched photo
    ///    decodes), so a raw it says the system reads is never handed to
    ///    LibRaw, whose image the editor would offer a raw's controls for;
    /// 3. LibRaw's, for a raw the system decoder gives no image for
    ///    (lossless-compressed Fujifilm X-E3 files on macOS 27.2.1, issue
    ///    #161), and only then: it is far slower. Of the stack's decode
    ///    settings its image takes the Kelvin and tint, in the color step
    ///    after the decode (`CameraColorStep`, issue #170), and no other
    ///    (`isRaw` false): the renderer applies its own noise reduction.
    ///
    /// Nil when neither has one (ImageIO is tried next).
    static func rawImage<Image>(settings: RAWDecodeSettings, system: (RAWDecodeSettings) -> Image?,
                                libRaw: () throws -> Image?, droppedChoices: () -> Void = {}) rethrows -> Image? {
        if let image = system(settings) { return image }
        if settings.choosesTheDecode, let image = system(settings.withoutDecodeChoices) {
            droppedChoices()
            return image
        }
        return try libRaw()
    }

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "decode")

    /// LibRaw's decode, at half size when the target is at most half the
    /// frame, through its color step for the settings' white balance. Nil
    /// when LibRaw cannot decode the file either; its reason is logged, since
    /// the caller then reports only that the file is undecodable. A task
    /// cancelled during the decode throws `CancellationError` (R21).
    ///
    /// The step's profile is the built-in one. A stack's profile reference
    /// (`Adjustments.cameraProfile`) would be resolved here and given to the
    /// step with `CameraColor.with(profile:)` (#89); no build has profiles
    /// to resolve yet, so every reference renders with the built-in profile.
    private static func decodeWithLibRaw(_ url: URL, longEdge: Int?, settings: RAWDecodeSettings) throws -> Decoded? {
        do {
            let output = try LibRawDecoder.decode(url, longEdge: longEdge)
            guard !output.linear.extent.isEmpty else { return nil }
            return Decoded(image: output.step.apply(to: output.linear, settings: settings),
                           context: RenderContext(scale: Self.scale(of: output.linear, native: output.fullSize),
                                                  isRaw: false, balancedByDecoder: true,
                                                  lens: Self.libRawLensState(url, corrected: output.hasLensCorrections)),
                           decoder: .libRaw, camera: CameraDecode(linear: output.linear, step: output.step),
                           demosaic: output.demosaic)
        } catch let cancelled as CancellationError {
            throw cancelled
        } catch {
            log.error("\(url.lastPathComponent, privacy: .private): no image from the system RAW decoder, and \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The lens state of a LibRaw decode: built in exactly when LibRaw applied
    /// the camera's tables (`Output.hasLensCorrections`; code review C7), so a
    /// frame outside LibRaw's image or a kernel that failed leaves Auto free.
    static func libRawLensState(_ url: URL, corrected: Bool) -> CameraLensState {
        if corrected { return .builtInCorrection }
        let state = CameraLensState.read(url, systemDecodes: false, decoderCorrects: false)
        return state == .builtInCorrection ? .tables(.none) : state
    }

    /// The system RAW decoder's image of a raw with its default settings, or nil
    /// when it gives none. For comparing it with LibRaw (`photobench rawcompare`).
    public static func systemRAWImage(_ url: URL) -> CIImage? {
        CIRAWFilter(imageURL: url).flatMap { RAWDecodeGraph.output(of: $0) }
    }

    /// The RAW decoder's image, or nil when it gives none.
    private static func decodeRAW(_ url: URL, longEdge: Int?, draft: Bool, extendedRange: Bool,
                                  settings: RAWDecodeSettings) -> Decoded? {
        let wholeSensor = settings.fullFrame ? CameraFrame.fullFrameFilter(for: url) : nil
        if let raw = wholeSensor ?? CIRAWFilter(imageURL: url) {
            if extendedRange {
                raw.extendedDynamicRangeAmount = 1
            }
            let outcome = settings.apply(to: raw, source: url)
            let native = raw.nativeSize
            let layout = DNGLayout(contentsOf: url)
            if let longEdge, native.width > 0, native.height > 0 {
                let scale = Double(longEdge) / Double(max(native.width, native.height))
                // Scaled decodes of DNGs with reduced linear raw copies come out
                // cyan; those decode at full size and are scaled afterwards.
                if scale < 1, layout?.hasReducedLinearRaw != true {
                    // Ask for a little more than needed so the final resample is a downscale.
                    raw.scaleFactor = Float(min(1, scale * 1.25))
                }
                raw.isDraftModeEnabled = draft
            }
            // The decoder can give an empty image without an error (a small
            // synthetic DNG does): treat it as no output. The image has a
            // graph of its own, or the decode before it could smear its edges
            // (`RAWDecodeGraph`). A linear DNG's is rendered whole first, or
            // parts of a render could differ from run to run (`LinearRawDecode`);
            // if that render fails, the decoder's image is used as it is.
            if var output = RAWDecodeGraph.output(of: raw), !output.extent.isEmpty {
                if layout?.hasLinearRaw == true, let whole = LinearRawDecode.rendered(output) {
                    output = whole
                }
                // Read from the filter that decoded: its own correction is what the image has (status.md Q1).
                let lens = CameraLensState.read(url, systemDecodes: true,
                                                decoderCorrects: raw.isLensCorrectionSupported && raw.isLensCorrectionEnabled)
                return Decoded(image: output, context: RenderContext(scale: Self.scale(of: output, native: native),
                                                                     isRaw: true, balancedByDecoder: true,
                                                                     cameraFrame: wholeSensor == nil ? nil : CameraFrame.rect(of: url),
                                                                     lens: lens),
                               machineLearning: outcome, decoder: .systemRAW)
            }
        }
        return nil
    }

    /// Everything that is not RAW, and RAW files the RAW decoder gives no image for.
    private static func decodeWithImageIO(_ url: URL, longEdge: Int?, forSizeOnly: Bool) throws -> Decoded {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              CGImageSourceGetCount(source) > 0
        else { throw Failure.undecodable(url) }

        if let longEdge {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: longEdge,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw Failure.undecodable(url)
            }
            let image = CIImage(cgImage: thumbnail)
            return Decoded(image: image, context: RenderContext(scale: Self.scale(of: image, native: Self.pixelSize(source)),
                                                                isRaw: false, lens: .notRaw))
        }
        guard let lazy = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw Failure.undecodable(url)
        }
        // Read from the GPU, never from the file in a render split into parts.
        let image = forSizeOnly ? lazy : ResidentDecode.resident(lazy) ?? lazy
        return Decoded(image: image, context: RenderContext(scale: 1, isRaw: false, lens: .notRaw))
    }

    /// Long edge of the decode over the long edge of the master, at most 1.
    static func scale(of image: CIImage, native: CGSize?) -> Double {
        guard let native, image.extent.isInfinite == false else { return 1 }
        let longest = max(native.width, native.height)
        guard longest > 0 else { return 1 }
        return min(1, max(image.extent.width, image.extent.height) / longest)
    }

    static func pixelSize(_ source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Decodes with extended range, or returns nil for an image without HDR content
    /// (see `hdrImage`). Videos are never decoded here.
    ///
    /// A gain map alone is not HDR content here (issue #277): a HEIC, JPEG or
    /// other non-raw file is HDR only when it is HLG or PQ encoded, whether or
    /// not it also has a gain map, and a raw only when it is a floating-point
    /// DNG, whatever auxiliary images it carries.
    static func decodeHDR(_ url: URL, longEdge: Int?, settings: RAWDecodeSettings = .none) throws -> Decoded? {
        if SupportedFormats.isRaw(pathExtension: url.pathExtension) {
            guard DNGLayout(contentsOf: url)?.hasFloatingPointRaw == true else { return nil }
            return try decode(url, longEdge: longEdge, draft: false, extendedRange: true, settings: settings)
        }
        guard FileKind(pathExtension: url.pathExtension) != .video,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              hasHDREncoding(source)
        else { return nil }
        // Decoded as before #277, `.expandToHDR` included, so HLG and PQ files keep their look.
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true, .expandToHDR: true]) else {
            throw Failure.undecodable(url)
        }
        return Decoded(image: image, context: RenderContext(scale: 1, isRaw: false, lens: .notRaw))
    }

    /// Whether the first image is HLG or PQ encoded. Creating the image only
    /// reads its header; the pixels are not decoded.
    static func hasHDREncoding(_ source: CGImageSource) -> Bool {
        CGImageSourceCreateImageAtIndex(source, 0, nil)?.colorSpace.map(CGColorSpaceUsesITUR_2100TF) ?? false
    }
}
