import Foundation

/// The per-site tables the X-Trans kernels read (`DemosaicKernels`), worked
/// out from the pattern alone, so the kernels hold no pattern of their own
/// and the CPU reference reads the same numbers.
///
/// **Method (this project's, written from published descriptions; nothing
/// taken from another demosaic's code or tables).**
///
/// - *Green at a red or blue site* is estimated along four directions
///   (horizontal, vertical, both diagonals) by the constant color
///   difference assumption (Gunturk, Glotzbach, Altunbasak, Schafer and
///   Mersereau, "Demosaicking: color filter array interpolation", IEEE
///   Signal Processing Magazine 22(1), 2005, section on color difference
///   methods): along the line, G − C is taken as varying linearly between
///   the nearest greens on either side, where C, the site's own color, is
///   interpolated linearly from its nearest samples on the line. On a Bayer
///   pattern this is Hamilton and Adams' estimate (US patent 5,629,734:
///   the greens' mean plus half the own color's second difference); on the
///   X-Trans pattern the greens and own colors lie at uneven distances, and
///   the weights follow from them.
/// - *The four estimates are blended* by inverse squared directional
///   variation, so the direction along an edge dominates (in the manner of
///   Pekkucuksen and Altunbasak, "Gradient based threshold free color filter
///   array interpolation", ICIP 2010, generalized here from two directions
///   to four). The variation of a direction is the mean absolute difference
///   of consecutive same-color samples along it, over three parallel lines
///   through and beside the site.
/// - *Red and blue* are the green less an interpolated color difference
///   (G − R, G − B), from that color's sites in the 5 x 5 window, weighted
///   by inverse squared distance and by inverse squared green difference to
///   the center (edge-directed weights in the manner of Kimmel,
///   "Demosaicing: image reconstruction from color CCD samples", IEEE
///   Transactions on Image Processing 8(9), 1999).
public struct DemosaicTables: Sendable, Hashable {
    /// Horizontal, vertical, down-right, up-right.
    public static let directions: [(dx: Int, dy: Int)] = [(1, 0), (0, 1), (1, 1), (1, -1)]
    /// The site's estimate taps and variation pairs are given for each direction.
    public static let directionCount = 4
    /// Largest number of taps of one direction's green estimate.
    public static let maximumTaps = 8
    /// Largest number of sample pairs of one direction's variation.
    public static let maximumPairs = 16
    /// Largest number of one color's sites in a 5 x 5 window.
    public static let maximumNeighbours = 12
    /// How far a direction looks for a green on each side, in steps.
    static let greenReach = 3
    /// How far it looks for the own color on each side of a green.
    static let colorReach = 6

    public struct Tap: Sendable, Hashable {
        public var dx: Int32
        public var dy: Int32
        public var weight: Float
    }

    public struct Pair: Sendable, Hashable {
        public var ax: Int32
        public var ay: Int32
        public var bx: Int32
        public var by: Int32
        public var weight: Float
    }

    public let pattern: CFAPattern
    /// `[site][direction]`: taps of the green estimate (empty for a green
    /// site, or a direction with no green within reach on a side).
    public let greenTaps: [[[Tap]]]
    /// `[site][direction]`: pairs whose weighted absolute differences sum
    /// to the direction's variation.
    public let variationPairs: [[[Pair]]]
    /// `[site][color]`: that color's sites in the 5 x 5 window, with their
    /// distance weight (empty for the site's own color, and for green).
    public let neighbours: [[[Tap]]]

    public init?(_ pattern: CFAPattern) {
        self.pattern = pattern
        let p = pattern.period
        var green: [[[Tap]]] = []
        var pairs: [[[Pair]]] = []
        var neighbours: [[[Tap]]] = []
        for site in 0..<(p * p) {
            let sx = site % p, sy = site / p
            func color(_ x: Int, _ y: Int) -> Int { pattern.color(x: ((sx + x) % p + p) % p, y: ((sy + y) % p + p) % p) }
            let own = color(0, 0)
            var siteGreen: [[Tap]] = []
            var sitePairs: [[Pair]] = []
            for direction in Self.directions {
                let (dx, dy) = direction
                siteGreen.append(own == 1 ? [] : Self.greenEstimate(own: own, dx: dx, dy: dy, color: color))
                sitePairs.append(Self.variation(dx: dx, dy: dy, color: color))
            }
            var siteNeighbours: [[Tap]] = []
            for target in 0..<3 {
                var list: [Tap] = []
                // Red and blue only: green is estimated at every pixel before them.
                if target != own, target != 1 {
                    for y in -2...2 {
                        for x in -2...2 where !(x == 0 && y == 0) && color(x, y) == target {
                            list.append(Tap(dx: Int32(x), dy: Int32(y), weight: Float(1 / Double(x * x + y * y))))
                        }
                    }
                }
                siteNeighbours.append(Self.centered(list))
            }
            green.append(siteGreen)
            pairs.append(sitePairs)
            neighbours.append(siteNeighbours)
        }
        // Every red or blue site needs at least one direction, every site
        // both other colors in its window, and every list must fit the kernels' arrays.
        for site in 0..<(p * p) {
            let own = pattern.colors[site]
            if own != 1, !green[site].contains(where: { !$0.isEmpty }) { return nil }
            for target in [0, 2] where target != own && neighbours[site][target].isEmpty { return nil }
            if green[site].contains(where: { $0.count > Self.maximumTaps }) { return nil }
            if pairs[site].contains(where: { $0.isEmpty || $0.count > Self.maximumPairs }) { return nil }
            if neighbours[site].contains(where: { $0.count > Self.maximumNeighbours }) { return nil }
        }
        greenTaps = green
        variationPairs = pairs
        self.neighbours = neighbours
    }

