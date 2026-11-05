import PhotoCore
import PhotoUI
import SwiftUI

/// The library window's menus (section 6 of docs/UI_REDESIGN.md).
///
/// Titles and enabled states come from `LibraryMenuContext`, which the window
/// publishes; it is nil while another window is key, so every item here is
/// off then. Bare-key items show the key, but the grid and loupe handle it
/// (AppKit offers an unmodified key to the first responder before the menu),
/// and they are on only while one of them has the keyboard. Command-key items
/// are on whenever the window is key and the command has something to act on.
struct LibraryCommands: Commands {
    @FocusedValue(\.libraryMenu) private var menu
    /// The import window, key: ⌥⌘I toggles its options (one item per key
    /// equivalent; AppKit stops at the first match, even a disabled one).
    @FocusedValue(\.importMenu) private var importMenu
    @Environment(\.openWindow) private var openWindow

    private var model: LibraryModel? { menu?.model }

    /// The window is key and `test` holds.
    private func can(_ test: (LibraryMenuState) -> Bool = { _ in true }) -> Bool {
        guard let state = menu?.state, state.isWindowKey else { return false }
        return test(state)
    }

    /// The grid, loupe or video loupe has the keyboard and `test` holds.
    private func canByKey(_ test: (LibraryMenuState) -> Bool = { _ in true }) -> Bool {
        guard let state = menu?.state, state.bareKeysActive else { return false }
        return test(state)
    }

    var body: some Commands {
        fileCommands
        editCommands
        viewCommands
        photoCommands
        adjustCommands
        SidebarCommands()
        ToolbarCommands()
    }

    // MARK: File

