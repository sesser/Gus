import PhotoCore
import PhotoUI
import SwiftUI

/// The library window's toolbar (section 5 of docs/UI_REDESIGN.md):
/// customizable, in three groups, with the filter and search for the grid
/// only. The sidebar toggle and the title come from the system.
struct LibraryToolbar: CustomizableToolbarContent {
    @Bindable var model: LibraryModel

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "import") { ImportToolbarButton(model: model) }
        ToolbarItem(id: "export") {
            Button {
                model.export.begin()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export the selected photos")
            .disabled(model.itemCount == 0 || model.export.isExporting)
        }
        groupSpacer()
        ToolbarItem(id: "mode") {
            Picker("View", selection: $model.mode) {
                Label("Grid", systemImage: "square.grid.2x2").tag(BrowserMode.grid)
                Label("Loupe", systemImage: "rectangle").tag(BrowserMode.loupe)
            }
            .pickerStyle(.segmented)
            .disabled(model.itemCount == 0)
            .help("Switch between the grid and a single photo")
        }
        ToolbarItem(id: "size") { SizeControl(model: model) }
        ToolbarItem(id: "activity", placement: .status) { ActivityToolbarItem(model: model) }
            .customizationBehavior(.disabled)
            .hidden(!ActivityToolbarItem.isVisible(model))
        groupSpacer()
        ToolbarItem(id: "filter") { FilterSortMenu(model: model) }
            .hidden(model.mode != .grid)
        ToolbarItem(id: "search") {
            SearchField(text: $model.searchText, placeholder: String(localized: "Keywords, file type, camera, lens")) {
                NotificationCenter.default.post(name: .browserShouldTakeFocus, object: model)
            }
            .frame(minWidth: 180, idealWidth: 240, maxWidth: 300)
            .help("Commas separate alternatives: “orf, arw”. Words must all match: “sony jpg”.")
        }
        .hidden(model.mode != .grid)
        paletteItems
        ToolbarItem(id: "inspector") {
            Button {
                model.showsInspector.toggle()
            } label: {
                Label(model.showsInspector ? String(localized: "Hide Inspector") : String(localized: "Show Inspector"),
                      systemImage: "sidebar.trailing")
            }
            .help(model.showsInspector ? String(localized: "Hide Inspector") : String(localized: "Show Inspector"))
        }
        .customizationBehavior(.disabled)
    }

    /// Separates the groups on macOS 26; the earlier design groups by itself.
    @ToolbarContentBuilder
    private func groupSpacer() -> some CustomizableToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
    }

    /// Off by default; added with View ▸ Customize Toolbar….
    @ToolbarContentBuilder
    private var paletteItems: some CustomizableToolbarContent {
        let state = LibraryMenuState(model)
        ToolbarItem(id: "crop", showsByDefault: false) {
            Button { model.crop() } label: { Label("Crop", systemImage: "crop") }
                .disabled(state.mode == .grid ? !state.focusedIsPhoto : !state.canEditLoupePhoto)
        }
        ToolbarItem(id: "rotateLeft", showsByDefault: false) {
            Button { model.rotate(clockwise: false) } label: { Label("Rotate Left", systemImage: "rotate.left") }
                .disabled(state.mode == .grid ? !state.targetsIncludePhoto : !state.canEditLoupePhoto)
        }
        ToolbarItem(id: "rotateRight", showsByDefault: false) {
            Button { model.rotate(clockwise: true) } label: { Label("Rotate Right", systemImage: "rotate.right") }
                .disabled(state.mode == .grid ? !state.targetsIncludePhoto : !state.canEditLoupePhoto)
        }
        ToolbarItem(id: "original", showsByDefault: false) {
            Button { model.editor.toggleOriginal() } label: { Label("Original", systemImage: "square.split.2x1") }
                .disabled(!state.canEditLoupePhoto || state.isCropping)
        }
        ToolbarItem(id: "auto", showsByDefault: false) {
            Button { model.autoExposure() } label: { Label("Auto", systemImage: "wand.and.stars") }
                .disabled(state.mode == .grid ? !state.targetsIncludePhoto : !state.canEditLoupePhoto || state.isCropping)
        }
        ToolbarItem(id: "copyAdjustments", showsByDefault: false) {
            Button { model.copyAdjustments() } label: { Label("Copy Adjustments", systemImage: "doc.on.doc") }
                .disabled(!state.hasFocusedItem)
        }
        ToolbarItem(id: "pasteAdjustments", showsByDefault: false) {
            Button { model.pasteAdjustments() } label: { Label("Paste Adjustments", systemImage: "doc.on.clipboard") }
                .disabled(!state.hasCopiedAdjustments || !state.targetsIncludePhoto)
        }
        ToolbarItem(id: "addKeywords", showsByDefault: false) {
            Button { model.beginKeywordEntry() } label: { Label("Add Keywords", systemImage: "tag") }
                .disabled(!state.hasTargets)
        }
        ToolbarItem(id: "suggestKeywords", showsByDefault: false) {
            Button {
                model.suggestKeywords(for: model.actionTargetVersionIDs)
                model.showsInspector = true
            } label: {
                Label("Suggest Keywords", systemImage: "sparkles")
            }
            .disabled(!state.hasTargets)
        }
        ToolbarItem(id: "newAlbum", showsByDefault: false) {
            Button {
                model.sidebarSheet = .newAlbum(projectID: model.selectedProjectID)
            } label: {
                Label("New Album", systemImage: "rectangle.stack.badge.plus")
            }
        }
    }
}

