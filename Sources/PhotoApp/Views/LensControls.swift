import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// The Lens heading's controls (docs/features/chromatic-aberration/design.md
/// §3): Color Fringes (two slots, their Tolerance, the fringe map) and
/// Color Alignment (Align automatically and two sliders).
struct LensControls: View {
    let model: LibraryModel

    private var editor: AdjustmentEditor { model.editor }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GroupLabel(.colorFringes, editor: editor)
            ForEach([1, 2], id: \.self) { slot in
                FringeSlotRow(model: model, slot: slot)
                if let fill = editor.adjustments.colorFringes[slot: slot] {
                    AdjustSlider(title: LensText.toleranceTitle, value: fill.tolerance, range: ColorFringes.toleranceRange,
                                 defaultValue: ColorFringes.startingTolerance(for: fill.color), format: .plain,
                                 accessibilityLabel: LensText.toleranceLabel(slot),
                                 fieldAccessibilityLabel: LensText.toleranceValueLabel(slot)) { value, phase in
                        editor.setFringeTolerance(slot, value, phase: phase)
                    }
                    .showsTurnedOff(.colorFringes, editor: editor)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                AppKitButton(title: LensText.mapName, style: .toggle(isOn: editor.showsFringeMap), help: mapHelp,
                             isEnabled: model.canShowFringeMap) {
                    model.toggleFringeMap(from: .button)
                }
                .disabled(!model.canShowFringeMap)
                .padding(.top, 6)
                Text(LensText.fringeCaption(editor))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .background(InspectorRevealAnchor(isRequested: model.revealsFringeRow) {
                model.revealsFringeRow = false
            })
            GroupLabel(.colorAlignment, editor: editor)
            alignmentRow
            VStack(alignment: .leading, spacing: 2) {
                let alignment = editor.adjustments.colorAlignment
                AdjustSlider(title: LensText.redCyan, value: alignment.red, range: ColorAlignment.range, defaultValue: 0,
                             format: .signed) { value, phase in
                    editor.setAlignment(red: value, title: LensText.redCyan, phase: phase)
                }
                AdjustSlider(title: LensText.blueYellow, value: alignment.blue, range: ColorAlignment.range, defaultValue: 0,
                             format: .signed) { value, phase in
                    editor.setAlignment(blue: value, title: LensText.blueYellow, phase: phase)
                }
            }
            .showsTurnedOff(.colorAlignment, editor: editor)
        }
    }

    /// Align automatically, its spinner while measuring, and its caption (design §3, §7).
    private var alignmentRow: some View {
        let state = LensText.alignmentState(of: editor)
        let checked = editor.adjustments.colorAlignment.automatic || editor.isMeasuringAlignment
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                AppKitCheckbox(state: checked ? .on : .off, label: LensText.alignAutomatically,
                               help: LensText.alignHelp, title: LensText.alignAutomatically) {
                    editor.setAutomaticAlignment(!checked)
                }
                .frame(minHeight: SliderRow.height)
                if editor.isMeasuringAlignment {
                    ProgressView()
                        .controlSize(.mini)
                        .help(LensText.measuringLabel)
                        .accessibilityLabel(LensText.measuringLabel)
                }
                Spacer(minLength: 0)
            }
            Text(LensText.alignmentCaption(state))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, InspectorMetrics.checkBoxTitleInset)
                .padding(.bottom, 2)
        }
    }

    /// The toggle's tooltip, saying why it is dimmed when it is.
    private var mapHelp: String {
        if model.isReviewing { return LensText.mapReviewHelp }
        if editor.cropSession != nil { return LensText.mapCroppingHelp }
        if editor.adjustments.colorFringes.isIdentity { return LensText.mapNoPickHelp }
        return LensText.mapHelp
    }
}

/// One fringe slot's row: label, swatch and hue name, eyedropper, ⋯ menu;
/// the row's context menu holds the same items (design §3 "Slot rows").
struct FringeSlotRow: View {
    let model: LibraryModel
    let slot: Int

    private var editor: AdjustmentEditor { model.editor }

