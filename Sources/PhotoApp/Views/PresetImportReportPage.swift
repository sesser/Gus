import PhotoCore
import SwiftUI

/// The preset manager's Import Report page: what the last import with a
/// preset pack did, per pack and per preset (preset-pack import design §2,
/// §3). Back returns to the presets (Esc too); Done closes the sheet.
struct PresetImportReportPage: View {
    let model: LibraryModel
    let result: PresetImport.Result
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                PageHeader(title: String(localized: "Import Report")) { model.presetManagerPage = .list }
                Text(verbatim: PresetReportText.summary(of: result))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            List {
                if !result.failures.isEmpty {
                    Section {
                        ForEach(Array(result.failures.enumerated()), id: \.offset) { _, failure in
                            RefusedFileRow(failure: failure)
                        }
                    } header: {
                        Text("Not imported")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                ForEach(result.packs) { pack in
                    Section {
                        ForEach(pack.presets) { preset in
                            if preset.isUnreadable {
                                UnreadablePresetRow(preset: preset)
                            } else {
                                PresetReportRow(preset: preset)
                            }
                        }
                    } header: {
                        PackHeader(pack: pack)
                    }
                }
                let other = result.otherPresets
                if !other.imported.isEmpty {
                    Section {
                        let summary = LibraryModel.summary(of: other)
                        Text(verbatim: summary.message.isEmpty ? summary.title : "\(summary.title)\n\(summary.message)")
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        Text("Other presets")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        // A page fills the sheet: header on top, buttons at the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A pack's section header: its name, and what it gave.
private struct PackHeader: View {
    let pack: PresetImport.PackReport

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: pack.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(pack.name)
            Spacer()
            Text(verbatim: PresetReportText.summary(of: pack))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A preset, collapsed to its counts; expanded, one line per status.
private struct PresetReportRow: View {
    let preset: PresetImport.PackPresetReport

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                if !preset.mapped.isEmpty {
                    StatusLine(symbol: "checkmark.circle",
                               text: Text("Mapped: \(PresetReportText.tools(preset.mapped))"))
                }
                if !preset.approximated.isEmpty {
                    StatusLine(symbol: "plusminus.circle",
                               text: Text("Approximated: \(PresetReportText.approximated(preset.approximated))"))
                }
                if !preset.leftOut.isEmpty {
                    StatusLine(symbol: "minus.circle",
                               text: Text("Left out: \(PresetReportText.tools(preset.leftOut))"))
                }
                if !preset.unrecognized.isEmpty {
                    // Identifiers as the pack gives them, in monospace: data, not words of ours.
                    let identifiers = Text(verbatim: PresetReportText.identifiers(preset.unrecognized))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                    StatusLine(symbol: "questionmark.circle", text: Text("Not recognized: \(identifiers)"))
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 2)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: preset.name ?? "")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(preset.name ?? "")
                Text(verbatim: PresetReportText.counts(preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: preset.name ?? ""))
            .accessibilityValue(Text(verbatim: PresetReportText.counts(preset)))
        }
    }
}

/// One status line: a symbol in the secondary color, then the words, wrapping.
private struct StatusLine: View {
    let symbol: String
    let text: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            text
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A preset of a pack that could not be read and was skipped.
private struct UnreadablePresetRow: View {
    let preset: PresetImport.PackPresetReport

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: PresetReportText.name(preset))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Its settings can't be read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A file that was not imported, and why.
private struct RefusedFileRow: View {
    let failure: PresetImport.Failure

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: failure.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(failure.url.lastPathComponent)
                Text(verbatim: PresetReportText.reason(failure))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
