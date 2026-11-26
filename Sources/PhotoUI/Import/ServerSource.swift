import AppKit
import Observation
import PhotoCore
import os

/// A server import's alert (design §6.2, §6.3).
public struct ServerAlert: Equatable, Identifiable {
    public var title: String
    public var message: String
    public var id: String { title + message }
}

/// A server chosen as the import window's source (issue #271, design §4):
/// the check, the albums, the scope and the photos loaded so far. The window
/// contacts the server only when the person chose it or pressed Rescan
/// (design §2.3).
@MainActor
@Observable
public final class ServerBrowse {
    public let service: RemoteServiceRecord
    @ObservationIgnored public private(set) var client: (any RemotePhotoSource)?
    public internal(set) var isConnecting = true
    /// Why the server can't be browsed now (any of the check's results).
    public internal(set) var failure: ConnectionCheckResult?
    public internal(set) var info: RemoteServerInfo?
    public internal(set) var albums: [RemoteAlbum] = []
    public internal(set) var albumsLoaded = false
    public internal(set) var albumsFailed = false
    public internal(set) var albumID: String?
    public internal(set) var dates: CaptureDateRange?
    public internal(set) var assets: [RemoteAsset] = []
    @ObservationIgnored var assetsByURL: [URL: RemoteAsset] = [:]
    public internal(set) var linked: Set<String> = []
    /// Published to this server from this library (publishing R20): marked
    /// In Library like a linked photo.
    public internal(set) var published: Set<String> = []
    public internal(set) var nextCursor: String?
    public internal(set) var isLoadingPage = false
    public internal(set) var loadedFirstPage = false
    public internal(set) var albumGone = false
    /// The Date Range popover is open (the toolbar item, View ▸ Date Range…).
    public var showsDateRange = false
    /// The project name field: prefilled, then the person's (design §5.3).
    public var projectName = ""
    @ObservationIgnored var projectNameEdited = false
    @ObservationIgnored var connectTask: Task<Void, Never>?
    @ObservationIgnored var pageTask: Task<Void, Never>?
    @ObservationIgnored let thumbnails = RemoteThumbnails()

    init(service: RemoteServiceRecord) {
        self.service = service
    }

    public var address: ServerAddress? { service.serverAddress }
    public var isUnencrypted: Bool { address?.scheme == .http }
    public var hasMorePages: Bool { nextCursor != nil }
    public var album: RemoteAlbum? { albumID.flatMap { id in albums.first { $0.id == id } } }
    public var scopeName: String { album?.name ?? ServerText.allPhotos }
    public var scope: RemoteScope { RemoteScope(albumID: albumID, dates: dates) }

    /// The server's own number for the scope (R10): an album's count; none
    /// for All Photos.
    public var total: Int? { album?.assetCount }

    public var gridState: ServerGridState {
        ServerGridState.of(connecting: isConnecting, failure: failure, loadingFirstPage: !loadedFirstPage,
                           albumGone: albumGone, photoCount: assets.count, inAlbum: albumID != nil,
                           hasRange: dates.map { !$0.isEmpty } ?? false)
    }

    func cancel() {
        connectTask?.cancel()
        pageTask?.cancel()
    }

    /// Imported from this server or published to it from this library (R20).
    public func isInLibrary(_ id: String) -> Bool {
        linked.contains(id) || published.contains(id)
    }

    func setClient(_ client: (any RemotePhotoSource)?) {
        self.client = client
    }
}

extension CardImportModel: ServerSheetHost {
    private static let serverLog = Logger(subsystem: AppBranding.bundleIdentifier, category: "server-import")

    // MARK: Connections

