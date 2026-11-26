import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// File ▸ Publish… (issue #28, design §3): a sheet on the library window built
/// like Export, with two pages of its own (File Settings, the folder map).
/// The run starts after the sheet closes, with progress in Activity.
struct PublishSheet: View {
    let model: LibraryModel

    private var publish: PublishModel { model.publish }

    var body: some View {
        @Bindable var publish = publish
        Group {
            switch publish.page {
            case .main: PublishMainPage(model: model)
            case .settings: PublishSettingsPage(model: model)
            case .folderMap: PublishFolderMapPage(model: model)
            }
        }
        .frame(width: 560)
        .frame(minHeight: 480, idealHeight: 640)
        .presentationSizing(.fitted)
        // Skip or New Copy (design §8): Skip is the default; Cancel returns to the sheet.
        .alert(PublishText.questionTitle(publish.question?.published ?? 0, server: publish.service?.name ?? ""),
               isPresented: Binding(get: { publish.question != nil }, set: { if !$0 { publish.question = nil } }),
               presenting: publish.question) { _ in
            Button(PublishText.skip) { publish.answer(skip: true) }
                .keyboardShortcut(.defaultAction)
            Button(PublishText.newCopy) { publish.answer(skip: false) }
            Button("Cancel", role: .cancel) { publish.question = nil }
        } message: { question in
            Text(PublishText.questionMessage(published: question.published, total: question.total))
        }
    }
}

// MARK: - The main page (design §3.1 to §3.8)

private struct PublishMainPage: View {
    let model: LibraryModel

    private var publish: PublishModel { model.publish }

