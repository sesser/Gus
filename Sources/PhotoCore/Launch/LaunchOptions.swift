import Foundation

/// Command-line switches, used for development and profiling. The standalone
/// importer reads `--debug-script` only.
///
///     --library-root <folder>          keep catalog and previews in <folder> instead
///                                      of the standard per-user locations
///     --benchmark-scroll <report.json> scroll the grid at fixed speeds, write frame
///                                      statistics to the file, then quit
///     --debug-script "<commands>"      drive the UI for development checks (DebugScript)
///     --demosaic libraw                demosaic every raw LibRaw decodes with LibRaw's
///                                      own demosaic instead of ours (for comparing;
///                                      `RAW_DEMOSAIC=libraw` in the environment does
///                                      the same for every tool)
///     --gain-map-hdr on                temporary (#282, first stage): show and edit every
///                                      gain-map photo in HDR; honored only by a test
///                                      launch (`TemporaryGainMapHDR`)
///
/// The library app refuses to start without `--library-root` when it is a
/// test launch: a bundle identifier other than the release one, or
/// `--debug-script` or `--benchmark-scroll` passed (`LibraryLaunchGuard`).
///
/// Every switch takes exactly one value. AppKit reads launch arguments as
/// "-key value" pairs and treats any leftover argument as a document to open,
/// which suppresses the main window.
public struct LaunchOptions: Sendable {
    public var libraryRoot: URL?
    public var benchmarkReport: URL?
    public var debugScript: String?
    /// `LibRawDecoder.DemosaicChoice`'s raw value.
    public var demosaic: String?
    /// Temporary, #282's first stage (`TemporaryGainMapHDR`): remove with it.
    public var gainMapHDR: String?

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
            case "--demosaic":
                demosaic = iterator.next()
            case "--gain-map-hdr":
                gainMapHDR = iterator.next()
            default:
                break
            }
        }
    }
}
