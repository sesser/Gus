import AppKit
import PhotoCore
import SwiftUI

/// The import window: pick a source, choose photos, set where and how they are
/// copied, and import (section 8 of docs/UI_REDESIGN.md). The library app and
/// the standalone importer both show it, unchanged.
public struct ImportWindow: View {
    @Bindable var model: CardImportModel
    @State private var closeGuard: WindowCloseGuard?

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
            .background {
                ImportMenuPublisher(model: model)
                WindowReader { window in
                    model.window = window
                    // In the standalone importer closing the window quits, so
                    // it asks first while a copy runs.
                    if model.copiesOnly, let window, closeGuard == nil {
                        closeGuard = WindowCloseGuard(window) { [model] _ in
                            guard !QuitGuard.allowsQuit, model.isImporting else { return true }
                            Task { if await model.confirmQuit(.closeImportWindow) { NSApp.terminate(nil) } }
                            return false
                        }
                    }
                }
            }
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
            // A server import's failure (design §6.2, §6.3): title, message, OK.
            .alert(model.serverAlert?.title ?? "", isPresented: Binding(get: { model.serverAlert != nil },
                                                                        set: { if !$0 { model.serverAlert = nil } }),
                   presenting: model.serverAlert) { _ in
                // The default button (design §15, DQ-5): Return and Esc dismiss.
                Button("OK") { model.serverAlert = nil }
            } message: { alert in
                Text(alert.message)
            }
            .sheet(item: $model.serverSheet, onDismiss: { model.serverSheetDidDismiss() }) { sheet in
                ServerSheet(sheet: sheet)
            }
            // Remove Server… (design §3.7): Remove is destructive and no button
            // is the default, so Return does nothing.
            .confirmationDialog(String(localized: "Remove the server “\(model.removingServer?.name ?? "")”?",
                                       comment: "Alert before removing a server"),
                                isPresented: Binding(get: { model.removingServer != nil },
                                                     set: { if !$0 { model.removingServer = nil } }),
                                titleVisibility: .visible, presenting: model.removingServer) { service in
                Button("Remove", role: .destructive) { model.removeServer(service) }
                Button("Cancel", role: .cancel) { model.removingServer = nil }
            } message: { _ in
                Text("The API key is deleted from the Keychain. Photos you already imported stay in the library. The key itself still works on the server until you delete it in Immich.")
            }
    }

    private var deletionTitle: String {
        String(localized: "Delete \(model.pendingDeletion?.count ?? 0) files from \(model.source?.name ?? "")?")
    }

    /// "6 of 412 selected · Sony ILCE-7M3, shutter count 4,374"; after an
    /// import, "Imported 412 files". A server: design §4.6.
    private var subtitle: String {
        if let browse = model.browse { return serverSubtitle(browse) }
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

    private func serverSubtitle(_ browse: ServerBrowse) -> String {
        let suffix = browse.isUnencrypted ? ServerText.notEncryptedSuffix : ""
        if let done = model.doneText, !model.isImporting { return done + suffix }
        guard !model.shots.isEmpty else { return browse.isUnencrypted ? ServerText.notEncrypted : "" }
        let line = ServerSubtitle.of(selected: model.selection.count, loaded: model.shots.count,
                                     marked: model.duplicateCount, hasMorePages: browse.hasMorePages, total: browse.total)
        return ServerText.subtitle(line) + suffix
    }
}

/// Fixed (not customizable), in three groups: the source, the activity, and
/// the selection, options and Import.
private struct ImportToolbar: ToolbarContent {
    @Bindable var model: CardImportModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            SourceMenu(model: model)
            if let browse = model.browse {
                AlbumMenu(model: model, browse: browse)
                DateRangeButton(model: model, browse: browse)
            }
            Button {
                model.rescanSource()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .help("Rescan")
            .disabled(!model.hasSource || model.isImporting)
        }
        ToolbarItem(placement: .status) {
            ImportActivity(model: model)
        }
        ToolbarItem {
            Menu {
                Button("Select All") { model.selectAll() }
                    .disabled(!model.canSelectAll)
                Button("Deselect All") { model.selectNone() }
                    .disabled(!model.canDeselectAll)
                // Not for a server: videos are never listed and marked photos
                // stay visible (design §4.5, D8).
                if model.browse == nil {
                    Divider()
                    Toggle("Show Videos", isOn: $model.includesVideos)
                        .disabled(model.isImporting)
                    if !model.copiesOnly {
                        Toggle("Show Photos Already in Library", isOn: $model.showsDuplicates)
                    }
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
                    .disabled(model.selectedShots.isEmpty || !model.hasSource || (model.browse != nil && model.browse?.client == nil))
            }
        }
    }
}

