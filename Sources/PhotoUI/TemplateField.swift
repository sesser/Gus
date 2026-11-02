import AppKit
import PhotoCore
import SwiftUI

/// A naming template (see `ImportTemplate`) edited as a token field: each
/// token is a pill with a readable name, literal text between pills is plain,
/// and an Insert pull-down lists the tokens by name. The stored template,
/// copy and paste keep the `{capture:yyyy}` syntax (decision 19 of
/// docs/UI_REDESIGN.md); `TemplateParts` does the splitting.
public struct TemplateField: View {
    /// A token the Insert menu offers: its readable name and its syntax.
    public struct Token: Sendable {
        public var name: String
        public var text: String

        public init(_ name: String, _ text: String) {
            self.name = name
            self.text = text
        }
    }

    let title: String
    @Binding var text: String
    let tokens: [Token]
    /// Inserted tokens start a new path component.
    let folders: Bool
    let example: String?
    @State private var controller = TemplateFieldController()

    public init(title: String, text: Binding<String>, tokens: [Token], folders: Bool = false, example: String? = nil) {
        self.title = title
        _text = text
        self.tokens = tokens
        self.folders = folders
        self.example = example
    }

    /// Tokens every template can use.
    private static var shotTokens: [Token] {
        [
            Token(String(localized: "Capture Year", comment: "Template token"), "{capture:yyyy}"),
            Token(String(localized: "Capture Date", comment: "Smart album rule field and template token"), "{capture:yyyy-MM-dd}"),
            Token(String(localized: "Capture Month Name", comment: "Template token"), "{capture:MMMM}"),
            Token(String(localized: "Capture Time", comment: "Template token"), "{capture:HHmmss}"),
        ]
    }

    private static var cameraTokens: [Token] {
        [
            Token(String(localized: "Camera Model", comment: "Template token"), "{model}"),
            Token(String(localized: "Camera Make", comment: "Template token"), "{make}"),
            Token(String(localized: "Camera Serial Number", comment: "Smart album rule field and template token"), "{serial}"),
            Token(String(localized: "Lens", comment: "Inspector info row and template token"), "{lens}"),
        ]
    }

    public static var importFolderTokens: [Token] {
        shotTokens + [
            Token(String(localized: "Import Date", comment: "Smart album rule field and template token"), "{import:yyyy-MM-dd}"),
            Token(String(localized: "Job Code", comment: "Template token"), "{job}"),
        ] + cameraTokens
    }

    public static var importFileTokens: [Token] {
        importFolderTokens + [
            Token(String(localized: "File Name", comment: "Smart album rule field and template token"), "{name}"),
            Token(String(localized: "Number in the Original Name", comment: "Template token"), "{number}"),
            Token(String(localized: "Sequence in This Import", comment: "Template token"), "{seq:4}"),
            Token(String(localized: "Counter Across Imports", comment: "Template token"), "{counter:5}"),
        ]
    }

    public static var exportFileTokens: [Token] {
        shotTokens + [
            Token(String(localized: "Export Date", comment: "Template token: today's date when exporting"),
                  "{export:yyyy-MM-dd}"),
        ] + cameraTokens + [
            Token(String(localized: "File Name", comment: "Smart album rule field and template token"), "{name}"),
            Token(String(localized: "Number in the Original Name", comment: "Template token"), "{number}"),
            Token(String(localized: "Sequence in This Export",
                         comment: "Template token: the photo's position in the export"), "{seq:4}"),
        ]
    }

