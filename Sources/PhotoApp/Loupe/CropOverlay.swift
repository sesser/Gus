import AppKit
import PhotoCore
import PhotoUI

/// The loupe while a crop is edited: the whole photo, turned and straightened,
/// a little smaller than the loupe, under the crop frame with its handles and
/// a rule-of-thirds grid (a finer one while straightening).
///
/// Drag inside the frame to move it, from a handle or an edge to resize it,
/// and outside it to straighten. Changes go to the editor, which hands the
/// session back through `configure`; while straightening, the frame stays put
/// on screen and the image grows so it always covers the frame.
///
/// Geometry: the session's rectangle is in unit coordinates of the turned
/// frame. On screen, a point of that frame (pixels from its center, y down)
/// is at `center + scale * point`, with y flipped for the view.
@MainActor
final class CropOverlayView: NSView {
    var onChangeRect: ((CropRect) -> Void)?
    var onStraighten: ((Double, EditPhase) -> Void)?

    private let imageLayer = CALayer()
    private let shadeLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()

    private var image: CGImage?
    private var session: CropSession?
    private var scale: CGFloat = 1
    private var center = CGPoint.zero
    /// The frame on screen at the last layout.
    private var box = CGRect.zero
    private var needsFit = true
    private var drag: Drag?

    private enum Target: Equatable {
        case handle(CropGeometry.Handle)
        case inside
        case outside
    }

    private struct Drag {
        var target: Target
        var start: CGPoint
        var rect: CropRect
        var angle: Double
        /// The frame's center on screen, which a straightening drag turns about.
        var pivot: CGPoint
    }

    /// Room around the image, so the handles at its edges can be reached.
    private static let margin: CGFloat = 36
    private static let handleLength: CGFloat = 18
    private static let grabDistance: CGFloat = 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Palette.loupeBackground.cgColor
        // The image grows past the view while straightening.
        layer?.masksToBounds = true
        layerContentsRedrawPolicy = .never
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        shadeLayer.fillRule = .evenOdd
        shadeLayer.fillColor = NSColor.black.withAlphaComponent(0.6).cgColor
        gridLayer.strokeColor = NSColor.white.withAlphaComponent(0.45).cgColor
        gridLayer.fillColor = nil
        gridLayer.lineWidth = 0.5
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1
        handleLayer.strokeColor = NSColor.white.cgColor
        handleLayer.fillColor = nil
        handleLayer.lineWidth = 3
        handleLayer.lineCap = .square
        for sublayer in [imageLayer, shadeLayer, gridLayer, borderLayer, handleLayer] {
            sublayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "transform": NSNull(),
                                "path": NSNull()]
            layer?.addSublayer(sublayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    /// Shows `session` over `image` (the whole photo, before its quarter turns).
    func configure(session: CropSession, image: CGImage) {
        let previous = self.session
        if image !== self.image {
            self.image = image
            imageLayer.contents = image
        }
        self.session = session
        if previous == nil || previous?.crop.quarterTurns != session.crop.quarterTurns
            || previous?.sourceSize != session.sourceSize {
            needsFit = true
        } else if previous?.crop.angle != session.crop.angle, box.width > 0 {
            holdBox()
        }
        layoutLayers()
    }

    func reset() {
        session = nil
        image = nil
        imageLayer.contents = nil
        drag = nil
        needsFit = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsFit = true
        layoutLayers()
    }

    // MARK: Layout

    private var turnedSize: CGSize { session?.turnedSize ?? .zero }

    /// Centered frame pixels (y down) of a unit point.
    private func framePoint(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: (x - 0.5) * turnedSize.width, y: (y - 0.5) * turnedSize.height)
    }

