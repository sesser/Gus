import AppKit

/// Follows the library window for the menu bar: whether it is key (a sheet
/// or another window being key turns every library item off), whether
/// the grid, the loupe or the video loupe has the keyboard (bare-key items
/// are on only then; section 6 of docs/UI_REDESIGN.md), and whether the
/// sidebar has it (File ▸ Show in Finder then means its selected project;
/// docs/features/library-ops/design.md §5.2).
@MainActor
final class LibraryWindowObserver {
    private(set) weak var window: NSWindow?
    private var responderObservation: NSKeyValueObservation?
    private var keyObservers: [any NSObjectProtocol] = []
    private let onChange: (_ isKey: Bool, _ browserHasKeyboard: Bool, _ sidebarHasKeyboard: Bool) -> Void
    /// A view inside the sidebar (`SidebarMarker`), which tells its pane of
    /// the split view from the others.
    weak var sidebarMarker: NSView?
    /// The window left full screen, by any route (⌃⌘F, the green button,
    /// the menu): review ends.
    var onDidExitFullScreen: (() -> Void)?

    init(onChange: @escaping (_ isKey: Bool, _ browserHasKeyboard: Bool, _ sidebarHasKeyboard: Bool) -> Void) {
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
        onChange(window?.isKeyWindow == true, Self.isBrowser(window?.firstResponder),
                 Self.isInSidebar(window?.firstResponder, marker: sidebarMarker))
    }

    /// The first responder is a view in the sidebar's pane: its list, or the
    /// field editor of a row being renamed. The pane is the split view's
    /// subview that holds `marker`; SwiftUI's own list and split view classes
    /// are private, so the pane is found from a view of ours.
    static func isInSidebar(_ responder: NSResponder?, marker: NSView?) -> Bool {
        guard let view = responder as? NSView, let marker else { return false }
        var pane = marker
        while let parent = pane.superview, !(parent is NSSplitView) { pane = parent }
        guard pane.superview is NSSplitView else { return false }
        return view.isDescendant(of: pane)
    }

    /// The sidebar's list, for debug scripts to hand it the keyboard as a
    /// click on a row does: the table view in the sidebar's pane.
    func sidebarList() -> NSView? {
        guard let marker = sidebarMarker else { return nil }
        var pane = marker
        while let parent = pane.superview, !(parent is NSSplitView) { pane = parent }
        guard pane.superview is NSSplitView else { return nil }
        func find(_ view: NSView) -> NSView? {
            if view is NSTableView { return view }
            for subview in view.subviews {
                if let found = find(subview) { return found }
            }
            return nil
        }
        return find(pane)
    }

    /// The grid, the loupe canvas, the comparison's panes, or a view inside
    /// the video loupe (AVKit gives the keyboard to a view of its own).
    static func isBrowser(_ responder: NSResponder?) -> Bool {
        var view = responder as? NSView
        while let current = view {
            if current is PhotoCollectionView || current is LoupeHostView || current is VideoLoupeHostView
                || current is ComparisonHostView { return true }
            view = current.superview
        }
        return false
    }
}
