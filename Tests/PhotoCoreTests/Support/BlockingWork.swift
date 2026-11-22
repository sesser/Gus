import Dispatch

/// Runs a test body that blocks for a long time (synchronous Core Image renders
/// that wait for the GPU, comparisons of millions of values in a debug build) on
/// Dispatch threads outside Swift concurrency's cooperative pool.
///
/// The cooperative pool has one thread per core, three on the CI runners, and
/// Swift Testing runs every test on it in parallel. A test that blocks a pool
/// thread for seconds holds back every other test's continuations; with all
/// three blocked, none runs. `WorkLaneTests.cancellingTheLastWaiterCancelsTheJob`
/// needs its cancellation to arrive within the 10 s its job sleeps, and on CI it
/// did not while the full-size decode tests blocked the pool (bug #253,
/// docs/features/core-image-split-render/status.md, "CI").
///
/// The body stays in the same task, so `#expect` and `#require` report to its
/// test as before; only the threads its nonisolated code runs on change.
func offCooperativePool<T, Failure: Error>(_ body: () async throws(Failure) -> T) async throws(Failure) -> T {
    try await withTaskExecutorPreference(BlockingWorkExecutor.shared, operation: body)
}

/// A task executor on a concurrent Dispatch queue: a job that blocks occupies a
/// Dispatch thread, never one of the cooperative pool's.
final class BlockingWorkExecutor: TaskExecutor {
    static let shared = BlockingWorkExecutor()
    static let label = "tests.blocking-work"

    private let queue = DispatchQueue(label: label, qos: .userInitiated, attributes: .concurrent)

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedTaskExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }
}
