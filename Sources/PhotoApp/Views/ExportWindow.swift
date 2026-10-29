import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// Exports the selected photos to a folder: names, file type, size,
/// metadata and a watermark, with presets for the whole set of options.
struct ExportWindow: View {
    let model: LibraryModel
    @Environment(\.dismissWindow) private var dismissWindow

    private var export: ExportModel { model.export }

    var body: some View {
        @Bindable var export = export
        VStack(spacing: 0) {
            HSplitView {
                ExportOptionsForm(export: export)
                    .frame(minWidth: 400, idealWidth: 440, maxWidth: 520)
                WatermarkPreview(export: export)
                    .frame(minWidth: 320)
            }
            Divider()
            footer
                .padding(12)
        }
        .frame(minWidth: 760, minHeight: 560)
        .preferredColorScheme(.dark)
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
        dismissWindow(id: "export")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let message = export.message {
                    Text(message)
                        .foregroundStyle(.orange)
                }
                if export.skippedVideos > 0 {
                    Text("\(export.skippedVideos) videos are not exported.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            Spacer()
            Toggle("Show in Finder when done", isOn: Binding(get: { export.revealsInFinder },
                                                              set: { export.revealsInFinder = $0 }))
            Button("Cancel", role: .cancel) { dismissWindow(id: "export") }
                .keyboardShortcut(.cancelAction)
            Button("Export \(export.versionIDs.count) Photos") {
                Task {
                    if await export.requestExport() { dismissWindow(id: "export") }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(export.versionIDs.isEmpty || export.isExporting)
        }
    }
}

private struct ExportOptionsForm: View {
    @Bindable var export: ExportModel
    @State private var savingPreset = false
    @State private var presetName = ""

    private var settings: Binding<ExportSettings> { $export.settings }

    var body: some View {
        Form {
            presetSection
            Section("Destination") {
                LabeledContent("Folder") {
                    HStack {
                        Text(export.destination.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(export.destination.path)
                        Button("Choose…") { export.chooseDestination() }
                    }
                }
            }
            namingSection
            formatSection
            sizeSection
            Section("Metadata") {
                Picker("Include", selection: settings.metadata) {
                    Text("All metadata").tag(ExportSettings.Metadata.all)
                    Text("All except location").tag(ExportSettings.Metadata.noLocation)
                    Text("Copyright and contact only").tag(ExportSettings.Metadata.copyright)
                    Text("None").tag(ExportSettings.Metadata.none)
                }
                .pickerStyle(.radioGroup)
                Text("Keywords and captions come from the library. Ratings and labels are never included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            watermarkSection
        }
        .formStyle(.grouped)
        .alert("Save Export Preset", isPresented: $savingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { export.savePreset(named: presetName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var presetSection: some View {
        Section("Preset") {
            Picker("Preset", selection: Binding(get: { export.presetID }, set: { export.applyPreset(id: $0) })) {
                Text("None").tag(Int64?.none)
                ForEach(export.presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            HStack {
                Button("Save as Preset…") {
                    presetName = export.presets.first { $0.id == export.presetID }?.name ?? ""
                    savingPreset = true
                }
                if let modified = export.modifiedPreset {
                    Button("Update “\(modified.name)”") { export.updateSelectedPreset() }
                }
                Spacer()
                if export.presetID != nil {
                    Button("Delete Preset", role: .destructive) { export.deleteSelectedPreset() }
                }
            }
        }
    }

    private var namingSection: some View {
        Section("File Names") {
            Picker("Name", selection: settings.naming) {
                Text("Original name").tag(ExportSettings.Naming.original)
                Text("Template").tag(ExportSettings.Naming.template)
            }
            .pickerStyle(.segmented)
            if export.settings.naming == .template {
                TemplateField(title: String(localized: "Template"), text: settings.fileNameTemplate,
                              tokens: TemplateField.exportFileTokens)
            }
            if let example = export.example {
                LabeledContent("Example") {
                    Text(example)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var formatSection: some View {
        Section("File Type") {
            Picker("Format", selection: settings.format) {
                Text("JPEG").tag(ExportSettings.FileFormat.jpeg)
                Text("TIFF").tag(ExportSettings.FileFormat.tiff)
            }
            .pickerStyle(.segmented)
            switch export.settings.format {
            case .jpeg:
                LabeledContent("Quality") {
                    HStack {
                        Slider(value: settings.jpegQuality, in: 0.1...1, step: 0.01)
                        Text(export.settings.jpegQuality.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            case .tiff:
                Picker("Bit depth", selection: settings.tiffBitDepth) {
                    Text("8 bits per channel").tag(8)
                    Text("16 bits per channel").tag(16)
                }
                Picker("Compression", selection: settings.tiffCompression) {
                    Text("None").tag(ExportSettings.TIFFCompression.none)
                    Text("LZW").tag(ExportSettings.TIFFCompression.lzw)
                    Text("ZIP").tag(ExportSettings.TIFFCompression.zip)
                }
            }
            Picker("Color space", selection: settings.colorSpace) {
                Text("sRGB").tag(ExportSettings.ColorSpace.sRGB)
                Text("Display P3").tag(ExportSettings.ColorSpace.displayP3)
                Text("Adobe RGB (1998)").tag(ExportSettings.ColorSpace.adobeRGB)
                Text("ProPhoto RGB").tag(ExportSettings.ColorSpace.proPhoto)
            }
            if export.settings.colorSpace.prefersHighBitDepth, export.settings.bitsPerComponent == 8 {
                Text("ProPhoto RGB is so wide that 8 bits per channel can show banding. 16-bit TIFF avoids it.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var sizeSection: some View {
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
                    HStack {
                        TextField("Width", value: settings.boxWidth, format: .number)
                            .labelsHidden()
                            .frame(width: 70)
                        Text(verbatim: "×")
                        TextField("Height", value: settings.boxHeight, format: .number)
                            .labelsHidden()
                            .frame(width: 70)
                        Text("pixels")
                    }
                }
            case .longEdge, .shortEdge:
                LabeledContent("Length") {
                    HStack {
                        TextField("Length", value: settings.edgeLength, format: .number)
                            .labelsHidden()
                            .frame(width: 70)
                        Text("pixels")
                    }
                }
            case .percent:
                LabeledContent("Scale") {
                    HStack {
                        Slider(value: settings.percent, in: 1...100, step: 1)
                        Text(verbatim: (export.settings.percent / 100).formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            LabeledContent("Resolution") {
                HStack {
                    TextField("Resolution", value: settings.ppi, format: .number)
                        .labelsHidden()
                        .frame(width: 70)
                    Text("pixels per inch")
                }
            }
            Text("Photos are never enlarged.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if export.settings.sizing != .full {
                Picker("Output sharpening", selection: settings.sharpening) {
                    Text("Off").tag(ExportSettings.SharpeningAmount.off)
                    Text("Light").tag(ExportSettings.SharpeningAmount.light)
                    Text("Standard").tag(ExportSettings.SharpeningAmount.standard)
                    Text("Strong").tag(ExportSettings.SharpeningAmount.strong)
                }
                if export.settings.sharpening != .off {
                    Picker("Sharpen for", selection: settings.sharpeningTarget) {
                        Text("Screen").tag(ExportSettings.SharpeningTarget.screen)
                        Text("Print").tag(ExportSettings.SharpeningTarget.print)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var watermarkSection: some View {
        Section("Watermark") {
            Toggle("Add a watermark", isOn: settings.watermarkEnabled)
                .disabled(export.settings.watermark == nil)
            LabeledContent("Image") {
                HStack {
                    if let watermark = export.settings.watermark {
                        Text(watermark.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Choose PNG…") { export.chooseWatermark() }
                }
            }
            if export.settings.watermark != nil, export.settings.watermarkEnabled {
                LabeledContent("Position") {
                    AnchorGrid(anchor: Binding(get: { export.settings.watermark?.anchor ?? .bottomRight },
                                               set: { export.settings.watermark?.anchor = $0 }))
                }
                watermarkSlider("Size", \.size, Watermark.sizeRange)
                watermarkSlider("Margin", \.margin, Watermark.marginRange)
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: Binding(get: { export.settings.watermark?.opacity ?? 1 },
                                              set: { export.settings.watermark?.opacity = $0 }), in: 0.05...1)
                        Text((export.settings.watermark?.opacity ?? 1).formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// A slider for a percentage of the image's long edge.
    private func watermarkSlider(_ title: LocalizedStringKey, _ path: WritableKeyPath<Watermark, Double>,
                                 _ range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: Binding(get: { export.settings.watermark?[keyPath: path] ?? range.lowerBound },
                                      set: { export.settings.watermark?[keyPath: path] = $0 }), in: range, step: 0.5)
                Text(verbatim: ((export.settings.watermark?[keyPath: path] ?? 0) / 100)
                    .formatted(.percent.precision(.fractionLength(0...1))))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
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
            Text("Preview of the first photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.black.opacity(0.35))
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