    /// Reads the saved servers (library app only; the importer has none).
    func loadServers() async {
        guard let catalog = library?.catalog else { return }
        do {
            servers = try await catalog.remoteServices()
        } catch {
            Self.serverLog.error("Reading servers failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Makes `service` the source and checks it (design §2.3).
    public func chooseServer(_ service: RemoteServiceRecord) {
        guard !isImporting else { return }
        doneText = nil
        closeServer()
        source = nil
        let browse = ServerBrowse(service: service)
        browse.projectName = RemoteProjectName.prefill(connection: service.name, scope: browse.scopeName)
        self.browse = browse
        connectServer()
    }

    /// Rescan (⌘R) and Try Again: a card or folder is scanned again; a server
    /// is checked again and read from its first page, keeping the selection
    /// of photos still listed (design §4.6).
    public func rescanSource() {
        if browse != nil {
            connectServer(keepingSelection: true)
        } else {
            rescan(keepingPicks: true)
        }
    }

    /// Leaves the server: its requests stop.
    func closeServer() {
        browse?.cancel()
        if browse != nil {
            browse = nil
            shots = []
            selection = []
        }
    }

    /// The check, then the albums and the first page (Try Again and Rescan
    /// run it too). `keepingSelection`: Rescan keeps photos still listed.
    public func connectServer(keepingSelection: Bool = false) {
        guard let browse, let library else { return }
        browse.cancel()
        let kept = keepingSelection ? selection : []
        browse.isConnecting = true
        browse.failure = nil
        browse.albumGone = false
        let service = browse.service
        let keys = library.remoteKeyStore
        browse.connectTask = Task {
            let outcome = await Self.check(service, keys: keys)
            guard !Task.isCancelled, self.browse === browse else { return }
            browse.isConnecting = false
            switch outcome {
            case .failed(let result):
                // No grid will appear: a later one must not take the keyboard (N-4).
                focusesGridWhenShown = false
                browse.failure = result
                browse.setClient(nil)
                shots = []
                selection = []
            case .ready(let client, let info):
                browse.setClient(client)
                browse.info = info
                loadAlbums()
                reloadPhotos(keeping: kept)
            }
        }
    }

    enum CheckOutcome {
        case ready(any RemotePhotoSource, RemoteServerInfo)
        case failed(ConnectionCheckResult)
    }

    /// The key from the store, a client, and the check (R2).
    /// Off the main actor: the Keychain may ask the person (code review C8).
    nonisolated static func check(_ service: RemoteServiceRecord, keys: any RemoteKeyStore) async -> CheckOutcome {
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
        let client: ImmichClient
        do {
            client = try ImmichClient(connection: connection)
        } catch {
            return .failed(.unreachable(reason: "", isLocalHost: address.isLocalNetworkHost))
        }
        let result = await client.check()
        guard case .passed(let info) = result else { return .failed(result) }
        return .ready(client, info)
    }

    func loadAlbums() {
        guard let browse, let client = browse.client else { return }
        browse.albumsLoaded = false
        browse.albumsFailed = false
        Task {
            do throws(RemoteError) {
                let albums = try await client.albums()
                guard self.browse === browse else { return }
                browse.albums = albums
            } catch {
                guard self.browse === browse else { return }
                browse.albumsFailed = true
                // One warning per failed load (design §15, DQ-6).
                let name = browse.service.name
                report(String(localized: "Couldn't load the albums of “\(name)”: \(Self.reason(error)). Choose Rescan to try again.",
                              comment: "Activity: a server's album list could not be read; the server's name and the reason"),
                       name: name, warning: true)
            }
            browse.albumsLoaded = true
        }
    }

    // MARK: Scope and pages (R9, R10, design §4.2 to §4.4)

    /// Chooses All Photos (nil) or an album: the grid reloads from the top,
    /// the selection is cleared and the project name follows.
    public func chooseAlbum(_ id: String?) {
        guard let browse, browse.albumID != id, !isImporting else { return }
        browse.albumID = id
        if !browse.projectNameEdited {
            let noteWasShown = addsToExistingProject
            browse.projectName = RemoteProjectName.prefill(connection: browse.service.name, scope: browse.scopeName)
            announceProjectNote(wasShown: noteWasShown)
        }
        doneText = nil
        reloadPhotos(keeping: [])
    }

    public func setDateRange(_ range: CaptureDateRange?) {
        guard let browse, !isImporting else { return }
        browse.dates = range?.isEmpty == true ? nil : range
        doneText = nil
        reloadPhotos(keeping: [])
    }

    /// The person typed in the project name field.
    public func setServerProjectName(_ name: String) {
        guard let browse else { return }
        let noteWasShown = addsToExistingProject
        browse.projectName = name
        browse.projectNameEdited = true
        announceProjectNote(wasShown: noteWasShown)
    }

    /// Whether "Adds to the existing project with this name." shows under the
    /// server's Project name field (design §15 DQ-13): a server source, Add to
    /// is New Project, and the name the import would use is a loaded
    /// project's. Computed, never stored; it follows the field and
    /// `library.projects`.
    public var addsToExistingProject: Bool {
        guard let browse, let library else { return false }
        return RemoteProjectName.addsToExistingProject(
            typed: browse.projectName, address: browse.address?.normalized ?? browse.service.address,
            existingProjectID: existingProjectID, projectNames: library.projects.lazy.map(\.project.name))
    }

    /// Announces the note once, at medium priority, when a change of the
    /// name (typing, or the prefill after an album change) makes it appear;
    /// never when it goes, and not for the window, source or Add to changing
    /// (the field's hint covers those).
    private func announceProjectNote(wasShown: Bool) {
        guard !wasShown, addsToExistingProject else { return }
        AccessibilityText.announce(ServerText.addsToExistingProject, priority: .medium)
    }

    /// Loads the scope's first page.
    func reloadPhotos(keeping kept: Set<URL>) {
        guard let browse else { return }
        browse.pageTask?.cancel()
        browse.assets = []
        browse.assetsByURL = [:]
        browse.nextCursor = nil
        browse.loadedFirstPage = false
        browse.albumGone = false
        browse.isLoadingPage = false
        shots = []
        selection = []
        loadPage(keeping: kept)
    }

    /// Asked by the grid when the visible area comes within a screen of the
    /// last loaded photo (D10). Never while a page is out.
    public func loadNextPageIfNeeded() {
        guard let browse, browse.hasMorePages, !browse.isLoadingPage, browse.failure == nil else { return }
        loadPage(keeping: [])
    }

    private func loadPage(keeping kept: Set<URL>) {
        guard let browse, let client = browse.client, let address = browse.address, let owner = browse.info?.ownerID else {
            return
        }
        let cursor = browse.nextCursor
        let scope = browse.scope
        let catalog = library?.catalog
        browse.isLoadingPage = true
        browse.pageTask = Task {
            do throws(RemoteError) {
                let page = try await client.page(scope: scope, cursor: cursor, ownerID: owner)
                // Marks come from the catalog; if it can't be read, none are shown
                // and the importer still skips linked photos.
                let linked = (try? await catalog?.linkedRemoteIDs(provider: browse.service.provider,
                                                                  address: address.normalized,
                                                                  among: page.assets.map(\.id))) ?? []
                let published = (try? await catalog?.publishedRemoteIDs(provider: browse.service.provider,
                                                                        address: address.normalized,
                                                                        among: page.assets.map(\.id))) ?? []
                guard !Task.isCancelled, self.browse === browse else { return }
                browse.isLoadingPage = false
                let isFirst = !browse.loadedFirstPage
                browse.loadedFirstPage = true
                browse.linked.formUnion(linked)
                browse.published.formUnion(published)
                // A page may repeat a photo the last one ended with (offsets
                // move when photos are added): appended once.
                let new = page.assets.filter { browse.assetsByURL[$0.gridURL] == nil }
                for asset in new { browse.assetsByURL[asset.gridURL] = asset }
                browse.assets += new
                browse.nextCursor = page.nextCursor
                shots += new.map { $0.shot(linked: browse.isInLibrary($0.id)) }
                if !kept.isEmpty {
                    selection.formUnion(new.filter { !browse.isInLibrary($0.id) }.map(\.gridURL).filter(kept.contains))
                }
                if isFirst {
                    AccessibilityText.announce(String(localized: "\(browse.assets.count) photos loaded",
                                                      comment: "VoiceOver: a server's first page arrived"),
                                               priority: .medium)
                }
            } catch {
                guard self.browse === browse else { return }
                browse.isLoadingPage = false
                if error == .cancelled || Task.isCancelled { return }
                switch error {
                case .status(400) where browse.albumID != nil && !browse.loadedFirstPage:
                    browse.albumGone = true
                case .status(401), .status(403), .certificate:
                    browse.failure = Self.failure(for: error)
                default:
                    if browse.loadedFirstPage {
                        report(String(localized: "Couldn't load more photos from “\(browse.service.name)”: \(Self.reason(error)). Scroll to try again."),
                               name: browse.service.name, warning: true)
                    } else {
                        browse.failure = Self.failure(for: error)
                    }
                }
                browse.loadedFirstPage = true
            }
        }
    }

    static func failure(for error: RemoteError) -> ConnectionCheckResult {
        switch error {
        case .status(401), .status(403): .keyRejected
        case .certificate(.changed(let summary)), .certificate(.untrusted(let summary)): .certificateChanged(summary)
        case .unreachable(let reason): .unreachable(reason: reason, isLocalHost: false)
        default: .notImmich
        }
    }

    /// A plain reason for Activity, never a developer's name for the error
    /// (code review C9).
    static func reason(_ error: RemoteError) -> String {
        switch error {
        case .unreachable(let reason), .disk(let reason): reason
        case .status(let code): HTTPURLResponse.localizedString(forStatusCode: code)
        case .certificate: String(localized: "The server's certificate has changed", comment: "Server check: certificate changed")
        case .malformed, .notAllowed, .transportRefused, .tooLarge, .cancelled:
            String(localized: "The server's answer could not be read", comment: "Activity: a server's answer was not what the app reads; ends a sentence")
        }
    }

    /// The remote asset a grid shot stands for.
    public func remoteAsset(for url: URL) -> RemoteAsset? {
        browse?.assetsByURL[url]
    }

    /// A server photo's thumbnail, at most a handful at once, cancelled with
    /// the cell's task (design §4.4). Memory only (R7).
    func remoteThumbnail(_ url: URL, pixelSize: Int, colorSpace: CGColorSpace?) async -> CGImage? {
        guard let browse, let client = browse.client, let id = RemoteAssetURL.assetID(of: url) else { return nil }
        return await browse.thumbnails.thumbnail(assetID: id, client: client, pixelSize: pixelSize, colorSpace: colorSpace)
    }

    // MARK: Importing (R12 to R21)

    func startServerImport() {
        guard let browse, let client = browse.client, let address = browse.address, let library, importTask == nil else {
            return
        }
        let assets = selectedShots.compactMap { browse.assetsByURL[$0.id] }
        guard !assets.isEmpty else { return }
        let job = jobCode.trimmingCharacters(in: .whitespaces)
        if !job.isEmpty {
            recentJobCodes = Array(([job] + recentJobCodes.filter { $0 != job }).prefix(10))
        }
        let project: RemoteProjectChoice = existingProjectID.map(RemoteProjectChoice.existing) ?? .named(browse.projectName)
        let options = RemoteImportOptions(
            destination: destination, template: template, project: project, jobCode: job, firstCounter: counter,
            metadata: presets.first { $0.id == presetID }?.values,
            link: RemoteLinkTarget(provider: browse.service.provider, address: address.normalized,
                                   serviceID: browse.service.id))
        let importer = RemoteImporter(catalog: library.catalog, sidecars: library.sidecars, source: client,
                                      metadataReader: metadataReader)
        let name = browse.service.name
        serverImportName = name
        doneText = nil
        alertText = nil
        serverAlert = nil
        progress = CopyImportProgress()
        importTask = Task {
            let result = await importer.run(assets, options: options) { update in
                Task { @MainActor in
                    guard self.importTask != nil else { return }
                    self.progress = update
                }
            }
            counter = result.nextCounter
            importTask = nil
            progress = nil
            await finishServerImport(result, name: name)
        }
    }

    private func finishServerImport(_ result: RemoteImportResult, name: String) async {
        let report = RemoteImportReport(result)
        self.report(ServerText.activityLines(report, name: name), name: name, warning: report.isWarning)
        if let alert = ServerText.alert(result, name: name) {
            serverAlert = ServerAlert(title: alert.title, message: alert.message)
        } else if result.stop == .stopped {
            doneText = String(localized: "Stopped after \(result.imported) photos", comment: "Import window subtitle after Stop")
        } else if result.imported == 0 {
            // As Activity says it (QA Q4).
            doneText = String(localized: "No photos were imported", comment: "Import window subtitle after a server import that imported nothing")
        } else {
            doneText = String(localized: "Imported \(result.imported) photos", comment: "Import window subtitle after a server import")
        }
        await library?.didFinishCopyImport(CopyImportResult(project: result.project,
                                                            insertedVersionIDs: result.insertedVersionIDs,
                                                            nextCounter: result.nextCounter))
        // Marks change: read the server again (design §4.7).
        let done = doneText
        connectServer(keepingSelection: false)
        doneText = done
    }

    func report(_ text: String, name: String, warning: Bool) {
        library?.report(text, action: Self.activityTitle(name: name), warning: warning)
    }

    // MARK: Adding, editing and removing (R1, R4)

    public func showAddServer() {
        guard let library, !isImporting else { return }
        serverSheet = ServerSheetModel(mode: .add, host: self, purpose: .importing, keys: library.remoteKeyStore)
    }

    /// The chosen server is being published to (design §4): it can't be
    /// edited or removed until the run ends.
    public var serverIsBusyPublishing: Bool {
        guard let uuid = library?.publishingServerUUID, let browse else { return false }
        return browse.service.uuid == uuid
    }

    public func showEditServer(reviewingCertificate: Bool = false) {
        guard let library, let service = browse?.service, !isImporting, !serverIsBusyPublishing else { return }
        let sheet = ServerSheetModel(mode: .edit(service), host: self, purpose: .importing, keys: library.remoteKeyStore)
        if reviewingCertificate, case .certificateChanged(let summary)? = browse?.failure {
            sheet.page = .certificate(summary, changed: true)
        }
        serverSheet = sheet
    }

    public func askToRemoveServer(_ service: RemoteServiceRecord? = nil) {
        guard !isImporting, let service = service ?? browse?.service,
              service.uuid != library?.publishingServerUUID else { return }
        removingServer = service
    }

    /// After Remove: the key leaves the Keychain, then the row (R4). The links
    /// stay (R16). If the Keychain refuses, nothing is removed and an alert
    /// says so (design §15, DQ-5); the server stays listed and chosen.
    public func removeServer(_ service: RemoteServiceRecord) {
        removingServer = nil
        guard let library, let id = service.id else { return }
        let keys = library.remoteKeyStore
        Task {
            do {
                if let refusal = try await library.catalog.removeRemoteService(service, keys: keys) {
                    serverAlert = ServerText.removalRefused(name: service.name, keychain: refusal.message)
                    return
                }
            } catch {
                Self.serverLog.error("Removing a server failed: \(String(describing: error), privacy: .public)")
            }
            if browse?.service.id == id { closeServer() }
            await loadServers()
            library.remoteServersChanged()
        }
    }

    /// The sheet saved a server: it becomes the source.
    public func serverSheetSaved(_ service: RemoteServiceRecord) async {
        await loadServers()
        library?.remoteServersChanged()
        serverSheet = nil
        chooseServer(service)
        // The keyboard goes to the grid once it is in the window, after the
        // first page lands (design §7, design review S4).
        focusesGridWhenShown = true
    }

    /// The Server sheet went: a Remove Server… asked from it asks now (S3).
    public func serverSheetDidDismiss() {
        guard let service = removalAfterSheet else { return }
        removalAfterSheet = nil
        askToRemoveServer(service)
    }

    // MARK: Publishing (issue #28)

    /// A publish run wrote records: photos the window lists that are now
    /// published are marked In Library in place, and unchecked (design §11).
    public func publishedRecordsChanged() {
        guard let browse, let address = browse.address, let catalog = library?.catalog, !browse.assets.isEmpty else { return }
        let ids = browse.assets.map(\.id)
        Task {
            guard let published = try? await catalog.publishedRemoteIDs(provider: browse.service.provider,
                                                                        address: address.normalized, among: ids),
                  self.browse === browse, !published.subtracting(browse.published).isEmpty else { return }
            browse.published.formUnion(published)
            shots = shots.map { shot in
                guard let asset = browse.assetsByURL[shot.id], browse.isInLibrary(asset.id) else { return shot }
                var marked = shot
                marked.files = marked.files.map { file in
                    var file = file
                    file.isDuplicate = true
                    return file
                }
                return marked
            }
            selection = selection.filter { url in browse.assetsByURL[url].map { !browse.isInLibrary($0.id) } ?? true }
        }
    }

    /// The servers again, after Publish added or changed one.
    public func loadServersAfterPublish() async {
        await loadServers()
    }

    // MARK: Hosting the Server sheet (publishing design §4)

    public var savedServers: [RemoteServiceRecord] { servers }
    public var serverCatalog: Catalog? { library?.catalog }
    public var serverSheetWindow: NSWindow? { window }

    public func serverSheetCancelled() {
        serverSheet = nil
    }

    /// Remove Server… asked from the sheet: asked once the sheet has gone (S3).
    public func serverSheetRemove(_ service: RemoteServiceRecord) {
        removalAfterSheet = service
        serverSheet = nil
    }

    /// Stop and Quit: waits for the stopped import to remove its partial file
    /// and finish the photo it was cataloging, or `timeout` (code review C7).
    public func waitUntilDone(timeout: Duration) async {
        await MainActorWait.whileTrue({ importTask != nil }, timeout: timeout)
    }
}

/// Server thumbnails in memory only (R7), at most six requests at once, kept
/// up to a bound; decoded and converted to the window's color space off the
/// main thread before they reach a layer.
actor RemoteThumbnails {
    private var cache: [String: CGImage] = [:]
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private static let limit = 2000
    private static let concurrent = 6

    func thumbnail(assetID: String, client: any RemotePhotoSource, pixelSize: Int, colorSpace: CGColorSpace?) async
        -> CGImage? {
        if let cached = cache[assetID] { return cached }
        await acquire()
        defer { release() }
        guard !Task.isCancelled else { return nil }
        guard let data = try? await client.thumbnail(assetID: assetID) else { return nil }
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            guard let colorSpace else { return decoded }
            return PreviewDiskCache.converted(decoded, to: colorSpace) ?? decoded
        }.value
        if let image {
            if cache.count > Self.limit { cache.removeAll() }
            cache[assetID] = image
        }
        return image
    }

    private func acquire() async {
        if running < Self.concurrent {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
