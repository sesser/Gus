import Foundation
import PhotoCore
import Synchronization

/// Rendering with adjustments: cached tiers with a typical stack against the
/// identity stack, and the loupe's live frames.
enum EditBenchmark {
    /// Exposure, tone, presence, a curve, grading and sharpening: most of the graph.
    static var typical: Adjustments {
        var adjustments = Adjustments()
        adjustments.exposure.ev = 0.4
        adjustments.tone = Tone(contrast: 15, highlights: -30, shadows: 25, whites: 10, blacks: -5)
        adjustments.presence = Presence(clarity: 20, dehaze: 10, vibrance: 15, saturation: 5)
        adjustments.toneCurve[.rgb] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.3, y: 0.25), CurvePoint(x: 0.7, y: 0.78),
                                       CurvePoint(x: 1, y: 1)]
        adjustments.colorGrade.shadows = GradeWheel(hue: 210, amount: 20)
        adjustments.colorGrade.highlights = GradeWheel(hue: 40, amount: 15)
        adjustments.sharpen = Sharpen(amount: 40, radius: 1, detail: 25, masking: 20)
        return adjustments
    }

    /// One pointer move of the pixel magnifier.
    private static func magnifierUpdate(_ tool: FringeMagnifierTool, at unit: CGPoint, level: PixelMagnifierLevel) {
        guard let reading = PixelMagnifier.reading(tool: tool, atOutput: unit, devicePixelsAcross: 2560) else { return }
        let picture = PixelMagnifier.picture(image: tool.image, center: reading.pixel, level: level, deviceSize: 256)
        _ = picture.bitmap(surround: (24, 24, 24))
    }

    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let library = try BenchLibrary(arguments)
        let limit = arguments.int("limit", default: 12)
        let frames = arguments.int("frames", default: 20)
        let generator = PreviewGenerator()
        // Live frames render on their own contexts, as in the app (`PreviewService.interactiveGenerator`).
        let interactive = generator.withEngine(.interactive())
        let items = try await library.itemsWithSources().compactMap { item, url in url.map { (item, $0) } }
            .filter { !$0.0.isVideo }
        // Live frames while previews are generated in the background, as after an import.
        let loadJobs = arguments.values["under-load"].flatMap(Int.init)
            ?? (arguments.flags.contains("under-load") ? PreviewService.defaultGenerateConcurrency : nil)
        let load = loadJobs.map { BackgroundLoad.start(jobs: $0, sources: items.map(\.1), generator: generator) }
        defer { load?.cancel() }
        if let loadJobs { print("Under load: \(loadJobs) preview renders running in the background") }
        var byFormat: [String: [URL]] = [:]
        for (item, url) in items {
            let format = (item.relativePath as NSString).pathExtension.lowercased()
            if byFormat[format, default: []].count < limit { byFormat[format, default: []].append(url) }
        }
        let stack = typical.editStack
        var results: [String: any Sendable] = [:]
        for (format, urls) in byFormat.sorted(by: { $0.key < $1.key }) {
            print("\(format.uppercased()): \(urls.count) files")
            var identity: [Double] = []
            var edited: [Double] = []
            var firstFrame: [Double] = []
            var nextFrames: [Double] = []
            var decodeChanges: [Double] = []
            // The Lens heading's controls next to a color slider (chromatic-aberration R18, AC15).
            var saturation: [Double] = []
            var fringeTolerance: [Double] = []
            var fringeMap: [Double] = []
            var alignment: [Double] = []
            // The pixel magnifier (chromatic-aberration R36, AC31).
            var magnifierFirstPixels: [Double] = []
            var magnifierUpdate: [Double] = []
            var magnifierUpdate100: [Double] = []
            var magnifierUpdateCropped: [Double] = []
            var magnifierHeldMB: [Double] = []
            var saturationWithMagnifier: [Double] = []
            for url in urls where load == nil {
                identity.append(try await measure { _ = try generator.jpegData(source: url, stack: .identity, tier: .preview) }.1.milliseconds)
                edited.append(try await measure { _ = try generator.jpegData(source: url, stack: stack, tier: .preview) }.1.milliseconds)
            }
            for url in urls {
                let session = LiveRenderSession(source: url, generator: interactive, colorSpace: nil)
                var values = typical
                firstFrame.append(try await measure { _ = try await session.render(values) }.1.milliseconds)
                for frame in 0..<frames {
                    values.exposure.ev = 0.4 + Double(frame) * 0.02
                    nextFrames.append(try await measure { _ = try await session.render(values, interactive: true) }.1.milliseconds)
                }
                for frame in 0..<frames {
                    values.presence.saturation = 5 + Double(frame)
                    saturation.append(try await measure { _ = try await session.render(values, interactive: true) }.1.milliseconds)
                }
                values.colorFringes = ColorFringes(slot1: CommonFringeColor.purple.slot, slot2: CommonFringeColor.green.slot)
                for frame in 0..<frames {
                    values.colorFringes.slot1?.tolerance = 25 + Double(frame)
                    fringeTolerance.append(try await measure { _ = try await session.render(values, interactive: true) }.1.milliseconds)
                }
                for frame in 0..<frames {
                    values.colorFringes.slot1?.tolerance = 25 + Double(frame)
                    fringeMap.append(try await measure {
                        _ = try await session.render(values, interactive: true, content: .fringeMap)
                    }.1.milliseconds)
                }
                for frame in 0..<frames {
                    values.colorAlignment = ColorAlignment(red: 5 + Double(frame), blue: -5)
                    alignment.append(try await measure { _ = try await session.render(values, interactive: true) }.1.milliseconds)
                }
                values = typical
                // Arming: the held pixels, on a context of their own as in the app.
                let magnifierGenerator = generator.withEngine(RenderEngine(contextCount: 1, name: "pixel-magnifier"))
                var held: FringeSamplePixels?
                magnifierFirstPixels.append(try await measure {
                    held = try FringePicker.samplePixels(source: url, values: values, generator: magnifierGenerator)
                }.1.milliseconds)
                if let pixels = held {
                    magnifierHeldMB.append(Double(pixels.byteCount) / 1_048_576)
                    let tool = FringeMagnifierTool(pixels: pixels, crop: Crop())
                    let croppedTool = FringeMagnifierTool(pixels: pixels, crop: Crop(rect: CropRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), angle: 3))
                    for frame in 0..<frames {
                        let unit = CGPoint(x: 0.3 + Double(frame) * 0.01, y: 0.4)
                        magnifierUpdate.append(await measure {
                            Self.magnifierUpdate(tool, at: unit, level: .standard)
                        }.1.milliseconds)
                        // The largest picture the magnifier draws, and the costliest cells (a straightened crop).
                        magnifierUpdate100.append(await measure {
                            Self.magnifierUpdate(tool, at: unit, level: .percent100)
                        }.1.milliseconds)
                        magnifierUpdateCropped.append(await measure {
                            Self.magnifierUpdate(croppedTool, at: unit, level: .percent100)
                        }.1.milliseconds)
                    }
                    for frame in 0..<frames {
                        values.presence.saturation = 25 + Double(frame)
                        saturationWithMagnifier.append(try await measure {
                            _ = try await session.render(values, interactive: true)
                        }.1.milliseconds)
                    }
                    values = typical
                }
                if SupportedFormats.isRaw(pathExtension: url.pathExtension) {
                    for frame in 0..<4 {
                        values.whiteBalance = WhiteBalance(preset: .custom, temperature: 4000 + Double(frame) * 500, tint: 0)
                        decodeChanges.append(try await measure { _ = try await session.render(values, interactive: true) }.1.milliseconds)
                    }
                }
            }
            var entry: [String: any Sendable] = [:]
            for (name, values) in [("preview identity", identity), ("preview edited", edited),
                                   ("live first frame", firstFrame), ("live next frame", nextFrames),
                                   ("live white balance", decodeChanges), ("live saturation", saturation),
                                   ("live fringe tolerance", fringeTolerance), ("live fringe map", fringeMap),
                                   ("live color alignment", alignment),
                                   ("magnifier first pixels", magnifierFirstPixels), ("magnifier update", magnifierUpdate),
                                   ("magnifier update 100%", magnifierUpdate100), ("magnifier 100%, cropped", magnifierUpdateCropped),
                                   ("magnifier held MB", magnifierHeldMB),
                                   ("saturation, magnifier held", saturationWithMagnifier)] where !values.isEmpty {
                let stats = Stats(values)
                print("  \(name.padding(toLength: 27, withPad: " ", startingAt: 0)) \(stats.line)")
                entry[name] = stats.dictionary
            }
            results[format] = entry
        }
        if let load { print("  background renders finished during the run: \(load.completed)") }
        return ["machine": machineDescription(), "under_load": loadJobs ?? 0, "formats": results]
    }
}

/// Renders previews of `sources` over and over, `jobs` at a time, until cancelled.
final class BackgroundLoad: Sendable {
    private let tasks: Mutex<[Task<Void, Never>]> = Mutex([])
    private let count = Mutex(0)

    var completed: Int { count.withLock { $0 } }

    static func start(jobs: Int, sources: [URL], generator: PreviewGenerator) -> BackgroundLoad {
        let load = BackgroundLoad()
        let tasks = (0..<jobs).map { job in
            Task.detached(priority: .utility) {
                var index = job
                while !Task.isCancelled, !sources.isEmpty {
                    let source = sources[index % sources.count]
                    _ = try? generator.jpegData(source: source, stack: .identity, tiers: [.preview, .thumbnail])
                    load.count.withLock { $0 += 1 }
                    index += jobs
                }
            }
        }
        load.tasks.withLock { $0 = tasks }
        return load
    }

    func cancel() {
        tasks.withLock { $0.forEach { $0.cancel() } }
    }
}
