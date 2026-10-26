import AppKit
import PhotoCore
import SwiftUI

/// A point curve over the photo's histogram. Click to add a point, drag to move
/// it, double-click a point to remove it.
struct CurveEditor: NSViewRepresentable {
    var points: [CurvePoint]
    var channel: ToneCurve.Channel
    var histogram: Histogram?
    let onChange: ([CurvePoint], EditPhase) -> Void

    func makeNSView(context: Context) -> CurveEditorView {
        CurveEditorView()
    }

    func updateNSView(_ view: CurveEditorView, context: Context) {
        view.onChange = onChange
        view.update(points: points, channel: channel, histogram: histogram)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CurveEditorView, context: Context) -> CGSize? {
        let width = proposal.width ?? 240
        return CGSize(width: width, height: width)
    }
}

final class CurveEditorView: NSView {
    var onChange: ([CurvePoint], EditPhase) -> Void = { _, _ in }
    private var points = ToneCurve.identityPoints
    private var channel = ToneCurve.Channel.rgb
    private var histogram: Histogram?
    private var dragIndex: Int?
    private static let inset: CGFloat = 6
    private static let hitRadius: CGFloat = 7

    override var isFlipped: Bool { false }

    func update(points: [CurvePoint], channel: ToneCurve.Channel, histogram: Histogram?) {
        // Never move a point out from under the mouse.
        if dragIndex == nil { self.points = points }
        self.channel = channel
        self.histogram = histogram
        needsDisplay = true
        setAccessibilityLabel(String(localized: "Tone Curve"))
    }

    private var plot: CGRect { bounds.insetBy(dx: Self.inset, dy: Self.inset) }

    private func location(of point: CurvePoint) -> CGPoint {
        CGPoint(x: plot.minX + point.x * plot.width, y: plot.minY + point.y * plot.height)
    }

    private func curvePoint(at location: CGPoint) -> CurvePoint {
        CurvePoint(x: min(max((location.x - plot.minX) / plot.width, 0), 1),
                   y: min(max((location.y - plot.minY) / plot.height, 0), 1))
    }

    private var color: NSColor {
        switch channel {
        case .rgb: .labelColor
        case .red: .systemRed
        case .green: .systemGreen
        case .blue: .systemBlue
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let plot = self.plot
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: plot, xRadius: 3, yRadius: 3).fill()

        drawHistogram(in: plot)

        NSColor.white.withAlphaComponent(0.08).setStroke()
        let grid = NSBezierPath()
        for i in 1..<4 {
            let fraction = CGFloat(i) / 4
            grid.move(to: CGPoint(x: plot.minX + fraction * plot.width, y: plot.minY))
            grid.line(to: CGPoint(x: plot.minX + fraction * plot.width, y: plot.maxY))
            grid.move(to: CGPoint(x: plot.minX, y: plot.minY + fraction * plot.height))
            grid.line(to: CGPoint(x: plot.maxX, y: plot.minY + fraction * plot.height))
        }
        grid.lineWidth = 1
        grid.stroke()
        let diagonal = NSBezierPath()
        diagonal.move(to: CGPoint(x: plot.minX, y: plot.minY))
        diagonal.line(to: CGPoint(x: plot.maxX, y: plot.maxY))
        diagonal.setLineDash([3, 3], count: 2, phase: 0)
        diagonal.stroke()

        let spline = MonotoneSpline(points)
        let curve = NSBezierPath()
        let steps = max(Int(plot.width), 2)
        for i in 0...steps {
            let x = Double(i) / Double(steps)
            let point = location(of: CurvePoint(x: x, y: min(max(spline.value(at: x), 0), 1)))
            if i == 0 { curve.move(to: point) } else { curve.line(to: point) }
        }
        curve.lineWidth = 1.5
        color.setStroke()
        curve.stroke()

        for (index, point) in points.enumerated() {
            let center = location(of: point)
            let dot = NSBezierPath(ovalIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            (index == dragIndex ? color : NSColor.windowBackgroundColor).setFill()
            dot.fill()
            color.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
    }

    private func drawHistogram(in plot: CGRect) {
        guard let histogram else { return }
        let bins: [UInt32] = switch channel {
        case .rgb: histogram.luminance
        case .red: histogram.red
        case .green: histogram.green
        case .blue: histogram.blue
        }
        // Clipped ends would flatten everything else; scale to the tallest inner bin.
        let peak = max(Double(bins.dropFirst().dropLast().max() ?? 1), 1)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: plot.minX, y: plot.minY))
        for (index, count) in bins.enumerated() {
            let x = plot.minX + CGFloat(index) / CGFloat(bins.count - 1) * plot.width
            let height = min(Double(count) / peak, 1) * plot.height * 0.9
            path.line(to: CGPoint(x: x, y: plot.minY + height))
        }
        path.line(to: CGPoint(x: plot.maxX, y: plot.minY))
        path.close()
        (channel == .rgb ? NSColor.white : color).withAlphaComponent(0.18).setFill()
        path.fill()
    }

    // MARK: Editing

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hit = points.indices.min { distance(points[$0], location) < distance(points[$1], location) }
            .flatMap { distance(points[$0], location) <= Self.hitRadius ? $0 : nil }
        if event.clickCount == 2 {
            if let hit, hit != 0, hit != points.count - 1 {
                points.remove(at: hit)
                needsDisplay = true
                onChange(points, .committed)
            }
            return
        }
        if let hit {
            dragIndex = hit
        } else {
            let point = curvePoint(at: location)
            let index = points.firstIndex { $0.x > point.x } ?? points.count
            guard index > 0, index < points.count else { return }
            points.insert(point, at: index)
            dragIndex = index
            onChange(points, .changing)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = dragIndex else { return }
        var point = curvePoint(at: convert(event.locationInWindow, from: nil))
        let low = index > 0 ? points[index - 1].x + 0.01 : 0
        let high = index < points.count - 1 ? points[index + 1].x - 0.01 : 1
        point.x = min(max(point.x, low), high)
        points[index] = point
        needsDisplay = true
        onChange(points, .changing)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragIndex != nil else { return }
        dragIndex = nil
        needsDisplay = true
        onChange(points, .committed)
    }

    private func distance(_ point: CurvePoint, _ location: CGPoint) -> CGFloat {
        let center = self.location(of: point)
        return hypot(center.x - location.x, center.y - location.y)
    }
}

/// A segmented control drawn by AppKit.
struct AppKitSegmented: NSViewRepresentable {
    var labels: [String]
    var selection: Int
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.picked(_:)))
        control.controlSize = .small
        control.segmentDistribution = .fillEqually
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onSelect = onSelect
        control.selectedSegment = selection
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void = { _ in }

        @objc func picked(_ sender: NSSegmentedControl) { onSelect(sender.selectedSegment) }
    }
}
