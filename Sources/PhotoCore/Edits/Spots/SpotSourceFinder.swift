import CoreGraphics
import CoreImage
import Foundation

/// Chooses a spot's source automatically (PRD R3, R16, R17).
///
/// Candidates lie on rings around the spot (2.25, 2.75, 3.5, 4.5 and 6
/// radii away, 16 directions each, the nearest ring first and the
/// directions counterclockwise from the right). A candidate is allowed
/// when its circle lies inside the photo and overlaps neither its own spot
/// nor any other spot. Of those, the ones wholly inside the visible crop
/// come first (design §5.5); among them the lowest score wins, the first in
/// that order on a tie. The score, on perceptual luminance:
///
/// - **context**: how well the ring around the spot (1.15 to 1.55 radii,
///   the clean surroundings a fill must continue) matches the same ring
///   around the candidate: the mean squared difference with the mean
///   difference taken out (structure), plus a quarter of the mean
///   difference squared (tone, which Heal corrects and Clone does not).
///   Matching the known surroundings of a hole against candidate patches
///   is exemplar-based filling's measure (Criminisi, Pérez and Toyama,
///   "Region Filling and Object Removal by Exemplar-Based Image
///   Inpainting", IEEE TIP 2004).
/// - **busyness**: how much more the candidate's own circle varies than the
///   spot's surroundings do, so a busy area loses to a quieter one nearby.
/// - **distance**: the sum is scaled by 1 + 0.1 per radius beyond the
///   nearest ring, so of two equal candidates the nearer wins.
///
/// Pure arithmetic in a fixed order over a `LuminanceWindow`: the same
/// inputs give the same source, which is what lets Choose Source
/// Automatically promise placement's answer (AC14).
public enum SpotSourceFinder {
    public static let ringDistances: [Double] = [2.25, 2.75, 3.5, 4.5, 6]
    public static let directions = 16
    /// How far around the spot the window must reach, in radii.
    public static let reach = 7.75

    /// What the finder needs, in pixels of the mask frame (top left origin, y down).
    public struct Request: Sendable {
        public var center: CGPoint
        public var radius: Double
        public var frameSize: CGSize
        /// Other spots' circles: (center, radius).
        public var others: [(center: CGPoint, radius: Double)]
        /// The crop's corners in the mask frame, in order around it; empty for none.
        public var visibleArea: [CGPoint]

        public init(center: CGPoint, radius: Double, frameSize: CGSize, others: [(center: CGPoint, radius: Double)] = [],
                    visibleArea: [CGPoint] = []) {
            self.center = center
            self.radius = radius
            self.frameSize = frameSize
            self.others = others
            self.visibleArea = visibleArea
        }
    }

    /// The source's center for `request` over `window`, or nil when no
    /// candidate is allowed (the spot too large for the photo, or every
    /// place taken by other spots or past the edges).
    public static func find(_ request: Request, in window: LuminanceWindow) -> CGPoint? {
        let r = request.radius
        guard r > 0, r.isFinite else { return nil }
        let geometry = SpotGeometry(frameSize: request.frameSize)
        let target = Ring(window: window, center: request.center, radius: r)
        var best: (inside: Bool, score: Double, point: CGPoint)?
        for distance in ringDistances {
            for direction in 0..<directions {
                let angle = 2 * Double.pi * Double(direction) / Double(directions)
                // Counterclockwise on screen: y down, so up is −y.
                let point = CGPoint(x: Double(request.center.x) + cos(angle) * distance * r,
                                    y: Double(request.center.y) - sin(angle) * distance * r)
                guard allowed(point, radius: r, request: request, geometry: geometry) else { continue }
                let offset = CGVector(dx: point.x - request.center.x, dy: point.y - request.center.y)
                guard let score = score(target: target, offset: offset, window: window) else { continue }
                let total = score * (1 + 0.1 * (distance - ringDistances[0]))
                let inside = isInside(point, radius: r, area: request.visibleArea)
                if let current = best {
                    if current.inside && !inside { continue }
                    if current.inside == inside, total >= current.score { continue }
                }
                best = (inside, total, point)
            }
        }
        return best?.point
    }

    /// Inside the frame (a pixel's margin for the boundary window), clear of its own spot and every other.
    static func allowed(_ point: CGPoint, radius r: Double, request: Request, geometry: SpotGeometry) -> Bool {
        let margin = 1.0
        let width = Double(request.frameSize.width), height = Double(request.frameSize.height)
        let x = Double(point.x), y = Double(point.y)
        guard x - r - margin >= 0, y - r - margin >= 0, x + r + margin <= width, y + r + margin <= height else {
            return false
        }
        if hypot(x - Double(request.center.x), y - Double(request.center.y)) < 2 * r { return false }
        for other in request.others where hypot(x - Double(other.center.x), y - Double(other.center.y)) < r + other.radius {
            return false
        }
        return true
    }

