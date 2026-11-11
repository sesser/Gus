import Foundation

/// Which files Show in Finder reveals for photos, and what it leaves out
/// (docs/features/library-ops, R14 and R16, design §5.1). The UI hands the
/// result to the Finder in one request.
public enum FinderReveal {
    /// The version whose master each target reveals: a grouped RAW+JPEG
    /// pair's RAW, whichever file its cell shows; otherwise the target's own
    /// file (with pairs ungrouped, a JPEG cell reveals the JPEG).
    public static func versionIDs(for targets: [CatalogItem]) -> [Int64] {
        targets.map { item in
            if item.representsPair, item.fileKind != .raw, let raw = item.partnerVersionID { return raw }
            return item.versionID
        }
    }

    /// Whether any target could be revealed, from what the browser already
    /// knows (the Offline badge). No disk access: this runs for every menu
    /// update. Both files of a pair are on one volume.
    public static func canReveal(_ targets: some Sequence<CatalogItem>, onlineVolumes: Set<Int64>) -> Bool {
        targets.contains { onlineVolumes.contains($0.volumeID) }
    }

    /// What one request to the Finder holds.
    public struct Outcome: Equatable, Sendable {
        /// The originals to select, in the targets' order, each once.
        public var urls: [URL] = []
        /// Photos left out because their volume is offline.
        public var offline = 0
        /// Photos left out because the file is not where the library has it.
        public var missing = 0

        public var skipped: Int { offline + missing }
    }

    /// `locations`: each photo's original, nil while its volume is offline.
    /// `exists` is asked once per file, when the command runs.
    public static func outcome(of locations: [URL?], exists: (URL) -> Bool) -> Outcome {
        var outcome = Outcome()
        var seen: Set<URL> = []
        for location in locations {
            guard let url = location else {
                outcome.offline += 1
                continue
            }
            guard exists(url) else {
                outcome.missing += 1
                continue
            }
            if seen.insert(url).inserted { outcome.urls.append(url) }
        }
        return outcome
    }
}

/// Whether a project has a folder Show in Finder can reveal (R15, R16,
/// design §5.2).
public enum ProjectFolder {
    public enum State: Equatable, Sendable {
        /// The project was not imported from one folder.
        case noFolder
        /// A volume holding its photos is not mounted.
        case volumeOffline
        /// Nothing is at the path, or it is not a folder.
        case missing
        /// The path is a volume's mount point (a card imported from its
        /// root): revealing it would open the volume, which R16 rules out.
        case mountPoint
        case available(URL)

        public var url: URL? {
            if case .available(let url) = self { url } else { nil }
        }
    }

    /// What the file system says about a path.
    public struct Probe: Equatable, Sendable {
        public var isDirectory: Bool
        public var isVolume: Bool

        public init(isDirectory: Bool, isVolume: Bool) {
            self.isDirectory = isDirectory
            self.isVolume = isVolume
        }

        /// Nil when nothing is there. One file-system call.
        public static func of(_ url: URL) -> Probe? {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isVolumeKey]) else { return nil }
            return Probe(isDirectory: values.isDirectory ?? false, isVolume: values.isVolume ?? false)
        }
    }

    /// `volumesOnline`: every volume holding the project's photos is mounted
    /// (true for a project without photos). The disk is asked only then, so
    /// another disk mounted at an offline card's path is not taken for it.
    public static func state(sourcePath: String?, volumesOnline: Bool, probe: (URL) -> Probe? = Probe.of) -> State {
        guard let sourcePath, !sourcePath.isEmpty else { return .noFolder }
        guard volumesOnline else { return .volumeOffline }
        let url = URL(fileURLWithPath: sourcePath, isDirectory: true)
        guard let found = probe(url), found.isDirectory else { return .missing }
        return found.isVolume ? .mountPoint : .available(url)
    }
}
