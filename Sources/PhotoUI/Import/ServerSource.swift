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
    /// The server as the window last read it: its address and trusted
    /// certificate are the ones every check contacts (publishing design D-18);
    /// a rename saved elsewhere is taken in place.
    public internal(set) var service: RemoteServiceRecord
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
    /// The key is read with the server's row as saved now, and only a row
    /// with the window's address and trusted certificate is contacted
    /// (publishing design D-18, security review N7). Otherwise nothing is
    /// sent and the window follows the server as saved, or, while an import
    /// runs, leaves everything as it was until the reconnect after it.
    /// `keepingSubtitle`: that reconnect keeps the import's ending subtitle.
    public func connectServer(keepingSelection: Bool = false, keepingSubtitle: Bool = false) {
        guard let browse, let library else { return }
        browse.cancel()
        let kept = keepingSelection ? selection : []
        let before = (failure: browse.failure, albumGone: browse.albumGone)
        browse.isConnecting = true
        browse.failure = nil
        browse.albumGone = false
        let service = browse.service
        let keys = library.remoteKeyStore
        let catalog = library.catalog
        browse.connectTask = Task {
            let outcome = await RemoteImportConnection.connect(service, catalog: catalog, keys: keys)
            guard !Task.isCancelled, self.browse === browse else { return }
            browse.isConnecting = false
            switch outcome {
            case .changed(let change):
                if isImporting {
                    // The run keeps the connection it was started with; the grid,
                    // its state and the selection stay as they were (D-18).
                    browse.failure = before.failure
                    browse.albumGone = before.albumGone
                    return
                }
                switch change {
                case .connectionChanged(let now): follow(.chooseAgain(now), keepingSubtitle: keepingSubtitle)
                case .removed, .unchanged: follow(.leave, keepingSubtitle: keepingSubtitle)
                }
            case .failed(let result):
                // No grid will appear: a later one must not take the keyboard (N-4).
                focusesGridWhenShown = false
                browse.failure = result
                browse.setClient(nil)
                shots = []
                selection = []
            case .ready(let client, let info, let saved):
                if !isImporting { takeSaved(saved) }
                browse.setClient(client)
                browse.info = info
                loadAlbums()
                reloadPhotos(keeping: kept)
            }
        }
    }

    /// The server the window shows was saved again (publishing design D-18,
    /// §11.1). Never brings the window forward or moves the keyboard.
    func follow(_ follow: RemoteSourceFollow, keepingSubtitle: Bool = false) {
        switch follow {
        case .none, .afterImport:
            break
        case .takeSaved(let saved):
            takeSaved(saved)
        case .chooseAgain(let saved):
            // As choosing the server: an earlier "Imported n photos" goes,
            // except after the import that just ended.
            let done = doneText
            chooseServer(saved)
            if keepingSubtitle { doneText = done }
        case .leave:
            // As after Remove Server….
            closeServer()
            Task { await loadServers() }
        }
    }

    /// The same address and certificate saved under another name: taken in
    /// place; the Project name follows unless the person typed one.
    private func takeSaved(_ saved: RemoteServiceRecord) {
        guard let browse, browse.service.id == saved.id, browse.service.name != saved.name else { return }
        browse.service = saved
        if !browse.projectNameEdited {
            let noteWasShown = addsToExistingProject
            browse.projectName = RemoteProjectName.prefill(connection: saved.name, scope: browse.scopeName)
            announceProjectNote(wasShown: noteWasShown)
        }
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
        // Marks change: read the server again (design §4.7), as saved now:
        // a server saved again during the run is followed here (D-18).
        let done = doneText
        connectServer(keepingSelection: false, keepingSubtitle: true)
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

    /// The servers again, after Publish added or changed one. The server the
    /// window shows is followed as saved now, whether the window is in front,
    /// behind, minimized or closed (publishing design D-18): a rename in
    /// place; another address or certificate as choosing it again; nothing
    /// while an import from it runs (the reconnect after it follows).
    public func loadServersAfterPublish() async {
        await loadServers()
        guard let browse, let id = browse.service.id else { return }
        follow(RemoteSourceFollow.after(held: browse.service, now: servers.first { $0.id == id }, importing: isImporting))
    }

    // MARK: Hosting the Server sheet (publishing design §4)

    public var savedServers: [RemoteServiceRecord] { servers }
    public var serverCatalog: Catalog? { library?.catalog }
    public var serverSheetWindow: NSWindow? { window }

    public func serverSheetCancelled() {
        serverSheet = nil
    }

    /// Save found the server being edited removed (publishing design D-16):
    /// nothing was saved; the sheet closes, the servers are read again, and a
    /// removed source is left as after Remove Server….
    public func serverSheetFoundRemoved(_ service: RemoteServiceRecord) async {
        serverSheet = nil
        if let id = service.id, browse?.service.id == id { closeServer() }
        await loadServers()
        library?.remoteServersChanged()
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
