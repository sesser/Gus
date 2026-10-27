import AppKit
import Observation
import PhotoCore
import PhotoUI
import os

/// The look-up table collections (built-in and imported), their previews on
/// the photo being edited, and importing and managing them.
@MainActor
@Observable
final class LookTableLibraryModel {
    /// A folder (or files) read for import, waiting for the person to confirm.
    struct ImportDraft: Identifiable {
        let id = UUID()
        var source: String
        var candidates: [LookTableImport.Candidate]
        /// Nil for a new collection.
        var collectionID: Int64?
        var newName: String
        var colorSpace = LookTable.ColorSpace.sRGB

        var importable: Int { candidates.count { $0.failure == nil } }
    }

    enum Sheet: Identifiable {
        case importing(ImportDraft)
        case manage

        var id: String {
            switch self {
            case .importing(let draft): draft.id.uuidString
            case .manage: "manage"
            }
        }
    }

    /// The browser shows every collection.
    static let allCollections = "all"

    @ObservationIgnored weak var library: LibraryModel?
    /// Built-in first, then imported collections by name.
    private(set) var collections: [LookTableCollection] = []
    /// The browser's collection (`allCollections` or a uuid).
    var browsedCollection = LookTableLibraryModel.allCollections {
        didSet {
            guard oldValue != browsedCollection else { return }
            UserDefaults.standard.set(browsedCollection, forKey: Self.browsedKey)
            expanded = Set(shownCollections.prefix(1).map(\.uuid))
        }
    }
    /// Expanded panes in the browser: only these render previews.
    var expanded: Set<String> = []
    /// The table picked in the browser, waiting for Apply.
    var selection: LookTableEntry?
    var sheet: Sheet?
    private(set) var isScanning = false
    /// Previews by `previewID(_:)`, for the current photo and its edit.
    private(set) var previews: [String: DecodedImage] = [:]
    @ObservationIgnored private var previewKey: String?
    @ObservationIgnored private var previewBase: DecodedImage?

