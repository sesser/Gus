import Foundation

/// The color filter pattern of a sensor, as it repeats from the top left of
/// the area a demosaic works on: 0 red, 1 green, 2 blue, `period` x
/// `period` sites, rows first. A Bayer sensor's second green is green.
public struct CFAPattern: Sendable, Hashable, CustomStringConvertible {
    public enum Kind: String, Sendable, Hashable {
        /// 2 x 2: one red, two greens on a diagonal, one blue.
        case bayer
        /// 6 x 6, Fujifilm's X-Trans: 20 greens, 8 reds and 8 blues, every
        /// row and every column holding all three colors.
        case xTrans
    }

    public let period: Int
    public let colors: [Int32]
    public let kind: Kind

    /// Nil for a pattern this build's kernels do not demosaic (the caller
    /// then leaves the file to LibRaw's own demosaic, R4).
    public init?(period: Int, colors: [Int32]) {
        guard colors.count == period * period, colors.allSatisfy({ (0...2).contains($0) }) else { return nil }
        self.period = period
        self.colors = colors
        let count = { (color: Int32) in colors.filter { $0 == color }.count }
        switch period {
        case 2:
            // Greens on one diagonal, red and blue on the other.
            guard count(0) == 1, count(1) == 2, count(2) == 1, colors[0] == colors[3] || colors[1] == colors[2],
                  (colors[0] == 1) == (colors[3] == 1), (colors[1] == 1) == (colors[2] == 1) else { return nil }
            kind = .bayer
        case 6:
            guard count(0) == 8, count(1) == 20, count(2) == 8 else { return nil }
            // Every row and every column has all three colors.
            for i in 0..<6 {
                var row = Set<Int32>(), column = Set<Int32>()
                for j in 0..<6 {
                    row.insert(colors[i * 6 + j])
                    column.insert(colors[j * 6 + i])
                }
                guard row.count == 3, column.count == 3 else { return nil }
            }
            kind = .xTrans
        default:
            return nil
        }
    }

    /// The color at a pixel of the area (x a column, y a row, both from 0).
    @inline(__always) public func color(x: Int, y: Int) -> Int {
        Int(colors[(y % period) * period + x % period])
    }

    /// The same pattern seen from a pixel `(x, y)` of the area: what a crop
    /// starting there has at its top left.
    public func shifted(x: Int, y: Int) -> CFAPattern {
        let p = period
        var moved: [Int32] = []
        moved.reserveCapacity(p * p)
        for site in 0..<(p * p) {
            let row: Int = (site / p + y) % p
            let column: Int = (site % p + x) % p
            moved.append(colors[row * p + column])
        }
        return CFAPattern(period: p, colors: moved)!
    }

    /// Rows of R, G and B letters, for logs and tests.
    public var description: String {
        (0..<period).map { y in
            String((0..<period).map { x in Array("RGB")[color(x: x, y: y)] })
        }.joined(separator: "/")
    }

    /// The pattern of the Fujifilm X-E3 and X-T3 as LibRaw reports it at
    /// their visible area's origin (measured; tests and synthetic mosaics).
    public static let xTransSample = CFAPattern(period: 6, colors: [
        1, 1, 0, 1, 1, 2,
        1, 1, 2, 1, 1, 0,
        2, 0, 1, 0, 2, 1,
        1, 1, 2, 1, 1, 0,
        1, 1, 0, 1, 1, 2,
        0, 2, 1, 2, 0, 1,
    ])!

    /// Red, green / green, blue.
    public static let rggb = CFAPattern(period: 2, colors: [0, 1, 1, 2])!
}
