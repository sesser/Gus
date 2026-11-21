import AppKit
import PhotoCore
import PhotoUI

/// The debug script's HDR merge commands (see `DebugScript`; hdr-merge design §14):
///
///     merge sheet                  (File ▸ Merge to HDR…: waits for the frames and the disk's answer, then
///                                   prints the frames, the reference, the message and flagged frames, the
///                                   name, folder, the formats offered, Auto-align and De-ghost, and the
///                                   sheet's measured height: the Form's content against what it shows)
///     merge format tiff|dng        (the sheet's format: prints the Name line and caption)
///     merge reference <name|row> [nowait]
///                                  (chooses the reference as a click on its row does; row counts from 1:
///                                   prints the reference, Name, Folder, message and flagged frames, whether
///                                   Merge is on once the folder is asked, the answers discarded since the
///                                   sheet opened (they came for a superseded reference), and the VoiceOver
///                                   announcement; nowait returns at once)
///     merge align on|off           (the Auto-align box: prints both boxes)
///     merge deghost on|off         (the De-ghost box: prints both boxes)
///     merge slowdisk <ms>          (adds a delay to each folder check, to see a superseded answer)
///     merge table select <row>|deselect
///                                  (selects a row of the sheet's table, or clears its selection, through
///                                   AppKit, as a click or ⌘-click does: prints the table's selected row and
///                                   the reference after)
///     merge start [nowait]         (presses Merge: prints the job; waits for the end unless nowait, so its
///                                   undo step lands in this command's group)
///     merge wait                   (waits for the running merge: prints the result row, or "stopped")
///     merge stop                   (the popover's Stop: prints the Activity row)
///     merge cancelsheet            (presses Cancel: prints whether a job runs)
///     print merge                  (running or not, step, detail, fraction, whether Merge is on and why
///                                   not, the selection, File ▸ Stop's job, whether a removal may start,
///                                   the undo action name)
@MainActor
enum DebugMergeCommands {
    static func run(_ words: [String], model: LibraryModel) async {
        let merge = model.merge
        let argument = words.dropFirst().first
        switch words.first {
        case "sheet":
            // A sheet closed just before still counts as up until it has gone
            // (the menu item is dimmed meanwhile).
            for _ in 0..<120 where !model.canMerge {
                try? await Task.sleep(for: .milliseconds(25))
            }
            merge.begin()
            await settle(merge)
            // The sheet's window is laid out after it is attached.
            try? await Task.sleep(for: .milliseconds(500))
            printSheet(model)
        case "format":
            merge.format = argument == "dng" ? .dng : .tiff
            await settle(merge)
            print("debug-script: merge format \(merge.format.rawValue) name \(nameLine(merge)) caption "
                  + (merge.format == .tiff ? MergeText.tiffCaption : MergeText.dngCaption))
        case "reference":
            guard let selection = merge.selection, let argument else {
                print("debug-script: merge reference: no sheet or no row")
                return
            }
            let frames = selection.frames
            let frame = Int(argument).flatMap { frames.indices.contains($0 - 1) ? frames[$0 - 1] : nil }
                ?? frames.first { $0.displayName == argument || $0.fileName == argument }
            guard let frame else {
                print("debug-script: merge reference: no frame \(argument)")
                return
            }
            merge.chooseReference(frame.versionID)
            if words.dropFirst(2).first == "nowait" {
                print("debug-script: merge reference \(frame.displayName) chosen; merge on \(merge.canStart)")
                return
            }
            await settle(merge)
            // The announcement waits for its debounce.
            try? await Task.sleep(for: .milliseconds(400))
            printReference(merge)
        case "align", "deghost":
            let on = argument != "off"
            if words.first == "align" { merge.options.align = on } else { merge.options.deghost = on }
            print("debug-script: merge align \(merge.options.align ? "on" : "off") deghost \(merge.options.deghost ? "on" : "off")"
                  + " name \(nameLine(merge)) merge on \(merge.canStart)")
        case "slowdisk":
            merge.debugDiskDelay = .milliseconds(Int(argument ?? "0") ?? 0)
            print("debug-script: merge slowdisk \(merge.debugDiskDelay)")
        case "table":
            await table(Array(words.dropFirst()), merge: merge)
        case "start":
            let canStart = merge.canStart
            let options = merge.options
            merge.start()
            try? await Task.sleep(for: .milliseconds(100))
            print("debug-script: merge start \(canStart) job merge title \(MergeText.jobTitle(merge.jobName ?? "-"))"
                  + " detail \(merge.progress.map { MergeText.detail($0.phase) } ?? "-")"
                  + " align \(options.align ? "on" : "off") deghost \(options.deghost ? "on" : "off")")
            if argument != "nowait" { await waitForEnd(model) }
        case "wait":
            await waitForEnd(model)
        case "stop":
            model.stop(.merge)
            await merge.waitUntilDone()
            print("debug-script: merge stopped; activity \(model.activity.messages.last?.text ?? "-")")
        case "cancelsheet":
            model.showsMergeSheet = false
            try? await Task.sleep(for: .milliseconds(300))
            print("debug-script: merge sheet closed; running \(merge.isMerging)")
        default:
            print("debug-script: merge sheet|format|reference|align|deghost|slowdisk|table|start|wait|stop|cancelsheet")
        }
    }

