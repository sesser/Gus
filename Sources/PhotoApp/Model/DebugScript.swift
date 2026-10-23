import AppKit
import PhotoCore
import UniformTypeIdentifiers

/// `--debug-script "<commands>"`: drives the UI for development checks without
/// screen recording permission. Commands are separated by ";":
///
///     wait <seconds>        snapshot <file.png>     key <key> [<key>…]
///     loupe | grid          size <points>           focus <index>
///     zoom                  project <n>|all         rating any|unrated|<1-5>
///     flag any|picked|rejected|unflagged|notrejected                 quit
///     pairs grouped|separate  pairfile raw|jpeg     advance on|off
///     selectall             addkeywords <a, b>      keyentry      text <typed text>
///     undo | redo           inspector on|off        keyword <n>   (sidebar keyword n, 0-based)
///     print <what>          (state for checks: selection, keywords, undo)
///
/// Keys are characters ("3", "p") or names (left, right, up, down, home, end,
/// pageup, pagedown, return, escape, space); prefix "opt+" or "shift+" for modifiers. Key events go through
/// the window, so they take the same path as real typing.
@MainActor
enum DebugScript {
    private static var started = false

    static func startIfRequested(model: LibraryModel) {
        guard let script = LaunchOptions.current.debugScript, !started else { return }
        started = true
        let commands = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        Task {
            // Give the window and the first items time to appear.
            try? await Task.sleep(for: .seconds(1))
            // Scripted commands arrive without events, so nothing would separate
            // their undo steps; each command gets its own group, as a key press would.
            let undoManager = model.undoManager
            undoManager.groupsByEvent = false
            // Only commands that can change photos get a group; empty groups
            // would otherwise become undo steps that do nothing.
            let changing: Set<String> = ["key", "addkeywords", "text", "pairfile"]
            for command in commands where !command.isEmpty {
                let grouped = changing.contains(String(command.prefix { $0 != " " }))
                if grouped { undoManager.beginUndoGrouping() }
                await run(command, model: model)
                if grouped { undoManager.endUndoGrouping() }
            }
        }
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.className.contains("Window") }
    }

    private static func run(_ command: String, model: LibraryModel) async {
        let parts = command.split(separator: " ").map(String.init)
        guard let verb = parts.first else { return }
        let rest = Array(parts.dropFirst())
        switch verb {
        case "wait":
            try? await Task.sleep(for: .seconds(Double(rest.first ?? "1") ?? 1))
        case "snapshot":
            if let path = rest.first { snapshot(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)) }
        case "key":
            for key in rest {
                send(key)
                try? await Task.sleep(for: .milliseconds(80))
            }
        case "loupe":
            model.openLoupe()
        case "grid":
            model.closeLoupe()
        case "size":
            model.thumbnailSize = Double(rest.first ?? "") ?? model.thumbnailSize
        case "focus":
            model.setFocus(Int(rest.first ?? "") ?? 0)
        case "zoom":
            send("z")
        case "project":
            if let index = Int(rest.first ?? ""), model.projects.indices.contains(index) {
                model.sidebarSelection = .project(model.projects[index].id)
            } else {
                model.sidebarSelection = .allPhotos
            }
        case "rating":
            switch rest.first {
            case "unrated": model.ratingRule = .unrated
            case let value?: model.ratingRule = Int(value).map { .atLeast(Rating(clamping: $0)) } ?? .any
            case nil: model.ratingRule = .any
            }
        case "flag":
            let rules: [String: LibraryFilter.FlagRule] = [
                "picked": .picked, "rejected": .rejected, "unflagged": .unflagged, "notrejected": .notRejected,
            ]
            model.flagRule = rules[rest.first ?? ""] ?? .any
        case "pairs":
            model.groupPairs = rest.first != "separate"
        case "pairfile":
            model.showPairFile(raw: rest.first != "jpeg")
        case "advance":
            model.autoAdvance = rest.first == "on"
        case "selectall":
            perform(#selector(NSResponder.selectAll(_:)), verb)
        case "addkeywords":
            model.addKeywords(KeywordCompletion.keywords(in: rest.joined(separator: " ")))
        case "keyentry":
            model.beginKeywordEntry()
        case "text":
            let text = command.dropFirst(verb.count + 1)
            (window?.firstResponder as? NSTextView)?.insertText(String(text), replacementRange: NSRange(location: NSNotFound, length: 0))
        case "undo", "redo":
            perform(Selector((verb + ":")), verb)
        case "inspector":
            model.showsInspector = rest.first != "off"
        case "keyword":
            if let index = Int(rest.first ?? ""), model.keywords.indices.contains(index) {
                model.sidebarSelection = .keyword(model.keywords[index].id)
            }
        case "print":
            printState(rest.first ?? "", model: model)
        case "quit":
            NSApp.terminate(nil)
        default:
            print("debug-script: unknown command \(verb)")
        }
    }

    /// Sends an action up the responder chain from the window's first responder,
    /// the way a menu item does in the key window. (A scripted launch is often
    /// not the active app, so there may be no key window to send it to.)
    private static func perform(_ action: Selector, _ name: String) {
        guard let responder = window?.firstResponder, responder.tryToPerform(action, with: nil) else {
            print("debug-script: nothing handled \(name)")
            return
        }
    }

    private static func printState(_ what: String, model: LibraryModel) {
        switch what {
        case "selection":
            print("debug-script: selection \(model.selection.count), focus \(model.focusIndex.map(String.init) ?? "-")")
        case "keywords":
            print("debug-script: keywords " + model.keywords.map { "\($0.name)=\($0.count)" }.joined(separator: " "))
        case "responder":
            print("debug-script: key \(NSApp.keyWindow.map { "\(type(of: $0))" } ?? "nil") first \(window?.firstResponder.map { "\(type(of: $0))" } ?? "nil") shared undo \(window?.undoManager === model.undoManager)")
        case "undo":
            let manager = model.undoManager
            print("debug-script: undo '\(manager.canUndo ? manager.undoActionName : "-")' redo '\(manager.canRedo ? manager.redoActionName : "-")'")
        case "items":
            print("debug-script: items " + model.items.prefix(12).map { "\($0.baseName):\($0.rating.rawValue)" }.joined(separator: " "))
        default:
            print("debug-script: nothing to print for \(what)")
        }
    }

    private static func send(_ spec: String) {
        guard let window else { return }
        var flags: NSEvent.ModifierFlags = []
        var key = spec
        while let range = key.range(of: "+"), key.count > 1 {
            switch key[..<range.lowerBound] {
            case "opt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            case "cmd": flags.insert(.command)
            default: break
            }
            key = String(key[range.upperBound...])
        }
        let named: [String: (UInt16, String)] = [
            "left": (123, "\u{F702}"), "right": (124, "\u{F703}"), "down": (125, "\u{F701}"), "up": (126, "\u{F700}"),
            "return": (36, "\r"), "escape": (53, "\u{1B}"), "space": (49, " "),
            "home": (115, "\u{F729}"), "end": (119, "\u{F72B}"), "pageup": (116, "\u{F72C}"), "pagedown": (121, "\u{F72D}"),
        ]
        let digits: [String: UInt16] = ["0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26]
        let letters: [String: UInt16] = ["p": 35, "x": 7, "u": 32, "z": 6, "[": 33, "]": 30]
        let (code, characters) = named[key] ?? (digits[key] ?? letters[key] ?? 0, key)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: code)
            else { continue }
            window.sendEvent(event)
        }
    }

    /// Renders the window's layer tree, which includes layer contents that
    /// `cacheDisplay` would miss.
    private static func snapshot(to url: URL) {
        guard let window, let view = window.contentView?.superview ?? window.contentView, let layer = view.layer else {
            print("debug-script: no window to snapshot")
            return
        }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("debug-script: wrote \(url.path)")
    }
}
