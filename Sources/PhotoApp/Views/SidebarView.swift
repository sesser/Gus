import AppKit
import PhotoCore
import PhotoUI
import SwiftUI
import UniformTypeIdentifiers

/// A sheet the sidebar or a menu command asks for.
enum SidebarSheet: Identifiable {
    case renameKeyword(KeywordSummary)
    case newAlbum(projectID: Int64?)
    /// Editing an existing smart album, or making one (nil) in a project or the library.
    case smartAlbum(SmartAlbum?, projectID: Int64?)

    var id: String {
        switch self {
        case .renameKeyword(let keyword): "keyword-\(keyword.id)"
        case .newAlbum(let project): "new-album-\(project ?? 0)"
        case .smartAlbum(let album, let project): "smart-\(album?.id ?? 0)-\(project ?? 0)"
        }
    }
}

/// Something the person asked to delete, waiting for confirmation.
/// An album, smart album or keyword waiting for the person to confirm its
/// deletion (from the sidebar's context menu or File ▸ Delete).
enum SidebarDeletion: Identifiable {
    case keyword(KeywordSummary)
    case album(AlbumSummary)
    case smartAlbum(SmartAlbum)

    var id: String {
        switch self {
        case .keyword(let keyword): "keyword-\(keyword.id)"
        case .album(let album): "album-\(album.id)"
        case .smartAlbum(let album): "smart-\(album.id)"
        }
    }
}

extension UTType {
    /// Photos dragged out of the grid. The ids travel through the model; the
    /// type lets drop targets recognize the drag.
    static let photoVersions = UTType(exportedAs: AppBranding.bundleIdentifier + ".versions")
}

struct SidebarView: View {
    @Bindable var model: LibraryModel
    @Environment(\.openWindow) private var openWindow
    // Defaults from section 3 of docs/UI_REDESIGN.md.
    @AppStorage("sidebar.section.library.expanded") private var libraryExpanded = true
    @AppStorage("sidebar.section.albums.expanded") private var albumsExpanded = true
    @AppStorage("sidebar.section.dates.expanded") private var datesExpanded = false
    @AppStorage("sidebar.section.keywords.expanded") private var keywordsExpanded = false
    @AppStorage("sidebar.section.projects.expanded") private var projectsExpanded = true
    @State private var expandedYears: Set<Int> = []
    @State private var expandedProjects: Set<Int64> = []
    /// The list has the keyboard; set to hand it back after a rename ends.
    @FocusState private var listHasKeyboard: Bool

    var body: some View {
        ScrollViewReader { proxy in
            list
                // File ▸ Rename on a project or album whose row is out of view:
                // its section opens, an album's project too, and the row scrolls
                // in (library-ops design §4, rename-albums-in-place design §2.5).
                // A renamed album, which may have moved in the list, only scrolls in.
                .onChange(of: model.sidebarReveal) { _, reveal in
                    guard let reveal else { return }
                    if reveal.opensContainers {
                        switch model.sidebarRowPlace(of: reveal.item) {
                        case .albums:
                            albumsExpanded = true
                        case .projects(let project):
                            projectsExpanded = true
                            if let project { expandedProjects.insert(project) }
                        case nil:
                            break
                        }
                    }
                    // After the update that opens them, when the row exists.
                    Task { proxy.scrollTo(reveal.item) }
                }
                // A row being renamed that is hidden or folded away takes its
                // field with it: the rename ends, saved (design §2.3), and the
                // sidebar, if it is still there, keeps the keyboard (R1).
                .onChange(of: listState) { old, new in
                    if model.sidebarListChanged(from: old, to: new), new.showsSidebar { listHasKeyboard = true }
                }
        }
    }

    /// How much of the list is open (`SidebarListState`).
    private var listState: SidebarListState {
        SidebarListState(showsSidebar: model.showsSidebar,
                         albumsOpen: model.showsSidebarSection(.albums) && albumsExpanded,
                         projectsOpen: model.showsSidebarSection(.projects) && projectsExpanded,
                         expandedProjects: expandedProjects)
    }

