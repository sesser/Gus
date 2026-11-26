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

    /// The settings and what the form shows beside them (shared with the
    /// Publish sheet's File Settings page, issue #28 design §3.6).
    let editor: ExportSettingsEditor

    var settings: ExportSettings {
        get { editor.settings }
        set { editor.settings = newValue }
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
    /// Photos being exported whose HDR choice is on (issue #282, R13), known when the sheet opens.
    private(set) var hdrPhotos = 0
    var previewImage: CGImage? { editor.previewImage }
    var watermarkImage: CGImage? { editor.watermarkImage }
    var example: String? { editor.example }
    var exampleContext: TemplateContext? { editor.exampleContext }

    private(set) var presets: [ExportPreset] = []
    /// The preset the settings were last loaded from or saved as.
    var presetID: Int64?

    /// Names already taken in the destination, waiting for the person to say
    /// what to do with them.
    struct Conflict: Identifiable {
        let id = UUID()
        let count: Int
        /// Those of `count` that are originals in the library: never replaced.
        let masters: Int
        let items: [ExportItem]
    }

    var conflict: Conflict?
    /// Why the export cannot start, shown next to the part of the sheet it
    /// concerns (form conventions, section 8 of docs/UI_REDESIGN.md).
    var issue: Issue?

    struct Issue: Equatable {
        enum Place: Equatable { case general, destination, preset, watermark }
        let place: Place
        let text: String
    }

    private(set) var progress: (done: Int, total: Int)? {
        didSet { if (oldValue == nil) != (progress == nil) { progressStarted = progress == nil ? nil : Date() } }
    }
    /// When the running export started (File ▸ Stop names the newest job).
    private(set) var progressStarted: Date?
    var isExporting: Bool { progress != nil }
    private(set) var lastSummary: ExportSummary?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Export pressed: the photos being read and the files in the way counted.
    @ObservationIgnored private var requests = ExportRequestGate()
    @ObservationIgnored private var requestTask: Task<Bool, Never>?
    /// A request is reading or counting (debug script; not observed).
    var isRequesting: Bool { requests.isPending }

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "export")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        editor = ExportSettingsEditor(settings: defaults.string(forKey: Keys.settings)
            .flatMap { try? ExportSettings.decode(from: $0) } ?? ExportSettings())
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        destination = defaults.string(forKey: Keys.destination).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? pictures.appending(path: String(localized: "Exports"), directoryHint: .isDirectory)
        revealsInFinder = defaults.object(forKey: Keys.revealsInFinder) as? Bool ?? true
        editor.onChange = { settings in
            if let json = try? settings.jsonString() { defaults.set(json, forKey: Keys.settings) }
        }
        // The shared form's Choose Image… comes here, so a good pick clears
        // Export's issue as it did before the form was shared (code review C3).
        editor.onWatermarkPicked = { [weak self] url in self?.useWatermark(at: url) }
    }

    var watermarks: WatermarkStore? { editor.watermarks }

    private var job: ExportJob? {
        guard let library else { return nil }
        return ExportJob(catalog: library.catalog,
                         renderer: ExportRenderer(generator: library.previews.generator, watermarks: watermarks),
                         copyNaming: PhotoName.naming)
    }

    // MARK: Opening

    /// Takes the library's action targets and asks for the window.
    func begin() {
        guard let library else { return }
        cancelRequest()
        let targets = library.actionTargets.map { library.items[$0] }
        let resolved = ExportTargets.resolve(targets)
        versionIDs = resolved.versionIDs
        skippedVideos = resolved.videos
        hdrPhotos = ExportTargets.hdrCount(targets)
        issue = nil
        conflict = nil
        editor.library = library
        editor.show(first: targets.first { !$0.isVideo }, versionID: versionIDs.first)
        Task {
            await refreshPresets()
            editor.updateExample()
        }
        library.showsExportSheet = true
    }

    // MARK: Choosing files

    /// Choose Folder…, as a sheet on the export sheet's window.
    func chooseDestination(in window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        panel.prompt = String(localized: "Choose Folder", comment: "Open panel button")
        panel.message = String(localized: "Choose the folder exported photos are written to.")
        Self.run(panel, in: window) { [weak self] url in self?.destination = url }
    }

    /// Choose Image… for the watermark.
    func chooseWatermark(in window: NSWindow?) {
        editor.chooseWatermark(in: window)
    }

    /// Attached to `window` when there is one (window-modal), else app-modal.
    static func run(_ panel: NSOpenPanel, in window: NSWindow?, then pick: @escaping @MainActor (URL) -> Void) {
        guard let window else {
            if panel.runModal() == .OK, let url = panel.url { pick(url) }
            return
        }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { pick(url) }
        }
    }

    /// Copies the PNG into the library and draws it with the current placement.
    func useWatermark(at url: URL) {
        if editor.useWatermark(at: url) {
            issue = nil
        } else if let text = editor.watermarkIssue {
            editor.watermarkIssue = nil
            issue = Issue(place: .watermark, text: text)
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
                issue = Issue(place: .preset, text: String(localized: "Could not save the preset: \(error.localizedDescription)"))
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
    /// when the export started (the window can close). Refused while another
    /// request reads or an export runs (a second Return); `cancelRequest`
    /// stops it, and then it neither asks nor starts (issue #163).
    func requestExport() async -> Bool {
        guard let job, let request = requests.begin(isExporting: isExporting) else { return false }
        let check = Task { await self.check(request, job: job) }
        requestTask = check
        return await check.value
    }

    /// Stops the request still reading the photos or counting the files in
    /// the way, when the sheet closes or opens again: its alert never shows
    /// and its export never starts.
    func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        requests.cancel()
    }

    private enum Answer {
        case issue(Issue)
        case conflict(Conflict)
        case start([ExportItem])
    }

    private func check(_ request: ExportRequestGate.Request, job: ExportJob) async -> Bool {
        let answer = await answer(job)
        // Cancelled while it read: the sheet that asked is gone.
        guard requests.end(request) else { return false }
        requestTask = nil
        switch answer {
        case .issue(let issue):
            self.issue = issue
            return false
        case .conflict(let conflict):
            self.conflict = conflict
            return false
        case .start(let items):
            start(items: items, policy: .keepBoth)
            return true
        }
    }

    private func answer(_ job: ExportJob) async -> Answer {
        guard !versionIDs.isEmpty else {
            return .issue(Issue(place: .general, text: String(localized: "There is nothing to export.")))
        }
        if let text = editor.settingsIssue {
            return .issue(Issue(place: .watermark, text: text))
        }
        let items: [ExportItem]
        let clashes: ExportClashes
        do {
            items = try await job.items(for: versionIDs)
            clashes = try await job.clashes(for: items, settings: settings, in: destination)
        } catch {
            return .issue(Issue(place: .general, text: String(localized: "Could not read the photos to export: \(error.localizedDescription)")))
        }
        if clashes.existing > 0 {
            return .conflict(Conflict(count: clashes.existing, masters: clashes.masters, items: items))
        }
        return .start(items)
    }

    /// The existing-files alert's message for `count` files in the way,
    /// `masters` of them originals in the library: what Keep Both does, or,
    /// when there are originals, what happens to the photos whose names are
    /// theirs. The messages with originals say what happens and compare no
    /// buttons (owner, sign-off P1; review.md R1 before that).
    /// `ExportClashes.originals` picks the case.
    static func conflictMessage(count: Int, masters: Int) -> String {
        switch ExportClashes(existing: count, masters: masters).originals {
        case .none:
            String(localized: "Keep Both writes the new files under numbered names.",
                   comment: "Export window: existing files alert message")
        case .some(let masters):
            String(localized: "\(masters) of them are originals in the library. Originals are never replaced, so those photos are written under numbered names.",
                   comment: "Export window: existing files alert message when some of the files are originals; how many")
        case .theOnlyFile:
            String(localized: "It is an original in the library. Originals are never replaced, so the new file is written under a numbered name.",
                   comment: "Export window: existing files alert message when the one file is an original")
        case .all:
            String(localized: "They are all originals in the library. Originals are never replaced, so the new files are written under numbered names.",
                   comment: "Export window: existing files alert message when every file is an original")
        }
    }

    /// Runs the export the window asked about with `policy` for taken names.
    func resolveConflict(_ policy: ExportConflictPolicy) {
        guard let conflict else { return }
        self.conflict = nil
        start(items: conflict.items, policy: policy)
    }

    private func start(items: [ExportItem], policy: ExportConflictPolicy) {
        guard let job, library != nil else { return }
        let request = ExportRequest(versionIDs: versionIDs, settings: settings, destination: destination, policy: policy)
        let reveals = revealsInFinder
        progress = (0, items.filter { !$0.isVideo }.count)
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

    /// Reports in Activity only, never an alert: the sheet has closed
    /// (design.md I3, owner ruling D2). Files skipped by choice are an
    /// information row; the export's own row follows, a warning listing the
    /// files that failed when any did.
    private func finish(_ summary: ExportSummary, reveals: Bool) {
        progress = nil
        task = nil
        lastSummary = summary
        let action = ActivityTitle.exportTo(summary.destination.lastPathComponent)
        let report = ExportActivityReport(summary)
        if let skipped = report.skippedByChoice {
            library?.report(Self.skippedMessage(skipped), action: action)
        }
        // Information, one row per reason, before the export's own (ml-denoise design §7).
        for row in report.machineLearningNotApplied {
            library?.report(MachineLearningText.exportedWithout(row.reason, count: row.count), action: action)
        }
        let finished = Self.finishedMessage(summary)
        library?.report(Self.detail(finished, report), action: action, warning: report.isWarning, announcing: finished)
        if reveals, !summary.written.isEmpty, !summary.cancelled {
            NSWorkspace.shared.activateFileViewerSelecting(summary.written)
        }
    }

    static func skippedMessage(_ count: Int) -> String {
        String(localized: "\(count) photos were skipped because their files already exist.",
               comment: "Activity: an export skipped photos whose names were taken, as the person chose")
    }

    /// The finished sentence, then one line per listed failure and "And N more.".
    static func detail(_ finished: String, _ report: ExportActivityReport) -> String {
        var lines = [finished] + report.listedFailures.map(text)
        if report.unlistedFailureCount > 0 {
            lines.append(String(localized: "And \(report.unlistedFailureCount) more.",
                                comment: "Activity: failures past the listed ones"))
        }
        return lines.joined(separator: "\n")
    }

    /// The Activity row's message when an export ends (section 1 of
    /// docs/UI_REDESIGN.md): "Exported 24 photos." or "Exported 22 of 24
    /// photos. 2 could not be written."
    static func finishedMessage(_ summary: ExportSummary) -> String {
        let written = summary.written.count
        let failed = summary.failures.count
        if summary.cancelled {
            return String(localized: "Export stopped after \(written) photos.")
        }
        if failed == 0 {
            return String(localized: "Exported \(written) photos.", comment: "Activity: an export finished")
        }
        if written == 0 {
            // Plurals follow the first number only, so "0 of 1 photos" is avoided.
            return String(localized: "\(failed) photos could not be written.", comment: "Activity: an export wrote nothing")
        }
        return String(localized: "Exported \(written) of \(written + failed) photos. \(failed) could not be written.",
                      comment: "Activity: an export finished with failures")
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
