import Foundation
import GRDB
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

/// Issue #271, the first review's findings: code review C1 to C6 and design
/// review B1 and S2 (docs/features/immich-import/code-review.md, review.md).
@Suite("Immich review fixes")
struct RemoteReviewFixTests {
    /// Reads metadata, and cancels the import's task the first time it is
    /// asked: a Stop that lands after the photo verified, before it is
    /// cataloged (C1).
    final class CancellingReader: MetadataReader {
        let task = Mutex<Task<RemoteImportResult, Never>?>(nil)
        let calls = Mutex(0)

        func metadata(for urls: [URL]) async throws -> [URL: ImageMetadata] {
            if calls.withLock({ $0 += 1; return $0 }) == 1 { task.withLock { $0?.cancel() } }
            return try await ImageIOMetadataReader().metadata(for: urls)
        }
    }

    @Test("A Stop after a photo verified catalogs that photo with its link, leaves no stray file and is no failure (C1)")
    func stopWhileFinishing() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: 3))
            let listed = try await RemoteImportTests.listed(setup)
            let reader = CancellingReader()
            let importer = RemoteImporter(catalog: setup.catalog, sidecars: nil, source: setup.client,
                                          metadataReader: reader, retry: .none)
            // The import waits until the reader holds its task (C17).
            let (gate, open) = AsyncStream<Void>.makeStream()
            let task = Task {
                for await _ in gate { break }
                return await importer.run(listed, options: RemoteImportTests.options(root, setup))
            }
            reader.task.withLock { $0 = task }
            open.yield()
            open.finish()
            let result = await task.value
            #expect(result.stop == .stopped)
            #expect(result.failures.isEmpty)
            #expect(result.imported == 1)
            // The library learns the project even so (C15).
            #expect(result.project?.name == "Home - All Photos")
            let files = RemoteImportTests.files(in: root)
            #expect(files == ["Photos/" + listed[0].fileName])
            let links = try await setup.catalog.database.read { db in try RemoteLinkRecord.fetchCount(db) }
            let images = try await setup.catalog.database.read { db in try ImageRecord.fetchCount(db) }
            #expect(links == 1 && images == 1)
        }
    }

    @Test("A catalog error after the move removes the moved file and reports a real reason (C1, C13)")
    func catalogErrorAfterMove() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: 1))
            // Everything up to the move works (volume, project, import run,
            // duplicate check); the master's insert, after the move, fails.
            try await setup.catalog.database.write { db in
                try db.execute(sql: """
                    CREATE TEMP TRIGGER refuseImage BEFORE INSERT ON image
                    BEGIN SELECT RAISE(ABORT, 'the test refuses this insert'); END
                    """)
            }
            let result = await RemoteImportTests.importer(setup).run(try await RemoteImportTests.listed(setup),
                                                                     options: RemoteImportTests.options(root, setup))
            #expect(result.imported == 0 && result.stop == nil)
            #expect(result.failures.count == 1)
            if case .disk(let reason)? = result.failures.first?.kind {
                #expect(reason.contains("the test refuses this insert"))
                #expect(!reason.contains("CancellationError"))
            } else {
                Issue.record("a disk failure was expected")
            }
            // The project and run were made before the move; the file is gone.
            #expect(RemoteImportTests.files(in: root).isEmpty)
            let images = try await setup.catalog.database.read { db in try ImageRecord.fetchCount(db) }
            #expect(images == 0)
        }
    }

    @Test("The server's rating and description reach both files of a RAW+JPEG pair (C2)")
    func pairGetsServerValues() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let dng = root.appending(path: "IMG_0200.DNG")
            try SyntheticDNG.write(to: dng, options: .init(width: 400, height: 300, seed: 11,
                                                           dateTimeOriginal: "2026:10:02 10:00:00"))
            let jpeg = root.appending(path: "IMG_0200.JPG")
            try SyntheticImages.writeJPEG(to: jpeg, width: 64, height: 48, seed: 12,
                                          exif: .init(dateTimeOriginal: "2026:10:02 10:00:00"))
            let taken = Date(timeIntervalSince1970: 1_790_935_200)
            // The RAW is listed first (later by a second), unrated; the JPEG is rated 4 with a description.
            let raw = FakeImmichServer.Asset(fileName: "IMG_0200.DNG", data: try Data(contentsOf: dng),
                                             takenAt: taken.addingTimeInterval(1))
            let companion = FakeImmichServer.Asset(fileName: "IMG_0200.JPG", data: try Data(contentsOf: jpeg),
                                                   description: "Beach", rating: 4, takenAt: taken)
            let setup = try await RemoteImportTests.setup(assets: [raw, companion])
            let listed = try await RemoteImportTests.listed(setup)
            #expect(listed.map(\.fileName) == ["IMG_0200.DNG", "IMG_0200.JPG"])
            let result = await RemoteImportTests.importer(setup).run(listed, options: RemoteImportTests.options(root, setup))
            #expect(result.imported == 2)
            let rows = try await setup.catalog.database.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT image.fileName, image.caption, version.rating FROM image JOIN version ON version.imageId = image.id
                    ORDER BY image.fileName
                    """).map { (name: $0[0] as String, caption: $0[1] as String?, rating: $0[2] as Int) }
            }
            #expect(rows.map(\.name) == ["IMG_0200.DNG", "IMG_0200.JPG"])
            #expect(rows.allSatisfy { $0.rating == 4 && $0.caption == "Beach" })
            let pairs = try await setup.catalog.database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM imagePair") }
            #expect(pairs == 1)
        }
    }

    @Test("Sizes the server reports are checked: negative or huge ones are not believed, and none crash (C3)")
    func insaneSizes() async throws {
        #expect(RemoteAsset.saneSize(-1) == nil)
        #expect(RemoteAsset.saneSize(Int64.max) == nil)
        #expect(RemoteAsset.saneSize(RemoteAsset.maximumSize) == RemoteAsset.maximumSize)
        #expect(RemoteAsset.saneSize(0) == 0)
        for size in ["9223372036854775807", "-5"] {
            let json = """
                {"id":"a","type":"IMAGE","originalFileName":"a.jpg","checksum":"x","fileCreatedAt":"2026-01-01T00:00:00.000Z",
                 "ownerId":"me","visibility":"timeline","exifInfo":{"fileSizeInByte":\(size)}}
                """
            let asset = try JSONDecoder().decode(ImmichDTO.Asset.self, from: Data(json.utf8))
            #expect(asset.remoteAsset(ownerID: "me")?.byteCount == nil)
        }
        // Built by hand past the decoder, two Int64.max sizes import without a trap.
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: 2))
            let huge = try await RemoteImportTests.listed(setup).map { asset in
                var asset = asset
                asset.byteCount = Int64.max
                return asset
            }
            let result = await RemoteImportTests.importer(setup).run(huge, options: RemoteImportTests.options(root, setup))
            #expect(result.imported == 2)
        }
    }

    @Test("Answers are capped: an endless /server/version is not Immich, a long album list fails, an original past its size stops (C4)")
    func caps() async throws {
        #expect(ImmichEndpoint.serverVersion.maximumResponseSize == 64 << 10)
        #expect(ImmichEndpoint.search(Data()).maximumResponseSize == 32 << 20)
        #expect(ImmichEndpoint.thumbnail(assetID: "a").maximumResponseSize == 16 << 20)
        let server = try await FakeImmichServer()
        server.add(.huge(path: "/server/version", bytes: 200 << 10))
        #expect(try await RemoteConnectionTests.client(server).check() == .notImmich)
        server.clearFaults()
        server.add(.huge(path: "/albums", bytes: 17 << 20))
        await #expect(throws: RemoteError.tooLarge) { _ = try await RemoteConnectionTests.client(server).albums() }
        server.clearFaults()

        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: 2))
            let listed = try await RemoteImportTests.listed(setup)
            setup.server.add(.oversize(listed[0].id))
            let result = await RemoteImportTests.importer(setup).run(listed, options: RemoteImportTests.options(root, setup))
            #expect(result.imported == 1)
            #expect(result.failures == [RemoteImportFailure(name: listed[0].fileName, kind: .incomplete)])
            #expect(RemoteImportTests.files(in: root) == ["Photos/" + listed[1].fileName])
        }
    }

    @Test("Numeric hosts are read as the system reads them: 8.8.8.8 in any form is refused (C5, AC3)")
    func numericHosts() throws {
        for refused in ["http://134744072", "http://0x08080808", "http://8.8.8.8", "http://010.010.010.010",
                        "http://08", "http://0x", "http://8.8.2056"] {
            let address = try RemoteConnectionTests.address(refused)
            #expect(TransportPolicy.of(address) == .refused(host: address.host), "\(refused)")
        }
        for local in ["http://2130706433", "http://0x7f000001", "http://10.1", "http://012.0.0.1", "http://192.168.1.5",
                      "http://3232235781"] {
            let address = try RemoteConnectionTests.address(local)
            #expect(TransportPolicy.of(address) == .unencryptedLocal, "\(local)")
        }
        // Names that only start like numbers are names.
        #expect(LocalNetwork.isLocal(host: "nas"))
        #expect(LocalNetwork.isLocal(host: "nas2"))
        #expect(!LocalNetwork.looksNumeric("1nas"))
    }

    @Test("A test launch never uses the Keychain, and there is no fallback to the release service (C6)")
    func keyStoreForLaunch() {
        let plain = LaunchOptions(arguments: ["app", "--library-root", "/tmp/x"])
        let scripted = LaunchOptions(arguments: ["app", "--library-root", "/tmp/x", "--debug-script", "quit"])
        #expect(RemoteKeyStores.usesMemory(bundleIdentifier: nil, options: plain))
        #expect(RemoteKeyStores.usesMemory(bundleIdentifier: AppBranding.bundleIdentifier, options: scripted))
        #expect(!RemoteKeyStores.usesMemory(bundleIdentifier: AppBranding.bundleIdentifier, options: plain))
        #expect(RemoteKeyStores.forLaunch(bundleIdentifier: nil, options: plain) is InMemoryKeyStore)
        let copy = RemoteKeyStores.forLaunch(bundleIdentifier: "com.example.copy", options: plain) as? KeychainKeyStore
        #expect(copy?.service == "com.example.copy.servers")
    }

    @Test("A certificate trusted in Edit is a change that is checked and saved (design review B1)")
    func trustedPendingIsAChange() {
        let https = ServerFormRules.addressState("https://photos.lan")
        #expect(!ServerFormRules.canSubmit(address: https, keyEntered: false, unencryptedConfirmed: false, nameTaken: false,
                                           isEdit: true, changed: false))
        #expect(ServerFormRules.canSubmit(address: https, keyEntered: false, unencryptedConfirmed: false, nameTaken: false,
                                          isEdit: true, changed: false, trustedPending: true))
        #expect(ServerFormRules.needsCheck(isEdit: true, addressChanged: false, keyEntered: false, trustedPending: true))
        #expect(!ServerFormRules.needsCheck(isEdit: true, addressChanged: false, keyEntered: false))
    }

    @Test("The Server sheet's height follows its content and the window (design review S2)")
    func sheetHeight() {
        #expect(ServerSheetHeight.ideal(certificatePage: false, changed: false, notice: false, result: false,
                                        windowHeight: nil) == 380)
        #expect(ServerSheetHeight.ideal(certificatePage: false, changed: false, notice: true, result: true,
                                        windowHeight: 2000) == 530)
        #expect(ServerSheetHeight.ideal(certificatePage: false, changed: false, notice: true, result: false,
                                        windowHeight: 400) == 360)
        #expect(ServerSheetHeight.ideal(certificatePage: true, changed: true, notice: false, result: false,
                                        windowHeight: 200) == ServerSheetHeight.minimum)
        #expect(ServerSheetHeight.ideal(certificatePage: true, changed: false, notice: false, result: false,
                                        windowHeight: 1000) == 470)
    }

    // MARK: Second pass

    static func pairAssets(_ root: URL, rawDescription: String?, jpegDescription: String?, jpegFirst: Bool) throws
        -> [FakeImmichServer.Asset] {
        let dng = root.appending(path: "IMG_0300.DNG")
        try SyntheticDNG.write(to: dng, options: .init(width: 400, height: 300, seed: 21,
                                                       dateTimeOriginal: "2026:10:03 10:00:00"))
        let jpeg = root.appending(path: "IMG_0300.JPG")
        try SyntheticImages.writeJPEG(to: jpeg, width: 64, height: 48, seed: 22,
                                      exif: .init(dateTimeOriginal: "2026:10:03 10:00:00"))
        let taken = Date(timeIntervalSince1970: 1_791_021_600)
        // Newest first: the one taken a second later is listed first.
        let raw = FakeImmichServer.Asset(fileName: "IMG_0300.DNG", data: try Data(contentsOf: dng),
                                         description: rawDescription, takenAt: jpegFirst ? taken : taken.addingTimeInterval(1))
        let companion = FakeImmichServer.Asset(fileName: "IMG_0300.JPG", data: try Data(contentsOf: jpeg),
                                               description: jpegDescription, rating: 4,
                                               takenAt: jpegFirst ? taken.addingTimeInterval(1) : taken)
        return [raw, companion]
    }

    static func pairRows(_ catalog: Catalog) async throws -> [(name: String, caption: String?, rating: Int)] {
        try await catalog.database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT image.fileName, image.caption, version.rating FROM image JOIN version ON version.imageId = image.id
                ORDER BY image.fileName
                """).map { (name: $0[0] as String, caption: $0[1] as String?, rating: $0[2] as Int) }
        }
    }

    @Test("A pair's description agrees with the companion listed first, and with two server descriptions (C12)")
    func pairCaptionEitherOrder() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let assets = try Self.pairAssets(root, rawDescription: nil, jpegDescription: "Beach", jpegFirst: true)
            let setup = try await RemoteImportTests.setup(assets: assets)
            let listed = try await RemoteImportTests.listed(setup)
            #expect(listed.map(\.fileName) == ["IMG_0300.JPG", "IMG_0300.DNG"])
            let result = await RemoteImportTests.importer(setup).run(listed, options: RemoteImportTests.options(root, setup))
            #expect(result.imported == 2)
            let rows = try await Self.pairRows(setup.catalog)
            #expect(rows.count == 2 && rows.allSatisfy { $0.caption == "Beach" && $0.rating == 4 })
            let versions = try await setup.catalog.database.read { db in try Int64.fetchAll(db, sql: "SELECT id FROM version") }
            #expect(try await setup.catalog.descriptiveSummary(forVersions: versions).mixed.isEmpty)
        }
        try await RepositoryFiles.withTemporaryDirectory { root in
            let assets = try Self.pairAssets(root, rawDescription: "Sunset", jpegDescription: "Beach", jpegFirst: false)
            let setup = try await RemoteImportTests.setup(assets: assets)
            let result = await RemoteImportTests.importer(setup).run(try await RemoteImportTests.listed(setup),
                                                                     options: RemoteImportTests.options(root, setup))
            #expect(result.imported == 2)
            // The first to land gave the pair its description; the second, empty, took it.
            let rows = try await Self.pairRows(setup.catalog)
            #expect(rows.allSatisfy { $0.caption == "Sunset" })
        }
    }

    @Test("Images of a pair that already hold different descriptions keep them (C12)")
    func pairCaptionsKept() async throws {
        let catalog = try Catalog.makeInMemory()
        let volume = try await catalog.registerVolume(VolumeDescriptor(identity: "V", name: "V", mountPath: "/Volumes/V"))
        let project = try await catalog.createProject(name: "P")
        func master(_ name: String, _ caption: String?, hash: String) -> NewMaster {
            var metadata = ImageMetadata(captureDate: Date(timeIntervalSince1970: 1_700_000_000))
            metadata.caption = caption
            return NewMaster(relativePath: "shoot/\(name)", fileSize: 10, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                             contentHash: hash, metadata: metadata)
        }
        let inserted = try await catalog.insertMasters([master("IMG_1.CR3", "Raw's", hash: "a"), master("IMG_1.JPG", "Jpeg's", hash: "b")],
                                                       volumeID: try #require(volume.id), projectID: try #require(project.id))
        #expect(inserted.pairsCreated == 1)
        let version = try #require(inserted.insertedVersionIDs.last)
        try await catalog.database.write { db in try Catalog.fillPairCaption(db, versionID: version, serverDescription: "Server's") }
        let captions = try await catalog.database.read { db in try String.fetchAll(db, sql: "SELECT caption FROM image ORDER BY fileName") }
        #expect(captions == ["Raw's", "Jpeg's"])
    }

    @Test("Names with format characters are listed; control characters are not (C14)")
    func formatCharacters() throws {
        for name in ["Family \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}.jpg", "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}.jpg",
                     "\u{200F}name.jpg", "soft\u{00AD}hyphen.jpg", "a..b.jpg"] {
            #expect(RemoteAsset.isPlainFileName(name), "\(name)")
            let json = try JSONSerialization.data(withJSONObject: [
                "id": "a", "type": "IMAGE", "originalFileName": name, "checksum": "x",
                "fileCreatedAt": "2026-01-01T00:00:00.000Z", "ownerId": "me", "visibility": "timeline",
            ])
            #expect(try JSONDecoder().decode(ImmichDTO.Asset.self, from: json).remoteAsset(ownerID: "me") != nil, "\(name)")
        }
        for name in ["a\u{0}.jpg", "a\u{7}.jpg", "a\u{1B}.jpg", "a\u{85}.jpg", ".", "..", "", "a/b.jpg", "a\\b.jpg"] {
            #expect(!RemoteAsset.isPlainFileName(name), "\(name)")
        }
    }

    @Test("Bodies without a length are capped while they stream (C16)")
    func streamingCaps() async throws {
        let server = try await FakeImmichServer()
        server.add(.chunked)
        server.add(.huge(path: "/albums", bytes: 17 << 20))
        await #expect(throws: RemoteError.tooLarge) { _ = try await RemoteConnectionTests.client(server).albums() }
        server.clearFaults()
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: 2))
            let listed = try await RemoteImportTests.listed(setup)
            setup.server.add(.chunked)
            setup.server.add(.oversize(listed[0].id))
            // The download itself stops at its limit while it streams (C19):
            // no more than the limit is ever written, and the file goes.
            let limit = try #require(listed[0].byteCount)
            let file = root.appending(path: "download.jpg")
            let written = Mutex<Int64>(0)
            await #expect(throws: RemoteError.tooLarge) {
                _ = try await setup.client.download(assetID: listed[0].id, to: file, limit: limit) { bytes in
                    written.withLock { $0 += bytes }
                }
            }
            #expect(written.withLock { $0 } <= limit)
            #expect(!FileManager.default.fileExists(atPath: file.path))
            // And the import reports that photo as incomplete.
            let result = await RemoteImportTests.importer(setup).run(listed, options: RemoteImportTests.options(root, setup))
            #expect(result.imported == 1)
            #expect(result.failures == [RemoteImportFailure(name: listed[0].fileName, kind: .incomplete)])
            #expect(RemoteImportTests.files(in: root) == ["Photos/" + listed[1].fileName])
        }
    }

    @Test("A trusted certificate is used only for the address it was trusted for (design review N-3)")
    func pinFollowsAddress() throws {
        let fingerprint = CertificateFingerprint(certificateData: Data("new".utf8))
        let old = CertificateFingerprint(certificateData: Data("old".utf8))
        let trusted = ServerFormRules.TrustedCertificate(fingerprint: fingerprint, trustedAt: Date(timeIntervalSince1970: 1),
                                                         address: "https://photos.lan")
        var existing = RemoteServiceRecord(name: "Home", address: "https://photos.lan", certificateFingerprint: old.hex,
                                           certificateTrustedAt: Date(timeIntervalSince1970: 0))
        #expect(ServerFormRules.pin(trusted: trusted, address: "https://photos.lan", existing: existing)?.fingerprint == fingerprint)
        #expect(ServerFormRules.pin(trusted: trusted, address: "https://other.lan", existing: existing) == nil)
        #expect(ServerFormRules.pin(trusted: nil, address: "https://photos.lan", existing: existing)?.fingerprint == old)
        existing.address = "https://moved.lan"
        #expect(ServerFormRules.pin(trusted: nil, address: "https://photos.lan", existing: existing) == nil)
    }
}
