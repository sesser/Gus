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
        /// The stored stack cannot be read (a newer build's, or damaged):
        /// editing is off so it is never written over.
        case unreadable(EditStack.ReadFailure)
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
    /// The crop being edited, while the loupe shows the crop frame.
    private(set) var cropSession: CropSession?
    /// The whole photo with its other adjustments, under the crop frame.
    private(set) var cropImage: CGImage?

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

    /// The values last saved for the photo; `adjustments` runs ahead of them
    /// while a control is being dragged.
    var savedAdjustments: Adjustments { committed }
    @ObservationIgnored private var sourceURL: URL?
    @ObservationIgnored private var session: LiveRenderSession?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var cropImageTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRender: (values: Adjustments, interactive: Bool)?
    @ObservationIgnored private var lastFrameWasInteractive = false
    /// The frame being rendered is a draft.
    @ObservationIgnored private var renderingInteractive = false
    @ObservationIgnored private var isChanging = false
    /// Values shown without being applied (a table hovered in a menu).
    @ObservationIgnored private var previewValues: Adjustments?
    @ObservationIgnored private var isPreviewing = false
    /// The loupe showed its cached rendition when the preview began.
    @ObservationIgnored private var previewRestoresCache = false
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
        // Moving to another photo (or closing the loupe) keeps the crop being edited.
        endCrop(save: true)
        finishSession()
        item = newItem
        isPreviewing = false
        previewValues = nil
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
        let generator = library.previews.interactiveGenerator
        let colorSpace = library.previews.displayColorSpace
        let versionID = newItem.versionID
        loadTask = Task {
            let stack: EditStack
            do {
                stack = try await catalog.version(id: versionID)?.decodedEditStack() ?? .identity
            } catch {
                guard !Task.isCancelled, item?.versionID == versionID else { return }
                state = .unreadable(EditStack.ReadFailure(error))
                return
            }
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
        cropSession = nil
        cropImage = nil
        cropImageTask?.cancel()
        cropImageTask = nil
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
        next.enableModules(changedFrom: adjustments)
        isPreviewing = false
        previewValues = nil
        showsOriginal = false
        isChanging = phase == .changing
        if next != adjustments {
            adjustments = next
            showsLive = true
            requestRender(interactive: phase == .changing)
            if cropSession != nil, phase == .committed { renderCropImage() }
        } else if phase == .committed, lastFrameWasInteractive || renderingInteractive
                    || pendingRender?.interactive == true {
            // The drag's frames were drafts: render the final one at full quality.
            requestRender(interactive: false)
        }
        if phase == .committed { commit(actionName) }
    }

    /// Back to the defaults for one heading.
    func reset(_ section: Adjustments.Section) {
        change(String(localized: "Reset \(AdjustText.title(section))", comment: "Undo action name; the heading's name"),
               phase: .committed) { $0 = $0.resetting(section) }
    }

    /// Turns a group's edits off (kept, not rendered) or back on, as one undo step.
    func setEnabled(_ group: Adjustments.Group, _ isEnabled: Bool) {
        let title = AdjustText.title(group)
        change(isEnabled ? String(localized: "Turn On \(title)", comment: "Undo action name; the group's name")
                         : String(localized: "Turn Off \(title)", comment: "Undo action name; the group's name"),
               phase: .committed) { $0.setEnabled(group, isEnabled) }
    }

    /// Turns every edited group of a heading off or back on, as one undo step.
    func setEnabled(_ section: Adjustments.Section, _ isEnabled: Bool) {
        let title = AdjustText.title(section)
        change(isEnabled ? String(localized: "Turn On \(title)", comment: "Undo action name; the group's name")
                         : String(localized: "Turn Off \(title)", comment: "Undo action name; the group's name"),
               phase: .committed) { values in
            for group in section.groups where values.isModified(group) {
                values.setEnabled(group, isEnabled)
            }
        }
    }

    func resetAll() {
        change(String(localized: "Reset Adjustments", comment: "Undo action name"), phase: .committed) {
            $0 = Adjustments(stack: EditStack(operations: $0.preserved))
        }
    }

    func toggleOriginal() {
        guard state == .ready, cropSession == nil else { return }
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

    // MARK: Previewing

    /// Shows the photo with `body` applied, without changing or saving
    /// anything; nil shows the applied values again while previewing goes on.
    func preview(_ body: ((inout Adjustments) -> Void)?) {
        guard state == .ready else { return }
        if !isPreviewing {
            isPreviewing = true
            previewRestoresCache = !showsLive
        }
        if let body {
            var values = adjustments
            body(&values)
            values.enableModules(changedFrom: adjustments)
            previewValues = values
            showsLive = true
        } else {
            previewValues = nil
        }
        requestRender(interactive: false)
    }

    /// Back to the applied values (the menu closed without a pick).
    func endPreview() {
        guard isPreviewing else { return }
        isPreviewing = false
        previewValues = nil
        if previewRestoresCache, adjustments == committed, !showsOriginal {
            // The cached rendition shows the saved values: no need to wait for a frame.
            showsLive = false
        }
        requestRender(interactive: false)
    }

    // MARK: Rendering

    /// Renders the latest values; requests made while a frame renders collapse
    /// into one.
    private func requestRender(interactive: Bool) {
        pendingRender = (previewValues ?? (showsOriginal ? .none : adjustments), interactive)
        guard renderTask == nil, let session else { return }
        renderTask = Task {
            while let next = pendingRender, !Task.isCancelled {
                pendingRender = nil
                renderingInteractive = next.interactive
                defer { renderingInteractive = false }
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

    /// The photo with its saved adjustments but no effects (look-up table,
    /// vignette, grain), at the loupe's size, for previewing tables on it.
    func lookTablePreviewBase() async -> DecodedImage? {
        guard let session else { return nil }
        return try? await session.render(Self.withoutEffects(committed)).image
    }

    /// Identifies what `lookTablePreviewBase` would render.
    var lookTablePreviewKey: String {
        "\(item?.versionID ?? 0)-\(Self.withoutEffects(adjustments).editStack.renderHash)"
    }

    private static func withoutEffects(_ values: Adjustments) -> Adjustments {
        values.effective.resetting(.effects)
    }

    // MARK: Cropping

    /// Shows the whole photo under the crop frame, starting from its saved crop
    /// (or the camera's).
    func beginCrop() {
        guard state == .ready, cropSession == nil, cropImageTask == nil, let url = sourceURL,
              let versionID = item?.versionID else { return }
        showsOriginal = false
        isPreviewing = false
        previewValues = nil
        let start = adjustments.crop
        cropImageTask?.cancel()
        cropImageTask = Task {
            let cameraRect = await Task.detached(priority: .userInitiated) { CameraFrame.rect(of: url) }.value ?? .full
            guard !Task.isCancelled, item?.versionID == versionID, let image = await renderWholeImage() else { return }
            // A photo without a crop shows its camera's frame; with one, the rectangle
            // is in the whole sensor already.
            let rect = start.rect ?? (start.isIdentity ? cameraRect : .full)
            cropSession = CropSession(crop: Crop(rect: rect, quarterTurns: start.quarterTurns, angle: start.angle),
                                      cameraRect: cameraRect,
                                      sourceSize: CGSize(width: image.width, height: image.height))
            cropImage = image
            cropImageTask = nil
        }
    }

    /// Ends the crop session, saving it as one undo step unless `save` is false.
    func endCrop(save: Bool) {
        cropImageTask?.cancel()
        cropImageTask = nil
        guard let session = cropSession else { return }
        cropSession = nil
        cropImage = nil
        guard save, session.saved != adjustments.crop else { return }
        change(String(localized: "Crop", comment: "Undo action name"), phase: .committed) { $0.crop = session.saved }
    }

    /// The photo's own frame again, without turns or straightening.
    func resetCrop() {
        if var session = cropSession {
            session.crop = Crop(rect: session.cameraRect)
            session.aspect = .free
            cropSession = session
        } else {
            change(String(localized: "Reset Crop", comment: "Undo action name"), phase: .committed) { $0.crop = Crop() }
        }
    }

    /// Moves or resizes the frame (from the loupe's drags).
    func setCropRect(_ rect: CropRect) {
        cropSession?.crop.rect = rect
    }

    /// Straightens, keeping the frame inside the image: each angle fits the
    /// rectangle the straightening started from.
    func straighten(_ angle: Double, phase: EditPhase) {
        guard var session = cropSession else {
            beginCrop(then: { $0.straighten(angle, phase: phase) })
            return
        }
        let start = session.straightenStart ?? session.rect
        let angle = min(max(angle, Crop.angleRange.lowerBound), Crop.angleRange.upperBound)
        session.crop.angle = angle
        session.crop.rect = CropGeometry.fitted(start, angle: angle, size: session.turnedSize)
        session.isStraightening = phase == .changing
        session.straightenStart = phase == .changing ? start : nil
        cropSession = session
    }

    /// Turns the photo a quarter turn, frame and all.
    func rotate(clockwise: Bool) {
        guard var session = cropSession else {
            beginCrop(then: { $0.rotate(clockwise: clockwise) })
            return
        }
        session.crop.quarterTurns = (session.crop.quarterTurns + (clockwise ? 1 : 3)) % 4
        session.crop.rect = session.rect.turned(clockwise: clockwise)
        cropSession = session
    }

    /// Holds the frame to `aspect`. Picking the aspect already held turns the
    /// frame from landscape to portrait or back.
    func setCropAspect(_ aspect: CropAspect) {
        guard var session = cropSession else {
            beginCrop(then: { $0.setCropAspect(aspect) })
            return
        }
        let size = session.turnedSize
        if aspect == session.aspect, let ratio = aspect.ratio, ratio != 1 {
            session.crop.rect = CropGeometry.flipped(session.rect, angle: session.crop.angle, size: size)
        } else {
            session.aspect = aspect
            if let ratio = session.ratio {
                session.crop.rect = CropGeometry.constrained(session.rect, to: ratio, angle: session.crop.angle, size: size)
            }
        }
        cropSession = session
    }

    /// Starts a session and runs `body` once it is ready.
    private func beginCrop(then body: @escaping @MainActor (AdjustmentEditor) -> Void) {
        beginCrop()
        guard let task = cropImageTask else { return }
        Task {
            await task.value
            if cropSession != nil { body(self) }
        }
    }

    /// Renders the photo with its other adjustments over the whole sensor, at the loupe's size.
    private func renderWholeImage() async -> CGImage? {
        guard let session else { return nil }
        var values = adjustments
        values.crop = Crop(rect: .full)
        return try? await session.render(values).image.cgImage
    }

    /// Renders the image under the crop frame again after another adjustment changed.
    private func renderCropImage() {
        cropImageTask?.cancel()
        cropImageTask = Task {
            guard let image = await renderWholeImage(), !Task.isCancelled, cropSession != nil else { return }
            cropImage = image
        }
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
        let adjuster = AutoAdjuster(generator: library.previews.interactiveGenerator)
        let values = adjustments
        Task {
            let result = await Task.detached(priority: .userInitiated) { try? work(adjuster, url, values) }.value
            isMeasuring = false
            guard let result, item?.versionID == versionID else { return }
            change(actionName, phase: .committed, result)
        }
    }
}
