import AppKit
import PhotoCore
import PhotoUI

/// `--debug-script "<commands>"`: drives the UI for development checks without
/// screen recording permission. Commands are separated by ";":
///
///     wait <seconds>        snapshot <file.png>     key <key> [<key>…]
///     loupe | grid          size <points>           focus <index>|<file name without extension>
///     zoom                  project <n>|all         rating any|unrated|<1-5>
///     flag any|picked|rejected|unflagged|notrejected                 quit
///     pairs grouped|separate  pairfile raw|jpeg     advance on|off
///     selectall             addkeywords <a, b>      keyentry      text <typed text>
///     undo | redo           inspector on|off        keyword <n>   (sidebar keyword n, 0-based)
///     print <what>          (state for checks: selection, keywords, undo, suggestions, items, hdr)
///     suggest               (analyzes the selection and waits)      accept <keyword>
///     album <name>          (from the selection)    smartalbum <name>  (rating ≥ 3)     remove
///     sidebar album|smart|month <n> | builtin <name> | changed | all  sheet smart|album|none
///     checkdisk             (looks for outside changes and waits)   resolvedisk library|file
///     click <x> <y>         (mouse down and up through the event queue, in window points
///                           from the top left; launch with `open` so the window is key)
///     hit <x> <y>           (prints the view under a point)
///     menukey <key> […]     (posts keys to the event queue, where an open menu reads them)
///     menupick <x> <y> <item>[/<submenu item>]   (picks from the menu of the menu button at a point)
///     buttons               (prints the window's AppKit buttons and where they are)
///     scroll <y>|bottom     (scrolls the inspector's Adjust tab to a point from its top)
///     hdr on|off            (the View menu's Show HDR; snapshots show HDR clipped at white)
///     import open | source <path> | dest <path> | job <text> | delete on|off | eject on|off
///            | run (waits) | confirm yes|no | snapshot <file> | print   (see ImportDebugCommands)
///     adjust …  original on|off  tab info|adjust   (see DebugAdjustCommands)
///     lut <name>|none       (the first table of that name in any collection)
///     lutimport <folder> [<collection>]   (into a new collection, or an existing one of that name)
///     luts                  (prints the collections)
///     lutwindow open|close|all|collection <name>|expand <name>|select <name>|apply|manage|snapshot <file>
///     copyadjust            pasteadjust            preset save|apply|delete <name> | preset (prints them)
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
        // Line by line, so output reaches a log file even when the app quits.
        setvbuf(stdout, nil, _IOLBF, 0)
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
            let changing: Set<String> = ["key", "addkeywords", "text", "pairfile", "accept", "album", "smartalbum", "remove",
                                         "adjust", "lut", "pasteadjust", "preset", "menupick", "lutwindow"]
            for command in commands where !command.isEmpty {
                let grouped = changing.contains(String(command.prefix { $0 != " " }))
                if grouped { undoManager.beginUndoGrouping() }
                await run(command, model: model)
                if grouped { undoManager.endUndoGrouping() }
            }
        }
    }

    private static var window: NSWindow? {
        // The library window, not the import or look-up table window.
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.className.contains("Window")
            && $0.title != String(localized: "Import") && $0.title != String(localized: "Look-Up Tables") }
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
            if let index = Int(rest.first ?? "") {
                model.setFocus(index)
            } else if let index = model.items.firstIndex(where: { $0.baseName == rest.joined(separator: " ") }) {
                model.setFocus(index)
            }
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
        case "suggest":
            model.suggestKeywords(for: model.actionTargetVersionIDs)
            while model.analysisTask != nil { try? await Task.sleep(for: .milliseconds(100)) }
        case "accept":
            model.acceptSuggestion(rest.joined(separator: " "))
        case "album":
            model.createAlbum(named: rest.joined(separator: " "), projectID: nil, adding: model.actionTargetVersionIDs)
        case "smartalbum":
            // A test album: rating at least 3, picks, or the given name's rule set.
            let rules = SmartAlbumRules(match: .all, rules: [SmartRule(field: .rating, comparison: .atLeast,
                                                                       value: RuleValue(number: 3))])
            model.createSmartAlbum(named: rest.joined(separator: " "), projectID: nil, rules: rules)
        case "remove":
            model.removeFromCurrentAlbum()
        case "sidebar":
            selectSidebar(rest, model: model)
        case "sheet":
            switch rest.first {
            case "smart": model.sidebarSheet = .smartAlbum(model.smartAlbums.first, projectID: nil)
            case "album": model.sidebarSheet = .newAlbum(projectID: nil)
            default: model.sidebarSheet = nil
            }
        case "checkdisk":
            model.checkForDiskChanges()
            try? await Task.sleep(for: .milliseconds(200))
            while model.diskCheckTask != nil { try? await Task.sleep(for: .milliseconds(100)) }
        case "resolvedisk":
            let changes = (try? await model.catalog.diskChanges(forVersions: model.actionTargetVersionIDs)) ?? []
            model.resolveDiskChanges(changes, with: rest.first == "file" ? .useFile : .keepLibrary)
        case "import":
            await runImportCommand(rest, model: model.cardImport, library: model)
        case "click":
            if let window, let point = windowPoint(rest, in: window) {
                printHit(window, at: point)
                // Both events at once: a control's tracking loop waits for the mouse up.
                // SwiftUI buttons inside a scroll view ignore these synthetic clicks.
                for (index, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
                    guard let event = NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: index + 1, clickCount: 1,
                        pressure: type == .leftMouseDown ? 1 : 0) else { continue }
                    NSApp.postEvent(event, atStart: false)
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        case "menupick":
            guard let window, let point = windowPoint(rest, in: window),
                  let hit = window.contentView?.superview?.hitTest(point) else { break }
            var view: NSView? = hit
            while let current = view, !(current is AppKitMenuButton.MenuPopUpButton) { view = current.superview }
            guard let button = view as? AppKitMenuButton.MenuPopUpButton, let menu = button.makeMenu?() else {
                print("debug-script: no menu button at that point")
                break
            }
            var target = menu
            let path = rest.dropFirst(2).joined(separator: " ").split(separator: "/").map(String.init)
            for (depth, title) in path.enumerated() {
                guard let index = target.items.firstIndex(where: { $0.title == title }) else {
                    print("debug-script: no menu item \(title)")
                    break
                }
                if depth == path.count - 1 {
                    target.performActionForItem(at: index)
                } else if let submenu = target.items[index].submenu {
                    target = submenu
                }
            }
            try? await Task.sleep(for: .milliseconds(300))
        case "menukey":
            for key in rest {
                send(key, posted: true)
                try? await Task.sleep(for: .milliseconds(150))
            }
        case "hdr":
            model.showsHDR = rest.first != "off"
        case "adjust":
            await DebugAdjustCommands.run(rest, editor: model.editor)
        case "lut", "lutimport", "luts", "lutwindow":
            await DebugLookTableCommands.run(verb, rest, model: model)
        case "copyadjust":
            model.copyAdjustments()
            try? await Task.sleep(for: .milliseconds(200))
        case "pasteadjust":
            model.pasteAdjustments()
        case "preset":
            let name = rest.dropFirst().joined(separator: " ")
            switch rest.first {
            case "save":
                model.saveAdjustmentPreset(named: name)
                try? await Task.sleep(for: .milliseconds(300))
            case "apply":
                if let preset = model.adjustmentPresets.first(where: { $0.name == name }) { model.applyAdjustmentPreset(preset) }
            case "delete":
                if let preset = model.adjustmentPresets.first(where: { $0.name == name }) {
                    model.deleteAdjustmentPreset(preset)
                    try? await Task.sleep(for: .milliseconds(300))
                }
            default:
                print("debug-script: presets " + model.adjustmentPresets.map(\.name).joined(separator: ", "))
            }
        case "original":
            model.editor.showsOriginal = rest.first != "off"
        case "tab":
            model.inspectorTab = rest.first == "info" ? .info : .adjust
        case "scroll":
            if let root = window?.contentView?.superview { scrollInspector(rest.first ?? "0", in: root) }
            try? await Task.sleep(for: .milliseconds(200))
        case "hit":
            if let window, let point = windowPoint(rest, in: window) { printHit(window, at: point) }
        case "buttons":
            if let window, let root = window.contentView?.superview { printButtons(in: root, window: window) }
        case "print":
            printState(rest.first ?? "", model: model)
        case "quit":
            // An open sheet would keep the app from quitting.
            for window in NSApp.windows {
                if let sheet = window.attachedSheet { window.endSheet(sheet) }
            }
            NSApp.terminate(nil)
        default:
            print("debug-script: unknown command \(verb)")
        }
    }

    /// import open, or one of the shared import commands.
    private static func runImportCommand(_ words: [String], model: CardImportModel, library: LibraryModel) async {
        if words.first == "open" {
            model.refreshSources()
            library.requestsImportWindow = true
            return
        }
        let importWindow = NSApp.windows.first { $0.isVisible && $0.title == String(localized: "Import") }
        if !(await ImportDebugCommands.run(words, model: model, window: importWindow)) {
            print("debug-script: unknown import command")
        }
    }

    private static func selectSidebar(_ words: [String], model: LibraryModel) {
        let index = Int(words.dropFirst().first ?? "") ?? 0
        switch words.first {
        case "album" where model.albums.indices.contains(index): model.sidebarSelection = .album(model.albums[index].id)
        case "smart" where model.smartAlbums.indices.contains(index):
            model.sidebarSelection = .smartAlbum(model.smartAlbums[index].id)
        case "changed": model.sidebarSelection = .changedOnDisk
        case "builtin":
            model.sidebarSelection = BuiltInAlbum(rawValue: words.dropFirst().first ?? "").map { .builtIn($0) } ?? .allPhotos
        case "month" where model.captureMonths.indices.contains(index):
            let month = model.captureMonths[index]
            model.sidebarSelection = .month(year: month.year, month: month.month)
        default: model.sidebarSelection = .allPhotos
        }
    }

    /// `x y` in points from the window's top-left corner, as in a 1x snapshot.
    /// The inspector's scroll view is the one whose document is a flipped clip's host.
    private static func scrollInspector(_ target: String, in view: NSView) {
        if let scrollView = view as? NSScrollView, scrollView.contentView is FlippedClipView,
           let document = scrollView.documentView {
            let maximum = max(0, document.frame.height - scrollView.contentView.bounds.height)
            let y = target == "bottom" ? maximum : min(maximum, Double(target) ?? 0)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }
        for subview in view.subviews { scrollInspector(target, in: subview) }
    }

    private static func windowPoint(_ words: [String], in window: NSWindow) -> NSPoint? {
        guard words.count >= 2, let x = Double(words[0]), let y = Double(words[1]) else { return nil }
        return NSPoint(x: x, y: window.frame.height - y)
    }

    private static func printHit(_ window: NSWindow, at point: NSPoint) {
        guard let frameView = window.contentView?.superview else { return }
        var hit = frameView.hitTest(frameView.convert(point, from: nil))
        var chain: [String] = []
        while let view = hit, chain.count < 4 {
            chain.append(String(describing: type(of: view)))
            hit = view.superview
        }
        print("debug-script: \(Int(point.x)),\(Int(window.frame.height - point.y)) hits " + chain.joined(separator: " < "))
    }

    private static func printButtons(in view: NSView, window: NSWindow) {
        if let button = view as? NSButton, !view.isHiddenOrHasHiddenAncestor {
            let frame = button.convert(button.bounds, to: nil)
            let name = button.title.isEmpty ? (button.toolTip ?? "") : button.title
            print("debug-script: button '\(name)' at \(Int(frame.midX)),\(Int(window.frame.height - frame.midY))")
        }
        for subview in view.subviews { printButtons(in: subview, window: window) }
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
        case "hdr":
            let potential = window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
            let headroom = model.loupeHDRHeadroom.map { String(format: "%.2f", $0) } ?? "none"
            print("debug-script: hdr setting \(model.showsHDR) screen potential \(potential) loupe headroom \(headroom)")
        case "selection":
            print("debug-script: selection \(model.selection.count), focus \(model.focusIndex.map(String.init) ?? "-")")
        case "keywords":
            print("debug-script: keywords " + model.keywords.map { "\($0.name)=\($0.count)" }.joined(separator: " "))
        case "responder":
            print("debug-script: key \(NSApp.keyWindow.map { "\(type(of: $0))" } ?? "nil") first \(window?.firstResponder.map { "\(type(of: $0))" } ?? "nil") shared undo \(window?.undoManager === model.undoManager)")
        case "undo":
            let manager = model.undoManager
            print("debug-script: undo '\(manager.canUndo ? manager.undoActionName : "-")' redo '\(manager.canRedo ? manager.redoActionName : "-")'")
        case "suggestions":
            let ids = model.actionTargetVersionIDs
            Task {
                let summary = try? await model.catalog.suggestionSummary(forVersions: ids)
                print("debug-script: suggestions " + (summary?.suggestions ?? []).map {
                    "\($0.name)=\($0.count)@\(String(format: "%.2f", $0.confidence))"
                }.joined(separator: " ") + " unanalyzed \(summary?.unanalyzedCount ?? -1)")
            }
        case "sidebar":
            let counts = model.sidebarCounts.map { "\(model.title(for: $0.key))=\($0.value)" }.sorted()
            print("debug-script: albums " + model.albums.map { "\($0.album.name)=\($0.count)" }.joined(separator: " ")
                  + " | months " + model.captureMonths.map { "\($0.id)=\($0.count)" }.joined(separator: " ")
                  + " | " + counts.joined(separator: " ") + " | showing \(model.items.count)")
        case "disk":
            print("debug-script: changed on disk \(model.diskChangeCount), writes \(model.writesSidecars)")
        case "import":
            ImportDebugCommands.printState(model.cardImport)
        case "adjustments":
            DebugAdjustCommands.printState(model.editor)
        case "items":
            print("debug-script: items " + model.items.prefix(12).map { "\($0.baseName):\($0.rating.rawValue)" }.joined(separator: " "))
        default:
            print("debug-script: nothing to print for \(what)")
        }
    }

    private static func send(_ spec: String, posted: Bool = false) {
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
            // Through the application when it is active, so local event monitors see
            // the key as they would a real one; a scripted launch often is not.
            if posted {
                NSApp.postEvent(event, atStart: false)
            } else if NSApp.isActive, NSApp.keyWindow === window {
                NSApp.sendEvent(event)
            } else {
                window.sendEvent(event)
            }
        }
    }

    /// Renders the window's layer tree, which includes layer contents that
    /// `cacheDisplay` would miss.
    private static func snapshot(to url: URL) {
        guard let window else {
            print("debug-script: no window to snapshot")
            return
        }
        WindowSnapshot.write(window, to: url)
    }
}
