import AppKit
import Observation
import PhotoCore
import os

/// A place to import from by copying: a card (or camera mounted as a disk) or
/// any folder.
public struct ImportSource: Hashable, Identifiable {
    public var url: URL
    public var name: String
    /// Has a DCIM folder.
    public var isCard: Bool
    public var isEjectable: Bool

    public var id: URL { url }

    /// Cards are scanned from their DCIM folder.
    public var scanRoot: URL {
        isCard ? url.appending(path: "DCIM", directoryHint: .isDirectory) : url
    }

    public static func describe(_ url: URL) -> ImportSource {
        let values = try? url.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeLocalizedNameKey,
                                                       .isVolumeKey])
        let isVolume = values?.isVolume == true
        let isEjectable = isVolume && (values?.volumeIsEjectable == true || values?.volumeIsRemovable == true)
        return ImportSource(url: url, name: (isVolume ? values?.volumeLocalizedName : nil) ?? url.lastPathComponent,
                            isCard: hasDCIM(url), isEjectable: isEjectable)
    }

    public static func hasDCIM(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.appending(path: "DCIM").path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Mounted volumes that look like cards or removable disks.
    public static func mountedCards() -> [ImportSource] {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeLocalizedNameKey, .isVolumeKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.map(describe).filter { $0.isCard || $0.isEjectable }.sorted { $0.name < $1.name }
    }
}

/// The library a copying import adds to. The standalone importer has none and
/// only copies.
@MainActor
public protocol CardImportLibrary: AnyObject {
    var catalog: Catalog { get }
    var sidecars: SidecarSync { get }
    var projects: [ProjectSummary] { get }
    func refreshProjects() async
    func didFinishCopyImport(_ result: CopyImportResult) async
}

/// State of the import window.
@MainActor
@Observable
public final class CardImportModel {
    /// Nil in the standalone importer: copies are not catalogued, nothing is
    /// marked as already in the library, and there is no project to choose.
    @ObservationIgnored public weak var library: (any CardImportLibrary)?
    @ObservationIgnored private let metadataReader: any MetadataReader
    @ObservationIgnored private let presetStore: any MetadataPresetStore
    @ObservationIgnored private var volumeObservers: [any NSObjectProtocol] = []

    public var copiesOnly: Bool { library == nil }

    // MARK: Source

    public private(set) var sources: [ImportSource] = []
    public var source: ImportSource? {
        didSet { if oldValue != source { rescan() } }
    }
    public private(set) var shots: [SourceShot] = []
    /// The newest photo's camera, for the status bar.
    public private(set) var camera: CameraSummary?
    public private(set) var isScanning = false
    var selection: Set<URL> = []
    var showsDuplicates = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored var lastClicked: URL?

    var visibleShots: [SourceShot] {
        showsDuplicates ? shots : shots.filter { !$0.isDuplicate }
    }

    public var duplicateCount: Int { shots.filter(\.isDuplicate).count }

    public var selectedShots: [SourceShot] {
        shots.filter { selection.contains($0.id) && !$0.isDuplicate }
    }

    // MARK: Options (remembered)

    public var destination: URL {
        didSet { defaults.set(destination.path, forKey: Keys.destination) }
    }
    var folderTemplate: String {
        didSet { defaults.set(folderTemplate, forKey: Keys.folderTemplate) }
    }
    var fileTemplate: String {
        didSet { defaults.set(fileTemplate, forKey: Keys.fileTemplate) }
    }
    var projectNameTemplate: String {
        didSet { defaults.set(projectNameTemplate, forKey: Keys.projectName) }
    }
    /// nil: a new project.
    var existingProjectID: Int64?
    public var jobCode = ""
    var recentJobCodes: [String] {
        didSet { defaults.set(recentJobCodes, forKey: Keys.jobCodes) }
    }
    var presets: [MetadataPreset] = []
    var presetID: Int64? {
        didSet { defaults.set(presetID.map { Int($0) } ?? 0, forKey: Keys.preset) }
    }
    public var ejectsWhenDone: Bool {
        didSet { defaults.set(ejectsWhenDone, forKey: Keys.eject) }
    }
    var includesVideos: Bool {
        didSet {
            defaults.set(includesVideos, forKey: Keys.videos)
            if oldValue != includesVideos { rescan() }
        }
    }
    /// Not remembered: deleting from the card is decided each time.
    public var deletesOriginals = false
    var counter: Int {
        didSet { defaults.set(counter, forKey: Keys.counter) }
    }

    var template: ImportTemplate { ImportTemplate(folder: folderTemplate, fileName: fileTemplate) }

    // MARK: Running

    private(set) var progress: CopyImportProgress?
    private(set) var lastResult: CopyImportResult?
    /// Verified files waiting for the person to confirm their deletion.
    public var pendingDeletion: [URL]?
    public var message: String?
    @ObservationIgnored private var importTask: Task<Void, Never>?

