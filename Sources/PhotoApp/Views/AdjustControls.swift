import AppKit
import PhotoCore
import SwiftUI

/// How a slider's value is written next to it.
enum SliderFormat {
    /// −100 … +100 style: "+25", "0", "−12".
    case signed
    /// 0 … 100 style.
    case plain
    /// Stops: "+0.35".
    case stops
    /// Kelvin: "5200 K".
    case kelvin
    /// One decimal: "1.2".
    case decimal
    /// Signed degrees with one decimal: "+1.5°".
    case degrees

    func text(_ value: Double) -> String {
        switch self {
        case .signed:
            let rounded = value.rounded()
            return rounded > 0 ? "+\(Int(rounded))" : rounded < 0 ? "−\(Int(-rounded))" : "0"
        case .plain:
            return "\(Int(value.rounded()))"
        case .stops:
            let text = String(format: "%.2f", abs(value))
            return value > 0.004 ? "+" + text : value < -0.004 ? "−" + text : "0.00"
        case .kelvin:
            return String(localized: "\(Int(value.rounded())) K", comment: "Color temperature in kelvin")
        case .decimal:
            return String(format: "%.1f", value)
        case .degrees:
            let text = String(format: "%.1f°", abs(value))
            return value >= 0.05 ? "+" + text : value <= -0.05 ? "−" + text : "0.0°"
        }
    }

    /// Reads what was typed in the value field.
    func value(from text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "K", with: "")
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "+", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    /// Slider steps for the arrow keys.
    var keyIncrement: Double {
        switch self {
        case .signed, .plain: 1
        case .stops: 0.05
        case .kelvin: 50
        case .decimal, .degrees: 0.1
        }
    }
}

/// How a slider's position follows its value.
enum SliderScale {
    case linear
    /// Position follows 1/value: color temperature, so equal moves look like
    /// equal color changes (mireds) from candlelight to shade.
    case reciprocal

    func position(_ value: Double) -> Double {
        switch self {
        case .linear: value
        case .reciprocal: -1_000_000 / max(value, 1)
        }
    }

    func value(_ position: Double) -> Double {
        switch self {
        case .linear: position
        case .reciprocal: -1_000_000 / min(position, -1)
        }
    }
}

/// A labeled slider with an editable value, drawn and tracked by AppKit so that
/// it works inside the inspector's scroll view and takes scripted clicks.
/// Double-click the slider (or its label) to reset it.
struct AdjustSlider: NSViewRepresentable {
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var defaultValue: Double
    var format = SliderFormat.signed
    var scale = SliderScale.linear
    var isEnabled = true
    /// The row's tooltip and VoiceOver help (the label, slider and field); nil for none.
    var help: String?
    let onChange: (Double, EditPhase) -> Void
    /// False while the slider's group is turned off (`showsTurnedOff`).
    @Environment(\.adjustGroupIsOn) private var groupIsOn

    func makeNSView(context: Context) -> SliderRow {
        SliderRow()
    }

    func updateNSView(_ row: SliderRow, context: Context) {
        row.configure(title: title, value: value, range: range, defaultValue: defaultValue, format: format,
                      scale: scale, isEnabled: isEnabled, groupIsOn: groupIsOn, help: help, onChange: onChange)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SliderRow, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 276, height: SliderRow.height)
    }
}

/// Dimensions of the inspector's rows (section 4 of docs/UI_REDESIGN.md).
enum InspectorMetrics {
    static let padding: CGFloat = 12
    static let labelWidth: CGFloat = 80
    static let gap: CGFloat = 6
    static let valueWidth: CGFloat = 44
    static let rowPitch: CGFloat = 24
    static let headerHeight: CGFloat = 28
    static let groupLabelHeight: CGFloat = 20
    static let disclosureSlot: CGFloat = 16
    static let checkSlot: CGFloat = 16
    /// From a small check box's leading edge to its title's, as AppKit lays
    /// it out in the current design: a caption under it starts there, so it
    /// reads as the check box's note.
    @MainActor static let checkBoxTitleInset: CGFloat = {
        let button = NSButton(checkboxWithTitle: "M", target: nil, action: nil)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.sizeToFit()
        return button.cell?.titleRect(forBounds: button.bounds).minX ?? 18
    }()
    static let resetSlot: CGFloat = 20
}

