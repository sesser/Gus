import AppKit
import PhotoCore
import PhotoUI

/// The debug script's Copy Adjustments commands (copy-adjustments-selective
/// design §11; `DebugScript` lists them):
///
///     copyadjust                   (copies the focused photo with the sheet's defaults, no sheet: ⇧⌘C then Return)
///     copyadjust all | <name>…     (copies exactly those items, no sheet; names are `crop` and the groups'
///                                   stored names: light, colorGrade, spots, …)
///     copyadjust sheet             (Adjust ▸ Copy Adjustments…: opens the real sheet, waits for it, prints it)
///     copyadjust sheet check|uncheck <name>…|all
///                                  (sets boxes through the sheet's state, as Check All / Uncheck All do for all)
///     copyadjust sheet click <name>
///                                  (clicks a row's real check box, as the mouse or Space does: a heading by its
///                                   section's stored name, develop, details, lens, effects; then prints the sheet)
///     copyadjust sheet mouse <name> box|label
///                                  (a mouse click through the event queue on the row's box, or on its name
///                                   40 pt past the box: the row's own hit area; then prints the sheet)
///     copyadjust sheet confirm|cancel
///                                  (presses Copy or Cancel; prints the clipboard)
///     print copysheet              (each row: name, box, trailing text, enabled; Copy, the note, the sheet's size
///                                   against its ideal and the list's content against what it shows)
///     print clipboard              (the copied items by name, or none)
///     print messages               (every Activity message, oldest first, warnings marked)
///     print stacks                 (each photo shown: its saved operations after pending writes, off ones marked,
///                                   with the crop's rectangle, the spot count and the exposure, contrast and
///                                   Color Grading shadow amount)
@MainActor
enum DebugCopyAdjustmentsCommands {
    static func run(_ words: [String], model: LibraryModel) async {
        guard words.first == "sheet" else {
            await copyWithoutSheet(words, model: model)
            return
        }
        let names = Array(words.dropFirst(2))
        switch words.dropFirst().first {
        case nil:
            // A sheet closed just before still counts as up until it has gone.
            for _ in 0..<120 where !model.canCopyAdjustments {
                try? await Task.sleep(for: .milliseconds(25))
            }
            model.openCopySheet()
            for _ in 0..<200 where model.copySheet == nil || model.copySheetRead != nil {
                try? await Task.sleep(for: .milliseconds(25))
            }
            // The sheet's window is laid out after it is attached.
            try? await Task.sleep(for: .milliseconds(600))
            printSheet(model)
        case "check", "uncheck":
            guard let sheet = model.copySheet else { return print("debug-script: copyadjust sheet: no sheet") }
            let on = words.dropFirst().first == "check"
            if names == ["all"] || names == ["none"] {
                if on && names == ["all"] { sheet.state.checkAll() } else { sheet.state.uncheckAll() }
            } else {
                guard let items = items(names) else { return }
                sheet.state.set(items, on)
            }
            try? await Task.sleep(for: .milliseconds(200))
            printSheet(model)
        case "click":
            await click(names.first ?? "", model: model)
        case "mouse":
            await mouse(names.first ?? "", at: names.dropFirst().first ?? "box", model: model)
        case "confirm":
            model.confirmCopySheet()
            try? await Task.sleep(for: .milliseconds(500))
            printClipboard(model)
            print("debug-script: copyadjust sheet shown \(model.showsCopySheet)")
        case "cancel":
            model.cancelCopySheet()
            try? await Task.sleep(for: .milliseconds(500))
            printClipboard(model)
            print("debug-script: copyadjust sheet shown \(model.showsCopySheet)")
        default:
            print("debug-script: copyadjust sheet: unknown \(words.dropFirst().first ?? "")")
        }
    }

