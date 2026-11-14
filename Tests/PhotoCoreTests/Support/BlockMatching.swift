import CoreGraphics
import Foundation

/// Compares two pictures of one scene block by block: for telling whether a
/// render lines up with the JPEG a camera embedded in its raw file.
enum BlockMatching {
    /// `image` drawn `width` x `height` as 8-bit gray, rows from the top.
    static func gray(_ image: CGImage, width: Int, height: Int) -> [Float] {
        var bytes = [UInt8](repeating: 0, count: width * height)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes.map(Float.init)
    }

    struct Match {
        /// The block's center in `a`.
        var x: Int, y: Int
        /// Where the same detail is in `b`, relative to that.
        var dx: Double, dy: Double
        var score: Double
    }

    /// For each `block`-sized square of `a` with enough detail, on a grid of
    /// `step`, the shift within ±`search` pixels at which `b` correlates
    /// best with it (zero-mean normalized cross-correlation, so brightness
    /// and contrast do not matter), refined between pixels by a parabola
    /// through the best score and its neighbors. Blocks whose best match is
    /// weak (under 0.5) or at the edge of the search are left out.
    static func matches(_ a: [Float], _ b: [Float], width: Int, height: Int, block: Int, step: Int, search: Int) -> [Match] {
        var out: [Match] = []
        let half = block / 2, side = 2 * search + 1, area = Float(block * block)
        var cy = half + search
        while cy + half + search <= height {
            var cx = half + search
            while cx + half + search <= width {
                defer { cx += step }
                var meanA: Float = 0, varianceA: Float = 0
                for y in (cy - half)..<(cy + half) { for x in (cx - half)..<(cx + half) { meanA += a[y * width + x] } }
                meanA /= area
                for y in (cy - half)..<(cy + half) {
                    for x in (cx - half)..<(cx + half) { let d = a[y * width + x] - meanA; varianceA += d * d }
                }
                // Flat blocks (a standard deviation under about 8 levels) match anywhere.
                guard varianceA / area > 60 else { continue }
                var scores = [Double](repeating: -2, count: side * side)
                var best = (score: -2.0, dx: 0, dy: 0)
                for dy in -search...search {
                    for dx in -search...search {
                        var meanB: Float = 0
                        for y in (cy - half)..<(cy + half) { for x in (cx - half)..<(cx + half) { meanB += b[(y + dy) * width + x + dx] } }
                        meanB /= area
                        var covariance: Float = 0, varianceB: Float = 0
                        for y in (cy - half)..<(cy + half) {
                            for x in (cx - half)..<(cx + half) {
                                let da = a[y * width + x] - meanA, db = b[(y + dy) * width + x + dx] - meanB
                                covariance += da * db
                                varianceB += db * db
                            }
                        }
                        let score = varianceB > 0 ? Double(covariance / (varianceA * varianceB).squareRoot()) : -1
                        scores[(dy + search) * side + dx + search] = score
                        if score > best.score { best = (score, dx, dy) }
                    }
                }
                guard best.score > 0.5, abs(best.dx) < search, abs(best.dy) < search else { continue }
                func score(_ dx: Int, _ dy: Int) -> Double { scores[(dy + search) * side + dx + search] }
                func peak(_ before: Double, _ after: Double) -> Double {
                    let curve = before - 2 * best.score + after
                    return curve < 0 ? 0.5 * (before - after) / curve : 0
                }
                out.append(Match(x: cx, y: cy,
                                 dx: Double(best.dx) + peak(score(best.dx - 1, best.dy), score(best.dx + 1, best.dy)),
                                 dy: Double(best.dy) + peak(score(best.dx, best.dy - 1), score(best.dx, best.dy + 1)),
                                 score: best.score))
            }
            cy += step
        }
        return out
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? .nan : sorted[sorted.count / 2]
    }

    /// Mean gray of each `block`-sized square on a grid, with its center.
    static func means(_ image: [Float], width: Int, height: Int, block: Int) -> [(x: Int, y: Int, mean: Double)] {
        var out: [(Int, Int, Double)] = []
        for by in 0..<(height / block) {
            for bx in 0..<(width / block) {
                var sum: Float = 0
                for y in (by * block)..<((by + 1) * block) { for x in (bx * block)..<((bx + 1) * block) { sum += image[y * width + x] } }
                out.append((bx * block + block / 2, by * block + block / 2, Double(sum) / Double(block * block)))
            }
        }
        return out
    }
}
