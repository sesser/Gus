import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// Exports the selected photos (section 8 of docs/UI_REDESIGN.md): a sheet
/// on the library window, which freezes what it acts on. A fixed header, one
/// scrolling form column, then Cancel and Export. The export runs after the
/// sheet closes, with progress in the toolbar's Activity item.
struct ExportSheet: View {
    let model: LibraryModel

    private var export: ExportModel { model.export }

    var body: some View {
        @Bindable var export = export
        VStack(spacing: 0) {
            ExportHeader(model: model)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Divider()
            ExportForm(model: model)
            Divider()
            buttons
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 560)
        .frame(minHeight: 480, idealHeight: 640)
        .presentationSizing(.fitted)
        .alert(conflictTitle, isPresented: Binding(get: { export.conflict != nil },
                                                   set: { if !$0 { export.conflict = nil } })) {
            Button("Keep Both") { resolve(.keepBoth) }
                .keyboardShortcut(.defaultAction)
            Button("Replace", role: .destructive) { resolve(.overwrite) }
            Button("Skip Them") { resolve(.skip) }
            Button("Cancel", role: .cancel) { export.conflict = nil }
        } message: {
            Text("Keep Both writes the new files under numbered names.")
        }
    }

    private var conflictTitle: String {
        String(localized: "\(export.conflict?.count ?? 0) files already exist in “\(export.destination.lastPathComponent)”")
    }

    private func resolve(_ policy: ExportConflictPolicy) {
        export.resolveConflict(policy)
        model.showsExportSheet = false
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel", role: .cancel) { model.showsExportSheet = false }
                .keyboardShortcut(.cancelAction)
            Button(String(localized: "Export \(export.versionIDs.count) Photos")) {
                Task {
                    if await export.requestExport() { model.showsExportSheet = false }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(export.versionIDs.isEmpty || export.isExporting)
        }
    }
}

/// The first photo, how many are exported, and from where.
private struct ExportHeader: View {
    let model: LibraryModel

    var body: some View {
        let export = model.export
        HStack(spacing: 12) {
            Group {
                if let image = export.previewImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(nsColor: Palette.cell)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text("Export \(export.versionIDs.count) Photos")
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let issue = export.issue, issue.place == .general {
                    IssueText(text: issue.text)
                }
            }
            Spacer()
        }
    }

    /// "From All Photos · 3 videos are skipped".
    private var subtitle: String {
        let source = String(localized: "From \(model.title(for: model.sidebarSelection))", comment: "Export sheet: the sidebar source")
        let skipped = model.export.skippedVideos
        guard skipped > 0 else { return source }
        return [source, String(localized: "\(skipped) videos are skipped", comment: "Export sheet: videos are not exported")]
            .joined(separator: " · ")
    }
}

/// An error next to the row it concerns: a warning sign and the text.
private struct IssueText: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

/// A caption under the row it explains: 11 pt secondary.
private struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A number in a bezeled 72 pt field, right-aligned, its unit after it.
private struct NumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let unit: String

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
                .frame(width: 72)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

/// A continuous slider (no ticks) with its value in 44 pt of monospaced digits.
private struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// What the binding keeps: the slider moves freely, the value rounds.
    let step: Double
    let text: String

