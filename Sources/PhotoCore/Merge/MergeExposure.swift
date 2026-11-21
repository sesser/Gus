import Foundation

/// How bright each frame is against the reference, and where it clips,
/// measured on the frames' reduced copies once they are lined up.
///
/// The exposure is measured from the pixels, not taken from the metadata: a
/// shutter's real time differs from its nominal one by a few percent, and a
/// file may say nothing. Frames are ordered by brightness, each neighbor
/// pair is compared over the pixels both expose well (the median of the log
/// of their luminance ratio, robust to the few that moved), and the ratios
/// are chained to the reference. A pair with too little in common falls back
/// on the metadata's exposure values; with none, on equal exposure.
public enum MergeExposure {
    /// Values between these parts of a frame's clipping level are used for
    /// measuring: clear of noise below and of clipping above.
    public static let measuredRange: ClosedRange<Float> = 0.02...0.8
    /// Ratios between two frames outside this (16 stops either way), or not
    /// finite, are not believed: broken metadata, not a bracket (security
    /// review L3). Equal exposure is assumed instead.
    public static let plausible: ClosedRange<Double> = pow(2, -16)...pow(2, 16)

    /// A pair needs at least this part of the pixels in common.
    public static let minimumCommonFraction = 0.002

    /// The level each frame clips at: its brightest channel's 99.99th
    /// percentile, so one hot pixel doesn't set it, and never below the
    /// largest value a non-raw file can hold when it has one.
    public static func clipLevels(_ frames: [MergeBitmap]) -> [Double] {
        frames.map { frame in
            var maxima = [Float]()
            maxima.reserveCapacity(frame.count)
            for index in 0..<frame.count where frame.pixels[index * 4 + 3] > 0.99 {
                let rgb = frame.rgb(index)
                maxima.append(max(rgb.x, rgb.y, rgb.z))
            }
            guard !maxima.isEmpty else { return 1 }
            maxima.sort()
            let value = Double(maxima[min(maxima.count - 1, Int(Double(maxima.count) * 0.9999))])
            return value > 0 ? value : 1
        }
    }

    /// Each frame's exposure relative to `reference` (1 for it). `frames` are
    /// lined up on the reference's pixels (alpha 0 where a frame doesn't
    /// reach); `metadata` is each frame's exposure value from its file
    /// (time × ISO / f-number², nil when unknown).
    public static func exposures(_ frames: [MergeBitmap], clips: [Double], reference: Int,
                                 metadata: [Double?]) -> [Double] {
        let count = frames.count
        guard count > 1 else { return [1] }
        let medians: [Float] = frames.map { frame in
            var values = (0..<frame.count).map { MergeBitmap.luminance(frame.rgb($0)) }
            values.sort()
            return values[values.count / 2]
        }
        let order = (0..<count).sorted { medians[$0] < medians[$1] }
        // Ratio of each frame to the one before it in `order`.
        var stepRatio = [Double](repeating: 1, count: count)
        for position in 1..<count {
            let darker = order[position - 1], brighter = order[position]
            if let measured = ratio(frames[brighter], over: frames[darker], clips: (clips[brighter], clips[darker])),
               plausible.contains(measured) {
                stepRatio[position] = measured
            } else if let a = metadata[brighter], let b = metadata[darker], a > 0, b > 0, plausible.contains(a / b) {
                stepRatio[position] = a / b
            } else {
                stepRatio[position] = 1
            }
        }
        // Chain: exposure of each frame relative to the darkest, then to the reference.
        var relative = [Double](repeating: 1, count: count)
        var running = 1.0
        for position in 0..<count {
            if position > 0 { running *= stepRatio[position] }
            relative[order[position]] = running
        }
        let base = relative[reference]
        return relative.map { $0 / base }
    }

    /// Median ratio of `a` over `b` over pixels both expose well, or nil.
    static func ratio(_ a: MergeBitmap, over b: MergeBitmap, clips: (Double, Double)) -> Double? {
        var logs = [Float]()
        let lowA = measuredRange.lowerBound * Float(clips.0), highA = measuredRange.upperBound * Float(clips.0)
        let lowB = measuredRange.lowerBound * Float(clips.1), highB = measuredRange.upperBound * Float(clips.1)
        for index in 0..<min(a.count, b.count) {
            guard a.pixels[index * 4 + 3] > 0.99, b.pixels[index * 4 + 3] > 0.99 else { continue }
            let ra = a.rgb(index), rb = b.rgb(index)
            let ma = max(ra.x, ra.y, ra.z), mb = max(rb.x, rb.y, rb.z)
            guard ma > lowA, ma < highA, mb > lowB, mb < highB else { continue }
            let la = MergeBitmap.luminance(ra), lb = MergeBitmap.luminance(rb)
            guard la > 0, lb > 0 else { continue }
            logs.append(log(la / lb))
        }
        guard logs.count >= max(64, Int(Double(a.count) * minimumCommonFraction)) else { return nil }
        logs.sort()
        return Double(exp(logs[logs.count / 2]))
    }

    /// A file's exposure value: time × ISO / f-number² (nil without a time).
    /// Missing ISO or f-number count as equal across frames.
    /// Values that aren't finite and positive count as unknown (security review L3).
    public static func metadataExposure(time: Double?, fNumber: Double?, iso: Int?) -> Double? {
        guard let time, time.isFinite, time > 0 else { return nil }
        let number = fNumber.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 1
        let speed = Double(iso.flatMap { $0 > 0 ? $0 : nil } ?? 100)
        let value = time * speed / (number * number)
        return value.isFinite && value > 0 ? value : nil
    }
}