    /// Waits (up to 10 s) for the frames, the disk's answers for the current
    /// reference and the Name line.
    static func settle(_ merge: MergeModel) async {
        for _ in 0..<400 {
            if let sheet = merge.sheet, sheet.isDiskChecked, merge.resultName?.isFinal == true {
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    static func nameLine(_ merge: MergeModel) -> String {
        guard let name = merge.resultName else { return "-" }
        return name.text + (name.isFinal ? "" : " (unnumbered)")
    }

    static func message(_ merge: MergeModel) -> String {
        let flagged = merge.selection?.frames.filter { merge.flagged.contains($0.versionID) }.map(\.displayName) ?? []
        return "message \(merge.refusal.map(MergeText.refusal) ?? "none") flagged \(flagged.isEmpty ? "none" : flagged.joined(separator: ","))"
    }

    static func printReference(_ merge: MergeModel) {
        guard let sheet = merge.sheet else { return }
        print("debug-script: merge reference \(sheet.reference.displayName) name \(nameLine(merge))"
              + " folder \(sheet.reference.folder.path) \(message(merge)) disk \(sheet.isDiskChecked ? "answered" : "checking")"
              + " merge on \(merge.canStart)")
        print("debug-script: merge discarded \(merge.debugDiscarded.isEmpty ? "none" : merge.debugDiscarded.joined(separator: ","))"
              + " announcement \(merge.debugLastAnnouncement ?? "none")")
    }

    /// The sheet's table, through AppKit: what a click or ⌘-click does to its selection.
    static func table(_ words: [String], merge: MergeModel) async {
        guard let tableView = sheetWindow().flatMap({ views(of: NSTableView.self, in: $0.contentView) .first }) else {
            print("debug-script: merge table: no table in a sheet")
            return
        }
        switch words.first {
        case "select":
            let row = (Int(words.dropFirst().first ?? "1") ?? 1) - 1
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        case "deselect":
            tableView.deselectAll(nil)
        default:
            print("debug-script: merge table select <row>|deselect")
            return
        }
        // SwiftUI updates the binding, the model, then the table again.
        try? await Task.sleep(for: .milliseconds(300))
        await settle(merge)
        let selected = tableView.selectedRowIndexes.map { $0 + 1 }
        print("debug-script: merge table selected \(selected) reference \(merge.sheet?.reference.displayName ?? "-")"
              + " row \((merge.selection?.frames.firstIndex { $0.versionID == merge.referenceID } ?? -1) + 1)")
    }

    static func sheetWindow() -> NSWindow? {
        NSApp.windows.lazy.compactMap(\.attachedSheet).first
    }

    static func views<T: NSView>(of type: T.Type, in view: NSView?) -> [T] {
        guard let view else { return [] }
        let own: [T] = (view as? T).map { [$0] } ?? []
        return own + view.subviews.flatMap { views(of: type, in: $0) }
    }

    /// The sheet's height and its Form's: the scroll view that isn't the
    /// table's, its content against what it shows (design §5.7).
    static func metrics() -> String {
        guard let window = sheetWindow() else { return "sheet not attached" }
        let scrollViews = views(of: NSScrollView.self, in: window.contentView)
            .filter { !($0.documentView is NSTableView) }
        guard let form = scrollViews.max(by: { $0.frame.height < $1.frame.height }) else {
            return "sheet \(Int(window.frame.width))x\(Int(window.frame.height)) form not found"
        }
        let content = form.documentView?.frame.height ?? 0
        let shown = form.contentView.bounds.height
        return "sheet \(Int(window.frame.width))x\(Int(window.frame.height)) (ideal \(Int(MergeSheetMetrics.idealHeight)))"
            + " form content \(Int(content.rounded())) shown \(Int(shown.rounded())) scrolls \(content > shown + 0.5)"
    }

    static func waitForEnd(_ model: LibraryModel) async {
        // The Activity details in the order they showed (design §7.1: no
        // "Aligning" with Auto-align off), and the bar's last value.
        var details: [String] = []
        var fraction = 0.0
        while model.merge.isMerging {
            if let progress = model.merge.progress {
                let detail = MergeText.detail(progress.phase).split(separator: " ").first.map(String.init) ?? ""
                if details.last != detail { details.append(detail) }
                fraction = progress.fraction
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        print("debug-script: merge details \(details.joined(separator: ", ")) last fraction \(String(format: "%.3f", fraction))")
        await model.merge.waitUntilDone()
        // The landing goes through the write chain.
        await withCheckedContinuation { continuation in
            model.writes.afterPendingWrites { continuation.resume() }
        }
        try? await Task.sleep(for: .milliseconds(200))
        let last = model.activity.messages.last
        print("debug-script: merge ended; \(last?.isWarning == true ? "warning" : "row") \(last?.text ?? "-")")
    }

    static func printSheet(_ model: LibraryModel) {
        let merge = model.merge
        guard let selection = merge.selection else {
            print("debug-script: merge sheet shown \(model.showsMergeSheet), frames not read")
            return
        }
        print("debug-script: merge sheet shown \(model.showsMergeSheet) title \(MergeText.sheetTitle(selection.frames.count))")
        for frame in selection.frames {
            let role = frame.versionID == selection.referenceFrame.versionID ? " reference" : ""
            let flag = merge.flagged.contains(frame.versionID) ? " flagged" : ""
            print("debug-script: merge frame \(frame.displayName) \(frame.kind.map(FileKindText.badge) ?? "-")"
                  + " \(MergeText.shutter(frame.exposureTime)) \(MergeText.compensation(frame.exposureCompensation))"
                  + role + flag)
        }
        let disk = merge.sheet.map { !$0.isDiskChecked ? "checking" : $0.diskRefusal == nil ? "clear" : "refused" } ?? "-"
        print("debug-script: merge message \(merge.refusal.map(MergeText.refusal) ?? "none")"
              + "; note \(selection.sameExposure ? MergeText.sameExposureNote : "none"); disk \(disk)")
        print("debug-script: merge name \(nameLine(merge)) folder \(selection.referenceFrame.folder.path)"
              + " formats tiff dng (dng offered true) format \(merge.format.rawValue) merge on \(merge.canStart)")
        print("debug-script: merge align \(merge.options.align ? "on" : "off") deghost \(merge.options.deghost ? "on" : "off")"
              + " caption \(MergeText.referenceCaption(selection.referenceFrame.displayName))")
        print("debug-script: merge metrics \(metrics())")
    }

    static func printState(_ model: LibraryModel) {
        let merge = model.merge
        let reason = model.actionTargets.count < MergeLimits.minFrames ? "fewer than two"
            : merge.isMerging ? "running" : (model.otherModalIsUp || model.showsPresetSheet) ? "sheet up" : "none"
        let selected = model.selection.map { PhotoName.display(model.items[$0]) }
        print("debug-script: merge running \(merge.isMerging) phase \(merge.progress.map { MergeText.detail($0.phase) } ?? "-")"
              + " fraction \(merge.progress.map { String(format: "%.3f", $0.fraction) } ?? "-")"
              + " canMerge \(model.canMerge) reason \(reason) selection \(selected)"
              + " focus \(model.focusedItem.map(PhotoName.display) ?? "-")"
              + " stop \(model.newestStoppableJob.map { "\($0)" } ?? "-") canRemove \(model.canRemoveFromLibrary)"
              + " undo '\(model.undoManager.undoActionName)'")
    }
}
