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
private enum SidebarDeletion: Identifiable {
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
    @State private var deletion: SidebarDeletion?
    @AppStorage("sidebar.datesExpanded") private var datesExpanded = true
    @AppStorage("sidebar.albumsExpanded") private var albumsExpanded = true
    @AppStorage("sidebar.keywordsExpanded") private var keywordsExpanded = true
    @State private var expandedYears: Set<Int> = []
    @State private var expandedProjects: Set<Int64> = []

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section {
                SidebarHeader(title: "Library")
                    .selectionDisabled()
                SidebarRow(title: String(localized: "All Photos"), symbol: "photo.on.rectangle", count: model.libraryCount)
                    .tag(SidebarSelection.allPhotos)
                ForEach(BuiltInAlbum.allCases, id: \.self) { album in
                    SidebarRow(title: album.title, symbol: album.symbol, count: model.sidebarCounts[.builtIn(album)])
                        .tag(SidebarSelection.builtIn(album))
                }
                if model.diskChangeCount > 0 {
                    SidebarRow(title: String(localized: "Changed on Disk"), symbol: "exclamationmark.arrow.triangle.2.circlepath",
                               count: model.diskChangeCount)
                        .tag(SidebarSelection.changedOnDisk)
                        .help("Photos whose sidecar or file another app changed. Review them in the inspector.")
                }
            }
            if !model.captureMonths.isEmpty {
                Section {
                    SidebarHeader(title: "Dates", isExpanded: $datesExpanded)
                        .selectionDisabled()
                    if datesExpanded {
                        ForEach(years, id: \.year) { year in
                            let expanded = expansion(of: year.year, in: $expandedYears)
                            SidebarRow(title: String(year.year), symbol: "calendar", count: year.count, isExpanded: expanded)
                                .tag(SidebarSelection.year(year.year))
                            if expanded.wrappedValue {
                                ForEach(year.months) { month in
                                    SidebarRow(title: MonthText.monthOnly(year: month.year, month: month.month),
                                               symbol: "calendar", count: month.count, isNested: true)
                                        .tag(SidebarSelection.month(year: month.year, month: month.month))
                                }
                            }
                        }
                    }
                }
            }
            Section {
                SidebarHeader(title: "Albums", isExpanded: $albumsExpanded)
                    .selectionDisabled()
                let albums = model.albums.filter { $0.album.projectId == nil }
                let smart = model.smartAlbums.filter { $0.projectID == nil }
                if !albumsExpanded {
                    EmptyView()
                } else if albums.isEmpty, smart.isEmpty {
                    Text("Use File ▸ New Album to make one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    albumRows(albums, smart)
                }
            }
            Section {
                // Folders dropped on the header or any project row each become
                // a new project, as they do on the browser.
                SidebarHeader(title: "Projects")
                    .selectionDisabled()
                    .onDrop(of: FolderDrop.types, isTargeted: nil) { FolderDrop.accept($0, model: model) }
                if model.projects.isEmpty {
                    Text("Import or drop a folder here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .onDrop(of: FolderDrop.types, isTargeted: nil) { FolderDrop.accept($0, model: model) }
                }
                ForEach(model.projects) { summary in
                    let albums = model.albums.filter { $0.album.projectId == summary.id }
                    let smart = model.smartAlbums.filter { $0.projectID == summary.id }
                    if albums.isEmpty, smart.isEmpty {
                        projectRow(summary)
                    } else {
                        let expanded = expansion(of: summary.id, in: $expandedProjects)
                        projectRow(summary, isExpanded: expanded)
                        if expanded.wrappedValue {
                            albumRows(albums, smart, isNested: true)
                        }
                    }
                }
            }
            Section {
                SidebarHeader(title: "Keywords", isExpanded: $keywordsExpanded)
                    .selectionDisabled()
                if !keywordsExpanded {
                    EmptyView()
                } else if model.keywords.isEmpty {
                    Text("Select photos and press ⌘K to add keywords.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.keywords) { keyword in
                        SidebarRow(title: keyword.name, symbol: "tag", count: keyword.count)
                            .tag(SidebarSelection.keyword(keyword.id))
                            .onDrop(of: [.photoVersions], isTargeted: nil) { _ in
                                model.addKeywords([keyword.name], to: model.draggedVersionIDs)
                                return true
                            }
                            .contextMenu {
                                Button("Rename…") { model.sidebarSheet = .renameKeyword(keyword) }
                                Button("Delete…", role: .destructive) { deletion = .keyword(keyword) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(item: $model.sidebarSheet) { sheet in
            SidebarSheetView(model: model, sheet: sheet)
        }
        .confirmationDialog(deletionTitle, isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
                            presenting: deletion) { deletion in
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
        switch deletion {
        case .keyword(let keyword): String(localized: "Delete the keyword “\(keyword.name)”?")
        case .album(let album): String(localized: "Delete the album “\(album.album.name)”?")
        case .smartAlbum(let album): String(localized: "Delete the smart album “\(album.name)”?")
        case nil: ""
        }
    }

    @ViewBuilder
    private func albumRows(_ albums: [AlbumSummary], _ smart: [SmartAlbum], isNested: Bool = false) -> some View {
        // Album and smart album ids come from different tables, so they can
        // coincide; the uuids keep the rows apart.
        ForEach(albums, id: \.album.uuid) { album in
            SidebarRow(title: album.album.name, symbol: "rectangle.stack", count: album.count, isNested: isNested)
                .tag(SidebarSelection.album(album.id))
                .onDrop(of: [.photoVersions], isTargeted: nil) { _ in
                    model.addToAlbum(album.id, versionIDs: model.draggedVersionIDs)
                    return true
                }
                .contextMenu {
                    Button("Rename…") { model.sidebarSheet = .renameAlbum(album) }
                    Button("Delete…", role: .destructive) { deletion = .album(album) }
                }
        }
        ForEach(smart, id: \.uuid) { album in
            SidebarRow(title: album.name, symbol: "gearshape", count: model.sidebarCounts[.smartAlbum(album.id)],
                       isNested: isNested)
                .tag(SidebarSelection.smartAlbum(album.id))
                .contextMenu {
                    Button("Edit…") { model.sidebarSheet = .smartAlbum(album, projectID: album.projectID) }
                    Button("Delete…", role: .destructive) { deletion = .smartAlbum(album) }
                }
        }
    }

    private func projectRow(_ summary: ProjectSummary, isExpanded: Binding<Bool>? = nil) -> some View {
        // Every project keeps room for a chevron, so the counts line up.
        SidebarRow(title: summary.project.name, symbol: "folder", count: summary.versionCount,
                   isExpanded: isExpanded, reservesChevron: true)
            .tag(SidebarSelection.project(summary.id))
            .help(summary.project.sourcePath ?? summary.project.name)
            .onDrop(of: FolderDrop.types, isTargeted: nil) { FolderDrop.accept($0, model: model) }
            .contextMenu {
                Button("New Album in Project…") { model.sidebarSheet = .newAlbum(projectID: summary.id) }
                Button("New Smart Album in Project…") { model.sidebarSheet = .smartAlbum(nil, projectID: summary.id) }
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

/// A section heading in the inspector's heading style. Collapsible sections
/// get a chevron that stays visible, so a collapsed section still reads as one.
///
/// The sidebar draws its own chevrons: the list gives every section header a
/// hover chevron (even with `.collapsible(false)`), and as soon as any row can
/// expand (a `DisclosureGroup`) it indents every row to make room for the
/// triangles. So headings are their section's first row, and years and
/// projects expand by inserting their children as indented rows.
private struct SidebarHeader: View {
    let title: LocalizedStringKey
    var isExpanded: Binding<Bool>?

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if let isExpanded {
                DisclosureChevron(isExpanded: isExpanded.wrappedValue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isExpanded?.wrappedValue.toggle() }
        .help(isExpanded.map { DisclosureChevron.help($0.wrappedValue) } ?? "")
    }
}

private struct DisclosureChevron: View {
    let isExpanded: Bool

    static let width: CGFloat = 14

    static func help(_ isExpanded: Bool) -> String {
        isExpanded ? String(localized: "Collapse") : String(localized: "Expand")
    }

    var body: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: Self.width)
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let count: Int?
    /// Shows a chevron after the count that expands the row's children.
    var isExpanded: Binding<Bool>?
    /// Keeps room for a chevron, so counts line up with rows that have one.
    var reservesChevron = false
    /// A child of a year or project: indented, with room for its parent's chevron.
    var isNested = false

    var body: some View {
        Label {
            HStack {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let count { CountBadge(count: count) }
                if let isExpanded {
                    Button { isExpanded.wrappedValue.toggle() } label: {
                        DisclosureChevron(isExpanded: isExpanded.wrappedValue)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(DisclosureChevron.help(isExpanded.wrappedValue))
                } else if reservesChevron || isNested {
                    Color.clear.frame(width: DisclosureChevron.width, height: 1)
                }
            }
        } icon: {
            Image(systemName: symbol)
        }
        .padding(.leading, isNested ? 18 : 0)
    }
}

private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

enum RatingText {
    static func stars(_ count: Int) -> String {
        String(repeating: "★", count: count)
    }

    static func atLeast(_ count: Int) -> String {
        count == 5 ? stars(5) : String(localized: "\(stars(count)) or better")
    }
}
