import AppKit
import PhotoCore
import PhotoUI
import os

/// One Duplicate as its undo step holds it: the copies it made, and what
/// Undo and Redo need to take them away and bring the same ones back.
@MainActor
private final class DuplicateStep {
    /// The copies, as their write made them.
    let copies: [DuplicatedVersion]
    /// The copies as Undo took them out of the catalog, for Redo.
    var removed: [RemovedCopy] = []
    /// The targets and the focused photo before, which Undo goes back to.
    let selectionBefore: [Int64]
    let focusBefore: Int64?

    init(copies: [DuplicatedVersion], selectionBefore: [Int64], focusBefore: Int64?) {
        self.copies = copies
        self.selectionBefore = selectionBefore
        self.focusBefore = focusBefore
    }
}

/// File ▸ Duplicate (docs/features/virtual-copies): a copy of each target
/// photo, in the catalog only. No file, folder or sidecar is touched.
extension LibraryModel {
    private static let duplicateLog = Logger(subsystem: AppBranding.bundleIdentifier, category: "duplicate")

    /// Duplicate has photos to act on and may start (design §4.1): not while
    /// a crop is being edited (unsaved state, as with Rotate), and one at a
    /// time. Imports and exports do not block it; a removal does, since it
    /// may take the targets. Not while two photos are compared
    /// (side-by-side-comparison design §16 D14): Duplicate moves the focus
    /// to the copy, and the comparison's focus is its active photo.
    var canDuplicateTargets: Bool {
        !isDuplicating && !isRemoving && editor.cropSession == nil && !isComparing
            && DuplicateTargets.canDuplicate(actionTargets.lazy.map { self.items[$0] })
    }

    /// Makes a copy of each target photo as one undo step. The copies appear
    /// after their originals once they are written, selected, the focused
    /// photo's copy focused (the loupe moves to it). Videos among the targets
    /// are left out and counted in Activity. A failure changes nothing, and
    /// leaves no undo step: the step is registered once the copies are
    /// written, as a paste that measures first registers its own.
    func duplicateTargets() {
        guard canDuplicateTargets else { return }
        let targets = actionTargets.map { items[$0] }
        let resolved = DuplicateTargets.resolve(targets)
        let ids = resolved.versionIDs
        guard !ids.isEmpty else { return }
        if resolved.skippedVideos > 0 {
            report(DuplicateText.videosSkipped(resolved.skippedVideos), action: DuplicateText.title)
        }
        let selectionBefore = targets.map(\.versionID)
        let focusBefore = focusedItem?.versionID
        let announcement = ids.count == 1
            ? item(versionID: ids[0]).map { DuplicateText.madeCopy(of: PhotoName.display($0)) }
            : nil
        let catalog = self.catalog
        isDuplicating = true
        // On the write chain, after every change made before it. Not
        // `persist`: a failure has its own words (design §4.4).
        writes.enqueue { [self] in
            // Activity shows the job only if it takes a moment; no Stop, the
            // copies are one transaction.
            let showJob = Task {
                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                duplicateJob = RemovalJob(title: DuplicateText.title, detail: DuplicateText.duplicating(ids.count))
            }
            defer {
                showJob.cancel()
                duplicateJob = nil
                isDuplicating = false
            }
            do {
                let made = try await catalog.duplicateVersions(ids: ids)
                let step = DuplicateStep(copies: made, selectionBefore: selectionBefore, focusBefore: focusBefore)
                registerDuplicateUndo(step, isUndo: true)
                await showCopies(step)
                AccessibilityText.announce(announcement ?? DuplicateText.madeCopies(made.count))
            } catch {
                Self.duplicateLog.error("Duplicate failed: \(String(describing: error), privacy: .public)")
                report(DuplicateText.failed + "\n" + error.localizedDescription, action: DuplicateText.title, warning: true,
                       announcing: DuplicateText.failed)
            }
        }
    }

    /// Undo takes the copies out again and goes back to the originals; Redo
    /// puts the same copies back (the same names) and selects them. Both run
    /// on the write chain, after the change they reverse.
    private func registerDuplicateUndo(_ step: DuplicateStep, isUndo: Bool) {
        undoManager.registerUndo(withTarget: self) { model in
            let catalog = model.catalog
            model.persist { [weak model] in
                if isUndo {
                    step.removed = try await catalog.removeCopies(versionIDs: step.copies.map(\.copyVersionID))
                    await model?.hideCopies(step)
                } else {
                    try await catalog.restoreCopies(step.removed)
                    await model?.showCopies(step)
                }
            }
            model.registerDuplicateUndo(step, isUndo: !isUndo)
        }
        undoManager.setActionName(DuplicateText.title)
    }

