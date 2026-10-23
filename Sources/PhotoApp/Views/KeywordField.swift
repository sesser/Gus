import AppKit
import PhotoCore
import SwiftUI

/// A comma-separated keyword field that completes the word being typed from the
/// library's keywords. ↓ and ↑ move through the suggestions, Tab or Return takes
/// the highlighted one (Tab the first when none is), Return otherwise commits.
struct KeywordField: View {
    let placeholder: String
    let names: [String]
    var focusesOnAppear = false
    let onCommit: ([String]) -> Void
    var onCancel: (() -> Void)?

    @State private var text = ""
    @State private var highlighted: Int?

    private var suggestions: [String] { KeywordCompletion.suggestions(for: text, from: names) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KeywordTextField(text: $text, placeholder: placeholder, focusesOnAppear: focusesOnAppear, onCommand: handle)
                .frame(height: 22)
                .onChange(of: text) { highlighted = nil }
            let suggestions = self.suggestions
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, name in
                        Text(name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(index == highlighted ? Color.accentColor.opacity(0.35) : .clear,
                                        in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                            .onTapGesture { complete(name) }
                    }
                }
                .padding(4)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func handle(_ command: KeywordTextField.Command) -> Bool {
        let suggestions = self.suggestions
        switch command {
        case .down:
            guard !suggestions.isEmpty else { return false }
            highlighted = min((highlighted ?? -1) + 1, suggestions.count - 1)
        case .up:
            guard !suggestions.isEmpty else { return false }
            highlighted = highlighted.map { max($0 - 1, 0) }
        case .tab:
            guard !suggestions.isEmpty else { return false }
            complete(suggestions[highlighted ?? 0])
        case .commit:
            if let highlighted, suggestions.indices.contains(highlighted) {
                complete(suggestions[highlighted])
            } else {
                let keywords = KeywordCompletion.keywords(in: text)
                text = ""
                onCommit(keywords)
            }
        case .cancel:
            if highlighted != nil {
                highlighted = nil
            } else if let onCancel {
                onCancel()
            } else {
                text = ""
            }
        }
        return true
    }

    private func complete(_ name: String) {
        text = KeywordCompletion.completing(text, with: name)
        highlighted = nil
    }
}

/// The AppKit text field underneath `KeywordField`, so arrow keys, Tab, Return
/// and Escape can be routed to the suggestions.
struct KeywordTextField: NSViewRepresentable {
    enum Command {
        case up, down, tab, commit, cancel
    }

    @Binding var text: String
    let placeholder: String
    let focusesOnAppear: Bool
    let onCommand: (Command) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        if focusesOnAppear {
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.stringValue != text {
            field.stringValue = text
            // A completion replaced the text: keep typing at the end.
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: KeywordTextField

        init(_ parent: KeywordTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let command: Command? = switch selector {
            case #selector(NSResponder.moveDown(_:)): .down
            case #selector(NSResponder.moveUp(_:)): .up
            case #selector(NSResponder.insertTab(_:)): .tab
            case #selector(NSResponder.insertNewline(_:)): .commit
            case #selector(NSResponder.cancelOperation(_:)): .cancel
            default: nil
            }
            guard let command else { return false }
            return parent.onCommand(command)
        }
    }
}

/// The ⌘K panel over the grid or loupe.
struct KeywordEntryPanel: View {
    let model: LibraryModel
    let request: KeywordEntryRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add keywords to \(request.versionIDs.count) photos")
                .font(.headline)
            KeywordField(placeholder: String(localized: "Keywords, separated by commas"),
                         names: model.keywordNames, focusesOnAppear: true,
                         onCommit: { model.endKeywordEntry(adding: $0) },
                         onCancel: { model.endKeywordEntry(adding: []) })
            Text("Return adds them. Tab completes, Esc closes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 12)
        .padding(.top, 24)
    }
}
