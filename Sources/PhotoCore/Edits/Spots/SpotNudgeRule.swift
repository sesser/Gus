/// When a run of spot nudges that is still waiting to be saved must be saved
/// first (healing code review C1): a run of option-arrow nudges is one undo
/// step, saved when the arrow is released; any other change that arrives
/// before then saves the run under its own name first, so each undo step
/// records exactly what it changed (PRD R7).
public enum SpotNudgeRule {
    /// `pending` is the waiting run's undo name, nil for none; `incoming` and
    /// `committing` are the arriving change's name and whether it saves.
    /// Only a further unsaved step of the same run joins it.
    public static func savesPendingFirst(pending: String?, incoming: String, committing: Bool) -> Bool {
        guard let pending else { return false }
        return committing || incoming != pending
    }
}
