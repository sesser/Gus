import AppKit
import PhotoCore
import PhotoUI

/// A detection under way (ai-masks design §5): what lands where when its result does.
struct PendingDetection: Equatable {
    enum Target: Equatable {
        /// A new mask; it is selected on landing only if the selection is still this.
        case newMask(selectionAtStart: UUID?)
        /// A component added to this mask.
        case component(mask: UUID)
        /// Update of these components of this mask, as they were when it started.
        case update(mask: UUID, components: [UpdatedComponent])
    }

    /// A component an Update started on: its place then, its kind and the
    /// result it named. The landing finds it by kind and result
    /// (`MaskDetectionUpdate`), so an edit meanwhile (Undo, Remove from Mask)
    /// can't move a result onto another component (code review C1).
    typealias UpdatedComponent = MaskDetectionUpdate.Started

    let id = UUID()
    let kind: MaskDetectionKind
    let target: Target

    /// The Update of the component at `index` of `mask` is under way.
    func updates(mask: UUID, index: Int) -> Bool {
        if case .update(mask, let components) = target { components.contains { $0.index == index } } else { false }
    }

    /// The requests to run: one per kind of result (Background is Subject's).
    var requests: [MaskRaster.Request] {
        guard case .update(_, let components) = target else { return [kind.request] }
        var seen = Set<MaskRaster.Request>()
        return components.map(\.kind.request).filter { seen.insert($0).inserted }
    }

    /// The kind to name when `request` fails: the first component's that uses it.
    func kind(for request: MaskRaster.Request) -> MaskDetectionKind {
        if case .update(_, let components) = target, let match = components.first(where: { $0.kind.request == request }) {
            return match.kind
        }
        return kind.request == request ? kind : (request == .person ? .people : .subject)
    }
}

/// A component as a failed Update knows it (design §7): its mask, its place
/// and the result it still names.
struct DetectionComponentKey: Hashable {
    var mask: UUID
    var index: Int
    var raster: String?
}

/// The words of detection masks (design §4, §12, §14).
enum MaskDetectionText {
    static let detectLabel = String(localized: "Detect", comment: "Accessibility label of the Masks heading's detection pull-down")
    static let newMaskHelp = String(localized: "New mask from the photo: Subject, People or Background",
                                    comment: "Tooltip of the New Mask row's detection pull-down")
    static let addHelp = String(localized: "Add to this mask from the photo: Subject, People or Background",
                                comment: "Tooltip of the Add to Mask row's detection pull-down")
    static let detecting = String(localized: "Detecting…", comment: "Caption while a mask detection runs")
    static let spinnerLabel = String(localized: "Detecting", comment: "Tooltip and VoiceOver label of a detection's spinner")
    static let waitHelp = String(localized: "Wait for the current detection to finish.",
                                 comment: "Tooltip of detection items dimmed while one runs")
    static let update = String(localized: "Update", comment: "Button: detect a mask component again")
    static let updateHelp = String(localized: "Detect again on this photo and replace the stored result",
                                   comment: "Tooltip of a detection component's Update button")
    static let croppingHelp = String(localized: "Finish cropping to detect in the photo.",
                                     comment: "Tooltip of the detection pull-down, dimmed while cropping")
    static let updateCroppingHelp = String(localized: "Finish cropping to detect again.",
                                           comment: "Tooltip of a detection's Update button, dimmed while cropping")

    /// The words under an Activity warning: the system's own, or the app's for its own failures.
    static func detail(_ error: MaskDetectionError) -> String {
        switch error {
        case .unavailable(let detail), .failed(let detail): detail
        case .unreadable: String(localized: "The photo could not be rendered for detection.",
                                 comment: "Activity warning's detail when a detection's input could not be made")
        case .unusableMask: String(localized: "The mask Vision gave could not be read.",
                                   comment: "Activity warning's detail when a detection's result is in a form the app can't use")
        }
    }
    static let updateDetection = String(localized: "Update Detection",
                                        comment: "Menu item, mask menu item, undo action name and History label")
    static let cancelled = String(localized: "Detection cancelled.", comment: "VoiceOver, after Cancel on a detection")

