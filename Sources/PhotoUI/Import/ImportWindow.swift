import AppKit
import PhotoCore
import SwiftUI

/// The import window: pick a source, choose photos, set where and how they are
/// copied, and import. The library app and the standalone importer both show it.
public struct ImportWindow: View {
    @Bindable var model: CardImportModel

    public init(model: CardImportModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                VStack(spacing: 0) {
                    SourceBar(model: model)
                    Divider()
                    ShotGrid(model: model)
                }
                .frame(minWidth: 520)
                ImportOptionsPanel(model: model)
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
            }
            Divider()
            CameraStatusBar(camera: model.camera)
        }
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(.dark)
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
    }

    private var deletionTitle: String {
        String(localized: "Delete \(model.pendingDeletion?.count ?? 0) files from \(model.source?.name ?? "")?")
    }
}

/// The newest photo's camera and its shutter count, centered at the bottom of
/// the window: "Sony ILCE-7M3 - 12,345".
private struct CameraStatusBar: View {
    let camera: CameraSummary?

    var body: some View {
        Group {
            if let camera {
                Text(Self.text(camera))
                    .help(String(localized: "Read from \(camera.fileName), the newest photo"))
            } else {
                Text(verbatim: " ")
            }
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(.bar)
    }

    static func text(_ camera: CameraSummary) -> String {
        guard let count = camera.shutterCount else { return camera.name }
        return String(localized: "\(camera.name) - \(count.formatted(.number))",
                      comment: "Import status bar: camera make and model, then its shutter count")
    }
}

private struct SourceBar: View {
    @Bindable var model: CardImportModel

    var body: some View {
        HStack(spacing: 10) {
            Picker("From", selection: $model.source) {
                if model.sources.isEmpty {
                    Text("No card connected").tag(ImportSource?.none)
                }
                ForEach(model.sources) { source in
                    Label(source.name, systemImage: source.isCard ? "sdcard" : "folder").tag(ImportSource?.some(source))
                }
            }
            .frame(maxWidth: 280)
            Button("Choose Folder…") { model.chooseFolder() }
            Button {
                model.rescan()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Look at the source again")
            .disabled(model.source == nil)
            Spacer()
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("Reading…").foregroundStyle(.secondary)
            } else if !model.shots.isEmpty {
                Text("\(model.selection.count) of \(model.shots.count - model.duplicateCount) selected")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("All") { model.selectAll() }
                .disabled(model.shots.isEmpty)
                .help("Select every photo")
            Button("None") { model.selectNone() }
                .disabled(model.selection.isEmpty)
                .help("Select no photos")
        }
        .padding(10)
    }
}

private struct ShotGrid: View {
    @Bindable var model: CardImportModel

