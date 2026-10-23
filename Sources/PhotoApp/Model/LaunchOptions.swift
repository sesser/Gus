import Foundation

/// Command-line switches, used for development and profiling.
///
///     --library-root <folder>          keep catalog and previews in <folder> instead
///                                      of the standard per-user locations
///     --benchmark-scroll <report.json> scroll the grid at fixed speeds, write frame
///                                      statistics to the file, then quit
///     --debug-script "<commands>"      drive the UI for development checks (DebugScript)
///
/// Every switch takes exactly one value. AppKit reads launch arguments as
/// "-key value" pairs and treats any leftover argument as a document to open,
/// which suppresses the main window.
struct LaunchOptions {
    var libraryRoot: URL?
    var benchmarkReport: URL?
    var debugScript: String?

    var benchmarkScroll: Bool { benchmarkReport != nil }

    static let current = LaunchOptions(arguments: CommandLine.arguments)

    init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--library-root":
                libraryRoot = iterator.next().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            case "--benchmark-scroll":
                benchmarkReport = iterator.next().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            case "--debug-script":
                debugScript = iterator.next()
            default:
                break
            }
        }
    }
}
