import AppKit
import os
import PhotoCore
import SwiftUI

/// The export settings being edited, with what the form shows beside them:
/// the first photo's file name, its preview and the watermark image. Shared
/// by the Export sheet and the Publish sheet's File Settings page, so both
/// edit the same settings with the same form (issue #28, R3, design §3.6).
@MainActor
@Observable
final class ExportSettingsEditor {
    @ObservationIgnored weak var library: LibraryModel?

    var settings: ExportSettings {
        didSet {
            guard settings != oldValue else { return }
            onChange?(settings)
            if settings.watermark?.identifier != oldValue.watermark?.identifier { loadWatermark() }
            updateExample()
        }
    }

    /// Told of every change (Export remembers its settings).
    @ObservationIgnored var onChange: ((ExportSettings) -> Void)?
    /// The host's handling of an image picked with Choose Image… (Export's
    /// clears its own issue, code review C3); without one, `useWatermark`.
    @ObservationIgnored var onWatermarkPicked: ((URL) -> Void)?
    /// A rendition of the first photo, for placing the watermark.
    private(set) var previewImage: CGImage?
    private(set) var watermarkImage: CGImage?
    /// The first photo's file name with the current settings.
    private(set) var example: String?
    /// The first photo, as the file name template sees it.
    private(set) var exampleContext: TemplateContext?
    /// The chosen watermark file wasn't a PNG.
    var watermarkIssue: String?
    @ObservationIgnored private var firstVersionID: Int64?
    @ObservationIgnored private var exampleTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    init(settings: ExportSettings) {
        self.settings = settings
    }

    var watermarks: WatermarkStore? {
        library.map { WatermarkStore(locations: $0.locations) }
    }

    /// The photos the form describes: the first photo's preview and name.
    func show(first item: CatalogItem?, versionID: Int64?) {
        firstVersionID = versionID
        watermarkIssue = nil
        loadPreview(item)
        loadWatermark()
        updateExample()
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

    func loadWatermark() {
        watermarkImage = nil
        guard let watermark = settings.watermark, let store = watermarks, store.contains(watermark.identifier),
              let source = CGImageSourceCreateWithURL(store.fileURL(for: watermark.identifier) as CFURL, nil)
        else { return }
        watermarkImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func updateExample() {
        guard let library, let first = firstVersionID else {
            example = nil
            exampleContext = nil
            return
        }
        let job = ExportJob(catalog: library.catalog, renderer: ExportRenderer(), copyNaming: PhotoName.naming)
        let settings = self.settings
        // The newest settings win: an older lookup finishing late is dropped.
        exampleTask?.cancel()
        exampleTask = Task {
            guard let item = try? await job.items(for: [first]).first, !Task.isCancelled else { return }
            let context = item.templateContext(sequence: 1, exportDate: Date())
            exampleContext = context
            example = ExportNaming.fileName(for: context, settings: settings)
        }
    }

    /// Choose Image… for the watermark.
    func chooseWatermark(in window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png]
        panel.prompt = String(localized: "Use Image", comment: "Open panel button: the watermark")
        panel.message = String(localized: "Choose a PNG image. Transparent areas stay see-through.")
        ExportModel.run(panel, in: window) { [weak self] url in self?.watermarkPicked(url) }
    }

    /// What Choose Image… does with the picked file: the host's handling,
    /// else `useWatermark`. The debug script picks through here too.
    func watermarkPicked(_ url: URL) {
        if let onWatermarkPicked {
            onWatermarkPicked(url)
        } else {
            useWatermark(at: url)
        }
    }

    /// Copies the PNG into the library and draws it with the current
    /// placement. False when it isn't a PNG.
    @discardableResult
    func useWatermark(at url: URL) -> Bool {
        guard let store = watermarks else { return false }
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
            watermarkIssue = nil
            return true
        } catch {
            watermarkIssue = String(localized: "“\(url.lastPathComponent)” is not a PNG image.")
            return false
        }
    }

    /// A settings problem Export would report (publishing design §3.6): the
    /// watermark image missing.
    var settingsIssue: String? {
        if let watermark = settings.activeWatermark, watermarks?.contains(watermark.identifier) != true {
            return String(localized: "The watermark image is missing. Choose it again.")
        }
        return nil
    }
}
