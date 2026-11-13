import CryptoKit
import Foundation
import GRDB

/// Where the catalog's masters are on disk, for asking whether a file about
/// to be written is one of them. Originals are never written, so anything
/// that puts a file where a person chose (export) asks here first.
///
/// A file is a master's when it is in the same folder under a name the file
/// system would take for the same one. Folders are compared as the file
/// system resolves them (symbolic links followed, `/tmp` and `/private/tmp`
/// the same, the spelling on disk). Names are compared ignoring case and
/// Unicode composition, which is what APFS and HFS+ do by default; on a
/// case-sensitive volume that protects a name too many, never one too few.
///
/// A master's place is protected whether or not its file is there now: a file
/// written where a missing master belongs would be taken for it later.
///
/// Place is only as good as the catalog's knowledge of volumes. A volume it
/// can't recognize once it is mounted elsewhere (one with no UUID and no
/// remount URL, a share under a second address) holds masters at places the
/// catalog has never heard of. So a file is also a master's when it has a
/// master's **content** (`holdsContent(ofFileAt:)`: the size and SHA-256 the
/// catalog keeps for every master), wherever it is and whatever its name.
public struct MasterFiles: Sendable {
    /// What the catalog knows of one master's bytes.
    public struct Content: Hashable, Sendable {
        public var size: Int64
        /// Lowercase hex SHA-256, as `image.contentHash`.
        public var hash: String

        public init(size: Int64, hash: String) {
            self.size = size
            self.hash = hash
        }
    }

    /// File names as the catalog has them, by resolved folder. They are
    /// folded only for the folder asked about (`names(in:)`): a library has
    /// far more masters than any one folder does.
    private var namesByFolder: [String: [String]] = [:]
    /// Every master's size: the cheap question, asked before any file is read.
    private var sizes: Set<Int64> = []
    /// Every master's hash. Equal hashes mean equal bytes and so equal sizes;
    /// nothing has to remember which size goes with which hash.
    private var hashes: Set<String> = []

    /// No masters: for exports that have no catalog.
    public static let none = MasterFiles([URL]())

    public init(_ urls: some Sequence<URL>, contents: some Sequence<Content> = [Content]()) {
        var folders: [String: [String]] = [:]
        for url in urls {
            folders[url.deletingLastPathComponent().path, default: []].append(url.lastPathComponent)
        }
        self.init(namesByFolder: folders, contents: contents)
    }

    /// Each folder is resolved once, however many masters it holds.
    init(namesByFolder folders: [String: [String]], contents: some Sequence<Content> = [Content]()) {
        for (folder, names) in folders {
            namesByFolder[Self.resolvedFolder(folder), default: []].append(contentsOf: names)
        }
        for content in contents {
            sizes.insert(content.size)
            hashes.insert(content.hash)
        }
    }

    public var isEmpty: Bool { namesByFolder.isEmpty && hashes.isEmpty }

    /// Whether the file at `url` has a master's bytes, for a file about to be
    /// replaced. Its size is compared first, and the file is read (SHA-256)
    /// only when that is some master's size, so a folder of ordinary files
    /// costs one `stat` each.
    ///
    /// Says yes when it can't tell: a file of a master's size that can't be
    /// read, or a read cut short because the task was cancelled, is taken for
    /// the master. The caller then replaces nothing, which is the safe side.
    /// A link is followed to the file it names. Reads the disk: not for the
    /// main actor. Holds one chunk of the file at a time (`hash(of:)`).
    public func holdsContent(ofFileAt url: URL) -> Bool {
        guard !hashes.isEmpty else { return false }
        let file = url.resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value else {
            // Nothing there (so nothing to replace), or nothing that can be asked.
            return FileManager.default.fileExists(atPath: file.path)
        }
        guard sizes.contains(size) else { return false }
        guard let hash = try? Self.hash(of: file) else { return true }
        return hashes.contains(hash)
    }

    /// How much of a file is read at a time, and so held, while it is hashed.
    static let hashChunkSize = 1 << 20

