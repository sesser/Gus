import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// Right-hand panel: Info (keywords and details) or Adjust (the loupe's photo).
struct InspectorView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $model.inspectorTab) {
                Text("Info").tag(InspectorTab.info)
                Text("Adjust").tag(InspectorTab.adjust)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            switch model.inspectorTab {
            case .info: InfoInspector(model: model)
            case .adjust: AdjustView(model: model)
            }
        }
    }
}

/// Histogram and details of the focused photo, then keywords of the selection.
private struct InfoInspector: View {
    let model: LibraryModel
    @State private var usage: [KeywordUsage] = []
    @State private var targetCount = 0
    @State private var details: VersionDetails?
    @State private var suggestions = SuggestionSummary()
    @State private var diskChanges: [DiskChange] = []

    var body: some View {
        AppKitScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.focusedItem?.isVideo != true {
                    InfoHistogram(model: model)
                }
                if let details {
                    InfoSection(details: details, item: model.focusedItem)
                    Divider()
                }
                if !diskChanges.isEmpty {
                    DiskChangeSection(model: model, changes: diskChanges)
                    Divider()
                }
                keywordsSection
                if targetCount > 0 {
                    suggestionsSection
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
                AppKitButton(title: String(localized: "Suggest Keywords for \(suggestions.unanalyzedCount) Photos")) {
                    model.suggestKeywords(for: model.actionTargetVersionIDs)
                }
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
            AppKitButton(title: suggestion.name, detail: total > 1 ? suggestion.count.formatted() : nil,
                         symbol: "plus", symbolWeight: .bold, style: .borderless,
                         help: String(localized: "Add this keyword to the selected photos it was suggested for")) {
                model.acceptSuggestion(suggestion.name)
            }
            AppKitButton(symbol: "xmark", symbolWeight: .bold, style: .borderless,
                         font: .preferredFont(forTextStyle: .caption2), tint: .secondaryLabelColor,
                         help: String(localized: "Don't suggest this keyword for these photos again")) {
                model.dismissSuggestion(suggestion.name)
            }
        }
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
                AppKitButton(symbol: "plus.circle", style: .borderless, tint: .controlAccentColor,
                             help: String(localized: "Add to all selected photos")) {
                    model.addKeywords([entry.keyword.name])
                }
            }
            AppKitButton(symbol: "xmark.circle.fill", style: .borderless, tint: .secondaryLabelColor,
                         help: String(localized: "Remove from the selected photos")) {
                if let id = entry.keyword.id { model.removeKeyword(id) }
            }
        }
        .font(.callout)
    }
}

/// Histogram of the focused photo: live while the loupe edits it, otherwise
/// counted from its cached thumbnail (which shows its saved adjustments).
private struct InfoHistogram: View {
    let model: LibraryModel
    @State private var loaded: Histogram?

    var body: some View {
        HistogramView(histogram: liveHistogram ?? loaded)
            .frame(height: 110)
            .task(id: Key(versionID: model.focusedItem?.versionID, editStackHash: model.focusedItem?.editStackHash)) {
                loaded = nil
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled, let item = model.focusedItem,
                      let request = model.previewRequest(for: item, tier: .thumbnail),
                      let image = try? await model.previews.image(for: request)
                else { return }
                let decoded = DecodedImage(cgImage: image)
                let counted = await Task.detached(priority: .utility) { Histogram(image: decoded.cgImage) }.value
                guard !Task.isCancelled else { return }
                loaded = counted
            }
    }

    private struct Key: Equatable {
        var versionID: Int64?
        var editStackHash: String?
    }

    private var liveHistogram: Histogram? {
        let editor = model.editor
        guard editor.state == .ready, editor.item?.versionID == model.focusedItem?.versionID else { return nil }
        return editor.histogram
    }
}

/// Red, green and blue counts drawn over each other; where they overlap the
/// colors add up to white.
struct HistogramView: View {
    let histogram: Histogram?

    var body: some View {
        Canvas { context, size in
            guard let histogram else { return }
            let plot = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            // Clipped ends would flatten everything else; scale to the tallest inner bin.
            let channels: [([UInt32], Color)] = [(histogram.red, .red), (histogram.green, .green), (histogram.blue, .blue)]
            let peak = max(Double(channels.compactMap { $0.0.dropFirst().dropLast().max() }.max() ?? 1), 1)
            context.blendMode = .plusLighter
            for (bins, color) in channels {
                var path = Path()
                path.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                for (index, count) in bins.enumerated() {
                    let x = plot.minX + CGFloat(index) / CGFloat(bins.count - 1) * plot.width
                    let height = min(Double(count) / peak, 1) * plot.height
                    path.addLine(to: CGPoint(x: x, y: plot.maxY - height))
                }
                path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.55)))
            }
        }
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(Text("Histogram"))
    }
}

