import AppKit
import PhotoCore
import PhotoUI

/// Debug-script commands for Rename, Show in Finder and the removals
/// (docs/features/library-ops); `DebugScript` lists them.
@MainActor
enum DebugLibraryOpsCommands {
    /// `alert`: the texts and buttons of the alert or sheet on the library
    /// window, each button with its key equivalent (`return` is the default
    /// button). `alert press <title>` clicks one and waits for a removal it
    /// starts to end; `alert key <key>` sends a key to it (return, escape,
    /// space, cmd+.) the way the key window would get it.
    static func alert(_ words: [String], window: NSWindow?, model: LibraryModel) async {
        guard let sheet = window?.attachedSheet, let content = sheet.contentView else {
            print("debug-script: alert none")
            return
        }
        var texts: [String] = []
        var buttons: [NSButton] = []
        func visit(_ view: NSView) {
            if let button = view as? NSButton, !button.isHidden, !button.title.isEmpty {
                buttons.append(button)
            } else if let field = view as? NSTextField, !field.isEditable, !field.stringValue.isEmpty {
                texts.append(field.stringValue)
            }
            view.subviews.forEach(visit)
        }
        visit(content)
        switch words.first {
        case "press":
            let title = words.dropFirst().joined(separator: " ")
            guard let button = buttons.first(where: { $0.title == title }) else {
                print("debug-script: alert has no button \(title)")
                return
            }
            button.performClick(nil)
            await settle(model, window: window)
        case "key":
            guard let event = keyEvent(words.dropFirst().first ?? "", in: sheet) else { return }
            // A key equivalent first, as the application offers it to the key window; then the key itself.
            if !sheet.performKeyEquivalent(with: event) { sheet.sendEvent(event) }
            await settle(model, window: window)
            print("debug-script: alert after key \(words.dropFirst().first ?? "") \(window?.attachedSheet == nil ? "closed" : "open")")
        default:
            for text in texts { print("debug-script: alert text \(text)") }
            for button in buttons {
                let key = switch button.keyEquivalent {
                case "\r": "return"
                case "\u{1B}": "escape"
                case "": "none"
                default: button.keyEquivalent
                }
                print("debug-script: alert button '\(button.title)' key \(key)\(button.hasDestructiveAction ? " destructive" : "")")
            }
        }
    }

    /// Waits for the alert's answer to be handled and, once the alert has
    /// closed, for a removal it started to end.
    /// Prints how long a removal ran when Activity showed its job.
    private static func settle(_ model: LibraryModel, window: NSWindow?) async {
        let start = ContinuousClock.now
        var job: RemovalJob?
        try? await Task.sleep(for: .milliseconds(400))
        while model.isRemoving, window?.attachedSheet == nil {
            job = model.removalJob ?? job
            try? await Task.sleep(for: .milliseconds(50))
        }
        if let job {
            let seconds = Double((ContinuousClock.now - start).components.attoseconds) / 1e18
                + Double((ContinuousClock.now - start).components.seconds)
            print(String(format: "debug-script: removal ran %.1f s, Activity job '%@'%@", seconds, job.title,
                         job.detail.map { " detail '\($0)'" } ?? ""))
        }
        try? await Task.sleep(for: .milliseconds(600))
    }

    private static func keyEvent(_ spec: String, in window: NSWindow) -> NSEvent? {
        let keys: [String: (UInt16, String, NSEvent.ModifierFlags)] = [
            "return": (36, "\r", []), "escape": (53, "\u{1B}", []), "cmd+.": (47, ".", .command), "space": (49, " ", []),
        ]
        guard let (code, characters, flags) = keys[spec] else {
            print("debug-script: alert key takes return, escape, space or cmd+.")
            return nil
        }
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                isARepeat: false, keyCode: code)
    }

    /// `removal fail on|off`: makes removals fail, as a damaged catalog
    /// would, to show that the catalog is left unchanged and Activity says
    /// so. Temporary triggers on this process's writer connection: nothing is
    /// stored in the catalog file.
    static func removal(_ words: [String], model: LibraryModel) async {
        guard words.first == "fail" else {
            print("debug-script: removal takes fail on|off")
            return
        }
        let on = words.dropFirst().first != "off"
        do {
            try await model.catalog.database.write { db in
                for table in ["image", "project"] {
                    try db.execute(sql: "DROP TRIGGER IF EXISTS temp.debug_removal_failure_\(table)")
                    guard on else { continue }
                    try db.execute(sql: """
                        CREATE TEMP TRIGGER debug_removal_failure_\(table) BEFORE DELETE ON main.\(table)
                        BEGIN SELECT RAISE(ABORT, 'forced removal failure'); END
                        """)
                }
            }
            print("debug-script: removal fail \(on ? "on" : "off")")
        } catch {
            print("debug-script: removal fail could not be set: \(error)")
        }
    }

    /// `sidebarfocus`: hands the keyboard to the sidebar's list, as a click on a row does.
    static func focusSidebar(_ model: LibraryModel) {
        guard let list = model.windowObserver.sidebarList(), let window = list.window else {
            print("debug-script: no sidebar list")
            return
        }
        window.makeFirstResponder(list)
    }

    /// `print projects`: each project's name, count and whether Show in
    /// Finder has a folder for it; the row being renamed and its field.
    static func printProjects(_ model: LibraryModel, window: NSWindow?) {
        let projects = model.projects.map { summary in
            "\(summary.project.name)=\(summary.versionCount)" + (model.canShowProjectInFinder(summary.id) ? " folder" : " nofolder")
        }
        var line = "debug-script: projects [" + projects.joined(separator: ", ") + "]"
        if case .project(let id) = model.sidebarSelection, let index = model.projects.firstIndex(where: { $0.id == id }) {
            line += " selected \(index)"
        }
        if let id = model.renamingProjectID, let index = model.projects.firstIndex(where: { $0.id == id }) {
            line += " renaming \(index)"
            // The field editor of the row's text field, with what is selected in it.
            if let editor = window?.firstResponder as? NSTextView {
                let range = editor.selectedRange()
                line += " field '\(editor.string)' selected \(range.location)..<\(range.location + range.length)"
            } else {
                line += " field without the keyboard"
            }
        }
        // How far the sidebar is scrolled (a row out of view is scrolled to before it is renamed).
        if let scroll = model.windowObserver.sidebarList()?.enclosingScrollView {
            let visible = scroll.documentVisibleRect
            line += " | sidebar shows \(Int(visible.minY))..<\(Int(visible.maxY)) of \(Int(scroll.documentView?.frame.height ?? 0))"
        }
        print(line)
    }

    /// `print reveal`: what Show in Finder would hand to the Finder for the
    /// targets, without opening it.
    static func printReveal(_ model: LibraryModel) async {
        let outcome = await model.finderRevealOutcome()
        print("debug-script: reveal [" + outcome.urls.map(\.lastPathComponent).joined(separator: ", ") + "]"
              + " folders \(Set(outcome.urls.map { $0.deletingLastPathComponent() }).count)"
              + " offline \(outcome.offline) missing \(outcome.missing)"
              + (outcome.skipped > 0 ? " | \(LibraryOpsText.notShown(outcome))" : ""))
    }

    /// `print removal`: whether a removal may start, whether one is asked
    /// for or running, and its Activity job.
    static func printRemoval(_ model: LibraryModel) {
        print("debug-script: removal can start \(model.canRemoveFromLibrary) removing \(model.isRemoving)"
              + " asking \(model.pendingRemoval != nil)"
              + " job \(model.removalJob.map { "'\($0.title)'" + ($0.detail.map { " '\($0)'" } ?? "") } ?? "none")")
    }
}
