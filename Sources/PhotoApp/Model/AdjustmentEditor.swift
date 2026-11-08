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
/// When a gesture ends the stack is saved (one undo step); once the write has
/// landed the item's edit hash changes, and the last frame becomes the new
/// preview in the memory cache, so the loupe switches back to its usual
/// renditions without a flash.
@MainActor
@Observable
final class AdjustmentEditor {
    enum State: Equatable {
        /// Nothing to edit yet, or the loupe is closed.
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
    /// A version whose crop session starts once it has loaded (Crop from the grid).
    @ObservationIgnored private var cropsWhenReady: Int64?
    /// The whole photo with its other adjustments, under the crop frame.
    private(set) var cropImage: CGImage?
    /// The mask the Masks heading and the loupe's handles edit.
    var selectedMaskID: UUID? {
        didSet {
            guard oldValue != selectedMaskID else { return }
            if selectedMask?.components.contains(where: { $0.shape.brushComponent }) != true { isBrushing = false }
            if showsMaskOverlay, state == .ready { showsLive = true; requestRender(interactive: false) }
            schedulePrefill()
        }
    }
    /// Shows the selected mask in red over the photo.
    var showsMaskOverlay = false {
        didSet {
            guard oldValue != showsMaskOverlay, state == .ready else { return }
            // Showing the overlay ends the sharpening map: the last asked for wins (design §6).
            if showsMaskOverlay, sharpeningMap.isShown {
                _ = sharpeningMap.end()
                // The same exit as endSharpeningMap: frees the full-resolution input.
                leaveSharpeningMap()
            }
            showsLive = true
            requestRender(interactive: false)
        }
    }
    /// Interactive frames may be reduced drafts (`LiveRenderSession`); off
    /// while the loupe is zoomed in.
    @ObservationIgnored var allowsDrafts = true
    /// Drags on the photo paint into the selected mask's brush.
    var isBrushing = false {
        // Painting needs the photo on screen.
        didSet {
            if isBrushing {
                endSharpeningMap()
                pickingFringeSlot = nil
            }
        }
    }
    /// The settings the next stroke paints with (its points are unused).
    var brushTemplate = BrushStroke(size: 0.03)
    /// Clicks on the photo add a color to the selected mask's color range.
    var isSamplingColor = false {
        didSet {
            if isSamplingColor {
                endSharpeningMap()
                pickingFringeSlot = nil
            }
        }
    }
    /// The mask frame's size in pixels, from the latest frame: its proportions
    /// place masks on screen.
    private(set) var maskFrameSize: CGSize?
    /// The stroke being painted: its mask, component and index.
    @ObservationIgnored var paintingStroke: (mask: UUID, component: Int, stroke: Int)?
    /// The camera's crop of a RAW file's whole sensor, if it has one.
    @ObservationIgnored private(set) var cameraRect: CropRect?

