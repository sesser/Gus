import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// A rectangle in unit coordinates of a frame: the origin is the top left
/// corner, x goes right and y goes down, and the frame is 1 × 1 whatever its
/// size in pixels.
public struct CropRect: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The whole frame.
    public static let full = CropRect(x: 0, y: 0, width: 1, height: 1)

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// The same rectangle after a quarter turn of its frame.
    public func turned(clockwise: Bool) -> CropRect {
        clockwise ? CropRect(x: 1 - (y + height), y: x, width: height, height: width)
                  : CropRect(x: y, y: 1 - (x + width), width: height, height: width)
    }

    /// The rectangle of a stored (sensor) frame in the frame as displayed with
    /// EXIF `orientation`.
    public func oriented(_ orientation: CGImagePropertyOrientation) -> CropRect {
        func map(_ u: Double, _ v: Double) -> (Double, Double) {
            switch orientation {
            case .up: (u, v)
            case .upMirrored: (1 - u, v)
            case .down: (1 - u, 1 - v)
            case .downMirrored: (u, 1 - v)
            case .leftMirrored: (v, u)
            case .right: (1 - v, u)
            case .rightMirrored: (1 - v, 1 - u)
            case .left: (v, 1 - u)
            }
        }
        let a = map(x, y)
        let b = map(x + width, y + height)
        return CropRect(x: min(a.0, b.0), y: min(a.1, b.1), width: abs(b.0 - a.0), height: abs(b.1 - a.1))
    }

    /// Within 1/10000 of the frame on every edge.
    public func isClose(to other: CropRect) -> Bool {
        let tolerance = 1e-4
        return abs(x - other.x) < tolerance && abs(y - other.y) < tolerance
            && abs(width - other.width) < tolerance && abs(height - other.height) < tolerance
    }
}

/// Quarter turns, straightening and the crop, applied before every other
/// adjustment so that the vignette and grain follow the cropped frame.
///
/// The rectangle is in unit coordinates of the frame after the quarter turns.
/// Straightening rotates the image about that frame's center, and the
/// rectangle is cut from the rotated image, axis aligned; the editor keeps it
/// inside the image (`CropGeometry`).
///
/// Without this operation the photo keeps the frame its decoder gives, which for
/// some raw files is already a crop chosen in the camera (an aspect ratio).
/// With it, raw files are decoded whole, so the rectangle can also reach the
/// part the camera cropped away (`CameraFrame`).
public struct Crop: AdjustmentModule {
    public static let kind: EditOperationKind = "crop"

    /// Degrees of straightening either way.
    public static let angleRange: ClosedRange<Double> = -45...45

    /// The part kept; nil keeps the whole frame.
    public var rect: CropRect?
    /// Clockwise quarter turns, 0 … 3.
    public var quarterTurns: Int
    /// Straightening in degrees; positive turns the image clockwise.
    public var angle: Double

    public init(rect: CropRect? = nil, quarterTurns: Int = 0, angle: Double = 0) {
        self.rect = rect
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
        self.angle = angle
    }

    init(_ values: ParameterValues) {
        if let x = values.optionalNumber("x"), let y = values.optionalNumber("y"),
           let width = values.optionalNumber("width"), let height = values.optionalNumber("height"),
           width > 0, height > 0 {
            rect = CropRect(x: x, y: y, width: width, height: height)
        }
        quarterTurns = ((Int(values.number("quarterTurns", default: 0)) % 4) + 4) % 4
        angle = min(max(values.number("angle", default: 0), Self.angleRange.lowerBound), Self.angleRange.upperBound)
    }

    public var isIdentity: Bool { rect == nil && quarterTurns == 0 && angle == 0 }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        if let rect {
            out.set("x", rect.x)
            out.set("y", rect.y)
            out.set("width", rect.width)
            out.set("height", rect.height)
        }
        out.set("quarterTurns", Double(quarterTurns), default: 0)
        out.set("angle", angle, default: 0)
        return out.values
    }

    /// Size of a frame of `size` after the quarter turns.
    public func turnedSize(_ size: CGSize) -> CGSize {
        quarterTurns.isMultiple(of: 2) ? size : CGSize(width: size.height, height: size.width)
    }

    /// How much larger than the output the source must be decoded so the
    /// cropped part keeps the output's resolution. `sourceSize` may be given
    /// before or after the EXIF orientation: the larger answer is used.
    public func sourceZoom(sourceSize: CGSize) -> Double {
        let rect = rect ?? .full
        func zoom(_ size: CGSize) -> Double {
            let longest = max(size.width, size.height)
            let kept = max(rect.width * size.width, rect.height * size.height)
            return kept > 0 ? longest / kept : 1
        }
        let swapped = CGSize(width: sourceSize.height, height: sourceSize.width)
        return max(1, zoom(sourceSize), zoom(swapped))
    }

    /// Turns, straightens and crops `image`. The result's extent starts at the origin.
    public func apply(to image: CIImage) -> CIImage {
        guard !isIdentity else { return image }
        let extent = image.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return image }
        let turned = turnedSize(extent.size)
        // Core Image's y axis points up, so a clockwise turn is a negative angle.
        let radians = -(Double(quarterTurns) * .pi / 2 + angle * .pi / 180)
        var rotation = CGAffineTransform(rotationAngle: radians)
        if angle == 0 {
            // Exact quarter turns keep pixels on the grid.
            let (cos, sin): (CGFloat, CGFloat) = [(1, 0), (0, -1), (-1, 0), (0, 1)][quarterTurns]
            rotation = CGAffineTransform(a: cos, b: sin, c: -sin, d: cos, tx: 0, ty: 0)
        }
        // About the image's center, then with the turned frame's corner at the origin.
        let transform = CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
            .concatenating(rotation)
            .concatenating(CGAffineTransform(translationX: turned.width / 2, y: turned.height / 2))
        let rect = self.rect ?? .full
        let x = (rect.x * turned.width).rounded()
        let top = ((1 - rect.y) * turned.height).rounded()
        let width = max(1, (rect.width * turned.width).rounded())
        let height = max(1, (rect.height * turned.height).rounded())
        let target = CGRect(x: x, y: top - height, width: width, height: height)
        // Clamping first repeats the edge pixels, so resampling at the border
        // never mixes in transparent black.
        return image.clampedToExtent()
            .transformed(by: transform)
            .cropped(to: target)
            .transformed(by: CGAffineTransform(translationX: -target.minX, y: -target.minY))
    }
}
