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

    /// The Amount slider or its field, shown in Manual only. A change that
    /// switches on a group never switched on (a script, a typed value) starts
    /// it in Manual where Auto can't apply, as Constrain to image does (DQ-4).
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
    /// The photos are the command's targets when it starts, and `body` gets
    /// them: the question and the change are about the same photos whatever
    /// is selected or open when the answer comes (code review C11).
    ///
    /// The loupe's photo alone is decided at once from the editor, which holds
    /// its saved values and its file's state: the change then registers its
    /// undo step before this returns, so ⌘Z right after ⌘V undoes it (code
    /// review C3). A selection is read off the main actor on a task of its own
    /// (`lensQuestionTask`), which never touches another batch (Auto Exposure,
    /// a measuring paste; code review C10): the saved stacks, then, only for
    /// photos with masks or spots whose Distortion uses Auto, their files, four
    /// at a time, with an Activity row under the command's title (design DQ-5).
    /// Stop on that row, or a newer paste or preset, ends it and writes nothing.
    func confirmingLensFrameChange(actionName: String, toolbarTitle: String? = nil,
                                   _ transform: @escaping @Sendable (Adjustments) -> Adjustments,
                                   then body: @escaping @MainActor ([CatalogItem]) -> Void) {
        // One question at a time (code review Q3): a paste or preset while it is up does nothing.
        guard !editor.isAskingLensFrame else { return }
        // A newer command ends an older one's pending read, whichever path it takes (owner ruling, C13).
        endPendingLensRead()
        let commandTargets = actionTargets.map { items[$0] }
        let targets = commandTargets.filter { !$0.isVideo }
        guard !targets.isEmpty else { return body(commandTargets) }
        let open = editor.state == .ready ? editor.item?.versionID : nil
        if targets.count == 1, let open, targets[0].versionID == open {
            let before = editor.savedAdjustments
            guard editor.asksLensFrameQuestion(from: before, to: transform(before)) else { return body(commandTargets) }
            let run = lensQuestionRun.begin()
            lensQuestionTask = Task {
                defer { if lensQuestionRun.owns(run) { lensQuestionTask = nil } }
                await askLensFrameQuestion(affected: 1, of: 1, includesOpen: true, run: run) { body(commandTargets) }
            }
            return
        }
        let catalog = self.catalog
        let writes = self.writes
        let sources = Dictionary(uniqueKeysWithValues: targets.map { ($0.versionID, sourceURL(for: $0)) })
        let openLens = editor.lensState
        let openAnswer = editor.lensFrameAnswer
        let run = lensQuestionRun.begin()
        lensQuestionTask = Task {
            defer {
                if lensQuestionRun.owns(run) {
                    setLensReadProgress(nil)
                    lensQuestionTask = nil
                }
            }
            // After pending saves, as the change itself reads them.
            let stored: StoredEditStacks
            do {
                stored = try await writes.savedEditStacks(forVersions: targets.map(\.versionID), in: catalog)
            } catch is CancellationError {
                // Stopped, or a newer command took over: nothing is written (code review C12).
                return
            } catch {
                // The change reads them again and reports what it can't.
                guard lensQuestionRun.owns(run) else { return }
                return body(commandTargets)
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
                // Only while this read is the current one: a replaced read leaves no row (review F9).
                guard lensQuestionRun.owns(run) else { return }
                setLensReadProgress((0, reads.count), title: actionName, toolbarTitle: toolbarTitle)
                var done = 0
                for chunk in stride(from: 0, to: reads.count, by: 4).map({ Array(reads[$0..<min($0 + 4, reads.count)]) }) {
                    guard !Task.isCancelled, lensQuestionRun.owns(run) else { return }
                    await withTaskGroup(of: (Int64, CameraLensState).self) { group in
                        for (id, url) in chunk { group.addTask { (id, await Self.readLensState(url)) } }
                        for await (id, state) in group { lenses[id] = state }
                    }
                    done += chunk.count
                    guard lensQuestionRun.owns(run) else { return }
                    setLensReadProgress((done, reads.count), title: actionName, toolbarTitle: toolbarTitle)
                }
            }
            guard !Task.isCancelled, lensQuestionRun.owns(run) else { return }
            setLensReadProgress(nil)
            let affected = candidates.filter { candidate in
                let lens = lenses[candidate.id]
                return LensCorrectionPlan(candidate.before.effective, lens: lens)
                    .movesFrame(comparedWith: LensCorrectionPlan(candidate.after.effective, lens: lens))
            }.count
            guard affected > 0 else { return body(commandTargets) }
            await askLensFrameQuestion(affected: affected, of: targets.count,
                                       includesOpen: open.map { sources.keys.contains($0) } ?? false, run: run) {
                body(commandTargets)
            }
        }
    }

    /// Ends a paste's or preset's pending read for the frame question: nothing
    /// is written for it and its Activity row goes. Every paste and preset
    /// calls it first, whether or not it reads or asks (owner ruling on code
    /// review C13), and not while the question is up (then the new command does
    /// nothing).
    func endPendingLensRead() {
        guard lensQuestionTask != nil || lensReadProgress != nil else { return }
        lensQuestionTask?.cancel()
        lensQuestionTask = nil
        _ = lensQuestionRun.begin()
        setLensReadProgress(nil)
    }

    /// Asks; on Change runs `body` unless a newer command took over (`run`).
    private func askLensFrameQuestion(affected: Int, of total: Int, includesOpen: Bool, run: Int,
                                      then body: @MainActor () -> Void) async {
        // A read ended before its task ran (a newer paste or preset in the same
        // turn) shows no question (code review C16).
        guard lensQuestionRun.owns(run), !Task.isCancelled else { return }
        editor.markAskingLensFrame(true)
        let alert = AdjustmentEditor.lensFrameAlert(affected: affected, of: total)
        let response = await WindowModal.run(alert, in: windowObserver.window)
        editor.markAskingLensFrame(false)
        guard response == .alertFirstButtonReturn, lensQuestionRun.owns(run) else { return }
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
