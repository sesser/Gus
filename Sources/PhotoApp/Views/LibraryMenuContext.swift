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
    var hasFocusedItem: Bool
    /// The loupe shows a photo, not a video.
    var showsLoupePhoto: Bool
    /// The loupe shows a photo whose adjustments can be edited.
    var canEditLoupePhoto: Bool
    var isCropping: Bool
    var showsOriginal: Bool
    var loupeShowsActualSize: Bool
    var showsInspector: Bool
    var inspectorTab: InspectorTab
    var showFileInfo: Bool
    var groupPairs: Bool
    var showsHDR: Bool
    var autoAdvance: Bool
    var sort: LibrarySort
    var isFiltered: Bool
    var hasCopiedAdjustments: Bool
    var presetCollections: [AdjustmentPresetCollection]
    var albums: [AlbumSummary]
    var isInAlbum: Bool
    var sidebarItem: SidebarItem?
    var isImporting: Bool
    var isExporting: Bool
    var isCheckingDisk: Bool

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
        hasFocusedItem = model.focusedItem != nil
        showsLoupePhoto = model.mode == .loupe && model.focusedItem?.isVideo == false
        canEditLoupePhoto = showsLoupePhoto && model.editor.state == .ready
        isCropping = model.editor.cropSession != nil
        showsOriginal = model.editor.showsOriginal
        loupeShowsActualSize = model.loupeShowsActualSize
        showsInspector = model.showsInspector
        inspectorTab = model.inspectorTab
        showFileInfo = model.showFileInfo
        groupPairs = model.groupPairs
        showsHDR = model.showsHDR
        autoAdvance = model.autoAdvance
        sort = model.sort
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
        isImporting = model.isImporting
        isExporting = model.export.isExporting
        isCheckingDisk = model.isCheckingDisk
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
