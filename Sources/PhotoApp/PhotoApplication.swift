import AppKit
import PhotoCore
import SwiftUI

@main
struct PhotoApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryLoader()

    var body: some Scene {
        Window(AppBranding.displayName, id: "library") {
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
            LibraryCommands(model: library.model)
        }

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
            state = .ready(try LibraryModel.open())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var model: LibraryModel? {
        if case .ready(let model) = state { model } else { nil }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run as a bare executable (swift run) rather than an app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct LibraryErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("The library could not be opened.")
                .font(.title3)
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(40)
    }
}

struct LibraryCommands: Commands {
    let model: LibraryModel?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Album…") { model?.sidebarSheet = .newAlbum(projectID: model?.selectedProjectID) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model == nil)
            Button("New Smart Album…") { model?.sidebarSheet = .smartAlbum(nil, projectID: model?.selectedProjectID) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(model == nil)
            Divider()
            Button("Import Folder…") {
                if let model { ImportPanel.run(model: model) }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(model == nil || model?.isImporting == true)
        }

        CommandMenu("Photo") {
            Menu("Rating") {
                Button("No Rating") { model?.perform(.setRating(.unrated)) }
                ForEach(1...5, id: \.self) { stars in
                    Button(RatingText.stars(stars)) { model?.perform(.setRating(Rating(clamping: stars))) }
                }
                Divider()
                Button("Raise Rating") { model?.perform(.adjustRating(1)) }
                Button("Lower Rating") { model?.perform(.adjustRating(-1)) }
            }
            Menu("Flag") {
                Button("Pick") { model?.perform(.setFlag(.picked)) }
                Button("Reject") { model?.perform(.setFlag(.rejected)) }
                Button("Clear Flag") { model?.perform(.setFlag(.none)) }
            }
            Menu("Color Label") {
                ForEach(ColorLabel.allCases, id: \.self) { label in
                    Button(ColorLabelText.name(label)) { model?.perform(.setColorLabel(label)) }
                }
            }
            Button("Add Keywords…") { model?.beginKeywordEntry() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model == nil || model?.itemCount == 0)
            Button("Suggest Keywords") {
                guard let model else { return }
                model.suggestKeywords(for: model.actionTargetVersionIDs)
                model.showsInspector = true
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(model == nil || model?.itemCount == 0)
            Menu("Add to Album") {
                ForEach(model?.albums ?? []) { album in
                    Button(album.album.name) { model?.addToAlbum(album.id) }
                }
            }
            .disabled(model?.albums.isEmpty ?? true)
            Button("Remove from Album") { model?.removeFromCurrentAlbum() }
                .disabled(model?.currentAlbumID == nil)
            Divider()
            Button("Check for Changes on Disk") { model?.checkForDiskChanges() }
                .disabled(model == nil || model?.isCheckingDisk == true)
            Divider()
            Menu("RAW+JPEG Pair") {
                Button("Show the RAW File") { model?.showPairFile(raw: true) }
                Button("Show the JPEG or HEIC File") { model?.showPairFile(raw: false) }
            }
            .disabled(model?.groupPairs != true)
            Divider()
            Toggle("Advance After Rating", isOn: Binding(
                get: { model?.autoAdvance ?? false },
                set: { model?.autoAdvance = $0 }
            ))
        }

        CommandGroup(before: .toolbar) {
            Button(model?.mode == .loupe ? String(localized: "Show Grid") : String(localized: "Show Loupe")) {
                guard let model else { return }
                if model.mode == .loupe { model.closeLoupe() } else { model.openLoupe() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model?.itemCount ?? 0 == 0)
            Button("Larger Thumbnails") { model?.resizeThumbnails(by: 1.2) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller Thumbnails") { model?.resizeThumbnails(by: 1 / 1.2) }
                .keyboardShortcut("-", modifiers: .command)
            Toggle("Show File Names", isOn: Binding(
                get: { model?.showFileInfo ?? true },
                set: { model?.showFileInfo = $0 }
            ))
            Toggle("Show Inspector", isOn: Binding(
                get: { model?.showsInspector ?? false },
                set: { model?.showsInspector = $0 }
            ))
            .keyboardShortcut("i", modifiers: [.command, .option])
            Toggle("Group RAW+JPEG Pairs", isOn: Binding(
                get: { model?.groupPairs ?? true },
                set: { model?.groupPairs = $0 }
            ))
            Divider()
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
