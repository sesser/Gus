import AppKit
import Observation
import PhotoCore
import PhotoUI
import os

/// Receives changes to the browser's item list. The grid uses this instead of
/// SwiftUI diffing so that a rating change touches one cell, not 50k.
@MainActor
protocol LibraryItemsObserver: AnyObject {
    /// The list was replaced (filter, scope or import).
    func libraryItemsReloaded()
    /// Items changed in place (culling values, edits).
    func libraryItemsChanged(at indices: IndexSet)
    /// Focus or selection was moved by something other than the grid itself.
    func libraryFocusChanged()
    /// Volumes came or went.
    func libraryAvailabilityChanged()
}

enum SidebarSelection: Hashable {
    case allPhotos
    case builtIn(BuiltInAlbum)
    case year(Int)
    case month(year: Int, month: Int)
    case project(Int64)
    case album(Int64)
    case smartAlbum(Int64)
    case keyword(Int64)
    /// Photos whose sidecar or file another app changed.
    case changedOnDisk
}

/// The loupe's zoom as the menus see it.
struct LoupeZoomState: Equatable {
    /// Zoomed in rather than fitted (`Z` then zooms to fit).
    var isZoomed = false
    var canZoomIn = false
    var canZoomOut = false
    /// Exactly 100 % (the toolbar's Fit / 100% shows neither at other steps).
    var isActualSize = false
}

extension SidebarSelection {
    /// Names the source in user defaults ("album:12"): the restored selection
    /// and each source's filter and sort.
    var storageKey: String {
        switch self {
        case .allPhotos: "all"
        case .builtIn(let album): "builtIn:\(album.rawValue)"
        case .year(let year): "year:\(year)"
        case .month(let year, let month): "month:\(year)-\(month)"
        case .project(let id): "project:\(id)"
        case .album(let id): "album:\(id)"
        case .smartAlbum(let id): "smartAlbum:\(id)"
        case .keyword(let id): "keyword:\(id)"
        case .changedOnDisk: "changedOnDisk"
        }
    }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        switch parts.first {
        case "all": self = .allPhotos
        case "changedOnDisk": self = .changedOnDisk
        case "builtIn": guard let album = BuiltInAlbum(rawValue: value) else { return nil }; self = .builtIn(album)
        case "year": guard let year = Int(value) else { return nil }; self = .year(year)
        case "month":
            let numbers = value.split(separator: "-").compactMap { Int($0) }
            guard numbers.count == 2 else { return nil }
            self = .month(year: numbers[0], month: numbers[1])
        case "project": guard let id = Int64(value) else { return nil }; self = .project(id)
        case "album": guard let id = Int64(value) else { return nil }; self = .album(id)
        case "smartAlbum": guard let id = Int64(value) else { return nil }; self = .smartAlbum(id)
        case "keyword": guard let id = Int64(value) else { return nil }; self = .keyword(id)
        default: return nil
        }
    }
}

/// The sidebar's sections, in order (section 3 of docs/UI_REDESIGN.md).
enum SidebarSection: String, CaseIterable, Hashable {
    case library, albums, dates, keywords, projects

    var title: String {
        switch self {
        case .library: String(localized: "Library")
        case .albums: String(localized: "Albums")
        case .dates: String(localized: "Dates")
        case .keywords: String(localized: "Keywords")
        case .projects: String(localized: "Projects")
        }
    }

    /// Library cannot be hidden.
    var canHide: Bool { self != .library }
}

extension LibraryModel {
    func showsSidebarSection(_ section: SidebarSection) -> Bool {
        !hiddenSidebarSections.contains(section)
    }

    /// View ▸ Sidebar Sections and the section header's Hide Section.
    func setSidebarSection(_ section: SidebarSection, shown: Bool) {
        guard section.canHide else { return }
        if shown { hiddenSidebarSections.remove(section) } else { hiddenSidebarSections.insert(section) }
    }
}

/// The smart albums every library has.
enum BuiltInAlbum: String, CaseIterable, Hashable {
    case lastImport, picks, rejects, unrated, noKeywords

    /// Rules for the rule-based ones; Last Import is an import run instead.
    var rules: SmartAlbumRules? {
        let rule: SmartRule? = switch self {
        case .lastImport: nil
        case .picks: SmartRule(field: .flag, comparison: .equals, value: RuleValue(text: "picked"))
        case .rejects: SmartRule(field: .flag, comparison: .equals, value: RuleValue(text: "rejected"))
        case .unrated: SmartRule(field: .rating, comparison: .equals, value: RuleValue(number: 0))
        case .noKeywords: SmartRule(field: .hasKeywords, comparison: .isFalse)
        }
        return rule.map { SmartAlbumRules(match: .all, rules: [$0]) }
    }
}

enum BrowserMode: Hashable {
    case grid
    case loupe
}

/// What the right-hand panel shows.
enum InspectorTab: String, Hashable {
    case info
    case adjust
}

/// State of the library window: what is shown, what is selected, and the work in
/// flight (imports, preview warming, catalog writes).
@MainActor
@Observable
final class LibraryModel {
    let locations: LibraryLocations
    let catalog: Catalog
    let importer: Importer
    let previews: PreviewService
    let suggester: any KeywordSuggester = VisionKeywordSuggester()
    let sidecars: SidecarSync
    let cardImport: CardImportModel
    let editor = AdjustmentEditor()
    /// Catalog writes in the order they were made, and the rule for reads
    /// whose results must agree with them (`persist`, `WriteChain.read`).
    let writes = WriteChain()
    let lookTableLibrary = LookTableLibraryModel()
    let presetPreviews = PresetPreviewModel()
    let export = ExportModel()
    /// The video loupe's player (View ▸ Play / Pause).
    let playback = VideoPlayback()
    /// Adjustments taken by Copy Adjustments.
    var copiedAdjustments: Adjustments?
    var adjustmentPresets: [AdjustmentPreset] = []
    let lookTables: LookTableStore

    // MARK: Sidebar and filters

    private(set) var projects: [ProjectSummary] = []
    private(set) var libraryCount = 0
    /// Every keyword with its photo count, for the sidebar and autocomplete.
    var keywords: [KeywordSummary] = []
    /// Bumped whenever keyword assignments may have changed.
    var keywordRevision = 0
    /// Bumped after descriptive fields (title, copyright, contact…) are written.
    var descriptionRevision = 0
    /// Bumped when new suggestions are stored or their state changes.
    var suggestionRevision = 0
    /// Background keyword analysis in progress.
    var suggestionProgress: (done: Int, total: Int)? {
        didSet { if (oldValue == nil) != (suggestionProgress == nil) { suggestionStarted = suggestionProgress == nil ? nil : Date() } }
    }
    var albums: [AlbumSummary] = []
    var smartAlbums: [SmartAlbum] = []
    var captureMonths: [CaptureMonth] = []
    var lastImportRunID: Int64?
    /// Photo counts for built-in and smart albums.
    var sidebarCounts: [SidebarSelection: Int] = [:]
    /// A sheet asked for by the sidebar or a menu command.
    var sidebarSheet: SidebarSheet?
    /// Photos whose sidecar or file another app changed, waiting for review.
    var diskChangeCount = 0
    /// Bumped when outside changes are found or settled.
    var diskChangeRevision = 0
    var isCheckingDisk = false
    /// Set when a card mounts and the import window should open for it.
    var requestsImportWindow = false
    /// A mounted card, named in the empty library's Import button.
    private(set) var mountedCardName: String?
    /// The look-up table browser sheet is up on the library window.
    var showsLookTableSheet = false
    /// The preset manager sheet is up on the library window.
    var showsPresetSheet = false
    /// Set to open the export window (the menu command and debug scripts).
    /// The Export sheet is up on the library window.
    var showsExportSheet = false
    /// What the last preset import did, shown in an alert.
    var presetImportSummary: PresetImportSummary?
    /// Open the import window when a card is inserted (Settings).
    var opensImportOnCard: Bool {
        didSet { UserDefaults.standard.set(opensImportOnCard, forKey: Self.opensImportOnCardKey) }
    }
    /// Write XMP sidecars when photos change (Settings).
    var writesSidecars: Bool {
        didSet {
            UserDefaults.standard.set(writesSidecars, forKey: Self.writesSidecarsKey)
            if writesSidecars { scheduleSidecarSync() }
        }
    }

