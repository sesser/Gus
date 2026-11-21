import AppKit
import PhotoCore

/// The debug script's commands for the Presets heading's views (#241,
/// design §10). None changes a photo, so none runs in an undo group:
///
///     preset view list|thumbnails|print   (the view switch's choice, as a segment click sets it; waits 600 ms, then
///                           prints the choice, what is stored, thumbnail renders since launch, the list rows
///                           and thumbnails in the window, and the height each takes from first to last)
///     hover <x> <y> | name <preset name> | end   (the pointer onto the preset row or thumbnail at a window point
///                           from the top left, or the one named, leaving the one hovered before as a real move
///                           does; end leaves it. Through the button's own enter and exit, so the loupe preview
///                           and its 120 ms hold run as for a real pointer. Prints the preview's state)
///     preset row <name> press|focus   (a list row or thumbnail by its preset's name: VoiceOver's press, in an
///                           undo group like the other preset commands; or the keyboard on it, for `key space`)
///     preset heading <collection>   (a collection's heading, through its button's click: opens or closes it,
///                           as a click does; prints whether it is open and what it stored)
///     print presetsbar      (the Presets button row: which arrangement shows, each control's frame, overlap or
///                           clear, and each arrangement's needed width against the narrowest column's room; then
///                           what VoiceOver reads for the switch, its segments and the rows)
@MainActor
enum DebugPresetViewCommands {
    /// The row or thumbnail the pointer is on.
    private static weak var hovered: ImageTile.HoverButton?

    static func runView(_ arguments: [String], model: LibraryModel, window: NSWindow?) async {
        switch arguments.first {
        case "list": model.presetsView = .list
        case "thumbnails": model.presetsView = .thumbnails
        case "print", nil: break
        default:
            print("debug-script: preset view takes list, thumbnails or print")
            return
        }
        try? await Task.sleep(for: .milliseconds(600))
        let names = Set(model.adjustmentPresets.map(\.name))
        var rows = 0, tiles = 0
        // The height from the first item's top to the last one's bottom, in each view.
        var rowSpan = CGRect.null, tileSpan = CGRect.null
        if let root = window?.contentView?.superview {
            visit(root) { button in
                guard names.contains(button.accessibilityLabel() ?? "") else { return }
                let frame = button.convert(button.bounds, to: nil)
                if button is PresetListRowButton {
                    rows += 1
                    rowSpan = rowSpan.union(frame)
                } else {
                    tiles += 1
                    tileSpan = tileSpan.union(frame)
                }
            }
        }
        let stored = UserDefaults.standard.string(forKey: PresetsViewChoice.defaultsKey) ?? "nothing"
        let height = { (span: CGRect) in span.isNull ? "-" : String(format: "%.0f", span.height) }
        print("debug-script: preset view \(model.presetsView.rawValue) stored \(stored)"
              + " thumbnailRenders \(model.presetPreviews.debugRenderedCount) rows \(rows) tiles \(tiles)"
              + " rowsHeight \(height(rowSpan)) tilesHeight \(height(tileSpan))")
    }

    static func runRow(_ arguments: [String], model: LibraryModel, window: NSWindow?) async {
        guard let window, let action = arguments.last, ["press", "focus"].contains(action), arguments.count >= 2 else {
            print("debug-script: preset row <name> press|focus")
            return
        }
        guard let button = target(["name"] + arguments.dropLast(), model: model, in: window) else {
            print("debug-script: no preset row or thumbnail named \(arguments.dropLast().joined(separator: " "))")
            return
        }
        if action == "press" {
            print("debug-script: preset row '\(button.accessibilityLabel() ?? "-")' press \(button.accessibilityPerformPress())")
            // The apply saves on the model's write chain.
            try? await Task.sleep(for: .milliseconds(600))
        } else {
            print("debug-script: preset row '\(button.accessibilityLabel() ?? "-")' focus \(window.makeFirstResponder(button))"
                  + " accepts \(button.acceptsFirstResponder) canBecomeKey \(button.canBecomeKeyView)")
        }
    }

    static func runHeading(_ arguments: [String], model: LibraryModel, window: NSWindow?) async {
        let name = arguments.joined(separator: " ")
        // The heading's title is the name, then its count.
        guard let root = window?.contentView?.superview,
              let heading = descendant(of: NSButton.self, in: root, where: {
                  !$0.isHiddenOrHasHiddenAncestor && ($0.toolTip == String(localized: "Expand") || $0.toolTip == String(localized: "Collapse"))
                      && $0.title.hasPrefix(name + " ")
              }) else {
            print("debug-script: no collection heading \(name)")
            return
        }
        heading.performClick(nil)
        try? await Task.sleep(for: .milliseconds(600))
        let stored = UserDefaults.standard.object(forKey: "adjust.presets.\(name)").map { "\($0)" } ?? "nothing"
        print("debug-script: preset heading '\(name)' stored \(stored)")
    }

