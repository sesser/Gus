import Darwin
import Foundation

/// Where publishing's rendered files and upload bodies go (R24; code review
/// C5, security review L1): `<temporary folder>/<bundle id>.publish/<launch>/`,
/// one folder per launch, each run a folder inside it that the run removes
/// when it ends.
///
/// Every copy of the app run by one user shares the base folder (the app is
/// not sandboxed, and a scripted copy has the same branding), so a launch
/// never removes another's folder while that copy runs. Each launch holds an
/// exclusive `flock` on `<launch>.lock`, taken atomically as the file is made
/// (`O_EXLOCK`) and before its folder exists, for as long as its process
/// lives; the system drops the lock when the process ends, however it ends.
/// Cleaning up removes only the folders whose lock it can take, and folders
/// with no lock file (an earlier layout, or a cleanup cut short), which no
/// running launch can own.
public enum PublishTemporaryFolders {
    /// The folder all launches' folders are made in.
    public static var base: URL {
        FileManager.default.temporaryDirectory.appending(path: "\(AppBranding.bundleIdentifier).publish",
                                                         directoryHint: .isDirectory)
    }

    /// This launch's folder, made and locked on first use.
    public static var launchFolder: URL { launch.folder }

    private static let launch: Launch = Launch.make(in: base)

    /// A launch's folder and the descriptor that holds its lock (open until
    /// the process ends; -1 when no lock could be taken).
    struct Launch: Sendable {
        let folder: URL
        let descriptor: Int32

        static func make(in base: URL) -> Launch {
            let name = UUID().uuidString
            let folder = base.appending(path: name, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            // The lock first, taken as the file is made, then the folder: a
            // folder is never seen without its held lock.
            let lock = base.appending(path: name + lockSuffix, directoryHint: .notDirectory)
            let descriptor = open(lock.path, O_CREAT | O_EXCL | O_RDWR | O_EXLOCK | O_NONBLOCK | O_CLOEXEC, 0o600)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return Launch(folder: folder, descriptor: descriptor)
        }
    }

    static let lockSuffix = ".lock"

    /// Removes the launch folders under `base` whose launch has ended, and
    /// folders with no lock file; keeps every folder a running launch holds,
    /// this one's included.
    public static func removeLeftovers(in base: URL? = nil) {
        let base = base ?? self.base
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: base.path) else { return }
        let locks = Set(names.filter { $0.hasSuffix(lockSuffix) }.map { String($0.dropLast(lockSuffix.count)) })
        for name in names where !name.hasSuffix(lockSuffix) && !locks.contains(name) {
            try? manager.removeItem(at: base.appending(path: name))
        }
        for name in locks {
            let lock = base.appending(path: name + lockSuffix, directoryHint: .notDirectory)
            // Taken only when no process holds it: its launch has ended.
            let descriptor = open(lock.path, O_RDONLY | O_EXLOCK | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { continue }
            try? manager.removeItem(at: base.appending(path: name, directoryHint: .isDirectory))
            try? manager.removeItem(at: lock)
            close(descriptor)
        }
    }

    /// A launch folder under `base` held by a lock (tests stand in for other
    /// launches with it). The descriptor stays open until `close`.
    static func makeLaunch(in base: URL) -> (folder: URL, descriptor: Int32) {
        let launch = Launch.make(in: base)
        return (launch.folder, launch.descriptor)
    }
}
