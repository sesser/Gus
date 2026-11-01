import Foundation
import PhotoCore

// Synthetic library generator and headless profiling for the catalog, importer
// and preview pipeline. Every command prints a human-readable report; --json adds
// a machine-readable one.

let usage = """
    usage: photobench <command> [options]

      generate   --output DIR [--jpeg N] [--dng N] [--heic N] [--pairs N] [--videos N] [--per-folder N]
                 [--jpeg-size WxH] [--dng-size WxH] [--heic-size WxH] [--video-seconds N]
                 Writes a synthetic library with unique pixels and EXIF dates.

      import     --library-root ROOT --source DIR [--imageio] [--chunk N] [--hash-concurrency N]
                 Imports DIR into the catalog under ROOT and reports stage timings.

      previews   --library-root ROOT [--tier thumbnail|preview] [--concurrency N] [--limit N]
                 [--format EXT] [--fresh]
                 Generates cached renditions for every version and reports per-format timings.

      read-cache --library-root ROOT [--tier thumbnail|preview] [--pixel-size N] [--limit N]
                 Decodes cached renditions the way the grid does and reports latency.

      query      --library-root ROOT
                 Times library queries and culling writes.

      suggest    --library-root ROOT [--limit N]
                 Runs on-device keyword analysis and reports per-stage timings.

      sidecars   --library-root ROOT [--limit N]
                 Writes sidecars for N photos, checks the library for outside changes, cleans up.

      copy       --source DIR --dest DIR [--limit N]
                 Copies N shots with verification and compares with a plain copy.

      edits      --library-root ROOT [--limit N] [--frames N] [--under-load [N]]
                 Renders previews with a typical set of adjustments and times the loupe's live frames.
                 With --under-load, times only the live frames while N preview renders run
                 in the background (default: the preview service's generate concurrency).

      kernels    [--size WxH] [--sigma N] [--runs N]
                 Times the runtime-compiled kernel spike against the stock filters at preview
                 size (2560 px) and full size (default 6000x4000), first call and steady state.

      blend-error
                 For each local control: the largest difference between blending the adjusted
                 image by alpha and running the module at alpha times the value (test scenes).

      synthesize --library-root ROOT --count N
                 Grows the catalog to N versions by cloning existing rows with new content
                 hashes and hard-linking their cached thumbnails (grid-scale testing).

      --json FILE  also write the results as JSON
    """

struct Arguments {
    var command: String
    var values: [String: String] = [:]
    var flags: Set<String> = []

    init(_ arguments: [String]) {
        command = arguments.first ?? "help"
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let name = String(argument.dropFirst(2))
                if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                    values[name] = arguments[index + 1]
                    index += 2
                    continue
                }
                flags.insert(name)
            }
            index += 1
        }
    }

    func url(_ name: String) throws -> URL {
        guard let value = values[name] else { throw BenchError("missing --\(name)") }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
    }

    func int(_ name: String, default fallback: Int) -> Int {
        values[name].flatMap(Int.init) ?? fallback
    }

    func size(_ name: String, default fallback: (Int, Int)) -> (Int, Int) {
        guard let value = values[name] else { return fallback }
        let parts = value.split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : fallback
    }
}

struct BenchError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
do {
    let report: [String: any Sendable]
    switch arguments.command {
    case "generate": report = try await Generate.run(arguments)
    case "import": report = try await ImportBenchmark.run(arguments)
    case "previews": report = try await PreviewBenchmark.generate(arguments)
    case "read-cache": report = try await PreviewBenchmark.readCache(arguments)
    case "query": report = try await QueryBenchmark.run(arguments)
    case "synthesize": report = try await Synthesize.run(arguments)
    case "suggest": report = try await SuggestionBenchmark.run(arguments)
    case "sidecars": report = try await SidecarBenchmark.run(arguments)
    case "copy": report = try await CopyBenchmark.run(arguments)
    case "edits": report = try await EditBenchmark.run(arguments)
    case "kernels": report = try await KernelBenchmark.run(arguments)
    case "blend-error": report = try await BlendErrorReport.run(arguments)
    default:
        print(usage)
        exit(arguments.command == "help" || arguments.flags.contains("help") ? 0 : 64)
    }
    if let path = arguments.values["json"] {
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
    }
} catch {
    FileHandle.standardError.write(Data("photobench: \(error)\n".utf8))
    exit(1)
}
