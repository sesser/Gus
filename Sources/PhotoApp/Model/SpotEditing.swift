import AppKit
import PhotoCore
import PhotoUI
import os

/// What the next spot gets (healing design §3): the mode, size, feather and
/// opacity last set, kept as app preferences under generic keys, never in
/// the photo.
struct SpotTemplate: Equatable {
    var mode = SpotMode.heal
    /// The radius, a fraction of the long edge.
    var size = SpotTemplate.defaultSize
    var feather = Spot.defaultFeather
    var opacity = Spot.defaultOpacity

    /// 0.3 % of the long edge: an 18-pixel radius at 24 MP (6000 px), wide
    /// enough to cover a typical dust speck with the soft edge outside it.
    static let defaultSize = 0.003
    /// The inspector's range for Size, in percent of the long edge (design §3).
    static let sizePercentRange: ClosedRange<Double> = 0.1...10

    private static let keys = (mode: "spots.mode", size: "spots.size", feather: "spots.feather", opacity: "spots.opacity")

    static func stored(_ defaults: UserDefaults = .standard) -> SpotTemplate {
        var template = SpotTemplate()
        if let mode = defaults.string(forKey: keys.mode).flatMap(SpotMode.init(rawValue:)) { template.mode = mode }
        if let size = defaults.object(forKey: keys.size) as? Double, size.isFinite {
            template.size = min(max(size, sizePercentRange.lowerBound / 100), sizePercentRange.upperBound / 100)
        }
        if let feather = defaults.object(forKey: keys.feather) as? Double, feather.isFinite {
            template.feather = min(max(feather, 0), 100)
        }
        if let opacity = defaults.object(forKey: keys.opacity) as? Double, opacity.isFinite {
            template.opacity = min(max(opacity, 0), 100)
        }
        return template
    }

    func store(_ defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: Self.keys.mode)
        defaults.set(size, forKey: Self.keys.size)
        defaults.set(feather, forKey: Self.keys.feather)
        defaults.set(opacity, forKey: Self.keys.opacity)
    }
}

/// Why the last click added no spot (design §3's caption, §5, §7).
enum SpotNotice: Equatable {
    /// No clean area nearby to copy from.
    case noSource
    /// The photo has `SpotLimits.spots` spots.
    case atLimit
}

extension AdjustmentEditor {
    private static let spotLog = Logger(subsystem: AppBranding.bundleIdentifier, category: "spots")

    var selectedSpot: Spot? {
        guard let selectedSpotID else { return nil }
        return adjustments.spots.spots.first { $0.id == selectedSpotID }
    }

    /// Its place in placement order, from 0: "Spot 3 of 12" is index 2.
    var selectedSpotIndex: Int? {
        guard let selectedSpotID else { return nil }
        return adjustments.spots.spots.firstIndex { $0.id == selectedSpotID }
    }

    /// Spots can be edited now: a photo ready, no crop session (design §8).
    /// Review and comparing are the model's rules (`LibraryModel.canEditSpots`).
    var canEditSpots: Bool { canPickFringe }

    var spotsAtLimit: Bool { !SpotLimits.canAddSpot(to: adjustments.spots) }

    /// The mask frame in pixels, for the spot rules; nil before the first frame.
    var spotGeometry: SpotGeometry? { maskSourceSize.map(SpotGeometry.init(frameSize:)) }

