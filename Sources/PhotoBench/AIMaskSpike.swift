import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation
import ImageIO
import PhotoCore
import UniformTypeIdentifiers
import Vision

/// SPIKE, issue #88 R1 (AI masks). Throwaway measurement code: nothing in the
/// apps or `photocli` calls it, and the feature build replaces it. Findings are
/// in `docs/features/ai-masks/status.md`.
///
/// For each file: renders the detection input (the mask frame at the preview
/// tier's long edge, empty stack), runs Vision's foreground and person instance
/// mask requests (and the semantic person segmentation for comparison), and
/// reports availability, mask resolution and format, instance counts, coverage,
/// soft-edge share, determinism, per-device agreement, cost, and the stored
/// size of the all-instances mask under the candidate encodings. With
/// `--upscale` it compares upscaling methods against Vision's own scaled mask,
/// and with `--output DIR` writes overlays and edge crops to look at (never
/// commit them: they are the owner's photos).
///
/// `photobench aimask-spike --files a.jpg:b.RAF [--dir DIR] [--runs N] [--long-edge N|full] [--upscale]
///  [--devices] [--sizes] [--output DIR]`
enum AIMaskSpike {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        var files = (arguments.values["files"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: (String($0) as NSString).expandingTildeInPath) }
        if let dir = arguments.values["dir"] {
            let folder = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            let kinds: Set<String> = ["jpg", "jpeg", "heic", "raf", "orf", "rw2", "dng", "cr2", "cr3", "nef", "arw"]
            files += names.filter { kinds.contains(($0 as NSString).pathExtension.lowercased()) }
                .map { folder.appendingPathComponent($0) }
        }
        guard !files.isEmpty else { throw BenchError("aimask-spike needs --files a.jpg:b.RAF or --dir DIR") }
        let runs = max(arguments.int("runs", default: 3), 1)
        let output = arguments.values["output"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let longEdge: Int? = arguments.values["long-edge"] == "full" ? nil
            : arguments.int("long-edge", default: PreviewTier.preview.longEdge)
        setvbuf(stdout, nil, _IOLBF, 0)

        print("OS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("revisions: foreground \(VNGenerateForegroundInstanceMaskRequest.supportedRevisions.map { $0 }), "
              + "person \(VNGeneratePersonInstanceMaskRequest.supportedRevisions.map { $0 }), "
              + "segmentation \(VNGeneratePersonSegmentationRequest.supportedRevisions.map { $0 })")
        var rows: [[String: any Sendable]] = []
        var firstDetection: [String: Double] = [:]
        for file in files {
            var row: [String: any Sendable] = ["file": file.lastPathComponent]
            let (rendered, renderTime) = try await measure {
                try PreviewGenerator().cgImage(source: file, stack: EditStack(), longEdge: longEdge,
                                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            }
            row["input"] = "\(rendered.width)x\(rendered.height)"
            row["render_ms"] = renderTime.milliseconds
            var line = "\(file.lastPathComponent) \(rendered.width)x\(rendered.height) render \(fmt(renderTime.milliseconds)) ms"
            for kind in Kind.allCases {
                let before = MaskBenchmark.footprint()
                let result = try detect(kind, in: rendered, runs: runs)
                if rows.isEmpty {
                    line += "\n  \(kind.rawValue) footprint \(formatBytes(before)) -> \(formatBytes(MaskBenchmark.footprint()))"
                }
                if firstDetection[kind.rawValue] == nil { firstDetection[kind.rawValue] = result.timesMs.first }
                row[kind.rawValue] = result.dictionary
                line += "\n  \(kind.rawValue): \(result.summary)"
                guard let mask = result.mask else { continue }
                let storage = Storage.measure(mask)
                row["\(kind.rawValue)_storage"] = storage.dictionary
                line += "\n    storage: \(storage.summary)"
                if arguments.flags.contains("devices"), kind != .segmentation {
                    let devices = try deviceAgreement(kind, in: rendered, reference: mask)
                    row["\(kind.rawValue)_devices"] = devices
                    line += "\n    devices: \(devices.map { "\($0.key) \($0.value)" }.sorted().joined(separator: ", "))"
                }
                if arguments.flags.contains("sizes"), kind != .segmentation {
                    let sizes = try inputSizeSensitivity(kind, file: file)
                    row["\(kind.rawValue)_sizes"] = sizes
                    line += "\n    input sizes: \(sizes.sorted { $0.key < $1.key }.map { "\($0.key) -> \($0.value)" }.joined(separator: ", "))"
                }
                if arguments.flags.contains("upscale"), kind != .segmentation, let observation = result.observation {
                    let report = try Upscale.compare(mask: mask, observation: observation, image: rendered,
                                                     output: output, name: "\(file.deletingPathExtension().lastPathComponent)-\(kind.rawValue)")
                    row["\(kind.rawValue)_upscale"] = report.dictionary
                    line += "\n    upscale: \(report.summary)"
                }
                if let output {
                    try writeOverlay(rendered, mask: mask, to: output.appendingPathComponent(
                        "\(file.deletingPathExtension().lastPathComponent)-\(kind.rawValue)-overlay.png"))
                    try writeGray(mask, to: output.appendingPathComponent(
                        "\(file.deletingPathExtension().lastPathComponent)-\(kind.rawValue)-lowres.png"))
                }
            }
            print(line)
            rows.append(row)
        }
        print("first detection in process (model load included): \(firstDetection.map { "\($0.key) \(fmt($0.value)) ms" }.sorted().joined(separator: ", "))")
        return ["machine": machineDescription(), "files": rows, "first_detection_ms": firstDetection]
    }

    enum Kind: String, CaseIterable {
        case foreground, person, segmentation
    }

    /// A soft mask, row-major, values 0 … 1.
    struct Mask {
        var width: Int
        var height: Int
        var values: [Float]

        var coverage: Double { values.reduce(0) { $0 + Double($1) } / Double(max(values.count, 1)) }
        /// Share of pixels strictly between 2% and 98%: how soft the edges are.
        var softShare: Double { Double(values.filter { $0 > 0.02 && $0 < 0.98 }.count) / Double(max(values.count, 1)) }
        var quantized: [UInt8] { values.map { UInt8((min(max($0, 0), 1) * 255).rounded()) } }
    }

    struct Detection {
        var available = true
        var error: String?
        var timesMs: [Double] = []
        var instances = 0
        var labelSize = ""
        var labelFormat = ""
        var maskFormat = ""
        var confidence: Float = 0
        var mask: Mask?
        var deterministic: Bool?
        var maxRunDifference: Float = 0
        var observation: (observation: VNInstanceMaskObservation, handler: VNImageRequestHandler)?

        var summary: String {
            if let error { return "error \(error)" }
            guard let mask else { return "no result, times \(timesMs.map { fmt($0) }) ms" }
            return "instances \(instances), confidence \(confidence), label map \(labelSize) \(labelFormat), mask \(mask.width)x\(mask.height) \(maskFormat), "
                + "coverage \(pct(mask.coverage)), soft \(pct(mask.softShare)), deterministic \(deterministic.map { "\($0)" } ?? "-") "
                + "(max diff \(maxRunDifference)), times \(timesMs.map { fmt($0) }) ms"
        }

        var dictionary: [String: any Sendable] {
            var out: [String: any Sendable] = ["times_ms": timesMs, "instances": instances, "confidence": Double(confidence)]
            if let error { out["error"] = error }
            if let mask {
                out["mask"] = "\(mask.width)x\(mask.height)"
                out["coverage"] = mask.coverage
                out["soft_share"] = mask.softShare
                out["label_map"] = "\(labelSize) \(labelFormat)"
                out["mask_format"] = maskFormat
            }
            if let deterministic { out["deterministic"] = deterministic; out["max_run_difference"] = Double(maxRunDifference) }
            return out
        }
    }

    static func detect(_ kind: Kind, in image: CGImage, runs: Int, device: MLComputeDevice? = nil) throws -> Detection {
        var detection = Detection()
        var masks: [Mask] = []
        for _ in 0..<runs {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            let request: VNImageBasedRequest
            switch kind {
            case .foreground: request = VNGenerateForegroundInstanceMaskRequest()
            case .person: request = VNGeneratePersonInstanceMaskRequest()
            case .segmentation:
                let segmentation = VNGeneratePersonSegmentationRequest()
                segmentation.qualityLevel = .accurate
                segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent32Float
                request = segmentation
            }
            if let device { request.setComputeDevice(device, for: .main) }
            let start = DispatchTime.now()
            do {
                try handler.perform([request])
            } catch {
                detection.error = "\(error)"
                return detection
            }
            var mask: Mask?
            if kind == .segmentation {
                detection.confidence = (request as? VNGeneratePersonSegmentationRequest)?.results?.first?.confidence ?? 0
                if let buffer = (request as? VNGeneratePersonSegmentationRequest)?.results?.first?.pixelBuffer {
                    mask = read(buffer)
                    detection.maskFormat = fourCC(CVPixelBufferGetPixelFormatType(buffer))
                    detection.instances = (mask?.coverage ?? 0) > 0 ? 1 : 0
                }
            } else {
                let results = (request as? VNGenerateForegroundInstanceMaskRequest)?.results
                    ?? (request as? VNGeneratePersonInstanceMaskRequest)?.results
                if let observation = results?.first {
                    let labels = observation.instanceMask
                    detection.labelSize = "\(CVPixelBufferGetWidth(labels))x\(CVPixelBufferGetHeight(labels))"
                    detection.labelFormat = fourCC(CVPixelBufferGetPixelFormatType(labels))
                    detection.instances = observation.allInstances.count
                    detection.confidence = observation.confidence
                    if !observation.allInstances.isEmpty {
                        let buffer = try observation.generateMask(forInstances: observation.allInstances)
                        detection.maskFormat = fourCC(CVPixelBufferGetPixelFormatType(buffer))
                        mask = read(buffer)
                    }
                    detection.observation = (observation, handler)
                }
            }
            detection.timesMs.append(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6)
            if let mask { masks.append(mask) }
        }
        detection.mask = masks.first
        if masks.count > 1, let first = masks.first {
            detection.deterministic = masks.allSatisfy { $0.width == first.width && $0.height == first.height && $0.values == first.values }
            detection.maxRunDifference = masks.dropFirst().map { maxDifference($0, first) }.max() ?? 0
        }
        return detection
    }

    /// Whether running on each compute device Vision offers gives the default's mask.
    static func deviceAgreement(_ kind: Kind, in image: CGImage, reference: Mask) throws -> [String: String] {
        let request: VNRequest = kind == .foreground ? VNGenerateForegroundInstanceMaskRequest() : VNGeneratePersonInstanceMaskRequest()
        var out: [String: String] = [:]
        for device in (try request.supportedComputeStageDevices[.main]) ?? [] {
            let name: String
            switch device {
            case .cpu: name = "cpu"
            case .gpu: name = "gpu"
            case .neuralEngine: name = "neuralEngine"
            @unknown default: name = "other"
            }
            let detection = try detect(kind, in: image, runs: 1, device: device)
            guard let mask = detection.mask else { out[name] = detection.error ?? "no mask"; continue }
            guard mask.width == reference.width, mask.height == reference.height else {
                out[name] = "size \(mask.width)x\(mask.height)"
                continue
            }
            let differing = zip(mask.values, reference.values).filter { abs($0 - $1) > 1.0 / 255 }.count
            out[name] = "max diff \(String(format: "%.4f", maxDifference(mask, reference))), "
                + "\(pct(Double(differing) / Double(mask.values.count))) differ by > 1/255, \(fmt(detection.timesMs.first ?? 0)) ms"
        }
        return out
    }

    /// Mask size for the same file rendered at other long edges.
    static func inputSizeSensitivity(_ kind: Kind, file: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        for edge in [512, 1024, 2560, 4096] {
            let image = try PreviewGenerator().cgImage(source: file, stack: EditStack(), longEdge: edge,
                                                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            let detection = try detect(kind, in: image, runs: 1)
            out["\(image.width)x\(image.height)"] = detection.mask.map {
                "\($0.width)x\($0.height), \(detection.instances) instances, coverage \(pct($0.coverage)), \(fmt(detection.timesMs.first ?? 0)) ms"
            } ?? "no mask"
        }
        return out
    }

    // MARK: Storage

    /// The all-instances mask, quantized to 8 bits, under each candidate encoding.
    struct Storage {
        var float32: Int
        var raw8: Int
        var raw8LZFSE: Int
        var raw8Zlib: Int
        var png8: Int
        var quantizationError: Float
        var stackPlain: Int
        var stackWithInline: Int
        var historySnapshotPlain: Int
        var historySnapshotInline: Int

        static func measure(_ mask: Mask) -> Storage {
            let bytes = mask.quantized
            let raw = Data(bytes)
            let lzfse = (try? (raw as NSData).compressed(using: .lzfse) as Data)?.count ?? -1
            let zlib = (try? (raw as NSData).compressed(using: .zlib) as Data)?.count ?? -1
            let png = pngData(bytes, width: mask.width, height: mask.height)
            let error = zip(bytes, mask.values).map { abs(Float($0) / 255 - min(max($1, 0), 1)) }.max() ?? 0
            // A typical stack, and the same with one mask whose component carries the PNG inline.
            let typical = EditBenchmark.typical.editStack
            var inline = typical
            inline.operations.append(EditOperation(kind: "localAdjustments", kindVersion: 2, parameters: [
                "masks": .list([.object([
                    "id": .string(UUID().uuidString),
                    "adjustments": .object(["exposure": .number(-0.7)]),
                    "components": .list([.object(["shape": .string("subject"),
                                                  "raster": .string(png.base64EncodedString())])]),
                ])]),
            ]))
            let plainJSON = (try? typical.jsonString()) ?? ""
            let inlineJSON = (try? inline.jsonString()) ?? ""
            func snapshot(_ json: String) -> Int {
                (try? (Data(json.utf8) as NSData).compressed(using: .lzfse) as Data)?.count ?? -1
            }
            return Storage(float32: mask.values.count * 4, raw8: raw.count, raw8LZFSE: lzfse, raw8Zlib: zlib,
                           png8: png.count, quantizationError: error, stackPlain: plainJSON.utf8.count,
                           stackWithInline: inlineJSON.utf8.count, historySnapshotPlain: snapshot(plainJSON),
                           historySnapshotInline: snapshot(inlineJSON))
        }

        var summary: String {
            "float32 \(float32) B, 8-bit raw \(raw8) B, LZFSE \(raw8LZFSE) B, zlib \(raw8Zlib) B, PNG \(png8) B "
                + "(8-bit error max \(String(format: "%.5f", quantizationError))); stack JSON \(stackPlain) -> \(stackWithInline) B inline, "
                + "history snapshot \(historySnapshotPlain) -> \(historySnapshotInline) B "
                + "(\(4 * 1024 * 1024 / max(historySnapshotInline, 1)) such entries fit 4 MiB)"
        }

        var dictionary: [String: any Sendable] {
            ["float32": float32, "raw8": raw8, "raw8_lzfse": raw8LZFSE, "raw8_zlib": raw8Zlib, "png8": png8,
             "quantization_error": Double(quantizationError), "stack_plain": stackPlain, "stack_inline": stackWithInline,
             "history_snapshot_plain": historySnapshotPlain, "history_snapshot_inline": historySnapshotInline]
        }
    }

    // MARK: Upscaling

    enum Upscale {
        struct Report {
            var visionScaledSize = ""
            var visionScaledMs = 0.0
            /// Method name to (mean absolute difference from Vision's scaled mask over all
            /// pixels, over the edge band, time in ms).
            var methods: [(String, Double, Double, Double)] = []
            var bandShare = 0.0

            var summary: String {
                "vision scaled \(visionScaledSize) in \(fmt(visionScaledMs)) ms, edge band \(pct(bandShare)); "
                    + methods.map { "\($0.0): MAD \(String(format: "%.4f", $0.1)) all, \(String(format: "%.4f", $0.2)) band, \(fmt($0.3)) ms" }
                    .joined(separator: "; ")
            }

            var dictionary: [String: any Sendable] {
                var out: [String: any Sendable] = ["vision_scaled": visionScaledSize, "vision_scaled_ms": visionScaledMs,
                                                   "band_share": bandShare]
                for method in methods {
                    out[method.0] = ["mad_all": method.1, "mad_band": method.2, "ms": method.3] as [String: any Sendable]
                }
                return out
            }
        }

        static func compare(mask: Mask, observation: (observation: VNInstanceMaskObservation, handler: VNImageRequestHandler),
                            image: CGImage, output: URL?, name: String) throws -> Report {
            var report = Report()
            let start = DispatchTime.now()
            let scaledBuffer = try observation.observation.generateScaledMaskForImage(
                forInstances: observation.observation.allInstances, from: observation.handler)
            report.visionScaledMs = elapsed(since: start)
            let reference = read(scaledBuffer)
            report.visionScaledSize = "\(reference.width)x\(reference.height) \(fourCC(CVPixelBufferGetPixelFormatType(scaledBuffer))) "
                + "range \(String(format: "%.3f", reference.values.min() ?? 0))…\(String(format: "%.3f", reference.values.max() ?? 0))"
            let width = image.width, height = image.height
            let guide = luminance(image)
            let planes = rgbPlanes(image)

            var results: [(String, Mask)] = []
            var t = DispatchTime.now()
            let bilinear = resizeBilinear(mask, width: width, height: height)
            results.append(("bilinear", bilinear))
            report.methods.append(("bilinear", 0, 0, elapsed(since: t)))
            for (radius, epsilon) in [(4, 1e-3), (8, 1e-4), (8, 1e-3)] {
                t = DispatchTime.now()
                let guided = FastGuidedFilter.upscale(mask, guide: guide, width: width, height: height,
                                                      radius: radius, epsilon: epsilon)
                let label = "fastGuided r\(radius) e\(epsilon)"
                results.append((label, guided))
                report.methods.append((label, 0, 0, elapsed(since: t)))
            }
            for (radius, epsilon) in [(4, 1e-3), (4, 1e-4), (2, 1e-4)] {
                t = DispatchTime.now()
                let guided = FastGuidedFilter.upscaleColor(mask, planes: planes, width: width, height: height,
                                                           radius: radius, epsilon: epsilon)
                let label = "colorGuided r\(radius) e\(epsilon)"
                results.append((label, guided))
                report.methods.append((label, 0, 0, elapsed(since: t)))
            }
            // The plain guided filter at the output size, on the bilinear upscale,
            // with a window about one mask pixel across.
            let fullRadius = Int((Double(width) / Double(mask.width)).rounded(.up))
            for (epsilon, color) in [(1e-3, false), (1e-4, true), (1e-3, true)] {
                t = DispatchTime.now()
                let guided = color
                    ? FastGuidedFilter.upscaleColor(bilinear, planes: planes, width: width, height: height,
                                                    radius: fullRadius, epsilon: epsilon)
                    : FastGuidedFilter.upscale(bilinear, guide: guide, width: width, height: height,
                                               radius: fullRadius, epsilon: epsilon)
                let label = "full\(color ? "Color" : "Gray") r\(fullRadius) e\(epsilon)"
                results.append((label, guided))
                report.methods.append((label, 0, 0, elapsed(since: t)))
            }
            // The same gray guided filter on the GPU, in the app's half-float working format.
            if let cpu = results.first(where: { $0.0.hasPrefix("fullGray") })?.1 {
                for format in [CIFormat.RGBAh, CIFormat.RGBAf] {
                    var times: [Double] = []
                    var gpu: Mask?
                    for _ in 0..<3 {
                        t = DispatchTime.now()
                        gpu = try GPUGuidedFilter.upscale(mask, image: image, radius: fullRadius, epsilon: 1e-3,
                                                          format: format)
                        times.append(elapsed(since: t))
                    }
                    let identity = GPUGuidedFilter.identityRenderMs(image, format: format)
                    let label = "gpuGray \(format == .RGBAh ? "half" : "float")"
                    if let gpu {
                        let difference = zip(gpu.values, cpu.values).map { Double(abs($0 - $1)) }
                        print("    \(label): vs CPU fullGray mean \(String(format: "%.5f", difference.reduce(0, +) / Double(difference.count))) "
                              + "max \(String(format: "%.4f", difference.max() ?? 0)); render+readback \(times.map { fmt($0) }) ms, "
                              + "identity render+readback \(fmt(identity)) ms")
                        results.append((label, gpu))
                        report.methods.append((label, 0, 0, times.min() ?? 0))
                    }
                }
            }
            for radius in [1.0, 4.0] {
                t = DispatchTime.now()
                let guided = coreImageGuided(mask, image: image, radius: radius, epsilon: 1e-3)
                let label = "CIGuidedFilter r\(Int(radius))"
                results.append((label, guided))
                report.methods.append((label, 0, 0, elapsed(since: t)))
            }

            // The edge band: where the reference or the bilinear upscale is undecided.
            var band = [Bool](repeating: false, count: width * height)
            let sameSize = reference.width == width && reference.height == height
            for index in 0..<(width * height) {
                let b = bilinear.values[index]
                let r = sameSize ? reference.values[index] : b
                band[index] = (b > 0.02 && b < 0.98) || (r > 0.02 && r < 0.98)
            }
            let bandCount = band.filter { $0 }.count
            report.bandShare = Double(bandCount) / Double(width * height)
            for (index, (label, result)) in results.enumerated() where sameSize {
                var all = 0.0, inBand = 0.0
                for i in 0..<(width * height) {
                    let d = Double(abs(result.values[i] - reference.values[i]))
                    all += d
                    if band[i] { inBand += d }
                }
                report.methods[index] = (label, all / Double(width * height), inBand / Double(max(bandCount, 1)),
                                         report.methods[index].3)
            }
            if let output {
                // A 400 px crop where the band is densest, for each method beside Vision's.
                let crop = densestWindow(band, width: width, height: height, size: 400)
                var tiles: [(String, Mask)] = [("vision", reference)] + results
                tiles = tiles.filter { $0.1.width == width && $0.1.height == height }
                for (label, result) in tiles {
                    try writeOverlay(image, mask: result, crop: crop, to: output.appendingPathComponent(
                        "\(name)-crop-\(label.replacingOccurrences(of: " ", with: "_")).png"))
                }
            }
            return report
        }

        static func elapsed(since start: DispatchTime) -> Double {
            Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
        }

        static func densestWindow(_ band: [Bool], width: Int, height: Int, size: Int) -> CGRect {
            let step = 50
            var best = (0, 0, -1)
            for y in stride(from: 0, through: max(height - size, 0), by: step) {
                for x in stride(from: 0, through: max(width - size, 0), by: step) {
                    var count = 0
                    for yy in stride(from: y, to: min(y + size, height), by: 4) {
                        for xx in stride(from: x, to: min(x + size, width), by: 4) where band[yy * width + xx] { count += 1 }
                    }
                    if count > best.2 { best = (x, y, count) }
                }
            }
            return CGRect(x: best.0, y: best.1, width: min(size, width), height: min(size, height))
        }

        static func coreImageGuided(_ mask: Mask, image: CGImage, radius: Double, epsilon: Double) -> Mask {
            let small = CIImage(bitmapData: Data(bytes: mask.values, count: mask.values.count * 4),
                                bytesPerRow: mask.width * 4, size: CGSize(width: mask.width, height: mask.height),
                                format: .Rf, colorSpace: nil)
            let guide = CIImage(cgImage: image)
            let filter = CIFilter(name: "CIGuidedFilter")!
            filter.setValue(small, forKey: kCIInputImageKey)
            filter.setValue(guide, forKey: "inputGuideImage")
            filter.setValue(radius, forKey: kCIInputRadiusKey)
            filter.setValue(epsilon, forKey: "inputEpsilon")
            let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
            var values = [Float](repeating: 0, count: image.width * image.height * 4)
            if let outputImage = filter.outputImage {
                context.render(outputImage, toBitmap: &values, rowBytes: image.width * 16,
                               bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                               format: .RGBAf, colorSpace: nil)
            }
            // Bitmaps in and out of Core Image are both top row first, so rows line up.
            var out = [Float](repeating: 0, count: image.width * image.height)
            // CIGuidedFilter gives NaN in places (a small subject): counted as 0 here.
            for i in 0..<(image.width * image.height) { out[i] = values[i * 4].isNaN ? 0 : min(max(values[i * 4], 0), 1) }
            return Mask(width: image.width, height: image.height, values: out)
        }
    }

    /// He and Sun, "Fast Guided Filter" (arXiv 1505.00996, 2015), on a gray
    /// guide: the linear coefficients are solved at the mask's resolution
    /// against the guide reduced to it, upsampled bilinearly, and applied to
    /// the full-resolution guide. Plain Swift, as a reference for a later kernel.
    enum FastGuidedFilter {
        static func upscale(_ mask: Mask, guide: Mask, width: Int, height: Int, radius: Int, epsilon: Double) -> Mask {
            let w = mask.width, h = mask.height
            let guideSmall = resizeArea(guide, width: w, height: h)
            let I = guideSmall.values.map(Double.init), p = mask.values.map(Double.init)
            let meanI = box(I, w, h, radius), meanP = box(p, w, h, radius)
            let corrII = box(zip(I, I).map(*), w, h, radius), corrIP = box(zip(I, p).map(*), w, h, radius)
            var a = [Double](repeating: 0, count: w * h), b = a
            for i in 0..<(w * h) {
                let variance = corrII[i] - meanI[i] * meanI[i]
                let covariance = corrIP[i] - meanI[i] * meanP[i]
                a[i] = covariance / (variance + epsilon)
                b[i] = meanP[i] - a[i] * meanI[i]
            }
            let meanA = Mask(width: w, height: h, values: box(a, w, h, radius).map(Float.init))
            let meanB = Mask(width: w, height: h, values: box(b, w, h, radius).map(Float.init))
            let bigA = resizeBilinear(meanA, width: width, height: height, clamp: false)
            let bigB = resizeBilinear(meanB, width: width, height: height, clamp: false)
            var out = [Float](repeating: 0, count: width * height)
            for i in 0..<(width * height) { out[i] = min(max(bigA.values[i] * guide.values[i] + bigB.values[i], 0), 1) }
            return Mask(width: width, height: height, values: out)
        }

        /// The same with the color guide (He, Sun and Tang 2013, eq. 14): a 3x3
        /// covariance per pixel, solved at the mask's resolution.
        static func upscaleColor(_ mask: Mask, planes: [Mask], width: Int, height: Int, radius: Int,
                                 epsilon: Double) -> Mask {
            let w = mask.width, h = mask.height, n = w * h
            let small = planes.map { resizeArea($0, width: w, height: h).values.map(Double.init) }
            let p = mask.values.map(Double.init)
            let m = small.map { box($0, w, h, radius) }
            let mp = box(p, w, h, radius)
            var products: [[Double]] = []
            for (i, j) in [(0, 0), (0, 1), (0, 2), (1, 1), (1, 2), (2, 2)] {
                products.append(box(zip(small[i], small[j]).map(*), w, h, radius))
            }
            let ip = (0..<3).map { box(zip(small[$0], p).map(*), w, h, radius) }
            var a = [[Double]](repeating: [Double](repeating: 0, count: n), count: 3)
            var b = [Double](repeating: 0, count: n)
            for k in 0..<n {
                let rr = products[0][k] - m[0][k] * m[0][k] + epsilon, rg = products[1][k] - m[0][k] * m[1][k]
                let rb = products[2][k] - m[0][k] * m[2][k], gg = products[3][k] - m[1][k] * m[1][k] + epsilon
                let gb = products[4][k] - m[1][k] * m[2][k], bb = products[5][k] - m[2][k] * m[2][k] + epsilon
                let c = (0..<3).map { ip[$0][k] - m[$0][k] * mp[k] }
                // Symmetric 3x3 inverse by cofactors.
                let i00 = gg * bb - gb * gb, i01 = rb * gb - rg * bb, i02 = rg * gb - rb * gg
                let i11 = rr * bb - rb * rb, i12 = rb * rg - rr * gb, i22 = rr * gg - rg * rg
                let det = rr * i00 + rg * i01 + rb * i02
                let a0 = (i00 * c[0] + i01 * c[1] + i02 * c[2]) / det
                let a1 = (i01 * c[0] + i11 * c[1] + i12 * c[2]) / det
                let a2 = (i02 * c[0] + i12 * c[1] + i22 * c[2]) / det
                a[0][k] = a0; a[1][k] = a1; a[2][k] = a2
                b[k] = mp[k] - a0 * m[0][k] - a1 * m[1][k] - a2 * m[2][k]
            }
            let big = (a + [b]).map {
                resizeBilinear(Mask(width: w, height: h, values: box($0, w, h, radius).map(Float.init)),
                               width: width, height: height, clamp: false).values
            }
            var out = [Float](repeating: 0, count: width * height)
            for i in 0..<(width * height) {
                let q = big[0][i] * planes[0].values[i] + big[1][i] * planes[1].values[i] + big[2][i] * planes[2].values[i] + big[3][i]
                out[i] = min(max(q, 0), 1)
            }
            return Mask(width: width, height: height, values: out)
        }

        /// Mean over a (2r+1)² window, clipped at the edges (summed-area table).
        static func box(_ values: [Double], _ w: Int, _ h: Int, _ r: Int) -> [Double] {
            var sat = [Double](repeating: 0, count: (w + 1) * (h + 1))
            for y in 0..<h {
                var row = 0.0
                for x in 0..<w {
                    row += values[y * w + x]
                    sat[(y + 1) * (w + 1) + x + 1] = sat[y * (w + 1) + x + 1] + row
                }
            }
            var out = [Double](repeating: 0, count: w * h)
            for y in 0..<h {
                let y0 = max(y - r, 0), y1 = min(y + r, h - 1) + 1
                for x in 0..<w {
                    let x0 = max(x - r, 0), x1 = min(x + r, w - 1) + 1
                    let sum = sat[y1 * (w + 1) + x1] - sat[y0 * (w + 1) + x1] - sat[y1 * (w + 1) + x0] + sat[y0 * (w + 1) + x0]
                    out[y * w + x] = sum / Double((y1 - y0) * (x1 - x0))
                }
            }
            return out
        }
    }

    /// The gray guided filter at the output size as a Core Image graph: two
    /// stitchable color kernels and two `CIBoxBlur`s (spike; window and edge
    /// handling are CIBoxBlur's, close to but not exactly the CPU reference's).
    enum GPUGuidedFilter {
        static let source = """
            #include <metal_stdlib>
            #include <CoreImage/CoreImage.h>
            using namespace metal;
            extern "C" {
            namespace coreimage {
            [[stitchable]] float4 gfPrepare(sample_t guide, sample_t mask) {
                float i = dot(guide.rgb, float3(0.2126, 0.7152, 0.0722));
                float p = mask.r;
                return float4(i, p, i * i, i * p);
            }
            [[stitchable]] float4 gfCoefficients(sample_t means, float epsilon) {
                float variance = means.b - means.r * means.r;
                float covariance = means.a - means.r * means.g;
                float a = covariance / (variance + epsilon);
                return float4(a, means.g - a * means.r, 0, 1);
            }
            [[stitchable]] float4 gfApply(sample_t coefficients, sample_t guide) {
                float i = dot(guide.rgb, float3(0.2126, 0.7152, 0.0722));
                float q = clamp(coefficients.r * i + coefficients.g, 0.0, 1.0);
                return float4(q, q, q, 1);
            }
            }
            }
            """

        static let kernels: [String: CIColorKernel] = {
            // Spike only: a failed compile shows up as a crash in a measurement tool.
            let compiled = try! CIKernel.kernels(withMetalString: source)
            return Dictionary(compiled.compactMap { kernel in (kernel as? CIColorKernel).map { (kernel.name, $0) } },
                              uniquingKeysWith: { first, _ in first })
        }()

        static func context(_ format: CIFormat) -> CIContext {
            CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .workingFormat: format,
                                .cacheIntermediates: false])
        }

        static func upscale(_ mask: Mask, image: CGImage, radius: Int, epsilon: Double, format: CIFormat) throws -> Mask {
            let width = image.width, height = image.height
            let extent = CGRect(x: 0, y: 0, width: width, height: height)
            let small = CIImage(bitmapData: Data(bytes: mask.values, count: mask.values.count * 4),
                                bytesPerRow: mask.width * 4, size: CGSize(width: mask.width, height: mask.height),
                                format: .Rf, colorSpace: nil)
            // Pixel centers aligned, as the CPU's bilinear.
            let p = small.clampedToExtent().samplingLinear()
                .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / CGFloat(mask.width),
                                                   y: CGFloat(height) / CGFloat(mask.height)))
                .cropped(to: extent)
            let guide = CIImage(cgImage: image)
            func box(_ input: CIImage) -> CIImage {
                input.clampedToExtent().applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: Double(radius)])
                    .cropped(to: extent)
            }
            guard let prepared = kernels["gfPrepare"]?.apply(extent: extent, arguments: [guide, p]),
                  let coefficients = kernels["gfCoefficients"]?.apply(extent: extent,
                                                                      arguments: [box(prepared), Float(epsilon)]),
                  let output = kernels["gfApply"]?.apply(extent: extent, arguments: [box(coefficients), guide])
            else { throw BenchError("guided filter kernels missing") }
            var values = [Float](repeating: 0, count: width * height * 4)
            context(format).render(output, toBitmap: &values, rowBytes: width * 16, bounds: extent, format: .RGBAf,
                                   colorSpace: nil)
            return Mask(width: width, height: height, values: stride(from: 0, to: values.count, by: 4).map { values[$0] })
        }

        /// What rendering the guide alone and reading it back costs, to set the filter's time against.
        static func identityRenderMs(_ image: CGImage, format: CIFormat) -> Double {
            let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            var values = [Float](repeating: 0, count: image.width * image.height * 4)
            let start = DispatchTime.now()
            context(format).render(CIImage(cgImage: image), toBitmap: &values, rowBytes: image.width * 16, bounds: extent,
                                   format: .RGBAf, colorSpace: nil)
            return Upscale.elapsed(since: start)
        }
    }

    // MARK: Pixels

    static func read(_ buffer: CVPixelBuffer) -> Mask {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!
        var values = [Float](repeating: 0, count: width * height)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes)
            for x in 0..<width {
                switch format {
                case kCVPixelFormatType_OneComponent32Float:
                    values[y * width + x] = row.assumingMemoryBound(to: Float.self)[x]
                case kCVPixelFormatType_OneComponent8:
                    values[y * width + x] = Float(row.assumingMemoryBound(to: UInt8.self)[x]) / 255
                case kCVPixelFormatType_OneComponent16Half:
                    values[y * width + x] = Float(row.assumingMemoryBound(to: Float16.self)[x])
                default:
                    values[y * width + x] = 0
                }
            }
        }
        return Mask(width: width, height: height, values: values)
    }

    /// Rec. 709 luma of the sRGB-encoded image, 0 … 1, top-down.
    static func luminance(_ image: CGImage) -> Mask {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var values = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            values[i] = (0.2126 * Float(rgba[i * 4]) + 0.7152 * Float(rgba[i * 4 + 1]) + 0.0722 * Float(rgba[i * 4 + 2])) / 255
        }
        return Mask(width: width, height: height, values: values)
    }

    /// The sRGB-encoded red, green and blue planes, 0 … 1, top-down.
    static func rgbPlanes(_ image: CGImage) -> [Mask] {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (0..<3).map { channel in
            Mask(width: width, height: height, values: (0..<(width * height)).map { Float(rgba[$0 * 4 + channel]) / 255 })
        }
    }

    /// Bilinear resampling with pixel centers aligned (as Core Image's linear sampling).
    static func resizeBilinear(_ mask: Mask, width: Int, height: Int, clamp: Bool = true) -> Mask {
        var out = [Float](repeating: 0, count: width * height)
        let sx = Float(mask.width) / Float(width), sy = Float(mask.height) / Float(height)
        for y in 0..<height {
            let fy = min(max((Float(y) + 0.5) * sy - 0.5, 0), Float(mask.height - 1))
            let y0 = Int(fy), y1 = min(y0 + 1, mask.height - 1), ty = fy - Float(y0)
            for x in 0..<width {
                let fx = min(max((Float(x) + 0.5) * sx - 0.5, 0), Float(mask.width - 1))
                let x0 = Int(fx), x1 = min(x0 + 1, mask.width - 1), tx = fx - Float(x0)
                let top = mask.values[y0 * mask.width + x0] * (1 - tx) + mask.values[y0 * mask.width + x1] * tx
                let bottom = mask.values[y1 * mask.width + x0] * (1 - tx) + mask.values[y1 * mask.width + x1] * tx
                let value = top * (1 - ty) + bottom * ty
                out[y * width + x] = clamp ? min(max(value, 0), 1) : value
            }
        }
        return Mask(width: width, height: height, values: out)
    }

    /// Area-average reduction (box over each output pixel's footprint).
    static func resizeArea(_ mask: Mask, width: Int, height: Int) -> Mask {
        var sums = [Double](repeating: 0, count: width * height), counts = sums
        for y in 0..<mask.height {
            let oy = min(y * height / mask.height, height - 1)
            for x in 0..<mask.width {
                let ox = min(x * width / mask.width, width - 1)
                sums[oy * width + ox] += Double(mask.values[y * mask.width + x])
                counts[oy * width + ox] += 1
            }
        }
        return Mask(width: width, height: height, values: zip(sums, counts).map { Float($0 / max($1, 1)) })
    }

    static func maxDifference(_ a: Mask, _ b: Mask) -> Float {
        guard a.width == b.width, a.height == b.height else { return .infinity }
        return zip(a.values, b.values).map { abs($0 - $1) }.max() ?? 0
    }

    static func pngData(_ bytes: [UInt8], width: Int, height: Int) -> Data {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func writeGray(_ mask: Mask, to url: URL) throws {
        try pngData(mask.quantized, width: mask.width, height: mask.height).write(to: url)
    }

    /// The image with everything outside the mask dimmed to a quarter and
    /// tinted red, so edges show; optionally cropped (top-down rectangle).
    static func writeOverlay(_ image: CGImage, mask: Mask, crop: CGRect? = nil, to url: URL) throws {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let full = mask.width == width && mask.height == height ? mask : resizeBilinear(mask, width: width, height: height)
        for i in 0..<(width * height) {
            let m = full.values[i].isNaN ? 0 : min(max(full.values[i], 0), 1)
            let keep = 0.25 + 0.75 * m
            rgba[i * 4] = UInt8(min(255, Float(rgba[i * 4]) * keep + (1 - m) * 90))
            rgba[i * 4 + 1] = UInt8(Float(rgba[i * 4 + 1]) * keep)
            rgba[i * 4 + 2] = UInt8(Float(rgba[i * 4 + 2]) * keep)
        }
        var out = context.makeImage()!
        if let crop { out = out.cropping(to: crop) ?? out }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, out, nil)
        guard CGImageDestinationFinalize(destination) else { throw BenchError("could not write \(url.path)") }
    }

    static func fourCC(_ type: OSType) -> String {
        let bytes = [UInt8((type >> 24) & 0xff), UInt8((type >> 16) & 0xff), UInt8((type >> 8) & 0xff), UInt8(type & 0xff)]
        return String(decoding: bytes, as: UTF8.self)
    }

    static func pct(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}

private func fmt(_ value: Double) -> String { String(format: "%.1f", value) }
