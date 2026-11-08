import AppKit
import Synchronization
import PhotoCore

extension LibraryModel {
    // MARK: Copy and paste

    /// Remembers the focused photo's adjustments for Paste Adjustments.
    func copyAdjustments() {
        guard let item = focusedItem, !item.isVideo else { return }
        if editor.item?.versionID == item.versionID, editor.state == .ready {
            copiedAdjustments = editor.adjustments
            return
        }
        let catalog = self.catalog
        Task {
            do {
                let stack = try await catalog.version(id: item.versionID)?.decodedEditStack() ?? .identity
                copiedAdjustments = Adjustments(stack: stack)
            } catch {
                report(AdjustText.unreadableMessage(EditStack.ReadFailure(error)),
                       action: String(localized: "Copy Adjustments"), warning: true)
            }
        }
    }

    /// Gives the selection (grid) or the photo on screen (loupe) the copied
    /// adjustments; videos are left out (`batchSelection`).
    func pasteAdjustments() {
        guard let copiedAdjustments else { return }
        let actionName = String(localized: "Paste Adjustments", comment: "Undo action name")
        if copiedAdjustments.needsAlignmentMeasurement {
            changeAdjustmentsMeasuringAlignment(actionName: actionName) { copiedAdjustments.pasted(onto: $0) }
            return
        }
        applyAdjustments(copiedAdjustments, toVersions: batchSelection(action: actionName).versionIDs, actionName: actionName)
    }

    /// A paste or preset that carries automatic color alignment: each photo
    /// it reaches is measured for itself (chromatic-aberration R16), one at a
    /// time with progress in Activity under the command's title, Stop
    /// writing nothing; then everything is saved as one undo step. A photo
    /// that can't be measured is left completely unchanged (R16a): offline
    /// ones with the existing warning, unreadable ones with the export's
    /// "the original could not be read". In the loupe, the inspector shows
    /// the measuring and, when it fails, "This photo could not be measured."
    func changeAdjustmentsMeasuringAlignment(actionName: String,
                                             _ transform: @escaping @Sendable (Adjustments) -> Adjustments) {
        let selection = batchSelection(action: actionName, needsMaster: { _ in true })
        let sources = selection.versionIDs.compactMap { id -> (Int64, URL, String)? in
            guard let item = item(versionID: id), let url = sourceURL(for: item) else { return nil }
            return (id, url, item.fileName)
        }
        guard !sources.isEmpty else { return }
        let catalog = self.catalog
        let generator = previews.interactiveGenerator
        let inLoupe = mode == .loupe
        batchAutoTask?.cancel()
        setBatchAutoProgress((0, sources.count), title: actionName)
        if inLoupe { editor.setMeasuringAlignment(true) }
        batchAutoTask = Task {
            defer {
                setBatchAutoProgress(nil)
                batchAutoTask = nil
                if inLoupe { editor.setMeasuringAlignment(false) }
            }
            guard let stored = try? await catalog.editStacks(forVersions: sources.map(\.0)) else { return }
            var measured: [Int64: ColorAlignment] = [:]
            var unreadable: [String] = []
            for (index, (id, url, name)) in sources.enumerated() {
                guard !Task.isCancelled else { return }
                // Stacks this build can't read are left to the catalog, which says so.
                guard let stack = stored.stacks[id] else { continue }
                let values = transform(Adjustments(stack: stack))
                if values.needsAlignmentMeasurement {
                    let alignment = await Task.detached(priority: .userInitiated) {
                        try? ColorAlignmentMeasurement.measure(source: url, adjustments: values, generator: generator)
                    }.value
                    if let alignment { measured[id] = alignment } else { unreadable.append(name) }
                } else {
                    measured[id] = values.colorAlignment
                }
                setBatchAutoProgress((index + 1, sources.count), title: actionName)
            }
            guard !Task.isCancelled else { return }
            for name in unreadable {
                report(String(localized: "\(name): the original could not be read."), action: actionName, warning: true)
            }
            if inLoupe, !unreadable.isEmpty { editor.noteAlignmentMeasureFailed() }
            let alignments = measured
            changeAdjustments(ofVersions: sources.map(\.0).filter { alignments[$0] != nil }, actionName: actionName) { id, values in
                let changed = transform(values)
                guard changed.needsAlignmentMeasurement, let alignment = alignments[id] else { return changed }
                return changed.measuringAlignment(alignment)
            }
        }
    }