private struct AdjustGroupIsOnKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// The group of the controls inside is turned off: labels and values go
    /// secondary and slider fills hide; the controls stay usable.
    var adjustGroupIsOn: Bool {
        get { self[AdjustGroupIsOnKey.self] }
        set { self[AdjustGroupIsOnKey.self] = newValue }
    }
}

extension View {
    /// Shows a group's controls as turned off while its edits are (they stay
    /// usable: changing one turns the group back on).
    func showsTurnedOff(_ group: Adjustments.Group, editor: AdjustmentEditor) -> some View {
        environment(\.adjustGroupIsOn, editor.adjustments.isEnabled(group))
    }
}

/// One row: an 80 pt label, a small slider filled from its default value,
/// and a bezeled value field. Double-clicking the label or the knob resets
/// it, as does the row's context menu.
final class SliderRow: NSView, NSTextFieldDelegate {
    static let height: CGFloat = 22

    private let label = ResettingLabel(labelWithString: "")
    private let field = NSTextField()
    private let slider = TrackingSlider()
    private var format = SliderFormat.signed
    private var scale = SliderScale.linear
    private var range: ClosedRange<Double> = 0...1
    private var defaultValue = 0.0
    private var groupIsOn = true
    private var isEnabled = true
    private var onChange: (Double, EditPhase) -> Void = { _, _ in }

    init() {
        super.init(frame: .zero)
        let small = NSFont.systemFont(ofSize: 11)
        label.font = small
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.onDoubleClick = { [weak self] in self?.reset() }

        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.alignment = .right
        field.controlSize = .small
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.target = self
        field.action = #selector(fieldCommitted)

        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.onDoubleClick = { [weak self] in self?.reset() }
        slider.onTrackingEnded = { [weak self] in
            guard let self else { return }
            self.onChange(self.sliderValue, .committed)
        }
        slider.valueText = { [weak self] in self.map { $0.format.text($0.sliderValue) } ?? "" }

        for view in [label, field, slider] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let metrics = InspectorMetrics.self
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.widthAnchor.constraint(equalToConstant: metrics.labelWidth),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: metrics.gap),
            slider.trailingAnchor.constraint(equalTo: field.leadingAnchor, constant: -metrics.gap),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.widthAnchor.constraint(equalToConstant: metrics.valueWidth),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(title: String, value: Double, range: ClosedRange<Double>, defaultValue: Double,
                   format: SliderFormat, scale: SliderScale, isEnabled: Bool, groupIsOn: Bool = true,
                   help: String? = nil, onChange: @escaping (Double, EditPhase) -> Void) {
        label.stringValue = title
        let ends = [scale.position(range.lowerBound), scale.position(range.upperBound)]
        slider.minValue = ends.min() ?? 0
        slider.maxValue = ends.max() ?? 1
        slider.altIncrementValue = scale == .linear ? format.keyIncrement : 0
        self.format = format
        self.scale = scale
        self.range = range
        self.defaultValue = defaultValue
        self.groupIsOn = groupIsOn
        self.isEnabled = isEnabled
        self.onChange = onChange
        slider.isEnabled = isEnabled
        field.isEditable = isEnabled
        for view in [self, label, slider, field] as [NSView] {
            view.toolTip = help
        }
        for element in [slider, field] as [NSView] {
            element.setAccessibilityHelp(help)
        }
        // Never move the knob under the person's mouse.
        if !slider.isTracking {
            slider.doubleValue = scale.position(value)
        }
        if field.currentEditor() == nil {
            field.stringValue = format.text(value)
        }
        updateStyle(value: value)
        setAccessibilityLabel(title)
        slider.setAccessibilityLabel(title)
        field.setAccessibilityLabel(String(localized: "\(title) value", comment: "VoiceOver: an adjustment slider's number field"))
    }