    var body: some View {
        VStack(spacing: 0) {
            PublishHeader(model: model)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Divider()
            if publish.servers.isEmpty {
                ContentUnavailableView {
                    Label(PublishText.noServerTitle, systemImage: "server.rack")
                } description: {
                    Text(PublishText.noServerDetail)
                } actions: {
                    Button("Add Server…") { publish.showServerSheet(editing: false) }
                }
                .frame(maxHeight: .infinity)
            } else {
                PublishForm(model: model)
            }
            Divider()
            buttons
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if publish.isConfirming {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let issue = publish.startIssue {
                IssueText(text: issue)
            }
            Spacer()
            Button("Cancel", role: .cancel) { model.showsPublishSheet = false }
                .keyboardShortcut(.cancelAction)
            Button(PublishText.title(publish.versionIDs.count)) {
                Task {
                    if await publish.requestPublish() { model.showsPublishSheet = false }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!publish.canPublish)
        }
    }
}

/// The first photo, how many are published, from where, and what is known
/// before anything runs (design §3.2).
private struct PublishHeader: View {
    let model: LibraryModel

    var body: some View {
        let publish = model.publish
        HStack(spacing: 12) {
            Group {
                if let image = publish.editor.previewImage {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Color(nsColor: Palette.cell)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(PublishText.title(publish.versionIDs.count))
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if publish.offlinePhotos > 0 { InfoLine(text: PublishText.offlineLine(publish.offlinePhotos)) }
                if publish.hdrPhotos > 0 { InfoLine(text: PublishText.hdrLine(publish.hdrPhotos)) }
            }
            Spacer()
        }
    }

    private var subtitle: String {
        let source = String(localized: "From \(model.publish.sourceName)", comment: "Export and Merge to HDR sheets: the sidebar source")
        let skipped = model.publish.skippedVideos
        guard skipped > 0 else { return source }
        return [source, String(localized: "\(skipped) videos are skipped", comment: "Export sheet: videos are not exported")]
            .joined(separator: " · ")
    }
}

/// An `info.circle` line, 11 pt secondary.
private struct InfoLine: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

private struct PublishForm: View {
    let model: LibraryModel

    private var publish: PublishModel { model.publish }

    var body: some View {
        @Bindable var publish = publish
        Form {
            serverSection
            albumSection
            stackingSection
            filesSection
        }
        .formStyle(.grouped)
    }

    // MARK: Server (design §3.3)

    private var serverSection: some View {
        Section("Server") {
            LabeledContent("Server") {
                Menu(publish.service?.name ?? String(localized: "None")) {
                    Picker("Server", selection: Binding(get: { publish.serviceID },
                                                        set: { id in
                                                            guard let service = publish.servers.first(where: { $0.id == id }) else { return }
                                                            Task { await publish.choose(service) }
                                                        })) {
                        ForEach(publish.servers) { service in
                            Text(service.name).tag(service.id as Int64?)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Divider()
                    Button("Add Server…") { publish.showServerSheet(editing: false) }
                    if let service = publish.service {
                        Button(String(localized: "Edit “\(service.name)”…", comment: "Publish sheet: server menu")) {
                            publish.showServerSheet(editing: true)
                        }
                    }
                }
                .fixedSize()
                .accessibilityHint(Text(serverHint))
            }
            if let service = publish.service {
                Caption(text: service.address)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(service.address)
                if service.serverAddress?.scheme == .http {
                    IssueText(text: PublishText.notEncrypted)
                }
            }
            checkState
            if !publish.missing.server.isEmpty {
                IssueText(text: PublishText.cantPublish(publish.missing.server))
            }
            if !publish.missing.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Caption(text: PublishText.fixPermissions)
                    HStack {
                        Button("Check Again") { publish.runCheck() }
                        Button("Edit Server…") { publish.showServerSheet(editing: true) }
                    }
                }
            }
        }
    }

    private var serverHint: String {
        publish.missing.server.isEmpty ? "" : PublishText.cantPublish(publish.missing.server)
    }

    @ViewBuilder private var checkState: some View {
        switch publish.check {
        case .idle, .passed:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Caption(text: PublishText.checking(publish.service?.name ?? ""))
            }
        case .failed(let result):
            let text = ServerText.result(result, host: publish.service?.serverAddress?.host ?? "",
                                         name: publish.service?.name ?? "", purpose: .publishing)
            VStack(alignment: .leading, spacing: 6) {
                if case .keychain(let message) = result {
                    Label(PublishText.keyUnreadable, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                    Caption(text: ServerText.keychainDetail(message))
                } else if let text {
                    Label(text.title, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(text.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Try Again") { publish.runCheck() }
                    switch result {
                    case .certificateChanged, .untrustedCertificate:
                        Button("Review Certificate…") { publish.showServerSheet(editing: true, reviewingCertificate: true) }
                    default:
                        Button("Edit Server…") { publish.showServerSheet(editing: true) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: Album (design §3.4)

    private var albumSection: some View {
        Section("Album") {
            LabeledContent("Album") {
                albumMenu
            }
            if publish.isNewAlbum {
                TextField("Name", text: Bindable(publish).newAlbumName)
                if let existing = publish.newAlbumNameTaken {
                    VStack(alignment: .leading, spacing: 4) {
                        InfoLine(text: PublishText.albumNameTaken)
                        Button(PublishText.useExistingAlbum) { publish.album = .existing(id: existing.id, name: existing.name) }
                    }
                }
            }
            if !publish.missing.album.isEmpty {
                IssueText(text: PublishText.albumNeeds(publish.missing.album))
                    .onAppear { AccessibilityText.announce(PublishText.albumNeeds(publish.missing.album), priority: .medium) }
            } else if case .failed(let reason) = publish.albumsState {
                VStack(alignment: .leading, spacing: 4) {
                    IssueText(text: PublishText.albumsFailed(reason))
                    Button("Try Again") { publish.loadAlbums() }
                }
            } else if publish.rememberedAlbumGone {
                IssueText(text: PublishText.albumGone(publish.album.name ?? ""))
            }
            Picker("Show in", selection: Bindable(publish).visibility) {
                Text("Timeline").tag(PublishVisibility.timeline)
                Text("Archive").tag(PublishVisibility.archive)
            }
            .pickerStyle(.segmented)
            .accessibilityHint(Text(archiveCaption ?? ""))
            if let archiveCaption {
                if publish.stacking {
                    IssueText(text: archiveCaption)
                        .onAppear { AccessibilityText.announce(archiveCaption, priority: .medium) }
                } else {
                    Caption(text: archiveCaption)
                }
            }
        }
    }

    private var archiveCaption: String? {
        guard publish.visibility == .archive else { return nil }
        return publish.stacking ? PublishText.archiveStacked : PublishText.archivePlain
    }

    private var albumTitle: String {
        if !(publish.serverInfo.map { PublishPermissions.canListAlbums($0.permissions) } ?? true), publish.album == .none {
            return String(localized: "None")
        }
        if publish.albumsState == .loading { return PublishText.loadingAlbums }
        if publish.rememberedAlbumGone { return PublishText.chooseAlbum }
        switch publish.album {
        case .none: return String(localized: "None")
        case .new: return PublishText.newAlbumItem
        case .existing(_, let name): return name
        }
    }

    private var albumMenu: some View {
        let canList = publish.serverInfo.map { PublishPermissions.canListAlbums($0.permissions) } ?? false
        return Menu(albumTitle) {
            Button("None") { publish.album = .none }
            Button(PublishText.newAlbumItem) { publish.album = .new(name: publish.newAlbumName) }
                .disabled(!canList)
            if !canList {
                Text(PublishText.albumsNeedRead)
            }
            if canList, !publish.albums.isEmpty {
                Divider()
                ForEach(publish.albums) { album in
                    Button(ServerText.album(album)) { publish.album = .existing(id: album.id, name: album.name) }
                }
            }
        }
        .fixedSize()
        .disabled(publish.albumsState == .loading || publish.check == .checking)
    }

    // MARK: Stacking (design §3.5)

    private var stackingSection: some View {
        Section("Stacking") {
            Toggle("Stack with original", isOn: Bindable(publish).stacking)
                .toggleStyle(.checkbox)
            Caption(text: PublishText.stackingCaption)
            if publish.stacking {
                LabeledContent("Folder map") {
                    HStack {
                        Text(PublishText.folderCount(publish.folderMap.count)).foregroundStyle(.secondary)
                        Button("Edit Folder Map…") { publish.showFolderMapPage() }
                    }
                }
                if publish.folderMap.isEmpty, publish.noneLinked {
                    InfoLine(text: PublishText.noOriginalYet)
                }
                if !publish.missing.stacking.isEmpty {
                    IssueText(text: PublishText.stackingNeeds(publish.missing.stacking))
                        .onAppear { AccessibilityText.announce(PublishText.stackingNeeds(publish.missing.stacking), priority: .medium) }
                }
                Button("Check Originals") { publish.checkOriginals() }
                    .disabled(!publish.canCheckOriginals)
                OriginalsCheckView(publish: publish)
            }
        }
    }

    // MARK: Files (design §3.6)

    private var filesSection: some View {
        Section("Files") {
            ExportPresetRow(presets: publish.presets, selectedID: publish.presetID, modified: publish.modifiedPreset,
                            apply: { publish.applyPreset(id: $0) }, save: { publish.savePreset(named: $0) },
                            update: { if let preset = publish.modifiedPreset { publish.savePreset(named: preset.name) } },
                            delete: { publish.deleteSelectedPreset() })
            LabeledContent("Settings") {
                HStack(alignment: .firstTextBaseline) {
                    Text(PublishText.settingsSummary(publish.editor.settings))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Edit Settings…") { publish.showSettingsPage() }
                }
            }
            if let issue = publish.settingsIssue { IssueText(text: issue) }
            TextField("Description", text: Bindable(publish).description, prompt: Text(PublishText.descriptionPrompt),
                      axis: .vertical)
                .lineLimit(2...4)
                .disabled(!publish.descriptionIsSent)
            if !publish.descriptionIsSent {
                Caption(text: PublishText.descriptionNotSent(publish.editor.settings.metadata))
            }
            Caption(text: PublishText.filesCaption(publish.editor.settings.metadata))
        }
    }
}

/// Check Originals' state under its button (design §7).
private struct OriginalsCheckView: View {
    let publish: PublishModel

    var body: some View {
        switch publish.originals {
        case .notRun:
            EmptyView()
        case .running(let done, let total):
            HStack {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text(PublishText.originalsProgress(done, total)).font(.system(size: 11)).monospacedDigit()
                    .accessibilityAddTraits(.updatesFrequently)
                Button("Stop") { publish.stopOriginalsCheck() }
            }
        case .failed(let reason):
            IssueText(text: PublishText.checkStopped(reason))
        case .result(let result):
            VStack(alignment: .leading, spacing: 4) {
                Label(PublishText.originalsSummary(found: result.found, of: result.checked),
                      systemImage: result.found == result.checked ? "checkmark.circle" : "exclamationmark.triangle")
                ForEach(result.groups, id: \.group) { entry in
                    DisclosureGroup(isExpanded: .constant(result.groups.count == 1) ) {
                        ForEach(Array(entry.photos.prefix(10).enumerated()), id: \.offset) { _, photo in
                            Text("\(photo.name): \(PublishText.reason(photo.reason))")
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if entry.photos.count > 10 {
                            Text(PublishText.andMore(entry.photos.count - 10)).font(.system(size: 11))
                        }
                    } label: {
                        Text("\(entry.photos.count): \(PublishText.groupTitle(entry.group))")
                    }
                }
                if result.offline > 0 { Caption(text: PublishText.originalsOffline(result.offline)) }
                Caption(text: PublishText.unstackedNote)
            }
        }
    }
}

// MARK: - File Settings (design §3.6)

private struct PublishSettingsPage: View {
    let model: LibraryModel

    var body: some View {
        let publish = model.publish
        VStack(spacing: 0) {
            Text("File Settings")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Divider()
            Form {
                ExportSettingsSections(editor: publish.editor)
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) { publish.closeSettingsPage(keeping: false) }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { publish.closeSettingsPage(keeping: true) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - The folder map (design §6)

private struct PublishFolderMapPage: View {
    let model: LibraryModel

    private var publish: PublishModel { model.publish }

    var body: some View {
        @Bindable var publish = publish
        VStack(spacing: 0) {
            Text(PublishText.folderMapTitle(publish.service?.name ?? ""))
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Divider()
            Form {
                Section {
                    Caption(text: PublishText.folderMapExplanation)
                }
                ForEach($publish.editingMap) { $mapping in
                    Section {
                        let shown = publish.displayPath(mapping)
                        LabeledContent("On this Mac") {
                            HStack {
                                Text(shown.connected ? shown.path : "\(shown.path) \(PublishText.notConnected)")
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                    .help(shown.path)
                                Button("Choose…") { publish.chooseFolder(replacing: mapping.id, in: NSApp.keyWindow) }
                            }
                        }
                        TextField("On the server", text: Binding(get: { mapping.serverPath },
                                                                 set: { mapping.serverPath = PublishFolderMapping.serverPathKept($0) }),
                                  prompt: Text(verbatim: "/mnt/media/photos"))
                        let issues = PublishFolderMapping.issues(of: mapping, in: publish.editingMap)
                        if issues.contains(.emptyServerPath) { IssueText(text: PublishText.enterServerPath) }
                        if issues.contains(.duplicateFolder) { IssueText(text: PublishText.folderAlreadyMapped) }
                        if !mapping.serverPath.isEmpty, !mapping.serverPath.hasPrefix("/") {
                            Caption(text: PublishText.pathsStartWithSlash)
                        }
                        if let example = publish.example(for: mapping) {
                            Text(PublishText.lookedFor(example.name, at: example.path))
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Caption(text: PublishText.noSelectedPhotoHere)
                        }
                        HStack {
                            Spacer()
                            Button("Remove Folder") { publish.editingMap.removeAll { $0.id == mapping.id } }
                        }
                    }
                }
                Section {
                    Button("Add Folder…") { publish.chooseFolder(in: NSApp.keyWindow) }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) { publish.closeFolderMapPage(saving: false) }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { publish.closeFolderMapPage(saving: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!publish.folderMapCanSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}
