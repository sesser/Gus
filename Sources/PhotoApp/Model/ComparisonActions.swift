import AppKit
import PhotoCore
import PhotoUI

/// Side by side comparison (docs/features/side-by-side-comparison): the
/// loupe showing two photos. The rules are `ComparisonRules` in PhotoCore;
/// this applies them to the library window. Every command acts on the
/// active photo, which is the focused one (`focusIndex`), so culling, the
/// menus, the Info tab and the window title need no second rule.
extension LibraryModel {
    var isComparing: Bool { comparison != nil }

    /// What the rules need to know of the photo at `index`.
    func comparisonCandidate(at index: Int) -> ComparisonCandidate {
        let item = items[index]
        return ComparisonCandidate(versionID: item.versionID, partnerVersionID: item.partnerVersionID,
                                   isVideo: item.isVideo, isOffline: isOffline(item))
    }

    /// View ▸ Compare Side by Side / Stop Comparing is enabled (by counts
    /// only; a photo that can't be compared is explained when chosen).
    var canToggleComparison: Bool {
        ComparisonRules.canToggle(isComparing: isComparing, isCropping: editor.cropSession != nil,
                                  isLoupe: mode == .loupe, selectedCount: selectedCount, itemCount: itemCount)
    }

    /// The pane's photo, while it is in the source.
    func comparisonItem(_ side: ComparisonSide) -> CatalogItem? {
        _ = itemsRevision
        return comparison.flatMap { item(versionID: $0[side]) }
    }

    // MARK: Entering and leaving

    /// View ▸ Compare Side by Side / Stop Comparing (S), the toolbar's
    /// Compare and the context menus' items.
    func toggleComparison() {
        if isComparing { stopComparing() } else { enterComparison() }
    }

    func enterComparison() {
        guard comparison == nil, canToggleComparison else { return }
        let isLoupe = mode == .loupe
        let entry = ComparisonRules.entry(isLoupe: isLoupe, selection: Array(selection), focus: focusIndex,
                                          count: items.count, remembered: isLoupe ? rememberedComparison : nil,
                                          candidate: comparisonCandidate(at:))
        switch entry {
        case .unavailable:
            return
        case .refused(let refusal):
            showComparisonRefusal(refusal)
        case .enter(let state):
            // Like entering review: photos only, as saved.
            if editor.showsOriginal { editor.showsOriginal = false }
            editor.endSharpeningMap()
            editor.armFringePicker(nil)
            // The loupe's photo refits into the pane it goes to; from the grid both appear at once.
            let animates = isLoupe && focusedItem?.isVideo == false && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            comparisonEntersFrom = animates ? focusedItem.flatMap { state.side(of: $0.versionID) } : nil
            comparisonLeaving = nil
            comparisonHDRHeadroom = [:]
            comparison = state
            rememberComparison(state)
            selectComparison(state)
            if mode != .loupe { mode = .loupe }
            announceComparison(state)
        }
    }

    /// Back to the single loupe on the active photo; the pair on screen
    /// stays selected (ruling RI-1).
    func stopComparing() {
        guard let state = comparison else { return }
        comparisonLeaving = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : state
        comparison = nil
        comparisonHDRHeadroom = [:]
        comparisonDidEnd()
        announceLoupePhoto()
    }

    /// Ends a comparison without the leaving animation: the loupe is
    /// closing, or it is about to show another photo alone.
    func endComparison() {
        guard comparison != nil || comparisonLeaving != nil else { return }
        let wasComparing = comparison != nil
        comparison = nil
        comparisonLeaving = nil
        comparisonHDRHeadroom = [:]
        if wasComparing { comparisonDidEnd() }
    }

    /// Each photo's last comparison, as it stands now, so `S` brings the
    /// same two back on the same sides with the same one active. Also
    /// called when a reload changes a side's file (`apply`).
    func rememberComparison(_ state: ComparisonState) {
        comparisonMemory[state.left] = state
        comparisonMemory[state.right] = state
    }

    /// The comparison the loupe's photo was last in since the loupe opened,
    /// and where its other photo is in the source now.
    private var rememberedComparison: (state: ComparisonState, partnerIndex: Int)? {
        guard let item = focusedItem, let state = comparisonMemory[item.versionID], let side = state.side(of: item.versionID),
              let partner = indexOfVersion(state[side.next]) else { return nil }
        return (state, partner)
    }

    // MARK: The active photo

    /// View ▸ Switch to Right Photo / Switch to Left Photo (A): the next pane.
    func switchComparisonSide() {
        guard let comparison else { return }
        setComparisonActive(comparison.active.next)
    }

