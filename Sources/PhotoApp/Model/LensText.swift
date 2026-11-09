import Foundation
import PhotoCore

/// The Lens heading's words (docs/features/chromatic-aberration/design.md §1, §12).
enum LensText {
    // MARK: Slots

    static func slotTitle(_ slot: Int) -> String {
        String(localized: "Color \(slot)", comment: "Fringe slot row label and VoiceOver group name; the argument is 1 or 2")
    }

    static var none: String { String(localized: "None", comment: "Empty fringe slot's value; no value in a metadata comparison") }

    /// The hue name a slot shows for its color (design §3 "Name").
    static func hueName(_ color: SIMD3<Double>) -> String {
        switch FringeHueName.band(of: color) {
        case .red: String(localized: "Red", comment: "Tone curve channel; fringe color name")
        case .orange: String(localized: "Orange", comment: "Fringe color name")
        case .yellow: String(localized: "Yellow", comment: "Fringe color name")
        case .green: String(localized: "Green", comment: "Tone curve channel; fringe color name")
        case .aqua: String(localized: "Aqua", comment: "Fringe color name")
        case .blue: String(localized: "Blue", comment: "Tone curve channel; fringe color name")
        case .purple: String(localized: "Purple", comment: "Fringe color name; a common fringe color in the slot menu")
        case .magenta: String(localized: "Magenta", comment: "Fringe color name")
        }
    }

    static func listedName(_ color: CommonFringeColor) -> String {
        switch color {
        case .purple: String(localized: "Purple", comment: "Fringe color name; a common fringe color in the slot menu")
        case .green: String(localized: "Green", comment: "Tone curve channel; fringe color name")
        }
    }

    static var toleranceTitle: String { String(localized: "Tolerance", comment: "Color range slider") }

    static func toleranceLabel(_ slot: Int) -> String {
        String(localized: "Color \(slot) tolerance", comment: "VoiceOver label of a fringe slot's Tolerance slider")
    }

    static func toleranceValueLabel(_ slot: Int) -> String {
        String(localized: "Color \(slot) tolerance value", comment: "VoiceOver label of a fringe slot's Tolerance field")
    }

    static func eyedropperLabel(_ slot: Int) -> String {
        String(localized: "Pick Color \(slot)", comment: "VoiceOver label of a fringe slot's eyedropper")
    }

    static var eyedropperHelp: String {
        String(localized: "Click a fringe in the photo to pick its color", comment: "Eyedropper tooltip and VoiceOver help")
    }

    static var eyedropperCroppingHelp: String {
        String(localized: "Finish cropping to pick a fringe color.", comment: "Eyedropper tooltip, dimmed in a crop session")
    }

    static func slotMenuLabel(_ slot: Int) -> String {
        String(localized: "Color \(slot) commands", comment: "VoiceOver label of a fringe slot's menu")
    }

    static func slotMenuHelp(_ slot: Int) -> String {
        String(localized: "Choose a common fringe color for Color \(slot), pick one from the photo, or clear it",
               comment: "Fringe slot menu's tooltip and VoiceOver help")
    }

    static var pickFromPhoto: String { String(localized: "Pick from Photo", comment: "Arms the slot's eyedropper") }
    static var commonColors: String {
        String(localized: "Common Fringe Colors", comment: "Section header in the slot menu: Purple and Green follow it")
    }
    static var clear: String { String(localized: "Clear", comment: "Clears the rating and flag filters; empties a fringe slot") }

    // MARK: Undo

    static var pickUndoName: String { String(localized: "Pick Fringe Color", comment: "Undo action name") }
    static var chooseUndoName: String {
        String(localized: "Choose Fringe Color", comment: "Undo action name, a color from the list")
    }
    static var clearUndoName: String { String(localized: "Clear Fringe Color", comment: "Undo action name") }
    static var turnOnAutomaticUndoName: String { String(localized: "Turn On Automatic Alignment", comment: "Undo action name") }
    static var turnOffAutomaticUndoName: String { String(localized: "Turn Off Automatic Alignment", comment: "Undo action name") }

    // MARK: Captions

