import AppKit
import SwiftUI

/// A button drawn and tracked by AppKit, for the inspector. It takes the
/// scripted clicks of `DebugScript`, which SwiftUI buttons in a scroll view ignore.
struct AppKitButton: NSViewRepresentable {
    enum Style {
        /// A small push button.
        case push
        /// No bezel: a symbol, a title, or both.
        case borderless
    }

    var title = ""
    /// Shown after the title in the secondary color, such as a count.
    var detail: String?
    var symbol: String?
    /// Shown when there is no symbol; a template image takes the tint.
    var image: NSImage?
    /// Where the symbol or image goes; next to the title unless given.
    var imagePosition: NSControl.ImagePosition?
    var symbolWeight = NSFont.Weight.regular
    var style = Style.push
    var font = NSFont.preferredFont(forTextStyle: .callout)
    var tint: NSColor?
    var help: String?
    var isEnabled = true
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = Button()
        button.target = context.coordinator
        button.action = #selector(Coordinator.click)
        button.imageHugsTitle = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        switch style {
        case .push:
            button.bezelStyle = .push
            button.isBordered = true
            button.controlSize = .small
        case .borderless:
            button.isBordered = false
            button.controlSize = .regular
        }
        let font = style == .push ? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small)) : font
        if let symbol {
            let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize * (title.isEmpty ? 1 : 0.8),
                                                            weight: symbolWeight)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
                .withSymbolConfiguration(configuration)
            button.imagePosition = imagePosition ?? (title.isEmpty ? .imageOnly : .imageLeading)
        } else if let image {
            button.image = image
            button.imagePosition = imagePosition ?? (title.isEmpty ? .imageOnly : .imageLeading)
        } else {
            button.image = nil
            button.imagePosition = .noImage
        }
        let text = NSMutableAttributedString(string: title, attributes: [.font: font])
        if let detail {
            text.append(NSAttributedString(string: " " + detail, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        button.attributedTitle = text
        button.contentTintColor = tint
        button.toolTip = help
        if title.isEmpty, let help { button.setAccessibilityLabel(help) }
        button.isEnabled = isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        // A symbol alone gets at least a small square to click.
        guard title.isEmpty, let cell = nsView.cell else { return nsView.intrinsicContentSize }
        return CGSize(width: max(cell.cellSize.width, 16), height: max(cell.cellSize.height, 16))
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void = {}

        @objc func click() { action() }
    }

    /// Lays out by its frame: a symbol's alignment rect is only the height of
    /// its glyph, which left image-only buttons a sliver to click.
    final class Button: NSButton {
        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    }
}
