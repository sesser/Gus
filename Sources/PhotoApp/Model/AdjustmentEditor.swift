import AppKit
import Observation
import PhotoCore
import PhotoUI
import os

/// Where a control's change is in its gesture.
enum EditPhase {
    /// A slider is being dragged: render, but do not save yet.
    case changing
    /// The drag ended, or a value was typed or picked: save, as one undo step.
    case committed
}

/// Adjustments of the photo shown in the loupe, while they are being edited.
///
/// Controls change `adjustments`; each change renders a frame through a
/// `LiveRenderSession`, which the loupe shows instead of its cached preview.
/// When a gesture ends the stack is saved (one undo step), the item's edit hash
/// changes, and the last frame becomes the new preview in the memory cache, so
/// the loupe switches back to its usual renditions without a flash.
@MainActor
@Observable
final class AdjustmentEditor {
    enum State: Equatable {
        /// No photo, or the loupe is closed.
        case idle
        case loading
        case ready
        case video
        case offline
    }

    @ObservationIgnored weak var library: LibraryModel?

    private(set) var state = State.idle
    /// The photo being edited.
    private(set) var item: CatalogItem?
    private(set) var isRaw = false
    /// What the decoder chose for a RAW file (as-shot white balance, defaults).
    private(set) var rawDefaults: RawDefaults?
    /// Current values, ahead of the catalog while a slider is dragged.
    private(set) var adjustments = Adjustments()
    /// Histogram of the latest frame.
    private(set) var histogram: Histogram?
    /// Auto exposure or white balance is measuring.
    private(set) var isMeasuring = false
    /// The loupe should show `frame` rather than its cached renditions.
    private(set) var showsLive = false
    /// Bumped for every new frame.
    private(set) var frameRevision = 0
    @ObservationIgnored private(set) var frame: LiveRenderSession.Frame?

    /// Shows the photo without adjustments (before/after).
    var showsOriginal = false {
        didSet {
            guard oldValue != showsOriginal, state == .ready else { return }
            if showsOriginal {
                showsLive = true
                requestRender(interactive: false)
            } else if adjustments == committed {
                // The cached preview already shows the saved adjustments.
                showsLive = false
            } else {
                requestRender(interactive: false)
            }
        }
    }

