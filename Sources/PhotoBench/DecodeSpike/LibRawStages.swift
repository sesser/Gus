import CLibRaw
import Foundation
import PhotoCore
import Synchronization

// SPIKE for issue #194 (question 1): throwaway. Where the time goes in a
// LibRaw decode set up as `LibRawDecoder.decode` sets it up, split at the
// progress events LibRaw reports between its steps, and what running LibRaw
// on bands of the frame at once would give (#177).

/// Times of the progress events of one decode, for the callback.
final class ProgressRecorder {
    let start = ContinuousClock.now
    var events: [(stage: UInt32, iteration: Int32, at: Double)] = []

    func record(_ stage: UInt32, _ iteration: Int32) {
        events.append((stage, iteration, (ContinuousClock.now - start).milliseconds))
    }

    /// The time of the first event of `stage` with `iteration`.
    func time(_ stage: LibRaw_progress, _ iteration: Int32) -> Double? {
        events.first { $0.stage == stage.rawValue && $0.iteration == iteration }?.at
    }
}

private let progressCallback: @convention(c) (UnsafeMutableRawPointer?, LibRaw_progress, Int32, Int32) -> Int32 = {
    data, stage, iteration, _ in
    if let data { Unmanaged<ProgressRecorder>.fromOpaque(data).takeUnretainedValue().record(stage.rawValue, iteration) }
    return 0
}

enum LibRawStages {
    struct Timing {
        var open = 0.0, unpack = 0.0, preScale = 0.0, scaleColors = 0.0, preInterpolate = 0.0
        var demosaic = 0.0, convert = 0.0, afterConvert = 0.0, makeImage = 0.0, repack = 0.0
        var total: Double { open + unpack + preScale + scaleColors + preInterpolate + demosaic + convert + afterConvert + makeImage + repack }
        var outputSize = ""
    }

