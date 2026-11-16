import Foundation
import PhotoCore

// SPIKE for issue #194: throwaway, not part of the app. Our own raw pipeline:
// LibRaw's unpack, our Metal demosaic, our color step, lensfun's published
// lens models. See docs/features/decode-pipeline-spike/spike.md for what it
// measured and how, and status.md for what to keep.
//
// `photobench decodespike --mode <mode> --files a.RW2:b.ORF [...]`
//
// Modes: stages, bands, verify, quality, real, timing, lens, color, budget.
// Nothing is written unless --output names a folder (outside the repository).
enum DecodeSpike {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let files = (arguments.values["files"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: (String($0) as NSString).expandingTildeInPath) }
        setvbuf(stdout, nil, _IOLBF, 0)
        print("machine: \(machineDescription())")
        switch arguments.values["mode"] {
        case "stages": return try LibRawStages.run(arguments, files: files)
        case "bands": return try LibRawStages.bands(arguments, files: files)
        case "verify": return try DemosaicVerify.run(arguments, files: files)
        case "quality": return try DemosaicQuality.synthetic(arguments, files: files)
        case "real": return try DemosaicQuality.real(arguments, files: files)
        case "timing": return try HybridTiming.run(arguments, files: files)
        case "lens": return try LensSpike.run(arguments, files: files)
        case "color": return try ColorSpike.run(arguments)
        case "budget": return try await HybridTiming.budget(arguments, files: files)
        default: throw BenchError("decodespike needs --mode stages|bands|verify|quality|real|timing|lens|color|budget")
        }
    }

    static func output(_ arguments: Arguments) throws -> URL? {
        guard let path = arguments.values["output"] else { return nil }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
