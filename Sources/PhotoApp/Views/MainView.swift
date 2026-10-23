import AppKit
import PhotoCore
import SwiftUI

struct MainView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            BrowserView(model: model)
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar { BrowserToolbar(model: model) }
        // Photos are judged against neutral dark surroundings.
        .preferredColorScheme(.dark)
        .task { await model.start() }
    }

    private var title: String {
        switch model.sidebarSelection {
        case .allPhotos:
            String(localized: "All Photos")
        case .project(let id):
            model.projects.first { $0.id == id }?.project.name ?? AppBranding.displayName
        }
    }

    private var subtitle: String {
        let count = model.itemCount
        return model.isFiltered
            ? String(localized: "\(count) photos match the filter")
            : String(localized: "\(count) photos")
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
            if model.itemCount == 0, model.mode == .grid {
                EmptyLibraryView(model: model)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(model: model)
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
                Text("Import a folder of photos. Originals stay where they are; \(AppBranding.displayName) only references them.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
                Button("Import Folder…") { ImportPanel.run(model: model) }
                    .controlSize(.large)
                    .disabled(model.isImporting)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(40)
    }
}

struct StatusBar: View {
    let model: LibraryModel

    var body: some View {
        HStack(spacing: 12) {
            if let progress = model.importProgress {
                ProgressView(value: Double(progress.filesProcessed), total: Double(max(progress.filesFound, 1)))
                    .frame(width: 140)
                Text(importText(progress))
                    .monospacedDigit()
                Button {
                    model.cancelImport()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Cancel Import")
            } else if let warming = model.warming {
                ProgressView(value: Double(warming.done), total: Double(max(warming.total, 1)))
                    .frame(width: 100)
                Text("Rendering previews \(warming.done) of \(warming.total)")
                    .monospacedDigit()
            } else if let message = model.statusMessage {
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if let item = model.focusedItem {
                if model.isOffline(item) {
                    Label("Offline", systemImage: "externaldrive.badge.xmark")
                        .help("The volume holding this original is not connected.")
                }
                Text(item.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
    }

    private func importText(_ progress: ImportProgress) -> String {
        switch progress.phase {
        case .scanning:
            String(localized: "Looking for photos…")
        case .importing, .finished:
            String(localized: "Importing \(progress.filesProcessed) of \(progress.filesFound)")
        }
    }
}

struct BrowserToolbar: ToolbarContent {
    @Bindable var model: LibraryModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                ImportPanel.run(model: model)
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import a folder of photos")
            .disabled(model.isImporting)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View", selection: $model.mode) {
                Label("Grid", systemImage: "square.grid.2x2").tag(BrowserMode.grid)
                Label("Loupe", systemImage: "rectangle").tag(BrowserMode.loupe)
            }
            .pickerStyle(.segmented)
            .disabled(model.itemCount == 0)
            .help("Switch between the grid and a single photo")

            Slider(value: $model.thumbnailSize, in: LibraryModel.thumbnailSizeRange) {
                Text("Thumbnail Size")
            } minimumValueLabel: {
                Image(systemName: "square.grid.3x3")
            } maximumValueLabel: {
                Image(systemName: "square.grid.2x2")
            }
            .frame(width: 160)
            .disabled(model.mode != .grid)
            .help("Thumbnail size")
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importFolder(url)
    }
}
