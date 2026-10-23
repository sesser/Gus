import Foundation

/// Command-line switches, used for development and profiling.
///
///     --library-root <folder>     keep catalog and previews in <folder> instead of
///                                 the standard per-user locations
///     --benchmark-scroll          scroll the grid at fixed speeds, write frame
///                                 statistics, then quit
///     --benchmark-output <file>   where the benchmark writes its JSON report
///     --debug-script "<commands>" drive the UI for development checks (DebugScript)
struct LaunchOptions {
    var libraryRoot: URL?
    var benchmarkScroll = false
    var benchmarkOutput: URL?
    var debugScript: String?

    static let current = LaunchOptions(arguments: CommandLine.arguments)

    init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--library-root":
                libraryRoot = iterator.next().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            case "--benchmark-scroll":
                benchmarkScroll = true
            case "--debug-script":
                debugScript = iterator.next()
            case "--benchmark-output":
                benchmarkOutput = iterator.next().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            default:
                break
            }
        }
    }
}