    static func addMaskAction(_ kind: MaskDetectionKind) -> String {
        switch kind {
        case .subject: String(localized: "Add Subject Mask", comment: "Undo action name")
        case .people: String(localized: "Add People Mask", comment: "Undo action name")
        case .background: String(localized: "Add Background Mask", comment: "Undo action name")
        }
    }

    static func addComponentAction(_ kind: MaskDetectionKind) -> String {
        switch kind {
        case .subject: String(localized: "Add Subject to Mask", comment: "Undo action name")
        case .people: String(localized: "Add People to Mask", comment: "Undo action name")
        case .background: String(localized: "Add Background to Mask", comment: "Undo action name")
        }
    }

    /// The caption of a component in `state` (design §4).
    static func caption(_ state: MaskDetectionState, kind: MaskDetectionKind) -> String {
        switch state {
        case .found(let count):
            switch kind {
            case .subject: String(localized: "\(count) subjects found.", comment: "Detection caption: Subject found")
            case .people where count >= 4:
                String(localized: "\(count) people found, the most that can be selected. Others in the photo may be left out.",
                       comment: "Detection caption: People found at the request's limit of four")
            case .people: String(localized: "\(count) people found.", comment: "Detection caption: People found")
            case .background: String(localized: "Everything except \(count) subjects.",
                                     comment: "Detection caption: Background, the subjects it leaves out")
            }
        case .empty:
            switch kind {
            case .subject: String(localized: "No subject stands out in this photo. It selects nothing.",
                                  comment: "Detection caption: Subject found nothing")
            case .people: String(localized: "No people were found in this photo. It selects nothing.",
                                 comment: "Detection caption: People found nothing")
            case .background: String(localized: "No subject was found, so there is no background to select. It selects nothing.",
                                     comment: "Detection caption: Background with no subject")
            }
        case .failed:
            String(localized: "Detection failed on this photo. It selects nothing. Choose Update to try again.",
                   comment: "Detection caption: failed")
        case .failedUpdate:
            String(localized: "Detection failed on this photo. The earlier result still applies. Choose Update to try again.",
                   comment: "Detection caption: an Update failed and the earlier result still applies")
        case .unavailable:
            String(localized: "Detection isn't available on this Mac. It selects nothing.",
                   comment: "Detection caption: the request can't run on this Mac")
        case .missing:
            String(localized: "The stored result is missing or damaged. It selects nothing. Choose Update to detect again.",
                   comment: "Detection caption: the stored result's row is missing or unreadable")
        case .loading:
            ""
        }
    }

    /// The Activity warning when a detection gives no result (design §6).
    static func couldNotDetect(_ kind: MaskDetectionKind, fileName: String) -> String {
        kind == .people
            ? String(localized: "Couldn't detect people in \(fileName).", comment: "Activity warning; the file's name follows")
            : String(localized: "Couldn't detect a subject in \(fileName).", comment: "Activity warning; the file's name follows")
    }

    static func added(_ kind: MaskDetectionKind, caption: String) -> String {
        switch kind {
        case .subject: String(localized: "Subject mask added. \(caption)", comment: "VoiceOver; the component's caption follows")
        case .people: String(localized: "People mask added. \(caption)", comment: "VoiceOver; the component's caption follows")
        case .background: String(localized: "Background mask added. \(caption)",
                                 comment: "VoiceOver; the component's caption follows")
        }
    }

    static func updated(caption: String) -> String {
        String(localized: "Detection updated. \(caption)", comment: "VoiceOver after Update Detection; the caption follows")
    }
}

extension AdjustmentEditor {
    /// How long the overlay shows a new result (design §9).
    static let overlayFlashDuration: Duration = .seconds(1.5)

    // MARK: What can act

    /// New Mask ▸ Subject, People, Background (design §11): as the shape
    /// items, and no detection under way.
    var canDetectMask: Bool {
        state == .ready && cropSession == nil && pendingDetection == nil
            && MaskLimits.canAddMask(to: adjustments.local)
    }

    /// The Add to Mask row's pull-down: a selected mask with room for a component.
    var canDetectComponent: Bool {
        guard let mask = selectedMask else { return false }
        return state == .ready && cropSession == nil && pendingDetection == nil && MaskLimits.canAddComponent(to: mask)
    }

