import AppKit
import PhotoCore
import PhotoUI

/// The film strip's resize handle (section 11, "Resize handle"): a capsule
/// in the strip's top margin and a zone along the whole top edge, 4 pt
/// either side of it. Dragging resizes the strip live and settles on the
/// nearest step at release; a double-click goes back to the default. To
/// VoiceOver it is a splitter whose increment and decrement move one step.
/// It never takes the keyboard.
final class FilmStripHandleView: NSView {
    weak var controller: FilmStripController?

    private let capsule = CALayer()
    private var isHovered = false
    private var isDragging = false
    /// For the cursor: whether the strip can grow or shrink from here.
    private var canGrow = true
    private var canShrink = true
    /// The step shown, for VoiceOver's value.
    private var shownStep: Double = FilmStripGeometry.defaultSize
    private var trackingArea: NSTrackingArea?

    /// The handle's frame for a strip whose top edge is at `top` in the host:
    /// from the capsule's place in the strip's 8 pt top margin up to the
    /// zone's top, 4 pt above the edge.
    static func frame(forStripTop top: CGFloat, width: CGFloat) -> NSRect {
        let bottom = top - CGFloat(FilmStripGeometry.verticalPadding)
        return NSRect(x: 0, y: bottom, width: width, height: top + FilmStripMetrics.handleReach - bottom)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        capsule.cornerRadius = FilmStripMetrics.handleSize.height / 2
        capsule.actions = PhotoCellView.noActions
        layer?.addSublayer(capsule)
        toolTip = String(localized: "Drag to resize the film strip")
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var isFlipped: Bool { false }

    /// The resize zone: 4 pt either side of the strip's top edge, which is
    /// `handleReach` below the view's top.
    private var zone: NSRect {
        let reach = FilmStripMetrics.handleReach
        return NSRect(x: 0, y: bounds.maxY - reach * 2, width: bounds.width, height: reach * 2)
    }

    func update(height: Double, range: ClosedRange<Double>, shownStep: Double, dragging: Bool) {
        let growable = height < range.upperBound
        let shrinkable = height > range.lowerBound
        if growable != canGrow || shrinkable != canShrink {
            canGrow = growable
            canShrink = shrinkable
            window?.invalidateCursorRects(for: self)
        }
        if self.shownStep != shownStep {
            self.shownStep = shownStep
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
        if isDragging != dragging {
            isDragging = dragging
            updateColor()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Centered in the strip's 8 pt top margin.
        let size = FilmStripMetrics.handleSize
        let marginMiddle = bounds.maxY - FilmStripMetrics.handleReach - CGFloat(FilmStripGeometry.verticalPadding) / 2
        capsule.frame = NSRect(x: (bounds.width - size.width) / 2, y: marginMiddle - size.height / 2,
                               width: size.width, height: size.height)
        CATransaction.commit()
    }

    private func updateColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let color: NSColor = isHovered || isDragging ? .labelColor : .secondaryLabelColor
        capsule.backgroundColor = color.resolved(for: effectiveAppearance).cgColor
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    // MARK: Cursor and hover

    /// The system's frame-resize cursor for a top edge: up and down, or only
    /// the way the strip can still go.
    private var cursor: NSCursor {
        let directions: NSCursor.FrameResizeDirection.Set = switch (canGrow, canShrink) {
        case (true, false): .outward
        case (false, true): .inward
        default: .all
        }
        return NSCursor.frameResize(position: .top, directions: directions)
    }

    override func resetCursorRects() {
        addCursorRect(zone, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: zone, options: [.mouseEnteredAndExited, .activeInActiveApp],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateColor()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateColor()
    }

    // Only the zone is the handle; below it lies the strip's top margin.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return zone.contains(local) ? self : nil
    }

    // MARK: Dragging

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            controller?.resetSize()
            return
        }
        controller?.beginResize(pointerY: event.locationInWindow.y)
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.resize(pointerY: event.locationInWindow.y)
    }

    override func mouseUp(with event: NSEvent) {
        controller?.endResize()
    }

    override func rightMouseDown(with event: NSEvent) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .splitter }
    override func accessibilityLabel() -> String? { String(localized: "Film Strip Size") }
    override func accessibilityValue() -> Any? { String(localized: "\(Int(shownStep)) points") }

    override func accessibilityPerformIncrement() -> Bool {
        controller?.stepSize(up: true) ?? false
    }

    override func accessibilityPerformDecrement() -> Bool {
        controller?.stepSize(up: false) ?? false
    }

    /// The handle's zone center in window coordinates (debug scripts).
    var zoneCenterInWindow: NSPoint {
        convert(NSPoint(x: zone.midX, y: zone.midY), to: nil)
    }
}
