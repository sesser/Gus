import AppKit
import PhotoCore
import SwiftUI

/// The Adjust tab's Masks heading: the list of masks (applied in order), the
/// selected mask's components, amount and local values, and the brush.
struct MasksSection: View {
    let editor: AdjustmentEditor
    @InspectorExpanded(Self.key, family: .adjust, default: true) private var isExpanded

    static let key = "adjust.section.masks"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: String(localized: "Masks", comment: "Adjust tab heading"), isExpanded: $isExpanded,
                          family: .adjust) {
                AppKitButton(symbol: editor.showsMaskOverlay ? "eye.fill" : "eye", style: .borderless,
                             tint: editor.showsMaskOverlay ? .controlAccentColor : .secondaryLabelColor,
                             help: String(localized: "Show the selected mask in red"),
                             isEnabled: editor.selectedMaskID != nil) {
                    editor.showsMaskOverlay.toggle()
                }
            }
            if isExpanded {
                Text("Presets and Paste Adjustments leave masks out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ShapeButtons(prompt: String(localized: "New Mask:"),
                             limit: MaskLimits.canAddMask(to: editor.adjustments.local) ? nil
                                 : String(localized: "A photo can have up to \(MaskLimits.masks) masks.",
                                          comment: "Tooltip: New Mask is dimmed at the limit")) { editor.addMask($0) }
                ForEach(Array(editor.adjustments.local.masks.enumerated()), id: \.element.id) { index, mask in
                    MaskRow(editor: editor, mask: mask, index: index)
                }
                if let mask = editor.selectedMask {
                    Divider()
                    MaskDetail(editor: editor, mask: mask)
                }
            }
        }
    }
}

/// A row of buttons, one per shape; dimmed, with `limit` as their tooltip,
/// when the limit is reached (design.md N8).
private struct ShapeButtons: View {
    let prompt: String
    var limit: String?
    let action: (MaskShapeKind) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(MaskShapeKind.allCases, id: \.self) { kind in
                AppKitButton(symbol: kind.symbol, style: .borderless, help: limit ?? kind.title,
                             accessibilityLabel: kind.title, isEnabled: limit == nil) { action(kind) }
                    // SwiftUI also applies its own enabled state to the
                    // control; without this it can turn the button back on.
                    .disabled(limit != nil)
                    .frame(width: 26)
            }
            Spacer()
        }
    }
}

/// A mask: its check box, its name (click selects, double-click renames in
/// place), and a ⋯ menu with Rename, Move Up, Move Down and Delete.
private struct MaskRow: View {
    let editor: AdjustmentEditor
    let mask: Mask
    let index: Int
    @State private var isRenaming = false

    var body: some View {
        let isSelected = editor.selectedMaskID == mask.id
        let count = editor.adjustments.local.masks.count
        let name = mask.name.isEmpty ? String(localized: "Mask \(index + 1)", comment: "A new mask's name") : mask.name
        HStack(spacing: InspectorMetrics.gap) {
            AppKitCheckbox(state: mask.isEnabled ? .on : .off, label: name,
                           help: mask.isEnabled ? String(localized: "Turn off this mask") : String(localized: "Turn on this mask")) {
                editor.setMaskEnabled(mask.id, !mask.isEnabled)
            }
            .frame(width: InspectorMetrics.checkSlot)
            MaskNameField(name: name, isSelected: isSelected, isRenaming: $isRenaming,
                          select: { editor.selectedMaskID = isSelected ? nil : mask.id },
                          rename: { editor.renameMask(mask.id, to: $0.trimmingCharacters(in: .whitespacesAndNewlines)) })
            AppKitMenuButton(title: "", symbol: "ellipsis.circle", entries: menuEntries(count: count),
                             help: String(localized: "Mask commands"))
                .frame(width: InspectorMetrics.resetSlot + 4)
        }
        .frame(height: SliderRow.height)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") { isRenaming = true }
            if index > 0 { Button("Move Up") { editor.moveMask(mask.id, by: -1) } }
            if index < count - 1 { Button("Move Down") { editor.moveMask(mask.id, by: 1) } }
            Button("Delete") { editor.removeMask(mask.id) }
        }
    }

    private func menuEntries(count: Int) -> [AppKitMenuButton.Entry] {
        [
            .item(String(localized: "Rename")) { isRenaming = true },
            .item(String(localized: "Move Up"), isEnabled: index > 0) { editor.moveMask(mask.id, by: -1) },
            .item(String(localized: "Move Down"), isEnabled: index < count - 1) { editor.moveMask(mask.id, by: 1) },
            .separator,
            .item(String(localized: "Delete")) { editor.removeMask(mask.id) },
        ]
    }
}

