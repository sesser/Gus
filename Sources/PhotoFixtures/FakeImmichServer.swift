import CryptoKit
import Foundation
import Network
import Synchronization

/// An Immich server in the test process, on 127.0.0.1 over plain http (issue
/// #271: "tests run against a local fake Immich server"; R25: the debug
/// script's `import server fake`). It answers only the requests the app
/// makes, filters the metadata search as Immich does (status.md, "API
/// verification"), records every request it gets (AC5), and can be told to
/// fail: drop connections, reject the key, lose an asset, serve corrupt
/// bytes, redirect, or not be Immich.
public final class FakeImmichServer: Sendable {
    public struct Asset: Sendable {
        public var id: String
        public var fileName: String
        public var data: Data
        public var type: String
        public var visibility: String
        public var isTrashed: Bool
        public var isEdited: Bool
        public var livePhotoVideoID: String?
        public var description: String?
        public var rating: Int?
        public var albumIDs: [String]
        public var ownerID: String
        public var takenAt: Date
        /// When false, the listing gives no `fileSizeInByte`.
        public var reportsSize: Bool
        /// An external library's asset (`libraryId` in the listing).
        public var libraryID: String?
        /// The checksum the listing gives in place of the bytes' SHA-1 (an
        /// external library's path hash).
        public var checksumOverride: String?

        public init(id: String = UUID().uuidString.lowercased(), fileName: String, data: Data, type: String = "IMAGE",
                    visibility: String = "timeline", isTrashed: Bool = false, isEdited: Bool = false,
                    livePhotoVideoID: String? = nil, description: String? = nil, rating: Int? = nil,
                    albumIDs: [String] = [], ownerID: String = FakeImmichServer.ownerID, takenAt: Date,
                    reportsSize: Bool = true, libraryID: String? = nil, checksumOverride: String? = nil) {
            self.id = id
            self.fileName = fileName
            self.data = data
            self.type = type
            self.visibility = visibility
            self.isTrashed = isTrashed
            self.isEdited = isEdited
            self.livePhotoVideoID = livePhotoVideoID
            self.description = description
            self.rating = rating
            self.albumIDs = albumIDs
            self.ownerID = ownerID
            self.takenAt = takenAt
            self.reportsSize = reportsSize
            self.libraryID = libraryID
            self.checksumOverride = checksumOverride
        }

        public var checksum: String { checksumOverride ?? Data(Insecure.SHA1.hash(data: data)).base64EncodedString() }

        /// Immich's checksum for an external library's file: the SHA-1 of
        /// "path:" and its path.
        public static func pathChecksum(_ path: String) -> String {
            Data(Insecure.SHA1.hash(data: Data("path:\(path)".utf8))).base64EncodedString()
        }
    }

    public struct Album: Sendable {
        public var id: String
        public var name: String
        /// What the server says it holds (videos included).
        public var assetCount: Int

        public init(id: String = UUID().uuidString.lowercased(), name: String, assetCount: Int) {
            self.id = id
            self.name = name
            self.assetCount = assetCount
        }
    }

    public struct Request: Sendable, Hashable, CustomStringConvertible {
        public var method: String
        public var path: String
        public var query: String
        public var sentKey: Bool
        public var body: Data

        public var description: String { "\(method) \(path)" + (query.isEmpty ? "" : "?\(query)") }
    }

    public enum Fault: Sendable, Hashable {
        /// Every connection is closed without an answer.
        case drop
        /// Every request with a key gets 401.
        case revokeKey
        /// The asset is gone: its original and thumbnail give 404.
        case deleteAsset(String)
        /// The asset's original is served with one byte changed.
        case corrupt(String)
        /// The asset's original is cut short.
        case truncate(String)
        /// `/server/version` answers with a web page.
        case notImmich
        /// Every request with a key is redirected to `location`.
        case redirect(location: String)
        /// The original download of this asset answers 503 this many times.
        case unavailable(String, times: Int)
        /// Originals are sent in pieces, with this pause between them.
        case slow(Duration)
    }

    public static let ownerID = "11111111-1111-4111-8111-111111111111"
    public static let validKey = "fake-key-0123456789"

