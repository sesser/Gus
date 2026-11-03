import AppKit
import PhotoCore
import SwiftUI

/// A naming template (see `ImportTemplate`) edited as a token field: each
/// token is a pill with a readable name, literal text between pills is plain,
/// and an Insert pull-down lists the tokens by group. The stored template,
/// copy and paste keep the `{capture:yyyy}` syntax (decision 19 of
/// docs/UI_REDESIGN.md); `TemplateParts` does the splitting and
/// `TemplateToken` the reading. The field wraps up to three lines, then
/// scrolls.
public struct TemplateField: View {
    /// Which tokens the Insert menu offers.
    public enum Tokens: Sendable {
        /// Import subfolders: dates, camera, job code.
        case importFolders
        /// Import file names and project names.
        case importFiles
        /// Export file names.
        case exportFiles
    }

    let title: String
    @Binding var text: String
    let tokens: Tokens
    /// Inserted tokens start a new path component.
    let folders: Bool
    /// A photo the menu takes example values from.
    let sample: TemplateContext?
    let example: String?
    @State private var controller = TemplateFieldController()

    public init(title: String, text: Binding<String>, tokens: Tokens, folders: Bool = false,
                sample: TemplateContext? = nil, example: String? = nil) {
        self.title = title
        _text = text
        self.tokens = tokens
        self.folders = folders
        self.sample = sample
        self.example = example
    }

    /// Three lines (form conventions, "Templates"): the label with Insert at
    /// the trailing end, the field at the column's full width, the example.
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                Spacer(minLength: 8)
                Menu(String(localized: "Insert", comment: "Template field: pull-down menu of tokens")) {
                    ForEach(TemplateTokenNames.groups(tokens), id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.tokens, id: \.self) { syntax in
                                Button(menuTitle(syntax)) {
                                    controller.insert(syntax, separator: folders ? "/" : nil)
                                }
                                .help(TemplateTokenNames.help(syntax) ?? "")
                            }
                        }
                    }
                }
                .fixedSize()
                .help(String(localized: "Insert a token", comment: "Template field help"))
            }
            TemplateTokenFieldView(title: title, text: $text, sample: sample, controller: controller)
                .frame(maxWidth: .infinity)
            if let example {
                TemplateExample(text: example)
            }
        }
    }

    /// "Capture Year (2026)" when there is a photo with a value for it.
    private func menuTitle(_ syntax: String) -> String {
        let name = TemplateTokenNames.name(for: syntax) ?? syntax
        guard let sample else { return name }
        let value = TemplateToken.value(of: syntax, in: sample)
        return value.isEmpty ? name : String(localized: "\(name) (\(value))",
                                             comment: "Template field Insert menu: a token and its value for the first photo")
    }
}

/// "Example: 2026/2026-10-30/DSC00328.ARW" in 11 pt secondary text, under
/// the field it explains.
public struct TemplateExample: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text("Example: \(text)", comment: "Under a naming template: what it makes of the first photo")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// Readable names of tokens (the pill table of decision 19).
enum TemplateTokenNames {
    struct Group {
        let title: String
        let tokens: [String]
    }

    static func groups(_ tokens: TemplateField.Tokens) -> [Group] {
        let date = String(localized: "Date", comment: "Template field Insert menu section")
        let camera = String(localized: "Camera", comment: "Template field Insert menu section")
        let file = String(localized: "File", comment: "Template field Insert menu section")
        let numbering = String(localized: "Numbering", comment: "Template field Insert menu section")
        let job = String(localized: "Job", comment: "Template field Insert menu section")
        let captureDates = ["{capture:yyyy}", "{capture:yyyy-MM-dd}", "{capture:MMMM}", "{capture:HHmmss}"]
        let cameraTokens = ["{make}", "{model}", "{serial}", "{lens}"]
        switch tokens {
        case .importFolders:
            return [Group(title: date, tokens: captureDates + ["{import:yyyy-MM-dd}"]),
                    Group(title: camera, tokens: cameraTokens),
                    Group(title: job, tokens: ["{job}"])]
        case .importFiles:
            return [Group(title: date, tokens: captureDates + ["{import:yyyy-MM-dd}"]),
                    Group(title: camera, tokens: cameraTokens),
                    Group(title: file, tokens: ["{name}", "{number}"]),
                    Group(title: numbering, tokens: ["{seq:4}", "{counter:5}"]),
                    Group(title: job, tokens: ["{job}"])]
        case .exportFiles:
            return [Group(title: date, tokens: captureDates + ["{export:yyyy-MM-dd}"]),
                    Group(title: camera, tokens: cameraTokens),
                    Group(title: file, tokens: ["{name}", "{number}"]),
                    Group(title: numbering, tokens: ["{seq:4}"])]
        }
    }