    /// The fill starts at the default, so an untouched slider shows none;
    /// turned off, labels and values go secondary and the fill hides.
    private func updateStyle(value: Double) {
        let isChanged = abs(value - defaultValue) > format.keyIncrement / 2
        // Labels stay secondary (never tertiary); turned off, the value goes secondary too.
        // A disabled row draws its text as AppKit draws a disabled control's own.
        label.textColor = isEnabled ? .secondaryLabelColor : .disabledControlTextColor
        field.textColor = !isEnabled ? .disabledControlTextColor
            : groupIsOn && isChanged ? .labelColor : .secondaryLabelColor
        if #available(macOS 26, *) {
            slider.neutralValue = scale.position(defaultValue)
            slider.trackFillColor = groupIsOn ? nil : .clear
        } else {
            // No fill from a neutral value before macOS 26: a neutral gray from the minimum.
            slider.trackFillColor = groupIsOn ? .systemGray : .clear
        }
    }

    /// For the debug script: whether the row takes input, its value and tooltip.
    var debugState: String {
        "enabled \(slider.isEnabled) value \(field.stringValue) tip '\(toolTip ?? "-")'"
    }

    /// The value at the knob, rounded to what the field shows.
    private var sliderValue: Double {
        let value = scale.value(slider.doubleValue)
        let step = format.keyIncrement
        return min(max((value / step).rounded() * step, range.lowerBound), range.upperBound)
    }

    @objc private func sliderMoved() {
        let value = sliderValue
        field.stringValue = format.text(value)
        updateStyle(value: value)
        // Keyboard changes arrive without a drag: each is a step of its own.
        onChange(value, slider.isTracking ? .changing : .committed)
    }

    @objc private func fieldCommitted() {
        guard let typed = format.value(from: field.stringValue) else {
            field.stringValue = format.text(sliderValue)
            return
        }
        set(typed)
    }

    private func set(_ typed: Double) {
        let value = min(max(typed, range.lowerBound), range.upperBound)
        slider.doubleValue = scale.position(value)
        field.stringValue = format.text(value)
        updateStyle(value: value)
        onChange(value, .committed)
    }

    private func reset() {
        guard slider.isEnabled else { return }
        set(defaultValue)
    }

    /// Reset "Exposure", while the value is not the default.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard slider.isEnabled, abs(scale.value(slider.doubleValue) - defaultValue) > format.keyIncrement / 2 else { return nil }
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(String(localized: "Reset “\(label.stringValue)”",
                                           comment: "Context menu of an adjustment slider; the slider's name")) { [weak self] in
            self?.reset()
        })
        return menu
    }

    /// Return commits the typed value, Escape drops it; either way the
    /// keyboard goes back to the grid or loupe, so culling keys work again.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            fieldCommitted()
            handKeyboardBack()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            field.abortEditing()
            field.stringValue = format.text(sliderValue)
            handKeyboardBack()
            return true
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            // ↑ / ↓ step the value, ×10 with Shift.
            let steps = NSEvent.modifierFlags.contains(.shift) ? 10.0 : 1.0
            let direction = selector == #selector(NSResponder.moveUp(_:)) ? 1.0 : -1.0
            let current = format.value(from: textView.string) ?? sliderValue
            set(current + direction * steps * format.keyIncrement)
            textView.string = field.stringValue
            return true
        default:
            return false
        }
    }

    private func handKeyboardBack() {
        guard let window else { return }
        NotificationCenter.default.post(name: .browserShouldTakeFocus, object: window)
    }

    /// The row's title, for debug scripts.
    var title: String { label.stringValue }

    /// Puts the keyboard in the value field, for debug scripts.
    func beginEditingValue() {
        window?.makeFirstResponder(field)
    }
}

/// Reports the start and end of a drag, and double-clicks.
final class TrackingSlider: NSSlider {
    var onDoubleClick: (() -> Void)?
    /// What VoiceOver says for the value: the row's formatted number.
    var valueText: (() -> String)?

    override func accessibilityValue() -> Any? {
        valueText?() ?? super.accessibilityValue()
    }
    var onTrackingEnded: (() -> Void)?
    private(set) var isTracking = false

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        isTracking = true
        // Runs the tracking loop until the mouse goes up.
        super.mouseDown(with: event)
        isTracking = false
        onTrackingEnded?()
    }
}

final class ResettingLabel: NSTextField {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { super.mouseDown(with: event) }
    }
}

/// A pop-up menu drawn by AppKit, for the same reasons as `AdjustSlider`.
struct AppKitPopUp: NSViewRepresentable {
    struct Item: Hashable {
        var title: String
        var tag: String
    }

    var items: [Item]
    var selection: String
    var isEnabled = true
    /// The tooltip and VoiceOver help; nil for none.
    var help: String?
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        if context.coordinator.items != items {
            context.coordinator.items = items
            button.removeAllItems()
            for item in items {
                button.addItem(withTitle: item.title)
                button.lastItem?.representedObject = item.tag
            }
        }
        if let index = items.firstIndex(where: { $0.tag == selection }) {
            button.selectItem(at: index)
        }
        button.isEnabled = isEnabled
        button.toolTip = help
        button.setAccessibilityHelp(help)
    }

    @MainActor
    final class Coordinator: NSObject {
        var items: [Item] = []
        var onSelect: (String) -> Void = { _ in }

        @objc func picked(_ sender: NSPopUpButton) {
            if let tag = sender.selectedItem?.representedObject as? String { onSelect(tag) }
        }
    }
}

