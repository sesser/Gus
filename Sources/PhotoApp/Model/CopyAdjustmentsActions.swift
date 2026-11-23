import AppKit
import PhotoCore
import PhotoUI

/// The Copy Adjustments sheet while it is up (issue #243, design §3): the
/// photo it copies from, its values frozen when it opened, what is checked,
/// and the header's thumbnail.
@MainActor
@Observable
final class CopySheet {
    let item: CatalogItem
    /// Where the master is, for the spots' frame size at paste time (R8).
    let sourceURL: URL?
    /// The library window's height under its toolbar when the sheet opened:
    /// a shorter window clamps the sheet, and the list scrolls (design §3.8).
    let windowHeight: CGFloat?
    var state: CopySheetState
    private(set) var previewImage: CGImage?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    init(item: CatalogItem, source: Adjustments, sourceURL: URL?, windowHeight: CGFloat? = nil) {
        self.item = item
        self.sourceURL = sourceURL
        self.windowHeight = windowHeight
        state = CopySheetState(source: source)
    }

    func loadPreview(_ request: PreviewRequest?, from previews: PreviewService) {
        guard let request else { return }
        previewTask = Task {
            let image = try? await previews.image(for: request, maxPixelSize: 88)
            guard !Task.isCancelled, let image else { return }
            previewImage = image
        }
    }

    func close() { previewTask?.cancel() }
}

extension LibraryModel {
    // MARK: Copy

    /// Adjust ▸ Copy Adjustments… and its other places (design §2, §7): the
    /// focused item is a photo and no sheet, dialog or alert of the window,
    /// nor the preset manager, is up.
    var canCopyAdjustments: Bool {
        (focusedItem.map { !$0.isVideo } ?? false) && !otherModalIsUp && !showsPresetSheet
    }

    /// Opens the sheet for the focused photo (R1). In the loupe the editor's
    /// saved values are used at once; elsewhere the catalog's, read after
    /// pending saves (a paste just made is in them), and the sheet opens when
    /// they are in. A photo whose edits can't be read opens nothing and says
    /// so in Activity, as before. A second request while that read runs does
    /// nothing.
    func openCopySheet() {
        guard canCopyAdjustments, copySheetRead == nil, let item = focusedItem else { return }
        if let values = editorCopySource(item) {
            presentCopySheet(item, source: values)
            return
        }
        copySheetRead = Task {
            defer { copySheetRead = nil }
            guard let values = await copySource(item), !Task.isCancelled else { return }
            presentCopySheet(item, source: values)
        }
    }

    /// The loupe's photo: the editor's saved values, never a slider's or a
    /// preset hover's values ahead of them.
    private func editorCopySource(_ item: CatalogItem) -> Adjustments? {
        guard editor.item?.versionID == item.versionID, editor.state == .ready else { return nil }
        return editor.savedAdjustments
    }

    /// What the sheet copies from: the editor's saved values, or the
    /// catalog's after pending saves. Nil, with the unreadable message in
    /// Activity, when the photo's edits can't be read.
    func copySource(_ item: CatalogItem) async -> Adjustments? {
        if let values = editorCopySource(item) { return values }
        do {
            return try await writes.savedAdjustments(ofVersion: item.versionID, in: catalog)
        } catch is CancellationError {
            return nil
        } catch {
            report(AdjustText.unreadableMessage(EditStack.ReadFailure(error)),
                   action: CopyAdjustmentsText.title, warning: true)
            return nil
        }
    }

    private func presentCopySheet(_ item: CatalogItem, source: Adjustments) {
        // Something else came up while the values were read.
        guard !otherModalIsUp, !showsPresetSheet else { return }
        let sheet = CopySheet(item: item, source: source, sourceURL: sourceURL(for: item),
                              windowHeight: windowObserver.window?.contentLayoutRect.height)
        sheet.loadPreview(previewRequest(for: item, tier: .thumbnail), from: previews)
        copySheet = sheet
        showsCopySheet = true
    }

    /// Copy (Return): the checked items become the clipboard, replacing any
    /// earlier copy (R4, R10). Nothing happens with nothing checked.
    func confirmCopySheet() {
        guard let sheet = copySheet, sheet.state.canCopy else { return }
        let copied = sheet.state.copied(from: sheet.sourceURL)
        copiedAdjustments = copied
        showsCopySheet = false
        AccessibilityText.announce(CopyAdjustmentsText.announcement(copied.summary), priority: .medium)
    }

    /// Cancel (Esc): neither the clipboard nor any photo changes.
    func cancelCopySheet() {
        showsCopySheet = false
    }

    // MARK: Paste

    /// Gives the selection (grid) or the photo on screen (loupe) the copied
    /// items, and nothing else (R5); videos are left out (`batchSelection`).
    func pasteAdjustments() {
        guard let copied = copiedAdjustments else { return }
        let actionName = String(localized: "Paste Adjustments", comment: "Undo action name")
        // Asks first when it moves the frame of photos that have masks or spots
        // (lens-corrections design §6; R7): the target's own, not the spots the
        // paste brings (code review C1).
        confirmingLensFrameChange(actionName: actionName, { copied.pastedForFrameQuestion(onto: $0) }) { [self] targets in
            if copied.includesSpots {
                pasteMeasuringSpotFrames(copied, actionName: actionName, targets: targets)
            } else if copied.values.needsAlignmentMeasurement {
                changeAdjustmentsMeasuringAlignment(actionName: actionName, targets: targets) { _, values in
                    copied.pasted(onto: values)
                }
            } else {
                changeAdjustments(ofVersions: batchSelection(action: actionName, targets: targets).versionIDs,
                                  actionName: actionName) { copied.pasted(onto: $0) }
            }
        }
    }

