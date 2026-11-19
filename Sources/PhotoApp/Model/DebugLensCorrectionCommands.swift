import AppKit
import PhotoCore

/// The debug script's commands for Distortion and Lens Vignetting
/// (docs/features/lens-corrections/design.md §16): `lens print`, `lens
/// distortion …` and `lens vignetting …` (through the controls' own paths,
/// so the frame question comes up as it would; answer it with `alert press`),
/// and `lens force kernelfail|tablecorrupt|off`.
@MainActor
enum DebugLensCorrectionCommands {
    /// `lens distortion|vignetting …` changes the photo at once: its own undo
    /// group. Not when the change will ask the frame question first: its step
    /// is then registered by `alert press Change` (in that command's group),
    /// and an empty group here would be an undo step that does nothing.
    static func changesPhoto(_ words: [String], editor: AdjustmentEditor) -> Bool {
        // A paste: its own group, and the loop waits for its read (it may ask instead).
        if words.first == "lens", words.dropFirst().first == "pastethenfocus" { return true }
        guard words.first == "lens", ["distortion", "vignetting"].contains(words.dropFirst().first ?? "") else { return false }
        guard let next = predicted(Array(words.dropFirst()), editor: editor) else { return true }
        // A change that changes nothing records nothing (an empty group would be an undo step).
        guard next != editor.adjustments else { return false }
        return !editor.asksLensFrameQuestion(from: editor.savedAdjustments, to: next)
    }

    /// The values a `lens distortion|vignetting …` command leaves on screen.
    private static func predicted(_ words: [String], editor: AdjustmentEditor) -> Adjustments? {
        let group: LensCorrectionStatus.Group = words.first == "distortion" ? .distortion : .vignetting
        let status = editor.lensStatus(group)
        var next = editor.adjustments
        switch (words.dropFirst().first, words.dropFirst(2).first.flatMap(Double.init)) {
        case ("on", _):
            next.setEnabled(group.adjustmentGroup, true)
            if status.startsInManual {
                if group == .distortion { next.distortion.source = .manual } else { next.lensVignetting.source = .manual }
            }
        case ("off", _): next.setEnabled(group.adjustmentGroup, false)
        case ("auto", _), ("manual", _):
            let source: LensCorrectionSource = words.dropFirst().first == "auto" ? .auto : .manual
            if group == .distortion { next.distortion.source = source } else { next.lensVignetting.source = source }
            next.setEnabled(group.adjustmentGroup, true)
        case ("amount", let value?):
            let isOn = group == .distortion ? next.distortion.isOn : next.lensVignetting.isOn
            if group == .distortion { next.distortion.setAmount(value) } else { next.lensVignetting.setAmount(value) }
            if !isOn, status.startsInManual {
                if group == .distortion { next.distortion.source = .manual } else { next.lensVignetting.source = .manual }
            }
        case ("constrain", _):
            if !next.distortion.isOn, status.startsInManual { next.distortion.source = .manual }
            next.distortion.constrain = words.dropFirst(2).first == "on"
        default: return nil
        }
        next.enableModules(changedFrom: editor.adjustments)
        return next
    }

