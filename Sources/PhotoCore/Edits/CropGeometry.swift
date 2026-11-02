import CoreGraphics
import Foundation

/// Keeps a crop rectangle inside a straightened image while it is dragged,
/// resized, constrained to an aspect ratio or straightened.
///
/// Rectangles are in unit coordinates of the turned frame (see `Crop`), whose
/// size in pixels is `size`. The image is that frame rotated by `angle`
/// degrees (clockwise) about its center; a rectangle fits when its four
/// corners lie on the image.
public enum CropGeometry {
    /// The eight places a rectangle is resized from.
    public enum Handle: CaseIterable, Sendable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
        var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
        var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
        public var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }
    }

    /// Smallest edge a rectangle is resized to, in pixels of the frame.
    static func minimumEdge(_ size: CGSize) -> Double {
        max(8, 0.02 * min(size.width, size.height))
    }

    // MARK: Fitting

    /// A point of the turned frame (pixels from its center, y down) in the
    /// coordinates of the unrotated image.
    private static func unrotated(_ x: Double, _ y: Double, angle: Double) -> (x: Double, y: Double) {
        let radians = angle * .pi / 180
        let cos = Foundation.cos(radians), sin = Foundation.sin(radians)
        return (cos * x + sin * y, -sin * x + cos * y)
    }

    /// Centered pixel coordinates of a rectangle's center and half extents.
    private static func centered(_ rect: CropRect, _ size: CGSize) -> (cx: Double, cy: Double, hw: Double, hh: Double) {
        ((rect.midX - 0.5) * size.width, (rect.midY - 0.5) * size.height,
         rect.width * size.width / 2, rect.height * size.height / 2)
    }

    private static func rect(cx: Double, cy: Double, hw: Double, hh: Double, _ size: CGSize) -> CropRect {
        CropRect(x: (cx - hw) / size.width + 0.5, y: (cy - hh) / size.height + 0.5,
                 width: 2 * hw / size.width, height: 2 * hh / size.height)
    }

    private static func contains(_ x: Double, _ y: Double, angle: Double, size: CGSize) -> Bool {
        let point = unrotated(x, y, angle: angle)
        let tolerance = 1e-6 * max(size.width, size.height)
        return abs(point.x) <= size.width / 2 + tolerance && abs(point.y) <= size.height / 2 + tolerance
    }

    /// True when every corner of `rect` lies on the image.
    public static func fits(_ rect: CropRect, angle: Double, size: CGSize) -> Bool {
        let c = centered(rect, size)
        return [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].allSatisfy { sx, sy in
            contains(c.cx + sx * c.hw, c.cy + sy * c.hh, angle: angle, size: size)
        }
    }

    /// `rect` shrunk about its center until it fits, its center first moved
    /// toward the frame's when it lies off the image. Its proportions stay.
    public static func fitted(_ rect: CropRect, angle: Double, size: CGSize) -> CropRect {
        var c = centered(rect, size)
        if !contains(c.cx, c.cy, angle: angle, size: size) {
            // The largest fraction of the way out that is still on the image, with a margin.
            var low = 0.0, high = 1.0
            for _ in 0..<40 {
                let middle = (low + high) / 2
                if contains(c.cx * middle, c.cy * middle, angle: angle, size: size) { low = middle } else { high = middle }
            }
            c.cx *= low * 0.98
            c.cy *= low * 0.98
        }
        let center = unrotated(c.cx, c.cy, angle: angle)
        var scale = 1.0
        for (sx, sy) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] {
            let offset = unrotated(sx * c.hw, sy * c.hh, angle: angle)
            for (position, extent, limit) in [(center.x, offset.x, size.width / 2), (center.y, offset.y, size.height / 2)]
            where abs(extent) > 1e-12 {
                let room = extent > 0 ? limit - position : -limit - position
                scale = min(scale, max(0, room / extent))
            }
        }
        return Self.rect(cx: c.cx, cy: c.cy, hw: c.hw * scale, hh: c.hh * scale, size)
    }

    /// The largest rectangle of `ratio` (width over height, in pixels) on the
    /// image, centered on the frame; nil `ratio` keeps the frame's proportions.
    public static func largest(ratio: Double?, angle: Double, size: CGSize) -> CropRect {
        let ratio = ratio ?? size.width / size.height
        // Far too large, then shrunk to fit.
        let hh = max(size.width, size.height) * 4
        return fitted(rect(cx: 0, cy: 0, hw: hh * ratio, hh: hh, size), angle: angle, size: size)
    }

    /// The largest rectangle of `ratio` inside `rect`, on its center.
    public static func constrained(_ rect: CropRect, to ratio: Double, angle: Double, size: CGSize) -> CropRect {
        var c = centered(rect, size)
        if c.hw / c.hh > ratio { c.hw = c.hh * ratio } else { c.hh = c.hw / ratio }
        return fitted(Self.rect(cx: c.cx, cy: c.cy, hw: c.hw, hh: c.hh, size), angle: angle, size: size)
    }

    /// The same area at the same center with width and height swapped in
    /// pixels (portrait for landscape), then fitted.
    public static func flipped(_ rect: CropRect, angle: Double, size: CGSize) -> CropRect {
        let c = centered(rect, size)
        return fitted(Self.rect(cx: c.cx, cy: c.cy, hw: c.hh, hh: c.hw, size), angle: angle, size: size)
    }

    /// Width over height of `rect` in pixels.
    public static func ratio(of rect: CropRect, size: CGSize) -> Double {
        rect.width * size.width / max(rect.height * size.height, 1e-9)
    }

    // MARK: Dragging

    /// `rect` moved by `dx`, `dy` (unit coordinates), as far as it stays on
    /// the image; it slides along an edge it reaches.
    public static func moved(_ rect: CropRect, dx: Double, dy: Double, angle: Double, size: CGSize) -> CropRect {
        func offset(_ rect: CropRect, _ dx: Double, _ dy: Double) -> CropRect {
            CropRect(x: rect.x + dx, y: rect.y + dy, width: rect.width, height: rect.height)
        }
        let start = fits(rect, angle: angle, size: size) ? rect : fitted(rect, angle: angle, size: size)
        let full = offset(start, dx, dy)
        if fits(full, angle: angle, size: size) { return full }
        let alongX = offset(start, farthest { fits(offset(start, dx * $0, 0), angle: angle, size: size) } * dx, 0)
        let t = farthest { fits(offset(alongX, 0, dy * $0), angle: angle, size: size) }
        return offset(alongX, 0, dy * t)
    }

    /// `rect` with the edges of `handle` moved to `point` (unit coordinates),
    /// keeping `ratio` (width over height in pixels) when given, as far as it
    /// stays on the image and no smaller than a few pixels.
    public static func resized(_ rect: CropRect, handle: Handle, to point: CGPoint, ratio: Double?,
                               angle: Double, size: CGSize) -> CropRect {
        let start = fits(rect, angle: angle, size: size) ? rect : fitted(rect, angle: angle, size: size)
        let target = resizedUnconstrained(start, handle: handle, to: point, ratio: ratio, size: size)
        if fits(target, angle: angle, size: size) { return target }
        let t = farthest { fits(interpolate(start, target, $0), angle: angle, size: size) }
        return interpolate(start, target, t)
    }

    private static func resizedUnconstrained(_ rect: CropRect, handle: Handle, to point: CGPoint, ratio: Double?,
                                             size: CGSize) -> CropRect {
        let minimum = minimumEdge(size)
        // Pixels, y down, with the frame's top left corner at the origin.
        var left = rect.x * size.width, right = (rect.x + rect.width) * size.width
        var top = rect.y * size.height, bottom = (rect.y + rect.height) * size.height
        let px = point.x * size.width, py = point.y * size.height
        if handle.movesLeft { left = min(px, right - minimum) }
        if handle.movesRight { right = max(px, left + minimum) }
        if handle.movesTop { top = min(py, bottom - minimum) }
        if handle.movesBottom { bottom = max(py, top + minimum) }
        if let ratio {
            var width = right - left, height = bottom - top
            if handle.isCorner {
                // The larger of the two proposals, so the corner follows the pointer.
                if width / height > ratio { height = width / ratio } else { width = height * ratio }
                if handle.movesLeft { left = right - width } else { right = left + width }
                if handle.movesTop { top = bottom - height } else { bottom = top + height }
            } else if handle == .top || handle == .bottom {
                width = height * ratio
                let middle = (left + right) / 2
                left = middle - width / 2
                right = middle + width / 2
            } else {
                height = width / ratio
                let middle = (top + bottom) / 2
                top = middle - height / 2
                bottom = middle + height / 2
            }
        }
        return CropRect(x: left / size.width, y: top / size.height,
                        width: (right - left) / size.width, height: (bottom - top) / size.height)
    }

    private static func interpolate(_ a: CropRect, _ b: CropRect, _ t: Double) -> CropRect {
        CropRect(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t,
                 width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    /// The largest `t` in 0 … 1 for which `accepts` holds, assuming it holds at 0.
    private static func farthest(_ accepts: (Double) -> Bool) -> Double {
        var low = 0.0, high = 1.0
        for _ in 0..<30 {
            let middle = (low + high) / 2
            if accepts(middle) { low = middle } else { high = middle }
        }
        return low
    }

    // MARK: The mask frame

    /// Where a point of the mask frame (unit coordinates of the oriented image
    /// before turns, straightening and crop; y down) lands in the cropped
    /// output, in unit coordinates of the output. `sourceSize` is the mask
    /// frame in pixels (any scale: only its proportions matter).
    ///
    /// The image turns clockwise by θ = 90° × quarter turns + straighten angle
    /// about its center (as `Crop.apply` does), then the rectangle is cut from
    /// the turned frame.
    public static func maskToOutput(_ point: CGPoint, crop: Crop, sourceSize: CGSize) -> CGPoint {
        let turned = crop.turnedSize(sourceSize)
        let s = (x: Double((point.x - 0.5) * sourceSize.width), y: Double((point.y - 0.5) * sourceSize.height))
        let r = rotatedClockwise(s, degrees: turnAngle(crop))
        let rect = crop.rect ?? .full
        let t = (x: r.x / turned.width + 0.5, y: r.y / turned.height + 0.5)
        return CGPoint(x: (t.x - rect.x) / rect.width, y: (t.y - rect.y) / rect.height)
    }

    /// The inverse of `maskToOutput`.
    public static func outputToMask(_ point: CGPoint, crop: Crop, sourceSize: CGSize) -> CGPoint {
        let turned = crop.turnedSize(sourceSize)
        let rect = crop.rect ?? .full
        let t = (x: rect.x + Double(point.x) * rect.width, y: rect.y + Double(point.y) * rect.height)
        let r = (x: Double((t.x - 0.5) * turned.width), y: Double((t.y - 0.5) * turned.height))
        let s = rotatedClockwise(r, degrees: -turnAngle(crop))
        return CGPoint(x: s.x / sourceSize.width + 0.5, y: s.y / sourceSize.height + 0.5)
    }

    /// The output position, in pixels from the output's top left corner (y
    /// down, continuous: a pixel's center is at +0.5), where a mask-frame point
    /// lands when `Crop.apply` renders a source of `sourceSize` pixels. Like
    /// `maskToOutput`, with the crop rectangle's edges rounded to whole pixels
    /// as the render rounds them (its left edge, and its top edge counted from
    /// the bottom, Core Image's y axis pointing up).
    public static func maskToOutputPixel(_ point: CGPoint, crop: Crop, sourceSize: CGSize) -> CGPoint {
        let turned = crop.turnedSize(sourceSize)
        let s = (x: Double((point.x - 0.5) * sourceSize.width), y: Double((point.y - 0.5) * sourceSize.height))
        let r = rotatedClockwise(s, degrees: turnAngle(crop))
        let rect = crop.rect ?? .full
        let left = (rect.x * turned.width).rounded()
        let top = turned.height - ((1 - rect.y) * turned.height).rounded()
        return CGPoint(x: r.x + turned.width / 2 - left, y: r.y + turned.height / 2 - top)
    }

    /// A mask-frame rotation (degrees, clockwise) as the output shows it.
    public static func outputRotation(_ degrees: Double, crop: Crop) -> Double {
        degrees + turnAngle(crop)
    }

    /// The whole clockwise turn of `crop`, in degrees.
    static func turnAngle(_ crop: Crop) -> Double {
        Double(crop.quarterTurns) * 90 + crop.angle
    }

    /// `point` (y down) turned clockwise by `degrees` about the origin.
    static func rotatedClockwise(_ point: (x: Double, y: Double), degrees: Double) -> (x: Double, y: Double) {
        let radians = degrees * .pi / 180
        let cos = Foundation.cos(radians), sin = Foundation.sin(radians)
        return (cos * point.x - sin * point.y, sin * point.x + cos * point.y)
    }
}
