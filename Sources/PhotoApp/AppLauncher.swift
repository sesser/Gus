import AppKit
import PhotoCore

/// The library app's entry point. Checks `LibraryLaunchGuard` before the
/// SwiftUI app exists: `PhotoApplication`'s `LibraryLoader` opens the catalog
/// (and migrates and creates the standard folders) as soon as SwiftUI builds
/// it, so a refused launch must never reach `PhotoApplication.main()`.
@main
enum AppLauncher {
    @MainActor static func main() {
        if case .refused(let reason) = LibraryLaunchGuard.current() {
            refuse(reason)
        }
        PhotoApplication.main()
    }

    /// Says on standard error and in an alert that `--library-root` is
    /// required, then quits. Nothing under the standard library has been
    /// touched at this point.
    @MainActor private static func refuse(_ reason: LibraryLaunchGuard.Reason) -> Never {
        FileHandle.standardError.write(Data((LibraryLaunchGuard.diagnostic(for: reason) + "\n").utf8))
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Can't Open the Library", comment: "Catalog failure view title")
        alert.informativeText = String(
            localized: "Test copies of \(AppBranding.displayName), and launches with --debug-script or --benchmark-scroll, must be started with --library-root <folder>. Nothing was opened.",
            comment: "Alert when a test launch has no --library-root; the app quits after it")
        alert.addButton(withTitle: String(localized: "Quit", comment: "Button of the alert when a test launch has no --library-root"))
        alert.runModal()
        exit(EX_USAGE)
    }
}
