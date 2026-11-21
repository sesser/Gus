import CoreGraphics
import Foundation

/// One photo of a merge as the sheet lists it and the job reads it (issue #150).
public struct MergeFrame: Sendable, Hashable, Identifiable {
    /// The version the person selected (a pair's RAW when its JPEG was).
    public var versionID: Int64
    public var imageID: Int64
    public var volumeID: Int64
    public var projectID: Int64
    /// What the library calls it: a copy's name, else the file name's stem.
    public var displayName: String
    public var fileName: String
    public var relativePath: String
    public var kind: FileKind?
    public var isCopy: Bool
    /// The master's file is reachable now (its volume mounted, the file there).
    public var isOnline: Bool
    /// The master's place at its volume's last known mount point.
    public var url: URL
    /// Size in pixels after orientation, from the catalog; nil when unknown.
    public var pixelSize: CGSize?
    /// Capture date, else the file's date (the catalog's sort date).
    public var date: Date
    public var exposureTime: Double?
    public var exposureCompensation: Double?
    public var fNumber: Double?
    public var iso: Int?

    public var id: Int64 { versionID }
    public var isVideo: Bool { kind == .video }
    public var isRaw: Bool { kind == .raw }
    public var folder: URL { url.deletingLastPathComponent() }

    public init(versionID: Int64, imageID: Int64, volumeID: Int64, projectID: Int64, displayName: String,
                fileName: String, relativePath: String, kind: FileKind?, isCopy: Bool, isOnline: Bool, url: URL,
                pixelSize: CGSize?, date: Date, exposureTime: Double? = nil, exposureCompensation: Double? = nil,
                fNumber: Double? = nil, iso: Int? = nil) {
        self.versionID = versionID
        self.imageID = imageID
        self.volumeID = volumeID
        self.projectID = projectID
        self.displayName = displayName
        self.fileName = fileName
        self.relativePath = relativePath
        self.kind = kind
        self.isCopy = isCopy
        self.isOnline = isOnline
        self.url = url
        self.pixelSize = pixelSize
        self.date = date
        self.exposureTime = exposureTime
        self.exposureCompensation = exposureCompensation
        self.fNumber = fNumber
        self.iso = iso
    }

    /// A frame from the catalog's record of a version. `displayName` is the
    /// copy's name for a copy; `isOnline` whether the master can be reached.
    public init(details: VersionDetails, displayName: String? = nil, isOnline: Bool) {
        let image = details.image
        let size: CGSize? = {
            guard let width = image.pixelWidth, let height = image.pixelHeight, width > 0, height > 0 else { return nil }
            return ImageMetadata.swapsDimensions(image.orientation)
                ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        }()
        self.init(versionID: details.version.id ?? 0, imageID: image.id ?? 0, volumeID: image.volumeId,
                  projectID: image.projectId,
                  displayName: displayName ?? (image.fileName as NSString).deletingPathExtension,
                  fileName: image.fileName, relativePath: image.relativePath,
                  kind: FileKind(pathExtension: (image.fileName as NSString).pathExtension),
                  isCopy: !details.version.isDefault, isOnline: isOnline,
                  url: details.volume.url(forRelativePath: image.relativePath), pixelSize: size,
                  date: image.captureDate ?? image.sortDate, exposureTime: image.exposureTime,
                  exposureCompensation: image.exposureCompensation, fNumber: image.fNumber, iso: image.iso)
    }

    /// The exposure value the file records (time × ISO / f-number²), nil without a time.
    public var metadataExposure: Double? {
        MergeExposure.metadataExposure(time: exposureTime, fNumber: fNumber, iso: iso)
    }
}

/// Why a merge can't run, shown in the sheet with the frames it is about
/// (design §6). Nothing is written while one stands.
public enum MergeRefusal: Sendable, Hashable {
    /// Fewer than two frames once a RAW+JPEG pair counts as one.
    case tooFew
    /// More than `MergeLimits.maxFrames`.
    case tooMany(limit: Int)
    /// A video among the targets: its name.
    case video(name: String)
    /// A copy beside its own original (or two copies of one photo): the
    /// copy's name and the other's.
    case sameFile(copy: String, original: String)
    /// Raws and non-raws together.
    case mixedKinds
    /// A frame of another size than the reference: its name and the reference's.
    case differentSize(name: String, reference: String)
    /// A frame with more pixels than `MergeLimits.maximumPixels`: its name
    /// and the limit in megapixels (security review M1).
    case tooLarge(name: String, megapixels: Int)
    /// The frames together would take more memory than a merge may use here.
    case tooMuchMemory
    /// Offline frames: the first one's name and how many there are.
    case offline(name: String, count: Int)
    /// A master that can't be read: its name.
    case unreadable(name: String)
    /// The reference's folder can't be written to: the reference's name and the folder's.
    case unwritableFolder(reference: String, folder: String)
}