    static func pickingCaption(slot: Int) -> String {
        String(localized: "Click a colored fringe in the photo to pick Color \(slot). The magnifier outlines the pixel a click takes. Press Esc to cancel.",
               comment: "Inspector caption, picking an empty slot"
)
    }

    static func replacingCaption(slot: Int) -> String {
        String(localized: "Color \(slot)'s effect is hidden while you pick. Click a colored fringe, or press Esc to cancel.",
               comment: "Inspector caption, replacing")
    }

    static var almostNoColorCaption: String {
        String(localized: "That spot has almost no color. Click a colored fringe, or press Esc to cancel.",
               comment: "Inspector caption after a neutral click")
    }

    /// The pixel magnifier's short state for a spot a click would refuse.
    static var almostNoColorState: String {
        String(localized: "Almost no color", comment: "The pixel magnifier's plate, at a spot a click would refuse; short state, not a sentence")
    }

    /// The fringe tool's note on the pixel magnifier's plate: what it draws.
    static var magnifierNote: String {
        String(localized: "Before edits", comment: "The pixel magnifier's plate: it shows the photo before the adjustments")
    }

    /// Picking ended because the sampled pixels couldn't be made (design §19 DQ-4).
    static var originalUnreadable: String {
        String(localized: "The original could not be read. Make sure it's available, then pick again.",
               comment: "Inspector caption and VoiceOver announcement when picking ends because the photo's pixels could not be read")
    }

    static var almostNoColorAnnouncement: String {
        String(localized: "That spot has almost no color.", comment: "VoiceOver announcement")
    }

    static var noPickCaption: String {
        String(localized: "Pick a fringe's color in the photo with the eyedropper, or choose Purple or Green from the menu beside it. The color turns gray where it lines a high-contrast edge.",
               comment: "Inspector caption, no pick")
    }

    static var pickCaption: String {
        String(localized: "Raise Tolerance to include colors further from the picked one. Colors away from high-contrast edges keep theirs.",
               comment: "Inspector caption, at least one pick")
    }

    static func setAnnouncement(slot: Int, color: SIMD3<Double>) -> String {
        let name = hueName(color).lowercased()
        return String(localized: "Color \(slot) set to \(name).",
                      comment: "VoiceOver announcement after a pick or a choice from the list; %lld slot, %@ hue name")
    }

    static func clearedAnnouncement(slot: Int) -> String {
        String(localized: "Color \(slot) cleared.", comment: "VoiceOver announcement after a clear")
    }

    /// The caption under the fringe slots: one role at a time (design §3).
    @MainActor
    static func fringeCaption(_ editor: AdjustmentEditor) -> String {
        if let slot = editor.pickingFringeSlot {
            if editor.fringePickRefused { return almostNoColorCaption }
            return editor.fringeSlotIsReplaced(slot) ? replacingCaption(slot: slot) : pickingCaption(slot: slot)
        }
        if editor.fringePixelsUnreadable { return originalUnreadable }
        if let map = editor.shownFringeMap { return legend(map) }
        return editor.adjustments.colorFringes.isIdentity ? noPickCaption : pickCaption
    }

    // MARK: Fringe map

    static var mapName: String { String(localized: "Fringe Map", comment: "Inspector toggle; caption badge") }

    static func badge(_ status: FringeMapStatus) -> String {
        status.isNotApplied ? String(localized: "Fringe Map · Not Applied", comment: "Caption badge, Color Fringes off")
                            : mapName
    }

    static func badgeHelp(_ status: FringeMapStatus) -> String {
        status.isNotApplied
            ? String(localized: "Showing where fringe color would be removed instead of the photo. Color Fringes is turned off. Press Esc to see the photo again.",
                     comment: "Badge tooltip, not applied")
            : String(localized: "Showing where fringe color is removed instead of the photo: white loses its color, black keeps it. Press Esc to see the photo again.",
                     comment: "Badge tooltip, applied")
    }

    static func legend(_ status: FringeMapStatus) -> String {
        status.isNotApplied
            ? String(localized: "Color Fringes is turned off. Turn it on to remove color from the white areas, and the gray areas in part.",
                     comment: "Legend, group off")
            : String(localized: "White areas lose their color, gray areas in part, and black areas keep it.",
                     comment: "Legend, applied")
    }

