import AppKit
import PhotoCore

/// The `import …` commands of `--debug-script`, shared by the library app and
/// the standalone importer:
///
///     import source <path> | dest <path> | job <text> | delete on|off | eject on|off
///            | videos on|off (waits) | rescan (waits) | toggle <index of a shown shot>
///            | accessibility <role>|any [<n> press|<action name>] (see AccessibilityProbe)
///            | run (waits) | start (does not wait) | close (the window) | terminate (as ⌘Q)
///            | alert [<button title>] (prints the window's alert, or presses a button) | confirm yes|no | snapshot <file> | print
///            | template folder|file|project <text> | tokens … (see TemplateFieldProbe)
///            | grid (each cell: name, checked, focus) | key left|right|up|down|space|return (to the grid)
///            | contextmenu <index> [<item title>] | options on|off | duplicates on|off | gridshot <png> (the grid alone)
///            | optionsshot <png> (the options inspector's content)
@MainActor
public enum ImportDebugCommands {
    /// Runs one command (the words after "import"). Returns false for a command
    /// it does not know, so the caller can try its own.
    @discardableResult
    public static func run(_ words: [String], model: CardImportModel, window: NSWindow?) async -> Bool {
        let argument = words.dropFirst().joined(separator: " ")
        switch words.first {
        case "source":
            model.source = ImportSource.describe(URL(fileURLWithPath: argument))
            await waitForScan(model)
        case "videos":
            model.includesVideos = argument == "on"
            await waitForScan(model)
        case "rescan":
            model.rescan(keepingPicks: true)
            await waitForScan(model)
        case "toggle":
            guard let index = Int(argument), model.visibleShots.indices.contains(index) else { return false }
            model.click(model.visibleShots[index], extend: false)
        case "dest":
            model.destination = URL(fileURLWithPath: argument)
        case "job":
            model.jobCode = argument
        case "template":
            let text = words.dropFirst(2).joined(separator: " ")
            switch words.dropFirst().first {
            case "folder": model.folderTemplate = text
            case "file": model.fileTemplate = text
            case "project": model.projectNameTemplate = text
            default: return false
            }
            try? await Task.sleep(for: .milliseconds(200))
        case "tokens":
            TemplateFieldProbe.run(Array(words.dropFirst()), in: window)
        case "delete":
            model.deletesOriginals = argument == "on"
        case "eject":
            model.ejectsWhenDone = argument == "on"
        case "run":
            model.startImport()
            try? await Task.sleep(for: .milliseconds(100))
            while model.isImporting { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(500))
        case "start":
            // As Import N Photos, without waiting for the copy.
            model.startImport()
            try? await Task.sleep(for: .milliseconds(300))
        case "close":
            window?.performClose(nil)
            try? await Task.sleep(for: .milliseconds(600))
        case "terminate":
            // As ⌘Q, asking first when a job runs (QuitGuard). Later: terminate
            // waits in a run loop of its own for the answer, and the script
            // has to go on to give it.
            DispatchQueue.main.async { NSApp.terminate(nil) }
            try? await Task.sleep(for: .milliseconds(600))
        case "alert":
            // The alert on the window: title, message and buttons; or press one.
            // On this window, or (a quit alert in the library app) on another.
            guard let sheet = window?.attachedSheet ?? NSApp.windows.lazy.compactMap(\.attachedSheet).first,
                  let alertView = sheet.contentView else {
                print("debug-script: import alert: none")
                return true
            }
            let buttons = buttons(in: alertView)
            if argument.isEmpty {
                let texts = textFields(in: alertView).map(\.stringValue).filter { !$0.isEmpty }
                print("debug-script: import alert \(texts.joined(separator: " | ")) buttons [\(buttons.map { "\($0.title) key \($0.keyEquivalent.debugDescription)" }.joined(separator: ", "))]")
            } else if let button = buttons.first(where: { $0.title == argument }) {
                button.performClick(nil)
                try? await Task.sleep(for: .milliseconds(600))
            }
        case "confirm":
            model.confirmDeletion(argument == "yes")
            try? await Task.sleep(for: .seconds(1))
        case "snapshot":
            if let window { WindowSnapshot.write(window, to: URL(fileURLWithPath: argument)) }
        case "accessibility":
            AccessibilityProbe.run(Array(words.dropFirst()), in: window)
            try? await Task.sleep(for: .milliseconds(200))
        case "print":
            printState(model)
        case "grid":
            ImportGridProbe.printGrid(in: window)
        case "key":
            ImportGridProbe.send(argument, in: window)
            try? await Task.sleep(for: .milliseconds(150))
        case "contextmenu":
            ImportGridProbe.contextMenu(Array(words.dropFirst()), in: window)
        case "duplicates":
            model.showsDuplicates = argument == "on"
            try? await Task.sleep(for: .milliseconds(300))
        case "options":
            model.showsOptions = argument != "off"
            try? await Task.sleep(for: .milliseconds(400))
        case "menukey":
            // ⌘-keys sent through the app, which routes them as real ones (needs
            // the app active, see CLAUDE.md).
            guard let window else { return false }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(300))
            var flags: NSEvent.ModifierFlags = [.command]
            var key = argument
            if key.hasPrefix("opt+") { flags.insert(.option); key.removeFirst(4) }
            if key.hasPrefix("shift+") { flags.insert(.shift); key.removeFirst(6) }
            let codes: [String: UInt16] = ["i": 34, "a": 0, "o": 31, "r": 15]
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil,
                                                   characters: key, charactersIgnoringModifiers: key,
                                                   isARepeat: false, keyCode: codes[key] ?? 0)
                else { return false }
                NSApp.sendEvent(event)
            }
            try? await Task.sleep(for: .milliseconds(300))
            print("debug-script: import menukey \(argument) key window \(NSApp.keyWindow === window) "
                  + "options \(model.showsOptions) selected \(model.selectedShots.count)")
        case "optionsshot":
            ImportGridProbe.snapshotOptions(in: window, to: URL(fileURLWithPath: argument))
        case "gridshot":
            ImportGridProbe.snapshotGrid(in: window, to: URL(fileURLWithPath: argument))
        default:
            return false
        }
        return true
    }

    private static func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons(in:))
    }

    private static func textFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(textFields(in:))
    }

    private static func waitForScan(_ model: CardImportModel) async {
        try? await Task.sleep(for: .milliseconds(100))
        while model.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
    }

    public static func printState(_ model: CardImportModel) {
        let camera = model.camera.map { "\($0.name) count \($0.shutterCount.map(String.init) ?? "-") from \($0.fileName)" }
        let selected = model.selectedShots.map(\.primary.name).joined(separator: ",")
        var parts = ["import source \(model.source?.name ?? "-") card \(model.source?.isCard == true)"]
        parts.append("shots \(model.shots.count) duplicates \(model.duplicateCount) selected \(model.selectedShots.count) [\(selected)]")
        parts.append("deletion \(model.pendingDeletion?.count ?? 0) alert \(model.alertText ?? "-") done \(model.doneText ?? "-")")
        parts.append("error \(model.readError ?? "-") camera \(camera ?? "-") options \(model.showsOptions)")
        parts.append("folders \(model.folderTemplate) files \(model.fileTemplate) project \(model.projectNameTemplate)")
        print("debug-script: " + parts.joined(separator: " "))
    }
}