/// A heading of the Adjust tab: its groups' check box (mixed when only some
/// are on), a reset, and the context menu.
struct AdjustSection<Content: View>: View {
    let section: Adjustments.Section
    let editor: AdjustmentEditor
    @ViewBuilder let content: Content
    @InspectorExpanded private var isExpanded: Bool

    init(_ section: Adjustments.Section, editor: AdjustmentEditor, @ViewBuilder content: () -> Content) {
        self.section = section
        self.editor = editor
        self.content = content()
        _isExpanded = InspectorExpanded(Self.key(section), family: .adjust, default: true)
    }

    static func key(_ section: Adjustments.Section) -> String { "adjust.section.\(section.rawValue)" }

    var body: some View {
        let title = AdjustText.title(section)
        let values = editor.adjustments
        let modified = section.groups.filter { values.isModified($0) }
        let isOn = !modified.isEmpty && modified.allSatisfy { values.isEnabled($0) }
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title, isExpanded: $isExpanded, family: .adjust,
                          turnOff: modified.isEmpty ? nil
                              : (isOn ? String(localized: "Turn Off") : String(localized: "Turn On"),
                                 { editor.setEnabled(section, !isOn) }),
                          reset: values.isModified(section) ? { editor.reset(section) } : nil) {
                SectionToggle(section: section, editor: editor)
            } trailing: {
                AppKitButton(symbol: "arrow.counterclockwise", style: .borderless, tint: .secondaryLabelColor,
                             help: String(localized: "Reset \(title)"), isEnabled: values.isModified(section)) {
                    editor.reset(section)
                }
            }
            if isExpanded {
                content
                    .padding(.bottom, 4)
            }
        }
    }
}

/// The line between inspector sections: 1 pt, 8 above and below.
struct InspectorSeparator: View {
    var body: some View {
        Divider().padding(.vertical, 8)
    }
}

/// Which sections Collapse All and Expand All reach: the tab's.
enum InspectorFamily: Hashable {
    case adjust, info
}

/// Whether each inspector heading is expanded, remembered across launches,
/// and changed together by Collapse All / Expand All.
@MainActor
@Observable
final class InspectorExpansion {
    static let shared = InspectorExpansion()

    private var values: [String: Bool] = [:]
    @ObservationIgnored private var known: [String: InspectorFamily] = [:]

    func isExpanded(_ key: String, family: InspectorFamily, default value: Bool) -> Bool {
        known[key] = family
        if let stored = values[key] { return stored }
        return UserDefaults.standard.object(forKey: key) == nil ? value : UserDefaults.standard.bool(forKey: key)
    }

    func set(_ key: String, _ expanded: Bool) {
        values[key] = expanded
        UserDefaults.standard.set(expanded, forKey: key)
    }

    /// Collapse All / Expand All for the headings of one tab seen so far.
    func setAll(_ family: InspectorFamily, expanded: Bool) {
        for (key, keyFamily) in known where keyFamily == family { set(key, expanded) }
    }
}

/// A heading's expansion in `InspectorExpansion`.
@MainActor
@propertyWrapper
struct InspectorExpanded: DynamicProperty {
    let key: String
    let family: InspectorFamily
    let defaultValue: Bool

    init(_ key: String, family: InspectorFamily, default value: Bool) {
        self.key = key
        self.family = family
        defaultValue = value
    }

    var wrappedValue: Bool {
        get { InspectorExpansion.shared.isExpanded(key, family: family, default: defaultValue) }
        nonmutating set { InspectorExpansion.shared.set(key, newValue) }
    }

    var projectedValue: Binding<Bool> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

/// A heading's row, 28 pt high (section 4 of docs/UI_REDESIGN.md): the
/// disclosure triangle in a 16 pt slot, the title, then the check box column
/// and a 20 pt trailing control (reset). Its context menu turns the heading
/// off or on, resets it, and collapses or expands every heading of the tab.
struct SectionHeader<Check: View, Trailing: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let family: InspectorFamily
    var turnOff: (title: String, action: () -> Void)?
    var reset: (() -> Void)?
    /// The trailing control's width: a reset's 20 pt, nil for its own (a count).
    var trailingWidth: CGFloat? = InspectorMetrics.resetSlot
    @ViewBuilder let check: Check
    @ViewBuilder let trailing: Trailing