    /// The pill's name; nil for a token the grammar does not know (shown as text).
    static func name(for syntax: String) -> String? {
        guard let token = TemplateToken(syntax: syntax) else { return nil }
        switch token {
        case .date(let source, let pattern):
            switch (source, pattern) {
            case (.capture, "yyyy"): return String(localized: "Capture Year", comment: "Template token")
            case (.capture, "yyyy-MM-dd"):
                return String(localized: "Capture Date", comment: "Smart album rule field and template token")
            case (.capture, "MMMM"): return String(localized: "Capture Month", comment: "Template token")
            case (.capture, "HHmmss"): return String(localized: "Capture Time", comment: "Template token")
            case (.import, "yyyy-MM-dd"):
                return String(localized: "Import Date", comment: "Smart album rule field and template token")
            case (.export, "yyyy-MM-dd"):
                return String(localized: "Export Date", comment: "Template token: today's date when exporting")
            case (.capture, _):
                return String(localized: "Capture Date (\(pattern))",
                              comment: "Template token: the capture date in a pattern of the user's, e.g. yyyyMM")
            case (.import, _):
                return String(localized: "Import Date (\(pattern))",
                              comment: "Template token: the import date in a pattern of the user's, e.g. yyyyMM")
            case (.export, _):
                return String(localized: "Export Date (\(pattern))",
                              comment: "Template token: the export date in a pattern of the user's, e.g. yyyyMM")
            }
        case .make: return String(localized: "Camera Make", comment: "Template token")
        case .model: return String(localized: "Camera Model", comment: "Template token")
        case .serial: return String(localized: "Serial Number", comment: "Template token")
        case .lens: return String(localized: "Lens", comment: "Inspector info row and template token")
        case .name: return String(localized: "Original Name", comment: "Export sheet: keep each file's name; template token")
        case .number: return String(localized: "Original Number", comment: "Template token: the digits in the original name")
        case .ext(nil): return String(localized: "Extension", comment: "Template token")
        case .ext(.lower): return String(localized: "Lowercase Extension", comment: "Template token")
        case .ext(.upper): return String(localized: "Uppercase Extension", comment: "Template token")
        case .sequence: return String(localized: "Sequence Number", comment: "Template token")
        case .counter: return String(localized: "Import Counter", comment: "Template token")
        case .job: return String(localized: "Job Code", comment: "Template token")
        }
    }

    /// Help for the tokens whose name needs it.
    static func help(_ syntax: String) -> String? {
        TemplateToken(syntax: syntax) == .counter
            ? String(localized: "Keeps counting across imports", comment: "Template field Insert menu: Import Counter help")
            : nil
    }

