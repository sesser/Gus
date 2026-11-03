import Foundation

/// The library window's layout around review mode (section 2 of
/// docs/UI_REDESIGN.md): entering records it and gives the review layout,
/// leaving gives back what was recorded. The loupe is not part of it:
/// leaving review stays in the loupe.
public struct ReviewLayout: Equatable, Sendable {
    public var showsSidebar: Bool
    public var showsInspector: Bool
    public var isFullScreen: Bool

    public init(showsSidebar: Bool, showsInspector: Bool, isFullScreen: Bool) {
        self.showsSidebar = showsSidebar
        self.showsInspector = showsInspector
        self.isFullScreen = isFullScreen
    }

    /// Both panes hidden, full screen.
    public static let review = ReviewLayout(showsSidebar: false, showsInspector: false, isFullScreen: true)
}

/// Review mode on or off, with the layout to go back to.
public struct ReviewSession: Equatable, Sendable {
    public private(set) var recorded: ReviewLayout?

    public init() {}

    public var isReviewing: Bool { recorded != nil }

    /// The layout to show; nil when already reviewing.
    public mutating func enter(from current: ReviewLayout) -> ReviewLayout? {
        guard recorded == nil else { return nil }
        recorded = current
        return .review
    }

    /// The layout to restore, keeping what changed during review that the
    /// person asked for: an inspector brought back with ⌥⌘I stays. Nil when
    /// not reviewing.
    public mutating func exit(current: ReviewLayout) -> ReviewLayout? {
        guard var layout = recorded else { return nil }
        recorded = nil
        layout.showsInspector = layout.showsInspector || current.showsInspector
        return layout
    }
}