    /// One decode with `LibRawDecoder`'s settings, `quality` LibRaw's demosaic
    /// (nil its default: AHD for Bayer, three-pass for X-Trans), `crop` a crop
    /// box of the visible area (for bands).
    static func decode(_ url: URL, half: Bool, quality: Int32? = nil,
                       crop: (left: UInt32, top: UInt32, width: UInt32, height: UInt32)? = nil) throws -> Timing {
        let recorder = ProgressRecorder()
        var timing = Timing()
        guard let processor = libraw_init(0) else { throw BenchError("no memory") }
        defer { libraw_close(processor) }
        libraw_set_progress_handler(processor, progressCallback, Unmanaged.passUnretained(recorder).toOpaque())
        libraw_set_output_bps(processor, 16)
        libraw_set_gamma(processor, 0, 1)
        libraw_set_gamma(processor, 1, 1)
        libraw_set_no_auto_bright(processor, 1)
        libraw_set_adjust_maximum_thr(processor, 0)
        let clock = ContinuousClock()
        var t = clock.now
        var code = libraw_open_file(processor, url.path)
        guard code == LIBRAW_SUCCESS.rawValue else { throw BenchError("open \(code)") }
        timing.open = (clock.now - t).milliseconds
        if let crop { processor.pointee.params.cropbox = (crop.left, crop.top, crop.width, crop.height) }
        processor.pointee.params.half_size = half ? 1 : 0
        if let quality { processor.pointee.params.user_qual = quality }
        if let color = LibRawDecoder.cameraColor(url) {
            libraw_set_output_color(processor, 0)
            processor.pointee.params.highlight = 1
            processor.pointee.params.use_camera_wb = 0
            processor.pointee.params.use_auto_wb = 0
            let m = color.asShotNeutral.min() / color.asShotNeutral
            processor.pointee.params.user_mul = (Float(m.x), Float(m.y), Float(m.z), Float(m.y))
        }
        t = clock.now
        code = libraw_unpack(processor)
        guard code == LIBRAW_SUCCESS.rawValue else { throw BenchError("unpack \(code)") }
        timing.unpack = (clock.now - t).milliseconds
        let processStart = (clock.now - recorder.start).milliseconds
        let levelsBefore = (processor.pointee.color.maximum, processor.pointee.color.black, processor.pointee.color.data_maximum,
                            processor.pointee.color.linear_max)
        code = libraw_dcraw_process(processor)
        if ProcessInfo.processInfo.environment["SPIKE_LEVELS"] != nil {
            print("    levels: maximum \(levelsBefore.0) → \(processor.pointee.color.maximum), black \(levelsBefore.1) → \(processor.pointee.color.black), "
                  + "data_maximum \(levelsBefore.2) → \(processor.pointee.color.data_maximum), linear_max \(levelsBefore.3)")
        }
        guard code == LIBRAW_SUCCESS.rawValue else { throw BenchError("process \(code)") }
        let processEnd = (clock.now - recorder.start).milliseconds
        t = clock.now
        var status: Int32 = 0
        guard let image = libraw_dcraw_make_mem_image(processor, &status) else { throw BenchError("make image \(status)") }
        timing.makeImage = (clock.now - t).milliseconds
        // The bridge's own repack to RGBA, as `LibRawDecoder.decode` does it.
        t = clock.now
        let width = Int(image.pointee.width), height = Int(image.pointee.height)
        let offset = MemoryLayout<libraw_processed_image_t>.offset(of: \.data)!
        let source = UnsafeRawPointer(image).advanced(by: offset).assumingMemoryBound(to: UInt16.self)
        var rgba = Data(count: width * height * 8)
        rgba.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt16.self)
            for pixel in 0..<(width * height) {
                out[pixel * 4] = source[pixel * 3]
                out[pixel * 4 + 1] = source[pixel * 3 + 1]
                out[pixel * 4 + 2] = source[pixel * 3 + 2]
                out[pixel * 4 + 3] = .max
            }
        }
        timing.repack = (clock.now - t).milliseconds
        libraw_dcraw_clear_mem(image)
        timing.outputSize = "\(width)x\(height)"

        let scale0 = recorder.time(LIBRAW_PROGRESS_SCALE_COLORS, 0) ?? processStart
        let scale1 = recorder.time(LIBRAW_PROGRESS_SCALE_COLORS, 1) ?? scale0
        let pre0 = recorder.time(LIBRAW_PROGRESS_PRE_INTERPOLATE, 0) ?? scale1
        let pre1 = recorder.time(LIBRAW_PROGRESS_PRE_INTERPOLATE, 1) ?? pre0
        let conv0 = recorder.time(LIBRAW_PROGRESS_CONVERT_RGB, 0) ?? processEnd
        let conv1 = recorder.time(LIBRAW_PROGRESS_CONVERT_RGB, 1) ?? conv0
        timing.preScale = scale0 - processStart
        timing.scaleColors = scale1 - scale0
        timing.preInterpolate = pre1 - scale1
        timing.demosaic = conv0 - pre1
        timing.convert = conv1 - conv0
        timing.afterConvert = processEnd - conv1
        return timing
    }

    static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    static func run(_ arguments: Arguments, files: [URL]) throws -> [String: any Sendable] {
        let runs = arguments.int("runs", default: 5)
        let qualities: [Int32?] = arguments.values["qualities"].map { $0.split(separator: ",").map { Int32($0) } } ?? [nil]
        var rows: [[String: any Sendable]] = []
        print("Stage times in ms: median of \(runs) runs (min–max), one decode at a time, single thread (LibRaw has no threads here)")
        for url in files {
            for half in [true, false] {
                for quality in qualities where !(half && quality != qualities.first!) {
                    var samples: [Timing] = []
                    for _ in 0..<runs { samples.append(try decode(url, half: half, quality: quality)) }
                    func stat(_ key: KeyPath<Timing, Double>) -> String {
                        let v = samples.map { $0[keyPath: key] }
                        return String(format: "%.0f (%.0f–%.0f)", median(v), v.min()!, v.max()!)
                    }
                    let label = "\(url.lastPathComponent) \(half ? "half" : "full") q=\(quality.map(String.init) ?? "default")"
                    print("\(label) → \(samples[0].outputSize)")
                    print("  open \(stat(\.open))  unpack \(stat(\.unpack))  raw2image+black \(stat(\.preScale))  scale_colors \(stat(\.scaleColors))  "
                          + "pre_interpolate \(stat(\.preInterpolate))  demosaic \(stat(\.demosaic))  convert_to_rgb \(stat(\.convert))  "
                          + "rest \(stat(\.afterConvert))  make_mem_image \(stat(\.makeImage))  repack \(stat(\.repack))  TOTAL \(stat(\.total))")
                    rows.append(["file": url.lastPathComponent, "half": half, "quality": quality.map(Int.init) ?? -1,
                                 "unpack": median(samples.map(\.unpack)), "demosaic": median(samples.map(\.demosaic)),
                                 "total": median(samples.map(\.total))])
                }
            }
        }
        return ["stages": rows]
    }

    /// Full decodes of `url` split into `bands` horizontal bands of the
    /// visible area (each with `overlap` rows either side, starting on the
    /// pattern), each band its own LibRaw instance, all at once: wall time.
    /// Every band unpacks the whole file again, as a band decode with LibRaw's
    /// public API must.
    static func bands(_ arguments: Arguments, files: [URL]) throws -> [String: any Sendable] {
        let runs = arguments.int("runs", default: 3)
        let counts = (arguments.values["bands"] ?? "1,2,4,6,8,10,14").split(separator: ",").compactMap { Int($0) }
        let overlap = 24
        for url in files {
            let mosaic = try RawMosaic(url)
            let period = mosaic.period
            print("\(url.lastPathComponent): visible \(mosaic.width)x\(mosaic.height), period \(period)")
            for count in counts {
                var walls: [Double] = []
                var bandTotals: [Double] = []
                for _ in 0..<runs {
                    let height = mosaic.height
                    let rows = (height / count / period) * period
                    let crops: [(UInt32, UInt32, UInt32, UInt32)] = (0..<count).map { index in
                        let start = max(0, index * rows - overlap)
                        let end = index == count - 1 ? height : min(height, (index + 1) * rows + overlap)
                        return (0, UInt32(start), UInt32(mosaic.width), UInt32(end - start))
                    }
                    let results = Mutex([Double](repeating: 0, count: count))
                    let start = ContinuousClock.now
                    DispatchQueue.concurrentPerform(iterations: count) { index in
                        var t = Double.nan
                        do { t = try decode(url, half: false, crop: crops[index]).total } catch {
                            print("    band \(index) rows \(crops[index].1)+\(crops[index].3): \(error)")
                        }
                        results.withLock { $0[index] = t }
                    }
                    walls.append((ContinuousClock.now - start).milliseconds)
                    bandTotals.append(results.withLock { $0.max() ?? 0 })
                }
                print(String(format: "  %2d bands: wall %.0f ms (min %.0f, max %.0f); slowest band's own total %.0f ms",
                             count, median(walls), walls.min()!, walls.max()!, median(bandTotals)))
            }
            // Throughput: N whole files at once.
            for concurrent in [1, 2, 4, 8, 10] {
                let start = ContinuousClock.now
                DispatchQueue.concurrentPerform(iterations: concurrent) { _ in _ = try? decode(url, half: false) }
                let wall = (ContinuousClock.now - start).milliseconds
                print(String(format: "  %2d whole decodes at once: wall %.0f ms, %.0f ms per decode", concurrent, wall, wall / Double(concurrent)))
            }
        }
        return [:]
    }
}
