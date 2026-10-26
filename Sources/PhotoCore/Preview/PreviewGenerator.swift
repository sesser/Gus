import CoreImage
import Foundation
import ImageIO

/// Decodes masters and renders them through the edit stack.
public struct PreviewGenerator: Sendable {
    public enum Failure: Error, Equatable {
        case undecodable(URL)
        case renderFailed
    }

    public let engine: RenderEngine
    public let renderer: any EditStackRenderer
    public var jpegQuality: Double

    public init(engine: RenderEngine = RenderEngine(), renderer: any EditStackRenderer = AdjustmentRenderer(),
                jpegQuality: Double = 0.82) {
        self.engine = engine
        self.renderer = renderer
        self.jpegQuality = jpegQuality
    }

    /// The lazy Core Image graph for `source` rendered with `stack`, no larger than
    /// `longEdge` pixels (nil for full resolution).
    public func image(source: URL, stack: EditStack, longEdge: Int?, draft: Bool = false) throws -> CIImage {
        let decoded = try Self.decode(source, longEdge: longEdge, draft: draft,
                                      settings: renderer.decodeSettings(for: stack))
        var image = try renderer.apply(stack, to: decoded.image, context: decoded.context)
        if let longEdge {
            image = image.scaledToFit(longEdge: longEdge)
        }
        return image
    }

    /// Encoded rendition for the disk cache.
    public func jpegData(source: URL, stack: EditStack, tier: PreviewTier) throws -> Data {
        guard let data = try jpegData(source: source, stack: stack, tiers: [tier])[tier] else { throw Failure.renderFailed }
        return data
    }

    /// Several tiers from a single decode at the largest tier's size.
    public func jpegData(source: URL, stack: EditStack, tiers: Set<PreviewTier>) throws -> [PreviewTier: Data] {
        guard let largest = tiers.max(by: { $0.longEdge < $1.longEdge }) else { return [:] }
        let base = try image(source: source, stack: stack, longEdge: largest.longEdge,
                             draft: tiers.allSatisfy(\.allowsDraftDecode))
        return try encode(base, tiers: tiers)
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
    /// RAW decoder's standard amount of extended range, and images with a gain map
    /// or HLG or PQ encoding. Camera raws stay SDR, although their highlights
    /// would also go above white with extended range.
    public func hdrImage(source: URL, stack: EditStack, longEdge: Int?) throws -> CGImage? {
        guard renderer.preservesExtendedRange(stack),
              let decoded = try Self.decodeHDR(source, longEdge: longEdge, settings: renderer.decodeSettings(for: stack))
        else { return nil }
        var image = try renderer.apply(stack, to: decoded.image, context: decoded.context)
        if let longEdge {
            image = image.scaledToFit(longEdge: longEdge)
        }
        guard let rendered = engine.makeHDRCGImage(image) else { throw Failure.renderFailed }
        return rendered.contentHeadroom >= RenderEngine.minimumHDRHeadroom ? rendered : nil
    }

    /// Full-resolution (or capped) rendition for 1:1 viewing, in `colorSpace`
    /// (Display P3 when nil).
    public func cgImage(source: URL, stack: EditStack, longEdge: Int? = nil,
                        colorSpace: CGColorSpace? = nil) throws -> CGImage {
        let image = try image(source: source, stack: stack, longEdge: longEdge)
        guard let cgImage = engine.makeCGImage(image, colorSpace: colorSpace) else { throw Failure.renderFailed }
        return cgImage
    }

    // MARK: Decoding

    /// A decoded master and what the renderer needs to know about it.
    public struct Decoded {
        public var image: CIImage
        public var context: RenderContext
    }

    /// Decodes a master into the working space, oriented, at roughly `longEdge`.
    ///
    /// RAW files go through `CIRAWFilter`, which can demosaic at a reduced scale
    /// (and in draft mode) for small targets, and applies the stack's decode
    /// settings. Everything else is decoded by ImageIO, which downsamples during
    /// decode when a size is given.
    static func decode(_ url: URL, longEdge: Int?, draft: Bool, extendedRange: Bool = false,
                       settings: RAWDecodeSettings = .none) throws -> Decoded {
        if SupportedFormats.isRaw(pathExtension: url.pathExtension), let raw = CIRAWFilter(imageURL: url) {
            if extendedRange {
                raw.extendedDynamicRangeAmount = 1
            }
            settings.apply(to: raw)
            let native = raw.nativeSize
            if let longEdge, native.width > 0, native.height > 0 {
                let scale = Double(longEdge) / Double(max(native.width, native.height))
                // Scaled decodes of DNGs with reduced linear raw copies come out
                // cyan; those decode at full size and are scaled afterwards.
                if scale < 1, DNGLayout(contentsOf: url)?.hasReducedLinearRaw != true {
                    // Ask for a little more than needed so the final resample is a downscale.
                    raw.scaleFactor = Float(min(1, scale * 1.25))
                }
                raw.isDraftModeEnabled = draft
            }
            if let output = raw.outputImage {
                return Decoded(image: output, context: RenderContext(scale: Self.scale(of: output, native: native),
                                                                     isRaw: true))
            }
        }

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
                                                                isRaw: false))
        }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw Failure.undecodable(url)
        }
        return Decoded(image: image, context: RenderContext(scale: 1, isRaw: false))
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
    static func decodeHDR(_ url: URL, longEdge: Int?, settings: RAWDecodeSettings = .none) throws -> Decoded? {
        if SupportedFormats.isRaw(pathExtension: url.pathExtension) {
            guard DNGLayout(contentsOf: url)?.hasFloatingPointRaw == true else { return nil }
            return try decode(url, longEdge: longEdge, draft: false, extendedRange: true, settings: settings)
        }
        guard FileKind(pathExtension: url.pathExtension) != .video,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let hasGainMap = [kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeHDRGainMap].contains {
            CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil
        }
        // Creating the image only reads its header; the pixels are not decoded.
        let isHLGOrPQ = CGImageSourceCreateImageAtIndex(source, 0, nil)?.colorSpace.map(CGColorSpaceUsesITUR_2100TF) ?? false
        guard hasGainMap || isHLGOrPQ else { return nil }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true, .expandToHDR: true]) else {
            throw Failure.undecodable(url)
        }
        return Decoded(image: image, context: RenderContext(scale: 1, isRaw: false))
    }
}
