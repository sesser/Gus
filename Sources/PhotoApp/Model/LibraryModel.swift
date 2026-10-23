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
    case project(Int64)
    case keyword(Int64)
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

    // MARK: Sidebar and filters

    private(set) var projects: [ProjectSummary] = []
    private(set) var libraryCount = 0
    /// Every keyword with its photo count, for the sidebar and autocomplete.
    var keywords: [KeywordSummary] = []
    /// Bumped whenever keyword assignments may have changed.
    var keywordRevision = 0

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
        let scope: LibraryFilter.Scope = switch sidebarSelection {
        case .allPhotos: .allPhotos
        case .project(let id): .project(id)
        case .keyword(let id): .keyword(id)
        }
        return LibraryFilter(scope: scope, rating: ratingRule, flag: flagRule, groupsPairs: groupPairs)
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
    private static let showsInspectorKey = "browser.showsInspector"

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
    @ObservationIgnored private var started = false
    @ObservationIgnored private var volumeObservers: [any NSObjectProtocol] = []

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
        showsInspector = defaults.bool(forKey: Self.showsInspectorKey)
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
            }
        } catch {
            Self.log.error("Refreshing volumes failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refreshVolumes() }
            })
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
