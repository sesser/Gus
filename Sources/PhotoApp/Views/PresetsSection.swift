import AppKit
import PhotoCore
import SwiftUI

/// The Presets heading of the Adjust tab: Save, Import and Manage, then a
/// picture of the focused photo with each preset, by collection. Hovering a
/// picture shows the preset in the loupe; clicking it applies the preset to
/// the photo on screen (loupe) or the selection (grid).
struct PresetsSection: View {
    let model: LibraryModel
    @State private var isExpanded = SectionHeaderState.isExpanded(key: Self.key, default: false)

    static let key = "adjust.section.presets"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: String(localized: "Presets"), isExpanded: $isExpanded, key: Self.key) {
                EmptyView()
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    buttons
                    if model.adjustmentPresets.isEmpty {
                        Text("Save a photo's adjustments as a preset, or import presets (.\(PresetFile.fileExtension), .lrtemplate, .xmp or .dng).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(model.adjustmentPresetCollections) { collection in
                        if collection.name.isEmpty {
                            PresetGrid(model: model, presets: collection.presets)
                        } else {
                            PresetCollectionSection(model: model, collection: collection)
                        }
                    }
                }
            }
        }
    }

    /// Push buttons do not shrink: they wrap when the inspector is narrow.
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                saveButton
                importButton
                manageButton
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    saveButton
                    importButton
                }
                manageButton
            }
        }
    }

    private var saveButton: AppKitButton {
        AppKitButton(title: String(localized: "Save…", comment: "Save a preset"), style: .push,
                     help: String(localized: "Save this photo's adjustments as a preset"),
                     isEnabled: model.focusedItem != nil) {
            model.promptForAdjustmentPreset()
        }
    }

    private var importButton: AppKitButton {
        AppKitButton(title: String(localized: "Import…"), style: .push,
                     help: String(localized: "Add presets from files or folders (.\(PresetFile.fileExtension), .lrtemplate, .xmp or .dng)")) {
            model.chooseAdjustmentPresetImport()
        }
    }

    private var manageButton: AppKitButton {
        AppKitButton(title: String(localized: "Manage…"), style: .push,
                     help: String(localized: "Rename, move, export and delete presets")) {
            model.requestsPresetWindow = true
        }
    }
}

/// A collection's sub-heading (collapsed until opened) and its pictures.
private struct PresetCollectionSection: View {
    let model: LibraryModel
    let collection: AdjustmentPresetCollection
    @State private var isExpanded = false

    private var key: String { "adjust.presets.\(collection.name)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let help = isExpanded ? String(localized: "Collapse") : String(localized: "Expand")
            AppKitButton(title: collection.name, detail: collection.presets.count.formatted(),
                         symbol: isExpanded ? "chevron.down" : "chevron.right", symbolWeight: .semibold,
                         style: .borderless, help: help) {
                isExpanded.toggle()
                UserDefaults.standard.set(isExpanded, forKey: key)
            }
            if isExpanded {
                PresetGrid(model: model, presets: collection.presets)
            }
        }
        .onAppear { isExpanded = SectionHeaderState.isExpanded(key: key, default: false) }
    }
}

/// Two columns of pictures, rendered while they are shown.
private struct PresetGrid: View {
    let model: LibraryModel
    let presets: [AdjustmentPreset]

    private var previews: PresetPreviewModel { model.presetPreviews }

    var body: some View {
        // Saved values: reading the live ones would redraw every picture on each step of a drag.
        let current = model.mode == .loupe && model.editor.state == .ready ? model.editor.savedAdjustments : nil
        let aspect = model.focusedItem?.orientedSize.map { $0.width / max($0.height, 1) }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(presets) { preset in
                ImageTile(image: previews.previews[PresetPreviewModel.previewID(preset)]?.cgImage,
                          title: preset.name,
                          placeholderAspect: aspect,
                          // Outlined when the photo already has the preset's settings.
                          isSelected: current.map { preset.applied(onto: $0) == $0 } ?? false,
                          help: "\(preset.name)\n\(PresetText.groups(preset))",
                          onHover: { previews.hover(preset, isInside: $0) }) {
                    model.applyAdjustmentPreset(preset)
                }
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
