import AppKit
import PhotoCore
import SwiftUI

/// The Presets heading's list view (#241, design §4): one row per preset,
/// its name only, in the collection's order. Rows are AppKit buttons: a
/// SwiftUI `List` or `NSTableView` would nest a second scroller in the
/// inspector's, and SwiftUI buttons in that scroll view swallow clicks in the
/// earlier design (design §4.3).
struct PresetList: View {
    let model: LibraryModel
    let presets: [AdjustmentPreset]
    /// Where each row's name starts.
    let textInset: CGFloat

    private var previews: PresetPreviewModel { model.presetPreviews }

    var body: some View {
        let current = PresetItemRules.markedAgainst(model)
        // Rows touch: moving from one to the next never leaves a gap where the preview could end.
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(presets) { preset in
                PresetListRow(name: preset.name, isApplied: PresetItemRules.isApplied(preset, to: current),
                          textInset: textInset, help: PresetItemRules.help(preset),
                          onHover: { previews.hover(preset, isInside: $0) }) {
                    model.applyAdjustmentPreset(preset)
                }
                .presetContextMenu(preset, model: model)
            }
        }
    }
}

/// The list rows' dimensions (design §4.2).
enum PresetListMetrics {
    static let height: CGFloat = 22
    /// From the row's edges to its name and to the applied mark.
    static let inset: CGFloat = 8
    static let markerPointSize: CGFloat = 12
    /// What the name always leaves at the trailing edge for the mark and the
    /// space before it, so a name doesn't re-truncate when the mark comes and goes.
    static let markerRoom: CGFloat = 20
    /// As the thumbnails' outline.
    static let cornerRadius: CGFloat = 4
    /// A collection heading's chevron weight (`PresetCollectionSection`).
    static let headingSymbolWeight = NSFont.Weight.semibold
    /// Where an open collection heading's title starts, as AppKit lays out
    /// its button (`AppKitButton`, borderless, chevron.down): its rows' names
    /// start there.
    @MainActor static let headingTitleInset: CGFloat = {
        let button = AppKitButton.Button()
        button.isBordered = false
        button.controlSize = .regular
        button.imageHugsTitle = true
        let font = NSFont.preferredFont(forTextStyle: .callout)
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: font.pointSize * 0.8, weight: headingSymbolWeight))
        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString(string: "M", attributes: [.font: font])
        button.sizeToFit()
        return button.cell?.titleRect(forBounds: button.bounds).minX ?? inset
    }()
}

/// One preset in the list: a full-width row that applies it when pressed and
/// reports the pointer for the loupe's preview, as a thumbnail does.
struct PresetListRow: NSViewRepresentable {
    var name: String
    var isApplied: Bool
    var textInset: CGFloat
    var help: String
    var onHover: (Bool) -> Void
    let action: () -> Void

    func makeCoordinator() -> AppKitButton.Coordinator { AppKitButton.Coordinator() }

    func makeNSView(context: Context) -> PresetListRowButton {
        let button = PresetListRowButton()
        button.target = context.coordinator
        button.action = #selector(AppKitButton.Coordinator.click)
        return button
    }

    func updateNSView(_ button: PresetListRowButton, context: Context) {
        context.coordinator.action = action
        button.onHover = onHover
        button.configure(name: name, isApplied: isApplied, textInset: textInset)
        button.toolTip = help
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PresetListRowButton, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 0
        return CGSize(width: width, height: PresetListMetrics.height)
    }
}

/// Draws a list row: the hover and pressed fills, the name and the applied
/// mark, in system colors resolved for the current appearance. A button for
/// VoiceOver and Full Keyboard Access, named for the preset.
final class PresetListRowButton: ImageTile.HoverButton {
    private(set) var name = ""
    private(set) var isApplied = false
    private(set) var textInset = PresetListMetrics.inset

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryPushIn)
        title = ""
        imagePosition = .noImage
        focusRingType = .default
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(name: String, isApplied: Bool, textInset: CGFloat) {
        guard name != self.name || isApplied != self.isApplied || textInset != self.textInset else { return }
        self.name = name
        self.isApplied = isApplied
        self.textInset = textInset
        // The title is never drawn (`draw(_:)`), but the cell, which AppKit
        // can make the element of a cell-based control, takes its name from it.
        title = name
        setAccessibilityLabel(name)
        setAccessibilityValue(isApplied ? Self.appliedValue : nil)
        cell?.setAccessibilityValue(isApplied ? Self.appliedValue : nil)
        needsDisplay = true
    }

    /// A row applies; it is never on or off, so a press leaves no state for
    /// VoiceOver to read as a value.
    override func setNextState() {}

    /// VoiceOver's value for the preset the photo already has (the look-up
    /// table browser's tooltip for its applied table).
    static var appliedValue: String { String(localized: "Applied to this photo") }

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: PresetListMetrics.height)
    }

    override func hoverDidChange() { needsDisplay = true }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    /// Return and Enter apply the focused row as Space does.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\u{3}" {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // A pressed row, else a hovered one; the focus ring, not a fill, shows the keyboard.
        if let fill: NSColor = isHighlighted ? .secondarySystemFill : isHovered ? .tertiarySystemFill : nil {
            fill.setFill()
            Self.shape(bounds).fill()
        }
        let metrics = PresetListMetrics.self
        let font = NSFont.preferredFont(forTextStyle: .callout)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: name, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ])
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let width = max(bounds.width - textInset - metrics.inset - metrics.markerRoom, 0)
        text.draw(with: NSRect(x: textInset, y: (bounds.height - lineHeight) / 2, width: width, height: lineHeight),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        if isApplied, let marker = Self.marker {
            let size = marker.size
            let rect = NSRect(x: bounds.maxX - metrics.inset - size.width, y: (bounds.height - size.height) / 2,
                              width: size.width, height: size.height)
            marker.draw(in: rect.integral, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        Self.shape(bounds).fill()
    }

    private static func shape(_ rect: NSRect) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: PresetListMetrics.cornerRadius, yRadius: PresetListMetrics.cornerRadius)
    }

    /// `checkmark.circle.fill` in the accent color, as the look-up table
    /// browser marks its applied table: the check stays cut out of the
    /// circle. Drawn when shown, so the accent color is the current one.
    private static let marker: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: PresetListMetrics.markerPointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        return NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.controlAccentColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }()
}
