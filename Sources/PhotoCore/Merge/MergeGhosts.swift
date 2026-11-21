import Foundation

/// Finds where a frame shows something the reference doesn't (a person who
/// walked, leaves that moved), so the merge takes those areas from the
/// reference alone (R10).
///
/// A consistency test against the reference, after exposure is taken out:
/// two frames of a still scene give the same light wherever both expose it
/// well, and a frame that disagrees by more than noise does there saw
/// something else (in the spirit of the variance tests the HDR literature
/// uses for this, e.g. Reinhard et al. 2005, §4.8; the reference-frame
/// strategy of Grosch 2006, "Fast and robust high dynamic range image
/// generation with camera and object movement"). Where the reference is
/// clipped or black the test is one-sided: a frame that is clearly darker
/// than the reference's clipping level, or clearly brighter than its black,
/// disagrees with it.
///
/// Measured on the reduced copies, slightly blurred so a fraction of a pixel
/// of alignment error doesn't count at edges, then cleaned (isolated pixels
/// dropped), grown and feathered, so a moving object is taken out whole.
public enum MergeGhosts {
    /// Values between these parts of the clipping level are trusted.
    public static let trusted: ClosedRange<Float> = 0.01...0.9
    /// Frames disagree when a channel differs by more than this factor
    /// (ln 1.5: about 0.6 stop, far beyond the noise of a reduced copy).
    public static let threshold: Float = log(1.5)
    /// Added to every value before comparing, as a part of the reference's
    /// clipping level: keeps noise near black from counting.
    public static let floor: Float = 0.002

    /// Ghost masks (0 to 1) on the reference's reduced pixels, one per frame;
    /// all zero for the reference itself.
    public static func masks(_ frames: [MergeBitmap], plans: [MergeFramePlan], reference: Int) -> [MergePlane] {
        let ref = Neighborhood(frames[reference])
        let growRadius = max(2, max(ref.bitmap.width, ref.bitmap.height) / 256)
        return frames.indices.map { index in
            if index == reference { return MergePlane(width: ref.bitmap.width, height: ref.bitmap.height) }
            let raw = disagreement(Neighborhood(frames[index]), ref, exposure: Float(plans[index].exposure),
                                   clip: Float(plans[index].clip), referenceClip: Float(plans[reference].clip))
            // Majority of the 3 x 3 neighborhood: isolated pixels go.
            var cleaned = raw.boxMean(radius: 1)
            for i in cleaned.values.indices { cleaned.values[i] = cleaned.values[i] > 0.5 ? 1 : 0 }
            var grown = cleaned.dilated(radius: growRadius).boxMean(radius: growRadius)
            for i in grown.values.indices { grown.values[i] = min(1, grown.values[i] * 2) }
            return grown
        }
    }

    /// A frame with, at every pixel, its 3 x 3 neighborhood's blurred color and
    /// the smallest and largest brightest-channel value in it, so a test
    /// next to a clipped or black area knows it is there.
    struct Neighborhood {
        var bitmap: MergeBitmap
        var blurred: MergeBitmap
        var low: [Float]
        var high: [Float]

        init(_ bitmap: MergeBitmap) {
            self.bitmap = bitmap
            blurred = MergeGhosts.blurred(bitmap)
            let w = bitmap.width, h = bitmap.height
            var maxima = [Float](repeating: 0, count: w * h)
            for index in maxima.indices {
                let rgb = bitmap.rgb(index)
                maxima[index] = max(rgb.x, rgb.y, rgb.z)
            }
            var low = maxima, high = maxima
            for y in 0..<h {
                for x in 0..<w {
                    var lo = Float.infinity, hi = -Float.infinity
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let v = maxima[min(max(y + dy, 0), h - 1) * w + min(max(x + dx, 0), w - 1)]
                            lo = min(lo, v)
                            hi = max(hi, v)
                        }
                    }
                    low[y * w + x] = lo
                    high[y * w + x] = hi
                }
            }
            self.low = low
            self.high = high
        }
    }

    /// 1 where the frame disagrees with the reference, else 0.
    static func disagreement(_ frame: Neighborhood, _ reference: Neighborhood, exposure: Float, clip: Float,
                             referenceClip: Float) -> MergePlane {
        var plane = MergePlane(width: reference.bitmap.width, height: reference.bitmap.height)
        let lowF = trusted.lowerBound * clip, highF = trusted.upperBound * clip
        let lowR = trusted.lowerBound * referenceClip, highR = trusted.upperBound * referenceClip
        let floorValue = floor * referenceClip
        for index in 0..<plane.values.count {
            guard frame.blurred.pixels[index * 4 + 3] > 0.99 else { continue }
            // The frame must itself be trustworthy all around to say anything.
            guard frame.low[index] > lowF, frame.high[index] < highF else { continue }
            var differs = false
            if reference.high[index] >= highR {
                // The reference clips here or next to here: the frame disagrees
                // only if all around it is clearly below that level.
                differs = frame.high[index] / exposure * 1.5 < highR
            } else if reference.low[index] <= lowR {
                // The reference is black here or next to here: the frame
                // disagrees only if all around it is clearly above black.
                differs = frame.low[index] / exposure > lowR * 1.5
            } else {
                let x = frame.blurred.rgb(index) / exposure, r = reference.blurred.rgb(index)
                for c in 0..<3 where abs(log(x[c] + floorValue) - log(r[c] + floorValue)) > threshold {
                    differs = true
                }
            }
            if differs { plane.values[index] = 1 }
        }
        return plane
    }

    /// A 3 x 3 box blur of the colors, edges clamped; alpha becomes the
    /// neighborhood's smallest, so a pixel next to a frame's edge isn't trusted.
    static func blurred(_ bitmap: MergeBitmap) -> MergeBitmap {
        let w = bitmap.width, h = bitmap.height
        var out = bitmap
        for y in 0..<h {
            for x in 0..<w {
                var sum = SIMD3<Float>.zero
                var alpha: Float = 1
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = min(max(x + dx, 0), w - 1), ny = min(max(y + dy, 0), h - 1)
                        sum += bitmap.rgb(x: nx, y: ny)
                        alpha = min(alpha, bitmap.pixels[(ny * w + nx) * 4 + 3])
                    }
                }
                let i = (y * w + x) * 4
                out.pixels[i] = sum.x / 9
                out.pixels[i + 1] = sum.y / 9
                out.pixels[i + 2] = sum.z / 9
                out.pixels[i + 3] = alpha
            }
        }
        return out
    }
}
