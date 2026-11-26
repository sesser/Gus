import Foundation

/// Every sheet, confirmation dialog and alert that SwiftUI presents on the
/// library window, other than the preset manager: the one list the window's
/// "one sheet at a time" rule (UI_REDESIGN §8) reads when a preset pack
/// import ends and wants to open the manager on its report (#203: F2, C7, C9).
///
/// **A new sheet, dialog or alert on the library window goes here**, with its
/// flag in `LibraryModel.isUp(_:)`, and calls `modalDidClose()` when it has
/// closed: a sheet from its `onDismiss`, a dialog or alert by being of kind
/// `.dialog` (`MainView` watches `dialogIsUp`). Otherwise a report can open
/// over it. `LibraryModalTests` fails when `MainView` and `SidebarView`
/// present more than this lists. Panels and alerts run through `WindowModal`
/// (AppKit) are not covered.
enum LibraryModal: CaseIterable {
    case export, lookTables, sidebarSheet, sidebarDeletion, removal, importSummary, merge, copyAdjustments, publish, publishServer, publishResults

    enum Kind {
        /// Calls `modalDidClose()` from its `onDismiss`, once it has gone.
        case sheet
        /// A confirmation dialog or an alert: no `onDismiss`, so `MainView` sees it close.
        case dialog
    }

    var kind: Kind {
        switch self {
        case .export, .lookTables, .sidebarSheet, .merge, .copyAdjustments, .publish, .publishServer, .publishResults: .sheet
        case .sidebarDeletion, .removal, .importSummary: .dialog
        }
    }
}

extension LibraryModel {
    func isUp(_ modal: LibraryModal) -> Bool {
        switch modal {
        case .export: showsExportSheet
        case .lookTables: showsLookTableSheet
        case .sidebarSheet: sidebarSheet != nil
        case .sidebarDeletion: sidebarDeletion != nil
        case .removal: pendingRemoval != nil
        case .importSummary: presetImportSummary != nil
        case .merge: showsMergeSheet
        case .copyAdjustments: showsCopySheet
        case .publish: showsPublishSheet
        case .publishServer: publish.serverSheet != nil
        case .publishResults: showsPublishResults
        }
    }

    /// A sheet, dialog or alert other than the preset manager is up on the window.
    var otherModalIsUp: Bool { LibraryModal.allCases.contains(where: isUp) }

    /// A dialog or alert is up (they close without `onDismiss`).
    var dialogIsUp: Bool { LibraryModal.allCases.contains { $0.kind == .dialog && isUp($0) } }

    /// One sheet at a time: the preset manager opens now, or, when another
    /// sheet, dialog or alert is up, once the last of them has closed.
    func openPresetSheetWhenFree() {
        if otherModalIsUp {
            presetSheetWaits = true
        } else {
            showsPresetSheet = true
        }
    }

    /// A sheet, dialog or alert of the window has closed: a waiting report opens, unless one is still up.
    func modalDidClose() {
        // Publish's Server sheet comes up in its place first (publishing design §4).
        if publish.sheetDidClose() { return }
        guard presetSheetWaits, !otherModalIsUp else { return }
        presetSheetWaits = false
        presetManagerPage = .report
        showsPresetSheet = true
    }
}
