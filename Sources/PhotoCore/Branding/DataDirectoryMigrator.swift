import Foundation
import os

/// Moves the per-user data directory when the product is renamed.
///
/// The catalog lives at `Application Support/<appSupportDirectoryName>/…`. After a
/// rename, `AppBranding.previousAppSupportDirectoryNames` lists the old folder
/// names; on launch the first one that exists is renamed to the current name. The
/// move is a same-volume rename, so it is atomic and leaves nothing half-copied.
/// Old preview caches are deleted rather than moved since they can be regenerated.
public enum DataDirectoryMigrator {
    public enum Outcome: Equatable, Sendable {
        /// The current directory exists (or nothing exists yet); nothing was moved.
        case nothingToDo
        /// An old directory was renamed to the current name.
        case moved(from: URL, to: URL)
        /// Both the current and an old directory exist. Nothing is touched; the old
        /// one is reported so it can be dealt with by hand.
        case conflict(current: URL, previous: URL)
    }

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "migration")

    /// Migrates `parent/<previous>` to `parent/<current>` if needed.
    @discardableResult
    public static func migrateDirectory(
        in parent: URL,
        currentName: String,
        previousNames: [String],
        fileManager: FileManager = .default
    ) throws -> Outcome {
        let current = parent.appending(path: currentName, directoryHint: .isDirectory)
        let candidates = previousNames
            .filter { $0 != currentName }
            .map { parent.appending(path: $0, directoryHint: .isDirectory) }
        let existingPrevious = candidates.first { fileManager.fileExists(atPath: $0.path) }

        if fileManager.fileExists(atPath: current.path) {
            if let existingPrevious {
                log.error("Data directory conflict: \(current.path, privacy: .public) and \(existingPrevious.path, privacy: .public) both exist")
                return .conflict(current: current, previous: existingPrevious)
            }
            return .nothingToDo
        }
        guard let existingPrevious else { return .nothingToDo }
        try fileManager.moveItem(at: existingPrevious, to: current)
        log.notice("Moved data directory \(existingPrevious.path, privacy: .public) to \(current.path, privacy: .public)")
        return .moved(from: existingPrevious, to: current)
    }

    /// Deletes cache folders left behind by earlier names.
    public static func removeObsoleteCaches(
        in parent: URL,
        previousNames: [String],
        currentName: String,
        fileManager: FileManager = .default
    ) {
        for name in previousNames where name != currentName {
            let url = parent.appending(path: name, directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                log.error("Could not remove obsolete cache \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Runs both steps against the standard per-user locations. Call once at launch,
    /// before the catalog is opened.
    @discardableResult
    public static func migrateStandardLocations(fileManager: FileManager = .default) throws -> Outcome {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true)
        removeObsoleteCaches(in: caches, previousNames: AppBranding.previousCacheDirectoryNames,
                             currentName: AppBranding.cacheDirectoryName, fileManager: fileManager)
        return try migrateDirectory(in: support, currentName: AppBranding.appSupportDirectoryName,
                                    previousNames: AppBranding.previousAppSupportDirectoryNames,
                                    fileManager: fileManager)
    }
}
