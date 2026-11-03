import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

struct MainView: View {
    @Bindable var model: LibraryModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(get: { model.showsSidebar ? .all : .detailOnly },
                                                      set: { model.showsSidebar = $0 != .detailOnly })) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 320)
        } detail: {
            BrowserView(model: model)
                .inspector(isPresented: $model.showsInspector) {
                    InspectorView(model: model)
                        .inspectorColumnWidth(min: 280, ideal: 300, max: 420)
                }
        }
        .navigationTitle(model.windowTitle)
        .navigationSubtitle(model.windowSubtitle)
        .toolbar(id: "library") { LibraryToolbar(model: model) }
        .background { LibraryMenuPublisher(model: model) }
        // The library window only (SwiftUI sets this window's NSWindow.appearance):
        // photos are judged against neutral dark surroundings; Import and
        // Settings follow the system.
        .preferredColorScheme(.dark)
        // Review: the toolbar shows only while the pointer is at the top.
        .windowToolbarFullScreenVisibility(model.isReviewing ? .onHover : .automatic)
        .task { await model.start() }
        .onChange(of: model.requestsImportWindow) {
            guard model.requestsImportWindow else { return }
            model.requestsImportWindow = false
            openWindow(id: "import")
        }
        // One sheet at a time (section 8, "The rule").
        .sheet(isPresented: $model.showsExportSheet) {
            ExportSheet(model: model)
        }
        .sheet(isPresented: $model.showsLookTableSheet) {
            LookTableBrowserSheet(model: model)
        }
        .sheet(isPresented: $model.showsPresetSheet) {
            PresetManagerSheet(model: model)
        }
        .alert(model.export.report?.title ?? "", isPresented: Binding(
            get: { model.export.report != nil }, set: { if !$0 { model.export.report = nil } }
        )) {
            Button("OK") { model.export.report = nil }
        } message: {
            Text(model.export.report?.message ?? "")
        }
        .alert(model.presetImportSummary?.title ?? "", isPresented: Binding(
            get: { model.presetImportSummary != nil }, set: { if !$0 { model.presetImportSummary = nil } }
        )) {
            Button("OK") { model.presetImportSummary = nil }
        } message: {
            Text(model.presetImportSummary?.message ?? "")
        }
    }

}

extension View {
    /// On macOS 26 the grid scrolls under the toolbar for the system
    /// scroll-edge effect; its scroll view insets its content by itself
    /// (`automaticallyAdjustsContentInsets`). Earlier, a plain toolbar.
    @ViewBuilder
    func underToolbar() -> some View {
        if #available(macOS 26, *) {
            ignoresSafeArea(.container, edges: .top)
        } else {
            self
        }
    }
}

/// Grid, with the loupe laid over it while open. The grid stays alive underneath
/// so its scroll position survives a trip to the loupe.
struct BrowserView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        ZStack {
            Color(nsColor: Palette.gridBackground)
            GridView(model: model)
                .underToolbar()
            if model.mode == .loupe {
                LoupeView(model: model)
            }
            // ⌘K: a popover on the content's top edge (section 8).
            VStack {
                Color.clear
                    .frame(width: 1, height: 1)
                    .popover(item: Binding(get: { model.keywordEntry },
                                           set: { if $0 == nil, model.keywordEntry != nil { model.endKeywordEntry(adding: []) } }),
                             arrowEdge: .top) { request in
                        KeywordEntryPanel(model: model, request: request)
                    }
                Spacer()
            }
            .allowsHitTesting(false)
            if model.itemCount == 0, model.mode == .grid, !model.isFolderDropTargeted {
                EmptyLibraryView(model: model)
            }
        }
        .onDrop(of: FolderDrop.types, isTargeted: $model.isFolderDropTargeted) { providers in
            FolderDrop.accept(providers, model: model)
        }
        .overlay {
            if model.isFolderDropTargeted { FolderDropHighlight() }
        }
    }
}

/// "No Photos Yet" with Import and Add Folder Without Copying, or "No Photos
/// Match" with Clear Filter (section 9 of docs/UI_REDESIGN.md).
private struct EmptyLibraryView: View {
    let model: LibraryModel

    var body: some View {
        if model.isFiltered {
            ContentUnavailableView {
                Label("No Photos Match", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Clear Filter") { model.clearFilter() }
            }
        } else {
            ContentUnavailableView {
                Label("No Photos Yet", systemImage: "photo.stack")
            } description: {
                Text("Import copies photos from a card or folder into the folder you choose. Add Folder Without Copying uses photos where they are; \(AppBranding.displayName) only references them.",
                     comment: "Empty library: copying versus using photos in place")
                Text("You can also drag folders here.", comment: "Empty library hint")
            } actions: {
                Button(model.mountedCardName.map { String(localized: "Import from \($0)…", comment: "Empty library: a card is mounted") }
                       ?? String(localized: "Import from Card or Folder…")) {
                    model.cardImport.refreshSources()
                    model.requestsImportWindow = true
                }
                .buttonStyle(.borderedProminent)
                Button("Add Folder Without Copying…") { ImportPanel.run(model: model) }
                    .disabled(model.isImporting)
            }
        }
    }
}

@MainActor
enum ImportPanel {
    static func run(model: LibraryModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Import")
        panel.message = String(localized: "Choose a folder. Photos inside it, including subfolders, are added to a new project.")
        Task {
            guard await WindowModal.run(panel), let url = panel.url else { return }
            model.importFolder(url)
        }
    }
}
