/// What a finished export reports in Activity; never an alert, since the
/// export ran after its sheet closed (design.md I3, owner ruling D2). The UI
/// puts it into words.
public struct ExportActivityReport: Hashable, Sendable {
    /// Files that failed are listed up to this many; the rest are counted.
    public static let failureListLimit = 10

    /// The export's row is a warning: some photos could not be written.
    public var isWarning: Bool
    /// The failures the row lists, in the order they happened.
    public var listedFailures: [ExportSummary.Failure]
    /// Failures past `failureListLimit` ("And N more.").
    public var unlistedFailureCount: Int
    /// Photos the person chose to skip because their names were taken; an
    /// information row of its own, or nil when none were.
    public var skippedByChoice: Int?
    /// Photos written without the machine learning noise reduction their
    /// stacks ask for, by reason: one information row each, posted before
    /// the export's own row (ml-denoise design §7). Reasons in
    /// `MachineLearningNoiseReduction.Reason.allCases` order; empty when every
    /// request applied.
    public var machineLearningNotApplied: [MachineLearningRow]

    public struct MachineLearningRow: Hashable, Sendable {
        public var reason: MachineLearningNoiseReduction.Reason
        public var count: Int
    }

    public init(_ summary: ExportSummary) {
        isWarning = !summary.failures.isEmpty
        listedFailures = Array(summary.failures.prefix(Self.failureListLimit))
        unlistedFailureCount = max(summary.failures.count - Self.failureListLimit, 0)
        skippedByChoice = summary.skippedExisting > 0 ? summary.skippedExisting : nil
        let reasons = summary.machineLearning.compactMap(\.outcome.reason)
        machineLearningNotApplied = MachineLearningNoiseReduction.Reason.allCases.compactMap { reason in
            let count = reasons.filter { $0 == reason }.count
            return count > 0 ? MachineLearningRow(reason: reason, count: count) : nil
        }
    }
}