    private var list: some View {
        List(selection: $model.sidebarSelection) {
            Section(isExpanded: $libraryExpanded) {
                Label("All Photos", systemImage: SidebarSymbols.symbol(for: .allPhotos))
                    .badge(model.libraryCount)
                    .tag(SidebarSelection.allPhotos)
                ForEach(BuiltInAlbum.allCases, id: \.self) { album in
                    Label(album.title, systemImage: SidebarSymbols.symbol(for: .builtIn(album)))
                        .badge(model.sidebarCounts[.builtIn(album)] ?? 0)
                        .tag(SidebarSelection.builtIn(album))
                }
                if model.diskChangeCount > 0 {
                    Label {
                        Text("Changed on Disk")
                    } icon: {
                        Image(systemName: SidebarSymbols.symbol(for: .changedOnDisk)).foregroundStyle(.orange)
                    }
                    .badge(model.diskChangeCount)
                    .tag(SidebarSelection.changedOnDisk)
                    .help("Photos whose sidecar or file another app changed. Review them in the inspector.")
                }
            } header: {
                header(.library, isExpanded: $libraryExpanded)
            }
            if model.showsSidebarSection(.albums) {
                Section(isExpanded: $albumsExpanded) {
                    let albums = model.albums.filter { $0.album.projectId == nil }
                    let smart = model.smartAlbums.filter { $0.projectID == nil }
                    if albums.isEmpty, smart.isEmpty {
                        EmptySectionLine(text: String(localized: "No albums"), link: String(localized: "New Album…")) {
                            model.sidebarSheet = .newAlbum(projectID: nil)
                        }
                    } else {
                        albumRows(albums, smart)
                    }
                } header: {
                    header(.albums, isExpanded: $albumsExpanded)
                }
            }
            if model.showsSidebarSection(.dates) {
                Section(isExpanded: $datesExpanded) {
                    if model.captureMonths.isEmpty {
                        EmptySectionLine(text: String(localized: "No capture dates"), link: nil) {}
                    }
                    ForEach(years, id: \.year) { year in
                        DisclosureGroup(isExpanded: expansion(of: year.year, in: $expandedYears)) {
                            ForEach(year.months) { month in
                                Label(MonthText.monthOnly(year: month.year, month: month.month),
                                      systemImage: SidebarSymbols.symbol(for: .month(year: month.year, month: month.month)))
                                    .badge(month.count)
                                    .tag(SidebarSelection.month(year: month.year, month: month.month))
                            }
                        } label: {
                            Label(String(year.year), systemImage: SidebarSymbols.symbol(for: .year(year.year)))
                                .badge(year.count)
                                .tag(SidebarSelection.year(year.year))
                        }
                    }
                } header: {
                    header(.dates, isExpanded: $datesExpanded)
                }
            }
            if model.showsSidebarSection(.keywords) {
                Section(isExpanded: $keywordsExpanded) {
                    if model.keywords.isEmpty {
                        // A link that cannot act is hidden, not dimmed.
                        EmptySectionLine(text: String(localized: "No keywords"),
                                         link: model.actionTargets.isEmpty ? nil : String(localized: "Add Keywords…")) {
                            model.beginKeywordEntry()
                        }
                    }
                    ForEach(model.keywords) { keyword in
                        Label(keyword.name, systemImage: SidebarSymbols.symbol(for: .keyword(keyword.id)))
                            .badge(keyword.count)
                            .tag(SidebarSelection.keyword(keyword.id))
                            .onDrop(of: [.photoVersions], isTargeted: nil) { _ in
                                model.addKeywords([keyword.name], to: model.draggedVersionIDs)
                                return true
                            }
                            .contextMenu {
                                Button("Rename…") { model.sidebarSheet = .renameKeyword(keyword) }
                                Button("Delete…", role: .destructive) { model.sidebarDeletion = .keyword(keyword) }
                            }
                    }
                } header: {
                    header(.keywords, isExpanded: $keywordsExpanded)
                }
            }
            if model.showsSidebarSection(.projects) {
                Section(isExpanded: $projectsExpanded) {
                    if model.projects.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No projects").foregroundStyle(.secondary)
                            Button("Import from Card or Folder…") {
                                model.cardImport.refreshSources()
                                openWindow(id: "import")
                            }
                            .buttonStyle(.link)
                        }
                        .selectionDisabled()
                        .onDrop(of: FolderDrop.types, isTargeted: nil) { FolderDrop.accept($0, model: model) }
                    }
                    // Identified by their sidebar selection, which no other row
                    // shares (keywords have ids of the same type): `scrollTo` finds the row.
                    ForEach(model.projects, id: \.sidebarSelection) { summary in
                        let albums = model.albums.filter { $0.album.projectId == summary.id }
                        let smart = model.smartAlbums.filter { $0.projectID == summary.id }
                        if albums.isEmpty, smart.isEmpty {
                            projectRow(summary)
                        } else {
                            DisclosureGroup(isExpanded: expansion(of: summary.id, in: $expandedProjects)) {
                                albumRows(albums, smart)
                            } label: {
                                projectRow(summary)
                            }
                        }
                    }
                } header: {
                    // Folders dropped on the header or any project row each become
                    // a new project, as they do on the browser.
                    header(.projects, isExpanded: $projectsExpanded)
                        .onDrop(of: FolderDrop.types, isTargeted: nil) { FolderDrop.accept($0, model: model) }
                }
            }
        }
        .listStyle(.sidebar)
        .focused($listHasKeyboard)
        // Return on a selected project or album renames it in place, as in the
        // Finder (library-ops design §3, rename-albums-in-place design §2.2);
        // on any other row it does nothing. A view key: only while the list
        // has the keyboard.
        .onKeyPress(.return) {
            guard model.sidebarSelection.renameRoute == .inPlace, model.sidebarRename == nil else { return .ignored }
            model.beginSidebarRename(model.sidebarSelection)
            return .handled
        }
        .background { SidebarMarker(observer: model.windowObserver) }
        .sheet(item: $model.sidebarSheet) { sheet in
            SidebarSheetView(model: model, sheet: sheet)
        }
        .confirmationDialog(deletionTitle, isPresented: Binding(get: { model.sidebarDeletion != nil },
                                                                set: { if !$0 { model.sidebarDeletion = nil } }),
                            presenting: model.sidebarDeletion) { deletion in
            Button("Delete", role: .destructive) {
                switch deletion {
                case .keyword(let keyword): model.deleteKeyword(keyword.id)
                case .album(let album): model.deleteAlbum(album.id)
                case .smartAlbum(let album): model.deleteSmartAlbum(album.id)
                }
            }
        } message: { deletion in
            switch deletion {
            case .keyword(let keyword):
                Text("It is removed from \(keyword.count) photos. The photos stay in the library.")
            case .album:
                Text("The photos stay in the library.")
            case .smartAlbum:
                Text("Only the album is deleted, not its photos.")
            }
        }
    }

    private var deletionTitle: String {
        switch model.sidebarDeletion {
        case .keyword(let keyword): String(localized: "Delete the keyword “\(keyword.name)”?")
        case .album(let album): String(localized: "Delete the album “\(album.album.name)”?")
        case .smartAlbum(let album): String(localized: "Delete the smart album “\(album.name)”?")
        case nil: ""
        }
    }

    @ViewBuilder
    private func albumRows(_ albums: [AlbumSummary], _ smart: [SmartAlbum]) -> some View {
        // Identified by their sidebar selection, as projects are, so `scrollTo`
        // finds the row. Album and smart album ids come from different tables
        // and can coincide: the selection's case, and the smart albums'
        // uuids, keep the rows apart.
        ForEach(albums, id: \.sidebarSelection) { album in
            // While it is being renamed its name is a text field in place;
            // the symbol and the count stay (rename-albums-in-place design §2.3).
            Label {
                rowName(album.album.name, of: .album(album.id))
            } icon: {
                Image(systemName: SidebarSymbols.symbol(for: .album(album.id)))
            }
            .badge(album.count)
            .tag(SidebarSelection.album(album.id))
            .onDrop(of: [.photoVersions], isTargeted: nil) { _ in
                model.addToAlbum(album.id, versionIDs: model.draggedVersionIDs)
                return true
            }
            .contextMenu {
                RenameButton()
                Divider()
                Button("Delete…", role: .destructive) { model.sidebarDeletion = .album(album) }
            }
            .renameAction { model.beginSidebarRename(.album(album.id)) }
        }
        // No Rename and no Return: a smart album's name is in its editor (design §4).
        ForEach(smart, id: \.uuid) { album in
            Label(album.name, systemImage: SidebarSymbols.symbol(for: .smartAlbum(album.id)))
                .badge(model.sidebarCounts[.smartAlbum(album.id)] ?? 0)
                .tag(SidebarSelection.smartAlbum(album.id))
                .contextMenu {
                    Button("Edit…") { model.sidebarSheet = .smartAlbum(album, projectID: album.projectID) }
                    Divider()
                    Button("Delete…", role: .destructive) { model.sidebarDeletion = .smartAlbum(album) }
                }
        }
    }

    /// A project's or an album's name in its row: a text field in place
    /// while the row is being renamed, the same for both.
    @ViewBuilder
    private func rowName(_ name: String, of item: SidebarSelection) -> some View {
        if let rename = model.sidebarRename, rename.item == item {
            SidebarNameField(rename: rename, label: SidebarRenameText.fieldLabel(for: item)) { save, byKey in
                model.endSidebarRename(rename, save: save)
                // Return and Escape leave the keyboard with the sidebar;
                // a click elsewhere has already taken it there.
                if byKey { listHasKeyboard = true }
            }
        } else {
            Text(name)
        }
    }

    /// A project's row. While it is being renamed its name is a text field
    /// in place; the folder symbol and the count stay (library-ops design §4).
    private func projectRow(_ summary: ProjectSummary) -> some View {
        Label {
            rowName(summary.project.name, of: .project(summary.id))
        } icon: {
            Image(systemName: SidebarSymbols.symbol(for: .project(summary.id)))
        }
        .badge(summary.versionCount)
        .tag(SidebarSelection.project(summary.id))
        // The folder's path: renaming the project leaves the folder's name as it is.
        .help(summary.project.sourcePath ?? summary.project.name)
        .onDrop(of: FolderDrop.types, isTargeted: nil) { FolderDrop.accept($0, model: model) }
        .contextMenu {
            Button("New Album in Project…") { model.sidebarSheet = .newAlbum(projectID: summary.id) }
            Button("New Smart Album in Project…") { model.sidebarSheet = .smartAlbum(nil, projectID: summary.id) }
            Divider()
            RenameButton()
            // Left out without a folder to reveal (library-ops design §5.2).
            if model.canShowProjectInFinder(summary.id) {
                Button(LibraryOpsText.showInFinder) { model.showProjectInFinder(summary.id) }
            }
            // Last and alone; left out while an import keeps a removal from starting (§8).
            if model.canRemoveFromLibrary {
                Divider()
                Button(LibraryOpsText.removeProjectMenu, role: .destructive) { model.removeProjectFromLibrary(summary.id) }
            }
        }
        .renameAction { model.beginSidebarRename(.project(summary.id)) }
    }

    /// A section's system header, with Collapse / Expand and Hide Section.
    private func header(_ section: SidebarSection, isExpanded: Binding<Bool>) -> some View {
        Text(section.title)
            .contextMenu {
                Button(isExpanded.wrappedValue ? String(localized: "Collapse") : String(localized: "Expand")) {
                    isExpanded.wrappedValue.toggle()
                }
                if section.canHide {
                    Button("Hide Section") { model.setSidebarSection(section, shown: false) }
                }
            }
    }

    private struct Year {
        var year: Int
        var count: Int
        var months: [CaptureMonth]
    }

    private var years: [Year] {
        Dictionary(grouping: model.captureMonths, by: \.year)
            .map { Year(year: $0.key, count: $0.value.map(\.count).reduce(0, +), months: $0.value) }
            .sorted { $0.year > $1.year }
    }

    private func expansion<ID: Hashable>(of id: ID, in set: Binding<Set<ID>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(id) },
                set: { expanded in
                    if expanded { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
                })
    }
}

