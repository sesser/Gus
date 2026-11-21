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
/// disagrees with it. Where the frame itself is clipped or black, the same
/// (revision 2026-11-21: with any frame as the reference, a darker reference
/// meets brighter frames that clip where something moved, and the reverse):
/// a clipped frame whose lowest value is clearly above the reference
/// disagrees, and a black frame disagrees where the reference is clearly
/// brighter than anything the frame's black level could hide. That second
/// test reads only the black level, never the black frame's own values: a
/// JPEG's camera curve crushes its toe below proportional, so those values
/// under-say the light by any amount (code review C14).
///
/// Measured on the reduced copies, slightly blurred so a fraction of a pixel
/// of alignment error doesn't count at edges, then cleaned (isolated pixels
/// dropped), grown and feathered, so a moving object is taken out whole. What
/// the frame's own black or clipping says is cleaned and grown on its own, and
/// kept only where some other frame has a trusted value: there a mask that
/// grew past the evidence could only hand the pixel to the reference's
/// clipped or black values (C14).
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
        func spread(_ raw: MergePlane) -> MergePlane {
            // Majority of the 3 x 3 neighborhood: isolated pixels go.
            var cleaned = raw.boxMean(radius: 1)
            for i in cleaned.values.indices { cleaned.values[i] = cleaned.values[i] > 0.5 ? 1 : 0 }
            var grown = cleaned.dilated(radius: growRadius).boxMean(radius: growRadius)
            for i in grown.values.indices { grown.values[i] = min(1, grown.values[i] * 2) }
            return grown
        }
        return frames.indices.map { index in
            if index == reference { return MergePlane(width: ref.bitmap.width, height: ref.bitmap.height) }
            let raw = disagreement(Neighborhood(frames[index]), ref, exposure: Float(plans[index].exposure),
                                   clip: Float(plans[index].clip), referenceClip: Float(plans[reference].clip))
            var mask = spread(raw.main)
            // Tests that rest on the frame's own black or clipping: never where
            // the frame is the only one that holds the light.
            guard raw.bound.values.contains(where: { $0 > 0 }) else { return mask }
            let bound = spread(raw.bound)
            let others = usableElsewhere(frames, plans: plans, except: index)
            for i in mask.values.indices where others[i] {
                mask.values[i] = max(mask.values[i], bound.values[i])
            }
            return mask
        }
    }

    /// Whether some frame other than `index` has a trusted value (brightest
    /// channel within `trusted` of its clipping level) at each pixel.
    static func usableElsewhere(_ frames: [MergeBitmap], plans: [MergeFramePlan], except index: Int) -> [Bool] {
        var usable = [Bool](repeating: false, count: frames[index].count)
        for (other, frame) in frames.enumerated() where other != index {
            let clip = Float(plans[other].clip)
            let low = trusted.lowerBound * clip, high = trusted.upperBound * clip
            for i in usable.indices where !usable[i] && frame.pixels[i * 4 + 3] > 0.99 {
                let rgb = frame.rgb(i)
                let m = max(rgb.x, rgb.y, rgb.z)
                usable[i] = m > low && m < high
            }
        }
        return usable
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

    /// 1 where the frame disagrees with the reference, else 0: in `main` where
    /// the test reads the frame's values against the reference's, in `bound`
    /// where it rests on the frame being clipped or black there.
    static func disagreement(_ frame: Neighborhood, _ reference: Neighborhood, exposure: Float, clip: Float,
                             referenceClip: Float) -> (main: MergePlane, bound: MergePlane) {
        var plane = MergePlane(width: reference.bitmap.width, height: reference.bitmap.height)
        var boundPlane = plane
        let lowF = trusted.lowerBound * clip, highF = trusted.upperBound * clip
        let lowR = trusted.lowerBound * referenceClip, highR = trusted.upperBound * referenceClip
        let floorValue = floor * referenceClip
        let factor: Float = 1.5
        for index in 0..<plane.values.count {
            guard frame.blurred.pixels[index * 4 + 3] > 0.99 else { continue }
            // Where the frame is black or clipped here or next to here, its
            // values are only a bound on the light: a black frame's an upper
            // bound, a clipped one's a lower bound. Each test below uses only
            // what the frame's values can still say, so a still scene never
            // disagrees with itself, whichever frame is the reference (A13).
            let frameBlack = frame.low[index] <= lowF
            let frameClipped = frame.high[index] >= highF
            if frameBlack && frameClipped { continue }
            var differs = false, bounded = false
            if reference.high[index] >= highR {
                // The reference clips here or next to here: the frame disagrees
                // only if all around it is clearly below that level.
                differs = !frameClipped && frame.high[index] / exposure * factor < highR
            } else if reference.low[index] <= lowR {
                // The reference is black here or next to here: the frame
                // disagrees only if all around it is clearly above black.
                differs = !frameBlack && frame.low[index] / exposure > lowR * factor
            } else if frameClipped {
                // The frame clips where the reference doesn't: it disagrees if
                // even its lowest value is clearly above the reference's highest.
                bounded = frame.low[index] / exposure > reference.high[index] * factor
            } else if frameBlack {
                // The frame is black where the reference isn't: it disagrees if
                // all around, the reference is clearly brighter than the light
                // the frame's black level can hide. Not against the frame's own
                // values, which a camera's toe crushes below proportional (C14).
                bounded = reference.low[index] > lowF / exposure * factor
            } else {
                let x = frame.blurred.rgb(index) / exposure, r = reference.blurred.rgb(index)
                for c in 0..<3 where abs(log(x[c] + floorValue) - log(r[c] + floorValue)) > threshold {
                    differs = true
                }
            }
            if differs { plane.values[index] = 1 }
            if bounded { boundPlane.values[index] = 1 }
        }
        return (plane, boundPlane)
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