/// What the Source pop-up can choose: a card or folder, or a saved server.
private enum SourceChoice: Hashable {
    case files(ImportSource)
    case server(Int64)
}

/// Mounted cards, chosen folders, saved servers (library app), a divider,
/// Choose Folder… and Add Server…, then Edit and Remove for the current
/// server (design §2.2).
private struct SourceMenu: View {
    let model: CardImportModel

    private var selection: Binding<SourceChoice?> {
        Binding(get: {
            if let id = model.browse?.service.id { return .server(id) }
            return model.source.map(SourceChoice.files)
        }, set: { choice in
            switch choice {
            case .files(let source)?: model.choose(source)
            case .server(let id)?: if let service = model.servers.first(where: { $0.id == id }) { model.chooseServer(service) }
            case nil: break
            }
        })
    }

    var body: some View {
        Menu {
            Picker(selection: selection) {
                ForEach(model.sources) { source in
                    Label(source.name, systemImage: source.isCard ? "sdcard" : "folder").tag(SourceChoice?.some(.files(source)))
                }
                if !model.copiesOnly {
                    ForEach(model.servers) { service in
                        Label(service.name, systemImage: "server.rack")
                            .accessibilityLabel(Text(String(localized: "\(service.name), server",
                                                            comment: "VoiceOver: a server in the Source pop-up")))
                            .tag(SourceChoice?.some(.server(service.id ?? 0)))
                    }
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button("Choose Folder…") { model.chooseFolder() }
            if !model.copiesOnly {
                Button("Add Server…") { model.showAddServer() }
                if let service = model.browse?.service {
                    Divider()
                    Button(String(localized: "Edit “\(service.name)”…")) { model.showEditServer() }
                    Button(String(localized: "Remove “\(service.name)”…", comment: "Source pop-up: remove the current server")) {
                        model.askToRemoveServer()
                    }
                }
            }
        } label: {
            if let service = model.browse?.service {
                Label(service.name, systemImage: "server.rack")
                    .labelStyle(.titleAndIcon)
            } else if let source = model.source {
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
/// 160 pt bar and "File 12 of 412 · 1.2 of 18 GB" with the current file as
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
        } else if let browse = model.browse, let status = serverStatus(browse) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(status)
                    .foregroundStyle(.secondary)
                    .toolbarStatusText()
            }
            .toolbarCapsuleInset()
        }
    }

    /// "Connecting to ‹name›…", "Loading photos…", "Loading more photos…"
    /// (design §4.4).
    private func serverStatus(_ browse: ServerBrowse) -> String? {
        if browse.isConnecting {
            return ToolbarMetrics.statusLine(name: browse.service.name) { ServerText.connecting($0) }
        }
        guard browse.isLoadingPage else { return nil }
        return browse.loadedFirstPage ? String(localized: "Loading more photos…", comment: "Import window: a server's next page")
                                      : String(localized: "Loading photos…", comment: "Import window: a server's first page")
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
        if let browse = model.browse {
            ServerGridArea(model: model, browse: browse)
        } else {
            fileContent
        }
    }

    @ViewBuilder private var fileContent: some View {
        let name = model.source?.name ?? ""
        switch ImportGridState.of(hasSource: model.source != nil, isScanning: model.isScanning, readError: model.readError,
                                  shotCount: model.shots.count, duplicateCount: model.duplicateCount,
                                  showsDuplicates: model.showsDuplicates) {
        case .noSource where model.copiesOnly:
            ContentUnavailableView {
                Label("Insert a Card or Choose a Folder", systemImage: "sdcard")
            } actions: {
                Button("Choose Folder…") { model.chooseFolder() }
            }
        case .noSource:
            // The library app also offers servers (design §2.4).
            ContentUnavailableView {
                Label(model.servers.isEmpty ? String(localized: "Insert a Card, Choose a Folder or Add a Server")
                                            : String(localized: "Insert a Card, Choose a Folder or Open a Server"),
                      systemImage: "sdcard")
            } actions: {
                Button("Choose Folder…") { model.chooseFolder() }
                if model.servers.isEmpty {
                    Button("Add Server…") { model.showAddServer() }
                } else {
                    Menu("Open Server") {
                        ForEach(model.servers) { service in
                            Button(service.name) { model.chooseServer(service) }
                        }
                        Divider()
                        Button("Add Server…") { model.showAddServer() }
                    }
                    .fixedSize()
                }
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
            if let browse = model.browse {
                ServerSection(model: model, browse: browse)
            }
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
                        if let browse = model.browse {
                            // Plain text for a server (design §5.3), stacked and
                            // leading-aligned like the template fields (§15 DQ-14),
                            // with the reuse note under it (DQ-13).
                            let addsToExisting = model.addsToExistingProject
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Project name")
                                    .accessibilityHidden(true)
                                TextField("Project name", text: Binding(get: { browse.projectName },
                                                                        set: { model.setServerProjectName($0) }))
                                    .textFieldStyle(.roundedBorder)
                                    .labelsHidden()
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityHint(Text(addsToExisting ? ServerText.addsToExistingProject : ""))
                                if addsToExisting {
                                    Caption(text: ServerText.addsToExistingProject)
                                        .accessibilityHidden(true)
                                }
                            }
                        } else {
                            TemplateField(title: String(localized: "Project name"), text: $model.projectNameTemplate,
                                          tokens: .importFiles, sample: model.exampleContext)
                        }
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
                if model.browse != nil {
                    Caption(text: String(localized: "Description and star rating from Immich are added to a new photo when it has none here."))
                }
            }
            // Nothing on a server is ever deleted or ejected (design §5.1).
            if model.browse == nil {
                afterImport
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingPreset) { preset in
            PresetEditor(preset: preset, onSave: model.savePreset, onDelete: { model.deletePreset($0) })
        }
    }

    @ViewBuilder private var afterImport: some View {
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
    /// Delete Preset… asks first (design.md I11).
    @State private var confirmsDeletion = false
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

    private func field(_ field: DescriptiveField) -> some View {
        TextField(FieldLabelText.text(field), text: binding(field),
                  prompt: field == .rights ? Text("© {capture:yyyy} Your Name") : nil)
    }

    private func binding(_ field: DescriptiveField) -> Binding<String> {
        switch field {
        case .creator: text(\.creator)
        case .rights: text(\.rights)
        case .usageTerms: text(\.usageTerms)
        case .caption: text(\.caption)
        case .title: text(\.title)
        case .altText: text(\.altText)
        case .extendedDescription: text(\.extendedDescription)
        case .jobTitle: text(\.jobTitle)
        case .email: contact(\.email)
        case .phone: contact(\.phone)
        case .url: contact(\.url)
        case .address: contact(\.address)
        case .city: contact(\.city)
        case .region: contact(\.region)
        case .postalCode: contact(\.postalCode)
        case .country: contact(\.country)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Preset name", text: $preset.name)
                // The shared field labels (design.md I9), in the editor's order.
                // The Info tab's heading for these fields (design.md I8).
                Section("Metadata") {
                    ForEach(MetadataPreset.editorFields.metadata, id: \.self, content: field)
                }
                Section("Contact") {
                    ForEach(MetadataPreset.editorFields.contact, id: \.self, content: field)
                }
                Text("Text can use the same tokens as templates, such as {capture:yyyy}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                if preset.id != nil {
                    Button("Delete Preset…", role: .destructive) { confirmsDeletion = true }
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
        .alert(String(localized: "Delete the preset “\(preset.name)”?",
                      comment: "Alert before deleting an adjustment or metadata preset; its name"),
               isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive) {
                if let id = preset.id { onDelete(id) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Copies already imported keep their metadata.", comment: "Delete metadata preset alert")
        }
    }
}

/// The inspector's first section for a server (design §5): where photos come
/// from and how the connection is protected.
private struct ServerSection: View {
    let model: CardImportModel
    let browse: ServerBrowse

    var body: some View {
        Section("Server") {
            LabeledContent("Name") {
                Text(browse.service.name)
                    .lineLimit(2)
                    .help(browse.service.name)
            }
            LabeledContent("Address") {
                Text(browse.service.address)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(browse.service.address)
            }
            if let info = browse.info {
                LabeledContent("Version") {
                    Text(String(localized: "Immich \(info.version.description)", comment: "Import options: the server's version"))
                }
            }
            LabeledContent("Connection") {
                if browse.isUnencrypted {
                    Label(String(localized: "Not encrypted (http)"), systemImage: "exclamationmark.triangle")
                } else if browse.service.certificateFingerprint != nil {
                    Text("Encrypted, certificate trusted by you")
                } else {
                    Text("Encrypted (https)")
                }
            }
            Caption(text: String(localized: "Photos are copied from the server. Nothing on the server is changed."))
            if browse.info?.hasMoreThanNeeded == true {
                Caption(text: String(localized: "This key can do more than importing needs. Only reading is used."))
            }
            Button("Edit Server…") { model.showEditServer() }
                .disabled(model.isImporting)
        }
    }
}

/// The grid area for a server (design §4.7).
private struct ServerGridArea: View {
    let model: CardImportModel
    let browse: ServerBrowse

    private var description: Text {
        Text("Only your own photos are listed. Videos, archived, hidden, locked and trashed photos are not.")
    }

    var body: some View {
        let name = browse.service.name
        switch browse.gridState {
        case .connecting:
            ProgressView(ServerText.connecting(name))
        case .loading:
            ProgressView("Reading \(name)…")
        case .cantConnect(let result):
            let text = ServerText.result(result, host: browse.address?.host ?? "", name: name)
            ContentUnavailableView {
                Label(ServerText.cantConnect(name), systemImage: "exclamationmark.triangle")
            } description: {
                Text([text?.title, text?.detail].compactMap { $0 }.joined(separator: "\n"))
                    .textSelection(.enabled)
            } actions: {
                Button("Try Again") { model.rescanSource() }
                if case .certificateChanged = result {
                    Button("Review Certificate…") { model.showEditServer(reviewingCertificate: true) }
                } else {
                    Button("Edit Server…") { model.showEditServer() }
                }
            }
        case .noPhotosAll:
            ContentUnavailableView {
                Label("No Photos on \(name)", systemImage: "photo.on.rectangle")
            } description: {
                description
            }
        case .noPhotosInAlbum:
            ContentUnavailableView {
                Label("No Photos in “\(browse.scopeName)”", systemImage: "photo.on.rectangle")
            } description: {
                description
            } actions: {
                Button("Show All Photos") { model.chooseAlbum(nil) }
            }
        case .noPhotosInRange:
            ContentUnavailableView {
                Label("No Photos in This Date Range", systemImage: "calendar")
            } description: {
                description
            } actions: {
                Button("Clear Date Range") { model.setDateRange(nil) }
            }
        case .albumGone:
            ContentUnavailableView {
                Label(String(localized: "“\(browse.scopeName)” Is No Longer on the Server",
                             comment: "Import window: the chosen album was deleted on the server"),
                      systemImage: "photo.on.rectangle")
            } actions: {
                Button("Show All Photos") { model.chooseAlbum(nil) }
            }
        case .photos:
            ImportGridView(model: model, shots: model.visibleShots, selection: model.selection)
        }
    }
}

/// The Album pop-up (design §4.2, DQ-4): All Photos, then the account's
/// albums by name with the server's count.
private struct AlbumMenu: View {
    let model: CardImportModel
    let browse: ServerBrowse

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { browse.albumID }, set: { model.chooseAlbum($0) })) {
                Text(ServerText.allPhotos).tag(String?.none)
                if !browse.albums.isEmpty { Divider() }
                ForEach(browse.albums) { album in
                    Text(ServerText.album(album)).tag(String?.some(album.id))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if browse.albumsFailed {
                Button("Albums unavailable") {}
                    .disabled(true)
            }
        } label: {
            // Truncated in the middle, at most 180 pt (design §4.1, S6).
            Label {
                Text(browse.albumsLoaded ? browse.scopeName : ServerText.allPhotos)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: ServerToolbarMetrics.titleWidth)
            } icon: {
                Image(systemName: "photo.on.rectangle")
            }
            .labelStyle(.titleAndIcon)
        }
        .help("Album")
        .accessibilityLabel(Text("Album"))
        .accessibilityValue(Text(browse.scopeName))
        .disabled(!browse.albumsLoaded || model.isImporting || browse.client == nil)
    }
}

/// Date Range (design §4.3): a popover with two optional days.
private struct DateRangeButton: View {
    let model: CardImportModel
    @Bindable var browse: ServerBrowse

    var body: some View {
        Button {
            browse.showsDateRange = true
        } label: {
            if let range = browse.dates, !range.isEmpty {
                Label {
                    Text(ServerText.dateRangeText(range))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: ServerToolbarMetrics.titleWidth)
                } icon: {
                    Image(systemName: "calendar")
                }
                .labelStyle(.titleAndIcon)
            } else {
                Label("Date Range", systemImage: "calendar")
            }
        }
        .help("Show only photos taken within a date range")
        .accessibilityLabel(Text("Date Range"))
        .accessibilityValue(Text(ServerText.dateRangeText(browse.dates)))
        .disabled(model.isImporting || browse.client == nil)
        .popover(isPresented: $browse.showsDateRange, arrowEdge: .bottom) {
            DateRangePopover(model: model, initial: browse.dates) { browse.showsDateRange = false }
        }
    }
}

private struct DateRangePopover: View {
    let model: CardImportModel
    let close: () -> Void
    @State private var usesFrom: Bool
    @State private var usesTo: Bool
    @State private var from: Date
    @State private var to: Date

