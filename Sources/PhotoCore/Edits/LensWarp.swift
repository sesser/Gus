import CoreGraphics
import Foundation
import ImageIO

/// How a lens moves points, as the Distortion group corrects it (issue #87):
/// for a point of the corrected picture at radius ρ from the optical center,
/// in units of the frame's half diagonal (times `LensWarp.radiusUnit`), the
/// radius the recorded image has it at, over ρ.
public enum LensRadialModel: Hashable, Sendable {
    /// The manual Amount: `1 − c ρ²`. Positive `c` takes each point from
    /// nearer the center, which straightens lines that bow outward (barrel).
    case manual(c: Double)
    /// DNG `WarpRectilinear` for one plane: `kr0 + kr1 ρ² + kr2 ρ⁴ + kr3 ρ⁶`
    /// (DNG specification 1.3 and later, "WarpRectilinear").
    case polynomial([Double])
    /// A Fujifilm table (`FujifilmRAF.LensTables`, green only): a point
    /// recorded at radius r belongs at r / (1 + D(r) / 100), D linear between
    /// the knots; so the corrected picture's ρ takes the r with
    /// r / (1 + D(r) / 100) = ρ (as `EmbeddedLensCorrection`).
    case fujifilm(knots: [Double], distortion: [Double])

    /// The manual Amount's strength: at ±100 a point at the frame's corner is
    /// taken from 8% of the half diagonal nearer to (or further from) the
    /// center, about the barrel of a wide zoom at its widest (status.md).
    public static let manualCornerShift = 0.08

    /// The model for a manual Amount (−100 … +100).
    public static func manual(amount: Double) -> LensRadialModel {
        .manual(c: manualCornerShift * amount / 100)
    }

    /// Source radius over corrected radius at `rho`.
    public func ratio(_ rho: Double) -> Double {
        switch self {
        case .manual(let c):
            return 1 - c * rho * rho
        case .polynomial(let k):
            let r2 = rho * rho
            return k.reversed().reduce(0) { $0 * r2 + $1 }
        case .fujifilm(let knots, let distortion):
            guard rho > 0 else { return 1 + EmbeddedLensCorrection.value(distortion, knots: knots, at: 0) / 100 }
            return Self.fujifilmSourceRadius(knots: knots, distortion: distortion, destination: rho) / rho
        }
    }

