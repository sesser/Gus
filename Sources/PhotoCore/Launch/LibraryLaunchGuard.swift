import Foundation

/// Decides whether a launch of the library app may open the standard library
/// (the per-user catalog and preview cache in `LibraryLocations.standard`).
///
/// The bundle identifier only separates preferences; the standard library
/// lives at a fixed path. So a test launch must name its own library with
/// `--library-root`, or it opens the owner's. A launch is a test launch when
/// either
/// - the running bundle's identifier is not the release identifier (a test
///   copy such as `<release id>.debugtest`, or no bundle at all, as with
///   `swift run`), or
/// - it was started with `--debug-script` or `--benchmark-scroll`.
///
/// A test launch without `--library-root` is refused: the app says so and
/// quits before anything under the standard library is resolved, opened or
/// created. It always says so on standard error; it also shows an alert,
/// except in a scripted launch (`--debug-script` or `--benchmark-scroll`),
/// which nobody may be watching and which an alert would keep from ending
/// (owner's ruling, 2026-11-07). Every launch with `--library-root` is
/// allowed.
public enum LibraryLaunchGuard {
    public enum Decision: Equatable, Sendable {
        case allowed
        /// `showsAlert` is false for scripted launches: standard error only.
        case refused(Reason, showsAlert: Bool)
    }

    /// Why a launch counts as a test launch. When both apply, the bundle
    /// identifier is reported.
    public enum Reason: Equatable, Sendable {
        /// The running bundle's identifier (nil: not run from a bundle) is not
        /// the release identifier.
        case notReleaseBundle(identifier: String?)
        /// `--debug-script` or `--benchmark-scroll` was passed.
        case scriptedLaunch
    }

    public static func decide(bundleIdentifier: String?,
                              releaseIdentifier: String = AppBranding.bundleIdentifier,
                              options: LaunchOptions) -> Decision {
        guard options.libraryRoot == nil else { return .allowed }
        let scripted = options.debugScript != nil || options.benchmarkScroll
        if bundleIdentifier != releaseIdentifier {
            return .refused(.notReleaseBundle(identifier: bundleIdentifier), showsAlert: !scripted)
        }
        if scripted {
            return .refused(.scriptedLaunch, showsAlert: false)
        }
        return .allowed
    }

    /// The running process's decision.
    public static func current(bundle: Bundle = .main, options: LaunchOptions = .current) -> Decision {
        decide(bundleIdentifier: bundle.bundleIdentifier, options: options)
    }

    /// A one-line explanation for standard error. Not localized: it is for
    /// whoever started the process from a shell or script.
    public static func diagnostic(for reason: Reason) -> String {
        let cause = switch reason {
        case .notReleaseBundle(let identifier?):
            "bundle identifier \(identifier) is not the release identifier \(AppBranding.bundleIdentifier)"
        case .notReleaseBundle(nil):
            "not running from a bundle with the release identifier \(AppBranding.bundleIdentifier)"
        case .scriptedLaunch:
            "--debug-script or --benchmark-scroll was passed"
        }
        return "Refusing to open the standard library: \(cause). "
            + "Test launches must pass --library-root <folder>. Nothing was opened; quitting."
    }
}
