import Darwin
import Foundation
import Synchronization

/// An advisory lock on a library, held by the app while the library is open
/// and by command-line write commands while they write.
///
/// The catalog is a WAL database, so other processes can always read it, but
/// the running app does not notice changes another process writes. Write
/// commands therefore refuse while the app holds this lock; read commands
/// never take it. It is a `flock` on `Library/library.lock`: the system drops
/// it when the holder exits or crashes, so it is never left behind. The file
/// holds the holder's process id, for messages only.
public final class LibraryLock: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// Another process holds the lock (its id, when it could be read).
        case held(processID: Int32?)
        case unavailable(errno: Int32)
    }

    public static let fileName = "library.lock"

    public let url: URL
    private let descriptor: Mutex<Int32>

    private init(url: URL, descriptor: Int32) {
        self.url = url
        self.descriptor = Mutex(descriptor)
    }

    deinit { release() }

    public static func url(for locations: LibraryLocations) -> URL {
        locations.catalogDirectory.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// Takes the lock for `locations`, retrying until `timeout` has passed
    /// while another process holds it.
    public static func acquire(_ locations: LibraryLocations, timeout: Duration = .zero) throws(Failure) -> LibraryLock {
        try acquire(at: url(for: locations), timeout: timeout)
    }

    public static func acquire(at url: URL, timeout: Duration = .zero) throws(Failure) -> LibraryLock {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw .unavailable(errno: errno) }
        let deadline = ContinuousClock.now + timeout
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let error = errno
            guard error == EWOULDBLOCK, ContinuousClock.now < deadline else {
                close(descriptor)
                throw error == EWOULDBLOCK ? .held(processID: holder(at: url)) : .unavailable(errno: error)
            }
            usleep(20_000)
        }
        let pid = Array("\(getpid())\n".utf8)
        ftruncate(descriptor, 0)
        _ = pid.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, $0.count, 0) }
        return LibraryLock(url: url, descriptor: descriptor)
    }

    /// The process id written by the holder.
    static func holder(at url: URL) -> Int32? {
        (try? String(contentsOf: url, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Gives the lock up. Further calls do nothing.
    public func release() {
        descriptor.withLock { descriptor in
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
    }
}
