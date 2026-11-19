import AppKit
import PhotoCore
import PhotoUI

/// The Distortion and Lens Vignetting groups' changes (docs/features/
/// lens-corrections/design.md §3) and the question asked before a change
/// that moves the frame of a photo with masks or spots (§6). Each change is
/// one undo step; one that also switches its group on is the same step.
extension AdjustmentEditor {
    typealias LensGroup = LensCorrectionStatus.Group

    /// What the group shows for the open photo. Never compiles the kernels
    /// on the main actor (code review C1): until their compile has finished
    /// they count as available, and `lensKernelsRevision` redraws the group
    /// when it does.
    func lensStatus(_ group: LensGroup) -> LensCorrectionStatus {
        _ = lensKernelsRevision
        return LensCorrectionStatus(group, values: adjustments, lens: lensState,
                                    kernelsAvailable: !AdjustmentRenderer.lensCorrectionKernelsKnownUnavailable)
    }

    /// The group's check box. Checking a group on a file where Auto can't
    /// apply starts it in Manual, in the same step (design §3.2, RI-5).
    func toggleLensGroup(_ group: LensGroup) {
        let status = lensStatus(group)
        let adjustmentGroup = group.adjustmentGroup
        guard !status.isChecked else {
            setEnabled(adjustmentGroup, false)
            return
        }
        let title = AdjustText.title(adjustmentGroup)
        change(String(localized: "Turn On \(title)", comment: "Undo action name; the group's name"), phase: .committed) { values in
            values.setEnabled(adjustmentGroup, true)
            guard status.startsInManual else { return }
            switch group {
            case .distortion: values.distortion.source = .manual
            case .vignetting: values.lensVignetting.source = .manual
            }
        }
        announceStatus(group)
    }

    /// A Source segment. A dimmed Auto can't be chosen (design §3.2).
    func setLensSource(_ group: LensGroup, _ source: LensCorrectionSource) {
        if source == .auto, lensStatus(group).autoUnavailable != nil { return }
        // Off: the segment turns the group on (PRD R15); on with that source: nothing.
        guard let next = adjustments.choosingLensSource(group.adjustmentGroup, source) else { return }
        change(LensCorrectionText.sourceUndoName(group), phase: .committed) { $0 = next }
        announceStatus(group)
    }

    /// The Amount slider or its field (Manual).
    /// Shown only in Manual; a group never switched on that it switches on
    /// (a script, a typed value) follows DQ-4 as Constrain to image does.
    func setLensAmount(_ group: LensGroup, _ value: Double, phase: EditPhase) {
        let isOn = group == .distortion ? adjustments.distortion.isOn : adjustments.lensVignetting.isOn
        let startsInManual = !isOn && lensStatus(group).startsInManual
        change(LensCorrectionText.amountUndoName(group), phase: phase) { values in
            switch group {
            case .distortion:
                values.distortion.setAmount(value)
                if startsInManual { values.distortion.source = .manual }
            case .vignetting:
                values.lensVignetting.setAmount(value)
                if startsInManual { values.lensVignetting.source = .manual }
            }
        }
    }

    /// Constrain to image (Distortion).
    /// Constrain to image (Distortion). On a group never switched on, it
    /// switches it on (`enableModules`), and where Auto can't apply it starts
    /// in Manual in the same step, as the check box does (design §3.2 DQ-4,
    /// review F2).
    func setConstrainToImage(_ isOn: Bool) {
        guard adjustments.distortion.constrain != isOn else { return }
        let startsInManual = !adjustments.distortion.isOn && lensStatus(.distortion).startsInManual
        change(LensCorrectionText.constrainUndoName(isOn), phase: .committed) { values in
            values.distortion.constrain = isOn
            if startsInManual { values.distortion.source = .manual }
        }
    }

    /// The caption's sentence, once, when acting made a status known (design §11).
    private func announceStatus(_ group: LensGroup) {
        if let sentence = LensCorrectionText.announcement(lensStatus(group).caption, group: group) {
            AccessibilityText.announce(sentence)
        }
    }

    // MARK: The frame question (design §6, R6)

    /// Masks and spots of a photo, whether their groups are on or not.
    func masksAndSpots(_ values: Adjustments) -> Int {
        values.local.masks.count + values.spots.spots.count
    }

