import Foundation
import ImageIO

/// What a source file says about its color, read from its header only.
public enum SourceColorModel {
    /// True when the file is known to hold no color: its image's color model
    /// is gray (a gray JPEG, TIFF or PNG). False for a raw, whatever its
    /// sensor (a raw is never called colorless: Black & White design §6),
    /// for any color model other than gray, and for a file that can't be read.
    /// Reads the header, never the pixels; call it off the main actor.
    public static func isMonochrome(_ url: URL) -> Bool {
        guard !SupportedFormats.isRaw(pathExtension: url.pathExtension),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelGray as String
    }
}