    /// The candidate's circle (its center and eight points on it) inside the convex `area`; true without one.
    static func isInside(_ point: CGPoint, radius: Double, area: [CGPoint]) -> Bool {
        guard area.count >= 3 else { return true }
        let points = [point] + (0..<8).map { index -> CGPoint in
            let angle = Double(index) * .pi / 4
            return CGPoint(x: Double(point.x) + cos(angle) * radius, y: Double(point.y) + sin(angle) * radius)
        }
        return points.allSatisfy { inConvex($0, area) }
    }

    static func inConvex(_ p: CGPoint, _ polygon: [CGPoint]) -> Bool {
        var sign = 0.0
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            let cross = Double((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x))
            if abs(cross) < 1e-9 { continue }
            if sign == 0 { sign = cross } else if (cross > 0) != (sign > 0) { return false }
        }
        return true
    }

    /// The sample points around the spot, and their luminance (nil where
    /// the ring passes the photo's edge: those points are left out).
    struct Ring {
        /// Offsets from the center (pixels).
        var context: [CGVector] = []
        var values: [Double?] = []
        var interior: [CGVector] = []
        var variance = 0.0

        init(window: LuminanceWindow, center: CGPoint, radius r: Double) {
            for rho in [1.15, 1.35, 1.55] {
                for step in 0..<24 {
                    let angle = 2 * Double.pi * (Double(step) + 0.5) / 24
                    context.append(CGVector(dx: cos(angle) * rho * r, dy: sin(angle) * rho * r))
                }
            }
            interior = [CGVector(dx: 0, dy: 0)]
            for rho in [0.35, 0.65, 0.92] {
                for step in 0..<12 {
                    let angle = 2 * Double.pi * Double(step) / 12
                    interior.append(CGVector(dx: cos(angle) * rho * r, dy: sin(angle) * rho * r))
                }
            }
            values = context.map { window.value(at: CGPoint(x: center.x + $0.dx, y: center.y + $0.dy)) }
            variance = Self.variance(values.compactMap { $0 })
        }

        static func variance(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let mean = values.reduce(0, +) / Double(values.count)
            return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        }
    }

    /// Context mismatch plus excess busyness of the candidate at `offset`; nil
    /// when the window does not cover it.
    static func score(target: Ring, offset: CGVector, window: LuminanceWindow) -> Double? {
        var differences: [Double] = []
        differences.reserveCapacity(target.context.count)
        for (index, vector) in target.context.enumerated() {
            guard let known = target.values[index] else { continue }
            guard let value = window.value(at: CGPoint(x: window.spotCenter.x + vector.dx + offset.dx,
                                                       y: window.spotCenter.y + vector.dy + offset.dy)) else { return nil }
            differences.append(known - value)
        }
        guard !differences.isEmpty else { return nil }
        let mean = differences.reduce(0, +) / Double(differences.count)
        let structure = differences.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(differences.count)
        var inside: [Double] = []
        inside.reserveCapacity(target.interior.count)
        for vector in target.interior {
            guard let value = window.value(at: CGPoint(x: window.spotCenter.x + vector.dx + offset.dx,
                                                       y: window.spotCenter.y + vector.dy + offset.dy)) else { return nil }
            inside.append(value)
        }
        let busy = max(0, Ring.variance(inside) - target.variance)
        return structure + 0.25 * mean * mean + busy + 1e-9
    }
}

/// Perceptual luminance (Rec. 2020 Y in the sRGB curve, as the Lens
/// heading's luma) of a square of the mask frame around a spot, at most
/// `maximumSide` samples across, read by bilinear interpolation in mask
/// frame pixels.
public struct LuminanceWindow: Sendable {
    /// Where the spot is, in mask frame pixels.
    public var spotCenter: CGPoint
    /// The window's top left corner in mask frame pixels.
    public var origin: CGPoint
    /// Mask frame pixels per sample.
    public var step: Double
    public var width: Int
    public var height: Int
    /// Rows from the top.
    public var values: [Float]

    public static let maximumSide = 384

    public init(spotCenter: CGPoint, origin: CGPoint, step: Double, width: Int, height: Int, values: [Float]) {
        precondition(values.count == width * height)
        self.spotCenter = spotCenter
        self.origin = origin
        self.step = step
        self.width = width
        self.height = height
        self.values = values
    }

    /// The window a spot of `radius` at `center` needs over a frame of
    /// `frameSize`: `SpotSourceFinder.reach` radii around it, clipped to the
    /// frame, sampled no finer than one frame pixel.
    public static func layout(center: CGPoint, radius: Double, frameSize: CGSize)
        -> (origin: CGPoint, step: Double, width: Int, height: Int) {
        let reach = SpotSourceFinder.reach * radius
        let minX = max(0, (Double(center.x) - reach).rounded(.down))
        let minY = max(0, (Double(center.y) - reach).rounded(.down))
        let maxX = min(Double(frameSize.width), (Double(center.x) + reach).rounded(.up))
        let maxY = min(Double(frameSize.height), (Double(center.y) + reach).rounded(.up))
        let side = max(maxX - minX, maxY - minY, 1)
        let step = max(1, side / Double(maximumSide))
        return (CGPoint(x: minX, y: minY), step, max(1, Int(((maxX - minX) / step).rounded(.up))),
                max(1, Int(((maxY - minY) / step).rounded(.up))))
    }

