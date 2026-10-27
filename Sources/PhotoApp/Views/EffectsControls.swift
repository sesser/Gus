import AppKit
import PhotoCore
import SwiftUI

/// The Effects heading: look-up table, vignette and grain.
struct EffectsControls: View {
    let model: LibraryModel

    private var editor: AdjustmentEditor { model.editor }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel(.lookTable, editor: editor)
            LookTableControls(model: model)
                .dimmedWhenOff(.lookTable, editor: editor)
            GroupLabel(.vignette, editor: editor)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 8) {
                adjustSlider(editor, String(localized: "Amount"), \.vignette.amount)
                adjustSlider(editor, String(localized: "Size", comment: "Vignette or grain size"), \.vignette.size,
                             range: 0...100, defaultValue: 50, format: .plain)
                adjustSlider(editor, String(localized: "Roundness"), \.vignette.roundness)
            }
            .dimmedWhenOff(.vignette, editor: editor)
            GroupLabel(.grain, editor: editor)
                .padding(.top, 6)
            GrainControls(editor: editor)
                .dimmedWhenOff(.grain, editor: editor)
        }
    }
}

/// The applied table (picked from a menu of collections), its intensity and
/// color space, and the browser, import and management windows.
private struct LookTableControls: View {
    let model: LibraryModel

    private var editor: AdjustmentEditor { model.editor }
    private var library: LookTableLibraryModel { model.lookTableLibrary }

    var body: some View {
        let table = editor.adjustments.lookTable
        VStack(alignment: .leading, spacing: 8) {
            LabeledPopUp(title: String(localized: "Table")) {
                HStack(spacing: 4) {
                    AppKitMenuButton(title: library.displayName(for: table), entries: menu(selected: table.identifier),
                                     help: String(localized: "Choose a look-up table"))
                    if let identifier = table.identifier, !model.lookTables.contains(identifier) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help("This table is missing from the library, so it is not applied.")
                    }
                    Spacer(minLength: 0)
                }
            }
            if table.identifier != nil {
                adjustSlider(editor, String(localized: "Intensity"), \.lookTable.intensity, range: 0...100,
                             defaultValue: 100, format: .plain)
                LabeledPopUp(title: String(localized: "Color Space")) {
                    AppKitPopUp(items: LookTable.ColorSpace.allCases.map { .init(title: LookTableText.title($0), tag: $0.rawValue) },
                                selection: table.colorSpace.rawValue) { tag in
                        editor.change(String(localized: "Look-Up Table"), phase: .committed) {
                            $0.lookTable.colorSpace = LookTable.ColorSpace(rawValue: tag) ?? .sRGB
                        }
                    }
                }
            }
            // Push buttons do not shrink: wrap them when the inspector is narrow,
            // or they would widen the whole column and eat its padding.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    browseButton
                    importButton
                    manageButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        browseButton
                        importButton
                    }
                    manageButton
                }
            }
        }
    }

    private var browseButton: AppKitButton {
        AppKitButton(title: String(localized: "Browse…"), style: .push,
                     help: String(localized: "See every table on this photo")) {
            model.requestsLookTableWindow = true
        }
    }

    private var importButton: AppKitButton {
        AppKitButton(title: String(localized: "Import…"), style: .push,
                     help: String(localized: "Add a folder of .cube files as a collection")) {
            model.requestsLookTableWindow = true
            library.chooseImportSource()
        }
    }

    private var manageButton: AppKitButton {
        AppKitButton(title: String(localized: "Manage…"), style: .push,
                     help: String(localized: "Rename or remove collections and tables")) {
            model.requestsLookTableWindow = true
            library.sheet = .manage
        }
    }

    private func menu(selected: String?) -> [AppKitMenuButton.Entry] {
        var entries: [AppKitMenuButton.Entry] = [
            .check(String(localized: "None", comment: "No look-up table"), isOn: selected == nil) {
                editor.change(String(localized: "Look-Up Table"), phase: .committed) { $0.lookTable = LookTable() }
            },
            .separator,
        ]
        for collection in library.collections {
            entries.append(.submenu(collection.name, collection.entries.map { entry in
                .check(entry.name, isOn: entry.identifier == selected) { library.apply(entry, editor: editor) }
            }))
        }
        return entries
    }
}

/// Grain strength, its amount per tonal range, its character and size.
private struct GrainControls: View {
    let editor: AdjustmentEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            adjustSlider(editor, String(localized: "Strength"), \.grain.strength, range: Grain.strengthRange,
                         format: .plain)
            caption(String(localized: "Amount by Tone"))
            adjustSlider(editor, String(localized: "Shadows"), \.grain.shadows, range: 0...100, defaultValue: 30,
                         format: .plain)
            adjustSlider(editor, String(localized: "Midtones", comment: "Color grading range"), \.grain.midtones,
                         range: 0...100, defaultValue: 40, format: .plain)
            adjustSlider(editor, String(localized: "Highlights"), \.grain.highlights, range: 0...100, defaultValue: 15,
                         format: .plain)
            caption(String(localized: "Character"))
            adjustSlider(editor, String(localized: "Roughness"), \.grain.roughness, range: 0...100, defaultValue: 50,
                         format: .plain)
            adjustSlider(editor, String(localized: "Color"), \.grain.color, range: 0...100, format: .plain)
            adjustSlider(editor, String(localized: "Size", comment: "Vignette or grain size"), \.grain.size,
                         range: Grain.sizeRange, defaultValue: 1, format: .decimal)
            if editor.adjustments.grain.strength == 0 {
                Text("Raise Strength to add grain. Grain is easiest to judge at 1:1 (Z).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}
