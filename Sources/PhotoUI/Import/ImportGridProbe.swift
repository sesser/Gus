import AppKit

/// The debug script's view of the import grid (see `ImportDebugCommands`).
@MainActor
enum ImportGridProbe {
    static func collectionView(in window: NSWindow?) -> ImportCollectionView? {
        func find(_ view: NSView) -> ImportCollectionView? {
            if let grid = view as? ImportCollectionView { return grid }
            for subview in view.subviews { if let grid = find(subview) { return grid } }
            return nil
        }
        return window?.contentView.flatMap(find)
    }

    static func printGrid(in window: NSWindow?) {
        guard let grid = collectionView(in: window), let controller = grid.controller else {
            print("debug-script: import grid: none shown")
            return
        }
        let firstResponder = window?.firstResponder === grid
        print("debug-script: import grid \(controller.shots.count) shots, columns \(controller.layout.columns), "
              + "focus \(controller.focusIndex.map(String.init) ?? "-"), first responder \(firstResponder)")
        for path in grid.indexPathsForVisibleItems().sorted() {
            guard let view = grid.item(at: path)?.view as? ImportCellView else { continue }
            let value = view.accessibilityValue().map { "\($0)" } ?? "-"
            print("debug-script:   \(path.item) \(view.accessibilityRole()?.rawValue ?? "-") "
                  + "'\(view.accessibilityLabel() ?? "-")' value \(value)")
        }
    }

    static func send(_ key: String, in window: NSWindow?) {
        guard let window, let grid = collectionView(in: window) else { return }
        window.makeFirstResponder(grid)
        let named: [String: (UInt16, String)] = [
            "left": (123, "\u{F702}"), "right": (124, "\u{F703}"), "down": (125, "\u{F701}"), "up": (126, "\u{F700}"),
            "return": (36, "\r"), "space": (49, " "), "home": (115, "\u{F729}"), "end": (119, "\u{F72B}"),
        ]
        guard let (code, characters) = named[key],
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
        else {
            print("debug-script: import key: unknown \(key)")
            return
        }
        grid.keyDown(with: event)
    }

    /// Lists the context menu of cell `index`, or picks the item titled so.
    static func contextMenu(_ words: [String], in window: NSWindow?) {
        guard let grid = collectionView(in: window), let controller = grid.controller else { return }
        let menu = controller.menu(forItemAt: words.first.flatMap(Int.init))
        let title = words.dropFirst().joined(separator: " ")
        if !title.isEmpty {
            guard let index = menu?.items.firstIndex(where: { $0.title == title }) else {
                print("debug-script: import contextmenu: no item \(title)")
                return
            }
            menu?.performActionForItem(at: index)
            return
        }
        let items = menu?.items.map { $0.isSeparatorItem ? "—" : ($0.isEnabled ? $0.title : "(\($0.title))") } ?? []
        print("debug-script: import contextmenu \(items.joined(separator: " | "))")
    }

    /// The options inspector without its glass background, which window
    /// snapshots cannot draw: the largest view around the first template
    /// field that is still inspector-wide.
    static func snapshotOptions(in window: NSWindow?, to url: URL) {
        guard let root = window?.contentView, let field = TemplateFieldProbe.templateFields(in: root).first else { return }
        var view: NSView = field
        while let parent = view.superview, parent.frame.width <= 420 { view = parent }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        print("debug-script: wrote \(url.path) (\(Int(view.frame.width))×\(Int(view.frame.height)))")
    }

    static func snapshotGrid(in window: NSWindow?, to url: URL) {
        guard let grid = collectionView(in: window), let scroll = grid.enclosingScrollView,
              let bitmap = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) else { return }
        scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        print("debug-script: wrote \(url.path)")
    }
}