    var body: some View {
        let help = isExpanded ? String(localized: "Collapse") : String(localized: "Expand")
        HStack(spacing: 0) {
            AppKitDisclosure(isExpanded: $isExpanded, help: help)
                .frame(width: InspectorMetrics.disclosureSlot)
            AppKitButton(title: title, style: .borderless, font: .systemFont(ofSize: 13, weight: .semibold), help: help) {
                isExpanded.toggle()
            }
            .padding(.leading, 4)
            Spacer(minLength: 4)
            check
                .frame(width: InspectorMetrics.checkSlot)
            trailing
                .frame(width: trailingWidth, height: InspectorMetrics.resetSlot)
        }
        .frame(height: InspectorMetrics.headerHeight)
        .contentShape(Rectangle())
        .contextMenu {
            if let turnOff { Button(turnOff.title, action: turnOff.action) }
            if let reset { Button("Reset", action: reset) }
            if turnOff != nil || reset != nil { Divider() }
            Button("Collapse All") { InspectorExpansion.shared.setAll(family, expanded: false) }
            Button("Expand All") { InspectorExpansion.shared.setAll(family, expanded: true) }
        }
    }
}

extension SectionHeader where Check == Color {
    /// A heading with nothing to turn off.
    init(title: String, isExpanded: Binding<Bool>, family: InspectorFamily, reset: (() -> Void)? = nil,
         trailingWidth: CGFloat? = InspectorMetrics.resetSlot, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, isExpanded: isExpanded, family: family, reset: reset, trailingWidth: trailingWidth,
                  check: { Color.clear }, trailing: trailing)
    }
}

extension SectionHeader where Check == Color, Trailing == Color {
    init(title: String, isExpanded: Binding<Bool>, family: InspectorFamily) {
        self.init(title: title, isExpanded: isExpanded, family: family, check: { Color.clear }, trailing: { Color.clear })
    }
}

/// A heading's check box: checked while all its edits apply, mixed while only
/// some do, unchecked while they are kept but off. Shown only when the heading
/// has edits; its slot stays.
struct SectionToggle: View {
    let section: Adjustments.Section
    let editor: AdjustmentEditor

    var body: some View {
        if section.groups.count == 1, let group = section.groups.first {
            GroupToggle(group: group, editor: editor)
        } else {
            let values = editor.adjustments
            let modified = section.groups.filter { values.isModified($0) }
            let enabled = modified.filter { values.isEnabled($0) }
            let isOn = !modified.isEmpty && enabled.count == modified.count
            let title = AdjustText.title(section)
            AppKitCheckbox(state: isOn ? .on : enabled.isEmpty ? .off : .mixed, isVisible: !modified.isEmpty, label: title,
                           help: isOn ? String(localized: "Turn off \(title) to compare") : String(localized: "Turn on \(title)")) {
                editor.setEnabled(section, !isOn)
            }
        }
    }
}

/// A group's check box: checked while its edits apply. It checks itself when
/// a control of the group changes; unchecking it keeps the edits but shows
/// the photo without them.
struct GroupToggle: View {
    let group: Adjustments.Group
    let editor: AdjustmentEditor

    var body: some View {
        let isModified = editor.adjustments.isModified(group)
        let isOn = isModified && editor.adjustments.isEnabled(group)
        let title = AdjustText.title(group)
        AppKitCheckbox(state: isOn ? .on : .off, isVisible: isModified, label: title,
                       help: isOn ? String(localized: "Turn off \(title) to compare") : String(localized: "Turn on \(title)")) {
            editor.setEnabled(group, !isOn)
        }
    }
}

/// A group's label, 20 pt high with 10 above: 11 pt semibold secondary, an
/// optional trailing control (Auto), and the check box in the heading's column.
struct GroupLabel<Trailing: View>: View {
    let group: Adjustments.Group
    let editor: AdjustmentEditor
    @ViewBuilder let trailing: Trailing

    init(_ group: Adjustments.Group, editor: AdjustmentEditor, @ViewBuilder trailing: () -> Trailing) {
        self.group = group
        self.editor = editor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            ControlGroupLabel(text: AdjustText.title(group))
            Spacer(minLength: 4)
            trailing
                .padding(.trailing, InspectorMetrics.gap)
            GroupToggle(group: group, editor: editor)
                .frame(width: InspectorMetrics.checkSlot)
            Color.clear
                .frame(width: InspectorMetrics.resetSlot, height: 1)
        }
        .frame(height: InspectorMetrics.groupLabelHeight)
        .padding(.top, 10)
    }
}

