import Foundation

/// The order of a library window's catalog writes, and the rule for the
/// reads whose results must agree with them.
///
/// Writes run one after another in the order they were queued, so changes
/// reach the catalog in the order they were made and an undo step runs after
/// the change it reverses.
///
/// The window shows some changes before their write lands (culling) and
/// others only once it has (an edit's render hash). A catalog read that runs
/// beside the chain can therefore return a row from before a write and be
/// used after it: a reload then puts the old values back on screen, and the
/// editor, loading a photo whose last save is still queued, starts from the
/// older stack and writes it back with the next change. `read(_:apply:)`
/// rules both out. It reads only once every write queued before it has
/// landed, and hands the result on only if no write was queued while it
/// read; otherwise it reads again.
@MainActor
public final class WriteChain {
    /// Writes queued so far. A read's result is current while this is
    /// unchanged since it started reading.
    public private(set) var queuedCount = 0
    /// The last write queued; it runs after every earlier one.
    private var tail: Task<Void, Never>?

    public init() {}

    /// Runs `work` after every write queued before it.
    public func enqueue(_ work: @escaping @MainActor () async -> Void) {
        queuedCount += 1
        let previous = tail
        tail = Task {
            await previous?.value
            await work()
        }
    }

    /// Runs `body` once the writes queued so far have finished. Not itself a
    /// write: later writes do not wait for it.
    public func afterPendingWrites(_ body: @escaping @MainActor () async -> Void) {
        let previous = tail
        Task {
            await previous?.value
            await body()
        }
    }

    /// Reads with `fetch` and hands the result to `apply`, which runs before
    /// anything else on the main actor, so no write can come between the
    /// check and its use. `fetch` runs only once every write queued so far
    /// has finished, and runs again if a write was queued while it ran.
    /// Throws `CancellationError` when the calling task is cancelled, and
    /// whatever `fetch` throws; `apply` is not called then.
    @discardableResult
    public func read<Value>(_ fetch: @MainActor () async throws -> Value,
                            apply: (Value) throws -> Void) async throws -> Value {
        while true {
            try Task.checkCancellation()
            let mark = await settled()
            let value = try await fetch()
            try Task.checkCancellation()
            guard mark == queuedCount else { continue }
            try apply(value)
            return value
        }
    }

    /// Waits until no write is pending, including writes queued while it
    /// waits, and returns the count of writes queued by then.
    func settled() async -> Int {
        while true {
            let mark = queuedCount
            await tail?.value
            if mark == queuedCount { return mark }
        }
    }
}