    /// Remembered across launches; each source keeps its own filter and sort.
    var sidebarSelection: SidebarSelection = .allPhotos {
        didSet {
            guard oldValue != sidebarSelection else { return }
            UserDefaults.standard.set(sidebarSelection.storageKey, forKey: Self.sidebarSelectionKey)
            applySourceSettings()
            reloadItems(keepFocus: false)
        }
    }
    var ratingRule: LibraryFilter.RatingRule = .any {
        didSet {
            guard oldValue != ratingRule else { return }
            saveSourceSettings()
            reloadItems(keepFocus: true)
        }
    }
    var flagRule: LibraryFilter.FlagRule = .any {
        didSet {
            guard oldValue != flagRule else { return }
            saveSourceSettings()
            reloadItems(keepFocus: true)
        }
    }

    /// The toolbar's search field; reloads a moment after typing stops.
    var searchText = "" {
        didSet {
            if oldValue != searchText { saveSourceSettings() }
            guard LibraryFilter(search: oldValue).searchTerms != LibraryFilter(search: searchText).searchTerms,
                  !isApplyingSourceSettings else { return }
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                reloadItems(keepFocus: true)
            }
        }
    }
    var sort: LibrarySort {
        didSet {
            guard oldValue != sort else { return }
            // The last sort chosen is the default for sources without one.
            if !isApplyingSourceSettings {
                UserDefaults.standard.set(sort.key.rawValue, forKey: Self.sortKeyKey)
                UserDefaults.standard.set(sort.ascending, forKey: Self.sortAscendingKey)
            }
            saveSourceSettings()
            reloadItems(keepFocus: true)
        }
    }

    var filter: LibraryFilter {
        LibraryFilter(scope: scope(for: sidebarSelection), rating: ratingRule, flag: flagRule, search: searchText,
                      sort: sort, groupsPairs: groupPairs)
    }

    @ObservationIgnored private let sourceSettings = SourceViewSettingsStore()
    @ObservationIgnored private var isApplyingSourceSettings = false

    /// The default sort for a source with no settings: the last one chosen.
    private var defaultSort: LibrarySort {
        let defaults = UserDefaults.standard
        return LibrarySort(key: defaults.string(forKey: Self.sortKeyKey).flatMap(LibrarySort.Key.init(rawValue:)) ?? .captureDate,
                           ascending: defaults.object(forKey: Self.sortAscendingKey) as? Bool ?? true)
    }

    /// Takes the selected source's filter and sort (one reload follows).
    private func applySourceSettings() {
        let settings = sourceSettings.settings(for: sidebarSelection.storageKey, defaultSort: defaultSort)
        isApplyingSourceSettings = true
        defer { isApplyingSourceSettings = false }
        ratingRule = settings.rating
        flagRule = settings.flag
        searchText = settings.search
        sort = settings.sort
    }

    private func saveSourceSettings() {
        guard !isApplyingSourceSettings else { return }
        sourceSettings.save(SourceViewSettings(rating: ratingRule, flag: flagRule, search: searchText, sort: sort),
                            for: sidebarSelection.storageKey, defaultSort: defaultSort)
    }

    func clearFilter() {
        ratingRule = .any
        flagRule = .any
        searchText = ""
    }

    func scope(for selection: SidebarSelection) -> LibraryFilter.Scope {
        switch selection {
        case .allPhotos: .allPhotos
        case .builtIn(let album):
            if let rules = album.rules {
                .rules(rules, projectID: nil)
            } else {
                .importRun(lastImportRunID ?? -1)
            }
        case .year(let year):
            .captureDays(start: String(format: "%04d-01-01", year), end: String(format: "%04d-01-01", year + 1))
        case .month(let year, let month):
            Self.monthScope(year: year, month: month)
        case .project(let id): .project(id)
        case .album(let id): .album(id)
        case .smartAlbum(let id): smartAlbums.first { $0.id == id }?.scope ?? .album(-1)
        case .keyword(let id): .keyword(id)
        case .changedOnDisk: .changedOnDisk
        }
    }

    private static func monthScope(year: Int, month: Int) -> LibraryFilter.Scope {
        let days = CaptureMonth(year: year, month: month, count: 0).days
        return .captureDays(start: days.start, end: days.end)
    }

    var isFiltered: Bool {
        ratingRule != .any || flagRule != .any || !LibraryFilter(search: searchText).searchTerms.isEmpty
    }

    /// What the loupe's Adjust tab shows. The video loupe replaces the photo
    /// loupe, which leaves the editor idle, so a focused video decides.
    var loupeAdjustState: AdjustmentEditor.State {
        focusedItem?.isVideo == true ? .video : editor.state
    }

    /// What the browser shows instead of the grid, nil while it has photos.
    var emptyState: EmptySourceState? {
        let kind: EmptySourceState.SourceKind = switch sidebarSelection {
        case .album: .album
        case .smartAlbum: .smartAlbum
        default: .other
        }
        return EmptySourceState.resolve(shownCount: itemCount, libraryCount: libraryCount, isFiltered: isFiltered,
                                        source: kind)
    }

    // MARK: Items, focus, selection

    /// Not observed: the grid and the film strip are told about changes
    /// through `LibraryItemsObserver`.
    @ObservationIgnored private(set) var items: [CatalogItem] = []
    @ObservationIgnored private var indexByVersionID: [Int64: Int] = [:]
    /// Observed stand-in for `items` for SwiftUI views (counts, titles).
    private(set) var itemsRevision = 0
    private(set) var focusIndex: Int?
    @ObservationIgnored private(set) var selection = IndexSet()
    /// Observed stand-in for `selection`, which is not observed.
    private(set) var selectionRevision = 0
    var mode: BrowserMode = .grid
    /// The library window is key: no sheet or other window is in front.
    private(set) var isWindowKey = false
    /// The grid, the loupe or the video loupe has the keyboard, so the bare
    /// culling keys act on photos (section 6 of docs/UI_REDESIGN.md).
    private(set) var browserHasKeyboard = false
    @ObservationIgnored private(set) lazy var windowObserver: LibraryWindowObserver = {
        let observer = LibraryWindowObserver { [weak self] isKey, browser in
            guard let self else { return }
            if isWindowKey != isKey { isWindowKey = isKey }
            if browserHasKeyboard != browser { browserHasKeyboard = browser }
        }
        // Leaving full screen by a system route ends review; the window
        // stays out of full screen.
        observer.onDidExitFullScreen = { [weak self] in self?.exitReview(restoringFullScreen: false) }
        return observer
    }()
    @ObservationIgnored private var searchFocusPending = false
    /// The folder being added, for Activity's "Add Folder “…”".
    @ObservationIgnored private var batchFolderName: String?
    /// Sections hidden with View ▸ Sidebar Sections, remembered.
    var hiddenSidebarSections: Set<SidebarSection> = Set(
        (UserDefaults.standard.stringArray(forKey: "sidebar.hiddenSections") ?? []).compactMap(SidebarSection.init(rawValue:))
    ) {
        didSet { UserDefaults.standard.set(hiddenSidebarSections.map(\.rawValue).sorted(), forKey: "sidebar.hiddenSections") }
    }
    /// A sidebar item waiting for its deletion to be confirmed.
    var sidebarDeletion: SidebarDeletion?
    /// What the menus need of the loupe's zoom (its controller owns the zoom).
    var loupeZoom = LoupeZoomState()
    /// The open ⌘K keyword field, with the photos it will tag.
    var keywordEntry: KeywordEntryRequest?
    /// Masking's row should scroll into view once the inspector shows it
    /// (showing the sharpening map from a menu; design §3).
    var revealsMaskingRow = false
    /// The Lens heading's Color Fringes group should scroll into view
    /// (Show Fringe Map from the menu, chromatic-aberration design §6).
    var revealsFringeRow = false
    var showsInspector: Bool {
        // Review hides it for a while; the person's choice is what's kept.
        didSet { if !review.isReviewing { UserDefaults.standard.set(showsInspector, forKey: Self.showsInspectorKey) } }
    }
    /// The sidebar column (the split view's visibility).
    var showsSidebar = true
    /// Review mode (View ▸ Enter Review, F) and the layout it goes back to.
    var review = ReviewSession()
    /// The inspector's tab, remembered separately for the grid and the loupe.
    var inspectorTab: InspectorTab {
        get { mode == .loupe ? loupeInspectorTab : gridInspectorTab }
        set {
            if mode == .loupe { loupeInspectorTab = newValue } else { gridInspectorTab = newValue }
        }
    }
    private var gridInspectorTab: InspectorTab {
        didSet { UserDefaults.standard.set(gridInspectorTab.rawValue, forKey: Self.gridInspectorTabKey) }
    }
    private var loupeInspectorTab: InspectorTab {
        didSet { UserDefaults.standard.set(loupeInspectorTab.rawValue, forKey: Self.loupeInspectorTabKey) }
    }

    var focusedItem: CatalogItem? {
        _ = itemsRevision
        guard let focusIndex, items.indices.contains(focusIndex) else { return nil }
        return items[focusIndex]
    }

    var itemCount: Int {
        _ = itemsRevision
        return items.count
    }

    // MARK: Preferences

    var thumbnailSize: Double {
        didSet { UserDefaults.standard.set(thumbnailSize, forKey: Self.thumbnailSizeKey) }
    }
    var autoAdvance: Bool {
        didSet { UserDefaults.standard.set(autoAdvance, forKey: Self.autoAdvanceKey) }
    }
    /// File name and type badge under each thumbnail.
    var showFileInfo: Bool {
        didSet { UserDefaults.standard.set(showFileInfo, forKey: Self.showFileInfoKey) }
    }
    /// The loupe shows highlights above SDR white on displays with extended
    /// dynamic range.
    var showsHDR: Bool {
        didSet { UserDefaults.standard.set(showsHDR, forKey: Self.showsHDRKey) }
    }
    /// Headroom of the HDR image the loupe is showing (brightest value relative to
    /// SDR white), or nil while it shows an SDR image.
    var loupeHDRHeadroom: Float?
    /// One item per RAW+JPEG pair instead of both files.
    var groupPairs: Bool {
        didSet {
            guard oldValue != groupPairs else { return }
            UserDefaults.standard.set(groupPairs, forKey: Self.groupPairsKey)
            reloadItems(keepFocus: true)
            Task {
                await refreshProjects()
                await refreshKeywords()
            }
        }
    }
    /// The loupe's film strip is shown (when not reviewing).
    var showsFilmStrip: Bool {
        didSet { UserDefaults.standard.set(showsFilmStrip, forKey: Self.showsFilmStripKey) }
    }
    /// The film strip's thumbnail step, separate from the grid's size
    /// (`FilmStripGeometry.steps`).
    var filmStripSize: Double {
        didSet { UserDefaults.standard.set(filmStripSize, forKey: Self.filmStripSizeKey) }
    }
    static let thumbnailSizeRange = 80.0...360.0
    private static let thumbnailSizeKey = "browser.thumbnailSize"
    private static let autoAdvanceKey = "culling.autoAdvance"
    private static let showFileInfoKey = "browser.showFileInfo"
    private static let groupPairsKey = "browser.groupPairs"
    private static let showsHDRKey = "loupe.showsHDR"
    private static let showsFilmStripKey = "loupe.showsFilmStrip"
    private static let filmStripSizeKey = "loupe.filmStripSize"
    private static let showsInspectorKey = "browser.showsInspector"
    private static let gridInspectorTabKey = "browser.inspectorTab"
    private static let loupeInspectorTabKey = "loupe.inspectorTab"
    private static let writesSidecarsKey = "sidecars.write"
    private static let opensImportOnCardKey = "import.openOnCard"
    private static let sidebarSelectionKey = "sidebar.selection"
    private static let sortKeyKey = "browser.sortKey"
    private static let sortAscendingKey = "browser.sortAscending"

    // MARK: Background work

    private(set) var importProgress: ImportProgress? {
        didSet { if (oldValue == nil) != (importProgress == nil) { importStarted = importProgress == nil ? nil : Date() } }
    }
    /// When the running batch of folder adds started (File ▸ Stop).
    @ObservationIgnored private(set) var importStarted: Date?
    /// The folder being imported, while a batch of several runs.
    private(set) var importBatch: ImportBatchPosition?
    /// Folders from Finder are being dragged over the browser.
    var isFolderDropTargeted = false
    private(set) var warming: (done: Int, total: Int)? {
        didSet { if (oldValue == nil) != (warming == nil) { warmingStarted = warming == nil ? nil : Date() } }
    }
    /// The newest Activity message (debug scripts).
    var statusMessage: String? { activity.messages.last?.text }
    /// Messages for the toolbar's Activity popover, the 20 newest until quit.
    private(set) var activity = ActivityLog()

    /// Posts a message to Activity, and has VoiceOver say it (medium
    /// priority). `action` titles the row: the undo name of the action, or the
    /// command and its object (`ActivityTitle`). `warning`: the person asked for
    /// something that did not happen and can make it happen by acting; anything
    /// expected (completions, cancellations, videos skipped) is information.
    func report(_ text: String, action: String, warning: Bool = false) {
        report(text, action: action, warning: warning, announcing: text)
    }

    /// Posts to Activity; VoiceOver hears `announcing`, such as a long
    /// message's first sentence.
    func report(_ text: String, action: String, warning: Bool, announcing: String) {
        activity.post(text, title: action, isWarning: warning)
        AccessibilityText.announce(announcing, priority: .medium)
    }
    /// Photos in the selected source before rating, flag and search.
    private(set) var sourceTotal: Int?
    /// When rendering previews and suggesting keywords started: the Activity
    /// item shows them only after `ActivityLog.backgroundDelay`.
    @ObservationIgnored private(set) var warmingStarted: Date? {
        didSet { if warmingStarted != nil { scheduleActivityTick() } }
    }
    @ObservationIgnored private(set) var suggestionStarted: Date? {
        didSet { if suggestionStarted != nil { scheduleActivityTick() } }
    }
    /// Bumped when a background job passes its delay, to show it.
    private(set) var activityTick = 0
    /// Batch Auto Exposure measuring the grid's selection.
    private(set) var batchAutoProgress: (done: Int, total: Int)?
    /// The command a batch measurement runs for (Paste Adjustments, Apply
    /// Preset …, measuring color alignment); nil for Auto Exposure.
    private(set) var batchAutoTitle: String?
    /// `batchAutoTitle` fitted to the toolbar (a long preset name shortened in the middle).
    private(set) var batchAutoToolbarTitle: String?
    @ObservationIgnored var batchAutoTask: Task<Void, Never>?

    private func scheduleActivityTick() {
        Task {
            try? await Task.sleep(for: .seconds(ActivityLog.backgroundDelay))
            activityTick += 1
        }
    }

    /// The Activity popover was opened.
    func markActivitySeen() {
        activity.markSeen()
    }

    func setBatchAutoProgress(_ progress: (done: Int, total: Int)?, title: String? = nil, toolbarTitle: String? = nil) {
        batchAutoProgress = progress
        batchAutoTitle = progress == nil ? nil : title
        batchAutoToolbarTitle = progress == nil ? nil : toolbarTitle
    }
    private(set) var onlineVolumeIDs: Set<Int64> = []

    /// The grid and the loupe's film strip, held weakly (`addObserver`).
    @ObservationIgnored private var itemsObservers: [WeakItemsObserver] = []
    /// Held while the library is open, so command-line writes refuse instead of
    /// changing the catalog behind the window's back (`LibraryLock`).
    @ObservationIgnored private var libraryLock: LibraryLock?
    @ObservationIgnored private var volumesByID: [Int64: VolumeRecord] = [:]
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var importQueue = FolderImportQueue()
    /// Items dropped during the current batch that were not folders.
    @ObservationIgnored private var ignoredDropCount = 0
    /// Counts folder imports, so late progress reports of an earlier one are dropped.
    @ObservationIgnored private var importGeneration = 0
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    /// Undo for changes to photos and keywords. The grid and loupe answer
    /// undo:/redo: with it, so text fields keep their own undo.
    @ObservationIgnored var undoManager = UndoManager()
    @ObservationIgnored private var lastLiveRefresh = Date.distantPast
    @ObservationIgnored private(set) var started = false
    /// Times the loupe canvas refitted to a new frame (debug scripts check a
    /// film strip change refits it once).
    @ObservationIgnored var loupeFitCount = 0
    @ObservationIgnored private var volumeObservers: [any NSObjectProtocol] = []
    @ObservationIgnored var pendingAnalysis: [Int64] = []
    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var sidebarRefreshTask: Task<Void, Never>?
    @ObservationIgnored var sidecarSyncTask: Task<Void, Never>?
    @ObservationIgnored var sidecarSyncPending = false
    @ObservationIgnored var diskCheckTask: Task<Void, Never>?
    /// Version ids being dragged from the grid, for drops on the sidebar.
    @ObservationIgnored var draggedVersionIDs: [Int64] = []
    @ObservationIgnored var analysisTask: Task<Void, Never>?

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "library")

    init(locations: LibraryLocations, catalog: Catalog, importer: Importer, previews: PreviewService,
         lookTables: LookTableStore) {
        self.locations = locations
        self.catalog = catalog
        self.importer = importer
        self.previews = previews
        self.lookTables = lookTables
        let defaults = UserDefaults.standard
        let size = defaults.double(forKey: Self.thumbnailSizeKey)
        thumbnailSize = Self.thumbnailSizeRange.contains(size) ? size : 180
        autoAdvance = defaults.bool(forKey: Self.autoAdvanceKey)
        showFileInfo = defaults.object(forKey: Self.showFileInfoKey) as? Bool ?? true
        groupPairs = defaults.object(forKey: Self.groupPairsKey) as? Bool ?? true
        showsHDR = defaults.object(forKey: Self.showsHDRKey) as? Bool ?? true
        showsFilmStrip = defaults.object(forKey: Self.showsFilmStripKey) as? Bool ?? true
        filmStripSize = FilmStripGeometry.validatedSize(defaults.object(forKey: Self.filmStripSizeKey) as? Double)
        showsInspector = defaults.bool(forKey: Self.showsInspectorKey)
        gridInspectorTab = defaults.string(forKey: Self.gridInspectorTabKey).flatMap(InspectorTab.init(rawValue:)) ?? .info
        loupeInspectorTab = defaults.string(forKey: Self.loupeInspectorTabKey).flatMap(InspectorTab.init(rawValue:))
            ?? .adjust
        writesSidecars = defaults.object(forKey: Self.writesSidecarsKey) as? Bool ?? true
        sort = LibrarySort(key: defaults.string(forKey: Self.sortKeyKey).flatMap(LibrarySort.Key.init(rawValue:)) ?? .captureDate,
                           ascending: defaults.object(forKey: Self.sortAscendingKey) as? Bool ?? true)
        // The source selected last time, with its filter and sort (checked
        // against the catalog once projects, albums and keywords are loaded).
        if let restored = defaults.string(forKey: Self.sidebarSelectionKey).flatMap(SidebarSelection.init(storageKey:)) {
            sidebarSelection = restored
        }
        sidecars = SidecarSync(catalog: catalog, metadataReader: importer.metadataReader)
        cardImport = CardImportModel(metadataReader: importer.metadataReader, presets: catalog)
        opensImportOnCard = defaults.object(forKey: Self.opensImportOnCardKey) as? Bool ?? true
        cardImport.library = self
        applySourceSettings()
        editor.library = self
        lookTableLibrary.library = self
        presetPreviews.library = self
        export.library = self
    }

    /// Opens the catalog at the standard location (or `--library-root`).
    static func open(options: LaunchOptions = .current) throws -> LibraryModel {
        // AppLauncher quits on a refused launch before the app exists; this
        // only stops a future caller from reaching the standard library.
        if case .refused(let reason, _) = LibraryLaunchGuard.current(options: options) {
            preconditionFailure(LibraryLaunchGuard.diagnostic(for: reason))
        }
        let locations: LibraryLocations
        if let root = options.libraryRoot {
            locations = .rooted(at: root)
        } else {
            try DataDirectoryMigrator.migrateStandardLocations()
            locations = try .standard()
        }
        try locations.createDirectories()
        // A command-line write holds the lock for moments only. If another
        // process keeps it (a second copy of the app), open anyway, as before.
        let lock: LibraryLock?
        do {
            lock = try LibraryLock.acquire(locations, timeout: .seconds(2))
        } catch {
            log.warning("Library lock not taken: \(String(describing: error), privacy: .public)")
            lock = nil
        }
        let catalog = try Catalog.open(at: locations.catalogFileURL)
        let importer = Importer(catalog: catalog, metadataReader: MetadataReaders.makeDefault())
        let lookTables = LookTableStore(locations: locations)
        let generator = PreviewGenerator(renderer: AdjustmentRenderer(lookTables: lookTables))
        let previews = PreviewService(cacheDirectory: locations.previewCacheDirectory, catalog: catalog,
                                      generator: generator)
        previews.cache.removeObsoletePipelineVersions()
        let model = LibraryModel(locations: locations, catalog: catalog, importer: importer, previews: previews,
                                 lookTables: lookTables)
        model.libraryLock = lock
        return model
    }

    func start() async {
        guard !started else { return }
        started = true
        observeVolumes()
        await refreshVolumes()
        await refreshProjects()
        await refreshKeywords()
        reloadItems(keepFocus: false)
        scheduleSidecarSync()
        await refreshAdjustmentPresets()
        await lookTableLibrary.reload()
        let lookTables = self.lookTables
        Task.detached(priority: .utility) { lookTables.installBuiltIns() }
        await refreshDiskChanges()
        // Changes other apps made while this one was not running.
        checkForDiskChanges(delay: .seconds(5))
    }

    // MARK: Loading

    /// Reloads the list. With `keepFocus` the focused version stays focused, or
    /// `focusVersionID` when given (for instance the other half of a pair, after
    /// switching which file represents it).
    func reloadItems(keepFocus: Bool, focusVersionID: Int64? = nil) {
        reloadTask?.cancel()
        let filter = self.filter
        let catalog = self.catalog
        let focusID = focusVersionID ?? (keepFocus ? focusedItem?.versionID : nil)
        reloadTask = Task {
            do {
                // Through the write chain: a row read before a queued write
                // would otherwise put the old values (an edit's hash, a
                // rating shown before its write) back on screen.
                let items = try await writes.read {
                    try await catalog.libraryItems(matching: filter)
                } apply: { items in
                    apply(items, focusVersionID: focusID)
                }
                // For "87 of 4,623 · Filtered".
                if isFiltered {
                    var whole = filter
                    whole.rating = .any
                    whole.flag = .any
                    whole.search = ""
                    let total = try? await catalog.itemCount(matching: whole)
                    guard !Task.isCancelled else { return }
                    sourceTotal = total
                } else {
                    sourceTotal = items.count
                }
            } catch is CancellationError {
            } catch {
                Self.log.error("Loading items failed: \(error.localizedDescription, privacy: .public)")
                report(String(localized: "Could not load photos: \(error.localizedDescription)"), action: ActivityTitle.loadLibrary,
                       warning: true)
            }
        }
    }

    private func apply(_ newItems: [CatalogItem], focusVersionID: Int64?) {
        items = newItems
        indexByVersionID = Dictionary(newItems.enumerated().map { ($1.versionID, $0) }, uniquingKeysWith: { first, _ in first })
        if let focusVersionID, let index = indexByVersionID[focusVersionID] {
            focusIndex = index
        } else {
            focusIndex = newItems.isEmpty ? nil : 0
        }
        selection = focusIndex.map { IndexSet(integer: $0) } ?? []
        selectionRevision += 1
        if items.isEmpty { mode = .grid }
        itemsRevision += 1
        notifyObservers { $0.libraryItemsReloaded() }
    }

    func refreshProjects() async {
        do {
            projects = try await catalog.projectSummaries(groupingPairs: groupPairs)
            libraryCount = try await catalog.versionCount(groupingPairs: groupPairs)
        } catch {
            Self.log.error("Loading projects failed: \(error.localizedDescription, privacy: .public)")
        }
        if case .project(let id) = sidebarSelection, !projects.contains(where: { $0.id == id }) {
            sidebarSelection = .allPhotos
        }
        scheduleSidebarRefresh()
    }

    /// Albums, smart albums, dates and their counts, a moment after the last
    /// change (culling while a filter-like album is open changes many counts).
    func scheduleSidebarRefresh() {
        sidebarRefreshTask?.cancel()
        sidebarRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refreshSidebar()
        }
    }

    func refreshSidebar() async {
        let catalog = self.catalog
        let grouped = groupPairs
        do {
            albums = try await catalog.albumSummaries(groupingPairs: grouped)
            smartAlbums = try await catalog.smartAlbums()
            captureMonths = try await catalog.captureMonths(groupingPairs: grouped)
            let lastRun = try await catalog.lastImportRun()?.id
            if lastRun != lastImportRunID {
                lastImportRunID = lastRun
                if sidebarSelection == .builtIn(.lastImport) { reloadItems(keepFocus: true) }
            }
            var counts: [SidebarSelection: Int] = [:]
            let selections = BuiltInAlbum.allCases.map(SidebarSelection.builtIn) + smartAlbums.map { .smartAlbum($0.id) }
            for selection in selections {
                counts[selection] = try await catalog.itemCount(matching: LibraryFilter(scope: scope(for: selection),
                                                                                        groupsPairs: grouped))
            }
            sidebarCounts = counts
        } catch {
            Self.log.error("Loading the sidebar failed: \(error.localizedDescription, privacy: .public)")
        }
        switch sidebarSelection {
        case .album(let id) where !albums.contains { $0.id == id }: sidebarSelection = .allPhotos
        case .smartAlbum(let id) where !smartAlbums.contains { $0.id == id }: sidebarSelection = .allPhotos
        default: break
        }
    }

    func refreshKeywords() async {
        do {
            keywords = try await catalog.keywordSummaries(groupingPairs: groupPairs)
        } catch {
            Self.log.error("Loading keywords failed: \(error.localizedDescription, privacy: .public)")
        }
        keywordRevision += 1
        if case .keyword(let id) = sidebarSelection, !keywords.contains(where: { $0.id == id }) {
            sidebarSelection = .allPhotos
        }
        scheduleSidebarRefresh()
    }

    // MARK: Volumes

    func refreshVolumes() async {
        let mounted = await Task.detached(priority: .utility) { VolumeAvailability.mountedVolumes() }.value
        mountedCardName = await Task.detached(priority: .utility) { ImportSource.mountedCards().first(where: \.isCard)?.name }.value
        do {
            let online = try await catalog.refreshVolumeAvailability(mounted: mounted)
            let volumes = try await catalog.volumes()
            volumesByID = Dictionary(uniqueKeysWithValues: volumes.compactMap { volume in volume.id.map { ($0, volume) } })
            if online != onlineVolumeIDs {
                onlineVolumeIDs = online
                notifyObservers { $0.libraryAvailabilityChanged() }
                refreshStaleMetadata()
                if started {
                    scheduleSidecarSync()
                    checkForDiskChanges(delay: .seconds(2))
                }
            }
        } catch {
            Self.log.error("Refreshing volumes failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let mounted = name == NSWorkspace.didMountNotification
                    ? notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL : nil
                Task { @MainActor in
                    await self?.refreshVolumes()
                    if let mounted { self?.volumeDidMount(mounted) }
                }
            })
        }
    }

    /// Reads metadata again for masters a previous version of the reader
    /// handled, on whatever volumes are mounted. Runs quietly in the background.
    func refreshStaleMetadata() {
        guard metadataTask == nil else { return }
        let catalog = self.catalog
        let reader = importer.metadataReader
        let online = onlineVolumeIDs
        metadataTask = Task {
            while !Task.isCancelled {
                guard let stale = try? await catalog.staleMetadata(onVolumes: online), !stale.isEmpty else { break }
                let byURL = Dictionary(stale.map { ($0.url, $0.imageID) }, uniquingKeysWith: { first, _ in first })
                let read = (try? await reader.metadata(for: stale.map(\.url))) ?? [:]
                let byImage = Dictionary(read.compactMap { url, metadata in byURL[url].map { ($0, metadata) } },
                                         uniquingKeysWith: { first, _ in first })
                do {
                    try await catalog.refreshMetadata(byImage, checked: stale.map(\.imageID))
                } catch {
                    Self.log.error("Refreshing metadata failed: \(error.localizedDescription, privacy: .public)")
                    break
                }
            }
            metadataTask = nil
        }
    }

    /// A card (a volume with a DCIM folder) opens the import window.
    private func volumeDidMount(_ url: URL) {
        guard opensImportOnCard, ImportSource.hasDCIM(url) else { return }
        cardImport.refreshSources(preferring: url)
        requestsImportWindow = true
    }

    /// After a copying import: show the new photos and start the background work.
    func didFinishCopyImport(_ result: CopyImportResult) async {
        await refreshVolumes()
        await refreshProjects()
        await refreshKeywords()
        scheduleSidecarSync()
        if let projectID = result.project?.id {
            if sidebarSelection == .project(projectID) {
                reloadItems(keepFocus: true)
            } else {
                sidebarSelection = .project(projectID)
            }
            warmPreviews(projectIDs: [projectID])
            suggestKeywords(for: result.insertedVersionIDs)
        }
    }

    func isOffline(_ item: CatalogItem) -> Bool {
        !onlineVolumeIDs.contains(item.volumeID)
    }

    /// The master's location, or nil while its volume is offline.
    func sourceURL(for item: CatalogItem) -> URL? {
        guard !isOffline(item), let volume = volumesByID[item.volumeID] else { return nil }
        return volume.url(forRelativePath: item.relativePath)
    }

    func volumeName(for item: CatalogItem) -> String? {
        volumesByID[item.volumeID]?.name
    }

    func previewRequest(for item: CatalogItem, tier: PreviewTier) -> PreviewRequest? {
        guard let key = PreviewCacheKey(item: item, tier: tier) else { return nil }
        return PreviewRequest(versionID: item.versionID, key: key, sourceURL: sourceURL(for: item))
    }

    // MARK: Focus and selection

    /// Called by the grid when the person changes the selection with the mouse.
    func gridSelectionChanged(_ newSelection: IndexSet, focus: Int?) {
        selection = newSelection
        if let focus {
            focusIndex = focus
        } else if let current = focusIndex, !newSelection.contains(current) {
            focusIndex = newSelection.first
        }
        selectionRevision += 1
    }

    /// Photos selected in the grid (observed through the selection's revision).
    var selectedCount: Int {
        _ = selectionRevision
        return selection.count
    }

    /// File ▸ Stop's job from the library window: the newest running export,
    /// batch of folder adds or copying import (design.md I4).
    var newestStoppableJob: StoppableJob? {
        var running: [StoppableJob: Date] = [:]
        running[.export] = export.progressStarted
        running[.addFolders] = importProgress == nil ? nil : importStarted
        running[.cardImport] = cardImport.progressStarted
        return StoppableJob.newest(running)
    }

    func stop(_ job: StoppableJob) {
        switch job {
        case .export: export.cancel()
        case .addFolders: cancelImport()
        case .cardImport: cardImport.cancelImport()
        }
    }

    /// Edit ▸ Deselect All: the selection becomes the focused photo alone, so
    /// commands act on it as after a plain click (design.md I5).
    func collapseSelection() {
        guard selection.count > 1, let focusIndex else { return }
        setFocus(focusIndex)
    }

    /// Moves focus and selection; `extend` grows the selection instead (shift).
    func setFocus(_ index: Int, extend: Bool = false, notify: Bool = true) {
        guard items.indices.contains(index) else { return }
        if extend, let anchor = focusIndex {
            selection.insert(integersIn: min(anchor, index)...max(anchor, index))
        } else {
            selection = IndexSet(integer: index)
        }
        focusIndex = index
        selectionRevision += 1
        if notify { notifyObservers { $0.libraryFocusChanged() } }
    }

    func moveFocus(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = focusIndex ?? 0
        setFocus(min(max(current + delta, 0), items.count - 1))
    }

    func openLoupe(at index: Int? = nil) {
        if let index { setFocus(index) }
        guard focusIndex != nil else { return }
        mode = .loupe
    }

    func closeLoupe() {
        // Leaving the loupe (Return, Space, ⌘↩) leaves review too.
        exitReview()
        mode = .grid
        notifyObservers { $0.libraryFocusChanged() }
    }

    /// Edit ▸ Find ▸ Find…: the keyboard goes to the search field, which
    /// filters the grid; from the loupe, back to the grid first, which hands the
    /// keyboard on once it shows (`takesSearchFocus`).
    func beginSearch() {
        if mode == .loupe {
            searchFocusPending = true
            closeLoupe()
        } else {
            NotificationCenter.default.post(name: .searchShouldTakeFocus, object: self)
        }
    }

    /// The grid is about to take the keyboard: true (once) when Find… asked
    /// for the search field instead.
    func takesSearchFocus() -> Bool {
        defer { searchFocusPending = false }
        return searchFocusPending
    }

    func indexOfVersion(_ versionID: Int64) -> Int? {
        indexByVersionID[versionID]
    }

    /// VoiceOver's Open in Loupe on a grid cell.
    func openLoupe(onVersion versionID: Int64) {
        if let index = indexByVersionID[versionID] { openLoupe(at: index) }
    }

    // MARK: Culling

    /// A version's culling values, as remembered for undo.
    struct CullingValues: Hashable {
        var rating: Rating
        var flag: Flag
        var colorLabel: ColorLabel

        init(_ item: CatalogItem) {
            rating = item.rating
            flag = item.flag
            colorLabel = item.colorLabel
        }
    }

    /// Applies the action to the selection (grid) or the photo on screen (loupe)
    /// and saves it right away.
    func perform(_ action: CullingAction) {
        let targets = actionTargets
        guard !targets.isEmpty else { return }
        var before: [Int64: CullingValues] = [:]
        var after: [Int64: CullingValues] = [:]
        for index in targets {
            let item = items[index]
            var values = CullingValues(item)
            before[item.versionID] = values
            switch action {
            case .setRating(let rating): values.rating = rating
            case .adjustRating(let delta): values.rating = Rating(clamping: item.rating.rawValue + delta)
            case .setFlag(let flag): values.flag = flag
            case .setColorLabel(let label): values.colorLabel = label
            }
            after[item.versionID] = values
        }
        applyCulling(after, undoingTo: before, actionName: action.undoActionName)
        let results = targets.map { index in
            let item = items[index]
            return CullingDescription.Result(
                photo: CullingDescription.Result.photo(versionID: item.versionID, partnerVersionID: item.partnerVersionID),
                rating: item.rating, flag: item.flag, colorLabel: item.colorLabel)
        }
        var announcement = CullingDescription.announcement(of: action.change, step: action.ratingStep, results: results)
            .map(PhotoAccessibility.text) ?? ""

        if autoAdvance, targets.count == 1, let focusIndex, focusIndex + 1 < items.count {
            setFocus(focusIndex + 1)
            // One announcement: two would cut each other off.
            let next = items[focusIndex + 1]
            announcement = PhotoAccessibility.advanced(announcement, to: next, offline: isOffline(next))
        }
        AccessibilityText.announce(announcement)
    }

    /// Announces the photo the loupe moved to (arrows, Home, End):
    /// "DSC00232, RAW, 3 stars, Picked, 13 of 87".
    func announceLoupePhoto() {
        guard mode == .loupe, let index = focusIndex, items.indices.contains(index) else { return }
        let item = items[index]
        AccessibilityText.announce(PhotoAccessibility.loupeMove(to: item, offline: isOffline(item), index: index,
                                                                count: items.count))
    }

    /// A culling action VoiceOver chose on one photo. Like a context menu, it
    /// applies to the selection when the photo is in it; otherwise the photo
    /// is selected first.
    func performAccessibilityAction(_ action: CullingAction, onVersion versionID: Int64) {
        guard let index = indexByVersionID[versionID] else { return }
        if !actionTargets.contains(index) { setFocus(index) }
        perform(action)
    }

    /// Shows the new values at once, saves them in order, and registers the
    /// previous values for undo (whose redo is this call again).
    func applyCulling(_ values: [Int64: CullingValues], undoingTo previous: [Int64: CullingValues], actionName: String) {
        // The catalog applies each change to both halves of a pair; when they are
        // shown separately, the partner's cell changes with it.
        var changed = IndexSet()
        for (versionID, value) in values {
            guard let index = indexByVersionID[versionID] else { continue }
            var indices = [index]
            if let partner = items[index].partnerVersionID, let partnerIndex = indexByVersionID[partner] {
                indices.append(partnerIndex)
            }
            for index in indices {
                items[index].rating = value.rating
                items[index].flag = value.flag
                items[index].colorLabel = value.colorLabel
                changed.insert(index)
            }
        }
        let groups = Dictionary(grouping: values.keys) { values[$0]! }
        let catalog = self.catalog
        persist {
            for (value, ids) in groups {
                try await catalog.setCulling(rating: value.rating, flag: value.flag, colorLabel: value.colorLabel,
                                             forVersions: ids)
            }
        }
        itemsRevision += 1
        if !changed.isEmpty { notifyObservers { $0.libraryItemsChanged(at: changed) } }
        afterPendingWrites { $0.scheduleSidebarRefresh() }

        undoManager.registerUndo(withTarget: self) { model in
            model.applyCulling(previous, undoingTo: values, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// The selection in the grid, or the photo on screen in the loupe.
    var actionTargets: IndexSet {
        // `selection` is not observed: menus and toolbar items that depend on
        // the targets refresh through its revision.
        _ = selectionRevision
        if mode == .loupe || selection.isEmpty {
            return focusIndex.map { IndexSet(integer: $0) } ?? []
        }
        return selection
    }

    var actionTargetVersionIDs: [Int64] {
        actionTargets.map { items[$0].versionID }
    }

    // MARK: Edits

    /// Shows a version's new edit hash: the grid and loupe load renditions for it.
    /// Edits are per file; unlike culling they do not reach a pair's partner.
    func setEditStackHash(_ hash: String, forVersion versionID: Int64) {
        guard let index = indexByVersionID[versionID], items[index].editStackHash != hash else { return }
        items[index].editStackHash = hash
        itemsRevision += 1
        notifyObservers { $0.libraryItemsChanged(at: IndexSet(integer: index)) }
    }

    // MARK: Pairs

    /// Makes the RAW (`raw`) or the JPEG/HEIC represent the targeted pairs while
    /// pairs are grouped.
    func showPairFile(raw: Bool) {
        var covers: [Int64: Bool] = [:]
        var previous: [Int64: Bool] = [:]
        for index in actionTargets where items[index].partnerVersionID != nil {
            let item = items[index]
            covers[item.versionID] = !raw
            previous[item.versionID] = item.fileKind != .raw
        }
        guard !covers.isEmpty else { return }
        setPairCovers(covers, undoingTo: previous)
    }

    /// `showsCompanion` per pair, keyed by the version id of either half. The
    /// focused pair stays focused through the switch.
    func setPairCovers(_ covers: [Int64: Bool], undoingTo previous: [Int64: Bool]) {
        let focusID: Int64? = focusedItem.flatMap { item -> Int64? in
            guard let partner = item.partnerVersionID,
                  let showsCompanion = covers[item.versionID] ?? covers[partner] else { return item.versionID }
            let itemIsCompanion = item.fileKind != .raw
            return itemIsCompanion == showsCompanion ? item.versionID : partner
        }
        let catalog = self.catalog
        let groups = Dictionary(grouping: covers.keys) { covers[$0]! }
        persist {
            for (showsCompanion, ids) in groups {
                try await catalog.setPairsShowCompanion(showsCompanion, forVersions: ids)
            }
        }
        afterPendingWrites { model in model.reloadItems(keepFocus: true, focusVersionID: focusID) }

        let actionName = String(localized: "Switch RAW+JPEG Pair", comment: "Undo action name")
        undoManager.registerUndo(withTarget: self) { model in
            model.setPairCovers(previous, undoingTo: covers)
        }
        undoManager.setActionName(actionName)
    }

    // MARK: Saving

    /// Runs catalog work after every earlier write, so changes reach the catalog
    /// in the order they were made (and undo steps after the change they undo).
    func persist(_ work: @escaping @MainActor () async throws -> Void) {
        writes.enqueue { [self] in
            do {
                try await work()
            } catch {
                Self.log.error("Saving failed: \(error.localizedDescription, privacy: .public)")
                report(String(localized: "Could not save the change: \(error.localizedDescription)"),
                       action: undoManager.undoActionName.nilIfEmpty ?? ActivityTitle.saveChanges, warning: true)
            }
            scheduleSidecarSync()
        }
    }

    /// Runs `body` once the writes queued so far have finished.
    func afterPendingWrites(_ body: @escaping @MainActor (LibraryModel) async -> Void) {
        writes.afterPendingWrites { [self] in await body(self) }
    }

    // MARK: Import

    var isImporting: Bool { importProgress != nil }
    /// True until a batch of folder imports has finished, its status included.
    var isImportRunning: Bool { importTask != nil }

    /// Imports a folder in place as a new project named after it.
    func importFolder(_ folder: URL) {
        importFolders([folder])
    }

    /// Imports folders (chosen, dropped from Finder or scripted) one after
    /// another, each in place as its own project; see `DroppedFolders` for what
    /// counts. Folders added while a batch runs join it.
    func importFolders(_ urls: [URL]) {
        let dropped = DroppedFolders(urls)
        let added = importQueue.enqueue(dropped.folders)
        ignoredDropCount += dropped.ignored.count
        guard importTask == nil else {
            updateImportBatch()
            return
        }
        guard !added.isEmpty else {
            if !dropped.ignored.isEmpty {
                report(String(localized: "Only folders can be imported. Drag in a folder of photos."),
                       action: ActivityTitle.addFolder(nil), warning: true)
            }
            ignoredDropCount = 0
            return
        }
        importTask = Task {
            // A drop that arrives while a finished batch reports starts another.
            repeat {
                await runImportBatch()
            } while importQueue.isRunning && !Task.isCancelled
            importTask = nil
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    private func runImportBatch() async {
        let importer = self.importer
        var folderErrors: [(name: String, error: any Error)] = []
        while let folder = importQueue.next() {
            batchFolderName = Importer.defaultProjectName(for: folder)
            importGeneration += 1
            let generation = importGeneration
            importProgress = ImportProgress(phase: .scanning)
            updateImportBatch()
            do {
                try Task.checkCancellation()
                let summary = try await importer.importFolder(folder) { progress in
                    Task { @MainActor in self.importDidProgress(progress, generation: generation) }
                }
                importQueue.record(summary)
                await finishFolderImport(summary)
            } catch is CancellationError {
                importProgress = nil
                importBatch = nil
                let started = importQueue.started
                let totals = importQueue.finish()
                ignoredDropCount = 0
                report(String(localized: "Import cancelled."), action: ActivityTitle.addFolders(started, name: batchFolderName))
                await refreshProjects()
                warmPreviews(projectIDs: totals.projectIDs)
                reloadItems(keepFocus: true)
                return
            } catch {
                Self.log.error("Import of \(folder.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                folderErrors.append((Importer.defaultProjectName(for: folder), error))
            }
        }
        importProgress = nil
        importBatch = nil
        let folderCount = importQueue.started
        let totals = importQueue.finish()
        let ignored = ignoredDropCount
        ignoredDropCount = 0
        await finishImportBatch(totals, folderCount: folderCount, ignored: ignored, folderErrors: folderErrors)
    }

    private func updateImportBatch() {
        guard let folder = importQueue.current, importQueue.count > 1 else {
            importBatch = nil
            return
        }
        importBatch = ImportBatchPosition(name: Importer.defaultProjectName(for: folder),
                                          index: importQueue.started, count: importQueue.count)
    }

    private func importDidProgress(_ progress: ImportProgress, generation: Int) {
        // Late reports of the previous folder in a batch are dropped.
        guard importTask != nil, generation == importGeneration,
              progress.filesProcessed >= (importProgress?.filesProcessed ?? 0) else { return }
        importProgress = progress
        // Let the library fill in while a long import runs.
        if Date().timeIntervalSince(lastLiveRefresh) > 1.5, progress.imported > 0 {
            lastLiveRefresh = Date()
            Task {
                await refreshProjects()
                if sidebarSelection == .allPhotos { reloadItems(keepFocus: true) }
            }
        }
    }

    /// One folder of a batch is in: its project shows in the sidebar.
    private func finishFolderImport(_ summary: ImportSummary) async {
        await refreshVolumes()
        await refreshProjects()
        scheduleSidecarSync()
        suggestKeywords(for: summary.insertedVersionIDs)
    }

    private func finishImportBatch(_ totals: FolderImportQueue.Totals, folderCount: Int, ignored: Int,
                                   folderErrors: [(name: String, error: any Error)]) async {
        await refreshKeywords()
        var message: String
        if let failure = folderErrors.first, folderCount == 1 {
            message = String(localized: "Import failed: \(failure.error.localizedDescription)")
        } else if folderCount > 1 {
            message = totals.failed > 0
                ? String(localized: "\(folderCount) folders. Imported: \(totals.imported). Already in the library: \(totals.alreadyInLibrary). Could not import: \(totals.failed).")
                : String(localized: "\(folderCount) folders. Imported: \(totals.imported). Already in the library: \(totals.alreadyInLibrary).")
            if let failure = folderErrors.first {
                message += " " + String(localized: "Could not import “\(failure.name)”: \(failure.error.localizedDescription)")
            }
        } else {
            message = totals.failed > 0
                ? String(localized: "Imported: \(totals.imported). Already in the library: \(totals.alreadyInLibrary). Could not import: \(totals.failed).")
                : String(localized: "Imported: \(totals.imported). Already in the library: \(totals.alreadyInLibrary).")
        }
        if ignored > 0 {
            message += " " + String(localized: "Ignored \(ignored) items that are not folders.")
        }
        report(message, action: ActivityTitle.addFolders(folderCount, name: batchFolderName),
               warning: totals.failed > 0 || !folderErrors.isEmpty)
        // The first new project opens; the rest are listed in the sidebar.
        if let projectID = totals.projectIDs.first {
            if sidebarSelection == .project(projectID) {
                reloadItems(keepFocus: true)
            } else {
                sidebarSelection = .project(projectID)
            }
            warmPreviews(projectIDs: totals.projectIDs)
        } else {
            reloadItems(keepFocus: true)
        }
    }

    /// Renders previews for freshly imported projects in the background. Visible
    /// thumbnails still jump the queue.
    func warmPreviews(projectIDs: [Int64]) {
        guard !projectIDs.isEmpty else { return }
        warmTask?.cancel()
        let catalog = self.catalog
        let previews = self.previews
        warmTask = Task {
            var items: [CatalogItem] = []
            for projectID in projectIDs {
                items += (try? await catalog.libraryItems(matching: LibraryFilter(scope: .project(projectID)))) ?? []
            }
            let requests = items.compactMap { previewRequest(for: $0, tier: .preview) }.filter { $0.sourceURL != nil }
            warming = (0, requests.count)
            var done = 0
            await withTaskGroup(of: Void.self) { group in
                var pending = requests.makeIterator()
                for _ in 0..<PreviewService.defaultGenerateConcurrency {
                    guard let request = pending.next() else { break }
                    group.addTask { try? await previews.prepare(request, priority: .background) }
                }
                for await _ in group {
                    done += 1
                    if done.isMultiple(of: 8) || done == requests.count { warming = (done, requests.count) }
                    if Task.isCancelled { group.cancelAll(); break }
                    if let request = pending.next() {
                        group.addTask { try? await previews.prepare(request, priority: .background) }
                    }
                }
            }
            warming = nil
        }
    }
}

extension LibraryModel: CardImportLibrary {}

// MARK: Observers

extension LibraryModel {
    /// Starts telling `observer` about item, focus and availability changes.
    /// Held weakly; released observers are dropped.
    func addObserver(_ observer: any LibraryItemsObserver) {
        itemsObservers.removeAll { $0.value == nil }
        guard !itemsObservers.contains(where: { $0.value === observer }) else { return }
        itemsObservers.append(WeakItemsObserver(value: observer))
    }

    func removeObserver(_ observer: any LibraryItemsObserver) {
        itemsObservers.removeAll { $0.value == nil || $0.value === observer }
    }

    /// The observers still alive, in the order they were added.
    var observers: [any LibraryItemsObserver] {
        itemsObservers.compactMap(\.value)
    }

    /// Calls `body` on each live observer. A copy is iterated, so an
    /// observer may add or remove observers from its callback.
    private func notifyObservers(_ body: (any LibraryItemsObserver) -> Void) {
        for observer in observers { body(observer) }
    }
}

private struct WeakItemsObserver {
    weak var value: (any LibraryItemsObserver)?
}

/// Where a batch of folder imports stands, for the Activity item.
struct ImportBatchPosition: Equatable {
    /// The folder being imported, as its project will be named.
    var name: String
    /// 1-based.
    var index: Int
    var count: Int
}
