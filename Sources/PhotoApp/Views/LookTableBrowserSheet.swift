import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// Every look-up table of a collection previewed on the photo being edited,
/// as a sheet on the library window (section 8, "Other sheets"). Importing
/// and managing are pages of the sheet with a Back button, not sheets on it.
/// Collections are panes; only expanded panes render their previews.
struct LookTableBrowserSheet: View {
    let model: LibraryModel
    @Environment(\.dismiss) private var dismiss

    private var library: LookTableLibraryModel { model.lookTableLibrary }
    private var editor: AdjustmentEditor { model.editor }

    var body: some View {
        Group {
            switch library.page {
            case .importing(let draft):
                LookTableImportPage(library: library, draft: draft)
            case .manage:
                LookTableManagePage(library: library)
            case nil:
                browser
            }
        }
        .frame(width: 760, height: 560)
        .task { await library.reload() }
        .onDisappear { library.page = nil }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            BrowserBar(model: model)
            Divider()
            if editor.state != .ready {
                Text("Open a photo in the loupe to preview look-up tables on it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                Divider()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(library.shownCollections) { collection in
                        CollectionPane(model: model, collection: collection)
                    }
                }
                .padding(.bottom, 10)
            }
            .background(Color(nsColor: Palette.gridBackground))
            Divider()
            HStack(spacing: 12) {
                Button("Remove from Photo") {
                    editor.change(String(localized: "Look-Up Table"), phase: .committed) { $0.lookTable = LookTable() }
                }
                .disabled(editor.state != .ready || editor.adjustments.lookTable.identifier == nil)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    guard let selection = library.selection else { return }
                    library.apply(selection, editor: editor)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editor.state != .ready || library.selection == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

/// Collection pop-up, Import… and Manage….
private struct BrowserBar: View {
    let model: LibraryModel

    var body: some View {
        @Bindable var library = model.lookTableLibrary
        HStack(spacing: 10) {
            Picker("Collection", selection: $library.browsedCollection) {
                Text("All Collections").tag(LookTableLibraryModel.allCollections)
                Divider()
                ForEach(library.collections) { collection in
                    Text(collection.name).tag(collection.uuid)
                }
            }
            .frame(maxWidth: 320)
            Spacer()
            if library.isScanning {
                ProgressView().controlSize(.small)
            }
            Button("Import…") { library.chooseImportSource() }
                .help("Add a folder of .cube files as a collection")
            Button("Manage…") { library.page = .manage }
                .help("Rename or remove collections and tables")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// A page's top row: Back, and its title.
private struct PageHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Label("Back", systemImage: "chevron.backward")
            }
            .keyboardShortcut("[", modifiers: .command)
            Text(title)
                .font(.headline)
            Spacer()
        }
    }
}

/// One collection: a header that expands and collapses it, then its tables.
private struct CollectionPane: View {
    let model: LibraryModel
    let collection: LookTableCollection

    private var library: LookTableLibraryModel { model.lookTableLibrary }