    /// SHA-256 of a file as the catalog stores it (`SHA256ContentHasher`: the
    /// whole file, lowercase hex), with a cancellation check between chunks.
    ///
    /// Read with `read(2)` into one buffer that is used again for every chunk,
    /// so hashing holds `hashChunkSize` bytes however large the file is and
    /// however many files one plan hashes. `FileHandle.read(upToCount:)`
    /// hands back autoreleased data, and a plan is one synchronous call with
    /// no autorelease pool of its own: every chunk of every file stayed in
    /// memory until the plan returned (2 GiB held for a 2 GiB file).
    static func hash(of url: URL) throws -> String {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY) } ?? -1
        }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: hashChunkSize, alignment: 16)
        defer { buffer.deallocate() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let count = read(descriptor, buffer.baseAddress, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buffer[..<count]))
        }
        return hasher.finalize().hexString
    }

    public func contains(_ url: URL) -> Bool {
        names(in: url.deletingLastPathComponent()).contains(url.lastPathComponent)
    }

    /// The masters in one folder: resolves the folder once, for checking many names in it.
    public func names(in folder: URL) -> Names {
        guard !namesByFolder.isEmpty, let names = namesByFolder[Self.resolvedFolder(folder.path)] else {
            return Names(folded: [])
        }
        return Names(folded: Set(names.lazy.map(Self.folded)))
    }

    /// The file names of one folder's masters.
    public struct Names: Sendable {
        var folded: Set<String>

        public var isEmpty: Bool { folded.isEmpty }

        public func contains(_ fileName: String) -> Bool {
            !folded.isEmpty && folded.contains(MasterFiles.folded(fileName))
        }
    }

    /// The folder as the file system knows it. Parts that don't exist (a
    /// folder not made yet, an unmounted volume) can't be resolved: they are
    /// kept as written under the deepest folder that exists, folded like names.
    ///
    /// Links are followed first: a URL's resource values describe a link
    /// itself when it is the last part of the path, so the canonical path of
    /// a folder that is a link would be the link's.
    static func resolvedFolder(_ path: String) -> String {
        var url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var missing: [String] = []
        while true {
            if let canonical = (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.canonicalPathKey]))?
                .canonicalPath {
                return missing.reversed().reduce(canonical) { ($0 as NSString).appendingPathComponent(folded($1)) }
            }
            let parent = url.deletingLastPathComponent().standardizedFileURL
            guard parent.path != url.path, url.path != "/" else { return url.path }
            missing.append(url.lastPathComponent)
            url = parent
        }
    }

    /// A name as a case-insensitive file system compares it.
    static func folded(_ name: String) -> String {
        name.decomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: nil)
            .decomposedStringWithCanonicalMapping
    }
}

extension Catalog {
    /// Every master's place on disk. The whole catalog: a file written by an
    /// export must not land on any photo's master, not only on those being
    /// exported.
    ///
    /// A volume's masters are placed at the mount point the catalog recorded
    /// (where export reads them from) and wherever that volume is mounted now
    /// (`mounted`, matched by identity as everywhere else). The recorded path
    /// alone is not enough: it is brought up to date only by the app
    /// (`refreshVolumeAvailability`), so `photocli`, or the app between a
    /// remount and its refresh, would look for a moved volume's masters where
    /// they no longer are and miss them where they are. A volume mounted at
    /// several paths is placed at each. Nothing is written to the catalog.
    ///
    /// Every master's size and content hash come along, for the files a place
    /// can't vouch for (`MasterFiles.holdsContent(ofFileAt:)`).
    public func masterFiles(mounted: [VolumeDescriptor] = VolumeAvailability.mountedVolumes()) async throws
        -> MasterFiles {
        struct Folder: Hashable {
            var volumeID: Int64
            /// Relative to the volume; empty at its root.
            var directory: String
        }
        // Grouped by folder while reading, so that a folder of thousands of masters
        // is one path to build and one folder to resolve.
        typealias Read = (volumes: [VolumeRecord], names: [Folder: [String]], contents: [MasterFiles.Content])
        let (volumes, names, contents): Read = try await database.read { db in
            var names: [Folder: [String]] = [:]
            var contents: [MasterFiles.Content] = []
            let rows = try Row.fetchCursor(db, sql: "SELECT volumeId, relativePath, fileSize, contentHash FROM image")
            while let row = try rows.next() {
                let path: String = row["relativePath"]
                let slash = path.lastIndex(of: "/")
                let folder = Folder(volumeID: row["volumeId"], directory: slash.map { String(path[..<$0]) } ?? "")
                names[folder, default: []].append(slash.map { String(path[path.index(after: $0)...]) } ?? path)
                contents.append(MasterFiles.Content(size: row["fileSize"], hash: row["contentHash"]))
            }
            return (try VolumeRecord.fetchAll(db), names, contents)
        }
        var mountPaths: [Int64: Set<String>] = [:]
        for volume in volumes {
            guard let id = volume.id else { continue }
            mountPaths[id] = Set([volume.mountPath]
                + mounted.lazy.filter { $0.identity == volume.identity }.map(\.mountPath))
        }
        // The file system is asked outside the read, which holds a database connection.
        var namesByFolder: [String: [String]] = [:]
        for (folder, names) in names {
            for mountPath in mountPaths[folder.volumeID] ?? [] {
                namesByFolder[(mountPath as NSString).appendingPathComponent(folder.directory), default: []]
                    .append(contentsOf: names)
            }
        }
        return MasterFiles(namesByFolder: namesByFolder, contents: contents)
    }
}
