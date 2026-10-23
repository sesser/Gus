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

    public init(engine: RenderEngine = RenderEngine(), renderer: any EditStackRenderer = PassThroughRenderer(),
                jpegQuality: Double = 0.82) {
        self.engine = engine
        self.renderer = renderer
        self.jpegQuality = jpegQuality
    }

    /// The lazy Core Image graph for `source` rendered with `stack`, no larger than
    /// `longEdge` pixels (nil for full resolution).
    public func image(source: URL, stack: EditStack, longEdge: Int?, draft: Bool = false) throws -> CIImage {
        var image = try Self.decode(source, longEdge: longEdge, draft: draft)
        image = try renderer.apply(stack, to: image)
        if let longEdge {
            image = image.scaledToFit(longEdge: longEdge)
        }
        return image
    }

    /// Encoded rendition for the disk cache.
    public func jpegData(source: URL, stack: EditStack, tier: PreviewTier) throws -> Data {
        let image = try image(source: source, stack: stack, longEdge: tier.longEdge, draft: tier.allowsDraftDecode)
        guard let data = engine.jpegData(image, quality: jpegQuality) else { throw Failure.renderFailed }
        return data
    }

    /// Full-resolution (or capped) rendition for 1:1 viewing.
    public func cgImage(source: URL, stack: EditStack, longEdge: Int? = nil) throws -> CGImage {
        let image = try image(source: source, stack: stack, longEdge: longEdge)
        guard let cgImage = engine.makeCGImage(image) else { throw Failure.renderFailed }
        return cgImage
    }

    // MARK: Decoding

    /// Decodes a master into the working space, oriented, at roughly `longEdge`.
    ///
    /// RAW files go through `CIRAWFilter`, which can demosaic at a reduced scale
    /// (and in draft mode) for small targets. Everything else is decoded by ImageIO,
    /// which downsamples during decode when a size is given.
    static func decode(_ url: URL, longEdge: Int?, draft: Bool) throws -> CIImage {
        if SupportedFormats.isRaw(pathExtension: url.pathExtension), let raw = CIRAWFilter(imageURL: url) {
            let native = raw.nativeSize
            if let longEdge, native.width > 0, native.height > 0 {
                let scale = Double(longEdge) / Double(max(native.width, native.height))
                if scale < 1 {
                    // Ask for a little more than needed so the final resample is a downscale.
                    raw.scaleFactor = Float(min(1, scale * 1.25))
                }
                raw.isDraftModeEnabled = draft
            }
            if let output = raw.outputImage {
                return output
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
            return CIImage(cgImage: thumbnail)
        }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw Failure.undecodable(url)
        }
        return image
    }
}