    /// Puts the written copies into the list, each after its master's other
    /// items (`DuplicatePlacement`), selects them and focuses the copy of the
    /// photo that had the focus. A copy whose source is not on screen (the
    /// source changed meanwhile) is not shown here; one a reload already
    /// brought in is not added twice.
    private func showCopies(_ step: DuplicateStep) async {
        let wanted = step.copies.filter { indexOfVersion($0.sourceVersionID) != nil }
        guard !wanted.isEmpty else {
            // Another source is on screen: its list and selection stay as they are.
            await refreshCounts()
            return
        }
        guard let fetched = try? await catalog.libraryItems(versionIDs: wanted.map(\.copyVersionID)) else {
            // The copies are written; show what the catalog holds.
            reloadItems(keepFocus: true)
            await refreshCounts()
            return
        }
        let byID = Dictionary(fetched.map { ($0.versionID, $0) }, uniquingKeysWith: { first, _ in first })
        // In the order they were made, which is the order of their names.
        let copies = wanted.compactMap { byID[$0.copyVersionID] }
        let new = copies.filter { indexOfVersion($0.versionID) == nil }
        let focus = wanted.first { $0.sourceVersionID == step.focusBefore }?.copyVersionID
        replaceItems(DuplicatePlacement.inserting(new, into: items, sort: sort), selecting: copies.map(\.versionID),
                     focusVersionID: focus)
        await refreshCounts()
    }

    /// Takes the copies out of the list and goes back to the photos that were
    /// the targets, the focus where it was.
    private func hideCopies(_ step: DuplicateStep) async {
        let gone = Set(step.copies.map(\.copyVersionID))
        guard (step.copies.map(\.copyVersionID) + step.selectionBefore).contains(where: { indexOfVersion($0) != nil }) else {
            // Neither the copies nor their originals are on screen (another source).
            await refreshCounts()
            return
        }
        // A crop being edited on a copy that is gone has nothing to save.
        if let open = focusedItem, gone.contains(open.versionID) { editor.endCrop(save: false) }
        replaceItems(items.filter { !gone.contains($0.versionID) }, selecting: step.selectionBefore,
                     focusVersionID: step.focusBefore)
        await refreshCounts()
    }

    /// Copies count as photos everywhere photos are counted (PRD D6): the
    /// sidebar's projects, albums, keywords, dates and smart albums.
    private func refreshCounts() async {
        await refreshProjects()
        await refreshKeywords()
    }
}

/// The words of Duplicate and of a copy's marks (design §10).
enum DuplicateText {
    static var title: String {
        String(localized: "Duplicate", comment: "File menu and photo context menus: makes a copy of each selected photo in the library (no file is copied). Also its undo action name and its Activity row title")
    }

    static func videosSkipped(_ count: Int) -> String {
        String(localized: "\(count) videos weren't duplicated.", comment: "Activity, after Duplicate on a selection with videos")
    }

    static func duplicating(_ count: Int) -> String {
        String(localized: "Duplicating \(count) photos…", comment: "Activity: under the title of a Duplicate that takes a while")
    }

    static var failed: String {
        String(localized: "The photos couldn't be duplicated. The library is unchanged.", comment: "Activity warning")
    }

    static func madeCopy(of name: String) -> String {
        String(localized: "Made a copy of “\(name)”.", comment: "VoiceOver, after Duplicate on one photo; its name")
    }

    static func madeCopies(_ count: Int) -> String {
        String(localized: "Made \(count) copies.", comment: "VoiceOver, after Duplicate on several photos")
    }

    static var badge: String {
        String(localized: "Copy", comment: "Loupe caption badge: the photo is a copy made with Duplicate")
    }

    /// The Copy badge's tooltip and VoiceOver help; `fileName` is the master's.
    static func badgeHelp(_ fileName: String) -> String {
        String(localized: "A copy of “\(fileName)”. Its adjustments, rating, flag, label, keywords and albums are its own.",
               comment: "Tooltip of the loupe caption's Copy badge; the original's file name")
    }
}
