import Foundation

/// The toolbar's Activity item: jobs while they run, and recent messages
/// that used to go to the status bar (section 1 of docs/UI_REDESIGN.md).
public struct ActivityLog: Hashable, Sendable {
    public struct Message: Hashable, Sendable, Identifiable {
        public var id: Int
        public var text: String
        public var date: Date
    }

    /// Newest last, at most `limit`.
    public private(set) var messages: [Message] = []
    /// Messages posted since the popover was last opened.
    public private(set) var unseenCount = 0
    public let limit: Int
    private var nextID = 0

    public init(limit: Int = 20) {
        self.limit = limit
    }

    public mutating func post(_ text: String, at date: Date = Date()) {
        // The same message again (a repeated error) moves to the end.
        messages.removeAll { $0.text == text }
        messages.append(Message(id: nextID, text: text, date: date))
        nextID += 1
        if messages.count > limit { messages.removeFirst(messages.count - limit) }
        unseenCount = min(unseenCount + 1, messages.count)
    }

    /// The popover was opened.
    public mutating func markSeen() {
        unseenCount = 0
    }

    /// Rendering previews and suggesting keywords run in the background
    /// after imports; they show only once they have run this long.
    public static let backgroundDelay: TimeInterval = 5

    /// Whether a job started at `start` shows at `now`.
    public static func shows(background: Bool, startedAt start: Date, now: Date) -> Bool {
        !background || now.timeIntervalSince(start) >= backgroundDelay
    }
}
