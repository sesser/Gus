import AppKit
import PhotoCore

/// Review mode (section 2 of docs/UI_REDESIGN.md): the loupe on the focused
/// photo, both panes hidden, full screen with the toolbar shown on hover.
/// Esc or F restores the layout and stays in the loupe.
extension LibraryModel {
    var isReviewing: Bool { review.isReviewing }

    func toggleReview() {
        if review.isReviewing { exitReview() } else { enterReview() }
    }

    func enterReview() {
        guard focusIndex != nil, !review.isReviewing else { return }
        let window = windowObserver.window
        let current = ReviewLayout(showsSidebar: showsSidebar, showsInspector: showsInspector,
                                   isFullScreen: window?.styleMask.contains(.fullScreen) == true)
        guard let layout = review.enter(from: current) else { return }
        if mode != .loupe { openLoupe() }
        apply(layout, in: window)
    }

    /// `restoringFullScreen` false: the window left full screen by itself
    /// and stays out of it; only the panes come back.
    func exitReview(restoringFullScreen: Bool = true) {
        let window = windowObserver.window
        let isFullScreen = window?.styleMask.contains(.fullScreen) == true
        let current = ReviewLayout(showsSidebar: showsSidebar, showsInspector: showsInspector, isFullScreen: isFullScreen)
        guard var layout = review.exit(current: current) else { return }
        if !restoringFullScreen { layout.isFullScreen = isFullScreen }
        apply(layout, in: window)
    }

    private func apply(_ layout: ReviewLayout, in window: NSWindow?) {
        showsSidebar = layout.showsSidebar
        showsInspector = layout.showsInspector
        if let window, window.styleMask.contains(.fullScreen) != layout.isFullScreen {
            window.toggleFullScreen(nil)
        }
    }
}