    /// Update Detection for `mask` (design §7): it has a detection component,
    /// and nothing blocks editing or another detection.
    func canUpdateDetection(of mask: Mask?) -> Bool {
        guard let mask else { return false }
        return state == .ready && cropSession == nil && pendingDetection == nil
            && mask.components.contains { $0.shape.detection != nil }
    }

    // MARK: Starting

    /// A new mask from the photo (design §5): detects, and adds the mask when the result lands.
    func addDetectionMask(_ kind: MaskDetectionKind) {
        guard canDetectMask else { return }
        startDetection(PendingDetection(kind: kind, target: .newMask(selectionAtStart: selectedMaskID)))
    }

    /// A component from the photo added to the selected mask.
    func addDetectionComponent(_ kind: MaskDetectionKind) {
        guard canDetectComponent, let mask = selectedMaskID else { return }
        startDetection(PendingDetection(kind: kind, target: .component(mask: mask)))
    }

    /// Detects again for the component at `index` of `mask`, or for every
    /// detection component of the mask, as one undo step (design §7).
    func updateDetection(mask id: UUID, index: Int? = nil) {
        guard let mask = adjustments.local.masks.first(where: { $0.id == id }), canUpdateDetection(of: mask) else { return }
        let components = mask.components.enumerated().compactMap { position, component -> PendingDetection.UpdatedComponent? in
            guard let detection = component.shape.detection, index == nil || position == index else { return nil }
            return .init(index: position, kind: detection.kind, raster: detection.raster,
                         operation: component.operation, invert: component.invert)
        }
        guard let first = components.first else { return }
        startDetection(PendingDetection(kind: first.kind, target: .update(mask: id, components: components)))
    }

    private func startDetection(_ pending: PendingDetection) {
        guard let library, let source = sourceURL, let item else { return }
        // A new mask takes the photo on screen: the sharpening map ends, as for any new mask (design §10).
        endSharpeningMap()
        pendingDetection = pending
        let engine = library.previews.interactiveGenerator.engine
        let detector = maskDetector
        let versionID = item.versionID
        let requests = pending.requests
        var values = adjustments
        detectionTask = Task { [weak self] in
            // At most twice more if the mask frame changes while detecting.
            for _ in 0..<3 {
                let input = values
                let work = Task.detached(priority: .userInitiated) {
                    try await MaskDetectionRun.run(requests, source: source, adjustments: input, engine: engine,
                                                   detector: detector)
                }
                let outcome = await withTaskCancellationHandler { await work.result } onCancel: { work.cancel() }
                guard !Task.isCancelled, case .success(let results) = outcome else { return }
                // While the lens frame question is up nothing else changes the
                // photo: the result waits for the answer (code review C2).
                while self?.isAskingLensFrame == true {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                }
                guard let self, !Task.isCancelled, pendingDetection == pending, self.item?.versionID == versionID
                else { return }
                // The input was the mask frame Distortion defined then: a frame
                // changed meanwhile is detected again in the new one.
                if adjustments.effective.distortion != input.effective.distortion {
                    values = adjustments
                    continue
                }
                land(pending, results: results)
                return
            }
            // The frame kept changing: nothing lands; say so as a cancel would.
            self?.cancelDetection()
        }
    }

    /// Cancels a pending Update when a component it covers was changed
    /// (operation, Invert) or removed, or its mask was deleted, by whatever
    /// write (the row's controls, ⌘Z, Redo, a History revert): design DR-5.
    /// As Cancel: the change stands, no result is written, the old one keeps
    /// applying, and "Detection cancelled." is announced.
    func cancelUpdateIfCoveredChanged() {
        guard case .update(let id, let covered)? = pendingDetection?.target else { return }
        let mask = adjustments.local.masks.first { $0.id == id }
        if !MaskDetectionUpdate.isIntact(covered, in: mask) { cancelDetection() }
    }

    /// Stops a detection: nothing is added and nothing changes (AC3).
    func cancelDetection(announcing: Bool = true) {
        guard pendingDetection != nil else { return }
        detectionTask?.cancel()
        detectionTask = nil
        pendingDetection = nil
        if announcing { AccessibilityText.announce(MaskDetectionText.cancelled, priority: .medium) }
    }

    // MARK: Landing