    var body: some View {
        VStack(spacing: 0) {
            if model.duplicateCount > 0 {
                HStack {
                    Text("\(model.duplicateCount) photos are already in the library and are not imported.")
                    Spacer()
                    Toggle("Show them", isOn: $model.showsDuplicates)
                        .toggleStyle(.checkbox)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
            }
            if model.shots.isEmpty, !model.isScanning {
                ContentUnavailableView(model.source == nil ? String(localized: "Insert a card or choose a folder")
                                                           : String(localized: "No photos found"),
                                       systemImage: "sdcard")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)], spacing: 10) {
                        ForEach(model.visibleShots) { shot in
                            ShotTile(shot: shot, selected: model.selection.contains(shot.id))
                                .onTapGesture {
                                    guard !shot.isDuplicate else { return }
                                    model.click(shot, extend: NSEvent.modifierFlags.contains(.shift))
                                }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(Color(nsColor: Palette.gridBackground))
    }
}

private struct ShotTile: View {
    let shot: SourceShot
    let selected: Bool
    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(white: 0.2))
                    .aspectRatio(1.4, contentMode: .fit)
                    .overlay {
                        if let thumbnail {
                            Image(decorative: thumbnail, scale: 1)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Image(systemName: shot.isDuplicate ? "checkmark.seal" : (selected ? "checkmark.circle.fill" : "circle"))
                    .font(.title3)
                    .foregroundStyle(shot.isDuplicate ? .secondary : (selected ? Color.accentColor : .white.opacity(0.8)))
                    .shadow(radius: 2)
                    .padding(6)
            }
            HStack {
                Text((shot.primary.name as NSString).deletingPathExtension)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            }
            .font(.caption)
            Text(dateText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .opacity(shot.isDuplicate ? 0.5 : 1)
        .contentShape(Rectangle())
        .task(id: shot.id) {
            thumbnail = await SourceThumbnails.shared.thumbnail(for: shot.primary.url)
        }
        .help(shot.isDuplicate ? String(localized: "Already in the library") : shot.files.map(\.name).joined(separator: " + "))
    }

    /// In the capture's own time: cameras usually record local time without a
    /// zone, stored as UTC (see `ImageMetadata.captureDate`).
    private var dateText: String {
        let metadata = shot.primary.metadata
        var style = Date.FormatStyle.dateTime.day().month().hour().minute()
        if metadata.captureDate != nil {
            style.timeZone = metadata.captureOffsetSeconds.flatMap(TimeZone.init(secondsFromGMT:)) ?? TimeZone(secondsFromGMT: 0)!
        }
        return shot.date.formatted(style)
    }

    private var badge: String {
        shot.files.map { FileKindText.badge($0.kind) }.joined(separator: "+")
    }
}

private struct ImportOptionsPanel: View {
    @Bindable var model: CardImportModel
    @State private var editingPreset: MetadataPreset?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Destination") {
                    LabeledContent("Folder") {
                        HStack {
                            Text(model.destination.path)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .help(model.destination.path)
                            Button("Choose…") { model.chooseDestination() }
                        }
                    }
                    TemplateField(title: String(localized: "Subfolders"), text: $model.folderTemplate, folders: true)
                    TemplateField(title: String(localized: "File names"), text: $model.fileTemplate, folders: false)
                    if let example = model.example {
                        LabeledContent("Example") {
                            Text(example)
                                .font(.caption.monospaced())
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
                Section(model.copiesOnly ? String(localized: "Job") : String(localized: "Project")) {
                    if let library = model.library {
                        Picker("Add to", selection: $model.existingProjectID) {
                            Text("A new project").tag(Int64?.none)
                            ForEach(library.projects) { summary in
                                Text(summary.project.name).tag(Int64?.some(summary.id))
                            }
                        }
                        if model.existingProjectID == nil {
                            TemplateField(title: String(localized: "Name"), text: $model.projectNameTemplate, folders: false)
                        }
                    }
                    HStack {
                        TextField("Job code", text: $model.jobCode, prompt: Text("e.g. Smith wedding"))
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
                        }
                    }
                }
                Section("Metadata") {
                    Picker("Apply", selection: $model.presetID) {
                        Text("No metadata").tag(Int64?.none)
                        ForEach(model.presets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    HStack {
                        Button("New Preset…") {
                            editingPreset = MetadataPreset(name: String(localized: "Untitled Preset"),
                                                           values: SidecarValues(rights: "© {capture:yyyy} "))
                        }
                        if let preset = model.presets.first(where: { $0.id == model.presetID }) {
                            Button("Edit…") { editingPreset = preset }
                        }
                    }
                    .controlSize(.small)
                    if model.presetID != nil {
                        Text("Written to sidecar files next to the copies; the copies stay identical to the originals.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Videos") {
                    Toggle("Include videos", isOn: $model.includesVideos)
                    if !model.copiesOnly {
                        Text("Videos are copied and catalogued like photos and play in the loupe. They cannot be edited.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("After Importing") {
                    Toggle("Delete originals from the source", isOn: $model.deletesOriginals)
                    Toggle("Eject the card", isOn: $model.ejectsWhenDone)
                        .disabled(model.source?.isEjectable != true)
                }
            }
            .formStyle(.grouped)
            Divider()
            ImportFooter(model: model)
                .padding(12)
        }
        .sheet(item: $editingPreset) { preset in
            PresetEditor(preset: preset, onSave: model.savePreset, onDelete: { model.deletePreset($0) })
        }
    }
}

/// A template text field with a menu of tokens to insert.
private struct TemplateField: View {
    let title: String
    @Binding var text: String
    let folders: Bool

    private var tokens: [(String, String)] {
        var list: [(String, String)] = [
            (String(localized: "Capture year"), "{capture:yyyy}"),
            (String(localized: "Capture date"), "{capture:yyyy-MM-dd}"),
            (String(localized: "Capture month name"), "{capture:MMMM}"),
            (String(localized: "Capture time"), "{capture:HHmmss}"),
            (String(localized: "Import date"), "{import:yyyy-MM-dd}"),
            (String(localized: "Job code"), "{job}"),
            (String(localized: "Camera model"), "{model}"),
            (String(localized: "Camera make"), "{make}"),
            (String(localized: "Camera serial number"), "{serial}"),
            (String(localized: "Lens"), "{lens}"),
        ]
        if !folders {
            list += [
                (String(localized: "Original name"), "{name}"),
                (String(localized: "Number in the original name"), "{number}"),
                (String(localized: "Sequence in this import"), "{seq:4}"),
                (String(localized: "Counter across imports"), "{counter:5}"),
            ]
        }
        return list
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, text: $text)
                    .labelsHidden()
                    .font(.body.monospaced())
                Menu {
                    ForEach(tokens, id: \.1) { name, token in
                        Button("\(name)  \(token)") { text += (folders && !text.isEmpty && !text.hasSuffix("/") ? "/" : "") + token }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Insert a token")
            }
        }
    }
}

private struct ImportFooter: View {
    let model: CardImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = model.progress {
                ProgressView(value: Double(progress.bytesDone), total: Double(max(progress.bytesTotal, 1))) {
                    Text("Copying \(progress.currentName)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                } currentValueLabel: {
                    Text("\(progress.filesDone) of \(progress.filesTotal) files · \(ByteCountFormatter.string(fromByteCount: progress.bytesDone, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: progress.bytesTotal, countStyle: .file))")
                        .monospacedDigit()
                }
            } else if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if model.isImporting {
                    Button("Stop", role: .cancel) { model.cancelImport() }
                } else {
                    Button("Import \(model.selectedShots.count) Photos") { model.startImport() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.selectedShots.isEmpty)
                }
            }
        }
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

/// Thumbnails of source files from their embedded previews (no RAW decoding
/// when the file has one), decoded off the main thread and kept while the
/// window is open.
actor SourceThumbnails {
    static let shared = SourceThumbnails()
    private var cache: [URL: CGImage] = [:]

    func thumbnail(for url: URL) async -> CGImage? {
        if let cached = cache[url] { return cached }
        if FileKind(pathExtension: url.pathExtension) == .video {
            let poster = try? await VideoFrames.poster(of: url, longEdge: 360)
            if let poster { cache[url] = poster }
            return poster
        }
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceThumbnailMaxPixelSize: 360,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        if let image {
            if cache.count > 4000 { cache.removeAll() }
            cache[url] = image
        }
        return image
    }
}
