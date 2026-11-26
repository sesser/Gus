import Foundation
import PhotoFixtures
import Security
import Testing
@testable import PhotoCore

/// Issue #271: addresses, the transport policy, certificates, the connection
/// check and the request allowlist, against `FakeImmichServer` on 127.0.0.1.
/// Nothing here reaches another host.
@Suite("Immich connections")
struct RemoteConnectionTests {
    static func address(_ text: String) throws -> ServerAddress {
        try ServerAddress.parse(text).get()
    }

    static func client(_ server: FakeImmichServer, key: String = FakeImmichServer.validKey,
                       timeout: TimeInterval = 5) throws -> ImmichClient {
        try ImmichClient(connection: RemoteConnection(address: address(server.address), key: key,
                                                      unencryptedConfirmed: true), requestTimeout: timeout)
    }

    // MARK: Addresses (design §3.2, R16)

    @Test("Addresses are normalized: scheme, case, default port, trailing slash and /api")
    func normalizes() throws {
        let cases: [(String, String)] = [
            ("photos.example.com", "https://photos.example.com"),
            ("HTTPS://Photos.Example.COM:443/", "https://photos.example.com"),
            ("https://photos.example.com/api/", "https://photos.example.com"),
            ("https://photos.example.com:8443/immich/api", "https://photos.example.com:8443/immich"),
            ("http://192.168.1.5:2283", "http://192.168.1.5:2283"),
            ("http://NAS:80/", "http://nas"),
            ("  http://[FD00::1]:2283/  ", "http://[fd00::1]:2283"),
        ]
        for (typed, normalized) in cases {
            #expect(try Self.address(typed).normalized == normalized, "\(typed)")
        }
        #expect(ServerAddress.parse("ftp://photos.example.com") == .failure(.unsupportedScheme))
        #expect(ServerAddress.parse("mailto:me@example.com") == .failure(.unsupportedScheme))
        #expect(ServerAddress.parse("") == .failure(.empty))
        #expect(ServerAddress.parse("https://user:pw@photos.example.com") == .failure(.invalid))
        #expect(ServerAddress.parse("https://photos.example.com/?x=1") == .failure(.invalid))
        #expect(try Self.address("https://photos.example.com:8443/immich").apiBaseURL.absoluteString
            == "https://photos.example.com:8443/immich/api")
    }

    // MARK: Transport policy (R5, AC3)

    @Test("Plain http only to the local network, and only once confirmed (AC3)")
    func transportPolicy() throws {
        for local in ["http://192.168.1.5", "http://nas.local", "http://nas", "http://10.0.0.2:2283", "http://172.20.1.1",
                      "http://127.0.0.1:8080", "http://localhost", "http://[fd12::5]", "http://[fe80::1]", "http://169.254.3.4"] {
            let address = try Self.address(local)
            #expect(TransportPolicy.of(address) == .unencryptedLocal, "\(local)")
            #expect(throws: RemoteError.transportRefused(host: address.host)) {
                try RemoteHTTPSession(connection: RemoteConnection(address: address, key: "k"))
            }
            _ = try RemoteHTTPSession(connection: RemoteConnection(address: address, key: "k", unencryptedConfirmed: true))
        }
        for remote in ["http://example.com", "http://8.8.8.8", "http://172.32.0.1", "http://[2001:db8::1]",
                       "http://nas.example.com"] {
            let address = try Self.address(remote)
            #expect(TransportPolicy.of(address) == .refused(host: address.host), "\(remote)")
            #expect(throws: RemoteError.transportRefused(host: address.host)) {
                try RemoteHTTPSession(connection: RemoteConnection(address: address, key: "k", unencryptedConfirmed: true))
            }
        }
        #expect(TransportPolicy.of(try Self.address("https://example.com")) == .encrypted)
    }

    // MARK: Certificates (R6, AC4)

    /// Two self-signed certificates for "photos.lan" (made with openssl for
    /// this test; never trusted by the system).
    static let certificateA = "MIIBTDCB86ADAgECAgEBMAoGCCqGSM49BAMCMBUxEzARBgNVBAMMCnBob3Rvcy5sYW4wIBcNMjYxMTI0MDMxODU3WhgPMjEyNjEwMzEwMzE4NTdaMBUxEzARBgNVBAMMCnBob3Rvcy5sYW4wWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAR0rbloy4km9P4dlPI8ddbM+pFSqXIg0MF7ZTbpDoJHN8nPw3PT01KKSLciMqclf1630jzzuIbIqlP8tKACj+kSozIwMDAdBgNVHQ4EFgQUI7tqOeDNZTtZR0Y34oGOuAhroj8wDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNIADBFAiBzs0FL/9zurr8KHZQgT93ZrJLDl0DcZNVMbTQvlmUdEQIhAKCAm0SqLK/sSFju+CJRJR8/TJQEe9jFvWpAYDl3isrV"

    static func certificate(_ base64: String) throws -> SecCertificate {
        let data = try #require(Data(base64Encoded: base64))
        return try #require(SecCertificateCreateWithData(nil, data as CFData))
    }

    static func trust(_ certificate: SecCertificate) throws -> SecTrust {
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "photos.lan" as CFString), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }

    @Test("Fingerprints are shown in two lines of 16 pairs and stored as hexadecimal")
    func fingerprintFormats() throws {
        let fingerprint = CertificateFingerprint(certificateData: Data("x".utf8))
        #expect(fingerprint.hex.count == 64)
        #expect(CertificateFingerprint(hex: fingerprint.hex) == fingerprint)
        #expect(CertificateFingerprint(hex: fingerprint.colonSeparated) == fingerprint)
        #expect(CertificateFingerprint(hex: "00") == nil)
        let lines = fingerprint.displayLines
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.count == 16 * 2 + 14 + 2 })
        #expect(lines[0].contains("  "))
        #expect(fingerprint.colonSeparated.split(separator: ":").count == 32)
        #expect(fingerprint.spokenGroups.split(separator: " ").count == 16)
    }
}

