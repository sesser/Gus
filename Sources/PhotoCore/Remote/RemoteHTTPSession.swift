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
        return try await perform(request, limit: endpoint.maximumResponseSize, anyStatus: false).body
    }

    /// Sends `endpoint` and returns its answer whatever the status: a 2xx
    /// body up to the endpoint's cap, any other status's body up to
    /// `RemoteAnswer.errorBodyLimit` (publishing reports the server's own
    /// words, R23). Throws only when no HTTP answer came (or it was refused at
    /// its head: encoded, over the cap).
    public func exchange(_ endpoint: ImmichEndpoint) async throws(RemoteError) -> RemoteAnswer {
        let request = try makeRequest(method: endpoint.method, path: endpoint.path, query: endpoint.queryItems,
                                      body: endpoint.body, sendsKey: endpoint.sendsKey)
        return try await perform(request, limit: endpoint.maximumResponseSize, anyStatus: true)
    }

    /// Any method and path: refused unless the allowlist has it. Exists so
    /// tests can show that nothing outside the allowlist is ever sent (AC5).
    func send(method: String, path: String) async throws(RemoteError) -> Data {
        try await perform(try makeRequest(method: method, path: path, query: [], body: nil, sendsKey: true),
                          limit: 1 << 16, anyStatus: false).body
    }

    func makeRequest(method: String, path: String, query: [URLQueryItem], body: Data?, sendsKey: Bool,
                     contentType: String = "application/json") throws(RemoteError) -> URLRequest {
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
        // Bodies as sent: an encoded answer is decoded by the system before
        // any cap sees its bytes, so one is refused at its head (code review
        // C23; what the system may decode before the head is #279).
        request.setValue(ContentCoding.identity, forHTTPHeaderField: "Accept-Encoding")
        if let body {
            request.httpBody = body
        }
        if body != nil || method != "GET" {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
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
    private func perform(_ request: URLRequest, limit: Int, anyStatus: Bool) async throws(RemoteError) -> RemoteAnswer {
        let sink = MemorySink(limit: limit, anyStatus: anyStatus)
        let task = session.dataTask(with: request)
        delegate.register(sink, for: task.taskIdentifier)
        let outcome: Result<RemoteAnswer, TaskFailure> = await withTaskCancellationHandler {
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

    /// The system's error. A refused certificate is taken by the task's sink
    /// (`TaskSink.finished`), never here: another task's refusal is not this
    /// one's.
    func mapped(_ error: any Error) -> RemoteError {
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

    // MARK: Uploads (publishing, R17)

    /// Streams `file` as the body of `endpoint` (publishing's upload: the
    /// multipart body `PublishUploadBody` wrote), never holding it in memory,
    /// and returns the answer whatever its status.
    ///
    /// Cancelling the calling task ends the upload by R17's rule: a body not
    /// yet fully sent is cancelled at once; a body fully sent (handed to the
    /// system; status.md, task 5) waits for its answer until `ending`'s
    /// deadline, which the first cancellation of the run sets, and is
    /// cancelled then. "Fully sent" is read when the cancellation comes, not
    /// from a callback that may not have arrived.
    public func upload(_ endpoint: ImmichEndpoint, fromFile file: URL, contentType: String,
                       ending: RemoteUploadEnding) async throws(RemoteError) -> RemoteAnswer {
        let request = try makeRequest(method: endpoint.method, path: endpoint.path, query: endpoint.queryItems,
                                      body: nil, sendsKey: endpoint.sendsKey, contentType: contentType)
        let sink = MemorySink(limit: endpoint.maximumResponseSize, anyStatus: true) { sent, expected in
            if RemoteUploadEnding.isFullySent(sent: sent, expected: expected) { ending.didSendAll() }
        }
        let task = session.uploadTask(with: request, fromFile: file)
        delegate.register(sink, for: task.taskIdentifier)
        // Whether this upload's answer is awaited by an ending run: set by the
        // cancellation, ended once the upload is over, whichever order the
        // two come in (the handler may run beside the return).
        enum Wait { case running, awaiting, over }
        let wait = Mutex(Wait.running)
        let outcome: Result<RemoteAnswer, TaskFailure> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                sink.start(continuation)
                task.resume()
            }
        } onCancel: {
            let waits = RemoteUploadEnding.end(task, by: ending.deadline())
            let began = wait.withLock { state -> Bool in
                guard waits, state == .running else { return false }
                state = .awaiting
                return true
            }
            if began { ending.beganAwaiting() }
        }
        let wasAwaited = wait.withLock { state -> Bool in
            defer { state = .over }
            return state == .awaiting
        }
        if wasAwaited { ending.endedAwaiting() }
        delegate.unregister(task.taskIdentifier)
        switch outcome {
        case .success(let answer):
            return answer
        case .failure(let failure):
            throw mapped(failure)
        }
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
    /// Decided here: a status, the cap, the disk, an answer that isn't HTTP
    /// or is encoded.
    case remote(RemoteError)
    /// The system's error, and the certificate refused in the handshake, if
    /// that was why.
    case transport(any Error, refused: TrustDecision?)
}

/// The content codings an answer may have (code review C23). The system
/// decodes gzip, deflate and br before a delegate sees a byte, and hands the
/// decoded body over in pieces of any size (a 1 MiB gzip answer arrived as a
/// 672 MB piece), with no length to check at the head. Asking for
/// `identity` does not stop a server that compresses anyway, so an answer
/// with any other coding is refused at its head: no decoded byte reaches a
/// sink. That does not bound what the system decodes before it hands over
/// the head: an answer with no `Content-Type` (or `text/plain`) whose body
/// arrives after its head is sniffed, and about 1 MiB of gzip was decoded
/// into 0.16 to 2.5 GB first (security review, second pass; accepted by the
/// owner 2026-11-24, issue #279). URLSession offers no way to turn that off.
enum ContentCoding {
    static let identity = "identity"

    /// False for an answer whose body is not sent as is.
    static func isIdentity(_ response: HTTPURLResponse) -> Bool {
        guard let value = response.value(forHTTPHeaderField: "Content-Encoding") else { return true }
        let coding = value.trimmingCharacters(in: .whitespaces).lowercased()
        return coding.isEmpty || coding == identity
    }
}

/// What the delegate hands a task's response, bytes and end to.
protocol TaskSink: AnyObject, Sendable {
    /// False to stop at once.
    func received(_ response: URLResponse) -> Bool
    /// False to stop the task.
    func received(_ data: Data) -> Bool
    /// `takeRefused` gives the certificate refused in a handshake, and is
    /// asked only by a task that failed before any answer came: one that had
    /// an answer got past its handshake, so a refusal is another task's.
    func finished(_ error: (any Error)?, takeRefused: () -> TrustDecision?)
    /// An upload's body went to the system.
    func sent(_ total: Int64, of expected: Int64)
}

extension TaskSink {
    func sent(_ total: Int64, of expected: Int64) {}
}

/// Hands a task's result to its caller once, whichever comes first: the
/// caller's continuation or the result. A call made from a task that is
/// already cancelled cancels its data task before it stores its
/// continuation, and the system can report that end in between; the result
/// then waits here, and `wait` resumes at once (code review C22).
final class ResultHandoff<Value: Sendable>: Sendable {
    private enum State {
        case empty
        case waiting(CheckedContinuation<Value, Never>)
        case ready(Value)
        case handedOver
    }

    private let state = Mutex(State.empty)

    /// Called once, by the caller.
    func wait(_ continuation: CheckedContinuation<Value, Never>) {
        let ready: Value? = state.withLock { state in
            switch state {
            case .empty:
                state = .waiting(continuation)
                return nil
            case .ready(let value):
                state = .handedOver
                return value
            case .waiting, .handedOver:
                preconditionFailure("A task's result was waited for twice")
            }
        }
        if let ready { continuation.resume(returning: ready) }
    }

    /// The first result counts; any later one is dropped.
    func deliver(_ value: Value) {
        let waiting: CheckedContinuation<Value, Never>? = state.withLock { state in
            switch state {
            case .empty:
                state = .ready(value)
                return nil
            case .waiting(let continuation):
                state = .handedOver
                return continuation
            case .ready, .handedOver:
                return nil
            }
        }
        waiting?.resume(returning: value)
    }
}

/// Collects one answer in memory, at most `limit` bytes of it: the count is
/// checked as each piece arrives, on the delegate's queue, so the cap stops
/// the task whether or not the caller is running.
final class MemorySink: TaskSink {
    private struct State {
        var data = Data()
        var status = 0
        var limit: Int
        var refusal: RemoteError?
    }

    /// A non-2xx answer is kept, with at most `RemoteAnswer.errorBodyLimit`
    /// bytes of its body (`exchange`); otherwise it is refused at its head.
    private let anyStatus: Bool
    private let state: Mutex<State>
    private let handoff = ResultHandoff<Result<RemoteAnswer, TaskFailure>>()
    /// An upload's body went to the system: (sent, expected).
    private let onSent: (@Sendable (Int64, Int64) -> Void)?

    init(limit: Int, anyStatus: Bool = false, onSent: (@Sendable (Int64, Int64) -> Void)? = nil) {
        self.anyStatus = anyStatus
        self.onSent = onSent
        state = Mutex(State(limit: limit))
    }

    func sent(_ total: Int64, of expected: Int64) {
        onSent?(total, expected)
    }

    func start(_ continuation: CheckedContinuation<Result<RemoteAnswer, TaskFailure>, Never>) {
        handoff.wait(continuation)
    }

    func received(_ response: URLResponse) -> Bool {
        state.withLock { state in
            guard let http = response as? HTTPURLResponse else {
                state.refusal = .malformed
                return false
            }
            state.status = http.statusCode
            if !(200..<300).contains(http.statusCode) {
                guard anyStatus else {
                    state.refusal = .status(http.statusCode)
                    return false
                }
                state.limit = min(state.limit, RemoteAnswer.errorBodyLimit)
            }
            guard ContentCoding.isIdentity(http) else {
                state.refusal = .malformed
                return false
            }
            guard response.expectedContentLength <= Int64(state.limit) else {
                // An error's body is only words for a report: an overlong
                // one is dropped, the status kept.
                if !(200..<300).contains(http.statusCode) {
                    state.limit = 0
                    return true
                }
                state.refusal = .tooLarge
                return false
            }
            state.data.reserveCapacity(max(0, min(Int(response.expectedContentLength), state.limit)))
            return true
        }
    }

    func received(_ data: Data) -> Bool {
        state.withLock { state in
            guard state.refusal == nil else { return false }
            guard state.data.count + data.count <= state.limit else {
                if !(200..<300).contains(state.status) {
                    // Words past the error cap are not read; the status stands.
                    return false
                }
                state.refusal = .tooLarge
                state.data = Data()
                return false
            }
            state.data.append(data)
            return true
        }
    }

    func finished(_ error: (any Error)?, takeRefused: () -> TrustDecision?) {
        let result = state.withLock { state -> Result<RemoteAnswer, TaskFailure> in
            defer { state.data = Data() }
            if let refusal = state.refusal {
                return .failure(.remote(refusal))
            } else if state.status != 0, !(200..<300).contains(state.status) {
                // An error answer stopped at the cap reads as what arrived.
                return .success(RemoteAnswer(status: state.status, body: state.data))
            } else if let error {
                return .failure(.transport(error, refused: state.status == 0 ? takeRefused() : nil))
            } else if state.status == 0 {
                return .failure(.remote(.malformed))
            } else {
                return .success(RemoteAnswer(status: state.status, body: state.data))
            }
        }
        handoff.deliver(result)
    }
}

/// An HTTP answer: its status and body (`RemoteHTTPSession.exchange`).
public struct RemoteAnswer: Sendable, Hashable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }

    /// The most of a non-2xx answer's body that is read: its message is all
    /// publishing uses (R23).
    public static let errorBodyLimit = 64 << 10

    /// The server's `message`, if the body is Immich's error JSON (`{"message":
    /// "…"}`, or a list of messages), cut at 200 characters (design §10.2).
    public var serverMessage: String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        let text: String? = if let message = object["message"] as? String {
            message
        } else if let messages = object["message"] as? [String] {
            messages.joined(separator: "; ")
        } else {
            nil
        }
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed.count > 200 ? String(trimmed.prefix(200)) : trimmed
    }
}