/// The series the person selected, as the sheet shows it: frames in
/// capture order, the reference, the first refusal that applies with the
/// frames it flags, and the same-exposure note (design §5, §6.1).
public struct MergeSelection: Sendable, Hashable {
    public var frames: [MergeFrame]
    /// Index into `frames` of the frame that names the result and the others
    /// are lined up to (R3, A9).
    public var reference: Int
    public var refusal: MergeRefusal?
    /// The frames `refusal` is about.
    public var flagged: Set<Int64>
    /// Every frame has the same shutter, aperture, ISO and compensation, none missing.
    public var sameExposure: Bool
    /// What the frames' pixels may take (`MergeLimits.frameMemoryBudget`),
    /// kept so a change of reference decides the refusals the same way.
    public var memoryBudget: Int

    public var referenceFrame: MergeFrame { frames[reference] }

    /// The frame chosen by default (R3): `MergeSelection.reference(in:)`.
    public var defaultReference: Int { Self.reference(in: frames) }

    /// The version ids to read for `items`: a RAW+JPEG pair once, as its RAW,
    /// whichever half was selected (R8). Videos are kept, for the refusal.
    public static func versionIDs(for items: [CatalogItem]) -> [Int64] {
        var seen = Set<Int64>()
        var ids: [Int64] = []
        for item in items {
            var id = item.versionID
            if let partner = item.partnerVersionID, item.fileKind != .raw, item.partnerKind == .raw {
                id = partner
            }
            if seen.insert(id).inserted { ids.append(id) }
        }
        return ids
    }

    /// The selection for `frames` (from `versionIDs`, in any order).
    /// `memoryBudget`: what the frames' pixels may take (`MergeLimits.frameMemoryBudget`).
    public init(frames unordered: [MergeFrame], memoryBudget: Int = MergeLimits.frameMemoryBudget) {
        let frames = unordered.sorted {
            $0.date != $1.date ? $0.date < $1.date
                : $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
        self.frames = frames
        self.memoryBudget = memoryBudget
        reference = Self.reference(in: frames)
        sameExposure = Self.sameExposure(frames)
        (refusal, flagged) = Self.refusal(frames, reference: reference, memoryBudget: memoryBudget)
    }

    /// The same frames with `versionID`'s frame as the reference (R3; design
    /// §5.5): any listed frame, a flagged one or a video included (A13). The
    /// refusals are decided again; of those known from the catalog only the
    /// different-size one names and flags frames by the reference (§6.4).
    /// Nil when `versionID` is not one of the frames.
    public func choosingReference(_ versionID: Int64) -> MergeSelection? {
        guard let index = frames.firstIndex(where: { $0.versionID == versionID }) else { return nil }
        var next = self
        next.reference = index
        (next.refusal, next.flagged) = Self.refusal(frames, reference: index, memoryBudget: memoryBudget)
        return next
    }

    /// The frame at 0 EV compensation when the metadata says which (some
    /// frames at 0, others not), the earliest of them; otherwise the earliest
    /// frame (R3). `frames` are in capture order.
    public static func reference(in frames: [MergeFrame]) -> Int {
        let photos = frames.indices.filter { !frames[$0].isVideo }
        let atZero = photos.filter { abs(frames[$0].exposureCompensation ?? .nan) < 0.05 }
        let known = photos.filter { frames[$0].exposureCompensation != nil }
        if let first = atZero.first, atZero.count < known.count || known.count < photos.count {
            return first
        }
        return photos.first ?? 0
    }

    static func sameExposure(_ frames: [MergeFrame]) -> Bool {
        guard frames.count >= 2, let first = frames.first else { return false }
        func key(_ frame: MergeFrame) -> [Double]? {
            guard let time = frame.exposureTime, let number = frame.fNumber, let iso = frame.iso,
                  let compensation = frame.exposureCompensation else { return nil }
            let values = [time, number, Double(iso), compensation]
            // Values that aren't finite say nothing (security review L3).
            return values.allSatisfy(\.isFinite) ? values : nil
        }
        guard let reference = key(first) else { return false }
        return frames.allSatisfy { frame in
            guard let values = key(frame) else { return false }
            return zip(values, reference).allSatisfy { abs($0 - $1) <= 1e-6 * max(1, abs($1)) }
        }
    }

    /// The first refusal of design §6.1 that applies, and its flagged frames.
    static func refusal(_ frames: [MergeFrame], reference: Int, memoryBudget: Int) -> (MergeRefusal?, Set<Int64>) {
        if frames.count < MergeLimits.minFrames {
            return (.tooFew, Set(frames.map(\.versionID)))
        }
        if frames.count > MergeLimits.maxFrames {
            return (.tooMany(limit: MergeLimits.maxFrames), Set(frames.dropFirst(MergeLimits.maxFrames).map(\.versionID)))
        }
        let videos = frames.filter(\.isVideo)
        if let first = videos.first {
            return (.video(name: first.displayName), Set(videos.map(\.versionID)))
        }
        let byImage = Dictionary(grouping: frames, by: \.imageID)
        for frame in frames {
            guard let group = byImage[frame.imageID], group.count > 1 else { continue }
            let original = group.first { !$0.isCopy } ?? group[0]
            let copies = group.filter { $0.versionID != original.versionID }
            guard let copy = copies.first else { continue }
            return (.sameFile(copy: copy.displayName, original: original.displayName), Set(copies.map(\.versionID)))
        }
        let raws = frames.filter(\.isRaw), others = frames.filter { !$0.isRaw }
        if !raws.isEmpty, !others.isEmpty {
            let flagged = raws.count >= others.count ? others : raws
            return (.mixedKinds, Set(flagged.map(\.versionID)))
        }
        // Measured from the chosen reference: the first frame (capture order)
        // of another size is named, and every one of another size flagged
        // (design §6.1 case 6, revision 2026-11-21).
        let ref = frames[reference]
        if let size = ref.pixelSize {
            let others = frames.filter { $0.pixelSize != nil && $0.pixelSize != size }
            if let first = others.first {
                return (.differentSize(name: first.displayName, reference: ref.displayName), Set(others.map(\.versionID)))
            }
        }
        // Sizes as the catalog has them (the job checks the decoders' too).
        func pixels(_ frame: MergeFrame) -> Double {
            frame.pixelSize.map { Double($0.width) * Double($0.height) } ?? 0
        }
        let tooLarge = frames.filter { pixels($0) > Double(MergeLimits.maximumPixels) }
        if let first = tooLarge.first {
            return (.tooLarge(name: first.displayName, megapixels: MergeLimits.maximumPixels / 1_000_000),
                    Set(tooLarge.map(\.versionID)))
        }
        let total = frames.reduce(0.0) { $0 + pixels($1) } * 8
        if total > Double(memoryBudget) {
            return (.tooMuchMemory, Set(frames.map(\.versionID)))
        }
        let offline = frames.filter { !$0.isOnline }
        if let first = offline.first {
            return (.offline(name: first.displayName, count: offline.count), Set(offline.map(\.versionID)))
        }
        return (nil, [])
    }

    /// The file name a merge of this selection gets now in the reference's
    /// folder (R3, R4): the reference's stem, `_HDR` and the format's
    /// extension, numbered past any file in the folder (`files`, its names)
    /// or library master there with that stem (`MergeNaming`).
    public func resultName(format: MergeFormat, masters: MasterFiles.Names, files: [String]) -> String {
        MergeNaming.name(stem: (referenceFrame.fileName as NSString).deletingPathExtension, format: format,
                         masters: masters, files: files)
    }
}

/// The merged file's name (R3, R4).
///
/// Numbered (`_HDR-2`, `-3`…, export's numbering) whenever any file or library
/// master in the folder has the same **stem**, whatever its extension, not
/// only the same name: two masters of one stem would share a sidecar
/// (`IMG_1234_HDR.xmp`), and a TIFF and a DNG merged from one bracket would
/// read and write each other's values (code review C3).
public enum MergeNaming {
    public static let suffix = "_HDR"

