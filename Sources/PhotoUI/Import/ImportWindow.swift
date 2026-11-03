import AppKit
import PhotoCore
import SwiftUI

/// The import window: pick a source, choose photos, set where and how they are
/// copied, and import (section 8 of docs/UI_REDESIGN.md). The library app and
/// the standalone importer both show it, unchanged.
public struct ImportWindow: View {
    @Bindable var model: CardImportModel

    public init(model: CardImportModel) {
        self.model = model
    }

    public var body: some View {
        ImportGridArea(model: model)
            .frame(minWidth: 520, minHeight: 480)
            .inspector(isPresented: $model.showsOptions) {
                ImportOptionsForm(model: model)
                    .inspectorColumnWidth(min: 300, ideal: 320, max: 400)
            }
            .toolbar { ImportToolbar(model: model) }
            .navigationTitle(model.copiesOnly ? AppBranding.importerDisplayName
                                              : String(localized: "Import", comment: "Import window title"))
            .navigationSubtitle(subtitle)
            .background { ImportMenuPublisher(model: model) }
            .onAppear { model.refreshSources() }
            .alert(deletionTitle, isPresented: Binding(get: { model.pendingDeletion != nil },
                                                       set: { if !$0 { model.confirmDeletion(false) } })) {
                Button("Delete", role: .destructive) { model.confirmDeletion(true) }
                Button("Keep Them", role: .cancel) { model.confirmDeletion(false) }
            } message: {
                if model.copiesOnly {
                    Text("Every one of them was copied and checked.")
                } else {
                    Text("Every one of them was copied and checked. Photos that were already in the library are not deleted.")
                }
            }
            .alert(model.alertText ?? "", isPresented: Binding(get: { model.alertText != nil },
                                                               set: { if !$0 { model.alertText = nil } })) {
                Button("OK", role: .cancel) { model.alertText = nil }
            }
    }

    private var deletionTitle: String {
        String(localized: "Delete \(model.pendingDeletion?.count ?? 0) files from \(model.source?.name ?? "")?")
    }

    /// "6 of 412 selected · Sony ILCE-7M3, shutter count 4,374"; after an
    /// import, "Imported 412 files".
    private var subtitle: String {
        if let done = model.doneText, !model.isImporting { return done }
        guard !model.shots.isEmpty else { return "" }
        let selected = String(localized: "\(model.selection.count) of \(model.shots.count - model.duplicateCount) selected")
        guard let camera = model.camera else { return selected }
        let cameraText = camera.shutterCount.map {
            String(localized: "\(camera.name), shutter count \($0.formatted(.number))",
                   comment: "Import window subtitle: the newest photo's camera and its shutter count")
        } ?? camera.name
        return "\(selected) · \(cameraText)"
    }
}

/// Fixed (not customizable), in three groups: the source, the activity, and
/// the selection, options and Import.
private struct ImportToolbar: ToolbarContent {
    @Bindable var model: CardImportModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            SourceMenu(model: model)
            Button {
                model.rescan(keepingPicks: true)
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .help("Rescan")
            .disabled(model.source == nil || model.isImporting)
        }
        ToolbarItem(placement: .status) {
            ImportActivity(model: model)
        }
        ToolbarItem {
            Menu {
                Button("Select All") { model.selectAll() }
                    .disabled(!model.shots.contains { !$0.isDuplicate })
                Button("Deselect All") { model.selectNone() }
                    .disabled(model.selection.isEmpty)
                Divider()
                Toggle("Show Videos", isOn: $model.includesVideos)
                    .disabled(model.isImporting)
                if !model.copiesOnly {
                    Toggle("Show Photos Already in Library", isOn: $model.showsDuplicates)
                }
            } label: {
                Label("Selection", systemImage: "checklist")
            }
            .help("Selection")
        }
        ToolbarItem {
            Button {
                model.showsOptions.toggle()
            } label: {
                Label(model.showsOptions ? "Hide Options" : "Show Options", systemImage: "sidebar.trailing")
            }
            .help(model.showsOptions ? "Hide Options" : "Show Options")
        }
        ToolbarItem(placement: .primaryAction) {
            if model.isImporting {
                Button("Stop") { model.cancelImport() }
            } else {
                Button("Import \(model.selectedShots.count) Photos") { model.startImport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedShots.isEmpty || model.source == nil)
            }
        }
    }
}

