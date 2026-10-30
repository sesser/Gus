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
        }
    }

    /// Reads what was typed in the value field.
    func value(from text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "K", with: "")
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
        case .decimal: 0.1
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
    let onChange: (Double, EditPhase) -> Void

    func makeNSView(context: Context) -> SliderRow {
        SliderRow()
    }

    func updateNSView(_ row: SliderRow, context: Context) {
        row.configure(title: title, value: value, range: range, defaultValue: defaultValue, format: format,
                      scale: scale, isEnabled: isEnabled, onChange: onChange)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SliderRow, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: SliderRow.height)
    }
}

final class SliderRow: NSView, NSTextFieldDelegate {
    static let height: CGFloat = 38

    private let label = ResettingLabel(labelWithString: "")
    private let field = NSTextField()
    private let slider = TrackingSlider()
    private var format = SliderFormat.signed
    private var scale = SliderScale.linear
    private var range: ClosedRange<Double> = 0...1
    private var defaultValue = 0.0
    private var onChange: (Double, EditPhase) -> Void = { _, _ in }

    init() {
        super.init(frame: .zero)
        label.font = .preferredFont(forTextStyle: .callout)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.onDoubleClick = { [weak self] in self?.reset() }

        field.font = .monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize,
                                                weight: .regular)
        field.alignment = .right
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
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

        for view in [label, field, slider] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: field.leadingAnchor, constant: -6),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
            field.widthAnchor.constraint(equalToConstant: 64),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(title: String, value: Double, range: ClosedRange<Double>, defaultValue: Double,
                   format: SliderFormat, scale: SliderScale, isEnabled: Bool,
                   onChange: @escaping (Double, EditPhase) -> Void) {
        label.stringValue = title
        let ends = [scale.position(range.lowerBound), scale.position(range.upperBound)]
        slider.minValue = ends.min() ?? 0
        slider.maxValue = ends.max() ?? 1
        slider.altIncrementValue = scale == .linear ? format.keyIncrement : 0
        self.format = format
        self.scale = scale
        self.range = range
        self.defaultValue = defaultValue
        self.onChange = onChange
        slider.isEnabled = isEnabled
        field.isEditable = isEnabled
        label.textColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        // Never move the knob under the person's mouse.
        if !slider.isTracking {
            slider.doubleValue = scale.position(value)
        }
        if field.currentEditor() == nil {
            field.stringValue = format.text(value)
        }
        setAccessibilityLabel(title)
        slider.setAccessibilityLabel(title)
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
        // Keyboard changes arrive without a drag: each is a step of its own.
        onChange(value, slider.isTracking ? .changing : .committed)
    }

    @objc private func fieldCommitted() {
        guard let typed = format.value(from: field.stringValue) else {
            field.stringValue = format.text(sliderValue)
            return
        }
        let value = min(max(typed, range.lowerBound), range.upperBound)
        slider.doubleValue = scale.position(value)
        field.stringValue = format.text(value)
        onChange(value, .committed)
    }

    private func reset() {
        guard slider.isEnabled else { return }
        slider.doubleValue = scale.position(defaultValue)
        field.stringValue = format.text(defaultValue)
        onChange(defaultValue, .committed)
    }
}

/// Reports the start and end of a drag, and double-clicks.
final class TrackingSlider: NSSlider {
    var onDoubleClick: (() -> Void)?
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

/// A collapsible heading of the Adjust tab, with its check box and a reset button.
struct AdjustSection<Content: View>: View {
    let section: Adjustments.Section
    let editor: AdjustmentEditor
    @ViewBuilder let content: Content
    @State private var isExpanded: Bool

    init(_ section: Adjustments.Section, editor: AdjustmentEditor, @ViewBuilder content: () -> Content) {
        self.section = section
        self.editor = editor
        self.content = content()
        _isExpanded = State(initialValue: SectionHeaderState.isExpanded(key: Self.key(section), default: true))
    }

    static func key(_ section: Adjustments.Section) -> String { "adjust.section.\(section.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: AdjustText.title(section), isExpanded: $isExpanded, key: Self.key(section)) {
                SectionToggle(section: section, editor: editor)
            } trailing: {
                AppKitButton(symbol: "arrow.counterclockwise", style: .borderless, tint: .secondaryLabelColor,
                             help: String(localized: "Reset \(AdjustText.title(section))"),
                             isEnabled: editor.adjustments.isModified(section)) {
                    editor.reset(section)
                }
            }
            if isExpanded {
                content
            }
        }
    }
}

