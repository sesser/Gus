import AppKit
import PhotoCore
import PhotoUI

/// The debug script's HDR merge commands (see `DebugScript`; hdr-merge design §14):
///
///     merge sheet                  (File ▸ Merge to HDR…: waits for the frames and the disk's answer, then
///                                   prints the frames, the reference, the message and flagged frames, the
///                                   name, folder and the formats offered)
///     merge format tiff|dng        (the sheet's format: prints the Name line and caption)
///     merge start [nowait]         (presses Merge: prints the job; waits for the end unless nowait, so its
///                                   undo step lands in this command's group)
///     merge wait                   (waits for the running merge: prints the result row, or "stopped")
///     merge stop                   (the popover's Stop: prints the Activity row)
///     merge cancelsheet            (presses Cancel: prints whether a job runs)
///     print merge                  (running or not, step, detail, fraction, whether Merge is on and why
///                                   not, the selection)
@MainActor
enum DebugMergeCommands {
    static func run(_ words: [String], model: LibraryModel) async {
        let merge = model.merge
        switch words.first {
        case "sheet":
            merge.begin()
            for _ in 0..<400 where merge.diskCheck == nil {
                try? await Task.sleep(for: .milliseconds(25))
            }
            for _ in 0..<80 where merge.resultName == nil && merge.refusal == nil {
                try? await Task.sleep(for: .milliseconds(25))
            }
            printSheet(model)
        case "format":
            merge.format = words.dropFirst().first == "dng" ? .dng : .tiff
            let before = merge.resultName
            for _ in 0..<80 where merge.resultName == before {
                try? await Task.sleep(for: .milliseconds(25))
            }
            print("debug-script: merge format \(merge.format.rawValue) name \(merge.resultName ?? "-") caption "
                  + (merge.format == .tiff ? MergeText.tiffCaption : MergeText.dngCaption))
        case "start":
            let canStart = merge.canStart
            merge.start()
            try? await Task.sleep(for: .milliseconds(100))
            print("debug-script: merge start \(canStart) job merge title \(MergeText.jobTitle(merge.jobName ?? "-"))"
                  + " detail \(merge.progress.map { MergeText.detail($0.phase) } ?? "-")")
            if words.dropFirst().first != "nowait" { await waitForEnd(model) }
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
            print("debug-script: merge sheet|format|start|wait|stop|cancelsheet")
        }
    }

    static func waitForEnd(_ model: LibraryModel) async {
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
        let disk = switch merge.diskCheck {
        case nil: "checking"
        case .clear: "clear"
        case .refused: "refused"
        }
        print("debug-script: merge message \(merge.refusal.map(MergeText.refusal) ?? "none")"
              + "; note \(selection.sameExposure ? MergeText.sameExposureNote : "none"); disk \(disk)")
        print("debug-script: merge name \(merge.resultName ?? "-") folder \(selection.referenceFrame.folder.path)"
              + " formats tiff dng (dng offered true) format \(merge.format.rawValue) merge on \(merge.canStart)")
    }

    static func printState(_ model: LibraryModel) {
        let merge = model.merge
        let reason = model.actionTargets.count < MergeLimits.minFrames ? "fewer than two"
            : merge.isMerging ? "running" : (model.otherModalIsUp || model.showsPresetSheet) ? "sheet up" : "none"
        let selected = model.selection.map { PhotoName.display(model.items[$0]) }
        print("debug-script: merge running \(merge.isMerging) phase \(merge.progress.map { MergeText.detail($0.phase) } ?? "-")"
              + " fraction \(merge.progress.map { String(format: "%.3f", $0.fraction) } ?? "-")"
              + " canMerge \(model.canMerge) reason \(reason) selection \(selected)"
              + " focus \(model.focusedItem.map(PhotoName.display) ?? "-")")
    }
}