/// Requests and the check against the fake server.
@Suite("Immich check and allowlist")
struct RemoteCheckTests {
    @Test("Each failure of the check has its own result (AC2)")
    func sevenResults() async throws {
        let server = try await FakeImmichServer()
        // Passes with exactly the five permissions, and with more.
        guard case .passed(let info) = try await RemoteConnectionTests.client(server).check() else {
            Issue.record("expected a pass")
            return
        }
        #expect(info.version == ImmichVersion(3, 4, 2))
        #expect(!info.hasMoreThanNeeded)
        #expect(info.ownerID == FakeImmichServer.ownerID)
        #expect(ImmichClient.neededPermissions == ["asset.read", "asset.view", "asset.download", "album.read", "user.read"])
        server.setPermissions(ImmichClient.neededPermissions + ["asset.delete", "server.about"])
        guard case .passed(let more) = try await RemoteConnectionTests.client(server).check() else {
            Issue.record("a key with more permissions passes (R3)")
            return
        }
        #expect(more.hasMoreThanNeeded)
        #expect(more.ownerID == FakeImmichServer.ownerID)
        server.setPermissions(["all"])
        #expect(try await RemoteConnectionTests.client(server).check().kind == "passed")

        // A key missing each permission names that one; user.read too, with
        // no fallback that lists photos unfiltered (RI-E1).
        for permission in ImmichClient.neededPermissions {
            server.setPermissions(ImmichClient.neededPermissions.filter { $0 != permission })
            #expect(try await RemoteConnectionTests.client(server).check() == .missingPermissions([permission]))
        }
        server.setPermissions(["asset.read"])
        #expect(try await RemoteConnectionTests.client(server).check()
            == .missingPermissions(["asset.view", "asset.download", "album.read", "user.read"]))
        server.setPermissions(ImmichClient.neededPermissions)