    private struct State {
        var assets: [Asset] = []
        var albums: [Album] = []
        var version = (3, 4, 2)
        var permissions = ["asset.read", "asset.view", "asset.download", "album.read", "user.read"]
        var key = FakeImmichServer.validKey
        var faults: [Fault] = []
        var requests: [Request] = []
        var unavailableLeft: [String: Int] = [:]
        var onOriginal: (@Sendable (String) -> Void)?
    }

    private let state = Mutex(State())
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-immich")
    public let port: UInt16

    /// Starts listening on 127.0.0.1 at a free port.
    public init() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        self.listener = listener
        let queue = self.queue
        port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, any Error>) in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { state in
                let value: Result<UInt16, any Error>? = switch state {
                case .ready: .success(listener.port?.rawValue ?? 0)
                case .failed(let error): .failure(error)
                case .cancelled: .failure(CancellationError())
                default: nil
                }
                guard let value, resumed.withLock({ let was = $0; $0 = true; return !was }) else { return }
                continuation.resume(with: value)
            }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: queue)
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    deinit {
        listener.cancel()
    }

    public func stop() {
        listener.cancel()
    }

    /// "http://127.0.0.1:<port>".
    public var address: String { "http://127.0.0.1:\(port)" }

    // MARK: Configuration

    public func setAssets(_ assets: [Asset]) { state.withLock { $0.assets = assets } }
    public func addAssets(_ assets: [Asset]) { state.withLock { $0.assets += assets } }
    public var assets: [Asset] { state.withLock { $0.assets } }
    public func setAlbums(_ albums: [Album]) { state.withLock { $0.albums = albums } }
    public func setVersion(_ major: Int, _ minor: Int, _ patch: Int) { state.withLock { $0.version = (major, minor, patch) } }
    public func setPermissions(_ permissions: [String]) { state.withLock { $0.permissions = permissions } }
    public func setKey(_ key: String) { state.withLock { $0.key = key } }
    public func clearFaults() { state.withLock { $0.faults = []; $0.unavailableLeft = [:] } }

    public func add(_ fault: Fault) {
        state.withLock { state in
            state.faults.append(fault)
            if case .unavailable(let id, let times) = fault { state.unavailableLeft[id] = times }
        }
    }

    /// Called (on the server's queue) as each original download starts.
    public func onOriginal(_ handler: (@Sendable (String) -> Void)?) { state.withLock { $0.onOriginal = handler } }

    public var requests: [Request] { state.withLock { $0.requests } }
    public func clearRequests() { state.withLock { $0.requests = [] } }

    // MARK: Fixtures

    /// `count` small JPEGs named IMG_0001.JPG and on, IMG_000n taken n - 1
    /// days before 2026-11-01 (so the lowest number is the newest).
    public static func jpegAssets(count: Int, startingAt first: Int = 1, albumIDs: [String] = []) throws -> [Asset] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "fake-immich-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let start = Date(timeIntervalSince1970: 1_793_491_200) // 2026-11-01T00:00:00Z
        return try (0..<count).map { offset in
            let number = first + offset
            let name = String(format: "IMG_%04d.JPG", number)
            let url = folder.appending(path: name)
            let taken = start.addingTimeInterval(Double(-(number - 1)) * 86_400)
            let stamp = taken.formatted(Date.VerbatimFormatStyle(
                format: "\(year: .defaultDigits):\(month: .twoDigits):\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
                timeZone: TimeZone(secondsFromGMT: 0)!, calendar: Calendar(identifier: .gregorian)))
            try SyntheticImages.writeJPEG(to: url, width: 64, height: 48, seed: UInt64(number),
                                          exif: .init(dateTimeOriginal: stamp))
            return Asset(fileName: name, data: try Data(contentsOf: url), albumIDs: albumIDs, takenAt: taken)
        }
    }

    // MARK: Serving

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, complete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.respond(to: request, on: connection)
            } else if complete || error != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private struct ParsedRequest {
        var method: String
        var path: String
        var query: String
        var headers: [String: String]
        var body: Data
    }

    private static func parse(_ buffer: Data) -> ParsedRequest? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = buffer[end.upperBound...]
        guard body.count >= length else { return nil }
        let target = String(requestLine[1])
        let parts = target.split(separator: "?", maxSplits: 1)
        return ParsedRequest(method: String(requestLine[0]), path: String(parts.first ?? ""),
                             query: parts.count > 1 ? String(parts[1]) : "", headers: headers,
                             body: Data(body.prefix(length)))
    }

    private struct Response {
        var status: Int
        var contentType = "application/json"
        var body = Data()
        var headers: [String: String] = [:]
        var pause: Duration?

        static func json(_ object: Any, status: Int = 200) -> Response {
            Response(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
    }

    private func respond(to request: ParsedRequest, on connection: NWConnection) {
        let key = request.headers["x-api-key"]
        let snapshot = state.withLock { state -> State in
            state.requests.append(Request(method: request.method, path: request.path, query: request.query,
                                          sentKey: key != nil, body: request.body))
            return state
        }
        if snapshot.faults.contains(.drop) { return connection.cancel() }
        let response = answer(request, key: key, state: snapshot)
        send(response, on: connection)
    }

    private func answer(_ request: ParsedRequest, key: String?, state snapshot: State) -> Response {
        let path = request.path.hasPrefix("/api") ? String(request.path.dropFirst(4)) : request.path
        if path == "/server/version", request.method == "GET" {
            if snapshot.faults.contains(.notImmich) {
                return Response(status: 200, contentType: "text/html", body: Data("<html>Hello</html>".utf8))
            }
            let (major, minor, patch) = snapshot.version
            return .json(["major": major, "minor": minor, "patch": patch, "prerelease": NSNull(), "featureLevel": 1])
        }
        for fault in snapshot.faults {
            if case .redirect(let location) = fault {
                return Response(status: 302, headers: ["Location": location])
            }
        }
        guard let key, key == snapshot.key, !snapshot.faults.contains(.revokeKey) else {
            return .json(["message": "Invalid API key", "statusCode": 401], status: 401)
        }
        func requires(_ permission: String) -> Response? {
            snapshot.permissions.contains(permission) || snapshot.permissions.contains("all")
                ? nil : .json(["message": "Missing required permission: \(permission)"], status: 403)
        }
        switch (request.method, path) {
        case ("GET", "/api-keys/me"):
            return .json(["id": "key", "name": "Import", "createdAt": "2026-01-01T00:00:00.000Z",
                          "updatedAt": "2026-01-01T00:00:00.000Z", "permissions": snapshot.permissions])
        case ("GET", "/users/me"):
            return requires("user.read") ?? .json(["id": Self.ownerID, "name": "Owner", "email": "owner@example.invalid"])
        case ("GET", "/albums"):
            return requires("album.read") ?? .json(snapshot.albums.map { album in
                ["id": album.id, "albumName": album.name, "assetCount": album.assetCount,
                 "albumUsers": [["user": ["id": Self.ownerID], "role": "editor"]]] as [String: Any]
            })
        case ("POST", "/search/metadata"):
            return requires("asset.read") ?? search(request.body, state: snapshot)
        default:
            break
        }
        let parts = path.split(separator: "/")
        guard request.method == "GET", parts.count == 3, parts[0] == "assets" else {
            return .json(["message": "Not found"], status: 404)
        }
        let id = String(parts[1])
        guard let asset = snapshot.assets.first(where: { $0.id == id }),
              !snapshot.faults.contains(.deleteAsset(id)) else {
            return .json(["message": "Not found or no asset access"], status: parts[2] == "original" ? 404 : 400)
        }
        switch parts[2] {
        case "thumbnail":
            if let missing = requires("asset.view") { return missing }
            return Response(status: 200, contentType: "image/jpeg", body: asset.data)
        case "original":
            if let missing = requires("asset.download") { return missing }
            snapshot.onOriginal?(id)
            let left = state.withLock { state -> Int in
                let left = state.unavailableLeft[id] ?? 0
                if left > 0 { state.unavailableLeft[id] = left - 1 }
                return left
            }
            if left > 0 { return .json(["message": "Unavailable"], status: 503) }
            var data = asset.data
            if snapshot.faults.contains(.corrupt(id)), !data.isEmpty { data[data.count / 2] ^= 0xFF }
            var response = Response(status: 200, contentType: "image/jpeg", body: data)
            if snapshot.faults.contains(.truncate(id)) {
                response.headers["X-Truncate"] = "1"
            }
            for fault in snapshot.faults {
                if case .slow(let pause) = fault { response.pause = pause }
            }
            return response
        default:
            return .json(["message": "Not found"], status: 404)
        }
    }

    private func search(_ body: Data, state snapshot: State) -> Response {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return .json(["message": "Bad request"], status: 400)
        }
        let filter = object["filter"] as? [String: Any] ?? [:]
        var matches = snapshot.assets
        if let type = (filter["type"] as? [String: Any])?["eq"] as? String { matches = matches.filter { $0.type == type } }
        if let visibility = (filter["visibility"] as? [String: Any])?["eq"] as? String {
            matches = matches.filter { $0.visibility == visibility }
        } else {
            matches = matches.filter { $0.visibility != "locked" }
        }
        if let trashed = filter["trashedAt"] as? [String: Any], trashed["eq"] is NSNull {
            matches = matches.filter { !$0.isTrashed }
        }
        if let albums = (filter["albumIds"] as? [String: Any])?["any"] as? [String] {
            guard albums.allSatisfy({ id in snapshot.albums.contains { $0.id == id } }) else {
                return .json(["message": "Not found or no album.read access"], status: 400)
            }
            matches = matches.filter { !Set($0.albumIDs).isDisjoint(with: albums) }
        }
        if let taken = filter["takenAt"] as? [String: Any] {
            let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            if let start = (taken["gte"] as? String).flatMap({ try? style.parse($0) }) { matches = matches.filter { $0.takenAt >= start } }
            if let end = (taken["lt"] as? String).flatMap({ try? style.parse($0) }) { matches = matches.filter { $0.takenAt < end } }
        }
        let order = object["orderBy"] as? [String: Any]
        let ascending = order?["direction"] as? String == "asc"
        matches.sort { ascending ? $0.takenAt < $1.takenAt : $0.takenAt > $1.takenAt }
        let size = object["size"] as? Int ?? 250
        let offset = (object["cursor"] as? String).flatMap(Int.init) ?? 0
        let page = Array(matches.dropFirst(offset).prefix(size))
        let next: Any = offset + size < matches.count ? String(offset + size) : NSNull()
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let items = page.map { asset -> [String: Any] in
            var exif: [String: Any] = ["make": "Synthetic", "model": "Generator"]
            if asset.reportsSize { exif["fileSizeInByte"] = asset.data.count }
            exif["description"] = asset.description ?? ""
            exif["rating"] = asset.rating ?? NSNull()
            return [
                "id": asset.id, "type": asset.type, "originalFileName": asset.fileName, "checksum": asset.checksum,
                "fileCreatedAt": style.format(asset.takenAt), "fileModifiedAt": style.format(asset.takenAt),
                "localDateTime": style.format(asset.takenAt), "ownerId": asset.ownerID, "isTrashed": asset.isTrashed,
                "isEdited": asset.isEdited, "isFavorite": false, "isArchived": asset.visibility == "archive",
                "visibility": asset.visibility, "livePhotoVideoId": asset.livePhotoVideoID ?? NSNull(),
                "libraryId": asset.libraryID ?? NSNull(),
                "exifInfo": exif,
            ]
        }
        return .json(["albums": ["total": 0, "count": 0, "items": [], "facets": []],
                      "assets": ["total": items.count, "count": items.count, "items": items, "facets": [],
                                 "nextPage": NSNull(), "nextCursor": next]])
    }

    private func send(_ response: Response, on connection: NWConnection) {
        let truncate = response.headers["X-Truncate"] != nil
        var headers = response.headers
        headers["X-Truncate"] = nil
        // Truncated: a shorter file than the listing reported, sent whole.
        let body = truncate ? response.body.prefix(response.body.count / 2) : response.body
        var head = "HTTP/1.1 \(response.status) \(response.status == 200 ? "OK" : "Status")\r\n"
        head += "Content-Type: \(response.contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        guard let pause = response.pause, body.count > 1 else {
            connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        // Slowly: the head and half the body, a pause, then the rest.
        let half = body.count / 2
        connection.send(content: Data(head.utf8) + body.prefix(half), completion: .contentProcessed { [queue] _ in
            let delay = Double(pause.components.seconds) + Double(pause.components.attoseconds) / 1e18
            queue.asyncAfter(deadline: .now() + delay) {
                connection.send(content: body.dropFirst(half), completion: .contentProcessed { _ in connection.cancel() })
            }
        })
    }
}
