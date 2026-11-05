import Foundation
import PhotoCore
import PhotoFixtures

/// Machine learning noise reduction against the classical decoder (ml-denoise
/// PRD R14): one raw rendered with the setting off and on at the three
/// outputs a person waits on, through the calls the app makes: the grid's
/// thumbnail and the loupe's 2560 px preview (`PreviewGenerator.jpegData`,
/// the disk cache's encode included) and a full-resolution JPEG export
/// (`ExportRenderer.export`, written to a temporary folder).
///
/// The first run of each case is reported apart: it includes loading the
/// decoder's model. The source is a synthetic 24-megapixel DNG with noise
/// unless `--source` names a raw.
enum DenoiseBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let runs = max(1, arguments.int("runs", default: 5))
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "photobench-denoise-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source: URL
        if arguments.values["source"] != nil {
            source = try arguments.url("source")
        } else {
            let (width, height) = arguments.size("size", default: (6000, 4000))
            source = folder.appending(path: "noisy-\(width)x\(height).dng")
            try SyntheticDNG.write(to: source, options: .init(width: width, height: height, seed: 11, noise: 0.02,
                                                              writesNoiseProfile: true, iso: 6400))
        }
        let availability = MachineLearningNoiseReduction.availability(for: source)
        let size = PreviewGenerator.nativeSize(source) ?? .zero
        print("Source: \(source.lastPathComponent), \(Int(size.width)) × \(Int(size.height)), \(runs) runs")
        print("Machine learning noise reduction: \(availability.rawValue)")

        let generator = PreviewGenerator()
        let exporter = ExportRenderer(generator: generator)
        var report: [String: any Sendable] = [
            "machine": machineDescription(), "source": source.lastPathComponent, "width": Int(size.width),
            "height": Int(size.height), "runs": runs, "availability": availability.rawValue,
        ]
        for machineLearning in [false, true] {
            var adjustments = Adjustments()
            adjustments.noiseReduction = NoiseReduction(luminance: 50, color: 50, machineLearning: machineLearning)
            let stack = adjustments.editStack
            let mode = machineLearning ? "on" : "off"
            print("\nMachine learning \(mode)")
            let outputs: [(String, () throws -> MachineLearningNoiseReduction.Outcome)] = [
                ("thumbnail", {
                    try generator.encodedRendering(source: source, stack: stack, tiers: [.thumbnail]).machineLearning
                }),
                ("preview", {
                    try generator.encodedRendering(source: source, stack: stack, tiers: [.preview]).machineLearning
                }),
                ("export", {
                    try exporter.export(source: source, stack: stack, values: SidecarValues(), settings: ExportSettings(),
                                        to: folder.appending(path: "export-\(mode).jpg"), replacing: true)
                }),
            ]
            for (name, render) in outputs {
                var times: [Double] = []
                var outcome = MachineLearningNoiseReduction.Outcome.notRequested
                for _ in 0..<(runs + 1) {
                    let (result, duration) = try await measure { try render() }
                    outcome = result
                    times.append(duration.seconds)
                }
                let first = times.removeFirst()
                let stats = Stats(times.map { $0 * 1000 })
                let applied = outcome == .notRequested ? "" : (outcome.isApplied ? ", applied" : ", NOT applied")
                print("  \(name.padding(toLength: 10, withPad: " ", startingAt: 0)) first "
                      + String(format: "%.2f s, then median %.2f s (max %.2f s)", first, stats.percentile(0.5) / 1000,
                               stats.max / 1000) + applied)
                let entry: [String: any Sendable] = ["firstSeconds": first, "medianSeconds": stats.percentile(0.5) / 1000,
                                                     "maxSeconds": stats.max / 1000, "applied": outcome.isApplied]
                report["\(mode).\(name)"] = entry
            }
        }
        return report
    }
}
