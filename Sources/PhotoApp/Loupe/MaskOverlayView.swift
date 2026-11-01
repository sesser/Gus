import AppKit
import PhotoCore
import PhotoUI

/// Handles for the selected mask over the loupe's photo: the ends of linear
/// gradients and the band they fade over, the center, radii and outline of
/// radial ones, and the brush cursor with its size and feather rings.
///
/// It sits inside the image view, so it zooms and scrolls with the photo.
/// Points are unit coordinates of the photo on screen (the output frame, y
/// down), mapped to the mask frame by the editor (`CropGeometry`). Each drag
/// is one undo step: frames render while it moves, it saves on release. With
/// nothing to drag (no mask selected, or only ranges), clicks pass through.
@MainActor
final class MaskOverlayView: NSView {
    weak var editor: AdjustmentEditor?

    private let lineLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let cursorLayer = CAShapeLayer()
    private var cursor: CGPoint?
    private var drag: Drag?

    private enum Part: Equatable {
        case linearStart, linearEnd, linearBody
        case radialCenter, radialX, radialY
    }

    private struct Drag {
        var component: Int
        var part: Part
        var start: CGPoint
        var shape: MaskShape
    }

    private static let handleRadius: CGFloat = 6
    private static let grabDistance: CGFloat = 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shapeLayer in [lineLayer, handleLayer, cursorLayer] {
            shapeLayer.fillColor = nil
            shapeLayer.lineWidth = 1.5
            shapeLayer.actions = ["path": NSNull()]
            layer?.addSublayer(shapeLayer)
        }
        lineLayer.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        lineLayer.shadowOpacity = 0.6
        lineLayer.shadowRadius = 1
        lineLayer.shadowOffset = .zero
        handleLayer.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        handleLayer.fillColor = NSColor.white.cgColor
        cursorLayer.strokeColor = NSColor.white.cgColor
        cursorLayer.shadowOpacity = 0.7
        cursorLayer.shadowRadius = 1
        cursorLayer.shadowOffset = .zero
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

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

