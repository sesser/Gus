import AppKit
import PhotoCore

/// The images grid cells draw with (the library grid's and the import
/// grid's): SF Symbols, rows of stars and type badges, rendered once each.
/// SF Symbols rendered once into images layers can use.
@MainActor
public enum Symbols {
    private static var cache: [String: CGImage] = [:]

    public static func image(_ name: String, color: NSColor, pointSize: CGFloat) -> CGImage? {
        let key = "\(name)|\(color.description)|\(pointSize)"
        if let cached = cache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return nil }
        var rect = CGRect(origin: .zero, size: symbol.size)
        let image = symbol.cgImage(forProposedRect: &rect, context: nil,
                                   hints: [.ctm: AffineTransform(scale: 2)])
        cache[key] = image
        return image
    }
}

extension Symbols {
    private static var starCache: [String: CGImage] = [:]

    /// `count` filled stars in a row, as one image (nil for none).
    public static func stars(_ count: Int, color: NSColor, pointSize: CGFloat) -> CGImage? {
        guard count > 0 else { return nil }
        let key = "\(count)|\(color.description)"
        if let cached = starCache[key] { return cached }
        guard let star = image("star.fill", color: color, pointSize: pointSize) else { return nil }
        let gap = 2
        let width = star.width * count + gap * (count - 1)
        guard let context = CGContext(data: nil, width: width, height: star.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for index in 0..<count {
            context.draw(star, in: CGRect(x: index * (star.width + gap), y: 0, width: star.width, height: star.height))
        }
        let image = context.makeImage()
        starCache[key] = image
        return image
    }
}

/// Small rounded type badges ("RAW", "JPEG"), rendered once per label.
@MainActor
public enum Badges {
    public struct Badge {
        public let image: CGImage
        /// Size in points.
        public let size: CGSize
    }

    private static var cache: [String: Badge] = [:]

    /// 10 pt bold, in `appearance`'s colors.
    public static func image(_ text: String?, appearance: NSAppearance) -> Badge? {
        guard let text, !text.isEmpty else { return nil }
        let key = text + "|" + appearance.name.rawValue
        if let cached = cache[key] { return cached }
        let font = NSFont.systemFont(ofSize: 10, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.badgeText.resolved(for: appearance),
                                                         .kern: 0.3]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        let size = CGSize(width: ceil(textSize.width) + 8, height: 15)
        let scale: CGFloat = 2
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        let fill = (text.hasPrefix(FileKindText.badge(.raw)) ? Palette.rawBadgeFill : Palette.badgeFill).resolved(for: appearance)
        context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 3, cornerHeight: 3,
                               transform: nil))
        context.setFillColor(fill.cgColor)
        context.fillPath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2 + 0.5))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        let badge = Badge(image: image, size: size)
        cache[key] = badge
        return badge
    }
}
