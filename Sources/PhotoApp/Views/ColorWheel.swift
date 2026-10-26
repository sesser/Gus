import AppKit
import PhotoCore
import SwiftUI

/// A hue and amount picker: the puck's angle is the hue, its distance from the
/// center the amount. Double-click to clear.
struct ColorWheel: NSViewRepresentable {
    var hue: Double
    var amount: Double
    let onChange: (_ hue: Double, _ amount: Double, EditPhase) -> Void

    func makeNSView(context: Context) -> ColorWheelView {
        ColorWheelView()
    }

    func updateNSView(_ view: ColorWheelView, context: Context) {
        view.onChange = onChange
        view.update(hue: hue, amount: amount)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ColorWheelView, context: Context) -> CGSize? {
        let side = min(proposal.width ?? 160, 170)
        return CGSize(width: proposal.width ?? side, height: side)
    }
}

final class ColorWheelView: NSView {
    var onChange: (Double, Double, EditPhase) -> Void = { _, _, _ in }
    private var hue = 0.0
    private var amount = 0.0
    private var isDragging = false
    private var wheelImage: (diameter: CGFloat, image: CGImage)?

    func update(hue: Double, amount: Double) {
        if !isDragging {
            self.hue = hue
            self.amount = amount
        }
        needsDisplay = true
        setAccessibilityLabel(String(localized: "Color wheel"))
    }

    private var wheel: CGRect {
        let side = min(bounds.width, bounds.height) - 4
        return CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let wheel = self.wheel
        if let image = image(diameter: wheel.width) {
            context.saveGState()
            context.addEllipse(in: wheel)
            context.clip()
            context.draw(image, in: wheel)
            context.restoreGState()
        }
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let ring = NSBezierPath(ovalIn: wheel)
        ring.lineWidth = 1
        ring.stroke()
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: wheel.midX - 4, y: wheel.midY))
        cross.line(to: CGPoint(x: wheel.midX + 4, y: wheel.midY))
        cross.move(to: CGPoint(x: wheel.midX, y: wheel.midY - 4))
        cross.line(to: CGPoint(x: wheel.midX, y: wheel.midY + 4))
        cross.stroke()

        let puck = puckLocation
        let dot = NSBezierPath(ovalIn: CGRect(x: puck.x - 6, y: puck.y - 6, width: 12, height: 12))
        NSColor.white.setStroke()
        dot.lineWidth = 2
        dot.stroke()
        NSColor.black.withAlphaComponent(0.5).setStroke()
        let outline = NSBezierPath(ovalIn: CGRect(x: puck.x - 7.5, y: puck.y - 7.5, width: 15, height: 15))
        outline.lineWidth = 1
        outline.stroke()
    }

    private var puckLocation: CGPoint {
        let radius = wheel.width / 2 * amount / 100
        let angle = hue * .pi / 180
        return CGPoint(x: wheel.midX + cos(angle) * radius, y: wheel.midY + sin(angle) * radius)
    }

    /// Hues around the rim, fading to grey at the center; drawn once per size.
    private func image(diameter: CGFloat) -> CGImage? {
        let scale = window?.backingScaleFactor ?? 2
        let pixels = Int(diameter * scale)
        if let cached = wheelImage, cached.diameter == diameter { return cached.image }
        guard pixels > 0,
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        let rowBytes = context.bytesPerRow
        let buffer = data.bindMemory(to: UInt8.self, capacity: rowBytes * pixels)
        let center = Double(pixels) / 2
        for y in 0..<pixels {
            for x in 0..<pixels {
                let dx = Double(x) + 0.5 - center
                let dy = Double(y) + 0.5 - center
                let distance = min((dx * dx + dy * dy).squareRoot() / center, 1)
                var degrees = atan2(dy, dx) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                let color = NSColor(hue: degrees / 360, saturation: distance * 0.75, brightness: 0.62, alpha: 1)
                let offset = (pixels - 1 - y) * rowBytes + x * 4
                buffer[offset] = UInt8(color.redComponent * 255)
                buffer[offset + 1] = UInt8(color.greenComponent * 255)
                buffer[offset + 2] = UInt8(color.blueComponent * 255)
                buffer[offset + 3] = 255
            }
        }
        guard let image = context.makeImage() else { return nil }
        wheelImage = (diameter, image)
        return image
    }

    // MARK: Editing

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            amount = 0
            needsDisplay = true
            onChange(hue, 0, .committed)
            return
        }
        isDragging = true
        track(event)
    }

    override func mouseDragged(with event: NSEvent) {
        track(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        onChange(hue, amount, .committed)
    }

    private func track(_ event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let dx = location.x - wheel.midX
        let dy = location.y - wheel.midY
        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        hue = degrees.rounded()
        amount = min(hypot(dx, dy) / (wheel.width / 2), 1) * 100
        amount = amount.rounded()
        needsDisplay = true
        onChange(hue, amount, .changing)
    }
}