    /// A spot's center lies in the photo as cropped (design §8: only those are drawn and selectable).
    func isVisible(_ spot: Spot) -> Bool {
        guard let point = outputPoint(fromMask: spot.center) else { return false }
        return (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    var visibleSpots: [Spot] { adjustments.spots.spots.filter(isVisible) }

    /// How many spots lie outside the crop (the caption counts them, design §3).
    var spotsOutsideCrop: Int { adjustments.spots.spots.count - visibleSpots.count }

    /// The selected spot's source is outside the crop (design §3's caption).
    var selectedSourceIsOutsideCrop: Bool {
        guard let spot = selectedSpot, let point = outputPoint(fromMask: spot.source) else { return false }
        return !((0...1).contains(point.x) && (0...1).contains(point.y))
    }

    // MARK: The tool

    /// Edit Spots on or off (H, the menu, the button). Turning it on needs an editable photo.
    func setEditingSpots(_ isOn: Bool) {
        guard !isOn || canEditSpots else { return }
        isEditingSpots = isOn
    }

    func toggleEditingSpots() {
        setEditingSpots(!isEditingSpots)
    }

    // MARK: Changing spots

    /// Changes the spots as one undo step (or a live frame while `phase` is
    /// changing), unless the result would pass `SpotLimits`.
    @discardableResult
    func changeSpots(_ actionName: String, phase: EditPhase, _ body: (inout Spots) -> Void) -> Bool {
        guard state == .ready else { return false }
        var next = adjustments.spots
        body(&next)
        guard SpotLimits.allows(next) else { return false }
        spotNotice = nil
        change(actionName, phase: phase) { $0.spots = next }
        return true
    }

    /// Changes one spot.
    func changeSpot(_ id: UUID, _ actionName: String, phase: EditPhase, _ body: (inout Spot) -> Void) {
        changeSpots(actionName, phase: phase) { spots in
            guard let index = spots.spots.firstIndex(where: { $0.id == id }) else { return }
            body(&spots.spots[index])
        }
    }

    /// A click on empty photo while Edit Spots is on (design §4): a spot with
    /// the next spot's values at `point` (output unit coordinates), sourced
    /// automatically, selected. Clicks queue behind one still finding its source.
    func addSpot(atOutput point: CGPoint) {
        guard isEditingSpots, canEditSpots else { return }
        spotPlacements.append(point)
        guard spotPlacementTask == nil else { return }
        spotPlacementTask = Task { [weak self] in
            while let self, !Task.isCancelled, !self.spotPlacements.isEmpty {
                let next = self.spotPlacements.removeFirst()
                await self.placeSpot(atOutput: next)
            }
            // A cancelled task's handle was cleared by whoever cancelled it; a
            // newer task's (on the next photo) is not this one's to clear (C2).
            guard !Task.isCancelled else { return }
            self?.spotPlacementTask = nil
        }
    }

    private func placeSpot(atOutput point: CGPoint) async {
        guard isEditingSpots, canEditSpots, let versionID = item?.versionID else { return }
        guard !spotsAtLimit else {
            refuseSpot(.atLimit)
            return
        }
        guard let center = maskPoint(fromOutput: point), let geometry = spotGeometry else { return }
        let template = spotTemplate
        var spot = Spot(mode: template.mode, center: MaskPoint(x: min(max(center.x, 0), 1), y: min(max(center.y, 0), 1)),
                        size: template.size, source: center, feather: template.feather, opacity: template.opacity)
        var values = adjustments
        values.spots.spots.append(spot)
        let found: MaskPoint?
        do {
            found = try await automaticSpotSource(for: spot.id, in: values)
        } catch {
            Self.spotLog.error("No automatic source: \(error.localizedDescription, privacy: .public)")
            found = nil
        }
        // The photo, the tool or the spots may have changed while the source was found.
        guard item?.versionID == versionID, isEditingSpots, state == .ready else { return }
        guard let found else {
            refuseSpot(.noSource)
            return
        }
        spot.source = found
        spot = geometry.constrained(spot)
        guard !spotsAtLimit else {
            refuseSpot(.atLimit)
            return
        }
        guard changeSpots(String(localized: "Add Spot", comment: "Undo action name and History label"), phase: .committed,
                          { $0.spots.append(spot) }) else { return }
        selectedSpotID = spot.id
        let number = adjustments.spots.spots.count
        AccessibilityText.announce(String(localized: "Spot \(number) added. \(SpotText.mode(spot.mode)). Copied from the \(SpotText.direction(of: spot, geometry: geometry)).",
                                          comment: "VoiceOver after a click adds a spot: its number, Heal or Clone, and where its source lies (left, upper right…)"))
    }

    /// Nothing added: the alert sound, the caption and VoiceOver say why (design §5, §7).
    func refuseSpot(_ notice: SpotNotice) {
        spotNotice = notice
        NSSound.beep()
        AccessibilityText.announce(SpotText.notice(notice))
    }

    /// Choose Source Automatically (R17): placement's logic for the selected spot, one undo step.
    func chooseSpotSourceAutomatically() {
        guard let id = selectedSpotID, canEditSpots, let versionID = item?.versionID else { return }
        let values = adjustments
        spotSourceTask?.cancel()
        spotSourceTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.spotSourceTask = nil } }
            let found: MaskPoint?
            do {
                found = try await self.automaticSpotSource(for: id, in: values)
            } catch {
                Self.spotLog.error("No automatic source: \(error.localizedDescription, privacy: .public)")
                found = nil
            }
            guard self.item?.versionID == versionID, self.state == .ready,
                  let spot = self.adjustments.spots.spots.first(where: { $0.id == id }) else { return }
            guard let found, let geometry = self.spotGeometry else {
                self.refuseSpot(.noSource)
                return
            }
            let sourced = geometry.sourcing(spot, from: found)
            self.changeSpot(id, String(localized: "Choose Spot Source", comment: "Undo action name and History label"),
                            phase: .committed) { $0.source = sourced.source }
            AccessibilityText.announce(String(localized: "Source chosen. Copied from the \(SpotText.direction(of: sourced, geometry: geometry)).",
                                              comment: "VoiceOver after Choose Source Automatically; where the source lies (left, upper right…)"))
        }
    }

    /// The spot moved to `center` (mask frame), its source keeping its offset
    /// where the rules allow. The center stays inside the crop, so a dragged
    /// or nudged spot never leaves the view while selected (design review F3).
    func moveSpot(_ id: UUID, to center: MaskPoint, phase: EditPhase) {
        guard let geometry = spotGeometry else { return }
        let held = heldInCrop(center)
        changeSpot(id, SpotText.moveSpot, phase: phase) { $0 = geometry.moving($0, to: held) }
    }

    /// `point` (mask frame) moved as little as needed to lie inside the photo as cropped.
    func heldInCrop(_ point: MaskPoint) -> MaskPoint {
        guard let output = outputPoint(fromMask: point) else { return point }
        let clamped = CGPoint(x: min(max(output.x, 0), 1), y: min(max(output.y, 0), 1))
        guard clamped != output else { return point }
        return maskPoint(fromOutput: clamped) ?? point
    }

    /// The source moved to `source` (mask frame), held inside the photo and clear of its spot.
    func moveSpotSource(_ id: UUID, to source: MaskPoint, phase: EditPhase) {
        guard let geometry = spotGeometry else { return }
        changeSpot(id, SpotText.moveSource, phase: phase) { $0 = geometry.sourcing($0, from: source) }
    }

    /// A spot's radius (a fraction of the long edge); the next spot's too (design §3).
    func resizeSpot(_ id: UUID, to size: Double, actionName: String, phase: EditPhase) {
        guard let geometry = spotGeometry else { return }
        let clamped = min(max(size, SpotTemplate.sizePercentRange.lowerBound / 100), SpotTemplate.sizePercentRange.upperBound / 100)
        spotTemplate.size = clamped
        changeSpot(id, actionName, phase: phase) { $0 = geometry.resizing($0, to: clamped) }
    }

    /// The Size slider: the selected spot, or the next spot with none selected.
    func setSpotSize(percent: Double, phase: EditPhase) {
        if let id = selectedSpotID {
            resizeSpot(id, to: percent / 100, actionName: String(localized: "Spot Size", comment: "Undo action name and History label"),
                       phase: phase)
        } else {
            spotTemplate.size = min(max(percent, SpotTemplate.sizePercentRange.lowerBound),
                                    SpotTemplate.sizePercentRange.upperBound) / 100
        }
    }

    func setSpotFeather(_ value: Double, phase: EditPhase) {
        spotTemplate.feather = value
        guard let id = selectedSpotID else { return }
        changeSpot(id, String(localized: "Spot Feather", comment: "Undo action name and History label"), phase: phase) {
            $0.feather = value
        }
    }

    func setSpotOpacity(_ value: Double, phase: EditPhase) {
        spotTemplate.opacity = value
        guard let id = selectedSpotID else { return }
        changeSpot(id, String(localized: "Spot Opacity", comment: "Undo action name and History label"), phase: phase) {
            $0.opacity = value
        }
    }

    /// Heal or Clone: the selected spot (one undo step) and the next spot.
    func setSpotMode(_ mode: SpotMode) {
        spotTemplate.mode = mode
        guard let id = selectedSpotID, selectedSpot?.mode != mode else { return }
        changeSpot(id, String(localized: "Change Spot Mode", comment: "Undo action name and History label"), phase: .committed) {
            $0.mode = mode
        }
    }

    /// The mode the menus and the segmented control show: the selected spot's, else the next spot's.
    var shownSpotMode: SpotMode { selectedSpot?.mode ?? spotTemplate.mode }

    func deleteSpot(_ id: UUID) {
        guard changeSpots(SpotText.delete, phase: .committed, { $0.spots.removeAll { $0.id == id } }) else { return }
        if selectedSpotID == id { selectedSpotID = nil }
        let count = SpotText.count(adjustments.spots.spots.count)
        AccessibilityText.announce(String(localized: "Spot deleted. \(count).",
                                          comment: "VoiceOver after a spot is deleted; how many are left (“3 spots”)"))
    }

    func deleteSelectedSpot() {
        if let selectedSpotID { deleteSpot(selectedSpotID) }
    }

    /// Delete All Spots: one undo step, no dialog (design §6).
    func deleteAllSpots() {
        guard !adjustments.spots.isIdentity else { return }
        selectedSpotID = nil
        changeSpots(SpotText.deleteAll, phase: .committed) { $0 = Spots() }
        AccessibilityText.announce(String(localized: "All spots deleted.", comment: "VoiceOver after Delete All Spots"))
    }

    /// Select Next / Previous Spot: the spots in the crop, in placement order, wrapping.
    func selectSpot(next: Bool) {
        let visible = visibleSpots
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedSpotID }
        let index: Int
        if let current {
            index = (current + (next ? 1 : -1) + visible.count) % visible.count
        } else {
            index = next ? 0 : visible.count - 1
        }
        selectedSpotID = visible[index].id
        if let spot = selectedSpot { AccessibilityText.announce(SpotText.elementLabel(spot, editor: self)) }
    }

    /// A nudge of the selected spot or its source by (`dx`, `dy`) in output
    /// unit coordinates (the option-arrow keys, design §6). Frames render
    /// at once; a run of nudges saves as one undo step when the arrow is
    /// released (the loupe's key up), or after a pause if no release comes
    /// (the key went up in another view).
    func nudgeSelectedSpot(dx: Double, dy: Double, source: Bool) {
        guard let spot = selectedSpot, let id = selectedSpotID,
              let origin = outputPoint(fromMask: source ? spot.source : spot.center),
              let moved = maskPoint(fromOutput: CGPoint(x: origin.x + dx, y: origin.y + dy)) else { return }
        let name = source ? SpotText.moveSource : SpotText.moveSpot
        if let pending = spotNudge, pending.name != name { commitSpotNudge() }
        if source { moveSpotSource(id, to: moved, phase: .changing) } else { moveSpot(id, to: moved, phase: .changing) }
        spotNudge?.task.cancel()
        spotNudge = (name, Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.commitSpotNudge()
        })
    }

    /// Forgets a waiting run of nudges whose values an undo, a redo or
    /// another writer replaced.
    func dropSpotNudge() {
        spotNudge?.task.cancel()
        spotNudge = nil
    }

    /// Saves a run of nudges as one undo step.
    func commitSpotNudge() {
        guard let pending = spotNudge else { return }
        spotNudge = nil
        pending.task.cancel()
        change(pending.name, phase: .committed) { _ in }
    }
}

