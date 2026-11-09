/// Which of the grid's selected photos a batch adjustment (Paste, Apply
/// Preset, Auto Exposure, Reset All Adjustments, Rotate) changes: one undo
/// step over the versions the grid shows, videos left out, and photos whose
/// master must be read (Auto Exposure measures it; Rotate reads a raw's
/// camera frame) left out while their volume is offline. Stacks this build
/// cannot read are left out later, by the catalog.
public enum BatchEdit {
    /// Which run of a replaceable job is the current one: a cancelled run's
    /// clean-up only touches state it still owns.
    public struct LatestRun: Sendable {
        public private(set) var current = 0

        public init() {}

        public mutating func begin() -> Int {
            current += 1
            return current
        }

        public func owns(_ run: Int) -> Bool { run == current }
    }

    /// What measuring color alignment found for a paste or preset (R16a).
    public struct AlignmentMeasurements: Sendable {
        public private(set) var alignments: [Int64: ColorAlignment] = [:]
        /// Files whose originals could not be read, in the order measured.
        public private(set) var unreadableOriginals: [String] = []
        private var failed = Set<Int64>()

        public init() {}

        /// `alignment` nil: the original could not be measured.
        public mutating func record(_ alignment: ColorAlignment?, id: Int64, name: String) {
            if let alignment {
                alignments[id] = alignment
            } else {
                failed.insert(id)
                unreadableOriginals.append(name)
            }
        }

        /// The versions to change: all but those whose originals could not be
        /// read. A version whose stack this build can't read has no
        /// measurement either, and stays in: the catalog skips it and reports it.
        public func versionsToChange(from ids: [Int64]) -> [Int64] {
            var kept: [Int64] = []
            for id in ids where !failed.contains(id) { kept.append(id) }
            return kept
        }
    }

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