private extension ProjectSummary {
    var sidebarSelection: SidebarSelection { .project(id) }
}

private extension AlbumSummary {
    var sidebarSelection: SidebarSelection { .album(id) }
}

/// A project's or an album's name being edited in its sidebar row. It takes
/// the keyboard when it appears, with the whole name selected. Return saves,
/// Escape puts the old name back, and losing the keyboard (a click
/// elsewhere, Tab) saves, as in the Finder. The model ends each rename once,
/// whichever of these comes first.
private struct SidebarNameField: View {
    @Bindable var rename: SidebarRename
    /// What VoiceOver calls the field: "Project name" or "Album name".
    let label: String
    /// `save` is false when the edit was cancelled; `byKey` when Return or
    /// Escape ended it.
    let onEnd: (_ save: Bool, _ byKey: Bool) -> Void
    @FocusState private var hasKeyboard: Bool

    var body: some View {
        TextField(text: $rename.draft) { Text(label) }
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused($hasKeyboard)
            .onSubmit { onEnd(true, true) }
            .onExitCommand { onEnd(false, true) }
            .onChange(of: hasKeyboard) { _, has in
                if !has { onEnd(true, false) }
            }
            // Once the field is in the window: a row scrolled into view for
            // the rename appears before it is, and a request made then is dropped.
            .background { WindowReader { if $0 != nil { hasKeyboard = true } } }
            .accessibilityLabel(label)
    }
}

