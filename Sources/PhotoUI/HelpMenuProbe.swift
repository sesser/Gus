import AppKit

/// Debug scripts' `helpmenu` (both apps): whether the menu bar has a Help
/// menu that AppKit treats as the help menu, which is where it puts the
/// search field that finds menu commands, and the items in it.
@MainActor
public enum HelpMenuProbe {
    public static func print() {
        let main = NSApp.mainMenu
        let help = NSApp.helpMenu
        let inMenuBar = main?.items.contains { $0.submenu != nil && $0.submenu === help } ?? false
        if let help {
            help.delegate?.menuNeedsUpdate?(help)
            help.update()
        }
        let items = help?.items.map { ($0.isSeparatorItem ? "—" : $0.title) + ($0.isHidden ? " (hidden)" : "") } ?? []
        Swift.print("debug-script: help menu \(help.map { "'\($0.title)'" } ?? "nil") in menu bar \(inMenuBar)"
                    + " items [\(items.joined(separator: ", "))]"
                    + " | menu bar [\(main?.items.map(\.title).joined(separator: ", ") ?? "")]")
    }
}
