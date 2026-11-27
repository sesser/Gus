import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// Exports the selected photos (section 8 of docs/UI_REDESIGN.md): a sheet
/// on the library window, which freezes what it acts on. A fixed header, one
/// scrolling form column, then Cancel and Export. The export runs after the
/// sheet closes, with progress in the toolbar's Activity item.
struct ExportSheet: View {
    let model: LibraryModel

    private var export: ExportModel { model.export }

    var body: some View {
        @Bindable var export = export
        VStack(spacing: 0) {
            ExportHeader(model: model)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Divider()
            ExportForm(model: model)
            Divider()
            buttons
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 560)
        .frame(minHeight: 480, idealHeight: 640)
        .presentationSizing(.fitted)
        .alert(conflictTitle, isPresented: Binding(get: { export.conflict != nil },
                                                   set: { if !$0 { export.conflict = nil } })) {
            Button("Keep Both") { resolve(.keepBoth) }
                .keyboardShortcut(.defaultAction)
            Button("Replace", role: .destructive) { resolve(.overwrite) }
            Button("Skip Them") { resolve(.skip) }
            Button("Cancel", role: .cancel) { export.conflict = nil }
        } message: {
            Text(ExportModel.conflictMessage(count: export.conflict?.count ?? 0, masters: export.conflict?.masters ?? 0))
        }
    }

    private var conflictTitle: String {
        String(localized: "\(export.conflict?.count ?? 0) files already exist in “\(export.destination.lastPathComponent)”")
    }

    private func resolve(_ policy: ExportConflictPolicy) {
        export.resolveConflict(policy)
        model.showsExportSheet = false
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel", role: .cancel) { model.showsExportSheet = false }
                .keyboardShortcut(.cancelAction)
            Button(String(localized: "Export \(export.versionIDs.count) Photos")) {
                Task {
                    if await export.requestExport() { model.showsExportSheet = false }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(export.versionIDs.isEmpty || export.isExporting)
        }
    }
}

/// The first photo, how many are exported, and from where.
private struct ExportHeader: View {
    let model: LibraryModel

    var body: some View {
        let export = model.export
        HStack(spacing: 12) {
            Group {
                if let image = export.previewImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(nsColor: Palette.cell)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text("Export \(export.versionIDs.count) Photos")
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                // Information, not an issue: above any general issue (issue #282, design §10).
                if export.hdrPhotos > 0 {
                    Label {
                        Text(HDRText.exportNotice(export.hdrPhotos)).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                if let issue = export.issue, issue.place == .general {
                    IssueText(text: issue.text)
                }
            }
            Spacer()
        }
    }

    /// "From All Photos · 3 videos are skipped".
    private var subtitle: String {
        let source = String(localized: "From \(model.title(for: model.sidebarSelection))", comment: "Export and Merge to HDR sheets: the sidebar source")
        let skipped = model.export.skippedVideos
        guard skipped > 0 else { return source }
        return [source, String(localized: "\(skipped) videos are skipped", comment: "Export sheet: videos are not exported")]
            .joined(separator: " · ")
    }
}

/// An error next to the row it concerns: a warning sign and the text.
struct IssueText: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

/// A caption under the row it explains: 11 pt secondary.
struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ExportForm: View {
    let model: LibraryModel

    private var export: ExportModel { model.export }

    var body: some View {
        @Bindable var export = export
        Form {
            ExportPresetRow(presets: export.presets, selectedID: export.presetID, modified: export.modifiedPreset,
                            issue: export.issue?.place == .preset ? export.issue?.text : nil,
                            apply: { export.applyPreset(id: $0) }, save: { export.savePreset(named: $0) },
                            update: { export.updateSelectedPreset() }, delete: { export.deleteSelectedPreset() })
            Section("Destination") {
                LabeledContent("Folder") {
                    HStack {
                        Text(export.destination.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(export.destination.path)
                        Button("Choose Folder…") { export.chooseDestination(in: NSApp.keyWindow) }
                    }
                }
                Toggle("Show in Finder when done", isOn: $export.revealsInFinder)
                    .toggleStyle(.checkbox)
                if let issue = export.issue, issue.place == .destination { IssueText(text: issue.text) }
            }
            ExportSettingsSections(editor: export.editor,
                                   watermarkIssue: export.issue?.place == .watermark ? export.issue?.text : nil)
        }
        .formStyle(.grouped)
    }
}

enum ExportText {
    static func anchorName(_ anchor: Watermark.Anchor) -> String {
        switch anchor {
        case .topLeft: String(localized: "Top left")
        case .top: String(localized: "Top")
        case .topRight: String(localized: "Top right")
        case .left: String(localized: "Left")
        case .center: String(localized: "Center")
        case .right: String(localized: "Right")
        case .bottomLeft: String(localized: "Bottom left")
        case .bottom: String(localized: "Bottom")
        case .bottomRight: String(localized: "Bottom right")
        }
    }
}