    init(model: CardImportModel, initial: CaptureDateRange?, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        let today = Self.utcDay(Date())
        _usesFrom = State(initialValue: initial?.from != nil)
        _usesTo = State(initialValue: initial?.through != nil)
        _from = State(initialValue: CaptureDateRange.utc(initial?.from) ?? today)
        _to = State(initialValue: CaptureDateRange.utc(initial?.through) ?? today)
    }

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// The local calendar day of `date`, as midnight UTC (the photo's own
    /// day, as the grid shows it).
    static func utcDay(_ date: Date) -> Date {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return CaptureDateRange.utc(parts) ?? date
    }

    private var range: CaptureDateRange {
        let calendar = Self.utcCalendar
        return CaptureDateRange(from: usesFrom ? calendar.dateComponents([.year, .month, .day], from: from) : nil,
                                through: usesTo ? calendar.dateComponents([.year, .month, .day], from: to) : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capture date").font(.system(size: 13, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Toggle("From", isOn: $usesFrom).toggleStyle(.checkbox)
                    DatePicker("From date", selection: $from, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                        .disabled(!usesFrom)
                }
                GridRow {
                    Toggle("To", isOn: $usesTo).toggleStyle(.checkbox)
                    DatePicker("To date", selection: $to, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                        .disabled(!usesTo)
                }
            }
            if range.isReversed {
                Label("The start date is after the end date.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
            }
            HStack {
                Spacer()
                Button("Clear") {
                    model.setDateRange(nil)
                    close()
                }
                Button("Apply") {
                    model.setDateRange(range)
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(range.isReversed)
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}

/// The server toolbar items' title width (design §4.1, design review S6).
enum ServerToolbarMetrics {
    static let titleWidth: CGFloat = 180
}
