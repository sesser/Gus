import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// Adjust ▸ Copy Adjustments… (copy-adjustments-selective design §3): a
/// sheet on the library window built like Export and Merge to HDR. A fixed
/// header (the photo, Check All, Uncheck All), the rows in the Adjust tab's
/// order with a check box each, scrolling when the window is short, then the
/// masks note and Cancel and Copy.
///
/// Each box is a system check box (`AppKitCheckbox`): it shows a heading's
/// mixed state, is a Tab stop with Full Keyboard Access, and its click goes
/// through `CopySheetState.click`, the one rule for headings (§3.4). A click
/// anywhere else on the row does the same.
struct CopyAdjustmentsSheet: View {
    let model: LibraryModel

    var body: some View {
        Group {
            if let sheet = model.copySheet {
                VStack(spacing: 0) {
                    CopySheetHeader(sheet: sheet)
                        .padding(.horizontal, 20)
                        .padding(.vertical, CopySheetMetrics.barPadding)
                    Divider()
                    ScrollView {
                        CopySheetRows(sheet: sheet)
                            .padding(.horizontal, 20)
                            .padding(.vertical, CopySheetMetrics.listInset)
                    }
                    Divider()
                    footer(sheet)
                        .padding(.horizontal, 20)
                        .padding(.vertical, CopySheetMetrics.barPadding)
                }
            } else {
                // The sheet's state goes as it closes.
                Color.clear
            }
        }
        .frame(width: CopySheetMetrics.width)
        .frame(minHeight: CopySheetMetrics.minHeight,
               idealHeight: CopySheetMetrics.idealHeight(withNote: model.copySheet?.state.sourceHasNoChanges == true,
                                                         window: model.copySheet?.windowHeight))
        .presentationSizing(.fitted)
    }

    private func footer(_ sheet: CopySheet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CopyAdjustmentsText.masksNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if !sheet.state.canCopy {
                    Text(CopyAdjustmentsText.checkSomething)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelCopySheet() }
                    .keyboardShortcut(.cancelAction)
                Button(CopyAdjustmentsText.copyButton) { model.confirmCopySheet() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!sheet.state.canCopy)
                    .accessibilityHint(sheet.state.canCopy ? "" : CopyAdjustmentsText.checkSomething)
            }
        }
    }
}

/// The photo's thumbnail, the title, "From …", Check All and Uncheck All.
private struct CopySheetHeader: View {
    let sheet: CopySheet

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let image = sheet.previewImage {
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
                Text(CopyAdjustmentsText.title)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(CopyAdjustmentsText.source(PhotoName.display(sheet.item)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button(CopyAdjustmentsText.checkAll) { sheet.state.checkAll() }
                    Button(CopyAdjustmentsText.uncheckAll) { sheet.state.uncheckAll() }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                if sheet.state.sourceHasNoChanges {
                    Label {
                        Text(CopyAdjustmentsText.noAdjustments).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The rows: headings and single rows at the leading edge, a heading's
/// groups indented under it (design §3.2).
private struct CopySheetRows: View {
    let sheet: CopySheet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(CopyRow.all.enumerated()), id: \.element) { index, row in
                Group {
                    if row.isHeading {
                        VStack(alignment: .leading, spacing: 0) {
                            CopySheetRow(sheet: sheet, kind: .heading(row))
                            ForEach(row.items, id: \.self) { item in
                                CopySheetRow(sheet: sheet, kind: .child(item))
                                    .padding(.leading, CopySheetMetrics.indent)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(CopyAdjustmentsText.title(row))
                    } else {
                        CopySheetRow(sheet: sheet, kind: .single(row))
                    }
                }
                .padding(.top, index == 0 ? 0 : CopySheetMetrics.blockGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(CopyAdjustmentsText.listName)
    }
}

/// One row: the box, the name, the trailing text, and for Crop and Spots a
/// caption under the name. The whole row toggles the box.
private struct CopySheetRow: View {
    enum Kind {
        /// A heading over several groups: bold, no trailing text.
        case heading(CopyRow)
        /// A row with one item (Crop & Straighten, Spots, Tone Curve…): bold, with its text.
        case single(CopyRow)
        /// A heading's group: regular, indented, with its text.
        case child(CopyItem)
    }

    let sheet: CopySheet
    let kind: Kind

    private var row: CopyRow? {
        switch kind {
        case .heading(let row), .single(let row): row
        case .child: nil
        }
    }

    private var item: CopyItem? {
        switch kind {
        case .heading: nil
        case .single(let row): row.items.first
        case .child(let item): item
        }
    }

    private var title: String {
        switch kind {
        case .heading(let row), .single(let row): CopyAdjustmentsText.title(row)
        case .child(let item): CopyAdjustmentsText.title(item)
        }
    }

    private var note: String? {
        guard let item else { return nil }
        return sheet.state.note(for: item).map(CopyAdjustmentsText.note)
    }

    private var caption: String? {
        switch item {
        case .crop?: CopyAdjustmentsText.cropCaption
        case .group(.spots)?: CopyAdjustmentsText.spotsCaption
        default: nil
        }
    }

    private var state: AppKitCheckbox.State {
        let check: CopyCheck = if let row { sheet.state.state(of: row) } else if let item {
            sheet.state.isChecked(item) ? .on : .off
        } else { .off }
        return switch check {
        case .on: .on
        case .off: .off
        case .mixed: .mixed
        }
    }

    private func click() {
        if let row {
            sheet.state.click(row)
        } else if let item {
            sheet.state.toggle(item)
        }
    }

    var body: some View {
        let isBold = if case .child = kind { false } else { true }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CopySheetMetrics.boxGap) {
                // VoiceOver reads the name and the text once, as the box's label.
                AppKitCheckbox(state: state, label: [title, note].compactMap { $0 }.joined(separator: ", "),
                               help: caption ?? title, controlSize: .regular, action: click)
                    .fixedSize()
                Text(title)
                    .font(.system(size: 13, weight: isBold ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(title)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
            }
            .frame(height: CopySheetMetrics.rowPitch)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, CopySheetMetrics.captionIndent)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: click)
    }
}

/// The sheet's size (design §3.8).
enum CopySheetMetrics {
    static let width: CGFloat = 420
    static let minHeight: CGFloat = 380
    /// The content's height as measured with `print copysheet` (design §3.8:
    /// the measure, at most 680): the list's 520 pt and 140 pt of header,
    /// dividers, footer and buttons; 20 pt more with the note for a photo
    /// with no adjustments. The default case does not scroll.
    /// A window shorter than that clamps it (never under `minHeight`): only the list scrolls.
    static func idealHeight(withNote: Bool, window: CGFloat?) -> CGFloat {
        let content: CGFloat = withNote ? 680 : 660
        guard let window, window > 0 else { return content }
        return max(minHeight, min(content, window))
    }
    static let barPadding: CGFloat = 12
    static let listInset: CGFloat = 8
    static let rowPitch: CGFloat = 20
    /// Above every heading and single row but the first.
    static let blockGap: CGFloat = 4
    /// Between the box and its name.
    static let boxGap: CGFloat = 4
    /// A heading's groups: one check box (16 pt at the regular size) plus 6 pt (design §3.2).
    static let indent: CGFloat = 22
    /// A caption under a row's name: past its box and the gap.
    static let captionIndent: CGFloat = 20
}