    static func runHover(_ arguments: [String], model: LibraryModel, window: NSWindow?) async {
        guard let window else { return }
        if arguments.first == "end" {
            let name = hovered?.accessibilityLabel() ?? "-"
            hovered?.simulateHover(false)
            hovered = nil
            // Past the 120 ms hold, so the preview has ended.
            try? await Task.sleep(for: .milliseconds(400))
            printHover(name, model: model)
            return
        }
        guard let target = target(arguments, model: model, in: window) else {
            print("debug-script: hover found no preset row or thumbnail there")
            return
        }
        if let previous = hovered, previous !== target { previous.simulateHover(false) }
        target.simulateHover(true)
        hovered = target
        // Past the hold of the row just left, and time for a frame.
        try? await Task.sleep(for: .milliseconds(600))
        printHover(target.accessibilityLabel() ?? "-", model: model)
    }

    /// The hovered preset's name, whether the editor previews, what the loupe
    /// shows (`preview`: the previewed values; `saved`: the photo's saved
    /// edits; `other`), previews ended by a pointer leaving, and the
    /// editor's render requests.
    private static func printHover(_ name: String, model: LibraryModel) {
        let editor = model.editor
        let shown = editor.frame?.adjustments
        let loupe = if editor.isPreviewing, let values = editor.debugPreviewValues, shown == values {
            "preview"
        } else if !editor.showsLive || shown == editor.savedAdjustments {
            "saved"
        } else {
            "other"
        }
        print("debug-script: hover '\(name)' preview \(editor.isPreviewing ? "on" : "off") loupe \(loupe)"
              + " ends \(model.presetPreviews.debugHoverEnds) renders \(editor.debugRenderRequests) mode \(model.mode)")
    }

    private static func target(_ arguments: [String], model: LibraryModel, in window: NSWindow) -> ImageTile.HoverButton? {
        if arguments.first == "name" {
            let name = arguments.dropFirst().joined(separator: " ")
            var found: ImageTile.HoverButton?
            if let root = window.contentView?.superview {
                visit(root) { if found == nil, $0.accessibilityLabel() == name { found = $0 } }
            }
            return found
        }
        guard arguments.count >= 2, let x = Double(arguments[0]), let y = Double(arguments[1]),
              let frameView = window.contentView?.superview else { return nil }
        let point = NSPoint(x: x, y: window.frame.height - y)
        var view = frameView.hitTest(frameView.convert(point, from: nil))
        while let current = view, !(current is ImageTile.HoverButton) { view = current.superview }
        return view as? ImageTile.HoverButton
    }

    private static func visit(_ view: NSView, _ body: (ImageTile.HoverButton) -> Void) {
        if let button = view as? ImageTile.HoverButton, !button.isHiddenOrHasHiddenAncestor { body(button) }
        for subview in view.subviews { visit(subview, body) }
    }

    // MARK: The button row

    /// `print presetsbar`: the row as laid out now, then each arrangement's
    /// needed width (from the controls' real sizes) against the room the
    /// row has at the inspector's narrowest, with an overlay scroller and
    /// with a legacy one.
    static func printBar(in window: NSWindow?) {
        guard let root = window?.contentView?.superview,
              let control = descendant(of: NSSegmentedControl.self, in: root, where: {
                  $0.accessibilityLabel() == String(localized: "Presets view") && !$0.isHiddenOrHasHiddenAncestor
              }),
              let scroll = control.enclosingScrollView else {
            print("debug-script: presetsbar not shown (open the Presets heading in the Adjust tab)")
            return
        }
        let clip = scroll.contentView
        func button(_ title: String) -> NSButton? {
            descendant(of: NSButton.self, in: clip, where: { $0.title == title && !$0.isHiddenOrHasHiddenAncestor })
        }
        guard let save = button(String(localized: "Save…", comment: "Save a preset")),
              let importButton = button(String(localized: "Import…")),
              let manage = button(String(localized: "Manage…")) else {
            print("debug-script: presetsbar push buttons not found")
            return
        }
        let views: [NSView] = [save, importButton, manage, control]
        let frames = views.map { $0.convert($0.bounds, to: clip) }
        let sameLine = { (a: Int, b: Int) in abs(frames[a].midY - frames[b].midY) < 2 }
        let shown = if sameLine(0, 2) && sameLine(0, 3) { "1" } else if sameLine(0, 3) { "2" }
            else if sameLine(2, 3) { "3" } else { "unknown" }
        var overlap = false
        for i in frames.indices { for j in frames.indices where j > i && frames[i].intersects(frames[j]) { overlap = true } }
        let points = { (value: CGFloat) in String(format: "%.1f", value) }
        let describe = { (rect: CGRect) in "\(points(rect.minX)),\(points(rect.minY)) \(points(rect.width))x\(points(rect.height))" }
        let names = ["save", "import", "manage", "switch"]
        let visible = clip.bounds.width
        let rowStart = frames[0].minX
        let available = visible - InspectorMetrics.padding - rowStart
        print("debug-script: presetsbar arrangement \(shown) visible \(points(visible)) available \(points(available)) "
              + zip(names, frames).map { "\($0) \(describe($1))" }.joined(separator: " ")
              // From the push button before the switch on its line.
              + " gap \(points(frames[3].minX - (shown == "2" ? frames[1].maxX : frames[2].maxX)))"
              + (overlap ? " overlap" : " clear"))
        let sizes = PresetsBarGeometry.Sizes(save: frames[0].size, importButton: frames[1].size,
                                             manage: frames[2].size, viewSwitch: frames[3].size)
        // As `print inspectorwidth`: the visible width at the narrowest pane, the scroller taking the same then.
        let pane = scroll.frame.width
        let legacyNow = scroll.scrollerStyle == .legacy && scroll.hasVerticalScroller
        let scroller = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let narrowest = visible - (pane - InspectorMetrics.minimumColumnWidth) - InspectorMetrics.padding - rowStart
        let overlayRoom = legacyNow ? narrowest + scroller : narrowest
        let legacyRoom = legacyNow ? narrowest : narrowest - scroller
        let needs = PresetsBarGeometry.Arrangement.allCases.map {
            "\($0.rawValue) \(points(PresetsBarGeometry.neededWidth($0, sizes)))"
        }.joined(separator: " ")
        print("debug-script: presetsbar needs \(needs) scroller \(legacyNow ? "legacy" : "overlay")"
              + " narrowest overlay \(points(overlayRoom)) -> \(PresetsBarGeometry.arrangement(forWidth: overlayRoom, sizes).rawValue)"
              + " legacy \(points(legacyRoom)) -> \(PresetsBarGeometry.arrangement(forWidth: legacyRoom, sizes).rawValue)"
              + " switch segments \(control.segmentCount) width \(points(control.intrinsicContentSize.width))")
        printAccessibility(of: control, in: clip)
    }

