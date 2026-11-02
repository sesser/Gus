import PhotoCore
import SwiftUI

/// The import window's menu items, shared by the library app and the
/// standalone importer and on only while an import window is key (section 6
/// of docs/UI_REDESIGN.md). Select All / Deselect All and Show / Hide Options
/// come with the rebuilt import window (plan step 13): today's grid cannot take
/// the keyboard, so ⌘A must stay with the text fields, and the options are not
/// a pane that hides.
public struct ImportCommands: Commands {
    /// The library app also offers Show Photos Already in Library.
    let includesLibraryItems: Bool
    @FocusedValue(\.importMenu) private var menu

    public init(includesLibraryItems: Bool) {
        self.includesLibraryItems = includesLibraryItems
    }

    private var model: CardImportModel? { menu?.model }

    private func can(_ test: (ImportMenuState) -> Bool) -> Bool {
        menu.map { test($0.state) } ?? false
    }

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose Folder…") { model?.chooseFolder() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!can { !$0.isImporting })
            Button("Rescan") { model?.rescan(keepingPicks: true) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!can { $0.hasSource && !$0.isImporting })
            Button("Import Selected Photos") { model?.startImport() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!can { $0.hasSource && $0.selectedCount > 0 && !$0.isImporting })
            Button("Stop Import") { model?.cancelImport() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!can { $0.isImporting })
            Divider()
        }
        CommandGroup(after: .sidebar) {
            Toggle("Show Videos", isOn: Binding(
                get: { menu?.state.includesVideos ?? false },
                set: { model?.includesVideos = $0 }
            ))
            .disabled(!can { !$0.isImporting })
            if includesLibraryItems {
                Toggle("Show Photos Already in Library", isOn: Binding(
                    get: { menu?.state.showsDuplicates ?? false },
                    set: { model?.showsDuplicates = $0 }
                ))
                .disabled(!can { !$0.copiesOnly })
            }
            Divider()
        }
    }
}

/// What the import menus read from the import window, published with
/// `focusedSceneValue` so the menus follow it.
struct ImportMenuContext: Equatable {
    let model: CardImportModel
    let state: ImportMenuState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.state == rhs.state
    }
}

struct ImportMenuState: Equatable {
    var hasSource: Bool
    var selectedCount: Int
    var isImporting: Bool
    var includesVideos: Bool
    var showsDuplicates: Bool
    var copiesOnly: Bool

    @MainActor
    init(_ model: CardImportModel) {
        hasSource = model.source != nil
        selectedCount = model.selectedShots.count
        // `progress` is observed and set with the import task, which is not.
        isImporting = model.progress != nil || model.isImporting
        includesVideos = model.includesVideos
        showsDuplicates = model.showsDuplicates
        copiesOnly = model.copiesOnly
    }
}

extension FocusedValues {
    @Entry var importMenu: ImportMenuContext?
}

/// Publishes the import menu context from a view of its own.
struct ImportMenuPublisher: View {
    let model: CardImportModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .focusedSceneValue(\.importMenu, ImportMenuContext(model: model, state: ImportMenuState(model)))
    }
}
