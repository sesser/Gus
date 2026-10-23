import Foundation

/// File types the importer picks up, by extension.
public enum SupportedFormats {
    public static let rawExtensions: Set<String> = ["cr3", "cr2", "nef", "arw", "dng", "raf", "orf", "rw2"]
    public static let bitmapExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "tif", "tiff", "png"]
    public static let allExtensions = rawExtensions.union(bitmapExtensions)

    public static func isSupported(_ url: URL) -> Bool {
        allExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isRaw(pathExtension: String) -> Bool {
        rawExtensions.contains(pathExtension.lowercased())
    }
}

/// A candidate master found on disk.
public struct ScannedFile: Hashable, Sendable {
    public var url: URL
    public var fileSize: Int64
    public var modifiedAt: Date
    /// Mount point of the volume holding the file.
    public var volumeURL: URL
}

/// Recursively lists supported image files under a folder. Hidden files and the
/// contents of packages (bundles, libraries of other apps) are skipped.
public enum FileScanner {
    static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .volumeURLKey,
    ]

    /// Sorted by path. Checks for cancellation as it goes.
    public static func scan(_ root: URL) throws -> [ScannedFile] {
        let root = root.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true } // keep going past unreadable folders
        ) else { return [] }

        var files: [ScannedFile] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited.isMultiple(of: 512) { try Task.checkCancellation() }
            guard SupportedFormats.isSupported(url),
                  let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile == true,
                  let volumeURL = values.volume
            else { continue }
            files.append(ScannedFile(url: url, fileSize: Int64(values.fileSize ?? 0),
                                     modifiedAt: values.contentModificationDate ?? .distantPast,
                                     volumeURL: volumeURL))
        }
        try Task.checkCancellation()
        return files.sorted { $0.url.path < $1.url.path }
    }
}