    // MARK: Applying to many photos

    /// Replaces the adjustments of `ids` (keeping operations this build does not
    /// know), as one undo step.
    func applyAdjustments(_ values: Adjustments, toVersions ids: [Int64], actionName: String) {
        changeAdjustments(ofVersions: ids, actionName: actionName) { values.pasted(onto: $0) }
    }

    /// Gives each of `ids` `transform` of its adjustments, as one undo step.
    func changeAdjustments(ofVersions ids: [Int64], actionName: String,
                           _ transform: @escaping @Sendable (Adjustments) -> Adjustments) {
        changeAdjustments(ofVersions: ids, actionName: actionName) { _, values in transform(values) }
    }

    /// As above, with each version's id, for changes that differ per photo.
    ///
    /// Machine learning noise reduction reaches raw files only (ml-denoise
    /// R10): a file that is not RAW gets the other values, and an Activity
    /// row says how many were left without it.
    func changeAdjustments(ofVersions ids: [Int64], actionName: String,
                           _ transform: @escaping @Sendable (Int64, Adjustments) -> Adjustments) {
        guard !ids.isEmpty else { return }
        let change = Pending<(before: [Int64: EditStack], after: [Int64: EditStack])>()
        let skipped = Pending<Int>()
        let catalog = self.catalog
        let notRaw = Set(ids.filter { item(versionID: $0).map { $0.fileKind != .raw } ?? false })
        let leftOff = LeftOffCounter()
        let rawOnly: @Sendable (Int64, Adjustments) -> Adjustments = { id, values in
            let changed = transform(id, values)
            guard notRaw.contains(id), changed.asksForMachineLearning else { return changed }
            leftOff.add(id)
            return changed.forNonRawFile()
        }
        persist {
            // Stacks this build cannot read are left as they are (a newer build's edits).
            let result = try await catalog.changeEditStacks(ofVersions: ids, rawOnly)
            change.value = (result.before, result.after)
            skipped.value = result.unreadable.count
        }
        afterPendingWrites { model in
            if let value = change.value { model.showEditStacks(value.after) }
            let count = leftOff.count
            if count > 0 {
                model.report(MachineLearningText.leftOffForNonRaw(count), action: actionName)
            }
            if let count = skipped.value, count > 0 {
                model.report(String(localized: "\(count) photos were left unchanged: their edits can't be changed in this version.",
                                    comment: "Activity, after a batch adjustment: stacks this build cannot read"),
                             action: actionName, warning: true)
            }
        }
        registerEditStacksUndo(change, isUndo: true, actionName: actionName)
    }

    private func registerEditStacksUndo(_ change: Pending<(before: [Int64: EditStack], after: [Int64: EditStack])>,
                                        isUndo: Bool, actionName: String) {
        undoManager.registerUndo(withTarget: self) { model in
            let catalog = model.catalog
            model.persist { [weak model] in
                guard let value = change.value else { return }
                let stacks = isUndo ? value.before : value.after
                try await catalog.setEditStacks(stacks)
                // Only once written: previews render the catalog's stacks.
                model?.showEditStacks(stacks)
            }
            model.registerEditStacksUndo(change, isUndo: !isUndo, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Shows saved stacks in the grid, the loupe and the Adjust tab.
    private func showEditStacks(_ stacks: [Int64: EditStack]) {
        for (id, stack) in stacks {
            setEditStackHash(stack.renderHash, forVersion: id)
            editor.catalogChanged(stack, forVersion: id)
        }
    }
}

/// The files a batch left without machine learning noise reduction, counted
/// inside the catalog's write (any thread).
private final class LeftOffCounter: Sendable {
    private let ids = Mutex<Set<Int64>>([])

    func add(_ id: Int64) { ids.withLock { _ = $0.insert(id) } }

    var count: Int { ids.withLock { $0.count } }
}
