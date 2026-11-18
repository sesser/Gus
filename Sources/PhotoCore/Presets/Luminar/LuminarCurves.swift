import Foundation

/// Tone curves of preset packs: their point lists, the curves that stand in
/// for tools with no control here (Supercontrast, Matte), and composing
/// several into one point curve. Curves are evaluated with `MonotoneSpline`,
/// as the renderer evaluates a point curve.
enum LuminarCurves {
    typealias Curve = @Sendable (Double) -> Double

    /// Points a composed curve is sampled at.
    static let sampleCount = 17

    /// The points of a curve parameter's option value, stored as
    /// `[c, x0, y0, x1, y1, …]` (0 … 1) where the leading value is not a
    /// coordinate, as a list or as the text of one (`"['0.5', '0', …]"`).
    /// Nil when it holds no curve.
    static func points(_ value: LuminarTemplate.OptionValue) -> [CurvePoint]? {
        let items: [String]
        switch value {
        case .list(let list):
            items = list
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed != "0",
                  let parsed = try? JSONSerialization.jsonObject(with: Data(trimmed.replacingOccurrences(of: "'", with: "\"").utf8)),
                  let list = parsed as? [Any] else { return nil }
            items = list.map { LuminarTemplate.text($0) }
        }
        var numbers: [Double] = []
        for item in items {
            let number = LuminarTemplate.number(item)
            guard !number.isNaN else { return nil }
            numbers.append(number)
        }
        if numbers.count % 2 == 1 { numbers.removeFirst() }
        guard numbers.count >= 4 else { return nil }
        var points: [CurvePoint] = []
        var index = 0
        while index + 1 < numbers.count {
            points.append(CurvePoint(x: numbers[index], y: numbers[index + 1]))
            index += 2
        }
        return normalized(points)
    }

    /// Sorted by x (stably) and clamped to the unit square; identity under two points.
    static func normalized(_ points: [CurvePoint]) -> [CurvePoint] {
        let clamped = points.map { CurvePoint(x: clamp($0.x), y: clamp($0.y)) }
        let sorted = clamped.enumerated().sorted { a, b in
            a.element.x == b.element.x ? a.offset < b.offset : a.element.x < b.element.x
        }.map(\.element)
        return sorted.count >= 2 ? sorted : ToneCurve.identityPoints
    }

    static func isIdentity(_ points: [CurvePoint]) -> Bool {
        points.allSatisfy { abs($0.x - $0.y) < 1e-9 }
    }

    static func clamp(_ value: Double, _ low: Double = 0, _ high: Double = 1) -> Double {
        min(max(value, low), high)
    }

    static func spline(_ points: [CurvePoint]) -> Curve {
        let spline = MonotoneSpline(points)
        return { spline.value(at: $0) }
    }

    /// `curves` applied in order, sampled at `sampleCount` points, clamped
    /// to the unit square and never decreasing.
    static func sampled(_ curves: [Curve]) -> [CurvePoint] {
        var points: [CurvePoint] = []
        var highest = 0.0
        for index in 0..<sampleCount {
            let x = Double(index) / Double(sampleCount - 1)
            var y = x
            for curve in curves { y = curve(y) }
            highest = max(highest, clamp(y))
            points.append(CurvePoint(x: x, y: highest))
        }
        return points
    }

    /// 1 over most of the range, falling to 0 at black and white.
    private static func endpointGuard(_ x: Double) -> Double {
        min(1, 8 * x * (1 - x))
    }

    /// Contrast within the shadows, midtones and highlights (thirds of the
    /// range): `amounts` (0 … 100) steepen each region around a pivot that
    /// `balances` (−100 … +100) move down (the region brightens) or up.
    static func supercontrast(amounts: [Double], balances: [Double]) -> Curve {
        var regions: [(gain: Double, center: Double, reach: Double, pivot: Double)] = []
        for index in 0..<3 {
            let low = Double(index) / 3, high = Double(index + 1) / 3
            let center = (low + high) / 2, half = (high - low) / 2
            let pivot = center - balances[index] / 100 * half * LuminarMapping.supercontrastPivotTravel
            regions.append((amounts[index] / 100 * LuminarMapping.supercontrastGain, center, half * 1.5, pivot))
        }
        let fixed = regions
        return { x in
            var shift = 0.0
            for region in fixed {
                let distance = (x - region.center) / region.reach
                if region.gain == 0 || abs(distance) >= 1 { continue }
                let window = pow(cos(Double.pi / 2 * distance), 2)
                shift += region.gain * (x - region.pivot) * window
            }
            return clamp(x + shift * endpointGuard(x))
        }
    }

    /// The Matte look: blacks lifted to `fade`% and a mild S-curve of
    /// `contrast`, mixed in by `amount` (0 … 100; contrast −100 … +100).
    static func matte(amount: Double, fade: Double, contrast: Double) -> Curve {
        let lift = clamp(fade / 100)
        let strength = clamp(contrast / 100, -1, 0.9)
        let mix = clamp(amount / 100)
        return { x in
            let s = x + strength * x * (1 - x) * (2 * x - 1)
            let faded = lift + (1 - lift) * s
            return clamp(x + mix * (faded - x))
        }
    }
}