/// When a stopped run's uploads give up (R17, design §9): the first
/// cancellation of the run sets the deadline, `bound` after it; nothing
/// restarts or extends it.
public final class RemoteUploadEnding: Sendable {
    public let bound: Duration
    private let started = Mutex<ContinuousClock.Instant?>(nil)
    /// Uploads fully sent when the run began to end, still waiting for their answer.
    private let awaiting = Mutex(0)
    /// Told on the session's delegate queue when an upload's whole body went
    /// to the system (tests and the debug script stop a run there).
    private let onFullySent: (@Sendable () -> Void)?
    /// Told when the first answer starts being awaited (true) and when the
    /// last one awaited has come or been given up (false): the run's
    /// "Waiting for … to answer" (publishing design §9, review D-1).
    private let onAwaitingChange: (@Sendable (Bool) -> Void)?

    public init(bound: Duration = .seconds(10), onFullySent: (@Sendable () -> Void)? = nil,
                onAwaitingChange: (@Sendable (Bool) -> Void)? = nil) {
        self.bound = bound
        self.onFullySent = onFullySent
        self.onAwaitingChange = onAwaitingChange
    }

    func didSendAll() {
        onFullySent?()
    }

    /// An ending run waits for at least one answer to a fully sent file.
    public var isAwaitingAnswers: Bool { awaiting.withLock { $0 > 0 } }

