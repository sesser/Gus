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
/// with no lock file (an earlier layout, or a cleanup cut short) once they
/// are a day old, which no running launch can own unless its lock file was
/// removed by something else that long ago (security review N6).
///
/// The base folder is the user's alone (mode 0700), and nothing in it is
/// touched unless it is a real folder, not a symbolic link, owned by this
/// user; no lock file is opened through a symbolic link (security review N5).
public enum PublishTemporaryFolders {
    /// The folder all launches' folders are made in.
    public static var base: URL {
        FileManager.default.temporaryDirectory.appending(path: "\(AppBranding.bundleIdentifier).publish",
                                                         directoryHint: .isDirectory)
    }

    /// This launch's folder, made and locked on first use.
    public static var launchFolder: URL { launch.folder }

    private static let launch: Launch = Launch.make(in: base)

    /// How many names a launch tries before it gives up on the shared base
    /// (security review N6: a cleanup in another copy can take a new name's
    /// lock in the instant between its creation and its locking).
    static let lockAttempts = 8

    /// A folder with no lock file is removed only when it hasn't changed for
    /// this long (security review N6).
    static let unlockedAge: TimeInterval = 24 * 60 * 60

    /// A launch's folder and the descriptor that holds its lock (open until
    /// the process ends; -1 when no lock could be taken).
    struct Launch: Sendable {
        let folder: URL
        let descriptor: Int32

        /// Makes and locks a launch folder under `base`, trying a new name
        /// when a lock can't be taken. With no lock after `lockAttempts`
        /// names, or a base that isn't this user's own folder, the launch
        /// works in a folder of its own outside the base, which no other
        /// launch's cleanup reaches (never an unlocked folder in the base).
        static func make(in base: URL, names: () -> String = { UUID().uuidString }) -> Launch {
            if PublishTemporaryFolders.prepare(base) {
                for _ in 0..<lockAttempts {
                    let name = names()
                    // The lock first, taken as the file is made, then the
                    // folder: a folder is never seen without its held lock.
                    let lock = base.appending(path: name + lockSuffix, directoryHint: .notDirectory)
                    let descriptor = open(lock.path,
                                          O_CREAT | O_EXCL | O_RDWR | O_EXLOCK | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
                                          0o600)
                    guard descriptor >= 0 else { continue }
                    let folder = base.appending(path: name, directoryHint: .isDirectory)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                             attributes: [.posixPermissions: 0o700])
                    return Launch(folder: folder, descriptor: descriptor)
                }
            }
            let own = base.deletingLastPathComponent()
                .appending(path: base.lastPathComponent + "-" + names(), directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: own, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            return Launch(folder: own, descriptor: -1)
        }
    }

    static let lockSuffix = ".lock"

    /// Makes `base` (mode 0700) when it is missing; true when it is a real
    /// folder, not a symbolic link, owned by this user, its mode then set to
    /// 0700 (a base made by an earlier build had the default mode).
    static func prepare(_ base: URL) -> Bool {
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(base.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else {
            return false
        }
        if info.st_mode & 0o777 != 0o700 { chmod(base.path, 0o700) }
        return true
    }

    /// Removes the launch folders under `base` whose launch has ended, and
    /// day-old entries with no lock file; keeps every folder a running
    /// launch holds, this one's included. Does nothing unless `base` is this
    /// user's own real folder.
    public static func removeLeftovers(in base: URL? = nil, now: Date = Date()) {
        let base = base ?? self.base
        let manager = FileManager.default
        var info = stat()
        guard lstat(base.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
              let names = try? manager.contentsOfDirectory(atPath: base.path) else { return }
        let locks = Set(names.filter { $0.hasSuffix(lockSuffix) }.map { String($0.dropLast(lockSuffix.count)) })
        for name in names where !name.hasSuffix(lockSuffix) && !locks.contains(name) {
            let entry = base.appending(path: name)
            var entryInfo = stat()
            guard lstat(entry.path, &entryInfo) == 0 else { continue }
            let modified = Date(timeIntervalSince1970: TimeInterval(entryInfo.st_mtimespec.tv_sec))
            guard now.timeIntervalSince(modified) >= unlockedAge else { continue }
            try? manager.removeItem(at: entry)
        }
        for name in locks {
            let lock = base.appending(path: name + lockSuffix, directoryHint: .notDirectory)
            // Taken only when no process holds it: its launch has ended. A
            // lock file that is a symbolic link is never opened.
            let descriptor = open(lock.path, O_RDONLY | O_EXLOCK | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { continue }
            try? manager.removeItem(at: base.appending(path: name, directoryHint: .isDirectory))
            try? manager.removeItem(at: lock)
            close(descriptor)
        }
    }

    /// A launch folder under `base` held by a lock (tests stand in for other
    /// launches with it). The descriptor stays open until `close`.
    static func makeLaunch(in base: URL, names: () -> String = { UUID().uuidString }) -> (folder: URL, descriptor: Int32) {
        let launch = Launch.make(in: base, names: names)
        return (launch.folder, launch.descriptor)
    }
}
