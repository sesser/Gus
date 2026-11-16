import CLibRaw
import CoreImage
import Foundation
import Metal
import PhotoCore
import PhotoFixtures

// SPIKE for issue #194 (question 2): throwaway. How good the demosaic is.
//
// `synthetic`: a known truth. Each real Bayer raw binned 2x2 (each color from
// its own sites, nothing interpolated) is a full-color picture with real
// detail; it is sampled through an RGGB mosaic, written as a DNG (black 0,
// white 65535, camera = linear sRGB), and demosaiced by ours, by LibRaw's
// demosaics and by the system decoder, each compared with the truth.
//
// `real`: the real mosaics, ours against LibRaw's default demosaic (both in
// the same camera RGB, through the same color step), and no-reference
// measures of false color for ours, LibRaw's, the system decoder's and
// Lightroom's renders of the same middle of the frame.
enum DemosaicQuality {
    /// LibRaw's demosaic of a file into camera RGB (balanced by `multipliers`,
    /// as `LibRawDecoder` asks), not turned (`user_flip` 0), values / 65535.
    static func libRaw(_ url: URL, quality: Int32?, multipliers: SIMD3<Double>) throws -> (picture: RGBPicture, ms: Double) {
        guard let processor = libraw_init(0) else { throw BenchError("no memory") }
        defer { libraw_close(processor) }
        libraw_set_output_bps(processor, 16)
        libraw_set_gamma(processor, 0, 1)
        libraw_set_gamma(processor, 1, 1)
        libraw_set_no_auto_bright(processor, 1)
        libraw_set_adjust_maximum_thr(processor, 0)
        libraw_set_output_color(processor, 0)
        let start = ContinuousClock.now
        guard libraw_open_file(processor, url.path) == LIBRAW_SUCCESS.rawValue else { throw BenchError("open") }
        processor.pointee.params.user_flip = 0
        processor.pointee.params.highlight = 1
        processor.pointee.params.use_camera_wb = 0
        processor.pointee.params.use_auto_wb = 0
        if let quality { processor.pointee.params.user_qual = quality }
        processor.pointee.params.user_mul = (Float(multipliers.x), Float(multipliers.y), Float(multipliers.z), Float(multipliers.y))
        guard libraw_unpack(processor) == LIBRAW_SUCCESS.rawValue, libraw_dcraw_process(processor) == LIBRAW_SUCCESS.rawValue else {
            throw BenchError("process")
        }
        var status: Int32 = 0
        guard let image = libraw_dcraw_make_mem_image(processor, &status) else { throw BenchError("image") }
        defer { libraw_dcraw_clear_mem(image) }
        let ms = (ContinuousClock.now - start).milliseconds
        let w = Int(image.pointee.width), h = Int(image.pointee.height)
        let offset = MemoryLayout<libraw_processed_image_t>.offset(of: \.data)!
        let source = UnsafeRawPointer(image).advanced(by: offset).assumingMemoryBound(to: UInt16.self)
        var pixels = [SIMD3<Float>](repeating: .zero, count: w * h)
        for i in 0..<(w * h) { pixels[i] = SIMD3(Float(source[i * 3]), Float(source[i * 3 + 1]), Float(source[i * 3 + 2])) / 65535 }
        return (RGBPicture(width: w, height: h, pixels: pixels), ms)
    }

    static let qualityNames: [Int32: String] = [0: "bilinear", 1: "VNG", 2: "PPG", 3: "AHD", 4: "DCB", 11: "DHT", 12: "AAHD"]

    // MARK: Synthetic truth

    static let srgbToXYZ: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = (
        SIMD3(0.4124, 0.3576, 0.1805), SIMD3(0.2126, 0.7152, 0.0722), SIMD3(0.0193, 0.1192, 0.9505))

