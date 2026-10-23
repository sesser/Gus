import Foundation

/// Where the catalog and the preview cache live on disk.
///
/// The parent folders come from `AppBranding`; everything below them uses generic
/// names so that renaming the product only ever moves the top-level folder.
public struct LibraryLocations: Sendable, Equatable {
    /// Directory holding the SQLite catalog and its WAL files.
    public var catalogDirectory: URL
    /// Root of the regenerable preview cache. Safe to delete at any time.
    public var previewCacheDirectory: URL

    public static let catalogFileName = "catalog.sqlite"
    public static let catalogFolderName = "Library"
    public static let previewFolderName = "Previews"

    public init(catalogDirectory: URL, previewCacheDirectory: URL) {
        self.catalogDirectory = catalogDirectory
        self.previewCacheDirectory = previewCacheDirectory
    }

    public var catalogFileURL: URL {
        catalogDirectory.appending(path: Self.catalogFileName, directoryHint: .notDirectory)
    }

    /// Standard per-user locations derived from `AppBranding`.
    public static func standard(fileManager: FileManager = .default) throws -> LibraryLocations {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true)
        return LibraryLocations(
            catalogDirectory: support
                .appending(path: AppBranding.appSupportDirectoryName, directoryHint: .isDirectory)
                .appending(path: catalogFolderName, directoryHint: .isDirectory),
            previewCacheDirectory: caches
                .appending(path: AppBranding.cacheDirectoryName, directoryHint: .isDirectory)
                .appending(path: previewFolderName, directoryHint: .isDirectory)
        )
    }

    /// Self-contained locations under one folder, for tests, benchmarks and
    /// `--library-root` launches.
    public static func rooted(at root: URL) -> LibraryLocations {
        LibraryLocations(
            catalogDirectory: root.appending(path: catalogFolderName, directoryHint: .isDirectory),
            previewCacheDirectory: root.appending(path: previewFolderName, directoryHint: .isDirectory)
        )
    }

    public func createDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: catalogDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: previewCacheDirectory, withIntermediateDirectories: true)
    }
}
