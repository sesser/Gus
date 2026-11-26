import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// Export's File Names, File Type, Size, Metadata and Watermark sections,
/// over an `ExportSettingsEditor`: the Export sheet's form and the Publish
/// sheet's File Settings page are this one form (issue #28, design §3.6).
struct ExportSettingsSections: View {
    @Bindable var editor: ExportSettingsEditor
    /// A watermark problem the host reports (Export: the missing image).
    var watermarkIssue: String?

    var body: some View {
        let settings = $editor.settings
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
            Caption(text: String(localized: "Keywords and descriptions come from the library. Ratings and labels are never included."))
        }
        watermarkSection(settings)
    }

    private func namingSection(_ settings: Binding<ExportSettings>) -> some View {
        Section("File Names") {
            Picker("Name", selection: settings.naming) {
                Text("Original Name").tag(ExportSettings.Naming.original)
                Text("Template").tag(ExportSettings.Naming.template)
            }
            .pickerStyle(.segmented)
            if editor.settings.naming == .template {
                TemplateField(title: String(localized: "Template"), text: settings.fileNameTemplate,
                              tokens: .exportFiles, sample: editor.exampleContext, example: editor.example)
            } else if let example = editor.example {
                TemplateExample(text: example)
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
            switch editor.settings.format {
            case .jpeg:
                LabeledContent("Quality") {
                    ValueSlider(value: settings.jpegQuality, range: 0.1...1, step: 0.01,
                                text: editor.settings.jpegQuality.formatted(.percent.precision(.fractionLength(0))))
                }
            case .tiff:
                Picker("Bit depth", selection: settings.tiffBitDepth) {
                    Text("8 Bits per Channel").tag(8)
                    Text("16 Bits per Channel").tag(16)
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
            if editor.settings.colorSpace.prefersHighBitDepth, editor.settings.bitsPerComponent == 8 {
                IssueText(text: String(localized: "ProPhoto RGB is so wide that 8 bits per channel can show banding. 16-bit TIFF avoids it."))
            }
        }
    }

    private func sizeSection(_ settings: Binding<ExportSettings>) -> some View {
        Section("Size") {
            Picker("Size", selection: settings.sizing) {
                Text("Full Size").tag(ExportSettings.Sizing.full)
                Text("Fit Within").tag(ExportSettings.Sizing.fit)
                Text("Long Edge").tag(ExportSettings.Sizing.longEdge)
                Text("Short Edge").tag(ExportSettings.Sizing.shortEdge)
                Text("Percentage").tag(ExportSettings.Sizing.percent)
            }
            switch editor.settings.sizing {
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
                                text: (editor.settings.percent / 100).formatted(.percent.precision(.fractionLength(0))))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Resolution") {
                    NumberField(title: "Resolution", value: settings.ppi, unit: String(localized: "pixels per inch"))
                }
                Caption(text: String(localized: "Photos are never enlarged."))
            }
            if editor.settings.sizing != .full {
                Picker("Output sharpening", selection: settings.sharpening) {
                    Text("Off").tag(ExportSettings.SharpeningAmount.off)
                    Text("Light").tag(ExportSettings.SharpeningAmount.light)
                    Text("Standard").tag(ExportSettings.SharpeningAmount.standard)
                    Text("Strong").tag(ExportSettings.SharpeningAmount.strong)
                }
                if editor.settings.sharpening != .off {
                    Picker("Sharpen for", selection: settings.sharpeningTarget) {
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
                .disabled(editor.settings.watermark == nil)
            LabeledContent("Image") {
                HStack {
                    if let watermark = editor.settings.watermark {
                        Text(watermark.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Choose Image…") { editor.chooseWatermark(in: NSApp.keyWindow) }
                }
            }
            if let issue = watermarkIssue ?? editor.watermarkIssue { IssueText(text: issue) }
            if editor.settings.watermark != nil, editor.settings.watermarkEnabled {
                LabeledContent("Position") {
                    AnchorGrid(anchor: Binding(get: { editor.settings.watermark?.anchor ?? .bottomRight },
                                               set: { editor.settings.watermark?.anchor = $0 }))
                }
                watermarkSlider("Size", \.size, Watermark.sizeRange, step: 0.5)
                watermarkSlider("Margin", \.margin, Watermark.marginRange, step: 0.5)
                LabeledContent("Opacity") {
                    ValueSlider(value: Binding(get: { editor.settings.watermark?.opacity ?? 1 },
                                               set: { editor.settings.watermark?.opacity = $0 }),
                                range: 0.05...1, step: 0.01,
                                text: (editor.settings.watermark?.opacity ?? 1).formatted(.percent.precision(.fractionLength(0))))
                }
                // The first photo with the watermark, only while there is one.
                WatermarkPreview(editor: editor)
                    .frame(maxWidth: 520, minHeight: 220, maxHeight: 220)
            }
        }
    }

    /// A slider for a percentage of the image's long edge.
    private func watermarkSlider(_ title: LocalizedStringKey, _ path: WritableKeyPath<Watermark, Double>,
                                 _ range: ClosedRange<Double>, step: Double) -> some View {
        LabeledContent(title) {
            ValueSlider(value: Binding(get: { editor.settings.watermark?[keyPath: path] ?? range.lowerBound },
                                       set: { editor.settings.watermark?[keyPath: path] = $0 }),
                        range: range, step: step,
                        text: ((editor.settings.watermark?[keyPath: path] ?? 0) / 100)
                            .formatted(.percent.precision(.fractionLength(0...1))))
        }
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
    let editor: ExportSettingsEditor

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                if let image = editor.previewImage {
                    let size = fitted(CGSize(width: image.width, height: image.height), in: geometry.size)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: size.width, height: size.height)
                        if let watermark = editor.settings.activeWatermark, let mark = editor.watermarkImage {
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
