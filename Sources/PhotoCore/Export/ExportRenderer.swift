import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders one version for export and writes it: the master through its edit
/// stack at full resolution, resized, output sharpened, watermarked, then
/// encoded in the chosen format and color space.
public struct ExportRenderer: Sendable {
    public enum Failure: Error, Equatable {
        case renderFailed
        case writeFailed
        /// The settings name a watermark the store does not have.
        case missingWatermark
    }

    public let generator: PreviewGenerator
    public let watermarks: WatermarkStore?

    public init(generator: PreviewGenerator = PreviewGenerator(), watermarks: WatermarkStore? = nil) {
        self.generator = generator
        self.watermarks = watermarks
    }

    /// The final image, at the origin, in the working space.
    func image(source: URL, stack: EditStack, settings: ExportSettings) throws -> CIImage {
        let rendered = try generator.image(source: source, stack: stack, longEdge: nil)
        let extent = rendered.extent
        var image = rendered.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let size = ExportSizing.outputSize(for: extent.size, settings: settings)
        let target = CGRect(origin: .zero, size: size)
        if size != extent.size {
            image = image.resized(to: size)
            if let sharpen = Self.outputSharpening(settings) {
                image = AdjustmentRenderer.sharpen(image, sharpen, scale: 1, extent: target)
            }
        }
        if let watermark = settings.activeWatermark {
            image = try watermarked(image, size: size, watermark: watermark)
        }
        return image.cropped(to: target)
    }

    /// Renders and writes one file to `url`, replacing what is there only when
    /// `replacing`. The file appears complete or not at all.
    public func export(source: URL, stack: EditStack, values: SidecarValues, settings: ExportSettings,
                       to url: URL, replacing: Bool) throws {
        let image = try image(source: source, stack: stack, settings: settings)
        guard let cgImage = generator.engine.makeCGImage(image, colorSpace: settings.colorSpace.cgColorSpace,
                                                         bitsPerComponent: settings.bitsPerComponent)
        else { throw Failure.renderFailed }
        let sourceProperties = CGImageSourceCreateWithURL(source as CFURL, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        let metadata = ExportMetadata.make(source: sourceProperties, values: values, settings: settings)
        try Self.write(cgImage, metadata: metadata, settings: settings, to: url, replacing: replacing)
    }

    // MARK: Steps

    /// Unsharp mask settings for the output size and medium, or nil when off.
    /// Print gets a wider radius as the resolution goes up, since ink spreads
    /// over more pixels.
    static func outputSharpening(_ settings: ExportSettings) -> Sharpen? {
        let amount: Double
        switch (settings.sharpening, settings.sharpeningTarget) {
        case (.off, _): return nil
        case (.light, .screen): amount = 35
        case (.standard, .screen): amount = 60
        case (.strong, .screen): amount = 95
        case (.light, .print): amount = 50
        case (.standard, .print): amount = 85
        case (.strong, .print): amount = 125
        }
        let radius = settings.sharpeningTarget == .screen ? 0.6 : min(max(Double(settings.ppi) / 300, 0.6), 2)
        return Sharpen(amount: amount, radius: radius, detail: 30, masking: 15)
    }

    private func watermarked(_ image: CIImage, size: CGSize, watermark: Watermark) throws -> CIImage {
        guard let watermarks, watermarks.contains(watermark.identifier),
              let mark = CIImage(contentsOf: watermarks.fileURL(for: watermark.identifier)), !mark.extent.isEmpty
        else { throw Failure.missingWatermark }
        let rect = WatermarkLayout.rect(imageSize: size, watermarkSize: mark.extent.size, watermark: watermark)
        guard rect.width > 0, rect.height > 0 else { return image }
        let fade = CIFilter.colorMatrix()
        fade.inputImage = mark
        let opacity = CGFloat(min(max(watermark.opacity, 0), 1))
        // Premultiplied: fading scales every component.
        fade.rVector = CIVector(x: opacity, y: 0, z: 0, w: 0)
        fade.gVector = CIVector(x: 0, y: opacity, z: 0, w: 0)
        fade.bVector = CIVector(x: 0, y: 0, z: opacity, w: 0)
        fade.aVector = CIVector(x: 0, y: 0, z: 0, w: opacity)
        let placed = (fade.outputImage ?? mark)
            .transformed(by: CGAffineTransform(translationX: -mark.extent.minX, y: -mark.extent.minY))
            .resized(to: CGSize(width: max(1, rect.width.rounded()), height: max(1, rect.height.rounded())))
            .transformed(by: CGAffineTransform(translationX: rect.minX.rounded(), y: rect.minY.rounded()))
        return placed.composited(over: image)
    }

    static func write(_ image: CGImage, metadata: ExportMetadata, settings: ExportSettings, to url: URL,
                      replacing: Bool) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        // A hidden name next to the target, so the move is a rename on the same volume.
        let temporary = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).partial",
                                            directoryHint: .notDirectory)
        defer { try? fileManager.removeItem(at: temporary) }

        let type: UTType = settings.format == .jpeg ? .jpeg : .tiff
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type.identifier as CFString, 1, nil)
        else { throw Failure.writeFailed }
        var properties = metadata.properties
        switch settings.format {
        case .jpeg:
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(settings.jpegQuality, 0), 1)
        case .tiff:
            var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = settings.tiffCompression.tagValue
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        CGImageDestinationAddImageAndMetadata(destination, image, metadata.xmp, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.writeFailed }

        if replacing, fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
    }
}