    static var mapHelp: String {
        String(localized: "Show where fringe color is removed, in place of the photo", comment: "Toggle tooltip and help, enabled")
    }

    static var mapNoPickHelp: String {
        String(localized: "Pick or choose a fringe color to show the fringe map.", comment: "Toggle tooltip, dimmed with no pick")
    }

    static var mapCroppingHelp: String {
        String(localized: "Finish cropping to show the fringe map.", comment: "Toggle tooltip, crop session")
    }

    static var mapReviewHelp: String {
        String(localized: "Exit Review (F) to show the fringe map.", comment: "Toggle tooltip, review mode")
    }

    static var menuTitle: (show: String, hide: String) {
        (String(localized: "Show Fringe Map", comment: "Adjust menu; loupe context menu; VoiceOver action"),
         String(localized: "Hide Fringe Map", comment: "Adjust menu; loupe context menu; VoiceOver action"))
    }

    static var refiningMap: String {
        String(localized: "Refining the fringe map", comment: "Caption spinner tooltip and VoiceOver label")
    }

    static var refiningPhoto: String {
        String(localized: "Refining the photo", comment: "Caption spinner while the loupe waits for the photo's full detail: replacing a pick zoomed in, or after a change, pan or zoom at 100% and above.")
    }

    static func canvasValue(_ status: FringeMapStatus, photoValue: String) -> String {
        status.isNotApplied
            ? String(localized: "Fringe map, not applied, \(photoValue)", comment: "Canvas VoiceOver value, group off")
            : String(localized: "Fringe map, \(photoValue)", comment: "Canvas VoiceOver value; %@ is the photo's usual value")
    }

    static func pickingCanvasValue(_ photoValue: String) -> String {
        String(localized: "Picking a fringe color, \(photoValue)", comment: "Canvas VoiceOver value while picking")
    }

    static func showAnnouncement(_ status: FringeMapStatus) -> String {
        status.isNotApplied
            ? String(localized: "Showing the fringe map. Color Fringes is turned off.", comment: "Announcement, not applied")
            : String(localized: "Showing the fringe map.", comment: "Announcement")
    }

    // MARK: Color alignment

    static var alignAutomatically: String { String(localized: "Align automatically", comment: "Check box") }
    static var alignHelp: String {
        String(localized: "Measure this photo and line up its red and blue edges with the green",
               comment: "Check box tooltip and help")
    }
    static var redCyan: String { String(localized: "Red/cyan", comment: "Slider") }
    static var blueYellow: String { String(localized: "Blue/yellow", comment: "Slider") }
    static var measuringLabel: String {
        String(localized: "Measuring color alignment", comment: "Spinner tooltip and VoiceOver label")
    }

    enum AlignmentState: Equatable {
        case off, measuring, corrected, nothingFound, failed, handSet
    }

    @MainActor
    static func alignmentState(of editor: AdjustmentEditor) -> AlignmentState {
        let alignment = editor.adjustments.colorAlignment
        if editor.isMeasuringAlignment { return .measuring }
        if editor.alignmentMeasureFailed { return .failed }
        if alignment.automatic { return alignment.isIdentity ? .nothingFound : .corrected }
        return alignment.isIdentity ? .off : .handSet
    }

    static func alignmentCaption(_ state: AlignmentState) -> String {
        switch state {
        case .off:
            String(localized: "Removes red/cyan and blue/yellow outlines that widen toward the corners.", comment: "Caption, off")
        case .measuring: String(localized: "Measuring this photo…", comment: "Caption, measuring")
        case .corrected:
            String(localized: "Measured on this photo. Paste and presets measure each photo again.", comment: "Caption, automatic")
        case .nothingFound:
            String(localized: "No color edges were found to correct in this photo.", comment: "Caption, measured nothing")
        case .failed: String(localized: "This photo could not be measured.", comment: "Caption, failed")
        case .handSet: String(localized: "Set by hand. Paste and presets copy these values.", comment: "Caption, hand-set")
        }
    }
}