    /// Lab of linear sRGB (D65), negatives clipped.
    static func labSRGB(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let p = pointwiseMax(c, .zero)
        let (a, b, d) = srgbToXYZ
        let xyz = SIMD3((p * a).sum(), (p * b).sum(), (p * d).sum()) / SIMD3(0.95047, 1.0, 1.08883)
        func f(_ t: Float) -> Float { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let fx = f(xyz.x), fy = f(xyz.y), fz = f(xyz.z)
        return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    static func encode(_ v: Float) -> Float {
        let x = min(max(v, 0), 1)
        return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
    }

    /// Color PSNR over the sRGB-encoded values (dB), a border left out.
    static func cpsnr(_ a: RGBPicture, _ truth: RGBPicture, border: Int = 8) -> Double {
        var sum = 0.0, n = 0.0
        for y in border..<(truth.height - border) {
            for x in border..<(truth.width - border) {
                let p = a[x, y], q = truth[x, y]
                for c in 0..<3 { let d = Double(encode(p[c]) - encode(q[c])); sum += d * d; n += 1 }
            }
        }
        return 10 * log10(1 / (sum / n))
    }

    static func synthetic(_ arguments: Arguments, files: [URL]) throws -> [String: any Sendable] {
        let demosaicer = try MetalDemosaicer()
        let scratch = FileManager.default.temporaryDirectory.appending(path: "decodespike-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let qualities: [Int32] = [0, 1, 2, 3, 4, 11, 12]
        print("Synthetic truth: each raw binned 2x2, through an RGGB mosaic; demosaics compared with the truth (8 px border left out).")
        print("ΔE76 in Lab of linear sRGB (the fictitious camera's space); edges = top 10% of the truth's L* gradient.")
        for url in files {
            let real = try RawMosaic(url)
            guard !real.isXTrans else { continue }
            let binned = try demosaicer.read(try demosaicer.run(real, algorithm: .bilinear, bin: 2, format: .rgba32Float).output)
            let w = (real.width / 2) & ~1, h = (real.height / 2) & ~1
            var truth = RGBPicture(rgba: binned, width: real.width / 2, height: real.height / 2).cropped(x: 0, y: 0, width: w, height: h)
            // The truth is what a 16-bit file holds: quantized, at most white.
            truth = truth.map { (pointwiseMin(pointwiseMax($0, .zero), SIMD3(repeating: 1)) * 65535).rounded(.toNearestOrEven) / 65535 }
            let rggb: [Int32] = [0, 1, 1, 2]
            let mosaic = RawMosaic(truth: truth.pixels, width: w, height: h, pattern: rggb, period: 2)
            let truthLab = truth.pixels.map(labSRGB)
            let edges = Measure.edgeMask(truthLab, width: w, height: h)
            print("\n\(url.lastPathComponent): truth \(w)x\(h)")
            func report(_ name: String, _ picture: RGBPicture, ms: Double? = nil) {
                let labs = picture.pixels.map(labSRGB)
                let c = Measure.compare(labs, truthLab, edges: edges, width: w, height: h)
                let fc = Measure.falseColor(labs, edges: edges, width: w, height: h)
                print(String(format: "  %-18@ CPSNR %5.2f dB  %@  edge HF chroma %.2f, detail %.2f%@", name as NSString, cpsnr(picture, truth),
                             c.description as NSString, fc.chroma, fc.detail, ms.map { String(format: "  (%.0f ms)", $0) } ?? ""))
            }
            let truthFC = Measure.falseColor(truthLab, edges: edges, width: w, height: h)
            print(String(format: "  %-18@ edge HF chroma %.2f, detail %.2f", "truth" as NSString, truthFC.chroma, truthFC.detail))
            for algorithm in DemosaicAlgorithm.allCases {
                let run = try demosaicer.run(mosaic, algorithm: algorithm, format: .rgba32Float)
                report("ours \(algorithm.rawValue)", RGBPicture(rgba: try demosaicer.read(run.output), width: w, height: h))
            }
            // The same mosaic as a DNG, for LibRaw and the system decoder.
            var data = Data(count: w * h * 2)
            data.withUnsafeMutableBytes { raw in
                let out = raw.bindMemory(to: UInt16.self)
                for i in 0..<(w * h) { out[i] = mosaic.values[i].littleEndian }
            }
            let dng = scratch.appending(path: "\(url.deletingPathExtension().lastPathComponent)-truth.dng")
            try SyntheticDNG.write(to: dng, options: SyntheticDNG.Options(width: w, height: h, seed: 1), mosaic: data)
            for quality in qualities {
                let lib = try libRaw(dng, quality: quality, multipliers: SIMD3(1, 1, 1))
                guard lib.picture.width == w, lib.picture.height == h else { print("  LibRaw size \(lib.picture.width)x\(lib.picture.height)"); continue }
                report("LibRaw \(qualityNames[quality]!)", lib.picture, ms: lib.ms)
            }
            // The system decoder: flat look (boost 0), noise reduction 0, rendered in linear sRGB (the camera's space), gain fitted.
            var adjustments = Adjustments()
            adjustments.decode.look = .flat
            adjustments.noiseReduction.luminance = 0
            adjustments.noiseReduction.color = 0
            if let image = try? PreviewGenerator().image(source: dng, stack: adjustments.editStack, longEdge: nil) {
                let context = CIContext(options: [.workingColorSpace: Measure.working, .workingFormat: CIFormat.RGBAh])
                let extent = image.extent.integral
                guard Int(extent.width) == w, Int(extent.height) == h else {
                    print("  system decoder: \(Int(extent.width))x\(Int(extent.height)), not the mosaic's size"); continue
                }
                var floats = [Float](repeating: 0, count: w * h * 4)
                floats.withUnsafeMutableBytes {
                    context.render(image, toBitmap: $0.baseAddress!, rowBytes: w * 16, bounds: extent, format: .RGBAf,
                                   colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
                }
                let system = RGBPicture(rgba: floats, width: w, height: h)
                // One gain: the median ratio of green over mid-tones.
                var ratios: [Float] = []
                for i in stride(from: 0, to: w * h, by: 7) where truth.pixels[i].y > 0.05 && truth.pixels[i].y < 0.5 {
                    ratios.append(truth.pixels[i].y / max(system.pixels[i].y, 1e-6))
                }
                ratios.sort()
                let gain = ratios[ratios.count / 2]
                print(String(format: "  system decoder: gain fitted %.3f (%+.2f EV)", gain, log2(gain)))
                report("system (flat)", system.map { $0 * gain })
            }
        }
        return [:]
    }

    // MARK: Real files

    static func real(_ arguments: Arguments, files: [URL]) throws -> [String: any Sendable] {
        let demosaicer = try MetalDemosaicer()
        let size = arguments.int("crop", default: 2048)
        let lightroom = arguments.values["lightroom"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        print("Real mosaics: the middle \(size)x\(size) of the frame (not turned), ΔE76 through the built-in color step and look.")
        for url in files {
            let mosaic = try RawMosaic(url)
            guard let color = mosaic.color, let step = Measure.ColorStep(CameraColorStep(color: color, channelScale: mosaic.channelScale)) else {
                print("\(url.lastPathComponent): no usable color"); continue
            }
            let x0 = (mosaic.width - size) / 2, y0 = (mosaic.height - size) / 2
            func shown(_ picture: RGBPicture) -> [SIMD3<Float>] {
                picture.cropped(x: x0, y: y0, width: size, height: size).pixels.map { Measure.lab(step.apply($0)) }
            }
            print("\n\(url.lastPathComponent) (\(mosaic.make) \(mosaic.model)), \(mosaic.width)x\(mosaic.height)")
            let reference = try libRaw(url, quality: nil, multipliers: mosaic.multipliers)
            let referenceLab = shown(reference.picture)
            let edges = Measure.edgeMask(referenceLab, width: size, height: size)
            let fcReference = Measure.falseColor(referenceLab, edges: edges, width: size, height: size)
            print(String(format: "  LibRaw %@ (its default): edge HF chroma %.2f, detail %.2f", (mosaic.isXTrans ? "3-pass X-Trans" : "AHD") as NSString,
                         fcReference.chroma, fcReference.detail))
            let bilinear = try libRaw(url, quality: 0, multipliers: mosaic.multipliers)
            let algorithms: [DemosaicAlgorithm] = mosaic.isXTrans ? [.bilinear] : DemosaicAlgorithm.allCases
            for algorithm in algorithms {
                let run = try demosaicer.run(mosaic, algorithm: algorithm, format: .rgba16Float)
                let ours = RGBPicture(rgba: try demosaicer.read(run.output), width: mosaic.width, height: mosaic.height)
                let labs = shown(ours)
                let c = Measure.compare(labs, referenceLab, edges: edges, width: size, height: size)
                let blocks = Measure.deltaE(Measure.blockLab(ours.cropped(x: x0, y: y0, width: size, height: size).map(step.apply)),
                                            Measure.blockLab(reference.picture.cropped(x: x0, y: y0, width: size, height: size).map(step.apply)))
                let fc = Measure.falseColor(labs, edges: edges, width: size, height: size)
                print("  ours \(algorithm.rawValue) vs LibRaw default: 16 px blocks \(Measure.Summary(blocks)); \(c)")
                print(String(format: "      edge HF chroma %.2f, detail %.2f", fc.chroma, fc.detail))
                if algorithm == .bilinear {
                    // Ours and LibRaw's bilinear do the same arithmetic: they should agree but for LibRaw's 16-bit output.
                    var differences: [Float] = []
                    var nearWhite = 0, over = 0
                    for y in 8..<(mosaic.height - 8) where y % 3 == 0 {
                        for x in 8..<(mosaic.width - 8) where x % 3 == 0 {
                            let d = max((ours[x, y] - bilinear.picture[x, y]).max(), (bilinear.picture[x, y] - ours[x, y]).max())
                            differences.append(d)
                            if d > 4 / 65535 {
                                over += 1
                                if bilinear.picture[x, y].max() > 0.9 * Float(mosaic.multipliers.min()) { nearWhite += 1 }
                            }
                        }
                    }
                    let sorted = differences.sorted()
                    print(String(format: "      vs LibRaw's own bilinear (q 0), every third pixel, in 65535ths: median %.2f, p99.9 %.2f, max %.1f; "
                                 + "%d of %d over 4, %d of those at a bright pixel (over 0.9 of the smallest channel's white)",
                                 sorted[sorted.count / 2] * 65535, sorted[Int(Double(sorted.count) * 0.999)] * 65535, sorted.last! * 65535,
                                 over, sorted.count, nearWhite))
                }
            }
            // The system decoder (the app's default render) and Lightroom: no-reference measures on the same middle, as shown (turned).
            func middle(_ image: CIImage) -> [SIMD3<Float>] {
                let e = image.extent
                let crop = CGRect(x: (e.midX - CGFloat(size) / 2).rounded(), y: (e.midY - CGFloat(size) / 2).rounded(), width: CGFloat(size), height: CGFloat(size))
                return Measure.render(image.cropped(to: crop)).pixels.map(Measure.lab)
            }
            func noReference(_ name: String, _ labs: [SIMD3<Float>]) {
                let edges = Measure.edgeMask(labs, width: size, height: size)
                let fc = Measure.falseColor(labs, edges: edges, width: size, height: size)
                print(String(format: "  %@: edge HF chroma %.2f, detail %.2f (its own edges)", name as NSString, fc.chroma, fc.detail))
            }
            noReference("LibRaw default, its own edges", referenceLab)
            if let system = PreviewGenerator.systemRAWImage(url) { noReference("system decoder (default)", middle(system)) }
            if let lightroom {
                let prefix = url.deletingPathExtension().lastPathComponent
                let tiff = lightroom.appending(path: "\(prefix)-adobe-standard.tif")
                if let image = CIImage(contentsOf: tiff) { noReference("Lightroom Adobe Standard (sharpening 40, color NR 25)", middle(image)) }
            }
        }
        return [:]
    }
}
