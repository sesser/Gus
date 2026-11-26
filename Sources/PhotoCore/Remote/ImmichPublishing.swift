import Foundation

/// An asset as publishing reads it (issue #28): from `GET /assets/{id}` or a
/// search by path. Only what the rules for an original (R13), a duplicate
/// (R19) and a stack (R14) need.
public struct RemoteAssetInfo: Hashable, Sendable, Identifiable {
    public var id: String
    /// Nil when the server named none (never treated as the account's).
    public var ownerID: String?
    /// `IMAGE`, `VIDEO`, …
    public var type: String
    /// `timeline`, `archive`, `hidden` (a locked asset is never returned).
    public var visibility: String?
    public var isTrashed: Bool
    /// The path the server reads the file from (an external library's real path).
    public var originalPath: String?
    /// `exifInfo.fileSizeInByte`, when the server gave a sane one.
    public var byteCount: Int64?
    public var stack: RemoteStackRef?

    public init(id: String, ownerID: String?, type: String = "IMAGE", visibility: String? = "timeline",
                isTrashed: Bool = false, originalPath: String? = nil, byteCount: Int64? = nil,
                stack: RemoteStackRef? = nil) {
        self.id = id
        self.ownerID = ownerID
        self.type = type
        self.visibility = visibility
        self.isTrashed = isTrashed
        self.originalPath = originalPath
        self.byteCount = byteCount
        self.stack = stack
    }

    public var isImage: Bool { type == "IMAGE" }
    public var isHidden: Bool { visibility == "hidden" }
}

/// An asset's stack, as `GET /assets/{id}` gives it.
public struct RemoteStackRef: Hashable, Sendable {
    public var id: String
    public var primaryAssetID: String
    public var assetCount: Int

    public init(id: String, primaryAssetID: String, assetCount: Int) {
        self.id = id
        self.primaryAssetID = primaryAssetID
        self.assetCount = assetCount
    }
}

/// What the server did with an upload (status.md, "Request and response shapes").
public enum RemoteUploadOutcome: Hashable, Sendable {
    /// 201: a new asset.
    case created(String)
    /// 200: the account already had a file with these bytes; its id (R19).
    case duplicate(String)

    public var assetID: String {
        switch self {
        case .created(let id), .duplicate(let id): id
        }
    }
}

/// Why a publishing request did not do what it asked.
public enum PublishFailure: Error, Equatable, Sendable {
    /// No HTTP answer (or one refused at its head): unreachable, the
    /// certificate, cancelled, unreadable.
    case remote(RemoteError)
    /// The server answered with another status, in its own words if it gave any.
    case refused(status: Int, message: String?)

    /// Worth asking again (R22): unreachable, 429, 502 to 504.
    public var isTransient: Bool {
        switch self {
        case .remote(let error): error.isTransient
        case .refused(let status, _): [429, 502, 503, 504].contains(status)
        }
    }

    public var isCancelled: Bool { self == .remote(.cancelled) }

    /// The permission a 403 names ("Missing required permission: asset.upload").
    public var missingPermission: String? {
        guard case .refused(403, let message?) = self,
              let range = message.range(of: "Missing required permission: ") else { return nil }
        let name = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "."))))
        return name.isEmpty ? nil : name
    }

    /// The run stops on this (R22): a rejected key, a changed or untrusted
    /// certificate, a missing permission, or no server after the retries.
    public var stop: PublishStop? {
        switch self {
        case .remote(.certificate): .certificateChanged
        case .remote(let error) where error.isTransient: .unreachable
        case .refused(401, _): .keyRejected
        case .refused(let status, _) where [429, 502, 503, 504].contains(status): .unreachable
        case .refused(403, _): missingPermission.map { .missingPermission($0) }
        default: nil
        }
    }
}

/// Why a run stopped before its end (R22, design §10.1).
public enum PublishStop: Hashable, Sendable {
    /// The person's Stop (or Stop and Quit).
    case stopped
    case unreachable
    case keyRejected
    case certificateChanged
    case missingPermission(String)
    /// A retry's server check failed before anything was sent; what it found
    /// (review D-5).
    case checkFailed(ConnectionCheckResult)

    public var isFault: Bool { self != .stopped }
}

/// What the publish check found (design §3.3): the server and the key's
/// permissions; the account only when stacking asked for it.
public struct PublishServerInfo: Hashable, Sendable {
    public var version: ImmichVersion
    public var permissions: [String]
    /// The key's account (`GET /users/me`, `user.read`), read only with stacking.
    public var ownerID: String?

