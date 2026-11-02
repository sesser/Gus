import AppKit
import PhotoCore

/// The debug script's `tokens` commands (`import tokens …`, `export tokens …`):
/// drive and print the template fields of a window.
///
///     tokens                         each field: label, pills and text as shown, template
///     tokens type <n> <text>         types at the end of field n, then ends editing
///     tokens select <n> <loc> [<len>]  selects in field n, then moves focus away (as a click on Insert can)
///     tokens insert <n> <syntax>     what the Insert menu does (at the last selection, or the end if never edited)
///     tokens copy <n>                what Copy puts on the pasteboard for the whole field
///     tokens paste <n> <text>        what Paste of <text> inserts
///
/// Copy and paste use a private pasteboard, never the general one.
@MainActor
public enum TemplateFieldProbe {
    public static func run(_ words: [String], in window: NSWindow?) {
        guard let root = window?.contentView else {
            print("debug-script: tokens: no window")
            return
        }
        let fields = templateFields(in: root)
        let index = words.count > 1 ? Int(words[1]) : nil
        let argument = words.dropFirst(2).joined(separator: " ")
        func field() -> TemplateTokenField? {
            guard let index, fields.indices.contains(index) else {
                print("debug-script: tokens: no field \(words.count > 1 ? words[1] : "-") of \(fields.count)")
                return nil
            }
            return fields[index]
        }
        switch words.first {
        case nil:
            for (index, field) in fields.enumerated() { print("debug-script: tokens \(index) \(describe(field))") }
        case "type":
            guard let field = field(), let window else { return }
            window.makeFirstResponder(field)
            guard let editor = field.currentEditor() as? NSTextView else { return }
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            editor.insertText(argument, replacementRange: editor.selectedRange())
            window.makeFirstResponder(nil)
            print("debug-script: tokens \(index ?? 0) \(describe(field))")
        case "select":
            guard let field = field(), let window else { return }
            let numbers = words.dropFirst(2).compactMap { Int($0) }
            window.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(location: numbers.first ?? 0, length: numbers.dropFirst().first ?? 0)
            window.makeFirstResponder(nil)
            print("debug-script: tokens \(index ?? 0) selection \(field.lastSelection.map { "\($0.location),\($0.length)" } ?? "-")")
        case "insert":
            guard let field = field() else { return }
            field.insert(argument, separator: nil)
            print("debug-script: tokens \(index ?? 0) \(describe(field))")
        case "copy":
            guard let field = field() else { return }
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("debug-script.tokens"))
            _ = field.delegate?.tokenField?(field, writeRepresentedObjects: (field.objectValue as? [Any]) ?? [],
                                            to: pasteboard)
            print("debug-script: tokens copy \(pasteboard.string(forType: .string) ?? "-")")
            pasteboard.releaseGlobally()
        case "paste":
            guard let field = field() else { return }
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("debug-script.tokens"))
            pasteboard.clearContents()
            pasteboard.setString(argument, forType: .string)
            let objects = field.delegate?.tokenField?(field, readFrom: pasteboard) ?? []
            let shown = objects.map { object in
                object is TemplateToken
                    ? "[\(field.delegate?.tokenField?(field, displayStringForRepresentedObject: object) ?? "?")]"
                    : "\(object)"
            }
            print("debug-script: tokens paste \(shown.joined())")
            pasteboard.releaseGlobally()
        default:
            print("debug-script: unknown tokens command")
        }
    }

    static func templateFields(in view: NSView) -> [TemplateTokenField] {
        if let field = view as? TemplateTokenField { return [field] }
        return view.subviews.flatMap(templateFields(in:))
    }

    /// `'Subfolders' [Capture Year]/[Capture Date] = {capture:yyyy}/{capture:yyyy-MM-dd}`
    private static func describe(_ field: TemplateTokenField) -> String {
        let shown = ((field.objectValue as? [Any]) ?? []).map { object -> String in
            let text = field.delegate?.tokenField?(field, displayStringForRepresentedObject: object) ?? "?"
            let style = field.delegate?.tokenField?(field, styleForRepresentedObject: object)
            return style == NSTokenField.TokenStyle.none ? text : "[\(text)]"
        }
        return "'\(field.accessibilityLabel() ?? "-")' \(shown.joined()) = \(field.template) "
            + "height \(Int(field.frame.height)) editing \(field.currentEditor() != nil)"
            + (field.toolTip.map { " tooltip \($0.replacingOccurrences(of: "\n", with: "; "))" } ?? "")
    }
}
