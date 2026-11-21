import AppKit
import os
import PhotoCore
import PhotoUI

/// One merge as its undo step holds it (hdr-merge design §9).
@MainActor
private final class MergeStep {
    let master: MergedMaster
    let url: URL
    /// The frames' versions, which Undo selects again.
    let frames: [Int64]
    /// The photo as Undo took it out, for Redo.
    var removed: RemovedMaster?

    init(master: MergedMaster, url: URL, frames: [Int64]) {
        self.master = master
        self.url = url
        self.frames = frames
    }
}

/// File ▸ Merge to HDR… (issue #150): the sheet's frozen frames and choices,
/// and the merge running behind it once the sheet has closed.
@MainActor
@Observable
final class MergeModel {
    @ObservationIgnored weak var library: LibraryModel?
    @ObservationIgnored private let defaults: UserDefaults

    static let formatKey = "merge.format"

    /// The format chosen last, kept as a preference (design §5.3); TIFF at first.
    var format: MergeFormat {
        didSet {
            guard format != oldValue else { return }
            defaults.set(format.rawValue, forKey: Self.formatKey)
            updateName()
        }
    }

    // MARK: The sheet

    /// The sheet's frames, reference, boxes and disk answers (PhotoCore's
    /// rules); nil while the frames are read. Made new on every open, so the
    /// reference is the default and both boxes are on (AC3c, AC9a).
    private(set) var sheet: MergeSheetState?
    /// The targets' versions when the sheet opened (the landing rule compares them).
    private(set) var targetIDs: [Int64] = []
    /// A disk check has taken over half a second (the sheet's small spinner).
    private(set) var isCheckingSlowly = false
    /// The reference's thumbnail for the header; the previous reference's
    /// stays until the new one is ready (design §5.8).
    private(set) var previewImage: CGImage?
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var nameTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var diskTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var slowTask: Task<Void, Never>?
    @ObservationIgnored private var announceTask: Task<Void, Never>?
    /// A change of reference waits to be announced (§11): once the debounce
    /// has passed and the disk and the name are known.
    @ObservationIgnored private var announcementPending = false
    @ObservationIgnored private var debounceElapsed = false
    /// The message as VoiceOver last heard it (the sheet's own reading at open).
    @ObservationIgnored private var announcedRefusal: MergeRefusal?
    /// Debug script: a delay added to each folder check (to see a superseded
    /// answer), and the answers that came for a reference no longer chosen.
    @ObservationIgnored var debugDiskDelay: Duration = .zero
    @ObservationIgnored var debugDiscarded: [String] = []
    /// Debug script: the last announcement made after a change of reference.
    @ObservationIgnored private(set) var debugLastAnnouncement: String?

    var selection: MergeSelection? { sheet?.selection }

    /// The message the sheet shows, the first that applies (design §6).
    var refusal: MergeRefusal? { sheet?.refusal }

    /// The frames the message is about.
    var flagged: Set<Int64> { sheet?.flagged ?? [] }

    /// Merge is on: frames read, the disk asked for this reference and nothing refused, no merge running.
    var canStart: Bool { sheet?.canStart(isMerging: isMerging) ?? false }

    var framesInSeveralFolders: Bool { sheet?.framesInSeveralFolders ?? false }

    var referenceID: Int64? { sheet?.referenceID }

    /// Auto-align and De-ghost (design §5.6): on at every open, never stored.
    var options: MergeOptions {
        get { sheet?.options ?? .standard }
        set { sheet?.options = newValue }
    }

    /// The Name line: the numbered name once known, else the unnumbered
    /// candidate (`isFinal` false: shown in secondary color). Shown with a
    /// refusal too: it is the reference's, whatever stops the merge (§5.3).
    var resultName: (text: String, isFinal: Bool)? {
        sheet?.name(format: format)
    }

