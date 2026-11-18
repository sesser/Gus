import AppKit
import PhotoCore
import SwiftUI

/// The Adjust tab's Spots heading (docs/features/healing/design.md §2, §3, §9):
/// the Edit Spots toggle, what the controls act on, Heal or Clone, Size,
/// Feather and Opacity, the state caption and the paste note.
struct SpotsSection: View {
    let editor: AdjustmentEditor
    @InspectorExpanded(Self.key, family: .adjust, default: false) private var isExpanded

    static let key = "adjust.section.spots"

    var body: some View {
        let values = editor.adjustments
        let isModified = values.isModified(Adjustments.Group.spots)
        let isOn = values.isEnabled(Adjustments.Group.spots)
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: SpotText.title, isExpanded: $isExpanded, family: .adjust,
                          turnOff: isModified ? (isOn ? String(localized: "Turn Off") : String(localized: "Turn On"),
                                                 { editor.setEnabled(Adjustments.Group.spots, !isOn) }) : nil,
                          reset: isModified ? { editor.deleteAllSpots() } : nil, resetTitle: SpotText.deleteAll,
                          trailingWidth: nil) {
                GroupToggle(group: .spots, editor: editor)
            } trailing: {
                HStack(spacing: 0) {
                    AppKitButton(symbol: editor.showsSpotOverlay ? "eye.fill" : "eye", style: .borderless,
                                 tint: editor.showsSpotOverlay && editor.isEditingSpots ? .controlAccentColor : .secondaryLabelColor,
                                 help: String(localized: "Show the spots and their sources",
                                              comment: "Tooltip of the Spots heading's eye: shows or hides the spot overlay"),
                                 accessibilityLabel: editor.showsSpotOverlay ? SpotText.hideOverlay : SpotText.showOverlay,
                                 isEnabled: editor.isEditingSpots) {
                        editor.showsSpotOverlay.toggle()
                    }
                    .disabled(!editor.isEditingSpots)
                    .frame(width: InspectorMetrics.resetSlot)
                    AppKitButton(symbol: "arrow.counterclockwise", style: .borderless, tint: .secondaryLabelColor,
                                 help: SpotText.deleteAll, isEnabled: isModified) {
                        editor.deleteAllSpots()
                    }
                    .disabled(!isModified)
                    .frame(width: InspectorMetrics.resetSlot)
                }
            }
            if isExpanded {
                SpotControls(editor: editor)
            }
        }
    }
}

private struct SpotControls: View {
    let editor: AdjustmentEditor

