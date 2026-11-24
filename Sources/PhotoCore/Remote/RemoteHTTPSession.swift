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
    /// The answer was larger than it may be: a JSON answer or thumbnail over
    /// its cap, or a download past its expected size (code review C4).
    case tooLarge
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
        return try await perform(request, limit: endpoint.maximumResponseSize)
    }

    /// Any method and path: refused unless the allowlist has it. Exists so
    /// tests can show that nothing outside the allowlist is ever sent (AC5).
    func send(method: String, path: String) async throws(RemoteError) -> Data {
        try await perform(try makeRequest(method: method, path: path, query: [], body: nil, sendsKey: true), limit: 1 << 16)
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

    /// Sends `request` and reads at most `limit` bytes of a 2xx answer: a
    /// longer one is refused as soon as its length is known, or when it passes
    /// the limit, so no answer can grow without bound in memory.
    ///
    /// The bytes are taken by the session's delegate as they arrive, not by
    /// the caller: a stream the caller reads (`URLSession.bytes(for:)`) stops
    /// taking bytes while the caller can't run, and a caller held up longer
    /// than the request timeout (every thread of the shared pool busy) got
    /// "The request timed out." in place of the answer or `tooLarge` (CI on
    /// PR #278, status.md).
    private func perform(_ request: URLRequest, limit: Int) async throws(RemoteError) -> Data {
        let sink = MemorySink(limit: limit)
        let task = session.dataTask(with: request)
        delegate.register(sink, for: task.taskIdentifier)
        let outcome: Result<Data, TaskFailure> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                sink.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        delegate.unregister(task.taskIdentifier)
        switch outcome {
        case .success(let data):
            return data
        case .failure(let failure):
            throw mapped(failure)
        }
    }

    func mapped(_ failure: TaskFailure) -> RemoteError {
        switch failure {
        case .remote(let error): error
        case .transport(let error, let refused): refused.map { .certificate($0) } ?? mapped(error)
        }
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
    /// `limit`: the most bytes it may have (the size the server reported, or
    /// `RemoteAsset.maximumSize`); a longer answer is stopped there and fails
    /// with `tooLarge` (code review C4).
    public func download(_ endpoint: ImmichEndpoint, to file: URL, limit: Int64 = RemoteAsset.maximumSize,
                         progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws(RemoteError) -> Download {
        let request = try makeRequest(method: endpoint.method, path: endpoint.path, query: endpoint.queryItems,
                                      body: endpoint.body, sendsKey: endpoint.sendsKey)
        guard FileManager.default.createFile(atPath: file.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: file) else {
            throw .disk(CocoaError(.fileWriteNoPermission).localizedDescription)
        }
        let sink = DownloadSink(handle: handle, limit: limit, progress: progress)
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

/// Why a task the delegate followed ended without its answer.
enum TaskFailure: Error, Sendable {
    /// Decided here: a status, the cap, the disk, an answer that isn't HTTP.
    case remote(RemoteError)
    /// The system's error, and the certificate refused in the handshake, if
    /// that was why.
    case transport(any Error, refused: TrustDecision?)
}

/// What the delegate hands a task's response, bytes and end to.
protocol TaskSink: AnyObject, Sendable {
    /// False to stop at once.
    func received(_ response: URLResponse) -> Bool
    /// False to stop the task.
    func received(_ data: Data) -> Bool
    func finished(_ error: (any Error)?, refused: TrustDecision?)
}

/// Collects one answer in memory, at most `limit` bytes of it: the count is
/// checked as each piece arrives, on the delegate's queue, so the cap stops
/// the task whether or not the caller is running.
final class MemorySink: TaskSink {
    private struct State {
        var continuation: CheckedContinuation<Result<Data, TaskFailure>, Never>?
        var data = Data()
        var status = 0
        var refusal: RemoteError?
    }

    private let limit: Int
    private let state = Mutex(State())

    init(limit: Int) {
        self.limit = limit
    }

    func start(_ continuation: CheckedContinuation<Result<Data, TaskFailure>, Never>) {
        state.withLock { $0.continuation = continuation }
    }

    func received(_ response: URLResponse) -> Bool {
        state.withLock { state in
            guard let http = response as? HTTPURLResponse else {
                state.refusal = .malformed
                return false
            }
            state.status = http.statusCode
            guard (200..<300).contains(http.statusCode) else {
                state.refusal = .status(http.statusCode)
                return false
            }
            guard response.expectedContentLength <= Int64(limit) else {
                state.refusal = .tooLarge
                return false
            }
            state.data.reserveCapacity(max(0, min(Int(response.expectedContentLength), limit)))
            return true
        }
    }

    func received(_ data: Data) -> Bool {
        state.withLock { state in
            guard state.refusal == nil else { return false }
            guard state.data.count + data.count <= limit else {
                state.refusal = .tooLarge
                state.data = Data()
                return false
            }
            state.data.append(data)
            return true
        }
    }

    func finished(_ error: (any Error)?, refused: TrustDecision?) {
        let (continuation, result) = state.withLock { state in
            let continuation = state.continuation
            state.continuation = nil
            let result: Result<Data, TaskFailure>
            if let refusal = state.refusal {
                result = .failure(.remote(refusal))
            } else if let error {
                result = .failure(.transport(error, refused: refused))
            } else if state.status == 0 {
                result = .failure(.remote(.malformed))
            } else {
                result = .success(state.data)
            }
            state.data = Data()
            return (continuation, result)
        }
        continuation?.resume(returning: result)
    }
}

/// Receives one download's bytes: writes them, hashes them, reports them.
final class DownloadSink: TaskSink {
    private struct State {
        var continuation: CheckedContinuation<Result<RemoteHTTPSession.Download, RemoteError>, Never>?
        var hasher = Insecure.SHA1()
        var count: Int64 = 0
        var status = 0
        var expectedLength: Int64?
        var writeError: String?
        var tooLarge = false
    }

    private let handle: FileHandle
    private let limit: Int64
    private let progress: @Sendable (Int64) -> Void
    private let state = Mutex(State())

    init(handle: FileHandle, limit: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.handle = handle
        self.limit = limit
        self.progress = progress
    }

    func start(_ continuation: CheckedContinuation<Result<RemoteHTTPSession.Download, RemoteError>, Never>) {
        state.withLock { $0.continuation = continuation }
    }

    /// False to stop at once: a `Content-Length` past the limit.
    func received(_ response: URLResponse) -> Bool {
        let http = response as? HTTPURLResponse
        return state.withLock { state in
            state.status = http?.statusCode ?? 0
            let length = response.expectedContentLength
            state.expectedLength = length >= 0 ? length : nil
            if (200..<300).contains(state.status), length > limit {
                state.tooLarge = true
                return false
            }
            return true
        }
    }

    /// False to stop the download (a status that is not 2xx, the disk, or
    /// bytes past the limit).
    func received(_ data: Data) -> Bool {
        let carryOn = state.withLock { state -> Bool in
            guard (200..<300).contains(state.status), state.writeError == nil, !state.tooLarge else { return false }
            guard state.count + Int64(data.count) <= limit else {
                state.tooLarge = true
                return false
            }
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

    func finished(_ error: (any Error)?, refused: TrustDecision?) {
        let error: RemoteError? = error.map { error in
            if let refused { return .certificate(refused) }
            guard let urlError = error as? URLError else { return .unreachable(error.localizedDescription) }
            return urlError.code == .cancelled ? .cancelled : .unreachable(RemoteHTTPSession.reason(urlError))
        }
        let (continuation, result) = state.withLock { state in
            let continuation = state.continuation
            state.continuation = nil
            let result: Result<RemoteHTTPSession.Download, RemoteError>
            if state.tooLarge {
                result = .failure(.tooLarge)
            } else if let writeError = state.writeError {
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
    private let state = Mutex<(refused: TrustDecision?, sinks: [Int: any TaskSink])>((nil, [:]))

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

    func register(_ sink: any TaskSink, for task: Int) {
        state.withLock { $0.sinks[task] = sink }
    }

    func unregister(_ task: Int) {
        _ = state.withLock { $0.sinks.removeValue(forKey: task) }
    }

    private func sink(_ task: URLSessionTask) -> (any TaskSink)? {
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

    // MARK: Answers and downloads

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let carryOn = sink(dataTask)?.received(response) ?? true
        completionHandler(carryOn ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let sink = sink(dataTask) else { return }
        if !sink.received(data) { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let sink = sink(task) else { return }
        sink.finished(error, refused: error == nil ? nil : takeRefused())
    }
}
