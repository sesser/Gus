import Foundation

/// Whether quitting (or, in the standalone importer, closing its window)
/// asks first because it would stop a job (section 8 of docs/UI_REDESIGN.md,
/// "Quitting while copying").
public enum QuitConfirmation: Equatable, Sendable {
    /// The standalone importer: "Stop Importing from “‹source›”?".
    case stopCopy
    /// The library app: "Quit While Importing?" (a copy or folders being added).
    case importing
    /// The library app: "Quit While Exporting?".
    case exporting

    public enum App: Sendable { case library, importer }
    public enum Trigger: Sendable { case quit, closeImportWindow }

    /// Nil: go ahead without asking.
    public static func needed(app: App, trigger: Trigger, isCopying: Bool, isAddingFolders: Bool = false,
                              isExporting: Bool = false) -> QuitConfirmation? {
        switch app {
        case .importer:
            // Closing the importer's only window quits it.
            return isCopying ? .stopCopy : nil
        case .library:
            // Closing the library's Import window keeps the copy going.
            guard trigger == .quit else { return nil }
            if isCopying || isAddingFolders { return .importing }
            return isExporting ? .exporting : nil
        }
    }
}
