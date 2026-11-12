import AppKit
import PhotoCore
import PhotoUI
import os

/// A running removal as the Activity item shows it: indeterminate, and
/// without Stop, since a transaction cannot be stopped part way.
struct RemovalJob: Equatable {
    var title: String
    var detail: String?
}

/// Rename a project, Show in Finder, and Remove from Library
/// (docs/features/library-ops). All three change the catalog at most: no
/// file, folder or sidecar is moved, renamed, written or deleted here.
extension LibraryModel {
    private static let opsLog = Logger(subsystem: AppBranding.bundleIdentifier, category: "library-ops")

    /// The project selected in the sidebar, for File ▸ Rename, Remove
    /// Project from Library… and, with the sidebar focused, Show in Finder.
    var selectedProject: ProjectSummary? {
        guard case .project(let id) = sidebarSelection else { return nil }
        return projects.first { $0.id == id }
    }

    // MARK: Renaming a project

    /// Puts the project's sidebar row into editing (design §4), making the
    /// row visible first: the sidebar, the Projects section, the row.
    func beginProjectRename(_ id: Int64) {
        guard projects.contains(where: { $0.id == id }) else { return }
        showsSidebar = true
        setSidebarSection(.projects, shown: true)
        renamingProjectID = id
        revealProjectRow()
    }

    /// The row's field ended: saves what was typed (`typed` nil: Escape, the
    /// old name stays). An empty name is refused with the alert sound, and
    /// VoiceOver is told why.
    func endProjectRename(_ id: Int64, typed: String?) {
        guard renamingProjectID == id else { return }
        renamingProjectID = nil
        guard let typed, let current = projects.first(where: { $0.id == id })?.project.name else { return }
        switch ProjectRename.resolve(typed: typed, current: current) {
        case .rename(let name):
            renameProject(id, to: name)
        case .unchanged:
            break
        case .refused:
            NSSound.beep()
            AccessibilityText.announce(LibraryOpsText.emptyName)
        }
    }

    /// Saves a project's name in the catalog as one undo step. The sidebar
    /// shows it at once; the write follows in order.
    func renameProject(_ id: Int64, to name: String) {
        guard let previous = projects.first(where: { $0.id == id })?.project.name, previous != name else { return }
        showProjectName(name, forProject: id)
        let catalog = self.catalog
        persist { try await catalog.renameProject(id: id, to: name) }
        // What the catalog holds, should the write have failed.
        afterPendingWrites { await $0.refreshProjects() }
        undoManager.registerUndo(withTarget: self) { $0.renameProject(id, to: previous) }
        undoManager.setActionName(LibraryOpsText.renameProjectUndo)
    }

    // MARK: Show in Finder

    /// Whether Show in Finder has photos it can reveal: any target whose
    /// volume is online, as the Offline badge already says. No disk access.
    var canShowTargetsInFinder: Bool {
        FinderReveal.canReveal(actionTargets.lazy.map { self.items[$0] }, onlineVolumes: onlineVolumeIDs)
    }

    /// The files Show in Finder would hand to the Finder for the targets,
    /// and how many it leaves out. Whether each file is there is checked
    /// now, off the main actor.
    func finderRevealOutcome() async -> FinderReveal.Outcome {
        let targets = actionTargets.map { items[$0] }
        let ids = FinderReveal.versionIDs(for: targets)
        var known = Dictionary(targets.map { ($0.versionID, $0) }, uniquingKeysWith: { first, _ in first })
        // A grouped pair showing its JPEG reveals the RAW, which the grid does not hold.
        let others = ids.filter { known[$0] == nil }
        if !others.isEmpty {
            for item in (try? await catalog.libraryItems(versionIDs: others)) ?? [] { known[item.versionID] = item }
        }
        let locations = ids.map { id in known[id].flatMap { sourceURL(for: $0) } }
        return await Task.detached(priority: .userInitiated) {
            FinderReveal.outcome(of: locations) { FileManager.default.fileExists(atPath: $0.path) }
        }.value
    }

