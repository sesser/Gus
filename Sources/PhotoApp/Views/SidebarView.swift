import PhotoCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: LibraryModel

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
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            FilterPanel(model: model)
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
