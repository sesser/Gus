import Foundation
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

/// Issue #271, the seventh code review pass: a call that starts cancelled
/// always returns (C22), and an encoded answer is refused at its head,
/// before the system decodes a byte of it (C23).
@Suite("Remote session: cancelled calls and encoded answers")
struct RemoteSessionTests {
    /// `operation`'s value, or nil when it has not returned within `bound`,
    /// so a call that never returns fails the test instead of hanging it. The
    /// bound is no wait for the result: a result that is there returns at
    /// once, and the timer is cancelled.
    static func returns<T: Sendable>(within bound: Duration = .seconds(10),
                                     _ operation: @escaping @Sendable () async -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = Mutex(false)
            let finish: @Sendable (T?) -> Void = { value in
                if once.withLock({ let first = !$0; $0 = true; return first }) { continuation.resume(returning: value) }
            }
            let timer = Task {
                try? await Task.sleep(for: bound)
                finish(nil)
            }
            Task {
                finish(await operation())
                timer.cancel()
            }
        }
    }

    static func session(_ server: FakeImmichServer) throws -> RemoteHTTPSession {
        try RemoteHTTPSession(connection: RemoteConnection(address: RemoteConnectionTests.address(server.address),
                                                           key: FakeImmichServer.validKey, unencryptedConfirmed: true),
                              requestTimeout: 5)
    }

    static func response(_ headers: [String: String], status: Int = 200) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(url: URL(string: "http://127.0.0.1/api/server/version")!, statusCode: status,
                                     httpVersion: "HTTP/1.1", headerFields: headers))
    }

    // MARK: C22

    @Test("A task's end that comes before its caller waits is handed over at once, for answers and downloads (C22)")
    func endBeforeWait() async throws {
        // The order a call made from a cancelled task can take: the system
        // reports the cancel before the caller has stored its continuation.
        // Before the fix the result was dropped and the caller waited for
        // ever; the bound turns that into a failure.
        let memory = MemorySink(limit: 1 << 10)
        memory.finished(URLError(.cancelled), takeRefused: { nil })
        let answer = await Self.returns { await withCheckedContinuation { memory.start($0) } }
        guard case .failure(.transport(let error, let refused))? = answer else {
            Issue.record("The answer's end was lost: \(String(describing: answer))")
            return
        }
        #expect((error as? URLError)?.code == .cancelled && refused == nil)

        let file = FileManager.default.temporaryDirectory.appending(path: "handoff-\(UUID().uuidString)")
        #expect(FileManager.default.createFile(atPath: file.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: file) }
        let download = DownloadSink(handle: try FileHandle(forWritingTo: file), limit: 1 << 10, progress: { _ in })
        download.finished(URLError(.cancelled), takeRefused: { nil })
        let downloaded = await Self.returns { await withCheckedContinuation { download.start($0) } }
        #expect(downloaded == .failure(.cancelled))

        // The usual order still works, and a second end is dropped.
        let usual = MemorySink(limit: 1 << 10)
        async let waited = Self.returns { await withCheckedContinuation { usual.start($0) } }
        #expect(usual.received(try Self.response([:])))
        #expect(usual.received(Data("{}".utf8)))
        usual.finished(nil, takeRefused: { nil })
        usual.finished(URLError(.timedOut), takeRefused: { nil })
        guard case .success(let data)? = await waited else {
            Issue.record("The answer was lost")
            return
        }
        #expect(data == Data("{}".utf8))
    }

    @Test("A call made from a task that is already cancelled returns cancelled, and never hangs (C22)")
    func alreadyCancelledCalls() async throws {
        let server = try await FakeImmichServer()
        server.setAssets(try FakeImmichServer.jpegAssets(count: 1))
        let id = try #require(server.assets.first?.id)
        let session = try Self.session(server)
        await RepositoryFiles.withTemporaryDirectory { root in
            // The window C22 needed (a thread preempted between the cancel
            // and the wait) can't be forced from here; `endBeforeWait` pins
            // that order. This checks the outcome, many times over.
            for round in 0..<50 {
                let file = root.appending(path: "original-\(round).jpg")
                let outcome = await Self.returns { () -> [RemoteError?] in
                    withUnsafeCurrentTask { $0?.cancel() }
                    var errors: [RemoteError?] = []
                    for endpoint in [ImmichEndpoint.serverVersion, .thumbnail(assetID: id)] {
                        do throws(RemoteError) {
                            _ = try await session.data(endpoint)
                            errors.append(nil)
                        } catch {
                            errors.append(error)
                        }
                    }
                    do throws(RemoteError) {
                        _ = try await session.download(.original(assetID: id), to: file)
                        errors.append(nil)
                    } catch {
                        errors.append(error)
                    }
                    return errors
                }
                #expect(outcome == [.cancelled, .cancelled, .cancelled], "round \(round)")
                #expect(!FileManager.default.fileExists(atPath: file.path))
            }
        }
    }

    // MARK: C23

    @Test("An answer is refused at its head when it is encoded, before a byte of it is read (C23)")
    func encodedRefusedAtHead() throws {
        for coding in ["gzip", "deflate", "br", "GZIP", " x-gzip ", "gzip, identity"] {
            let memory = MemorySink(limit: 1 << 10)
            #expect(!memory.received(try Self.response(["Content-Encoding": coding])), "\(coding)")
            memory.finished(URLError(.cancelled), takeRefused: { Issue.record("A refusal was taken"); return nil })
            // The refusal stands even if a piece were handed over.
            #expect(!memory.received(Data("{}".utf8)))
        }
        for coding in ["identity", " Identity ", ""] {
            let memory = MemorySink(limit: 1 << 10)
            #expect(memory.received(try Self.response(["Content-Encoding": coding])), "\(coding)")
        }
        // A status other than 2xx still wins over the coding.
        let status = MemorySink(limit: 1 << 10)
        #expect(!status.received(try Self.response(["Content-Encoding": "gzip"], status: 404)))

        let file = FileManager.default.temporaryDirectory.appending(path: "encoded-\(UUID().uuidString)")
        #expect(FileManager.default.createFile(atPath: file.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: file) }
        let download = DownloadSink(handle: try FileHandle(forWritingTo: file), limit: 1 << 20, progress: { _ in })
        #expect(!download.received(try Self.response(["Content-Encoding": "gzip", "Content-Length": "10"])))
        #expect(!download.received(Data(count: 10)))
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) == 0)
    }

    @Test("A server that compresses whatever it is asked is refused: the check, lists, thumbnails and downloads (C23)")
    func encodedAnswersRefused() async throws {
        let server = try await FakeImmichServer()
        server.setAssets(try FakeImmichServer.jpegAssets(count: 1))
        let asset = try #require(server.assets.first)
        server.add(.contentEncoding("deflate"))

        // The fake's deflate is real: the system decodes it into the answer,
        // so a client that let it through would read it.
        let plain = try await URLSession(configuration: .ephemeral)
            .data(from: URL(string: server.address + "/api/server/version")!).0
        #expect((try JSONSerialization.jsonObject(with: plain) as? [String: Any])?["major"] as? Int == 3)

        let client = try RemoteConnectionTests.client(server)
        let session = try Self.session(server)
        server.clearRequests()
        #expect(await client.check() == .notImmich)
        await #expect(throws: RemoteError.malformed) { _ = try await session.data(.serverVersion) }
        await #expect(throws: RemoteError.malformed) { _ = try await client.albums() }
        await #expect(throws: RemoteError.malformed) { _ = try await client.thumbnail(assetID: asset.id) }
        await RepositoryFiles.withTemporaryDirectory { root in
            let file = root.appending(path: "original.jpg")
            let written = Mutex<Int64>(0)
            await #expect(throws: RemoteError.malformed) {
                _ = try await client.download(assetID: asset.id, to: file, limit: Int64(asset.data.count)) { bytes in
                    written.withLock { $0 += bytes }
                }
            }
            #expect(written.withLock { $0 } == 0)
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
        // A label alone is refused too: the rule is the head, not the bytes.
        server.clearFaults()
        server.add(.contentEncoding("GZIP"))
        await #expect(throws: RemoteError.malformed) { _ = try await session.data(.serverVersion) }
        // Every request asked for the body as it is.
        let asked = Set(server.requests.map(\.acceptEncoding))
        #expect(asked == [ContentCoding.identity], "\(asked)")
    }

    @Test("An identity answer is read as before: the check, thumbnails and downloads (C23)")
    func identityAnswersRead() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: 1))
            setup.server.add(.contentEncoding("identity"))
            guard case .passed(let info) = await setup.client.check() else {
                Issue.record("The check did not pass")
                return
            }
            #expect(info.ownerID == FakeImmichServer.ownerID)
            let asset = try #require(setup.server.assets.first)
            #expect(try await setup.client.thumbnail(assetID: asset.id) == asset.data)
            let file = root.appending(path: "original.jpg")
            let download = try await setup.client.download(assetID: asset.id, to: file, limit: Int64(asset.data.count)) { _ in }
            #expect(download.byteCount == Int64(asset.data.count))
            #expect(try Data(contentsOf: file) == asset.data)
        }
    }
}
