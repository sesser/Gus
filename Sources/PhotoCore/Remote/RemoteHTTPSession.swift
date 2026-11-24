import CryptoKit
import Foundation
import Synchronization

/// What reaching a server can come to, apart from a response.
public enum RemoteError: Error, Equatable, Sendable {
    /// A request outside `RemoteRequestAllowlist`: never sent (R7).
    case notAllowed(method: String, path: String)
    /// Plain http to a host that is not on the local network, or not
    /// confirmed (R5): never sent.
    case transportRefused(host: String)
    /// No answer: the system's reason, in its own words (no URL in it).
    case unreachable(String)
    /// The certificate was not accepted (R6). Nothing was sent: the decision
    /// is made in the TLS handshake, before the request.
    case certificate(TrustDecision)
    /// An HTTP status other than 2xx; a redirect is one too, since redirects
    /// are never followed (R7).
    case status(Int)
    /// The answer could not be read as the API's.
    case malformed
    /// The download could not be written here: the system's reason.
    case disk(String)
    case cancelled

    /// Worth asking again (R20): the server may come back.
    var isTransient: Bool {
        switch self {
        case .unreachable: true
        case .status(let code): [502, 503, 504].contains(code)
        default: false
        }
    }
}

/// How to reach one server: its address, key and pinned certificate. The key
/// is never part of any description, so it can't reach a log or a debug
/// print by accident (R1).
public struct RemoteConnection: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var address: ServerAddress
    public var key: String
    public var pinned: CertificateFingerprint?
    /// The person ticked "Send my key and photos without encryption" (R5).
    public var unencryptedConfirmed: Bool

    public init(address: ServerAddress, key: String, pinned: CertificateFingerprint? = nil,
                unencryptedConfirmed: Bool = false) {
        self.address = address
        self.key = key
        self.pinned = pinned
        self.unencryptedConfirmed = unencryptedConfirmed
    }

    public var description: String { "RemoteConnection(\(address))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["address": address.normalized]) }
}

/// The one way the app talks to a server (R7, R23): an ephemeral session (no
/// cookies, no cache on disk, no credential storage), requests only from the
/// allowlist, the key only to the connection's own host, redirects never
/// followed, and the certificate decided by `TrustDecision` in the handshake.
public final class RemoteHTTPSession: Sendable {
    public let connection: RemoteConnection
    private let session: URLSession
    private let delegate: SessionDelegate

    /// Per request: how long without a byte before it is given up.
    public static let requestTimeout: TimeInterval = 30

    public init(connection: RemoteConnection, requestTimeout: TimeInterval = RemoteHTTPSession.requestTimeout)
        throws(RemoteError) {
        guard TransportPolicy.of(connection.address).permits(unencryptedConfirmed: connection.unencryptedConfirmed) else {
            throw .transportRefused(host: connection.address.host)
        }
        self.connection = connection
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6
        delegate = SessionDelegate(host: connection.address.host, pinned: connection.pinned)
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    /// The decision of the last TLS handshake that was refused, if any.
    public var lastRefusedCertificate: TrustDecision? { delegate.refused }

    // MARK: Requests

    /// Sends `endpoint` and returns the body of a 2xx answer.
    public func data(_ endpoint: ImmichEndpoint) async throws(RemoteError) -> Data {
        let request = try makeRequest(method: endpoint.method, path: endpoint.path, query: endpoint.queryItems,
                                      body: endpoint.body, sendsKey: endpoint.sendsKey)
        return try await perform(request)
    }

    /// Any method and path: refused unless the allowlist has it. Exists so
    /// tests can show that nothing outside the allowlist is ever sent (AC5).
    func send(method: String, path: String) async throws(RemoteError) -> Data {
        try await perform(try makeRequest(method: method, path: path, query: [], body: nil, sendsKey: true))
    }

    func makeRequest(method: String, path: String, query: [URLQueryItem], body: Data?, sendsKey: Bool)
        throws(RemoteError) -> URLRequest {
        guard RemoteRequestAllowlist.permits(method: method, path: path) else {
            throw .notAllowed(method: method, path: path)
        }
        guard var components = URLComponents(url: connection.address.apiBaseURL, resolvingAgainstBaseURL: false) else {
            throw .malformed
        }
        components.percentEncodedPath += path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url, url.host?.lowercased() == connection.address.host.lowercased() else {
            throw .malformed
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if sendsKey { request.setValue(connection.key, forHTTPHeaderField: "x-api-key") }
        return request
    }

    private func perform(_ request: URLRequest) async throws(RemoteError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapped(error)
        }
        guard let http = response as? HTTPURLResponse else { throw .malformed }
        guard (200..<300).contains(http.statusCode) else { throw .status(http.statusCode) }
        return data
    }

    func mapped(_ error: any Error) -> RemoteError {
        if let refused = delegate.takeRefused() { return .certificate(refused) }
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .unreachable(error.localizedDescription) }
        if urlError.code == .cancelled { return Task.isCancelled ? .cancelled : .unreachable(urlError.localizedDescription) }
        return .unreachable(Self.reason(urlError))
    }

    /// The system's sentence ("The request timed out."), without the URL
    /// it may name.
    static func reason(_ error: URLError) -> String {
        var text = error.localizedDescription
        if let url = error.failingURL?.absoluteString { text = text.replacingOccurrences(of: url, with: "") }
        return text
    }

    // MARK: Downloads

    /// What a download wrote.
    public struct Download: Sendable, Equatable {
        public var byteCount: Int64
        /// Base64 SHA-1 of the bytes as they arrived.
        public var sha1: String
        /// The response's `Content-Length`, if it gave one.
        public var expectedLength: Int64?
    }

