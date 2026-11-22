import Dispatch
import Testing

/// `offCooperativePool` (Support/BlockingWork.swift): without it working, the
/// suites that use it would block the cooperative pool again and nothing would
/// say so until CI starved (bug #253, docs/features/core-image-split-render/status.md).
@Suite("Blocking test work")
struct BlockingWorkTests {
    @Test("A body run off the cooperative pool runs on the blocking-work queue, in the test's own task")
    func runsOffTheCooperativePool() async throws {
        let label = await offCooperativePool { String(cString: __dispatch_queue_get_label(nil)) }
        #expect(label == BlockingWorkExecutor.label)
        // Across an await inside the body too.
        let afterAwait = await offCooperativePool {
            await Task.yield()
            return String(cString: __dispatch_queue_get_label(nil))
        }
        #expect(afterAwait == BlockingWorkExecutor.label)
        // The same task: the test's task-locals, which `#expect` reports through.
        let test = await offCooperativePool { Test.current?.id }
        #expect(test != nil && test == Test.current?.id)
        // Errors pass through.
        struct Expected: Error {}
        await #expect(throws: Expected.self) { try await offCooperativePool { throw Expected() } }
    }
}
