import AppKit
import PhotoCore

/// The debug script's commands for the Lens heading
/// (docs/features/chromatic-aberration/design.md §15 "Debug-script hooks").
@MainActor
enum DebugLensCommands {
    private static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.className.contains("Window") }
    }

    private static func loupe() -> LoupeController? {
        guard let root = window?.contentView else { return nil }
        func find(_ view: NSView) -> LoupeHostView? {
            if let host = view as? LoupeHostView { return host }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        return find(root)?.controller
    }

    /// `adjust fringe …` and `adjust align …`.
    static func adjust(_ name: String, _ words: [String], editor: AdjustmentEditor) async {
        let verb = words.first ?? ""
        let slot = Int(words.dropFirst().first ?? "") ?? 1
        switch (name, verb) {
        case ("fringe", "pick"):
            let numbers = words.dropFirst(2).compactMap(Double.init)
            guard numbers.count == 2 else { break }
            if editor.pickingFringeSlot != slot { editor.armFringePicker(slot) }
            let before = editor.adjustments
            let requested = CGPoint(x: numbers[0], y: numbers[1])
            let geometry = loupe()?.clickGeometry(atUnit: requested) ?? (unit: requested, devicePixelsAcross: 2560)
            editor.pickFringe(at: geometry.unit, devicePixelsAcross: geometry.devicePixelsAcross)
            for _ in 0..<400 where editor.adjustments == before && !editor.fringePickRefused {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(200))
        case ("fringe", "fill"):
            guard let listed = CommonFringeColor(name: words.dropFirst(2).first ?? "") else { break }
            editor.fillFringe(slot, with: listed)
        case ("fringe", "clear"):
            editor.clearFringe(slot)
        case ("fringe", "tolerance"):
            guard let value = Double(words.dropFirst(2).first ?? "") else { break }
            editor.setFringeTolerance(slot, value, phase: .committed)
        case ("align", "auto"):
            editor.setAutomaticAlignment(words.dropFirst().first != "off")
            try? await Task.sleep(for: .milliseconds(50))
            while editor.isMeasuringAlignment { try? await Task.sleep(for: .milliseconds(50)) }
        case ("align", "redcyan"), ("align", "blueyellow"):
            guard let value = Double(words.dropFirst().first ?? "") else { break }
            if verb == "redcyan" {
                editor.setAlignment(red: value, title: LensText.redCyan, phase: .committed)
            } else {
                editor.setAlignment(blue: value, title: LensText.blueYellow, phase: .committed)
            }
        default:
            print("debug-script: unknown adjust \(name) \(verb)")
        }
    }

    /// `magnifier level <percent>|up|down`, `magnifier move <x> <y>`: neither changes a photo.
    static func magnifier(_ words: [String], model: LibraryModel) {
        switch words.first {
        case "level":
            switch words.dropFirst().first {
            case "up": model.stepPixelMagnifierLevel(up: true)
            case "down": model.stepPixelMagnifierLevel(up: false)
            default: model.setPixelMagnifierLevel(PixelMagnifierLevel(stored: Int(words.dropFirst().first ?? "") ?? 0))
            }
        case "resignkeyboard":
            // Takes the keyboard away from the loupe, as tabbing to an inspector control does.
            NSApp.mainWindow?.makeFirstResponder(nil)
            print("debug-script: first responder \(String(describing: NSApp.mainWindow?.firstResponder))")
        case "hideoriginal", "restoreoriginal":
            // DR22: takes the focused photo's file away, or puts it back (scratch libraries only).
            guard let item = model.focusedItem, let url = model.sourceURL(for: item) else { break }
            let hidden = url.appendingPathExtension("hidden")
            let (from, to) = words.first == "hideoriginal" ? (url, hidden) : (hidden, url)
            do {
                try FileManager.default.moveItem(at: from, to: to)
            } catch {
                print("debug-script: \(error)")
            }
        case "move":
            let numbers = words.dropFirst().compactMap(Double.init)
            guard numbers.count == 2 else { break }
            loupe()?.moveMagnifierPointer(toUnit: CGPoint(x: numbers[0], y: numbers[1]))
        default:
            print("debug-script: unknown magnifier command")
        }
    }

    /// `print magnifier [pixels]`: what the magnifier shows.
    static func printMagnifier(all: Bool, model: LibraryModel) {
        guard let state = loupe()?.magnifierState else {
            print("debug-script: magnifier no loupe")
            return
        }
        let level = model.pixelMagnifierLevel
        let held = model.editor.samplePixelsByteCount
        print("debug-script: magnifier visible \(state.isVisible) level \(level.rawValue) active \(model.isPixelMagnifierActive)"
              + " ready \(state.isReady) heldBytes \(held) backing \(state.backing)")
        guard state.isVisible else { return }
        let side = (state.placement.isLeftOfPointer ? "left" : "right") + " " + (state.placement.isAbovePointer ? "above" : "below")
        print("debug-script: magnifier placement \(side) frame \(state.frame)")
        guard let reading = state.reading, let picture = state.picture else {
            print("debug-script: magnifier values - - - -")
            return
        }
        let maskPoint = model.editor.fringeMagnifierTool?.maskPoint(of: reading.pixel)
        let point = maskPoint.map { String(format: "%.6f,%.6f", $0.x, $0.y) } ?? "-"
        print("debug-script: magnifier outlined \(reading.pixel.x),\(reading.pixel.y) maskPoint \(point)"
              + " R \(reading.values.r) G \(reading.values.g) B \(reading.values.b) L \(reading.values.l)")
        var line2 = reading.note ?? ""
        if case .refused(let text) = reading.verdict { line2 = text }
        let drawn = picture.cells.compactMap(\.self).count
        print("debug-script: magnifier line2 '\(PixelMagnifierText.title(level)) | \(line2)' verdict \(reading.verdict)"
              + " devicePerPhoto \(picture.cellSize) grid \(level.showsGrid) cells \(picture.cellsAcross) drawn \(drawn)")
        guard all else { return }
        for row in 0..<picture.cellsAcross {
            let middle = picture.cellsAcross / 2
            let line: [String] = (0..<picture.cellsAcross).map { column in
                let x = picture.center.x + column - middle, y = picture.center.y + row - middle
                guard let value = picture.cells[row * picture.cellsAcross + column] else { return "\(x),\(y):-" }
                return "\(x),\(y):\(value.r)/\(value.g)/\(value.b)"
            }
            print("debug-script: magnifier pixels " + line.joined(separator: " "))
        }
    }

    /// `fringemap on|off|toggle` and `fringearm 1|2|off`: neither changes a photo.
    static func run(_ verb: String, _ words: [String], model: LibraryModel) {
        switch verb {
        case "fringemap":
            switch words.first {
            case "on": model.setFringeMap(true, from: .menu)
            case "off": model.setFringeMap(false, from: .menu)
            default: model.toggleFringeMap(from: .menu)
            }
        default:
            if let slot = Int(words.first ?? "") {
                if model.editor.pickingFringeSlot != slot { model.editor.armFringePicker(slot) }
            } else {
                model.editor.armFringePicker(nil)
            }
        }
    }

    /// Listing, and Pick from Photo, change nothing: no undo group for them.
    static func contextMenuChangesNothing(_ words: [String]) -> Bool {
        guard words.first == "contextmenu", words.dropFirst().first == "fringe" else { return false }
        let item = words.dropFirst(3).joined(separator: " ")
        return item.isEmpty || item == LensText.pickFromPhoto
    }

    /// `contextmenu fringe <slot> [<item>]`: the row's context menu, from the same entries.
    static func contextMenu(_ words: [String], model: LibraryModel) {
        let slot = Int(words.first ?? "") ?? 1
        let entries = FringeSlotRow.entries(model: model, slot: slot)
        let title = words.dropFirst().joined(separator: " ")
        guard !title.isEmpty else {
            let listed = entries.map { entry -> String in
                switch entry.kind {
                case .header: "[header \(entry.title)]"
                case .separator: "—"
                case .item: "\(entry.title)\(entry.isEnabled ? "" : " (disabled)")"
                }
            }
            print("debug-script: contextmenu fringe \(slot) [\(listed.joined(separator: " | "))]")
            return
        }
        guard let entry = entries.first(where: { $0.kind == .item && $0.title == title }) else {
            print("debug-script: contextmenu fringe \(slot) has no item \(title)")
            return
        }
        guard entry.isEnabled else {
            print("debug-script: contextmenu fringe \(slot) item \(title) is disabled")
            return
        }
        entry.action()
    }

    static func printState(model: LibraryModel) {
        let editor = model.editor
        let fringes = editor.adjustments.colorFringes
        for slot in [1, 2] {
            if let fill = fringes[slot: slot] {
                let c = fill.color
                let swatch = editor.fringeSwatches[slot].map { String(format: "%.4f,%.4f,%.4f", $0.x, $0.y, $0.z) } ?? "-"
                print("debug-script: fringe slot \(slot) color \(String(format: "%.4f,%.4f,%.4f", c.x, c.y, c.z))"
                      + " name \(LensText.hueName(c)) tolerance \(fill.tolerance) swatch \(swatch)")
            } else {
                print("debug-script: fringe slot \(slot) none")
            }
            let menu = FringeSlotRow.entries(model: model, slot: slot).filter { $0.kind != .separator }.map {
                $0.kind == .header ? "[\($0.title)]" : "\($0.title)\($0.isEnabled ? "" : " (disabled)")"
            }
            print("debug-script: fringe slot \(slot) menu [\(menu.joined(separator: " | "))]")
        }
        let sample = editor.lastFringeSample.map {
            String(format: "%.4f,%.4f %@", $0.point.x, $0.point.y, $0.refused ? "refused" : "picked")
        } ?? "-"
        let cursor = editor.pickingFringeSlot != nil ? "crosshair" : "arrow"
        print("debug-script: fringe picking \(editor.pickingFringeSlot.map(String.init) ?? "none") lastSample \(sample)"
              + " cursor \(cursor) canPick \(editor.canPickFringe) refiningPhoto \(editor.isRefiningPickPreview)")
        print("debug-script: fringe caption '\(LensText.fringeCaption(editor))' unreadable \(editor.fringePixelsUnreadable)")
        let shown = editor.shownFringeMap
        print("debug-script: fringe map asked \(editor.showsFringeMap) onScreen \(shown != nil)"
              + " badge '\(shown.map(LensText.badge) ?? "-")' legend '\(shown.map(LensText.legend) ?? "-")'"
              + " refining \(editor.isRefiningSharpeningMap && shown != nil) canShow \(model.canShowFringeMap)"
              + " suspended overlay \(editor.sharpeningMap.suspendedOverlay) original \(editor.sharpeningMap.suspendedOriginal)"
              + " content \(editor.currentContent)")
        let alignment = editor.adjustments.colorAlignment
        print("debug-script: fringe alignment automatic \(alignment.automatic) measuring \(editor.isMeasuringAlignment)"
              + " red \(alignment.red) blue \(alignment.blue) on \(editor.adjustments.isEnabled(.colorAlignment))"
              + " caption '\(LensText.alignmentCaption(LensText.alignmentState(of: editor)))'")
    }
}