    public var body: some View {
        LabeledContent(title) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TemplateTokenFieldView(title: title, text: $text, tokens: tokens, controller: controller)
                        .frame(maxWidth: .infinity)
                    Menu("Insert") {
                        ForEach(tokens, id: \.text) { token in
                            Button(token.name) {
                                controller.insert(token.text, separator: folders ? "/" : nil)
                            }
                        }
                    }
                    .fixedSize()
                    .help(String(localized: "Insert a token", comment: "Template field help"))
                }
                if let example {
                    Text(example)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// Lets the Insert menu reach the token field it sits next to.
@MainActor
final class TemplateFieldController {
    weak var field: TemplateTokenField?

    func insert(_ token: String, separator: String?) {
        field?.insert(token, separator: separator)
    }
}

/// A token in the field. Literal text is kept as plain `String`s, which is
/// what `NSTokenField` hands back for text typed between tokens.
final class TemplateToken: NSObject {
    let syntax: String

    init(_ syntax: String) {
        self.syntax = syntax
    }
}

/// The `NSTokenField` behind `TemplateField`.
final class TemplateTokenField: NSTokenField {
    /// The template the field shows, in `{…}` syntax.
    var parts: [TemplatePart] {
        get {
            ((objectValue as? [Any]) ?? []).compactMap { object in
                if let token = object as? TemplateToken { return .token(token.syntax) }
                if let text = object as? String { return .text(text) }
                return nil
            }
        }
        set {
            objectValue = newValue.map { part -> Any in
                switch part {
                case .token(let syntax): TemplateToken(syntax)
                case .text(let text): text
                }
            }
        }
    }

    var template: String { TemplateParts.join(parts) }
    /// Called after an edit changes the template.
    var onChange: ((String) -> Void)?

    /// Inserts at the caret while editing, otherwise at the end.
    func insert(_ token: String, separator: String?) {
        var location = Int.max
        if let editor = currentEditor() {
            if editor.selectedRange.length > 0 { editor.delete(nil) }
            location = editor.selectedRange.location
        }
        let result = TemplateParts.inserting(token, into: parts, at: location, separator: separator)
        parts = result.parts
        currentEditor()?.selectedRange = NSRange(location: result.caret, length: 0)
        onChange?(template)
    }

    /// Opening a window must not select the whole template (in the accent
    /// color it read as an error, F23); Tab still selects all, as in any field.
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, NSApp.currentEvent?.type != .keyDown, let editor = currentEditor() {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
        return became
    }
}

private struct TemplateTokenFieldView: NSViewRepresentable {
    let title: String
    @Binding var text: String
    let tokens: [TemplateField.Token]
    let controller: TemplateFieldController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TemplateTokenField {
        let field = TemplateTokenField()
        // Only the end of editing makes tokens of typed text: commas and
        // spaces are ordinary characters in a file name.
        field.tokenizingCharacterSet = CharacterSet()
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.usesSingleLineMode = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controller.field = field
        return field
    }

    func updateNSView(_ field: TemplateTokenField, context: Context) {
        context.coordinator.names = Dictionary(tokens.map { ($0.text, $0.name) }, uniquingKeysWith: { first, _ in first })
        field.onChange = { [binding = $text] template in
            if binding.wrappedValue != template { binding.wrappedValue = template }
        }
        field.setAccessibilityLabel(title)
        controller.field = field
        if field.template != text {
            field.parts = TemplateParts.parse(text)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: TemplateTokenField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: field.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject, NSTokenFieldDelegate {
        /// Readable names by syntax, from the field's Insert menu.
        var names: [String: String] = [:]

        func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
            if let token = representedObject as? TemplateToken {
                // A token the menu does not offer (`{ext}`, another date
                // pattern) shows as written.
                return names[token.syntax] ?? token.syntax
            }
            return representedObject as? String
        }

        func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
            (representedObject as? TemplateToken)?.syntax ?? representedObject as? String
        }

        func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
            editingString
        }

        func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle {
            representedObject is TemplateToken ? .rounded : .none
        }

        func tokenField(_ tokenField: NSTokenField, writeRepresentedObjects objects: [Any], to pboard: NSPasteboard) -> Bool {
            let text = objects.map { ($0 as? TemplateToken)?.syntax ?? ($0 as? String) ?? "" }.joined()
            pboard.clearContents()
            return pboard.setString(text, forType: .string)
        }

        func tokenField(_ tokenField: NSTokenField, readFrom pboard: NSPasteboard) -> [Any]? {
            guard let text = pboard.string(forType: .string) else { return nil }
            return TemplateParts.parse(text).map { part -> Any in
                switch part {
                case .token(let syntax): TemplateToken(syntax)
                case .text(let text): text
                }
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? TemplateTokenField else { return }
            field.onChange?(field.template)
        }

        /// Text typed as `{job}` becomes a pill, and neighboring text merges.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? TemplateTokenField else { return }
            let parts = field.parts
            let normalized = TemplateParts.normalized(parts)
            if normalized != parts { field.parts = normalized }
            field.onChange?(field.template)
        }
    }
}
