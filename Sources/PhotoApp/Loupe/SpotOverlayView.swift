import AppKit
import PhotoCore
import PhotoUI

/// The spots over the loupe's photo while Edit Spots is on
/// (docs/features/healing/design.md §4): a ring per spot in the crop, solid
/// for Heal and dashed for Clone; the selected one heavier, with its feather
/// core, a resize handle at 3 o'clock, and its source as a ring with a cross
/// and an arrow to the spot; the next spot's rings around the pointer.
///
/// It sits inside the image view, so it zooms and scrolls with the photo.
/// Only spots and handles take the mouse: a click elsewhere goes to the
/// canvas, which adds a spot there (`LoupeScrollView.onPick`) or pans on a
/// drag. While the overlay is hidden nothing is drawn or hit, so every click
/// adds. Each drag is one undo step: frames render while it moves, it saves
/// on release.
@MainActor
final class SpotOverlayView: NSView {
    weak var editor: AdjustmentEditor?
    /// The loupe's context menu, for a right-click on a spot (which selects it first).
    var contextMenu: (() -> NSMenu?)?
    /// The canvas element VoiceOver reaches: the spots' elements are its
    /// children, since the scroll view holding this view is hidden from
    /// VoiceOver (design review F1).
    weak var accessibilityHost: NSView?

    private let haloLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let dashedHaloLayer = CAShapeLayer()
    private let dashedLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let arrowLayer = CAShapeLayer()
    private let cursorHaloLayer = CAShapeLayer()
    private let cursorLayer = CAShapeLayer()
    private var cursor: CGPoint?
    private var drag: Drag?

    enum Part: Equatable {
        case spot, source, resize
    }

    private struct Drag {
        var id: UUID
        var part: Part
        var start: CGPoint
        var original: Spot
        var moved = false
    }

    /// The drawn radius never goes below this at any zoom, so a speck stays selectable.
    nonisolated private static let minimumRadius: CGFloat = 8
    private static let handleRadius: CGFloat = 6
    private static let grabDistance: CGFloat = 10
    private static let dragThreshold: CGFloat = 3
    private static let dash: [NSNumber] = [4, 3]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shape in [haloLayer, dashedHaloLayer, ringLayer, dashedLayer, handleLayer, arrowLayer, cursorHaloLayer, cursorLayer] {
            shape.fillColor = nil
            shape.actions = ["path": NSNull(), "lineWidth": NSNull(), "strokeColor": NSNull()]
            layer?.addSublayer(shape)
        }
        dashedLayer.lineDashPattern = Self.dash
        dashedHaloLayer.lineDashPattern = Self.dash
        handleLayer.fillColor = NSColor.white.cgColor
        handleLayer.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        handleLayer.lineWidth = 1
        arrowLayer.strokeColor = NSColor.white.cgColor
        arrowLayer.shadowOpacity = 0.6
        arrowLayer.shadowRadius = 1
        arrowLayer.shadowOffset = .zero
        applyContrast()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    @objc private func displayOptionsChanged() {
        applyContrast()
        refresh()
    }

    /// White strokes over a dark hairline (design §4); Increase Contrast darkens
    /// the hairline to 60 % and adds half a point to every stroke.
    private var extra: CGFloat { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.5 : 0 }