    var body: some View {
        let isExpanded = library.expanded.contains(collection.uuid)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded { library.expanded.remove(collection.uuid) } else { library.expanded.insert(collection.uuid) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)
                    Text(collection.name)
                        .font(.headline)
                    Text(collection.entries.count.formatted())
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if isExpanded {
                if collection.entries.isEmpty {
                    Text("This collection is empty.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)], spacing: 10) {
                    ForEach(collection.entries) { entry in
                        LookTableTile(model: model, entry: entry)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
                .task(id: "\(model.editor.lookTablePreviewKey)|\(collection.entries.map(LookTableLibraryModel.previewID))") {
                    guard model.editor.state == .ready else { return }
                    // Wait for an edit to settle before rendering every table.
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    await library.renderPreviews(of: collection, editor: model.editor)
                }
            }
            Divider()
        }
    }
}

private struct LookTableTile: View {
    let model: LibraryModel
    let entry: LookTableEntry

    private var library: LookTableLibraryModel { model.lookTableLibrary }

    var body: some View {
        let isSelected = library.selection?.identifier == entry.identifier
        let isApplied = model.editor.adjustments.lookTable.identifier == entry.identifier
        VStack(alignment: .leading, spacing: 4) {
            Rectangle()
                .fill(Color(white: 0.2))
                .aspectRatio(1.4, contentMode: .fit)
                .overlay {
                    if let preview = library.previews[LookTableLibraryModel.previewID(entry)] {
                        Image(decorative: preview.cgImage, scale: 1)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack(spacing: 4) {
                if isApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .help("Applied to this photo")
                }
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { library.apply(entry, editor: model.editor) }
        .onTapGesture { library.selection = entry }
        .help(entry.fileName.isEmpty ? entry.name : "\(entry.name) (\(entry.fileName))")
    }
}

/// Confirms an import: where the tables go, their names and color space.
struct LookTableImportPage: View {
    let library: LookTableLibraryModel
    /// Cancel closes the sheet from every page; Back returns to the tables.
    @Environment(\.dismiss) private var dismiss
    @State var draft: LookTableLibraryModel.ImportDraft
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: String(localized: "Import Look-Up Tables")) { library.page = nil }
            Text(draft.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Form {
                Picker("Add to", selection: $draft.collectionID) {
                    Text("New Collection").tag(Int64?.none)
                    ForEach(library.importedCollections) { collection in
                        Text(collection.name).tag(collection.rowID)
                    }
                }
                if draft.collectionID == nil {
                    TextField("Name", text: $draft.newName)
                }
                Picker("Color space", selection: $draft.colorSpace) {
                    ForEach(LookTable.ColorSpace.allCases, id: \.self) { space in
                        Text(LookTableText.title(space)).tag(space)
                    }
                }
                .help("The color space the tables were made for. Most creative tables expect sRGB.")
            }
            List {
                ForEach($draft.candidates) { $candidate in
                    HStack {
                        if let failure = candidate.failure {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .help(failure)
                            Text(candidate.url.lastPathComponent)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Not a readable table")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("Name", text: $candidate.name)
                                .textFieldStyle(.plain)
                            Spacer()
                            Text(candidate.url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .frame(minHeight: 220, maxHeight: .infinity)
            if draft.candidates.isEmpty {
                Text("No .cube files were found.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Names come from each file's title, or its file name. Click a name to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Import \(draft.importable) Tables")) {
                    isImporting = true
                    Task {
                        await library.runImport(draft)
                        isImporting = false
                        library.page = nil
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.importable == 0 || isImporting)
            }
        }
        .padding(20)
        // A page fills the sheet: header on top, buttons at the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Renames and removes imported collections and their tables.
struct LookTableManagePage: View {
    let library: LookTableLibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRemoval: LookTableCollection?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: String(localized: "Manage Look-Up Tables")) { library.page = nil }
            if library.importedCollections.isEmpty {
                ContentUnavailableView("No Imported Collections", systemImage: "square.stack.3d.up",
                                       description: Text("Import a folder of .cube files to start a collection."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(library.importedCollections) { collection in
                        Section {
                            ForEach(collection.entries) { entry in
                                EntryRow(library: library, entry: entry)
                            }
                        } header: {
                            CollectionRow(library: library, collection: collection) { pendingRemoval = collection }
                        }
                    }
                }
            }
            HStack {
                Text("Photos that use a removed table keep their look.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import…") { library.chooseImportSource() }
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { library.page = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        // A page fills the sheet: header on top, buttons at the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert(String(localized: "Remove the collection \(pendingRemoval?.name ?? "")?"),
               isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval { library.deleteCollection(pendingRemoval) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its \(pendingRemoval?.entries.count ?? 0) tables leave the list. Photos that use them keep their look.")
        }
    }
}

private struct CollectionRow: View {
    let library: LookTableLibraryModel
    let collection: LookTableCollection
    let remove: () -> Void
    @State private var name = ""

    var body: some View {
        HStack {
            TextField("Collection name", text: $name)
                .textFieldStyle(.plain)
                .font(.headline)
                .onSubmit { library.renameCollection(collection, to: name) }
            Spacer()
            Button("Add Tables…") { library.chooseImportSource(into: collection.rowID) }
                .buttonStyle(.borderless)
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this collection")
        }
        .onAppear { name = collection.name }
        .onChange(of: collection.name) { name = collection.name }
    }
}

private struct EntryRow: View {
    let library: LookTableLibraryModel
    let entry: LookTableEntry
    @State private var name = ""

    var body: some View {
        HStack {
            TextField("Table name", text: $name)
                .textFieldStyle(.plain)
                .onSubmit { library.renameEntry(entry, to: name) }
            Spacer()
            Picker("Color space", selection: Binding(get: { entry.colorSpace },
                                                     set: { library.setColorSpace($0, for: entry) })) {
                ForEach(LookTable.ColorSpace.allCases, id: \.self) { space in
                    Text(LookTableText.title(space)).tag(space)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            Button(role: .destructive) {
                library.deleteEntry(entry)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this table from the collection")
        }
        .help(entry.fileName)
        .onAppear { name = entry.name }
        .onChange(of: entry.name) { name = entry.name }
    }
}
