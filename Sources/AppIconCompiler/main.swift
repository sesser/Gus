import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Turns square artwork into a macOS .iconset: the art is clipped to the standard
// rounded-square icon body (824 of 1024 px, centered) over a soft drop shadow,
// then rendered at every size iconutil expects. Scripts/build-app.sh runs this,
// then `iconutil -c icns`.
//
// Recent macOS draws .icns icons on a light plate at the non-Retina 16 and 32 px
// sizes, whatever their shape (tested on macOS 27); Retina sizes show the icon as
// is. Avoiding the plate takes the Icon Composer format, compiled by Xcode's
// actool, which the SwiftPM build does not use.
//
// usage: app-icon <artwork> <output.iconset>

struct IconError: Error, CustomStringConvertible {
    let description: String
}

let canvasSize = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185.4
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(size: Int) throws -> CGContext {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw IconError(description: "could not create a \(size) px bitmap") }
    context.interpolationQuality = .high
    return context
}

func loadArtwork(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw IconError(description: "could not read \(url.path)") }
    guard image.width == image.height else {
        throw IconError(description: "artwork must be square, got \(image.width) × \(image.height)")
    }
    return image
}

/// The 1024 px master: artwork filling the rounded-square body, transparent margin.
func makeMaster(_ artwork: CGImage) throws -> CGImage {
    let context = try makeContext(size: canvasSize)
    let shape = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.addPath(shape)
    context.clip()
    context.draw(artwork, in: body)
    guard let master = context.makeImage() else { throw IconError(description: "could not render the master") }
    return master
}

/// Downscales in halving steps before the last resample, which keeps small sizes
/// from aliasing.
func resized(_ image: CGImage, to size: Int) throws -> CGImage {
    var current = image
    while current.width / 2 >= size * 2 {
        current = try draw(current, size: current.width / 2)
    }
    return current.width == size ? current : try draw(current, size: size)
}

func draw(_ image: CGImage, size: Int) throws -> CGImage {
    let context = try makeContext(size: size)
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let result = context.makeImage() else { throw IconError(description: "could not render \(size) px") }
    return result
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw IconError(description: "could not write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError(description: "could not write \(url.path)") }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: app-icon <artwork> <output.iconset>\n".utf8))
    exit(64)
}
do {
    let master = try makeMaster(try loadArtwork(URL(fileURLWithPath: arguments[1])))
    let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
    try? FileManager.default.removeItem(at: output)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            try writePNG(try resized(master, to: points * scale), to: output.appending(path: name))
        }
    }
} catch {
    FileHandle.standardError.write(Data("app-icon: \(error)\n".utf8))
    exit(1)
}