        // A rejected key.
        #expect(try await RemoteConnectionTests.client(server, key: "wrong").check() == .keyRejected)
        // Too old, with both versions.
        server.setVersion(3, 1, 9)
        #expect(try await RemoteConnectionTests.client(server).check()
            == .tooOld(found: ImmichVersion(3, 1, 9), needed: ImmichVersion(3, 2, 0)))
        server.setVersion(3, 2, 0)
        #expect(try await RemoteConnectionTests.client(server).check().kind == "passed")
        // Not Immich.
        server.add(.notImmich)
        #expect(try await RemoteConnectionTests.client(server).check() == .notImmich)
        server.clearFaults()
        // Unreachable: nothing listens at the port any more.
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        let result = try await RemoteConnectionTests.client(server, timeout: 2).check()
        guard case .unreachable(_, let isLocal) = result else {
            Issue.record("expected unreachable, got \(result)")
            return
        }
        #expect(isLocal)
    }

    @Test("A certificate the system does not trust is offered, a pinned one passes, another fails (AC4)")
    func certificates() throws {
        let certificate = try RemoteConnectionTests.certificate(RemoteConnectionTests.certificateA)
        let summary = CertificateSummary(certificate)
        #expect(summary.subject == "photos.lan")
        #expect(summary.issuer == "photos.lan")
        #expect(summary.notBefore != nil && summary.notAfter != nil)
        let decision = TrustDecision.decide(trust: try RemoteConnectionTests.trust(certificate), host: "photos.lan",
                                            pinned: nil)
        #expect(decision == .untrusted(summary))
        #expect(!decision.accepts)
        let pinned = TrustDecision.decide(trust: try RemoteConnectionTests.trust(certificate), host: "photos.lan",
                                          pinned: summary.fingerprint)
        #expect(pinned == .pinned && pinned.accepts)
        let other = CertificateFingerprint(certificateData: Data("another certificate".utf8))
        let changed = TrustDecision.decide(trust: try RemoteConnectionTests.trust(certificate), host: "photos.lan",
                                           pinned: other)
        #expect(changed == .changed(summary) && !changed.accepts)
    }

    @Test("No code path turns certificate checking off (AC4)")
    func noTrustBypass() throws {
        let source = try String(contentsOf: RepositoryFiles.url("Sources/PhotoCore/Remote/RemoteHTTPSession.swift"),
                                encoding: .utf8)
        for bypass in ["NSAllowsArbitraryLoads", "allowsAnyCertificate", "SecTrustSetExceptions",
                       "kSecTrustResultProceed", "performDefaultHandling"] {
            #expect(!source.contains(bypass), "\(bypass)")
        }
        let plist = try String(contentsOf: RepositoryFiles.url("Support/Info.plist"), encoding: .utf8)
        #expect(!plist.contains("NSAllowsArbitraryLoads"))
        #expect(plist.contains("NSAllowsLocalNetworking"))
        #expect(plist.contains("NSLocalNetworkUsageDescription"))
        let importerPlist = try String(contentsOf: RepositoryFiles.url("Support/Importer-Info.plist"), encoding: .utf8)
        #expect(!importerPlist.contains("NSAppTransportSecurity"))
    }

    @Test("Only the allowlisted read requests reach the server; nothing else is sent (AC5)")
    func allowlist() async throws {
        let server = try await FakeImmichServer()
        server.setAssets(try FakeImmichServer.jpegAssets(count: 2))
        server.setAlbums([FakeImmichServer.Album(name: "Trip", assetCount: 2)])
        let client = try RemoteConnectionTests.client(server)
        _ = await client.check()
        _ = try await client.albums()
        let page = try await client.page(scope: RemoteScope(), cursor: nil, ownerID: FakeImmichServer.ownerID)
        _ = try await client.thumbnail(assetID: page.assets[0].id)
        try await RepositoryFiles.withTemporaryDirectory { folder in
            _ = try await client.download(assetID: page.assets[0].id, to: folder.appending(path: "x.jpg"), limit: RemoteAsset.maximumSize) { _ in }
        }
        // Anything off the list fails before a byte is sent.
        let http = try RemoteHTTPSession(connection: client.connection)
        // No update or delete of anything (issue #28, R9): only publishing's
        // four writes are on the list (`RemoteRequestAllowlist.writes`).
        for (method, path) in [("DELETE", "/assets"), ("PUT", "/assets/abc"), ("PATCH", "/albums/abc"),
                               ("PUT", "/assets"), ("GET", "/server/about"), ("GET", "/assets/abc/original/../x"),
                               ("DELETE", "/albums/abc"), ("PATCH", "/albums/abc"), ("DELETE", "/albums/abc/assets"),
                               ("PUT", "/stacks/abc"), ("DELETE", "/stacks/abc"), ("DELETE", "/stacks"),
                               ("POST", "/albums/abc/assets"), ("PUT", "/albums"), ("POST", "/assets/abc"),
                               ("POST", "/trash/restore"), ("PUT", "/albums/abc/users")] {
            await #expect(throws: RemoteError.notAllowed(method: method, path: path)) {
                _ = try await http.send(method: method, path: path)
            }
        }
        let requests = server.requests
        #expect(!requests.isEmpty)
        for request in requests {
            let path = String(request.path.dropFirst(4))
            #expect(RemoteRequestAllowlist.permits(method: request.method, path: path), "\(request)")
            #expect(!["PUT", "PATCH", "DELETE"].contains(request.method))
            if request.method == "POST" { #expect(path == "/search/metadata") }
            if path.hasSuffix("/original") || path.hasSuffix("/thumbnail") { #expect(request.query.contains("edited=false")) }
            #expect(request.sentKey == (path != "/server/version"))
        }
        #expect(requests.count == 7)
        let writes = RemoteRequestAllowlist.writes.map { "\($0.method) \($0.pattern)" }
        #expect(writes == ["POST ^/assets$", "POST ^/albums$", "PUT ^/albums/[0-9A-Za-z-]{1,64}/assets$", "POST ^/stacks$"])
    }

    @Test("A redirect is not followed, so another host never gets the key (AC5, R7)")
    func redirectNotFollowed() async throws {
        let server = try await FakeImmichServer()
        let other = try await FakeImmichServer()
        server.add(.redirect(location: other.address + "/api/api-keys/me"))
        #expect(try await RemoteConnectionTests.client(server).check() == .notImmich)
        #expect(other.requests.isEmpty)
        #expect(server.requests.map(\.path) == ["/api/server/version", "/api/api-keys/me"])
    }

    @Test("The key is never in a connection's description")
    func keyHidden() throws {
        let connection = RemoteConnection(address: try RemoteConnectionTests.address("https://photos.example.com"),
                                          key: "SECRET-KEY-TEXT")
        for text in [String(describing: connection), String(reflecting: connection), "\(connection)",
                     String(describing: Mirror(reflecting: connection).children.map(\.value))] {
            #expect(!text.contains("SECRET-KEY-TEXT"))
        }
    }

    @Test("The in-memory store keeps keys and fails on demand (AC2's Keychain failure)")
    func keyStore() throws {
        let store = InMemoryKeyStore()
        try store.setKey("k1", account: "a")
        #expect(try store.key(account: "a") == "k1")
        try store.deleteKey(account: "a")
        #expect(try store.key(account: "a") == nil)
        store.failing = true
        #expect(throws: RemoteKeyStoreError.self) { try store.setKey("k", account: "a") }
        #expect(throws: RemoteKeyStoreError.self) { _ = try store.key(account: "a") }
        #expect(KeychainKeyStore.service(bundleIdentifier: "com.example.copy") == "com.example.copy.servers")
        #expect(KeychainKeyStore.service(bundleIdentifier: "com.example.copy")
            != KeychainKeyStore.service(bundleIdentifier: AppBranding.bundleIdentifier))
        // An item already gone is a successful delete; a Deny is a refusal (DQ-5).
        #expect(KeychainKeyStore.deleted(errSecSuccess) && KeychainKeyStore.deleted(errSecItemNotFound))
        #expect(!KeychainKeyStore.deleted(errSecAuthFailed) && !KeychainKeyStore.deleted(errSecUserCanceled))
        // The system's text loses one final period inside a sentence.
        #expect(RemoteKeyStoreError.inSentence("The specified item could not be found in the keychain. ")
            == "The specified item could not be found in the keychain")
        #expect(RemoteKeyStoreError.inSentence("No period") == "No period")
        #expect(RemoteKeyStoreError.from(errSecItemNotFound).inSentence.hasSuffix(".") == false)
    }

    @Test("Remove Server: a refusing store leaves the row and the key; a key already gone removes the row (DQ-5, R4)")
    func removal() async throws {
        let catalog = try Catalog.makeInMemory()
        let store = InMemoryKeyStore()
        let service = try await catalog.saveRemoteService(RemoteServiceRecord(name: "Home", address: "https://photos.example.com"))
        try store.setKey("k", account: service.uuid)
        store.failing = true
        let refusal = try await catalog.removeRemoteService(service, keys: store)
        #expect(refusal != nil)
        store.failing = false
        #expect(try await catalog.remoteServices().map(\.id) == [service.id])
        #expect(try store.key(account: service.uuid) == "k")
        // Removed: the key, then the row.
        #expect(try await catalog.removeRemoteService(service, keys: store) == nil)
        #expect(try store.key(account: service.uuid) == nil)
        #expect(try await catalog.remoteServices().isEmpty)
        // A key already gone (the store's errSecItemNotFound) still removes the row.
        let other = try await catalog.saveRemoteService(RemoteServiceRecord(name: "Other", address: "https://other.example.com"))
        #expect(try await catalog.removeRemoteService(other, keys: store) == nil)
        #expect(try await catalog.remoteServices().isEmpty)
    }
}
