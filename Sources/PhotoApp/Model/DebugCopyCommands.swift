import AppKit
import PhotoCore
import PhotoUI

/// Debug-script commands for File ▸ Duplicate and a copy's marks
/// (docs/features/virtual-copies); `DebugScript` lists them.
@MainActor
enum DebugCopyCommands {
    /// `duplicate`: File ▸ Duplicate's action on the targets, waited for
    /// until its copies are written and shown, so its undo step lands in the
    /// command's undo group. `duplicate fail on|off` makes it fail in the
    /// catalog, as `removal fail` does for removals.
    static func duplicate(_ words: [String], model: LibraryModel) async {
        if words.first == "fail" {
            await setFailure(words.dropFirst().first != "off", model: model)
            return
        }
        guard model.canDuplicateTargets else {
            print("debug-script: duplicate unavailable")
            return
        }
        let start = ContinuousClock.now
        var job: RemovalJob?
        model.duplicateTargets()
        while model.isDuplicating {
            job = model.duplicateJob ?? job
            try? await Task.sleep(for: .milliseconds(50))
        }
        if let job {
            let elapsed = ContinuousClock.now - start
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            print(String(format: "debug-script: duplicate ran %.1f s, Activity job '%@'%@", seconds, job.title,
                         job.detail.map { " detail '\($0)'" } ?? ""))
        }
        // The counts in the sidebar follow the copies.
        try? await Task.sleep(for: .milliseconds(600))
    }

    /// Waits for a Duplicate another command started (a menu item, a key),
    /// so its undo step, registered once the copies are written, lands in
    /// that command's undo group.
    static func waitForDuplicate(_ model: LibraryModel) async {
        while model.isDuplicating { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// Temporary triggers on this process's writer connection: nothing is
    /// stored in the catalog file.
    private static func setFailure(_ on: Bool, model: LibraryModel) async {
        do {
            try await model.catalog.database.write { db in
                try db.execute(sql: "DROP TRIGGER IF EXISTS temp.debug_duplicate_failure")
                guard on else { return }
                try db.execute(sql: """
                    CREATE TEMP TRIGGER debug_duplicate_failure BEFORE INSERT ON main.version
                    BEGIN SELECT RAISE(ABORT, 'forced duplicate failure'); END
                    """)
            }
            print("debug-script: duplicate fail \(on ? "on" : "off")")
        } catch {
            print("debug-script: duplicate fail could not be set: \(error)")
        }
    }

    /// `print copies`: the list with each item's name as the grid shows it
    /// (copies marked `*`), the focus and selection, whether Duplicate can
    /// run, the copy marks the cells on screen draw, and in the loupe the
    /// window title and the caption's Copy badge.
    static func printCopies(_ model: LibraryModel, window: NSWindow?) {
        let names = model.items.prefix(14).enumerated().map { index, item in
            "\(index):'\(PhotoName.display(item))'" + (item.isCopy ? "*" : "") + ":\(item.rating.rawValue)"
                + (item.representsPair ? ":pair" : "")
        }
        print("debug-script: copies items \(model.items.count) [" + names.joined(separator: " ") + "]")
        let selection = model.actionTargets.map(String.init).joined(separator: ",")
        var line = "debug-script: copies focus \(model.focusIndex.map(String.init) ?? "-") targets [\(selection)]"
        line += " canDuplicate \(model.canDuplicateTargets) duplicating \(model.isDuplicating)"
        line += " subtitle '\(model.windowSubtitle)' library \(model.libraryCount)"
        print(line)
        if let grid = window.flatMap({ descendant(of: PhotoCollectionView.self, in: $0.contentView) }) {
            let marked = grid.indexPathsForVisibleItems().sorted().compactMap { path -> String? in
                guard let view = grid.item(at: path)?.view as? PhotoCellView, view.showsCopyMark else { return nil }
                let frame = view.copyMarkFrame
                return "\(path.item)@\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
            }
            print("debug-script: copies grid marks [" + marked.joined(separator: " ") + "]")
        }
        if let strip = window.flatMap({ descendant(of: FilmStripCollectionView.self, in: $0.contentView) }) {
            let marked = strip.indexPathsForVisibleItems().sorted().compactMap { path -> String? in
                guard let view = strip.item(at: path)?.view as? FilmStripCellView, view.showsCopyMark else { return nil }
                return "\(path.item) tip '\(view.toolTip ?? "")'"
            }
            print("debug-script: copies strip marks [" + marked.joined(separator: " | ") + "]")
        }
        if model.mode == .loupe, let item = model.focusedItem {
            let badge = item.isCopy ? "'\(DuplicateText.badge)' help '\(DuplicateText.badgeHelp(item.fileName))'" : "none"
            print("debug-script: copies loupe title '\(model.windowTitle)' badge \(badge)")
        }
    }

    private static func descendant<V: NSView>(of type: V.Type, in view: NSView?) -> V? {
        guard let view else { return nil }
        if let match = view as? V { return match }
        for subview in view.subviews {
            if let match = descendant(of: type, in: subview) { return match }
        }
        return nil
    }
}