    func beganAwaiting() {
        let count = awaiting.withLock { count -> Int in
            count += 1
            return count
        }
        if count == 1 { onAwaitingChange?(true) }
    }

    func endedAwaiting() {
        let count = awaiting.withLock { count -> Int in
            count = max(0, count - 1)
            return count
        }
        if count == 0 { onAwaitingChange?(false) }
    }

    /// The deadline, set by the first call.
    public func deadline() -> ContinuousClock.Instant {
        started.withLock { started in
            if let started { return started + bound }
            let now = ContinuousClock.now
            started = now
            return now + bound
        }
    }

    /// When the run began to end, if it has.
    public var endedAt: ContinuousClock.Instant? { started.withLock { $0 } }

    /// A body not fully sent is cancelled now; one fully sent is left to
    /// answer until `deadline`, then cancelled (a no-op once it has ended).
    /// True when it is left to answer.
    @discardableResult
    static func end(_ task: URLSessionTask, by deadline: ContinuousClock.Instant) -> Bool {
        guard isFullySent(sent: task.countOfBytesSent, expected: task.countOfBytesExpectedToSend) else {
            task.cancel()
            return false
        }
        Task.detached {
            try? await Task.sleep(until: deadline, clock: .continuous)
            task.cancel()
        }
        return true
    }