    /// A click on a pane, the switch key, VoiceOver's Make Active.
    func setComparisonActive(_ side: ComparisonSide, announces: Bool = true) {
        guard var state = comparison, state.active != side else { return }
        state.active = side
        comparison = state
        rememberComparison(state)
        selectComparison(state)
        guard announces, let item = comparisonItem(side) else { return }
        // High priority, so a fast run speaks only the latest.
        let photo = AccessibilityText.list([PhotoName.display(item), PhotoAccessibility.value(for: item, offline: isOffline(item))])
        AccessibilityText.announce(ComparisonText.active(side, photo: photo))
    }

    // MARK: Walking a side

    /// The arrows, Home and End move the active side through the source;
    /// the other side stays (design §6). Returns the photo it moved to.
    @discardableResult
    func walkComparison(_ walk: ComparisonRules.Walk, announces: Bool = true) -> CatalogItem? {
        guard let state = comparison, let active = indexOfVersion(state.activeVersionID),
              let other = indexOfVersion(state.otherVersionID),
              let target = ComparisonRules.walkTarget(walk, from: active, other: other, count: items.count,
                                                      candidate: comparisonCandidate(at:)) else { return nil }
        return replaceComparisonActive(with: target, announces: announces)
    }

    /// Puts the photo at `index` in the active side.
    @discardableResult
    private func replaceComparisonActive(with index: Int, announces: Bool) -> CatalogItem? {
        guard var state = comparison, items.indices.contains(index) else { return nil }
        let item = items[index]
        state[state.active] = item.versionID
        comparison = state
        comparisonHDRHeadroom[state.active] = nil
        rememberComparison(state)
        selectComparison(state)
        if announces {
            AccessibilityText.announce(ComparisonText.moved(state.active, photo: PhotoAccessibility.loupeMove(
                to: item, offline: isOffline(item), index: index, count: items.count)))
        }
        return item
    }

    /// A click (or VoiceOver's press) on a film strip cell while comparing
    /// (design §7).
    func comparisonStripClick(_ index: Int) {
        guard let state = comparison, items.indices.contains(index), let active = indexOfVersion(state.activeVersionID),
              let other = indexOfVersion(state.otherVersionID) else { return }
        switch ComparisonRules.stripClick(on: index, activeIndex: active, otherIndex: other, active: state.active,
                                          candidate: comparisonCandidate(at:)) {
        case .nothing: break
        case .activate(let side): setComparisonActive(side)
        case .replaceActive(let target): replaceComparisonActive(with: target, announces: true)
        // The cell's marks already say why; the system's "can't do that".
        case .refuse: NSSound.beep()
        }
    }

    // MARK: Link

    /// View ▸ Link Zoom and Position, the caption's toggle, the pane menu.
    func setComparisonLinked(_ linked: Bool) {
        guard linksComparison != linked else { return }
        linksComparison = linked
        AccessibilityText.announce(linked ? ComparisonText.linkedAnnouncement : ComparisonText.unlinkedAnnouncement)
    }

    // MARK: Words

    private func announceComparison(_ state: ComparisonState) {
        guard let left = item(versionID: state.left), let right = item(versionID: state.right) else { return }
        AccessibilityText.announce(ComparisonText.entered(left: PhotoName.display(left), right: PhotoName.display(right),
                                                          active: state.active))
    }

    /// The alert of a comparison that was asked for and did not start
    /// (design §3): on the library window, one OK button.
    private func showComparisonRefusal(_ refusal: ComparisonRefusal) {
        let text = comparisonRefusalText(refusal)
        let alert = NSAlert()
        alert.messageText = text.title
        alert.informativeText = text.message
        // The alert's first button is the system's default button (Return).
        alert.addButton(withTitle: String(localized: "OK"))
        let window = windowObserver.window
        Task { _ = await WindowModal.run(alert, in: window) }
    }

    /// What the refusal's alert says.
    func comparisonRefusalText(_ refusal: ComparisonRefusal) -> (title: String, message: String) {
        // As the removal confirmation names a photo: a copy by its own name.
        func name(_ versionID: Int64) -> String { item(versionID: versionID).map(PhotoName.inFull) ?? "" }
        // The title names what was asked: one photo, or two (design §16 D5).
        let alertTitle = refusal.concernsOnePhoto ? ComparisonText.cantCompareThis : ComparisonText.cantCompareThese
        switch refusal {
        case .video(let id, _):
            return (alertTitle,
                    String(localized: "“\(name(id))” is a video. Only photos can be compared.",
                           comment: "Alert: Compare Side by Side on a video; its file name"))
        case .offline(let id, _):
            let volume = item(versionID: id).flatMap(volumeName(for:)) ?? ""
            return (alertTitle,
                    String(localized: "The original of “\(name(id))” is offline. Connect “\(volume)” to compare it.",
                           comment: "Alert: Compare Side by Side on an offline photo; its file name, its volume's name"))
        case .pairHalves(let first, let second):
            // The RAW first, whichever comes first in the source.
            let files = [first, second].sorted { item(versionID: $0)?.fileKind == .raw && item(versionID: $1)?.fileKind != .raw }
            return (alertTitle,
                    String(localized: "“\(name(files[0]))” and “\(name(files[1]))” are the RAW and JPEG files of one photo.",
                           comment: "Alert: Compare Side by Side on the two files of a RAW+JPEG pair; the RAW's and the JPEG's file names"))
        case .noPartner:
            return (alertTitle,
                    String(localized: "There’s no other photo in “\(title(for: sidebarSelection))” that can be compared with it.",
                           comment: "Alert: Compare Side by Side with no second photo; the source's name"))
        }
    }
}