    /// Distance weights moved as little as possible (in the chi-squared
    /// sense, w = s (1 + μ + λ·o)) so that their centroid is the center: an
    /// average of the color difference is then exact where the difference
    /// varies linearly (a shaded surface), instead of off by its slope times
    /// the centroid's offset. The weights as they were when that would make
    /// one negative.
    static func centered(_ taps: [Tap]) -> [Tap] {
        guard taps.count >= 3 else { return taps }
        let s = taps.map { Double($0.weight) }
        let o = taps.map { (tap: Tap) -> SIMD2<Double> in SIMD2<Double>(Double(tap.dx), Double(tap.dy)) }
        let total = s.reduce(0, +)
        var m = SIMD2<Double>.zero
        var mxx = 0.0, mxy = 0.0, myy = 0.0
        for (si, oi) in zip(s, o) {
            m += si * oi
            mxx += si * oi.x * oi.x
            mxy += si * oi.x * oi.y
            myy += si * oi.y * oi.y
        }
        // (M − m mᵀ / S) λ = −m, μ = −λ·m / S.
        let a = mxx - m.x * m.x / total, b = mxy - m.x * m.y / total, d = myy - m.y * m.y / total
        let determinant = a * d - b * b
        guard abs(determinant) > 1e-12 else { return taps }
        let lambdaX: Double = (-m.x * d + m.y * b) / determinant
        let lambdaY: Double = (m.x * b - m.y * a) / determinant
        let lambda = SIMD2<Double>(lambdaX, lambdaY)
        let mu: Double = -(lambda * m).sum() / total
        var weights: [Double] = []
        for (si, oi) in zip(s, o) {
            let shift: Double = (lambda * oi).sum()
            weights.append(si * (1 + mu + shift))
        }
        guard weights.allSatisfy({ $0 > 0 }) else { return taps }
        return zip(taps, weights).map { Tap(dx: $0.dx, dy: $0.dy, weight: Float($1)) }
    }

    /// Green at a site of color `own` along (dx, dy): G − C taken as linear
    /// between the nearest greens either side, C interpolated along the line.
    static func greenEstimate(own: Int, dx: Int, dy: Int, color: (Int, Int) -> Int) -> [Tap] {
        func at(_ t: Int) -> Int { color(t * dx, t * dy) }
        guard let plus = (1...greenReach).first(where: { at($0) == 1 }),
              let minus = (1...greenReach).first(where: { at(-$0) == 1 }) else { return [] }
        var weights: [Int: Double] = [0: 1]
        // Weights of the two greens: linear interpolation at 0 from −minus and +plus.
        let span = Double(plus + minus)
        for (position, weight) in [(plus, Double(minus) / span), (-minus, Double(plus) / span)] {
            weights[position, default: 0] += weight
            // The own color at the green: linear between its nearest samples on the line either side
            // (0, the site itself, is one of them), or the nearer one alone.
            let isOwn = { (t: Int) -> Bool in t != position && at(t) == own }
            let below = stride(from: position, through: -colorReach, by: -1).first(where: isOwn)
            let above = stride(from: position, through: colorReach, by: 1).first(where: isOwn)
            switch (below, above) {
            case let (a?, b?):
                let gap = Double(b - a)
                weights[a, default: 0] -= weight * Double(b - position) / gap
                weights[b, default: 0] -= weight * Double(position - a) / gap
            case let (a?, nil):
                weights[a, default: 0] -= weight
            case let (nil, b?):
                weights[b, default: 0] -= weight
            case (nil, nil):
                weights[0, default: 0] -= weight
            }
        }
        return weights.filter { $0.value != 0 }.sorted { $0.key < $1.key }
            .map { (entry: (key: Int, value: Double)) -> Tap in
                let tx: Int = entry.key * dx, ty: Int = entry.key * dy
                return Tap(dx: Int32(tx), dy: Int32(ty), weight: Float(entry.value))
            }
    }

    /// The variation along (dx, dy): consecutive same-color samples within
    /// two steps of the center on the line through the site (weight 2) and
    /// on the two lines beside it (weight 1 each), each difference divided
    /// by its distance in steps; the weights sum to 1.
    static func variation(dx: Int, dy: Int, color: (Int, Int) -> Int) -> [Pair] {
        // The perpendicular step: beside a horizontal line is the row above or below; beside a diagonal, the next diagonal.
        let (px, py) = dy == 0 ? (0, 1) : dx == 0 ? (1, 0) : (1, -dx * dy)
        var raw: [(ax: Int, ay: Int, bx: Int, by: Int, lineWeight: Double, distance: Int)] = []
        for (line, lineWeight) in [(0, 2.0), (-1, 1.0), (1, 1.0)] {
            let ox = line * px, oy = line * py
            for t in -2...1 {
                let c = color(ox + t * dx, oy + t * dy)
                // The next sample of the same color: nothing of that color lies between the two.
                guard let next = ((t + 1)...2).first(where: { (u: Int) -> Bool in
                    color(ox + u * dx, oy + u * dy) == c
                }) else { continue }
                raw.append((ox + t * dx, oy + t * dy, ox + next * dx, oy + next * dy, lineWeight, next - t))
            }
        }
        // A weighted mean of the differences per step.
        var total = 0.0
        for entry in raw { total += entry.lineWeight }
        guard total > 0 else { return [] }
        var pairs: [Pair] = []
        for entry in raw {
            let weight: Double = entry.lineWeight / Double(entry.distance) / total
            pairs.append(Pair(ax: Int32(entry.ax), ay: Int32(entry.ay), bx: Int32(entry.bx), by: Int32(entry.by),
                              weight: Float(weight)))
        }
        return pairs
    }
}
