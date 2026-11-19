import CoreGraphics
import Foundation

/// A spot's circles in pixels of a mask frame of a given size, and the rules
/// that keep a source usable (design §4): inside the photo and clear of its
/// own spot. Pixel coordinates have their origin at the top left, y down,
/// as the unit coordinates they come from.
public struct SpotGeometry: Hashable, Sendable {
    /// The mask frame's size in pixels.
    public var frameSize: CGSize

    public init(frameSize: CGSize) {
        self.frameSize = frameSize
    }

    public var longEdge: Double { Double(max(frameSize.width, frameSize.height)) }

    public func pixels(_ point: MaskPoint) -> CGPoint {
        CGPoint(x: point.x * frameSize.width, y: point.y * frameSize.height)
    }

    public func unit(_ point: CGPoint) -> MaskPoint {
        MaskPoint(x: Double(point.x / max(frameSize.width, 1)), y: Double(point.y / max(frameSize.height, 1)))
    }

    /// The radius of a spot of `size` in pixels.
    public func radius(_ size: Double) -> Double {
        size * longEdge
    }

    /// `source` moved as little as possible so that its circle (radius
    /// `radius` px) lies inside the frame and does not overlap the spot's
    /// circle at `center`: first pushed outward along the line from the
    /// spot until the two circles touch, then held inside the frame. Near a
    /// corner the second rule can undo the first; the frame wins, since a
    /// source outside the photo has nothing to copy.
    public func constrainedSource(_ source: CGPoint, center: CGPoint, radius: Double) -> CGPoint {
        var point = source
        let dx = Double(point.x - center.x), dy = Double(point.y - center.y)
        let distance = hypot(dx, dy)
        let minimum = 2 * radius
        if distance < minimum {
            // Straight to the right when the two centers coincide.
            let (ux, uy) = distance > 1e-9 ? (dx / distance, dy / distance) : (1.0, 0.0)
            point = CGPoint(x: Double(center.x) + ux * minimum, y: Double(center.y) + uy * minimum)
        }
        return insideFrame(point, radius: radius)
    }

    /// `point` held so that a circle of `radius` around it lies inside the
    /// frame; the middle of the frame along an edge shorter than the circle.
    public func insideFrame(_ point: CGPoint, radius: Double) -> CGPoint {
        func clamp(_ value: Double, _ length: Double) -> Double {
            guard length >= 2 * radius else { return length / 2 }
            return min(max(value, radius), length - radius)
        }
        return CGPoint(x: clamp(Double(point.x), Double(frameSize.width)), y: clamp(Double(point.y), Double(frameSize.height)))
    }

    /// `spot` with its source held to the rules.
    public func constrained(_ spot: Spot) -> Spot {
        var spot = spot
        let source = constrainedSource(pixels(spot.source), center: pixels(spot.center), radius: radius(spot.size))
        spot.source = unit(source)
        return spot
    }

    /// `spot` moved to `center` (unit coordinates, held on the photo), its
    /// source keeping the same offset where the rules allow (design §4).
    public func moving(_ spot: Spot, to center: MaskPoint) -> Spot {
        var moved = spot
        moved.center = MaskPoint(x: min(max(center.x, 0), 1), y: min(max(center.y, 0), 1))
        moved.source = MaskPoint(x: spot.source.x + moved.center.x - spot.center.x,
                                 y: spot.source.y + moved.center.y - spot.center.y)
        return constrained(moved)
    }

    /// `spot` at `size`, its source pushed outward when the circles would overlap.
    public func resizing(_ spot: Spot, to size: Double) -> Spot {
        var resized = spot
        resized.size = min(max(size, Spot.sizeRange.lowerBound), Spot.sizeRange.upperBound)
        return constrained(resized)
    }

    /// `spot` copying from `source`, held to the rules (a dragged source
    /// stops at its own spot and at the photo's edge).
    public func sourcing(_ spot: Spot, from source: MaskPoint) -> Spot {
        var sourced = spot
        sourced.source = source
        return constrained(sourced)
    }

    /// Where the source lies seen from the spot, in eight directions:
    /// for VoiceOver ("Copied from the left").
    public static func direction(from center: CGPoint, to source: CGPoint) -> SpotDirection {
        let dx = Double(source.x - center.x), dy = Double(source.y - center.y)
        // 0 to the right, counterclockwise on screen (y down, so −dy is up).
        var angle = atan2(-dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }
        let index = Int(((angle + 22.5) / 45).rounded(.down)) % 8
        return SpotDirection.allCases[index]
    }
}

/// Where spots lie against the crop (healing design §8). Points of the output
/// (the photo as cropped) are unit coordinates, y down.
public enum SpotCrop {
    /// How far past the output's edges still counts as on them: the
    /// round trip through `CropGeometry` (turns, straightening) is not
    /// exact, and a spot held at an edge must stay visible (review R2-1).
    public static let tolerance = 1e-9

    /// `point` lies in the photo as cropped, within `tolerance`.
    public static func contains(_ point: CGPoint) -> Bool {
        let range = -tolerance...(1 + tolerance)
        return range.contains(Double(point.x)) && range.contains(Double(point.y))
    }

    /// `point` (mask frame) moved as little as needed, in the output, to lie
    /// in the photo as cropped by `crop` over a mask frame of `sourceSize`.
    /// A stored point is rounded to 10⁻⁶ (`MaskPoint`), which can carry a
    /// point clamped onto the edge just past it; the margin then grows in
    /// steps until the stored point maps inside, so the result always
    /// passes `contains`.
    public static func held(_ point: MaskPoint, crop: Crop, sourceSize: CGSize) -> MaskPoint {
        let output = CropGeometry.maskToOutput(CGPoint(x: point.x, y: point.y), crop: crop, sourceSize: sourceSize)
        guard !contains(output) else { return point }
        var held = point
        for margin in [0, 1e-6, 1e-5, 1e-4, 1e-3] {
            let clamped = CGPoint(x: min(max(Double(output.x), margin), 1 - margin),
                                  y: min(max(Double(output.y), margin), 1 - margin))
            let mapped = CropGeometry.outputToMask(clamped, crop: crop, sourceSize: sourceSize)
            held = MaskPoint(x: Double(mapped.x), y: Double(mapped.y))
            if contains(CropGeometry.maskToOutput(CGPoint(x: held.x, y: held.y), crop: crop, sourceSize: sourceSize)) {
                return held
            }
        }
        return held
    }
}

/// Eight directions, counterclockwise from the right.
public enum SpotDirection: String, CaseIterable, Sendable {
    case right, upperRight, above, upperLeft, left, lowerLeft, below, lowerRight
}