    /// Whether a master's file name and relative path, as the catalog has
    /// them, name one file in a folder of the volume: the name is the path's
    /// last part, and no part is empty, `.` or `..`, or holds a NUL
    /// (security review L8).
    public static func isPlainPlace(fileName: String, relativePath: String) -> Bool {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relativePath.hasPrefix("/"), let last = parts.last, last == fileName else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }
    }

    /// File names longer than this many bytes (UTF-8) are not allowed by APFS
    /// and HFS+.
    static let maximumNameBytes = 255

    public static func name(stem: String, format: MergeFormat, masters: MasterFiles.Names, files: [String]) -> String {
        // Room for the suffix, a number and the extension: a reference whose
        // own name nearly fills the file system's limit gives a shorter stem
        // (security review L1).
        let reserve = (suffix + "-999." + format.fileExtension).utf8.count
        var stem = stem
        while stem.utf8.count + reserve > maximumNameBytes, !stem.isEmpty { stem.removeLast() }
        let taken = Set(files.map { MasterFiles.folded(($0 as NSString).deletingPathExtension) })
        func isFree(_ candidate: String) -> Bool {
            !taken.contains(MasterFiles.folded(candidate)) && !masters.containsStem(candidate)
        }
        var candidate = stem + suffix
        var number = 2
        while !isFree(candidate) {
            candidate = stem + suffix + "-\(number)"
            number += 1
        }
        return candidate + "." + format.fileExtension
    }
}

/// Whether the merged photo takes the selection when it lands (design §8.3):
/// only when the person has left things as they were, so a merge that ends
/// while they work elsewhere never moves what they are looking at.
public enum MergeLanding {
    /// `started`: the targets' versions when the merge started. `now`: the
    /// targets now. `showsGrid`: the grid is on screen (in the loupe the
    /// loupe stays on its photo). `shown`: the source on screen holds the
    /// merged photo and no filter hides it.
    public static func selects(started: [Int64], now: [Int64], showsGrid: Bool, shown: Bool) -> Bool {
        showsGrid && shown && Set(started) == Set(now) && !started.isEmpty
    }
}
