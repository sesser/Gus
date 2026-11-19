import AppKit
import PhotoCore
import PhotoUI

/// The Distortion and Lens Vignetting groups' changes (docs/features/
/// lens-corrections/design.md §3) and the question asked before a change
/// that moves the frame of a photo with masks or spots (§6). Each change is
/// one undo step; one that also switches its group on is the same step.
extension AdjustmentEditor {
    typealias LensGroup = LensCorrectionStatus.Group

    /// What the group shows for the open photo.
    func lensStatus(_ group: LensGroup) -> LensCorrectionStatus {
        LensCorrectionStatus(group, values: adjustments, lens: lensState,
                             kernelsAvailable: AdjustmentRenderer.lensCorrectionKernelsAvailable)
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

    /// A Source segment. The selected one again changes nothing; a dimmed
    /// Auto can't be chosen (design §3.2).
    func setLensSource(_ group: LensGroup, _ source: LensCorrectionSource) {
        let status = lensStatus(group)
        if source == .auto, status.autoUnavailable != nil { return }
        let current = group == .distortion ? adjustments.distortion.source : adjustments.lensVignetting.source
        guard current != source || !status.isChecked else { return }
        change(LensCorrectionText.sourceUndoName(group), phase: .committed) { values in
            switch group {
            case .distortion: values.distortion.source = source
            case .vignetting: values.lensVignetting.source = source
            }
            values.setEnabled(group.adjustmentGroup, true)
        }
        announceStatus(group)
    }

    /// The Amount slider or its field (Manual).
    func setLensAmount(_ group: LensGroup, _ value: Double, phase: EditPhase) {
        change(LensCorrectionText.amountUndoName(group), phase: phase) { values in
            switch group {
            case .distortion: values.distortion.setAmount(value)
            case .vignetting: values.lensVignetting.setAmount(value)
            }
        }
    }

    /// Constrain to image (Distortion).
    func setConstrainToImage(_ isOn: Bool) {
        guard adjustments.distortion.constrain != isOn else { return }
        change(LensCorrectionText.constrainUndoName(isOn), phase: .committed) { $0.distortion.constrain = isOn }
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
        // The first button is the default (Return); one titled Cancel takes Esc.
        alert.addButton(withTitle: LensCorrectionText.change)
        alert.addButton(withTitle: LensCorrectionText.cancel)
        return alert
    }
}

extension LibraryModel {
    /// Runs `body` (a paste or a preset) after asking the frame question once
    /// for the whole command, with counts, when it would move the corrected
    /// frame of photos that have masks or spots (design §6, AC6). Cancel runs
    /// nothing. Never asked again on the loupe's photo once answered on this
    /// visit; the answer counts as one for it.
    func confirmingLensFrameChange(_ transform: @escaping @Sendable (Adjustments) -> Adjustments,
                                   then body: @escaping @MainActor () -> Void) {
        let targets = actionTargets.map { items[$0] }.filter { !$0.isVideo }
        guard !targets.isEmpty else { return body() }
        let catalog = self.catalog
        let writes = self.writes
        let sources = Dictionary(uniqueKeysWithValues: targets.map { ($0.versionID, sourceURL(for: $0)) })
        let open = editor.state == .ready ? editor.item?.versionID : nil
        let openLens = editor.lensState
        let openAnswer = editor.lensFrameAnswer
        lensQuestionTask = Task {
            defer { lensQuestionTask = nil }
            // After pending saves, as the change itself reads them.
            guard let stored = try? await writes.savedEditStacks(forVersions: targets.map(\.versionID), in: catalog) else {
                return body()
            }
            let stacks = stored.stacks
            let affected = await Task.detached(priority: .userInitiated) {
                stacks.filter { id, stack in
                    let before = Adjustments(stack: stack)
                    let after = transform(before)
                    let count = max(before.local.masks.count + before.spots.spots.count,
                                    after.local.masks.count + after.spots.spots.count)
                    guard count > 0 else { return false }
                    if id == open, let answer = openAnswer, count <= answer { return false }
                    // The file is read only where Auto could make a difference.
                    let usesAuto = (before.distortion.isOn && before.distortion.source == .auto)
                        || (after.distortion.isOn && after.distortion.source == .auto)
                    let lens: CameraLensState? = if id == open { openLens } else if usesAuto, let url = sources[id] ?? nil {
                        Self.lensState(of: url)
                    } else { nil }
                    return LensCorrectionPlan(before.effective, lens: lens)
                        .movesFrame(comparedWith: LensCorrectionPlan(after.effective, lens: lens))
                }.count
            }.value
            guard affected > 0, !Task.isCancelled else { return body() }
            editor.markAskingLensFrame(true)
            let alert = AdjustmentEditor.lensFrameAlert(affected: affected, of: targets.count)
            let response = await WindowModal.run(alert, in: windowObserver.window)
            editor.markAskingLensFrame(false)
            guard response == .alertFirstButtonReturn else { return }
            if let open, sources.keys.contains(open) { editor.noteLensFrameAnswered() }
            body()
        }
    }

    /// The lens state of a master as its renders read it (`CameraLensState`).
    nonisolated static func lensState(of url: URL) -> CameraLensState {
        let defaults = SupportedFormats.isRaw(pathExtension: url.pathExtension) ? RawDefaults(source: url) : nil
        return CameraLensState.read(url, systemDecodes: defaults != nil, decoderCorrects: defaults?.lensCorrectedByDecoder ?? false)
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
