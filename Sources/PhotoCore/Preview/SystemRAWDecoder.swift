import CoreImage
import Foundation

/// The one test of whether a file is decoded as a raw: by the system's RAW
/// decoder (`CIRAWFilter`), which applies the stack's decode settings (Kelvin
/// white balance, the profile, its noise reduction, extended range, the whole
/// sensor).
///
/// A raw file the system decoder gives no image for (Fujifilm X-E3 files on
/// macOS 27.2.1, issue #161) is decoded by LibRaw instead, and is then a
/// rendered image like a JPEG everywhere: none of the decode settings reach
/// it, the renderer applies relative white balance and its own noise
/// reduction, and the Adjust tab offers what it offers for a file that is not
/// RAW. The file's extension alone does not say which of the two a raw is, so
/// the editor, the live sessions, Auto and the measurements all ask here, and
/// `PreviewGenerator.decode` decides the same way (`RenderContext.isRaw`).
public enum SystemRAWDecoder {
    /// Whether the system's RAW decoder gives an image of `url` decoded as an
    /// untouched photo is (`givesImageUntouched`). Reads the file's header
    /// (20 to 100 ms): callers that ask with every frame keep the answer (`Memo`).
    ///
    /// `PreviewGenerator.decode` decides by the same test: when the stack's
    /// own choices (the whole sensor, a decoder version) leave the system
    /// decoder without an image, it decodes without them before it would turn
    /// to LibRaw, so a raw this says the system reads never gets LibRaw's image.
    public static func reads(_ url: URL) -> Bool {
        guard SupportedFormats.isRaw(pathExtension: url.pathExtension), let raw = CIRAWFilter(imageURL: url) else {
            return false
        }
        return givesImageUntouched(raw)
    }

    /// The test itself, on a filter just made for the file: set up as for a
    /// photo without edits (`RAWDecodeSettings.none`, which pins the decoder
    /// version as every decode does), it has an image. Leaves the filter set
    /// up that way.
    static func givesImageUntouched(_ raw: CIRAWFilter) -> Bool {
        RAWDecodeSettings.none.apply(to: raw)
        return givesImage(raw)
    }

    /// The decoder can give no image, or an empty one, without an error.
    static func givesImage(_ raw: CIRAWFilter) -> Bool {
        RAWDecodeGraph.output(of: raw).map { !$0.extent.isEmpty } ?? false
    }

    /// The answer for one file, read once.
    public struct Memo: Sendable {
        public let source: URL
        private var answer: Bool?

        /// - Parameter known: The answer, when the caller has it already
        ///   (the editor, from `RawDefaults`): the file is then never asked.
        public init(_ source: URL, known: Bool? = nil) {
            self.source = source
            answer = known
        }

        public mutating func reads() -> Bool {
            if let answer { return answer }
            let read = SystemRAWDecoder.reads(source)
            answer = read
            return read
        }

        /// The settings that reach `source`'s decode: `settings` for a raw the
        /// system decoder reads, none for everything else, so a change of a
        /// setting the decode ignores never asks for another decode.
        public mutating func decodeSettings(_ settings: @autoclosure () -> RAWDecodeSettings) -> RAWDecodeSettings {
            reads() ? settings() : .none
        }
    }
}
