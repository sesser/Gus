import AppKit
import PhotoCore
import SwiftUI

/// The Presets heading of the Adjust tab: Save, Import and Manage and the
/// view switch, then the presets by collection, as a list of names or as
/// pictures of the focused photo with each preset (#241). Hovering a preset
/// shows it in the loupe; clicking it applies the preset to the photo on
/// screen (loupe) or the selection (grid).
struct PresetsSection: View {
    let model: LibraryModel
    @InspectorExpanded(Self.key, family: .adjust, default: false) private var isExpanded

    static let key = "adjust.section.presets"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: String(localized: "Presets"), isExpanded: $isExpanded, family: .adjust)
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    buttons
                    if model.adjustmentPresets.isEmpty {
                        Text("Save a photo's adjustments as a preset, or import presets (.\(PresetFile.fileExtension), .lrtemplate, .xmp, .dng or .lnpc).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(model.adjustmentPresetCollections) { collection in
                        if collection.name.isEmpty {
                            PresetItems(model: model, presets: collection.presets, textInset: PresetListMetrics.inset)
                        } else {
                            PresetCollectionSection(model: model, collection: collection)
                        }
                    }
                }
            }
        }
    }

    /// Push buttons do not shrink: they wrap when the inspector is narrow,
    /// and the view switch stays at the right edge of the first line that
    /// has room for it (`PresetsBarGeometry`).
    private var buttons: some View {
        PresetsBarLayout {
            saveButton
            importButton
            manageButton
            viewSwitch
        }
    }

    private var saveButton: some View {
        AppKitButton(title: String(localized: "Save…", comment: "Save a preset"), style: .push,
                     help: String(localized: "Save this photo's adjustments as a preset"),
                     isEnabled: model.canSaveAdjustmentPreset) {
            model.promptForAdjustmentPreset()
        }
        // SwiftUI applies its own enabled state to the control as well.
        .disabled(!model.canSaveAdjustmentPreset)
    }

    private var importButton: AppKitButton {
        AppKitButton(title: String(localized: "Import…"), style: .push,
                     help: String(localized: "Add presets from files or folders (.\(PresetFile.fileExtension), .lrtemplate, .xmp, .dng or .lnpc)")) {
            model.chooseAdjustmentPresetImport()
        }
    }

    private var manageButton: AppKitButton {
        AppKitButton(title: String(localized: "Manage…"), style: .push,
                     help: String(localized: "Rename, move, export and delete presets")) {
            model.showsPresetSheet = true
        }
    }

    /// Thumbnails or List, app-wide (design §2). Shown and enabled in every
    /// state: the choice is useful before the first import too.
    private var viewSwitch: some View {
        let choices = PresetsViewChoice.segments
        return AppKitSegmented(labels: [String(localized: "Thumbnails", comment: "Presets view switch: VoiceOver name of the thumbnails segment"),
                                        String(localized: "List", comment: "Presets view switch: VoiceOver name of the list segment")],
                               symbols: ["square.grid.2x2", "list.bullet"],
                               selection: choices.firstIndex(of: model.presetsView) ?? 0,
                               toolTips: [String(localized: "Show presets as thumbnails"),
                                          String(localized: "Show presets as a list")],
                               accessibilityLabel: String(localized: "Presets view")) { index in
            if choices.indices.contains(index) { model.presetsView = choices[index] }
        }
        .fixedSize()
    }
}

extension PresetsViewChoice {
    /// The switch's segments, left to right.
    static let segments: [PresetsViewChoice] = [.thumbnails, .list]
}

/// Lays out Save, Import, Manage and the view switch, in that order, by
/// `PresetsBarGeometry`: one view tree whatever the arrangement, so
/// VoiceOver and the keyboard reach the switch after Manage in each.
private struct PresetsBarLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let sizes = sizes(of: subviews) else { return .zero }
        return PresetsBarGeometry.size(forWidth: proposal.width, sizes)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let sizes = sizes(of: subviews) else { return }
        let frames = PresetsBarGeometry.frames(forWidth: bounds.width, sizes)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func sizes(of subviews: Subviews) -> PresetsBarGeometry.Sizes? {
        guard subviews.count == 4 else { return nil }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return PresetsBarGeometry.Sizes(save: sizes[0], importButton: sizes[1], manage: sizes[2], viewSwitch: sizes[3])
    }
}