    static func run(_ words: [String], model: LibraryModel) async {
        let editor = model.editor
        switch words.first {
        case "print":
            printState(editor)
        case "pastethenfocus":
            // Paste Adjustments, then at once another photo selected, before the
            // command's read of its targets ends: the question and the change must
            // still be about the photos selected when it started (code review C11).
            let name = words.dropFirst().joined(separator: " ")
            let before = model.actionTargetVersionIDs
            model.pasteAdjustments()
            if let index = model.items.firstIndex(where: { PhotoName.display($0) == name }) { model.setFocus(index) }
            print("debug-script: lens pasted onto \(before.count), now selected \(model.actionTargetVersionIDs.count)")
            await DebugScript.waitForBatchWork(model)
        case "force":
            switch words.dropFirst().first {
            case "kernelfail": LensCorrectionDebug.fault = .kernelFailure
            case "tablecorrupt": LensCorrectionDebug.fault = .tableCorrupt
            default: LensCorrectionDebug.fault = nil
            }
            // The file's state is read with the photo: read it again.
            editor.reload()
            for _ in 0..<100 where editor.state != .ready { try? await Task.sleep(for: .milliseconds(50)) }
            print("debug-script: lens force \(LensCorrectionDebug.fault?.rawValue ?? "off")")
        case "distortion", "vignetting":
            let group: LensCorrectionStatus.Group = words.first == "distortion" ? .distortion : .vignetting
            let rest = Array(words.dropFirst())
            switch (rest.first, rest.dropFirst().first) {
            case ("on", _), ("off", _):
                if editor.lensStatus(group).isChecked != (rest.first == "on") { editor.toggleLensGroup(group) }
            case ("auto", _): editor.setLensSource(group, .auto)
            case ("manual", _): editor.setLensSource(group, .manual)
            case ("amount", let value?):
                guard let amount = Double(value) else { break }
                // A drag: frames while it moves, then the commit, where the question is asked.
                editor.setLensAmount(group, amount, phase: .changing)
                try? await Task.sleep(for: .milliseconds(100))
                editor.setLensAmount(group, amount, phase: .committed)
            case ("constrain", let value?) where group == .distortion:
                editor.setConstrainToImage(value == "on")
            default:
                print("debug-script: unknown lens \(words.joined(separator: " "))")
            }
            try? await Task.sleep(for: .milliseconds(400))
            if editor.isAskingLensFrame { print("debug-script: lens asking") }
        default:
            print("debug-script: unknown lens \(words.first ?? "")")
        }
    }

    static func printState(_ editor: AdjustmentEditor) {
        let plan = LensCorrectionPlan(editor.adjustments.effective, lens: editor.lensState)
        print("debug-script: lens state \(describe(editor.lensState)) kernels \(!AdjustmentRenderer.lensCorrectionKernelsKnownUnavailable)"
              + " asking \(editor.isAskingLensFrame) answered \(editor.lensFrameAnswer.map(String.init) ?? "no")"
              + " warp \(plan.warp != nil) gain \(plan.gain != nil)")
        for group in LensCorrectionStatus.Group.allCases {
            let status = editor.lensStatus(group)
            let values = editor.adjustments
            let (isOn, source, amount) = group == .distortion
                ? (values.distortion.isOn, values.distortion.source, values.distortion.amount)
                : (values.lensVignetting.isOn, values.lensVignetting.source, values.lensVignetting.amount)
            let constrain = group == .distortion ? " constrain \(values.distortion.constrain)" : ""
            let applies = group == .distortion ? plan.warp != nil : plan.gain != nil
            print("debug-script: lens \(group.rawValue) on \(isOn) checked \(status.isChecked) applies \(applies)"
                  + " source \(source.rawValue) amount \(amount)\(constrain) row \(status.caption.rawValue)"
                  + " segment \(status.selectedSegment.map(String.init) ?? "none")"
                  + " autoEnabled \(status.autoUnavailable == nil) autoUnavailable \(status.autoUnavailable?.rawValue ?? "-")"
                  + " amountShown \(status.showsAmount) warning \(status.caption.isWarning)")
            print("debug-script: lens \(group.rawValue) caption \(LensCorrectionText.caption(status.caption, group: group))")
        }
    }

    static func describe(_ state: CameraLensState?) -> String {
        switch state {
        case nil: "unknown"
        case .notRaw: "notRaw"
        case .decoderCorrects: "decoderCorrects"
        case .builtInCorrection: "builtInCorrection"
        case .unreadable: "unreadable"
        case .tables(let tables):
            "tables(\(tables.origin?.rawValue ?? "none") distortion \(tables.distortion != nil) vignetting \(tables.vignetting != nil))"
        }
    }
}