    /// The whole body was handed to the system. An unknown length is never
    /// fully sent.
    static func isFullySent(sent: Int64, expected: Int64) -> Bool {
        expected > 0 && sent >= expected
    }
}

/// Receives one download's bytes: writes them, hashes them, reports them.
final class DownloadSink: TaskSink {
    private struct State {
        var hasher = Insecure.SHA1()
        var count: Int64 = 0
        var status = 0
        var expectedLength: Int64?
        /// Decided here: a status, an answer that isn't HTTP or is encoded,
        /// bytes past the limit, the disk.
        var refusal: RemoteError?
    }

    private let handle: FileHandle
    private let limit: Int64
    private let progress: @Sendable (Int64) -> Void
    private let state = Mutex(State())
    private let handoff = ResultHandoff<Result<RemoteHTTPSession.Download, RemoteError>>()

    init(handle: FileHandle, limit: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.handle = handle
        self.limit = limit
        self.progress = progress
    }

    func start(_ continuation: CheckedContinuation<Result<RemoteHTTPSession.Download, RemoteError>, Never>) {
        handoff.wait(continuation)
    }

    /// False to stop at once, before any byte of the body: a status that is
    /// not 2xx, an answer that isn't HTTP or is encoded, or a
    /// `Content-Length` past the limit.
    func received(_ response: URLResponse) -> Bool {
        state.withLock { state in
            guard let http = response as? HTTPURLResponse else {
                state.refusal = .malformed
                return false
            }
            state.status = http.statusCode
            let length = response.expectedContentLength
            state.expectedLength = length >= 0 ? length : nil
            guard (200..<300).contains(http.statusCode) else {
                state.refusal = .status(http.statusCode)
                return false
            }
            guard ContentCoding.isIdentity(http) else {
                state.refusal = .malformed
                return false
            }
            guard length <= limit else {
                state.refusal = .tooLarge
                return false
            }
            return true
        }
    }

    /// False to stop the download (the disk, or bytes past the limit).
    func received(_ data: Data) -> Bool {
        let carryOn = state.withLock { state -> Bool in
            guard state.refusal == nil, state.status != 0 else { return false }
            guard state.count + Int64(data.count) <= limit else {
                state.refusal = .tooLarge
                return false
            }
            do {
                try handle.write(contentsOf: data)
            } catch {
                state.refusal = .disk(error.localizedDescription)
                return false
            }
            state.hasher.update(data: data)
            state.count += Int64(data.count)
            return true
        }
        if carryOn { progress(Int64(data.count)) }
        return carryOn
    }

    func finished(_ error: (any Error)?, takeRefused: () -> TrustDecision?) {
        let result = state.withLock { state -> Result<RemoteHTTPSession.Download, RemoteError> in
            if let refusal = state.refusal {
                return .failure(refusal)
            } else if let error {
                if state.status == 0, let refused = takeRefused() { return .failure(.certificate(refused)) }
                guard let urlError = error as? URLError else { return .failure(.unreachable(error.localizedDescription)) }
                return .failure(urlError.code == .cancelled ? .cancelled : .unreachable(RemoteHTTPSession.reason(urlError)))
            } else if state.status == 0 {
                return .failure(.malformed)
            }
            do {
                try handle.synchronize()
                return .success(.init(byteCount: state.count, sha1: Data(state.hasher.finalize()).base64EncodedString(),
                                      expectedLength: state.expectedLength))
            } catch {
                return .failure(.disk(error.localizedDescription))
            }
        }
        handoff.deliver(result)
    }
}

/// The session's delegate: decides certificates, refuses redirects, and
/// hands each task's answer to its sink.
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

    // MARK: Uploads

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        sink(task)?.sent(totalBytesSent, of: totalBytesExpectedToSend)
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
        sink.finished(error, takeRefused: takeRefused)
    }
}
