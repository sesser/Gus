import Foundation

/// What a server told the check (R2): shown in the inspector's Server section.
public struct RemoteServerInfo: Hashable, Sendable {
    public var version: ImmichVersion
    /// The key's permissions as the server listed them.
    public var permissions: [String]
    /// The account the key belongs to (`GET /users/me`): only its photos are
    /// listed (R9, RI-E1).
    public var ownerID: String

    public init(version: ImmichVersion, permissions: [String], ownerID: String) {
        self.version = version
        self.permissions = permissions
        self.ownerID = ownerID
    }

    /// The key can do more than importing needs (design §5's second caption).
    public var hasMoreThanNeeded: Bool {
        permissions.contains("all") || Set(permissions).subtracting(ImmichClient.neededPermissions).isEmpty == false
    }
}

/// The result of checking a connection (R2, AC2, design §3.4): a pass, one of
/// the seven named failures, or a certificate the person may review. A
/// Keychain failure is the seventh; the sheet and the window produce it, not
/// the check.
public enum ConnectionCheckResult: Hashable, Sendable {
    case passed(RemoteServerInfo)
    case unreachable(reason: String, isLocalHost: Bool)
    case notImmich
    case keyRejected
    case missingPermissions([String])
    case tooOld(found: ImmichVersion, needed: ImmichVersion)
    /// No pin and the system does not trust the certificate: page 2.
    case untrustedCertificate(CertificateSummary)
    /// A pinned connection met another certificate.
    case certificateChanged(CertificateSummary)
    case keychain(String)

    /// For the debug script and logs: the kind, never any text the server sent.
    public var kind: String {
        switch self {
        case .passed: "passed"
        case .unreachable: "unreachable"
        case .notImmich: "notImmich"
        case .keyRejected: "keyRejected"
        case .missingPermissions: "missingPermissions"
        case .tooOld: "tooOld"
        case .untrustedCertificate: "untrustedCertificate"
        case .certificateChanged: "certificateChanged"
        case .keychain: "keychain"
        }
    }
}

/// A server the import window browses and imports from (R23). `ImmichClient`
/// is the one implementation; the protocol keeps the window and the importer
/// free of HTTP.
public protocol RemotePhotoSource: Sendable {
    var connection: RemoteConnection { get }
    func check() async -> ConnectionCheckResult
    func albums() async throws(RemoteError) -> [RemoteAlbum]
    func page(scope: RemoteScope, cursor: String?, ownerID: String) async throws(RemoteError) -> RemotePage
    func thumbnail(assetID: String) async throws(RemoteError) -> Data
    /// `limit`: the most bytes the original may have (the size the server
    /// reported, else `RemoteAsset.maximumSize`).
    func download(assetID: String, to file: URL, limit: Int64, progress: @escaping @Sendable (Int64) -> Void)
        async throws(RemoteError) -> RemoteHTTPSession.Download
}

/// Immich over `RemoteHTTPSession`.
public final class ImmichClient: RemotePhotoSource {
    /// The smallest set of permissions importing needs (R3), in the order
    /// the sheet's caption lists them. `user.read` gives the account's id, so
    /// only its own photos are listed (R9, RI-E1).
    public static let neededPermissions = ["asset.read", "asset.view", "asset.download", "album.read", "user.read"]
    /// Photos per page (status.md: 1 to 1000; a first screen never needs a
    /// second page).
    public static let pageSize = 250

    private let http: RemoteHTTPSession
    public var connection: RemoteConnection { http.connection }

    public init(connection: RemoteConnection, requestTimeout: TimeInterval = RemoteHTTPSession.requestTimeout)
        throws(RemoteError) {
        http = try RemoteHTTPSession(connection: connection, requestTimeout: requestTimeout)
    }

    /// The missing permissions of a key whose list is `permissions`.
    public static func missing(from permissions: [String]) -> [String] {
        guard !permissions.contains("all") else { return [] }
        return neededPermissions.filter { !permissions.contains($0) }
    }

    // MARK: The check (R2)

