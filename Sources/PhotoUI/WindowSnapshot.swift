import AppKit
import UniformTypeIdentifiers

/// Writes a window's contents to a PNG, for debug scripts (no screen recording
/// permission needed).
@MainActor
public enum WindowSnapshot {
    public static func write(_ window: NSWindow, to url: URL) {
        // An open sheet is its own window; show it rather than the dimmed window behind.
        let window = window.attachedSheet ?? window
        guard let view = window.contentView?.superview ?? window.contentView, let layer = view.layer else {
            print("debug-script: no window to snapshot")
            return
        }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("debug-script: wrote \(url.path)")
    }
}
