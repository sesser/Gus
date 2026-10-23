import PhotoCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: LibraryModel
    @State private var renaming: KeywordSummary?
    @State private var newName = ""
    @State private var deleting: KeywordSummary?
    @AppStorage("sidebar.keywordsExpanded") private var keywordsExpanded = true

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section("Library") {
                Label {
                    HStack {
                        Text("All Photos")
                        Spacer()
                        CountBadge(count: model.libraryCount)
                    }
                } icon: {
                    Image(systemName: "photo.on.rectangle")
                }
                .tag(SidebarSelection.allPhotos)
            }
            Section("Projects") {
                if model.projects.isEmpty {
                    Text("Import a folder to create a project.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.projects) { summary in
                    Label {
                        HStack {
                            Text(summary.project.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            CountBadge(count: summary.versionCount)
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .tag(SidebarSelection.project(summary.id))
                    .help(summary.project.sourcePath ?? summary.project.name)
                }
            }
            Section("Keywords", isExpanded: $keywordsExpanded) {
                if model.keywords.isEmpty {
                    Text("Select photos and press ⌘K to add keywords.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.keywords) { keyword in
                    Label {
                        HStack {
                            Text(keyword.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            CountBadge(count: keyword.count)
                        }
                    } icon: {
                        Image(systemName: "tag")
                    }
                    .tag(SidebarSelection.keyword(keyword.id))
                    .contextMenu {
                        Button("Rename…") {
                            newName = keyword.name
                            renaming = keyword
                        }
                        Button("Delete…", role: .destructive) { deleting = keyword }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .alert("Rename Keyword", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               presenting: renaming) { keyword in
            TextField("Name", text: $newName)
            Button("Rename") { model.renameKeyword(keyword.id, to: newName) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Using the name of another keyword merges the two.")
        }
        .confirmationDialog(deletingTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { keyword in
            Button("Delete Keyword", role: .destructive) { model.deleteKeyword(keyword.id) }
        } message: { keyword in
            Text("It is removed from \(keyword.count) photos. The photos stay in the library.")
        }
        .safeAreaInset(edge: .bottom) {
            FilterPanel(model: model)
        }
    }
}

extension SidebarView {
    private var deletingTitle: String {
        String(localized: "Delete the keyword “\(deleting?.name ?? "")”?")
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