/// The Spots words shared by the inspector, menus, overlay and VoiceOver.
enum SpotText {
    static var title: String { AdjustText.title(Adjustments.Group.spots) }
    static var moveSpot: String { String(localized: "Move Spot", comment: "Undo action name, History label and Adjust ▸ Spots submenu") }
    static var moveSource: String { String(localized: "Move Spot Source", comment: "Undo action name and History label") }
    static var delete: String { String(localized: "Delete Spot", comment: "Undo action name, History label, menu item and the trash button's tooltip") }
    static var chooseSource: String { String(localized: "Choose Source Automatically", comment: "Adjust ▸ Spots, the ⋯ menu, the loupe's context menu and VoiceOver action") }
    static var selectNext: String { String(localized: "Select Next Spot", comment: "Adjust ▸ Spots and the ⋯ menu") }
    static var selectPrevious: String { String(localized: "Select Previous Spot", comment: "Adjust ▸ Spots and the ⋯ menu") }
    static var showOverlay: String { String(localized: "Show Spot Overlay", comment: "Adjust ▸ Spots and the loupe's context menu") }
    static var hideOverlay: String { String(localized: "Hide Spot Overlay", comment: "Adjust ▸ Spots and the loupe's context menu") }
    static var editSpots: String { String(localized: "Edit Spots", comment: "Adjust ▸ Spots, the Spots heading's toggle, the loupe's context menu and the toolbar item") }
    static var finishEditing: String { String(localized: "Finish Editing Spots", comment: "Adjust ▸ Spots and the loupe's context menu, while Edit Spots is on") }
    static var deleteAll: String { String(localized: "Delete All Spots", comment: "Undo action name, History label, menu item and the Spots heading's reset") }