extension GroupLabel where Trailing == EmptyView {
    init(_ group: Adjustments.Group, editor: AdjustmentEditor) {
        self.init(group, editor: editor) { EmptyView() }
    }
}

/// A group's caption: 11 pt semibold secondary, mixed case.
struct ControlGroupLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// A caption in the 80 pt label column, the pop-up starting where slider
/// tracks start.
struct LabeledPopUp<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.adjustGroupIsOn) private var groupIsOn

    var body: some View {
        HStack(spacing: InspectorMetrics.gap) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: InspectorMetrics.labelWidth, alignment: .leading)
            content
        }
        .frame(minHeight: SliderRow.height)
    }
}

/// The system disclosure triangle (`NSButton` with the disclosure bezel).
struct AppKitDisclosure: NSViewRepresentable {
    @Binding var isExpanded: Bool
    var help: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.click(_:)))
        button.bezelStyle = .disclosure
        button.setButtonType(.pushOnPushOff)
        button.controlSize = .small
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.toggle = { isExpanded.toggle() }
        button.state = isExpanded ? .on : .off
        button.toolTip = help
        button.setAccessibilityLabel(help)
    }

    @MainActor
    final class Coordinator: NSObject {
        var toggle: () -> Void = {}

        @objc func click(_ sender: NSButton) { toggle() }
    }
}

/// A system check box with a mixed state, hidden (its slot kept) when there
/// is nothing to turn on or off.
struct AppKitCheckbox: NSViewRepresentable {
    enum State { case on, off, mixed }

    var state: State
    var isVisible = true
    /// What VoiceOver names it: the section or mask ("Light, checkbox, checked").
    var label: String
    /// The tooltip, and VoiceOver's help.
    var help: String
    /// Shown on the trailing side at the slider labels' size; nil for a bare
    /// check box. A titled one is named by its title.
    var title: String?
    var isEnabled = true
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.click(_:)))
        button.allowsMixedState = true
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.state = switch state {
        case .on: .on
        case .off: .off
        case .mixed: .mixed
        }
        button.title = title ?? ""
        button.isEnabled = isEnabled
        button.isHidden = !isVisible
        button.toolTip = help
        button.setAccessibilityLabel(title == nil ? label : nil)
        button.setAccessibilityHelp(help)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        title == nil ? nil : nsView.fittingSize
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void = {}

        /// AppKit moved the state on its own; the model decides it.
        @objc func click(_ sender: NSButton) { action() }
    }
}

/// Names of the Adjust tab's headings and controls.
enum AdjustText {
    static func title(_ group: Adjustments.Group) -> String {
        switch group {
        case .profile: String(localized: "Profile")
        case .whiteBalance: String(localized: "White Balance")
        // UI names only (decision 15): the group stays `light` in edit stacks.
        case .light: String(localized: "Tone", comment: "Adjust tab group: exposure, contrast, highlights…")
        case .presence: String(localized: "Presence")
        case .toneCurve: String(localized: "Tone Curve")
        case .sharpening: String(localized: "Sharpening")
        case .noiseReduction: String(localized: "Noise Reduction")
        case .colorMixer: String(localized: "Color Mixer", comment: "Adjust tab heading")
        case .colorGrade: String(localized: "Color Grading", comment: "Adjust tab heading")
        case .lookTable: String(localized: "Look-Up Table")
        case .vignette: String(localized: "Vignette", comment: "Adjust tab group")
        case .grain: String(localized: "Grain", comment: "Adjust tab group")
        case .colorFringes: String(localized: "Color Fringes", comment: "Adjust tab group under Lens: picked fringe colors turned gray near high-contrast edges")
        case .colorAlignment: String(localized: "Color Alignment", comment: "Adjust tab group under Lens: lines up red and blue with green toward the corners")
        }
    }

