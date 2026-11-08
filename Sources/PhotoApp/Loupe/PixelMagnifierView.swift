import AppKit
import PhotoCore
import PhotoUI

/// The pixel magnifier's drawing (docs/features/chromatic-aberration/design.md
/// §20): a round picture of the photo's own pixels with an outlined middle
/// pixel, and a plate of values under it. Plain drawing in the content layer
/// with no interaction of its own: it takes no clicks, no keyboard focus and
/// has no accessibility element. It knows no tool; the loupe gives it what to show.
final class PixelMagnifierView: NSView {
    /// What the magnifier shows now.
    struct Content: Equatable {
        /// Nil until the tool's pixels are ready.
        var picture: PixelMagnifier.Picture?
        var values: PixelMagnifierValues?
        var verdict = PixelMagnifierVerdict.fine
        var note: String?
        var level = PixelMagnifierLevel.standard
        var backing = 2
    }

    private static let side = PixelMagnifierLayout.ringDiameter
    private static let pictureOrigin = (PixelMagnifierLayout.ringDiameter - PixelMagnifierLayout.pictureDiameter) / 2

    private let pictureLayer = CALayer()
    private let gridLayer = CAShapeLayer()
    private let outlineLayers = [CAShapeLayer(), CAShapeLayer()]
    private let ringLayers = [CAShapeLayer(), CAShapeLayer()]
    private let plate = PixelMagnifierPlate()
    private let spinner = NSProgressIndicator()
    private var content = Content()
    private var geometryKey: (level: Int, backing: Int, contrast: Bool)?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(origin: .zero, size: PixelMagnifierLayout.compositeSize))
        wantsLayer = true
        guard let root = layer else { return }
        let diameter = PixelMagnifierLayout.pictureDiameter
        pictureLayer.frame = CGRect(x: Self.pictureOrigin, y: Self.pictureOrigin, width: diameter, height: diameter)
        pictureLayer.cornerRadius = diameter / 2
        pictureLayer.masksToBounds = true
        pictureLayer.magnificationFilter = .nearest
        pictureLayer.minificationFilter = .nearest
        pictureLayer.contentsGravity = .resize
        pictureLayer.actions = ["contents": NSNull()]
        root.addSublayer(pictureLayer)
        pictureLayer.addSublayer(gridLayer)
        for layer in outlineLayers {
            layer.fillColor = nil
            layer.lineJoin = .miter
            pictureLayer.addSublayer(layer)
        }
        let center = CGPoint(x: Self.side / 2, y: Self.side / 2)
        for (index, layer) in ringLayers.enumerated() {
            let radius = diameter / 2 + (index == 0 ? 1 : 2.5)
            layer.path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
                                transform: nil)
            layer.fillColor = nil
            layer.strokeColor = index == 0 ? NSColor(white: 0.9, alpha: 1).cgColor : NSColor(white: 0.1, alpha: 1).cgColor
            layer.lineWidth = index == 0 ? 2 : 1
            root.addSublayer(layer)
        }
        ringLayers[1].shadowOpacity = 0.4
        ringLayers[1].shadowRadius = 4
        ringLayers[1].shadowOffset = CGSize(width: 0, height: 2)
        plate.frame = NSRect(x: 0, y: Self.side + PixelMagnifierLayout.plateGap, width: Self.side,
                             height: PixelMagnifierLayout.plateHeight)
        addSubview(plate)
        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isDisplayedWhenStopped = false
        spinner.frame = NSRect(x: (Self.side - 16) / 2, y: (Self.side - 16) / 2, width: 16, height: 16)
        spinner.setAccessibilityElement(false)
        addSubview(spinner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// It takes no clicks: a click over its drawing goes to the photo and picks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }

    func setSpinning(_ spinning: Bool) {
        if spinning { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    func show(_ content: Content) {
        guard content != self.content || pictureLayer.contents == nil else { return }
        self.content = content
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateGeometry()
        pictureLayer.contents = content.picture.flatMap(Self.image) ?? Self.surroundImage(size: Int(PixelMagnifierLayout.pictureDiameter) * content.backing)
        gridLayer.isHidden = !content.level.showsGrid || content.picture == nil
        outlineLayers.forEach { $0.isHidden = content.picture == nil }
        CATransaction.commit()
        plate.show(content)
    }

    /// The grid and the outline are fixed for a level: the outlined pixel is
    /// always the picture's middle.
    private func updateGeometry() {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        guard geometryKey?.level != content.level.rawValue || geometryKey?.backing != content.backing
                || geometryKey?.contrast != contrast else { return }
        geometryKey = (content.level.rawValue, content.backing, contrast)
        let scale = CGFloat(content.backing)
        let device = Int(PixelMagnifierLayout.pictureDiameter) * content.backing
        let cell = content.level.cellSize
        pictureLayer.contentsScale = scale
        // Cell edges, in points, relative to the middle cell's top left corner.
        let middle = CGFloat((device - cell) / 2) / scale
        let step = CGFloat(cell) / scale
        let path = CGMutablePath()
        let length = CGFloat(device) / scale
        var offset = middle.truncatingRemainder(dividingBy: step)
        while offset < length {
            let line = offset + 0.5 / scale
            path.move(to: CGPoint(x: line, y: 0))
            path.addLine(to: CGPoint(x: line, y: length))
            path.move(to: CGPoint(x: 0, y: line))
            path.addLine(to: CGPoint(x: length, y: line))
            offset += step
        }
        gridLayer.frame = pictureLayer.bounds
        gridLayer.path = path
        gridLayer.lineWidth = 1 / scale
        gridLayer.strokeColor = NSColor(white: 0.5, alpha: contrast ? 0.45 : 0.3).cgColor
        let weight: CGFloat = contrast ? 2 : 1
        let pixel = CGRect(x: middle, y: middle, width: step, height: step)
        for (index, layer) in outlineLayers.enumerated() {
            let inset = -weight * (CGFloat(index) + 0.5)
            layer.path = CGPath(rect: pixel.insetBy(dx: inset, dy: inset), transform: nil)
            layer.lineWidth = weight
            layer.strokeColor = index == 0 ? NSColor.white.cgColor : NSColor.black.cgColor
        }
    }

    private static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

    /// The surround color as the bitmap's 8-bit Display P3 components.
    private static func surround() -> (r: UInt8, g: UInt8, b: UInt8) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            Palette.loupeBackground.usingColorSpace(.displayP3)?.getRed(&red, green: &green, blue: &blue, alpha: nil)
        }
        return (UInt8(red * 255), UInt8(green * 255), UInt8(blue * 255))
    }

    private static func image(_ picture: PixelMagnifier.Picture) -> CGImage? {
        cgImage(picture.bitmap(surround: surround()), size: picture.deviceSize)
    }

    private static func surroundImage(size: Int) -> CGImage? {
        let color = surround()
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            rgba[i] = color.r
            rgba[i + 1] = color.g
            rgba[i + 2] = color.b
        }
        return cgImage(rgba, size: size)
    }

    private static func cgImage(_ rgba: [UInt8], size: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: displayP3, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// The plate of values under the picture (design §20 "The plate"): two lines
/// that never change size.
private final class PixelMagnifierPlate: NSView {
    private var content = PixelMagnifierView.Content()

    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { false }

    func show(_ content: PixelMagnifierView.Content) {
        self.content = content
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor(white: 0.12, alpha: 1).setFill()
        path.fill()
        let secondary = NSColor(white: 1, alpha: contrast ? 1 : 0.6)
        let refused = if case .refused = content.verdict { true } else { false }
        // Dimmed numbers, the symbol and the word carry a refusal; never color alone.
        let primary = refused && !contrast ? secondary : NSColor.white
        let digits = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let letters = NSFont.systemFont(ofSize: 10)
        let values = content.values
        let columns: [(String, String)] = [
            (PixelMagnifierText.red, values.map { String($0.r) } ?? "–"),
            (PixelMagnifierText.green, values.map { String($0.g) } ?? "–"),
            (PixelMagnifierText.blue, values.map { String($0.b) } ?? "–"),
            (PixelMagnifierText.luminance, values.map { String($0.l) } ?? "–"),
        ]
        let columnWidth = (bounds.width - 12) / 4
        for (index, column) in columns.enumerated() {
            let x = 6 + CGFloat(index) * columnWidth
            (column.0 as NSString).draw(at: NSPoint(x: x, y: 4), withAttributes: [.font: letters, .foregroundColor: secondary])
            let attributes: [NSAttributedString.Key: Any] = [.font: digits, .foregroundColor: primary]
            let size = (column.1 as NSString).size(withAttributes: attributes)
            (column.1 as NSString).draw(at: NSPoint(x: x + columnWidth - 3 - size.width, y: 3), withAttributes: attributes)
        }
        let small = NSFont.systemFont(ofSize: 10)
        (PixelMagnifierText.title(content.level) as NSString)
            .draw(at: NSPoint(x: 6, y: 19), withAttributes: [.font: small, .foregroundColor: secondary])
        drawRightOfSecondLine(small: small, secondary: secondary)
    }

    private func drawRightOfSecondLine(small: NSFont, secondary: NSColor) {
        guard content.picture != nil else { return }
        if case .refused(let text) = content.verdict {
            let attributes: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: NSColor.white]
            let width = (text as NSString).size(withAttributes: attributes).width
            (text as NSString).draw(at: NSPoint(x: bounds.width - 6 - width, y: 19), withAttributes: attributes)
            let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                symbol.draw(in: NSRect(x: bounds.width - 6 - width - symbol.size.width - 3, y: 20, width: symbol.size.width, height: symbol.size.height))
            }
        } else if let note = content.note {
            let attributes: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: secondary]
            let width = (note as NSString).size(withAttributes: attributes).width
            (note as NSString).draw(at: NSPoint(x: bounds.width - 6 - width, y: 19), withAttributes: attributes)
        }
    }
}