    /// Shows the photo without adjustments (before/after).
    var showsOriginal = false {
        didSet {
            guard oldValue != showsOriginal, state == .ready else { return }
            // Show Original ends the sharpening map, by any path: the last asked for wins (design §6).
            if showsOriginal { endSharpeningMap() }
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

    // MARK: Sharpening map state

    /// Whether a map is asked for, and what it suspended (design §6). One
    /// slot serves both maps (chromatic-aberration design §6): `mapKind` says
    /// which; switching maps keeps what the first suspended.
    private(set) var sharpeningMap = SharpeningMapState()
    /// The map the slot holds while `sharpeningMap.isShown`.
    private(set) var mapKind = LiveRenderSession.Content.sharpeningMap
    var showsSharpeningMap: Bool { sharpeningMap.isShown && mapKind == .sharpeningMap }
    var showsFringeMap: Bool { sharpeningMap.isShown && mapKind == .fringeMap }
    /// What the fringe map on screen says (badge, legend, VoiceOver); nil
    /// while it is not on screen.
    private(set) var shownFringeMap: FringeMapStatus?
    /// What frames show now: the photo, or the map asked for. The fringe map
    /// is suspended while an eyedropper is armed (chromatic-aberration design §6).
    var currentContent: LiveRenderSession.Content {
        guard sharpeningMap.isShown else { return .photo }
        return mapKind == .fringeMap && pickingFringeSlot != nil ? .photo : mapKind
    }

    // MARK: Color fringes and alignment state

    /// The fringe slot whose eyedropper is armed (1 or 2), nil when none
    /// (chromatic-aberration design §4). Never saved, never an undo step.
    var pickingFringeSlot: Int? {
        didSet {
            guard oldValue != pickingFringeSlot else { return }
            fringePickRefused = false
            syncSamplePixels()
            if pickingFringeSlot != nil {
                // One picking or painting tool at a time; the photo being edited.
                isBrushing = false
                isSamplingColor = false
                if showsSharpeningMap { endSharpeningMap() }
                showsOriginal = false
            }
            guard state == .ready else { return }
            if fringeSlotIsReplaced(oldValue) || fringeSlotIsReplaced(pickingFringeSlot) || showsFringeMap {
                showsLive = true
                requestRender(interactive: false)
            }
        }
    }
    /// The pixels picks sample, held while a slot is picking (status.md OQ14);
    /// nil until the first render is done, or after a change that alters them.
    private(set) var fringeSamplePixels: FringeSamplePixels?
    @ObservationIgnored private var samplePixelsTask: Task<FringeSamplePixels?, Never>?
    @ObservationIgnored private var samplePixelsKey: SamplePixelsKey?
    /// A context of its own, so holding the pixels never queues behind a preview or slows a live frame.
    @ObservationIgnored private lazy var samplePixelsEngine = RenderEngine(contextCount: 1, name: "pixel-magnifier")
    private struct SamplePixelsKey: Equatable {
        var source: URL
        var settings: RAWDecodeSettings
        var alignment: ColorAlignment
    }
    /// The last click while picking found almost no color (design §4).
    private(set) var fringePickRefused = false
    /// The last sample: where it was taken (mask frame, unit) and whether it was refused.
    @ObservationIgnored private(set) var lastFringeSample: (point: CGPoint, refused: Bool)?
    @ObservationIgnored private var fringePickTask: Task<Void, Never>?
    /// When the last pick landed (the double-click after it is ignored).
    @ObservationIgnored var lastFringePick: Date?
    /// The full-resolution frame of a replaced slot's preview is still rendering 0.5 s on.
    private(set) var isRefiningPickPreview = false
    /// Each filled slot's color as a pixel of it looks in the photo now (linear Rec. 2020).
    private(set) var fringeSwatches: [Int: SIMD3<Double>] = [:]
    @ObservationIgnored private var swatchTask: Task<Void, Never>?
    /// Align automatically is measuring this photo.
    private(set) var isMeasuringAlignment = false
    /// The last measurement of this photo failed (its original could not be read).
    private(set) var alignmentMeasureFailed = false
    @ObservationIgnored private var alignmentTask: Task<Void, Never>?
    /// Measures a hovered preset's automatic alignment on this photo.
    @ObservationIgnored private var hoverAlignmentTask: Task<Void, Never>?
    /// What the sharpening map on screen says (badge, legend, VoiceOver);
    /// nil while the photo is on screen. Set with the frame that shows it,
    /// so nothing claims a map that is not on screen (design §5).
    private(set) var shownSharpeningMap: SharpeningMapStatus?
    /// The full-resolution map is still rendering about 0.5 s after the last input.
    private(set) var isRefiningSharpeningMap = false
    /// The loupe is zoomed in: the refined map renders at full size, not the fit size.
    @ObservationIgnored var loupeIsZoomed = false {
        didSet { if loupeIsZoomed != oldValue, sharpeningMap.isShown { scheduleMapRefinement() } }
    }
    @ObservationIgnored private var mapRefiner: SharpeningMapRefiner?
    /// The full-resolution map's input is held (for the debug script).
    var holdsFullResolutionMap: Bool { mapRefiner != nil }
    @ObservationIgnored private var mapRefineTask: Task<Void, Never>?
    @ObservationIgnored private var mapRefinement: RenderCancellation?
    /// Tells the spinner of a superseded refinement from the current one's.
    @ObservationIgnored private var mapRefineGeneration = 0

    // MARK: Machine learning noise reduction state

    /// What machine learning noise reduction does for the values being
    /// edited (ml-denoise design §3): the inspector's check box, caption,
    /// Color row and Decoder pop-up read it. Nil until the photo is ready.
    private(set) var machineLearning: MachineLearningNoiseReduction.Status?
    /// Why the values on screen (a hover preview's included) asked for it
    /// and did not get it: the caption's badge and the canvas's VoiceOver
    /// value (design §6). Changes with the frame that shows it.
    private(set) var machineLearningNotApplied: MachineLearningNoiseReduction.Reason?
    /// The loupe has waited more than 0.5 s for a frame decoded with it (design §6).
    private(set) var isAwaitingMachineLearningFrame = false
    /// The latest values asked for whose frame decodes with it, until that frame arrives.
    @ObservationIgnored private var awaitedMachineLearningValues: Adjustments?
    @ObservationIgnored private var machineLearningSpinnerTask: Task<Void, Never>?
    /// The loupe had the photo's preview cached when it arrived, so the
    /// first frame (for the histogram) is not something the person waits on.
    @ObservationIgnored private var previewWasCached = true
    /// An offline photo's stack asks for it (only "this Mac" can be told then).
    @ObservationIgnored private var offlineAsksMachineLearning = false
    /// The cached preview the photo arrived with is a fallback from a failed
    /// machine learning decode of the saved values: S8 shows with it until a
    /// frame says otherwise (design §15, DQ-3).
    @ObservationIgnored private var arrivedWithFailedFallback = false

    @ObservationIgnored private var committed = Adjustments()

    /// The values last saved for the photo; `adjustments` runs ahead of them
    /// while a control is being dragged.
    var savedAdjustments: Adjustments { committed }
    @ObservationIgnored private var sourceURL: URL?
    @ObservationIgnored private var session: LiveRenderSession?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var cropImageTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRender: (values: Adjustments, interactive: Bool,
                                                    cancellation: RenderCancellation?)?
    /// The full-quality render that follows a drag (on release, or after a
    /// pause), cancelled when new input arrives.
    @ObservationIgnored private var refinement: RenderCancellation?
    @ObservationIgnored private var refineTask: Task<Void, Never>?
    /// Fills the session's stage cache for the selected mask on idle.
    @ObservationIgnored private var prefill: RenderCancellation?
    @ObservationIgnored private var prefillTask: Task<Void, Never>?
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
            loadOfflineMachineLearning(newItem, catalog: library.catalog)
            return
        }
        state = .loading
        sourceURL = url
        isRaw = SupportedFormats.isRaw(pathExtension: url.pathExtension)
        let catalog = library.catalog
        let generator = library.previews.interactiveGenerator
        let colorSpace = library.previews.displayColorSpace
        let versionID = newItem.versionID
        let cache = library.previews.cache
        let previewKey = library.previewRequest(for: newItem, tier: .preview)?.key
        let writes = library.writes
        // The Lens kernels compile once, the first time; not on the first frame that needs them.
        Self.prepareLensKernelsOnce()
        loadTask = Task {
            let defaults = SupportedFormats.isRaw(pathExtension: url.pathExtension)
                ? await Task.detached(priority: .userInitiated) { RawDefaults(source: url) }.value : nil
            let camera = SupportedFormats.isRaw(pathExtension: url.pathExtension)
                ? await Task.detached(priority: .userInitiated) { CameraFrame.rect(of: url) }.value : nil
            let cached = await Task.detached(priority: .userInitiated) { previewKey.map(cache.contains) ?? false }.value
            let fallback = previewKey.flatMap(cache.sessionOnlyReason)
            guard !Task.isCancelled, item?.versionID == versionID else { return }
            // Through the write chain: a save of this photo can still be
            // queued (it was left and opened again before the save landed).
            // Loaded from before it, the next change would write the older
            // values back and drop that save (editor-follow-edit-drop).
            do {
                try await writes.read {
                    try await catalog.version(id: versionID)?.decodedEditStack() ?? .identity
                } apply: { stack in
                    guard item?.versionID == versionID else { return }
                    let loaded = Adjustments(stack: stack)
                    adjustments = loaded
                    committed = loaded
                    rawDefaults = defaults
                    previewWasCached = cached
                    arrivedWithFailedFallback = fallback == .failed
                    if let fallback { learnUnavailability(fallback) }
                    cameraRect = camera
                    session = LiveRenderSession(source: url, generator: generator, colorSpace: colorSpace)
                    state = .ready
                    refreshMachineLearning()
                    refreshFringeSwatches()
                    if cropsWhenReady == versionID {
                        cropsWhenReady = nil
                        beginCrop()
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, item?.versionID == versionID else { return }
                state = .unreadable(EditStack.ReadFailure(error))
                return
            }
            guard item?.versionID == versionID, state == .ready else { return }
            // A frame for the histogram, once the person settles on this photo.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, item?.versionID == versionID else { return }
            requestRender(interactive: false)
        }
    }

    /// Loads the open photo again (the debug script, after changing what this Mac reports).
    func reload() {
        let current = item
        follow(nil)
        follow(current)
    }

    private func finishSession() {
        // Another photo, or no loupe: the map ends, the overlay's preference stays.
        let restore = sharpeningMap.end()
        stopMapRefinement()
        mapRefiner = nil
        shownSharpeningMap = nil
        loadTask?.cancel()
        loadTask = nil
        renderTask?.cancel()
        renderTask = nil
        pendingRender = nil
        refineTask?.cancel()
        refineTask = nil
        refinement?.cancel()
        refinement = nil
        prefillTask?.cancel()
        prefill?.cancel()
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
        selectedMaskID = nil
        cameraRect = nil
        paintingStroke = nil
        isBrushing = false
        isSamplingColor = false
        maskFrameSize = nil
        stopAwaitingMachineLearning()
        pickingFringeSlot = nil
        fringePickTask?.cancel()
        fringePickTask = nil
        lastFringeSample = nil
        lastFringePick = nil
        shownFringeMap = nil
        mapKind = .sharpeningMap
        swatchTask?.cancel()
        if !fringeSwatches.isEmpty { fringeSwatches = [:] }
        alignmentTask?.cancel()
        alignmentTask = nil
        isMeasuringAlignment = false
        alignmentMeasureFailed = false
        offlineAsksMachineLearning = false
        arrivedWithFailedFallback = false
        previewWasCached = true
        if machineLearning != nil { machineLearning = nil }
        if machineLearningNotApplied != nil { machineLearningNotApplied = nil }
        pruneRenditions()
        adjustments = Adjustments()
        committed = Adjustments()
        if restore.overlay {
            // With no session this renders nothing; drop what it asked for.
            showsMaskOverlay = true
            pendingRender = nil
            showsLive = false
        }
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
        // New input: a pending full-quality render or cache fill is out of date.
        refineTask?.cancel()
        refinement?.cancel()
        prefillTask?.cancel()
        prefill?.cancel()
        stopMapRefinement()
        var next = adjustments
        body(&next)
        next.enableModules(changedFrom: adjustments)
        isPreviewing = false
        previewValues = nil
        showsOriginal = false
        isChanging = phase == .changing
        if next != adjustments {
            if next.colorAlignment != adjustments.colorAlignment { alignmentMeasureFailed = false }
            adjustments = next
            sharpeningMap.valuesChanged()
            showsLive = true
            refreshMachineLearning()
            refreshFringeSwatches()
            syncSamplePixels()
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
        // While the map is shown, this shows the original (which ends the map).
        if sharpeningMap.isShown {
            showsOriginal = true
            return
        }
        showsOriginal.toggle()
    }

    // MARK: Sharpening map

    /// The map can be shown: an editable photo, not cropping. (Review mode
    /// is the model's rule, `LibraryModel.canShowSharpeningMap`.)
    var canShowSharpeningMap: Bool {
        state == .ready && cropSession == nil && cropImageTask == nil
    }

    /// Shows the sharpening map in place of the photo. It suspends the mask
    /// overlay and Show Original and turns the mask tools off; the photo
    /// stays until the first map frame is ready.
    func showSharpeningMap() {
        showMap(.sharpeningMap)
    }

    /// Shows `kind` in the map slot. Over the other map it takes its place
    /// and keeps what that one suspended (chromatic-aberration design §6).
    func showMap(_ kind: LiveRenderSession.Content) {
        guard canShowSharpeningMap, kind.isMap else { return }
        if sharpeningMap.isShown {
            guard mapKind != kind else { return }
            stopMapRefinement()
            mapKind = kind
            requestRender(interactive: false)
            return
        }
        isBrushing = false
        isSamplingColor = false
        if kind == .sharpeningMap { pickingFringeSlot = nil }
        mapKind = kind
        sharpeningMap.show(overlay: showsMaskOverlay, original: showsOriginal)
        showsMaskOverlay = false
        showsOriginal = false
        requestRender(interactive: false)
    }

    /// The person hid the map: the loupe goes back to what it showed,
    /// with the overlay and Show Original if they were on (design §6).
    func hideSharpeningMap() {
        guard sharpeningMap.isShown else { return }
        let restore = sharpeningMap.hide()
        leaveSharpeningMap()
        if restore.overlay { showsMaskOverlay = true }
        if restore.original { showsOriginal = true }
        requestRender(interactive: false)
    }

    /// Something that needs the photo ended the map: the overlay's
    /// preference comes back, Show Original does not.
    func endSharpeningMap() {
        guard sharpeningMap.isShown else { return }
        let restore = sharpeningMap.end()
        leaveSharpeningMap()
        if restore.overlay { showsMaskOverlay = true }
        requestRender(interactive: false)
    }

    /// Stops refining and frees the full-resolution map's memory. The map
    /// stays on screen until the photo's frame replaces it.
    private func leaveSharpeningMap() {
        stopMapRefinement()
        mapRefiner = nil
        mapKind = .sharpeningMap
    }

    private func stopMapRefinement() {
        mapRefineTask?.cancel()
        mapRefineTask = nil
        mapRefinement?.cancel()
        mapRefinement = nil
        mapRefineGeneration += 1
        if isRefiningSharpeningMap { isRefiningSharpeningMap = false }
        if isRefiningPickPreview { isRefiningPickPreview = false }
    }

    /// Once input pauses for about 150 ms, renders the map from the
    /// full-resolution master at the loupe's zoom (prd.md R6); the estimate
    /// stays on screen until it is ready. A spinner shows if it is still
    /// running about 0.5 s after the last input.
    private func scheduleMapRefinement() {
        stopMapRefinement()
        let content = currentContent
        let refinesPhoto = content == .photo && fringeSlotIsReplaced(pickingFringeSlot) && loupeIsZoomed
        guard sharpeningMap.isShown || refinesPhoto, let session, let url = sourceURL, let library else { return }
        let refiner = mapRefiner ?? SharpeningMapRefiner(source: url, generator: library.previews.interactiveGenerator,
                                                         colorSpace: library.previews.displayColorSpace)
        mapRefiner = refiner
        let values = refinesPhoto ? valuesOnScreen : (previewValues ?? adjustments)
        let longEdge = loupeIsZoomed ? nil : session.longEdge
        let generation = mapRefineGeneration
        mapRefineTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, content == currentContent, pendingRender == nil else { return }
            let token = RenderCancellation()
            mapRefinement = token
            let spinner = Task {
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled, generation == mapRefineGeneration {
                    if refinesPhoto { isRefiningPickPreview = true } else { isRefiningSharpeningMap = true }
                }
            }
            defer {
                spinner.cancel()
                if generation == mapRefineGeneration {
                    isRefiningSharpeningMap = false
                    isRefiningPickPreview = false
                }
            }
            do {
                let refined = try await refiner.render(values, longEdge: longEdge, content: content, cancellation: token)
                guard !Task.isCancelled, generation == mapRefineGeneration, content == currentContent,
                      session === self.session,
                      (refinesPhoto ? valuesOnScreen : (previewValues ?? adjustments)) == values else { return }
                show(refined)
            } catch is CancellationError {
                // Newer input; its frame schedules another refinement.
            } catch {
                Self.log.error("Sharpening map refinement failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Puts a frame on screen and updates what follows it.
    private func show(_ rendered: LiveRenderSession.Frame) {
        frame = rendered
        if rendered.adjustments == awaitedMachineLearningValues { stopAwaitingMachineLearning() }
        if let reason = rendered.machineLearning.reason { learnUnavailability(reason) }
        if rendered.machineLearning == .applied, rendered.adjustments == committed {
            dropFallbackPreview()
        }
        defer { refreshMachineLearning() }
        if rendered.content == .sharpeningMap {
            showsLive = true
            let status = SharpeningMapStatus(rendered.adjustments)
            if shownSharpeningMap != status { shownSharpeningMap = status }
        } else if shownSharpeningMap != nil {
            shownSharpeningMap = nil
        }
        if rendered.content == .fringeMap {
            showsLive = true
            let status = FringeMapStatus(rendered.adjustments)
            if shownFringeMap != status { shownFringeMap = status }
        } else if shownFringeMap != nil {
            shownFringeMap = nil
        }
        frameRevision += 1
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
        let hash = stack.renderHash
        library.persist { [weak self] in
            try await catalog.setEditStack(stack, forVersion: versionID)
            self?.showSaved(hash, forVersion: versionID)
        }
        if versionID == item?.versionID {
            let values = Adjustments(stack: stack)
            committed = values
            sessionHashes.insert(hash)
            if adjustments != values {
                // Undo or redo on the open photo.
                adjustments = values
                sharpeningMap.valuesChanged()
                showsLive = true
                refreshMachineLearning()
                refreshFringeSwatches()
                syncSamplePixels()
                endFringeMapWithoutPicks()
                requestRender(interactive: false)
            }
        }

        library.undoManager.registerUndo(withTarget: self) { editor in
            editor.apply(previous, toVersion: versionID, undoingTo: stack, actionName: actionName)
        }
        library.undoManager.setActionName(actionName)
    }

    /// Shows a saved stack's hash, once its write has landed: the grid, film
    /// strip and loupe then ask for renditions of it, which `PreviewService`
    /// renders from the catalog's stack. Shown earlier, they would ask while
    /// the catalog still has the previous stack (stale-preview-after-save);
    /// the live frame stays on screen until then. Runs on the write chain,
    /// so hashes are shown in the order their writes land.
    private func showSaved(_ hash: String, forVersion versionID: Int64) {
        library?.setEditStackHash(hash, forVersion: versionID)
        if versionID == item?.versionID {
            item?.editStackHash = hash
            seedPreviewIfRendered()
        }
    }

    /// A stack saved for a version by something else (paste, a preset, their undo).
    func catalogChanged(_ stack: EditStack, forVersion versionID: Int64) {
        guard versionID == item?.versionID, state == .ready else { return }
        let values = Adjustments(stack: stack)
        committed = values
        adjustments = values
        item?.editStackHash = stack.renderHash
        showsOriginal = false
        sharpeningMap.valuesChanged()
        refreshMachineLearning()
        refreshFringeSwatches()
        syncSamplePixels()
        endFringeMapWithoutPicks()
        // The map stays on screen until its next frame; the photo's renditions follow otherwise.
        if !sharpeningMap.isShown { showsLive = false }
        // For the histogram; the loupe loads the new edit's renditions itself.
        requestRender(interactive: false)
    }

    /// Once the frame on screen shows the saved values, it becomes the cached
    /// preview of the new edit hash and the loupe goes back to its renditions.
    private func seedPreviewIfRendered() {
        guard let library, let item, let frame, !isChanging, !showsOriginal, !lastFrameWasInteractive, frame.showsPhoto,
              frame.adjustments == committed, adjustments == committed,
              item.editStackHash == committed.editStack.renderHash,
              let request = library.previewRequest(for: item, tier: .preview)
        else { return }
        library.previews.insertIntoMemory(frame.image.cgImage, for: request)
        showsLive = false
    }

    // MARK: Machine learning noise reduction

    /// Turns machine learning noise reduction on or off, as one undo step (R9).
    func setMachineLearning(_ isOn: Bool) {
        change(isOn ? String(localized: "Turn On Machine Learning", comment: "Undo action name")
                    : String(localized: "Turn Off Machine Learning", comment: "Undo action name"),
               phase: .committed) { $0.noiseReduction.machineLearning = isOn }
    }

    /// The Decoder pop-up's choice: the machine learning version turns it on,
    /// another turns it off and becomes Profile's decoder (R3), in one undo step.
    func chooseDecoder(_ version: String) {
        guard let defaults = rawDefaults else { return }
        change(String(localized: "Decoder"), phase: .committed) {
            $0.chooseDecoder(version, defaultVersion: defaults.defaultDecoderVersion)
        }
    }

    /// Luminance's default for the values being edited: the machine learning
    /// decoder's while it applies, otherwise the classical decoder's.
    var luminanceNoiseReductionDefault: Double {
        guard isRaw, let defaults = rawDefaults else { return 0 }
        if machineLearning?.isApplied == true, let learned = defaults.machineLearningLuminanceNoiseReduction {
            return learned
        }
        return defaults.luminanceNoiseReduction ?? 0
    }

    /// `values` render through the machine learning decoder here (a failure
    /// is only known once its frame arrives).
    private func decodesWithMachineLearning(_ values: Adjustments) -> Bool {
        isRaw && values.asksForMachineLearning && values.isEnabled(.noiseReduction)
            && rawDefaults?.machineLearning == .available
    }

    private func status(for values: Adjustments) -> MachineLearningNoiseReduction.Status {
        let failed: Bool
        if let frame, frame.adjustments == values {
            failed = frame.machineLearning == .notApplied(.failed)
        } else {
            // Before a frame of these values: the cached fallback shown on arrival.
            failed = frame == nil && arrivedWithFailedFallback && values == committed
        }
        return MachineLearningNoiseReduction.Status(
            asks: values.asksForMachineLearning, groupIsOn: values.isEnabled(.noiseReduction),
            availability: isRaw ? rawDefaults?.machineLearning : .notRaw, renderFailed: failed)
    }

    /// The saved values rendered with machine learning: a fallback kept for
    /// the session under their key is out of date, so the next arrival
    /// renders (and caches) them again instead of showing it.
    private func dropFallbackPreview() {
        guard let item, let library,
              let key = library.previewRequest(for: item, tier: .preview)?.key,
              library.previews.cache.sessionOnlyReason(for: key) != nil else { return }
        arrivedWithFailedFallback = false
        library.previews.cache.removeSessionOnly(key)
        if let thumbnail = PreviewCacheKey(contentHash: key.contentHash, editStackHash: key.editStackHash, tier: .thumbnail) {
            library.previews.cache.removeSessionOnly(thumbnail)
        }
    }

    /// A render found the decoder unavailable where the photo looked
    /// available (macOS lacks its model, owner ruling 9): the photo takes
    /// that state with the frame, and keeps it while it stays open.
    private func learnUnavailability(_ reason: MachineLearningNoiseReduction.Reason) {
        guard rawDefaults?.machineLearning == .available else { return }
        switch reason {
        case .notOnThisMac: rawDefaults?.machineLearning = .notOnThisMac
        case .cameraNotSupported: rawDefaults?.machineLearning = .cameraNotSupported
        case .failed: break
        }
    }

    /// Recomputes the inspector's status and the badge's reason.
    private func refreshMachineLearning() {
        let edited: MachineLearningNoiseReduction.Status? = state == .ready ? status(for: adjustments) : nil
        if machineLearning != edited { machineLearning = edited }
        let onScreen = previewValues ?? (showsOriginal ? .none : adjustments)
        let reason = state == .ready ? status(for: onScreen).notAppliedReason : nil
        if machineLearningNotApplied != reason { machineLearningNotApplied = reason }
    }

    /// Starts waiting for a frame of `values`; the spinner shows if it has
    /// not come 0.5 s after the wait began (design §6). Newer values asked
    /// for during the wait extend it without restarting the delay.
    private func awaitMachineLearning(_ values: Adjustments) {
        awaitedMachineLearningValues = values
        guard machineLearningSpinnerTask == nil, !isAwaitingMachineLearningFrame else { return }
        machineLearningSpinnerTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            machineLearningSpinnerTask = nil
            // On arrival with the preview cached, the right image is already on screen.
            if awaitedMachineLearningValues != nil, showsLive || !previewWasCached {
                isAwaitingMachineLearningFrame = true
            }
        }
    }

    private func stopAwaitingMachineLearning() {
        awaitedMachineLearningValues = nil
        machineLearningSpinnerTask?.cancel()
        machineLearningSpinnerTask = nil
        if isAwaitingMachineLearningFrame { isAwaitingMachineLearningFrame = false }
    }

    /// An offline photo: the badge can still say "this Mac" (design §6),
    /// which needs only the stack.
    private func loadOfflineMachineLearning(_ item: CatalogItem, catalog: Catalog) {
        guard item.fileKind == .raw, !MachineLearningNoiseReduction.systemSupportsMachineLearning else { return }
        let versionID = item.versionID
        loadTask = Task {
            let stack = (try? await catalog.version(id: versionID)?.decodedEditStack()) ?? .identity
            guard !Task.isCancelled, self.item?.versionID == versionID, state == .offline else { return }
            let values = Adjustments(stack: stack)
            offlineAsksMachineLearning = values.asksForMachineLearning && values.isEnabled(.noiseReduction)
            if offlineAsksMachineLearning { machineLearningNotApplied = .notOnThisMac }
        }
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
        refreshMachineLearning()
    }

    /// A hovered preset that carries automatic alignment (chromatic-aberration
    /// design §10): shown at once with the photo's own alignment, then with
    /// the alignment measured on this photo once that is done. Nothing
    /// measured here is saved unless the preset is applied.
    func previewMeasuringAlignment(_ body: @escaping (inout Adjustments) -> Void) {
        guard state == .ready else { return }
        var target = adjustments
        body(&target)
        hoverAlignmentTask?.cancel()
        guard target.needsAlignmentMeasurement, let library, let url = sourceURL else {
            preview(body)
            return
        }
        let current = adjustments.colorAlignment
        preview { values in
            body(&values)
            values.colorAlignment = current
        }
        let generator = library.previews.interactiveGenerator
        let measuring = target
        hoverAlignmentTask = Task {
            let measured = await Task.detached(priority: .utility) {
                try? ColorAlignmentMeasurement.measure(source: url, adjustments: measuring, generator: generator)
            }.value
            guard !Task.isCancelled, isPreviewing, previewValues != nil, let measured else { return }
            preview { values in
                body(&values)
                values = values.measuringAlignment(measured)
            }
        }
    }

    /// Back to the applied values (the menu closed without a pick).
    func endPreview() {
        hoverAlignmentTask?.cancel()
        guard isPreviewing else { return }
        isPreviewing = false
        previewValues = nil
        if previewRestoresCache, adjustments == committed, !showsOriginal {
            // The cached rendition shows the saved values: no need to wait for a frame.
            showsLive = false
        }
        requestRender(interactive: false)
        refreshMachineLearning()
    }

    // MARK: Rendering

    /// Renders the latest values; requests made while a frame renders collapse
    /// into one.
    private func requestRender(interactive: Bool) {
        var cancellation: RenderCancellation?
        if !interactive {
            cancellation = RenderCancellation()
            refinement = cancellation
        }
        pendingRender = (valuesOnScreen, interactive, cancellation)
        if let values = pendingRender?.values, decodesWithMachineLearning(values) {
            awaitMachineLearning(values)
        } else {
            stopAwaitingMachineLearning()
        }
        guard renderTask == nil, let session else { return }
        renderTask = Task {
            while let next = pendingRender, !Task.isCancelled {
                pendingRender = nil
                renderingInteractive = next.interactive
                defer { renderingInteractive = false }
                do {
                    let overlay = showsMaskOverlay && !showsOriginal ? selectedMaskID : nil
                    let content = currentContent
                    let rendered = try await session.render(next.values, interactive: next.interactive,
                                                            allowsDrafts: allowsDrafts, overlayMask: overlay,
                                                            content: content, cancellation: next.cancellation)
                    guard !Task.isCancelled, session === self.session else { break }
                    // A frame rendered before the map was hidden or switched: the right one follows.
                    if rendered.content != currentContent { continue }
                    maskFrameSize = rendered.maskFrameSize
                    lastFrameWasInteractive = next.interactive
                    // Only frames showing the photo give the histogram (R7).
                    if (!showsOriginal || next.values == .none), rendered.showsPhoto, let histogram = rendered.histogram {
                        self.histogram = histogram
                    }
                    show(rendered)
                    seedPreviewIfRendered()
                    if rendered.content.isMap {
                        // The map's refinement is the full-resolution one, not a full-size frame.
                        if pendingRender == nil { scheduleMapRefinement() }
                    } else if fringeSlotIsReplaced(pickingFringeSlot), loupeIsZoomed {
                        // Picking again zoomed in: the photo without the slot, refined to full resolution.
                        if pendingRender == nil { scheduleMapRefinement() }
                    } else if next.interactive {
                        scheduleRefinement()
                    } else {
                        schedulePrefill()
                    }
                } catch is CancellationError {
                    // Superseded by newer input; the draft stays on screen.
                } catch {
                    Self.log.error("Live render failed: \(error.localizedDescription, privacy: .public)")
                    // No frame will come for these values.
                    if next.values == awaitedMachineLearningValues { stopAwaitingMachineLearning() }
                }
            }
            if session === self.session { renderTask = nil }
        }
    }

    /// A full-quality frame once input pauses for about 150 ms; the drag's
    /// last (possibly reduced) frame stays on screen until it is ready.
    private func scheduleRefinement() {
        refineTask?.cancel()
        refineTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, state == .ready, lastFrameWasInteractive, pendingRender == nil else { return }
            requestRender(interactive: false)
        }
    }

    /// After about 150 ms without input, renders into the session's stage cache
    /// what a drag of the selected mask will reuse (the image entering the
    /// mask step, the estimates, the masks before it), so the drag's first
    /// frame is cheap. Cancelled by new input between stages.
    private func schedulePrefill() {
        prefillTask?.cancel()
        prefill?.cancel()
        guard selectedMaskID != nil else { return }
        prefillTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, state == .ready, let session, pendingRender == nil, renderTask == nil else { return }
            let token = RenderCancellation()
            prefill = token
            try? await session.prepare(adjustments, editing: selectedMaskID, allowsDrafts: allowsDrafts,
                                       cancellation: token)
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
        // Crop ends the map; it does not come back after Done (design §6).
        endSharpeningMap()
        pickingFringeSlot = nil
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

    /// Reset Crop can act: the photo has a crop, or the open crop session
    /// has one (the heading's reset button and Adjust ▸ Reset Crop).
    var canResetCrop: Bool {
        cropSession.map { $0.saved != Crop() } ?? !adjustments.crop.isIdentity
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

    /// Crop (`C`, the grid's Crop): starts cropping `versionID` as soon as
    /// the loupe has loaded it.
    func beginCropWhenReady(versionID: Int64) {
        if item?.versionID == versionID, state == .ready {
            beginCrop()
        } else {
            cropsWhenReady = versionID
        }
    }

    /// `C` and Crop / Finish Cropping: starts the session, or saves it.
    func toggleCrop() {
        if cropSession != nil { endCrop(save: true) } else { beginCrop() }
    }

    /// Turns the photo a quarter turn, frame and all. Outside a crop session
    /// the turn is saved at once as one undo step; inside one, the frame turns.
    func rotate(clockwise: Bool) {
        guard var session = cropSession else {
            guard state == .ready, cropImageTask == nil else { return }
            let camera = cameraRect
            change(String(localized: "Rotate", comment: "Undo action name"), phase: .committed) {
                $0.crop = $0.crop.turned(clockwise: clockwise, cameraRect: camera)
            }
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

    // MARK: Color fringes (chromatic-aberration design §3–§6)

    /// Values a frame should show: a hover preview's, the original, or the
    /// edited values; while a filled slot is picked again, without that
    /// slot's graying (design §4), as a preview never saved.
    var valuesOnScreen: Adjustments {
        var values = previewValues ?? (showsOriginal ? .none : adjustments)
        if let slot = pickingFringeSlot, values.colorFringes[slot: slot] != nil {
            values.colorFringes[slot: slot] = nil
        }
        return values
    }

    /// Picking `slot` would replace a color it holds.
    func fringeSlotIsReplaced(_ slot: Int?) -> Bool {
        guard let slot else { return false }
        return adjustments.colorFringes[slot: slot] != nil
    }

    /// Picking from the photo is possible: an editable photo, no crop session.
    var canPickFringe: Bool { state == .ready && cropSession == nil && cropImageTask == nil }

    /// Arms `slot`'s eyedropper, or disarms it when it is armed (the button
    /// and Pick from Photo); nil disarms whichever is armed (Esc).
    func armFringePicker(_ slot: Int?) {
        guard let slot else {
            pickingFringeSlot = nil
            return
        }
        guard canPickFringe else { return }
        pickingFringeSlot = pickingFringeSlot == slot ? nil : slot
    }

    /// A tool is picking with the pixel magnifier.
    var pixelMagnifierIsPicking: Bool { pickingFringeSlot != nil }

    /// The fringe tool for the pixel magnifier and the click, once its pixels are held.
    var pixelMagnifierTool: FringeMagnifierTool? {
        fringeSamplePixels.map {
            FringeMagnifierTool(pixels: $0, crop: maskCrop, note: LensText.magnifierNote, refusal: LensText.almostNoColorState)
        }
    }

    /// Bytes the magnifier holds now (the debug script, photobench's record).
    var samplePixelsByteCount: Int { fringeSamplePixels?.byteCount ?? 0 }

    /// Holds the sampled image while a slot is picking (status.md OQ14): one
    /// render off the main thread when picking starts, and again only when
    /// something that changes that image changes (R30). Released as soon as
    /// picking ends (R36).
    private func syncSamplePixels() {
        guard pickingFringeSlot != nil, state == .ready, let library, let url = sourceURL else {
            samplePixelsTask?.cancel()
            samplePixelsTask = nil
            samplePixelsKey = nil
            if fringeSamplePixels != nil { fringeSamplePixels = nil }
            return
        }
        var settings = isRaw ? adjustments.decodeSettings : .none
        settings.fullFrame = isRaw
        let key = SamplePixelsKey(source: url, settings: settings, alignment: adjustments.effective.colorAlignment)
        guard key != samplePixelsKey else { return }
        samplePixelsKey = key
        if fringeSamplePixels != nil { fringeSamplePixels = nil }
        samplePixelsTask?.cancel()
        let values = adjustments
        let generator = library.previews.generator.withEngine(samplePixelsEngine)
        samplePixelsTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try FringePicker.samplePixels(source: url, values: values, generator: generator) }
            }.value
            guard !Task.isCancelled, samplePixelsKey == key else { return nil }
            switch result {
            case .success(let pixels):
                fringeSamplePixels = pixels
                return pixels
            case .failure(let error):
                Self.log.error("Reading the photo for picking failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    /// A click while a slot is picking, at `point` (output unit coordinates,
    /// y down: the middle of the pointer's device pixel), with the output
    /// `devicePixelsAcross` wide on screen. Takes the pixel the magnifier
    /// outlines there, the same rule (R22), or refuses a spot with almost
    /// no color (design §4). A click before the pixels are held waits for
    /// them and follows the same rule.
    func pickFringe(at point: CGPoint, devicePixelsAcross: Double) {
        guard let slot = pickingFringeSlot, state == .ready, samplePixelsTask != nil,
              let versionID = item?.versionID else { return }
        let crop = maskCrop
        fringePickTask?.cancel()
        fringePickTask = Task {
            var pixels = fringeSamplePixels
            if pixels == nil { pixels = await samplePixelsTask?.value }
            // A change of the sampled image can have started another render.
            if pixels == nil { pixels = await samplePixelsTask?.value }
            guard !Task.isCancelled, item?.versionID == versionID, pickingFringeSlot == slot, let pixels else { return }
            let tool = FringeMagnifierTool(pixels: pixels, crop: crop)
            guard let result = FringePicker.pick(tool: tool, atOutput: point, devicePixelsAcross: devicePixelsAcross) else { return }
            switch result {
            case .color(let color, let at):
                lastFringeSample = (at, false)
                lastFringePick = Date()
                pickingFringeSlot = nil
                change(LensText.pickUndoName, phase: .committed) {
                    $0.colorFringes[slot: slot] = ColorFringes.Slot(color: color)
                }
                AccessibilityText.announce(LensText.setAnnouncement(slot: slot, color: color))
            case .almostNoColor(let at):
                lastFringeSample = (at, true)
                fringePickRefused = true
                AccessibilityText.announce(LensText.almostNoColorAnnouncement)
            }
        }
    }

    /// Fills `slot` with a listed color at its starting Tolerance, as one
    /// undo step; cancels any picking (design §3 "The slot menu").
    func fillFringe(_ slot: Int, with listed: CommonFringeColor) {
        guard state == .ready else { return }
        pickingFringeSlot = nil
        change(LensText.chooseUndoName, phase: .committed) { $0.colorFringes[slot: slot] = listed.slot }
        AccessibilityText.announce(LensText.setAnnouncement(slot: slot, color: listed.color))
    }

    /// Empties `slot`, as one undo step; the fringe map ends with the last pick.
    func clearFringe(_ slot: Int) {
        guard state == .ready, adjustments.colorFringes[slot: slot] != nil else { return }
        if pickingFringeSlot == slot { pickingFringeSlot = nil }
        change(LensText.clearUndoName, phase: .committed) { $0.colorFringes[slot: slot] = nil }
        AccessibilityText.announce(LensText.clearedAnnouncement(slot: slot))
        endFringeMapWithoutPicks()
    }

    /// With no pick left there is nothing to map: the fringe map ends.
    private func endFringeMapWithoutPicks() {
        guard showsFringeMap, adjustments.colorFringes.isIdentity else { return }
        endSharpeningMap()
        AccessibilityText.announce(String(localized: "Showing the photo.",
                                          comment: "VoiceOver, when the sharpening map is hidden"))
    }

    func setFringeTolerance(_ slot: Int, _ value: Double, phase: EditPhase) {
        change(LensText.toleranceTitle, phase: phase) { $0.colorFringes[slot: slot]?.tolerance = value }
    }

    /// The swatches follow the values: the stored colors through the
    /// adjustments after the fringe step (design §14 OQ2, point 3).
    private func refreshFringeSwatches() {
        swatchTask?.cancel()
        guard state == .ready, let library else { return }
        let values = adjustments
        let slots = [1, 2].compactMap { number in values.colorFringes[slot: number].map { (number, $0.color) } }
        guard !slots.isEmpty else {
            if !fringeSwatches.isEmpty { fringeSwatches = [:] }
            return
        }
        let isRaw = isRaw
        let generator = library.previews.interactiveGenerator
        swatchTask = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let colors = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: slots.compactMap { number, color in
                    FringePicker.swatch(color, values: values, isRaw: isRaw, generator: generator).map { (number, $0) }
                })
            }.value
            guard !Task.isCancelled, values == adjustments else { return }
            fringeSwatches = colors
        }
    }

    private static let lensKernels = Task.detached(priority: .utility) { AdjustmentRenderer.prepareLensKernels() }

    /// Starts compiling the Lens kernels the first time a photo opens.
    static func prepareLensKernelsOnce() {
        _ = lensKernels
    }

    // MARK: Color alignment (chromatic-aberration design §7)

    /// Align automatically: on measures the photo and saves the values as one
    /// undo step; off removes the correction. Unchecking while measuring
    /// stops it and saves nothing.
    func setAutomaticAlignment(_ isOn: Bool) {
        guard state == .ready else { return }
        if !isOn {
            if isMeasuringAlignment {
                alignmentTask?.cancel()
                alignmentTask = nil
                isMeasuringAlignment = false
                return
            }
            change(LensText.turnOffAutomaticUndoName, phase: .committed) { $0.colorAlignment = ColorAlignment() }
            return
        }
        guard !isMeasuringAlignment, let library, let url = sourceURL, let versionID = item?.versionID else { return }
        isMeasuringAlignment = true
        alignmentMeasureFailed = false
        let values = adjustments
        let generator = library.previews.interactiveGenerator
        alignmentTask = Task {
            let measured = await Task.detached(priority: .userInitiated) {
                try? ColorAlignmentMeasurement.measure(source: url, adjustments: values, generator: generator)
            }.value
            guard !Task.isCancelled, item?.versionID == versionID else { return }
            isMeasuringAlignment = false
            alignmentTask = nil
            guard let measured else {
                alignmentMeasureFailed = true
                return
            }
            change(LensText.turnOnAutomaticUndoName, phase: .committed) { $0 = $0.measuringAlignment(measured) }
            AccessibilityText.announce(LensText.alignmentCaption(LensText.alignmentState(of: self)))
        }
    }

    /// A paste or preset measuring the open photo (`changeAdjustmentsMeasuringAlignment`).
    func setMeasuringAlignment(_ isMeasuring: Bool) {
        isMeasuringAlignment = isMeasuring
        if isMeasuring { alignmentMeasureFailed = false }
    }

    /// A paste or preset could not measure the open photo, which it left unchanged.
    func noteAlignmentMeasureFailed() {
        alignmentMeasureFailed = true
    }

    /// A Red/cyan or Blue/yellow slider: the values become hand-set (R10).
    func setAlignment(red: Double? = nil, blue: Double? = nil, title: String, phase: EditPhase) {
        change(title, phase: phase) { $0.colorAlignment.setByHand(red: red, blue: blue) }
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