/// Mounted cards, chosen folders, a divider, Choose Folder….
private struct SourceMenu: View {
    let model: CardImportModel

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { model.source }, set: { if let source = $0 { model.choose(source) } })) {
                ForEach(model.sources) { source in
                    Label(source.name, systemImage: source.isCard ? "sdcard" : "folder").tag(ImportSource?.some(source))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button("Choose Folder…") { model.chooseFolder() }
        } label: {
            if let source = model.source {
                Label(source.name, systemImage: source.isCard ? "sdcard" : "folder")
                    .labelStyle(.titleAndIcon)
            } else {
                Label("No Card Connected", systemImage: "sdcard")
                    .labelStyle(.titleAndIcon)
            }
        }
        .help("Source")
        .disabled(model.isImporting)
    }
}

/// While scanning, a spinner and "Reading ‹source›…"; while copying, a
/// 160 pt bar and "12 of 412 files · 1.2 of 18 GB" with the current file as
/// its tooltip.
private struct ImportActivity: View {
    let model: CardImportModel

    var body: some View {
        if let progress = model.progress {
            HStack(spacing: 8) {
                ProgressView(value: Double(progress.bytesDone), total: Double(max(progress.bytesTotal, 1)))
                    .frame(width: 160)
                Text(model.progressDetail ?? "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .toolbarStatusText()
            }
            .toolbarCapsuleInset()
            .help(progress.currentName)
        } else if model.isScanning, let source = model.source {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(ToolbarMetrics.statusLine(name: source.name) {
                    String(localized: "Reading \($0)…", comment: "Import window: scanning a card or folder")
                })
                .foregroundStyle(.secondary)
                .toolbarStatusText()
            }
            .toolbarCapsuleInset()
        }
    }
}

/// The grid, or what stands in for it (the states table).
private struct ImportGridArea: View {
    @Bindable var model: CardImportModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: Palette.gridBackground))
    }

    @ViewBuilder private var content: some View {
        let name = model.source?.name ?? ""
        switch ImportGridState.of(hasSource: model.source != nil, isScanning: model.isScanning, readError: model.readError,
                                  shotCount: model.shots.count, duplicateCount: model.duplicateCount,
                                  showsDuplicates: model.showsDuplicates) {
        case .noSource:
            ContentUnavailableView {
                Label("Insert a Card or Choose a Folder", systemImage: "sdcard")
            } actions: {
                Button("Choose Folder…") { model.chooseFolder() }
            }
        case .scanning:
            ProgressView("Reading \(name)…")
            case .readError(let error):
            ContentUnavailableView {
                Label("Can't Read \(name)", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Rescan") { model.rescan(keepingPicks: true) }
            }
        case .noPhotos:
            ContentUnavailableView {
                Label("No Photos on \(name)", systemImage: model.source?.isCard == true ? "sdcard" : "folder")
            } actions: {
                Button("Choose Folder…") { model.chooseFolder() }
            }
        case .allImported(let count):
            ContentUnavailableView {
                Label("All \(count) Photos Are Already in the Library", systemImage: "checkmark.circle")
            } actions: {
                Button("Show Them") { model.showsDuplicates = true }
            }
        case .shots:
            ImportGridView(model: model, shots: model.visibleShots, selection: model.selection)
        }
    }
}

/// The options inspector: a grouped form in the order the decisions are made.
private struct ImportOptionsForm: View {
    @Bindable var model: CardImportModel
    @State private var editingPreset: MetadataPreset?

