import AppKit
import PhotoCore

/// Asks before a quit that would stop a job (`QuitConfirmation`), with a
/// window-modal alert: Keep Importing / Keep Exporting (default, Return and
/// Esc) and Stop and Quit. After Stop and Quit nothing more is said.
@MainActor
public enum QuitGuard {
    /// Set once the person chose Stop and Quit (or a script quits), so the
    /// termination that follows does not ask again.
    public static var allowsQuit = false

    /// The alert's text for one case.
    public struct Text: Equatable, Sendable {
        public var title: String
        public var message: String
        public var keep: String
    }

    public static func text(for confirmation: QuitConfirmation, source: String = "", copied: Int = 0,
                            total: Int = 0) -> Text {
        switch confirmation {
        case .stopCopy:
            Text(title: String(localized: "Stop Importing from “\(source)”?", comment: "Quit alert in the standalone importer"),
                 message: String(localized: "Files copied and checked so far: \(copied) of \(total). The rest stay on “\(source)”.",
                                 comment: "Quit alert in the standalone importer"),
                 keep: String(localized: "Keep Importing", comment: "Quit alert button"))
        case .importing:
            Text(title: String(localized: "Quit While Importing?", comment: "Quit alert in the library app"),
                 message: String(localized: "The rest is not copied.", comment: "Quit alert in the library app"),
                 keep: String(localized: "Keep Importing", comment: "Quit alert button"))
        case .exporting:
            Text(title: String(localized: "Quit While Exporting?", comment: "Quit alert in the library app"),
                 message: String(localized: "The rest is not exported.", comment: "Quit alert in the library app"),
                 keep: String(localized: "Keep Exporting", comment: "Quit alert button"))
        }
    }

    /// True when the person chose Stop and Quit.
    public static func ask(_ text: Text, in window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = text.title
        alert.informativeText = text.message
        alert.addButton(withTitle: text.keep).keyEquivalent = "\r"
        // Not destructive-styled: stopping loses no data, it only leaves the
        // rest where it is.
        alert.addButton(withTitle: String(localized: "Stop and Quit", comment: "Quit alert button"))
        // Esc keeps the job going too (the first button already has Return).
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, event.window === alert.window else { return event }
            if let parent = alert.window.sheetParent {
                parent.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
            } else {
                NSApp.stopModal(withCode: .alertFirstButtonReturn)
            }
            return nil
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        let stop = await WindowModal.run(alert, in: window) == .alertSecondButtonReturn
        if stop { allowsQuit = true }
        return stop
    }
}

/// Lets a SwiftUI window ask before it closes: a delegate in front of
/// SwiftUI's own, answering `windowShouldClose` and forwarding the rest.
/// The standalone importer uses it, where closing the window quits.
@MainActor
public final class WindowCloseGuard: NSObject, NSWindowDelegate {
    /// Read by the two nonisolated forwarding overrides below. AppKit calls
    /// a window's delegate on the main thread only, and this is set once in
    /// `init` (on the main actor), so the unchecked access cannot race.
    private nonisolated(unsafe) weak var original: (any NSWindowDelegate)?
    private let shouldClose: (NSWindow) -> Bool

    /// `shouldClose` false keeps the window open (it may close it later).
    public init(_ window: NSWindow, shouldClose: @escaping (NSWindow) -> Bool) {
        original = window.delegate
        self.shouldClose = shouldClose
        super.init()
        window.delegate = self
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shouldClose(sender) else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    // AppKit asks these on the main thread, where the window lives.
    public nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    public nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}
