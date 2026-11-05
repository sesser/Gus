import SwiftUI
import PhotoCore
import PhotoUI

/// The sharpening map's commands (docs/features/sharpen-mask-preview/design.md
/// §3): the Adjust menu, the loupe's context menu and VoiceOver action, Esc,
/// and the inspector's toggle all come here.
extension LibraryModel {
    /// Show Sharpening Map can act: an editable photo in the loupe, no crop
    /// session, not reviewing. The menu, context menu, VoiceOver actions and
    /// the inspector button all read this (design §11, P2).
    var canShowSharpeningMap: Bool {
        mode == .loupe && focusedItem?.isVideo == false && editor.canShowSharpeningMap && !isReviewing
    }

    /// Where a show or hide comes from.
    enum SharpeningMapCommand {
        /// The inspector's toggle, which speaks its own state and sits under Masking.
        case button
        /// The menu bar, the context menu, the VoiceOver action, the debug
        /// script: revealing Masking on show and announcing the change.
        case menu
        /// Esc in the loupe: announces the change.
        case key
    }

    func toggleSharpeningMap(from command: SharpeningMapCommand) {
        setSharpeningMap(!editor.showsSharpeningMap, from: command)
    }

    func setSharpeningMap(_ shown: Bool, from command: SharpeningMapCommand) {
        if shown {
            guard canShowSharpeningMap, !editor.showsSharpeningMap else { return }
            editor.showSharpeningMap()
            guard editor.showsSharpeningMap else { return }
            if command == .menu { revealMasking() }
            if command != .button {
                AccessibilityText.announce(SharpeningMapText.showAnnouncement(SharpeningMapStatus(editor.adjustments)))
            }
        } else {
            guard editor.showsSharpeningMap else { return }
            editor.hideSharpeningMap()
            if command != .button {
                AccessibilityText.announce(String(localized: "Showing the photo.",
                                                  comment: "VoiceOver, when the sharpening map is hidden"))
            }
        }
    }

    /// The inspector on Adjust with Details expanded and Masking in view,
    /// as Suggest Keywords reveals Keywords (design.md I7).
    private func revealMasking() {
        showsInspector = true
        inspectorTab = .adjust
        InspectorExpansion.shared.set(Self.detailsExpansionKey, true)
        revealsMaskingRow = true
    }

    /// The Adjust tab's Details heading, in `InspectorExpansion`.
    static var detailsExpansionKey: String { AdjustSection<EmptyView>.key(.details) }
}

/// The sharpening map's words (design §5, §8, §9).
enum SharpeningMapText {
    static var name: String {
        String(localized: "Sharpening Map", comment: "Name of the view of where Masking lets sharpening through: the inspector's toggle and the loupe caption's badge")
    }

    static func badge(_ status: SharpeningMapStatus) -> String {
        status.isNotApplied
            ? String(localized: "Sharpening Map · Not Applied",
                     comment: "Loupe caption badge: the map is shown while nothing is sharpened (Amount 0 or Sharpening off, and no mask in effect with Sharpness)")
            : name
    }

    static func badgeHelp(_ status: SharpeningMapStatus) -> String {
        status.isNotApplied
            ? String(localized: "Showing where sharpening would go instead of the photo. No sharpening is applied now. Press Esc to see the photo again.",
                     comment: "Tooltip of the loupe caption's badge, not applied")
            : String(localized: "Showing where Masking lets sharpening through instead of the photo: white is sharpened, black is not. Press Esc to see the photo again.",
                     comment: "Tooltip of the loupe caption's badge, applied")
    }

    /// The inspector caption while the map is shown (design §5, §7).
    static func legend(_ status: SharpeningMapStatus) -> String {
        let reason: String = switch status.reason {
        case nil:
            String(localized: "White areas are sharpened, gray areas in part, and black areas not at all.",
                   comment: "Inspector legend under Sharpening Map, sharpening applied")
        case .turnedOff:
            String(localized: "Sharpening is turned off. Turn it on to sharpen the white areas, and the gray areas in part.",
                   comment: "Inspector legend under Sharpening Map, the Sharpening group is off")
        case .amountZero:
            String(localized: "Amount is 0. Raise it to sharpen the white areas, and the gray areas in part.",
                   comment: "Inspector legend under Sharpening Map, Amount 0")
        }
        guard status.notesMaskSharpening else { return reason }
        // Says only that masks sharpen, never that they follow the map (owner ruling RI-2).
        return reason + " " + String(localized: "Masks with Sharpness still sharpen the areas they cover.",
                                     comment: "Added to the legend when Amount is 0 or Sharpening is off and a mask in effect has Sharpness")
    }

    /// The inspector caption while the map is hidden: the Sharpening hint.
    static var hint: String {
        String(localized: "Judge Amount, Radius and Detail at 100% (Z) once the change is saved. Sharpening Map shows Masking's effect at any zoom.",
               comment: "Inspector caption under the Sharpening Map toggle while the map is hidden")
    }

    static func showAnnouncement(_ status: SharpeningMapStatus) -> String {
        status.isNotApplied
            ? String(localized: "Showing the sharpening map. No sharpening is applied.",
                     comment: "VoiceOver, when the sharpening map is shown while nothing is sharpened")
            : String(localized: "Showing the sharpening map.", comment: "VoiceOver, when the sharpening map is shown")
    }

    /// The loupe canvas's VoiceOver value: the map first, then the photo's usual value.
    static func canvasValue(_ status: SharpeningMapStatus, photoValue: String) -> String {
        status.isNotApplied
            ? String(localized: "Sharpening map, no sharpening applied, \(photoValue)",
                     comment: "Loupe VoiceOver value while the map is shown and nothing is sharpened; the argument is the photo's usual value, such as Picked, 13 of 87")
            : String(localized: "Sharpening map, \(photoValue)",
                     comment: "Loupe VoiceOver value while the map is shown; the argument is the photo's usual value, such as Picked, 13 of 87")
    }

    static var menuTitle: (show: String, hide: String) {
        (String(localized: "Show Sharpening Map", comment: "Shows where Masking lets sharpening through, in place of the photo"),
         String(localized: "Hide Sharpening Map", comment: "Returns the loupe to the photo"))
    }
}
