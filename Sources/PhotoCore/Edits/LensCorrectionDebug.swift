import Synchronization

/// Debug switches for the Distortion and Lens Vignetting groups, so a scripted
/// check can see what a person is told when correction can't run (R11, AC11).
/// Never a setting: only the debug script (`lens force`) and tests set them.
public enum LensCorrectionDebug {
    public enum Fault: String, CaseIterable, Sendable {
        /// The kernels behave as if they could not be compiled.
        case kernelFailure = "kernelfail"
        /// Every table Auto could use reads as damaged.
        case tableCorrupt = "tablecorrupt"
    }

    private static let state = Mutex<Fault?>(nil)

    /// A fault for the current task and the tasks it starts only: what tests
    /// set, so parallel suites never see it (code review C9).
    @TaskLocal public static var taskFault: Fault?

    /// The fault in effect: the task's, or the process-wide one the debug
    /// script sets.
    public static var fault: Fault? {
        get { taskFault ?? state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
