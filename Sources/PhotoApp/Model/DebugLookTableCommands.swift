import AppKit
import PhotoCore
import PhotoUI

/// The debug script's look-up table commands (see `DebugScript`).
@MainActor
enum DebugLookTableCommands {
    static func run(_ verb: String, _ words: [String], model: LibraryModel) async {
        let library = model.lookTableLibrary
        let name = words.joined(separator: " ")
        switch verb {
        case "lut":
            if name == "none" {
                model.editor.change("Debug lut", phase: .committed) { $0.lookTable = LookTable() }
            } else if let entry = entry(named: name, in: library) {
                library.apply(entry, editor: model.editor)
            } else {
                print("debug-script: no look-up table named \(name)")
            }
        case "lutimport":
            guard let path = words.first else { return }
            let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            let collectionName = words.dropFirst().joined(separator: " ")
            let candidates = LookTableImport.candidates(in: folder)
            let existing = library.importedCollections.first { $0.name == collectionName }?.rowID
            let draft = LookTableLibraryModel.ImportDraft(
                source: folder.path, candidates: candidates, collectionID: existing,
                newName: collectionName.isEmpty ? LookTableNaming.cleanedFileName(folder.lastPathComponent) : collectionName)
            await library.runImport(draft)
        case "luts":
            await library.reload()
            for collection in library.collections {
                print("debug-script: lut collection \(collection.name): "
                      + collection.entries.map { "\($0.name) [\($0.colorSpace.rawValue)]" }.joined(separator: ", "))
            }
        case "lutwindow":
            await window(words, model: model)
        default:
            break
        }
    }

    private static func window(_ words: [String], model: LibraryModel) async {
        let library = model.lookTableLibrary
        let argument = words.dropFirst().joined(separator: " ")
        switch words.first {
        case "open":
            model.showsLookTableSheet = true
            try? await Task.sleep(for: .milliseconds(500))
        case "close":
            model.showsLookTableSheet = false
            try? await Task.sleep(for: .milliseconds(400))
        case "all":
            library.browsedCollection = LookTableLibraryModel.allCollections
        case "collection":
            if let collection = library.collections.first(where: { $0.name == argument }) {
                library.browsedCollection = collection.uuid
            }
        case "expand":
            if let collection = library.collections.first(where: { $0.name == argument }) {
                library.expanded.insert(collection.uuid)
            }
        case "select":
            library.selection = entry(named: argument, in: library)
        case "apply":
            // As the sheet's Apply button.
            guard let selection = library.selection else { return }
            library.apply(selection, editor: model.editor)
            model.showsLookTableSheet = false
            try? await Task.sleep(for: .milliseconds(400))
        case "manage":
            library.page = .manage
            try? await Task.sleep(for: .milliseconds(300))
        case "back":
            library.page = nil
            try? await Task.sleep(for: .milliseconds(300))
        case "importmenu":
            // Adjust ▸ Import Look-Up Tables… after its panel returns this folder.
            let folder = URL(fileURLWithPath: (argument as NSString).expandingTildeInPath, isDirectory: true)
            await library.openImportPage(for: [folder])
            try? await Task.sleep(for: .milliseconds(500))
        case "importrun":
            // As the import page's Import button.
            guard case .importing(let draft) = library.page else {
                print("debug-script: the import page is not shown")
                return
            }
            await library.runImport(draft)
            library.page = nil
            try? await Task.sleep(for: .milliseconds(300))
        case "page":
            let page = switch library.page {
            case .importing(let draft): "import (\(draft.importable) of \(draft.candidates.count) tables)"
            case .manage: "manage"
            case nil: "tables"
            }
            print("debug-script: lutwindow sheet \(model.showsLookTableSheet) attached \(NSApp.windows.contains { $0.attachedSheet != nil }) page \(page)")
        case "snapshot":
            // A sheet on the library window; the snapshot shows the sheet.
            guard let window = NSApp.windows.first(where: { $0.attachedSheet != nil }) else {
                print("debug-script: the look-up table sheet is not open")
                return
            }
            WindowSnapshot.write(window, to: URL(fileURLWithPath: (argument as NSString).expandingTildeInPath))
        default:
            print("debug-script: unknown lutwindow command")
        }
    }

    private static func entry(named name: String, in library: LookTableLibraryModel) -> LookTableEntry? {
        for collection in library.collections {
            if let entry = collection.entries.first(where: { $0.name == name }) { return entry }
        }
        return nil
    }
}
