import AppKit
import os
import PhotoCore
import SwiftUI

/// The export window's state and the export running behind it: what is being
/// exported, the settings (remembered between exports, and saved as presets),
/// and the progress of the export once it starts.
@MainActor
@Observable
final class ExportModel {
    @ObservationIgnored weak var library: LibraryModel?
    @ObservationIgnored private let defaults: UserDefaults

    enum Keys {
        static let settings = "export.settings"
        static let destination = "export.destination"
        static let revealsInFinder = "export.revealsInFinder"
    }

    var settings: ExportSettings {
        didSet {
            guard settings != oldValue else { return }
            if let json = try? settings.jsonString() { defaults.set(json, forKey: Keys.settings) }
            if settings.watermark?.identifier != oldValue.watermark?.identifier { loadWatermark() }
            updateExample()
        }
    }

    var destination: URL {
        didSet { defaults.set(destination.path, forKey: Keys.destination) }
    }

    var revealsInFinder: Bool {
        didSet { defaults.set(revealsInFinder, forKey: Keys.revealsInFinder) }
    }

    /// The versions the window exports (pairs resolved to their RAW).
    private(set) var versionIDs: [Int64] = []
    private(set) var skippedVideos = 0
    /// A rendition of the first photo, for placing the watermark.
    private(set) var previewImage: CGImage?
    private(set) var watermarkImage: CGImage?
    /// The first photo's file name with the current settings.
    private(set) var example: String?

    private(set) var presets: [ExportPreset] = []
    /// The preset the settings were last loaded from or saved as.
    var presetID: Int64?

    /// Names already taken in the destination, waiting for the person to say
    /// what to do with them.
    struct Conflict: Identifiable {
        let id = UUID()
        let count: Int
        let items: [ExportItem]
    }

    var conflict: Conflict?
    /// What the window shows when it cannot start (a bad watermark, nothing to export…).
    var message: String?

