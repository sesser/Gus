import AppKit

/// Follows the library window for the menu bar: whether it is key (a sheet
/// or another window being key turns every library item off) and whether
/// the grid, the loupe or the video loupe has the keyboard (bare-key items
/// are on only then; section 6 of docs/UI_REDESIGN.md).
@MainActor
final class LibraryWindowObserver {
    private(set) weak var window: NSWindow?
    private var responderObservation: NSKeyValueObservation?
    private var keyObservers: [any NSObjectProtocol] = []
    private let onChange: (_ isKey: Bool, _ browserHasKeyboard: Bool) -> Void
    /// The window left full screen, by any route (⌃⌘F, the green button,
    /// the menu): review ends.
    var onDidExitFullScreen: (() -> Void)?

    init(onChange: @escaping (_ isKey: Bool, _ browserHasKeyboard: Bool) -> Void) {
        self.onChange = onChange
    }

    func attach(_ window: NSWindow?) {
        guard window !== self.window else { return }
        self.window = window
        responderObservation = nil
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
        guard let window else {
            report()
            return
        }
        responderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.report() }
        }
        keyObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDidExitFullScreen?() }
        })
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            })
        }
        report()
    }

    private func report() {
        onChange(window?.isKeyWindow == true, Self.isBrowser(window?.firstResponder))
    }

    /// The grid, the loupe canvas, or a view inside the video loupe (AVKit
    /// gives the keyboard to a view of its own).
    static func isBrowser(_ responder: NSResponder?) -> Bool {
        var view = responder as? NSView
        while let current = view {
            if current is PhotoCollectionView || current is LoupeHostView || current is VideoLoupeHostView { return true }
            view = current.superview
        }
        return false
    }
}