    /// Reveals the targets' originals, all in one request, so files in one
    /// folder open one Finder window. Photos that are offline or not where
    /// the library has them are left out and counted in Activity. Never a
    /// folder or a volume: only originals are passed on.
    func showTargetsInFinder() {
        guard !actionTargets.isEmpty else { return }
        Task {
            let outcome = await finderRevealOutcome()
            if !outcome.urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outcome.urls) }
            if outcome.skipped > 0 {
                report(LibraryOpsText.notShown(outcome), action: LibraryOpsText.showInFinder)
            }
        }
    }

    /// Whether the project has a folder to reveal now (`projectFolders`).
    func canShowProjectInFinder(_ id: Int64) -> Bool {
        projectFolders[id] != nil
    }

    /// Reveals the project's folder, selected in its parent. The folder is
    /// checked again first: it may have gone since the menu was shown, and
    /// then nothing opens and the item dims.
    func showProjectInFinder(_ id: Int64) {
        guard projects.contains(where: { $0.id == id }) else { return }
        Task {
            await refreshProjectFolders()
            guard let folder = projectFolders[id] else { return }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    /// Works out which projects have a folder that can be revealed: a source
    /// path, every volume of its photos mounted, the folder there and not a
    /// volume's mount point. One file-system call per project, off the main
    /// actor, when projects or volumes change and when the app comes
    /// forward; menus only read the result.
    func refreshProjectFolders() async {
        projectFoldersGeneration += 1
        let generation = projectFoldersGeneration
        let candidates = projects.compactMap { summary -> (Int64, String)? in
            summary.project.sourcePath.map { (summary.id, $0) }
        }
        let online = onlineVolumeIDs
        let volumes: [Int64: Set<Int64>]
        do {
            volumes = try await catalog.projectVolumeIDs()
        } catch {
            Self.opsLog.error("Reading project volumes failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let folders = await Task.detached(priority: .utility) {
            var folders: [Int64: URL] = [:]
            for (id, path) in candidates {
                let state = ProjectFolder.state(sourcePath: path, volumesOnline: (volumes[id] ?? []).isSubset(of: online))
                if let url = state.url { folders[id] = url }
            }
            return folders
        }.value
        guard generation == projectFoldersGeneration, folders != projectFolders else { return }
        projectFolders = folders
    }

    // MARK: Removing

    /// Whether a removal may start now (design §8): not beside a folder add
    /// or a copying import, which fail if their project is removed under
    /// them, and not beside another removal (`RemovalAvailability`).
    var canRemoveFromLibrary: Bool {
        RemovalAvailability.canStart(isRemoving: isRemoving, isAddingFolders: isImporting,
                                     isCopying: cardImport.progress != nil)
    }

    /// File ▸ Remove from Library… (⌘⌫) and the context menus': asks, then
    /// removes the targets from the catalog.
    func removeTargetsFromLibrary() {
        let targets = actionTargets.map { items[$0] }
        guard canRemoveFromLibrary, !targets.isEmpty else { return }
        let versionIDs = targets.map(\.versionID)
        let count = targets.count
        // A copy has no file of its own: it goes by its name in the grid.
        let fileName = count == 1 ? PhotoName.inFull(targets[0]) : nil
        let catalog = self.catalog
        askToRemove(title: LibraryOpsText.removeFromLibrary, failure: LibraryOpsText.photosNotRemoved) {
            // From the catalog: a pair's other file, or an original's copies, may not be in the grid.
            let plan = try await catalog.photoRemovalPlan(forVersions: versionIDs)
            let confirmation = RemovalConfirmation.photos(plan, shown: count, fileName: fileName)
            return PendingRemoval(text: LibraryOpsText.alert(confirmation), title: LibraryOpsText.removeFromLibrary,
                                  job: RemovalJob(title: LibraryOpsText.removeFromLibrary, detail: LibraryOpsText.removing(count)),
                                  failure: LibraryOpsText.photosNotRemoved,
                                  announcement: fileName.map(LibraryOpsText.removedPhoto) ?? LibraryOpsText.removedPhotos(count),
                                  remove: { try await catalog.removePhotos(versionIDs: versionIDs) })
        }
    }

    /// File ▸ Remove Project from Library… and the project row's: asks,
    /// then removes the project, its photos and its own albums.
    func removeProjectFromLibrary(_ id: Int64) {
        guard canRemoveFromLibrary, projects.contains(where: { $0.id == id }) else { return }
        let catalog = self.catalog
        let grouped = groupPairs
        askToRemove(title: LibraryOpsText.removeProject, failure: LibraryOpsText.projectNotRemoved) {
            guard let plan = try await catalog.projectRemovalPlan(id: id, groupingPairs: grouped) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let detail = plan.photoCount > 0 ? LibraryOpsText.removing(plan.photoCount) : nil
            return PendingRemoval(text: LibraryOpsText.alert(RemovalConfirmation.project(plan)), title: LibraryOpsText.removeProject,
                                  job: RemovalJob(title: LibraryOpsText.removeProject, detail: detail),
                                  failure: LibraryOpsText.projectNotRemoved,
                                  announcement: LibraryOpsText.removedProject(plan.project.name),
                                  remove: { try await catalog.removeProject(id: id) })
        }
    }

    /// Reads what the removal would take and puts the confirmation up
    /// (`pendingRemoval`, shown by the window). Nothing is removed before
    /// the person has answered.
    private func askToRemove(title: String, failure: String, prepare: @escaping @MainActor () async throws -> PendingRemoval) {
        // From the request on, so a second ⌘⌫ cannot ask twice.
        isRemoving = true
        // An open keyword field would tag photos that are about to go.
        if keywordEntry != nil { endKeywordEntry(adding: []) }
        Task {
            do {
                pendingRemoval = try await prepare()
            } catch {
                isRemoving = false
                reportRemovalFailure(error, text: failure, title: title)
            }
        }
    }

    /// The confirmation went away without Remove (Cancel, Escape, ⌘.).
    func cancelRemoval() {
        guard pendingRemoval != nil else { return }
        pendingRemoval = nil
        isRemoving = false
    }

    /// The person chose Remove: write, then show the result. Nothing changes
    /// on screen before the write has landed, and a failure changes nothing
    /// at all (R13).
    func confirmRemoval(_ pending: PendingRemoval) {
        pendingRemoval = nil
        isRemoving = true
        Task {
            // Activity shows the job only if it takes a moment (design §6.3).
            let showJob = Task {
                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                removalJob = pending.job
            }
            defer {
                showJob.cancel()
                removalJob = nil
                isRemoving = false
            }
            do {
                let result = try await removeInOrder(pending.remove)
                await removalDidFinish(result, announcement: pending.announcement)
            } catch {
                reportRemovalFailure(error, text: pending.failure, title: pending.title)
            }
        }
    }

    /// A warning in Activity, with the error under it; VoiceOver hears the
    /// first line. No alert: there is nothing to do but try again.
    private func reportRemovalFailure(_ error: any Error, text: String, title: String) {
        Self.opsLog.error("Removal failed: \(String(describing: error), privacy: .public)")
        report(text + "\n" + error.localizedDescription, action: title, warning: true, announcing: text)
    }

    /// Runs the removal on the write chain, after every change made before
    /// it, with sidecar writing paused: a run in flight is waited for, and
    /// none writes until the removal has ended, so no sidecar is written for
    /// a photo while it is being removed or after (R5).
    private func removeInOrder(_ remove: @escaping @Sendable () async throws -> RemovalResult) async throws -> RemovalResult {
        let outcome: Result<RemovalResult, any Error> = await withCheckedContinuation { continuation in
            writes.enqueue { [self] in
                await pauseSidecarSync()
                do {
                    continuation.resume(returning: .success(try await remove()))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
                resumeSidecarSync()
            }
        }
        return try outcome.get()
    }

    /// Stops sidecar writing and waits for a run in flight. The run ends
    /// after the file it is on (`SidecarSync.pauseQueue`); it is not
    /// cancelled, which could end it between writing a sidecar and
    /// recording that it did. A task still waiting to start its run is
    /// cancelled, so the removal does not wait out its delay.
    private func pauseSidecarSync() async {
        sidecars.pauseQueue()
        if !sidecarSyncIsWriting { sidecarSyncTask?.cancel() }
        await sidecarSyncTask?.value
    }

    private func resumeSidecarSync() {
        sidecars.resumeQueue()
        scheduleSidecarSync()
    }

    /// The removal is in the catalog: the photos leave every source, the
    /// focus goes to the photo after the last removed one unless the focused
    /// photo is still there (`RemovalFocus`), and the undo stack is cleared,
    /// since its steps may name photos that are gone (design §6.3, A4).
    private func removalDidFinish(_ result: RemovalResult, announcement: String) async {
        let removedImages = Set(result.imageIDs)
        let removedCopies = Set(result.copyVersionIDs)
        // A master takes every version of it; a copy removed alone only itself.
        let isRemoved: (CatalogItem) -> Bool = { removedImages.contains($0.imageID) || removedCopies.contains($0.versionID) }
        // A crop being edited on a removed photo has nothing to save.
        if let open = focusedItem, isRemoved(open) { editor.endCrop(save: false) }
        undoManager.removeAllActions()
        let next = RemovalFocus.index(count: items.count, focus: focusIndex) { isRemoved(items[$0]) }
            .map { items[$0].versionID }
        reloadItems(keepFocus: true, focusVersionID: next)
        // A source that is gone (the project, a keyword left without photos)
        // hands the browser back to All Photos, as it does elsewhere.
        await refreshProjects()
        await refreshKeywords()
        await refreshSidebar()
        await refreshDiskChanges()
        AccessibilityText.announce(announcement)
    }
}

/// The words of Rename, Show in Finder and the removals (design §10).
enum LibraryOpsText {
    static var showInFinder: String {
        String(localized: "Show in Finder", comment: "File menu, photo and project context menus, and Activity row title")
    }
    static var removeFromLibraryMenu: String {
        String(localized: "Remove from Library…", comment: "File menu and photo context menus: asks, then removes the photos from the library; files stay on disk")
    }
    static var removeProjectMenu: String {
        String(localized: "Remove Project from Library…", comment: "File menu and project context menu: asks, then removes the project from the library; files stay on disk")
    }
    static var removeFromLibrary: String {
        String(localized: "Remove from Library", comment: "Activity job and row title")
    }
    static var removeProject: String {
        String(localized: "Remove Project from Library", comment: "Activity job and row title")
    }
    static var renameProjectUndo: String {
        String(localized: "Rename Project", comment: "Undo action name")
    }
    static var projectNameLabel: String {
        String(localized: "Project name", comment: "Import options row: the new project's name template. Also VoiceOver's label for a project's name field in the sidebar")
    }
    static var emptyName: String {
        String(localized: "The name can't be empty.", comment: "VoiceOver, after an empty project name was refused")
    }

    static func rename(_ name: String) -> String {
        String(localized: "Rename “\(name)”", comment: "File menu; the project selected in the sidebar, renamed in place")
    }

    static func removing(_ count: Int) -> String {
        String(localized: "Removing \(count) photos…", comment: "Activity: under the title of a removal from the library that takes a while")
    }

    static var photosNotRemoved: String {
        String(localized: "The photos couldn't be removed. The library is unchanged.", comment: "Activity warning")
    }
    static var projectNotRemoved: String {
        String(localized: "The project couldn't be removed. The library is unchanged.", comment: "Activity warning")
    }

    static func removedPhotos(_ count: Int) -> String {
        String(localized: "Removed \(count) photos from the library.", comment: "VoiceOver, after a removal")
    }
    static func removedPhoto(_ fileName: String) -> String {
        String(localized: "Removed “\(fileName)” from the library.", comment: "VoiceOver, after one photo was removed; its file name, or a copy's name")
    }
    static func removedProject(_ name: String) -> String {
        String(localized: "Removed the project “\(name)” from the library.", comment: "VoiceOver, after a project was removed")
    }

    /// Activity, when Show in Finder left photos out.
    static func notShown(_ outcome: FinderReveal.Outcome) -> String {
        let count = outcome.skipped
        return outcome.missing > 0
            ? String(localized: "\(count) photos weren't shown because their originals are offline or missing.",
                     comment: "Activity, after Show in Finder")
            : String(localized: "\(count) photos weren't shown because their originals are offline.",
                     comment: "Activity, after Show in Finder")
    }

    /// A confirmation's words.
    struct Alert: Equatable {
        var title: String
        var message: String
    }

    /// The confirmation's title and message, its sentences in order.
    static func alert(_ confirmation: RemovalConfirmation) -> Alert {
        let title = switch confirmation.title {
        case .photo(let fileName):
            String(localized: "Remove “\(fileName)” from the library?", comment: "Removal confirmation title: one photo's file name, or a copy's name")
        case .photos(let count):
            String(localized: "Remove \(count) photos from the library?", comment: "Removal confirmation title")
        case .project(let name):
            String(localized: "Remove the project “\(name)” from the library?", comment: "Removal confirmation title")
        }
        return Alert(title: title, message: confirmation.sentences.map(sentence).joined(separator: " "))
    }

    private static func sentence(_ sentence: RemovalConfirmation.Sentence) -> String {
        switch sentence {
        case .projectPhotos(let count):
            String(localized: "Its \(count) photos are removed with it.", comment: "Project removal confirmation")
        case .projectHasNoPhotos:
            String(localized: "It has no photos.", comment: "Project removal confirmation")
        case .pairFiles(let count):
            String(localized: "Both files of each RAW+JPEG pair are removed, \(count) files in all.",
                   comment: "Removal confirmation: pairs add files beyond the photos selected")
        case .projectAlbums(let count):
            String(localized: "Its \(count) albums are deleted.", comment: "Project removal confirmation: its albums and smart albums")
        case .copiesOfPhoto(1):
            String(localized: "Its copy is removed with it.",
                   comment: "Photo removal confirmation: one original with one copy (made with Duplicate), which goes too")
        case .copiesOfPhoto(let count):
            String(localized: "Its \(count) copies are removed with it.",
                   comment: "Photo removal confirmation: one original whose copies (made with Duplicate) go too; two or more")
        case .copiesOfPhotos(let count):
            String(localized: "\(count) copies of these photos are removed with them.",
                   comment: "Photo removal confirmation: several photos, some with copies (made with Duplicate) that were not selected")
        case .photosConsequences:
            String(localized: "The files and their sidecar files stay on disk, unchanged. Their edits are lost, along with their ratings, keywords and albums in the library. You can't undo this action.",
                   comment: "Photo removal confirmation")
        case .copyConsequences:
            String(localized: "The original and its file are not affected. The copy's edits are lost, along with its rating, keywords and albums. You can't undo this action.",
                   comment: "Photo removal confirmation: the one photo is a copy made with Duplicate")
        case .copiesConsequences:
            String(localized: "The originals and their files are not affected. The copies' edits are lost, along with their ratings, keywords and albums. You can't undo this action.",
                   comment: "Photo removal confirmation: every photo is a copy made with Duplicate")
        case .projectConsequences:
            String(localized: "The folder, its files and their sidecar files stay on disk, unchanged. The photos' edits are lost, along with their ratings, keywords and albums in the library. You can't undo this action.",
                   comment: "Project removal confirmation")
        case .emptyProjectConsequences:
            String(localized: "The folder stays on disk, unchanged.", comment: "Project removal confirmation: a project without photos")
        }
    }
}

/// A removal read from the catalog and waiting for the person's answer:
/// what the confirmation says, and what follows if they choose Remove.
struct PendingRemoval: Identifiable {
    let id = UUID()
    var text: LibraryOpsText.Alert
    /// The Activity row's title, should it fail.
    var title: String
    var job: RemovalJob
    var failure: String
    /// What VoiceOver hears once it is done.
    var announcement: String
    var remove: @Sendable () async throws -> RemovalResult
}