/// A mask's name: a click selects the mask, a double-click (or Rename)
/// edits it in place; Return saves, Escape gives up.
private struct MaskNameField: NSViewRepresentable {
    let name: String
    let isSelected: Bool
    @Binding var isRenaming: Bool
    let select: () -> Void
    let rename: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> Field {
        let field = Field(labelWithString: name)
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        let coordinator = context.coordinator
        coordinator.rename = rename
        coordinator.endRenaming = { isRenaming = false }
        field.onClick = select
        field.onDoubleClick = { isRenaming = true }
        field.font = isSelected ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
        field.toolTip = String(localized: "Select this mask; double-click to rename it")
        if isRenaming, !field.isEditable {
            field.beginRenaming(name)
        } else if !isRenaming, field.isEditable {
            field.endRenaming(name)
        } else if !field.isEditable, field.stringValue != name {
            field.stringValue = name
        }
    }

    final class Field: NSTextField {
        var onClick: (() -> Void)?
        var onDoubleClick: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            guard !isEditable else { return super.mouseDown(with: event) }
            if event.clickCount == 2 { onDoubleClick?() } else { onClick?() }
        }

        func beginRenaming(_ name: String) {
            stringValue = name
            isEditable = true
            isBezeled = true
            bezelStyle = .roundedBezel
            drawsBackground = true
            window?.makeFirstResponder(self)
            currentEditor()?.selectAll(nil)
        }

        func endRenaming(_ name: String) {
            isEditable = false
            isBezeled = false
            drawsBackground = false
            stringValue = name
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var rename: (String) -> Void = { _ in }
        var endRenaming: () -> Void = {}
        private var cancelled = false

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                cancelled = true
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if !cancelled { rename(field.stringValue) }
            cancelled = false
            endRenaming()
        }
    }
}

private struct MaskDetail: View {
    let editor: AdjustmentEditor
    let mask: Mask

    static func operationTitle(_ operation: MaskOperation) -> String {
        switch operation {
        case .add: String(localized: "Add", comment: "Mask operation")
        case .subtract: String(localized: "Subtract", comment: "Mask operation")
        case .intersect: String(localized: "Intersect", comment: "Mask operation")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(mask.components.enumerated()), id: \.offset) { index, component in
                ComponentRow(editor: editor, component: component, index: index)
            }
            ShapeButtons(prompt: String(localized: "Add to Mask:"),
                         limit: MaskLimits.canAddComponent(to: mask) ? nil
                             : String(localized: "A mask can combine up to \(MaskLimits.componentsPerMask) shapes.",
                                      comment: "Tooltip: Add to Mask is dimmed at the limit")) {
                editor.addComponent($0, operation: .add)
            }
            if mask.components.contains(where: { $0.shape.brushComponent }) || editor.isBrushing {
                BrushControls(editor: editor)
            }
            AdjustSlider(title: String(localized: "Amount", comment: "Mask amount"), value: mask.amount,
                         range: Mask.amountRange, defaultValue: 100, format: .plain) { value, phase in
                editor.setMaskAmount(value, phase: phase)
            }
            ForEach(LocalValues.controls, id: \.name) { control in
                AdjustSlider(title: Self.title(control.name), value: mask.adjustments[keyPath: control.keyPath],
                             range: control.range, defaultValue: 0,
                             format: control.name == "exposure" ? .stops : control.name == "sharpen" ? .plain : .signed) {
                    value, phase in editor.setLocal(control.keyPath, value, phase: phase)
                }
            }
        }
    }

    static func title(_ control: String) -> String {
        switch control {
        case "exposure": String(localized: "Exposure")
        case "contrast": String(localized: "Contrast")
        case "highlights": String(localized: "Highlights")
        case "shadows": String(localized: "Shadows")
        case "whites": String(localized: "Whites")
        case "blacks": String(localized: "Blacks")
        case "temperature": String(localized: "Temperature")
        case "tint": String(localized: "Tint")
        case "vibrance": String(localized: "Vibrance")
        case "saturation": String(localized: "Saturation")
        case "clarity": String(localized: "Clarity")
        case "dehaze": String(localized: "Dehaze")
        default: String(localized: "Sharpness", comment: "Local sharpening")
        }
    }
}

private struct ComponentRow: View {
    let editor: AdjustmentEditor
    let component: MaskComponent
    let index: Int

