import AppKit
import PhotoCore
import PhotoUI

/// The open photo's history entries as the panel shows them, with the photo
/// they were read for and the formatters of that load.
struct EditHistoryList {
    var versionID: Int64?
    /// Newest first; the first entry is the current state.
    var entries: [EditHistoryEntry] = []
    var time = EditHistoryTime()
}

extension LibraryModel {
    /// What the History panel shows for the focused photo (design §6).
    var historyPanelState: EditHistoryPanelState {
        let focus = focusedItem?.versionID
        // The video loupe does not hand its video to the editor, so the item says it.
        let source: EditHistoryPanelState.Source = if focusedItem?.isVideo == true {
            .video
        } else if let focus, editor.item?.versionID == focus {
            switch editor.state {
            case .ready: .ready
            case .video: .video
            case .offline: .offline
            case .unreadable: .unreadable
            case .idle, .loading: .notReady
            }
        } else {
            .notReady
        }
        let loaded = focus != nil && history.versionID == focus ? history.entries.count : nil
        return .make(isLoupe: mode == .loupe, isReviewing: isReviewing, source: source, entryCount: loaded)
    }

    /// View ▸ Show / Hide History applies: the loupe, not reviewing.
    var canShowHistory: Bool { mode == .loupe && !isReviewing }

    /// The panel is shown and expanded (the menu item's title).
    var historyIsOpen: Bool { showsHistory && showsInspector }

    /// View ▸ Show / Hide History (⌥⌘3). Show brings the inspector back if it
    /// is hidden, expands the panel and hands it the keyboard; hide collapses
    /// it and gives the keyboard back to the loupe.
    func toggleHistory() {
        guard canShowHistory else { return }
        if historyIsOpen {
            showsHistory = false
            NotificationCenter.default.post(name: .browserShouldTakeFocus, object: self)
        } else {
            showsInspector = true
            showsHistory = true
            historyWantsKeyboard = true
        }
    }

    /// A write recorded (or may have recorded) entries: the list reloads.
    func historyChanged() {
        historyRevision += 1
    }

    /// Reads the focused photo's entries off the main thread and keeps them if
    /// the focus has not moved on. A failed read leaves the list not loaded.
    func loadHistory(forVersion versionID: Int64) async {
        let catalog = self.catalog
        let entries: [EditHistoryEntry]
        do {
            entries = try await catalog.editHistory(forVersion: versionID)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        history = EditHistoryList(versionID: versionID, entries: entries, time: EditHistoryTime())
    }

    /// Returns the open photo to the state `entry` recorded (click or Return in
    /// the list). One undo step named "Revert to “…”", one new entry.
    func revertHistory(to entry: EditHistoryEntry) {
        guard mode == .loupe, history.entries.first?.id != entry.id, let versionID = history.versionID else { return }
        editor.revert(toHistoryEntry: entry, ofVersion: versionID)
    }
}