    private static let browsedKey = "edits.lutCollection"
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "edits")

    init() {
        browsedCollection = UserDefaults.standard.string(forKey: Self.browsedKey) ?? "builtIn"
    }

    var builtIn: LookTableCollection {
        BuiltInLookTables.collection(named: String(localized: "Built-in", comment: "Look-up table collection"),
                                     entryName: LookTableText.builtInName)
    }

    /// What the browser lists for its pick.
    var shownCollections: [LookTableCollection] {
        browsedCollection == Self.allCollections ? collections : collections.filter { $0.uuid == browsedCollection }
    }

    var importedCollections: [LookTableCollection] { collections.filter { !$0.isBuiltIn } }

    func reload() async {
        guard let catalog = library?.catalog else { return }
        do {
            collections = [builtIn] + (try await catalog.lookTableCollections())
        } catch {
            Self.log.error("Loading look-up tables failed: \(error.localizedDescription, privacy: .public)")
            collections = [builtIn]
        }
        if browsedCollection != Self.allCollections, !collections.contains(where: { $0.uuid == browsedCollection }) {
            browsedCollection = builtIn.uuid
        }
        if expanded.isEmpty || !expanded.contains(where: { id in shownCollections.contains { $0.uuid == id } }) {
            expanded = Set(shownCollections.prefix(1).map(\.uuid))
        }
    }

    /// The name to show for an applied table: its library name when it is
    /// still listed, otherwise the name it had when applied.
    func displayName(for table: LookTable) -> String {
        guard let identifier = table.identifier else { return String(localized: "None", comment: "No look-up table") }
        for collection in collections {
            if let entry = collection.entries.first(where: { $0.identifier == identifier }) { return entry.name }
        }
        return table.name
    }

    // MARK: Applying

    /// Applies a table to the photo being edited, keeping the intensity of the
    /// table it replaces.
    func apply(_ entry: LookTableEntry, editor: AdjustmentEditor) {
        guard let store = library?.lookTables else { return }
        if let builtIn = BuiltInLookTables.table(identifier: entry.identifier) {
            _ = try? store.install(builtIn.data)
        }
        guard store.contains(entry.identifier) else {
            library?.statusMessage = String(localized: "\(entry.name) is missing from the library.")
            return
        }
        let current = editor.adjustments.lookTable
        editor.change(String(localized: "Look-Up Table"), phase: .committed) {
            $0.lookTable = entry.lookTable(intensity: current.identifier == nil ? 100 : current.intensity)
        }
    }

    // MARK: Previews

    static func previewID(_ entry: LookTableEntry) -> String {
        "\(entry.identifier)-\(entry.colorSpace.rawValue)"
    }

    /// Renders the previews of a collection's tables on the photo being edited,
    /// unless they were rendered for this photo and edit already.
    func renderPreviews(of collection: LookTableCollection, editor: AdjustmentEditor) async {
        guard let library else { return }
        let store = library.lookTables
        let key = editor.lookTablePreviewKey
        if key != previewKey {
            previewKey = key
            previews = [:]
            previewBase = nil
        }
        if previewBase == nil {
            guard let rendered = await editor.lookTablePreviewBase(), previewKey == key else { return }
            let engine = library.previews.generator.engine
            // Every preview starts from one small copy.
            previewBase = await Task.detached(priority: .userInitiated) {
                LookTableBrowsing.reduced(rendered.cgImage, longEdge: 360, engine: engine).map(DecodedImage.init)
            }.value
        }
        guard let base = previewBase else { return }
        let engine = library.previews.generator.engine
        for entry in collection.entries where previews[Self.previewID(entry)] == nil {
            guard !Task.isCancelled, previewKey == key else { return }
            let preview = await Task.detached(priority: .utility) { () -> DecodedImage? in
                guard let cube = store.cube(for: entry.identifier),
                      let image = LookTableBrowsing.preview(of: base.cgImage, with: cube, colorSpace: entry.colorSpace,
                                                            engine: engine, longEdge: 360)
                else { return nil }
                return DecodedImage(cgImage: image)
            }.value
            guard !Task.isCancelled, previewKey == key else { return }
            if let preview { previews[Self.previewID(entry)] = preview }
        }
    }

    // MARK: Importing

    /// Asks for a folder (or `.cube` files), reads it, and shows the import sheet.
    func chooseImportSource(into collectionID: Int64? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: LookTableStore.fileExtension) ?? .data]
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose a folder of .cube look-up tables, or the files themselves.")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        prepareImport(panel.urls, into: collectionID)
    }

    /// Reads `urls` (one folder, or files) and shows the import sheet.
    func prepareImport(_ urls: [URL], into collectionID: Int64? = nil) {
        isScanning = true
        Task {
            let candidates = await Task.detached(priority: .userInitiated) { () -> [LookTableImport.Candidate] in
                if urls.count == 1, urls[0].hasDirectoryPath {
                    return LookTableImport.candidates(in: urls[0])
                }
                return LookTableImport.candidates(for: urls.flatMap { url in
                    url.hasDirectoryPath ? LookTableBrowsing.files(in: url) : [url]
                })
            }.value
            isScanning = false
            let folder = urls.count == 1 && urls[0].hasDirectoryPath ? urls[0] : urls[0].deletingLastPathComponent()
            let existing = collectionID.flatMap { id in importedCollections.first { $0.rowID == id }?.rowID }
            sheet = .importing(ImportDraft(source: folder.path, candidates: candidates, collectionID: existing,
                                           newName: LookTableNaming.cleanedFileName(folder.lastPathComponent)))
        }
    }

    /// Imports a confirmed draft and shows its collection.
    func runImport(_ draft: ImportDraft) async {
        guard let library else { return }
        let name = draft.newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination: LookTableImport.Destination = draft.collectionID.map { .existing($0) }
            ?? .new(name.isEmpty ? String(localized: "Untitled Collection") : name)
        let store = library.lookTables
        let catalog = library.catalog
        let candidates = draft.candidates
        let colorSpace = draft.colorSpace
        do {
            let result = try await LookTableImport.run(candidates, into: destination, colorSpace: colorSpace,
                                                       store: store, catalog: catalog)
            await reload()
            if let collection = collections.first(where: { $0.rowID == result.collectionID }) {
                browsedCollection = collection.uuid
                expanded.insert(collection.uuid)
            }
            library.statusMessage = String(localized: "Imported \(result.added) look-up tables.")
        } catch {
            Self.log.error("Importing look-up tables failed: \(error.localizedDescription, privacy: .public)")
            library.statusMessage = String(localized: "Could not import the look-up tables: \(error.localizedDescription)")
        }
    }

    // MARK: Managing

    func renameCollection(_ collection: LookTableCollection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = collection.rowID, !trimmed.isEmpty, trimmed != collection.name else { return }
        change { try await $0.renameLookTableCollection(id: id, to: trimmed) }
    }

    func deleteCollection(_ collection: LookTableCollection) {
        guard let id = collection.rowID else { return }
        change { try await $0.deleteLookTableCollection(id: id) }
    }

    func renameEntry(_ entry: LookTableEntry, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = entry.rowID, !trimmed.isEmpty, trimmed != entry.name else { return }
        change { try await $0.renameLookTableEntry(id: id, to: trimmed) }
    }

    func setColorSpace(_ colorSpace: LookTable.ColorSpace, for entry: LookTableEntry) {
        guard let id = entry.rowID, colorSpace != entry.colorSpace else { return }
        change { try await $0.setLookTableColorSpace(colorSpace, forEntry: id) }
    }

    func deleteEntry(_ entry: LookTableEntry) {
        guard let id = entry.rowID else { return }
        if selection?.rowID == id { selection = nil }
        change { try await $0.deleteLookTableEntry(id: id) }
    }

    /// Library changes are not undoable: they never change a photo, and
    /// edits keep the table files they use.
    private func change(_ work: @escaping @Sendable (Catalog) async throws -> Void) {
        guard let catalog = library?.catalog else { return }
        Task {
            do {
                try await work(catalog)
            } catch {
                Self.log.error("Changing look-up tables failed: \(error.localizedDescription, privacy: .public)")
                library?.statusMessage = String(localized: "Could not save the change: \(error.localizedDescription)")
            }
            await reload()
        }
    }
}

/// Names of built-in tables and color spaces.
enum LookTableText {
    static func builtInName(_ key: String) -> String {
        switch key {
        case "warm": String(localized: "Warm", comment: "Built-in look-up table")
        case "cool": String(localized: "Cool", comment: "Built-in look-up table")
        case "fade": String(localized: "Fade", comment: "Built-in look-up table")
        case "mono": String(localized: "Mono", comment: "Built-in look-up table")
        case "sepia": String(localized: "Sepia", comment: "Built-in look-up table")
        case "tealOrange": String(localized: "Teal and Orange", comment: "Built-in look-up table")
        case "crossProcess": String(localized: "Cross Process", comment: "Built-in look-up table")
        case "bleach": String(localized: "Bleach", comment: "Built-in look-up table")
        default: key
        }
    }

    static func title(_ space: LookTable.ColorSpace) -> String {
        switch space {
        case .sRGB: String(localized: "sRGB", comment: "Color space")
        case .displayP3: String(localized: "Display P3", comment: "Color space")
        case .adobeRGB: String(localized: "Adobe RGB", comment: "Color space")
        case .proPhoto: String(localized: "ProPhoto RGB", comment: "Color space")
        }
    }
}