    private func view(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: unit.x * bounds.width, y: unit.y * bounds.height)
    }

    private func unit(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / max(bounds.width, 1), y: point.y / max(bounds.height, 1))
    }

    private func view(_ point: MaskPoint) -> CGPoint? {
        editor?.outputPoint(fromMask: point).map(view)
    }

    /// A point `dx`, `dy` pixels (y down) of the mask frame away from `point`.
    private func offset(_ point: MaskPoint, dx: Double, dy: Double) -> MaskPoint? {
        guard let size = editor?.maskSourceSize else { return nil }
        return MaskPoint(x: point.x + dx / Double(size.width), y: point.y + dy / Double(size.height))
    }

    private var longEdge: Double {
        editor?.maskSourceSize.map { Double(max($0.width, $0.height)) } ?? 1
    }

    /// Radial handles: center, the end of the x radius, the end of the y radius, in the view.
    private func radialPoints(_ gradient: RadialGradient) -> (center: CGPoint, x: CGPoint, y: CGPoint)? {
        let angle = gradient.rotation * .pi / 180
        let rx = gradient.radiusX * longEdge, ry = gradient.radiusY * longEdge
        guard let center = view(gradient.center),
              let xEnd = offset(gradient.center, dx: cos(angle) * rx, dy: sin(angle) * rx).flatMap(view),
              let yEnd = offset(gradient.center, dx: -sin(angle) * ry, dy: cos(angle) * ry).flatMap(view)
        else { return nil }
        return (center, xEnd, yEnd)
    }

    // MARK: Drawing

    /// Redraws from the editor's selected mask.
    func refresh() {
        let lines = CGMutablePath(), handles = CGMutablePath()
        func handle(_ point: CGPoint) {
            handles.addEllipse(in: CGRect(x: point.x - Self.handleRadius, y: point.y - Self.handleRadius,
                                          width: 2 * Self.handleRadius, height: 2 * Self.handleRadius))
        }
        if let mask = editor?.selectedMask, editor?.isBrushing != true {
            for component in mask.components {
                switch component.shape {
                case .linear(let gradient):
                    guard let a = view(gradient.start), let b = view(gradient.end) else { continue }
                    lines.move(to: a)
                    lines.addLine(to: b)
                    // The band the gradient fades over, across the line.
                    let f = gradient.feather / 100
                    let d = CGVector(dx: b.x - a.x, dy: b.y - a.y)
                    let length = max(hypot(d.dx, d.dy), 1)
                    let across = CGVector(dx: -d.dy / length * 2000, dy: d.dx / length * 2000)
                    for t in [0.5 - f / 2, 0.5 + f / 2] {
                        let p = CGPoint(x: a.x + d.dx * t, y: a.y + d.dy * t)
                        lines.move(to: CGPoint(x: p.x - across.dx, y: p.y - across.dy))
                        lines.addLine(to: CGPoint(x: p.x + across.dx, y: p.y + across.dy))
                    }
                    handle(a)
                    handle(b)
                case .radial(let gradient):
                    guard let points = radialPoints(gradient) else { continue }
                    let angle = gradient.rotation * .pi / 180
                    let rx = gradient.radiusX * longEdge, ry = gradient.radiusY * longEdge
                    for step in 0...72 {
                        let t = Double(step) / 72 * 2 * .pi
                        let x = cos(t) * rx, y = sin(t) * ry
                        guard let p = offset(gradient.center, dx: cos(angle) * x - sin(angle) * y,
                                             dy: sin(angle) * x + cos(angle) * y).flatMap(view) else { continue }
                        if step == 0 { lines.move(to: p) } else { lines.addLine(to: p) }
                    }
                    lines.move(to: points.center)
                    lines.addLine(to: points.x)
                    handle(points.center)
                    handle(points.x)
                    handle(points.y)
                default:
                    continue
                }
            }
        }
        lineLayer.path = lines
        handleLayer.path = handles
        drawCursor()
    }

    /// The brush's size and feather rings around the pointer.
    private func drawCursor() {
        let path = CGMutablePath()
        if let editor, editor.isBrushing, let cursor, let center = editor.maskPoint(fromOutput: unit(cursor)) {
            let radius = editor.brushTemplate.size * longEdge
            let core = radius * (1 - editor.brushTemplate.feather / 100)
            for r in [radius, core] where r > 0 {
                guard let edge = offset(center, dx: r, dy: 0).flatMap(view) else { continue }
                let viewRadius = hypot(edge.x - cursor.x, edge.y - cursor.y)
                path.addEllipse(in: CGRect(x: cursor.x - viewRadius, y: cursor.y - viewRadius, width: 2 * viewRadius,
                                           height: 2 * viewRadius))
            }
        }
        cursorLayer.path = path
    }

    // MARK: Events

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let editor, let mask = editor.selectedMask, !isHidden else { return nil }
        if editor.isBrushing || editor.isSamplingColor { return super.hitTest(point) }
        let local = convert(point, from: superview)
        return target(at: local, in: mask) == nil ? nil : super.hitTest(point)
    }

    private func target(at point: CGPoint, in mask: Mask) -> (component: Int, part: Part)? {
        func near(_ p: CGPoint?) -> Bool { p.map { hypot($0.x - point.x, $0.y - point.y) <= Self.grabDistance } ?? false }
        for (index, component) in mask.components.enumerated().reversed() {
            switch component.shape {
            case .linear(let gradient):
                let a = view(gradient.start), b = view(gradient.end)
                if near(a) { return (index, .linearStart) }
                if near(b) { return (index, .linearEnd) }
                if let a, let b {
                    let d = CGVector(dx: b.x - a.x, dy: b.y - a.y)
                    let t = ((point.x - a.x) * d.dx + (point.y - a.y) * d.dy) / max(d.dx * d.dx + d.dy * d.dy, 1)
                    let closest = CGPoint(x: a.x + d.dx * t, y: a.y + d.dy * t)
                    if (0...1).contains(t), near(closest) { return (index, .linearBody) }
                }
            case .radial(let gradient):
                guard let points = radialPoints(gradient) else { continue }
                if near(points.x) { return (index, .radialX) }
                if near(points.y) { return (index, .radialY) }
                if near(points.center) { return (index, .radialCenter) }
            default:
                continue
            }
        }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        drawCursor()
    }

    override func mouseExited(with event: NSEvent) {
        cursor = nil
        drawCursor()
    }

    override func mouseDown(with event: NSEvent) {
        guard let editor, let mask = editor.selectedMask else { return }
        let point = convert(event.locationInWindow, from: nil)
        if editor.isSamplingColor {
            editor.sampleColor(at: unit(point))
            return
        }
        if editor.isBrushing {
            editor.beginStroke(at: unit(point))
            return
        }
        guard let target = target(at: point, in: mask) else { return }
        drag = Drag(component: target.component, part: target.part, start: point,
                    shape: mask.components[target.component].shape)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        if editor?.isBrushing == true {
            editor?.continueStroke(to: unit(point))
            drawCursor()
            return
        }
        apply(point, phase: .changing)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if editor?.isBrushing == true {
            editor?.continueStroke(to: unit(point), finished: true)
            return
        }
        apply(point, phase: .committed)
        drag = nil
    }

    /// The dragged part moved to `point`.
    private func apply(_ point: CGPoint, phase: EditPhase) {
        guard let drag, let editor, let target = editor.maskPoint(fromOutput: unit(point)),
              let origin = editor.maskPoint(fromOutput: unit(drag.start)) else { return }
        var shape = drag.shape
        switch (shape, drag.part) {
        case (.linear(var gradient), .linearStart):
            gradient.start = target
            shape = .linear(gradient)
        case (.linear(var gradient), .linearEnd):
            gradient.end = target
            shape = .linear(gradient)
        case (.linear(var gradient), .linearBody):
            let dx = target.x - origin.x, dy = target.y - origin.y
            gradient.start = MaskPoint(x: gradient.start.x + dx, y: gradient.start.y + dy)
            gradient.end = MaskPoint(x: gradient.end.x + dx, y: gradient.end.y + dy)
            shape = .linear(gradient)
        case (.radial(var gradient), .radialCenter):
            gradient.center = target
            shape = .radial(gradient)
        case (.radial(var gradient), .radialX), (.radial(var gradient), .radialY):
            guard let size = editor.maskSourceSize else { return }
            // In mask-frame pixels, y down.
            let dx = (target.x - gradient.center.x) * Double(size.width)
            let dy = (target.y - gradient.center.y) * Double(size.height)
            let distance = hypot(dx, dy) / longEdge
            if drag.part == .radialX {
                gradient.radiusX = min(max(distance, RadialGradient.radiusRange.lowerBound), RadialGradient.radiusRange.upperBound)
                gradient.rotation = atan2(dy, dx) * 180 / .pi
            } else {
                let angle = gradient.rotation * .pi / 180
                let along = abs(-sin(angle) * dx + cos(angle) * dy) / longEdge
                gradient.radiusY = min(max(along, RadialGradient.radiusRange.lowerBound), RadialGradient.radiusRange.upperBound)
            }
            shape = .radial(gradient)
        default:
            return
        }
        editor.setComponent(drag.component, String(localized: "Move Mask Handle"), phase: phase) { $0.shape = shape }
    }
}
