import Foundation

/// A photo listed by a server, as the import window and the importer use it.
/// Provider-neutral; `ImmichClient` fills it from Immich's listing.
public struct RemoteAsset: Hashable, Sendable, Identifiable {
    /// The server's id for the asset (Immich: a UUID).
    public var id: String
    public var fileName: String
    /// Base64 SHA-1 of the original's bytes, as the server reported it (R13).
    public var checksum: String
    /// The original's size as the server reported it, if it did.
    public var byteCount: Int64?
    public var metadata: ImageMetadata
    public var modifiedAt: Date
    /// Edited on the server (R21): the original is still what is imported.
    public var isEdited: Bool
    /// A Live Photo's still: its video is never downloaded (R14).
    public var hasLiveVideo: Bool
    /// It belongs to an external library (the server gave a `libraryId`): its
    /// checksum may be of its path, so it is verified by size only (R13,
    /// RI-E2).
    public var isExternalLibrary: Bool
    /// The server's description, imported when the library has none (R17).
    public var serverDescription: String?
    /// The server's star rating, 1 to 5, or nil (R17).
    public var serverRating: Int?

    public init(id: String, fileName: String, checksum: String, byteCount: Int64?, metadata: ImageMetadata,
                modifiedAt: Date, isEdited: Bool = false, hasLiveVideo: Bool = false, isExternalLibrary: Bool = false,
                serverDescription: String? = nil, serverRating: Int? = nil) {
        self.id = id
        self.fileName = fileName
        self.checksum = checksum
        self.byteCount = byteCount
        self.metadata = metadata
        self.modifiedAt = modifiedAt
        self.isEdited = isEdited
        self.hasLiveVideo = hasLiveVideo
        self.isExternalLibrary = isExternalLibrary
        self.serverDescription = serverDescription
        self.serverRating = serverRating
    }

    /// A server's file name the app accepts (security review F1): not empty,
    /// not "." or "..", and no `/`, `\` or control character (Unicode
    /// category Cc, NUL included). Format characters (Cf: the zero-width
    /// joiner of an emoji sequence, the ZWNJ some scripts need, direction
    /// marks) are accepted; the template fallback and the containment check
    /// keep the path safe whatever the name (code review C14).
    public static func isPlainFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 1024 else { return false }
        return !name.unicodeScalars.contains { $0 == "/" || $0 == "\\" || $0.properties.generalCategory == .control }
    }

    /// An id the server gave that the app may put in a request's path (an
    /// asset's or an album's; security review N1): 1 to 64 ASCII letters,
    /// digits and hyphens, nothing else. No other script, no line separator
    /// (U+2028, U+2029) and no control character can pass, so no id reaches
    /// a URL's path unencoded.
    public static func isServerID(_ id: String) -> Bool {
        let scalars = id.unicodeScalars
        guard (1...64).contains(scalars.count) else { return false }
        return scalars.allSatisfy { scalar in
            switch scalar {
            case "0"..."9", "a"..."z", "A"..."Z", "-": true
            default: false
            }
        }
    }

    /// The largest original a server may report or send: 64 GiB. A size
    /// outside 0...this is not believed (code review C3, C4).
    public static let maximumSize: Int64 = 64 << 30

    /// A size the server reported, if it is one: nil when negative or larger
    /// than `maximumSize`.
    public static func saneSize(_ size: Int64?) -> Int64? {
        guard let size, size >= 0, size <= maximumSize else { return nil }
        return size
    }

    /// The URL that stands for the asset in the import grid, whose shots are
    /// keyed by URL. Never fetched: the scheme is the app's own, and the
    /// importer finds the asset by its id.
    public var gridURL: URL { RemoteAssetURL.make(assetID: id, fileName: fileName) }

    /// The asset as one shot of the import grid (pairs are never grouped
    /// for a server, design §4.5). `isDuplicate` marks a linked photo.
    public func shot(linked: Bool) -> SourceShot {
        let kind = FileKind(pathExtension: (fileName as NSString).pathExtension) ?? .jpeg
        var file = SourceFile(url: gridURL, size: byteCount ?? 0, modifiedAt: modifiedAt, kind: kind, metadata: metadata)
        file.isDuplicate = linked
        return SourceShot(files: [file])
    }
}

/// `remote-asset:/<id>/<file name>`: the grid's key for a remote asset.
public enum RemoteAssetURL {
    public static let scheme = "remote-asset"

    public static func make(assetID: String, fileName: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.path = "/" + assetID + "/" + (fileName.isEmpty ? "photo" : fileName)
        return components.url ?? URL(string: "\(scheme):/\(assetID)/photo")!
    }

    public static func assetID(of url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.first.map(String.init)
    }

    public static func isRemote(_ url: URL) -> Bool { url.scheme == scheme }
}

/// Which photos a server lists: everything (All Photos) or one album, within
/// an optional capture date range (R10, R10b).
public struct RemoteScope: Hashable, Sendable {
    public var albumID: String?
    public var dates: CaptureDateRange?

    public init(albumID: String? = nil, dates: CaptureDateRange? = nil) {
        self.albumID = albumID
        self.dates = dates
    }
}

/// Whole days, inclusive, in the photo's own local time (design §4.3). Either
/// end may be open.
public struct CaptureDateRange: Hashable, Sendable {
    /// Calendar days as (year, month, day).
    public var from: DateComponents?
    public var through: DateComponents?

    public init(from: DateComponents?, through: DateComponents?) {
        self.from = from
        self.through = through
    }

    public var isEmpty: Bool { from == nil && through == nil }

    /// The start is after the end (Apply is dimmed).
    public var isReversed: Bool {
        guard let start = Self.utc(from), let end = Self.utc(through) else { return false }
        return start > end
    }

    /// Bounds on Immich's `takenAt`, which is UTC: a day in the photo's own
    /// time is matched as that wall clock read as UTC, start inclusive and
    /// the day after the end exclusive.
    public var bounds: (start: Date?, endExclusive: Date?) {
        (Self.utc(from), Self.utc(through).map { $0.addingTimeInterval(86_400) })
    }

    public static func utc(_ day: DateComponents?) -> Date? {
        guard let day, let year = day.year, let month = day.month, let date = day.day else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: date))
    }
}

/// An album on a server, with the count the server gives (R10: it may
/// include videos, which are never listed).
public struct RemoteAlbum: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var assetCount: Int

    public init(id: String, name: String, assetCount: Int) {
        self.id = id
        self.name = name
        self.assetCount = assetCount
    }

    /// By name, case-insensitive and localized (design §4.2).
    public static func sorted(_ albums: [RemoteAlbum]) -> [RemoteAlbum] {
        albums.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }
}

/// One page of a listing: the photos and the cursor of the next page (nil on
/// the last).
public struct RemotePage: Hashable, Sendable {
    public var assets: [RemoteAsset]
    public var nextCursor: String?

    public init(assets: [RemoteAsset], nextCursor: String?) {
        self.assets = assets
        self.nextCursor = nextCursor
    }
}