/// The comparison's words (design §12).
@MainActor
enum ComparisonText {
    static var compare: String { String(localized: "Compare Side by Side", comment: "View menu, context menus (S): show two photos side by side") }
    static var stop: String { String(localized: "Stop Comparing", comment: "View menu, context menu, VoiceOver action and Adjust tab button (S)") }
    static var link: String { String(localized: "Link Zoom and Position", comment: "View menu, pane context menu, caption toggle's label: both panes zoom and scroll together") }
    static var unlink: String { String(localized: "Unlink Zoom and Position", comment: "VoiceOver action on a comparison pane") }
    static var cantCompareThese: String { String(localized: "Can’t Compare These Photos", comment: "Alert title: Compare Side by Side was refused") }
    static var cantCompareThis: String { String(localized: "Can’t Compare This Photo", comment: "Alert title: Compare Side by Side was asked for one photo and refused") }
    static var linkedAnnouncement: String { String(localized: "Zoom and position linked", comment: "VoiceOver: the comparison's link was turned on") }
    static var unlinkedAnnouncement: String { String(localized: "Zoom and position not linked", comment: "VoiceOver: the comparison's link was turned off") }

    /// "Switch to Right Photo" while the left one is active: the side it will make active.
    static func switchTitle(active: ComparisonSide?) -> String {
        active == .right ? String(localized: "Switch to Left Photo", comment: "View menu (A): makes the left photo of the comparison active")
                         : String(localized: "Switch to Right Photo", comment: "View menu (A): makes the right photo of the comparison active")
    }

    /// The link toggle's tooltip says what a click will do.
    static func linkHelp(linked: Bool) -> String {
        linked ? String(localized: "Zoom and scroll each photo on its own", comment: "Tooltip of the comparison's link toggle while linked")
               : String(localized: "Zoom and scroll both photos together", comment: "Tooltip of the comparison's link toggle while not linked")
    }

    /// "Left photo" / "Right photo": a pane, in VoiceOver's values.
    static func side(_ side: ComparisonSide) -> String {
        side == .left ? String(localized: "Left photo", comment: "VoiceOver: the comparison's left pane, or its photo's film strip cell")
                      : String(localized: "Right photo", comment: "VoiceOver: the comparison's right pane, or its photo's film strip cell")
    }

    /// "Left photo, active" for the active pane's value.
    static func paneValue(_ side: ComparisonSide, isActive: Bool) -> String {
        guard isActive else { return self.side(side) }
        return side == .left ? String(localized: "Left photo, active", comment: "VoiceOver: the comparison's left pane while it is the active one")
                             : String(localized: "Right photo, active", comment: "VoiceOver: the comparison's right pane while it is the active one")
    }

    /// "Comparing DSC00231 and DSC00232. Left photo active."
    static func entered(left: String, right: String, active: ComparisonSide) -> String {
        active == .left
            ? String(localized: "Comparing \(left) and \(right). Left photo active.", comment: "VoiceOver, on entering comparison: the two photos' names")
            : String(localized: "Comparing \(left) and \(right). Right photo active.", comment: "VoiceOver, on entering comparison with the right photo active: the two photos' names")
    }

    /// "Right photo active: DSC00232, 2 stars, Picked."
    static func active(_ side: ComparisonSide, photo: String) -> String {
        side == .left ? String(localized: "Left photo active: \(photo)", comment: "VoiceOver, after switching sides: the photo's name and culling values")
                      : String(localized: "Right photo active: \(photo)", comment: "VoiceOver, after switching sides: the photo's name and culling values")
    }

    /// "Right photo: DSC00233, RAW, 13 of 87": a side moved to another photo.
    static func moved(_ side: ComparisonSide, photo: String) -> String {
        side == .left ? String(localized: "Left photo: \(photo)", comment: "VoiceOver, after the left side moved to another photo: the loupe's announcement of it")
                      : String(localized: "Right photo: \(photo)", comment: "VoiceOver, after the right side moved to another photo: the loupe's announcement of it")
    }
}
