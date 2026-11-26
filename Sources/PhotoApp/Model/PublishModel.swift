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

    /// The Skip / New Copy question (design §8), with the server, client and
    /// check it was asked for, so the answer starts that run (review F1).
    struct Question: Identifiable {
        let id = UUID()
        let published: Int
        let total: Int
        let items: [PublishItem]
        let alreadyPublished: Set<Int64>
        let service: RemoteServiceRecord
        let client: ImmichClient
        let info: PublishServerInfo
    }

    // MARK: The sheet

    private(set) var page: Page = .main
    private(set) var servers: [RemoteServiceRecord] = []
    /// Each opening of the sheet, and each dismissal, is a new session: an
    /// answer applies only to the session it was asked in (review F1).
    @ObservationIgnored private var session = 0
    /// The session Publish was pressed in, while its check and lookup run.
    private var confirmingSession: Int?
    @ObservationIgnored private var confirmTask: Task<Bool, Never>?
    private(set) var serviceID: Int64?
    private(set) var check: CheckState = .idle
    @ObservationIgnored private(set) var client: ImmichClient?
    private(set) var albums: [RemoteAlbum] = []
    private(set) var albumsState: AlbumsState = .notLoaded
    /// The album, visibility, stacking and render settings chosen. A change
    /// of album leaves Check Originals' result as it is (design §7).
    var album: PublishAlbumChoice = .none
    var newAlbumName = ""
    var visibility: PublishVisibility = .timeline
    var stacking = true {
        didSet {
            guard stacking != oldValue else { return }
            resetOriginals()
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
    var isConfirming: Bool { confirmingSession != nil && confirmingSession == session }
    /// The sheet is reading its servers (its empty state waits for them, review F9).
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
    /// One publish at a time, held from a run's start (a retry's check
    /// included) until it has ended (R21, code review C2).
    private(set) var slot = PublishSlot()
    /// Retry Failed was pressed and the servers are being read again.
    private(set) var isRetryPending = false
    /// The server the running publish goes to (its uuid), nil when none runs.
    private(set) var runningServerUUID: String?
    /// Every run since launch, newest last (R23: Retry Failed until quit).
    private(set) var runs: [PublishRun] = []
    var resultsRunID: UUID?
    /// Debug script: the client whose server holds the next upload; tests stop there.
    @ObservationIgnored var debugOnFullySent: (@Sendable () -> Void)?
    /// Debug script and tests: the ending bound (the quit wait's 10 s otherwise).
    @ObservationIgnored var endingBound: Duration = .seconds(10)

    /// A run or retry holds the slot: its Activity job, Stop and the quit
    /// question apply (a retry's check included, review D-2).
    var isPublishing: Bool { slot.isBusy }
    /// The run is ending: Stop was asked, or a fault met. Nothing clears it
    /// before the run has ended (design §9, review F2).
    var isEnding: Bool { slot.isStopping || progress?.phase == .ending }

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
        session += 1
        let opened = session
        cancelSheetWork()
        page = .main
        description = ""
        question = nil
        startIssue = nil
        // Nothing from the last opening counts until this one has checked
        // its server (review F9).
        check = .checking
        client = nil
        albums = []
        albumsState = .notLoaded
        editor.library = library
        editor.show(first: targets.first { !$0.isVideo }, versionID: versionIDs.first)
        isLoading = true
        Task {
            await refreshPresets()
            await loadServers()
            guard session == opened else { return }
            isLoading = false
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

    /// The saved servers changed in either window (review F4): Retry
    /// Failed's reasons and the sheet's menu follow at once.
    func serversChanged() {
        Task { await loadServers() }
    }

    /// Chooses a server and runs the check. Its remembered choices are
    /// loaded unless `keepingChoices` (back from editing the chosen server:
    /// the form stays as the person left it, review F5); its folder map,
    /// links and names are read again either way.
    func choose(_ service: RemoteServiceRecord, keepingChoices: Bool = false) async {
        guard let library, let id = service.id else { return }
        let opened = session
        serviceID = id
        // Dimmed until this server's check passes (review F9).
        checkTask?.cancel()
        albumsTask?.cancel()
        check = .checking
        client = nil
        albums = []
        albumsState = .notLoaded
        resetOriginals()
        let saved = (try? await library.catalog.publishSettings(serviceID: id)) ?? RemotePublishSettings()
        guard session == opened, serviceID == id else { return }
        if !keepingChoices {
            let choices = saved.choices ?? .firstRun(exportSettings: library.export.settings)
            editor.settings = choices.settings
            presetID = choices.presetID
            album = choices.album
            newAlbumName = album.name ?? ""
            if case .new = album { album = .none }
            visibility = choices.visibility
            stacking = choices.stacking
        }
        folderMap = saved.folderMap
        let sources = (try? await library.catalog.publishSources(versionIDs: versionIDs, address: service.address)) ?? [:]
        let details = (try? await ExportJob(catalog: library.catalog, renderer: ExportRenderer(), copyNaming: PhotoName.naming)
            .items(for: versionIDs)) ?? []
        guard session == opened, serviceID == id else { return }
        self.sources = sources
        noneLinked = !sources.values.contains { !$0.linkedAssetIDs.isEmpty }
        names = Dictionary(details.map { ($0.versionID, $0.reportName) }, uniquingKeysWith: { first, _ in first })
        runCheck()
    }

    /// The check of design §3.3: contacts only the chosen server.
    func runCheck() {
        guard let library, let service else { return }
        checkTask?.cancel()
        albumsTask?.cancel()
        check = .checking
        client = nil
        albums = []
        albumsState = .notLoaded
        let keys = library.remoteKeyStore
        let readsAccount = stacking
        let opened = session
        checkTask = Task {
            let outcome = await Self.connect(service, keys: keys, readsAccount: readsAccount)
            guard !Task.isCancelled, session == opened, self.serviceID == service.id else { return }
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

    /// Publish N Photos is enabled (design §3.8): never over what an earlier
    /// opening or server left (review F9).
    var canPublish: Bool {
        guard !isLoading, client != nil, serverInfo != nil, missing.isEmpty, !isPublishing, !isConfirming,
              !versionIDs.isEmpty else { return false }
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

    /// Done: saved to the server at once, even if the publish is cancelled
    /// (design §6), each server path as kept (a trailing slash dropped,
    /// review F6).
    func closeFolderMapPage(saving: Bool) {
        defer { page = .main }
        guard saving, folderMapCanSave, let library, let id = serviceID else { return }
        let map = editingMap.map(\.kept)
        if map != folderMap { resetOriginals() }
        folderMap = map
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
            // The new section's server field takes the keyboard (design §6, review F17).
            focusedMapping = mapping.id
        }
    }

    /// The folder map pair whose server field has the keyboard.
    var focusedMapping: UUID?

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
        resetOriginals()
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
        resetOriginals()
    }

    /// Check Originals' result or check in progress no longer applies (a
    /// change of server, folder map or stacking box, a new opening, the
    /// sheet closing): cancelled and cleared, so nothing stale comes back
    /// (review F11).
    private func resetOriginals() {
        originalsTask?.cancel()
        originalsTask = nil
        originals = .notRun
    }

    /// The sheet's own requests stop: its check, albums, Check Originals and
    /// a Publish being confirmed.
    private func cancelSheetWork() {
        confirmTask?.cancel()
        confirmTask = nil
        confirmingSession = nil
        checkTask?.cancel()
        albumsTask?.cancel()
        resetOriginals()
    }

    /// The sheet went away. Closed for the Server sheet in its place, its
    /// state stays for its return; closed any other way (Cancel, Esc, a
    /// run started), nothing it asked for may act any more (review F1).
    func sheetClosed() {
        resetOriginals()
        guard pendingServerSheet == nil, !returnsAfterServerSheet else { return }
        session += 1
        cancelSheetWork()
        question = nil
    }

    // MARK: Pressing Publish (design §3.8)

    /// Publish N Photos: confirms permissions again and looks up records
    /// (design §3.8), closing the sheet when the run starts. Cancel, or the
    /// sheet closing any other way, stops it (review F1). True when started.
    @discardableResult
    func confirm() async -> Bool {
        guard canPublish else { return false }
        confirmTask?.cancel()
        let task = Task { await requestPublish() }
        confirmTask = task
        let started = await task.value
        if started { library?.showsPublishSheet = false }
        return started
    }

    /// Asks Skip or New Copy when any photo was published to this server,
    /// else starts. After every wait it gives up unless the same opening of
    /// the sheet is still there, and it works with the server and client it
    /// checked, never one chosen since.
    private func requestPublish() async -> Bool {
        guard canPublish, let library, let service else { return false }
        let opened = session
        // Publishing while a check runs cancels it (design §7).
        resetOriginals()
        confirmingSession = opened
        startIssue = nil
        defer { if confirmingSession == opened { confirmingSession = nil } }
        let outcome = await Self.connect(service, keys: library.remoteKeyStore, readsAccount: stacking)
        guard !Task.isCancelled, session == opened, serviceID == service.id else { return false }
        let client: ImmichClient
        let info: PublishServerInfo
        switch outcome {
        case .failed(let result):
            self.client = nil
            check = .failed(result)
            return false
        case .ready(let ready, let readyInfo):
            client = ready
            info = readyInfo
            self.client = ready
            check = .passed(readyInfo)
            guard missing.isEmpty else { return false }
        }
        let records: [Int64: [RemotePublicationRecord]]
        do {
            records = try await library.catalog.publications(address: service.address, versionIDs: versionIDs)
        } catch {
            guard session == opened else { return false }
            startIssue = error.localizedDescription
            return false
        }
        guard !Task.isCancelled, session == opened else { return false }
        let items = versionIDs.map {
            PublishItem(versionID: $0, name: names[$0] ?? "", album: albumChoiceForRun.usesAlbum, stacking: stacking)
        }
        let published = Set(records.keys)
        if !published.isEmpty {
            question = Question(published: published.count, total: items.count, items: items, alreadyPublished: published,
                                service: service, client: client, info: info)
            return false
        }
        return start(items: items, skipped: 0, service: service, client: client, info: info)
    }

    /// Skip (true) or New Copy (false) for the question's photos.
    func answer(skip: Bool) {
        guard let question else { return }
        self.question = nil
        let items = skip ? question.items.filter { !question.alreadyPublished.contains($0.versionID) } : question.items
        if start(items: items, skipped: skip ? question.published : 0, service: question.service,
                 client: question.client, info: question.info) {
            library?.showsPublishSheet = false
        }
    }

    /// Starts a run; false, with the reason in the sheet, when another
    /// publish holds the slot (R21).
    private func start(items: [PublishItem], skipped: Int, service: RemoteServiceRecord, client: ImmichClient,
                       info: PublishServerInfo) -> Bool {
        guard let library else { return false }
        let choices = PublishChoices(settings: editor.settings, presetID: presetID, album: albumChoiceForRun,
                                     visibility: visibility, stacking: stacking)
        let run = PublishRun(service: service, choices: choices, description: description, items: items,
                             skipped: skipped, videos: skippedVideos)
        guard claim(run) else {
            startIssue = PublishText.retryRefusal(.running)
            return false
        }
        // Remembered when a run starts, never on Cancel (design §3.7).
        if let id = service.id {
            var remembered = choices
            if case .new = remembered.album { remembered.album = .none }
            Task { try? await library.catalog.savePublishChoices(remembered, serviceID: id) }
        }
        defaults.set(service.uuid, forKey: Self.lastServerKey)
        runs.append(run)
        let map = folderMap
        task = Task { await execute(run, retrying: false, client: client, accountID: info.ownerID, folderMap: map) }
        return true
    }

    private func job(client: any RemotePublishDestination, accountID: String?, folderMap: [PublishFolderMapping]) -> PublishJob? {
        guard let library else { return nil }
        var job = PublishJob(catalog: library.catalog,
                             renderer: ExportRenderer(generator: library.previews.generator, watermarks: editor.watermarks),
                             destination: client, accountID: accountID, folderMap: folderMap,
                             endingBound: endingBound, copyNaming: PhotoName.naming)
        job.onFullySent = debugOnFullySent
        // Each upload is marked In Library in the import window as it is
        // recorded, not when the run ends (design §11, review F14).
        job.onRecorded = { [weak library] _ in Task { @MainActor in library?.cardImport.publishedRecordsChanged() } }
        return job
    }

    /// Takes the slot for `run` and shows its Activity job (R21): from here
    /// until `finish`, nothing else publishes, and Stop and the quit question
    /// apply.
    private func claim(_ run: PublishRun, phase: PublishProgress.Phase = .rendering, total: Int? = nil) -> Bool {
        guard slot.claim(run.id) else { return false }
        jobName = run.service.name
        started = Date()
        runningServerUUID = run.service.uuid
        progress = PublishProgress(done: 0, total: total ?? run.items.count, current: 0, phase: phase)
        return true
    }

    /// Runs `run` (it holds the slot) and finishes it.
    private func execute(_ run: PublishRun, retrying: Bool, client: any RemotePublishDestination, accountID: String?,
                         folderMap: [PublishFolderMapping]) async {
        guard let job = job(client: client, accountID: accountID, folderMap: folderMap) else {
            var ended = run
            ended.ending = .stopped(.stopped)
            ended.endedAt = Date()
            return finish(ended)
        }
        if retrying { progress?.total = run.retryCandidates.count }
        let ended = await job.run(run, retrying: retrying) { progress in
            Task { @MainActor in
                guard self.slot.holder == run.id, let current = self.progress else { return }
                // A report sent before the stop may arrive after it (review F2).
                self.progress = current.followed(by: progress)
            }
        }
        finish(ended)
    }

    /// Reports in Activity only, never an alert (design §10): the run's row,
    /// with Show Results…. Releases the slot.
    private func finish(_ run: PublishRun) {
        var run = run
        if run.endedAt == nil { run.endedAt = Date() }
        if let index = runs.firstIndex(where: { $0.id == run.id }) { runs[index] = run } else { runs.append(run) }
        progress = nil
        started = nil
        task = nil
        runningServerUUID = nil
        slot.release(run.id)
        // An album the run made is remembered as an existing album (R7): the
        // album only, and only while no later run to that server has started
        // (review F18).
        if case .ready(let id, let name, true) = run.album, let library, let serviceID = run.service.id,
           run.mayRememberItsAlbum(among: runs) {
            Task { try? await library.catalog.rememberMadeAlbum(id: id, name: name, serviceID: serviceID) }
            if self.serviceID == serviceID, !library.showsPublishSheet || album.name == name {
                album = .existing(id: id, name: name)
            }
        }
        let counts = run.counts
        let lines = PublishText.activityLines(run)
        library?.report(lines.joined(separator: "\n"), action: PublishText.jobTitle(run.service.name),
                        warning: counts.isWarning(ending: run.ending), announcing: lines.first ?? "",
                        actionID: PublishText.resultsActionID(run.id))
        library?.cardImport.publishedRecordsChanged()
    }

    /// Stop (Activity, File ▸ Stop Publishing, Stop and Quit): the run ends
    /// by R17's rule, showing Stopping until it has (design §9, review D-1).
    func cancel() {
        guard isPublishing else { return }
        slot.stop()
        progress?.phase = .ending
        task?.cancel()
    }

    /// Stop and Quit: waits for the run to end (it bounds itself, design §9).
    func waitUntilDone(timeout: Duration) async {
        await MainActorWait.whileTrue({ task != nil }, timeout: timeout)
    }

    // MARK: Results and Retry Failed (design §10)

    /// Runs that have ended, oldest first: the results, the Run pop-up and
    /// File ▸ Publish Results… never show one still going (review F8).
    var endedRuns: [PublishRun] {
        runs.filter { $0.ending != nil && $0.id != slot.holder }
    }

    var resultsRun: PublishRun? {
        let ended = endedRuns
        return ended.first { $0.id == resultsRunID } ?? ended.last
    }

    func showResults(_ id: UUID? = nil) {
        guard let run = endedRuns.first(where: { $0.id == id }) ?? endedRuns.last else { return }
        resultsRunID = run.id
        library?.showsPublishResults = true
    }

    /// The results sheet appeared: the servers are read again, so Retry
    /// Failed's reason is current (review F4).
    func resultsAppeared() {
        serversChanged()
    }

    enum RetryRefusal: Equatable { case running, serverRemoved, addressChanged }

    func retryRefusal(_ run: PublishRun) -> RetryRefusal? {
        if isPublishing { return .running }
        guard let current = servers.first(where: { $0.uuid == run.service.uuid }) else { return .serverRemoved }
        return current.address == run.service.address ? nil : .addressChanged
    }

    /// Retry Failed (R23): the run's server, settings and choices. The
    /// servers are read again first; a refusal found then leaves the sheet
    /// open with its reason (review F4). Otherwise the retry takes the slot
    /// at once and its server check is part of the run, in Activity with
    /// Stop (review D-2), so nothing else can start meanwhile (code review C2).
    func retry(_ id: UUID) {
        guard let library, !isRetryPending, !isPublishing, let run = runs.first(where: { $0.id == id }) else { return }
        isRetryPending = true
        Task {
            await loadServers()
            isRetryPending = false
            guard retryRefusal(run) == nil, let service = servers.first(where: { $0.uuid == run.service.uuid }),
                  claim(run, phase: .checking, total: run.retryCandidates.count) else { return }
            library.showsPublishResults = false
            task = Task { await retryRun(run, service: service) }
        }
    }

    /// A retry holding the slot: its check, then the run. A check that fails
    /// ends it, saying what the check found (review D-5).
    private func retryRun(_ run: PublishRun, service: RemoteServiceRecord) async {
        guard let library else { return }
        let outcome = await Self.connect(service, keys: library.remoteKeyStore, readsAccount: run.choices.stacking)
        var ended = run
        ended.endedAt = Date()
        if Task.isCancelled {
            ended.ending = .stopped(.stopped)
            return finish(ended)
        }
        switch outcome {
        case .failed(let result):
            ended.ending = .stopped(.checkFailed(result))
            finish(ended)
        case .ready(let client, let info):
            let missing = PublishPermissions.missing(from: info.permissions, album: run.choices.album,
                                                     stacking: run.choices.stacking)
            if let first = missing.all.first {
                ended.ending = .stopped(.missingPermission(first))
                return finish(ended)
            }
            let map = (try? await library.catalog.publishSettings(serviceID: service.id ?? -1))?.folderMap ?? []
            if Task.isCancelled {
                ended.ending = .stopped(.stopped)
                return finish(ended)
            }
            let phase: PublishProgress.Phase = isEnding ? .ending : .rendering
            progress?.phase = phase
            await execute(run, retrying: true, client: client, accountID: info.ownerID, folderMap: map)
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

    /// Back from the Server sheet: the server saved is chosen. Editing the
    /// one already chosen keeps every choice as the person left it; only a
    /// move to another server (a new one included) loads that server's
    /// remembered choices (design §4, review F5).
    func serverSheetSaved(_ service: RemoteServiceRecord) async {
        await loadServers()
        serverSheet = nil
        if let saved = servers.first(where: { $0.id == service.id }) {
            await choose(saved, keepingChoices: saved.id == serverBeforeSheet)
        }
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