    private var fileCommands: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import from Card or Folder…") {
                model?.cardImport.refreshSources()
                openWindow(id: "import")
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(!can())
            Button("Add Folder Without Copying…") {
                if let model { ImportPanel.run(model: model) }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            // A folder chosen while another is added joins its queue, as a drop does.
            .disabled(!can())
            Divider()
            Button("New Album…") { model?.sidebarSheet = .newAlbum(projectID: model?.selectedProjectID) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!can())
            Button("New Smart Album…") { model?.sidebarSheet = .smartAlbum(nil, projectID: model?.selectedProjectID) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!can())
            Button("Edit Smart Album…") {
                if case .smartAlbum(let album) = menu?.state.sidebarItem {
                    model?.sidebarSheet = .smartAlbum(album, projectID: album.projectID)
                }
            }
            .disabled(!can { if case .smartAlbum = $0.sidebarItem { true } else { false } })
            Button(renameTitle) {
                switch menu?.state.sidebarItem {
                case .album(let album): model?.sidebarSheet = .renameAlbum(album)
                case .keyword(let keyword): model?.sidebarSheet = .renameKeyword(keyword)
                case .smartAlbum, nil: break
                }
            }
            .disabled(!can { $0.sidebarItem?.isRenamable == true })
            Button(deleteTitle) {
                model?.sidebarDeletion = switch menu?.state.sidebarItem {
                case .album(let album): .album(album)
                case .smartAlbum(let album): .smartAlbum(album)
                case .keyword(let keyword): .keyword(keyword)
                case nil: nil
                }
            }
            .disabled(!can { $0.sidebarItem != nil })
            Divider()
            Button("Export…") { model?.export.begin() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!can { $0.canExport })
            Button("Check for Changes on Disk") { model?.checkForDiskChanges() }
                .disabled(!can { !$0.isCheckingDisk })
            // One item for ⌘. (design.md P3, I4): the import window's Stop
            // Import while it is key, else the newest job Activity shows.
            if menu == nil, let importMenu {
                Button("Stop Import") { importMenu.stopImport() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!importMenu.canStopImport)
            } else {
                Button(stopTitle) {
                    if let job = menu?.state.stoppableJob { model?.stop(job) }
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!can { $0.stoppableJob != nil })
            }
            Divider()
        }
    }

    /// "Stop Export", "Stop Adding Folders" or "Stop Import"; "Stop" when
    /// nothing runs.
    private var stopTitle: String {
        switch can() ? menu?.state.stoppableJob : nil {
        case .export: String(localized: "Stop Export", comment: "File menu (⌘.): stops the running export")
        case .addFolders: String(localized: "Stop Adding Folders", comment: "File menu (⌘.): stops adding folders")
        case .cardImport: String(localized: "Stop Import")
        case nil: String(localized: "Stop")
        }
    }

    /// "Rename “Holiday”…" for an album or keyword selected in the sidebar.
    private var renameTitle: String {
        guard can(), let item = menu?.state.sidebarItem, item.isRenamable else { return String(localized: "Rename…") }
        return String(localized: "Rename “\(item.name)”…", comment: "File menu; the album or keyword selected in the sidebar")
    }

    private var deleteTitle: String {
        guard can(), let item = menu?.state.sidebarItem else { return String(localized: "Delete…") }
        return String(localized: "Delete “\(item.name)”…", comment: "File menu; the album, smart album or keyword selected in the sidebar")
    }

    // MARK: Edit

    private var editCommands: some Commands {
        CommandGroup(after: .pasteboard) {
            // One item for ⇧⌘A (design.md P3, I5): the import window's while it
            // is key, else the grid's, which keeps only the focused photo.
            if menu == nil, let importMenu {
                Button("Deselect All") { importMenu.deselectAll() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!importMenu.canDeselectAll)
            } else {
                Button("Deselect All") { model?.collapseSelection() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!canByKey { $0.mode == .grid && $0.selectedCount > 1 })
            }
            Divider()
            Menu("Find") {
                // Find holds find commands only; Clear Filter lives in View ▸
                // Filter (owner ruling D1).
                Button("Find…") { model?.beginSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!can())
            }
        }
    }

    // MARK: View

    /// SwiftUI puts the system items (Show / Hide Toolbar, Customize
    /// Toolbar…, Show / Hide Sidebar) at the top of the View menu; these follow.
    private var viewCommands: some Commands {
        CommandGroup(after: .sidebar) {
            Button(menu?.state.mode == .loupe ? String(localized: "Show Grid") : String(localized: "Show Loupe")) {
                guard let model else { return }
                if model.mode == .loupe { model.closeLoupe() } else { model.openLoupe() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!can { $0.itemCount > 0 })
            Button(menu?.state.isReviewing == true ? String(localized: "Exit Review") : String(localized: "Enter Review")) {
                model?.toggleReview()
            }
            .keyboardShortcut("f", modifiers: [])
            .disabled(!canByKey { $0.hasFocusedItem })
            Divider()
            Button(menu?.state.loupeZoom.isZoomed == true ? String(localized: "Zoom to Fit")
                                                           : String(localized: "Zoom to 100%")) {
                NotificationCenter.default.post(name: .loupeShouldToggleZoom, object: model)
            }
            .keyboardShortcut("z", modifiers: [])
            .disabled(!canByKey { $0.showsLoupePhoto })
            // The same items zoom the loupe and resize the grid's thumbnails.
            Button(isLoupe ? String(localized: "Zoom In") : String(localized: "Larger Thumbnails")) { resize(larger: true) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!can { $0.mode == .grid || ($0.showsLoupePhoto && $0.loupeZoom.canZoomIn) })
            Button(isLoupe ? String(localized: "Zoom Out") : String(localized: "Smaller Thumbnails")) { resize(larger: false) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!can { $0.mode == .grid || ($0.showsLoupePhoto && $0.loupeZoom.canZoomOut) })
            Button(menu?.state.showsOriginal == true ? String(localized: "Show Adjustments")
                                                      : String(localized: "Show Original")) {
                model?.editor.toggleOriginal()
            }
            .keyboardShortcut("\\", modifiers: [])
            .disabled(!canByKey { $0.canEditLoupePhoto && !$0.isCropping })
            // Mirrors the caption's toggle (section 11); review hides the strip.
            Button(menu?.state.showsFilmStrip == false ? String(localized: "Show Film Strip")
                                                       : String(localized: "Hide Film Strip")) {
                model?.showsFilmStrip.toggle()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
            .disabled(!can { $0.mode == .loupe && !$0.isReviewing })
            // A bare key: the video loupe's event monitor plays and pauses on
            // Space; the grid's Space opens the loupe (design.md N9, I6).
            Button(menu?.state.isVideoPlaying == true ? String(localized: "Pause") : String(localized: "Play")) {
                model?.playback.toggle()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!canByKey { $0.showsLoupeVideo })
            Divider()
            Button(menu?.state.showFileInfo == false ? String(localized: "Show File Names")
                                                     : String(localized: "Hide File Names")) {
                model?.showFileInfo.toggle()
            }
            .disabled(!can())
            Toggle("Group RAW+JPEG Pairs", isOn: Binding(
                get: { menu?.state.groupPairs ?? true },
                set: { model?.groupPairs = $0 }
            ))
            .disabled(!can())
            Button(menu?.state.showsHDR == false ? String(localized: "Show HDR Highlights")
                                                 : String(localized: "Hide HDR Highlights")) {
                model?.showsHDR.toggle()
            }
            .disabled(!can())
            // Rating, Flag and Sort By act on the grid; Clear Filter works in the loupe too.
            Menu("Filter") {
                RatingFilterPicker(rule: Binding(get: { menu?.state.ratingRule ?? .any },
                                                 set: { model?.ratingRule = $0 }))
                    .disabled(!can { $0.mode == .grid })
                FlagFilterPicker(rule: Binding(get: { menu?.state.flagRule ?? .any },
                                               set: { model?.flagRule = $0 }))
                    .disabled(!can { $0.mode == .grid })
                Divider()
                Button("Clear Filter") { model?.clearFilter() }
                    .disabled(!can { $0.isFiltered })
            }
            .disabled(!can())
            Menu("Sort By") {
                SortPickers(sort: Binding(get: { menu?.state.sort ?? LibrarySort() }, set: { model?.sort = $0 }))
            }
            .disabled(!can { $0.mode == .grid })
            Menu("Sidebar Sections") {
                ForEach(SidebarSection.allCases.filter(\.canHide), id: \.self) { section in
                    Toggle(section.title, isOn: Binding(
                        get: { menu?.state.hiddenSidebarSections.contains(section) != true },
                        set: { model?.setSidebarSection(section, shown: $0) }
                    ))
                }
            }
            .disabled(!can())
            Divider()
            if menu == nil, let importMenu {
                Button(importMenu.optionsTitle) { importMenu.toggleOptions() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            } else {
                Button(menu?.state.showsInspector == true ? String(localized: "Hide Inspector")
                                                          : String(localized: "Show Inspector")) {
                    model?.showsInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(!can())
            }
            // A checkmark on the tab shown while the inspector is (design.md I19).
            Toggle("Info", isOn: tabBinding(.info))
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(!can())
            Toggle("Adjust", isOn: tabBinding(.adjust))
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(!can())
            Divider()
        }
    }

    private var isLoupe: Bool { menu?.state.mode == .loupe }

    /// ⌘= / ⌘−: thumbnails in the grid, zoom steps in the loupe.
    private func resize(larger: Bool) {
        guard let model else { return }
        if model.mode == .loupe {
            NotificationCenter.default.post(name: .loupeShouldStepZoom, object: model,
                                            userInfo: [LoupeZoomStep.zoomInKey: larger])
        } else {
            model.resizeThumbnails(by: larger ? 1.2 : 1 / 1.2)
        }
    }

    private func show(_ tab: InspectorTab) {
        guard let model else { return }
        model.showsInspector = true
        model.inspectorTab = tab
    }

    // MARK: Photo

    private var photoCommands: some Commands {
        CommandMenu("Photo") {
            Menu("Rating") {
                Button("No Rating") { cull(.setRating(.unrated)) }
                    .keyboardShortcut("0", modifiers: [])
                ForEach(1...5, id: \.self) { stars in
                    Button(RatingText.stars(stars)) { cull(.setRating(Rating(clamping: stars))) }
                        .keyboardShortcut(KeyEquivalent(Character(String(stars))), modifiers: [])
                }
                Divider()
                Button("Raise Rating") { cull(.adjustRating(1)) }
                    .keyboardShortcut("]", modifiers: [])
                Button("Lower Rating") { cull(.adjustRating(-1)) }
                    .keyboardShortcut("[", modifiers: [])
            }
            .disabled(!canByKey { $0.hasTargets })
            Menu("Flag") {
                Button("Pick") { cull(.setFlag(.picked)) }
                    .keyboardShortcut("p", modifiers: [])
                Button("Reject") { cull(.setFlag(.rejected)) }
                    .keyboardShortcut("x", modifiers: [])
                Button("Clear Flag") { cull(.setFlag(.none)) }
                    .keyboardShortcut("u", modifiers: [])
            }
            .disabled(!canByKey { $0.hasTargets })
            Menu("Color Label") {
                ForEach(ColorLabel.allCases, id: \.self) { label in
                    Button(ColorLabelText.name(label)) { cull(.setColorLabel(label)) }
                        .keyboardShortcut(KeyEquivalent(Character(String(label.rawValue))), modifiers: .option)
                }
            }
            .disabled(!canByKey { $0.hasTargets })
            Toggle("Advance After Rating", isOn: Binding(
                get: { menu?.state.autoAdvance ?? false },
                set: { model?.autoAdvance = $0 }
            ))
            .disabled(!can())
            Divider()
            Button("Add Keywords…") { model?.beginKeywordEntry() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!can { $0.hasTargets })
            Button("Suggest Keywords") { model?.suggestKeywordsForTargets() }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(!can { $0.hasTargets })
            Menu("Add to Album") {
                ForEach(menu?.state.albums ?? []) { album in
                    Button(album.album.name) { model?.addToAlbum(album.id) }
                }
            }
            .disabled(!can { $0.hasTargets && !$0.albums.isEmpty })
            Button("Remove from Album") { model?.removeFromCurrentAlbum() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!canByKey { $0.hasTargets && $0.isInAlbum })
            Divider()
            // Checkmarks for the file the pairs show, mixed when they differ (design.md I14).
            Menu("RAW+JPEG Pair") {
                pairToggle(String(localized: "Show the RAW File"), raw: true)
                pairToggle(String(localized: "Show the JPEG or HEIC File"), raw: false)
            }
            .disabled(!can { $0.pairDisplay != nil })
        }
    }

    /// On while the inspector shows `tab`; choosing it shows that tab.
    private func tabBinding(_ tab: InspectorTab) -> Binding<Bool> {
        Binding(get: { menu?.state.showsInspector == true && menu?.state.inspectorTab == tab },
                set: { _ in show(tab) })
    }

    /// A RAW+JPEG Pair item. `Toggle(sources:)` is SwiftUI's only way to a
    /// mixed state: one source per state shown (on and off for mixed), and
    /// only the first one's setter acts, so a choice runs once.
    private func pairToggle(_ title: String, raw: Bool) -> some View {
        let display = can() ? menu?.state.pairDisplay : nil
        let values: [Bool] = switch display.map({ raw ? $0.raw : $0.companion }) {
        case .on: [true]
        case .mixed: [true, false]
        case .off, nil: [false]
        }
        let sources = values.enumerated().map { index, value in
            Binding(get: { value }, set: { _ in if index == 0 { model?.showPairFile(raw: raw) } })
        }
        return Toggle(sources: sources, isOn: \.self) { Text(title) }
    }

    /// Batch adjust commands: the grid's selected photos, or the loupe's photo
    /// outside a crop session.
    private func adjustsTargets(_ state: LibraryMenuState) -> Bool {
        state.mode == .grid ? state.targetsIncludePhoto : state.canEditLoupePhoto && !state.isCropping
    }

    private func cull(_ action: CullingAction) {
        model?.perform(action)
    }

    // MARK: Adjust

    private var adjustCommands: some Commands {
        CommandMenu("Adjust") {
            Button("Copy Adjustments") { model?.copyAdjustments() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!can { $0.focusedIsPhoto })
            Button("Paste Adjustments") { model?.pasteAdjustments() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!can { $0.hasCopiedAdjustments && $0.targetsIncludePhoto })
            Menu("Apply Preset") {
                ForEach(menu?.state.presetCollections ?? []) { collection in
                    if collection.name.isEmpty {
                        ForEach(collection.presets) { preset in
                            Button(preset.name) { model?.applyAdjustmentPreset(preset) }
                        }
                    } else {
                        Menu(collection.name) {
                            ForEach(collection.presets) { preset in
                                Button(preset.name) { model?.applyAdjustmentPreset(preset) }
                            }
                        }
                    }
                }
            }
            .disabled(!can { !$0.presetCollections.isEmpty && $0.targetsIncludePhoto })
            Divider()
            Button("Auto Exposure") { model?.autoExposure() }
                .disabled(!can(adjustsTargets))
            Button("Reset All Adjustments") { model?.resetAllAdjustments() }
                .disabled(!can { $0.canResetAll })
            Divider()
            Button(menu?.state.isCropping == true ? String(localized: "Finish Cropping") : String(localized: "Crop")) {
                model?.crop()
            }
            .keyboardShortcut("c", modifiers: [])
            .disabled(!canByKey { $0.mode == .grid ? $0.focusedIsPhoto : $0.canEditLoupePhoto })
            Button("Reset Crop") { model?.editor.resetCrop() }
                .disabled(!can { $0.canResetCrop })
            Button("Rotate Left") { model?.rotate(clockwise: false) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!can { $0.mode == .grid ? $0.targetsIncludePhoto : $0.canEditLoupePhoto })
            Button("Rotate Right") { model?.rotate(clockwise: true) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!can { $0.mode == .grid ? $0.targetsIncludePhoto : $0.canEditLoupePhoto })
            Menu("New Mask") {
                ForEach(MaskShapeKind.allCases, id: \.self) { kind in
                    Button(kind.title) { model?.editor.addMask(kind) }
                }
            }
            .disabled(!can { $0.canAddMask })
            // The Masks heading's eye button (design.md N7).
            Button(menu?.state.showsMaskOverlay == true ? String(localized: "Hide Mask Overlay")
                                                        : String(localized: "Show Mask Overlay")) {
                model?.editor.showsMaskOverlay.toggle()
            }
            .disabled(!can { $0.hasSelectedMask })
            // The two "see a mask in the loupe" items together (sharpen-mask-preview design §3).
            Button(menu?.state.showsSharpeningMap == true ? SharpeningMapText.menuTitle.hide
                                                          : SharpeningMapText.menuTitle.show) {
                model?.toggleSharpeningMap(from: .menu)
            }
            .disabled(!can { $0.canShowSharpeningMap })
            Divider()
            Button("Save Adjustments as Preset…") { model?.promptForAdjustmentPreset() }
                .disabled(!can { $0.canSaveAsPreset })
            Button("Import Presets…") { model?.chooseAdjustmentPresetImport() }
                .disabled(!can())
            Button("Manage Presets…") { model?.showsPresetSheet = true }
                .disabled(!can())
            // Preset items, then the look-up table items (design.md N5, D-Q4).
            Divider()
            Button("Import Look-Up Tables…") { model?.lookTableLibrary.chooseImportFromMenu() }
                .disabled(!can())
            Button("Browse Look-Up Tables…") { model?.showsLookTableSheet = true }
                .disabled(!can())
        }
    }
}
