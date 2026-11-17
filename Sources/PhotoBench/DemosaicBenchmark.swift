import CoreImage
import Darwin
import Foundation
import ImageIO
import PhotoCore
import PhotoFixtures

/// Our GPU demosaic against LibRaw's own (issue #196). Every mode reads
/// files in place and writes nothing unless `--output` is given.
///
///     photobench demosaic --mode truth --files A.RW2:B.CR2 [--crop N]
///     photobench demosaic --mode real --files A.RAF:B.RAF [--crop 2048]
///     photobench demosaic --mode timing --files A.RAF [--runs 6]
///     photobench demosaic --mode memory --file A.RAF
///
/// - `truth` (AC2, AC3): each Bayer raw binned 2 x 2 (each color from its own
///   sites, nothing interpolated) is a full-color picture of real detail; it
///   is sampled through an RGGB and an X-Trans mosaic, written as DNGs
///   (camera = linear sRGB), and demosaiced by ours and by LibRaw's own
///   (AHD and three-pass X-Trans), each compared with the truth.
/// - `real` (AC3, AC4, AC6): the middle of each real frame, ours against
///   LibRaw's own through the same color step and look.
/// - `timing` (AC15): decode plus render to 8-bit sRGB, full and half size,
///   first run and the median of the rest; the unpack alone; the GPU time.
/// - `memory` (AC13): one full-size decode in a fresh process: its footprint
///   above what the process held before.
enum DemosaicBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        // `--nr off` or `--nr hY,hC`: the noise reduction the decodes use (measuring and tuning).
        if let nr = arguments.values["nr"] {
            var arguments = arguments
            arguments.values["nr"] = nil
            let values = nr.split(separator: ",").compactMap { Float(String($0)) }
            let reduction: GPUDemosaic.ColorNoiseReduction? = values.count >= 2
                ? GPUDemosaic.ColorNoiseReduction(luminanceStrength: values[0], colorStrength: values[1]) : nil
            return try await GPUDemosaic.$decodeNoiseReduction.withValue(reduction) { try await run(arguments) }
        }
        let files = (arguments.values["files"] ?? arguments.values["file"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: (String($0) as NSString).expandingTildeInPath) }
        guard !files.isEmpty else { throw BenchError("demosaic needs --files a.RAF:b.RW2") }
        switch arguments.values["mode"] ?? "real" {
        case "truth": return try truth(arguments, files: files)
        case "real": return try real(arguments, files: files)
        case "timing": return try timing(arguments, files: files)
        case "memory": return try memory(files[0])
        case "live": return try await live(arguments, files: files)
        case "pattern":
            for url in files {
                let m = try LibRawDecoder.sensorMosaic(url)
                let noise = NoiseModel.estimate(m); print("\(url.lastPathComponent): system decoder \(SystemRAWDecoder.reads(url) ? "reads it" : "no image"); noise a \(noise.a) b \(noise.b) (σ at 0.18: \((noise.variance(at: 0.18)).squareRoot())) \(m.pattern) \(m.width)x\(m.height) black \(m.blackPerSite.min() ?? 0)…\(m.blackPerSite.max() ?? 0) span \(m.whiteSpan) multipliers \(m.multipliers)")
            }
            return [:]
        default: throw BenchError("--mode is truth, real, timing or memory")
        }
    }

    /// A decode's image before its color step, as floats.
    static func linear(_ url: URL, _ choice: LibRawDecoder.DemosaicChoice, halfSize: Bool = false) throws
        -> (picture: RGBPicture, output: LibRawDecoder.Output) {
        let output = try LibRawDecoder.decode(url, halfSize: halfSize, lensCorrections: false, demosaic: choice)
        return (Measure.render(output.linear), output)
    }

    // MARK: Truth

    static func truth(_ arguments: Arguments, files: [URL]) throws -> [String: any Sendable] {
        let crop = arguments.int("crop", default: 0)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "demosaic-truth-\(getpid())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        print("Truth: each raw binned 2 x 2, sampled through RGGB and X-Trans; CPSNR over sRGB-encoded values;")
        print("edge chroma error = |Δa, Δb| in Lab of linear sRGB at the truth's top 10% L* gradient (8 px border out).")
        var rows: [[String: any Sendable]] = []
        for url in files {
            let mosaic = try LibRawDecoder.sensorMosaic(url)
            guard mosaic.pattern.kind == .bayer else { print("\(url.lastPathComponent): not Bayer, skipped"); continue }
            let binned = try GPUDemosaic.shared().run(mosaic, halfSize: true, precision: .float, noiseReduction: nil)
            var w = binned.width / 6 * 6, h = binned.height / 6 * 6
            if crop > 0 { w = min(w, crop / 6 * 6); h = min(h, crop / 6 * 6) }
            let whole = RGBPicture(rgba: binned.floats(), width: binned.width, height: binned.height)
            // The truth is what a 16-bit file holds: quantized, at most white.
            let truth = whole.cropped(x: (whole.width - w) / 2 / 6 * 6, y: (whole.height - h) / 2 / 6 * 6, width: w, height: h)
                .map { (pointwiseMin(pointwiseMax($0, .zero), SIMD3(repeating: 1)) * 65535).rounded(.toNearestOrEven) / 65535 }
            let truthLab = truth.pixels.map(Measure.labSRGB)
            let edges = Measure.edgeMask(truthLab, width: w, height: h)
            print("\n\(url.lastPathComponent): truth \(w)x\(h)")
            for (name, pattern) in [("RGGB", CFAPattern.rggb), ("X-Trans", CFAPattern.xTransSample)] {
                var values = Data(count: w * h * 2)
                values.withUnsafeMutableBytes { raw in
                    let out = raw.bindMemory(to: UInt16.self)
                    for y in 0..<h {
                        for x in 0..<w {
                            out[y * w + x] = UInt16(truth[x, y][pattern.color(x: x, y: y)] * 65535).littleEndian
                        }
                    }
                }
                let dng = scratch.appending(path: "\(url.deletingPathExtension().lastPathComponent)-\(name).dng")
                var options = SyntheticDNG.Options(width: w, height: h, seed: 1)
                options.cfaPeriod = pattern.period
                options.cfaColors = pattern.colors.map(UInt8.init)
                try SyntheticDNG.write(to: dng, options: options, mosaic: values)
                for choice in [LibRawDecoder.DemosaicChoice.automatic, .libRaw] {
                    let clock = ContinuousClock(), start = clock.now
                    guard let (picture, output) = try? linear(dng, choice) else { print("  \(name) \(choice): no decode"); continue }
                    let ms = (clock.now - start).milliseconds
                    guard picture.width == w, picture.height == h else {
                        print("  \(name) \(choice): \(picture.width)x\(picture.height), not the truth's size"); continue
                    }
                    let labs = picture.pixels.map(Measure.labSRGB)
                    let comparison = Measure.compare(labs, truthLab, edges: edges, width: w, height: h)
                    let fc = Measure.falseColor(labs, edges: edges, width: w, height: h)
                    let psnr = Measure.cpsnr(picture, truth)
                    var channel = SIMD3<Double>.zero
                    for y in 8..<(h - 8) {
                        for x in 8..<(w - 8) {
                            for c in 0..<3 {
                                let d = Double(Measure.encode(picture[x, y][c]) - Measure.encode(truth[x, y][c]))
                                channel[c] += d * d
                            }
                        }
                    }
                    let count = Double((w - 16) * (h - 16))
                    let perChannel = (0..<3).map { 10 * log10(1 / (channel[$0] / count)) }
                    print(String(format: "      PSNR R %.2f G %.2f B %.2f; ΔE flat median %.2f p95 %.2f, edges median %.2f p95 %.2f", perChannel[0], perChannel[1], perChannel[2],
                                 comparison.flat.median, comparison.flat.p95, comparison.edges.median, comparison.edges.p95))
                    let label = "\(name) \(output.demosaic)"
                    print(String(format: "  %-34@ CPSNR %6.2f dB  edge chroma error p95 %6.2f  median %5.2f  edge ΔE p95 %6.2f"
                                 + "  false color %.2f detail %.2f  (%.0f ms)", label as NSString, psnr,
                                 comparison.edgeChroma.p95, comparison.edgeChroma.median, comparison.edges.p95,
                                 fc.chroma, fc.detail, ms))
                    if let folder = arguments.values["output"] {
                        let stem = "\(url.deletingPathExtension().lastPathComponent)-\(name)-\(choice.rawValue)"
                        try writePNG(picture, to: URL(fileURLWithPath: folder).appending(path: stem + ".png"))
                        try writePNG(truth, to: URL(fileURLWithPath: folder).appending(path: "\(url.deletingPathExtension().lastPathComponent)-truth.png"))
                        // Error, ×8, on a grey background.
                        let error = RGBPicture(width: w, height: h, pixels: (0..<(w * h)).map { i in
                            let d = SIMD3<Float>((0..<3).map { Measure.encode(picture.pixels[i][$0]) - Measure.encode(truth.pixels[i][$0]) })
                            return pointwiseMin(pointwiseMax(SIMD3(repeating: 0.5) + d * 8, .zero), SIMD3(repeating: 1))
                        })
                        try writePNG(error, to: URL(fileURLWithPath: folder).appending(path: stem + "-error.png"), encoded: true)
                    }
                    rows.append(["file": url.lastPathComponent, "pattern": name, "demosaic": "\(output.demosaic)",
                                 "cpsnr": psnr, "edgeChromaP95": comparison.edgeChroma.p95])
                }
            }
            let fc = Measure.falseColor(truthLab, edges: edges, width: w, height: h)
            print(String(format: "  truth: false color %.2f detail %.2f", fc.chroma, fc.detail))
        }
        return ["rows": rows]
    }

    /// An 8-bit sRGB PNG of linear (or, `encoded`, already encoded) values.
    static func writePNG(_ picture: RGBPicture, to url: URL, encoded: Bool = false) throws {
        var bytes = [UInt8](repeating: 255, count: picture.width * picture.height * 4)
        for (i, p) in picture.pixels.enumerated() {
            for c in 0..<3 { bytes[i * 4 + c] = UInt8(min(max((encoded ? p[c] : Measure.encode(p[c])) * 255, 0), 255).rounded()) }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: picture.width, height: picture.height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: picture.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BenchError("could not write \(url.path)") }
    }

    // MARK: Real files

    static func real(_ arguments: Arguments, files: [URL]) throws -> [String: any Sendable] {
        let size = arguments.int("crop", default: 2048)
        print("Real: the middle \(size)x\(size) of the frame, through the built-in color step and look (camera's white balance).")
        var rows: [[String: any Sendable]] = []
        for url in files {
            let (oursPicture, ours) = try linear(url, .automatic)
            let (libPicture, lib) = try linear(url, .libRaw)
            guard let step = Measure.ColorStep(lib.step) else { print("\(url.lastPathComponent): no usable color"); continue }
            guard oursPicture.width == libPicture.width, oursPicture.height == libPicture.height else {
                print("\(url.lastPathComponent): sizes differ"); continue
            }
            let oursMiddle = oursPicture.middle(size), libMiddle = libPicture.middle(size)
            let w = libMiddle.width, h = libMiddle.height
            let oursLab = oursMiddle.pixels.map { Measure.lab(step.apply($0)) }
            let libLab = libMiddle.pixels.map { Measure.lab(step.apply($0)) }
            let libEdges = Measure.edgeMask(libLab, width: w, height: h)
            let oursEdges = Measure.edgeMask(oursLab, width: w, height: h)
            let fcLib = Measure.falseColor(libLab, edges: libEdges, width: w, height: h)
            let fcOurs = Measure.falseColor(oursLab, edges: oursEdges, width: w, height: h)
            let blocks = Measure.Summary(Measure.deltaE(Measure.blockLab(oursMiddle.map(step.apply)),
                                                        Measure.blockLab(libMiddle.map(step.apply))))
            let pixels = Measure.compare(oursLab, libLab, edges: libEdges, width: w, height: h)
            print("\n\(url.lastPathComponent) (\(ours.cameraMake) \(ours.cameraModel)), \(oursPicture.width)x\(oursPicture.height): ours \(ours.demosaic)")
            print(String(format: "  false color (detail): LibRaw %.2f (%.2f), ours %.2f (%.2f): ratio %.2f, detail ratio %.2f",
                         fcLib.chroma, fcLib.detail, fcOurs.chroma, fcOurs.detail, fcOurs.chroma / fcLib.chroma,
                         fcOurs.detail / fcLib.detail))
            print("  ours vs LibRaw: 16 px blocks ΔE \(blocks); \(pixels)")
            rows.append(["file": url.lastPathComponent, "falseColorLibRaw": fcLib.chroma, "detailLibRaw": fcLib.detail,
                         "falseColor": fcOurs.chroma, "detail": fcOurs.detail, "blockMedian": blocks.median,
                         "blockP95": blocks.p95, "edgeMedian": pixels.edges.median])
        }
        return ["rows": rows]
    }

    // MARK: Timing

    static func timing(_ arguments: Arguments, files: [URL]) throws -> [String: any Sendable] {
        let runs = max(2, arguments.int("runs", default: 6))
        let context = CIContext(options: [.workingColorSpace: Measure.working, .workingFormat: CIFormat.RGBAh,
                                          .cacheIntermediates: false])
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let choices: [LibRawDecoder.DemosaicChoice] = arguments.flags.contains("libraw") ? [.automatic, .libRaw] : [.automatic]
        print("Decode plus render to 8-bit sRGB (seconds): first run, then median (min–max) of the other \(runs - 1).")
        var rows: [[String: any Sendable]] = []
        func timed(_ body: () throws -> Void) rethrows -> (first: Double, median: Double, low: Double, high: Double) {
            var times: [Double] = []
            for _ in 0..<runs {
                let start = ContinuousClock.now
                try body()
                times.append((ContinuousClock.now - start).milliseconds / 1000)
            }
            let rest = times.dropFirst().sorted()
            return (times[0], rest[rest.count / 2], rest.first!, rest.last!)
        }
        func text(_ t: (first: Double, median: Double, low: Double, high: Double)) -> String {
            String(format: "%.3f, %.3f (%.3f–%.3f)", t.first, t.median, t.low, t.high)
        }
        for url in files {
            var row: [String: any Sendable] = ["file": url.lastPathComponent]
            for choice in choices {
                var made = ""
                for half in [false, true] {
                    let t = try timed {
                        let output = try LibRawDecoder.decode(url, halfSize: half, demosaic: choice)
                        made = "\(output.demosaic)"
                        let image = output.image()
                        _ = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: srgb)
                    }
                    let key = "\(choice.rawValue) \(half ? "half" : "full")"
                    row[key] = text(t)
                    print("\(url.lastPathComponent) \(key) [\(made)]: \(text(t))")
                }
            }
            if let mosaic = try? LibRawDecoder.sensorMosaic(url) {
                let unpack = try timed { _ = try LibRawDecoder.sensorMosaic(url) }
                var gpu: [Double] = [], halfGPU: [Double] = [], alone: [Double] = []
                for _ in 0..<runs {
                    gpu.append(try GPUDemosaic.shared().run(mosaic).gpuSeconds * 1000)
                    halfGPU.append(try GPUDemosaic.shared().run(mosaic, halfSize: true).gpuSeconds * 1000)
                    alone.append(try GPUDemosaic.shared().run(mosaic, noiseReduction: nil).gpuSeconds * 1000)
                }
                let g = gpu.dropFirst().sorted(), hg = halfGPU.dropFirst().sorted(), a = alone.dropFirst().sorted()
                let line = String(format: "unpack and copy %@ s; GPU full %.1f ms (%.1f–%.1f; the demosaic alone %.1f), half %.1f ms",
                                  text(unpack), g[g.count / 2], g.first!, g.last!, a[a.count / 2], hg[hg.count / 2])
                print("\(url.lastPathComponent) \(line)")
                row["gpu"] = line
            }
            rows.append(row)
        }
        return ["machine": machineDescription(), "rows": rows]
    }

    // MARK: Live frames

    /// The loupe's live frames for a raw (AC15, R18): the fitted session's
    /// first frame, then white balance and exposure frames from the kept
    /// decode; the 100% renderer's full decode, its first region (a
    /// 3024 x 1800 window in the middle) and white balance regions. Compare
    /// demosaics with `RAW_DEMOSAIC=libraw` (the 100% renderer decodes in a
    /// task of its own, so only the process's setting reaches it).
    static func live(_ arguments: Arguments, files: [URL]) async throws -> [String: any Sendable] {
        let frames = arguments.int("frames", default: 10)
        let generator = PreviewGenerator(engine: RenderEngine.interactive())
        func ms(_ start: ContinuousClock.Instant) -> Double { (ContinuousClock.now - start).milliseconds }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        print("Live frames (ms), demosaic \(LibRawDecoder.launchDemosaic.rawValue): first, then medians of \(frames).")
        for url in files {
            let session = LiveRenderSession(source: url, generator: generator, colorSpace: nil)
            var values = Adjustments()
            var start = ContinuousClock.now
            _ = try await session.render(values)
            let first = ms(start)
            var balance: [Double] = [], exposure: [Double] = []
            for i in 0..<frames {
                values.whiteBalance = WhiteBalance(preset: .custom, temperature: 3000 + Double(i) * 300, tint: Double(i))
                start = .now
                _ = try await session.render(values, interactive: true)
                balance.append(ms(start))
            }
            for i in 0..<frames {
                values.exposure.ev = Double(i) * 0.1
                start = .now
                _ = try await session.render(values, interactive: true)
                exposure.append(ms(start))
            }
            let region = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil)
            values = Adjustments()
            start = .now
            try await region.prepare(values)
            let decode = ms(start)
            let size = PreviewGenerator.nativeSize(url) ?? CGSize(width: 6000, height: 4000)
            let unit = CGRect(x: 0.5 - 1512 / size.width, y: 0.5 - 900 / size.height, width: 3024 / size.width, height: 1800 / size.height)
            start = .now
            _ = try await region.render(values, unit: unit)
            let firstRegion = ms(start)
            var regions: [Double] = []
            for i in 0..<frames {
                values.whiteBalance = WhiteBalance(preset: .custom, temperature: 3000 + Double(i) * 300, tint: Double(i))
                start = .now
                _ = try await region.render(values, unit: unit)
                regions.append(ms(start))
            }
            print(String(format: "%@: fit first frame %.0f, white balance %.1f, exposure %.1f; 100%%: decode %.0f, first region %.0f, white balance %.1f",
                         url.lastPathComponent, first, median(balance), median(exposure), decode, firstRegion, median(regions)))
        }
        return [:]
    }

    // MARK: Memory

    static func footprint() -> (current: UInt64, peak: UInt64) {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        guard result == 0 else { return (0, 0) }
        return (info.ri_phys_footprint, info.ri_lifetime_max_phys_footprint)
    }

    static func memory(_ url: URL) throws -> [String: any Sendable] {
        // Warm the engine on a small mosaic so its compile is not counted.
        let small = SensorMosaic(width: 64, height: 64, pattern: .xTransSample, values: [UInt16](repeating: 1000, count: 4096))!
        _ = try GPUDemosaic.shared().run(small)
        let before = footprint()
        let output = try LibRawDecoder.decode(url)
        let after = footprint()
        let mb = { (bytes: UInt64) in Double(bytes) / 1_048_576 }
        let line = String(format: "%@ [%@]: footprint before %.0f MB, peak during the decode %.0f MB (%.0f MB above), held after %.0f MB",
                          url.lastPathComponent, "\(output.demosaic)", mb(before.current), mb(after.peak),
                          mb(after.peak) - mb(before.current), mb(after.current))
        print(line)
        return ["memory": line]
    }
}
