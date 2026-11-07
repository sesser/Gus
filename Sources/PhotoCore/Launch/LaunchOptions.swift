import Foundation

/// Command-line switches, used for development and profiling. The standalone
/// importer reads `--debug-script` only.
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
public struct LaunchOptions: Sendable {
    public var libraryRoot: URL?
    public var benchmarkReport: URL?
    public var debugScript: String?

    public var benchmarkScroll: Bool { benchmarkReport != nil }

    public static let current = LaunchOptions(arguments: CommandLine.arguments)

    public init(arguments: [String]) {
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
