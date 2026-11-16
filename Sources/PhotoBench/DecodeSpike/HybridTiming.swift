import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal
import PhotoCore

// SPIKE for issue #194 (questions 2 and 5): throwaway. Time of the hybrid
// pipeline (LibRaw unpack, our Metal demosaic, the color step in Core Image)
// against LibRaw's whole decode and the system decoder, to a preview (2560 px
// long edge, 8-bit) and at full size (half float), and the live path.
enum HybridTiming {
    static let previewEdge = 2560

    /// The demosaiced texture as a Core Image image: tagged as the working
    /// space (its camera RGB passes through unconverted, as `LibRawDecoder`'s
    /// does), the right way up, turned as the file says.
    static func image(_ texture: MTLTexture, flip: Int) -> CIImage {
        let h = CGFloat(texture.height)
        var image = CIImage(mtlTexture: texture, options: [.colorSpace: Measure.working])!
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -h))
        switch flip {
        case 3: image = image.oriented(.down)
        case 5: image = image.oriented(.left)
        case 6: image = image.oriented(.right)
        default: break
        }
        let e = image.extent
        return image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
    }

    static func scaled(_ image: CIImage, longEdge: Int) -> CIImage {
        let e = image.extent
        let scale = Double(longEdge) / Double(max(e.width, e.height))
        guard scale < 1 else { return image }
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = image
        lanczos.scale = Float(scale)
        return lanczos.outputImage!
    }

    /// Renders to 8-bit sRGB (a preview) or half float (full size), returns ms.
    static func render(_ image: CIImage, context: CIContext, eightBit: Bool) -> Double {
        let start = ContinuousClock.now
        let e = image.extent.integral
        let w = Int(e.width), h = Int(e.height)
        let bytes = eightBit ? 4 : 8
        var buffer = [UInt8](repeating: 0, count: w * h * bytes)
        buffer.withUnsafeMutableBytes {
            context.render(image, toBitmap: $0.baseAddress!, rowBytes: w * bytes, bounds: e,
                           format: eightBit ? .RGBA8 : .RGBAh,
                           colorSpace: eightBit ? CGColorSpace(name: CGColorSpace.sRGB)! : Measure.working)
        }
        return (ContinuousClock.now - start).milliseconds
    }

    struct Row {
        var label: String
        var samples: [Double] = []
        var parts: [String: [Double]] = [:]
        mutating func add(_ total: Double, _ parts: [String: Double] = [:]) {
            samples.append(total)
            for (k, v) in parts { self.parts[k, default: []].append(v) }
        }
        var line: String {
            let first = samples.first ?? .nan
            let rest = Array(samples.dropFirst())
            let warm = rest.isEmpty ? Double.nan : LibRawStages.median(rest)
            let spread = rest.isEmpty ? "" : String(format: " (%.0f–%.0f)", rest.min()!, rest.max()!)
            let partText = parts.keys.sorted().map { k in String(format: "%@ %.1f", k as NSString, LibRawStages.median(Array(parts[k]!.dropFirst().isEmpty ? parts[k]! : Array(parts[k]!.dropFirst())))) }
                .joined(separator: ", ")
            return String(format: "  %-44@ first %7.0f ms, then median %7.0f ms%@   [%@]", label as NSString, first, warm, spread, partText as NSString)
        }
    }

    static func run(_ arguments: Arguments, files: [URL]) throws -> [String: any Sendable] {
        let runs = arguments.int("runs", default: 6)
        let demosaicer = try MetalDemosaicer()
        print(String(format: "Metal library and pipelines compiled in %.0f ms (once per process)", demosaicer.compileMs))
        let context = CIContext(mtlCommandQueue: demosaicer.queue,
                                options: [.workingColorSpace: Measure.working, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
        let appContext = Measure.context()
        print("Each line: the first run in this process (files already in the OS file cache), then the median of the next \(runs - 1) (min–max).")
        for url in files {
            let probe = try RawMosaic(url)
            print("\n\(url.lastPathComponent): \(probe.make) \(probe.model), visible \(probe.width)x\(probe.height) (\(String(format: "%.1f", Double(probe.width * probe.height) / 1e6)) MP), \(probe.isXTrans ? "X-Trans" : "Bayer")")
            let algorithms: [DemosaicAlgorithm] = probe.isXTrans ? [.bilinear] : DemosaicAlgorithm.allCases
            let bin = probe.isXTrans ? 3 : 2
            // Our pipeline: unpack, demosaic (or bin), color step, then a preview or a full-size half-float render.
            for (variant, binned) in algorithms.map({ ($0.rawValue, false) }) + [("bin \(bin)x\(bin)", true)] {
                for target in ["preview", "full"] where !(binned && target == "full") {
                    var row = Row(label: "ours \(variant) → \(target)")
                    for _ in 0..<runs {
                        let start = ContinuousClock.now
                        let mosaic = try RawMosaic(url)
                        let run = try demosaicer.run(mosaic, algorithm: DemosaicAlgorithm(rawValue: variant) ?? .bilinear, bin: binned ? bin : 1)
                        let step = CameraColorStep(color: mosaic.color, channelScale: mosaic.channelScale)
                        var picture = step.apply(to: image(run.output, flip: mosaic.flip), temperature: nil, tint: nil)
                        if target == "preview" { picture = scaled(picture, longEdge: previewEdge) }
                        let renderMs = render(picture, context: context, eightBit: target == "preview")
                        var parts = ["open+unpack": mosaic.openMs + mosaic.unpackMs, "copy": mosaic.copyMs, "upload": run.uploadMs,
                                     "gpu": run.gpuMs, "color+render": renderMs]
                        for (k, v) in run.passMs { parts["gpu:" + k] = v }
                        row.add((ContinuousClock.now - start).milliseconds, parts)
                    }
                    print(row.line)
                }
            }
            // LibRaw's whole decode as the app's fallback does it, then the same color step.
            for (label, half) in [("LibRaw decode (app fallback) → preview", true), ("LibRaw decode full → full", false)] {
                var row = Row(label: label)
                for _ in 0..<min(runs, 3) {
                    let start = ContinuousClock.now
                    let output = half ? try LibRawDecoder.decode(url, longEdge: previewEdge) : try LibRawDecoder.decode(url)
                    let decodeMs = (ContinuousClock.now - start).milliseconds
                    var picture = output.image()
                    if half { picture = scaled(picture, longEdge: previewEdge) }
                    let renderMs = render(picture, context: appContext, eightBit: half)
                    row.add((ContinuousClock.now - start).milliseconds, ["decode": decodeMs, "render": renderMs])
                }
                print(row.line)
            }
            // The system decoder through the app's preview generator, unedited.
            if PreviewGenerator.systemRAWImage(url) != nil {
                let generator = PreviewGenerator()
                for (label, edge) in [("system decoder → preview", previewEdge as Int?), ("system decoder full → full", nil)] {
                    var row = Row(label: label)
                    for _ in 0..<runs {
                        let start = ContinuousClock.now
                        let picture = try generator.image(source: url, stack: .identity, longEdge: edge)
                        let renderMs = render(edge.map { scaled(picture, longEdge: $0) } ?? picture, context: appContext, eightBit: edge != nil)
                        row.add((ContinuousClock.now - start).milliseconds, ["render": renderMs])
                    }
                    print(row.line)
                }
            } else {
                print("  system decoder: no image for this file")
            }
        }
        return [:]
    }

    // MARK: Budget and the live path

    /// The live path: a kept decode re-rendered for each slider move.
    /// Ours keeps the demosaiced texture (white balance included: it is in the
    /// color step); the app keeps the system decoder's decode in a
    /// `LiveRenderSession` and decodes again when white balance changes.
    static func budget(_ arguments: Arguments, files: [URL]) async throws -> [String: any Sendable] {
        let frames = arguments.int("frames", default: 20)
        let demosaicer = try MetalDemosaicer()
        let context = CIContext(mtlCommandQueue: demosaicer.queue,
                                options: [.workingColorSpace: Measure.working, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
        for url in files {
            let mosaic = try RawMosaic(url)
            let run = try demosaicer.run(mosaic, algorithm: mosaic.isXTrans ? .bilinear : .ha)
            let kept = image(run.output, flip: mosaic.flip)
            let step = CameraColorStep(color: mosaic.color, channelScale: mosaic.channelScale)
            let asShot = step.asShot?.kelvin ?? 5000
            print("\n\(url.lastPathComponent): live frames at \(previewEdge) px, \(frames) frames each, median (min–max) ms")
            func report(_ label: String, _ samples: [Double]) {
                print(String(format: "  %-58@ %6.1f (%.1f–%.1f)", label as NSString, LibRawStages.median(samples), samples.min()!, samples.max()!))
            }
            var exposure: [Double] = [], balance: [Double] = []
            for frame in 0..<frames {
                var transform = step.transform(temperature: nil, tint: nil)
                transform.exposure *= pow(2, Double(frame) * 0.02)
                exposure.append(render(scaled(transform.apply(to: kept), longEdge: previewEdge), context: context, eightBit: true))
                let picture = step.apply(to: kept, temperature: asShot - 1000 + Double(frame) * 100, tint: Double(frame))
                balance.append(render(scaled(picture, longEdge: previewEdge), context: context, eightBit: true))
            }
            report("ours, kept full demosaic: exposure (color step) per frame", exposure)
            report("ours, kept full demosaic: white balance per frame", balance)
            // The same with the demosaic downscaled once to the preview and kept at that size.
            let small = Measure.context().createCGImage(scaled(kept, longEdge: previewEdge), from: scaled(kept, longEdge: previewEdge).extent,
                                                         format: .RGBAh, colorSpace: Measure.working).map { CIImage(cgImage: $0) }
            if let small {
                var smallBalance: [Double] = []
                for frame in 0..<frames {
                    smallBalance.append(render(step.apply(to: small, temperature: asShot - 1000 + Double(frame) * 100, tint: 0), context: context, eightBit: true))
                }
                report("ours, kept preview-size demosaic: white balance per frame", smallBalance)
            }
            // The app today: a live session over the file (system decoder, or LibRaw for files it cannot read).
            let generator = PreviewGenerator().withEngine(.interactive())
            let session = LiveRenderSession(source: url, generator: generator, colorSpace: nil)
            var values = Adjustments()
            var first: [Double] = [], next: [Double] = [], wb: [Double] = []
            first.append(try await measure { _ = try await session.render(values) }.1.milliseconds)
            for frame in 0..<frames {
                values.exposure.ev = Double(frame) * 0.02
                next.append(try await measure { _ = try await session.render(values, interactive: true) }.1.milliseconds)
            }
            for frame in 0..<min(frames, 6) {
                values.whiteBalance = WhiteBalance(preset: .custom, temperature: 4000 + Double(frame) * 300, tint: 0)
                wb.append(try await measure { _ = try await session.render(values, interactive: true) }.1.milliseconds)
            }
            report("app LiveRenderSession: first frame", first)
            report("app LiveRenderSession: exposure per frame", next)
            report("app LiveRenderSession: white balance per frame", wb)
        }
        return [:]
    }
}
