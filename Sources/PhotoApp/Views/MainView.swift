import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

struct MainView: View {
    @Bindable var model: LibraryModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
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
        // Photos are judged against neutral dark surroundings.
        .preferredColorScheme(.dark)
        .task { await model.start() }
        .onChange(of: model.requestsImportWindow) {
            guard model.requestsImportWindow else { return }
            model.requestsImportWindow = false
            openWindow(id: "import")
        }
        .onChange(of: model.requestsLookTableWindow) {
            guard model.requestsLookTableWindow else { return }
            model.requestsLookTableWindow = false
            openWindow(id: "lookTables")
        }
        .onChange(of: model.requestsPresetWindow) {
            guard model.requestsPresetWindow else { return }
            model.requestsPresetWindow = false
            openWindow(id: "presets")
        }
        .onChange(of: model.requestsExportWindow) {
            guard model.requestsExportWindow else { return }
            model.requestsExportWindow = false
            openWindow(id: "export")
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

/// Grid, with the loupe laid over it while open. The grid stays alive underneath
/// so its scroll position survives a trip to the loupe.
struct BrowserView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        ZStack {
            Color(nsColor: Palette.gridBackground)
            GridView(model: model)
            if model.mode == .loupe {
                LoupeView(model: model)
            }
            if let request = model.keywordEntry {
                VStack {
                    KeywordEntryPanel(model: model, request: request)
                    Spacer()
                }
            }
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

private struct EmptyLibraryView: View {
    let model: LibraryModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: model.isFiltered ? "line.3.horizontal.decrease.circle" : "photo.stack")
                .font(.system(size: 44, weight: .light))
            if model.isFiltered {
                Text("No photos match the filter.")
                    .font(.title3)
            } else {
                Text("No photos yet")
                    .font(.title3)
                Text("Import a folder of photos, or drag folders here. Originals stay where they are; \(AppBranding.displayName) only references them.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
                Button("Add Folder Without Copying…") { ImportPanel.run(model: model) }
                    .controlSize(.large)
                    .disabled(model.isImporting)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(40)
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importFolder(url)
    }
}