    var body: some View {
        HStack {
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                .labelsHidden()
            Text(verbatim: text)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}

private struct ExportForm: View {
    let model: LibraryModel
    @State private var savingPreset = false
    @State private var presetName = ""
    @State private var deletingPreset = false

    private var export: ExportModel { model.export }

    var body: some View {
        @Bindable var export = export
        let settings = $export.settings
        Form {
            presetRow
            Section("Destination") {
                LabeledContent("Folder") {
                    HStack {
                        Text(export.destination.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(export.destination.path)
                        Button("Choose Folder…") { export.chooseDestination(in: NSApp.keyWindow) }
                    }
                }
                Toggle("Show in Finder when done", isOn: $export.revealsInFinder)
                    .toggleStyle(.checkbox)
                if let issue = export.issue, issue.place == .destination { IssueText(text: issue.text) }
            }
            namingSection(settings)
            formatSection(settings)
            sizeSection(settings)
            Section("Metadata") {
                Picker("Include", selection: settings.metadata) {
                    Text("All metadata").tag(ExportSettings.Metadata.all)
                    Text("All except location").tag(ExportSettings.Metadata.noLocation)
                    Text("Copyright and contact only").tag(ExportSettings.Metadata.copyright)
                    Text("None").tag(ExportSettings.Metadata.none)
                }
                .pickerStyle(.radioGroup)
                Caption(text: String(localized: "Keywords and captions come from the library. Ratings and labels are never included."))
            }
            watermarkSection(settings)
        }
        .formStyle(.grouped)
        .alert("Save Export Preset", isPresented: $savingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { export.savePreset(named: presetName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(String(localized: "Delete the export preset “\(selectedPreset?.name ?? "")”?"), isPresented: $deletingPreset) {
            Button("Delete", role: .destructive) { export.deleteSelectedPreset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var selectedPreset: ExportPreset? {
        export.presets.first { $0.id == export.presetID }
    }

    /// One pop-up: None, the presets, then Save as Preset…, Update and Delete.
    private var presetRow: some View {
        LabeledContent("Preset") {
            Menu(selectedPreset?.name ?? String(localized: "None")) {
                Button("None") { export.applyPreset(id: nil) }
                ForEach(export.presets) { preset in
                    Button(preset.name) { export.applyPreset(id: preset.id) }
                }
                Divider()
                Button("Save as Preset…") {
                    presetName = selectedPreset?.name ?? ""
                    savingPreset = true
                }
                if let modified = export.modifiedPreset {
                    Button("Update “\(modified.name)”") { export.updateSelectedPreset() }
                }
                if let preset = selectedPreset {
                    Button("Delete “\(preset.name)”…") { deletingPreset = true }
                }
            }
            .fixedSize()
        }
        .overlay(alignment: .bottomLeading) {
            if let issue = export.issue, issue.place == .preset { IssueText(text: issue.text).offset(y: 18) }
        }
    }

    private func namingSection(_ settings: Binding<ExportSettings>) -> some View {
        Section("File Names") {
            Picker("Name", selection: settings.naming) {
                Text("Original Name").tag(ExportSettings.Naming.original)
                Text("Template").tag(ExportSettings.Naming.template)
            }
            .pickerStyle(.segmented)
            if export.settings.naming == .template {
                VStack(alignment: .leading, spacing: 4) {
                    TemplateField(title: String(localized: "Template"), text: settings.fileNameTemplate,
                                  tokens: TemplateField.exportFileTokens)
                    if let example = export.example {
                        Caption(text: example)
                            .textSelection(.enabled)
                    }
                }
            } else if let example = export.example {
                Caption(text: example)
            }
        }
    }

    private func formatSection(_ settings: Binding<ExportSettings>) -> some View {
        Section("File Type") {
            Picker("Format", selection: settings.format) {
                Text("JPEG").tag(ExportSettings.FileFormat.jpeg)
                Text("TIFF").tag(ExportSettings.FileFormat.tiff)
            }
            .pickerStyle(.segmented)
            switch export.settings.format {
            case .jpeg:
                LabeledContent("Quality") {
                    ValueSlider(value: settings.jpegQuality, range: 0.1...1, step: 0.01,
                                text: export.settings.jpegQuality.formatted(.percent.precision(.fractionLength(0))))
                }
            case .tiff:
                Picker("Bit Depth", selection: settings.tiffBitDepth) {
                    Text("8 bits per channel").tag(8)
                    Text("16 bits per channel").tag(16)
                }
                Picker("Compression", selection: settings.tiffCompression) {
                    Text("None").tag(ExportSettings.TIFFCompression.none)
                    Text("LZW").tag(ExportSettings.TIFFCompression.lzw)
                    Text("ZIP").tag(ExportSettings.TIFFCompression.zip)
                }
            }
            Picker("Color Space", selection: settings.colorSpace) {
                Text("sRGB").tag(ExportSettings.ColorSpace.sRGB)
                Text("Display P3").tag(ExportSettings.ColorSpace.displayP3)
                Text("Adobe RGB (1998)").tag(ExportSettings.ColorSpace.adobeRGB)
                Text("ProPhoto RGB").tag(ExportSettings.ColorSpace.proPhoto)
            }
            if export.settings.colorSpace.prefersHighBitDepth, export.settings.bitsPerComponent == 8 {
                IssueText(text: String(localized: "ProPhoto RGB is so wide that 8 bits per channel can show banding. 16-bit TIFF avoids it."))
            }
        }
    }

    private func sizeSection(_ settings: Binding<ExportSettings>) -> some View {
        Section("Size") {
            Picker("Size", selection: settings.sizing) {
                Text("Full size").tag(ExportSettings.Sizing.full)
                Text("Fit within").tag(ExportSettings.Sizing.fit)
                Text("Long edge").tag(ExportSettings.Sizing.longEdge)
                Text("Short edge").tag(ExportSettings.Sizing.shortEdge)
                Text("Percentage").tag(ExportSettings.Sizing.percent)
            }
            switch export.settings.sizing {
            case .full:
                EmptyView()
            case .fit:
                LabeledContent("Box") {
                    HStack(spacing: 6) {
                        NumberField(title: "Width", value: settings.boxWidth, unit: "")
                        Text(verbatim: "×").foregroundStyle(.secondary)
                        NumberField(title: "Height", value: settings.boxHeight, unit: String(localized: "pixels"))
                    }
                }
            case .longEdge, .shortEdge:
                LabeledContent("Length") {
                    NumberField(title: "Length", value: settings.edgeLength, unit: String(localized: "pixels"))
                }
            case .percent:
                LabeledContent("Scale") {
                    ValueSlider(value: settings.percent, range: 1...100, step: 1,
                                text: (export.settings.percent / 100).formatted(.percent.precision(.fractionLength(0))))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Resolution") {
                    NumberField(title: "Resolution", value: settings.ppi, unit: String(localized: "pixels per inch"))
                }
                Caption(text: String(localized: "Photos are never enlarged."))
            }
            if export.settings.sizing != .full {
                Picker("Output Sharpening", selection: settings.sharpening) {
                    Text("Off").tag(ExportSettings.SharpeningAmount.off)
                    Text("Light").tag(ExportSettings.SharpeningAmount.light)
                    Text("Standard").tag(ExportSettings.SharpeningAmount.standard)
                    Text("Strong").tag(ExportSettings.SharpeningAmount.strong)
                }
                if export.settings.sharpening != .off {
                    Picker("Sharpen For", selection: settings.sharpeningTarget) {
                        Text("Screen").tag(ExportSettings.SharpeningTarget.screen)
                        Text("Print").tag(ExportSettings.SharpeningTarget.print)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private func watermarkSection(_ settings: Binding<ExportSettings>) -> some View {
        Section("Watermark") {
            Toggle("Add a watermark", isOn: settings.watermarkEnabled)
                .toggleStyle(.checkbox)
                .disabled(export.settings.watermark == nil)
            LabeledContent("Image") {
                HStack {
                    if let watermark = export.settings.watermark {
                        Text(watermark.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Choose Image…") { export.chooseWatermark(in: NSApp.keyWindow) }
                }
            }
            if let issue = export.issue, issue.place == .watermark { IssueText(text: issue.text) }
            if export.settings.watermark != nil, export.settings.watermarkEnabled {
                LabeledContent("Position") {
                    AnchorGrid(anchor: Binding(get: { export.settings.watermark?.anchor ?? .bottomRight },
                                               set: { export.settings.watermark?.anchor = $0 }))
                }
                watermarkSlider("Size", \.size, Watermark.sizeRange, step: 0.5)
                watermarkSlider("Margin", \.margin, Watermark.marginRange, step: 0.5)
                LabeledContent("Opacity") {
                    ValueSlider(value: Binding(get: { export.settings.watermark?.opacity ?? 1 },
                                               set: { export.settings.watermark?.opacity = $0 }),
                                range: 0.05...1, step: 0.01,
                                text: (export.settings.watermark?.opacity ?? 1).formatted(.percent.precision(.fractionLength(0))))
                }
                // The first photo with the watermark, only while there is one.
                WatermarkPreview(export: export)
                    .frame(maxWidth: 520, minHeight: 220, maxHeight: 220)
            }
        }
    }

    /// A slider for a percentage of the image's long edge.
    private func watermarkSlider(_ title: LocalizedStringKey, _ path: WritableKeyPath<Watermark, Double>,
                                 _ range: ClosedRange<Double>, step: Double) -> some View {
        LabeledContent(title) {
            ValueSlider(value: Binding(get: { export.settings.watermark?[keyPath: path] ?? range.lowerBound },
                                       set: { export.settings.watermark?[keyPath: path] = $0 }),
                        range: range, step: step,
                        text: ((export.settings.watermark?[keyPath: path] ?? 0) / 100)
                            .formatted(.percent.precision(.fractionLength(0...1))))
        }
    }
}

/// Nine buttons, one per anchor.
private struct AnchorGrid: View {
    @Binding var anchor: Watermark.Anchor

    private let rows: [[Watermark.Anchor]] = [
        [.topLeft, .top, .topRight], [.left, .center, .right], [.bottomLeft, .bottom, .bottomRight],
    ]

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { candidate in
                        Button {
                            anchor = candidate
                        } label: {
                            Image(systemName: candidate == anchor ? "circle.inset.filled" : "circle")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(ExportText.anchorName(candidate))
                        .accessibilityAddTraits(candidate == anchor ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// The first photo with the watermark drawn where the export puts it.
private struct WatermarkPreview: View {
    let export: ExportModel

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                if let image = export.previewImage {
                    let size = fitted(CGSize(width: image.width, height: image.height), in: geometry.size)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: size.width, height: size.height)
                        if let watermark = export.settings.activeWatermark, let mark = export.watermarkImage {
                            let rect = WatermarkLayout.rect(imageSize: size,
                                                            watermarkSize: CGSize(width: mark.width, height: mark.height),
                                                            watermark: watermark, flipped: true)
                            Image(decorative: mark, scale: 1)
                                .resizable()
                                .frame(width: rect.width, height: rect.height)
                                .opacity(watermark.opacity)
                                .offset(x: rect.minX, y: rect.minY)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                } else {
                    ProgressView()
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
        .accessibilityLabel(Text("Preview of the first photo"))
    }

    private func fitted(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

enum ExportText {
    static func anchorName(_ anchor: Watermark.Anchor) -> String {
        switch anchor {
        case .topLeft: String(localized: "Top left")
        case .top: String(localized: "Top")
        case .topRight: String(localized: "Top right")
        case .left: String(localized: "Left")
        case .center: String(localized: "Center")
        case .right: String(localized: "Right")
        case .bottomLeft: String(localized: "Bottom left")
        case .bottom: String(localized: "Bottom")
        case .bottomRight: String(localized: "Bottom right")
        }
    }
}