/// A heading's row: the disclosure chevron, a check box (or the room for
/// one, so every title lines up), the title, then trailing controls. The
/// chevron and the title both expand and collapse it; `key` remembers which.
struct SectionHeader<Check: View, Trailing: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let key: String
    /// Leaves room for the check box (the Adjust tab lines its titles up).
    var reservesCheck = true
    var titleFont: NSFont = .preferredFont(forTextStyle: .headline)
    @ViewBuilder let check: Check
    @ViewBuilder let trailing: Trailing

    var body: some View {
        let help = isExpanded ? String(localized: "Collapse") : String(localized: "Expand")
        HStack(spacing: 4) {
            AppKitButton(symbol: isExpanded ? "chevron.down" : "chevron.right", symbolWeight: .semibold,
                         style: .borderless, font: .systemFont(ofSize: 10), tint: .secondaryLabelColor,
                         help: help, action: flip)
                .frame(width: 14)
            if reservesCheck {
                check
                    .frame(width: 18)
            }
            AppKitButton(title: title, style: .borderless, font: titleFont, help: help, action: flip)
            Spacer()
            trailing
        }
    }

    private func flip() {
        isExpanded.toggle()
        UserDefaults.standard.set(isExpanded, forKey: key)
    }
}

extension SectionHeader where Check == Color {
    /// A heading with nothing to turn off.
    init(title: String, isExpanded: Binding<Bool>, key: String, reservesCheck: Bool = true,
         titleFont: NSFont = .preferredFont(forTextStyle: .headline), @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, isExpanded: isExpanded, key: key, reservesCheck: reservesCheck, titleFont: titleFont,
                  check: { Color.clear }, trailing: trailing)
    }
}

/// Whether a heading is expanded, remembered across launches.
enum SectionHeaderState {
    static func isExpanded(key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? value : UserDefaults.standard.bool(forKey: key)
    }
}

/// The round check box of a heading: checked while all its edits apply, a dash
/// while only some do. Unchecking it shows the photo without the heading's
/// edits (they are kept).
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
            AppKitButton(symbol: isOn ? "checkmark.circle.fill" : enabled.isEmpty ? "circle" : "minus.circle.fill",
                         style: .borderless, tint: enabled.isEmpty ? .tertiaryLabelColor : .controlAccentColor,
                         help: modified.isEmpty ? String(localized: "\(title) has no edits")
                             : isOn ? String(localized: "Turn off \(title) to compare")
                             : String(localized: "Turn on \(title)"),
                         isEnabled: !modified.isEmpty) {
                editor.setEnabled(section, !isOn)
            }
        }
    }
}

/// The round check box of a group: checked while its edits apply. It checks
/// itself when a control of the group changes; unchecking it shows the photo
/// without that group's edits (they are kept).
struct GroupToggle: View {
    let group: Adjustments.Group
    let editor: AdjustmentEditor

    var body: some View {
        let isModified = editor.adjustments.isModified(group)
        let isOn = isModified && editor.adjustments.isEnabled(group)
        let title = AdjustText.title(group)
        AppKitButton(symbol: isOn ? "checkmark.circle.fill" : "circle", style: .borderless,
                     tint: isOn ? .controlAccentColor : .tertiaryLabelColor,
                     help: !isModified ? String(localized: "\(title) has no edits")
                         : isOn ? String(localized: "Turn off \(title) to compare")
                         : String(localized: "Turn on \(title)"),
                     isEnabled: isModified) {
            editor.setEnabled(group, !isOn)
        }
    }
}

/// A group's caption with its round check box.
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
        HStack(alignment: .center, spacing: 6) {
            GroupToggle(group: group, editor: editor)
            ControlGroupLabel(text: AdjustText.title(group))
            Spacer()
            trailing
        }
    }
}

extension GroupLabel where Trailing == EmptyView {
    init(_ group: Adjustments.Group, editor: AdjustmentEditor) {
        self.init(group, editor: editor) { EmptyView() }
    }
}

/// Names of the Adjust tab's headings and controls.
enum AdjustText {
    static func title(_ group: Adjustments.Group) -> String {
        switch group {
        case .profile: String(localized: "Profile")
        case .whiteBalance: String(localized: "White Balance")
        case .light: String(localized: "Light")
        case .presence: String(localized: "Presence")
        case .toneCurve: String(localized: "Tone Curve")
        case .sharpening: String(localized: "Sharpening")
        case .noiseReduction: String(localized: "Noise Reduction")
        case .colorMixer: String(localized: "Color Mixer", comment: "Adjust tab heading")
        case .colorGrade: String(localized: "Color Grading", comment: "Adjust tab heading")
        case .lookTable: String(localized: "Look-Up Table")
        case .vignette: String(localized: "Vignette", comment: "Adjust tab group")
        case .grain: String(localized: "Grain", comment: "Adjust tab group")
        }
    }

    static func title(_ section: Adjustments.Section) -> String {
        switch section {
        case .develop: String(localized: "Develop", comment: "Adjust tab heading")
        case .tone: String(localized: "Tone", comment: "Adjust tab heading")
        case .details: String(localized: "Details", comment: "Adjust tab heading")
        case .colorMixer: String(localized: "Color Mixer", comment: "Adjust tab heading")
        case .colorGrading: String(localized: "Color Grading", comment: "Adjust tab heading")
        case .effects: String(localized: "Effects", comment: "Adjust tab heading")
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
        if button.menu?.items.first?.title != title {
            let titleMenu = NSMenu()
            titleMenu.addItem(withTitle: title, action: nil, keyEquivalent: "")
            button.menu = titleMenu
        }
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