    /// A commit from `previous` to `next` asks first: it moves the corrected
    /// frame of a photo that has masks or spots, and the question was not
    /// answered on this visit since the last one was added.
    func asksLensFrameQuestion(from previous: Adjustments, to next: Adjustments) -> Bool {
        let count = max(masksAndSpots(previous), masksAndSpots(next))
        guard count > 0, lensFrameAnswer.map({ count > $0 }) ?? true else { return false }
        let before = LensCorrectionPlan(previous.effective, lens: lensState)
        let after = LensCorrectionPlan(next.effective, lens: lensState)
        return before.movesFrame(comparedWith: after)
    }

    /// Puts the question up on the library window; the change on screen waits
    /// for the answer (`finishLensFrameQuestion`).
    func askLensFrameQuestion(_ actionName: String, versionID: Int64) {
        isAskingLensFrame = true
        let alert = Self.lensFrameAlert(affected: 1, of: 1)
        let window = library?.windowObserver.window
        Task {
            let response = await WindowModal.run(alert, in: window)
            finishLensFrameQuestion(change: response == .alertFirstButtonReturn, actionName: actionName, versionID: versionID)
        }
    }

    /// The question's alert: Change (default, Return), Cancel (Esc, ⌘.).
    static func lensFrameAlert(affected: Int, of total: Int) -> NSAlert {
        let alert = NSAlert()
        if total > 1 {
            alert.messageText = LensCorrectionText.frameQuestionTitleMany
            alert.informativeText = LensCorrectionText.frameQuestionMessage(affected: affected, of: total)
        } else {
            alert.messageText = LensCorrectionText.frameQuestionTitle
            alert.informativeText = LensCorrectionText.frameQuestionMessage
        }
        // Change is the default (Return; NSAlert makes its first button the
        // sheet's default button): the person chose the change and it can be
        // undone (design §6). The button titled Cancel takes Esc and ⌘.
        alert.addButton(withTitle: LensCorrectionText.change)
        alert.addButton(withTitle: LensCorrectionText.cancel)
        return alert
    }
}

extension LibraryModel {
    /// Runs `body` (a paste or a preset, `actionName`) after asking the frame
    /// question once for the whole command, with counts, when it would move
    /// the corrected frame of photos that have masks or spots (design §6, AC6).
    /// Cancel runs nothing.
    ///
    /// The loupe's photo alone is decided at once from the editor, which holds
    /// its saved values and its file's state: the change then registers its
    /// undo step before this returns, so ⌘Z right after ⌘V undoes it (code
    /// review C3). A selection is read off the main actor: the saved stacks,
    /// then, only for photos with masks or spots whose Distortion uses Auto,
    /// their files, four at a time with progress in Activity under the
    /// command's title; Stop there, or a newer paste or preset, ends it
    /// (`batchAutoTask`, code review C2).
    func confirmingLensFrameChange(actionName: String, _ transform: @escaping @Sendable (Adjustments) -> Adjustments,
                                   then body: @escaping @MainActor () -> Void) {
        // One question at a time (code review Q3): a paste or preset while it is up does nothing.
        guard !editor.isAskingLensFrame else { return }
        let targets = actionTargets.map { items[$0] }.filter { !$0.isVideo }
        guard !targets.isEmpty else { return body() }
        let open = editor.state == .ready ? editor.item?.versionID : nil
        if targets.count == 1, let open, targets[0].versionID == open {
            let before = editor.savedAdjustments
            guard editor.asksLensFrameQuestion(from: before, to: transform(before)) else { return body() }
            Task { await askLensFrameQuestion(affected: 1, of: 1, includesOpen: true, run: nil, then: body) }
            return
        }
        let catalog = self.catalog
        let writes = self.writes
        let sources = Dictionary(uniqueKeysWithValues: targets.map { ($0.versionID, sourceURL(for: $0)) })
        let openLens = editor.lensState
        let openAnswer = editor.lensFrameAnswer
        batchAutoTask?.cancel()
        let run = batchAutoRun.begin()
        batchAutoTask = Task {
            defer {
                if batchAutoRun.owns(run) {
                    setBatchAutoProgress(nil)
                    batchAutoTask = nil
                }
            }
            // After pending saves, as the change itself reads them.
            guard let stored = try? await writes.savedEditStacks(forVersions: targets.map(\.versionID), in: catalog) else {
                return body()
            }
            let candidates = await Task.detached(priority: .userInitiated) {
                Self.frameCandidates(stored.stacks, transform: transform, open: open, openAnswer: openAnswer)
            }.value
            // Files are read only where Auto could make a difference.
            let reads = candidates.filter { $0.usesAuto && $0.id != open }.compactMap { candidate in
                (sources[candidate.id] ?? nil).map { (candidate.id, $0) }
            }
            var lenses: [Int64: CameraLensState] = [:]
            if let open { lenses[open] = openLens }
            if !reads.isEmpty {
                setBatchAutoProgress((0, reads.count), title: actionName)
                for chunk in stride(from: 0, to: reads.count, by: 4).map({ Array(reads[$0..<min($0 + 4, reads.count)]) }) {
                    guard !Task.isCancelled, batchAutoRun.owns(run) else { return }
                    await withTaskGroup(of: (Int64, CameraLensState).self) { group in
                        for (id, url) in chunk { group.addTask { (id, await Self.readLensState(url)) } }
                        for await (id, state) in group { lenses[id] = state }
                    }
                    setBatchAutoProgress((min(lenses.count, reads.count), reads.count), title: actionName)
                }
            }
            guard !Task.isCancelled, batchAutoRun.owns(run) else { return }
            let affected = candidates.filter { candidate in
                let lens = lenses[candidate.id]
                return LensCorrectionPlan(candidate.before.effective, lens: lens)
                    .movesFrame(comparedWith: LensCorrectionPlan(candidate.after.effective, lens: lens))
            }.count
            setBatchAutoProgress(nil)
            guard affected > 0 else { return body() }
            await askLensFrameQuestion(affected: affected, of: targets.count,
                                       includesOpen: open.map { sources.keys.contains($0) } ?? false, run: run, then: body)
        }
    }