    public init(version: ImmichVersion, permissions: [String], ownerID: String?) {
        self.version = version
        self.permissions = permissions
        self.ownerID = ownerID
    }

    public func has(_ permission: String) -> Bool {
        permissions.contains("all") || permissions.contains(permission)
    }
}

/// A server photos are published to (issue #28). `ImmichClient` is the one
/// implementation; the protocol keeps the publish run free of HTTP.
public protocol RemotePublishDestination: Sendable {
    var connection: RemoteConnection { get }
    /// The check publishing makes (design §3.3): reachable, Immich, new
    /// enough, key accepted, its permissions; the account when `readsAccount`.
    /// Missing permissions are not a failure here: the sheet names them per
    /// option (design §5).
    func publishCheck(readsAccount: Bool) async -> PublishCheckResult
    /// `GET /assets/{id}`: nil when the server does not return it (a missing,
    /// another account's unshared or a locked asset all read the same, R15).
    func asset(id: String) async throws(PublishFailure) -> RemoteAssetInfo?
    /// The assets whose server path is one of `paths` (R12), the account's,
    /// partners' and any other the server shows (filtered by the caller).
    func assets(atPaths paths: [String]) async throws(PublishFailure) -> [RemoteAssetInfo]
    /// The account's own albums; holding `assetID` when given.
    func ownAlbums(holding assetID: String?) async throws(PublishFailure) -> [RemoteAlbum]
    /// `POST /assets` from the multipart body in `file`.
    func upload(bodyFile file: URL, contentType: String, ending: RemoteUploadEnding) async throws(PublishFailure)
        -> RemoteUploadOutcome
    /// `POST /albums` with the first asset in it (status.md, item 8).
    func createAlbum(named name: String, assetIDs: [String]) async throws(PublishFailure) -> RemoteAlbum
    /// `PUT /albums/{id}/assets`. An asset already in the album counts as
    /// added (R22); the ids the server refused are returned with its error.
    func addToAlbum(_ albumID: String, assetIDs: [String]) async throws(PublishFailure) -> [String: String]
    /// `POST /stacks`: the first id becomes primary (R14).
    func createStack(_ assetIDs: [String]) async throws(PublishFailure) -> RemoteStackRef
}

public enum PublishCheckResult: Hashable, Sendable {
    case passed(PublishServerInfo)
    /// One of the check's failures (never `.passed` or `.missingPermissions`).
    case failed(ConnectionCheckResult)
}

extension ImmichDTO {
    struct AssetDetail: Decodable {
        var id: String
        var type: String?
        var ownerId: String?
        var visibility: String?
        var isTrashed: Bool?
        var originalPath: String?
        var exifInfo: Exif?
        var stack: Stack?
    }

    struct Stack: Decodable {
        var id: String
        var primaryAssetId: String
        var assetCount: Int?
    }

    struct UploadAnswer: Decodable {
        var id: String
        var status: String
    }

    struct CreatedStack: Decodable {
        var id: String
        var primaryAssetId: String
        var assets: [Member]?

        struct Member: Decodable { var id: String }
    }

    struct BulkResult: Decodable {
        var id: String
        var success: Bool
        var error: String?
    }

    struct PathSearchResponse: Decodable {
        var assets: Page

        struct Page: Decodable {
            var items: [AssetDetail]
            var nextCursor: String?
        }
    }

    /// Assets whose server path is one of `paths` (`eq` is exact, so the
    /// composed and decomposed forms go in one `in`; status.md, item 6).
    static func pathSearchBody(paths: [String], cursor: String?) throws -> Data {
        var body: [String: Any] = [
            "filter": ["originalPath": ["in": paths]],
            "size": 100,
            "withExif": true,
        ]
        if let cursor { body["cursor"] = cursor }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}

extension RemoteAssetInfo {
    init(_ dto: ImmichDTO.AssetDetail) {
        self.init(id: dto.id, ownerID: dto.ownerId, type: dto.type ?? "", visibility: dto.visibility,
                  isTrashed: dto.isTrashed == true, originalPath: dto.originalPath,
                  byteCount: RemoteAsset.saneSize(dto.exifInfo?.fileSizeInByte),
                  stack: dto.stack.map { RemoteStackRef(id: $0.id, primaryAssetID: $0.primaryAssetId,
                                                        assetCount: $0.assetCount ?? 0) })
    }
}

extension ImmichClient: RemotePublishDestination {
    /// What a key needs to be saved from Publish (R1, design §4).
    public static let publishingPermissions = ["asset.upload", "asset.read"]