    /// "12 spots", "1 spot".
    static func count(_ count: Int) -> String {
        String(localized: "\(count) spots", comment: "How many spots a photo has: the Spots context row at the limit, captions and VoiceOver")
    }

    static func mode(_ mode: SpotMode) -> String {
        switch mode {
        case .heal: String(localized: "Heal", comment: "Spot mode: blend the copied texture into the surrounding tone and color")
        case .clone: String(localized: "Clone", comment: "Spot mode: copy the source exactly as it is")
        }
    }

    static func modeHelp(_ mode: SpotMode) -> String {
        switch mode {
        case .heal: String(localized: "Blend the copied texture into the surrounding tone and color",
                           comment: "Tooltip of the Heal segment")
        case .clone: String(localized: "Copy the source exactly as it is", comment: "Tooltip of the Clone segment")
        }
    }

    static func notice(_ notice: SpotNotice) -> String {
        switch notice {
        case .noSource:
            String(localized: "There's no clean area nearby to copy from. Try a smaller size, or click somewhere else.",
                   comment: "Spots caption and VoiceOver: a click found no source, nothing was added")
        case .atLimit:
            String(localized: "This photo has \(SpotLimits.spots) spots, the most it can have. Delete one to add another.",
                   comment: "Spots caption, the Spot Limit badge's tooltip and VoiceOver: the photo is at the limit")
        }
    }

