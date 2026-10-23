import PhotoCore
import SwiftUI

/// Right-hand panel: keywords of the selection and details of the focused photo.
struct InspectorView: View {
    let model: LibraryModel
    @State private var usage: [KeywordUsage] = []
    @State private var targetCount = 0
    @State private var details: VersionDetails?
    @State private var suggestions = SuggestionSummary()
    @State private var diskChanges: [DiskChange] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !diskChanges.isEmpty {
                    DiskChangeSection(model: model, changes: diskChanges)
                    Divider()
                }
                keywordsSection
                if targetCount > 0 {
                    suggestionsSection
                }
                if let details {
                    Divider()
                    InfoSection(details: details, item: model.focusedItem)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: Reload(selection: model.selectionRevision, keywords: model.keywordRevision,
                         suggestions: model.suggestionRevision, disk: model.diskChangeRevision,
                         focus: model.focusedItem?.versionID)) {
            // Coalesces bursts of selection changes (shift-arrowing through a shoot).
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let ids = model.actionTargetVersionIDs
            let loaded = (try? await model.catalog.keywordUsage(forVersions: ids)) ?? []
            let loadedDetails = try? await model.catalog.details(forVersion: model.focusedItem?.versionID ?? -1)
            let loadedSuggestions = (try? await model.catalog.suggestionSummary(forVersions: ids)) ?? SuggestionSummary()
            let loadedChanges = model.diskChangeCount > 0 ? ((try? await model.catalog.diskChanges(forVersions: ids)) ?? []) : []
            guard !Task.isCancelled else { return }
            diskChanges = loadedChanges
            usage = loaded
            suggestions = loadedSuggestions
            targetCount = ids.count
            details = loadedDetails
        }
    }

    private struct Reload: Equatable {
        var selection: Int
        var keywords: Int
        var suggestions: Int
        var disk: Int
        var focus: Int64?
    }

    /// Chips for keywords the on-device analysis suggests; clicking one adds it.
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Suggested")
                    .font(.headline)
                Spacer()
                if let progress = model.suggestionProgress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 60)
                        .help("Looking at photos for keyword suggestions")
                }
            }
            if suggestions.suggestions.isEmpty, suggestions.unanalyzedCount == 0 {
                Text("No suggestions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(suggestions.suggestions) { suggestion in
                    SuggestionChip(suggestion: suggestion, total: targetCount, model: model)
                }
            }
            if suggestions.unanalyzedCount > 0, model.suggestionProgress == nil {
                Button("Suggest Keywords for \(suggestions.unanalyzedCount) Photos") {
                    model.suggestKeywords(for: model.actionTargetVersionIDs)
                }
                .controlSize(.small)
            }
        }
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

private struct SuggestionChip: View {
    let suggestion: SuggestionUsage
    let total: Int
    let model: LibraryModel

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.acceptSuggestion(suggestion.name)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.bold))
                    Text(suggestion.name)
                    if total > 1 {
                        Text(suggestion.count, format: .number)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Add this keyword to the selected photos it was suggested for")
            Button {
                model.dismissSuggestion(suggestion.name)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Don't suggest this keyword for these photos again")
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

/// Lays out children left to right, wrapping to new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
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
        if let date = LoupeInfoBar.captureDateText(image) {
            rows.append(Row(label: String(localized: "Captured"), value: date))
        }
        if let camera = [image.cameraMake, image.cameraModel].compactMap({ $0 }).joined(separator: " ").nilIfEmpty {
            rows.append(Row(label: String(localized: "Camera"), value: camera))
        }
        if let lens = image.lensModel {
            rows.append(Row(label: String(localized: "Lens"), value: lens))
        }
        if let width = image.pixelWidth, let height = image.pixelHeight {
            rows.append(Row(label: String(localized: "Size"), value: String(localized: "\(width) × \(height) px")))
        }
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
