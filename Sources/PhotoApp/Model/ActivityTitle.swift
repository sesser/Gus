import Foundation

/// Titles of Activity rows that come from commands without an undo name:
/// the command's menu title without its ellipsis, and its object (section 1
/// of docs/UI_REDESIGN.md). Import from “‹source›” is the import window's
/// (`CardImportModel`).
enum ActivityTitle {
    /// One folder by name; a batch of several, or a drop with none, plain.
    static func addFolder(_ name: String?) -> String {
        name.map { String(localized: "Add Folder “\($0)”", comment: "Activity row title: a folder added without copying") }
            ?? String(localized: "Add Folder", comment: "Activity row title: folders added without copying")
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