    private func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: center.x + scale * point.x, y: center.y - scale * point.y)
    }

    /// The unit point of the turned frame under a point of the view.
    private func unitPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - center.x) / scale / turnedSize.width + 0.5,
                y: (center.y - point.y) / scale / turnedSize.height + 0.5)
    }

    private func boxRect(_ rect: CropRect) -> CGRect {
        let topLeft = viewPoint(framePoint(rect.x, rect.y))
        let bottomRight = viewPoint(framePoint(rect.x + rect.width, rect.y + rect.height))
        return CGRect(x: topLeft.x, y: bottomRight.y, width: bottomRight.x - topLeft.x, height: topLeft.y - bottomRight.y)
    }

    private var available: CGRect { bounds.insetBy(dx: Self.margin, dy: Self.margin) }

    /// The whole straightened image in the view.
    private func fitImage() {
        guard let session, available.width > 0, available.height > 0 else { return }
        let radians = session.crop.angle * .pi / 180
        let size = turnedSize
        let width = size.width * abs(cos(radians)) + size.height * abs(sin(radians))
        let height = size.width * abs(sin(radians)) + size.height * abs(cos(radians))
        scale = min(available.width / width, available.height / height)
        center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// The frame as large as the view allows, in its middle.
    private func fitBox() {
        guard let session, available.width > 0, available.height > 0 else { return }
        let rect = session.rect
        let size = turnedSize
        scale = min(available.width / (rect.width * size.width), available.height / (rect.height * size.height))
        let middle = framePoint(rect.midX, rect.midY)
        center = CGPoint(x: bounds.midX - scale * middle.x, y: bounds.midY + scale * middle.y)
    }

    /// Keeps the frame where it was on screen for a new rectangle: the image
    /// scales instead.
    private func holdBox() {
        guard let session else { return }
        let rect = session.rect
        guard rect.width > 0 else { return }
        scale = box.width / (rect.width * turnedSize.width)
        let middle = framePoint(rect.midX, rect.midY)
        center = CGPoint(x: box.midX - scale * middle.x, y: box.midY + scale * middle.y)
    }

    private func layoutLayers() {
        guard let session, let image else { return }
        if needsFit {
            fitImage()
            needsFit = false
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        imageLayer.position = center
        let radians = -(Double(session.crop.quarterTurns) * .pi / 2 + session.crop.angle * .pi / 180)
        imageLayer.transform = CATransform3DRotate(CATransform3DMakeScale(scale, scale, 1), radians, 0, 0, 1)

        box = boxRect(session.rect)
        let shade = CGMutablePath()
        shade.addRect(bounds.insetBy(dx: -1, dy: -1))
        shade.addRect(box)
        shadeLayer.path = shade
        borderLayer.path = CGPath(rect: box, transform: nil)
        gridLayer.path = gridPath(fine: session.isStraightening)
        handleLayer.path = handlePath()
        CATransaction.commit()
    }

    /// Thirds, or a graph-paper grid of square cells for straightening.
    private func gridPath(fine: Bool) -> CGPath {
        let path = CGMutablePath()
        if fine {
            let step = max(min(box.width, box.height) / 10, 8)
            var x = box.minX + step
            while x < box.maxX - 0.5 {
                path.move(to: CGPoint(x: x, y: box.minY))
                path.addLine(to: CGPoint(x: x, y: box.maxY))
                x += step
            }
            var y = box.maxY - step
            while y > box.minY + 0.5 {
                path.move(to: CGPoint(x: box.minX, y: y))
                path.addLine(to: CGPoint(x: box.maxX, y: y))
                y -= step
            }
        } else {
            for fraction in [1.0 / 3, 2.0 / 3] {
                let x = box.minX + box.width * fraction
                let y = box.minY + box.height * fraction
                path.move(to: CGPoint(x: x, y: box.minY))
                path.addLine(to: CGPoint(x: x, y: box.maxY))
                path.move(to: CGPoint(x: box.minX, y: y))
                path.addLine(to: CGPoint(x: box.maxX, y: y))
            }
        }
        return path
    }

    /// Corner brackets and bars at the middle of each edge.
    private func handlePath() -> CGPath {
        let path = CGMutablePath()
        let length = min(Self.handleLength, box.width / 3, box.height / 3)
        for (x, y, dx, dy) in [(box.minX, box.maxY, 1.0, -1.0), (box.maxX, box.maxY, -1, -1),
                               (box.maxX, box.minY, -1, 1), (box.minX, box.minY, 1, 1)] {
            path.move(to: CGPoint(x: x, y: y + dy * length))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * length, y: y))
        }
        path.move(to: CGPoint(x: box.midX - length / 2, y: box.maxY))
        path.addLine(to: CGPoint(x: box.midX + length / 2, y: box.maxY))
        path.move(to: CGPoint(x: box.midX - length / 2, y: box.minY))
        path.addLine(to: CGPoint(x: box.midX + length / 2, y: box.minY))
        path.move(to: CGPoint(x: box.minX, y: box.midY - length / 2))
        path.addLine(to: CGPoint(x: box.minX, y: box.midY + length / 2))
        path.move(to: CGPoint(x: box.maxX, y: box.midY - length / 2))
        path.addLine(to: CGPoint(x: box.maxX, y: box.midY + length / 2))
        return path
    }

    // MARK: Pointer

    /// What a press at `point` would drag. Handles win over the inside, and
    /// the whole length of an edge resizes.
    private func target(at point: CGPoint) -> Target {
        let reach = Self.grabDistance
        let corners: [(CropGeometry.Handle, CGPoint)] = [
            (.topLeft, CGPoint(x: box.minX, y: box.maxY)), (.topRight, CGPoint(x: box.maxX, y: box.maxY)),
            (.bottomRight, CGPoint(x: box.maxX, y: box.minY)), (.bottomLeft, CGPoint(x: box.minX, y: box.minY)),
        ]
        for (handle, corner) in corners where hypot(point.x - corner.x, point.y - corner.y) <= reach * 1.4 {
            return .handle(handle)
        }
        let withinX = point.x >= box.minX - reach && point.x <= box.maxX + reach
        let withinY = point.y >= box.minY - reach && point.y <= box.maxY + reach
        if withinX, abs(point.y - box.maxY) <= reach { return .handle(.top) }
        if withinX, abs(point.y - box.minY) <= reach { return .handle(.bottom) }
        if withinY, abs(point.x - box.minX) <= reach { return .handle(.left) }
        if withinY, abs(point.x - box.maxX) <= reach { return .handle(.right) }
        return box.contains(point) ? .inside : .outside
    }

    private func cursor(for target: Target) -> NSCursor {
        switch target {
        case .handle(let handle): Self.resizeCursor(handle)
        case .inside: drag == nil ? .openHand : .closedHand
        case .outside: Self.rotateCursor
        }
    }

    private static func resizeCursor(_ handle: CropGeometry.Handle) -> NSCursor {
        let position: NSCursor.FrameResizePosition = switch handle {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        }
        return .frameResize(position: position, directions: .all)
    }

    /// A curved arrow: drag to turn the image.
    private static let rotateCursor: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: false) { rect in
            for (color, weight) in [(NSColor.white, NSFont.Weight.heavy), (NSColor.black, .medium)] {
                let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: weight)
                    .applying(.init(paletteColors: [color]))
                guard let symbol = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90",
                                           accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
                else { continue }
                let origin = NSPoint(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2)
                symbol.draw(in: NSRect(origin: origin, size: symbol.size))
            }
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }()

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(for: target(at: convert(event.locationInWindow, from: nil))).set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard drag == nil, session != nil else { return }
        cursor(for: target(at: convert(event.locationInWindow, from: nil))).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let session else { return }
        let point = convert(event.locationInWindow, from: nil)
        drag = Drag(target: target(at: point), start: point, rect: session.rect, angle: session.crop.angle,
                    pivot: CGPoint(x: box.midX, y: box.midY))
        if let drag { cursor(for: drag.target).set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let session, scale > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let size = turnedSize
        switch drag.target {
        case .inside:
            let dx = (point.x - drag.start.x) / scale / size.width
            let dy = (drag.start.y - point.y) / scale / size.height
            onChangeRect?(CropGeometry.moved(drag.rect, dx: dx, dy: dy, angle: session.crop.angle, size: size))
        case .handle(let handle):
            onChangeRect?(CropGeometry.resized(drag.rect, handle: handle, to: unitPoint(point), ratio: session.ratio,
                                               angle: session.crop.angle, size: size))
        case .outside:
            // Angles in the y-down frame, so dragging clockwise turns the image clockwise.
            func angle(_ p: CGPoint) -> Double { atan2(drag.pivot.y - p.y, p.x - drag.pivot.x) }
            var delta = (angle(point) - angle(drag.start)) * 180 / .pi
            if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
            onStraighten?(drag.angle + delta, .changing)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag, let session else { return }
        self.drag = nil
        if drag.target == .outside {
            onStraighten?(session.crop.angle, .committed)
        } else if !bounds.insetBy(dx: 4, dy: 4).contains(box) {
            // The frame went past the view: bring all of it back into sight.
            fitBox()
            layoutLayers()
        }
        cursor(for: target(at: convert(event.locationInWindow, from: nil))).set()
    }
}