    static func title(_ section: Adjustments.Section) -> String {
        switch section {
        // UI names only (decision 15): the sections stay `develop` and `tone`.
        case .develop: String(localized: "Light", comment: "Adjust tab heading: profile, white balance, tone, presence")
        case .tone: String(localized: "Tone Curve", comment: "Adjust tab heading")
        case .details: String(localized: "Details", comment: "Adjust tab heading")
        case .lens: String(localized: "Lens", comment: "Adjust tab heading for lens corrections: color fringes, color alignment")
        case .colorMixer: String(localized: "Color Mixer", comment: "Adjust tab heading")
        case .colorGrading: String(localized: "Color Grading", comment: "Adjust tab heading")
        case .effects: String(localized: "Effects", comment: "Adjust tab heading")
        }
    }

    /// Why a photo's edits cannot be changed here.
    static func unreadableMessage(_ failure: EditStack.ReadFailure) -> String {
        let name = AppBranding.displayName
        return switch failure {
        case .newerVersion:
            String(localized: "These edits were saved by a newer version of \(name). Editing is off so they are not lost.",
                   comment: "Adjust tab and status line; %@ is the app's name")
        case .exceedsLimits:
            String(localized: "These edits hold more masks or brush points than this version of \(name) allows. Editing is off so they are not lost.",
                   comment: "Adjust tab and status line; %@ is the app's name")
        case .damaged:
            String(localized: "These edits cannot be read. Editing is off so they are not lost.",
                   comment: "Adjust tab and status line")
        }
    }
}

/// A clickable picture with a caption under it, outlined when selected, as
/// wide as offered. `onHover` hears the pointer come and go.
struct ImageTile: NSViewRepresentable {
    var image: CGImage?
    var title: String
    /// Width over height while there is no picture yet (the picture's, when
    /// known, so the tile keeps its size when it arrives).
    var placeholderAspect: CGFloat?
    var isSelected: Bool
    var help: String?
    var onHover: ((Bool) -> Void)?
    let action: () -> Void

    static let defaultPlaceholderAspect: CGFloat = 1.5
    static let captionHeight: CGFloat = 18

    func makeCoordinator() -> AppKitButton.Coordinator { AppKitButton.Coordinator() }

    func makeNSView(context: Context) -> HoverButton {
        let button = HoverButton()
        button.isBordered = false
        button.imagePosition = .imageAbove
        button.imageScaling = .scaleProportionallyUpOrDown
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.target = context.coordinator
        button.action = #selector(AppKitButton.Coordinator.click)
        return button
    }

    func updateNSView(_ button: HoverButton, context: Context) {
        context.coordinator.action = action
        button.onHover = onHover
        if let image {
            button.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            button.contentTintColor = nil
        } else {
            let configuration = NSImage.SymbolConfiguration(pointSize: 22, weight: .light)
            button.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            button.contentTintColor = .tertiaryLabelColor
        }
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: isSelected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
        ])
        button.lineBreakMode = .byTruncatingMiddle
        button.layer?.borderWidth = isSelected ? 2 : 0
        button.layer?.borderColor = NSColor.controlAccentColor.cgColor
        button.toolTip = help ?? title
        button.setAccessibilityLabel(title)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HoverButton, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 120
        let aspect = image.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) }
            ?? placeholderAspect ?? Self.defaultPlaceholderAspect
        return CGSize(width: width, height: (width / max(aspect, 0.5)).rounded() + Self.captionHeight)
    }

    /// Reports the pointer entering and leaving.
    final class HoverButton: NSButton {
        var onHover: ((Bool) -> Void)?
        private var area: NSTrackingArea?
        private var isHovered = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            self.area = area
        }

        override func mouseEntered(with event: NSEvent) {
            isHovered = true
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            guard isHovered else { return }
            isHovered = false
            onHover?(false)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            // Leaving the window (a collapsed heading) sends no exit of its own.
            if newWindow == nil, isHovered {
                isHovered = false
                onHover?(false)
            }
        }
    }
}

/// A pull-down menu drawn by AppKit.
struct AppKitMenuButton: NSViewRepresentable {
    enum Entry {
        case item(String, isEnabled: Bool = true, () -> Void)
        /// An item with a check mark when `isOn`; `preview` runs while it is highlighted.
        case check(String, isOn: Bool, preview: (() -> Void)? = nil, () -> Void)
        case submenu(String, [Entry])
        case separator
    }

