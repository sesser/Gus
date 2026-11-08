import PhotoCore
import SwiftUI

/// What the menu bar reads from the library window. SwiftUI does not refresh
/// `Commands` built from a plain model value, so the window publishes this
/// value through `focusedSceneValue`: when it changes, the menus are rebuilt
/// with the new titles and enabled states. It is nil while another window
/// (Import, Settings) is focused.
struct LibraryMenuContext: Equatable {
    let model: LibraryModel
    let state: LibraryMenuState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.state == rhs.state
    }
}

/// The menu-relevant part of the model, compared to decide when the menus
/// change.
struct LibraryMenuState: Equatable {
    /// The library window is key with no sheet in front.
    var isWindowKey: Bool
    /// The grid, loupe or video loupe has the keyboard: bare keys act on photos.
    var browserHasKeyboard: Bool
    var mode: BrowserMode
    var itemCount: Int
    /// Culling and batch commands have photos to act on.
    var hasTargets: Bool
    /// Photos selected in the grid (Edit ▸ Deselect All needs two or more).
    var selectedCount: Int
    var hasFocusedItem: Bool
    /// The focused photo is not a video (Crop from the grid).
    var focusedIsPhoto: Bool
    /// Some of the photos a batch command would change are not videos.
    var targetsIncludePhoto: Bool
    /// The loupe shows a photo, not a video.
    var showsLoupePhoto: Bool
    /// The loupe shows a photo whose adjustments can be edited.
    var canEditLoupePhoto: Bool
    var isCropping: Bool
    /// Adjust ▸ Reset Crop: an editable loupe photo with a crop, or a crop
    /// session that has one.
    var canResetCrop: Bool
    /// Adjust ▸ New Mask ▸: an editable loupe photo, not cropping, under the
    /// mask limit.
    var canAddMask: Bool
    /// Adjust ▸ Show / Hide Mask Overlay: a mask is selected in the loupe.
    var hasSelectedMask: Bool
    /// Reset All Adjustments has something to reset. In the loupe: the photo's
    /// adjustments are not at their defaults. In the grid the items can't
    /// tell (their hash leaves out turned-off groups), so it is true.
    var canResetAll: Bool
    /// Save Adjustments as Preset… (`LibraryModel.canSaveAdjustmentPreset`).
    var canSaveAsPreset: Bool
    /// RAW+JPEG Pair ▸: which file the targeted pairs show; nil with no pair.
    var pairDisplay: PairDisplay?
    var showsMaskOverlay: Bool
    /// Adjust ▸ Show / Hide Sharpening Map: asked for, and can be shown
    /// (`LibraryModel.canShowSharpeningMap`).
    var showsSharpeningMap: Bool
    var canShowSharpeningMap: Bool
    /// The fringe map (chromatic-aberration design §6), `LibraryModel.canShowFringeMap`.
    var showsFringeMap: Bool
    var canShowFringeMap: Bool
    /// A tool is picking with the pixel magnifier, and its zoom.
    var isPixelMagnifierActive: Bool
    var pixelMagnifierLevel: PixelMagnifierLevel
    /// The map on screen says no sharpening is applied (design §7).
    var sharpeningMapNotApplied: Bool
    /// The loupe shows a video.
    var showsLoupeVideo: Bool
    /// The video loupe's player is playing (View ▸ Play / Pause's title).
    var isVideoPlaying: Bool
    var showsOriginal: Bool
    var loupeZoom: LoupeZoomState
    var showsInspector: Bool
    var isReviewing: Bool
    /// The loupe's film strip is on (review hides it without changing this).
    var showsFilmStrip: Bool
    var inspectorTab: InspectorTab
    var showFileInfo: Bool
    var groupPairs: Bool
    var showsHDR: Bool
    var autoAdvance: Bool
    var sort: LibrarySort
    var ratingRule: LibraryFilter.RatingRule
    var flagRule: LibraryFilter.FlagRule
    var isFiltered: Bool
    var hasCopiedAdjustments: Bool
    var presetCollections: [AdjustmentPresetCollection]
    var albums: [AlbumSummary]
    var isInAlbum: Bool
    var sidebarItem: SidebarItem?
    var isExporting: Bool
    /// File ▸ Stop's job (⌘.), nil when none runs.
    var stoppableJob: StoppableJob?
    /// File ▸ Export…, the toolbar's Export and the context menu's Export….
    var canExport: Bool
    var isCheckingDisk: Bool
    var hiddenSidebarSections: Set<SidebarSection>

    /// The album, smart album or keyword selected in the sidebar, for File ▸
    /// Rename, Delete and Edit Smart Album.
    enum SidebarItem: Equatable {
        case album(AlbumSummary)
        case smartAlbum(SmartAlbum)
        case keyword(KeywordSummary)

