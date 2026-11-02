import AppKit
import PhotoCore

/// Adjust commands that act on every selected photo in the grid as one undo
/// step, and on the photo on screen in the loupe (decision 5 of
/// docs/UI_REDESIGN.md).
extension LibraryModel {
    /// The photos a batch command changes: the versions the grid shows,
    /// without videos, and without offline photos when `needsMaster` reads the
    /// master. Stacks this build cannot read are left out by the catalog,
    /// which says so (`changeAdjustments`).
    func batchSelection(needsMaster: (CatalogItem) -> Bool = { _ in false }) -> BatchEdit.Selection {
        let selection = BatchEdit.select(actionTargets.map { index in
            let item = items[index]
            return BatchEdit.Candidate(versionID: item.versionID, isVideo: item.isVideo, needsMaster: needsMaster(item),
                                       isOnline: !isOffline(item))
        })
        // TODO(UI redesign step 5): report `selection.skipped` (videos, offline
        // masters) in the toolbar's Activity item. There is nowhere to say it
        // before then, and no new UI is wanted for it.
        return selection
    }

    /// Resets every adjustment (operations this build does not know stay).
    func resetAllAdjustments() {
        if mode == .loupe {
            editor.resetAll()
            return
        }
        changeAdjustments(ofVersions: batchSelection().versionIDs,
                          actionName: String(localized: "Reset Adjustments", comment: "Undo action name")) {
            Adjustments(stack: EditStack(operations: $0.preserved))
        }
    }

    /// A quarter turn, committed at once (in a crop session, the frame turns).
    /// A raw without a crop keeps its camera frame, read from the master.
    func rotate(clockwise: Bool) {
        if mode == .loupe {
            editor.rotate(clockwise: clockwise)
            return
        }
        let isRaw: (CatalogItem) -> Bool = { $0.fileKind == .raw }
        let selection = batchSelection(needsMaster: isRaw)
        let raws = selection.versionIDs.compactMap { id -> (Int64, URL)? in
            guard let item = item(versionID: id), isRaw(item), let url = sourceURL(for: item) else { return nil }
            return (id, url)
        }
        let actionName = String(localized: "Rotate", comment: "Undo action name")
        Task {
            let cameraRects = await Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: raws.map { ($0.0, CameraFrame.rect(of: $0.1)) })
            }.value
            changeAdjustments(ofVersions: selection.versionIDs, actionName: actionName) { id, values in
                var values = values
                values.crop = values.crop.turned(clockwise: clockwise, cameraRect: cameraRects[id] ?? nil)
                return values
            }
        }
    }

    /// Auto Exposure: each photo measured from its master with its own
    /// adjustments, then all set as one undo step.
    func autoExposure() {
        if mode == .loupe {
            editor.autoExposure()
            return
        }
        let selection = batchSelection(needsMaster: { _ in true })
        let sources = selection.versionIDs.compactMap { id -> (Int64, URL)? in
            guard let item = item(versionID: id), let url = sourceURL(for: item) else { return nil }
            return (id, url)
        }
        guard !sources.isEmpty else { return }
        let catalog = self.catalog
        let adjuster = AutoAdjuster(generator: previews.interactiveGenerator)
        let actionName = String(localized: "Auto Exposure", comment: "Undo action name")
        // TODO(UI redesign step 5): show this measuring in the Activity item.
        Task {
            guard let stored = try? await catalog.editStacks(forVersions: sources.map(\.0)) else { return }
            let measured = await Task.detached(priority: .userInitiated) {
                var values: [Int64: Double] = [:]
                for (id, url) in sources {
                    guard let stack = stored.stacks[id],
                          let ev = try? adjuster.exposure(source: url, adjustments: Adjustments(stack: stack)) else { continue }
                    values[id] = ev
                }
                return values
            }.value
            changeAdjustments(ofVersions: Array(measured.keys), actionName: actionName) { id, values in
                var values = values
                if let ev = measured[id] { values.exposure.ev = ev }
                return values
            }
        }
    }

    /// Crop / Finish Cropping (`C`). In the grid, opens the loupe on the
    /// focused photo and starts cropping once it is ready.
    func crop() {
        if mode == .loupe {
            editor.toggleCrop()
            return
        }
        guard let index = focusIndex, items.indices.contains(index), !items[index].isVideo else { return }
        openLoupe(at: index)
        editor.beginCropWhenReady(versionID: items[index].versionID)
    }

    func item(versionID: Int64) -> CatalogItem? {
        indexOfVersion(versionID).map { items[$0] }
    }
}
