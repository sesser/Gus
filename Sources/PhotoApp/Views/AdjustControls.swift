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

/// A collapsible heading of the Adjust tab, with a reset button.
struct AdjustSection<Content: View>: View {
    let section: Adjustments.Section
    let editor: AdjustmentEditor
    @ViewBuilder let content: Content
    @State private var isExpanded: Bool

    init(_ section: Adjustments.Section, editor: AdjustmentEditor, @ViewBuilder content: () -> Content) {
        self.section = section
        self.editor = editor
        self.content = content()
        let defaults = UserDefaults.standard
        _isExpanded = State(initialValue: defaults.object(forKey: Self.key(section)) == nil
            || defaults.bool(forKey: Self.key(section)))
    }

    static func key(_ section: Adjustments.Section) -> String { "adjust.section.\(section.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                AppKitButton(title: AdjustText.title(section), symbol: isExpanded ? "chevron.down" : "chevron.right",
                             symbolWeight: .semibold, style: .borderless,
                             font: .preferredFont(forTextStyle: .headline),
                             help: isExpanded ? String(localized: "Collapse") : String(localized: "Expand")) {
                    isExpanded.toggle()
                    UserDefaults.standard.set(isExpanded, forKey: Self.key(section))
                }
                Spacer()
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

/// Names of the Adjust tab's headings and controls.
enum AdjustText {
    static func title(_ section: Adjustments.Section) -> String {
        switch section {
        case .develop: String(localized: "Develop", comment: "Adjust tab heading")
        case .tone: String(localized: "Tone", comment: "Adjust tab heading")
        case .details: String(localized: "Details", comment: "Adjust tab heading")
        case .colorGrading: String(localized: "Color Grading", comment: "Adjust tab heading")
        }
    }
}

/// A clickable picture with a caption under it, outlined when selected.
struct ImageTile: NSViewRepresentable {
    var image: CGImage?
    var title: String
    var isSelected: Bool
    var help: String?
    let action: () -> Void

    func makeCoordinator() -> AppKitButton.Coordinator { AppKitButton.Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.imagePosition = .imageAbove
        button.imageScaling = .scaleProportionallyUpOrDown
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.target = context.coordinator
        button.action = #selector(AppKitButton.Coordinator.click)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        if let image {
            button.image = NSImage(cgImage: image, size: NSSize(width: 104, height: 104 * CGFloat(image.height) / CGFloat(max(image.width, 1))))
        } else {
            button.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        }
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: isSelected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
        ])
        button.lineBreakMode = .byTruncatingMiddle
        button.layer?.borderWidth = isSelected ? 2 : 0
        button.layer?.borderColor = NSColor.controlAccentColor.cgColor
        button.toolTip = help ?? title
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 110, height: 100)
    }
}