    var title: String
    /// Shown instead of a title, borderless (the ⋯ menus).
    var symbol: String?
    var entries: [Entry]
    var help: String?
    /// Ends the items' previews: with false when the highlight moves to an item
    /// without one, with true when the menu closes.
    var endPreview: ((_ menuClosed: Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = MenuPopUpButton(frame: .zero, pullsDown: true)
        (button.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        // The button's own menu only holds the title (a pull-down shows its first
        // item); the real menu is built when it is clicked.
        let shown = button.menu?.items.first
        if shown?.title != title || (symbol != nil && shown?.image == nil) {
            let titleMenu = NSMenu()
            let item = titleMenu.addItem(withTitle: title, action: nil, keyEquivalent: "")
            if let symbol {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
                button.isBordered = false
                (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
                button.imagePosition = .imageOnly
            }
            button.menu = titleMenu
        }
        if let help { button.setAccessibilityLabel(help) }
        let entries = entries
        let coordinator = context.coordinator
        coordinator.endPreview = endPreview
        (button as? MenuPopUpButton)?.makeMenu = {
            let menu = NSMenu()
            menu.autoenablesItems = false
            coordinator.actions = []
            coordinator.previews = [:]
            coordinator.rootMenu = menu
            menu.delegate = coordinator
            add(entries, to: menu, coordinator: coordinator)
            return menu
        }
        button.toolTip = help
    }

    /// As wide as the title (a pull-down would otherwise size itself to its
    /// longest item), but no wider than offered: a long title truncates.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        if symbol != nil { return CGSize(width: 24, height: 20) }
        let font = nsView.font ?? .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 36
        let offered = proposal.width.map { $0.isFinite ? $0 : titleWidth } ?? titleWidth
        return CGSize(width: max(min(titleWidth, offered), 60), height: nsView.intrinsicContentSize.height)
    }

    private func add(_ entries: [Entry], to menu: NSMenu, coordinator: Coordinator) {
        for entry in entries {
            switch entry {
            case .item(let title, let isEnabled, let action):
                let item = NSMenuItem(title: title, action: #selector(Coordinator.pick(_:)), keyEquivalent: "")
                item.target = coordinator
                item.tag = coordinator.actions.count
                item.isEnabled = isEnabled
                coordinator.actions.append(action)
                menu.addItem(item)
            case .check(let title, let isOn, let preview, let action):
                let item = NSMenuItem(title: title, action: #selector(Coordinator.pick(_:)), keyEquivalent: "")
                item.target = coordinator
                item.tag = coordinator.actions.count
                item.state = isOn ? .on : .off
                if let preview { coordinator.previews[item.tag] = preview }
                coordinator.actions.append(action)
                menu.addItem(item)
            case .submenu(let title, let children):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                submenu.delegate = coordinator
                add(children, to: submenu, coordinator: coordinator)
                item.submenu = submenu
                item.isEnabled = !children.isEmpty
                menu.addItem(item)
            case .separator:
                menu.addItem(.separator())
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var actions: [() -> Void] = []
        /// Previews by item tag.
        var previews: [Int: () -> Void] = [:]
        var endPreview: ((Bool) -> Void)?
        weak var rootMenu: NSMenu?
        private var isPreviewing = false

        // Not `perform(_:)`: #selector would pick NSObject's performSelector: and crash.
        @objc func pick(_ sender: NSMenuItem) {
            if actions.indices.contains(sender.tag) { actions[sender.tag]() }
        }

        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            if let item, item.action != nil, let preview = previews[item.tag] {
                isPreviewing = true
                preview()
            } else if isPreviewing, item?.submenu == nil {
                // A submenu's own item stays highlighted while its items are.
                isPreviewing = false
                endPreview?(false)
            }
        }

        func menuDidClose(_ menu: NSMenu) {
            guard menu === rootMenu, !previews.isEmpty else { return }
            isPreviewing = false
            // After the picked item's action, which comes once the menu is closed.
            let endPreview = endPreview
            Task { @MainActor in endPreview?(true) }
        }
    }

    /// Pops up a menu made at click time with the standard menu tracking. A
    /// pull-down's own tracking does not send the actions of items in its
    /// submenus, and SwiftUI updates would replace a menu kept on the button.
    final class MenuPopUpButton: NSPopUpButton {
        var makeMenu: (() -> NSMenu)?

        override func mouseDown(with event: NSEvent) {
            showMenu()
        }

        override func performClick(_ sender: Any?) {
            showMenu()
        }

        override func accessibilityPerformPress() -> Bool {
            showMenu()
            return true
        }

        private func showMenu() {
            guard isEnabled, let menu = makeMenu?() else { return }
            menu.font = font
            let below = NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : bounds.minY - 4)
            menu.popUp(positioning: nil, at: below, in: self)
        }
    }
}
