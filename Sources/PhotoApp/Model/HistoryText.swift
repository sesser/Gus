import Foundation

/// The wording of edit history entries. An entry is named like the undo step
/// of its change (PRD A4), and the names for undo, redo and revert are whole
/// catalog strings, not concatenations, so they can be localized.
enum HistoryText {
    /// The label of the entry a write records: `actionName` for an edit,
    /// "Undo ..." or "Redo ..." when the write is the window's undo or redo.
    static func label(_ actionName: String, undoing: Bool, redoing: Bool) -> String {
        if undoing { return undone(actionName) }
        if redoing { return redone(actionName) }
        return actionName
    }

    static func undone(_ actionName: String) -> String {
        String(localized: "Undo \(actionName)", comment: "Edit history entry and its undo name: a change taken back; the name of the undone step follows")
    }

    static func redone(_ actionName: String) -> String {
        String(localized: "Redo \(actionName)", comment: "Edit history entry: a change done again; the name of the redone step follows")
    }

    /// The undo name and entry label of a revert to the entry labeled `label`.
    static func revert(toLabel label: String) -> String {
        String(localized: "Revert to “\(label)”", comment: "Edit history: undo name and entry label of a return to an earlier state; the earlier entry's label in quotes")
    }
}
