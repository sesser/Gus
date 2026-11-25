import AppKit
import Synchronization
import PhotoCore

extension LibraryModel {
    // MARK: Measuring paste and presets

    /// A paste or preset that carries automatic color alignment: each photo
    /// it reaches is measured for itself (chromatic-aberration R16), one at a
    /// time with progress in Activity under the command's title, Stop
    /// writing nothing; then everything is saved as one undo step. A photo
    /// that can't be measured is left completely unchanged (R16a): offline
    /// ones with the existing warning, unreadable ones with the export's
    /// "the original could not be read". In the loupe, the inspector shows
    /// the measuring and, when it fails, "This photo could not be measured."
    /// `toolbarTitle` is `actionName` fitted to the toolbar, when it can be long.
    /// `targets` are the command's photos when it asked first (code review C11).
    func changeAdjustmentsMeasuringAlignment(actionName: String, toolbarTitle: String? = nil, targets: [CatalogItem]? = nil,
                                             _ transform: @escaping @Sendable (Adjustments) -> Adjustments) {
        changeAdjustmentsMeasuringAlignment(actionName: actionName, toolbarTitle: toolbarTitle, targets: targets) { _, values in
            transform(values)
        }
    }

    /// As above, with each version's id, for changes that differ per photo
    /// (a paste's spots, #243 R8). `then` runs after the write, with the
    /// versions it wrote; never when Stop or a newer command ended the
    /// measuring.
    func changeAdjustmentsMeasuringAlignment(actionName: String, toolbarTitle: String? = nil, targets: [CatalogItem]? = nil,
                                             then: (@MainActor (_ written: Set<Int64>) -> Void)? = nil,
                                             _ transform: @escaping @Sendable (Int64, Adjustments) -> Adjustments) {
        let selection = batchSelection(action: actionName, targets: targets, needsMaster: { _ in true })
        let sources = selection.versionIDs.compactMap { id -> (Int64, URL, String)? in
            guard let item = item(versionID: id), let url = sourceURL(for: item) else { return nil }
            return (id, url, PhotoName.inFull(item))
        }
        guard !sources.isEmpty else { return }
        let catalog = self.catalog
        let writes = self.writes
        let generator = previews.interactiveGenerator
        // The loupe's photo shows the measuring (and a failure) only while it is
        // one of this command's photos: after a frame question's read the open
        // photo may be another (code review C14).
        let targetIDs = Set(sources.map(\.0))
        let opensTarget = { [weak self] () -> Bool in
            guard let self, mode == .loupe, let open = editor.item?.versionID else { return false }
            return targetIDs.contains(open)
        }
        let inLoupe = opensTarget()
        batchAutoTask?.cancel()
        let run = batchAutoRun.begin()
        setBatchAutoProgress((0, sources.count), title: actionName, toolbarTitle: toolbarTitle)
        if inLoupe { editor.setMeasuringAlignment(true) }
        batchAutoTask = Task {
            defer {
                if batchAutoRun.owns(run) {
                    setBatchAutoProgress(nil)
                    batchAutoTask = nil
                    if inLoupe { editor.setMeasuringAlignment(false) }
                }
            }
            // After pending saves, so each photo is measured with the values it has now.
            guard let stored = try? await writes.savedEditStacks(forVersions: sources.map(\.0), in: catalog) else { return }
            var measured = BatchEdit.AlignmentMeasurements()
            for (index, (id, url, name)) in sources.enumerated() {
                guard !Task.isCancelled else { return }
                // Stacks this build can't read stay in the list below: the catalog skips and reports them.
                guard let stack = stored.stacks[id] else { continue }
                let values = transform(id, Adjustments(stack: stack))
                if values.needsAlignmentMeasurement {
                    let alignment = await Task.detached(priority: .userInitiated) {
                        try? ColorAlignmentMeasurement.measure(source: url, adjustments: values, generator: generator)
                    }.value
                    measured.record(alignment, id: id, name: name)
                } else {
                    measured.record(values.colorAlignment, id: id, name: name)
                }
                guard batchAutoRun.owns(run) else { return }
                setBatchAutoProgress((index + 1, sources.count), title: actionName, toolbarTitle: toolbarTitle)
            }
            guard !Task.isCancelled, batchAutoRun.owns(run) else { return }
            let unreadable = measured.unreadableOriginals
            if !unreadable.isEmpty {
                // One row for the command (design §19 DQ-2): the count, then the files.
                let summary = Self.unreadableSummary(unreadable.count)
                report(Self.unreadableDetail(summary, names: unreadable), action: actionName, warning: true,
                       announcing: summary)
            }
            // Only when the open photo is itself one whose original could not be read (code review C15).
            if opensTarget(), let open = editor.item?.versionID, measured.failed(open) { editor.noteAlignmentMeasureFailed() }
            let alignments = measured.alignments
            changeAdjustments(ofVersions: measured.versionsToChange(from: sources.map(\.0)), actionName: actionName,
                              then: then) { id, values in
                let changed = transform(id, values)
                guard changed.needsAlignmentMeasurement, let alignment = alignments[id] else { return changed }
                return changed.measuringAlignment(alignment)
            }
        }
    }