    /// The Name line is shown in secondary color: only the unnumbered
    /// candidate (§5.8), or a refusal stands (D-H12), so it never reads as a
    /// promise while Merge is off.
    var resultNameIsTentative: Bool {
        guard let name = resultName else { return false }
        return !name.isFinal || refusal != nil
    }

    // MARK: The job

    /// Where the running merge is, nil when none runs.
    private(set) var progress: MergeProgress?
    /// The file the running merge writes.
    private(set) var jobName: String?
    /// When the running merge started (File ▸ Stop names the newest job).
    private(set) var started: Date?
    var isMerging: Bool { started != nil }
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "merge")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        format = defaults.string(forKey: Self.formatKey).flatMap(MergeFormat.init(rawValue:)) ?? .tiff
    }

    // MARK: Opening

    /// File ▸ Merge to HDR…: freezes the targets as frames and opens the sheet;
    /// the frames are read from the catalog and the disk asked off the main actor.
    func begin() {
        guard let library, library.canMerge else { return }
        stopSheetTasks()
        sheet = nil
        isCheckingSlowly = false
        previewImage = nil
        announcementPending = false
        announcedRefusal = nil
        debugDiscarded = []
        debugLastAnnouncement = nil
        let targets = library.actionTargets.map { library.items[$0] }
        targetIDs = targets.map(\.versionID)
        let ids = MergeSelection.versionIDs(for: targets)
        let online = library.onlineVolumeIDs
        let catalog = library.catalog
        library.showsMergeSheet = true
        openTask = Task {
            var frames: [MergeFrame] = []
            for id in ids {
                guard let details = try? await catalog.details(forVersion: id) else { continue }
                let name = PhotoName.naming.copyName(of: details.version, fileName: details.image.fileName)
                frames.append(MergeFrame(details: details, displayName: name,
                                         isOnline: online.contains(details.image.volumeId)))
            }
            guard !Task.isCancelled else { return }
            guard !frames.isEmpty else {
                // Every target's catalog record went missing meanwhile: nothing to show.
                Self.log.error("Merge: none of the selected photos could be read from the catalog")
                library.showsMergeSheet = false
                return
            }
            let sheet = MergeSheetState(selection: MergeSelection(frames: frames))
            self.sheet = sheet
            loadPreview()
            askDisk()
            updateName()
        }
    }

    /// A row chosen in the table (click, arrow, VoiceOver): the reference
    /// (design §5.5). `nil` and the chosen row again change nothing.
    func chooseReference(_ versionID: Int64?) {
        guard var next = sheet, next.chooseReference(versionID) else { return }
        sheet = next
        loadPreview()
        askDisk()
        updateName()
        scheduleAnnouncement()
    }

    /// Asks the disk what the current reference still needs (design §6.2,
    /// §5.8): whether every master can be read (once) and whether the
    /// reference's folder can be written to (once per folder), off the main
    /// actor. The spinner shows only when that takes over half a second.
    private func askDisk() {
        guard var sheet else { return }
        let preflight = MergePreflight.disk
        let delay = debugDiskDelay
        if sheet.unreadable == nil, !askedReadable {
            askedReadable = true
            let frames = sheet.selection.frames
            startSlowTimer()
            diskTasks.append(Task {
                let unreadable = await Task.detached { preflight.firstUnreadable(frames)?.versionID }.value
                guard !Task.isCancelled else { return }
                self.sheet?.record(unreadable: unreadable)
                diskAnswered()
            })
        }
        guard let folder = sheet.folderToAsk else { return }
        sheet.asking(folder)
        self.sheet = sheet
        startSlowTimer()
        diskTasks.append(Task {
            let writable = await Task.detached {
                if delay > .zero { try? await Task.sleep(for: delay) }
                return preflight.isWritableFolder(folder)
            }.value
            guard !Task.isCancelled, var current = self.sheet else { return }
            let decides = current.record(folder: folder, writable: writable)
            self.sheet = current
            if !decides {
                debugDiscarded.append(folder.lastPathComponent)
            }
            diskAnswered()
        })
    }
    /// Case 8 has been asked for this sheet (it doesn't depend on the reference).
    @ObservationIgnored private var askedReadable = false

    private func startSlowTimer() {
        guard slowTask == nil else { return }
        slowTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if sheet?.isDiskChecked == false { isCheckingSlowly = true }
        }
    }

    private func diskAnswered() {
        guard let sheet else { return }
        if sheet.isDiskChecked {
            slowTask?.cancel()
            slowTask = nil
            isCheckingSlowly = false
            // What the sheet says before anything is chosen is its own reading (§11).
            if !announcementPending { announcedRefusal = sheet.refusal }
        }
        announceIfReady()
    }

    /// The Name line for the chosen reference and format, decided again when
    /// the merge starts. An answer for a superseded reference or format is ignored.
    private func updateName() {
        guard let library, let sheet else { return }
        nameTask?.cancel()
        let job = HDRMergeJob(catalog: library.catalog, metadataReader: library.importer.metadataReader)
        let format = self.format
        let selection = sheet.selection
        let reference = sheet.referenceID
        // When the place can't be named (a damaged record, a folder that can't
        // be listed) the unnumbered name stands; pressing Merge says why.
        let candidate = sheet.name(format: format).text
        nameTask = Task {
            let url = try? await job.resultURL(for: selection, format: format)
            guard !Task.isCancelled else { return }
            self.sheet?.record(name: url?.lastPathComponent ?? candidate, reference: reference, format: format)
            announceIfReady()
        }
    }

    /// The reference's thumbnail; the one shown stays until it is ready.
    private func loadPreview() {
        guard let library, let sheet else { return }
        let reference = sheet.referenceID
        guard let item = library.item(versionID: reference)
                ?? targetIDs.lazy.compactMap({ library.item(versionID: $0) }).first,
              let request = library.previewRequest(for: item, tier: .thumbnail) else { return }
        let previews = library.previews
        previewTask?.cancel()
        previewTask = Task {
            let image = try? await previews.image(for: request, maxPixelSize: 88)
            guard !Task.isCancelled, self.sheet?.referenceID == reference, let image else { return }
            previewImage = image
        }
    }

    /// One announcement after a change of reference (design §11): about 0.3 s
    /// after the last change, so arrowing through rows says only the last,
    /// and only once the folder's and the name's answers are in.
    private func scheduleAnnouncement() {
        announcementPending = true
        debounceElapsed = false
        announceTask?.cancel()
        announceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            debounceElapsed = true
            announceIfReady()
        }
    }

    private func announceIfReady() {
        guard announcementPending, debounceElapsed, let sheet, sheet.isDiskChecked else { return }
        let name = sheet.name(format: format)
        guard name.isFinal else { return }
        announcementPending = false
        var text = MergeText.referenceAnnouncement(sheet.reference.displayName, result: name.text)
        switch MergeSheetState.messageChange(from: announcedRefusal, to: sheet.refusal) {
        case .none: break
        case .refusal(let refusal): text += " " + MergeText.refusal(refusal)
        case .available: text += " " + MergeText.mergeAvailable
        }
        announcedRefusal = sheet.refusal
        debugLastAnnouncement = text
        AccessibilityText.announce(text, priority: .medium)
    }

    private func stopSheetTasks() {
        for task in [openTask, nameTask, previewTask, slowTask, announceTask] { task?.cancel() }
        for task in diskTasks { task.cancel() }
        diskTasks = []
        slowTask = nil
        askedReadable = false
    }

    /// The sheet closed (Cancel, Esc, or Merge): what it was still reading
    /// stops. The choices are forgotten (the next open makes a new state).
    func sheetClosed() {
        stopSheetTasks()
    }

    // MARK: Running

    /// Merge: closes the sheet and starts the job (design §5.4, §7).
    func start() {
        guard canStart, let library, let sheet else { return }
        let selection = sheet.selection
        let options = sheet.options
        let job = HDRMergeJob(catalog: library.catalog, metadataReader: library.importer.metadataReader)
        let format = self.format
        let startedTargets = targetIDs
        let frames = selection.frames.map(\.versionID)
        library.showsMergeSheet = false
        started = Date()
        jobName = resultName?.text ?? (selection.referenceFrame.fileName as NSString).deletingPathExtension
        progress = MergeProgress(phase: .reading(1, selection.frames.count), fraction: 0)
        let writes = library.writes
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                progress = nil
                started = nil
                jobName = nil
                task = nil
            }
            do {
                jobName = try await job.resultURL(for: selection, format: format).lastPathComponent
                let result = try await job.run(selection, format: format, options: options, progress: { [weak self] progress in
                    Task { @MainActor [weak self] in self?.update(progress) }
                }, catalogue: { insert in
                    try await Self.onWriteChain(writes, insert)
                })
                await finished(result, frames: frames, startedTargets: startedTargets)
            } catch is CancellationError {
                library.report(MergeText.stopped, action: MergeText.title, warning: false,
                               announcing: MergeText.announceStopped)
            } catch let failure as HDRMergeJob.Failure {
                Self.log.error("Merge failed: \(String(describing: failure), privacy: .private)")
                let text: String
                if case .catalogFailed = failure {
                    text = MergeText.reason(failure)
                } else {
                    text = MergeText.failed + " " + MergeText.reason(failure)
                }
                library.report(text, action: MergeText.title, warning: true, announcing: MergeText.announceFailed)
            } catch {
                Self.log.error("Merge failed: \(String(describing: error), privacy: .private)")
                library.report(MergeText.failed + " " + error.localizedDescription, action: MergeText.title,
                               warning: true, announcing: MergeText.announceFailed)
            }
        }
    }

    /// File ▸ Stop Merge and the popover's Stop.
    func cancel() {
        task?.cancel()
    }

    /// Waits for the running merge to end (the debug script's `merge wait`).
    func waitUntilDone() async {
        await task?.value
    }

    /// Waits for the running merge to end, or for `timeout`, whichever is first
    /// (Stop and Quit: a stopped merge cleans up before the app goes). `task`
    /// is cleared when the merge's task ends.
    func waitUntilDone(timeout: Duration) async {
        await MainActorWait.whileTrue({ task != nil }, timeout: timeout)
    }

    private func update(_ next: MergeProgress) {
        guard progress != nil else { return }
        // Reports hop to the main actor one by one: never backward.
        if let current = progress, next.fraction < current.fraction { return }
        progress = next
    }

    /// Runs `insert` on the library's write chain, after every change made
    /// before it, and gives its result back.
    private static func onWriteChain(_ writes: WriteChain,
                                     _ insert: @escaping @Sendable () async throws -> MergedMaster) async throws
        -> MergedMaster {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                writes.enqueue {
                    do {
                        continuation.resume(returning: try await insert())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: Landing

    private func finished(_ result: HDRMergeJob.Result, frames: [Int64], startedTargets: [Int64]) async {
        guard let library else { return }
        let path = result.url.path
        let name = result.url.lastPathComponent
        library.report(MergeText.merged(result.frameCount, path: path), action: MergeText.title, warning: false,
                       announcing: MergeText.announceMerged(name))
        guard let master = result.master else {
            // Another import catalogued the file first: it is in the library, not ours to undo.
            await show(result.existingVersionID, startedTargets: startedTargets)
            return
        }
        if library.writesSidecars {
            let sidecars = library.sidecars
            let mounted = library.onlineVolumeIDs
            library.writes.enqueue {
                do {
                    _ = try await sidecars.writeSidecars(forImages: [master.imageID], mountedVolumes: mounted)
                } catch {
                    // A sidecar that couldn't be written is flagged by the sync itself;
                    // this is the catalog failing under it.
                    Self.log.error("Merge: the sidecar step failed: \(String(describing: error), privacy: .private)")
                }
            }
        }
        let step = MergeStep(master: master, url: result.url, frames: frames)
        registerUndo(step, isUndo: true)
        await show(master.versionID, startedTargets: startedTargets)
    }

    /// Puts the merged photo on screen when the source holds it; it takes the
    /// selection only when nothing was touched meanwhile (`MergeLanding`).
    /// Reads through the write chain (`writes.read`), so never from inside a
    /// write: it would wait for itself.
    private func show(_ versionID: Int64?, startedTargets: [Int64]) async {
        guard let library else { return }
        let filter = library.filter
        let catalog = library.catalog
        _ = try? await library.writes.read {
            try await catalog.libraryItems(matching: filter)
        } apply: { items in
            let shown = versionID.map { id in items.contains { $0.versionID == id } } ?? false
            let now = library.actionTargets.map { library.items[$0].versionID }
            let focus = library.focusedItem?.versionID
            if let versionID, MergeLanding.selects(started: startedTargets, now: now, showsGrid: library.mode == .grid,
                                                   shown: shown) {
                library.replaceItems(items, selecting: [versionID], focusVersionID: versionID)
            } else {
                library.replaceItems(items, selecting: now, focusVersionID: focus)
            }
        }
        await library.refreshProjects()
        await library.refreshKeywords()
    }

    /// One step, "Merge to HDR" (design §9): Undo takes the photo out of the
    /// library and leaves its file; Redo puts the same photo back when its
    /// file is unchanged. Both run on the write chain, after what they reverse.
    private func registerUndo(_ step: MergeStep, isUndo: Bool) {
        guard let library else { return }
        let undoManager = library.undoManager
        // The merge ends on its own, outside any event: a group of its own
        // (the debug script turns grouping by event off).
        let opensGroup = undoManager.groupingLevel == 0
        if opensGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: library) { [weak self] model in
            let catalog = model.catalog
            model.persist {
                if isUndo {
                    step.removed = try await catalog.removeMergedMaster(imageID: step.master.imageID)
                    // Nothing was there to take out (a Redo couldn't put it back): nothing to say.
                    guard step.removed != nil else { return }
                    model.report(MergeText.removedFromLibrary(step.url.lastPathComponent, path: step.url.path),
                                 action: MergeText.title)
                    await self?.hide(step)
                } else if let removed = step.removed {
                    if try await catalog.restoreMergedMaster(removed, fileAt: step.url) {
                        // Not here: this runs as the write chain's tail, and `show`
                        // reads through the chain, which would wait for this very
                        // write and never return (QA Q1). Once it has ended.
                        model.writes.afterPendingWrites {
                            await self?.show(step.master.versionID, startedTargets: [])
                        }
                    } else {
                        model.report(MergeText.notAddedBack(step.url.lastPathComponent), action: MergeText.title,
                                     warning: true)
                    }
                }
            }
            self?.registerUndo(step, isUndo: !isUndo)
        }
        undoManager.setActionName(MergeText.title)
        if opensGroup { undoManager.endUndoGrouping() }
    }

    /// Takes the merged photo off the screen and selects the frames again.
    private func hide(_ step: MergeStep) async {
        guard let library else { return }
        let remaining = library.items.filter { $0.versionID != step.master.versionID }
        let frames = step.frames.filter { id in remaining.contains { $0.versionID == id } }
        library.replaceItems(remaining, selecting: frames, focusVersionID: frames.first ?? library.focusedItem?.versionID)
        await library.refreshProjects()
        await library.refreshKeywords()
    }
}

extension LibraryModel {
    /// File ▸ Merge to HDR… and the grid's context item (design §4): two
    /// targets or more (a grouped pair is one), no merge running, and no
    /// other sheet, dialog or alert up. The rest is said in the sheet.
    var canMerge: Bool {
        actionTargets.count >= MergeLimits.minFrames && !merge.isMerging && !otherModalIsUp && !showsPresetSheet
    }
}