    /// A date in a pattern the menu does not offer.
    static func isCustomDate(_ syntax: String) -> Bool {
        guard case .date(let source, let pattern) = TemplateToken(syntax: syntax) else { return false }
        switch (source, pattern) {
        case (.capture, "yyyy"), (.capture, "yyyy-MM-dd"), (.capture, "MMMM"), (.capture, "HHmmss"),
             (.import, "yyyy-MM-dd"), (.export, "yyyy-MM-dd"):
            return false
        default:
            return true
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

/// A token in the field. Literal text, and tokens the grammar does not know,
/// are plain `String`s, which is what `NSTokenField` hands back for text typed
/// between tokens.
final class TemplateTokenObject: NSObject {
    let syntax: String

    init(_ syntax: String) {
        self.syntax = syntax
    }
}

/// The `NSTokenField` behind `TemplateField`.
final class TemplateTokenField: NSTokenField {
    static let maximumLines = 3

    /// The template the field shows, in `{…}` syntax.
    var parts: [TemplatePart] {
        get {
            ((objectValue as? [Any]) ?? []).compactMap { object in
                if let token = object as? TemplateTokenObject { return .token(token.syntax) }
                if let text = object as? String { return .text(text) }
                return nil
            }
        }
        set {
            objectValue = Self.objects(TemplateParts.join(newValue))
            invalidateIntrinsicContentSize()
            updateToolTip()
        }
    }

    /// Tokens the grammar knows are pills; other braces are text.
    static func isToken(_ syntax: String) -> Bool { TemplateToken(syntax: syntax) != nil }

    static func objects(_ template: String) -> [Any] {
        TemplateParts.parse(template, isToken: isToken).map { part -> Any in
            switch part {
            case .token(let syntax): TemplateTokenObject(syntax)
            case .text(let text): text
            }
        }
    }

    var template: String { TemplateParts.join(parts) }

    /// A photo for the tooltip's values.
    var sample: TemplateContext? {
        didSet { updateToolTip() }
    }

    /// Dates in patterns of the user's show their value as the field's
    /// tooltip ("Capture Date (yyyyMM): 202610"): NSTokenField has no
    /// tooltip per token.
    func updateToolTip() {
        guard let sample else {
            toolTip = nil
            return
        }
        let lines = parts.compactMap { part -> String? in
            guard case .token(let syntax) = part, TemplateTokenNames.isCustomDate(syntax),
                  let name = TemplateTokenNames.name(for: syntax) else { return nil }
            return "\(name): \(TemplateToken.value(of: syntax, in: sample))"
        }
        toolTip = lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    /// Called after an edit changes the template.
    var onChange: ((String) -> Void)?
    /// The last selection while editing, kept when editing ends, so Insert
    /// goes there even after focus moved to the menu. Nil until edited.
    private(set) var lastSelection: NSRange?
    private var selectionObserver: (any NSObjectProtocol)?

    /// Replaces the last selection, or goes at the last caret position (the
    /// end if the field was never edited), then returns focus to the field
    /// with the caret after the token.
    func insert(_ token: String, separator: String?) {
        let wasEditing = currentEditor() != nil
        let selection = wasEditing ? currentEditor()?.selectedRange : lastSelection
        if !wasEditing { window?.makeFirstResponder(self) }
        var location = Int.max
        if let editor = currentEditor(), let selection {
            let length = (editor.string as NSString).length
            let start = min(selection.location, length)
            editor.selectedRange = NSRange(location: start, length: min(selection.length, length - start))
            if editor.selectedRange.length > 0 { editor.delete(nil) }
            location = editor.selectedRange.location
        }
        let result = TemplateParts.inserting(token, into: parts, at: location, separator: separator,
                                             isToken: Self.isToken)
        parts = result.parts
        currentEditor()?.selectedRange = NSRange(location: result.caret, length: 0)
        lastSelection = NSRange(location: result.caret, length: 0)
        onChange?(template)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The field editor's `textViewDidChangeSelection`, observed rather
        // than implemented: NSTokenField handles that delegate call itself.
        // The editor is the window's shared one, so only ours counts.
        selectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let editor = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let current = self.currentEditor(), ObjectIdentifier(current) == editor else { return }
                self.lastSelection = current.selectedRange
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    isolated deinit {
        if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
    }

    /// Opening a window must not select the whole template (in the accent
    /// color it read as an error, F23); Tab still selects all, as in any field.
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, NSApp.currentEvent?.type != .keyDown, let editor = currentEditor() {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
        if became, let editor = currentEditor() { lastSelection = editor.selectedRange }
        return became
    }

    /// Up to three lines, then the field scrolls.
    func fittingHeight(width: CGFloat) -> CGFloat {
        guard let cell = cell as? NSTokenFieldCell, let font else { return 22 }
        let line = NSLayoutManager().defaultLineHeight(for: font)
        let empty = cell.copy() as! NSTokenFieldCell
        empty.objectValue = []
        let bounds = NSRect(x: 0, y: 0, width: width, height: 10_000)
        let oneLine = empty.cellSize(forBounds: bounds).height
        let content: CGFloat
        if let editor = currentEditor() as? NSTextView, let layout = editor.layoutManager, let container = editor.textContainer {
            // The glyphs' bounds: `usedRect` adds the caret's extra line.
            let glyphs = layout.glyphRange(for: container)
            content = layout.boundingRect(forGlyphRange: glyphs, in: container).height + oneLine - line
        } else {
            content = cell.cellSize(forBounds: bounds).height
        }
        return min(max(content, oneLine), oneLine + line * CGFloat(Self.maximumLines - 1))
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fittingHeight(width: bounds.width > 0 ? bounds.width : 240))
    }
}

private struct TemplateTokenFieldView: NSViewRepresentable {
    let title: String
    @Binding var text: String
    let sample: TemplateContext?
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
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.usesSingleLineMode = false
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controller.field = field
        return field
    }

    func updateNSView(_ field: TemplateTokenField, context: Context) {
        field.onChange = { [binding = $text] template in
            if binding.wrappedValue != template { binding.wrappedValue = template }
        }
        field.setAccessibilityLabel(title)
        controller.field = field
        if field.template != text {
            field.parts = TemplateParts.parse(text)
        }
        field.sample = sample
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: TemplateTokenField, context: Context) -> CGSize? {
        let width = proposal.width ?? 240
        return CGSize(width: width, height: field.fittingHeight(width: width))
    }

    @MainActor
    final class Coordinator: NSObject, NSTokenFieldDelegate {
        func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
            if let token = representedObject as? TemplateTokenObject {
                return TemplateTokenNames.name(for: token.syntax) ?? token.syntax
            }
            return representedObject as? String
        }

        func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
            (representedObject as? TemplateTokenObject)?.syntax ?? representedObject as? String
        }

        func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
            editingString
        }

        func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle {
            representedObject is TemplateTokenObject ? .rounded : .none
        }

        func tokenField(_ tokenField: NSTokenField, writeRepresentedObjects objects: [Any], to pboard: NSPasteboard) -> Bool {
            let text = objects.map { ($0 as? TemplateTokenObject)?.syntax ?? ($0 as? String) ?? "" }.joined()
            pboard.clearContents()
            return pboard.setString(text, forType: .string)
        }

        func tokenField(_ tokenField: NSTokenField, readFrom pboard: NSPasteboard) -> [Any]? {
            guard let text = pboard.string(forType: .string) else { return nil }
            return TemplateTokenField.objects(text)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? TemplateTokenField else { return }
            field.invalidateIntrinsicContentSize()
            field.updateToolTip()
            field.onChange?(field.template)
        }

        /// Text typed as `{job}` becomes a pill, and neighboring text merges.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? TemplateTokenField else { return }
            let parts = field.parts
            let normalized = TemplateParts.normalized(parts, isToken: TemplateTokenField.isToken)
            if normalized != parts { field.parts = normalized }
            field.invalidateIntrinsicContentSize()
            field.onChange?(field.template)
        }
    }
}
