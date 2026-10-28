import AppKit
import PhotoCore
import SwiftUI

/// Lists presets by collection: rename, move, choose what they apply, export
/// and remove them; import more.
struct PresetManagerWindow: View {
    let model: LibraryModel
    @State private var pendingRemoval: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.adjustmentPresets.isEmpty {
                ContentUnavailableView("No Presets", systemImage: "slider.horizontal.3",
                                       description: Text("Save a photo's adjustments as a preset, or import presets (.\(PresetFile.fileExtension), .lrtemplate, .xmp or .dng)."))
            } else {
                List {
                    ForEach(model.adjustmentPresetCollections) { collection in
                        Section {
                            ForEach(collection.presets) { preset in
                                PresetRow(model: model, preset: preset)
                            }
                        } header: {
                            PresetCollectionHeader(model: model, collection: collection) {
                                pendingRemoval = collection.name
                            }
                        }
                    }
                }
            }
            HStack {
                Text("Applying a preset replaces only the settings it includes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import…") { model.chooseAdjustmentPresetImport() }
                Button("Export All…") {
                    model.exportAdjustmentPresets(model.adjustmentPresets, suggestedName: String(localized: "Presets"))
                }
                .disabled(model.adjustmentPresets.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 360)
        .preferredColorScheme(.dark)
        .alert(String(localized: "Remove the collection \(pendingRemoval ?? "")?"),
               isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval { model.deleteAdjustmentPresetCollection(pendingRemoval) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its presets are removed. Photos keep the adjustments they were given.")
        }
    }
}

/// A collection's name (editable), with Export and Remove.
private struct PresetCollectionHeader: View {
    let model: LibraryModel
    let collection: AdjustmentPresetCollection
    let remove: () -> Void
    @State private var name = ""

    var body: some View {
        HStack {
            if collection.name.isEmpty {
                Text("No Collection")
                    .font(.headline)
            } else {
                TextField("Collection name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .onSubmit { model.renameAdjustmentPresetCollection(collection.name, to: name) }
            }
            Spacer()
            Button {
                model.exportAdjustmentPresets(collection.presets, suggestedName: collection.name.isEmpty
                                              ? String(localized: "Presets") : collection.name)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help("Export this collection as one preset file")
            if !collection.name.isEmpty {
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this collection and its presets")
            }
        }
        .onAppear { name = collection.name }
        .onChange(of: collection.name) { name = collection.name }
    }
}

/// A preset's name (editable) and what it applies, with a menu of changes.
private struct PresetRow: View {
    let model: LibraryModel
    let preset: AdjustmentPreset
    @State private var name = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Preset name", text: $name)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        var renamed = preset
                        renamed.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.updateAdjustmentPreset(renamed)
                    }
                Text(PresetText.groups(preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Menu {
                Menu("Include") {
                    ForEach(Adjustments.Group.allCases, id: \.self) { group in
                        Toggle(AdjustText.title(group), isOn: Binding(
                            get: { preset.groups.contains(group) },
                            set: { isOn in
                                var changed = preset
                                if isOn { changed.groups.insert(group) } else { changed.groups.remove(group) }
                                model.updateAdjustmentPreset(changed)
                            }))
                    }
                }
                Menu("Move To") {
                    Button("No Collection") { move(to: "") }
                        .disabled(preset.collection.isEmpty)
                    ForEach(model.adjustmentPresetCollectionNames, id: \.self) { collection in
                        Button(collection) { move(to: collection) }
                            .disabled(collection == preset.collection)
                    }
                    Divider()
                    Button("New Collection…") {
                        if let collection = Self.askForCollectionName() { move(to: collection) }
                    }
                }
                Divider()
                Button("Export…") { model.exportAdjustmentPresets([preset], suggestedName: preset.name) }
                Button("Delete", role: .destructive) { model.deleteAdjustmentPreset(preset) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change, export or delete this preset")
        }
        .onAppear { name = preset.name }
        .onChange(of: preset.name) { name = preset.name }
    }

    private func move(to collection: String) {
        var moved = preset
        moved.collection = collection
        model.updateAdjustmentPreset(moved)
    }

    @MainActor
    static func askForCollectionName() -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "New Collection")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = String(localized: "Collection name")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Move"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
