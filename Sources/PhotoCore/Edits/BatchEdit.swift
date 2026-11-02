/// Which of the grid's selected photos a batch adjustment (Paste, Apply
/// Preset, Auto Exposure, Reset All Adjustments, Rotate) changes: one undo
/// step over the versions the grid shows, videos left out, and photos whose
/// master must be read (Auto Exposure measures it; Rotate reads a raw's
/// camera frame) left out while their volume is offline. Stacks this build
/// cannot read are left out later, by the catalog.
public enum BatchEdit {
    public struct Candidate: Hashable, Sendable {
        public var versionID: Int64
        public var isVideo: Bool
        /// The change reads the master file.
        public var needsMaster: Bool
        public var isOnline: Bool

        public init(versionID: Int64, isVideo: Bool, needsMaster: Bool = false, isOnline: Bool = true) {
            self.versionID = versionID
            self.isVideo = isVideo
            self.needsMaster = needsMaster
            self.isOnline = isOnline
        }
    }

    public struct Selection: Hashable, Sendable {
        public var versionIDs: [Int64] = []
        public var skippedVideos = 0
        public var skippedOffline = 0

        public var skipped: Int { skippedVideos + skippedOffline }
    }

    /// The versions to change, in order, and how many were left out and why.
    public static func select(_ candidates: [Candidate]) -> Selection {
        var selection = Selection()
        var seen = Set<Int64>()
        for candidate in candidates where seen.insert(candidate.versionID).inserted {
            if candidate.isVideo {
                selection.skippedVideos += 1
            } else if candidate.needsMaster && !candidate.isOnline {
                selection.skippedOffline += 1
            } else {
                selection.versionIDs.append(candidate.versionID)
            }
        }
        return selection
    }
}
