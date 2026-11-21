import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// File ▸ Merge to HDR… (hdr-merge design §5): a sheet on the library window
/// built like the Export sheet. A fixed header with the refusal or note, the
/// frames in capture order, the result's format, name and folder, then
/// Cancel and Merge. The merge runs after the sheet closes, in Activity.
struct MergeSheet: View {
    let model: LibraryModel

    private var merge: MergeModel { model.merge }

    var body: some View {
        VStack(spacing: 0) {
            MergeHeader(model: model)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Divider()
            MergeForm(model: model)
            Divider()
            buttons
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 560)
        .frame(minHeight: 420, idealHeight: 560)
        .presentationSizing(.fitted)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if merge.isCheckingSlowly {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("Cancel", role: .cancel) { model.showsMergeSheet = false }
                .keyboardShortcut(.cancelAction)
            Button(MergeText.mergeButton) { merge.start() }
                .keyboardShortcut(.defaultAction)
                .disabled(!merge.canStart)
        }
    }
}

/// The reference's thumbnail, how many frames, from where, and the message.
private struct MergeHeader: View {
    let model: LibraryModel

    var body: some View {
        let merge = model.merge
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let image = merge.previewImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(nsColor: Palette.cell)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(MergeText.sheetTitle(merge.selection?.frames.count ?? merge.targetIDs.count))
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(MergeText.source(model.title(for: model.sidebarSelection)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let refusal = merge.refusal {
                    IssueText(text: MergeText.refusal(refusal))
                }
            }
            Spacer()
        }
    }
}

private struct MergeForm: View {
    let model: LibraryModel

    private var merge: MergeModel { model.merge }

    var body: some View {
        @Bindable var merge = merge
        Form {
            Section(MergeText.photosSection) {
                framesTable
                if let selection = merge.selection {
                    Caption(text: MergeText.referenceCaption(selection.referenceFrame.displayName))
                    if selection.sameExposure {
                        Label {
                            Text(MergeText.sameExposureNote).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            Section(MergeText.resultSection) {
                Picker(MergeText.formatLabel, selection: $merge.format) {
                    Text(MergeText.tiff).tag(MergeFormat.tiff)
                    Text(MergeText.dng).tag(MergeFormat.dng)
                }
                .pickerStyle(.segmented)
                Caption(text: merge.format == .tiff ? MergeText.tiffCaption : MergeText.dngCaption)
                LabeledContent(MergeText.nameLabel) {
                    Text(merge.resultName ?? "—")
                        .textSelection(.enabled)
                }
                if let selection = merge.selection {
                    LabeledContent(MergeText.folderLabel) {
                        Text(selection.referenceFrame.folder.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(selection.referenceFrame.folder.path)
                    }
                    Caption(text: MergeText.savedNextTo(selection.referenceFrame.displayName)
                        + (merge.framesInSeveralFolders ? " " + MergeText.severalFolders : ""))
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The frames in capture order, the flagged ones marked by a symbol and
    /// their accessibility value, never by color alone (design §5.2, §11).
    private var framesTable: some View {
        let frames = merge.selection?.frames ?? []
        let reference = merge.selection.map { $0.referenceFrame.versionID }
        let flagged = merge.flagged
        return Table(frames) {
            TableColumn(MergeText.photoColumn) { frame in
                HStack(spacing: 4) {
                    if flagged.contains(frame.versionID) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(frame.displayName)
                    if frame.versionID == reference {
                        Text(MergeText.referenceRole).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(flagged.contains(frame.versionID) ? MergeText.problem : "")
            }
            TableColumn(MergeText.typeColumn) { frame in
                Text(frame.kind.map(FileKindText.badge) ?? "—")
            }
            .width(min: 50, ideal: 60)
            TableColumn(MergeText.shutterColumn) { frame in
                Text(MergeText.shutter(frame.exposureTime)).monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            TableColumn(MergeText.compensationColumn) { frame in
                Text(MergeText.compensation(frame.exposureCompensation)).monospacedDigit()
            }
            .width(min: 80, ideal: 100)
        }
        .frame(height: min(250, CGFloat(max(frames.count, 2)) * 24 + 28))
    }
}
