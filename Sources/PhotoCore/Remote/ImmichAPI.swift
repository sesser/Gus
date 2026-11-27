import Foundation

/// The Immich requests the app makes, and nothing else (issue #271 R7, design
/// §3; the shapes are recorded in docs/features/immich-import/status.md, "API
/// verification", and docs/features/publishing-engine/status.md, "Immich
/// verification"). Importing only reads: its one POST is the metadata search,
/// which changes nothing on the server. Publishing (issue #28, R9) adds four
/// writes and no other: upload an asset, create an album, add assets to an
/// album, create a stack. Nothing updates or deletes anything; adding another
/// write needs the owner's approval.
public enum ImmichEndpoint: Hashable, Sendable {
    /// `GET /server/version`, no key: is this Immich, and is it new enough.
    case serverVersion
    /// `GET /api-keys/me`: is the key accepted, and its permissions.
    case apiKeyMe
    /// `GET /users/me` (`user.read`): the account's id (R3, R9).
    case userMe
    /// `GET /albums?isOwned=true` (`album.read`).
    case ownAlbums
    /// `POST /search/metadata` (`asset.read`), the JSON body.
    case search(Data)
    /// `GET /assets/{id}/thumbnail?size=thumbnail&edited=false` (`asset.view`).
    case thumbnail(assetID: String)
    /// `GET /assets/{id}/original?edited=false` (`asset.download`): the
    /// original file, never the server's edit (R12, R21).
    case original(assetID: String)
    /// `GET /assets/{id}` (`asset.read`): one asset with its owner, type,
    /// visibility, trash, path, size and stack (publishing R11, R13, R14, R19).
    case asset(id: String)
    /// `GET /albums?isOwned=true&assetId=…` (`album.read`): the account's
    /// albums holding the asset, to find an album whose create lost its
    /// answer (publishing R22).
    case ownAlbumsHolding(assetID: String)
    /// Publishing's writes (R9). `POST /assets` (`asset.upload`): the rendered
    /// file as multipart, streamed from disk (`RemoteHTTPSession.upload`).
    case upload
    /// `POST /albums` (`album.create`), the JSON body.
    case createAlbum(Data)
    /// `PUT /albums/{id}/assets` (`albumAsset.create`), the JSON body.
    case addToAlbum(albumID: String, Data)
    /// `POST /stacks` (`stack.create`), the JSON body. Immich replaces the
    /// stacks whose primary is named (status.md, item 10).
    case createStack(Data)

    public var method: String {
        switch self {
        case .search, .upload, .createAlbum, .createStack: "POST"
        case .addToAlbum: "PUT"
        default: "GET"
        }
    }

    /// One of publishing's four writes (R9).
    public var writes: Bool {
        switch self {
        case .upload, .createAlbum, .addToAlbum, .createStack: true
        default: false
        }
    }

    /// Relative to the API root (`<address>/api`).
    public var path: String {
        switch self {
        case .serverVersion: "/server/version"
        case .apiKeyMe: "/api-keys/me"
        case .userMe: "/users/me"
        case .ownAlbums: "/albums"
        case .search: "/search/metadata"
        case .thumbnail(let id): "/assets/\(id)/thumbnail"
        case .original(let id): "/assets/\(id)/original"
        case .asset(let id): "/assets/\(id)"
        case .ownAlbumsHolding: "/albums"
        case .upload: "/assets"
        case .createAlbum: "/albums"
        case .addToAlbum(let id, _): "/albums/\(id)/assets"
        case .createStack: "/stacks"
        }
    }

    public var queryItems: [URLQueryItem] {
        switch self {
        case .ownAlbums: [URLQueryItem(name: "isOwned", value: "true")]
        case .thumbnail: [URLQueryItem(name: "size", value: "thumbnail"), URLQueryItem(name: "edited", value: "false")]
        case .original: [URLQueryItem(name: "edited", value: "false")]
        case .ownAlbumsHolding(let id): [URLQueryItem(name: "isOwned", value: "true"), URLQueryItem(name: "assetId", value: id)]
        default: []
        }
    }

