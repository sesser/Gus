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

    /// The window the confirmation is attached to: the key window, else
    /// the main one, else the first of the visible ones; but never one
    /// `isPassedOver` names. The About window and the license windows are
    /// passed over: a quit asked from one of them is confirmed on the
    /// app's own window (the library's, the import window), where the job
    /// it would stop is. When that window shows a sheet, the confirmation
    /// goes on the sheet (`frontSheet`). Nil when no other window is there:
    /// the alert then stands alone.
    public static func host<Window>(key: Window?, main: Window?, visible: [Window],
                                    isPassedOver: (Window) -> Bool,
                                    attachedSheet: (Window) -> Window?) -> Window? {
        ([key, main].compactMap { $0 } + visible).first { !isPassedOver($0) }
            .map { frontSheet(of: $0, attachedSheet: attachedSheet) }
    }

    /// The front-most sheet on a window (a sheet's own sheet included), or
    /// the window itself when it shows none. A sheet asked on a window
    /// that already shows one is not shown: AppKit keeps it until the
    /// first ends, and the quit would seem to do nothing. While a sheet is
    /// up it is the key window, so this is where a quit asked from the
    /// window itself already goes.
    public static func frontSheet<Window>(of window: Window, attachedSheet: (Window) -> Window?) -> Window {
        var front = window
        // Bounded, so a chain that came back on itself could not hang a quit.
        for _ in 0..<16 {
            guard let sheet = attachedSheet(front) else { break }
            front = sheet
        }
        return front
    }
}
