import AppKit
import Observation
import PhotoCore
import os

/// Receives changes to the browser's item list. The grid uses this instead of
/// SwiftUI diffing so that a rating change touches one cell, not 50k.
@MainActor
protocol LibraryItemsObserver: AnyObject {
    /// The list was replaced (filter, scope or import).
    func libraryItemsReloaded()
    /// Items changed in place (culling values).
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
    let cardImport = CardImportModel()

    // MARK: Sidebar and filters

    private(set) var projects: [ProjectSummary] = []
    private(set) var libraryCount = 0
    /// Every keyword with its photo count, for the sidebar and autocomplete.
    var keywords: [KeywordSummary] = []
    /// Bumped whenever keyword assignments may have changed.
    var keywordRevision = 0
    /// Bumped when new suggestions are stored or their state changes.
    var suggestionRevision = 0
    /// Background keyword analysis in progress.
    var suggestionProgress: (done: Int, total: Int)?
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

    var sidebarSelection: SidebarSelection = .allPhotos {
        didSet { if oldValue != sidebarSelection { reloadItems(keepFocus: false) } }
    }
    var ratingRule: LibraryFilter.RatingRule = .any {
        didSet { if oldValue != ratingRule { reloadItems(keepFocus: true) } }
    }
    var flagRule: LibraryFilter.FlagRule = .any {
        didSet { if oldValue != flagRule { reloadItems(keepFocus: true) } }
    }

