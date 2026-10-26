import AppKit
import Observation
import PhotoCore
import PhotoUI
import os

/// The `.cube` files of a folder the person picked, each previewed on the photo
/// being edited.
@MainActor
@Observable
final class LookTableBrowser {
    struct Entry: Identifiable, Hashable {
        let url: URL
        var name: String { url.deletingPathExtension().lastPathComponent }
        var id: URL { url }
    }

    @ObservationIgnored weak var library: LibraryModel?
    private(set) var folder: URL?
    private(set) var entries: [Entry] = []
    /// Small renders of the photo with each table.
    private(set) var previews: [URL: DecodedImage] = [:]
    /// Content hashes, to show which entry the photo uses.
    private(set) var identifiers: [URL: String] = [:]
    /// Files that are not valid tables.
    private(set) var failures: Set<URL> = []
    @ObservationIgnored private var cubes: [URL: ColorCube] = [:]
    @ObservationIgnored private var previewKey: String?
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    private static let folderKey = "edits.lutFolder"
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "edits")

    init() {
        folder = UserDefaults.standard.string(forKey: Self.folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
        rescan()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose a folder of .cube look-up tables.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(url)
    }

    func setFolder(_ url: URL) {
        folder = url
        UserDefaults.standard.set(url.path, forKey: Self.folderKey)
        rescan()
    }

    func rescan() {
        scanTask?.cancel()
        previews = [:]
        identifiers = [:]
        failures = []
        cubes = [:]
        previewKey = nil
        guard let folder else {
            entries = []
            return
        }
        scanTask = Task {
            let urls = await Task.detached(priority: .userInitiated) { LookTableBrowsing.files(in: folder) }.value
            guard !Task.isCancelled else { return }
            entries = urls.map(Entry.init)
        }
    }

    /// Renders every entry's preview on `base`, unless they were rendered for `key` already.
    func refreshPreviews(base: DecodedImage, key: String) async {
        guard key != previewKey, let engine = library?.previews.generator.engine else { return }
        previewKey = key
        for entry in entries {
            guard !Task.isCancelled else { return }
            let url = entry.url
            let cached = cubes[url]
            let result = await Task.detached(priority: .utility) { () -> (ColorCube, String, DecodedImage?)? in
                let cube: ColorCube
                let identifier: String
                if let cached {
                    cube = cached
                    identifier = ""
                } else {
                    guard let data = try? Data(contentsOf: url),
                          let lut = try? CubeLUT(parsing: String(decoding: data, as: UTF8.self)) else { return nil }
                    cube = lut.colorCube()
                    identifier = Digest.sha256Hex(data)
                }
                let preview = LookTableBrowsing.preview(of: base.cgImage, with: cube, engine: engine)
                return (cube, identifier, preview.map { DecodedImage(cgImage: $0) })
            }.value
            guard !Task.isCancelled, previewKey == key else { return }
            guard let (cube, identifier, preview) = result else {
                failures.insert(url)
                continue
            }
            cubes[url] = cube
            if !identifier.isEmpty { identifiers[url] = identifier }
            previews[url] = preview
        }
    }

    /// Copies the table into the library and applies it to the photo being edited.
    func apply(_ entry: Entry, editor: AdjustmentEditor) {
        guard let store = library?.lookTables else { return }
        do {
            let table = try store.importFile(at: entry.url)
            identifiers[entry.url] = table.identifier
            let intensity = editor.adjustments.lookTable.identifier == nil ? 100 : editor.adjustments.lookTable.intensity
            editor.change(String(localized: "Look-Up Table"), phase: .committed) {
                $0.lookTable = LookTable(identifier: table.identifier, name: table.name, intensity: intensity)
            }
        } catch {
            Self.log.error("Could not use \(entry.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            failures.insert(entry.url)
            library?.statusMessage = String(localized: "\(entry.name) is not a look-up table this app can read.")
        }
    }
}