    /// `copyadjust` and `copyadjust <name>…`: the focused photo's values read
    /// as the sheet reads them, no sheet shown.
    private static func copyWithoutSheet(_ names: [String], model: LibraryModel) async {
        guard let item = model.focusedItem, !item.isVideo else { return print("debug-script: copyadjust: no photo") }
        guard let source = await model.copySource(item) else { return print("debug-script: copyadjust: unreadable") }
        var state = CopySheetState(source: source)
        if names == ["all"] {
            state.checkAll()
        } else if !names.isEmpty {
            guard let items = items(names) else { return }
            state.uncheckAll()
            state.set(items, true)
        }
        // As the sheet's Copy: nothing checked copies nothing (R4).
        guard state.canCopy else { return print("debug-script: copyadjust: nothing checked; clipboard unchanged") }
        model.copiedAdjustments = state.copied(from: model.sourceURL(for: item))
        printClipboard(model)
    }

    private static func items(_ names: [String]) -> [CopyItem]? {
        let items = names.compactMap(CopyItem.init(name:))
        guard items.count == names.count else {
            print("debug-script: copyadjust: unknown item in \(names.joined(separator: " "))")
            return nil
        }
        return items
    }

    /// The sheet's rows as the boxes show top to bottom: a heading, then its groups.
    private static var entries: [(name: String, row: CopyRow?, item: CopyItem?)] {
        CopyRow.all.flatMap { row -> [(name: String, row: CopyRow?, item: CopyItem?)] in
            guard row.isHeading, case .section(let section) = row else {
                return [(row.items[0].name, row, nil)]
            }
            return [(section.rawValue, row, nil)] + row.items.map { ($0.name, nil, $0) }
        }
    }

    /// The sheet's check boxes, top to bottom.
    private static func checkboxes() -> [NSButton] {
        guard let window = DebugMergeCommands.sheetWindow() else { return [] }
        return DebugMergeCommands.views(of: NSButton.self, in: window.contentView)
            .filter(\.allowsMixedState)
            .sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
    }

    private static func click(_ name: String, model: LibraryModel) async {
        let boxes = checkboxes()
        let entries = entries
        guard boxes.count == entries.count, let index = entries.firstIndex(where: { $0.name == name }) else {
            print("debug-script: copyadjust sheet click: \(boxes.count) boxes for \(entries.count) rows, or no row \(name)")
            return
        }
        boxes[index].performClick(nil)
        try? await Task.sleep(for: .milliseconds(300))
        printSheet(model)
    }

    private static func mouse(_ name: String, at part: String, model: LibraryModel) async {
        let boxes = checkboxes()
        guard let window = DebugMergeCommands.sheetWindow(), boxes.count == entries.count,
              let index = entries.firstIndex(where: { $0.name == name }) else {
            return print("debug-script: copyadjust sheet mouse: no sheet or no row \(name)")
        }
        let frame = boxes[index].convert(boxes[index].bounds, to: nil)
        let point = NSPoint(x: part == "label" ? frame.maxX + 40 : frame.midX, y: frame.midY)
        for (number, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: number + 1, clickCount: 1,
                                                 pressure: type == .leftMouseDown ? 1 : 0) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
        try? await Task.sleep(for: .milliseconds(400))
        print("debug-script: copyadjust sheet mouse \(name) \(part) at \(Int(point.x)),\(Int(point.y))"
              + " hit \(window.contentView?.hitTest(point).map { String(describing: type(of: $0)) } ?? "-")")
        printSheet(model)
    }

