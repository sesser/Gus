/// The publish sheet's check that found its server saved again since it was
/// chosen (security review N7: nothing was sent) leaves the sheet at
/// Checking… until the server is checked again as saved now. The reload the
/// Save posts does that only while the sheet shows (nothing is contacted
/// otherwise), and the sheet is hidden while its own Server sheet is up. So
/// this records a check left waiting and says when to check again: at once
/// when the sheet shows and has already read the change, else when it shows
/// again, unless choosing a server (the reload's own recheck included) came
/// first (code review C14).
public struct PublishCheckRecovery: Equatable, Sendable {
    /// A check ended on a change, and nothing has checked the server since.
    public private(set) var isWaiting = false

    public init() {}

    /// A check started (choosing a server, Try Again): nothing waits.
    public mutating func checkStarted() {
        isWaiting = false
    }

    /// The check of `checked` found the server saved with another address or
    /// trusted certificate. `listed` is the chosen server in the sheet's list
    /// now (nil when no longer listed: the removal's reload clears the sheet).
    /// True: check again now.
    public mutating func checkFoundChange(checked: RemoteServiceRecord, listed: RemoteServiceRecord?,
                                          sheetShown: Bool) -> Bool {
        guard let listed else {
            isWaiting = false
            return false
        }
        // The sheet's list already has the change: its reload has come and
        // gone, so no recheck from it is still to come.
        let reloaded = PublishServerChange.after(reload: [listed], chosenID: listed.id, before: checked) != .unchanged
        if sheetShown, reloaded {
            isWaiting = false
            return true
        }
        isWaiting = true
        return false
    }

    /// The sheet shows again (back from its Server sheet). True: check again
    /// now.
    public func sheetShown() -> Bool {
        isWaiting
    }
}