    /// A paste that carries Spots (R8): each photo's frame is measured from
    /// its master first, and its spots are replaced only when the frame has
    /// the size of the one they were copied from; the other copied items
    /// apply to every photo. Then, after the change has landed, at most two
    /// warnings say how many of the photos it wrote kept their own spots, and
    /// why (design §5.1, §15 DQ-1).
    ///
    /// One photo (the loupe's, or one selected) is measured on the write
    /// chain, so its undo step is registered before this returns (code
    /// review C4). Several are measured before the write, four at a time, in
    /// Activity with Stop; ⌘Z during that read undoes the step before the
    /// paste (the measuring paste's known limit, lens-corrections).
    private func pasteMeasuringSpotFrames(_ copied: CopiedAdjustments, actionName: String, targets: [CatalogItem]) {
        let ids = batchSelection(action: actionName, targets: targets).versionIDs
        guard !ids.isEmpty else { return }
        let byID = Dictionary(targets.map { ($0.versionID, $0) }, uniquingKeysWith: { first, _ in first })
        let masters = ids.map { ($0, byID[$0].flatMap(sourceURL(for:))) }
        let report: @MainActor (SpotPastePlan, Set<Int64>) -> Void = { [weak self] plan, written in
            self?.reportSpotsLeftOut(plan.reaching(written), actionName: actionName)
        }
        if ids.count == 1, !copied.values.needsAlignmentMeasurement {
            let planned = Pending<SpotPastePlan>()
            changeAdjustments(ofVersions: ids, actionName: actionName, preparing: {
                // Nil only when cancelled: then no frame is known and the photo keeps its spots.
                let plan = await Self.spotPastePlan(copied, masters: masters)
                    ?? SpotPastePlan(ids: ids, sourceFrame: nil, frames: [:])
                planned.value = plan
                return Self.spotPaste(copied, plan)
            }, then: { written in
                if let plan = planned.value { report(plan, written) }
            })
            return
        }
        let photos = ids.compactMap { byID[$0] }
        batchAutoTask?.cancel()
        let run = batchAutoRun.begin()
        setBatchAutoProgress((0, ids.count), title: actionName)
        batchAutoTask = Task {
            defer {
                if batchAutoRun.owns(run) {
                    setBatchAutoProgress(nil)
                    batchAutoTask = nil
                }
            }
            let plan = await Self.spotPastePlan(copied, masters: masters) { [self] done in
                guard batchAutoRun.owns(run) else { return false }
                setBatchAutoProgress((done, ids.count), title: actionName)
                return true
            }
            guard let plan, !Task.isCancelled, batchAutoRun.owns(run) else { return }
            let transform = Self.spotPaste(copied, plan)
            if copied.values.needsAlignmentMeasurement {
                changeAdjustmentsMeasuringAlignment(actionName: actionName, targets: photos,
                                                    then: { report(plan, $0) }, transform)
            } else {
                changeAdjustments(ofVersions: ids, actionName: actionName, then: { report(plan, $0) }, transform)
            }
        }
    }

    /// Each photo gets the copied items, and the spots when its frame matched.
    private static func spotPaste(_ copied: CopiedAdjustments,
                                  _ plan: SpotPastePlan) -> @Sendable (Int64, Adjustments) -> Adjustments {
        let matching = plan.matching
        return { id, values in copied.pasted(onto: values, pastingSpots: matching.contains(id)) }
    }

    /// Measures the source's frame and each master's, off the main actor,
    /// four at a time. `progress` gets the count read after each four and
    /// ends the read by returning false (then the result is nil). Without
    /// the source's size no photo can match, and nothing else is read.
    private static func spotPastePlan(_ copied: CopiedAdjustments, masters: [(Int64, URL?)],
                                      progress: (@MainActor (Int) -> Bool)? = nil) async -> SpotPastePlan? {
        let source = copied.sourceURL
        let sourceFrame = await Task.detached(priority: .userInitiated) {
            source.flatMap(PreviewGenerator.maskFrameSize)
        }.value
        var frames: [Int64: CGSize] = [:]
        var done = 0
        let reads = sourceFrame == nil ? [] : masters
        for chunk in stride(from: 0, to: reads.count, by: 4).map({ Array(reads[$0..<min($0 + 4, reads.count)]) }) {
            guard !Task.isCancelled else { return nil }
            await withTaskGroup(of: (Int64, CGSize?).self) { group in
                for (id, url) in chunk {
                    group.addTask { (id, url.flatMap(PreviewGenerator.maskFrameSize)) }
                }
                for await (id, size) in group { frames[id] = size }
            }
            done += chunk.count
            if let progress, !progress(done) { return nil }
        }
        return SpotPastePlan(ids: masters.map(\.0), sourceFrame: sourceFrame, frames: frames)
    }

    /// At most two warnings per paste for the photos that kept their own
    /// spots: the size differs first, then the size could not be read
    /// (design §15 DQ-1).
    private func reportSpotsLeftOut(_ outcome: SpotPastePlan, actionName: String) {
        if outcome.otherSize > 0 {
            report(CopyAdjustmentsText.spotsOtherSize(outcome.otherSize), action: actionName, warning: true)
        }
        if outcome.unknownSize > 0 {
            report(CopyAdjustmentsText.spotsUnknownSize(outcome.unknownSize), action: actionName, warning: true)
        }
    }
}