    private func applyContrast() {
        let halo = NSColor.black.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.6 : 0.35)
        for shape in [haloLayer, dashedHaloLayer, cursorHaloLayer, selectedHaloLayer] { shape.strokeColor = halo.cgColor }
        for shape in [ringLayer, dashedLayer, cursorLayer] { shape.strokeColor = NSColor.white.cgColor }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow,
                                                               .inVisibleRect], owner: self))
    }

    override func layout() {
        super.layout()
        refresh()
    }

    // MARK: Geometry

    private func unit(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / max(bounds.width, 1), y: point.y / max(bounds.height, 1))
    }

    private func view(_ point: MaskPoint) -> CGPoint? {
        editor?.outputPoint(fromMask: point).map { CGPoint(x: $0.x * bounds.width, y: $0.y * bounds.height) }
    }

    /// A circle of `size` (a fraction of the long edge) around `center` on screen: its radius in points.
    private func viewRadius(_ size: Double, at center: MaskPoint) -> CGFloat? {
        guard let editor, let frame = editor.maskSourceSize, let middle = view(center) else { return nil }
        let pixels = size * Double(max(frame.width, frame.height))
        let edge = MaskPoint(x: center.x + pixels / Double(frame.width), y: center.y)
        guard let other = view(edge) else { return nil }
        // Uniform scale and rotation keep a circle round, so one edge point gives the radius.
        return hypot(other.x - middle.x, other.y - middle.y)
    }

    /// Where a spot is drawn: center, true radius on screen, and the drawn one.
    private struct Placed {
        var spot: Spot
        var center: CGPoint
        var radius: CGFloat
        var drawn: CGFloat { max(radius, SpotOverlayView.minimumRadius) }
    }

    private func placed(_ spot: Spot) -> Placed? {
        guard let center = view(spot.center), let radius = viewRadius(spot.size, at: spot.center) else { return nil }
        return Placed(spot: spot, center: center, radius: radius)
    }

    /// The spots drawn and hit: those in the crop, while the overlay is shown.
    private var shownSpots: [Placed] {
        guard let editor, editor.isEditingSpots, editor.showsSpotOverlay else { return [] }
        return editor.visibleSpots.compactMap(placed)
    }

    private func resizeHandle(_ placed: Placed) -> CGPoint {
        CGPoint(x: placed.center.x + placed.drawn, y: placed.center.y)
    }

    private func sourcePlaced(_ spot: Spot) -> (center: CGPoint, radius: CGFloat)? {
        guard let center = view(spot.source), let radius = viewRadius(spot.size, at: spot.source) else { return nil }
        return (center, max(radius, Self.minimumRadius))
    }

    // MARK: Drawing

    /// Redraws from the editor's spots, selection and next-spot values.
    func refresh() {
        let solid = CGMutablePath(), dashed = CGMutablePath()
        let selectedSolid = CGMutablePath(), selectedDashed = CGMutablePath()
        let handles = CGMutablePath(), arrows = CGMutablePath()
        let selectedID = editor?.selectedSpotID
        for item in shownSpots {
            let isSelected = item.spot.id == selectedID
            let path = isSelected ? (item.spot.mode == .heal ? selectedSolid : selectedDashed)
                                  : (item.spot.mode == .heal ? solid : dashed)
            path.addEllipse(in: CGRect(x: item.center.x - item.drawn, y: item.center.y - item.drawn,
                                       width: 2 * item.drawn, height: 2 * item.drawn))
            guard isSelected else { continue }
            // The feather's core as a thin inner ring.
            let core = item.radius * (1 - item.spot.feather / 100)
            if core > 1, core < item.drawn - 1 {
                arrows.addEllipse(in: CGRect(x: item.center.x - core, y: item.center.y - core, width: 2 * core, height: 2 * core))
            }
            let handle = resizeHandle(item)
            handles.addEllipse(in: CGRect(x: handle.x - Self.handleRadius, y: handle.y - Self.handleRadius,
                                          width: 2 * Self.handleRadius, height: 2 * Self.handleRadius))
            if let source = sourcePlaced(item.spot) {
                arrows.addEllipse(in: CGRect(x: source.center.x - source.radius, y: source.center.y - source.radius,
                                             width: 2 * source.radius, height: 2 * source.radius))
                let cross: CGFloat = 5
                arrows.move(to: CGPoint(x: source.center.x - cross, y: source.center.y))
                arrows.addLine(to: CGPoint(x: source.center.x + cross, y: source.center.y))
                arrows.move(to: CGPoint(x: source.center.x, y: source.center.y - cross))
                arrows.addLine(to: CGPoint(x: source.center.x, y: source.center.y + cross))
                addArrow(to: arrows, from: source.center, to: item.center, endingAt: item.drawn)
            }
        }
        let light = 1.5 + extra, heavy = 2.5 + extra
        ringLayer.path = solid
        dashedLayer.path = dashed
        haloLayer.path = solid
        dashedHaloLayer.path = dashed
        for shape in [ringLayer, dashedLayer] { shape.lineWidth = light }
        for shape in [haloLayer, dashedHaloLayer] { shape.lineWidth = light + 1.5 }
        selectedRingLayer.path = selectedSolid
        selectedDashedLayer.path = selectedDashed
        let selectedAll = CGMutablePath()
        selectedAll.addPath(selectedSolid)
        selectedAll.addPath(selectedDashed)
        selectedHaloLayer.path = selectedAll
        for shape in [selectedRingLayer, selectedDashedLayer] { shape.lineWidth = heavy }
        selectedHaloLayer.lineWidth = heavy + 1.5
        selectedHaloLayer.strokeColor = haloLayer.strokeColor
        handleLayer.path = handles
        arrowLayer.path = arrows
        arrowLayer.lineWidth = 1 + extra
        arrowLayer.fillColor = nil
        arrowHeadLayer.path = arrowHeads(arrows)
        drawCursor()
    }

    private lazy var selectedRingLayer: CAShapeLayer = makeLayer(dashed: false, halo: false)
    private lazy var selectedDashedLayer: CAShapeLayer = makeLayer(dashed: true, halo: false)
    private lazy var selectedHaloLayer: CAShapeLayer = makeLayer(dashed: false, halo: true)
    private lazy var arrowHeadLayer: CAShapeLayer = {
        let shape = CAShapeLayer()
        shape.fillColor = NSColor.white.cgColor
        shape.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
        shape.lineWidth = 0.5
        shape.actions = ["path": NSNull()]
        layer?.addSublayer(shape)
        return shape
    }()
    /// The filled heads `addArrow` recorded.
    private var heads: [CGPath] = []

    private func arrowHeads(_ path: CGPath) -> CGPath {
        let all = CGMutablePath()
        for head in heads { all.addPath(head) }
        heads.removeAll()
        return all
    }

    private func makeLayer(dashed: Bool, halo: Bool) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.fillColor = nil
        shape.actions = ["path": NSNull(), "lineWidth": NSNull()]
        shape.strokeColor = halo ? NSColor.black.withAlphaComponent(0.35).cgColor : NSColor.white.cgColor
        if dashed { shape.lineDashPattern = Self.dash }
        // Under the handles and the arrow.
        layer?.insertSublayer(shape, below: handleLayer)
        return shape
    }

    /// A line from `start` to the circle of `radius` around `end`, with a filled 8 pt arrowhead there.
    private func addArrow(to path: CGMutablePath, from start: CGPoint, to end: CGPoint, endingAt radius: CGFloat) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > radius + 1 else { return }
        let ux = dx / length, uy = dy / length
        let tip = CGPoint(x: end.x - ux * radius, y: end.y - uy * radius)
        path.move(to: start)
        path.addLine(to: tip)
        let head: CGFloat = 8
        let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
        let triangle = CGMutablePath()
        triangle.move(to: tip)
        triangle.addLine(to: CGPoint(x: base.x - uy * head / 2, y: base.y + ux * head / 2))
        triangle.addLine(to: CGPoint(x: base.x + uy * head / 2, y: base.y - ux * head / 2))
        triangle.closeSubpath()
        heads.append(triangle)
    }

    /// The next spot's size around the pointer, and its feather core (design §4), over empty photo only.
    private func drawCursor() {
        let path = CGMutablePath()
        if let editor, editor.isEditingSpots, let cursor, target(at: cursor) == nil,
           let center = editor.maskPoint(fromOutput: unit(cursor)),
           let radius = viewRadius(editor.spotTemplate.size, at: center) {
            let core = radius * (1 - editor.spotTemplate.feather / 100)
            for r in [radius, core] where r > 0.5 {
                path.addEllipse(in: CGRect(x: cursor.x - r, y: cursor.y - r, width: 2 * r, height: 2 * r))
            }
        }
        let dashed = editor?.spotTemplate.mode == .clone
        cursorLayer.lineDashPattern = dashed ? Self.dash : nil
        cursorHaloLayer.lineDashPattern = dashed ? Self.dash : nil
        cursorLayer.lineWidth = 1 + extra
        cursorHaloLayer.lineWidth = 2.5 + extra
        cursorLayer.path = path
        cursorHaloLayer.path = path
    }

    // MARK: Hits

    /// What a click at `point` (view coordinates) takes, in the design's
    /// priority (§4): the selected spot's source and resize handle, then the
    /// inside of any ring, newest first.
    func target(at point: CGPoint) -> (id: UUID, part: Part)? {
        let shown = shownSpots
        if let selected = shown.first(where: { $0.spot.id == editor?.selectedSpotID }) {
            let handle = resizeHandle(selected)
            if hypot(handle.x - point.x, handle.y - point.y) <= Self.grabDistance { return (selected.spot.id, .resize) }
            if let source = sourcePlaced(selected.spot),
               hypot(source.center.x - point.x, source.center.y - point.y) <= max(source.radius, Self.grabDistance) {
                return (selected.spot.id, .source)
            }
        }
        for item in shown.reversed() where hypot(item.center.x - point.x, item.center.y - point.y) <= item.drawn {
            return (item.spot.id, .spot)
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        return target(at: local) == nil ? nil : super.hitTest(point)
    }

    override func mouseMoved(with event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        updatePointer()
        drawCursor()
    }

    /// The arrow over a spot's ring or a handle (a click there selects, it
    /// does not add), the crosshair over the rest of the photo (design §4).
    /// Set from the pointer, since cursor rectangles can't be circles (design review F4).
    private func updatePointer() {
        guard let editor, editor.isEditingSpots, !isHidden, let cursor, bounds.contains(cursor) else { return }
        (target(at: cursor) == nil ? NSCursor.crosshair : NSCursor.arrow).set()
    }

    override func mouseExited(with event: NSEvent) {
        cursor = nil
        drawCursor()
    }

    /// The canvas's own pointer events reach here too (the scroll view forwards them).
    func pointerMoved(toWindowPoint location: NSPoint?) {
        cursor = location.map { convert($0, from: nil) }
        drawCursor()
    }

    override func mouseDown(with event: NSEvent) {
        guard let editor else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let target = target(at: point),
              let spot = editor.adjustments.spots.spots.first(where: { $0.id == target.id }) else { return }
        // The keyboard goes back to the loupe, as a click on the photo would give it (design review F5).
        NotificationCenter.default.post(name: .browserShouldTakeFocus, object: window)
        editor.selectedSpotID = target.id
        drag = Drag(id: target.id, part: target.part, start: point, original: spot)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !drag.moved {
            guard hypot(point.x - drag.start.x, point.y - drag.start.y) > Self.dragThreshold else { return }
            drag.moved = true
            self.drag = drag
        }
        apply(point, phase: .changing)
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil }
        guard let drag, drag.moved else { return }
        apply(convert(event.locationInWindow, from: nil), phase: .committed)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let target = target(at: point) { editor?.selectedSpotID = target.id }
        return contextMenu?()
    }

    /// The dragged part moved to `point`.
    private func apply(_ point: CGPoint, phase: EditPhase) {
        guard let drag, let editor, let now = editor.maskPoint(fromOutput: unit(point)),
              let then = editor.maskPoint(fromOutput: unit(drag.start)) else { return }
        let dx = now.x - then.x, dy = now.y - then.y
        switch drag.part {
        case .spot:
            editor.moveSpot(drag.id, to: MaskPoint(x: drag.original.center.x + dx, y: drag.original.center.y + dy), phase: phase)
        case .source:
            editor.moveSpotSource(drag.id, to: MaskPoint(x: drag.original.source.x + dx, y: drag.original.source.y + dy),
                                  phase: phase)
        case .resize:
            guard let geometry = editor.spotGeometry else { return }
            let center = geometry.pixels(drag.original.center), pointer = geometry.pixels(now)
            let size = Double(hypot(pointer.x - center.x, pointer.y - center.y)) / geometry.longEdge
            editor.resizeSpot(drag.id, to: size, actionName: String(localized: "Resize Spot", comment: "Undo action name and History label"),
                              phase: phase)
        }
    }

    // MARK: Accessibility (design §12)

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? {
        guard let editor, editor.isEditingSpots, editor.showsSpotOverlay else { return [] }
        return shownSpots.map { SpotAccessibilityElement(spot: $0.spot, frame: frame(for: $0), overlay: self) }
    }

    private func frame(for item: Placed) -> NSRect {
        let rect = CGRect(x: item.center.x - item.drawn, y: item.center.y - item.drawn, width: 2 * item.drawn, height: 2 * item.drawn)
        return NSAccessibility.screenRect(fromView: self, rect: rect)
    }

    /// The actions VoiceOver offers on a spot: only those that can act.
    func actions(for spot: Spot) -> [NSAccessibilityCustomAction] {
        guard let editor else { return [] }
        var actions: [NSAccessibilityCustomAction] = []
        func add(_ name: String, _ body: @escaping @MainActor (AdjustmentEditor) -> Void) {
            actions.append(NSAccessibilityCustomAction(name: name) { [weak editor] in
                guard let editor else { return false }
                MainActor.assumeIsolated {
                    editor.selectedSpotID = spot.id
                    body(editor)
                }
                return true
            })
        }
        add(String(localized: "Select", comment: "VoiceOver action on a spot")) { _ in }
        add(spot.mode == .heal ? String(localized: "Switch to Clone", comment: "VoiceOver action on a spot")
                               : String(localized: "Switch to Heal", comment: "VoiceOver action on a spot")) {
            $0.setSpotMode(spot.mode == .heal ? .clone : .heal)
        }
        let step = editor.spotNudgeStep
        for (direction, name, source) in Self.nudges {
            add(name) { editor in
                editor.nudgeSelectedSpot(dx: direction.dx * Double(step.width), dy: direction.dy * Double(step.height),
                                         source: source)
                editor.commitSpotNudge()
            }
        }
        add(SpotText.chooseSource) { $0.chooseSpotSourceAutomatically() }
        add(SpotText.delete) { $0.deleteSpot(spot.id) }
        return actions
    }

    private static var nudges: [((dx: Double, dy: Double), String, Bool)] {
        [((-1, 0), String(localized: "Move Spot Left", comment: "VoiceOver action on a spot"), false),
         ((1, 0), String(localized: "Move Spot Right", comment: "VoiceOver action on a spot"), false),
         ((0, -1), String(localized: "Move Spot Up", comment: "VoiceOver action on a spot"), false),
         ((0, 1), String(localized: "Move Spot Down", comment: "VoiceOver action on a spot"), false),
         ((-1, 0), String(localized: "Move Source Left", comment: "VoiceOver action on a spot"), true),
         ((1, 0), String(localized: "Move Source Right", comment: "VoiceOver action on a spot"), true),
         ((0, -1), String(localized: "Move Source Up", comment: "VoiceOver action on a spot"), true),
         ((0, 1), String(localized: "Move Source Down", comment: "VoiceOver action on a spot"), true)]
    }
}

/// One spot as VoiceOver sees it: a button labelled "Spot 3, Heal, upper left".
final class SpotAccessibilityElement: NSAccessibilityElement {
    /// Selects the spot: what a VoiceOver press does.
    private let press: @MainActor @Sendable () -> Void

    @MainActor
    init(spot: Spot, frame: NSRect, overlay: SpotOverlayView) {
        let id = spot.id
        press = { [weak overlay] in
            overlay?.editor?.selectedSpotID = id
            overlay?.refresh()
        }
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityParent(overlay.accessibilityHost ?? overlay)
        setAccessibilityFrame(frame)
        if let editor = overlay.editor {
            setAccessibilityLabel(SpotText.elementLabel(spot, editor: editor))
            if editor.selectedSpotID == spot.id {
                setAccessibilityValue(String(localized: "Selected", comment: "VoiceOver value of the selected spot"))
            }
        }
        setAccessibilityHelp(String(localized: "Press to select", comment: "VoiceOver help of a spot on the photo"))
        setAccessibilityCustomActions(overlay.actions(for: spot))
    }

    // AppKit asks accessibility questions on the main thread.
    override func accessibilityPerformPress() -> Bool {
        let press = press
        MainActor.assumeIsolated { press() }
        return true
    }
}
