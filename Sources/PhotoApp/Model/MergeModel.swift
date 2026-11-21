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

    /// The frames the sheet shows, frozen when it opened; nil while they are read.
    private(set) var selection: MergeSelection?
    /// The targets' versions when the sheet opened (the landing rule compares them).
    private(set) var targetIDs: [Int64] = []
    /// The disk's answer (design §6.2): nil while it is asked.
    private(set) var diskCheck: DiskCheck?
    /// The disk is being asked, and has been for a while (the sheet's small spinner).
    private(set) var isCheckingSlowly = false
    /// The file name the result would get now.
    private(set) var resultName: String?
    /// The reference's thumbnail for the header.
    private(set) var previewImage: CGImage?
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var nameTask: Task<Void, Never>?

    enum DiskCheck: Equatable {
        case clear
        case refused(MergeRefusal, flagged: Int64)
    }

    /// The message the sheet shows, the first that applies (design §6).
    var refusal: MergeRefusal? {
        if let refusal = selection?.refusal { return refusal }
        if case .refused(let refusal, _) = diskCheck { return refusal }
        return nil
    }

    /// The frames the message is about.
    var flagged: Set<Int64> {
        if let selection, selection.refusal != nil { return selection.flagged }
        if case .refused(_, let frame) = diskCheck { return [frame] }
        return []
    }

    /// Merge is on: frames read, the disk asked and nothing refused, no merge running.
    var canStart: Bool {
        selection != nil && diskCheck == .clear && refusal == nil && !isMerging
    }

    var framesInSeveralFolders: Bool {
        guard let selection else { return false }
        return Set(selection.frames.map { $0.folder.standardizedFileURL.path }).count > 1
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
        openTask?.cancel()
        nameTask?.cancel()
        selection = nil
        diskCheck = nil
        isCheckingSlowly = false
        resultName = nil
        previewImage = nil
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
            let selection = MergeSelection(frames: frames)
            self.selection = selection
            loadPreview(selection)
            await check(selection)
        }
    }

    /// The disk's refusals, asked off the main actor (a network volume can be
    /// slow); the spinner shows only when that takes over half a second.
    private func check(_ selection: MergeSelection) async {
        let slow = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { isCheckingSlowly = true }
        }
        let answer = await Task.detached { MergePreflight.disk.check(selection) }.value
        slow.cancel()
        isCheckingSlowly = false
        guard !Task.isCancelled else { return }
        diskCheck = answer.map { .refused($0.refusal, flagged: $0.flagged) } ?? .clear
        updateName()
    }

    /// The Name line for the chosen format, decided again when the merge starts.
    private func updateName() {
        guard let library, let selection, selection.refusal == nil else { return }
        nameTask?.cancel()
        let job = HDRMergeJob(catalog: library.catalog, metadataReader: library.importer.metadataReader)
        let format = self.format
        nameTask = Task {
            let url = try? await job.resultURL(for: selection, format: format)
            guard !Task.isCancelled else { return }
            resultName = url?.lastPathComponent
        }
    }

    private func loadPreview(_ selection: MergeSelection) {
        guard let library, let item = library.item(versionID: selection.referenceFrame.versionID)
                ?? targetIDs.lazy.compactMap({ library.item(versionID: $0) }).first,
              let request = library.previewRequest(for: item, tier: .thumbnail) else { return }
        let previews = library.previews
        Task {
            let image = try? await previews.image(for: request, maxPixelSize: 88)
            previewImage = image
        }
    }

    /// The sheet closed (Cancel, Esc, or Merge): what it was still reading stops.
    func sheetClosed() {
        openTask?.cancel()
        nameTask?.cancel()
    }

    // MARK: Running

    /// Merge: closes the sheet and starts the job (design §5.4, §7).
    func start() {
        guard canStart, let library, let selection else { return }
        let job = HDRMergeJob(catalog: library.catalog, metadataReader: library.importer.metadataReader)
        let format = self.format
        let startedTargets = targetIDs
        let frames = selection.frames.map(\.versionID)
        library.showsMergeSheet = false
        started = Date()
        jobName = resultName ?? (selection.referenceFrame.fileName as NSString).deletingPathExtension
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
                let result = try await job.run(selection, format: format, progress: { [weak self] progress in
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
                        await self?.show(step.master.versionID, startedTargets: [])
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
