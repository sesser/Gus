import Foundation

/// Titles of Activity rows that come from commands without an undo name:
/// the command's menu title without its ellipsis, and its object (section 1
/// of docs/UI_REDESIGN.md). Import from “‹source›” is the import window's
/// (`CardImportModel`).
enum ActivityTitle {
    /// One folder by name; a drop with none, plain.
    static func addFolder(_ name: String?) -> String {
        name.map { String(localized: "Add Folder “\($0)”", comment: "Activity row title: a folder added without copying") }
            ?? String(localized: "Add Folder", comment: "Activity row title: folders added without copying")
    }

    /// A batch of several folders.
    static func addFolders(_ count: Int) -> String {
        String(localized: "Add \(count) Folders", comment: "Activity row title: several folders added without copying")
    }

    /// The title for a batch of `count` folders, the one named `name` if
    /// there is only one.
    static func addFolders(_ count: Int, name: String?) -> String {
        count > 1 ? addFolders(count) : addFolder(name)
    }

    /// A look-up table a photo uses that is missing from the library.
    static func lookTable(_ name: String) -> String {
        String(localized: "Look-Up Table “\(name)”", comment: "Activity row title: a missing look-up table")
    }

    static func exportTo(_ folder: String) -> String {
        String(localized: "Export to “\(folder)”", comment: "Activity row title")
    }

    static var importLookTables: String { String(localized: "Import Look-Up Tables", comment: "Activity row title") }
    static var importPresets: String { String(localized: "Import Presets", comment: "Activity row title") }
    static var exportPresets: String { String(localized: "Export Presets", comment: "Activity row title") }
    static var saveAsPreset: String { String(localized: "Save Adjustments as Preset", comment: "Activity row title") }
    static var saveChanges: String { String(localized: "Save Changes", comment: "Activity row title: saving to the library failed") }
    static var loadLibrary: String { String(localized: "Load Library", comment: "Activity row title") }
}
