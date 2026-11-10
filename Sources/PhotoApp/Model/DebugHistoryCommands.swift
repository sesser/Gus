import AppKit
import PhotoCore

/// Debug-script commands for the loupe's History panel (edit-history design §12):
///
/// - `history`: prints the panel's state, whether it is expanded, the entries
///   the model holds and the rows the table draws, newest first.
/// - `history wait`: waits (up to 3 s) until the list holds the focused photo's entries, then 0.6 s for queued saves to land and the list to reload.
/// - `history open` / `history close`: View ▸ Show / Hide History's action.
/// - `history revert <n>`: clicks row `n` (0 is the newest), as a person would.
@MainActor
enum DebugHistoryCommands {
    static func run(_ words: [String], model: LibraryModel, window: NSWindow?) async {
        switch words.first {
        case "wait":
            for _ in 0..<300 where model.history.versionID != model.focusedItem?.versionID {
                try? await Task.sleep(for: .milliseconds(10))
            }
            // Saves queue behind each other and the list reloads after each; the table takes the entries on its next update.
            try? await Task.sleep(for: .milliseconds(600))
        case "open":
            if !model.historyIsOpen { model.toggleHistory() }
            try? await Task.sleep(for: .milliseconds(300))
        case "close":
            if model.historyIsOpen { model.toggleHistory() }
            try? await Task.sleep(for: .milliseconds(300))
        case "revert":
            guard let text = words.dropFirst().first, let row = Int(text), model.history.entries.indices.contains(row) else {
                print("debug-script: history revert expects a row number")
                return
            }
            model.revertHistory(to: model.history.entries[row])
            try? await Task.sleep(for: .milliseconds(500))
        default:
            printState(model: model, window: window)
        }
    }

    static func printState(model: LibraryModel, window: NSWindow?) {
        let table = window?.contentView.flatMap(findTable(in:))
        print("debug-script: history state \(model.historyPanelState) expanded \(model.showsHistory) "
              + "inspector \(model.showsInspector) entries \(model.history.entries.count) "
              + "table \(table != nil) rows \(table?.numberOfRows ?? 0) enabled \(table?.enclosingScrollView?.alphaValue == 1) "
              + "keyboard \(table.map { window?.firstResponder === $0 } ?? false)")
        for (index, entry) in model.history.entries.enumerated() {
            let drawn = (table?.view(atColumn: 0, row: index, makeIfNecessary: true) as? HistoryCell)?.debugText ?? "-"
            print("debug-script: history row \(index) \(entry.label) | \(model.history.time.exactText(entry.createdAt)) drawn \(drawn)")
        }
    }

    private static func findTable(in view: NSView) -> HistoryTable.KeyTableView? {
        if let table = view as? HistoryTable.KeyTableView { return table }
        for subview in view.subviews {
            if let found = findTable(in: subview) { return found }
        }
        return nil
    }
}