    /// The most bytes an answer may have (code review C4). `/server/version`
    /// is read before the address is known to be Immich, so it is the
    /// smallest. Originals are downloads with their own limit.
    public var maximumResponseSize: Int {
        switch self {
        case .serverVersion: 64 << 10
        case .apiKeyMe, .userMe: 1 << 20
        case .ownAlbums: 16 << 20
        case .search: 32 << 20
        case .thumbnail: 16 << 20
        case .original: 64 << 10
        case .asset: 1 << 20
        case .ownAlbumsHolding: 16 << 20
        case .upload: 64 << 10
        case .createAlbum, .addToAlbum, .createStack: 16 << 20
        }
    }

    /// `/server/version` is public; everything else needs the key.
    public var sendsKey: Bool { self != .serverVersion }

    public var body: Data? {
        switch self {
        case .search(let body), .createAlbum(let body), .addToAlbum(_, let body), .createStack(let body): body
        default: nil
        }
    }

    /// The permission a 403 on this request means is missing.
    public var permission: String? {
        switch self {
        case .serverVersion, .apiKeyMe: nil
        case .userMe: "user.read"
        case .ownAlbums: "album.read"
        case .search: "asset.read"
        case .thumbnail: "asset.view"
        case .original: "asset.download"
        case .asset: "asset.read"
        case .ownAlbumsHolding: "album.read"
        case .upload: "asset.upload"
        case .createAlbum: "album.create"
        case .addToAlbum: "albumAsset.create"
        case .createStack: "stack.create"
        }
    }
}

