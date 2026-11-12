import CoreGraphics
import Foundation
import PhotoCore
import PhotoFixtures

/// Side by side comparison at 100% (docs/features/side-by-side-comparison):
/// what the two panes wait for and hold. Each pane shows the saved edit's
/// full-resolution render, made off the main thread by the preview service
/// one after the other (its full-resolution lane takes one job at a time),
/// and keeps that image while it shows the photo. Panning afterwards moves
/// two layers and renders nothing; `compare panbench` in the app's debug
/// script measures that.
enum ComparisonBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let (width, height) = arguments.size("size", default: (6000, 4000))
        let runs = arguments.int("runs", default: 5)
        let folder = FileManager.default.temporaryDirectory.appending(path: "compare-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // `--sources a.RW2:b.RW2`: two real raws instead of the synthetic ones.
        var sources: [URL] = (arguments.values["sources"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: (String($0) as NSString).expandingTildeInPath) }
        if sources.count == 2 {
            print("Sources: \(sources.map(\.lastPathComponent).joined(separator: " and ")), \(runs) runs per case.")
        } else {
            sources = try (0..<2).map { index in
                let url = folder.appending(path: "bench-\(index).dng")
                try SyntheticDNG.write(to: url, options: .init(width: width, height: height, seed: UInt64(11 + index)))
                return url
            }
            print("Sources: two synthetic DNGs \(width) × \(height), \(runs) runs per case.")
        }
        let generator = PreviewGenerator().withEngine(.interactive())
        var report: [String: any Sendable] = ["machine": machineDescription(), "runs": runs]

        let cases: [(String, EditStack)] = [("no adjustments", .identity), ("typical stack", EditBenchmark.typical.editStack)]
        for (name, stack) in cases {
            print("\n\(name):")
            var first: [Double] = [], second: [Double] = [], both: [Double] = []
            var bytes: [Int64] = []
            var pixels: [String] = []
            // The process's footprint before, with one render held, and with both.
            var footprints: [[Int64]] = []
            for _ in 0..<runs {
                let before = MaskBenchmark.footprint()
                let (left, leftTime) = try await measure { () -> CGImage in
                    let image = try generator.cgImage(source: sources[0], stack: stack)
                    ViewportBenchmark.touch(image)
                    return image
                }
                let withOne = MaskBenchmark.footprint()
                let (right, rightTime) = try await measure { () -> CGImage in
                    let image = try generator.cgImage(source: sources[1], stack: stack)
                    ViewportBenchmark.touch(image)
                    return image
                }
                first.append(leftTime.milliseconds)
                second.append(rightTime.milliseconds)
                both.append(leftTime.milliseconds + rightTime.milliseconds)
                bytes = [left, right].map { Int64($0.bytesPerRow * $0.height) }
                pixels = [left, right].map { "\($0.width) × \($0.height)" }
                // Both held, as the two panes hold them.
                footprints.append([before, withOne, MaskBenchmark.footprint()])
            }
            print("  first photo sharp         \(Stats(first).line)")
            print("  second photo sharp, after \(Stats(second).line)")
            print("  both sharp                \(Stats(both).line)")
            print("  held: \(pixels.joined(separator: " and ")), \(bytes.map(formatBytes).joined(separator: " + ")) = "
                  + "\(formatBytes(bytes.reduce(0, +)))")
            // The renderer's own working memory is in these too, as in the single loupe's 100%.
            for (index, run) in footprints.enumerated() {
                print("  footprint, run \(index + 1): \(formatBytes(run[0])) before, \(formatBytes(run[1])) with one, "
                      + "\(formatBytes(run[2])) with both")
            }
            report[name] = [
                "first_ms": Stats(first).dictionary, "second_ms": Stats(second).dictionary, "both_ms": Stats(both).dictionary,
                "held_bytes": bytes.reduce(0, +), "footprint_before_one_both": footprints,
            ] as [String: any Sendable]
        }

        print("\nWhat two full-resolution renders hold, by size (8-bit BGRA, 4 bytes a pixel; an HDR render is 8):")
        var table: [String: any Sendable] = [:]
        for megapixels in [12, 20, 24, 45, 61, 100] {
            let one = Int64(megapixels) * 1_000_000 * 4
            print("  \(String(megapixels).padding(toLength: 4, withPad: " ", startingAt: 0)) MP  \(formatBytes(one * 2)) for two"
                  + " (\(formatBytes(one * 4)) for two in HDR)")
            table["\(megapixels)"] = one * 2
        }
        report["two_images_bytes_by_megapixels"] = table
        return report
    }
}