/// A collection's sub-heading (collapsed until opened) and its presets.
private struct PresetCollectionSection: View {
    let model: LibraryModel
    let collection: AdjustmentPresetCollection
    @State private var isExpanded = false

    private var key: String { "adjust.presets.\(collection.name)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let help = isExpanded ? String(localized: "Collapse") : String(localized: "Expand")
            AppKitButton(title: collection.name, detail: collection.presets.count.formatted(),
                         symbol: isExpanded ? "chevron.down" : "chevron.right", symbolWeight: PresetListMetrics.headingSymbolWeight,
                         style: .borderless, help: help) {
                isExpanded.toggle()
                UserDefaults.standard.set(isExpanded, forKey: key)
            }
            if isExpanded {
                PresetItems(model: model, presets: collection.presets, textInset: PresetListMetrics.headingTitleInset)
            }
        }
        .onAppear { isExpanded = UserDefaults.standard.bool(forKey: key) }
    }
}

/// A collection's presets in the chosen view. The list builds no
/// `PresetGrid`, so no thumbnail renders start while it shows (R8).
private struct PresetItems: View {
    let model: LibraryModel
    let presets: [AdjustmentPreset]
    /// Where a list row's name starts.
    let textInset: CGFloat

    var body: some View {
        switch model.presetsView {
        case .list: PresetList(model: model, presets: presets, textInset: textInset)
        case .thumbnails: PresetGrid(model: model, presets: presets)
        }
    }
}

/// What a preset's thumbnail and its list row share, so the two views can't
/// drift: the tooltip, the applied mark and the context menu.
enum PresetItemRules {
    /// The tooltip: the name and the groups the preset sets.
    static func help(_ preset: AdjustmentPreset) -> String {
        "\(preset.name)\n\(PresetText.groups(preset))"
    }

    /// The photo's saved values to mark presets against: in the loupe with
    /// its editor ready; nil elsewhere (the grid marks nothing). Saved, not
    /// live: reading the live ones would redraw every item on each step of a drag.
    @MainActor static func markedAgainst(_ model: LibraryModel) -> Adjustments? {
        guard model.mode == .loupe, model.editor.state == .ready else { return nil }
        // `savedAdjustments` is not observed. The open photo's saved hash is,
        // and it changes after every save, undo and outside change, once
        // `savedAdjustments` holds the new values: reading it makes the marks
        // follow (the list reads nothing else that would).
        _ = model.editor.item?.editStackHash
        return model.editor.savedAdjustments
    }

    /// The photo already has the preset's settings.
    static func isApplied(_ preset: AdjustmentPreset, to saved: Adjustments?) -> Bool {
        saved.map { preset.applied(onto: $0) == $0 } ?? false
    }
}

extension View {
    /// A preset's context menu, in both views: Apply and Manage Presets….
    func presetContextMenu(_ preset: AdjustmentPreset, model: LibraryModel) -> some View {
        contextMenu {
            Button("Apply") { model.applyAdjustmentPreset(preset) }
            Button("Manage Presets…") { model.showsPresetSheet = true }
        }
    }
}

/// Two columns of pictures, rendered while they are shown.
private struct PresetGrid: View {
    let model: LibraryModel
    let presets: [AdjustmentPreset]

    private var previews: PresetPreviewModel { model.presetPreviews }

    var body: some View {
        let current = PresetItemRules.markedAgainst(model)
        let aspect = model.focusedItem?.orientedSize.map { $0.width / max($0.height, 1) }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(presets) { preset in
                ImageTile(image: previews.previews[PresetPreviewModel.previewID(preset)]?.cgImage,
                          title: preset.name,
                          placeholderAspect: aspect,
                          // Outlined when the photo already has the preset's settings.
                          isSelected: PresetItemRules.isApplied(preset, to: current),
                          help: PresetItemRules.help(preset),
                          onHover: { previews.hover(preset, isInside: $0) }) {
                    model.applyAdjustmentPreset(preset)
                }
                .presetContextMenu(preset, model: model)
            }
        }
        .task(id: renderKey) {
            guard let item = model.focusedItem else { return }
            // Wait for an edit to settle before rendering every preset.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await previews.render(presets, on: item)
        }
    }

    private var renderKey: String {
        guard let item = model.focusedItem else { return "" }
        return previews.key(for: item) + "|" + presets.map(PresetPreviewModel.previewID).joined(separator: ",")
    }
}