    /// Asks; on Change runs `body` unless a newer command took over (`run`).
    private func askLensFrameQuestion(affected: Int, of total: Int, includesOpen: Bool, run: Int?,
                                      then body: @MainActor () -> Void) async {
        editor.markAskingLensFrame(true)
        let alert = AdjustmentEditor.lensFrameAlert(affected: affected, of: total)
        let response = await WindowModal.run(alert, in: windowObserver.window)
        editor.markAskingLensFrame(false)
        guard response == .alertFirstButtonReturn, run.map(batchAutoRun.owns) ?? true else { return }
        if includesOpen { editor.noteLensFrameAnswered() }
        body()
    }

    /// A target that holds masks or spots, with its values before and after.
    struct FrameCandidate: Sendable {
        var id: Int64
        var before: Adjustments
        var after: Adjustments
        /// Distortion uses Auto before or after: its file decides what moves.
        var usesAuto: Bool
    }

    nonisolated static func frameCandidates(_ stacks: [Int64: EditStack], transform: (Adjustments) -> Adjustments,
                                            open: Int64?, openAnswer: Int?) -> [FrameCandidate] {
        stacks.compactMap { id, stack in
            let before = Adjustments(stack: stack)
            let after = transform(before)
            let count = max(before.local.masks.count + before.spots.spots.count,
                            after.local.masks.count + after.spots.spots.count)
            guard count > 0 else { return nil }
            if id == open, let openAnswer, count <= openAnswer { return nil }
            let usesAuto = (before.distortion.isOn && before.distortion.source == .auto)
                || (after.distortion.isOn && after.distortion.source == .auto)
            return FrameCandidate(id: id, before: before, after: after, usesAuto: usesAuto)
        }
    }

    /// One file's lens state, off the main actor (`CameraLensState.read`).
    nonisolated static func readLensState(_ url: URL) async -> CameraLensState {
        CameraLensState.read(url)
    }
}

extension AdjustmentEditor {
    func markAskingLensFrame(_ isAsking: Bool) {
        isAskingLensFrame = isAsking
    }

    /// A paste or preset reaching the open photo was confirmed: asked on this
    /// visit, for the masks and spots it has (a paste never brings any).
    func noteLensFrameAnswered() {
        lensFrameAnswer = masksAndSpots(adjustments)
    }
}