    /// What VoiceOver reads: the switch (role, label, and its accessibility
    /// children down to the segments, with their names and selection) and
    /// each list row shown (the view, and its cell, which AppKit makes the
    /// element of a cell-based control).
    private static func printAccessibility(of control: NSSegmentedControl, in clip: NSView) {
        func describe(_ element: any NSAccessibilityProtocol) -> String {
            let name = element.accessibilityLabel() ?? element.accessibilityTitle() ?? "-"
            let value = element.accessibilityValue().map { " value '\($0)'" } ?? ""
            return "\(element.accessibilityRole()?.rawValue ?? "-") '\(name)'" + value
                + (element.accessibilityHelp().map { " help '\($0.replacingOccurrences(of: "\n", with: " / "))'" } ?? "")
                + (element.isAccessibilitySelected() ? " selected" : "")
        }
        func tree(_ element: any NSAccessibilityProtocol, depth: Int) -> String {
            let children = depth < 3 ? (element.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibilityProtocol } : []
            return describe(element) + (children.isEmpty ? "" : " [" + children.map { tree($0, depth: depth + 1) }.joined(separator: ", ") + "]")
        }
        print("debug-script: presetsbar accessibility switch " + tree(control, depth: 0)
              + (control.cell.map { " cell " + tree($0, depth: 0) } ?? ""))
        var rows: [String] = []
        func visit(_ view: NSView) {
            if let row = view as? PresetListRowButton, !row.isHiddenOrHasHiddenAncestor {
                rows.append(describe(row) + (row.cell.map { " cell " + describe($0) } ?? ""))
            }
            view.subviews.forEach(visit)
        }
        visit(clip)
        print("debug-script: presetsbar accessibility rows \(rows.count) [\(rows.joined(separator: ", "))]")
        printIndents(in: clip)
    }

    /// Where list rows' names start against the push buttons' edge and an
    /// open collection heading's title (design §4.2: under a heading, where
    /// its title starts; otherwise 8 pt in from the column's edge).
    private static func printIndents(in clip: NSView) {
        var lines: [String] = []
        func visit(_ view: NSView) {
            if let row = view as? PresetListRowButton, !row.isHiddenOrHasHiddenAncestor {
                let frame = row.convert(row.bounds, to: clip)
                lines.append("'\(row.name)' row \(Int(frame.minX))...\(Int(frame.maxX)) text \(String(format: "%.1f", frame.minX + row.textInset))")
            } else if let button = view as? NSButton, !button.isHiddenOrHasHiddenAncestor,
                      button.toolTip == String(localized: "Collapse") || button.toolTip == String(localized: "Expand"),
                      button.image != nil, !button.title.isEmpty, let cell = button.cell {
                let title = button.convert(cell.titleRect(forBounds: button.bounds), to: clip)
                lines.append("heading '\(button.title)' title \(String(format: "%.1f", title.minX))")
            }
            view.subviews.forEach(visit)
        }
        visit(clip)
        // The first and last row of each run, and every heading.
        let kept = lines.enumerated().filter { index, line in
            line.hasPrefix("heading") || index == 0 || index == lines.count - 1
                || lines[index - 1].hasPrefix("heading") || lines[index + 1].hasPrefix("heading")
        }.map(\.element)
        print("debug-script: presetsbar indents " + kept.joined(separator: "; "))
    }

    private static func descendant<V: NSView>(of type: V.Type, in view: NSView, where test: (V) -> Bool) -> V? {
        if let match = view as? V, test(match) { return match }
        for subview in view.subviews {
            if let match = descendant(of: type, in: subview, where: test) { return match }
        }
        return nil
    }
}