    /// Streams `endpoint`'s body into `file` (created, never replaced),
    /// hashing as it goes. On any failure or cancellation the file is removed.
    public func download(_ endpoint: ImmichEndpoint, to file: URL,
                         progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws(RemoteError) -> Download {
        let request = try makeRequest(method: endpoint.method, path: endpoint.path, query: endpoint.queryItems,
                                      body: endpoint.body, sendsKey: endpoint.sendsKey)
        guard FileManager.default.createFile(atPath: file.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: file) else {
            throw .disk(CocoaError(.fileWriteNoPermission).localizedDescription)
        }
        let sink = DownloadSink(handle: handle, progress: progress)
        let task = session.dataTask(with: request)
        delegate.register(sink, for: task.taskIdentifier)
        let outcome: Result<Download, RemoteError> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                sink.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        delegate.unregister(task.taskIdentifier)
        try? handle.close()
        switch outcome {
        case .success(let download):
            return download
        case .failure(let error):
            try? FileManager.default.removeItem(at: file)
            throw Task.isCancelled ? .cancelled : error
        }
    }
}

/// Receives one download's bytes: writes them, hashes them, reports them.
final class DownloadSink: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Result<RemoteHTTPSession.Download, RemoteError>, Never>?
        var hasher = Insecure.SHA1()
        var count: Int64 = 0
        var status = 0
        var expectedLength: Int64?
        var writeError: String?
    }

    private let handle: FileHandle
    private let progress: @Sendable (Int64) -> Void
    private let state = Mutex(State())

    init(handle: FileHandle, progress: @escaping @Sendable (Int64) -> Void) {
        self.handle = handle
        self.progress = progress
    }

    func start(_ continuation: CheckedContinuation<Result<RemoteHTTPSession.Download, RemoteError>, Never>) {
        state.withLock { $0.continuation = continuation }
    }

    func received(_ response: URLResponse) {
        let http = response as? HTTPURLResponse
        state.withLock { state in
            state.status = http?.statusCode ?? 0
            let length = response.expectedContentLength
            state.expectedLength = length >= 0 ? length : nil
        }
    }

    /// False to stop the download (a status that is not 2xx, or the disk).
    func received(_ data: Data) -> Bool {
        let carryOn = state.withLock { state -> Bool in
            guard (200..<300).contains(state.status), state.writeError == nil else { return false }
            do {
                try handle.write(contentsOf: data)
            } catch {
                state.writeError = error.localizedDescription
                return false
            }
            state.hasher.update(data: data)
            state.count += Int64(data.count)
            return true
        }
        if carryOn { progress(Int64(data.count)) }
        return carryOn
    }

    func finished(_ error: RemoteError?) {
        let (continuation, result) = state.withLock { state in
            let continuation = state.continuation
            state.continuation = nil
            let result: Result<RemoteHTTPSession.Download, RemoteError>
            if let writeError = state.writeError {
                result = .failure(.disk(writeError))
            } else if state.status != 0, !(200..<300).contains(state.status) {
                result = .failure(.status(state.status))
            } else if let error {
                result = .failure(error)
            } else {
                do {
                    try handle.synchronize()
                    result = .success(.init(byteCount: state.count, sha1: Data(state.hasher.finalize()).base64EncodedString(),
                                            expectedLength: state.expectedLength))
                } catch {
                    result = .failure(.disk(error.localizedDescription))
                }
            }
            return (continuation, result)
        }
        continuation?.resume(returning: result)
    }
}

/// The session's delegate: decides certificates, refuses redirects, and
/// hands download bytes to their sinks.
final class SessionDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private let host: String
    private let pinned: CertificateFingerprint?
    private let state = Mutex<(refused: TrustDecision?, sinks: [Int: DownloadSink])>((nil, [:]))

    init(host: String, pinned: CertificateFingerprint?) {
        self.host = host.lowercased()
        self.pinned = pinned
    }

    var refused: TrustDecision? { state.withLock { $0.refused } }

    func takeRefused() -> TrustDecision? {
        state.withLock { state in
            defer { state.refused = nil }
            return state.refused
        }
    }

    func register(_ sink: DownloadSink, for task: Int) {
        state.withLock { $0.sinks[task] = sink }
    }

    func unregister(_ task: Int) {
        _ = state.withLock { $0.sinks.removeValue(forKey: task) }
    }

    private func sink(_ task: URLSessionTask) -> DownloadSink? {
        state.withLock { $0.sinks[task.taskIdentifier] }
    }

    // MARK: Certificates (R6)

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    private func handle(_ challenge: URLAuthenticationChallenge,
                        _ completionHandler: @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            // No password or client certificate is ever offered.
            completionHandler(.rejectProtectionSpace, nil)
            return
        }
        guard space.host.lowercased() == host, let trust = space.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let decision = TrustDecision.decide(trust: trust, host: host, pinned: pinned)
        if decision.accepts {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            state.withLock { $0.refused = decision }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: Redirects (R7)

    /// Never followed: the 3xx itself is the answer, so the key can't reach a
    /// host a redirect names.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    // MARK: Downloads

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        sink(dataTask)?.received(response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let sink = sink(dataTask) else { return }
        if !sink.received(data) { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let sink = sink(task) else { return }
        guard let error else {
            sink.finished(nil)
            return
        }
        if let refused = takeRefused() {
            sink.finished(.certificate(refused))
        } else if let urlError = error as? URLError {
            sink.finished(urlError.code == .cancelled ? .cancelled : .unreachable(RemoteHTTPSession.reason(urlError)))
        } else {
            sink.finished(.unreachable(error.localizedDescription))
        }
    }
}
