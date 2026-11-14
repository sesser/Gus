import AppKit
import CryptoKit
import PhotoCore

/// The debug scripts' `about` commands, in both apps. They need no key
/// window, so they work in a process started from a shell:
///
///     about open [app|help]   (runs About ‹name› in the app menu, or in Help: the menu item's own action)
///     about close | escape [posted]   (the close button's action; an Esc key down for the window, handed to its
///                             monitor's handler, or with `posted` put in the event queue as a typed key is, which
///                             needs the app active: launch with `open`)
///     about menus             (where About ‹name› is in the app menu and in Help, enabled, its key equivalent)
///     about print             (the window: title, size and limits, buttons, Window menu; then what it shows:
///                             header, version line or its absence, dedication, each entry's name, sentence,
///                             license, address, page and whether it has View License, the footer; then every
///                             open license window)
///     about windows           (how many About windows and license windows there are, and every visible window)
///     about link <project>    (the entry's link, through the window's own open-URL action: under a debug
///                             script that prints the page instead of starting a browser)
///     about license <project>|app [print|close|find|snapshot <file.png>]
///                             (View License's action, only when the window offers it; print gives the license
///                             window's title, the bytes and SHA-256 of the text it shows, or its missing state;
///                             find is ⌘F in it)
///     about snapshot <file.png>
///     about height <points>|max   (the About window's height, kept within its limits, its top left in place:
///                             max shows everything at once, for a snapshot with the footer in it)
///     about quithost          (the window a quit confirmation would go on now: never the About window or a
///                             license window, and the sheet on a window that shows one; then the key window and
///                             the visible windows front to back)
///     about quitask [keep]    (asks "Quit While Exporting?" where ⌘Q during an export would, with nothing running
///                             and nothing quitting, and says whether the question is on screen, on what, and the
///                             window order; `keep` answers Keep Exporting. Not shown when no window would host it)
///     about closeothers       (the close buttons' action on every window that is not the About window or a
///                             license window, for checks with only those left)
///     about click <x> <y>     (a mouse down and up through the event queue, in the About window's points from its
///                             top left; launch with `open` so the app is active. A link clicked this way is
///                             reported, not opened)
///
/// `<project>` is a name from `Acknowledgements` in any case: libraw, darktable, lightcraft, grdb, exiftool.
@MainActor
public enum AboutDebugCommands {
    public static func run(_ arguments: [String], appName: String) async {
        let rest = Array(arguments.dropFirst())
        switch arguments.first {
        case "open":
            open(from: rest.first ?? "app", appName: appName)
            await settle()
        case "close":
            guard let window = visibleAbout() else { return }
            window.performClose(nil)
            await settle()
        case "escape":
            guard let window = visibleAbout(), let event = escapeKeyDown(in: window) else { return }
            if rest.first == "posted" {
                // Through the event queue, where the window's monitor gets
                // it as it gets a typed key. The app must be active.
                NSApp.postEvent(event, atStart: false)
                await settle()
                print("debug-script: about escape posted, app active \(NSApp.isActive), window open \(AboutWindowRegistry.aboutWindow?.isVisible == true)")
            } else {
                let handled = AboutWindowRegistry.closesAbout(event)
                await settle()
                print("debug-script: about escape handled \(handled), window open \(AboutWindowRegistry.aboutWindow?.isVisible == true)")
            }
        case "menus":
            printMenus(appName: appName)
        case "print":
            printWindow()
        case "windows":
            printWindows(appName: appName)
        case "link":
            link(rest.first ?? "")
        case "license":
            await license(rest)
        case "snapshot":
            guard let window = visibleAbout(), let path = rest.first else { return }
            WindowSnapshot.write(window, to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        case "height":
            guard let window = visibleAbout() else { return }
            let limits = window.contentMinSize.height...max(window.contentMinSize.height, window.contentMaxSize.height)
            let wanted = rest.first == "max" ? limits.upperBound : CGFloat(Double(rest.first ?? "") ?? Double(window.frame.height))
            var frame = window.frame
            let height = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: frame.width,
                                                                 height: min(max(wanted, limits.lowerBound), limits.upperBound))).height
            frame.origin.y += frame.height - height
            frame.size.height = height
            window.setFrame(frame, display: true)
            await settle()
            print("debug-script: about height \(size(window.frame.size))")
        case "quithost":
            print("debug-script: about quithost \(describe(QuitGuard.confirmationWindow)), key \(describe(NSApp.keyWindow))"
                  + ", app active \(NSApp.isActive), front to back [\(windowOrder())]")
        case "quitask":
            await quitAsk(rest.first)
        case "closeothers":
            let others = NSApp.windows.filter {
                $0.isVisible && $0.contentView != nil && $0.className.contains("Window") && !AboutWindowRegistry.owns($0)
            }
            others.forEach { $0.performClose(nil) }
            await settle()
            print("debug-script: about closeothers closed [\(others.map(\.title).joined(separator: ", "))]")
        case "click":
            guard let window = visibleAbout(), rest.count >= 2, let x = Double(rest[0]), let y = Double(rest[1]) else { return }
            click(NSPoint(x: x, y: window.frame.height - y), in: window)
            await settle()
        default:
            print("debug-script: unknown about command \(arguments.joined(separator: " "))")
        }
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(600))
    }

    private static func visibleAbout() -> NSWindow? {
        guard let window = AboutWindowRegistry.aboutWindow, window.isVisible else {
            print("debug-script: about window is not open")
            return nil
        }
        return window
    }

    // MARK: Menus

    private static func menu(_ name: String) -> NSMenu? {
        name == "help" ? NSApp.helpMenu : NSApp.mainMenu?.items.first?.submenu
    }

    /// The menu as an opening menu has it: SwiftUI may refresh items only then.
    private static func refreshed(_ menu: NSMenu) -> NSMenu {
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        return menu
    }

    private static func open(from name: String, appName: String) {
        let title = AboutText.aboutTitle(appName)
        guard let menu = menu(name).map(refreshed),
              let index = menu.items.firstIndex(where: { $0.title == title })
        else {
            print("debug-script: about open: no “\(title)” in the \(name) menu")
            return
        }
        guard menu.items[index].isEnabled else {
            print("debug-script: about open: “\(title)” is disabled in the \(name) menu")
            return
        }
        menu.performActionForItem(at: index)
        print("debug-script: about open: ran “\(title)” from the \(name) menu")
    }

    private static func printMenus(appName: String) {
        let title = AboutText.aboutTitle(appName)
        for name in ["app", "help"] {
            guard let menu = menu(name).map(refreshed) else {
                print("debug-script: about menus: no \(name) menu")
                continue
            }
            let shown = menu.items.filter { !$0.isHidden }
            let titles = shown.map { $0.isSeparatorItem ? "—" : $0.title }
            guard let index = shown.firstIndex(where: { $0.title == title }) else {
                print("debug-script: about menus: \(name) menu “\(menu.title)” has no “\(title)”; items [\(titles.joined(separator: ", "))]")
                continue
            }
            let item = shown[index]
            let next = shown.indices.contains(index + 1) ? (shown[index + 1].isSeparatorItem ? "separator" : "“\(shown[index + 1].title)”") : "nothing"
            print("debug-script: about menus: \(name) menu “\(menu.title)” has “\(title)” at \(index) of \(shown.count)"
                  + ", enabled \(item.isEnabled), key equivalent “\(item.keyEquivalent)”, followed by \(next)"
                  + ", count \(shown.filter { $0.title == title }.count); items [\(titles.joined(separator: ", "))]")
        }
        // File ▸ Close (⌘W), which closes the About and license windows too.
        func closeItem(_ menu: NSMenu?) -> NSMenuItem? {
            for item in menu?.items ?? [] {
                if item.keyEquivalent == "w", item.keyEquivalentModifierMask == .command { return item }
                if let found = closeItem(item.submenu) { return found }
            }
            return nil
        }
        print("debug-script: about menus: ⌘W item \(closeItem(NSApp.mainMenu).map { "“\($0.title)”" } ?? "none")")
        let system = #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        func usesSystemPanel(_ menu: NSMenu?) -> Bool {
            menu?.items.contains { $0.action == system || usesSystemPanel($0.submenu) } ?? false
        }
        print("debug-script: about menus: an item opens the system About panel \(usesSystemPanel(NSApp.mainMenu))")
    }

    // MARK: The window

    private static func size(_ size: NSSize) -> String {
        func side(_ value: CGFloat) -> String { value >= 10000 ? "unlimited" : String(format: "%.0f", value) }
        return "\(side(size.width))×\(side(size.height))"
    }

    private static func printWindow() {
        guard let window = AboutWindowRegistry.aboutWindow, window.isVisible else {
            print("debug-script: about window open false")
            return
        }
        let content = window.contentRect(forFrameRect: window.frame).size
        func button(_ kind: NSWindow.ButtonType) -> String {
            guard let button = window.standardWindowButton(kind) else { return "none" }
            return button.isHidden ? "hidden" : button.isEnabled ? "on" : "off"
        }
        let windowMenu = NSApp.windowsMenu.map(refreshed)
        let listed = windowMenu?.items.contains { $0.title == window.title } ?? false
        print("debug-script: about window open true, title “\(window.title)”, title shown \(window.titleVisibility == .visible)"
              + ", frame \(size(window.frame.size)), content \(size(content))"
              + ", min \(size(window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).size))"
              + " max \(size(window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMaxSize)).size))"
              + ", resizable \(window.styleMask.contains(.resizable))"
              + ", close \(button(.closeButton)) minimize \(button(.miniaturizeButton)) zoom \(button(.zoomButton))"
              + ", full screen allowed \(window.collectionBehavior.contains(.fullScreenPrimary))"
              + ", restorable \(window.isRestorable)"
              + ", in Window menu \(listed), key \(window.isKeyWindow)"
              + ", first responder \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")"
              + ", appearance \(window.effectiveAppearance.name.rawValue)")
        guard let shown = AboutWindowRegistry.shown else {
            print("debug-script: about shows nothing yet")
            return
        }
        print("debug-script: about header “\(shown.appName)”, version \(shown.content.version.map { "“\(AboutText.version($0))”" } ?? "none")")
        print("debug-script: about dedication “\(AboutText.dedication(shown.projectName))”")
        for entry in shown.content.entries {
            print("debug-script: about entry \(entry.name) | \(AboutText.summary(of: entry.project)) | \(AboutText.name(of: entry.license))"
                  + " | \(entry.displayAddress) | \(entry.page.absoluteString)"
                  + " | View License \(shown.content.offersLicense(for: entry) ? "“\(AboutText.viewLicenseLabel(entry.name))”" : "none")")
        }
        print("debug-script: about footer “\(AboutText.copyright)” | \(AboutText.freeSoftwareStatement(shown.projectName))"
              + " | View License \(shown.content.offersAppLicense ? "“\(AboutText.viewLicenseLabel(shown.projectName))”" : "none")")
        for document in AboutWindowRegistry.openLicenseDocuments.sorted(by: { name($0) < name($1) }) {
            printLicense(document)
        }
    }

    private static func printWindows(appName: String) {
        let title = AboutText.aboutTitle(appName)
        let visible = NSApp.windows.filter { $0.isVisible && $0.contentView != nil && $0.className.contains("Window") }
        let about = visible.filter { $0.title == title }
        let licenses = visible.filter { window in AboutWindowRegistry.owns(window) && window.title != title }
        print("debug-script: about windows: \(about.count) titled “\(title)”, \(licenses.count) license"
              + " [\(licenses.map(\.title).sorted().joined(separator: ", "))]"
              + ", visible [\(visible.map(\.title).joined(separator: ", "))]")
    }

    // MARK: Quit confirmation

    /// A window by its title; a sheet by the window it is on.
    private static func describe(_ window: NSWindow?) -> String {
        guard let window else { return "none" }
        if let parent = window.sheetParent { return "a sheet on \(describe(parent))" }
        return "“\(window.title)”"
    }

    private static func windowOrder() -> String {
        // Sheets are told with their windows; an untitled window by its class.
        NSApp.orderedWindows.filter { $0.isVisible && $0.sheetParent == nil && $0.className.contains("Window") }
            .map { $0.title.isEmpty ? "(\($0.className))" : "“\($0.title)”" }.joined(separator: ", ")
    }

    private static weak var askedOn: NSWindow?

    /// `QuitGuard.ask`, as the library app's quit calls it, without a job
    /// and without quitting: the answer is dropped.
    private static func quitAsk(_ argument: String?) async {
        if argument == "keep" {
            guard let host = askedOn, let alert = host.attachedSheet else {
                print("debug-script: about quitask keep: no question is up")
                return
            }
            host.endSheet(alert, returnCode: .alertFirstButtonReturn)
            await settle()
            print("debug-script: about quitask keep: answered, sheets on its window \(host.sheets.count)")
            return
        }
        guard let host = QuitGuard.confirmationWindow else {
            print("debug-script: about quitask: no window would host it; the alert would stand alone (not shown by the script)")
            return
        }
        askedOn = host
        let before = host.sheets.count
        let previous = host.attachedSheet
        Task { _ = await QuitGuard.ask(QuitGuard.text(for: .exporting), in: host) }
        await settle()
        // A question kept waiting behind another sheet is not on screen.
        let alert = host.attachedSheet
        let shown = alert != nil && alert !== previous && alert?.isVisible == true
        print("debug-script: about quitask on \(describe(host)): question on screen \(shown)"
              + ", sheets on it \(before) → \(host.sheets.count), key \(describe(NSApp.keyWindow))"
              + ", front to back [\(windowOrder())]")
    }

    /// Both at once: a control's tracking loop waits for the mouse up.
    private static func click(_ point: NSPoint, in window: NSWindow) {
        let hit = window.contentView?.superview?.hitTest(point)
        print("debug-script: about click at \(Int(point.x)),\(Int(window.frame.height - point.y)) hits \(hit.map { String(describing: type(of: $0)) } ?? "nothing"), key \(window.isKeyWindow)")
        for (index, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: index + 1, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }

    private static func escapeKeyDown(in window: NSWindow) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
                         charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: AboutWindowRegistry.escapeKeyCode)
    }

    // MARK: Links and licenses

    private static func entry(_ text: String) -> Acknowledgement? {
        Acknowledgements.all.first { $0.name.lowercased() == text.lowercased() || $0.project.rawValue.lowercased() == text.lowercased() }
    }

    private static func document(_ text: String) -> LicenseDocument? {
        text == "app" ? .app : entry(text).map { .project($0.project) }
    }

    private static func name(_ document: LicenseDocument) -> String {
        switch document {
        case .app: "app"
        case .project(let project): Acknowledgements.entry(for: project)?.name ?? project.rawValue
        }
    }

    private static func link(_ text: String) {
        guard visibleAbout() != nil, let shown = AboutWindowRegistry.shown else { return }
        guard let entry = entry(text), shown.content.entries.contains(entry) else {
            print("debug-script: about link: no entry \(text)")
            return
        }
        // What the window's links run (`AboutLinks.action`): under a script
        // it prints the page. Nothing is opened from here either way.
        if AboutLinks.opensInBrowser(entry.page) {
            print("debug-script: about link \(entry.page.absoluteString) is left to the system (not opened by the script)")
        }
    }

    private static func license(_ arguments: [String]) async {
        guard let document = document(arguments.first ?? "") else {
            print("debug-script: about license: no license \(arguments.first ?? "")")
            return
        }
        switch arguments.dropFirst().first {
        case nil:
            guard visibleAbout() != nil, let shown = AboutWindowRegistry.shown else { return }
            guard shown.content.availableLicenses.contains(document) else {
                print("debug-script: about license: the window has no View License for \(name(document))")
                return
            }
            AboutWindowRegistry.openLicense?(document)
            await settle()
            printLicense(document)
        case "print":
            printLicense(document)
        case "close":
            AboutWindowRegistry.licenseWindow(for: document)?.performClose(nil)
            await settle()
        case "find":
            guard let textView = textView(of: document) else {
                print("debug-script: about license: no text shown for \(name(document))")
                return
            }
            textView.find(.showFindInterface)
            await settle()
            print("debug-script: about license \(name(document)) find bar visible \(textView.enclosingScrollView?.isFindBarVisible == true)")
        case "snapshot":
            guard let window = AboutWindowRegistry.licenseWindow(for: document), window.isVisible, arguments.count >= 3 else { return }
            WindowSnapshot.write(window, to: URL(fileURLWithPath: (arguments[2] as NSString).expandingTildeInPath))
        default:
            print("debug-script: unknown about license command \(arguments.joined(separator: " "))")
        }
    }

    private static func textView(of document: LicenseDocument) -> LicenseTextView? {
        func find(_ view: NSView?) -> LicenseTextView? {
            guard let view else { return nil }
            if let textView = view as? LicenseTextView { return textView }
            for subview in view.subviews {
                if let found = find(subview) { return found }
            }
            return nil
        }
        guard let window = AboutWindowRegistry.licenseWindow(for: document), window.isVisible else { return nil }
        return find(window.contentView)
    }

    /// The license window as it is on screen: the text is read back from
    /// its text view, not from the file.
    private static func printLicense(_ document: LicenseDocument) {
        guard let window = AboutWindowRegistry.licenseWindow(for: document), window.isVisible else {
            print("debug-script: about license \(name(document)) window open false")
            return
        }
        let content = window.contentRect(forFrameRect: window.frame).size
        var line = "debug-script: about license \(name(document)) window open true, title “\(window.title)”"
            + ", content \(size(content)), content min \(size(window.contentMinSize))"
            + ", resizable \(window.styleMask.contains(.resizable)), restorable \(window.isRestorable)"
        if let textView = textView(of: document) {
            let data = Data(textView.string.utf8)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let font = textView.font.map { "\($0.fontName) \($0.pointSize)" } ?? "nil"
            line += ", text \(data.count) bytes, sha256 \(digest), editable \(textView.isEditable), selectable \(textView.isSelectable)"
                + ", font \(font), find bar \(textView.enclosingScrollView?.isFindBarVisible == true)"
                + ", first line “\(textView.string.prefix { !$0.isNewline })”"
        } else {
            line += ", text none (missing state)"
        }
        print(line)
    }
}