    public func publishCheck(readsAccount: Bool) async -> PublishCheckResult {
        let result = await check(requiring: [], readsAccount: readsAccount)
        switch result {
        case .passed(let info):
            return .passed(PublishServerInfo(version: info.version, permissions: info.permissions,
                                             ownerID: info.ownerID.isEmpty ? nil : info.ownerID))
        case .missingPermissions(let missing):
            // Only `user.read`, when the account was asked for: the sheet names it.
            guard let info = await keyInfo() else { return .failed(.missingPermissions(missing)) }
            return .passed(PublishServerInfo(version: info.version, permissions: info.permissions, ownerID: nil))
        default:
            return .failed(result)
        }
    }

    /// The version and the key's list, once a check found the account unreadable.
    private func keyInfo() async -> (version: ImmichVersion, permissions: [String])? {
        guard let version = try? await http.data(.serverVersion),
              let decoded = try? JSONDecoder().decode(ImmichDTO.ServerVersion.self, from: version),
              let key = try? await http.data(.apiKeyMe),
              let permissions = try? JSONDecoder().decode(ImmichDTO.APIKey.self, from: key) else { return nil }
        return (ImmichVersion(decoded.major, decoded.minor, decoded.patch), permissions.permissions)
    }

    /// One exchange, its failures as `PublishFailure`.
    private func answer(_ endpoint: ImmichEndpoint) async throws(PublishFailure) -> RemoteAnswer {
        do throws(RemoteError) {
            return try await http.exchange(endpoint)
        } catch {
            throw .remote(error)
        }
    }

    private static func refusal(_ answer: RemoteAnswer) -> PublishFailure {
        .refused(status: answer.status, message: answer.serverMessage)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ answer: RemoteAnswer) throws(PublishFailure) -> T {
        guard answer.isSuccess else { throw refusal(answer) }
        guard let value = try? JSONDecoder().decode(type, from: answer.body) else { throw .remote(.malformed) }
        return value
    }

    public func asset(id: String) async throws(PublishFailure) -> RemoteAssetInfo? {
        guard RemoteAsset.isServerID(id) else { return nil }
        let answer = try await answer(.asset(id: id))
        // A missing asset and one the key may not see answer alike (status.md, item 6).
        if answer.status == 400 || answer.status == 404 { return nil }
        return RemoteAssetInfo(try Self.decode(ImmichDTO.AssetDetail.self, answer))
    }

    public func assets(atPaths paths: [String]) async throws(PublishFailure) -> [RemoteAssetInfo] {
        var found: [RemoteAssetInfo] = []
        var cursor: String?
        // A path holds a handful of assets; ten pages is a bound, not a need.
        for _ in 0..<10 {
            let body: Data
            do {
                body = try ImmichDTO.pathSearchBody(paths: paths, cursor: cursor)
            } catch {
                throw .remote(.malformed)
            }
            let page = try Self.decode(ImmichDTO.PathSearchResponse.self, try await answer(.search(body)))
            found += page.assets.items.map(RemoteAssetInfo.init)
            guard let next = page.assets.nextCursor, !next.isEmpty else { break }
            cursor = next
        }
        return found
    }

    public func ownAlbums(holding assetID: String?) async throws(PublishFailure) -> [RemoteAlbum] {
        let endpoint: ImmichEndpoint = assetID.map { .ownAlbumsHolding(assetID: $0) } ?? .ownAlbums
        let albums = try Self.decode([ImmichDTO.Album].self, try await answer(endpoint))
        return RemoteAlbum.sorted(albums.map { RemoteAlbum(id: $0.id, name: $0.albumName, assetCount: $0.assetCount) })
    }

    public func upload(bodyFile file: URL, contentType: String, ending: RemoteUploadEnding) async throws(PublishFailure)
        -> RemoteUploadOutcome {
        let answer: RemoteAnswer
        do throws(RemoteError) {
            answer = try await http.upload(.upload, fromFile: file, contentType: contentType, ending: ending)
        } catch {
            throw .remote(error)
        }
        let decoded = try Self.decode(ImmichDTO.UploadAnswer.self, answer)
        guard !decoded.id.isEmpty else { throw .remote(.malformed) }
        return decoded.status == "duplicate" ? .duplicate(decoded.id) : .created(decoded.id)
    }

