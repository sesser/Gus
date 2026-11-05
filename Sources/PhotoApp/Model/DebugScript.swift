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
///     search [<text>]       (the toolbar's search; empty clears)
///     sort captureDate|rating|fileName [asc|desc]
///     pairs grouped|separate  pairfile raw|jpeg     advance on|off
///     selectall             addkeywords <a, b>      keyentry      text <typed text>
///     undo | redo           inspector on|off        keyword <n>   (sidebar keyword n, 0-based)
///     print <what>          (state for checks: selection, keywords, undo, suggestions, items, hdr, announcement,
///                           title (title, subtitle, filter and sort), activity,
///                           loupe [<x> <y>]: mode, magnification, visible rect, image point under x y)
///     suggest               (analyzes the selection and waits)      accept <keyword>
///     album <name>          (from the selection)    smartalbum <name>  (rating ≥ 3)     remove
///     sidebar album|smart|month <n> | builtin <name> | changed | all  sheet smart|album|none
///     checkdisk             (looks for outside changes and waits)   resolvedisk library|file
///     click <x> <y>         (mouse down and up through the event queue, in window points
///                           from the top left; launch with `open` so the window is key)
///     drag <x> <y> <x2> <y2> (mouse down, eight drags and up through the event queue, like click)
///     doubleclick <x> <y>   (two clicks, the second with a click count of 2; same coordinates as click)
///     optionscroll <x> <y> <lines>   (Option-scroll of a mouse wheel over a point in the loupe; positive zooms in)
///     hit <x> <y>           (prints the view under a point)
///     menuhover <x> <y> <item>[/<sub>] | end   (highlights a menu item; end closes the menu)
///     menukey <key> […]     (posts keys to the event queue, where an open menu reads them)
///     menupick <x> <y> <item>[/<submenu item>]   (picks from the menu of the menu button at a point)
///     buttons               (prints the window's AppKit buttons and where they are)
///     menuitems [<text>]    (main menu items whose title contains text: key equivalent, enabled, checked)
///     menupress <title>     (runs the main menu item with that title, if enabled)
///     sidebarsection [albums|dates|keywords|projects show|hide]   (prints the hidden sidebar sections)
///     contextmenu cell <n>|loupe|slider <title> [<item>[/<sub>]]   (prints a right-click's menu there, or runs an item)
///     editvalue <title>     (puts the keyboard in the value field of the inspector slider with that title)
///     accessibility <role>|any [<n> press|<action name>] | focused   (lists the window's accessibility
///                           elements with that role, e.g. AXImage, or runs an action on the nth; see AccessibilityProbe)
///     scroll <y>|bottom     (scrolls the inspector's Adjust tab to a point from its top)
///     hdr on|off            (the View menu's Show HDR; snapshots show HDR clipped at white)
///     filmstrip on|off|toggle   (the loupe's film strip, as its toggle: slides)
///     filmstripsize <points>    (stores the nearest step, as a release does)
///     windowsize <width> <height>   (the library window's content size, e.g. a short window for the strip's cap)
///     filmstripclick <n>    (a click on the strip's cell n, through the event queue like click; it must be on screen)
///     filmstripdrag <dy> [hold] | release | reset   (a drag on the resize handle by dy points, up positive,
///                           through the handle's own mouse methods, then release; hold leaves it mid-drag for a
///                           snapshot; reset is a double-click on the handle)
///     print filmstrip       (setting, stored and shown step, cell, height, offset, the centered index, the
///                           visible range, and the canvas fits since the last print)
///     review [on|off|grid|leavefullscreen]   (View ▸ Enter / Exit Review, as F; the Grid segment;
///                           the window leaving full screen; print review shows the layout)
///     import open | source <path> | dest <path> | job <text> | delete on|off | eject on|off
///            | videos on|off | rescan | toggle <n> | accessibility … | run (waits) | confirm yes|no | snapshot <file> | print
///            (see ImportDebugCommands)
///     adjust …  original on|off  tab info|adjust   (see DebugAdjustCommands)
///     metadata <field> [<text>]   print metadata   sidecars on|off   (see DebugMetadataCommands)
///     dropfolders <path>[, <path>…]   (imports dropped items the way a drop from Finder does)
///     waitimport            (waits for folder imports to finish, then prints the projects and status)
///     drophighlight on|off  (shows the browser's folder drop highlight)
///     lut <name>|none       (the first table of that name in any collection)
///     lutimport <folder> [<collection>]   (into a new collection, or an existing one of that name)
///     luts                  (prints the collections)
///     lutwindow open|close|all|collection <name>|expand <name>|select <name>|apply|manage|back|snapshot <file> (the sheet)
///     copyadjust            pasteadjust            preset save|apply|delete|preview <name> | preset (prints them)
///     preset import <path>…  (prints the summary)   preset summary <path>… (imports, shows the alert)
///     preset export <file> [<name>]                 preset window | windowshot <png> (the sheet)
///     export window | windowshot <png> | set <key>=<value>… | template <text> | run [keepboth|overwrite|skip]
///            | preset save|apply|delete <name> | print   (see DebugExportCommands)
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
            // would otherwise become undo steps that do nothing. A film strip
            // click moves focus, which saves a crop being edited.
            let changing: Set<String> = ["key", "addkeywords", "text", "pairfile", "accept", "album", "smartalbum", "remove",
                                         "adjust", "lut", "pasteadjust", "preset", "menupick", "lutwindow", "metadata",
                                         "menupress", "contextmenu", "filmstripclick"]
            for command in commands where !command.isEmpty {
                let words = command.split(separator: " ")
                // "accessibility <role> <n> <action>" runs an action; listing changes nothing.
                let grouped = changing.contains(String(words.first ?? ""))
                    || (words.first == "accessibility" && words.count >= 4)
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
        case "search":
            model.searchText = rest.joined(separator: " ")
        case "sort":
            if let key = rest.first.flatMap(LibrarySort.Key.init(rawValue:)) {
                model.sort = LibrarySort(key: key, ascending: rest.dropFirst().first != "desc")
            }
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
        case "dropfolders":
            let paths = rest.joined(separator: " ").split(separator: ",")
                .map { ($0.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath }
            // Item providers like Finder's, read by the drop's own code.
            let providers = paths.map { NSItemProvider(object: URL(fileURLWithPath: $0) as NSURL) }
            model.importFolders(await FolderDrop.urls(from: providers))
        case "waitimport":
            while model.isImportRunning { try? await Task.sleep(for: .milliseconds(100)) }
            print("debug-script: projects " + model.projects.map { "\($0.project.name)=\($0.versionCount)" }
                .joined(separator: " ") + " | \(model.statusMessage ?? "")")
        case "drophighlight":
            model.isFolderDropTargeted = rest.first == "on"
        case "click":
            if let window, let point = windowPoint(rest, in: window) {
                printHit(window, at: point)
                postClick(at: point, in: window)
                try? await Task.sleep(for: .milliseconds(300))
            }
        case "filmstrip":
            switch rest.first {
            case "off": model.showsFilmStrip = false
            case "toggle": model.showsFilmStrip.toggle()
            default: model.showsFilmStrip = true
            }
            try? await Task.sleep(for: .milliseconds(200))
        case "filmstripsize":
            if let size = Double(rest.first ?? "") {
                model.filmStripSize = FilmStripGeometry.nearestStep(size)
            }
            try? await Task.sleep(for: .milliseconds(200))
        case "windowsize":
            if let window, rest.count == 2, let width = Double(rest[0]), let height = Double(rest[1]) {
                window.setContentSize(NSSize(width: width, height: height))
            }
            try? await Task.sleep(for: .milliseconds(500))
        case "filmstripdrag":
            guard let window, let strip = filmStrip(in: window) else {
                print("debug-script: no film strip")
                break
            }
            dragFilmStripHandle(strip.handle, rest, in: window)
            try? await Task.sleep(for: .milliseconds(500))
        case "filmstripclick":
            guard let window, let index = Int(rest.first ?? "") else { break }
            guard let strip = filmStrip(in: window), let point = strip.windowPoint(ofCell: index) else {
                print("debug-script: film strip cell \(index) is not on screen")
                break
            }
            printHit(window, at: point)
            postClick(at: point, in: window)
            try? await Task.sleep(for: .milliseconds(400))
        case "doubleclick":
            if let window, let point = windowPoint(rest, in: window) {
                printHit(window, at: point)
                let types: [(NSEvent.EventType, Int)] = [(.leftMouseDown, 1), (.leftMouseUp, 1), (.leftMouseDown, 2), (.leftMouseUp, 2)]
                for (index, (type, count)) in types.enumerated() {
                    guard let event = NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: index + 1, clickCount: count,
                        pressure: type == .leftMouseDown ? 1 : 0) else { continue }
                    NSApp.postEvent(event, atStart: false)
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        case "optionscroll":
            // Synthetic scroll events have no window, so their location is wrong;
            // the factor and point go to the loupe's handler instead.
            if let window, rest.count == 3, let point = windowPoint(rest, in: window), let lines = Double(rest[2]),
               let scrollView = descendant(of: LoupeScrollView.self, in: window.contentView) {
                scrollView.onZoomScroll?(ScrollZoom.factor(deltaY: lines, precise: false, inverted: false), point)
                try? await Task.sleep(for: .milliseconds(200))
            }
        case "drag":
            if let window, rest.count == 4, let start = windowPoint(Array(rest.prefix(2)), in: window),
               let end = windowPoint(Array(rest.suffix(2)), in: window) {
                let steps = 8
                for step in 0...(steps + 1) {
                    let t = CGFloat(min(step, steps)) / CGFloat(steps)
                    let type: NSEvent.EventType = step == 0 ? .leftMouseDown : step > steps ? .leftMouseUp : .leftMouseDragged
                    let point = NSPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                    guard let event = NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: step + 1, clickCount: 1,
                        pressure: type == .leftMouseUp ? 0 : 1) else { continue }
                    NSApp.postEvent(event, atStart: false)
                    try? await Task.sleep(for: .milliseconds(30))
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        case "menupick":
            guard let (menu, index) = menuItem(rest) else { break }
            menu.performActionForItem(at: index)
            try? await Task.sleep(for: .milliseconds(300))
        case "menuhover":
            // Highlights an item as the pointer would, so its preview shows;
            // "end" closes the menu without a pick.
            if rest.first == "end" {
                if let menu = hoveredMenu { menu.delegate?.menuDidClose?(menu) }
                hoveredMenu = nil
            } else if let (menu, index) = menuItem(rest) {
                menu.delegate?.menu?(menu, willHighlight: menu.items[index])
                hoveredMenu = menuRoot
            }
            try? await Task.sleep(for: .milliseconds(600))
        case "menukey":
            // Posted keys are handled after this command returns, outside its
            // undo group; grouping by event, as for real keys, gives them one.
            model.undoManager.groupsByEvent = true
            for key in rest {
                send(key, posted: true)
                try? await Task.sleep(for: .milliseconds(150))
            }
            model.undoManager.groupsByEvent = false
        case "review":
            // As F; "print review" shows the layout.
            switch rest.first {
            case "off": model.exitReview()
            case "on": model.enterReview()
            // The toolbar's Grid segment, and ⌃⌘F (the window leaves full screen).
            case "grid": model.closeLoupe()
            case "leavefullscreen": model.windowObserver.window?.toggleFullScreen(nil)
            default: model.toggleReview()
            }
            try? await Task.sleep(for: .milliseconds(1500))
        case "hdr":
            model.showsHDR = rest.first != "off"
        case "metadata", "sidecars":
            await DebugMetadataCommands.run(verb, rest, model: model)
        case "adjust":
            await DebugAdjustCommands.run(rest, editor: model.editor)
        case "export":
            await DebugExportCommands.run(rest, model: model)
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
            case "import":
                let urls = rest.dropFirst().map { URL(fileURLWithPath: $0) }
                if let result = await model.importAdjustmentPresets(urls, showsSummary: false) {
                    let summary = LibraryModel.summary(of: result)
                    print("debug-script: \(summary.title)\n\(summary.message)")
                }
            case "export":
                // preset export <file> [name]: every preset, or the one named.
                let url = URL(fileURLWithPath: rest.dropFirst().first ?? "")
                let named = rest.dropFirst(2).joined(separator: " ")
                let presets = model.adjustmentPresets.filter { named.isEmpty || $0.name == named }
                do {
                    try model.writeAdjustmentPresets(presets, to: url)
                } catch {
                    print("debug-script: export failed: \(error)")
                }
            case "preview":
                if let preset = model.adjustmentPresets.first(where: { $0.name == name }) {
                    model.previewAdjustmentPreset(preset)
                    try? await Task.sleep(for: .milliseconds(600))
                }
            case "window":
                model.showsPresetSheet = true
                try? await Task.sleep(for: .milliseconds(500))
            case "windowshot":
                // A sheet on the library window; the snapshot shows the sheet.
                guard let window = NSApp.windows.first(where: { $0.attachedSheet != nil }) else {
                    print("debug-script: the presets sheet is not open")
                    break
                }
                WindowSnapshot.write(window, to: URL(fileURLWithPath: (name as NSString).expandingTildeInPath))
            case "summary":
                if let result = await model.importAdjustmentPresets(rest.dropFirst().map { URL(fileURLWithPath: $0) }) {
                    print("debug-script: imported \(result.imported.count)")
                }
                try? await Task.sleep(for: .milliseconds(500))
            case "apply":
                if let preset = model.adjustmentPresets.first(where: { $0.name == name }) { model.applyAdjustmentPreset(preset) }
            case "delete":
                if let preset = model.adjustmentPresets.first(where: { $0.name == name }) {
                    model.deleteAdjustmentPreset(preset)
                    try? await Task.sleep(for: .milliseconds(300))
                }
            default:
                print("debug-script: presets " + model.adjustmentPresets.map {
                    ($0.collection.isEmpty ? "" : "\($0.collection)/") + $0.name + " [\(PresetText.groups($0))]"
                }.joined(separator: ", "))
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
        case "editvalue":
            // Puts the keyboard in the value field of the inspector slider with this title.
            let title = rest.joined(separator: " ")
            if let row = window?.contentView.flatMap({ findSliderRow(titled: title, in: $0) }) {
                row.beginEditingValue()
            } else {
                print("debug-script: no slider titled \(title)")
            }
        case "sidebarsection":
            if let section = rest.first.flatMap(SidebarSection.init(rawValue:)) {
                model.setSidebarSection(section, shown: rest.dropFirst().first != "hide")
            }
            print("debug-script: hidden sections \(model.hiddenSidebarSections.map(\.rawValue).sorted())")
        case "menuitems":
            printMenuItems(containing: rest.joined(separator: " "))
        case "contextmenu":
            runContextMenu(rest)
            try? await Task.sleep(for: .milliseconds(300))
        case "menupress":
            pressMenuItem(titled: rest.joined(separator: " "))
            try? await Task.sleep(for: .milliseconds(300))
        case "accessibility":
            AccessibilityProbe.run(rest, in: window)
            try? await Task.sleep(for: .milliseconds(200))
        case "print":
            if rest.first == "review" {
                let window = model.windowObserver.window
                print("debug-script: review \(model.isReviewing) mode \(model.mode) sidebar \(model.showsSidebar) "
                      + "inspector \(model.showsInspector) fullscreen \(window?.styleMask.contains(.fullScreen) == true)")
            } else if rest.first == "loupe" {
                printLoupe(at: Array(rest.dropFirst()), model: model)
            } else if rest.first == "filmstrip" {
                let strip = window.flatMap(filmStrip(in:))
                print("debug-script: filmstrip setting \(model.showsFilmStrip) stored \(model.filmStripSize) shown \(strip != nil)"
                      + (strip.map { " " + $0.debugState } ?? "") + " fits \(model.loupeFitCount)")
                model.loupeFitCount = 0
            } else if rest.first == "metadata" {
                await DebugMetadataCommands.printSummary(model: model)
            } else {
                printState(rest.first ?? "", model: model)
            }
        case "quit":
            // An open sheet would keep the app from quitting; SwiftUI's close
            // through their bindings.
            model.showsExportSheet = false
            model.showsLookTableSheet = false
            model.showsPresetSheet = false
            try? await Task.sleep(for: .milliseconds(500))
            for window in NSApp.windows {
                if let sheet = window.attachedSheet { window.endSheet(sheet) }
            }
            QuitGuard.allowsQuit = true
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

    /// The menu of the menu button at `<x> <y>`, kept for `menuhover end`.
    private static var menuRoot: NSMenu?
    private static var hoveredMenu: NSMenu?

    /// The item at `<x> <y> <item>[/<sub>]`: the menu button there, then the
    /// item's path in its menu.
    private static func menuItem(_ words: [String]) -> (NSMenu, Int)? {
        guard let window, let point = windowPoint(words, in: window),
              let hit = window.contentView?.superview?.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, !(current is AppKitMenuButton.MenuPopUpButton) { view = current.superview }
        guard let button = view as? AppKitMenuButton.MenuPopUpButton, let menu = button.makeMenu?() else {
            print("debug-script: no menu button at that point")
            return nil
        }
        menuRoot = menu
        var target = menu
        let path = words.dropFirst(2).joined(separator: " ").split(separator: "/").map(String.init)
        for (depth, title) in path.enumerated() {
            guard let index = target.items.firstIndex(where: { $0.title == title }) else {
                print("debug-script: no menu item \(title)")
                return nil
            }
            if depth == path.count - 1 { return (target, index) }
            guard let submenu = target.items[index].submenu else { return nil }
            target = submenu
        }
        return nil
    }

    private static func windowPoint(_ words: [String], in window: NSWindow) -> NSPoint? {
        guard words.count >= 2, let x = Double(words[0]), let y = Double(words[1]) else { return nil }
        return NSPoint(x: x, y: window.frame.height - y)
    }

    /// A mouse down and up at a window point, through the event queue. Both
    /// at once: a control's tracking loop waits for the mouse up. SwiftUI
    /// buttons inside a scroll view ignore these synthetic clicks.
    private static func postClick(at point: NSPoint, in window: NSWindow) {
        for (index, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: index + 1, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }

    /// The handle's mouse methods with events at its zone, so a drag takes
    /// the path a real one does (without needing the app to be active).
    private static var heldDrag: NSPoint?

    private static func dragFilmStripHandle(_ handle: FilmStripHandleView, _ words: [String], in window: NSWindow) {
        func event(_ type: NSEvent.EventType, at point: NSPoint, clicks: Int = 1) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)
        }
        let start = handle.zoneCenterInWindow
        switch words.first {
        case "release":
            if let point = heldDrag, let up = event(.leftMouseUp, at: point) { handle.mouseUp(with: up) }
            heldDrag = nil
        case "reset":
            if let down = event(.leftMouseDown, at: start, clicks: 2) { handle.mouseDown(with: down) }
            if let up = event(.leftMouseUp, at: start, clicks: 2) { handle.mouseUp(with: up) }
        case let value?:
            guard let dy = Double(value) else { return }
            if let down = event(.leftMouseDown, at: start) { handle.mouseDown(with: down) }
            var point = start
            for step in 1...8 {
                point = NSPoint(x: start.x, y: start.y + CGFloat(dy) * CGFloat(step) / 8)
                if let drag = event(.leftMouseDragged, at: point) { handle.mouseDragged(with: drag) }
            }
            if words.dropFirst().first == "hold" {
                heldDrag = point
            } else if let up = event(.leftMouseUp, at: point) {
                handle.mouseUp(with: up)
            }
        case nil:
            break
        }
    }

    private static func filmStrip(in window: NSWindow) -> FilmStripController? {
        descendant(of: FilmStripCollectionView.self, in: window.contentView)?.controller
    }

    private static func printLoupe(at words: [String], model: LibraryModel) {
        guard let window, let scrollView = descendant(of: LoupeScrollView.self, in: window.contentView) else {
            print("debug-script: loupe mode \(model.mode) no canvas")
            return
        }
        let visible = scrollView.documentVisibleRect
        var line = String(format: "debug-script: loupe mode %@ magnification %.3f visible %.0f,%.0f %.0fx%.0f",
                          "\(model.mode)", scrollView.magnification, visible.minX, visible.minY, visible.width, visible.height)
        if let point = windowPoint(words, in: window), let document = scrollView.documentView {
            let imagePoint = document.convert(point, from: nil)
            line += String(format: " point %.1f,%.1f", imagePoint.x, imagePoint.y)
        }
        print(line)
    }

    private static func descendant<V: NSView>(of type: V.Type, in view: NSView?) -> V? {
        guard let view else { return nil }
        if let match = view as? V { return match }
        for subview in view.subviews {
            if let match = descendant(of: type, in: subview) { return match }
        }
        return nil
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

    /// `contextmenu cell <n> | loupe | slider <title> [<item>[/<sub>]]`: prints the
    /// context menu a right-click there gets, or runs one of its items.
    private static func runContextMenu(_ words: [String]) {
        guard let window, let root = window.contentView else { return }
        var view: NSView?
        var point = NSPoint.zero
        var path = Array(words.dropFirst())
        switch words.first {
        case "cell":
            guard let index = path.first.flatMap(Int.init), let grid = descendant(of: PhotoCollectionView.self, in: root),
                  let frame = grid.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { break }
            path.removeFirst()
            view = grid
            point = grid.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
        case "loupe":
            view = descendant(of: LoupeHostView.self, in: root)
            point = view.map { $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) } ?? .zero
        case "slider":
            let title = path.first ?? ""
            path.removeFirst()
            view = findSliderRow(titled: title, in: root)
            point = view.map { $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) } ?? .zero
        default:
            break
        }
        guard let view, let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                         clickCount: 1, pressure: 1),
              let menu = view.menu(for: event) else {
            print("debug-script: no context menu")
            return
        }
        let target = path.joined(separator: " ").split(separator: "/").map(String.init)
        if target.isEmpty {
            func show(_ menu: NSMenu, _ prefix: String) {
                for item in menu.items {
                    print("debug-script: context \(item.isSeparatorItem ? "—" : prefix + item.title)")
                    if let sub = item.submenu { show(sub, prefix + item.title + "/") }
                }
            }
            show(menu, "")
            return
        }
        var current = menu
        for (depth, title) in target.enumerated() {
            guard let index = current.items.firstIndex(where: { $0.title == title }) else {
                print("debug-script: no context item \(title)")
                return
            }
            if depth == target.count - 1 {
                current.performActionForItem(at: index)
            } else if let sub = current.items[index].submenu {
                current = sub
            }
        }
    }

    /// Runs the enabled main menu item with this title, as a click would.
    private static func pressMenuItem(titled title: String) {
        func find(_ menu: NSMenu?) -> (NSMenu, Int)? {
            guard let menu else { return nil }
            // As if opened, like `menuitems`: SwiftUI may refresh its items only then.
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.delegate?.menuWillOpen?(menu)
            menu.update()
            defer { menu.delegate?.menuDidClose?(menu) }
            for (index, item) in menu.items.enumerated() {
                if item.title == title { return (menu, index) }
                if let found = find(item.submenu) { return found }
            }
            return nil
        }
        guard let (menu, index) = find(NSApp.mainMenu) else {
            print("debug-script: no menu item \(title)")
            return
        }
        guard menu.items[index].isEnabled else {
            print("debug-script: menu item \(title) is disabled")
            return
        }
        menu.performActionForItem(at: index)
    }

    private static func findSliderRow(titled title: String, in view: NSView) -> SliderRow? {
        if let row = view as? SliderRow, row.title == title { return row }
        for subview in view.subviews {
            if let row = findSliderRow(titled: title, in: subview) { return row }
        }
        return nil
    }

    /// Main menu items whose title contains `text`: title, key equivalent and
    /// whether they are enabled, as AppKit sees them.
    private static func printMenuItems(containing text: String) {
        func visit(_ menu: NSMenu?, path: String) {
            // As if opened: SwiftUI may refresh its items only then.
            if let menu {
                menu.delegate?.menuNeedsUpdate?(menu)
                menu.delegate?.menuWillOpen?(menu)
                menu.update()
            }
            defer { if let menu { menu.delegate?.menuDidClose?(menu) } }
            for item in menu?.items ?? [] where !item.isSeparatorItem {
                let itemPath = path.isEmpty ? item.title : path + "/" + item.title
                if text.isEmpty || item.title.localizedCaseInsensitiveContains(text) {
                    var modifiers = ""
                    let mask = item.keyEquivalentModifierMask
                    if mask.contains(.control) { modifiers += "ctrl+" }
                    if mask.contains(.option) { modifiers += "opt+" }
                    if mask.contains(.shift) { modifiers += "shift+" }
                    if mask.contains(.command) { modifiers += "cmd+" }
                    let key = item.keyEquivalent.isEmpty ? "" : " key \(modifiers)\(item.keyEquivalent.debugDescription)"
                    print("debug-script: menu \(itemPath)\(key) \(item.isEnabled ? "enabled" : "disabled")"
                          + (item.state == .on ? " checked" : ""))
                }
                if let submenu = item.submenu { visit(submenu, path: itemPath) }
            }
        }
        visit(NSApp.mainMenu, path: "")
    }

    private static func printButtons(in view: NSView, window: NSWindow) {
        if let button = view as? NSControl, button is NSButton || button is NSSegmentedControl,
           !view.isHiddenOrHasHiddenAncestor {
            let frame = button.convert(button.bounds, to: nil)
            let title = (button as? NSButton)?.title ?? ""
            let name = title.isEmpty ? (button.toolTip ?? "") : title
            print("debug-script: button '\(name)' at \(Int(frame.midX)),\(Int(window.frame.height - frame.midY))"
                  + " width \(Int(frame.width)) \(type(of: button))")
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
        case "title":
            print("debug-script: title \(model.windowTitle) | \(model.windowSubtitle) | rating \(model.ratingRule) flag \(model.flagRule)"
                  + " search '\(model.searchText)' sort \(model.sort.key.rawValue) \(model.sort.ascending ? "asc" : "desc")")
        case "activity":
            let jobs = ActivityToolbarItem.jobs(model).map {
                $0.title + ($0.toolbarTitle.map { " (toolbar: \($0))" } ?? "") + ($0.detail.map { " | " + $0 } ?? "")
            }
                .joined(separator: "; ")
            print("debug-script: activity visible \(ActivityToolbarItem.isVisible(model)) jobs [\(jobs)] unseen \(model.activity.unseenCount)"
                  + " warning \(model.activity.unseenHasWarning) last \(model.activity.messages.last.map { "[\($0.title ?? "-")] \($0.text)" } ?? "-")")
        case "grid":
            if let scroll = window.flatMap({ descendant(of: PhotoCollectionView.self, in: $0.contentView) })?.enclosingScrollView {
                print("debug-script: grid inset top \(scroll.contentInsets.top) visible \(scroll.documentVisibleRect.integral)"
                      + " automatic \(scroll.automaticallyAdjustsContentInsets)")
            }
        case "appearance":
            for window in NSApp.windows where window.isVisible {
                print("debug-script: appearance '\(window.title)' set \(window.appearance?.name.rawValue ?? "nil")"
                      + " effective \(window.effectiveAppearance.name.rawValue)")
            }
        case "announcement":
            print("debug-script: announcement \(AccessibilityText.lastAnnouncement ?? "-")")
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
            // Separate pieces: as one expression, Swift 6.2 gives up type-checking it.
            let counts: [String] = model.sidebarCounts.map { "\(model.title(for: $0.key))=\($0.value)" }.sorted()
            let albums: String = model.albums.map { "\($0.album.name)=\($0.count)" }.joined(separator: " ")
            let months: String = model.captureMonths.map { "\($0.id)=\($0.count)" }.joined(separator: " ")
            print("debug-script: albums \(albums) | months \(months) | \(counts.joined(separator: " ")) | showing \(model.items.count)")
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