/// Camera, exposure, capture date and file of the focused photo.
private struct InfoSection: View {
    let details: VersionDetails
    let item: CatalogItem?

    var body: some View {
        let image = details.image
        VStack(alignment: .leading, spacing: 14) {
            if let camera = CameraSummary.displayName(make: image.cameraMake, model: image.cameraModel) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(camera)
                        .font(.title3.weight(.bold))
                        .textSelection(.enabled)
                    if let lens = image.lensModel {
                        Text(lens)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
            if hasExposure {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        ExposureTile(label: String(localized: "Shutter"), value: shutter)
                        ExposureTile(label: String(localized: "Aperture"), value: aperture)
                        ExposureTile(label: String(localized: "ISO"), value: image.iso.map { "\($0)" })
                    }
                    if image.exposureCompensation != nil || image.flashFired != nil {
                        HStack(spacing: 6) {
                            if let compensation = image.exposureCompensation {
                                InfoIndicator(symbol: "plusminus", text: Self.compensationText(compensation),
                                              isActive: compensation != 0,
                                              help: String(localized: "Exposure compensation"))
                            }
                            if let fired = image.flashFired {
                                InfoIndicator(symbol: fired ? "bolt.fill" : "bolt.slash",
                                              text: fired ? String(localized: "Flash fired") : String(localized: "No flash"),
                                              isActive: fired, help: nil)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if let size = sizeLine {
                        Text(size)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else if let size = sizeLine {
                Text(size)
                    .font(.caption)
            }
            if let date = LoupeInfoBar.captureDateText(image) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Captured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(date)
                        .font(.title3)
                        .textSelection(.enabled)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Filename")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(image.fileName)
                        .font(.headline)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if let partner = item?.partnerKind, let kind = item?.fileKind {
                        Text(verbatim: "\(FileKindText.badge(kind)) + \(FileKindText.badge(partner))")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .help("Shown as one photo with its partner file")
                    }
                }
                Text(folder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if details.volume.mountPath != "/" {
                    Text("On \(details.volume.name)", comment: "The disk a photo's file is on")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasExposure: Bool {
        let image = details.image
        return image.exposureTime != nil || image.fNumber != nil || image.iso != nil
            || image.exposureCompensation != nil || image.flashFired != nil
    }

    /// "+0.7 EV", "−1.3 EV", "0 EV".
    static func compensationText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let magnitude = abs(rounded).formatted(.number.precision(.fractionLength(0...1)))
        let signed = rounded > 0 ? "+" + magnitude : rounded < 0 ? "−" + magnitude : magnitude
        return String(localized: "\(signed) EV", comment: "Exposure compensation; the argument is a signed number")
    }

    private var shutter: String? {
        guard let time = details.image.exposureTime, time > 0 else { return nil }
        return time < 1 ? "1/\(Int((1 / time).rounded()))" : time.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var aperture: String? {
        details.image.fNumber.map { $0.formatted(.number.precision(.fractionLength(0...1))) }
    }

    /// "51 mm – 24 MP (6,048 × 4,024 px)"
    private var sizeLine: String? {
        let image = details.image
        var parts: [String] = []
        if let focal = image.focalLength {
            parts.append(String(localized: "\(Int(focal.rounded())) mm", comment: "Focal length"))
        }
        if let width = image.pixelWidth, let height = image.pixelHeight, width > 0, height > 0 {
            let megapixels = (Double(width * height) / 1_000_000).rounded()
            parts.append(String(localized: "\(Int(megapixels).formatted()) MP (\(width.formatted()) × \(height.formatted()) px)",
                                comment: "Megapixels, then width and height in pixels"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " – ")
    }

    /// The folder on its volume, as "Users/name/Pictures/".
    private var folder: String {
        let directory = (details.image.relativePath as NSString).deletingLastPathComponent
        return directory.isEmpty ? "/" : directory + "/"
    }
}

/// A small capsule for a capture setting; dimmed when it had no effect.
private struct InfoIndicator: View {
    let symbol: String
    let text: String
    let isActive: Bool
    let help: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(text)
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .help(help ?? "")
    }
}

private struct ExposureTile: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "–")
                .font(.title2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
