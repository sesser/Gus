import Foundation

/// Items dropped on the library (or chosen in an open panel), sorted into the
/// folders to import and the rest.
///
/// Each folder becomes its own project, named after it, exactly as a single
/// Import Folder… does: its subfolders are scanned with it, and a project of
/// the same name already in the library is left alone (the import makes a new
/// one holding only photos the library does not have yet). Files, packages
/// (bundles, other apps' libraries) and missing paths are ignored. Finder
/// aliases and symbolic links count as the folder they point to. A folder that
/// is the same as, or inside, another dropped folder is dropped from the list,
/// since that folder's import already covers it.
public struct DroppedFolders: Sendable, Equatable {
    /// In drop order.
    public var folders: [URL]
    /// Dropped items that are not folders.
    public var ignored: [URL]

    public init(folders: [URL], ignored: [URL]) {
        self.folders = folders
        self.ignored = ignored
    }

    public init(_ urls: [URL]) {
        var folders: [URL] = []
        var ignored: [URL] = []
        for url in urls {
            guard url.isFileURL, let folder = Self.folder(at: url) else {
                ignored.append(url)
                continue
            }
            folders.append(folder)
        }
        self.init(folders: Self.outermost(folders), ignored: ignored)
    }

    public var isEmpty: Bool { folders.isEmpty }

    /// The folder an item stands for, if it is one, packages excluded. An alias
    /// gives way to its target; a symbolic link stays, so its name names the
    /// project (the scanner follows it).
    static func folder(at url: URL) -> URL? {
        // Symbolic links count as alias files too.
        let kind = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
        let isAlias = kind?.isAliasFile == true && kind?.isSymbolicLink != true
        let target = isAlias ? (try? URL(resolvingAliasFileAt: url)) ?? url : url
        let values = try? target.resolvingSymlinksInPath()
            .resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        guard values?.isDirectory == true, values?.isPackage != true else { return nil }
        return target
    }

    /// Folders not equal to or inside an earlier or later one, in their order.
    static func outermost(_ folders: [URL]) -> [URL] {
        let paths = folders.map(comparablePath)
        return folders.indices.compactMap { index in
            let path = paths[index]
            let covered = paths.indices.contains { other in
                other != index && (isInside(path, paths[other]) || (paths[other] == path && other < index))
            }
            return covered ? nil : folders[index]
        }
    }

    /// A folder's path with links resolved and a trailing slash, so prefixes
    /// only match whole components.
    static func comparablePath(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasSuffix("/") ? path : path + "/"
    }

    static func isInside(_ path: String, _ folder: String) -> Bool {
        path != folder && path.hasPrefix(folder)
    }
}

/// Folders waiting to be imported one after another, and the running totals of
/// the batch. Folders dropped while a batch runs join its end, unless the
/// batch already covers them.
public struct FolderImportQueue: Sendable {
    public private(set) var pending: [URL] = []
    /// The folder being imported.
    public private(set) var current: URL?
    /// Folders handed out by `next()` in this batch, the current one included.
    public private(set) var started = 0
    /// Folders in this batch: started plus pending.
    public var count: Int { started + pending.count }
    public private(set) var totals = Totals()

    public struct Totals: Sendable, Equatable {
        public var folders = 0
        public var imported = 0
        /// Duplicates and files already in the catalog.
        public var alreadyInLibrary = 0
        /// Failures and catalogued paths whose content changed on disk.
        public var failed = 0
        /// Projects the batch created, in import order.
        public var projectIDs: [Int64] = []
    }

    public init() {}

    public var isRunning: Bool { current != nil || !pending.isEmpty }

    /// Adds folders not already pending, running, or inside one of those.
    /// Returns the folders added.
    @discardableResult
    public mutating func enqueue(_ folders: [URL]) -> [URL] {
        let queued = ([current].compactMap { $0 } + pending).map(DroppedFolders.comparablePath)
        let added = DroppedFolders.outermost(folders).filter { folder in
            let path = DroppedFolders.comparablePath(folder)
            return !queued.contains { $0 == path || DroppedFolders.isInside(path, $0) }
        }
        pending += added
        return added
    }

    /// Starts the next folder; nil when the batch is done. A new batch starts
    /// with fresh totals once the previous one has been finished.
    public mutating func next() -> URL? {
        current = pending.isEmpty ? nil : pending.removeFirst()
        if current != nil { started += 1 }
        return current
    }

    /// Adds a finished folder's import to the totals.
    public mutating func record(_ summary: ImportSummary) {
        let progress = summary.progress
        totals.folders += 1
        totals.imported += progress.imported
        totals.alreadyInLibrary += progress.duplicates + progress.alreadyInCatalog
        totals.failed += progress.failed + progress.changedOnDisk
        if let id = summary.project?.id { totals.projectIDs.append(id) }
    }

    /// Clears the batch: what is pending, the current folder and the totals.
    /// Returns the totals of the batch.
    @discardableResult
    public mutating func finish() -> Totals {
        let finished = totals
        self = FolderImportQueue()
        return finished
    }
}
