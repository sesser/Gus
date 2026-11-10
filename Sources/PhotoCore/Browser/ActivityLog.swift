import Foundation

/// The toolbar's Activity item: jobs while they run, and recent messages
/// that used to go to the status bar (section 1 of docs/UI_REDESIGN.md).
public struct ActivityLog: Hashable, Sendable {
    public struct Message: Hashable, Sendable, Identifiable {
        public var id: Int
        /// The undo name of the action that posted it, when there is one.
        public var title: String?
        public var text: String
        /// Something failed, as opposed to information.
        public var isWarning: Bool
        public var date: Date
    }

    /// Newest last, at most `limit`.
    public private(set) var messages: [Message] = []
    /// Messages posted since the popover was last closed.
    public private(set) var unseenCount = 0
    /// One of the unseen messages is a warning.
    public private(set) var unseenHasWarning = false
    /// The popover is open. The toolbar item is its anchor, so the item stays
    /// while this is true (`showsItem`).
    public private(set) var isPopoverShown = false
    public let limit: Int
    private var nextID = 0

    public init(limit: Int = 20) {
        self.limit = limit
    }

    public mutating func post(_ text: String, title: String? = nil, isWarning: Bool = false, at date: Date = Date()) {
        // The same message again (a repeated error) moves to the end.
        messages.removeAll { $0.text == text && $0.title == title }
        messages.append(Message(id: nextID, title: title, text: text, isWarning: isWarning, date: date))
        nextID += 1
        if messages.count > limit { messages.removeFirst(messages.count - limit) }
        unseenCount = min(unseenCount + 1, messages.count)
        unseenHasWarning = unseenHasWarning || isWarning
    }

    /// The popover opened or closed. Closing it marks every message read,
    /// those posted while it was open included: it listed them all. Opening
    /// it does not: reading the messages hides an idle item, and hiding the
    /// item takes away the popover's anchor before it can open (issue #56).
    public mutating func setPopoverShown(_ shown: Bool) {
        guard shown != isPopoverShown else { return }
        isPopoverShown = shown
        if !shown {
            unseenCount = 0
            unseenHasWarning = false
        }
    }

    /// Whether the toolbar shows the Activity item: while a job runs, while
    /// messages are unread, and while its popover is open (after its job
    /// ended, say).
    public func showsItem(jobsRunning: Bool) -> Bool {
        jobsRunning || unseenCount > 0 || isPopoverShown
    }

    /// Rendering previews and suggesting keywords run in the background
    /// after imports; they show only once they have run this long.
    public static let backgroundDelay: TimeInterval = 5

    /// Whether a job started at `start` shows at `now`.
    public static func shows(background: Bool, startedAt start: Date, now: Date) -> Bool {
        !background || now.timeIntervalSince(start) >= backgroundDelay
    }
}
