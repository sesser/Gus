import Foundation

/// Waiting on the main actor for a condition with a real deadline: the
/// condition is asked again every `interval` until it no longer holds or the
/// time is up, whatever the work behind it is doing. (Racing that work in a
/// task group doesn't bound the wait: a group waits for all its children, and
/// awaiting another task's value ignores cancellation; code review C7.)
@MainActor
public enum MainActorWait {
    /// Returns true when `condition` stopped holding before `timeout`.
    @discardableResult
    public static func whileTrue(_ condition: () -> Bool, timeout: Duration,
                                 interval: Duration = .milliseconds(50)) async -> Bool {
        let clock = ContinuousClock()
        let start = clock.now
        return await whileTrue(condition, timeout: timeout, interval: interval,
                               elapsed: { clock.now - start },
                               sleep: { try? await Task.sleep(for: $0) })
    }

    /// The same, with the time read from `elapsed` and waited by `sleep`
    /// (tests stand in for both, so they don't depend on the machine's load).
    static func whileTrue(_ condition: () -> Bool, timeout: Duration, interval: Duration,
                          elapsed: () -> Duration, sleep: (Duration) async -> Void) async -> Bool {
        while condition() {
            let spent = elapsed()
            guard spent < timeout else { return false }
            await sleep(min(interval, timeout - spent))
        }
        return true
    }
}
