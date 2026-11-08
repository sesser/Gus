import CoreImage
import Foundation

/// Picking a fringe color from the photo (design §4 "What a click samples",
/// §14 OQ2): from the photo's data, never from screen pixels, on the image
/// the fringe step works on (`AdjustmentRenderer.fringeInput`: the decoded
/// master, aligned, before any graying and before every other adjustment),
/// at full resolution whatever the loupe shows. Thin fringes snap: the most
/// colorful pixel within a small radius of the click is taken, and a spot
/// with almost no color is refused.
public enum FringePicker {
    public enum Result: Equatable, Sendable {
        /// The OkLab color to store, and the pixel it came from (mask-frame unit coordinates, y down).
        case color(SIMD3<Double>, at: CGPoint)
        /// The most colorful pixel within reach has less than `ColorFringes.neutralChroma`.
        case almostNoColor(at: CGPoint)
    }

    /// The snap radius in screen points (design §4: about 3 pt).
    public static let snapRadius = 3.0

    /// The most colorful pixel within `radius` pixels of `center` (pixel
    /// coordinates, y down), where `pixel` gives linear Rec. 2020 colors
    /// (nil outside the image). Ties keep the pixel nearest the center.
    public static func pick(center: CGPoint, radius: Double,
                            pixel: (Int, Int) -> SIMD3<Double>?) -> (color: SIMD3<Double>, x: Int, y: Int)? {
        let reach = Int(radius.rounded(.up))
        let cx = Int(center.x.rounded(.down)), cy = Int(center.y.rounded(.down))
        var best: (color: SIMD3<Double>, x: Int, y: Int, chroma: Double, distance: Double)?
        for y in (cy - reach)...(cy + reach) {
            for x in (cx - reach)...(cx + reach) {
                let dx = Double(x) + 0.5 - center.x, dy = Double(y) + 0.5 - center.y
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance <= max(radius, 0.71), let rgb = pixel(x, y) else { continue }
                let lab = ColorRange.okLab(linearRec2020: rgb)
                let chroma = (lab.y * lab.y + lab.z * lab.z).squareRoot()
                if let current = best, chroma < current.chroma || (chroma == current.chroma && distance >= current.distance) {
                    continue
                }
                best = (lab, x, y, chroma, distance)
            }
        }
        return best.map { ($0.color, $0.x, $0.y) }
    }

    /// Picks around `point` (unit coordinates of the mask frame, y down:
    /// a raw's whole sensor) within `radiusInWidths` of the frame's width
    /// (at least one pixel), from `values`' fringe input at full resolution.
    public static func sample(source: URL, values: Adjustments, at point: CGPoint, radiusInWidths: Double,
                              generator: PreviewGenerator) throws -> Result {
        guard let renderer = generator.renderer as? AdjustmentRenderer else { throw PreviewGenerator.Failure.renderFailed }
        let isRaw = SupportedFormats.isRaw(pathExtension: source.pathExtension)
        var settings = isRaw ? renderer.decodeSettings(for: values.editStack) : .none
        // Mask-frame points are on the whole sensor, whatever the camera cropped.
        settings.fullFrame = isRaw
        let decoded = try PreviewGenerator.decode(source, longEdge: nil, draft: false, settings: settings)
        let image = renderer.fringeInput(values, to: decoded.image)
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty else { throw PreviewGenerator.Failure.renderFailed }
        let width = Int(extent.width), height = Int(extent.height)
        let radius = max(1, radiusInWidths * extent.width)
        let center = CGPoint(x: point.x * extent.width, y: point.y * extent.height)
        let reach = Int(radius.rounded(.up)) + 1
        // Pixel rows from the top; Core Image's from the bottom.
        let left = max(0, Int(center.x) - reach), right = min(width, Int(center.x) + reach + 1)
        let top = max(0, Int(center.y) - reach), bottom = min(height, Int(center.y) + reach + 1)
        guard right > left, bottom > top else { return .almostNoColor(at: point) }
        let region = CGRect(x: extent.minX + CGFloat(left), y: extent.maxY - CGFloat(bottom),
                            width: CGFloat(right - left), height: CGFloat(bottom - top))
        let w = right - left, h = bottom - top
        var buffer = [Float](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { bytes in
            generator.engine.withContext {
                $0.render(image, toBitmap: bytes.baseAddress!, rowBytes: w * 16, bounds: region, format: .RGBAf,
                          colorSpace: RenderEngine.workingColorSpace)
            }
        }
        let picked = pick(center: center, radius: radius) { x, y in
            guard x >= left, x < right, y >= top, y < bottom else { return nil }
            let i = ((y - top) * w + (x - left)) * 4
            return SIMD3(Double(buffer[i]), Double(buffer[i + 1]), Double(buffer[i + 2]))
        }
        guard let picked else { return .almostNoColor(at: point) }
        let at = CGPoint(x: (Double(picked.x) + 0.5) / Double(width), y: (Double(picked.y) + 0.5) / Double(height))
        let chroma = (picked.color.y * picked.color.y + picked.color.z * picked.color.z).squareRoot()
        return chroma < ColorFringes.neutralChroma ? .almostNoColor(at: at) : .color(picked.color, at: at)
    }

    /// The slot's color as a pixel of it looks in the photo now, after the
    /// adjustments that follow the fringe step (design §14 OQ2, point 3), in
    /// linear Rec. 2020, for its swatch.
    public static func swatch(_ okLab: SIMD3<Double>, values: Adjustments, isRaw: Bool,
                              generator: PreviewGenerator) -> SIMD3<Double>? {
        guard let renderer = generator.renderer as? AdjustmentRenderer else { return nil }
        let image = renderer.swatch(okLab, values: values, context: RenderContext(isRaw: isRaw))
        var buffer = [Float](repeating: 0, count: 4)
        buffer.withUnsafeMutableBytes { bytes in
            generator.engine.withContext {
                $0.render(image, toBitmap: bytes.baseAddress!, rowBytes: 16, bounds: CGRect(x: 1, y: 1, width: 1, height: 1),
                          format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
            }
        }
        return SIMD3(Double(buffer[0]), Double(buffer[1]), Double(buffer[2]))
    }
}
