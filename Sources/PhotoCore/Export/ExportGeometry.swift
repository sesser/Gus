import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The pixel size an export comes out at.
public enum ExportSizing {
    /// Whole-pixel output size for a rendered master of `size`. Never larger
    /// than the master: an export is not upscaled.
    public static func outputSize(for size: CGSize, settings: ExportSettings) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        let scale = min(1, scaleFactor(for: size, settings: settings))
        guard scale < 1 else { return CGSize(width: size.width.rounded(), height: size.height.rounded()) }
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    private static func scaleFactor(for size: CGSize, settings: ExportSettings) -> Double {
        let long = max(size.width, size.height)
        let short = min(size.width, size.height)
        switch settings.sizing {
        case .full:
            return 1
        case .fit:
            return min(Double(max(settings.boxWidth, 1)) / size.width, Double(max(settings.boxHeight, 1)) / size.height)
        case .longEdge:
            return Double(max(settings.edgeLength, 1)) / long
        case .shortEdge:
            return Double(max(settings.edgeLength, 1)) / short
        case .percent:
            return min(max(settings.percent, 1), 100) / 100
        }
    }
}

/// Where a watermark goes on an image. The export and the export window's
/// preview both use it, so the preview shows what will be written.
public enum WatermarkLayout {
    /// The watermark's rectangle on an image of `imageSize`, with the origin at
    /// the bottom left (Core Image's) unless `flipped` (top left, as in views).
    ///
    /// The watermark's long side is `size` percent of the image's long edge,
    /// shrunk when needed so it fits inside the margins.
    public static func rect(imageSize: CGSize, watermarkSize: CGSize, watermark: Watermark,
                            flipped: Bool = false) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, watermarkSize.width > 0, watermarkSize.height > 0 else {
            return .zero
        }
        let long = max(imageSize.width, imageSize.height)
        let margin = long * min(max(watermark.margin, Watermark.marginRange.lowerBound), Watermark.marginRange.upperBound) / 100
        let size = min(max(watermark.size, Watermark.sizeRange.lowerBound), Watermark.sizeRange.upperBound)
        var scale = long * size / 100 / max(watermarkSize.width, watermarkSize.height)
        let room = CGSize(width: max(imageSize.width - 2 * margin, 1), height: max(imageSize.height - 2 * margin, 1))
        scale = min(scale, room.width / watermarkSize.width, room.height / watermarkSize.height)
        let width = watermarkSize.width * scale
        let height = watermarkSize.height * scale

        let x: CGFloat = switch watermark.anchor {
        case .topLeft, .left, .bottomLeft: margin
        case .top, .center, .bottom: (imageSize.width - width) / 2
        case .topRight, .right, .bottomRight: imageSize.width - margin - width
        }
        // Distance from the top edge.
        let top: CGFloat = switch watermark.anchor {
        case .topLeft, .top, .topRight: margin
        case .left, .center, .right: (imageSize.height - height) / 2
        case .bottomLeft, .bottom, .bottomRight: imageSize.height - margin - height
        }
        let y = flipped ? top : imageSize.height - top - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension CIImage {
    /// Scaled to exactly `size` (Lanczos, aspect ratio corrected for rounding),
    /// with the result at the origin. Edges are extended before scaling so the
    /// borders do not darken.
    func resized(to size: CGSize) -> CIImage {
        let extent = self.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return self }
        let origin = self.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let target = CGRect(origin: .zero, size: size)
        guard size != extent.size else { return origin.cropped(to: target) }
        let scale = size.height / extent.height
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = origin.clampedToExtent()
        filter.scale = Float(scale)
        filter.aspectRatio = Float((size.width / extent.width) / scale)
        return (filter.outputImage ?? origin).cropped(to: target)
    }
}