        /// Smart albums are renamed in their editor (Edit Smart Album…).
        var isRenamable: Bool {
            if case .smartAlbum = self { false } else { true }
        }

        var name: String {
            switch self {
            case .album(let album): album.album.name
            case .smartAlbum(let album): album.name
            case .keyword(let keyword): keyword.name
            }
        }
    }

    @MainActor
    init(_ model: LibraryModel) {
        isWindowKey = model.isWindowKey
        browserHasKeyboard = model.browserHasKeyboard
        mode = model.mode
        itemCount = model.itemCount
        hasTargets = !model.actionTargets.isEmpty
        selectedCount = model.selectedCount
        hasFocusedItem = model.focusedItem != nil
        focusedIsPhoto = model.focusedItem.map { !$0.isVideo } ?? false
        targetsIncludePhoto = model.actionTargets.contains { !model.items[$0].isVideo }
        showsLoupePhoto = model.mode == .loupe && model.focusedItem?.isVideo == false
        showsLoupeVideo = model.mode == .loupe && model.focusedItem?.isVideo == true
        isVideoPlaying = model.playback.isPlaying
        canEditLoupePhoto = showsLoupePhoto && model.editor.state == .ready
        isCropping = model.editor.cropSession != nil
        canResetCrop = canEditLoupePhoto && model.editor.canResetCrop
        canAddMask = canEditLoupePhoto && !isCropping && MaskLimits.canAddMask(to: model.editor.adjustments.local)
        canSaveAsPreset = model.canSaveAdjustmentPreset
        pairDisplay = PairDisplay(model.actionTargets.lazy.map { model.items[$0] })
        hasSelectedMask = canEditLoupePhoto && model.editor.selectedMaskID != nil
        canResetAll = model.mode == .grid ? targetsIncludePhoto
            : canEditLoupePhoto && !isCropping && !model.editor.adjustments.isDefault
        showsMaskOverlay = model.editor.showsMaskOverlay
        showsSharpeningMap = model.editor.showsSharpeningMap
        canShowSharpeningMap = model.canShowSharpeningMap
        showsFringeMap = model.editor.showsFringeMap
        canShowFringeMap = model.canShowFringeMap
        isPixelMagnifierActive = model.isPixelMagnifierActive
        pixelMagnifierLevel = model.pixelMagnifierLevel
        sharpeningMapNotApplied = model.editor.shownSharpeningMap?.isNotApplied ?? false
        showsOriginal = model.editor.showsOriginal
        loupeZoom = model.loupeZoom
        showsInspector = model.showsInspector
        isReviewing = model.isReviewing
        showsFilmStrip = model.showsFilmStrip
        inspectorTab = model.inspectorTab
        showFileInfo = model.showFileInfo
        groupPairs = model.groupPairs
        showsHDR = model.showsHDR
        autoAdvance = model.autoAdvance
        sort = model.sort
        ratingRule = model.ratingRule
        flagRule = model.flagRule
        isFiltered = model.isFiltered
        hasCopiedAdjustments = model.copiedAdjustments != nil
        presetCollections = model.adjustmentPresetCollections
        albums = model.albums
        isInAlbum = model.currentAlbumID != nil
        sidebarItem = switch model.sidebarSelection {
        case .album(let id): model.albums.first { $0.id == id }.map(SidebarItem.album)
        case .smartAlbum(let id): model.smartAlbums.first { $0.id == id }.map(SidebarItem.smartAlbum)
        case .keyword(let id): model.keywords.first { $0.id == id }.map(SidebarItem.keyword)
        default: nil
        }
        isExporting = model.export.isExporting
        stoppableJob = model.newestStoppableJob
        canExport = ExportTargets.canExport(model.actionTargets.lazy.map { model.items[$0] }, isExporting: isExporting)
        isCheckingDisk = model.isCheckingDisk
        hiddenSidebarSections = model.hiddenSidebarSections
    }

    /// Items with a bare key: only while the grid, loupe or video loupe has
    /// the keyboard, so a letter typed anywhere else never culls.
    var bareKeysActive: Bool { isWindowKey && browserHasKeyboard }
    /// Culling items (bare keys) with photos to act on.
    var canCull: Bool { bareKeysActive && hasTargets }
}

extension FocusedValues {
    @Entry var libraryMenu: LibraryMenuContext?
}

/// Publishes the menu context from a view of its own, so a change in the
/// menu state re-renders this view only.
struct LibraryMenuPublisher: View {
    let model: LibraryModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .focusedSceneValue(\.libraryMenu, LibraryMenuContext(model: model, state: LibraryMenuState(model)))
    }
}