    /// The luminance at a mask frame point, or nil outside the window.
    public func value(at point: CGPoint) -> Double? {
        // Sample centers at origin + (i + 0.5) · step.
        let u = (Double(point.x) - Double(origin.x)) / step - 0.5
        let v = (Double(point.y) - Double(origin.y)) / step - 0.5
        guard u >= -0.5, v >= -0.5, u <= Double(width) - 0.5, v <= Double(height) - 0.5 else { return nil }
        let x0 = min(max(Int(u.rounded(.down)), 0), width - 1), y0 = min(max(Int(v.rounded(.down)), 0), height - 1)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let tx = min(max(u - Double(x0), 0), 1), ty = min(max(v - Double(y0), 0), 1)
        func at(_ x: Int, _ y: Int) -> Double { Double(values[y * width + x]) }
        let top = at(x0, y0) + (at(x1, y0) - at(x0, y0)) * tx
        let bottom = at(x0, y1) + (at(x1, y1) - at(x0, y1)) * tx
        return top + (bottom - top) * ty
    }

    /// Renders the window from `image`, the image entering the spot step
    /// (its extent the mask frame), through `engine`. Nil when the render fails.
    public static func render(_ image: CIImage, center: CGPoint, radius: Double, engine: RenderEngine) -> LuminanceWindow? {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty else { return nil }
        let frame = CGSize(width: extent.width, height: extent.height)
        let layout = layout(center: center, radius: radius, frameSize: frame)
        let scale = 1 / layout.step
        // Core Image is y up: the window's bottom edge, in the frame's own
        // coordinates, is the frame's height less the window's top and height.
        let bottom = Double(frame.height) - Double(layout.origin.y) - Double(layout.height) * layout.step
        var source = image.clampedToExtent()
        if layout.step > 1 {
            // An area average, so a coarse window still sees fine texture's level.
            source = source.applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: max(1, layout.step / 2)])
        }
        // The window's corner to the origin, then one sample per pixel: sample
        // i's center is origin + (i + ½) · step in the frame (rows top first).
        let placed = source
            .transformed(by: CGAffineTransform(translationX: -extent.minX - Double(layout.origin.x),
                                               y: -extent.minY - bottom))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
        var pixels = [Float](repeating: 0, count: layout.width * layout.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            engine.withContext {
                $0.render(placed.cropped(to: bounds), toBitmap: base, rowBytes: layout.width * 16, bounds: bounds,
                          format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
            }
            return true
        }
        guard rendered else { return nil }
        var values = [Float](repeating: 0, count: layout.width * layout.height)
        for index in values.indices {
            let y = Double(pixels[index * 4]) * 0.2627 + Double(pixels[index * 4 + 1]) * 0.6780
                + Double(pixels[index * 4 + 2]) * 0.0593
            values[index] = Float(encodeSRGB(y))
        }
        return LuminanceWindow(spotCenter: center, origin: layout.origin, step: layout.step, width: layout.width,
                               height: layout.height, values: values)
    }

    static func encodeSRGB(_ v: Double) -> Double {
        let c = min(max(v, 0), 1)
        return c <= 0.003_130_8 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}

extension SpotSourceFinder {
    /// The source for a spot of `size` at `center` over `image`, the image
    /// entering the spot step, avoiding `others` and preferring the inside of
    /// `crop`. The one path placement and Choose Source Automatically take
    /// (AC14). Nil when none is allowed or the window could not be rendered.
    public static func source(for center: MaskPoint, size: Double, others: [Spot], crop: Crop, image: CIImage,
                              engine: RenderEngine) -> MaskPoint? {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty else { return nil }
        let geometry = SpotGeometry(frameSize: extent.size)
        let centerPixels = geometry.pixels(center)
        let radius = geometry.radius(size)
        let request = Request(center: centerPixels, radius: radius, frameSize: extent.size,
                              others: others.map { (geometry.pixels($0.center), geometry.radius($0.size)) },
                              visibleArea: visibleArea(crop: crop, frameSize: extent.size))
        guard let window = LuminanceWindow.render(image, center: centerPixels, radius: radius, engine: engine),
              let point = find(request, in: window) else { return nil }
        return geometry.unit(point)
    }

    /// The crop's corners in mask frame pixels; empty when the crop keeps everything.
    static func visibleArea(crop: Crop, frameSize: CGSize) -> [CGPoint] {
        guard !crop.isIdentity else { return [] }
        return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)].map {
            let mapped = CropGeometry.outputToMask($0, crop: crop, sourceSize: frameSize)
            return CGPoint(x: mapped.x * frameSize.width, y: mapped.y * frameSize.height)
        }
    }
}
