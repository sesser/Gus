import AppKit
import PhotoCore
import UniformTypeIdentifiers

/// What a preset import did, shown in an alert.
struct PresetImportSummary: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

extension LibraryModel {
    // MARK: Listing

    func refreshAdjustmentPresets() async {
        adjustmentPresets = (try? await catalog.adjustmentPresets()) ?? []
    }

    /// Presets in no collection first, then each collection.
    var adjustmentPresetCollections: [AdjustmentPresetCollection] {
        AdjustmentPresetCollection.grouping(adjustmentPresets)
    }

    /// Names of the collections presets are in.
    var adjustmentPresetCollectionNames: [String] {
        adjustmentPresetCollections.map(\.name).filter { !$0.isEmpty }
    }

    // MARK: Applying

    /// Gives the selection (grid) or the photo on screen (loupe) the preset's groups.
    func applyAdjustmentPreset(_ preset: AdjustmentPreset) {
        changeAdjustments(ofVersions: actionTargetVersionIDs,
                          actionName: String(localized: "Apply Preset \(preset.name)", comment: "Undo action name")) {
            preset.applied(onto: $0)
        }
    }

    /// Shows the photo in the loupe with the preset, without saving it.
    func previewAdjustmentPreset(_ preset: AdjustmentPreset) {
        editor.preview { $0 = preset.applied(onto: $0) }
    }

    // MARK: Saving

    /// The focused photo's adjustments, from the editor when it has them loaded.
    private func focusedAdjustments() async -> Adjustments? {
        guard let item = focusedItem else { return nil }
        if editor.item?.versionID == item.versionID, editor.state == .ready { return editor.adjustments }
        let stack = (try? await catalog.version(id: item.versionID)?.decodedEditStack()) ?? .identity
        return Adjustments(stack: stack)
    }

    /// Saves the focused photo's adjustments under `name` in `collection`
    /// (replacing a preset of that name there), with `groups` or the photo's
    /// modified ones.
    func saveAdjustmentPreset(named name: String, collection: String = "", groups: Set<Adjustments.Group>? = nil) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let collection = collection.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            guard let values = await focusedAdjustments() else { return }
            let preset = AdjustmentPreset(name: name, collection: collection, groups: groups ?? values.modifiedGroups,
                                          adjustments: values)
            do {
                _ = try await catalog.saveAdjustmentPreset(preset)
            } catch {
                statusMessage = String(localized: "Could not save the preset: \(error.localizedDescription)")
            }
            await refreshAdjustmentPresets()
        }
    }

    /// Asks for a name, a collection and the groups to include, then saves a preset.
    func promptForAdjustmentPreset() {
        Task {
            guard let values = await focusedAdjustments() else { return }
            let dialog = PresetSaveDialog(collections: adjustmentPresetCollectionNames, modified: values.modifiedGroups)
            guard let answer = dialog.run() else { return }
            saveAdjustmentPreset(named: answer.name, collection: answer.collection, groups: answer.groups)
        }
    }

    // MARK: Managing

    /// Writes a changed preset (name, collection or groups) in place.
    func updateAdjustmentPreset(_ preset: AdjustmentPreset) {
        guard preset.id != nil, !preset.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            _ = try? await catalog.saveAdjustmentPresets([preset])
            await refreshAdjustmentPresets()
        }
    }

    func deleteAdjustmentPreset(_ preset: AdjustmentPreset) {
        guard let id = preset.id else { return }
        Task {
            try? await catalog.deleteAdjustmentPreset(id: id)
            await refreshAdjustmentPresets()
        }
    }

    func renameAdjustmentPresetCollection(_ collection: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != collection else { return }
        Task {
            try? await catalog.renameAdjustmentPresetCollection(collection, to: name)
            await refreshAdjustmentPresets()
        }
    }

    func deleteAdjustmentPresetCollection(_ collection: String) {
        Task {
            try? await catalog.deleteAdjustmentPresets(inCollection: collection)
            await refreshAdjustmentPresets()
        }
    }

    // MARK: Importing

    static var presetFileTypes: [UTType] {
        PresetImport.fileExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    /// Asks for preset files or folders, then imports them.
    func chooseAdjustmentPresetImport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.presetFileTypes
        panel.prompt = String(localized: "Import")
        panel.message = String(localized: "Choose presets (.\(PresetFile.fileExtension), .lrtemplate, .xmp or .dng), or folders of them.")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        Task { await importAdjustmentPresets(panel.urls) }
    }

    /// Reads and saves the presets in `urls`, then shows what was imported.
    @discardableResult
    func importAdjustmentPresets(_ urls: [URL], showsSummary: Bool = true) async -> PresetImport.Result? {
        let scan = await Task.detached(priority: .userInitiated) { PresetImport.scan(urls) }.value
        let result: PresetImport.Result
        do {
            result = try await PresetImport.run(scan, catalog: catalog, store: lookTables)
        } catch {
            statusMessage = String(localized: "Could not import the presets: \(error.localizedDescription)")
            return nil
        }
        await refreshAdjustmentPresets()
        if result.addedTables > 0 { await lookTableLibrary.reload() }
        if showsSummary { presetImportSummary = Self.summary(of: result) }
        return result
    }

    static func summary(of result: PresetImport.Result) -> PresetImportSummary {
        var lines: [String] = []
        let collections = Array(Set(result.imported.map(\.collection).filter { !$0.isEmpty })).sorted()
        if !collections.isEmpty {
            lines.append(String(localized: "Collections: \(collections.formatted(.list(type: .and)))"))
        }
        if !result.unsupported.isEmpty {
            let features = CameraRawFeature.allCases.compactMap { feature in
                result.unsupported[feature].map { String(localized: "\(PresetText.title(feature)) (\($0))") }
            }
            lines.append(String(localized: "Some settings have no equivalent here and were left out or approximated (number of presets): \(features.formatted(.list(type: .and)))."))
        }
        if result.addedTables > 0 {
            lines.append(String(localized: "Look-up tables added to the library: \(result.addedTables)"))
        }
        if !result.failures.isEmpty {
            let files = result.failures.prefix(8).map { "\($0.url.lastPathComponent) (\($0.reason))" }
            lines.append(String(localized: "Files that could not be read: \(files.formatted(.list(type: .and)))"))
        }
        let title = result.imported.isEmpty ? String(localized: "No Presets Imported")
            : String(localized: "Presets imported: \(result.imported.count)")
        return PresetImportSummary(title: title, message: lines.joined(separator: "\n\n"))
    }

    // MARK: Exporting

    /// Asks where to save `presets` as one preset file.
    func exportAdjustmentPresets(_ presets: [AdjustmentPreset], suggestedName: String) {
        guard !presets.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = UTType(filenameExtension: PresetFile.fileExtension).map { [$0] } ?? []
        panel.nameFieldStringValue = "\(suggestedName).\(PresetFile.fileExtension)"
        panel.message = String(localized: "Look-up tables the presets use are saved in the file.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try writeAdjustmentPresets(presets, to: url)
        } catch {
            statusMessage = String(localized: "Could not export the presets: \(error.localizedDescription)")
        }
    }

    func writeAdjustmentPresets(_ presets: [AdjustmentPreset], to url: URL) throws {
        try PresetFile(presets: presets, store: lookTables).data().write(to: url, options: .atomic)
    }
}

