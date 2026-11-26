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
/// bytes, redirect, compress whatever it is asked, or not be Immich.
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
        /// Listed as a favorite, with these tags (the app maps neither, R17).
        public var isFavorite = false
        public var tags: [String] = []
        /// The path the server reads the file from (publishing R12): an
        /// external library's real path, or the upload's place.
        public var originalPath: String?
        /// The stack it is in (publishing R14).
        public var stackID: String?
        /// An upload of the account (not an external library's file): the
        /// only kind an upload of the same bytes is answered as a duplicate
        /// of (status.md, item 9).
        public var isUpload: Bool
        /// False for another account that shares nothing with the key's: its
        /// assets are neither searched nor read. True (the default) for the
        /// key's own and a partner's (status.md, item 6).
        public var visibleToAccount = true
        /// What the upload that made it sent, besides the file.
        public var uploadFields: [String: String] = [:]

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
            self.isUpload = libraryID == nil
        }

        /// The bytes' size, as `exifInfo.fileSizeInByte` gives it.
        public var byteCount: Int { data.count }

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
        public var createdAt: Date
        /// Another account's album shared with the key's (never "owned").
        public var isOwned: Bool

        public init(id: String = UUID().uuidString.lowercased(), name: String, assetCount: Int,
                    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000), isOwned: Bool = true) {
            self.id = id
            self.name = name
            self.assetCount = assetCount
            self.createdAt = createdAt
            self.isOwned = isOwned
        }
    }

    public struct Request: Sendable, Hashable, CustomStringConvertible {
        public var method: String
        public var path: String
        public var query: String
        public var sentKey: Bool
        public var body: Data
        /// The request's `Accept-Encoding`, if it sent one.
        public var acceptEncoding: String?

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
        /// The answer at `path` (without `/api`) is `bytes` long, whatever it
        /// should be.
        case huge(path: String, bytes: Int)
        /// The asset's original has 1 KiB more than the listing says.
        case oversize(String)
        /// Every answer is sent chunked, with no `Content-Length`.
        case chunked
        /// Every answer says `Content-Encoding: <coding>`, whatever the
        /// request asked for, as a reverse proxy that compresses everything
        /// does. `deflate` compresses the body (zlib, RFC 1950), so a client
        /// that read it would get the answer; any other coding labels the body
        /// as it is.
        case contentEncoding(String)
        /// Publishing: `POST /stacks` is refused, as for a locked primary
        /// (400 "Not found or no asset.update access").
        case refuseStack
        /// The request at `method` `path` (without `/api`; a prefix ending
        /// in `/` matches below it) is carried out, then its connection is
        /// closed without an answer, this many times.
        case loseAnswer(method: String, path: String, times: Int)
        /// The request is answered `status` without being carried out, this
        /// many times (429, 503 for a temporary condition).
        case answer(method: String, path: String, status: Int, times: Int)
        /// Uploads are carried out and their answers held until
        /// `releaseHeldAnswers()` (R17, AC23).
        case holdUploadAnswer
        /// An upload's body is not read past its head: the client can't send
        /// it all (R17: not fully sent).
        case stallUploadBody
    }

    /// What one upload sent (publishing R4, R24): its fields and the file.
    public struct Upload: Sendable {
        public var fields: [String: String]
        public var partFileName: String?
        public var partContentType: String?
        public var data: Data
        public var assetID: String
        public var duplicate: Bool
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
        var onRequest: (@Sendable (String) -> Void)?
        var onAnswered: (@Sendable (String) -> Void)?
        var lostLeft: [String: Int] = [:]
        var answerLeft: [String: Int] = [:]
        /// Held upload answers, with the uploaded file's name.
        var held: [(fileName: String, send: @Sendable () -> Void)] = []
        var uploads: [Upload] = []
        /// Stack id to its primary.
        var stacks: [String: String] = [:]
        var onUploadReceived: (@Sendable (String) -> Void)?
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
    public func clearFaults() {
        state.withLock {
            $0.faults = []
            $0.unavailableLeft = [:]
            $0.lostLeft = [:]
            $0.answerLeft = [:]
        }
    }

    public func add(_ fault: Fault) {
        state.withLock { state in
            state.faults.append(fault)
            switch fault {
            case .unavailable(let id, let times): state.unavailableLeft[id] = times
            case .loseAnswer(let method, let path, let times): state.lostLeft[method + " " + path] = times
            case .answer(let method, let path, _, let times): state.answerLeft[method + " " + path] = times
            default: break
            }
        }
    }

    public func remove(_ fault: Fault) { state.withLock { $0.faults.removeAll { $0 == fault } } }

    /// Sends the upload answers `holdUploadAnswer` held (to connections the
    /// client may have closed).
    public func releaseHeldAnswers() {
        let held = state.withLock { state -> [@Sendable () -> Void] in
            defer { state.held = [] }
            return state.held.map(\.send)
        }
        for send in held { send() }
    }

    /// Sends the held answer to the upload of the file named `fileName` (its
    /// `filename` field), so a test decides the order uploads finish in.
    /// False when none is held.
    @discardableResult
    public func releaseHeldAnswer(fileName: String) -> Bool {
        let send = state.withLock { state -> (@Sendable () -> Void)? in
            guard let index = state.held.firstIndex(where: { $0.fileName == fileName }) else { return nil }
            return state.held.remove(at: index).send
        }
        send?()
        return send != nil
    }

    /// Answers held now.
    public var heldAnswerCount: Int { state.withLock { $0.held.count } }

    /// The file names of the uploads whose answers are held, in arrival order.
    public var heldFileNames: [String] { state.withLock { $0.held.map(\.fileName) } }

    /// Every upload the server carried out, in order.
    public var uploads: [Upload] { state.withLock { $0.uploads } }

    /// Called (on the server's queue) once an upload's whole body arrived,
    /// with the new or existing asset's id.
    public func onUploadReceived(_ handler: (@Sendable (String) -> Void)?) { state.withLock { $0.onUploadReceived = handler } }

    /// The asset with `id`, as the server holds it.
    public func asset(_ id: String) -> Asset? { state.withLock { $0.assets.first { $0.id == id } } }

    /// Changes an asset in place (a test trashing, hiding or locking it).
    public func update(_ id: String, _ change: (inout Asset) -> Void) {
        state.withLock { state in
            guard let index = state.assets.firstIndex(where: { $0.id == id }) else { return }
            change(&state.assets[index])
        }
    }

    /// The albums as the server holds them, with their members.
    public var albums: [(album: Album, assetIDs: [String])] {
        state.withLock { state in
            state.albums.map { album in (album, state.assets.filter { $0.albumIDs.contains(album.id) }.map(\.id)) }
        }
    }

    /// The listed (not trashed) members of `id`'s stack and its primary, or
    /// nil when it is in none that lists two.
    public func stack(of id: String) -> (id: String, primary: String, members: [String])? {
        state.withLock { state in Self.stackRef(of: id, state: state).map { ($0.id, $0.primary, $0.members) } }
    }

    /// Makes a stack directly (test setup), the first id primary.
    public func makeStack(_ ids: [String]) {
        state.withLock { state in
            let stackID = UUID().uuidString.lowercased()
            state.stacks[stackID] = ids[0]
            for index in state.assets.indices where ids.contains(state.assets[index].id) {
                state.assets[index].stackID = stackID
            }
        }
    }

    /// Called (on the server's queue) as each original download starts.
    public func onOriginal(_ handler: (@Sendable (String) -> Void)?) { state.withLock { $0.onOriginal = handler } }

    /// Called (on the server's queue) with each request's path as it
    /// arrives, before anything is answered.
    public func onRequest(_ handler: (@Sendable (String) -> Void)?) { state.withLock { $0.onRequest = handler } }

    /// Called (on the server's queue) with a request's path once its answer
    /// is over: every byte handed to the system, or the connection gone
    /// first (the client closed it).
    public func onAnswered(_ handler: (@Sendable (String) -> Void)?) { state.withLock { $0.onAnswered = handler } }

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
            if self.stallsUpload(buffer) {
                // The head is in; the body is never read (the connection stays
                // open until the client closes it).
                self.state.withLock { state in
                    state.requests.append(Request(method: "POST", path: "/api/assets", query: "", sentKey: true,
                                                  body: Data(), acceptEncoding: nil))
                }
                return
            }
            if let request = Self.parse(buffer) {
                self.respond(to: request, on: connection)
            } else if complete || error != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func stallsUpload(_ buffer: Data) -> Bool {
        guard state.withLock({ $0.faults.contains(.stallUploadBody) }),
              buffer.range(of: Data("\r\n\r\n".utf8)) != nil else { return false }
        return buffer.starts(with: Data("POST /api/assets ".utf8))
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
        var chunked = false

        static func json(_ object: Any, status: Int = 200) -> Response {
            Response(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
    }

    private func respond(to request: ParsedRequest, on connection: NWConnection) {
        let key = request.headers["x-api-key"]
        let snapshot = state.withLock { state -> State in
            state.requests.append(Request(method: request.method, path: request.path, query: request.query,
                                          sentKey: key != nil, body: request.body,
                                          acceptEncoding: request.headers["accept-encoding"]))
            return state
        }
        snapshot.onRequest?(request.path)
        if snapshot.faults.contains(.drop) { return connection.cancel() }
        let route = request.method + " " + (request.path.hasPrefix("/api") ? String(request.path.dropFirst(4)) : request.path)
        let canned: Int? = state.withLock { state in
            guard let key = state.answerLeft.keys.first(where: { Self.route(route, matches: $0) }),
                  let left = state.answerLeft[key], left > 0 else { return nil }
            state.answerLeft[key] = left - 1
            for case .answer(let method, let path, let status, _) in state.faults where method + " " + path == key {
                return status
            }
            return nil
        }
        if let canned {
            let answered = snapshot.onAnswered
            let path = request.path
            send(.json(["message": "Status \(canned)", "statusCode": canned], status: canned), on: connection) { answered?(path) }
            return
        }
        var response = answer(request, key: key, state: snapshot)
        let lose = state.withLock { state -> Bool in
            guard let key = state.lostLeft.keys.first(where: { Self.route(route, matches: $0) }),
                  let left = state.lostLeft[key], left > 0 else { return false }
            state.lostLeft[key] = left - 1
            return true
        }
        if lose { return connection.cancel() }
        if route == "POST /assets", snapshot.faults.contains(.holdUploadAnswer), (200..<300).contains(response.status) {
            let answered = snapshot.onAnswered
            let path = request.path
            let held = response
            let assetID = (try? JSONSerialization.jsonObject(with: response.body) as? [String: Any])?["id"] as? String
            state.withLock { state in
                let fileName = state.uploads.last { $0.assetID == assetID }?.fields["filename"] ?? ""
                state.held.append((fileName, { [weak self] in self?.send(held, on: connection) { answered?(path) } }))
            }
            return
        }
        response.chunked = snapshot.faults.contains(.chunked)
        for case .contentEncoding(let coding) in snapshot.faults {
            response.headers["Content-Encoding"] = coding
            if coding == "deflate" { response.body = Self.zlib(response.body) }
        }
        let answered = snapshot.onAnswered
        let path = request.path
        send(response, on: connection) { answered?(path) }
    }

    /// `route` ("POST /albums") is `pattern`, or below it when the pattern's
    /// path ends in "/".
    static func route(_ route: String, matches pattern: String) -> Bool {
        pattern.hasSuffix("/") ? route.hasPrefix(pattern) : route == pattern
    }

    private func answer(_ request: ParsedRequest, key: String?, state snapshot: State) -> Response {
        let path = request.path.hasPrefix("/api") ? String(request.path.dropFirst(4)) : request.path
        for case .huge(let hugePath, let bytes) in snapshot.faults where hugePath == path {
            return Response(status: 200, body: Data(repeating: 0x20, count: bytes))
        }
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
            if let missing = requires("album.read") { return missing }
            let query = Self.query(request.query)
            var albums = snapshot.albums
            if query["isOwned"] == "true" { albums = albums.filter(\.isOwned) }
            if let name = query["name"] { albums = albums.filter { $0.name == name } }
            if let holding = query["assetId"] {
                let asset = snapshot.assets.first { $0.id == holding }
                albums = albums.filter { asset?.albumIDs.contains($0.id) == true }
            }
            return .json(albums.map { Self.albumJSON($0, state: snapshot) })
        case ("POST", "/search/metadata"):
            return requires("asset.read") ?? search(request.body, state: snapshot)
        case ("POST", "/assets"):
            return requires("asset.upload") ?? upload(request)
        case ("POST", "/albums"):
            return requires("album.create") ?? createAlbum(request.body)
        case ("POST", "/stacks"):
            if let missing = requires("stack.create") { return missing }
            if snapshot.faults.contains(.refuseStack) {
                return .json(["message": "Not found or no asset.update access", "statusCode": 400], status: 400)
            }
            return createStack(request.body)
        default:
            break
        }
        let parts = path.split(separator: "/")
        if request.method == "PUT", parts.count == 3, parts[0] == "albums", parts[2] == "assets" {
            return requires("albumAsset.create") ?? addToAlbum(String(parts[1]), request.body)
        }
        if request.method == "GET", parts.count == 2, parts[0] == "assets" {
            if let missing = requires("asset.read") { return missing }
            return readAsset(String(parts[1]))
        }
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
            if snapshot.faults.contains(.oversize(id)) { data.append(Data(repeating: 0, count: 1024)) }
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
        var matches = snapshot.assets.filter(\.visibleToAccount)
        // `eq` and `in` compare bytes: case and Unicode form count (status.md, item 6).
        if let condition = filter["originalPath"] as? [String: Any] {
            let wanted = ((condition["in"] as? [String]) ?? []) + ((condition["eq"] as? String).map { [$0] } ?? [])
            let forms = wanted.map { Array($0.utf8) }
            matches = matches.filter { asset in asset.originalPath.map { forms.contains(Array($0.utf8)) } ?? false }
        }
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
                "isEdited": asset.isEdited, "isFavorite": asset.isFavorite, "isArchived": asset.visibility == "archive",
                "tags": asset.tags.map { ["id": UUID().uuidString.lowercased(), "name": $0, "value": $0] },
                "visibility": asset.visibility, "livePhotoVideoId": asset.livePhotoVideoID ?? NSNull(),
                "libraryId": asset.libraryID ?? NSNull(),
                "originalPath": asset.originalPath ?? NSNull(),
                "stack": Self.stackJSON(of: asset.id, state: snapshot),
                "exifInfo": exif,
            ]
        }
        return .json(["albums": ["total": 0, "count": 0, "items": [], "facets": []],
                      "assets": ["total": items.count, "count": items.count, "items": items, "facets": [],
                                 "nextPage": NSNull(), "nextCursor": next]])
    }

    // MARK: Publishing (issue #28; docs/features/publishing-engine/status.md)

    static func query(_ text: String) -> [String: String] {
        var items: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let name = parts.first?.removingPercentEncoding else { continue }
            items[name] = parts.count > 1 ? (parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? parts[1]) : ""
        }
        return items
    }

    private static func albumJSON(_ album: Album, state: State) -> [String: Any] {
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let members = state.assets.filter { $0.albumIDs.contains(album.id) }.count
        return ["id": album.id, "albumName": album.name, "assetCount": max(album.assetCount, members),
                "createdAt": style.format(album.createdAt), "ownerId": Self.ownerID,
                "albumUsers": [["user": ["id": Self.ownerID], "role": "editor"]]]
    }

    /// The listed members of an asset's stack: not trashed; nil when fewer
    /// than two are listed (status.md, items 5 and 10).
    private static func stackRef(of id: String, state: State) -> (id: String, primary: String, members: [String])? {
        guard let asset = state.assets.first(where: { $0.id == id }), let stackID = asset.stackID,
              let primary = state.stacks[stackID] else { return nil }
        let members = state.assets.filter { $0.stackID == stackID && !$0.isTrashed }.map(\.id)
        guard members.count >= 2 else { return nil }
        return (stackID, primary, members)
    }

    private static func stackJSON(of id: String, state: State) -> Any {
        guard let stack = stackRef(of: id, state: state) else { return NSNull() }
        return ["id": stack.id, "primaryAssetId": stack.primary, "assetCount": stack.members.count]
    }

    /// `GET /assets/{id}`: the key's own, a partner's or a shared asset;
    /// missing, unshared and locked alike are 400 (status.md, item 6).
    private func readAsset(_ id: String) -> Response {
        state.withLock { state in
            guard let asset = state.assets.first(where: { $0.id == id }), asset.visibleToAccount,
                  asset.visibility != "locked" else {
                return .json(["message": "Not found or no asset.read access", "statusCode": 400], status: 400)
            }
            return .json(Self.assetJSON(asset, state: state))
        }
    }

    private static func assetJSON(_ asset: Asset, state: State) -> [String: Any] {
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        var exif: [String: Any] = ["make": "Synthetic", "model": "Generator"]
        if asset.reportsSize { exif["fileSizeInByte"] = asset.data.count }
        return [
            "id": asset.id, "type": asset.type, "originalFileName": asset.fileName, "checksum": asset.checksum,
            "fileCreatedAt": style.format(asset.takenAt), "fileModifiedAt": style.format(asset.takenAt),
            "localDateTime": style.format(asset.takenAt), "ownerId": asset.ownerID, "isTrashed": asset.isTrashed,
            "visibility": asset.visibility, "libraryId": asset.libraryID ?? NSNull(),
            "originalPath": asset.originalPath ?? NSNull(), "stack": stackJSON(of: asset.id, state: state),
            "exifInfo": exif,
        ]
    }

    /// `POST /assets`: multipart; a file the account already uploaded (any
    /// visibility, the trash included) is answered 200 `duplicate` with the
    /// existing id, else 201 `created` (status.md, item 9).
    private func upload(_ request: ParsedRequest) -> Response {
        guard let type = request.headers["content-type"], let range = type.range(of: "boundary=") else {
            return .json(["message": "Bad request"], status: 400)
        }
        let boundary = String(type[range.upperBound...])
        let parts = Self.multipart(request.body, boundary: boundary)
        guard let file = parts.first(where: { $0.name == "assetData" }), let created = parts.first(where: { $0.name == "fileCreatedAt" }),
              parts.contains(where: { $0.name == "fileModifiedAt" }) else {
            return .json(["message": ["assetData, fileCreatedAt and fileModifiedAt are required"]], status: 400)
        }
        var fields: [String: String] = [:]
        for part in parts where part.name != "assetData" { fields[part.name] = String(decoding: part.data, as: UTF8.self) }
        let checksum = Data(Insecure.SHA1.hash(data: file.data)).base64EncodedString()
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let taken = (try? style.parse(String(decoding: created.data, as: UTF8.self)))
            ?? (try? Date.ISO8601FormatStyle().parse(String(decoding: created.data, as: UTF8.self))) ?? Date()
        let (id, duplicate) = state.withLock { state -> (String, Bool) in
            if let existing = state.assets.first(where: { $0.isUpload && $0.ownerID == Self.ownerID && $0.checksum == checksum }) {
                state.uploads.append(Upload(fields: fields, partFileName: file.fileName, partContentType: file.contentType,
                                            data: file.data, assetID: existing.id, duplicate: true))
                return (existing.id, true)
            }
            let name = fields["filename"] ?? file.fileName ?? "file"
            var asset = Asset(fileName: name, data: file.data, visibility: fields["visibility"] ?? "timeline", takenAt: taken)
            asset.originalPath = "/data/upload/\(Self.ownerID)/\(asset.id)/\(name)"
            asset.uploadFields = fields
            asset.isUpload = true
            state.assets.append(asset)
            state.uploads.append(Upload(fields: fields, partFileName: file.fileName, partContentType: file.contentType,
                                        data: file.data, assetID: asset.id, duplicate: false))
            return (asset.id, false)
        }
        state.withLock { $0.onUploadReceived }?(id)
        return .json(["id": id, "status": duplicate ? "duplicate" : "created"], status: duplicate ? 200 : 201)
    }

    struct Part {
        var name: String
        var fileName: String?
        var contentType: String?
        var data: Data
    }

    static func multipart(_ body: Data, boundary: String) -> [Part] {
        let delimiter = Data("--\(boundary)".utf8)
        var parts: [Part] = []
        var cursor = body.startIndex
        while let start = body.range(of: delimiter, in: cursor..<body.endIndex) {
            let afterDelimiter = start.upperBound
            if body[afterDelimiter...].starts(with: Data("--".utf8)) { break }
            guard let headEnd = body.range(of: Data("\r\n\r\n".utf8), in: afterDelimiter..<body.endIndex) else { break }
            let head = String(decoding: body[afterDelimiter..<headEnd.lowerBound], as: UTF8.self)
            guard let next = body.range(of: Data("\r\n".utf8) + delimiter, in: headEnd.upperBound..<body.endIndex) else { break }
            var part = Part(name: "", data: Data(body[headEnd.upperBound..<next.lowerBound]))
            for line in head.components(separatedBy: "\r\n") {
                let lower = line.lowercased()
                if lower.hasPrefix("content-disposition:") {
                    part.name = Self.parameter("name", in: line) ?? ""
                    part.fileName = Self.parameter("filename", in: line)
                } else if lower.hasPrefix("content-type:") {
                    part.contentType = line.dropFirst("content-type:".count).trimmingCharacters(in: .whitespaces)
                }
            }
            parts.append(part)
            cursor = next.lowerBound + 2
        }
        return parts
    }

    private static func parameter(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: " \(name)=\"") ?? line.range(of: ";\(name)=\"") else { return nil }
        let rest = line[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    /// `POST /albums`: the assets it names that the account may add are
    /// added; the others are dropped silently (status.md, table).
    private func createAlbum(_ body: Data) -> Response {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let name = object["albumName"] as? String else { return .json(["message": "Bad request"], status: 400) }
        let ids = object["assetIds"] as? [String] ?? []
        return state.withLock { state in
            // A later album is newer, whatever the clock.
            let newest = state.albums.map(\.createdAt).max() ?? Date(timeIntervalSince1970: 1_700_000_000)
            let album = Album(name: name, assetCount: 0, createdAt: max(Date(), newest.addingTimeInterval(1)))
            state.albums.append(album)
            for index in state.assets.indices where ids.contains(state.assets[index].id)
                && state.assets[index].ownerID == Self.ownerID && state.assets[index].visibility != "locked" {
                state.assets[index].albumIDs.append(album.id)
            }
            return .json(Self.albumJSON(album, state: state), status: 201)
        }
    }

    /// `PUT /albums/{id}/assets`: per id, added, or `duplicate` when it is
    /// already there; a trashed asset is added too (status.md, item 9).
    private func addToAlbum(_ albumID: String, _ body: Data) -> Response {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let ids = object["ids"] as? [String] else { return .json(["message": "Bad request"], status: 400) }
        return state.withLock { state in
            guard state.albums.contains(where: { $0.id == albumID && $0.isOwned }) else {
                return .json(["message": "Not found or no album.update access", "statusCode": 400], status: 400)
            }
            let results = ids.map { id -> [String: Any] in
                guard let index = state.assets.firstIndex(where: { $0.id == id && $0.visibleToAccount }) else {
                    return ["id": id, "success": false, "error": "no_permission"]
                }
                if state.assets[index].albumIDs.contains(albumID) { return ["id": id, "success": false, "error": "duplicate"] }
                state.assets[index].albumIDs.append(albumID)
                return ["id": id, "success": true]
            }
            return .json(results)
        }
    }

    /// `POST /stacks` as Immich 3.2.0 and 3.4.2 do it (status.md, items 5,
    /// 9, 10; 2026-11-26): every id the account's own and not locked; the
    /// stacks whose primary is named are merged, their members in the trash
    /// left out (and unstacked); a named non-primary member leaves its old
    /// stack alone; the first id is the new primary; named assets in the
    /// trash keep the new stack's id but are not listed.
    private func createStack(_ body: Data) -> Response {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let ids = object["assetIds"] as? [String], ids.count >= 2 else {
            return .json(["message": ["assetIds must contain at least 2 elements"]], status: 400)
        }
        return state.withLock { state in
            for id in ids {
                guard let asset = state.assets.first(where: { $0.id == id }), asset.ownerID == Self.ownerID,
                      asset.visibility != "locked" else {
                    return .json(["message": "Not found or no asset.update access", "statusCode": 400], status: 400)
                }
            }
            let merged = Set(state.stacks.filter { ids.contains($0.value) }.keys)
            let gathered = state.assets.filter { $0.stackID.map(merged.contains) == true && !$0.isTrashed }.map(\.id)
            var members = ids
            for id in gathered where !members.contains(id) { members.append(id) }
            let stackID = UUID().uuidString.lowercased()
            for index in state.assets.indices {
                if members.contains(state.assets[index].id) {
                    state.assets[index].stackID = stackID
                } else if let old = state.assets[index].stackID, merged.contains(old) {
                    state.assets[index].stackID = nil
                }
            }
            for old in merged { state.stacks[old] = nil }
            state.stacks[stackID] = ids[0]
            let listed = state.assets.filter { $0.stackID == stackID && !$0.isTrashed }.map { ["id": $0.id] }
            return .json(["id": stackID, "primaryAssetId": ids[0], "assets": listed], status: 201)
        }
    }

    /// `data` in the zlib format (RFC 1950): a header, raw deflate, and the
    /// Adler-32 of the data.
    static func zlib(_ data: Data) -> Data {
        guard let deflated = try? (data as NSData).compressed(using: .zlib) as Data else { return data }
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let adler = (b << 16) | a
        return Data([0x78, 0x9C]) + deflated
            + Data([UInt8(adler >> 24), UInt8((adler >> 16) & 0xFF), UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)])
    }

    private func send(_ response: Response, on connection: NWConnection, done: @escaping @Sendable () -> Void) {
        let finish: @Sendable (NWError?) -> Void = { _ in
            connection.cancel()
            done()
        }
        let truncate = response.headers["X-Truncate"] != nil
        var headers = response.headers
        headers["X-Truncate"] = nil
        // Truncated: a shorter file than the listing reported, sent whole.
        let body = truncate ? response.body.prefix(response.body.count / 2) : response.body
        if response.chunked {
            var head = "HTTP/1.1 \(response.status) Status\r\nContent-Type: \(response.contentType)\r\n"
            head += "Transfer-Encoding: chunked\r\nConnection: close\r\n"
            for (name, value) in headers { head += "\(name): \(value)\r\n" }
            var data = Data((head + "\r\n").utf8)
            var offset = body.startIndex
            while offset < body.endIndex {
                let end = min(offset + (64 << 10), body.endIndex)
                data += Data(String(end - offset, radix: 16).utf8) + Data("\r\n".utf8) + body[offset..<end] + Data("\r\n".utf8)
                offset = end
            }
            data += Data("0\r\n\r\n".utf8)
            connection.send(content: data, completion: .contentProcessed(finish))
            return
        }
        var head = "HTTP/1.1 \(response.status) \(response.status == 200 ? "OK" : "Status")\r\n"
        head += "Content-Type: \(response.contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        guard let pause = response.pause, body.count > 1 else {
            connection.send(content: Data(head.utf8) + body, completion: .contentProcessed(finish))
            return
        }
        // Slowly: the head and half the body, a pause, then the rest.
        let half = body.count / 2
        connection.send(content: Data(head.utf8) + body.prefix(half), completion: .contentProcessed { [queue] error in
            if let error { return finish(error) }
            let delay = Double(pause.components.seconds) + Double(pause.components.attoseconds) / 1e18
            queue.asyncAfter(deadline: .now() + delay) {
                connection.send(content: body.dropFirst(half), completion: .contentProcessed(finish))
            }
        })
    }
}
