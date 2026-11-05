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

    public init(_ summary: ExportSummary) {
        isWarning = !summary.failures.isEmpty
        listedFailures = Array(summary.failures.prefix(Self.failureListLimit))
        unlistedFailureCount = max(summary.failures.count - Self.failureListLimit, 0)
        skippedByChoice = summary.skippedExisting > 0 ? summary.skippedExisting : nil
    }
}