    var body: some View {
        let fill = editor.adjustments.colorFringes[slot: slot]
        HStack(spacing: InspectorMetrics.gap) {
            Text(LensText.slotTitle(slot))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: InspectorMetrics.labelWidth, alignment: .leading)
            if let fill {
                Image(systemName: "circle.fill")
                    .foregroundStyle(Color(nsColor: Self.swatch(editor.fringeSwatches[slot] ?? FringeColorMath.linearRec2020(okLab: fill.color))))
                    .accessibilityHidden(true)
                Text(LensText.hueName(fill.color))
                    .font(.system(size: 13))
            } else {
                Text(LensText.none)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            AppKitButton(symbol: "eyedropper", style: .toggle(isOn: editor.pickingFringeSlot == slot),
                         help: editor.canPickFringe ? LensText.eyedropperHelp : LensText.eyedropperCroppingHelp,
                         accessibilityLabel: LensText.eyedropperLabel(slot), isEnabled: editor.canPickFringe) {
                editor.armFringePicker(slot)
            }
            .disabled(!editor.canPickFringe)
            AppKitMenuButton(title: "", symbol: "ellipsis.circle", entries: Self.entries(model: model, slot: slot)
                .map(\.menuEntry), help: LensText.slotMenuHelp(slot), accessibilityLabel: LensText.slotMenuLabel(slot))
        }
        .frame(height: SliderRow.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LensText.slotTitle(slot))
        .accessibilityValue(fill.map { LensText.hueName($0.color) } ?? LensText.none)
        .contextMenu {
            ForEach(Self.entries(model: model, slot: slot).indices, id: \.self) { index in
                Self.entries(model: model, slot: slot)[index].contextItem
            }
        }
    }

    /// A linear Rec. 2020 color as the swatch draws it.
    static func swatch(_ rgb: SIMD3<Double>) -> NSColor {
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020),
              let color = CGColor(colorSpace: space, components: [rgb.x, rgb.y, rgb.z, 1]).flatMap(NSColor.init(cgColor:))
        else { return .gray }
        return color
    }

    /// One item of the slot's menu and context menu (design §3 "The slot menu").
    struct Entry {
        enum Kind { case item, header, separator }
        var kind: Kind
        var title: String
        var isEnabled = true
        var swatch: NSColor?
        var action: () -> Void = {}

        var menuEntry: AppKitMenuButton.Entry {
            switch kind {
            case .header: .header(title)
            case .separator: .separator
            case .item: swatch == nil ? .item(title, isEnabled: isEnabled, action)
                : .imageItem(title, image: Self.image(swatch), isEnabled: isEnabled, action)
            }
        }

        @MainActor @ViewBuilder var contextItem: some View {
            switch kind {
            case .header: Text(title)
            case .separator: Divider()
            case .item:
                Button(title, action: action)
                    .disabled(!isEnabled)
            }
        }

        static func image(_ color: NSColor?) -> NSImage? {
            let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color ?? .gray]))
            return image
        }
    }

    /// Pick from Photo; Common Fringe Colors: Purple, Green; Clear.
    @MainActor
    static func entries(model: LibraryModel, slot: Int) -> [Entry] {
        let editor = model.editor
        var entries = [Entry(kind: .item, title: LensText.pickFromPhoto, isEnabled: editor.canPickFringe) {
            if editor.pickingFringeSlot != slot { editor.armFringePicker(slot) }
        }]
        entries.append(Entry(kind: .separator, title: ""))
        entries.append(Entry(kind: .header, title: LensText.commonColors))
        for listed in CommonFringeColor.allCases {
            entries.append(Entry(kind: .item, title: LensText.listedName(listed), isEnabled: editor.state == .ready,
                                 swatch: swatch(FringeColorMath.linearRec2020(okLab: listed.color))) {
                editor.fillFringe(slot, with: listed)
            })
        }
        entries.append(Entry(kind: .separator, title: ""))
        entries.append(Entry(kind: .item, title: LensText.clear,
                             isEnabled: editor.adjustments.colorFringes[slot: slot] != nil) {
            editor.clearFringe(slot)
        })
        return entries
    }
}
