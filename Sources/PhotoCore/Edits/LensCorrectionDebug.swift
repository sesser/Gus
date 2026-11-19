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

    public static var fault: Fault? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