    var body: some View {
        Form {
            Section("Destination") {
                LabeledContent("Folder") {
                    HStack {
                        Text(model.destination.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(model.destination.path)
                        Button("Choose Folder…") { model.chooseDestination() }
                    }
                }
                let sample = model.exampleContext
                TemplateField(title: String(localized: "Subfolders"), text: $model.folderTemplate,
                              tokens: .importFolders, folders: true, sample: sample)
                TemplateField(title: String(localized: "File names"), text: $model.fileTemplate,
                              tokens: .importFiles, sample: sample, example: model.example)
            }
            Section(model.copiesOnly ? String(localized: "Job") : String(localized: "Project")) {
                if let library = model.library {
                    Picker("Add to", selection: $model.existingProjectID) {
                        Text("New Project").tag(Int64?.none)
                        ForEach(library.projects) { summary in
                            Text(summary.project.name).tag(Int64?.some(summary.id))
                        }
                    }
                    if model.existingProjectID == nil {
                        TemplateField(title: String(localized: "Project name"), text: $model.projectNameTemplate,
                                      tokens: .importFiles, sample: model.exampleContext)
                    }
                }
                LabeledContent("Job code") {
                    HStack(spacing: 6) {
                        TextField("Job code", text: $model.jobCode, prompt: Text("e.g. Smith wedding"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                        if !model.recentJobCodes.isEmpty {
                            Menu {
                                ForEach(model.recentJobCodes, id: \.self) { code in
                                    Button(code) { model.jobCode = code }
                                }
                            } label: {
                                Image(systemName: "clock")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Recent job codes")
                            .accessibilityLabel(Text("Recent job codes"))
                        }
                    }
                }
            }
            Section("Metadata") {
                LabeledContent("Preset") {
                    Menu(selectedPreset?.name ?? String(localized: "None")) {
                        Button("None") { model.presetID = nil }
                        ForEach(model.presets) { preset in
                            Button(preset.name) { model.presetID = preset.id }
                        }
                        Divider()
                        Button("New Preset…") {
                            editingPreset = MetadataPreset(name: String(localized: "Untitled Preset"),
                                                           values: SidecarValues(rights: "© {capture:yyyy} "))
                        }
                        if let preset = selectedPreset {
                            Button("Edit “\(preset.name)”…") { editingPreset = preset }
                        }
                    }
                    .fixedSize()
                }
                if model.presetID != nil {
                    Caption(text: String(localized: "Written to sidecar files next to the copies; the copies stay identical to the originals."))
                }
            }
            Section("After Import") {
                Toggle(isOn: $model.deletesOriginals) {
                    Text("Delete originals from “\(sourceName)”", comment: "Import option check box")
                }
                .toggleStyle(.checkbox)
                Toggle(isOn: $model.ejectsWhenDone) {
                    Text("Eject “\(sourceName)”", comment: "Import option check box")
                }
                .toggleStyle(.checkbox)
                .disabled(model.source?.isEjectable != true)
                Caption(text: String(localized: "Originals are deleted only after every copy is verified, and you're asked first."))
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingPreset) { preset in
            PresetEditor(preset: preset, onSave: model.savePreset, onDelete: { model.deletePreset($0) })
        }
    }

    private var selectedPreset: MetadataPreset? {
        model.presets.first { $0.id == model.presetID }
    }

    private var sourceName: String {
        model.source?.name ?? String(localized: "the source", comment: "Import options, when no source is chosen")
    }
}

/// 11 pt secondary text under the row it explains.
private struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Name and fields of a metadata preset.
private struct PresetEditor: View {
    @State var preset: MetadataPreset
    let onSave: (MetadataPreset) -> Void
    let onDelete: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss

    private func text(_ path: WritableKeyPath<SidecarValues, String?>) -> Binding<String> {
        Binding(get: { preset.values[keyPath: path] ?? "" },
                set: { preset.values[keyPath: path] = $0.isEmpty ? nil : $0 })
    }

    private func contact(_ path: WritableKeyPath<CreatorContact, String?>) -> Binding<String> {
        Binding(get: { preset.values.contact?[keyPath: path] ?? "" },
                set: { value in
                    var contact = preset.values.contact ?? CreatorContact()
                    contact[keyPath: path] = value.isEmpty ? nil : value
                    preset.values.contact = contact.isEmpty ? nil : contact
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Preset name", text: $preset.name)
                Section("Description") {
                    TextField("Creator", text: text(\.creator))
                    TextField("Copyright", text: text(\.rights), prompt: Text("© {capture:yyyy} Your Name"))
                    TextField("Usage terms", text: text(\.usageTerms))
                    TextField("Caption", text: text(\.caption))
                }
                Section("Contact") {
                    TextField("Email", text: contact(\.email))
                    TextField("Phone", text: contact(\.phone))
                    TextField("Website", text: contact(\.url))
                    TextField("Address", text: contact(\.address))
                    TextField("City", text: contact(\.city))
                    TextField("Region", text: contact(\.region))
                    TextField("Postal code", text: contact(\.postalCode))
                    TextField("Country", text: contact(\.country))
                }
                Text("Text can use the same tokens as templates, such as {capture:yyyy}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                if let id = preset.id {
                    Button("Delete Preset", role: .destructive) {
                        onDelete(id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(preset)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preset.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 460, height: 560)
    }
}
