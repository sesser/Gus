import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// The import window as an app of its own: copies from cards and folders into
/// folders, with no library. The library app can import the copies later.
/// The window, its model and the copying are the library app's, from PhotoUI
/// and PhotoCore, so the two cannot drift apart.
@main
struct ImporterApplication: App {
    @NSApplicationDelegateAdaptor(ImporterDelegate.self) private var appDelegate
    @State private var model = ImporterApplication.makeModel()

    var body: some Scene {
        Window(AppBranding.importerDisplayName, id: "import") {
            ImportWindow(model: model)
                .onAppear {
                    ImporterDelegate.model = model
                    model.followCards()
                    ImporterDebugScript.startIfRequested(model: model)
                }
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            ImportCommands(includesLibraryItems: false)
            // No help content yet: SwiftUI's "‹app› Help" only says so. The
            // Help menu and its search field stay (prd.md R1, R2).
            CommandGroup(replacing: .help) {}
        }
    }

    /// No catalog: presets and remembered options live in this app's preferences.
    @MainActor
    static func makeModel() -> CardImportModel {
        CardImportModel(metadataReader: MetadataReaders.makeDefault(), presets: DefaultsMetadataPresetStore())
    }
}

final class ImporterDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var model: CardImportModel?

    /// ⌘Q while a copy runs asks first (closing the window asks too, in
    /// `ImportWindow`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, !QuitGuard.allowsQuit, model.isImporting else { return .terminateNow }
        // Cancelled now and asked again after Stop and Quit: with
        // .terminateLater the app waits in a run loop mode in which the
        // alert's task never runs.
        Task { @MainActor in
            if await model.confirmQuit(.quit) { NSApp.terminate(nil) }
        }
        return .terminateCancel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run as a bare executable (swift run) rather than an app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// `--debug-script "<commands>"` for the importer, separated by ";":
///
///     wait <seconds>    snapshot <file.png>    helpmenu (the Help menu and its items)    quit
///     import …          (the library app's import commands, see ImportDebugCommands)
@MainActor
enum ImporterDebugScript {
    private static var started = false

    static func startIfRequested(model: CardImportModel) {
        guard let script = LaunchOptions.current.debugScript, !started else { return }
        started = true
        setvbuf(stdout, nil, _IOLBF, 0)
        let commands = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        Task {
            try? await Task.sleep(for: .seconds(1))
            for command in commands where !command.isEmpty {
                await run(command, model: model)
            }
        }
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.className.contains("Window") }
    }

    private static func run(_ command: String, model: CardImportModel) async {
        let parts = command.split(separator: " ").map(String.init)
        guard let verb = parts.first else { return }
        let rest = Array(parts.dropFirst())
        switch verb {
        case "wait":
            try? await Task.sleep(for: .seconds(Double(rest.first ?? "1") ?? 1))
        case "snapshot":
            if let window, let path = rest.first {
                WindowSnapshot.write(window, to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            }
        case "import":
            if !(await ImportDebugCommands.run(rest, model: model, window: window)) {
                print("debug-script: unknown import command")
            }
        case "helpmenu":
            HelpMenuProbe.print()
        case "quit":
            QuitGuard.allowsQuit = true
            NSApp.terminate(nil)
        default:
            print("debug-script: unknown command \(verb)")
        }
    }
}