    /// The first line of the row for originals a measuring paste or preset
    /// could not read.
    static func unreadableSummary(_ count: Int) -> String {
        String(localized: "\(count) photos were left unchanged: their originals could not be read.",
               comment: "Activity, after a paste or preset that measures color alignment: originals that could not be read; the files follow")
    }

    /// The summary, one line per file up to the export's limit, then "And N more.".
    static func unreadableDetail(_ summary: String, names: [String]) -> String {
        let limit = ExportActivityReport.failureListLimit
        var lines = [summary] + names.prefix(limit).map { String(localized: "\($0): the original could not be read.") }
        if names.count > limit {
            lines.append(String(localized: "And \(names.count - limit) more.", comment: "Activity: failures past the listed ones"))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Applying to many photos

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
                           then: (@MainActor (_ written: Set<Int64>) -> Void)? = nil,
                           _ transform: @escaping @Sendable (Int64, Adjustments) -> Adjustments) {
        changeAdjustments(ofVersions: ids, actionName: actionName, preparing: { transform }, then: then)
    }

    /// As above, with the change worked out on the write chain just before it
    /// is written (`prepare` may read files). The undo step is registered
    /// before this returns and the chain runs it after the change, so ⌘Z at
    /// once undoes this change, never the one before it (#243 code review
    /// C4). `prepare` holds back every later save while it runs: keep it to
    /// a few quick reads. `then` runs after the write with the versions it
    /// wrote (stacks this build can't read are skipped and reported).
    func changeAdjustments(ofVersions ids: [Int64], actionName: String,
                           preparing prepare: @escaping @MainActor () async -> @Sendable (Int64, Adjustments) -> Adjustments,
                           then: (@MainActor (_ written: Set<Int64>) -> Void)? = nil) {
        guard !ids.isEmpty else { return }
        let change = Pending<(before: [Int64: EditStack], after: [Int64: EditStack])>()
        let skipped = Pending<Int>()
        let catalog = self.catalog
        let label = HistoryText.label(actionName, undoing: undoManager.isUndoing, redoing: undoManager.isRedoing)
        let notRaw = Set(ids.filter { item(versionID: $0).map { $0.fileKind != .raw } ?? false })
        let leftOff = LeftOffCounter()
        persist {
            let transform = await prepare()
            let rawOnly: @Sendable (Int64, Adjustments) -> Adjustments = { id, values in
                let changed = transform(id, values)
                guard notRaw.contains(id), changed.asksForMachineLearning else { return changed }
                leftOff.add(id)
                return changed.forNonRawFile()
            }
            // Stacks this build cannot read are left as they are (a newer build's edits).
            let result = try await catalog.changeEditStacks(ofVersions: ids, historyLabel: label, rawOnly)
            change.value = (result.before, result.after)
            skipped.value = result.unreadable.count
            self.historyChanged()
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
            if let then, let value = change.value { then(Set(value.after.keys)) }
        }
        registerEditStacksUndo(change, isUndo: true, actionName: actionName)
    }

    private func registerEditStacksUndo(_ change: Pending<(before: [Int64: EditStack], after: [Int64: EditStack])>,
                                        isUndo: Bool, actionName: String) {
        undoManager.registerUndo(withTarget: self) { model in
            let catalog = model.catalog
            let label = HistoryText.label(actionName, undoing: isUndo, redoing: !isUndo)
            model.persist { [weak model] in
                guard let value = change.value else { return }
                let stacks = isUndo ? value.before : value.after
                try await catalog.setEditStacks(stacks, historyLabel: label)
                model?.historyChanged()
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
            showSavedEditStack(stack, forVersion: id)
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