    var filter: LibraryFilter {
        LibraryFilter(scope: scope(for: sidebarSelection), rating: ratingRule, flag: flagRule, groupsPairs: groupPairs)
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

    var isFiltered: Bool { ratingRule != .any || flagRule != .any }

    // MARK: Items, focus, selection

    /// Not observed: the grid is told about changes through `observer`.
    @ObservationIgnored private(set) var items: [CatalogItem] = []
    @ObservationIgnored private var indexByVersionID: [Int64: Int] = [:]
    /// Observed stand-in for `items` for SwiftUI views (counts, titles).
    private(set) var itemsRevision = 0
    private(set) var focusIndex: Int?
    @ObservationIgnored private(set) var selection = IndexSet()
    /// Observed stand-in for `selection`, which is not observed.
    private(set) var selectionRevision = 0
    var mode: BrowserMode = .grid
    /// The open ⌘K keyword field, with the photos it will tag.
    var keywordEntry: KeywordEntryRequest?
    var showsInspector: Bool {
        didSet { UserDefaults.standard.set(showsInspector, forKey: Self.showsInspectorKey) }
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
    static let thumbnailSizeRange = 80.0...360.0
    private static let thumbnailSizeKey = "browser.thumbnailSize"
    private static let autoAdvanceKey = "culling.autoAdvance"
    private static let showFileInfoKey = "browser.showFileInfo"
    private static let groupPairsKey = "browser.groupPairs"
    private static let showsHDRKey = "loupe.showsHDR"
    private static let showsInspectorKey = "browser.showsInspector"
    private static let writesSidecarsKey = "sidecars.write"
    private static let opensImportOnCardKey = "import.openOnCard"

    // MARK: Background work

    private(set) var importProgress: ImportProgress?
    private(set) var warming: (done: Int, total: Int)?
    var statusMessage: String?
    private(set) var onlineVolumeIDs: Set<Int64> = []

    @ObservationIgnored weak var observer: LibraryItemsObserver?
    @ObservationIgnored private var volumesByID: [Int64: VolumeRecord] = [:]
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    @ObservationIgnored private var writeChain: Task<Void, Never>?
    /// Undo for changes to photos and keywords. The grid and loupe answer
    /// undo:/redo: with it, so text fields keep their own undo.
    @ObservationIgnored var undoManager = UndoManager()
    @ObservationIgnored private var lastLiveRefresh = Date.distantPast
    @ObservationIgnored private(set) var started = false
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

    init(locations: LibraryLocations, catalog: Catalog, importer: Importer, previews: PreviewService) {
        self.locations = locations
        self.catalog = catalog
        self.importer = importer
        self.previews = previews
        let defaults = UserDefaults.standard
        let size = defaults.double(forKey: Self.thumbnailSizeKey)
        thumbnailSize = Self.thumbnailSizeRange.contains(size) ? size : 180
        autoAdvance = defaults.bool(forKey: Self.autoAdvanceKey)
        showFileInfo = defaults.object(forKey: Self.showFileInfoKey) as? Bool ?? true
        groupPairs = defaults.object(forKey: Self.groupPairsKey) as? Bool ?? true
        showsHDR = defaults.object(forKey: Self.showsHDRKey) as? Bool ?? true
        showsInspector = defaults.bool(forKey: Self.showsInspectorKey)
        writesSidecars = defaults.object(forKey: Self.writesSidecarsKey) as? Bool ?? true
        sidecars = SidecarSync(catalog: catalog, metadataReader: importer.metadataReader)
        opensImportOnCard = defaults.object(forKey: Self.opensImportOnCardKey) as? Bool ?? true
        cardImport.library = self
    }

    /// Opens the catalog at the standard location (or `--library-root`).
    static func open(options: LaunchOptions = .current) throws -> LibraryModel {
        let locations: LibraryLocations
        if let root = options.libraryRoot {
            locations = .rooted(at: root)
        } else {
            try DataDirectoryMigrator.migrateStandardLocations()
            locations = try .standard()
        }
        try locations.createDirectories()
        let catalog = try Catalog.open(at: locations.catalogFileURL)
        let importer = Importer(catalog: catalog, metadataReader: MetadataReaders.makeDefault())
        let previews = PreviewService(cacheDirectory: locations.previewCacheDirectory, catalog: catalog)
        previews.cache.removeObsoletePipelineVersions()
        return LibraryModel(locations: locations, catalog: catalog, importer: importer, previews: previews)
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
                let items = try await catalog.libraryItems(matching: filter)
                guard !Task.isCancelled else { return }
                apply(items, focusVersionID: focusID)
            } catch is CancellationError {
            } catch {
                Self.log.error("Loading items failed: \(error.localizedDescription, privacy: .public)")
                statusMessage = String(localized: "Could not load photos: \(error.localizedDescription)")
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
        observer?.libraryItemsReloaded()
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
        do {
            let online = try await catalog.refreshVolumeAvailability(mounted: mounted)
            let volumes = try await catalog.volumes()
            volumesByID = Dictionary(uniqueKeysWithValues: volumes.compactMap { volume in volume.id.map { ($0, volume) } })
            if online != onlineVolumeIDs {
                onlineVolumeIDs = online
                observer?.libraryAvailabilityChanged()
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
            warmPreviews(projectID: projectID)
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
        if notify { observer?.libraryFocusChanged() }
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
        mode = .grid
        observer?.libraryFocusChanged()
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

        if autoAdvance, targets.count == 1, let focusIndex, focusIndex + 1 < items.count {
            setFocus(focusIndex + 1)
        }
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
        if !changed.isEmpty { observer?.libraryItemsChanged(at: changed) }
        afterPendingWrites { $0.scheduleSidebarRefresh() }

        undoManager.registerUndo(withTarget: self) { model in
            model.applyCulling(previous, undoingTo: values, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// The selection in the grid, or the photo on screen in the loupe.
    var actionTargets: IndexSet {
        if mode == .loupe || selection.isEmpty {
            return focusIndex.map { IndexSet(integer: $0) } ?? []
        }
        return selection
    }

    var actionTargetVersionIDs: [Int64] {
        actionTargets.map { items[$0].versionID }
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
        let previous = writeChain
        writeChain = Task {
            await previous?.value
            do {
                try await work()
            } catch {
                Self.log.error("Saving failed: \(error.localizedDescription, privacy: .public)")
                statusMessage = String(localized: "Could not save the change: \(error.localizedDescription)")
            }
            scheduleSidecarSync()
        }
    }

    /// Runs `body` once the writes queued so far have finished.
    func afterPendingWrites(_ body: @escaping @MainActor (LibraryModel) async -> Void) {
        let previous = writeChain
        Task {
            await previous?.value
            await body(self)
        }
    }

    // MARK: Import

    var isImporting: Bool { importProgress != nil }

    func importFolder(_ folder: URL) {
        guard importTask == nil else { return }
        importProgress = ImportProgress(phase: .scanning)
        statusMessage = nil
        let importer = self.importer
        importTask = Task {
            defer { importTask = nil }
            do {
                let summary = try await importer.importFolder(folder) { progress in
                    Task { @MainActor in self.importDidProgress(progress) }
                }
                importProgress = nil
                await finishImport(summary)
            } catch is CancellationError {
                importProgress = nil
                statusMessage = String(localized: "Import cancelled.")
                await refreshProjects()
                reloadItems(keepFocus: true)
            } catch {
                importProgress = nil
                Self.log.error("Import failed: \(error.localizedDescription, privacy: .public)")
                statusMessage = String(localized: "Import failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    private func importDidProgress(_ progress: ImportProgress) {
        guard importTask != nil, progress.filesProcessed >= (importProgress?.filesProcessed ?? 0) else { return }
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

    private func finishImport(_ summary: ImportSummary) async {
        await refreshVolumes()
        await refreshProjects()
        await refreshKeywords()
        scheduleSidecarSync()
        let progress = summary.progress
        let skipped = progress.duplicates + progress.alreadyInCatalog
        let failed = progress.failed + progress.changedOnDisk
        statusMessage = failed > 0
            ? String(localized: "Imported: \(progress.imported). Already in the library: \(skipped). Could not import: \(failed).")
            : String(localized: "Imported: \(progress.imported). Already in the library: \(skipped).")
        if let projectID = summary.project?.id {
            if sidebarSelection == .project(projectID) {
                reloadItems(keepFocus: true)
            } else {
                sidebarSelection = .project(projectID)
            }
            warmPreviews(projectID: projectID)
            suggestKeywords(for: summary.insertedVersionIDs)
        } else {
            reloadItems(keepFocus: true)
        }
    }

    /// Renders previews for a freshly imported project in the background. Visible
    /// thumbnails still jump the queue.
    func warmPreviews(projectID: Int64) {
        warmTask?.cancel()
        let catalog = self.catalog
        let previews = self.previews
        warmTask = Task {
            guard let items = try? await catalog.libraryItems(matching: LibraryFilter(scope: .project(projectID))) else { return }
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
