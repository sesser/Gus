import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Watermark images copied into the library, named by the SHA-256 of their
/// contents, so a preset keeps its watermark when the original file moves.
public struct WatermarkStore: Sendable {
    public static let folderName = "Watermarks"
    public static let fileExtension = "png"

    public enum Failure: Error, Equatable {
        /// Not a PNG ImageIO can read.
        case notPNG
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The store inside a library's catalog folder.
    public init(locations: LibraryLocations) {
        self.init(directory: locations.catalogDirectory.appending(path: Self.folderName, directoryHint: .isDirectory))
    }

    /// Validates `url` as a PNG and copies it into the store (once per content).
    /// Returns a watermark with the default placement.
    public func importFile(at url: URL) throws -> Watermark {
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) > 0
        else { throw Failure.notPNG }
        let identifier = Digest.sha256Hex(data)
        let destination = fileURL(for: identifier)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
        return Watermark(identifier: identifier, name: url.lastPathComponent)
    }

    public func contains(_ identifier: String) -> Bool {
        guard Self.isValid(identifier) else { return false }
        return FileManager.default.fileExists(atPath: fileURL(for: identifier).path)
    }

    /// Where the file for `identifier` is (or would be).
    public func fileURL(for identifier: String) -> URL {
        directory.appending(path: identifier + "." + Self.fileExtension, directoryHint: .notDirectory)
    }

    /// Identifiers are hex digests, never paths.
    static func isValid(_ identifier: String) -> Bool {
        identifier.count == 64 && identifier.allSatisfy(\.isHexDigit)
    }
}
