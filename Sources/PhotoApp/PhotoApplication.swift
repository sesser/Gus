import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

@main
struct PhotoApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryLoader()

    var body: some Scene {
        Window(String(localized: "Library", comment: "The library window, in the Window menu; also a sidebar section"), id: "library") {
            Group {
                switch library.state {
                case .ready(let model):
                    MainView(model: model)
                        .onAppear {
                            ScrollBenchmark.startIfRequested(model: model)
                            DebugScript.startIfRequested(model: model)
                        }
                case .failed(let message):
                    LibraryErrorView(message: message)
                }
            }
            .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            LibraryCommands()
            ImportCommands(includesLibraryItems: true, includesOptionsItem: false)
        }

        Window(String(localized: "Import"), id: "import") {
            if let model = library.model {
                ImportWindow(model: model.cardImport)
            }
        }
        .defaultSize(width: 1200, height: 780)

        Settings {
            if let model = library.model {
                SettingsView(model: model)
            }
        }
    }
}

/// Opens the catalog once at launch.
@MainActor
@Observable
final class LibraryLoader {
    enum State {
        case ready(LibraryModel)
        case failed(String)
    }

    let state: State

    init() {
        do {
            let model = try LibraryModel.open()
            state = .ready(model)
            AppDelegate.library = model
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var model: LibraryModel? {
        if case .ready(let model) = state { model } else { nil }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The open library, for files opened from the Finder.
    @MainActor static weak var library: LibraryModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run as a bare executable (swift run) rather than an app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Preset files opened from the Finder (double-click, or dropped on the
    /// Dock icon) are imported into the library, with the usual summary.
    func application(_ application: NSApplication, open urls: [URL]) {
        let presets = urls.filter { PresetFile.fileExtensions.contains($0.pathExtension.lowercased()) }
        guard !presets.isEmpty, let library = Self.library else { return }
        Task { _ = await library.importAdjustmentPresets(presets) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct LibraryErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Can't Open the Library", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
                .textSelection(.enabled)
        }
    }
}

enum ColorLabelText {
    static func name(_ label: ColorLabel) -> String {
        switch label {
        case .none: String(localized: "No Label")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .gray: String(localized: "Gray")
        }
    }
}

extension LibraryModel {
    func resizeThumbnails(by factor: Double) {
        let range = Self.thumbnailSizeRange
        thumbnailSize = min(max(thumbnailSize * factor, range.lowerBound), range.upperBound)
    }
}