    var body: some View {
        let kind = MaskShapeKind(component.shape)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: kind.symbol)
                    .frame(width: 18)
                Text(kind.title)
                    .font(.callout)
                Spacer()
                AppKitPopUp(items: MaskOperation.allCases.map { .init(title: MaskDetail.operationTitle($0), tag: $0.rawValue) },
                            selection: component.operation.rawValue) { tag in
                    guard let operation = MaskOperation(rawValue: tag) else { return }
                    editor.setComponent(index, String(localized: "Mask Operation"), phase: .committed) { $0.operation = operation }
                }
                .frame(width: 96)
                AppKitButton(symbol: component.invert ? "circle.lefthalf.filled.inverse" : "circle.lefthalf.filled",
                             style: .borderless, tint: component.invert ? .controlAccentColor : .secondaryLabelColor,
                             help: String(localized: "Invert")) {
                    editor.setComponent(index, String(localized: "Invert"), phase: .committed) { $0.invert.toggle() }
                }
                .frame(width: 22)
                AppKitButton(symbol: "minus.circle", style: .borderless, help: String(localized: "Remove from Mask")) {
                    editor.removeComponent(index)
                }
                .frame(width: 22)
            }
            shapeControls
        }
    }

    @ViewBuilder private var shapeControls: some View {
        switch component.shape {
        case .linear(let gradient):
            slider(String(localized: "Feather"), gradient.feather, LinearGradient.featherRange, 100) { shape, value in
                guard case .linear(var g) = shape else { return shape }
                g.feather = value
                return .linear(g)
            }
        case .radial(let gradient):
            slider(String(localized: "Feather"), gradient.feather, RadialGradient.featherRange, 50) { shape, value in
                guard case .radial(var g) = shape else { return shape }
                g.feather = value
                return .radial(g)
            }
        case .luminanceRange(let range):
            slider(String(localized: "Lower", comment: "Luminance range"), range.lower * 100, 0...100, 50) { shape, value in
                guard case .luminanceRange(var r) = shape else { return shape }
                r.lower = value / 100
                return .luminanceRange(r)
            }
            slider(String(localized: "Upper", comment: "Luminance range"), range.upper * 100, 0...100, 100) { shape, value in
                guard case .luminanceRange(var r) = shape else { return shape }
                r.upper = value / 100
                return .luminanceRange(r)
            }
            slider(String(localized: "Smoothness"), range.smoothness * 100, 0...100, 10) { shape, value in
                guard case .luminanceRange(var r) = shape else { return shape }
                r.smoothness = value / 100
                return .luminanceRange(r)
            }
        case .colorRange(let range):
            HStack {
                AppKitButton(title: editor.isSamplingColor ? String(localized: "Done Picking") : String(localized: "Pick Colors"),
                             style: .push, help: String(localized: "Click the photo to add colors to the range")) {
                    editor.isSamplingColor.toggle()
                    if editor.isSamplingColor { editor.isBrushing = false }
                }
                Text("\(range.samples.count) colors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            slider(String(localized: "Tolerance"), range.tolerance, ColorRange.toleranceRange, 30) { shape, value in
                guard case .colorRange(var r) = shape else { return shape }
                r.tolerance = value
                return .colorRange(r)
            }
        case .brush:
            EmptyView()
        }
    }

    private func slider(_ title: String, _ value: Double, _ range: ClosedRange<Double>, _ defaultValue: Double,
                        _ update: @escaping (MaskShape, Double) -> MaskShape) -> some View {
        AdjustSlider(title: title, value: value, range: range, defaultValue: defaultValue, format: .plain) { value, phase in
            editor.setComponent(index, title, phase: phase) { $0.shape = update($0.shape, value) }
        }
    }
}

/// The brush toggle and the settings of the next stroke (not saved with the photo).
private struct BrushControls: View {
    @Bindable var editor: AdjustmentEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AppKitButton(title: editor.isBrushing ? String(localized: "Done Painting") : String(localized: "Paint"),
                             style: .push, help: String(localized: "Drag on the photo to paint into this mask")) {
                    editor.isBrushing.toggle()
                    if editor.isBrushing { editor.isSamplingColor = false }
                }
                AppKitButton(symbol: editor.brushTemplate.erase ? "eraser.fill" : "eraser", style: .borderless,
                             tint: editor.brushTemplate.erase ? .controlAccentColor : .secondaryLabelColor,
                             help: String(localized: "Erase")) {
                    editor.brushTemplate.erase.toggle()
                }
            }
            AdjustSlider(title: String(localized: "Size"), value: editor.brushTemplate.size * 100,
                         range: (BrushStroke.sizeRange.lowerBound * 100)...30, defaultValue: 3, format: .decimal) { value, _ in
                editor.brushTemplate.size = value / 100
            }
            AdjustSlider(title: String(localized: "Feather"), value: editor.brushTemplate.feather,
                         range: BrushStroke.percentRange, defaultValue: 50, format: .plain) { value, _ in
                editor.brushTemplate.feather = value
            }
            AdjustSlider(title: String(localized: "Flow"), value: editor.brushTemplate.flow,
                         range: BrushStroke.flowRange, defaultValue: 100, format: .plain) { value, _ in
                editor.brushTemplate.flow = value
            }
            AdjustSlider(title: String(localized: "Density"), value: editor.brushTemplate.density,
                         range: BrushStroke.flowRange, defaultValue: 100, format: .plain) { value, _ in
                editor.brushTemplate.density = value
            }
        }
    }
}