/// Click: Import from Card or Folder…; the menu adds Add Folder Without Copying….
private struct ImportToolbarButton: View {
    let model: LibraryModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            Button("Import from Card or Folder…") { openImport() }
            Button("Add Folder Without Copying…") { ImportPanel.run(model: model) }
                .disabled(model.isImporting)
        } label: {
            Label("Import", systemImage: "square.and.arrow.down")
        } primaryAction: {
            openImport()
        }
        .help("Import from a card or folder")
    }

    private func openImport() {
        model.cardImport.refreshSources()
        openWindow(id: "import")
    }
}

/// The thumbnail size in the grid; Fit / 100% in the loupe, neither selected
/// at other zoom levels.
private struct SizeControl: View {
    @Bindable var model: LibraryModel

    private enum Zoom: Hashable { case fit, actualSize }

    var body: some View {
        if model.mode == .grid {
            Slider(value: $model.thumbnailSize, in: LibraryModel.thumbnailSizeRange) {
                Text("Thumbnail Size")
            } minimumValueLabel: {
                Image(systemName: "photo").imageScale(.small)
            } maximumValueLabel: {
                Image(systemName: "photo").imageScale(.large)
            }
            .frame(width: 140)
            .help("Thumbnail size")
        } else {
            Picker("Zoom", selection: Binding<Zoom?>(
                get: {
                    let zoom = model.loupeZoom
                    return zoom.isActualSize ? .actualSize : (zoom.isZoomed ? nil : .fit)
                },
                set: { choice in
                    guard let choice else { return }
                    NotificationCenter.default.post(name: .loupeShouldSetZoom, object: model,
                                                    userInfo: [LoupeZoomStep.fitKey: choice == .fit])
                })) {
                Text("Fit").tag(Zoom?.some(.fit))
                Text("100%").tag(Zoom?.some(.actualSize))
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .disabled(model.focusedItem?.isVideo != false)
            .help("Fit the photo in the window, or show it at 100%")
        }
    }
}

/// Rating, Flag and Sort By, and Clear Filter: View ▸ Filter and View ▸ Sort
/// By's items. Filled while a filter is on.
private struct FilterSortMenu: View {
    @Bindable var model: LibraryModel

    var body: some View {
        Menu {
            RatingFilterPicker(rule: $model.ratingRule)
            FlagFilterPicker(rule: $model.flagRule)
            Section("Sort By") {
                SortPickers(sort: $model.sort)
            }
            Divider()
            Button("Clear Filter") { model.clearFilter() }
                .disabled(!model.isFiltered)
        } label: {
            Label("Filter and Sort", systemImage: model.isFiltered ? "line.3.horizontal.decrease.circle.fill"
                                                                   : "line.3.horizontal.decrease.circle")
        }
        .help("Filter and sort the photos")
    }
}