    /// Where the source lies seen from the spot, in words.
    static func direction(of spot: Spot, geometry: SpotGeometry) -> String {
        word(SpotGeometry.direction(from: geometry.pixels(spot.center), to: geometry.pixels(spot.source)))
    }

    static func word(_ direction: SpotDirection) -> String {
        switch direction {
        case .left: String(localized: "left", comment: "Spot announcement: Copied from the left")
        case .right: String(localized: "right", comment: "Spot announcement: Copied from the right")
        case .above: String(localized: "top", comment: "Spot announcement: Copied from the top")
        case .below: String(localized: "bottom", comment: "Spot announcement: Copied from the bottom")
        case .upperLeft: String(localized: "upper left", comment: "Spot announcement and position word")
        case .upperRight: String(localized: "upper right", comment: "Spot announcement and position word")
        case .lowerLeft: String(localized: "lower left", comment: "Spot announcement and position word")
        case .lowerRight: String(localized: "lower right", comment: "Spot announcement and position word")
        }
    }

    /// The position in thirds of the visible photo (design §12): "upper left" … "center".
    static func position(_ point: CGPoint) -> String {
        let column = min(max(Int(point.x * 3), 0), 2), row = min(max(Int(point.y * 3), 0), 2)
        switch (row, column) {
        case (0, 0): return word(.upperLeft)
        case (0, 1): return String(localized: "top", comment: "Spot announcement: Copied from the top")
        case (0, 2): return word(.upperRight)
        case (1, 0): return word(.left)
        case (1, 2): return word(.right)
        case (2, 0): return word(.lowerLeft)
        case (2, 1): return String(localized: "bottom", comment: "Spot announcement: Copied from the bottom")
        case (2, 2): return word(.lowerRight)
        default: return String(localized: "center", comment: "Spot position word: the middle third of the photo")
        }
    }

    /// The overlay element's label: "Spot 3, Heal, upper left" (design §12).
    @MainActor
    static func elementLabel(_ spot: Spot, editor: AdjustmentEditor) -> String {
        let number = (editor.adjustments.spots.spots.firstIndex { $0.id == spot.id } ?? 0) + 1
        let place = editor.outputPoint(fromMask: spot.center).map(position) ?? ""
        return String(localized: "Spot \(number), \(mode(spot.mode)), \(place)",
                      comment: "VoiceOver label of a spot on the photo: its number, Heal or Clone, its position")
    }
}
