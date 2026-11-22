import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// File ▸ Merge to HDR… (hdr-merge design §5): a sheet on the library window
/// built like the Export sheet. A fixed header with the refusal or note, the
/// frames in capture order (the chosen row is the reference, §5.5), the
/// Auto-align and De-ghost boxes (§5.6), the result's format, name and
/// folder, then Cancel and Merge. The Form scrolls between the header and the
/// buttons when its content is taller than the sheet (§5.7). The merge runs
/// after the sheet closes, in Activity.
struct MergeSheet: View {
    let model: LibraryModel

    private var merge: MergeModel { model.merge }

    var body: some View {
        VStack(spacing: 0) {
            MergeHeader(model: model)
                .padding(.horizontal, 20)
                .padding(.vertical, MergeSheetMetrics.barPadding)
            Divider()
            MergeForm(model: model)
            Divider()
            buttons
                .padding(.horizontal, 20)
                .padding(.vertical, MergeSheetMetrics.barPadding)
        }
        .frame(width: MergeSheetMetrics.width)
        .frame(minHeight: MergeSheetMetrics.minHeight, idealHeight: MergeSheetMetrics.idealHeight)
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

/// The sheet's size (design §5.7, D-H11): never taller than `idealHeight`;
/// more content scrolls in the Form.
enum MergeSheetMetrics {
    static let width: CGFloat = 560
    static let minHeight: CGFloat = 420
    /// The Form's content at three frames measured with `merge sheet` (517 pt),
    /// plus the header, dividers and buttons (118 pt) and 20 pt of slack is
    /// 655: over D-H11's cap of 640 after cuts i and ii, so the cap (cut iii).
    static let idealHeight: CGFloat = 640
    /// Vertical padding of the header and the button bar (D-H11 cut ii: 14 to 12).
    static let barPadding: CGFloat = 12
}

private struct MergeForm: View {
    let model: LibraryModel

    private var merge: MergeModel { model.merge }

    var body: some View {
        @Bindable var merge = merge
        // Each caption shares the Form row of the control it explains (D-H11):
        // a row of its own costs the grouped style's row padding on top of its text.
        Form {
            // No "Photos" header (D-H11 cut i): the title and the table's column
            // headings say it, and the table keeps "Photos" as its accessibility label.
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    FramesTable(merge: merge)
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
                OptionBox(title: MergeText.autoAlign, caption: MergeText.autoAlignCaption, isOn: $merge.options.align)
                OptionBox(title: MergeText.deghost, caption: MergeText.deghostCaption, isOn: $merge.options.deghost)
            }
            Section(MergeText.resultSection) {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(MergeText.formatLabel) {
                        Picker(MergeText.formatLabel, selection: $merge.format) {
                            Text(MergeText.tiff).tag(MergeFormat.tiff)
                            Text(MergeText.dng).tag(MergeFormat.dng)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel(MergeText.formatLabel)
                    }
                    Caption(text: merge.format == .tiff ? MergeText.tiffCaption : MergeText.dngCaption)
                }
                LabeledContent(MergeText.nameLabel) {
                    let name = merge.resultName
                    Text(name?.text ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(merge.resultNameIsTentative ? .secondary : .primary)
                        .help(name?.text ?? "")
                }
                if let selection = merge.selection {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(MergeText.folderLabel) {
                            Text(selection.referenceFrame.folder.path)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .help(selection.referenceFrame.folder.path)
                        }
                        Caption(text: MergeText.originalsCaption
                            + (merge.framesInSeveralFolders ? " " + MergeText.severalFolders : ""))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Auto-align or De-ghost (design §5.6): a system check box with its one-line
/// caption under the label's text; VoiceOver hears the caption as the box's
/// hint, not twice.
private struct OptionBox: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
                .accessibilityHint(caption)
            Caption(text: caption)
                // Indented to the label's text, past the box.
                .padding(.leading, OptionBox.captionIndent)
                .accessibilityHidden(true)
        }
    }

    /// A check box's width and the gap to its label at the regular control size.
    static let captionIndent: CGFloat = 20
}

/// The frames in capture order, the flagged ones marked by a symbol and their
/// accessibility value, never by color alone (design §5.2, §11). A
/// single-selection table whose chosen row is the reference (§5.5): always
/// exactly one row. A deselection (⌘-click on the chosen row, a click below
/// the rows) is put back at once, since the model ignores it.
private struct FramesTable: View {
    let merge: MergeModel
    @State private var row: Int64?

    var body: some View {
        let frames = merge.selection?.frames ?? []
        let reference = merge.referenceID
        let flagged = merge.flagged
        Table(frames, selection: $row) {
            TableColumn(MergeText.photoColumn) { frame in
                HStack(spacing: 4) {
                    if flagged.contains(frame.versionID) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(frame.displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(frame.displayName)
                    if frame.versionID == reference {
                        // The mark never truncates: the name gives way first.
                        Text(MergeText.referenceRole)
                            .foregroundStyle(.secondary)
                            .fixedSize()
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
        .accessibilityLabel(MergeText.photosSection)
        .accessibilityHint(MergeText.tableHint)
        .onChange(of: row) { _, chosen in
            merge.chooseReference(chosen)
            // Nil, or a row the model didn't take: the reference's row again.
            if chosen != merge.referenceID { row = merge.referenceID }
        }
        .onChange(of: reference, initial: true) { _, now in
            if row != now { row = now }
        }
    }
}