    private(set) var progress: (done: Int, total: Int)?
    var isExporting: Bool { progress != nil }
    /// How the last export went, when it is worth an alert.
    var report: Report?
    private(set) var lastSummary: ExportSummary?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    struct Report: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "export")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.string(forKey: Keys.settings).flatMap { try? ExportSettings.decode(from: $0) }
            ?? ExportSettings()
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        destination = defaults.string(forKey: Keys.destination).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? pictures.appending(path: String(localized: "Exports"), directoryHint: .isDirectory)
        revealsInFinder = defaults.object(forKey: Keys.revealsInFinder) as? Bool ?? true
    }

    var watermarks: WatermarkStore? {
        library.map { WatermarkStore(locations: $0.locations) }
    }

    private var job: ExportJob? {
        guard let library else { return nil }
        return ExportJob(catalog: library.catalog,
                         renderer: ExportRenderer(generator: library.previews.generator, watermarks: watermarks))
    }

    // MARK: Opening

    /// Takes the library's action targets and asks for the window.
    func begin() {
        guard let library else { return }
        let targets = library.actionTargets.map { library.items[$0] }
        let resolved = ExportTargets.resolve(targets)
        versionIDs = resolved.versionIDs
        skippedVideos = resolved.videos
        message = nil
        conflict = nil
        loadPreview(targets.first { !$0.isVideo })
        loadWatermark()
        Task {
            await refreshPresets()
            updateExample()
        }
        library.requestsExportWindow = true
    }

    private func loadPreview(_ item: CatalogItem?) {
        previewTask?.cancel()
        previewImage = nil
        guard let library, let item, let request = library.previewRequest(for: item, tier: .preview) else { return }
        let previews = library.previews
        previewTask = Task {
            let image = try? await previews.image(for: request, maxPixelSize: 900)
            guard !Task.isCancelled else { return }
            previewImage = image
        }
    }

    private func loadWatermark() {
        watermarkImage = nil
        guard let watermark = settings.watermark, let store = watermarks, store.contains(watermark.identifier),
              let source = CGImageSourceCreateWithURL(store.fileURL(for: watermark.identifier) as CFURL, nil)
        else { return }
        watermarkImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func updateExample() {
        guard let job, let first = versionIDs.first else {
            example = nil
            return
        }
        let settings = self.settings
        Task {
            guard let item = try? await job.items(for: [first]).first else { return }
            example = ExportNaming.fileName(for: item.templateContext(sequence: 1, exportDate: Date()), settings: settings)
        }
    }

    // MARK: Choosing files

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the folder exported photos are written to.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url
    }

    func chooseWatermark() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png]
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose a PNG image. Transparent areas stay see-through.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        useWatermark(at: url)
    }

    /// Copies the PNG into the library and draws it with the current placement.
    func useWatermark(at url: URL) {
        guard let store = watermarks else { return }
        do {
            var watermark = try store.importFile(at: url)
            if let current = settings.watermark {
                watermark.anchor = current.anchor
                watermark.margin = current.margin
                watermark.size = current.size
                watermark.opacity = current.opacity
            }
            settings.watermark = watermark
            settings.watermarkEnabled = true
            message = nil
        } catch {
            message = String(localized: "“\(url.lastPathComponent)” is not a PNG image.")
        }
    }

    // MARK: Presets

    func refreshPresets() async {
        guard let library else { return }
        do {
            presets = try await library.catalog.exportPresets()
        } catch {
            Self.log.error("Loading export presets failed: \(error.localizedDescription, privacy: .public)")
        }
        if let presetID, !presets.contains(where: { $0.id == presetID }) { self.presetID = nil }
    }

    func applyPreset(id: Int64?) {
        presetID = id
        guard let id, let preset = presets.first(where: { $0.id == id }) else { return }
        settings = preset.settings
    }

    /// The selected preset, when the settings no longer match it.
    var modifiedPreset: ExportPreset? {
        guard let preset = presets.first(where: { $0.id == presetID }), preset.settings != settings else { return nil }
        return preset
    }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let library, !trimmed.isEmpty else { return }
        let existing = presets.first { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        var preset = existing ?? ExportPreset(name: trimmed, settings: settings)
        preset.settings = settings
        let catalog = library.catalog
        Task {
            do {
                let saved = try await catalog.saveExportPreset(preset)
                await refreshPresets()
                presetID = saved.id
            } catch {
                message = String(localized: "Could not save the preset: \(error.localizedDescription)")
            }
        }
    }

    func updateSelectedPreset() {
        guard let preset = modifiedPreset else { return }
        savePreset(named: preset.name)
    }

    func deleteSelectedPreset() {
        guard let library, let id = presetID else { return }
        let catalog = library.catalog
        Task {
            try? await catalog.deleteExportPreset(id: id)
            presetID = nil
            await refreshPresets()
        }
    }

    // MARK: Exporting

    /// Starts the export, or asks first when names are taken. Returns true
    /// when the export started (the window can close).
    func requestExport() async -> Bool {
        guard let job, !isExporting else { return false }
        guard !versionIDs.isEmpty else {
            message = String(localized: "There is nothing to export.")
            return false
        }
        if let watermark = settings.activeWatermark, watermarks?.contains(watermark.identifier) != true {
            message = String(localized: "The watermark image is missing. Choose it again.")
            return false
        }
        let items: [ExportItem]
        do {
            items = try await job.items(for: versionIDs)
        } catch {
            message = String(localized: "Could not read the photos to export: \(error.localizedDescription)")
            return false
        }
        let date = Date()
        let contexts = items.filter { !$0.isVideo }.enumerated()
            .map { $1.templateContext(sequence: $0 + 1, exportDate: date) }
        let existing = ExportNaming.existingCount(contexts, settings: settings, in: destination)
        if existing > 0 {
            conflict = Conflict(count: existing, items: items)
            return false
        }
        start(items: items, policy: .keepBoth)
        return true
    }

    /// Runs the export the window asked about with `policy` for taken names.
    func resolveConflict(_ policy: ExportConflictPolicy) {
        guard let conflict else { return }
        self.conflict = nil
        start(items: conflict.items, policy: policy)
    }

    private func start(items: [ExportItem], policy: ExportConflictPolicy) {
        guard let job, let library else { return }
        let request = ExportRequest(versionIDs: versionIDs, settings: settings, destination: destination, policy: policy)
        let reveals = revealsInFinder
        progress = (0, items.filter { !$0.isVideo }.count)
        library.statusMessage = nil
        task = Task {
            let summary = await job.run(request, items: items) { done, total in
                Task { @MainActor in
                    guard self.progress != nil else { return }
                    self.progress = (max(done, self.progress?.done ?? 0), total)
                }
            }
            finish(summary, reveals: reveals)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func finish(_ summary: ExportSummary, reveals: Bool) {
        progress = nil
        task = nil
        lastSummary = summary
        let folder = summary.destination.lastPathComponent
        let written = summary.written.count
        library?.statusMessage = summary.cancelled
            ? String(localized: "Export stopped after \(written) photos.")
            : String(localized: "Exported \(written) photos to “\(folder)”.")
        if reveals, !summary.written.isEmpty, !summary.cancelled {
            NSWorkspace.shared.activateFileViewerSelecting(summary.written)
        }
        var lines: [String] = []
        if summary.skippedExisting > 0 {
            lines.append(String(localized: "\(summary.skippedExisting) photos were skipped because their files already exist."))
        }
        if summary.skippedVideos > 0 {
            lines.append(String(localized: "\(summary.skippedVideos) videos were skipped."))
        }
        for failure in summary.failures.prefix(10) {
            lines.append(Self.text(failure))
        }
        if summary.failures.count > 10 {
            lines.append(String(localized: "And \(summary.failures.count - 10) more."))
        }
        guard !summary.failures.isEmpty || summary.skippedExisting > 0 else { return }
        let title = summary.failures.isEmpty
            ? String(localized: "Exported \(written) photos")
            : String(localized: "\(summary.failures.count) photos could not be exported")
        report = Report(title: title, message: lines.joined(separator: "\n"))
    }

    static func text(_ failure: ExportSummary.Failure) -> String {
        let name = failure.fileName
        switch failure.reason {
        case .offline(let volume):
            return String(localized: "\(name): the volume “\(volume)” is not connected.")
        case .unreadable:
            return String(localized: "\(name): the original could not be read.")
        case .missingWatermark:
            return String(localized: "\(name): the watermark image is missing.")
        case .writeFailed(let reason):
            return String(localized: "\(name): \(reason)")
        }
    }
}