    /// The r with r / (1 + D(r) / 100) = `destination`, by bisection (the
    /// left side grows with r for every plausible table).
    static func fujifilmSourceRadius(knots: [Double], distortion: [Double], destination: Double) -> Double {
        var low = 0.0, high = destination * 2 + 0.1
        for _ in 0..<64 {
            let middle = (low + high) / 2
            let factor = 1 + EmbeddedLensCorrection.value(distortion, knots: knots, at: middle) / 100
            if middle / factor < destination { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    /// Moves nothing.
    public var isIdentity: Bool {
        switch self {
        case .manual(let c): c == 0
        case .polynomial(let k): k.first == 1 && k.dropFirst().allSatisfy { $0 == 0 }
        case .fujifilm(_, let distortion): distortion.allSatisfy { $0 == 0 }
        }
    }
}

/// How much light a lens lost toward the corners, as the Lens Vignetting
/// group gives it back: the gain at radius ρ of the recorded image, in units
/// of the frame's half diagonal (times `LensGain.radiusUnit`).
public enum LensGainModel: Hashable, Sendable {
    /// The manual Amount: `(1 + ρ²)^(2 a / 100)`, the shape of the cos⁴
    /// fall-off of a lens whose corner is 45° off its axis; ±100 gives ±2 EV
    /// at the corner.
    case manual(amount: Double)
    /// DNG `FixVignetteRadial`: `1 + k0 ρ² + k1 ρ⁴ + k2 ρ⁶ + k3 ρ⁸ + k4 ρ¹⁰`.
    case polynomial([Double])
    /// A Fujifilm table: 100 / V(r), V the light at r in percent of the center's.
    case fujifilm(knots: [Double], vignetting: [Double])

    public func gain(_ rho: Double) -> Double {
        switch self {
        case .manual(let amount):
            return pow(1 + rho * rho, 2 * amount / 100)
        case .polynomial(let k):
            let r2 = rho * rho
            return 1 + r2 * k.reversed().reduce(0) { $0 * r2 + $1 }
        case .fujifilm(let knots, let vignetting):
            let light = EmbeddedLensCorrection.value(vignetting, knots: knots, at: rho)
            return light > 0 ? 100 / light : 1
        }
    }

    public var isIdentity: Bool {
        switch self {
        case .manual(let amount): amount == 0
        case .polynomial(let k): k.allSatisfy { $0 == 0 }
        case .fujifilm(_, let vignetting): vignetting.allSatisfy { $0 == 100 }
        }
    }
}

/// The distance between two points. Written out in scalars, with explicit
/// types: Swift 6.2's type checker gave up on the same SIMD expressions in a
/// closure (CI on macOS 15, PR #230).
@inline(__always)
func lensDistance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
    let dx: Double = a.x - b.x
    let dy: Double = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
}

/// Where a correction's radii are measured from and in what unit, relative
/// to the frame it is applied to: the optical center's offset from the
/// frame's center and the unit radius, both in units of the frame's half
/// diagonal, the offset in the sensor's own orientation (x to the right, y
/// down), and the orientation the decoded image has relative to the sensor.
public struct LensFrameGeometry: Hashable, Sendable {
    public var centerOffset: SIMD2<Double>
    public var radiusUnit: Double
    public var orientation: CGImagePropertyOrientation

    public init(centerOffset: SIMD2<Double> = .zero, radiusUnit: Double = 1, orientation: CGImagePropertyOrientation = .up) {
        self.centerOffset = centerOffset
        self.radiusUnit = radiusUnit
        self.orientation = orientation
    }

    public static let centered = LensFrameGeometry()

    /// The matrix taking a vector of the decoded image in Core Image's
    /// coordinates (y up) to the sensor's (y down), rows first. A turn or a
    /// flip: its inverse is its transpose.
    public var toSensor: (Double, Double, Double, Double) {
        // The decoded image is the sensor's picture with `orientation` applied
        // (in y-down terms: 2 flips x, 3 turns 180°, 4 flips y, 5 swaps x and y,
        // 6 turns 90° clockwise, 7 swaps and negates both, 8 turns 90° counter-
        // clockwise); a vector of it in Core Image's terms is that with y
        // negated. These rows undo both.
        switch orientation {
        case .up: (1, 0, 0, -1)
        case .upMirrored: (-1, 0, 0, -1)
        case .down: (-1, 0, 0, 1)
        case .downMirrored: (1, 0, 0, 1)
        case .leftMirrored: (0, -1, 1, 0)
        case .right: (0, -1, -1, 0)
        case .rightMirrored: (0, 1, -1, 0)
        case .left: (0, 1, 1, 0)
        @unknown default: (1, 0, 0, -1)
        }
    }

    /// A sensor vector in the decoded image's coordinates (the transpose).
    func fromSensor(_ v: SIMD2<Double>) -> SIMD2<Double> {
        let m = toSensor
        let x: Double = m.0 * v.x + m.2 * v.y
        let y: Double = m.1 * v.x + m.3 * v.y
        return SIMD2<Double>(x, y)
    }

    func toSensor(_ v: SIMD2<Double>) -> SIMD2<Double> {
        let m = toSensor
        let x: Double = m.0 * v.x + m.1 * v.y
        let y: Double = m.2 * v.x + m.3 * v.y
        return SIMD2<Double>(x, y)
    }

    /// The unit radius in pixels of `frame`.
    func radius(of frame: CGRect) -> Double {
        radiusUnit * hypot(Double(frame.width), Double(frame.height)) / 2
    }

    /// The optical center in Core Image coordinates of `frame`.
    func center(of frame: CGRect) -> SIMD2<Double> {
        let halfDiagonal = hypot(Double(frame.width), Double(frame.height)) / 2
        let offset: SIMD2<Double> = fromSensor(centerOffset)
        let x: Double = Double(frame.midX) + offset.x * halfDiagonal
        let y: Double = Double(frame.midY) + offset.y * halfDiagonal
        return SIMD2<Double>(x, y)
    }
}

/// A distortion correction ready to apply to a frame: the radial model, a
/// DNG's tangential terms, where it is centered, and whether the corrected
/// picture is scaled to fill its frame (Constrain to image).
public struct LensWarp: Hashable, Sendable {
    public var radial: LensRadialModel
    /// DNG `WarpRectilinear`'s kt0 and kt1, in the sensor's orientation.
    public var tangential: SIMD2<Double>
    public var geometry: LensFrameGeometry
    public var fills: Bool

    public init(radial: LensRadialModel, tangential: SIMD2<Double> = .zero, geometry: LensFrameGeometry = .centered,
                fills: Bool) {
        self.radial = radial
        self.tangential = tangential
        self.geometry = geometry
        self.fills = fills
    }

    /// Moves nothing (whatever `fills` says: an identity fills its frame at scale 1).
    public var isIdentity: Bool { radial.isIdentity && tangential == .zero }

    /// The point of the recorded image a point of the corrected picture (in
    /// units of the radius, about the optical center, decoded orientation,
    /// Core Image's y up) is taken from, in the same units.
    func source(ofNormalized d: SIMD2<Double>) -> SIMD2<Double> {
        let u: SIMD2<Double> = geometry.toSensor(d)
        let r2: Double = u.x * u.x + u.y * u.y
        let ratio: Double = radial.ratio(r2.squareRoot())
        let kt0: Double = tangential.x, kt1: Double = tangential.y
        // The same operations, in the same order, as one SIMD expression had them.
        let tx: Double = kt0 * 2 * u.x * u.y + kt1 * (r2 + 2 * u.x * u.x)
        let ty: Double = kt1 * 2 * u.x * u.y + kt0 * (r2 + 2 * u.y * u.y)
        let sx: Double = u.x * ratio + tx
        let sy: Double = u.y * ratio + ty
        return geometry.fromSensor(SIMD2<Double>(sx, sy))
    }

    /// The scale the corrected picture is shown at in `frame`: 1, or with
    /// `fills` one at which every point of the frame's edge is taken from
    /// within the frame, so it has no empty edge.
    ///
    /// A warp about the frame's middle with no tangential terms takes the
    /// largest source-over-corrected ratio between the short side's middle
    /// and the corner, as the camera's own pictures and the Fujifilm step do
    /// (`EmbeddedLensCorrection.outputScale`; it agrees with an X-E3's JPEG
    /// to a third of a pixel): for a ratio that only grows or only falls
    /// with the radius that fills the frame exactly at the short side or the
    /// corner. Any other warp (a DNG's off-center or tangential one) takes
    /// the smallest scale at which 256 points of the edge read from within it.
    public func scale(in frame: CGRect) -> Double {
        guard fills, !isIdentity, frame.width > 0, frame.height > 0 else { return 1 }
        if geometry.centerOffset == .zero, tangential == .zero {
            let halfDiagonal = hypot(Double(frame.width), Double(frame.height)) / 2
            let unit = geometry.radiusUnit * halfDiagonal
            let short = Double(min(frame.width, frame.height)) / 2 / unit, corner = halfDiagonal / unit
            var largest = -Double.infinity
            for step in 0..<200 {
                let rho: Double = short + (corner - short) * Double(step) / 199
                largest = max(largest, radial.ratio(rho))
            }
            return largest
        }
        let radius = geometry.radius(of: frame)
        let center = geometry.center(of: frame)
        let edge = Self.edgePoints(of: frame)
        let minX = Double(frame.minX) - 0.01, maxX = Double(frame.maxX) + 0.01
        let minY = Double(frame.minY) - 0.01, maxY = Double(frame.maxY) + 0.01
        func fits(_ scale: Double) -> Bool {
            let unit: Double = radius * scale
            for point in edge {
                let d = SIMD2<Double>((point.x - center.x) / unit, (point.y - center.y) / unit)
                let s: SIMD2<Double> = source(ofNormalized: d)
                let px: Double = center.x + s.x * radius
                let py: Double = center.y + s.y * radius
                if px < minX || px > maxX || py < minY || py > maxY { return false }
            }
            return true
        }
        var low = 0.25, high = 4.0
        guard fits(high) else { return 1 }
        if fits(low) { return low }
        for _ in 0..<50 {
            let middle = (low + high) / 2
            if fits(middle) { high = middle } else { low = middle }
        }
        return high
    }

    /// `count` + 1 points along each side of `frame`, its corners included.
    static func edgePoints(of frame: CGRect, count n: Int = 64) -> [SIMD2<Double>] {
        var points: [SIMD2<Double>] = []
        for i in 0...n {
            let t = Double(i) / Double(n)
            let x = Double(frame.minX) + t * Double(frame.width), y = Double(frame.minY) + t * Double(frame.height)
            points += [SIMD2(x, Double(frame.minY)), SIMD2(x, Double(frame.maxY)),
                       SIMD2(Double(frame.minX), y), SIMD2(Double(frame.maxX), y)]
        }
        return points
    }

    /// The pixel of the recorded image (Core Image coordinates) that `point`
    /// of the corrected picture shown in `frame` at `scale` is taken from.
    public func source(of point: CGPoint, in frame: CGRect, scale: Double) -> CGPoint {
        let radius = geometry.radius(of: frame)
        let center = geometry.center(of: frame)
        let unit: Double = radius * scale
        let d = SIMD2<Double>((Double(point.x) - center.x) / unit, (Double(point.y) - center.y) / unit)
        let s: SIMD2<Double> = source(ofNormalized: d)
        return CGPoint(x: center.x + s.x * radius, y: center.y + s.y * radius)
    }
}

/// A vignetting correction ready to apply: its model and where it is centered.
public struct LensGain: Hashable, Sendable {
    public var model: LensGainModel
    public var geometry: LensFrameGeometry

    public init(model: LensGainModel, geometry: LensFrameGeometry = .centered) {
        self.model = model
        self.geometry = geometry
    }

    public var isIdentity: Bool { model.isIdentity }

    /// The gain at `point` (Core Image coordinates) of `frame`.
    public func gain(at point: CGPoint, in frame: CGRect) -> Double {
        let center = geometry.center(of: frame)
        let distance: Double = lensDistance(SIMD2<Double>(Double(point.x), Double(point.y)), center)
        return model.gain(distance / geometry.radius(of: frame))
    }

    /// A value `v` with `gain` applied: lifted at most to the decode's white
    /// (1), where a value already above it stays as it is, so a clipped area
    /// stays even toward the corners (as `EmbeddedLensCorrection` and the
    /// camera); lowered without a limit.
    public static func apply(_ gain: Double, to v: Double) -> Double {
        gain >= 1 ? max(min(v * gain, 1), v) : v * gain
    }
}

/// What the Distortion and Lens Vignetting groups apply to one photo: the
/// group's own values against what its file allows (`CameraLensState`). One
/// rule for every render, the Adjust tab's status and the question of
/// whether a change moves the corrected frame (design §6).
public struct LensCorrectionPlan: Hashable, Sendable {
    public var warp: LensWarp?
    public var gain: LensGain?

    public init(warp: LensWarp? = nil, gain: LensGain? = nil) {
        self.warp = warp
        self.gain = gain
    }

    /// - Parameter values: The effective adjustments (a group turned off is
    ///   at its defaults there, so off).
    public init(_ values: Adjustments, lens: CameraLensState?) {
        let distortion = values.distortion
        if distortion.isOn {
            switch distortion.source {
            case .manual:
                let warp = LensWarp(radial: .manual(amount: distortion.amount), fills: distortion.constrain)
                self.warp = warp.isIdentity ? nil : warp
            case .auto:
                if var warp = lens?.tables?.distortion, !warp.isIdentity {
                    warp.fills = distortion.constrain
                    self.warp = warp
                }
            }
        }
        let vignetting = values.lensVignetting
        if vignetting.isOn {
            switch vignetting.source {
            case .manual:
                let gain = LensGain(model: .manual(amount: vignetting.amount))
                self.gain = gain.isIdentity ? nil : gain
            case .auto:
                if let gain = lens?.tables?.vignetting, !gain.isIdentity { self.gain = gain }
            }
        }
    }

    public var isIdentity: Bool { warp == nil && gain == nil }

    /// Whether `other` puts the picture's points elsewhere in the frame than
    /// this plan: the frame the masks and spots are placed in moves (R6).
    public func movesFrame(comparedWith other: LensCorrectionPlan) -> Bool {
        warp != other.warp
    }
}
