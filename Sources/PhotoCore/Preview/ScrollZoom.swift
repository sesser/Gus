import CoreGraphics

/// Zooming with the scroll wheel. Each wheel line or trackpad point scales the
/// magnification by the same factor, so scrolling in and back out by the same
/// amount returns to the magnification it started from.
public enum ScrollZoom {
    /// Natural logarithm of the factor per line of a (non-precise) mouse wheel:
    /// about 16 % per notch.
    public static let logFactorPerLine: CGFloat = 0.15
    /// Per point of a trackpad or Magic Mouse, which report many small deltas.
    public static let logFactorPerPoint: CGFloat = 0.005

    /// The factor for one scroll event. Wheel away from the user or fingers up
    /// zoom in (a factor above 1) whatever the scrolling direction setting,
    /// which `inverted` reports.
    public static func factor(deltaY: CGFloat, precise: Bool, inverted: Bool) -> CGFloat {
        let exponent = deltaY * (precise ? logFactorPerPoint : logFactorPerLine)
        return exp(inverted ? -exponent : exponent)
    }

    /// `current` scaled by `factor`, kept between `minimum` and `maximum`.
    public static func magnification(_ current: CGFloat, factor: CGFloat,
                                     minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(current * factor, minimum), max(minimum, maximum))
    }

    /// The visible origin, in document coordinates, that keeps `anchor` at the
    /// same place in the view when the magnification changes from `old` to `new`.
    public static func visibleOrigin(keeping anchor: CGPoint, visibleOrigin origin: CGPoint,
                                     from old: CGFloat, to new: CGFloat) -> CGPoint {
        guard new > 0 else { return origin }
        let scale = old / new
        return CGPoint(x: anchor.x - (anchor.x - origin.x) * scale,
                       y: anchor.y - (anchor.y - origin.y) * scale)
    }
}