    var body: some View {
        let selected = editor.selectedSpot
        let template = editor.spotTemplate
        let cropping = editor.cropSession != nil
        VStack(alignment: .leading, spacing: 10) {
            AppKitButton(title: SpotText.editSpots, symbol: "bandage", style: .toggle(isOn: editor.isEditingSpots),
                         help: cropping ? String(localized: "Finish cropping to edit spots.",
                                                 comment: "Tooltip of Edit Spots during a crop session")
                                        : String(localized: "Click spots in the photo to heal or clone them (H)",
                                                 comment: "Tooltip of the Edit Spots toggle"),
                         accessibilityHint: String(localized: "Click spots in the photo to heal or clone them",
                                                   comment: "VoiceOver help of the Edit Spots toggle"),
                         isEnabled: editor.canEditSpots || editor.isEditingSpots) {
                editor.toggleEditingSpots()
            }
            .disabled(!(editor.canEditSpots || editor.isEditingSpots))
            .fixedSize()
            contextRow(selected: selected)
            AppKitSegmented(labels: SpotMode.allCases.map(SpotText.mode),
                            selection: SpotMode.allCases.firstIndex(of: editor.shownSpotMode) ?? 0,
                            toolTips: SpotMode.allCases.map(SpotText.modeHelp),
                            accessibilityLabel: String(localized: "Spot mode", comment: "VoiceOver name of the Heal / Clone control")) {
                editor.setSpotMode(SpotMode.allCases[$0])
            }
            .frame(maxWidth: .infinity)
            AdjustSlider(title: String(localized: "Size"), value: (selected?.size ?? template.size) * 100,
                         range: SpotTemplate.sizePercentRange, defaultValue: SpotTemplate.defaultSize * 100,
                         format: .decimal,
                         accessibilityLabel: String(localized: "Spot size", comment: "VoiceOver name of the Spots Size slider"),
                         fieldAccessibilityLabel: String(localized: "Spot size value", comment: "VoiceOver name of the Spots Size field")) { value, phase in
                editor.setSpotSize(percent: value, phase: phase)
            }
            AdjustSlider(title: String(localized: "Feather"), value: selected?.feather ?? template.feather,
                         range: Spot.percentRange, defaultValue: Spot.defaultFeather, format: .plain,
                         accessibilityLabel: String(localized: "Spot feather", comment: "VoiceOver name of the Spots Feather slider"),
                         fieldAccessibilityLabel: String(localized: "Spot feather value", comment: "VoiceOver name of the Spots Feather field")) { value, phase in
                editor.setSpotFeather(value, phase: phase)
            }
            AdjustSlider(title: String(localized: "Opacity", comment: "Spots slider: how much of the fix shows"),
                         value: selected?.opacity ?? template.opacity,
                         range: Spot.percentRange, defaultValue: Spot.defaultOpacity, format: .plain,
                         accessibilityLabel: String(localized: "Spot opacity", comment: "VoiceOver name of the Spots Opacity slider"),
                         fieldAccessibilityLabel: String(localized: "Spot opacity value", comment: "VoiceOver name of the Spots Opacity field")) { value, phase in
                editor.setSpotOpacity(value, phase: phase)
            }
            caption
            Text("Presets and Paste Adjustments leave spots out.",
                 comment: "The Spots heading's note, in the Masks heading's words (healing design §11)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .showsTurnedOff(.spots, editor: editor)
    }

    /// "New spot" or "Spot 3 of 12" (or the limit), the trash button and the ⋯ menu.
    private func contextRow(selected: Spot?) -> some View {
        let count = editor.adjustments.spots.spots.count
        let atLimit = editor.spotsAtLimit && selected == nil
        return HStack(spacing: InspectorMetrics.gap) {
            if atLimit {
                Label {
                    Text(SpotText.count(count))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let index = editor.selectedSpotIndex {
                Text("Spot \(index + 1) of \(count)", comment: "Spots context row: which spot the controls change, in placement order")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("New spot", comment: "Spots context row: the controls set the next spot's values")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AppKitButton(symbol: "trash", style: .borderless, tint: .secondaryLabelColor, help: SpotText.delete,
                         accessibilityLabel: SpotText.delete, isEnabled: selected != nil) {
                editor.deleteSelectedSpot()
            }
            .disabled(selected == nil)
            .frame(width: 22)
            AppKitMenuButton(title: "", symbol: "ellipsis.circle", entries: menuEntries(selected: selected),
                             help: String(localized: "Spot commands", comment: "Tooltip and VoiceOver name of the Spots ⋯ menu"))
                .frame(width: InspectorMetrics.resetSlot + 4)
        }
        .frame(height: SliderRow.height)
    }

    private func menuEntries(selected: Spot?) -> [AppKitMenuButton.Entry] {
        let canSelect = editor.isEditingSpots && editor.visibleSpots.count > 1
        return [
            .item(SpotText.chooseSource, isEnabled: selected != nil) { editor.chooseSpotSourceAutomatically() },
            .item(SpotText.selectNext, isEnabled: canSelect) { editor.selectSpot(next: true) },
            .item(SpotText.selectPrevious, isEnabled: canSelect) { editor.selectSpot(next: false) },
            .separator,
            .item(SpotText.delete, isEnabled: selected != nil) { editor.deleteSelectedSpot() },
            .item(SpotText.deleteAll, isEnabled: !editor.adjustments.spots.isIdentity) { editor.deleteAllSpots() },
        ]
    }

    @ViewBuilder
    private var caption: some View {
        let state = SpotCaption(editor)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if state.isWarning {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
            }
            Text(state.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// The Spots heading's state caption, one role at a time in the design's
/// priority (§3).
struct SpotCaption: Equatable {
    var text: String
    var isWarning = false

    @MainActor
    init(_ editor: AdjustmentEditor) {
        let count = editor.adjustments.spots.spots.count
        if editor.spotNotice == .noSource {
            text = SpotText.notice(.noSource)
        } else if editor.spotNotice == .atLimit || (editor.isEditingSpots && editor.spotsAtLimit) {
            text = SpotText.notice(.atLimit)
            isWarning = true
        } else if editor.isEditingSpots, editor.selectedSourceIsOutsideCrop {
            text = String(localized: "This spot's source is outside the crop. Drag the spot, or choose a source automatically.",
                          comment: "Spots caption: the selected spot copies from outside the crop")
        } else if editor.isEditingSpots, !editor.showsSpotOverlay {
            text = String(localized: "The overlay is hidden, so a click adds a spot. Show the overlay to select one.",
                          comment: "Spots caption while editing with the overlay hidden")
        } else if editor.isEditingSpots, editor.selectedSpotID != nil {
            text = String(localized: "Drag the spot to move it, or drag the circle it copies from. Press Delete to remove it.",
                          comment: "Spots caption while a spot is selected")
        } else if editor.isEditingSpots {
            text = count == 0
                ? String(localized: "Click a dust spot or blemish in the photo. Press Esc when you are done.",
                         comment: "Spots caption while editing a photo with no spots")
                : String(localized: "Click the photo to add a spot, or click a spot to change it. Press Esc when you are done.",
                         comment: "Spots caption while editing a photo with spots, none selected")
        } else if count == 0 {
            text = String(localized: "Choose Edit Spots, then click a dust spot or blemish in the photo. It is filled from a clean area nearby.",
                          comment: "Spots caption: not editing, no spots")
        } else {
            let outside = editor.spotsOutsideCrop
            let summary = outside == 0
                ? String(localized: "\(count) spots.", comment: "Spots caption: how many spots the photo has")
                : String(localized: "\(SpotText.count(count)), \(String(localized: "\(outside) outside the crop", comment: "Spots caption: how many spots lie outside the crop")).",
                         comment: "Spots caption: how many spots (“12 spots”), then how many lie outside the crop (“2 outside the crop”)")
            text = summary + " " + String(localized: "Choose Edit Spots to change them.",
                                          comment: "Spots caption, after the count: not editing")
        }
    }
}
