import AppKit

/// Reads a window's accessibility elements from inside the app, for debug
/// scripts, without VoiceOver or an accessibility permission.
///
/// SwiftUI builds its part of the tree only while an assistive app is
/// attached, so from inside the app the walk stops at its hosting views. The
/// AppKit views below them (the grid's cells, the loupe) are found by walking
/// the view hierarchy instead: their own answers, not proof that VoiceOver
/// reaches them.
@MainActor
public enum AccessibilityProbe {
    /// Elements under `window` with `role` ("AXImage", "AXCheckBox"; nil for
    /// all): the accessibility tree, then AppKit views that are elements.
    public static func elements(in window: NSWindow, role: String?) -> [any NSAccessibilityProtocol] {
        var found: [any NSAccessibilityProtocol] = []
        var seen = Set<ObjectIdentifier>()
        func add(_ element: any NSAccessibilityProtocol) {
            // No `role == nil || …`: Xcode 26's compiler sees the autoclosure
            // as sending `element` across isolation in release builds.
            if let role, element.accessibilityRole()?.rawValue != role { return }
            guard seen.insert(ObjectIdentifier(element)).inserted else { return }
            found.append(element)
        }
        func visit(_ element: any NSAccessibilityProtocol, depth: Int) {
            guard depth < 60 else { return }
            add(element)
            for child in element.accessibilityChildren() ?? [] {
                if let child = child as? any NSAccessibilityProtocol { visit(child, depth: depth + 1) }
            }
        }
        func visitViews(_ view: NSView) {
            if !view.isHiddenOrHasHiddenAncestor, view.isAccessibilityElement() { add(view) }
            for subview in view.subviews { visitViews(subview) }
        }
        visit(window, depth: 0)
        if let root = window.contentView?.superview { visitViews(root) }
        return found
    }

    /// "AXImage 'DSC00231, RAW plus JPEG' value '3 stars' selected actions [Pick, Reject]".
    public static func describe(_ element: any NSAccessibilityProtocol) -> String {
        var line = element.accessibilityRole()?.rawValue ?? "-"
        line += " '\(element.accessibilityLabel() ?? "")'"
        if let value = element.accessibilityValue() { line += " value '\(value)'" }
        if element.isAccessibilitySelected() { line += " selected" }
        let actions = element.accessibilityCustomActions()?.map(\.name) ?? []
        if !actions.isEmpty { line += " actions [\(actions.joined(separator: ", "))]" }
        return line
    }

    /// Runs "press" or a custom action by name. Returns false when the
    /// element has no such action.
    public static func perform(_ action: String, on element: any NSAccessibilityProtocol) -> Bool {
        if action == "press" { return element.accessibilityPerformPress() }
        guard let custom = element.accessibilityCustomActions()?.first(where: { $0.name == action }) else { return false }
        if let handler = custom.handler { return handler() }
        guard let target = custom.target, let selector = custom.selector else { return false }
        _ = target.perform(selector, with: custom)
        return true
    }

    /// The `accessibility <role> [<n> <action>]` debug command: lists the
    /// elements with that role (`any` for all), or runs an action on the nth.
    /// `accessibility focused` prints the element VoiceOver's cursor follows.
    public static func run(_ words: [String], in window: NSWindow?) {
        guard let window, let role = words.first else {
            print("debug-script: accessibility needs a window and a role")
            return
        }
        if role == "focused" {
            // What VoiceOver's cursor follows: the first responder's focused element.
            let focused = (window.firstResponder as? NSView)?.accessibilityFocusedUIElement
            let element = focused as? any NSAccessibilityProtocol
            print("debug-script: accessibility focused \(element.map(describe) ?? "-")")
            return
        }
        let elements = elements(in: window, role: role == "any" ? nil : role)
        if words.count >= 3, let index = Int(words[1]), elements.indices.contains(index) {
            let action = words.dropFirst(2).joined(separator: " ")
            let done = perform(action, on: elements[index])
            print("debug-script: accessibility \(action) on \(index): \(done ? "done" : "not done")")
            return
        }
        print("debug-script: accessibility \(elements.count) \(role)")
        for (index, element) in elements.enumerated().prefix(40) {
            print("debug-script:   \(index) \(describe(element))")
        }
    }
}
