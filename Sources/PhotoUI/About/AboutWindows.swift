import AppKit
import PhotoCore
import SwiftUI

/// Scene ids of the About window and its license windows.
enum AboutWindowID {
    static let about = "about"
    static let license = "license"
}

/// Layout constants of the About and license windows (design §3, §6).
enum AboutMetrics {
    static let width: CGFloat = 520
    static let idealHeight: CGFloat = 640
    static let minHeight: CGFloat = 400
    static let iconSize: CGFloat = 64
    /// Under the title bar, which the content does not go behind.
    static let headerTop: CGFloat = 4
    static let iconToName: CGFloat = 8
    static let nameToVersion: CGFloat = 2
    static let headerBottom: CGFloat = 16
    static let bodySide: CGFloat = 20
    static let bodyVertical: CGFloat = 16
    static let dedicationToEntries: CGFloat = 12
    static let entrySpacing: CGFloat = 14
    static let entryLineSpacing: CGFloat = 3
    static let entriesToDivider: CGFloat = 20
    static let dividerToFooter: CGFloat = 16
    static let copyrightToStatement: CGFloat = 4
    static let statementToButton: CGFloat = 8

    static let licenseDefaultSize = CGSize(width: 640, height: 720)
    static let licenseMinSize = CGSize(width: 420, height: 320)
    static let licenseTextInset: CGFloat = 16
    static let licenseFontSize: CGFloat = 12
}

/// What this process's bundle gives the About window.
extension AboutContent {
    /// Read now: the Info.plist's version and the license files in the
    /// bundle's resources. A bare executable (`swift run`) has neither.
    static var current: AboutContent {
        AboutContent(infoDictionary: Bundle.main.infoDictionary, licenses: .main)
    }

    /// The same without looking for the license files: what the window
    /// holds before it has appeared, so building the view reads no file.
    static var beforeAppearing: AboutContent {
        AboutContent(infoDictionary: Bundle.main.infoDictionary, licenses: BundledLicenses(directory: nil))
    }
}

extension BundledLicenses {
    static var main: BundledLicenses { BundledLicenses(directory: Bundle.main.resourceURL) }
}

/// The AppKit side of the About and license windows: which `NSWindow`s
/// they are (so Esc can close About, the Window menu can leave it out, and
/// the debug scripts can tell these windows from the app's main one), and
/// what the open About window shows, for the scripts' `about print`.
@MainActor
public enum AboutWindowRegistry {
    private final class WeakWindow {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }

    static private(set) weak var aboutWindow: NSWindow?
    private static var licenseWindows: [LicenseDocument: WeakWindow] = [:]
    private static var escapeMonitor: Any?

    /// What the About window last showed, and the names it was filled with.
    static var shown: (content: AboutContent, appName: String, projectName: String)?
    /// Opens a license window as its View License button does; set while
    /// an About window has been shown (the scripts' `about license`).
    static var openLicense: ((LicenseDocument) -> Void)?

    /// True for the About window and the license windows.
    public static func owns(_ window: NSWindow) -> Bool {
        window === aboutWindow || licenseWindows.values.contains { $0.window === window }
    }

    static func licenseWindow(for document: LicenseDocument) -> NSWindow? {
        licenseWindows[document]?.window
    }

    static var openLicenseDocuments: [LicenseDocument] {
        licenseWindows.filter { $0.value.window?.isVisible == true }.map(\.key)
    }

    static func registerAbout(_ window: NSWindow?) {
        guard let window else { return }
        aboutWindow = window
        // Reached from the app and Help menus, like the system's panel; not
        // listed among the Window menu's windows.
        window.isExcludedFromWindowsMenu = true
        // It only grows downward, to its content's height: no zoom. SwiftUI
        // has a modifier for minimize and full screen, none for zoom.
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        if escapeMonitor == nil {
            // Esc closes About as it closes the system's panel, whatever
            // has the keyboard in it. A monitor rather than a cancel button:
            // nothing is added to the window or its accessibility tree. It
            // stays for the life of the app and only answers for this window.
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                closesAbout(event) ? nil : event
            }
        }
    }

    static func registerLicense(_ window: NSWindow?, for document: LicenseDocument) {
        guard let window else { return }
        licenseWindows = licenseWindows.filter { $0.value.window != nil }
        licenseWindows[document] = WeakWindow(window)
    }

    /// Closes the About window for an Esc typed in it; false for any other
    /// key, any other window, or while a sheet is on it.
    static func closesAbout(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard event.type == .keyDown, event.keyCode == escapeKeyCode, modifiers.isEmpty,
              let window = aboutWindow, event.window === window, window.isVisible, window.attachedSheet == nil
        else { return false }
        window.performClose(nil)
        return true
    }

    static let escapeKeyCode: UInt16 = 53
}

/// Links in the About window open in the default browser through the
/// system. Under a debug script they are reported instead, so a scripted
/// check never starts a browser.
@MainActor
enum AboutLinks {
    static var reportsOnly = LaunchOptions.current.debugScript != nil

    /// True when the system should open the page; under a debug script,
    /// false after printing where the link goes.
    static func opensInBrowser(_ url: URL) -> Bool {
        guard reportsOnly else { return true }
        print("debug-script: about link would open \(url.absoluteString)")
        return false
    }

    /// The About window's `openURL`: what its links run.
    static let action = OpenURLAction { opensInBrowser($0) ? .systemAction : .handled }
}
