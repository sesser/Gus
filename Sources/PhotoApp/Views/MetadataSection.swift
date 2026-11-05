import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// The Info tab's Metadata heading: title, description, accessibility texts and
/// rights, then a Contact heading with the creator's details. Edits reach every
/// photo `versionIDs` names (and pair partners); a field the photos disagree on
/// shows "Multiple values" and changes only when something is typed into it.
struct MetadataSection: View {
    let model: LibraryModel
    let summary: DescriptiveSummary
    /// The photos `summary` describes.
    let versionIDs: [Int64]
    @InspectorExpanded(Self.key, family: .info, default: true) private var isExpanded
    /// Contact is a section of its own, collapsed until opened.
    @InspectorExpanded(Self.contactKey, family: .info, default: false) private var isContactExpanded

    static let key = "info.section.metadata"
    static let contactKey = "info.section.contact"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: String(localized: "Metadata"), isExpanded: $isExpanded, family: .info)
            if isExpanded {
                if versionIDs.isEmpty {
                    Text("Select photos to see and change their metadata.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    if !model.writesSidecars {
                        Text("XMP sidecars are off: these fields are kept in the library and written into exports, but other apps won't see them. Turn on sidecars in Settings to share them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    fields(DescriptiveField.general)
                }
            }
            if !versionIDs.isEmpty {
                InspectorSeparator()
                SectionHeader(title: String(localized: "Contact", comment: "Info tab: the creator's contact details heading"),
                              isExpanded: $isContactExpanded, family: .info)
                if isContactExpanded {
                    fields(DescriptiveField.contact)
                }
            }
        }
    }

    private func fields(_ fields: [DescriptiveField]) -> some View {
        ForEach(fields, id: \.self) { field in
            VStack(alignment: .leading, spacing: 2) {
                Text(DescriptiveFieldText.name(field))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MetadataTextField(
                    text: summary.values[field] ?? "",
                    placeholder: summary.mixed.contains(field) ? String(localized: "Multiple values") : "",
                    isMultiline: field.isMultiline,
                    accessibilityLabel: DescriptiveFieldText.name(field),
                    onCommit: commit(field))
                    .help(DescriptiveFieldText.help(field) ?? "")
            }
        }
    }

    /// Saves typed text when it changes what the photos hold. Bound to the
    /// photos shown when editing begins, so a selection change mid-edit does
    /// not redirect it.
    private func commit(_ field: DescriptiveField) -> (String) -> Void {
        let ids = versionIDs
        let current = summary.values[field]
        let isMixed = summary.mixed.contains(field)
        return { text in
            let value = DescriptiveField.normalized(text)
            if isMixed ? value == nil : value == current { return }
            model.setDescriptiveField(field, to: value, for: ids)
        }
    }
}

enum DescriptiveFieldText {
    /// The shared label set (`FieldLabelText`).
    static func name(_ field: DescriptiveField) -> String {
        FieldLabelText.text(field)
    }

    static func help(_ field: DescriptiveField) -> String? {
        switch field {
        case .altText: String(localized: "A short description read aloud by screen readers, under 250 characters")
        case .extendedDescription: String(localized: "A longer description for screen readers, when the alt text cannot say enough")
        default: nil
        }
    }
}

/// An AppKit text field (SwiftUI ones lose clicks under the toolbar on newer
/// systems) that wraps when `isMultiline`, commits when editing ends (Return,
/// Tab or a click elsewhere) and puts the text back on Esc. Option-Return
/// starts a new line.
struct MetadataTextField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let isMultiline: Bool
    let accessibilityLabel: String
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.focusRingType = .default
        field.font = .preferredFont(forTextStyle: .callout)
        if isMultiline {
            // A rounded bezel always draws one centered line; the square one wraps.
            field.bezelStyle = .squareBezel
            field.usesSingleLineMode = false
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.lineBreakMode = .byWordWrapping
        } else {
            field.bezelStyle = .roundedBezel
            field.cell?.isScrollable = true
            field.lineBreakMode = .byTruncatingTail
        }
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        update(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        update(field)
    }

    private func update(_ field: NSTextField) {
        field.placeholderString = placeholder
        field.setAccessibilityLabel(accessibilityLabel)
        // Leave what is being typed alone.
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTextField, context: Context) -> CGSize? {
        let width = min(proposal.width ?? 200, 10_000)
        guard isMultiline, let font = field.font else { return CGSize(width: width, height: 22) }
        // While editing the field editor holds the text; otherwise `text` may be newer than the field.
        let shown = field.currentEditor() == nil ? text : field.stringValue
        // The square bezel insets its text by about 4 points a side and 3 above and below.
        let bounds = ((shown.isEmpty ? " " : shown) as NSString).boundingRect(
            with: NSSize(width: max(width - 8, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        return CGSize(width: width, height: max(22, ceil(bounds.height) + 6))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MetadataTextField
        /// The commit of the photos shown when editing began.
        private var commit: ((String) -> Void)?

        init(_ parent: MetadataTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            commit = parent.onCommit
        }

        func controlTextDidChange(_ notification: Notification) {
            // A wrapping field grows as lines are added.
            (notification.object as? NSTextField)?.invalidateIntrinsicContentSize()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            (commit ?? parent.onCommit)(field.stringValue)
            commit = nil
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                textView.string = parent.text
                control.window?.makeFirstResponder(nil)
                return true
            }
            if selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), !parent.isMultiline {
                return true
            }
            return false
        }
    }
}