    public func createAlbum(named name: String, assetIDs: [String]) async throws(PublishFailure) -> RemoteAlbum {
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: ["albumName": name, "assetIds": assetIDs], options: [.sortedKeys])
        } catch {
            throw .remote(.malformed)
        }
        let album = try Self.decode(ImmichDTO.Album.self, try await answer(.createAlbum(body)))
        return RemoteAlbum(id: album.id, name: album.albumName, assetCount: album.assetCount)
    }

    public func addToAlbum(_ albumID: String, assetIDs: [String]) async throws(PublishFailure) -> [String: String] {
        guard RemoteAsset.isServerID(albumID) else { throw .refused(status: 400, message: nil) }
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: ["ids": assetIDs], options: [.sortedKeys])
        } catch {
            throw .remote(.malformed)
        }
        let results = try Self.decode([ImmichDTO.BulkResult].self, try await answer(.addToAlbum(albumID: albumID, body)))
        var refused: [String: String] = [:]
        for result in results where !result.success && result.error != "duplicate" {
            refused[result.id] = result.error ?? ""
        }
        return refused
    }

    public func createStack(_ assetIDs: [String]) async throws(PublishFailure) -> RemoteStackRef {
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: ["assetIds": assetIDs], options: [.sortedKeys])
        } catch {
            throw .remote(.malformed)
        }
        let stack = try Self.decode(ImmichDTO.CreatedStack.self, try await answer(.createStack(body)))
        return RemoteStackRef(id: stack.id, primaryAssetID: stack.primaryAssetId, assetCount: stack.assets?.count ?? 0)
    }
}

/// The upload's multipart body, written to a file beside the rendered photo
/// so it streams from disk (R17, R24): the values publishing names and the
/// rendered file, nothing else (R4, R24).
public enum PublishUploadBody {
    public struct Fields: Hashable, Sendable {
        /// The capture's wall-clock time labelled UTC (R4, RI-V1).
        public var createdAt: Date
        /// The name the naming setting gives (R3).
        public var fileName: String
        /// `timeline` or `archive` (R6).
        public var visibility: PublishVisibility

        public init(createdAt: Date, fileName: String, visibility: PublishVisibility) {
            self.createdAt = createdAt
            self.fileName = fileName
            self.visibility = visibility
        }
    }

    /// Writes the body for `file` to `body` and returns its content type.
    /// The file's bytes are copied in pieces, never held whole.
    public static func write(file: URL, fields: Fields, to body: URL, boundary: String = UUID().uuidString)
        throws -> String {
        let date = isoUTC(fields.createdAt)
        var head = ""
        func field(_ name: String, _ value: String) {
            head += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
        }
        field("fileCreatedAt", date)
        // The same value: the modification time dates nothing (status.md,
        // item 1) and says nothing new about the file.
        field("fileModifiedAt", date)
        field("filename", headerSafe(fields.fileName))
        field("visibility", fields.visibility.rawValue)
        let type = (fields.fileName as NSString).pathExtension.lowercased().hasPrefix("tif") ? "image/tiff" : "image/jpeg"
        head += "--\(boundary)\r\nContent-Disposition: form-data; name=\"assetData\"; filename=\"\(headerSafe(fields.fileName))\"\r\n"
        head += "Content-Type: \(type)\r\n\r\n"
        let tail = "\r\n--\(boundary)--\r\n"

        guard FileManager.default.createFile(atPath: body.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let output = try FileHandle(forWritingTo: body)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        try output.write(contentsOf: Data(head.utf8))
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data(tail.utf8))
        return "multipart/form-data; boundary=\(boundary)"
    }

    /// "2019-06-15T10:20:30.000Z": the date as UTC, with milliseconds.
    public static func isoUTC(_ date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: TimeZone(secondsFromGMT: 0)!).format(date)
    }

    /// A name in a header or field: no quote, backslash or line break.
    static func headerSafe(_ name: String) -> String {
        String(name.unicodeScalars.filter { $0 != "\"" && $0 != "\\" && $0.properties.generalCategory != .control }
            .map(Character.init))
    }
}

/// Where a published photo shows on the server (R6): set by the upload itself.
public enum PublishVisibility: String, Codable, Hashable, Sendable, CaseIterable {
    case timeline
    case archive
}