    public func check() async -> ConnectionCheckResult {
        let isLocal = connection.address.isLocalNetworkHost
        func failure(_ error: RemoteError) -> ConnectionCheckResult {
            switch error {
            case .certificate(.untrusted(let summary)): .untrustedCertificate(summary)
            case .certificate(.changed(let summary)): .certificateChanged(summary)
            case .certificate: .unreachable(reason: "", isLocalHost: isLocal)
            case .unreachable(let reason): .unreachable(reason: reason, isLocalHost: isLocal)
            case .transportRefused, .notAllowed: .unreachable(reason: "", isLocalHost: isLocal)
            case .cancelled: .unreachable(reason: "", isLocalHost: isLocal)
            case .status, .malformed, .tooLarge: .notImmich
            case .disk(let reason): .unreachable(reason: reason, isLocalHost: isLocal)
            }
        }
        // 1. Immich, and new enough: no key sent yet.
        let version: ImmichVersion
        do throws(RemoteError) {
            let data = try await http.data(.serverVersion)
            guard let decoded = try? JSONDecoder().decode(ImmichDTO.ServerVersion.self, from: data) else { return .notImmich }
            version = ImmichVersion(decoded.major, decoded.minor, decoded.patch)
        } catch {
            return failure(error)
        }
        guard version >= .minimum else { return .tooOld(found: version, needed: .minimum) }
        // 2. The key and its permissions.
        let permissions: [String]
        do throws(RemoteError) {
            let data = try await http.data(.apiKeyMe)
            guard let key = try? JSONDecoder().decode(ImmichDTO.APIKey.self, from: data) else { return .notImmich }
            permissions = key.permissions
        } catch .status(let code) where code == 401 || code == 403 {
            return .keyRejected
        } catch {
            return failure(error)
        }
        let missing = Self.missing(from: permissions)
        guard missing.isEmpty else { return .missingPermissions(missing) }
        // 3. The account's id: only its own photos are listed (R9, RI-E1).
        // There is no fallback that guesses it.
        let owner: String
        do throws(RemoteError) {
            let data = try await http.data(.userMe)
            guard let user = try? JSONDecoder().decode(ImmichDTO.User.self, from: data), !user.id.isEmpty else {
                return .notImmich
            }
            owner = user.id
        } catch .status(401) {
            return .keyRejected
        } catch .status(403) {
            return .missingPermissions(["user.read"])
        } catch {
            return failure(error)
        }
        return .passed(RemoteServerInfo(version: version, permissions: permissions, ownerID: owner))
    }

    // MARK: Browsing

    public func albums() async throws(RemoteError) -> [RemoteAlbum] {
        let data = try await http.data(.ownAlbums)
        guard let albums = try? JSONDecoder().decode([ImmichDTO.Album].self, from: data) else { throw .malformed }
        return RemoteAlbum.sorted(albums.map { RemoteAlbum(id: $0.id, name: $0.albumName, assetCount: $0.assetCount) })
    }

    public func page(scope: RemoteScope, cursor: String?, ownerID: String) async throws(RemoteError) -> RemotePage {
        let body: Data
        do {
            body = try ImmichDTO.searchBody(scope: scope, cursor: cursor, size: Self.pageSize)
        } catch {
            throw .malformed
        }
        let data = try await http.data(.search(body))
        guard let response = try? JSONDecoder().decode(ImmichDTO.SearchResponse.self, from: data) else { throw .malformed }
        let cursor = response.assets.nextCursor.flatMap { $0.isEmpty ? nil : $0 }
        return RemotePage(assets: response.assets.items.compactMap { $0.remoteAsset(ownerID: ownerID) }, nextCursor: cursor)
    }

    public func thumbnail(assetID: String) async throws(RemoteError) -> Data {
        try await http.data(.thumbnail(assetID: assetID))
    }

    public func download(assetID: String, to file: URL, limit: Int64, progress: @escaping @Sendable (Int64) -> Void)
        async throws(RemoteError) -> RemoteHTTPSession.Download {
        try await http.download(.original(assetID: assetID), to: file, limit: limit, progress: progress)
    }
}
