import Foundation
import PhotoFixtures
@testable import PhotoCore

/// Mask shapes without Core Image, in Double, at pixel centers of a
/// `width` × `height` frame (row-major, top row first): the formulas of
/// docs/PHASE6_PLAN.md, "Shapes". smoothstep(e, e, x) is a hard step: 0 below
/// e, 1 from e up.
enum MaskReference {
    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        if e1 <= e0 { return x >= e0 ? 1 : 0 }
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func plane(width: Int, height: Int, _ value: (Double, Double) -> Double) -> [Double] {
        var out = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { out[y * width + x] = value(Double(x) + 0.5, Double(y) + 0.5) }
        }
        return out
    }

    /// Position along start → end, 0 at the start and 1 at the end.
    static func linearPosition(_ g: LinearGradient, _ px: Double, _ py: Double, width: Int, height: Int) -> Double {
        let ax = g.start.x * Double(width), ay = g.start.y * Double(height)
        let dx = g.end.x * Double(width) - ax, dy = g.end.y * Double(height) - ay
        return ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    }

    /// 1 − smoothstep(½ − f/2, ½ + f/2, t); a hard step at ½ for f = 0.
    static func linear(_ g: LinearGradient, width: Int, height: Int) -> [Double] {
        let f = g.feather / 100
        return plane(width: width, height: height) { x, y in
            let t = linearPosition(g, x, y, width: width, height: height)
            return 1 - smoothstep(0.5 - f / 2, 0.5 + f / 2, t)
        }
    }

    /// The elliptical distance: 1 on the ellipse.
    static func radialDistance(_ g: RadialGradient, _ px: Double, _ py: Double, width: Int, height: Int) -> Double {
        let long = Double(max(width, height))
        let dx = px - g.center.x * Double(width), dy = py - g.center.y * Double(height)
        // The ellipse is turned clockwise (y down) by its rotation: turn the point back.
        let angle = g.rotation * .pi / 180
        let u = cos(angle) * dx + sin(angle) * dy
        let v = -sin(angle) * dx + cos(angle) * dy
        return ((u / (g.radiusX * long)) * (u / (g.radiusX * long)) + (v / (g.radiusY * long)) * (v / (g.radiusY * long)))
            .squareRoot()
    }

    /// 1 − smoothstep(1 − f, 1, r); 1 inside and on the ellipse for f = 0.
    static func radial(_ g: RadialGradient, width: Int, height: Int) -> [Double] {
        let f = g.feather / 100
        return plane(width: width, height: height) { x, y in
            let r = radialDistance(g, x, y, width: width, height: height)
            return f > 0 ? 1 - smoothstep(1 - f, 1, r) : (r <= 1 ? 1 : 0)
        }
    }

    /// Dabs a quarter of the radius apart (in long-edge units, so the same
    /// scene points at every resolution), none for a sample that does not move;
    /// each paints 1 in its core and 1 − smoothstep(core, radius, d) beyond;
    /// v ← v + a · flow · (density − v) within a stroke; strokes by max, erase
    /// by v_out · (1 − v). Every pixel visits every dab, in order.
    static func brush(_ brush: Brush, width: Int, height: Int) -> [Double] {
        let long = Double(max(width, height))
        var out = [Double](repeating: 0, count: width * height)
        for stroke in brush.strokes {
            let radius = stroke.size * long
            let core = radius * (1 - stroke.feather / 100)
            var centers: [(Double, Double)] = []
            var last: (Double, Double)?
            for point in stroke.points {
                let p = (point.x * Double(width), point.y * Double(height))
                if let l = last {
                    let distance = hypot(p.0 - l.0, p.1 - l.1)
                    guard distance > 0 else { continue }
                    let n = Int((distance / (radius / 4)).rounded(.up))
                    for k in 1...n {
                        let t = Double(k) / Double(n)
                        centers.append((l.0 + (p.0 - l.0) * t, l.1 + (p.1 - l.1) * t))
                    }
                } else {
                    centers.append(p)
                }
                last = p
            }
            var v = [Double](repeating: 0, count: width * height)
            for y in 0..<height {
                for x in 0..<width {
                    var value = 0.0
                    for center in centers {
                        let d = hypot(Double(x) + 0.5 - center.0, Double(y) + 0.5 - center.1)
                        let a = d > radius ? 0 : (d <= core ? 1 : 1 - smoothstep(core, radius, d))
                        value += a * stroke.flow / 100 * (stroke.density / 100 - value)
                    }
                    v[y * width + x] = value
                }
            }
            for i in out.indices { out[i] = stroke.erase ? out[i] * (1 - v[i]) : max(out[i], v[i]) }
        }
        return out
    }

    /// Perceptual luminance of a linear Rec. 2020 color, clamped to 0 … 1 first.
    static func perceptualLuminance(_ rgb: SIMD3<Double>) -> Double {
        let y = 0.2627 * rgb.x + 0.6780 * rgb.y + 0.0593 * rgb.z
        return ColorMath.encode(min(max(y, 0), 1))
    }

    static func luminance(_ range: LuminanceRange, y: Double) -> Double {
        let s = range.smoothness
        let low = smoothstep(range.lower - s, range.lower, y)
        let high = s > 0 ? 1 - smoothstep(range.upper, range.upper + s, y) : (y <= range.upper ? 1 : 0)
        return low * high
    }

    /// The weighted OkLab distance √(Δa² + Δb² + ¼ΔL²) to the nearest sample,
    /// of the color clamped to 0 … 1.
    static func colorDistance(_ samples: [SIMD3<Double>], _ rgb: SIMD3<Double>) -> Double {
        let lab = ColorMath.okLab(linearRec2020: SIMD3(min(max(rgb.x, 0), 1), min(max(rgb.y, 0), 1),
                                                       min(max(rgb.z, 0), 1)))
        return samples.map { s in
            let d = lab - s
            return (d.y * d.y + d.z * d.z + 0.25 * d.x * d.x).squareRoot()
        }.min() ?? .infinity
    }

    static func color(_ range: ColorRange, d: Double) -> Double {
        let tau = 0.015 + 0.06 * range.tolerance / 100
        return 1 - smoothstep(tau / 2, tau, d)
    }
}