    @ObservationIgnored private var committed = Adjustments()
    @ObservationIgnored private var sourceURL: URL?
    @ObservationIgnored private var session: LiveRenderSession?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRender: (values: Adjustments, interactive: Bool)?
    @ObservationIgnored private var lastFrameWasInteractive = false
    @ObservationIgnored private var isChanging = false
    /// Hashes saved while this photo was open; their renditions are deleted
    /// when it closes, except the last one.
    @ObservationIgnored private var sessionHashes: Set<String> = []

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "edits")

    // MARK: Following the loupe

    /// Called by the loupe with the photo it shows (nil when it closes).
    func follow(_ newItem: CatalogItem?) {
        if let newItem, newItem.versionID == item?.versionID {
            item = newItem
            return
        }
        finishSession()
        item = newItem
        guard let newItem, let library else {
            state = .idle
            return
        }
        if newItem.isVideo {
            state = .video
            return
        }
        guard let url = library.sourceURL(for: newItem) else {
            state = .offline
            return
        }
        state = .loading
        sourceURL = url
        isRaw = SupportedFormats.isRaw(pathExtension: url.pathExtension)
        let catalog = library.catalog
        let generator = library.previews.generator
        let colorSpace = library.previews.displayColorSpace
        let versionID = newItem.versionID
        loadTask = Task {
            let stack = (try? await catalog.version(id: versionID)?.decodedEditStack()) ?? .identity
            let defaults = SupportedFormats.isRaw(pathExtension: url.pathExtension)
                ? await Task.detached(priority: .userInitiated) { RawDefaults(source: url) }.value : nil
            guard !Task.isCancelled, item?.versionID == versionID else { return }
            let loaded = Adjustments(stack: stack)
            adjustments = loaded
            committed = loaded
            rawDefaults = defaults
            session = LiveRenderSession(source: url, generator: generator, colorSpace: colorSpace)
            state = .ready
            // A frame for the histogram, once the person settles on this photo.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, item?.versionID == versionID else { return }
            requestRender(interactive: false)
        }
    }

    private func finishSession() {
        loadTask?.cancel()
        loadTask = nil
        renderTask?.cancel()
        renderTask = nil
        pendingRender = nil
        session = nil
        frame = nil
        histogram = nil
        showsLive = false
        showsOriginal = false
        isChanging = false
        rawDefaults = nil
        sourceURL = nil
        pruneRenditions()
        adjustments = Adjustments()
        committed = Adjustments()
    }

    /// Deletes the cached renditions of intermediate edits of the photo being closed.
    private func pruneRenditions() {
        guard let item, let library else { return }
        let keep: Set<String> = [committed.editStack.renderHash, EditStack.identity.renderHash]
        for hash in sessionHashes.subtracting(keep) {
            for tier in PreviewTier.allCases {
                if let key = PreviewCacheKey(contentHash: item.contentHash, editStackHash: hash, tier: tier) {
                    library.previews.cache.remove(key)
                }
            }
        }
        sessionHashes = []
    }

    // MARK: Changing values

    /// Applies a change from a control. `actionName` names the undo step.
    func change(_ actionName: String, phase: EditPhase, _ body: (inout Adjustments) -> Void) {
        guard state == .ready else { return }
        var next = adjustments
        body(&next)
        showsOriginal = false
        isChanging = phase == .changing
        if next != adjustments {
            adjustments = next
            showsLive = true
            requestRender(interactive: phase == .changing)
        } else if phase == .committed, lastFrameWasInteractive {
            requestRender(interactive: false)
        }
        if phase == .committed { commit(actionName) }
    }

    /// Back to the defaults for one heading.
    func reset(_ section: Adjustments.Section) {
        change(String(localized: "Reset \(AdjustText.title(section))", comment: "Undo action name; the heading's name"),
               phase: .committed) { $0 = $0.resetting(section) }
    }

    func resetAll() {
        change(String(localized: "Reset Adjustments", comment: "Undo action name"), phase: .committed) {
            $0 = Adjustments(stack: EditStack(operations: $0.preserved))
        }
    }

    func toggleOriginal() {
        guard state == .ready else { return }
        showsOriginal.toggle()
    }

    private func commit(_ actionName: String) {
        guard let item, adjustments != committed else { return }
        apply(adjustments.editStack, toVersion: item.versionID, undoingTo: committed.editStack, actionName: actionName)
    }

    /// Saves `stack` for a version and registers the previous stack for undo.
    /// Works for any version, so undo still reaches a photo that is no longer open.
    func apply(_ stack: EditStack, toVersion versionID: Int64, undoingTo previous: EditStack, actionName: String) {
        guard let library else { return }
        let catalog = library.catalog
        library.persist {
            try await catalog.setEditStack(stack, forVersion: versionID)
        }
        let hash = stack.renderHash
        if versionID == item?.versionID {
            let values = Adjustments(stack: stack)
            committed = values
            sessionHashes.insert(hash)
            if adjustments != values {
                // Undo or redo on the open photo.
                adjustments = values
                showsLive = true
                requestRender(interactive: false)
            }
        }
        library.setEditStackHash(hash, forVersion: versionID)
        if versionID == item?.versionID {
            item?.editStackHash = hash
            seedPreviewIfRendered()
        }

        library.undoManager.registerUndo(withTarget: self) { editor in
            editor.apply(previous, toVersion: versionID, undoingTo: stack, actionName: actionName)
        }
        library.undoManager.setActionName(actionName)
    }

    /// A stack saved for a version by something else (paste, a preset, their undo).
    func catalogChanged(_ stack: EditStack, forVersion versionID: Int64) {
        guard versionID == item?.versionID, state == .ready else { return }
        let values = Adjustments(stack: stack)
        committed = values
        adjustments = values
        item?.editStackHash = stack.renderHash
        showsOriginal = false
        showsLive = false
        // For the histogram; the loupe loads the new edit's renditions itself.
        requestRender(interactive: false)
    }

    /// Once the frame on screen shows the saved values, it becomes the cached
    /// preview of the new edit hash and the loupe goes back to its renditions.
    private func seedPreviewIfRendered() {
        guard let library, let item, let frame, !isChanging, !showsOriginal, !lastFrameWasInteractive,
              frame.adjustments == committed, adjustments == committed,
              item.editStackHash == committed.editStack.renderHash,
              let request = library.previewRequest(for: item, tier: .preview)
        else { return }
        library.previews.insertIntoMemory(frame.image.cgImage, for: request)
        showsLive = false
    }

    // MARK: Rendering

    /// Renders the latest values; requests made while a frame renders collapse
    /// into one.
    private func requestRender(interactive: Bool) {
        pendingRender = (showsOriginal ? .none : adjustments, interactive)
        guard renderTask == nil, let session else { return }
        renderTask = Task {
            while let next = pendingRender, !Task.isCancelled {
                pendingRender = nil
                do {
                    let rendered = try await session.render(next.values, interactive: next.interactive)
                    guard !Task.isCancelled, session === self.session else { break }
                    frame = rendered
                    lastFrameWasInteractive = next.interactive
                    if !showsOriginal || next.values == .none {
                        histogram = rendered.histogram
                    }
                    frameRevision += 1
                    seedPreviewIfRendered()
                } catch {
                    Self.log.error("Live render failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            if session === self.session { renderTask = nil }
        }
    }

    /// The photo with its saved adjustments but no look-up table, at the loupe's
    /// size, for previewing tables on it.
    func lookTablePreviewBase() async -> DecodedImage? {
        guard let session else { return nil }
        var values = committed
        values.lookTable = LookTable()
        return try? await session.render(values).image
    }

    /// Identifies what `lookTablePreviewBase` would render.
    var lookTablePreviewKey: String {
        var values = adjustments
        values.lookTable = LookTable()
        return "\(item?.versionID ?? 0)-\(values.editStack.renderHash)"
    }

    // MARK: Auto

    func autoExposure() {
        measure(String(localized: "Auto Exposure", comment: "Undo action name")) { adjuster, url, values in
            let ev = try adjuster.exposure(source: url, adjustments: values)
            return { $0.exposure.ev = ev }
        }
    }

    func autoWhiteBalance() {
        measure(String(localized: "Auto White Balance", comment: "Undo action name")) { adjuster, url, values in
            let balance = try adjuster.whiteBalance(source: url, adjustments: values)
            return { $0.whiteBalance = balance }
        }
    }

    private func measure(_ actionName: String,
                         _ work: @escaping @Sendable (AutoAdjuster, URL, Adjustments) throws -> @Sendable (inout Adjustments) -> Void) {
        guard state == .ready, !isMeasuring, let library, let url = sourceURL, let versionID = item?.versionID else { return }
        isMeasuring = true
        let adjuster = AutoAdjuster(generator: library.previews.generator)
        let values = adjustments
        Task {
            let result = await Task.detached(priority: .userInitiated) { try? work(adjuster, url, values) }.value
            isMeasuring = false
            guard let result, item?.versionID == versionID else { return }
            change(actionName, phase: .committed, result)
        }
    }
}
