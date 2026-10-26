import Foundation
import PhotoCore

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

    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let library = try BenchLibrary(arguments)
        let limit = arguments.int("limit", default: 12)
        let frames = arguments.int("frames", default: 20)
        let generator = PreviewGenerator()
        let items = try await library.itemsWithSources().compactMap { item, url in url.map { (item, $0) } }
            .filter { !$0.0.isVideo }
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
            for url in urls {
                identity.append(try await measure { _ = try generator.jpegData(source: url, stack: .identity, tier: .preview) }.1.milliseconds)
                edited.append(try await measure { _ = try generator.jpegData(source: url, stack: stack, tier: .preview) }.1.milliseconds)

                let session = LiveRenderSession(source: url, generator: generator, colorSpace: nil)
                var values = typical
                firstFrame.append(try await measure { _ = try await session.render(values) }.1.milliseconds)
                for frame in 0..<frames {
                    values.exposure.ev = 0.4 + Double(frame) * 0.02
                    nextFrames.append(try await measure { _ = try await session.render(values, interactive: true) }.1.milliseconds)
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
                                   ("live white balance", decodeChanges)] where !values.isEmpty {
                let stats = Stats(values)
                print("  \(name.padding(toLength: 19, withPad: " ", startingAt: 0)) \(stats.line)")
                entry[name] = stats.dictionary
            }
            results[format] = entry
        }
        return ["machine": machineDescription(), "formats": results]
    }
}
