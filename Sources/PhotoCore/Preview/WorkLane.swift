import Foundation

/// A bounded-concurrency work queue with request coalescing, priorities and
/// cancellation, used by the preview pipeline.
///
/// - Requests with the same key share one job.
/// - Higher priority runs first; within a priority the most recent request wins,
///   so cells that just scrolled into view are served before ones that left.
/// - A cancelled request leaves its job; a job nobody waits for any more is
///   dropped if pending, or has its task cancelled if running.
actor WorkLane<Output: Sendable> {
    private final class Job {
        let id: UInt64
        let key: String
        var priority: Int
        var sequence: UInt64
        let taskPriority: TaskPriority
        let work: @Sendable () async throws -> Output
        var waiters: [UInt64: CheckedContinuation<Output, any Error>] = [:]
        var task: Task<Void, Never>?

        init(id: UInt64, key: String, priority: Int, taskPriority: TaskPriority,
             work: @escaping @Sendable () async throws -> Output) {
            self.id = id
            self.key = key
            self.priority = priority
            self.sequence = id
            self.taskPriority = taskPriority
            self.work = work
        }
    }

    private let limit: Int
    private var pending: [String: Job] = [:]
    /// Running jobs that still have waiters, by key.
    private var running: [String: Job] = [:]
    /// Every started job, including ones being cancelled, by id.
    private var active: [UInt64: Job] = [:]
    private var counter: UInt64 = 0

    init(concurrency: Int) {
        limit = max(1, concurrency)
    }

    /// Number of jobs waiting to start.
    var pendingCount: Int { pending.count }

    func run(key: String, priority: Int, taskPriority: TaskPriority = .medium,
             work: @escaping @Sendable () async throws -> Output) async throws -> Output {
        counter += 1
        let waiterID = counter
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let job = running[key] {
                    job.waiters[waiterID] = continuation
                } else if let job = pending[key] {
                    job.waiters[waiterID] = continuation
                    job.priority = max(job.priority, priority)
                    job.sequence = waiterID
                } else {
                    let job = Job(id: waiterID, key: key, priority: priority, taskPriority: taskPriority, work: work)
                    job.waiters[waiterID] = continuation
                    pending[key] = job
                    startJobs()
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, key: key) }
        }
    }

    private func cancelWaiter(_ waiterID: UInt64, key: String) {
        let job = pending[key] ?? running[key]
        guard let job, let continuation = job.waiters.removeValue(forKey: waiterID) else { return }
        continuation.resume(throwing: CancellationError())
        guard job.waiters.isEmpty else { return }
        if pending[key] === job {
            pending[key] = nil
        } else if running[key] === job {
            // Keep it in `active` (it still holds a slot) until the task notices.
            running[key] = nil
            job.task?.cancel()
        }
    }

    private func startJobs() {
        while active.count < limit, let job = nextJob() {
            pending[job.key] = nil
            running[job.key] = job
            active[job.id] = job
            let work = job.work
            let id = job.id
            job.task = Task.detached(priority: job.taskPriority) { [weak self] in
                let result: Result<Output, any Error>
                do {
                    try Task.checkCancellation()
                    result = .success(try await work())
                } catch {
                    result = .failure(error)
                }
                await self?.finish(id, result)
            }
        }
    }

    private func nextJob() -> Job? {
        pending.values.max { ($0.priority, $0.sequence) < ($1.priority, $1.sequence) }
    }

    private func finish(_ id: UInt64, _ result: Result<Output, any Error>) {
        guard let job = active.removeValue(forKey: id) else { return }
        if running[job.key] === job {
            running[job.key] = nil
        }
        let waiters = job.waiters.values
        job.waiters.removeAll()
        for continuation in waiters {
            continuation.resume(with: result)
        }
        startJobs()
    }
}
