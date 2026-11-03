import AppKit
import SwiftUI

/// An AppKit search field: its own clear button, Escape clears, and Return or
/// Escape hand the keyboard back to the grid or loupe for culling.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        field.sendsWholeSearchString = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingHead
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField
        weak var field: NSSearchField?

        init(_ parent: SearchField) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(takeFocus(_:)),
                                                   name: .searchShouldTakeFocus, object: nil)
        }

        /// Edit ▸ Find ▸ Find… (⌘F).
        @objc private func takeFocus(_ notification: Notification) {
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onFinish()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                control.stringValue = ""
                parent.text = ""
                parent.onFinish()
                return true
            default:
                return false
            }
        }
    }
}