/// Names for what preset imports report.
enum PresetText {
    static func title(_ feature: CameraRawFeature) -> String {
        switch feature {
        case .autoSettings: String(localized: "Auto white balance and auto tone")
        case .profile: String(localized: "Profiles and creative looks")
        case .texture: String(localized: "Texture", comment: "Imported preset setting")
        case .calibration: String(localized: "Calibration", comment: "Imported preset setting")
        case .globalColorGrade: String(localized: "Global color grading")
        case .pointColor: String(localized: "Point color")
        case .blackAndWhite: String(localized: "Black and white (approximated)")
        case .localAdjustments: String(localized: "Masks and local adjustments")
        case .retouching: String(localized: "Retouching")
        case .crop: String(localized: "Crop", comment: "Imported preset setting")
        case .lensCorrections: String(localized: "Lens corrections")
        case .transform: String(localized: "Perspective corrections")
        case .defringe: String(localized: "Defringe", comment: "Imported preset setting")
        case .vignetteStyle: String(localized: "Vignette feather and style")
        case .legacyProcess: String(localized: "Older process versions (approximated)")
        }
    }

    /// "All settings", or the groups a preset applies.
    static func groups(_ preset: AdjustmentPreset) -> String {
        if preset.includesEveryGroup { return String(localized: "All settings") }
        if preset.groups.isEmpty { return String(localized: "No settings") }
        return Adjustments.Group.allCases.filter(preset.groups.contains).map(AdjustText.title).joined(separator: ", ")
    }
}

/// The Save Preset dialog: name, collection and the groups to include.
@MainActor
struct PresetSaveDialog {
    struct Answer {
        var name: String
        var collection: String
        var groups: Set<Adjustments.Group>
    }

    let collections: [String]
    /// Checked at first.
    let modified: Set<Adjustments.Group>

    func run() -> Answer? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Save Preset")
        alert.informativeText = String(localized: "Applying the preset replaces the checked groups and leaves the others as they are. A preset with the same name in the collection is replaced.")
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        nameField.placeholderString = String(localized: "Preset name")
        let collectionField = NSComboBox(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        collectionField.placeholderString = String(localized: "No collection")
        collectionField.addItems(withObjectValues: collections)
        collectionField.completes = true

        let groups = Adjustments.Group.allCases
        let boxes = groups.map { group in
            let box = NSButton(checkboxWithTitle: AdjustText.title(group), target: nil, action: nil)
            box.state = modified.contains(group) ? .on : .off
            return box
        }
        let rows = stride(from: 0, to: boxes.count, by: 2).map { index in
            [boxes[index], index + 1 < boxes.count ? boxes[index + 1] : NSGridCell.emptyContentView]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 4
        grid.columnSpacing = 16

        let caption = NSTextField(labelWithString: String(localized: "Include"))
        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        let collectionLabel = NSTextField(labelWithString: String(localized: "Collection"))
        collectionLabel.font = caption.font
        collectionLabel.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [nameField, collectionLabel, collectionField, caption, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: nameField)
        stack.setCustomSpacing(12, after: collectionField)
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        nameField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        collectionField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        alert.accessoryView = stack
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let checked = zip(groups, boxes).filter { $0.1.state == .on }.map(\.0)
        return Answer(name: name, collection: collectionField.stringValue, groups: Set(checked))
    }
}
