import PhotoCore
import SwiftUI

/// Right-hand panel: keywords of the selection and details of the focused photo.
struct InspectorView: View {
    let model: LibraryModel
    @State private var usage: [KeywordUsage] = []
    @State private var targetCount = 0
    @State private var details: VersionDetails?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                keywordsSection
                if let details {
                    Divider()
                    InfoSection(details: details, item: model.focusedItem)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: Reload(selection: model.selectionRevision, keywords: model.keywordRevision,
                         focus: model.focusedItem?.versionID)) {
            // Coalesces bursts of selection changes (shift-arrowing through a shoot).
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let ids = model.actionTargetVersionIDs
            let loaded = (try? await model.catalog.keywordUsage(forVersions: ids)) ?? []
            let loadedDetails = try? await model.catalog.details(forVersion: model.focusedItem?.versionID ?? -1)
            guard !Task.isCancelled else { return }
            usage = loaded
            targetCount = ids.count
            details = loadedDetails
        }
    }

    private struct Reload: Equatable {
        var selection: Int
        var keywords: Int
        var focus: Int64?
    }

    private var keywordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Keywords")
                    .font(.headline)
                Spacer()
                if targetCount > 1 {
                    Text("\(targetCount) photos selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if targetCount == 0 {
                Text("Select photos to see and change their keywords.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if usage.isEmpty {
                    Text("No keywords")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(usage) { entry in
                    KeywordRow(entry: entry, total: targetCount, model: model)
                }
                KeywordField(placeholder: String(localized: "Add keywords"), names: model.keywordNames,
                             onCommit: { model.addKeywords($0) })
            }
        }
    }
}

private struct KeywordRow: View {
    let entry: KeywordUsage
    let total: Int
    let model: LibraryModel

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.keyword.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if total > 1 {
                Text("\(entry.count) of \(total)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.count < total {
                Button {
                    model.addKeywords([entry.keyword.name])
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Add to all selected photos")
            }
            Button {
                if let id = entry.keyword.id { model.removeKeyword(id) }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove from the selected photos")
        }
        .font(.callout)
    }
}

/// File and capture details of the focused photo.
private struct InfoSection: View {
    let details: VersionDetails
    let item: CatalogItem?

    var body: some View {
        let image = details.image
        VStack(alignment: .leading, spacing: 6) {
            Text("Info")
                .font(.headline)
            Text(image.fileName)
                .font(.callout.weight(.medium))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(rows, id: \.label) { row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                        Text(row.value)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
            }
            .font(.caption)
        }
    }

    private struct Row {
        var label: String
        var value: String
    }

    private var rows: [Row] {
        let image = details.image
        var rows: [Row] = []
        let capture = LoupeInfoBar.captureLine(details)
        if !capture.isEmpty { rows.append(Row(label: String(localized: "Captured"), value: capture)) }
        let exposure = LoupeInfoBar.exposureLine(image)
        if !exposure.isEmpty { rows.append(Row(label: String(localized: "Exposure"), value: exposure)) }
        if let partner = item?.partnerKind, let kind = item?.fileKind {
            rows.append(Row(label: String(localized: "Pair"),
                            value: "\(FileKindText.badge(kind)) + \(FileKindText.badge(partner))"))
        }
        rows.append(Row(label: String(localized: "Volume"), value: details.volume.name))
        rows.append(Row(label: String(localized: "Path"), value: image.relativePath))
        return rows
    }
}