    public var isImporting: Bool { importTask != nil }

    private let defaults: UserDefaults
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "card-import")

    private enum Keys {
        static let destination = "import.destination"
        static let folderTemplate = "import.folderTemplate"
        static let fileTemplate = "import.fileTemplate"
        static let projectName = "import.projectNameTemplate"
        static let jobCodes = "import.recentJobCodes"
        static let preset = "import.metadataPreset"
        static let eject = "import.ejectWhenDone"
        static let counter = "import.counter"
        static let videos = "import.includeVideos"
    }

    /// `presets`: the catalog in the library app, preferences in the
    /// standalone importer. `defaults` holds the remembered options.
    public init(metadataReader: any MetadataReader, presets: any MetadataPresetStore, defaults: UserDefaults = .standard) {
        self.metadataReader = metadataReader
        presetStore = presets
        self.defaults = defaults
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Pictures")
        destination = defaults.string(forKey: Keys.destination).map { URL(fileURLWithPath: $0) } ?? pictures
        folderTemplate = defaults.string(forKey: Keys.folderTemplate) ?? ImportTemplate().folder
        fileTemplate = defaults.string(forKey: Keys.fileTemplate) ?? ImportTemplate().fileName
        projectNameTemplate = defaults.string(forKey: Keys.projectName) ?? "{capture:yyyy-MM-dd} {job}"
        recentJobCodes = defaults.stringArray(forKey: Keys.jobCodes) ?? []
        let preset = defaults.integer(forKey: Keys.preset)
        presetID = preset == 0 ? nil : Int64(preset)
        ejectsWhenDone = defaults.bool(forKey: Keys.eject)
        counter = max(1, defaults.integer(forKey: Keys.counter))
        includesVideos = defaults.object(forKey: Keys.videos) as? Bool ?? true
    }

    // MARK: Sources

    /// Lists mounted cards; picks `preferred` (a card that just mounted) or keeps
    /// the current source.
    public func refreshSources(preferring preferred: URL? = nil) {
        var found = ImportSource.mountedCards()
        if let current = source, !current.isEjectable, !found.contains(current) { found.append(current) }
        sources = found
        if let preferred {
            source = found.first { $0.url.standardizedFileURL == preferred.standardizedFileURL } ?? ImportSource.describe(preferred)
            if let source, !sources.contains(source) { sources.append(source) }
        } else if source == nil || !(found.contains { $0 == source }) {
            source = found.first { $0.isCard } ?? found.first
        }
        Task { await loadPresets() }
    }

    /// Follows cards as they come and go, switching to a card when it mounts.
    /// The standalone importer uses this; the library app opens the window
    /// itself when a card mounts.
    public func followCards() {
        guard volumeObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let mounted = name == NSWorkspace.didMountNotification
                    ? notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL : nil
                Task { @MainActor in
                    guard let self, !self.isImporting else { return }
                    if let mounted, ImportSource.hasDCIM(mounted) {
                        self.refreshSources(preferring: mounted)
                    } else {
                        self.refreshSources()
                    }
                }
            })
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Choose")
        panel.message = copiesOnly
            ? String(localized: "Choose a folder to import from. Its photos are copied to the destination folder.")
            : String(localized: "Choose a folder to import from. Its photos are copied into the library's folders.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let chosen = ImportSource.describe(url)
        if !sources.contains(chosen) { sources.append(chosen) }
        source = chosen
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose where imported photos are copied to.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url
    }

    public func rescan() {
        scanTask?.cancel()
        shots = []
        camera = nil
        selection = []
        guard let source else { return }
        let reader = metadataReader
        let catalog = library?.catalog
        let videos = includesVideos
        isScanning = true
        scanTask = Task {
            do {
                let found = try await SourceScanner.scan(source.scanRoot, reader: reader, includingVideos: videos)
                let marked = if let catalog { try await SourceScanner.markDuplicates(in: found, catalog: catalog) } else { found }
                guard !Task.isCancelled else { return }
                shots = marked
                camera = CameraSummary(newestOf: marked)
                selection = Set(marked.filter { !$0.isDuplicate }.map(\.id))
            } catch is CancellationError {
            } catch {
                message = String(localized: "Could not read \(source.name): \(error.localizedDescription)")
            }
            isScanning = false
        }
    }

    // MARK: Selection

    /// Click toggles a shot; shift-click sets the range since the last click to
    /// the clicked shot's new state.
    func click(_ shot: SourceShot, extend: Bool) {
        let visible = visibleShots
        let selecting = !selection.contains(shot.id)
        if extend, let anchor = lastClicked, let from = visible.firstIndex(where: { $0.id == anchor }),
           let to = visible.firstIndex(where: { $0.id == shot.id }) {
            for index in min(from, to)...max(from, to) where !visible[index].isDuplicate {
                if selecting { selection.insert(visible[index].id) } else { selection.remove(visible[index].id) }
            }
        } else if selecting {
            selection.insert(shot.id)
        } else {
            selection.remove(shot.id)
        }
        lastClicked = shot.id
    }

    func selectAll() { selection = Set(shots.filter { !$0.isDuplicate }.map(\.id)) }
    func selectNone() { selection = [] }

    // MARK: Presets

    func loadPresets() async {
        presets = (try? await presetStore.metadataPresets()) ?? []
        if let presetID, !presets.contains(where: { $0.id == presetID }) { self.presetID = nil }
    }

    func savePreset(_ preset: MetadataPreset) {
        let store = presetStore
        Task {
            let saved = try? await store.saveMetadataPreset(preset)
            await loadPresets()
            if let id = saved?.id { presetID = id }
        }
    }

    func deletePreset(_ id: Int64) {
        let store = presetStore
        Task {
            try? await store.deleteMetadataPreset(id: id)
            await loadPresets()
        }
    }

    // MARK: Importing

    /// What the templates make of the first selected shot.
    var example: String? {
        guard let shot = selectedShots.first ?? visibleShots.first else { return nil }
        let metadata = shot.primary.metadata
        let context = TemplateContext(captureDate: metadata.captureDate, captureOffsetSeconds: metadata.captureOffsetSeconds,
                                      fileDate: shot.primary.modifiedAt, importDate: Date(), make: metadata.cameraMake,
                                      model: metadata.cameraModel, serial: metadata.cameraSerial, lens: metadata.lensModel,
                                      originalName: shot.primary.name, sequence: 1, counter: counter, jobCode: jobCode)
        return template.example(context)
    }

    public func startImport() {
        guard let source, importTask == nil else { return }
        let shots = selectedShots
        guard !shots.isEmpty else { return }
        let job = jobCode.trimmingCharacters(in: .whitespaces)
        if !job.isEmpty {
            recentJobCodes = Array(([job] + recentJobCodes.filter { $0 != job }).prefix(10))
        }
        let options = CopyImportOptions(
            destination: destination, template: template,
            project: existingProjectID.map(ProjectChoice.existing) ?? .new(nameTemplate: projectNameTemplate),
            jobCode: job, firstCounter: counter,
            metadata: presets.first { $0.id == presetID }?.values)
        let importer = CopyImporter(catalog: library?.catalog, sidecars: library?.sidecars)
        message = nil
        lastResult = nil
        progress = CopyImportProgress()
        importTask = Task {
            do {
                let result = try await importer.run(shots: shots, sourceRoot: source.url, options: options) { update in
                    Task { @MainActor in
                        guard self.importTask != nil else { return }
                        self.progress = update
                    }
                }
                counter = result.nextCounter
                lastResult = result
                importTask = nil
                progress = nil
                if deletesOriginals, !result.verifiedSources.isEmpty {
                    pendingDeletion = result.verifiedSources
                } else {
                    await finish(result, source: source)
                }
            } catch {
                importTask = nil
                progress = nil
                message = switch error {
                case is CancellationError where copiesOnly:
                    String(localized: "Import cancelled. Photos copied so far are in the destination folder.")
                case is CancellationError:
                    String(localized: "Import cancelled. Photos copied so far are in the library.")
                default:
                    String(localized: "Import failed: \(error.localizedDescription)")
                }
                await library?.refreshProjects()
                rescan()
            }
        }
    }

    public func cancelImport() {
        importTask?.cancel()
    }

    /// After the person answered the deletion question.
    public func confirmDeletion(_ delete: Bool) {
        guard let urls = pendingDeletion, let source, let result = lastResult else { return }
        pendingDeletion = nil
        if delete {
            let failed = CopyImporter.deleteSources(urls)
            if !failed.isEmpty {
                message = String(localized: "\(failed.count) files could not be deleted from \(source.name).")
            }
        }
        Task { await finish(result, source: source) }
    }

    private func finish(_ result: CopyImportResult, source: ImportSource) async {
        let failures = result.failures.count
        let copied = result.copied + result.alreadyAtDestination
        if message == nil {
            message = failures > 0
                ? String(localized: "Imported \(copied) files. \(failures) could not be copied.")
                : String(localized: "Imported \(copied) files.")
        }
        await library?.didFinishCopyImport(result)
        if ejectsWhenDone, source.isEjectable {
            let url = source.url
            let ejected = await Task.detached { (try? NSWorkspace.shared.unmountAndEjectDevice(at: url)) != nil }.value
            if ejected {
                self.source = nil
                refreshSources()
            } else {
                message = String(localized: "\(source.name) could not be ejected. It may still be in use.")
            }
        } else {
            rescan()
        }
    }
}