    /// Writes what the detection found as one undo step and one History
    /// entry (design A3): the result stored first, then the stack naming it.
    private func land(_ pending: PendingDetection, results: [MaskRaster.Request: Result<MaskRaster, MaskDetectionError>]) {
        pendingDetection = nil
        detectionTask = nil
        guard let library else { return }
        // Results go into the renderer's memory now and the catalog before the
        // stack: the stack's write queues behind the row's on the write chain.
        for (request, result) in results {
            switch result {
            case .success(let raster):
                // It ran: whatever this session learned before, the request runs on this Mac.
                unavailableRequests.remove(request)
                library.maskRasters.remember(raster)
                detectionResults[raster.digest] = library.maskRasters.cached(raster.digest)
                let catalog = library.catalog
                library.persist { try await catalog.storeMaskRaster(raster) }
            case .failure(let error):
                // The request that failed, not the first component's (code review C3).
                if case .unavailable = error { unavailableRequests.insert(request) }
                reportFailure(pending, request: request, error: error)
            }
        }

        func component(_ kind: MaskDetectionKind) -> MaskComponent {
            let raster = try? results[kind.request]?.get()
            return MaskComponent(.detection(MaskDetection(kind: kind, raster: raster?.digest)))
        }
        let found = (try? results[pending.kind.request]?.get())?.instances ?? 0 > 0
        switch pending.target {
        case .newMask(let selectionAtStart):
            var values = LocalValues()
            // A new mask shows its effect at once (design §5): darker behind, brighter on the subject.
            values.exposure = pending.kind == .background ? -0.5 : 0.3
            let mask = Mask(name: pending.kind.title, components: [component(pending.kind)], adjustments: values)
            guard changeMasks(MaskDetectionText.addMaskAction(pending.kind), phase: .committed, { $0.masks.append(mask) })
            else { return }
            if selectedMaskID == selectionAtStart {
                selectedMaskID = mask.id
                isBrushing = false
                isSamplingColor = false
            }
            // One announcement per outcome; a failure's caption says it (review F6).
            AccessibilityText.announce(MaskDetectionText.added(pending.kind, caption: caption(of: mask.components[0])),
                                       priority: .medium)
            if found { flashOverlay(on: mask.id) }
        case .component(let id):
            let added = component(pending.kind)
            guard adjustments.local.masks.contains(where: { $0.id == id }),
                  changeMasks(MaskDetectionText.addComponentAction(pending.kind), phase: .committed, { local in
                      guard let index = local.masks.firstIndex(where: { $0.id == id }) else { return }
                      local.masks[index].components.append(added)
                  }) else { return }
            AccessibilityText.announce(MaskDetectionText.added(pending.kind, caption: caption(of: added)), priority: .medium)
            if found { flashOverlay(on: id) }
        case .update(let id, let components):
            landUpdate(mask: id, components: components, results: results)
        }
    }

    /// Update: each component the Update started on, found again by kind and
    /// result (code review C1), takes its request's new result; one whose
    /// request failed keeps its old result and says so for this visit
    /// (design §7, DR-1). A component no longer there is left alone. An
    /// unchanged result writes nothing.
    private func landUpdate(mask id: UUID, components: [PendingDetection.UpdatedComponent],
                            results: [MaskRaster.Request: Result<MaskRaster, MaskDetectionError>]) {
        var next = adjustments.local
        guard let maskIndex = next.masks.firstIndex(where: { $0.id == id }) else { return }
        var landed: [Int] = []
        var flashes = false
        let positions = MaskDetectionUpdate.positions(of: components, in: next.masks[maskIndex].components)
        for (wanted, position) in zip(components, positions) {
            guard let position else { continue }
            landed.append(position)
            switch results[wanted.kind.request] {
            case .success(let raster)?:
                failedUpdates.remove(DetectionComponentKey(mask: id, index: position, raster: wanted.raster))
                next.masks[maskIndex].components[position].shape = .detection(MaskDetection(kind: wanted.kind,
                                                                                             raster: raster.digest))
                if raster.instances > 0 { flashes = true }
            case .failure?, nil:
                failedUpdates.insert(DetectionComponentKey(mask: id, index: position, raster: wanted.raster))
            }
        }
        let changed = next != adjustments.local
        if changed {
            changeMasks(MaskDetectionText.updateDetection, phase: .committed) { $0 = next }
            if flashes { flashOverlay(on: id) }
        }
        if let first = landed.first, let after = adjustments.local.masks.first(where: { $0.id == id }),
           after.components.indices.contains(first) {
            let text = caption(of: after.components[first], mask: id, index: first)
            AccessibilityText.announce(changed ? MaskDetectionText.updated(caption: text) : text, priority: .medium)
        }
    }