/// The only method and path pairs a connection sends (issue #271 R7, AC5;
/// issue #28 R9, AC6). The HTTP layer checks every request against it before
/// anything is sent, so a request built any other way fails with
/// `RemoteError.notAllowed`. The reads, then publishing's four writes; no
/// request that updates or deletes anything is on it.
public enum RemoteRequestAllowlist {
    static let entries: [(method: String, pattern: String)] = [
        ("GET", #"^/server/version$"#),
        ("GET", #"^/api-keys/me$"#),
        ("GET", #"^/users/me$"#),
        ("GET", #"^/albums$"#),
        ("POST", #"^/search/metadata$"#),
        ("GET", #"^/assets/[0-9A-Za-z-]{1,64}/thumbnail$"#),
        ("GET", #"^/assets/[0-9A-Za-z-]{1,64}/original$"#),
        ("GET", #"^/assets/[0-9A-Za-z-]{1,64}$"#),
        // Publishing's writes (R9): upload, create album, add to album, create stack.
        ("POST", #"^/assets$"#),
        ("POST", #"^/albums$"#),
        ("PUT", #"^/albums/[0-9A-Za-z-]{1,64}/assets$"#),
        ("POST", #"^/stacks$"#),
    ]

    /// The writes on the list, as (method, path pattern): exactly the four
    /// publishing may send (AC6).
    public static var writes: [(method: String, pattern: String)] {
        entries.filter { $0.method != "GET" && $0.pattern != #"^/search/metadata$"# }
    }

    /// `path` is relative to the API root. Matched by ICU itself
    /// (`NSRegularExpression`), whose `$` also matches before a final line
    /// terminator (a newline, U+2028, U+2029), so the match must cover the
    /// whole path (security review N1). `String.range(of:options:)` agrees
    /// on some macOS releases and not others; this answers alike on all.
    public static func permits(method: String, path: String) -> Bool {
        let whole = NSRange(path.startIndex..<path.endIndex, in: path)
        return entries.contains { entry in
            guard entry.method == method, let expression = try? NSRegularExpression(pattern: entry.pattern),
                  let match = expression.firstMatch(in: path, range: whole) else { return false }
            return match.range == whole
        }
    }
}

/// Immich's version (`/server/version`).
public struct ImmichVersion: Hashable, Sendable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// 3.2.0: the release with the `filter` and `cursor` search (Q1).
    public static let minimum = ImmichVersion(3, 2, 0)
}

/// Decoded Immich responses: only the fields the app reads.
enum ImmichDTO {
    struct ServerVersion: Decodable {
        var major: Int
        var minor: Int
        var patch: Int
    }

    struct APIKey: Decodable {
        var permissions: [String]
    }

    struct User: Decodable {
        var id: String
    }

    struct Album: Decodable {
        var id: String
        var albumName: String
        var assetCount: Int
    }

    struct SearchResponse: Decodable {
        var assets: Page
    }

    struct Page: Decodable {
        var items: [Asset]
        var nextCursor: String?
    }

    struct Asset: Decodable {
        var id: String
        var type: String
        var originalFileName: String
        var checksum: String
        var fileCreatedAt: String
        var fileModifiedAt: String?
        var localDateTime: String?
        var ownerId: String?
        var isTrashed: Bool?
        var isEdited: Bool?
        var visibility: String?
        var livePhotoVideoId: String?
        /// Set for an asset of an external library, whose checksum may be of
        /// its path (R13, RI-E2).
        var libraryId: String?
        var exifInfo: Exif?
    }

    struct Exif: Decodable {
        var description: String?
        var rating: Int?
        var fileSizeInByte: Int64?
        var make: String?
        var model: String?
        var lensModel: String?
        var exifImageWidth: Int?
        var exifImageHeight: Int?
    }

    /// The search body (status.md, "API verification"): images in the
    /// timeline, not trashed, newest capture first, in an album and a date
    /// range when asked.
    static func searchBody(scope: RemoteScope, cursor: String?, size: Int) throws -> Data {
        var filter: [String: Any] = [
            "type": ["eq": "IMAGE"],
            "visibility": ["eq": "timeline"],
            "trashedAt": ["eq": NSNull()],
        ]
        if let album = scope.albumID { filter["albumIds"] = ["any": [album]] }
        if let dates = scope.dates, !dates.isEmpty {
            var taken: [String: String] = [:]
            let bounds = dates.bounds
            if let start = bounds.start { taken["gte"] = isoString(start) }
            if let end = bounds.endExclusive { taken["lt"] = isoString(end) }
            filter["takenAt"] = taken
        }
        var body: [String: Any] = [
            "filter": filter,
            "orderBy": ["field": "fileCreatedAt", "direction": "desc"],
            "size": size,
            "withExif": true,
        ]
        if let cursor { body["cursor"] = cursor }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    static func isoString(_ date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
    }

    /// "2024-05-01T10:00:00.000Z", with or without the fraction.
    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

extension ImmichDTO.Asset {
    /// The asset as the app lists it, or nil when it must not be listed
    /// (R9: images only; trashed, hidden, archived and locked never; only the
    /// account's own, so never a partner's or another contributor's, nor one
    /// that names no owner; a format the library does not catalog, as a card's
    /// scan leaves it out).
    func remoteAsset(ownerID: String) -> RemoteAsset? {
        guard type == "IMAGE", isTrashed != true, visibility == nil || visibility == "timeline" else { return nil }
        guard let owner = ownerId, owner == ownerID else { return nil }
        // A name that could name a place, not just a file, is not listed
        // (security review F1).
        guard RemoteAsset.isPlainFileName(originalFileName) else { return nil }
        // Its id goes into the thumbnail's and the original's paths (security review N1).
        guard RemoteAsset.isServerID(id) else { return nil }
        guard let kind = FileKind(pathExtension: (originalFileName as NSString).pathExtension), kind != .video else {
            return nil
        }
        let created = ImmichDTO.date(fileCreatedAt)
        let local = ImmichDTO.date(localDateTime)
        var metadata = ImageMetadata()
        metadata.captureDate = created
        if let created, let local { metadata.captureOffsetSeconds = Int((local.timeIntervalSince(created)).rounded()) }
        metadata.cameraMake = exifInfo?.make
        metadata.cameraModel = exifInfo?.model
        metadata.lensModel = exifInfo?.lensModel
        metadata.pixelWidth = exifInfo?.exifImageWidth
        metadata.pixelHeight = exifInfo?.exifImageHeight
        let rating = exifInfo?.rating.flatMap { (1...5).contains($0) ? $0 : nil }
        let description = exifInfo?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteAsset(id: id, fileName: originalFileName, checksum: checksum,
                           byteCount: RemoteAsset.saneSize(exifInfo?.fileSizeInByte),
                           metadata: metadata, modifiedAt: ImmichDTO.date(fileModifiedAt) ?? created ?? Date(timeIntervalSince1970: 0),
                           isEdited: isEdited == true, hasLiveVideo: livePhotoVideoId != nil,
                           isExternalLibrary: libraryId?.isEmpty == false,
                           serverDescription: description?.isEmpty == false ? description : nil, serverRating: rating)
    }
}
