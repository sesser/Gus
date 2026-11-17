import Foundation

/// How noisy a raw is: the variance of a sensor value as a function of its
/// level, σ²(x) = a·x + b, with x the value after its black is taken off,
/// over the white span (0 … 1), before any multiplier. The Poissonian–
/// Gaussian model of Foi, Trimeche, Katkovnik and Egiazarian ("Practical
/// Poissonian-Gaussian noise modeling and fitting for single-image raw-data",
/// IEEE TIP 17(10), 2008): `a` the photon (signal-dependent) part, `b` the
/// read noise.
///
/// **Estimated from the file itself**, so the color noise reduction
/// (`GPUDemosaic`, R9) follows each camera and ISO with no table and no
/// setting: pairs of neighbouring green sites differ by noise alone where the
/// picture is smooth, so the spread of their differences at each level, made
/// robust to the edges among them (the median absolute deviation, Hampel's
/// estimator of scale, taken as the median of |difference|, read from a
/// histogram in steps of 1/64 octave), gives σ² at that level; a line through those points,
/// weighted by how many pairs each has, gives `a` and `b`. The pairs are a
/// fixed sample of the whole visible area (every eighth row), so a crop of
/// the same file, or the same file twice, gets the same model.
public struct NoiseModel: Sendable, Hashable {
    public var a: Double
    public var b: Double

    public init(a: Double, b: Double) {
        self.a = max(a, 0)
        self.b = max(b, 0)
    }

    public static let none = NoiseModel(a: 0, b: 0)

    /// Variance at a normalized level.
    public func variance(at level: Double) -> Double { a * max(level, 0) + b }

    /// Rows of pairs taken: one in this many.
    static let rowStep = 8
    /// Levels are binned; a bin needs this many pairs to count.
    static let binCount = 32
    static let minimumPairs = 400
    /// Pairs whose mean is above this part of white are left out: clipping squeezes their spread.
    static let highestLevel = 0.9
    static let lowestOctave = -24.0
    static let stepsPerOctave = 64
    static let histogramCount = 24 * 64 + 2

    /// The model of a mosaic, or `.none` when it has too few smooth pairs to tell.
    public static func estimate(_ mosaic: SensorMosaic) -> NoiseModel {
        let pattern = mosaic.pattern, p = pattern.period
        // The nearest green neighbour every green site of the pattern has in one direction:
        // to the right (X-Trans' 2 x 2 greens), else diagonally (Bayer).
        let offsets = [(1, 0), (1, 1), (0, 1), (1, -1)]
        func pairsGreens(_ o: (Int, Int)) -> Bool {
            for site in 0..<(p * p) where pattern.colors[site] == 1 {
                let x: Int = (site % p + o.0 + p) % p
                let y: Int = (site / p + o.1 + p) % p
                if pattern.color(x: x, y: y) == 1 { return true }
            }
            return false
        }
        guard let offset = offsets.first(where: pairsGreens) else { return .none }
        let values = mosaic.values, w = mosaic.width, h = mosaic.height
        let black = mosaic.blackPerSite, span = Double(mosaic.whiteSpan)
        // Per level bin, a histogram of log2 |difference| in 1/64 octave steps from 2⁻²⁴.
        var histograms = [[UInt32]](repeating: [UInt32](repeating: 0, count: histogramCount), count: binCount)
        var counts = [Int](repeating: 0, count: binCount)
        var levels = [Double](repeating: 0, count: binCount)
        for y in stride(from: 1, to: h - 1, by: rowStep) {
            let ny = y + offset.1
            for x in 0..<(w - 1) where pattern.color(x: x, y: y) == 1 && pattern.color(x: x + offset.0, y: ny) == 1 {
                let s1 = (y % p) * p + x % p, s2 = (ny % p) * p + (x + offset.0) % p
                let v1 = min(max(Double(values[y * w + x]) - Double(black[s1]), 0), span) / span
                let v2 = min(max(Double(values[ny * w + x + offset.0]) - Double(black[s2]), 0), span) / span
                let level = (v1 + v2) / 2
                guard level > 0, level < highestLevel else { continue }
                let bin = min(binCount - 1, Int(level / highestLevel * Double(binCount)))
                let difference = abs(v1 - v2)
                let slot = difference > 0
                    ? min(histogramCount - 1, max(0, Int((log2(difference) - lowestOctave) * Double(stepsPerOctave)) + 1)) : 0
                histograms[bin][slot] += 1
                counts[bin] += 1
                levels[bin] += level
            }
        }
        // σ² per bin from the median absolute deviation of the differences (each difference holds two samples' noise).
        var points: [(level: Double, variance: Double, weight: Double)] = []
        for index in 0..<binCount where counts[index] >= minimumPairs {
            // The median |difference|: the slot where half the pairs are reached, read at its middle.
            let half = UInt32(counts[index] / 2)
            var seen: UInt32 = 0, slot = 0
            while slot < histogramCount {
                seen += histograms[index][slot]
                if seen > half { break }
                slot += 1
            }
            let median = slot == 0 ? 0 : pow(2, lowestOctave + (Double(slot) - 0.5) / Double(stepsPerOctave))
            let sigma = 1.4826 * median
            points.append((levels[index] / Double(counts[index]), sigma * sigma / 2, Double(counts[index])))
        }
        guard points.count >= 2 else { return .none }
        // Weighted least squares of variance = a·level + b.
        var sw = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for point in points {
            sw += point.weight
            sx += point.weight * point.level
            sy += point.weight * point.variance
            sxx += point.weight * point.level * point.level
            sxy += point.weight * point.level * point.variance
        }
        let determinant = sw * sxx - sx * sx
        guard determinant > 0 else { return .none }
        var a = (sw * sxy - sx * sy) / determinant
        var b = (sy - a * sx) / sw
        if b < 0 {
            // Through the origin.
            a = sxy / sxx
            b = 0
        }
        if a < 0 {
            a = 0
            b = sy / sw
        }
        return NoiseModel(a: a, b: b)
    }
}