    /// Failed and Unavailable post a warning to Activity with the system's own
    /// words; empty never does (design §6, A10). Not announced: the landing's
    /// own announcement carries the caption (review F6).
    private func reportFailure(_ pending: PendingDetection, request: MaskRaster.Request, error: MaskDetectionError) {
        guard let library, let item else { return }
        let text = MaskDetectionText.couldNotDetect(pending.kind(for: request), fileName: item.fileName)
        let action: String = switch pending.target {
        case .newMask: MaskDetectionText.addMaskAction(pending.kind)
        case .component: MaskDetectionText.addComponentAction(pending.kind)
        case .update: MaskDetectionText.updateDetection
        }
        library.postActivity(text + "\n" + MaskDetectionText.detail(error), action: action, warning: true)
    }

    // MARK: States

    /// The state of a detection component, for its caption (design §4).
    func detectionState(of component: MaskComponent, mask: UUID? = nil, index: Int? = nil) -> MaskDetectionState? {
        guard let detection = component.shape.detection else { return nil }
        let lookup = detection.raster.flatMap { detectionResults[$0] }
        let state = MaskDetectionState.of(detection, lookup: lookup,
                                          unavailable: unavailableRequests.contains(detection.kind.request))
        if let mask, let index,
           failedUpdates.contains(DetectionComponentKey(mask: mask, index: index, raster: detection.raster)) {
            // A failed Update leaves a found result applying (design DR-1);
            // one that can't run here stays Unavailable (review N1).
            switch state {
            case .found(let count): return .failedUpdate(instances: count)
            case .unavailable: return .unavailable
            default: return .failed
            }
        }
        return state
    }

    /// The caption a component shows now.
    func caption(of component: MaskComponent, mask: UUID? = nil, index: Int? = nil) -> String {
        guard let detection = component.shape.detection,
              let state = detectionState(of: component, mask: mask, index: index) else { return "" }
        return MaskDetectionText.caption(state, kind: detection.kind)
    }

    /// Reads, off the main actor, the stored results the masks name that are not known yet.
    func loadDetectionResults() {
        guard let store = library?.maskRasters else { return }
        let wanted = adjustments.local.maskRasterDigests
            .filter { detectionResults[$0] == nil && !detectionResultLoads.contains($0) }
        guard !wanted.isEmpty else { return }
        for digest in wanted {
            if let cached = store.cached(digest) {
                detectionResults[digest] = cached
                continue
            }
            detectionResultLoads.insert(digest)
            Task { [weak self] in
                let lookup = await Task.detached(priority: .userInitiated) { store.lookup(digest) }.value
                self?.detectionResultLoads.remove(digest)
                self?.detectionResults[digest] = lookup
            }
        }
    }

    /// Forgets what is known of a result (the debug script deleted or damaged its row).
    func forgetDetectionResult(_ digest: String) {
        library?.maskRasters.forget(digest)
        detectionResults[digest] = nil
        loadDetectionResults()
    }

    // MARK: The overlay flash (design §9)

    /// Shows a new result on the selected mask for 1.5 s, when the overlay is off.
    private func flashOverlay(on mask: UUID) {
        guard selectedMaskID == mask, !showsMaskOverlay, state == .ready else { return }
        overlayFlashSets = true
        showsMaskOverlay = true
        overlayFlashSets = false
        isFlashingOverlay = true
        overlayFlashTask?.cancel()
        overlayFlashTask = Task { [weak self] in
            try? await Task.sleep(for: Self.overlayFlashDuration)
            guard !Task.isCancelled else { return }
            self?.endOverlayFlash()
        }
    }

    /// Ends a flash: the overlay goes off again. Does nothing without one.
    func endOverlayFlash() {
        guard isFlashingOverlay else { return }
        isFlashingOverlay = false
        overlayFlashTask?.cancel()
        overlayFlashTask = nil
        overlayFlashSets = true
        showsMaskOverlay = false
        overlayFlashSets = false
    }
}
