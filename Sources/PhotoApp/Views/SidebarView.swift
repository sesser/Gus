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
            Section("Library") {
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
                Section("Dates", isExpanded: $datesExpanded) {
                    ForEach(years, id: \.year) { year in
                        DisclosureGroup(isExpanded: expansion(of: year.year, in: $expandedYears)) {
                            ForEach(year.months) { month in
                                SidebarRow(title: MonthText.monthOnly(year: month.year, month: month.month),
                                           symbol: "calendar", count: month.count)
                                    .tag(SidebarSelection.month(year: month.year, month: month.month))
                            }
                        } label: {
                            SidebarRow(title: String(year.year), symbol: "calendar", count: year.count)
                                .tag(SidebarSelection.year(year.year))
                        }
                    }
                }
            }
            Section("Albums", isExpanded: $albumsExpanded) {
                let albums = model.albums.filter { $0.album.projectId == nil }
                let smart = model.smartAlbums.filter { $0.projectID == nil }
                if albums.isEmpty, smart.isEmpty {
                    Text("Use File ▸ New Album to make one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                albumRows(albums, smart)
            }
            Section("Projects") {
                if model.projects.isEmpty {
                    Text("Import a folder to create a project.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
            }
            Section("Keywords", isExpanded: $keywordsExpanded) {
                if model.keywords.isEmpty {
                    Text("Select photos and press ⌘K to add keywords.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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
        .safeAreaInset(edge: .bottom) {
            FilterPanel(model: model)
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
    private func albumRows(_ albums: [AlbumSummary], _ smart: [SmartAlbum]) -> some View {
        // Album and smart album ids come from different tables, so they can
        // coincide; the uuids keep the rows apart.
        ForEach(albums, id: \.album.uuid) { album in
            SidebarRow(title: album.album.name, symbol: "rectangle.stack", count: album.count)
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
            SidebarRow(title: album.name, symbol: "gearshape", count: model.sidebarCounts[.smartAlbum(album.id)])
                .tag(SidebarSelection.smartAlbum(album.id))
                .contextMenu {
                    Button("Edit…") { model.sidebarSheet = .smartAlbum(album, projectID: album.projectID) }
                    Button("Delete…", role: .destructive) { deletion = .smartAlbum(album) }
                }
        }
    }

    private func projectRow(_ summary: ProjectSummary) -> some View {
        SidebarRow(title: summary.project.name, symbol: "folder", count: summary.versionCount)
            .tag(SidebarSelection.project(summary.id))
            .help(summary.project.sourcePath ?? summary.project.name)
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

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let count: Int?

    var body: some View {
        Label {
            HStack {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let count { CountBadge(count: count) }
            }
        } icon: {
            Image(systemName: symbol)
        }
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

/// Rating and flag filters for whatever the sidebar has selected.
private struct FilterPanel: View {
    @Bindable var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Filter")
                    .font(.headline)
                Spacer()
                if model.isFiltered {
                    Button("Clear") {
                        model.ratingRule = .any
                        model.flagRule = .any
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
            Picker("Rating", selection: $model.ratingRule) {
                Text("Any rating").tag(LibraryFilter.RatingRule.any)
                Text("Unrated").tag(LibraryFilter.RatingRule.unrated)
                Divider()
                ForEach(1...5, id: \.self) { stars in
                    Text(RatingText.atLeast(stars)).tag(LibraryFilter.RatingRule.atLeast(Rating(clamping: stars)))
                }
            }
            Picker("Flag", selection: $model.flagRule) {
                Text("Any flag").tag(LibraryFilter.FlagRule.any)
                Text("Picked").tag(LibraryFilter.FlagRule.picked)
                Text("Not rejected").tag(LibraryFilter.FlagRule.notRejected)
                Text("Unflagged").tag(LibraryFilter.FlagRule.unflagged)
                Text("Rejected").tag(LibraryFilter.FlagRule.rejected)
            }
        }
        .pickerStyle(.menu)
        .padding(12)
        .background(.bar)
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