/// A view of ours inside the sidebar, by which `LibraryWindowObserver` tells
/// the sidebar's pane of the split view from the others. AppKit, because
/// SwiftUI does not say which pane has the window's first responder.
private struct SidebarMarker: NSViewRepresentable {
    let observer: LibraryWindowObserver

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        observer.sidebarMarker = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if observer.sidebarMarker !== view { observer.sidebarMarker = view }
    }
}

/// An empty section's one line: what is missing, and a link to make one.
private struct EmptySectionLine: View {
    let text: String
    let link: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text).foregroundStyle(.secondary)
            if let link {
                Text(verbatim: "·").foregroundStyle(.secondary)
                Button(link, action: action)
                    .buttonStyle(.link)
            }
        }
        .selectionDisabled()
    }
}

enum SidebarSymbols {
    /// A stack with the "automatic" badge: an album that fills itself from rules.
    static let smartAlbum = "square.stack.3d.up.badge.automatic"

    /// Each source's symbol, for its sidebar row and its empty state
    /// (design.md N3, D-Q1). Rows add any tint themselves.
    static func symbol(for selection: SidebarSelection) -> String {
        switch selection {
        case .allPhotos: "photo.on.rectangle"
        case .builtIn(let album): album.symbol
        case .year, .month: "calendar"
        case .project: "folder"
        case .album: "rectangle.stack"
        case .smartAlbum: smartAlbum
        case .keyword: "tag"
        case .changedOnDisk: "exclamationmark.triangle"
        }
    }
}

enum RatingText {
    static func stars(_ count: Int) -> String {
        String(repeating: "★", count: count)
    }

    static func atLeast(_ count: Int) -> String {
        count == 5 ? stars(5) : String(localized: "\(stars(count)) or Better", comment: "Rating filter. The argument is a row of stars.")
    }
}
