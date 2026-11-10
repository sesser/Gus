import Foundation

/// What the loupe's History panel shows (edit-history design §6): decided here
/// so the rule is testable without the window.
public enum EditHistoryPanelState: Equatable, Sendable {
    /// No panel: the grid and review mode never show history (R12).
    case absent
    /// The photo or its entries are not loaded yet. Nothing is drawn.
    case loading
    /// A photo that can be edited and has no entries yet.
    case empty
    case entries(Int)
    /// The panel stays, with a reason, so the inspector does not jump between photos.
    case unavailable(Reason)

    public enum Reason: Equatable, Sendable {
        case video
        case offline
        /// The stored stack can't be read by this build: nothing is written, so no list.
        case unreadable
        /// The list could not be read from the catalog.
        case failed
    }

    /// What the editor knows of the photo in the loupe.
    public enum Source: Equatable, Sendable {
        case notReady
        case ready
        case video
        case offline
        case unreadable
    }

    /// `entryCount` is nil until the list for the shown photo has loaded;
    /// `listFailed` says the read for it failed.
    public static func make(isLoupe: Bool, isReviewing: Bool, source: Source, entryCount: Int?,
                            listFailed: Bool = false) -> Self {
        guard isLoupe, !isReviewing else { return .absent }
        switch source {
        case .notReady: return .loading
        case .video: return .unavailable(.video)
        case .offline: return .unavailable(.offline)
        case .unreadable: return .unavailable(.unreadable)
        case .ready:
            if listFailed { return .unavailable(.failed) }
            guard let entryCount else { return .loading }
            return entryCount == 0 ? .empty : .entries(entryCount)
        }
    }

    /// Whether the rows can be clicked: only with entries, and not during a
    /// crop session, whose half-made crop a revert would discard.
    public func allowsRevert(isCropping: Bool) -> Bool {
        if case .entries = self { return !isCropping }
        return false
    }
}

/// The time text of history rows (design §5): the short time for today,
/// the system's relative form ("Yesterday, 4:10 PM") for yesterday, and the
/// date without the year for this year. One formatter set per list load.
public struct EditHistoryTime {
    private let calendar: Calendar
    private let now: Date
    private let sameDay: DateFormatter
    private let yesterday: DateFormatter
    private let thisYear: DateFormatter
    private let otherYear: DateFormatter
    private let spoken: DateFormatter
    private let exact: DateFormatter

    public init(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) {
        self.now = now
        var calendar = calendar
        calendar.locale = locale
        self.calendar = calendar
        func formatter(_ configure: (DateFormatter) -> Void) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            configure(formatter)
            return formatter
        }
        sameDay = formatter { $0.dateStyle = .none; $0.timeStyle = .short }
        yesterday = formatter { $0.dateStyle = .medium; $0.timeStyle = .short; $0.doesRelativeDateFormatting = true }
        thisYear = formatter { $0.setLocalizedDateFormatFromTemplate("MMMd jmm") }
        otherYear = formatter { $0.setLocalizedDateFormatFromTemplate("yMMMd jmm") }
        spoken = formatter { $0.dateStyle = .long; $0.timeStyle = .short; $0.doesRelativeDateFormatting = true }
        exact = formatter { $0.dateStyle = .medium; $0.timeStyle = .medium }
    }

    /// The row's trailing text.
    public func short(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return sameDay.string(from: date) }
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) {
            return yesterday.string(from: date)
        }
        return (calendar.isDate(date, equalTo: now, toGranularity: .year) ? thisYear : otherYear).string(from: date)
    }

    /// For VoiceOver: "Today at 2:41 PM".
    public func spokenText(_ date: Date) -> String { spoken.string(from: date) }

    /// The tooltip's full date and time with seconds.
    public func exactText(_ date: Date) -> String { exact.string(from: date) }
}

extension EditHistoryPanelState {
    /// Whether ⌥⌘3 may hand the keyboard to the list: only a list with rows has
    /// anything to move in (a request left pending would fire much later).
    public var canTakeKeyboard: Bool {
        if case .entries = self { return true }
        return false
    }
}
