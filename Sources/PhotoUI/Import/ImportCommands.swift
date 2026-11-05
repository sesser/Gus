import PhotoCore
import SwiftUI

/// The import window's menu items, shared by the library app and the
/// standalone importer and on only while an import window is key (section 6
/// of docs/UI_REDESIGN.md). Edit ▸ Select All (⌘A) is the system item: the
/// grid answers `selectAll(_:)` while it has the focus, and text fields keep
/// theirs.
public struct ImportCommands: Commands {
    /// The library app also offers Show Photos Already in Library.
    let includesLibraryItems: Bool
    /// Off in the library app, whose Show / Hide Inspector item (⌥⌘I too)
    /// toggles the options while an import window is key: AppKit stops at the
    /// first item with a key equivalent, even a disabled one.
    let includesOptionsItem: Bool
    /// Off in the library app, whose own Deselect All (⇧⌘A) and Stop (⌘.)
    /// act for the import window while it is key (design.md P3, I4, I5), for
    /// the same reason.
    let includesSharedItems: Bool
    @FocusedValue(\.importMenu) private var menu

    public init(includesLibraryItems: Bool, includesOptionsItem: Bool = true, includesSharedItems: Bool = true) {
        self.includesLibraryItems = includesLibraryItems
        self.includesOptionsItem = includesOptionsItem
        self.includesSharedItems = includesSharedItems
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
            if includesSharedItems {
                Button("Stop Import") { menu?.stopImport() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!(menu?.canStopImport ?? false))
            }
            Divider()
        }
        CommandGroup(after: .pasteboard) {
            if includesSharedItems {
                Button("Deselect All") { menu?.deselectAll() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!(menu?.canDeselectAll ?? false))
            }
        }
        CommandGroup(after: .sidebar) {
            if includesOptionsItem {
                Button(menu?.optionsTitle ?? String(localized: "Hide Options")) { menu?.toggleOptions() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(menu == nil)
            }
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
public struct ImportMenuContext: Equatable {
    let model: CardImportModel
    let state: ImportMenuState

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.state == rhs.state
    }

    /// Show Options / Hide Options.
    public var optionsTitle: String {
        state.showsOptions ? String(localized: "Hide Options") : String(localized: "Show Options")
    }

    @MainActor
    public func toggleOptions() {
        model.showsOptions.toggle()
    }

    /// Edit ▸ Deselect All (⇧⌘A) for the import window.
    public var canDeselectAll: Bool { state.selectedCount > 0 && !state.isImporting }

    @MainActor
    public func deselectAll() {
        model.selectNone()
    }

    /// File ▸ Stop Import (⌘.) for the import window.
    public var canStopImport: Bool { state.isImporting }

    @MainActor
    public func stopImport() {
        model.cancelImport()
    }
}

struct ImportMenuState: Equatable {
    var hasSource: Bool
    var selectedCount: Int
    var isImporting: Bool
    var includesVideos: Bool
    var showsDuplicates: Bool
    var copiesOnly: Bool
    var showsOptions: Bool

    @MainActor
    init(_ model: CardImportModel) {
        hasSource = model.source != nil
        selectedCount = model.selectedShots.count
        // `progress` is observed and set with the import task, which is not.
        isImporting = model.progress != nil || model.isImporting
        includesVideos = model.includesVideos
        showsDuplicates = model.showsDuplicates
        copiesOnly = model.copiesOnly
        showsOptions = model.showsOptions
    }
}

extension FocusedValues {
    @Entry public var importMenu: ImportMenuContext?
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
