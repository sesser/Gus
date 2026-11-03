import PhotoCore
import SwiftUI
import UniformTypeIdentifiers

/// A sheet the sidebar or a menu command asks for.
enum SidebarSheet: Identifiable {
    case renameKeyword(KeywordSummary)
    case renameAlbum(AlbumSummary)
    case newAlbum(projectID: Int64?)
    /// Editing an existing smart album, or making one (nil) in a project or the library.
    case smartAlbum(SmartAlbum?, projectID: Int64?)

    var id: String {
        switch self {
        case .renameKeyword(let keyword): "keyword-\(keyword.id)"
        case .renameAlbum(let album): "album-\(album.id)"
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

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section(isExpanded: $libraryExpanded) {
                Label("All Photos", systemImage: "photo.on.rectangle")
                    .badge(model.libraryCount)
                    .tag(SidebarSelection.allPhotos)
                ForEach(BuiltInAlbum.allCases, id: \.self) { album in
                    Label(album.title, systemImage: album.symbol)
                        .badge(model.sidebarCounts[.builtIn(album)] ?? 0)
                        .tag(SidebarSelection.builtIn(album))
                }
                if model.diskChangeCount > 0 {
                    Label {
                        Text("Changed on Disk")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
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
                                Label(MonthText.monthOnly(year: month.year, month: month.month), systemImage: "calendar")
                                    .badge(month.count)
                                    .tag(SidebarSelection.month(year: month.year, month: month.month))
                            }
                        } label: {
                            Label(String(year.year), systemImage: "calendar")
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
                        Label(keyword.name, systemImage: "tag")
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
                    ForEach(model.projects) { summary in
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
        // Album and smart album ids come from different tables, so they can
        // coincide; the uuids keep the rows apart.
        ForEach(albums, id: \.album.uuid) { album in
            Label(album.album.name, systemImage: "rectangle.stack")
                .badge(album.count)
                .tag(SidebarSelection.album(album.id))
                .onDrop(of: [.photoVersions], isTargeted: nil) { _ in
                    model.addToAlbum(album.id, versionIDs: model.draggedVersionIDs)
                    return true
                }
                .contextMenu {
                    Button("Rename…") { model.sidebarSheet = .renameAlbum(album) }
                    Button("Delete…", role: .destructive) { model.sidebarDeletion = .album(album) }
                }
        }
        ForEach(smart, id: \.uuid) { album in
            Label(album.name, systemImage: SidebarSymbols.smartAlbum)
                .badge(model.sidebarCounts[.smartAlbum(album.id)] ?? 0)
                .tag(SidebarSelection.smartAlbum(album.id))
                .contextMenu {
                    Button("Edit…") { model.sidebarSheet = .smartAlbum(album, projectID: album.projectID) }
                    Button("Delete…", role: .destructive) { model.sidebarDeletion = .smartAlbum(album) }
                }
        }
    }

    private func projectRow(_ summary: ProjectSummary) -> some View {
        Label(summary.project.name, systemImage: "folder")
            .badge(summary.versionCount)
            .tag(SidebarSelection.project(summary.id))
            .help(summary.project.sourcePath ?? summary.project.name)
            .onDrop(of: FolderDrop.types, isTargeted: nil) { FolderDrop.accept($0, model: model) }
            .contextMenu {
                Button("New Album in Project…") { model.sidebarSheet = .newAlbum(projectID: summary.id) }
                Button("New Smart Album in Project…") { model.sidebarSheet = .smartAlbum(nil, projectID: summary.id) }
            }
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
}

enum RatingText {
    static func stars(_ count: Int) -> String {
        String(repeating: "★", count: count)
    }

    static func atLeast(_ count: Int) -> String {
        count == 5 ? stars(5) : String(localized: "\(stars(count)) or Better", comment: "Rating filter. The argument is a row of stars.")
    }
}