    static func printSheet(_ model: LibraryModel) {
        guard let sheet = model.copySheet else {
            print("debug-script: copysheet shown \(model.showsCopySheet) none; canCopy \(model.canCopyAdjustments)")
            return
        }
        let state = sheet.state
        print("debug-script: copysheet title '\(CopyAdjustmentsText.title)' from '\(CopyAdjustmentsText.source(PhotoName.display(sheet.item)))'"
              + " noAdjustmentsNote \(state.sourceHasNoChanges) canCopyAdjustments \(model.canCopyAdjustments)")
        let boxes = checkboxes()
        for (index, entry) in entries.enumerated() {
            let check: CopyCheck = if let row = entry.row { state.state(of: row) } else {
                state.isChecked(entry.item!) ? .on : .off
            }
            let item = entry.item ?? (entry.row?.isHeading == false ? entry.row?.items.first : nil)
            let title = item.map(CopyAdjustmentsText.title) ?? entry.row.map(CopyAdjustmentsText.title) ?? ""
            let note = item.flatMap(state.note(for:)).map(CopyAdjustmentsText.note) ?? "-"
            let box = boxes.indices.contains(index) ? boxes[index] : nil
            let shown = box.map { $0.state == .on ? "on" : $0.state == .mixed ? "mixed" : "off" } ?? "?"
            let indent = entry.item == nil ? "" : "  "
            print("debug-script: copysheet row \(indent)\(title) [\(entry.name)] \(check) box \(shown)"
                  + " enabled \(box?.isEnabled ?? false) note '\(note)' ax '\(box?.accessibilityLabel() ?? "-")'")
        }
        print("debug-script: copysheet copy \(state.canCopy ? "on" : "off")"
              + (state.canCopy ? "" : " note '\(CopyAdjustmentsText.checkSomething)'") + " boxes \(boxes.count)")
        print("debug-script: copysheet metrics \(metrics(model))")
    }

    /// The sheet's size against its ideal, and the list's content against what it shows.
    private static func metrics(_ model: LibraryModel) -> String {
        guard let window = DebugMergeCommands.sheetWindow() else { return "sheet not attached" }
        let list = DebugMergeCommands.views(of: NSScrollView.self, in: window.contentView)
            .max { $0.frame.height < $1.frame.height }
        let content = list?.documentView?.frame.height ?? 0
        let shown = list?.contentView.bounds.height ?? 0
        let boxes = checkboxes()
        let boxWidth = boxes.first.map { Int($0.frame.width.rounded()) } ?? 0
        return "sheet \(Int(window.frame.width))x\(Int(window.frame.height)) (ideal \(Int(CopySheetMetrics.idealHeight(withNote: model.copySheet?.state.sourceHasNoChanges == true, window: model.copySheet?.windowHeight))))"
            + " list content \(Int(content.rounded())) shown \(Int(shown.rounded())) scrolls \(content > shown + 0.5)"
            + " box width \(boxWidth) parent window \(Int(window.sheetParent?.frame.height ?? 0))"
    }

    static func printStacks(_ model: LibraryModel) async {
        let items = model.items
        guard let stored = try? await model.writes.savedEditStacks(forVersions: items.map(\.versionID), in: model.catalog) else {
            return print("debug-script: stacks unreadable")
        }
        for item in items {
            guard let stack = stored.stacks[item.versionID] else {
                print("debug-script: stack \(PhotoName.display(item)) \(stored.unreadable[item.versionID] == nil ? "none" : "unreadable")")
                continue
            }
            let values = Adjustments(stack: stack)
            let kinds = stack.operations.map { $0.kind.rawValue + ($0.isEnabled ? "" : "(off)") }
            let crop = values.crop.rect.map { String(format: "%.2f,%.2f,%.2f,%.2f", $0.x, $0.y, $0.width, $0.height) } ?? "-"
            print("debug-script: stack \(PhotoName.display(item)) [\(kinds.joined(separator: " "))] crop \(crop)"
                  + " turns \(values.crop.quarterTurns) spots \(values.spots.spots.count) ev \(values.exposure.ev)"
                  + " contrast \(values.tone.contrast) gradeShadows \(values.colorGrade.shadows.amount)")
        }
    }

    /// Every Activity message, oldest first.
    static func printMessages(_ model: LibraryModel) {
        for message in model.activity.messages {
            print("debug-script: message [\(message.title ?? "-")]\(message.isWarning ? " warning" : "") \(message.text)")
        }
    }

    static func printClipboard(_ model: LibraryModel) {
        guard let copied = model.copiedAdjustments else { return print("debug-script: clipboard none") }
        let names = CopyItem.all.filter(copied.items.contains).map(\.name)
        print("debug-script: clipboard \(names.joined(separator: " ")) announcement '\(CopyAdjustmentsText.announcement(copied.summary))'")
    }
}
