import AppKit
import os
import PhotoCore
import PhotoUI
import SwiftUI

/// File ▸ Publish… (issue #28): the sheet's frozen targets and choices, the
/// server check, Check Originals, the folder map and File Settings pages, the
/// Skip or New Copy question, and the runs behind it with Retry Failed.
@MainActor
@Observable
final class PublishModel: ServerSheetHost {
    @ObservationIgnored weak var library: LibraryModel?
    @ObservationIgnored private let defaults: UserDefaults
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "publish")
    static let lastServerKey = "publish.lastServer"

    enum Page: Equatable { case main, settings, folderMap }

    enum CheckState: Equatable {
        case idle
        case checking
        case failed(ConnectionCheckResult)
        case passed(PublishServerInfo)
    }

    enum AlbumsState: Equatable {
        case notLoaded
        case loading
        case loaded
        case failed(String)
    }

    /// What Check Originals came to (design §7).
    enum OriginalsCheck: Equatable {
        case notRun
        case running(done: Int, total: Int)
        case result(OriginalsResult)
        case failed(String)
    }

    struct OriginalsResult: Equatable {
        var found: Int
        var checked: Int
        /// Photos without an original, by group, in the order first met.
        var groups: [(group: NoOriginalReason.Group, photos: [(name: String, reason: NoOriginalReason)])]
        var offline: Int

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.found == rhs.found && lhs.checked == rhs.checked && lhs.offline == rhs.offline
                && lhs.groups.map(\.group) == rhs.groups.map(\.group)
                && lhs.groups.map { $0.photos.map(\.name) } == rhs.groups.map { $0.photos.map(\.name) }
        }
    }

    /// The Skip / New Copy question (design §8).
    struct Question: Identifiable {
        let id = UUID()
        let published: Int
        let total: Int
        let items: [PublishItem]
        let alreadyPublished: Set<Int64>
    }

    // MARK: The sheet

    private(set) var page: Page = .main
    private(set) var servers: [RemoteServiceRecord] = []
    private(set) var serviceID: Int64?
    private(set) var check: CheckState = .idle
    @ObservationIgnored private(set) var client: ImmichClient?
    private(set) var albums: [RemoteAlbum] = []
    private(set) var albumsState: AlbumsState = .notLoaded
    /// The album, visibility, stacking and render settings chosen.
    var album: PublishAlbumChoice = .none {
        didSet { if album != oldValue { originals = .notRun } }
    }
    var newAlbumName = ""
    var visibility: PublishVisibility = .timeline
    var stacking = true {
        didSet {
            guard stacking != oldValue else { return }
            originals = .notRun
            // The account is read only with stacking (design §3.3).
            if stacking, case .passed(let info) = check, info.ownerID == nil, info.has("user.read") { runCheck() }
        }
    }
    var presetID: Int64?
    /// Typed for this run, never remembered (R5, R7).
    var description = ""
    /// The server's saved folder map.
    private(set) var folderMap: [PublishFolderMapping] = []
    /// The folder map page's copy, saved on Done.
    var editingMap: [PublishFolderMapping] = []
    /// The settings as they were on entering File Settings (Cancel restores them).
    @ObservationIgnored private var settingsOnEntry: ExportSettings?
    let editor: ExportSettingsEditor
    private(set) var presets: [ExportPreset] = []

    /// The targets frozen when the sheet opened (pairs to their raw).
    private(set) var versionIDs: [Int64] = []
    private(set) var skippedVideos = 0
    private(set) var hdrPhotos = 0
    private(set) var offlinePhotos = 0
    private(set) var sourceName = ""
    /// What finding the targets' originals needs (folder map examples, R16).
    private(set) var sources: [Int64: PublishSource] = [:]
    private(set) var names: [Int64: String] = [:]
    /// No selected photo was imported from this server (design §3.5's line).
    private(set) var noneLinked = true
    private(set) var originals: OriginalsCheck = .notRun
    @ObservationIgnored private var originalsTask: Task<Void, Never>?
    /// Publish was pressed: permissions confirmed again and records looked up.
    private(set) var isConfirming = false
    /// The sheet is reading its servers and the chosen one's choices.
    private(set) var isLoading = false
    var question: Question?
    /// A problem found when Publish was pressed, shown in the sheet.
    private(set) var startIssue: String?
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var albumsTask: Task<Void, Never>?

    // MARK: The Server sheet in place of this one (design §4)

    var serverSheet: ServerSheetModel?
    @ObservationIgnored private var pendingServerSheet: ServerSheetModel?
    /// The publish sheet comes back when the Server sheet has gone.
    @ObservationIgnored private var returnsAfterServerSheet = false
    @ObservationIgnored private var serverBeforeSheet: Int64?

    // MARK: Runs

    private(set) var progress: PublishProgress?
    private(set) var started: Date?
    private(set) var jobName = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var runningID: UUID?
    /// The server the running publish goes to (its uuid), nil when none runs.
    private(set) var runningServerUUID: String?
    /// Every run since launch, newest last (R23: Retry Failed until quit).
    private(set) var runs: [PublishRun] = []
    var resultsRunID: UUID?
    /// Debug script: the client whose server holds the next upload; tests stop there.
    @ObservationIgnored var debugOnFullySent: (@Sendable () -> Void)?
    /// Debug script and tests: the ending bound (the quit wait's 10 s otherwise).
    @ObservationIgnored var endingBound: Duration = .seconds(10)

    var isPublishing: Bool { started != nil }
    /// Stop was asked; the run waits for answers to fully sent files (design §9).
    var isEnding: Bool { progress?.phase == .ending }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        editor = ExportSettingsEditor(settings: ExportSettings())
    }

    var service: RemoteServiceRecord? { servers.first { $0.id == serviceID } }
    var serverInfo: PublishServerInfo? { if case .passed(let info) = check { info } else { nil } }

    // MARK: Opening

    /// File ▸ Publish…: freezes the targets and opens the sheet.
    func begin() {
        guard let library, !isPublishing else { return }
        let targets = library.actionTargets.map { library.items[$0] }
        let resolved = ExportTargets.resolve(targets)
        guard !resolved.versionIDs.isEmpty else { return }
        versionIDs = resolved.versionIDs
        skippedVideos = resolved.videos
        hdrPhotos = ExportTargets.hdrCount(targets)
        let byVersion = Dictionary(targets.map { ($0.versionID, $0) }, uniquingKeysWith: { first, _ in first })
        offlinePhotos = versionIDs.filter { id in byVersion[id].map(library.isOffline) ?? false }.count
        sourceName = library.title(for: library.sidebarSelection)
        page = .main
        description = ""
        originals = .notRun
        question = nil
        startIssue = nil
        isConfirming = false
        editor.library = library
        editor.show(first: targets.first { !$0.isVideo }, versionID: versionIDs.first)
        isLoading = true
        Task {
            defer { isLoading = false }
            await refreshPresets()
            await loadServers()
            // The server last published to, else the first by name (design §3.3).
            let remembered = defaults.string(forKey: Self.lastServerKey)
            if let chosen = servers.first(where: { $0.uuid == remembered }) ?? servers.first {
                await choose(chosen)
            } else {
                serviceID = nil
                check = .idle
            }
        }
        library.showsPublishSheet = true
    }

    func loadServers() async {
        guard let library else { return }
        servers = (try? await library.catalog.remoteServices()) ?? []
    }

    /// Chooses a server: its remembered choices and map, and the check.
    func choose(_ service: RemoteServiceRecord) async {
        guard let library, let id = service.id else { return }
        serviceID = id
        originals = .notRun
        let saved = (try? await library.catalog.publishSettings(serviceID: id)) ?? RemotePublishSettings()
        let choices = saved.choices ?? .firstRun(exportSettings: library.export.settings)
        editor.settings = choices.settings
        presetID = choices.presetID
        album = choices.album
        newAlbumName = album.name ?? ""
        if case .new = album { album = .none }
        visibility = choices.visibility
        stacking = choices.stacking
        folderMap = saved.folderMap
        sources = (try? await library.catalog.publishSources(versionIDs: versionIDs, address: service.address)) ?? [:]
        noneLinked = !sources.values.contains { !$0.linkedAssetIDs.isEmpty }
        let details = (try? await ExportJob(catalog: library.catalog, renderer: ExportRenderer(), copyNaming: PhotoName.naming)
            .items(for: versionIDs)) ?? []
        names = Dictionary(details.map { ($0.versionID, $0.reportName) }, uniquingKeysWith: { first, _ in first })
        runCheck()
    }

    /// The check of design §3.3: contacts only the chosen server.
    func runCheck() {
        guard let library, let service else { return }
        checkTask?.cancel()
        albumsTask?.cancel()
        check = .checking
        albums = []
        albumsState = .notLoaded
        let keys = library.remoteKeyStore
        let readsAccount = stacking
        checkTask = Task {
            let outcome = await Self.connect(service, keys: keys, readsAccount: readsAccount)
            guard !Task.isCancelled, self.serviceID == service.id else { return }
            switch outcome {
            case .failed(let result):
                client = nil
                check = .failed(result)
            case .ready(let client, let info):
                self.client = client
                check = .passed(info)
                if PublishPermissions.canListAlbums(info.permissions) { loadAlbums() }
            }
        }
    }

    enum Connection {
        case ready(ImmichClient, PublishServerInfo)
        case failed(ConnectionCheckResult)
    }

    /// The key from the store, a client and the check, off the main actor
    /// (the Keychain may ask the person).
    nonisolated static func connect(_ service: RemoteServiceRecord, keys: any RemoteKeyStore, readsAccount: Bool) async
        -> Connection {
        guard let address = service.serverAddress else { return .failed(.notImmich) }
        let key: String
        do throws(RemoteKeyStoreError) {
            guard let stored = try keys.key(account: service.uuid) else {
                return .failed(.keychain(RemoteKeyStoreError.from(errSecItemNotFound).message))
            }
            key = stored
        } catch {
            return .failed(.keychain(error.message))
        }
        let connection = RemoteConnection(address: address, key: key, pinned: service.pinnedFingerprint,
                                          unencryptedConfirmed: service.allowsUnencrypted)
        guard let client = try? ImmichClient(connection: connection) else {
            return .failed(.unreachable(reason: "", isLocalHost: address.isLocalNetworkHost))
        }
        switch await client.publishCheck(readsAccount: readsAccount) {
        case .passed(let info): return .ready(client, info)
        case .failed(let result): return .failed(result)
        }
    }

    func loadAlbums() {
        guard let client else { return }
        albumsTask?.cancel()
        albumsState = .loading
        albumsTask = Task {
            do throws(PublishFailure) {
                let found = try await client.ownAlbums(holding: nil)
                guard !Task.isCancelled else { return }
                albums = found
                albumsState = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                albumsState = .failed(PublishText.cause(PublishCause(error)))
            }
        }
    }

    // MARK: What the sheet shows

    /// The permissions the current options lack (R8, design §5).
    var missing: PublishPermissions.Missing {
        guard let info = serverInfo else { return PublishPermissions.Missing() }
        return PublishPermissions.missing(from: info.permissions, album: albumChoiceForRun, stacking: stacking)
    }

    /// The album as the run would use it: a new album named by the field.
    var albumChoiceForRun: PublishAlbumChoice {
        if case .new = album { return .new(name: newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return album
    }

    var isNewAlbum: Bool { if case .new = album { true } else { false } }

    /// A remembered album that is no longer on the server (design §3.4).
    var rememberedAlbumGone: Bool {
        guard case .existing(let id, _) = album, albumsState == .loaded else { return false }
        return !albums.contains { $0.id == id }
    }

    /// An album of the typed name exists (design §3.4's note).
    var newAlbumNameTaken: RemoteAlbum? {
        guard isNewAlbum else { return nil }
        let name = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        return albums.first { $0.name == name }
    }

    var settingsIssue: String? { editor.settingsIssue }

    /// Publish N Photos is enabled (design §3.8).
    var canPublish: Bool {
        guard serverInfo != nil, missing.isEmpty, !isPublishing, !isConfirming, !versionIDs.isEmpty else { return false }
        if isNewAlbum, newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return !rememberedAlbumGone && settingsIssue == nil
    }

    /// The metadata level omits descriptions (R5).
    var descriptionIsSent: Bool {
        editor.settings.metadata == .all || editor.settings.metadata == .noLocation
    }

    // MARK: Pages

    func showSettingsPage() {
        settingsOnEntry = editor.settings
        page = .settings
    }

    func closeSettingsPage(keeping: Bool) {
        if !keeping, let before = settingsOnEntry { editor.settings = before }
        settingsOnEntry = nil
        page = .main
    }

    func showFolderMapPage() {
        editingMap = folderMap
        page = .folderMap
    }

    var folderMapCanSave: Bool {
        editingMap.allSatisfy { PublishFolderMapping.issues(of: $0, in: editingMap).isEmpty }
    }

    /// Done: saved to the server at once, even if the publish is cancelled (design §6).
    func closeFolderMapPage(saving: Bool) {
        defer { page = .main }
        guard saving, folderMapCanSave, let library, let id = serviceID else { return }
        folderMap = editingMap
        originals = .notRun
        let map = editingMap
        Task { try? await library.catalog.saveFolderMap(map, serviceID: id) }
    }

    /// Add Folder… / Choose…: a folder on this Mac, by its volume (R12).
    func chooseFolder(replacing id: UUID? = nil, in window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Choose Folder", comment: "Open panel button")
        panel.message = PublishText.folderPanelMessage
        ExportModel.run(panel, in: window) { [weak self] url in self?.addFolder(url, replacing: id) }
    }

    func addFolder(_ url: URL, replacing id: UUID? = nil) {
        guard let mapping = Self.mapping(for: url) else { return }
        if let id, let index = editingMap.firstIndex(where: { $0.id == id }) {
            editingMap[index].volumeIdentity = mapping.volumeIdentity
            editingMap[index].folderPath = mapping.folderPath
            editingMap[index].lastKnownPath = mapping.lastKnownPath
        } else {
            editingMap.append(mapping)
        }
    }

    /// The folder as a pair of the map, with no server path yet.
    static func mapping(for url: URL) -> PublishFolderMapping? {
        guard let volume = try? url.resourceValues(forKeys: [.volumeURLKey]).volume,
              let descriptor = try? VolumeResolver.descriptor(forVolumeAt: volume) else { return nil }
        let relative = VolumeResolver.relativePath(of: url, inVolumeAt: descriptor.mountPath) ?? ""
        return PublishFolderMapping(volumeIdentity: descriptor.identity, folderPath: relative,
                                    lastKnownPath: url.standardizedFileURL.path, serverPath: "")
    }

    /// "‹name› is looked for at ‹path›" for the first target this pair wins
    /// (design §6), the raw's path for a pair.
    func example(for mapping: PublishFolderMapping) -> (name: String, path: String)? {
        for id in versionIDs {
            guard let source = sources[id] else { continue }
            for file in source.files {
                guard let won = PublishFolderMapping.winning(editingMap, volumeIdentity: file.volumeIdentity,
                                                             relativePath: file.relativePath),
                      won.mapping.id == mapping.id else { continue }
                return ((file.relativePath as NSString).lastPathComponent, won.path)
            }
        }
        return nil
    }

    /// The pair's Mac folder, and whether its volume is away.
    func displayPath(_ mapping: PublishFolderMapping) -> (path: String, connected: Bool) {
        guard let library else { return (mapping.lastKnownPath, false) }
        let volumes = library.volumesByIdentity
        guard let volume = volumes[mapping.volumeIdentity], library.onlineVolumeIDs.contains(volume.id ?? -1) else {
            return (mapping.lastKnownPath, false)
        }
        let path = mapping.folderPath.isEmpty ? volume.mountPath
            : URL(fileURLWithPath: volume.mountPath).appending(path: mapping.folderPath).path
        return (path, true)
    }

    // MARK: Presets (the export presets, design §3.6)

    func refreshPresets() async {
        guard let library else { return }
        presets = (try? await library.catalog.exportPresets()) ?? []
        if let presetID, !presets.contains(where: { $0.id == presetID }) { self.presetID = nil }
    }

    func applyPreset(id: Int64?) {
        presetID = id
        guard let id, let preset = presets.first(where: { $0.id == id }) else { return }
        editor.settings = preset.settings
    }

    var modifiedPreset: ExportPreset? {
        guard let preset = presets.first(where: { $0.id == presetID }), preset.settings != editor.settings else { return nil }
        return preset
    }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let library, !trimmed.isEmpty else { return }
        let existing = presets.first { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        var preset = existing ?? ExportPreset(name: trimmed, settings: editor.settings)
        preset.settings = editor.settings
        let catalog = library.catalog
        Task {
            if let saved = try? await catalog.saveExportPreset(preset) {
                await refreshPresets()
                presetID = saved.id
                await library.export.refreshPresets()
            }
        }
    }

    func deleteSelectedPreset() {
        guard let library, let id = presetID else { return }
        Task {
            try? await library.catalog.deleteExportPreset(id: id)
            presetID = nil
            await refreshPresets()
            await library.export.refreshPresets()
        }
    }

    // MARK: Check Originals (R16, design §7)

    var canCheckOriginals: Bool {
        guard let info = serverInfo, info.ownerID != nil, stacking else { return false }
        return missing.server.isEmpty && missing.stacking.isEmpty && !isPublishing
    }

    func checkOriginals() {
        guard canCheckOriginals, let library, let client, let service, let account = serverInfo?.ownerID else { return }
        originalsTask?.cancel()
        let finder = OriginalFinder(destination: client, catalog: library.catalog, address: service.address,
                                    accountID: account, folderMap: folderMap)
        let ids = versionIDs
        let byVersion = Dictionary(library.items.map { ($0.versionID, $0) }, uniquingKeysWith: { first, _ in first })
        let offline = Set(ids.filter { id in byVersion[id].map(library.isOffline) ?? false })
        let checkable = ids.filter { !offline.contains($0) }
        let sources = self.sources
        let names = self.names
        originals = .running(done: 0, total: checkable.count)
        originalsTask = Task {
            var result = OriginalsResult(found: 0, checked: checkable.count, groups: [], offline: offline.count)
            for (index, id) in checkable.enumerated() {
                guard let source = sources[id] else { continue }
                do throws(PublishFailure) {
                    switch try await finder.find(source) {
                    case .found:
                        result.found += 1
                    case .none(let reason):
                        let entry = (name: names[id] ?? "", reason: reason)
                        if let at = result.groups.firstIndex(where: { $0.group == reason.group }) {
                            result.groups[at].photos.append(entry)
                        } else {
                            result.groups.append((reason.group, [entry]))
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    originals = .failed(PublishText.cause(PublishCause(error)))
                    return
                }
                guard !Task.isCancelled else { return }
                originals = .running(done: index + 1, total: checkable.count)
            }
            originals = .result(result)
            AccessibilityText.announce(PublishText.originalsSummary(found: result.found, of: result.checked),
                                       priority: .medium)
        }
    }

    func stopOriginalsCheck() {
        originalsTask?.cancel()
        originals = .notRun
    }

    // MARK: Pressing Publish (design §3.8)

    /// Confirms permissions again and looks up records; asks Skip or New Copy
    /// when any photo was published to this server, else starts. True when
    /// the run started (the sheet closes).
    func requestPublish() async -> Bool {
        guard canPublish, let library, let service else { return false }
        stopOriginalsCheck()
        isConfirming = true
        startIssue = nil
        defer { isConfirming = false }
        switch await Self.connect(service, keys: library.remoteKeyStore, readsAccount: stacking) {
        case .failed(let result):
            check = .failed(result)
            return false
        case .ready(let client, let info):
            self.client = client
            check = .passed(info)
            guard missing.isEmpty else { return false }
        }
        let records: [Int64: [RemotePublicationRecord]]
        do {
            records = try await library.catalog.publications(address: service.address, versionIDs: versionIDs)
        } catch {
            startIssue = error.localizedDescription
            return false
        }
        let items = versionIDs.map {
            PublishItem(versionID: $0, name: names[$0] ?? "", album: albumChoiceForRun.usesAlbum, stacking: stacking)
        }
        let published = Set(records.keys)
        if !published.isEmpty {
            question = Question(published: published.count, total: items.count, items: items, alreadyPublished: published)
            return false
        }
        start(items: items, skipped: 0)
        return true
    }

    /// Skip (true) or New Copy (false) for the question's photos.
    func answer(skip: Bool) {
        guard let question else { return }
        self.question = nil
        let items = skip ? question.items.filter { !question.alreadyPublished.contains($0.versionID) } : question.items
        start(items: items, skipped: skip ? question.published : 0)
        library?.showsPublishSheet = false
    }

    private func start(items: [PublishItem], skipped: Int) {
        guard let library, let service, let client, let info = serverInfo else { return }
        let choices = PublishChoices(settings: editor.settings, presetID: presetID, album: albumChoiceForRun,
                                     visibility: visibility, stacking: stacking)
        // Remembered when a run starts, never on Cancel (design §3.7).
        if let id = service.id {
            var remembered = choices
            if case .new = remembered.album { remembered.album = .none }
            Task { try? await library.catalog.savePublishChoices(remembered, serviceID: id) }
        }
        defaults.set(service.uuid, forKey: Self.lastServerKey)
        let run = PublishRun(service: service, choices: choices, description: description, items: items,
                             skipped: skipped, videos: skippedVideos)
        runs.append(run)
        execute(run, retrying: false, client: client, accountID: info.ownerID, folderMap: folderMap)
    }

    private func job(client: any RemotePublishDestination, accountID: String?, folderMap: [PublishFolderMapping]) -> PublishJob? {
        guard let library else { return nil }
        var job = PublishJob(catalog: library.catalog,
                             renderer: ExportRenderer(generator: library.previews.generator, watermarks: editor.watermarks),
                             destination: client, accountID: accountID, folderMap: folderMap,
                             endingBound: endingBound, copyNaming: PhotoName.naming)
        job.onFullySent = debugOnFullySent
        return job
    }

    private func execute(_ run: PublishRun, retrying: Bool, client: any RemotePublishDestination, accountID: String?,
                         folderMap: [PublishFolderMapping]) {
        guard let job = job(client: client, accountID: accountID, folderMap: folderMap) else { return }
        jobName = run.service.name
        started = Date()
        runningID = run.id
        runningServerUUID = run.service.uuid
        let total = retrying ? run.retryCandidates.count : run.items.count
        progress = PublishProgress(done: 0, total: total, current: 0, phase: .rendering)
        task = Task {
            let ended = await job.run(run, retrying: retrying) { progress in
                Task { @MainActor in
                    guard self.runningID == run.id, self.progress != nil else { return }
                    self.progress = progress
                }
            }
            finish(ended)
        }
    }

    /// Reports in Activity only, never an alert (design §10): the run's row,
    /// with Show Results….
    private func finish(_ run: PublishRun) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) { runs[index] = run } else { runs.append(run) }
        progress = nil
        started = nil
        task = nil
        runningID = nil
        runningServerUUID = nil
        // An album the run made is remembered as an existing album (R7).
        if case .ready(let id, let name, true) = run.album, let library, let serviceID = run.service.id {
            var choices = run.choices
            choices.album = .existing(id: id, name: name)
            Task { try? await library.catalog.savePublishChoices(choices, serviceID: serviceID) }
            if self.serviceID == serviceID { album = .existing(id: id, name: name) }
        }
        let counts = run.counts
        let lines = PublishText.activityLines(run)
        library?.report(lines.joined(separator: "\n"), action: PublishText.jobTitle(run.service.name),
                        warning: counts.isWarning(ending: run.ending), announcing: lines.first ?? "",
                        actionID: PublishText.resultsActionID(run.id))
        library?.cardImport.publishedRecordsChanged()
    }

    func cancel() {
        task?.cancel()
        if isPublishing { progress?.phase = .ending }
    }

    /// Stop and Quit: waits for the run to end (it bounds itself, design §9).
    func waitUntilDone(timeout: Duration) async {
        await MainActorWait.whileTrue({ task != nil }, timeout: timeout)
    }

    // MARK: Results and Retry Failed (design §10)

    var resultsRun: PublishRun? {
        runs.first { $0.id == resultsRunID } ?? runs.last
    }

    func showResults(_ id: UUID? = nil) {
        resultsRunID = id ?? runs.last?.id
        library?.showsPublishResults = true
    }

    enum RetryRefusal: Equatable { case running, serverRemoved, addressChanged }

    func retryRefusal(_ run: PublishRun) -> RetryRefusal? {
        if isPublishing { return .running }
        guard let current = servers.first(where: { $0.uuid == run.service.uuid }) else { return .serverRemoved }
        return current.address == run.service.address ? nil : .addressChanged
    }

    /// Retry Failed (R23): the run's server, settings and choices.
    func retry(_ id: UUID) {
        guard let library, let run = runs.first(where: { $0.id == id }) else { return }
        library.showsPublishResults = false
        Task {
            await loadServers()
            guard retryRefusal(run) == nil, let service = servers.first(where: { $0.uuid == run.service.uuid }) else { return }
            switch await Self.connect(service, keys: library.remoteKeyStore, readsAccount: run.choices.stacking) {
            case .failed(let result):
                // Reported like any run (design §10.3).
                var ended = run
                ended.ending = .stopped(PublishText.stop(for: result))
                finish(ended)
            case .ready(let client, let info):
                let missing = PublishPermissions.missing(from: info.permissions, album: run.choices.album,
                                                         stacking: run.choices.stacking)
                if let first = missing.all.first {
                    var ended = run
                    ended.ending = .stopped(.missingPermission(first))
                    finish(ended)
                    return
                }
                let map = (try? await library.catalog.publishSettings(serviceID: service.id ?? -1))?.folderMap ?? []
                execute(run, retrying: true, client: client, accountID: info.ownerID, folderMap: map)
            }
        }
    }

    // MARK: Hosting the Server sheet (design §4)

    var savedServers: [RemoteServiceRecord] { servers }
    var serverCatalog: Catalog? { library?.catalog }
    var serverSheetWindow: NSWindow? { library?.window }

    /// Add Server… or Edit Server…: this sheet closes, the Server sheet comes
    /// up, and this one comes back after it (HIG Sheets: one at a time).
    func showServerSheet(editing: Bool, reviewingCertificate: Bool = false) {
        guard let library else { return }
        let mode: ServerSheetModel.Mode = if editing, let service { .edit(service) } else { .add }
        let sheet = ServerSheetModel(mode: mode, host: self, purpose: .publishing, keys: library.remoteKeyStore)
        if reviewingCertificate, case .failed(let result) = check {
            if case .certificateChanged(let summary) = result { sheet.page = .certificate(summary, changed: true) }
            if case .untrustedCertificate(let summary) = result { sheet.page = .certificate(summary, changed: false) }
        }
        serverBeforeSheet = serviceID
        pendingServerSheet = sheet
        library.showsPublishSheet = false
    }

    /// A library sheet closed: the waiting Server sheet comes up, or, after
    /// it, the publish sheet again.
    func sheetDidClose() -> Bool {
        guard let library else { return false }
        if let pending = pendingServerSheet, !library.showsPublishSheet {
            pendingServerSheet = nil
            returnsAfterServerSheet = true
            serverSheet = pending
            return true
        }
        if returnsAfterServerSheet, serverSheet == nil {
            returnsAfterServerSheet = false
            library.showsPublishSheet = true
            return true
        }
        return false
    }

    func serverSheetSaved(_ service: RemoteServiceRecord) async {
        await loadServers()
        serverSheet = nil
        if let saved = servers.first(where: { $0.id == service.id }) { await choose(saved) }
        await library?.cardImport.loadServersAfterPublish()
    }

    func serverSheetCancelled() {
        serverSheet = nil
        if let before = serverBeforeSheet, before != serviceID, let service = servers.first(where: { $0.id == before }) {
            Task { await choose(service) }
        }
    }

    func serverSheetRemove(_ service: RemoteServiceRecord) {}
}
