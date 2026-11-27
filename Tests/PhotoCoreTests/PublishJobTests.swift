import CryptoKit
import Foundation
import GRDB
import ImageIO
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

/// Issue #28: publishing runs against `FakeImmichServer`, which behaves as
/// status.md's "Immich verification" records.
@Suite("Publishing runs")
struct PublishJobTests {
    static let publishing = ["asset.upload", "asset.read", "album.read", "albumAsset.create", "album.create",
                             "user.read", "stack.create"]

    struct Fixture {
        let root: URL
        let folder: URL
        let catalog: Catalog
        let server: FakeImmichServer
        let client: ImmichClient
        let service: RemoteServiceRecord
        let temporary: URL

        var address: String { service.address }

        func version(_ fileName: String) async throws -> Int64 {
            let images = try await catalog.allImages()
            let image = try #require(images.first { $0.fileName == fileName })
            let imageID = try #require(image.id)
            let versions = try await catalog.versions(ofImage: imageID)
            return try #require(versions.first { $0.isDefault }?.id)
        }

        func image(_ fileName: String) async throws -> ImageRecord {
            try #require(try await catalog.allImages().first { $0.fileName == fileName })
        }

        func volumeIdentity() async throws -> String {
            try #require(try await catalog.volumes().first?.identity)
        }

        func masterData(_ fileName: String) throws -> Data {
            try Data(contentsOf: folder.appending(path: fileName))
        }

        /// Links `versionID` to the server's `remoteID`, as an import from it would.
        func link(_ versionID: Int64, to remoteID: String) async throws {
            let address = self.address
            let serviceID = service.id
            _ = try await catalog.database.write { db in
                try Catalog.insertLink(db, remoteID: remoteID, fingerprint: "x",
                                       link: RemoteLinkTarget(provider: .immich, address: address, serviceID: serviceID),
                                       versionID: versionID, at: Date())
            }
        }

        /// The name a version's file is uploaded under with `settings`.
        func uploadName(_ versionID: Int64, settings: ExportSettings = ExportSettings()) async throws -> String {
            let item = try #require(try await ExportJob(catalog: catalog, renderer: ExportRenderer()).items(for: [versionID]).first)
            return ExportNaming.fileName(for: item.templateContext(sequence: 1, exportDate: Date()), settings: settings)
        }

        /// The asset ids a stack create named, in order, for each create sent.
        var stackCreates: [[String]] {
            server.requests.filter { $0.method == "POST" && $0.path == "/api/stacks" }.compactMap {
                (try? JSONSerialization.jsonObject(with: $0.body) as? [String: [String]])?["assetIds"]
            }
        }

        func job(stacking: Bool = true, map: [PublishFolderMapping] = [], retry: RemoteRetryPolicy = .none,
                 bound: Duration = .seconds(2), concurrency: Int = 1) -> PublishJob {
            PublishJob(catalog: catalog, renderer: ExportRenderer(), destination: client,
                       accountID: stacking ? FakeImmichServer.ownerID : nil, folderMap: map, retry: retry,
                       endingBound: bound, concurrency: concurrency, temporaryRoot: temporary, timeZone: .gmt)
        }

        func makeRun(_ versionIDs: [Int64], album: PublishAlbumChoice = .none, stacking: Bool = true,
                     visibility: PublishVisibility = .timeline, settings: ExportSettings = ExportSettings(),
                     description: String? = nil) async throws -> PublishRun {
            var items: [PublishItem] = []
            for id in versionIDs {
                let details = try #require(try await catalog.details(forVersion: id))
                items.append(PublishItem(versionID: id, name: details.image.fileName, album: album.usesAlbum,
                                         stacking: stacking))
            }
            return PublishRun(service: service, choices: PublishChoices(settings: settings, album: album,
                                                                        visibility: visibility, stacking: stacking),
                              description: description, items: items)
        }

        /// Writes in the recorded requests, as "METHOD /path".
        var writes: [String] {
            server.requests.filter { $0.method != "GET" && $0.path != "/api/search/metadata" }
                .map { "\($0.method) \(String($0.path.dropFirst(4)))" }
        }

        /// No request of the run was off the allowlist, and every write is one of the four (AC6).
        func expectOnlyAllowedRequests(sourceLocation: SourceLocation = #_sourceLocation) {
            for request in server.requests {
                let path = String(request.path.dropFirst(4))
                #expect(RemoteRequestAllowlist.permits(method: request.method, path: path), "\(request)",
                        sourceLocation: sourceLocation)
                #expect(!["DELETE", "PATCH"].contains(request.method), sourceLocation: sourceLocation)
                if request.method == "PUT" {
                    #expect(path.hasPrefix("/albums/") && path.hasSuffix("/assets"), sourceLocation: sourceLocation)
                }
            }
        }
    }

    /// The client's request timeout: an idle timer URLSession keeps whatever the
    /// load, so it is set far beyond any step on a loaded runner (worst seen on
    /// CI: 7 s). Tests that hold an answer, or end a run at its bound, would
    /// otherwise race it (CI fix, status.md). No test here waits for it to fire.
    static let requestTimeout: TimeInterval = 120

    /// JPEGs in a folder, imported; a stays floating at 2024-05-01 10:00.
    static func fixture(_ root: URL, files: [String] = ["a.jpg", "b.jpg"]) async throws -> Fixture {
        let folder = root.appending(path: "Shoot")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, name) in files.enumerated() {
            let url = folder.appending(path: name)
            if name.uppercased().hasSuffix(".DNG") {
                try SyntheticDNG.write(to: url, options: .init(width: 300, height: 200, seed: UInt64(index + 1)))
            } else {
                try SyntheticImages.writeJPEG(to: url, width: 160, height: 120, seed: UInt64(index + 1),
                                              exif: .init(dateTimeOriginal: "2024:05:0\(index + 1) 10:00:00"))
            }
        }
        let catalog = try Catalog.makeInMemory()
        _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(folder)
        let server = try await FakeImmichServer()
        server.setPermissions(publishing)
        let address = try RemoteConnectionTests.address(server.address)
        let service = try await catalog.saveRemoteService(RemoteServiceRecord(name: "Home", address: address.normalized,
                                                                              allowsUnencrypted: true))
        let client = try RemoteConnectionTests.client(server, timeout: requestTimeout)
        return Fixture(root: root, folder: folder, catalog: catalog, server: server, client: client, service: service,
                       temporary: root.appending(path: "Temporary"))
    }

    static func edit(_ ev: Double) -> EditStack {
        EditStack(operations: [EditOperation(kind: "exposure", parameters: ["ev": .number(ev)])])
    }

    static func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Uploads (R2 to R5, R17, R24)

    @Test("Each photo uploads as its export would be, with only the values publishing names (AC3, AC6, R24)")
    func uploadsAsExported() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg"), b = try await f.version("b.jpg")
            let before = try ["a.jpg", "b.jpg"].map { try Self.sha256(f.folder.appending(path: $0)) }
            var settings = ExportSettings()
            settings.metadata = .all
            let run = await f.job(stacking: false).run(try await f.makeRun([a, b], stacking: false, settings: settings,
                                                                            description: "Typed for this run"))
            #expect(run.ending == .completed)
            #expect(run.counts.published == 2)
            let uploads = f.server.uploads
            #expect(uploads.count == 2)
            #expect(uploads.map { $0.fields["filename"] } == ["a.jpg", "b.jpg"])
            #expect(uploads.map { $0.fields["fileCreatedAt"] } == ["2024-05-01T10:00:00.000Z", "2024-05-02T10:00:00.000Z"])
            #expect(uploads.allSatisfy { $0.fields["fileModifiedAt"] == $0.fields["fileCreatedAt"] })
            #expect(uploads.allSatisfy { $0.fields["visibility"] == "timeline" })
            #expect(uploads.allSatisfy { Set($0.fields.keys) == ["fileCreatedAt", "fileModifiedAt", "filename", "visibility"] })
            #expect(uploads.allSatisfy { $0.partContentType == "image/jpeg" })
            // The pixels and metadata of an export with the same settings and the typed description.
            let item = try #require(try await ExportJob(catalog: f.catalog, renderer: ExportRenderer()).items(for: [a]).first)
            let exported = root.appending(path: "a-export.jpg")
            try ExportRenderer().export(source: item.sourceURL, stack: item.details.version.decodedEditStack(),
                                        values: PublishJob.values(item.values, description: "Typed for this run"),
                                        settings: settings, to: exported, replacing: false)
            #expect(uploads[0].data == (try Data(contentsOf: exported)))
            let xmp = String(decoding: uploads[0].data, as: UTF8.self)
            #expect(xmp.contains("Typed for this run"))
            #expect(!xmp.contains("Rating") && !xmp.contains("xmp:Label"))
            // The library is unchanged, the masters are byte for byte, no file is left.
            #expect(try await f.image("a.jpg").caption == nil)
            #expect(try ["a.jpg", "b.jpg"].map { try Self.sha256(f.folder.appending(path: $0)) } == before)
            #expect((try? FileManager.default.contentsOfDirectory(atPath: f.temporary.path)) ?? [] == [])
            // Each upload is recorded at once, for the server's address.
            let records = try await f.catalog.publications(address: f.address, versionIDs: [a, b])
            #expect(records[a]?.count == 1 && records[b]?.count == 1)
            #expect(records[a]?.first?.answer == .created)
            #expect(records[a]?.first?.remoteId == uploads[0].assetID)
            #expect(f.writes == ["POST /assets", "POST /assets"])
            f.expectOnlyAllowedRequests()
        }
    }

    @Test("An offline original fails only that photo; Archive is set by the upload (AC2, AC4, R6)")
    func offlineAndArchive() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg"), b = try await f.version("b.jpg")
            try FileManager.default.moveItem(at: f.folder.appending(path: "a.jpg"), to: root.appending(path: "away.jpg"))
            let run = await f.job(stacking: false).run(try await f.makeRun([a, b], stacking: false, visibility: .archive))
            let volume = try #require(try await f.catalog.volumes().first?.name)
            #expect(run.items[0].upload == .failed(.offline(volumeName: volume)))
            #expect(run.items[1].isAccepted)
            #expect(f.server.uploads.map { $0.fields["visibility"] } == ["archive"])
            #expect(f.server.asset(try #require(run.items[1].assetID))?.visibility == "archive")
            #expect(run.counts.failed == 1 && run.counts.published == 1)
        }
    }

    // MARK: Stacking (R10 to R15)

    @Test("A linked photo and its virtual copy stack on the linked asset, the later in grid order primary (AC7, AC10)")
    func linkAndCopy() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg")
            let original = FakeImmichServer.Asset(fileName: "a.jpg", data: try f.masterData("a.jpg"), takenAt: Date())
            f.server.addAssets([original])
            _ = try await f.catalog.database.write { db in
                try Catalog.insertLink(db, remoteID: original.id, fingerprint: original.checksum,
                                       link: RemoteLinkTarget(provider: .immich, address: f.address, serviceID: f.service.id),
                                       versionID: a, at: Date())
            }
            let copy = try #require(try await f.catalog.duplicateVersions(ids: [a]).first?.copyVersionID)
            // The copy differs, so its file is not a duplicate of the first.
            try await f.catalog.setEditStack(Self.edit(0.5), forVersion: copy, historyLabel: "Exposure")
            let run = await f.job(concurrency: 2).run(try await f.makeRun([a, copy]))
            #expect(run.items.allSatisfy { $0.stacking == .stacked })
            let first = try #require(run.items[0].assetID), second = try #require(run.items[1].assetID)
            let held = try #require(f.server.stack(of: original.id))
            #expect(held.primary == second)
            #expect(Set(held.members) == [original.id, first, second])
            #expect(run.counts.stacked == 2)
            f.expectOnlyAllowedRequests()
        }
    }

    @Test("Check Originals' tally agrees with the run: found as stacked, each reason as the run's, offline left out (AC12, QA Q2)")
    func originalsTallyMatchesRun() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg", "c.jpg", "d.jpg"])
            let ids = [try await f.version("a.jpg"), try await f.version("b.jpg"), try await f.version("c.jpg"),
                       try await f.version("d.jpg")]
            let original = FakeImmichServer.Asset(fileName: "a.jpg", data: try f.masterData("a.jpg"), takenAt: Date())
            f.server.addAssets([original])
            // a: its original is on the server; c and d: linked to an asset the server no longer has; b: nothing.
            _ = try await f.catalog.database.write { db in
                for (versionID, remoteID) in [(ids[0], original.id), (ids[2], "gone-c"), (ids[3], "gone-d")] {
                    try Catalog.insertLink(db, remoteID: remoteID, fingerprint: "x",
                                           link: RemoteLinkTarget(provider: .immich, address: f.address,
                                                                  serviceID: f.service.id),
                                           versionID: versionID, at: Date())
                }
            }
            let sources = try await f.catalog.publishSources(versionIDs: ids, address: f.address)
            var names: [Int64: String] = [:]
            for id in ids { names[id] = try #require(try await f.catalog.details(forVersion: id)).image.fileName }
            let finder = OriginalFinder(destination: f.client, catalog: f.catalog, address: f.address,
                                        accountID: FakeImmichServer.ownerID, folderMap: [])
            var steps: [Int] = []
            let tally = try #require(try await OriginalsTally.check(ids, offline: [], sources: sources, names: names,
                                                                    find: { source async throws(PublishFailure) in
                                                                        try await finder.find(source)
                                                                    },
                                                                    progress: { done, _ in steps.append(done) }))
            #expect(steps == [1, 2, 3, 4])
            #expect(tally.checked == 4 && tally.offline == 0 && tally.found == 1)
            #expect(tally.groups.map(\.group) == [.noMappedFolder, .importedOriginalNotFound])
            #expect(tally.groups.map { $0.photos.map(\.name) } == [["b.jpg"], ["c.jpg", "d.jpg"]])
            #expect(f.writes.isEmpty, "Check Originals only reads")

            // The run, with the same finder's rule, comes to the same.
            let run = await f.job().run(try await f.makeRun(ids))
            #expect(run.counts.stacked == tally.found)
            var fromRun = OriginalsTally(checked: ids.count, offline: 0)
            for item in run.items {
                switch item.stacking {
                case .stacked?: fromRun.add(.found(assetID: item.assetID ?? ""), name: names[item.versionID] ?? "")
                case .noOriginal(let reason)?: fromRun.add(.none(reason), name: names[item.versionID] ?? "")
                default: Issue.record("\(item.versionID): \(String(describing: item.stacking))")
                }
            }
            #expect(fromRun == tally)

            // Offline photos are counted and not looked for.
            let looked = Mutex(0)
            let partial = try #require(try await OriginalsTally.check(ids, offline: [ids[1], ids[3]], sources: sources,
                                                                      names: names,
                                                                      find: { source async throws(PublishFailure) in
                                                                          looked.withLock { $0 += 1 }
                                                                          return try await finder.find(source)
                                                                      }))
            #expect(partial.checked == 2 && partial.offline == 2 && partial.found == 1)
            #expect(looked.withLock { $0 } == 2)
            #expect(partial.groups.map { $0.photos.map(\.name) } == [["c.jpg"]])
        }
    }

    @Test("Check Originals stops on a failed request and gives nothing when cancelled (AC12, QA Q2)")
    func originalsTallyFailureAndCancel() async throws {
        let source = PublishSource(versionID: 1, imageID: 1, files: [], linkedAssetIDs: [])
        await #expect(throws: PublishFailure.self) {
            _ = try await OriginalsTally.check([1, 2], offline: [], sources: [1: source, 2: source], names: [:],
                                               find: { _ async throws(PublishFailure) in throw .remote(.disk("no")) })
        }
        let started = AsyncStream<Void>.makeStream()
        let task = Task {
            try await OriginalsTally.check([1, 2], offline: [], sources: [1: source, 2: source], names: [:],
                                           find: { _ async throws(PublishFailure) in
                                               started.continuation.yield()
                                               await Self.untilCancelled()
                                               throw .remote(.disk("cancelled"))
                                           })
        }
        for await _ in started.stream { break }
        task.cancel()
        #expect(try await task.value == nil)
    }

    @Test("With stacking off no stack request is sent; a linked asset in the trash falls through to the folder map (AC7)")
    func stackingOffAndFallThrough() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg")
            let image = try await f.image("a.jpg")
            var linked = FakeImmichServer.Asset(fileName: "a.jpg", data: Data([1]), takenAt: Date())
            linked.isTrashed = true
            var external = FakeImmichServer.Asset(fileName: "a.jpg", data: try f.masterData("a.jpg"), takenAt: Date(),
                                                  libraryID: "library")
            external.originalPath = "/mnt/photos/" + image.relativePath.split(separator: "/").last!
            f.server.addAssets([linked, external])
            let linkedID = linked.id
            _ = try await f.catalog.database.write { db in
                try Catalog.insertLink(db, remoteID: linkedID, fingerprint: "x",
                                       link: RemoteLinkTarget(provider: .immich, address: f.address, serviceID: nil),
                                       versionID: a, at: Date())
            }
            _ = await f.job(stacking: false).run(try await f.makeRun([a], stacking: false))
            #expect(!f.writes.contains("POST /stacks"))
            let folder = (image.relativePath as NSString).deletingLastPathComponent
            let map = [PublishFolderMapping(volumeIdentity: try await f.volumeIdentity(), folderPath: folder,
                                            lastKnownPath: f.folder.path, serverPath: "/mnt/photos")]
            // A changed photo, so this is not a duplicate of the first upload.
            try await f.catalog.setEditStack(Self.edit(0.3), forVersion: a, historyLabel: "Exposure")
            let run = await f.job(map: map).run(try await f.makeRun([a]))
            #expect(run.items[0].stacking == .stacked)
            #expect(f.server.stack(of: external.id)?.primary == run.items[0].assetID)
        }
    }

    @Test("The folder map finds the account's own asset beside a partner's, by size and path (AC8)")
    func folderMapOwnBesidePartner() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg")
            let image = try await f.image("a.jpg")
            let path = "/mnt/photos/" + image.fileName
            var own = FakeImmichServer.Asset(fileName: "a.jpg", data: try f.masterData("a.jpg"), takenAt: Date(), libraryID: "l1")
            own.originalPath = path
            var partner = FakeImmichServer.Asset(fileName: "a.jpg", data: try f.masterData("a.jpg"), ownerID: "partner",
                                                 takenAt: Date(), libraryID: "l2")
            partner.originalPath = path
            f.server.addAssets([partner, own])
            let folder = (image.relativePath as NSString).deletingLastPathComponent
            let map = [PublishFolderMapping(volumeIdentity: try await f.volumeIdentity(), folderPath: folder,
                                            lastKnownPath: "", serverPath: "/mnt/photos/")]
            let run = await f.job(map: map).run(try await f.makeRun([a]))
            #expect(run.items[0].stacking == .stacked)
            #expect(f.server.stack(of: own.id)?.members.contains(own.id) == true)
            #expect(f.server.stack(of: partner.id) == nil)
        }
    }

    @Test("A non-primary member's whole stack, but the trashed member, ends under the edit, with no request about the trashed one (AC10)")
    func joinsExistingStack() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg")
            let primary = FakeImmichServer.Asset(fileName: "p.jpg", data: Data([1]), takenAt: Date())
            let original = FakeImmichServer.Asset(fileName: "a.jpg", data: Data([2]), takenAt: Date())
            var trashed = FakeImmichServer.Asset(fileName: "m.jpg", data: Data([3]), takenAt: Date())
            trashed.isTrashed = true
            let member = FakeImmichServer.Asset(fileName: "n.jpg", data: Data([4]), takenAt: Date())
            f.server.addAssets([primary, original, trashed, member])
            f.server.makeStack([primary.id, original.id, trashed.id, member.id])
            _ = try await f.catalog.database.write { db in
                try Catalog.insertLink(db, remoteID: original.id, fingerprint: "x",
                                       link: RemoteLinkTarget(provider: .immich, address: f.address, serviceID: nil),
                                       versionID: a, at: Date())
            }
            let run = await f.job().run(try await f.makeRun([a]))
            let edit = try #require(run.items[0].assetID)
            let stack = try #require(f.server.stack(of: original.id))
            #expect(stack.primary == edit)
            #expect(Set(stack.members) == [edit, primary.id, original.id, member.id])
            #expect(f.server.asset(trashed.id)?.stackID == nil)
            // The create named the edit, the primary as read, and the original.
            let create = try #require(f.server.requests.last { $0.path == "/api/stacks" })
            let named = try #require(try JSONSerialization.jsonObject(with: create.body) as? [String: [String]])["assetIds"]
            #expect(named == [edit, primary.id, original.id])
            #expect(!f.server.requests.contains { $0.path.contains(trashed.id) || $0.path.contains(member.id) })
        }
    }

    @Test("A refused stack is a failure, not \"no original\"; Retry Failed stacks it with no second upload (AC10, AC11)")
    func refusedStackRetried() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg")
            let original = FakeImmichServer.Asset(fileName: "a.jpg", data: Data([2]), takenAt: Date())
            f.server.addAssets([original])
            _ = try await f.catalog.database.write { db in
                try Catalog.insertLink(db, remoteID: original.id, fingerprint: "x",
                                       link: RemoteLinkTarget(provider: .immich, address: f.address, serviceID: nil),
                                       versionID: a, at: Date())
            }
            f.server.add(.refuseStack)
            var run = await f.job().run(try await f.makeRun([a]))
            #expect(run.items[0].stacking == .failed(.stackRefused(message: "Not found or no asset.update access")))
            #expect(run.counts.failed == 1 && run.counts.notStacked == 0)
            #expect(run.retryCandidates == [a])
            f.server.remove(.refuseStack)
            run = await f.job().run(run, retrying: true)
            #expect(run.items[0].stacking == .stacked)
            #expect(f.server.uploads.count == 1)
            #expect(f.server.stack(of: original.id)?.primary == run.items[0].assetID)
            #expect(run.counts.failed == 0 && run.counts.stacked == 1)
        }
    }

    @Test("No original: published unstacked with the reason (AC9)")
    func noOriginalReasons() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg"), b = try await f.version("b.jpg")
            let image = try await f.image("b.jpg")
            let folder = (image.relativePath as NSString).deletingLastPathComponent
            let map = [PublishFolderMapping(volumeIdentity: try await f.volumeIdentity(), folderPath: folder,
                                            lastKnownPath: "", serverPath: "/mnt/x")]
            // a: linked to an asset the server doesn't return; b: nothing at its path.
            _ = try await f.catalog.database.write { db in
                try Catalog.insertLink(db, remoteID: "gone", fingerprint: "x",
                                       link: RemoteLinkTarget(provider: .immich, address: f.address, serviceID: nil),
                                       versionID: a, at: Date())
            }
            let run = await f.job(map: map).run(try await f.makeRun([a, b]))
            #expect(run.items[0].stacking == .noOriginal(.linkedNotReturned(path: "/mnt/x/a.jpg")))
            #expect(run.items[1].stacking == .noOriginal(.nothingAtPath("/mnt/x/b.jpg")))
            #expect(run.counts.notStacked == 2 && run.counts.published == 2 && run.counts.failed == 0)
        }
    }

    // MARK: Already on the server (R19)

    @Test("An identical file is already on the server: recorded, read first, then albumed and stacked (AC14)")
    func duplicateUsable() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg")
            let album = FakeImmichServer.Album(name: "Kept", assetCount: 0)
            f.server.setAlbums([album])
            _ = await f.job(stacking: false).run(try await f.makeRun([a], stacking: false))
            f.server.clearRequests()
            let run = await f.job(stacking: false).run(try await f.makeRun([a], album: .existing(id: album.id, name: "Kept"),
                                                                            stacking: false))
            #expect(run.items[0].upload == .accepted(.duplicate(try #require(f.server.uploads.first?.assetID))))
            #expect(run.items[0].check == .usable && run.items[0].album == .done)
            #expect(run.counts.alreadyOnServer == 1 && run.counts.published == 0)
            let paths = f.server.requests.map { "\($0.method) \($0.path)" }
            let read = try #require(paths.firstIndex { $0.hasPrefix("GET /api/assets/") })
            let added = try #require(paths.firstIndex { $0.hasPrefix("PUT /api/albums/") })
            #expect(read < added)
            #expect(try await f.catalog.publications(address: f.address, versionIDs: [a])[a]?.map(\.answer) == [.created, .duplicate])
            // Adding it again is no failure (R22).
            let again = await f.job(stacking: false).run(try await f.makeRun([a], album: .existing(id: album.id, name: "Kept"),
                                                                              stacking: false))
            #expect(again.items[0].album == .done && again.counts.failed == 0)
        }
    }

    @Test("A trashed, hidden or unreadable duplicate is reported and left alone (AC14, RI-V6)")
    func duplicateLeftAlone() async throws {
        for (change, reason) in [({ (asset: inout FakeImmichServer.Asset) in asset.isTrashed = true }, AlreadyThereReason.inTrash),
                                 ({ $0.visibility = "hidden" }, .hidden), ({ $0.visibility = "locked" }, .unreadable)] {
            try await RepositoryFiles.withTemporaryDirectory { root in
                let f = try await Self.fixture(root)
                let a = try await f.version("a.jpg")
                let album = FakeImmichServer.Album(name: "Kept", assetCount: 0)
                f.server.setAlbums([album])
                let first = await f.job(stacking: false).run(try await f.makeRun([a], stacking: false))
                f.server.update(try #require(first.items[0].assetID), change)
                f.server.clearRequests()
                let run = await f.job().run(try await f.makeRun([a], album: .existing(id: album.id, name: "Kept")))
                #expect(run.items[0].alreadyThere == reason)
                #expect(!f.server.requests.contains { $0.method == "PUT" || $0.path == "/api/stacks" })
                #expect(run.counts.alreadyThere[reason] == 1 && run.counts.failed == 0 && !run.offersRetry)
            }
        }
    }

    @Test("A read that fails for a temporary condition leaves the steps unfinished; Retry Failed completes them (AC14)")
    func duplicateReadFailsThenRetried() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg")
            let album = FakeImmichServer.Album(name: "Kept", assetCount: 0)
            f.server.setAlbums([album])
            _ = await f.job(stacking: false).run(try await f.makeRun([a], stacking: false))
            f.server.add(.answer(method: "GET", path: "/assets/", status: 503, times: 1))
            var run = await f.job(stacking: false).run(try await f.makeRun([a], album: .existing(id: album.id, name: "Kept"),
                                                                            stacking: false))
            #expect(run.items[0].check == .failed(.checkFailed(.server(status: 503, message: "Status 503"))))
            #expect(run.items[0].album == .pending)
            #expect(run.ending == .stopped(.unreachable))
            run = await f.job(stacking: false).run(run, retrying: true)
            #expect(run.items[0].check == .usable && run.items[0].album == .done)
            #expect(f.server.uploads.count == 2)
        }
    }

    // MARK: Albums (R6, R22)

    @Test("A new album is made with the first photo; a second run into it makes no second album (AC4)")
    func newAlbum() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg"), b = try await f.version("b.jpg")
            let run = await f.job(stacking: false).run(try await f.makeRun([a, b], album: .new(name: "Iceland"), stacking: false))
            guard case .ready(let id, "Iceland", true) = run.album else {
                Issue.record("the run made its album: \(run.album)")
                return
            }
            #expect(f.server.albums.count == 1)
            #expect(Set(f.server.albums[0].assetIDs) == Set(run.items.compactMap(\.assetID)))
            _ = await f.job(stacking: false).run(try await f.makeRun([a], album: .existing(id: id, name: "Iceland"), stacking: false))
            #expect(f.server.albums.count == 1)
            #expect(f.writes.filter { $0 == "POST /albums" }.count == 1)
        }
    }

    @Test("A lost answer to the create makes one album, never the older one of the same name, also on Retry Failed (AC24)")
    func lostAlbumCreate() async throws {
        for retried in [false, true] {
            try await RepositoryFiles.withTemporaryDirectory { root in
                let f = try await Self.fixture(root)
                let a = try await f.version("a.jpg"), b = try await f.version("b.jpg")
                // The first photo is already on the server, in an older album named the same.
                let first = await f.job(stacking: false).run(try await f.makeRun([a], stacking: false))
                let older = FakeImmichServer.Album(name: "Trip", assetCount: 1)
                f.server.setAlbums([older])
                f.server.update(try #require(first.items[0].assetID)) { $0.albumIDs = [older.id] }
                f.server.add(.loseAnswer(method: "POST", path: "/albums", times: 1))
                let retry: RemoteRetryPolicy = retried ? .none : RemoteRetryPolicy(delays: [.milliseconds(10)])
                var run = await f.job(stacking: false, retry: retry)
                    .run(try await f.makeRun([a, b], album: .new(name: "Trip"), stacking: false))
                if retried {
                    #expect(run.counts.failed >= 1)
                    run = await f.job(stacking: false, retry: .none).run(run, retrying: true)
                }
                let albums = f.server.albums
                #expect(albums.count == 2, "the older and the run's")
                let made = try #require(albums.first { $0.album.id != older.id })
                #expect(made.album.name == "Trip")
                #expect(Set(made.assetIDs) == Set(run.items.compactMap(\.assetID)))
                #expect(albums.first { $0.album.id == older.id }?.assetIDs == [try #require(first.items[0].assetID)])
                guard case .ready(let id, _, true) = run.album else {
                    Issue.record("the run's album is known: \(run.album)")
                    return
                }
                #expect(id == made.album.id)
                #expect(run.counts.failed == 0)
            }
        }
    }

    // MARK: Faults and stopping (R17, R21 to R23)

    @Test("A 429 is tried again; a rejected key stops the run and says which (AC16)")
    func faults() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg", "c.jpg"])
            let ids = [try await f.version("a.jpg"), try await f.version("b.jpg"), try await f.version("c.jpg")]
            f.server.add(.answer(method: "POST", path: "/assets", status: 429, times: 1))
            f.server.onUploadReceived { _ in f.server.add(.revokeKey) }
            let run = await f.job(stacking: false, retry: RemoteRetryPolicy(delays: [.milliseconds(10)]))
                .run(try await f.makeRun(ids, stacking: false))
            #expect(run.items[0].isAccepted)
            #expect(run.items[1].upload == .failed(.uploadRefused(.server(status: 401, message: "Invalid API key"))))
            #expect(run.items[2].upload == .pending)
            #expect(run.ending == .stopped(.keyRejected))
            #expect(run.retryCandidates == [ids[1], ids[2]])
        }
    }

    @Test("A lost connection stops the run as unreachable; Retry covers the unreached photos (AC16, AC21)")
    func lostConnection() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg", "c.jpg"])
            let ids = [try await f.version("a.jpg"), try await f.version("b.jpg"), try await f.version("c.jpg")]
            f.server.onUploadReceived { _ in f.server.add(.drop) }
            var run = await f.job(stacking: false).run(try await f.makeRun(ids, stacking: false))
            #expect(run.ending == .stopped(.unreachable))
            #expect(run.items[0].isAccepted && run.items[1].upload == .failed(.uploadInterrupted))
            #expect(run.items[2].upload == .pending)
            f.server.onUploadReceived(nil)
            f.server.clearFaults()
            f.server.remove(.drop)
            run = await f.job(stacking: false).run(run, retrying: true)
            #expect(run.ending == .completed)
            #expect(run.items.allSatisfy { $0.isAccepted })
            #expect(f.server.uploads.count == 3)
        }
    }

    @Test("The person's Stop: what arrived stays recorded; Retry finishes its steps but leaves out the unreached (AC20, AC21)")
    func personsStop() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg"])
            let ids = [try await f.version("a.jpg"), try await f.version("b.jpg")]
            let album = FakeImmichServer.Album(name: "Kept", assetCount: 0)
            f.server.setAlbums([album])
            let run = try await f.makeRun(ids, album: .existing(id: album.id, name: "Kept"), stacking: false)
            // Stopped when the client has sent the first file whole: it waits
            // for that answer, then does nothing more (design §9). The answer
            // is held until the Stop: an upload answered at once can end before
            // URLSession reports its whole body sent, and the Stop then came at
            // the second photo (CI fix, status.md).
            f.server.add(.holdUploadAnswer)
            // The answer must come within the bound to be kept: a bound far
            // beyond any step on a loaded runner.
            var job = f.job(stacking: false, bound: .seconds(60))
            let sent = AsyncStream<Void>.makeStream()
            job.onFullySent = { sent.continuation.yield() }
            let task = Task { await job.run(run) }
            for await _ in sent.stream { break }
            task.cancel()
            while f.server.heldAnswerCount == 0 { await Task.yield() }
            #expect(f.server.uploads.count == 1)
            f.server.releaseHeldAnswers()
            var ended = await task.value
            #expect(ended.ending == .stopped(.stopped))
            #expect(ended.items[0].isAccepted && ended.items[0].album == .pending)
            #expect(ended.items[1].upload == .pending)
            #expect(ended.counts.notFinished == 1 && ended.counts.notPublished == 1)
            #expect(try await f.catalog.publications(address: f.address, versionIDs: [ids[0]])[ids[0]]?.count == 1)
            #expect(ended.retryCandidates == [ids[0]])
            f.server.remove(.holdUploadAnswer)
            ended = await f.job(stacking: false).run(ended, retrying: true)
            #expect(ended.items[0].album == .done)
            #expect(ended.items[1].upload == .pending)
            #expect(f.server.uploads.count == 1)
        }
    }

    @Test("Each photo is filed in its album and stacked before the next one's upload: a Stop keeps the completed photo's steps (AC20, R21, QA Q1)")
    func stepsFollowEachUpload() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg"])
            let a = try await f.version("a.jpg"), b = try await f.version("b.jpg")
            // a has an original to stack on, linked as an import makes it.
            let original = FakeImmichServer.Asset(fileName: "a.jpg", data: try f.masterData("a.jpg"), takenAt: Date())
            f.server.addAssets([original])
            _ = try await f.catalog.database.write { db in
                try Catalog.insertLink(db, remoteID: original.id, fingerprint: original.checksum,
                                       link: RemoteLinkTarget(provider: .immich, address: f.address, serviceID: f.service.id),
                                       versionID: a, at: Date())
            }
            let album = FakeImmichServer.Album(name: "Kept", assetCount: 0)
            f.server.setAlbums([album])
            let run = try await f.makeRun([a, b], album: .existing(id: album.id, name: "Kept"))
            // Every upload's answer is held until the test lets it go.
            f.server.add(.holdUploadAnswer)
            let task = Task { await f.job(bound: .milliseconds(300), concurrency: 1).run(run) }
            // a's answer: let go, so a completes.
            while f.server.heldAnswerCount == 0 { await Task.yield() }
            f.server.releaseHeldAnswers()
            // b's answer is held: the run is stopped there.
            while f.server.heldAnswerCount == 0 { await Task.yield() }
            #expect(f.server.uploads.count == 2)
            task.cancel()
            let ended = await task.value

            #expect(ended.ending == .stopped(.stopped))
            #expect(ended.items[0].album == .done && ended.items[0].stacking == .stacked)
            let first = try #require(ended.items[0].assetID)
            let filed = f.server.albums.first { $0.album.id == album.id }?.assetIDs ?? []
            #expect(filed.contains(first))
            #expect(f.server.stack(of: original.id)?.members.contains(first) == true)
            // b never got past its upload.
            #expect(ended.items[1].versionID == b)
            #expect(ended.items[1].album != .done)
            #expect(filed.count == 1)
            f.server.releaseHeldAnswers()
            f.expectOnlyAllowedRequests()
        }
    }

    /// Watches an ending's wait for its deadline (`RemoteUploadEnding`): each
    /// deadline asked for and when it was asked, and whether one has come.
    /// With `sleeps` it waits as the app does; without, it returns at once.
    final class DeadlineWatch: Sendable {
        struct Ask {
            let deadline: ContinuousClock.Instant
            let at: ContinuousClock.Instant
        }

        private struct State {
            var asks: [Ask] = []
            var reached = false
        }

        private let state = Mutex(State())
        let sleeps: Bool

        init(sleeps: Bool) {
            self.sleeps = sleeps
        }

        var asks: [Ask] { state.withLock { $0.asks } }
        /// A deadline came (set before the wait returns, so before the cancel it leads to).
        var reached: Bool { state.withLock { $0.reached } }

        func wait(until deadline: ContinuousClock.Instant) async {
            state.withLock { $0.asks.append(Ask(deadline: deadline, at: .now)) }
            if sleeps { await RemoteUploadEnding.sleep(until: deadline) }
            state.withLock { $0.reached = true }
        }
    }

    // The three AC23 tests below assert order and events, not how long a step
    // took: CI's cooperative pool is starved by other suites (issue #259), so
    // any step can take seconds there (status.md, "CI fix").

    @Test("Ending: a fully sent upload answered while the run ends is recorded, and the run ends without waiting out the bound (AC23)")
    func endingRecordsAnAnswer() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg"])
            let a = try await f.version("a.jpg")
            f.server.add(.holdUploadAnswer)
            let run = try await f.makeRun([a], stacking: false)
            // A bound far beyond any step on a loaded runner (the worst seen
            // on CI: 7 s), so the answer always comes first; a run that waited
            // the bound out would end after it and fail below.
            let bound = Duration.seconds(60)
            var job = f.job(stacking: false, bound: bound)
            let watch = DeadlineWatch(sleeps: true)
            job.waitForEndingDeadline = { await watch.wait(until: $0) }
            let sent = AsyncStream<Void>.makeStream()
            job.onFullySent = { sent.continuation.yield() }
            let task = Task { await job.run(run) }
            // The client handed the whole body to the system; the server holds its answer.
            for await _ in sent.stream { break }
            let stoppedAt = ContinuousClock.now
            task.cancel()
            // Answered once the server has the body and the run is ending.
            while f.server.heldAnswerCount == 0 { await Task.yield() }
            f.server.releaseHeldAnswers()
            let ended = await task.value
            let endedAt = ContinuousClock.now
            // Left to answer, not cancelled at once: the answer was taken and
            // recorded. (Not `watch.asks`: the wait is asked for by a detached
            // task nothing awaits, so nothing orders it before this read; code
            // review C15.)
            #expect(ended.items[0].isAccepted)
            #expect(try await f.catalog.publications(address: f.address, versionIDs: [a])[a]?.count == 1)
            #expect(ended.ending == .stopped(.stopped))
            // ...and the run ended on the answer, before the bound after the
            // Stop. The deadline is the bound after the run's first cancel,
            // which comes after `stoppedAt`, so this is stricter than ending
            // before the deadline.
            #expect(endedAt < stoppedAt + bound, "the run waited out the bound")
            #expect(!watch.reached)
            #expect((try? FileManager.default.contentsOfDirectory(atPath: f.temporary.path)) ?? [] == [])
        }
    }

    @Test("Ending: with no answer to a fully sent upload the run ends at the bound, not before (AC23)")
    func endingGivesUpAtTheBound() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg"])
            let a = try await f.version("a.jpg")
            f.server.add(.holdUploadAnswer)
            let run = try await f.makeRun([a], stacking: false)
            let bound = Duration.seconds(2)
            var job = f.job(stacking: false, bound: bound)
            let watch = DeadlineWatch(sleeps: true)
            job.waitForEndingDeadline = { await watch.wait(until: $0) }
            let sent = AsyncStream<Void>.makeStream()
            job.onFullySent = { sent.continuation.yield() }
            let task = Task { await job.run(run) }
            for await _ in sent.stream { break }
            let stoppedAt = ContinuousClock.now
            task.cancel()
            // The server never answers.
            let ended = await task.value
            let elapsed = ContinuousClock.now - stoppedAt
            // One wait, for the bound after the Stop: set by the Stop, so between
            // the Stop and the moment the wait was asked for (never later).
            #expect(watch.asks.count == 1)
            let ask = try #require(watch.asks.first)
            #expect(ask.deadline - bound >= stoppedAt && ask.deadline - bound <= ask.at)
            // Not before: the run ended only once its deadline had come.
            #expect(watch.reached)
            #expect(elapsed >= bound)
            // Given up by that cancel: nothing recorded, the photo not published.
            #expect(ended.items[0].upload == .pending)
            #expect(try await f.catalog.publications(address: f.address, versionIDs: [a])[a] == nil)
            #expect(ended.counts.notPublished == 1)
            #expect(ended.ending == .stopped(.stopped))
            #expect(f.server.heldAnswerCount == 1)
            #expect((try? FileManager.default.contentsOfDirectory(atPath: f.temporary.path)) ?? [] == [])
            f.server.releaseHeldAnswers()
        }
    }

    @Test("An upload not fully sent is cancelled at once, without waiting for the bound (AC23)")
    func notFullySentCancelledAtOnce() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let server = try await FakeImmichServer()
            server.setPermissions(Self.publishing)
            server.add(.stallUploadBody)
            // The stalled body must not time out before the Stop.
            let client = try RemoteConnectionTests.client(server, timeout: Self.requestTimeout)
            let body = root.appending(path: "body")
            // Far more than the loopback buffers hold (status.md: about 4 MB).
            try Data(repeating: 7, count: 48 << 20).write(to: body)
            // A wait for the deadline returns at once, so an upload wrongly
            // left to wait ends quickly too, and is told apart by the ask.
            let watch = DeadlineWatch(sleeps: false)
            let awaiting = Mutex<[Bool]>([])
            // A bound far beyond any step on a loaded runner (the worst seen on
            // CI: 7 s), as in `endingRecordsAnAnswer`: an upload that ended only
            // at the deadline, by any wait, ends after it and fails below (QA Q8).
            let bound = Duration.seconds(60)
            let ending = RemoteUploadEnding(bound: bound, onFullySent: nil,
                                            onAwaitingChange: { change in awaiting.withLock { $0.append(change) } },
                                            waitUntil: { await watch.wait(until: $0) })
            let task = Task { () async -> Result<RemoteUploadOutcome, PublishFailure> in
                do throws(PublishFailure) {
                    return .success(try await client.upload(bodyFile: body, contentType: "multipart/form-data; boundary=x",
                                                            ending: ending))
                } catch {
                    return .failure(error)
                }
            }
            while !server.requests.contains(where: { $0.path == "/api/assets" }) { try await Task.sleep(for: .milliseconds(20)) }
            try await Task.sleep(for: .milliseconds(200))
            let stoppedAt = ContinuousClock.now
            task.cancel()
            let result = await task.value
            let endedAt = ContinuousClock.now
            // Cancelled before the bound after the Stop. The deadline is the bound
            // after the ending's first cancel, which comes after `stoppedAt`, so
            // an upload left to end at the deadline, through the injected wait or
            // any other, ends after this.
            #expect(endedAt < stoppedAt + bound, "the upload waited for the bound")
            guard case .failure(let failure) = result else {
                Issue.record("the upload was cancelled")
                return
            }
            // Ended by the cancel itself (not the request's timeout, which is not
            // `.cancelled`), with no wait for the deadline and no answer awaited.
            #expect(failure == .remote(.cancelled))
            #expect(ending.endedAt != nil, "the Stop reached the ending")
            #expect(watch.asks.isEmpty, "left to wait for the bound")
            #expect(awaiting.withLock { $0 }.isEmpty)
            #expect(!ending.isAwaitingAnswers)
        }
    }

    // MARK: Records (R17, R18, R20, R26)

    @Test("Records survive removing the server and go with their photo; the address knows them (R17, R20, R26)")
    func records() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg")
            #expect(try await f.catalog.hasRecordsOrLinks(address: f.address) == false)
            let run = await f.job(stacking: false).run(try await f.makeRun([a], stacking: false))
            let asset = try #require(run.items[0].assetID)
            #expect(try await f.catalog.publishedRemoteIDs(address: f.address, among: [asset, "other"]) == [asset])
            #expect(try await f.catalog.hasRecordsOrLinks(address: f.address))
            try await f.catalog.deleteRemoteService(id: try #require(f.service.id))
            #expect(try await f.catalog.publications(address: f.address, versionIDs: [a])[a]?.first?.serviceId == nil)
            #expect(try await f.catalog.publishedRemoteIDs(address: f.address, among: [asset]) == [asset])
            _ = try await f.catalog.removePhotos(versionIDs: [a])
            #expect(try await f.catalog.publishedRemoteIDs(address: f.address, among: [asset]).isEmpty)
        }
    }

    @Test("Choices and the folder map are remembered per server and go with it (R7, R12)")
    func rememberedChoices() async throws {
        let catalog = try Catalog.makeInMemory()
        let service = try await catalog.saveRemoteService(RemoteServiceRecord(name: "S", address: "https://s.example"))
        let id = try #require(service.id)
        #expect(try await catalog.publishSettings(serviceID: id) == RemotePublishSettings())
        var settings = ExportSettings()
        settings.jpegQuality = 0.7
        let choices = PublishChoices(settings: settings, album: .existing(id: "x", name: "X"), visibility: .archive, stacking: false)
        try await catalog.savePublishChoices(choices, serviceID: id)
        let map = [PublishFolderMapping(volumeIdentity: "uuid:1", folderPath: "P", lastKnownPath: "/V/P", serverPath: "/mnt")]
        try await catalog.saveFolderMap(map, serviceID: id)
        #expect(try await catalog.publishSettings(serviceID: id) == RemotePublishSettings(choices: choices, folderMap: map))
        try await catalog.deleteRemoteService(id: id)
        #expect(try await catalog.publishSettings(serviceID: id) == RemotePublishSettings())
    }

    // MARK: Review fixes

    @Test("Both halves of a pair linked: the pair and a copy of its RAW stack on the RAW's asset, the JPEG's untouched (AC7, R11)")
    func pairBothLinkedAndCopy() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["p.DNG", "p.jpg"])
            let raw = try await f.version("p.DNG"), jpeg = try await f.version("p.jpg")
            let rawAsset = FakeImmichServer.Asset(fileName: "p.DNG", data: Data([1]), takenAt: Date())
            let jpegAsset = FakeImmichServer.Asset(fileName: "p.jpg", data: Data([2]), takenAt: Date())
            f.server.addAssets([rawAsset, jpegAsset])
            try await f.link(raw, to: rawAsset.id)
            try await f.link(jpeg, to: jpegAsset.id)
            let copy = try #require(try await f.catalog.duplicateVersions(ids: [raw]).first?.copyVersionID)
            try await f.catalog.setEditStack(Self.edit(0.5), forVersion: copy, historyLabel: "Exposure")
            // The copy takes its original's link, before the pair partner's (R11).
            let sources = try await f.catalog.publishSources(versionIDs: [raw, copy], address: f.address)
            #expect(sources[raw]?.linkedAssetIDs.first == rawAsset.id)
            #expect(sources[copy]?.linkedAssetIDs.first == rawAsset.id)
            let run = await f.job().run(try await f.makeRun([raw, copy]))
            #expect(run.items.allSatisfy { $0.stacking == .stacked })
            let first = try #require(run.items[0].assetID), second = try #require(run.items[1].assetID)
            let stack = try #require(f.server.stack(of: rawAsset.id))
            #expect(stack.primary == second)
            #expect(Set(stack.members) == [rawAsset.id, first, second])
            // Only that one link is tried: nothing asks about the JPEG's asset.
            #expect(f.server.asset(jpegAsset.id)?.stackID == nil)
            #expect(!f.server.requests.contains { $0.path.contains(jpegAsset.id) || String(decoding: $0.body, as: UTF8.self).contains(jpegAsset.id) })
            f.expectOnlyAllowedRequests()
        }
    }

    @Test("Only the JPEG of a pair linked: the pair and a copy of its RAW both stack on the JPEG's asset (AC7, R11)")
    func pairJPEGLinkedAndCopy() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["p.DNG", "p.jpg"])
            let raw = try await f.version("p.DNG"), jpeg = try await f.version("p.jpg")
            let jpegAsset = FakeImmichServer.Asset(fileName: "p.jpg", data: Data([2]), takenAt: Date())
            f.server.addAssets([jpegAsset])
            try await f.link(jpeg, to: jpegAsset.id)
            let copy = try #require(try await f.catalog.duplicateVersions(ids: [raw]).first?.copyVersionID)
            try await f.catalog.setEditStack(Self.edit(0.5), forVersion: copy, historyLabel: "Exposure")
            let run = await f.job().run(try await f.makeRun([raw, copy]))
            #expect(run.items.allSatisfy { $0.stacking == .stacked })
            let first = try #require(run.items[0].assetID), second = try #require(run.items[1].assetID)
            let stack = try #require(f.server.stack(of: jpegAsset.id))
            #expect(stack.primary == second)
            #expect(Set(stack.members) == [jpegAsset.id, first, second])
        }
    }

    @Test("Two edits of one original: the later in grid order is primary whichever upload finishes first (AC10, code review C6)")
    func stackOrderWhicheverUploadFinishesFirst() async throws {
        for laterFinishesFirst in [false, true] {
            try await RepositoryFiles.withTemporaryDirectory { root in
                let f = try await Self.fixture(root)
                let a = try await f.version("a.jpg")
                let original = FakeImmichServer.Asset(fileName: "a.jpg", data: try f.masterData("a.jpg"), takenAt: Date())
                f.server.addAssets([original])
                try await f.link(a, to: original.id)
                let copy = try #require(try await f.catalog.duplicateVersions(ids: [a]).first?.copyVersionID)
                try await f.catalog.setEditStack(Self.edit(0.5), forVersion: copy, historyLabel: "Exposure")
                let names = (earlier: try await f.uploadName(a), later: try await f.uploadName(copy))
                #expect(names.earlier != names.later)
                // Both uploads reach the server and wait for their answers.
                f.server.add(.holdUploadAnswer)
                let recorded = AsyncStream<Int64>.makeStream()
                var job = f.job(concurrency: 2)
                job.onRecorded = { recorded.continuation.yield($0) }
                let run = try await f.makeRun([a, copy])
                let task = Task { await job.run(run) }
                while f.server.heldAnswerCount < 2 { await Task.yield() }
                // One upload is answered and recorded before the other is answered at all.
                let (firstName, firstID, secondName) = laterFinishesFirst ? (names.later, copy, names.earlier)
                    : (names.earlier, a, names.later)
                #expect(f.server.releaseHeldAnswer(fileName: firstName))
                for await id in recorded.stream where id == firstID { break }
                #expect(f.server.releaseHeldAnswer(fileName: secondName))
                let ended = await task.value
                #expect(ended.items.allSatisfy { $0.stacking == .stacked }, "\(laterFinishesFirst)")
                let earlier = try #require(ended.items[0].assetID), later = try #require(ended.items[1].assetID)
                let stack = try #require(f.server.stack(of: original.id))
                #expect(stack.primary == later, "later finishes first: \(laterFinishesFirst)")
                #expect(Set(stack.members) == [original.id, earlier, later])
                // One at a time: the later create names the earlier edit as the primary it read.
                #expect(f.stackCreates == [[earlier, original.id], [later, earlier, original.id]])
            }
        }
    }

    @Test("A trashed primary is named in the create and, restored before any later publication, is in the new stack, not as primary (R14, AC10, RI-E1)")
    func trashedPrimaryNamedAndRestored() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg")
            var primary = FakeImmichServer.Asset(fileName: "p.jpg", data: Data([1]), takenAt: Date())
            primary.isTrashed = true
            let original = FakeImmichServer.Asset(fileName: "a.jpg", data: Data([2]), takenAt: Date())
            let member = FakeImmichServer.Asset(fileName: "m.jpg", data: Data([3]), takenAt: Date())
            f.server.addAssets([primary, original, member])
            f.server.makeStack([primary.id, original.id, member.id])
            try await f.link(a, to: original.id)
            let run = await f.job().run(try await f.makeRun([a]))
            let edit = try #require(run.items[0].assetID)
            #expect(run.items[0].stacking == .stacked)
            #expect(f.stackCreates == [[edit, primary.id, original.id]])
            // In the trash it isn't listed; nothing reports it.
            #expect(Set(try #require(f.server.stack(of: original.id)).members) == [edit, original.id, member.id])
            #expect(run.counts.failed == 0 && run.counts.stacked == 1)
            f.server.update(primary.id) { $0.isTrashed = false }
            let restored = try #require(f.server.stack(of: original.id))
            #expect(restored.primary == edit)
            #expect(Set(restored.members) == [edit, primary.id, original.id, member.id])
        }
    }

    @Test("A later publication that replaces the stack while the former primary is still in the trash drops it (R14, RI-E1)")
    func laterPublicationDropsTrashedPrimary() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root)
            let a = try await f.version("a.jpg")
            var primary = FakeImmichServer.Asset(fileName: "p.jpg", data: Data([1]), takenAt: Date())
            primary.isTrashed = true
            let original = FakeImmichServer.Asset(fileName: "a.jpg", data: Data([2]), takenAt: Date())
            let member = FakeImmichServer.Asset(fileName: "m.jpg", data: Data([3]), takenAt: Date())
            f.server.addAssets([primary, original, member])
            f.server.makeStack([primary.id, original.id, member.id])
            try await f.link(a, to: original.id)
            let first = try #require(await f.job().run(try await f.makeRun([a])).items[0].assetID)
            // Published again (New Copy of a re-edited photo) while it is still in the trash.
            try await f.catalog.setEditStack(Self.edit(0.4), forVersion: a, historyLabel: "Exposure")
            let second = try #require(await f.job().run(try await f.makeRun([a])).items[0].assetID)
            #expect(f.stackCreates.last == [second, first, original.id], "the primary as read: the first edit")
            f.server.update(primary.id) { $0.isTrashed = false }
            let stack = try #require(f.server.stack(of: original.id))
            #expect(stack.primary == second)
            #expect(Set(stack.members) == [second, first, original.id, member.id])
            #expect(f.server.asset(primary.id)?.stackID == nil)
        }
    }

    @Test("After the person's Stop every report says ending, and says while an answer is awaited (review F2, D-1)")
    func stopKeepsEndingInEveryReport() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg", "c.jpg"])
            let ids = [try await f.version("a.jpg"), try await f.version("b.jpg"), try await f.version("c.jpg")]
            f.server.add(.holdUploadAnswer)
            let reports = Mutex<[PublishProgress]>([])
            // Stopped when a file is fully sent; whichever of the callback and
            // the assignment comes second cancels, and says so.
            let stop = Mutex<(task: Task<PublishRun, Never>?, asked: Bool)>((nil, false))
            let cancelled = AsyncStream<Void>.makeStream()
            var job = f.job(stacking: false, concurrency: 2)
            job.onFullySent = {
                stop.withLock { state in
                    state.asked = true
                    if let task = state.task {
                        task.cancel()
                        cancelled.continuation.yield()
                    }
                }
            }
            let run = try await f.makeRun(ids, stacking: false)
            let task = Task { await job.run(run) { progress in reports.withLock { $0.append(progress) } } }
            stop.withLock { state in
                state.task = task
                if state.asked {
                    task.cancel()
                    cancelled.continuation.yield()
                }
            }
            for await _ in cancelled.stream { break }
            // The fully sent file reaches the server, which answers now, while the run ends.
            while f.server.heldAnswerCount == 0 { await Task.yield() }
            f.server.releaseHeldAnswers()
            let ended = await task.value
            #expect(ended.ending == .stopped(.stopped))
            let all = reports.withLock { reports -> [PublishProgress] in reports }
            let stoppedAt = try #require(all.firstIndex { $0.phase == .ending }, "the Stop is reported")
            let after = all[stoppedAt...]
            #expect(after.allSatisfy { $0.phase == .ending }, "\(after.map(\.phase))")
            #expect(after.contains { $0.awaitsAnswer })
            #expect(after.last?.awaitsAnswer == false)
        }
    }

    @Test("An album a run made is remembered, and nothing else of that run's choices (review F18)")
    func madeAlbumRememberedAlone() async throws {
        let catalog = try Catalog.makeInMemory()
        let service = try await catalog.saveRemoteService(RemoteServiceRecord(name: "S", address: "https://s.example"))
        let id = try #require(service.id)
        // What a newer run left: Archive, stacking off, quality 70%.
        var settings = ExportSettings()
        settings.jpegQuality = 0.7
        let newer = PublishChoices(settings: settings, album: .none, visibility: .archive, stacking: false)
        try await catalog.savePublishChoices(newer, serviceID: id)
        try await catalog.rememberMadeAlbum(id: "made", name: "Trip", serviceID: id)
        var expected = newer
        expected.album = .existing(id: "made", name: "Trip")
        #expect(try await catalog.publishSettings(serviceID: id).choices == expected)
    }

    @Test("A retry that only finishes steps reports Uploading with each photo's number, never Rendering 0 (review F22, D-8)")
    func retryFinishingStepsReportsUploading() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg"])
            let ids = [try await f.version("a.jpg"), try await f.version("b.jpg")]
            let album = FakeImmichServer.Album(name: "Kept", assetCount: 0)
            f.server.setAlbums([album])
            f.server.add(.answer(method: "PUT", path: "/albums/", status: 500, times: 2))
            var run = await f.job(stacking: false).run(try await f.makeRun(ids, album: .existing(id: album.id, name: "Kept"),
                                                                             stacking: false))
            #expect(run.items.allSatisfy { $0.isAccepted && $0.hasFailed })
            #expect(run.retryCandidates == ids)
            f.server.clearFaults()
            let reports = Mutex<[PublishProgress]>([])
            run = await f.job(stacking: false).run(run, retrying: true) { progress in reports.withLock { $0.append(progress) } }
            #expect(run.items.allSatisfy { $0.album == .done })
            #expect(f.server.uploads.count == 2)
            let all = reports.withLock { reports -> [PublishProgress] in reports }
            #expect(!all.isEmpty)
            #expect(all.allSatisfy { $0.phase == .uploading && $0.current >= 1 }, "\(all.map { "\($0.phase) \($0.current)" })")
            #expect(all.map(\.current).max() == 2)
        }
    }

    // MARK: A Stop while a retry checks its server (PRD revision 7, R23, AC21, review D-10)

    /// Waits until the task is cancelled (never used to wait for an event).
    static func untilCancelled() async {
        try? await Task.sleep(for: .seconds(3600))
    }

    @Test("A Stop while a retry checks its server sends nothing and leaves the run as it was; the next retry still covers the unreached (AC21, D-10)")
    func stopDuringRetryCheck() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg", "c.jpg"])
            let ids = [try await f.version("a.jpg"), try await f.version("b.jpg"), try await f.version("c.jpg")]
            // A fault stop with a photo not reached (as `lostConnection`).
            f.server.onUploadReceived { _ in f.server.add(.drop) }
            let run = await f.job(stacking: false).run(try await f.makeRun(ids, stacking: false))
            f.server.onUploadReceived(nil)
            f.server.clearFaults()
            f.server.remove(.drop)
            #expect(run.ending == .stopped(.unreachable))
            #expect(run.retryCandidates == [ids[1], ids[2]])
            let keys = InMemoryKeyStore()
            try keys.setKey(FakeImmichServer.validKey, account: f.service.uuid)
            let service = f.service
            let temporary = f.temporary
            let catalog = f.catalog
            let makeJob: @Sendable (ImmichClient, PublishServerInfo) async -> PublishJob? = { client, info in
                PublishJob(catalog: catalog, renderer: ExportRenderer(), destination: client, accountID: info.ownerID,
                           folderMap: [], retry: .none, endingBound: .seconds(2), concurrency: 1,
                           temporaryRoot: temporary, timeZone: .gmt)
            }
            let writesBefore = f.writes
            let requestsBefore = f.server.requests.count

            // Stop while the server is being asked (its answer held), by the real check.
            f.server.add(.slowCheck(.seconds(30)))
            let retry = Task {
                await PublishRetry.perform(run, check: {
                    await PublishConnection.connect(service, catalog: catalog, keys: keys, readsAccount: false)
                }, makeJob: makeJob)
            }
            while !f.server.requests.dropFirst(requestsBefore).contains(where: { $0.path == "/api/server/version" }) {
                await Task.yield()
            }
            retry.cancel()
            let stopped = await retry.value
            #expect(stopped.ended(stopAsked: true) == nil, "\(stopped)")
            if case .calledOff = stopped {} else { Issue.record("not called off: \(stopped)") }
            f.server.clearFaults()

            // A Stop wins over a check result the app hasn't acted on (a fault found in the same instant).
            let started = AsyncStream<Void>.makeStream()
            let racing = Task {
                await PublishRetry.perform(run, check: {
                    started.continuation.yield()
                    await Self.untilCancelled()
                    return .failed(.keyRejected)
                }, makeJob: makeJob)
            }
            for await _ in started.stream { break }
            racing.cancel()
            let raced = await racing.value
            #expect(raced.ended(stopAsked: true) == nil, "\(raced)")

            // A Stop after the check passed, before the retry started on any photo.
            let preparing = AsyncStream<Void>.makeStream()
            let beforePhotos = Task {
                await PublishRetry.perform(run, check: {
                    await PublishConnection.connect(service, catalog: catalog, keys: keys, readsAccount: false)
                }, makeJob: { client, info in
                    preparing.continuation.yield()
                    await Self.untilCancelled()
                    return await makeJob(client, info)
                })
            }
            for await _ in preparing.stream { break }
            beforePhotos.cancel()
            let prepared = await beforePhotos.value
            #expect(prepared.ended(stopAsked: true) == nil, "\(prepared)")

            // Nothing was written; the run is as it was, its unreached photo still covered.
            #expect(f.writes == writesBefore)
            #expect(f.server.uploads.count == 1)
            #expect(run.ending == .stopped(.unreachable))
            #expect(run.retryCandidates == [ids[1], ids[2]])

            // The next Retry Failed publishes them.
            let next = await PublishRetry.perform(run, check: {
                await PublishConnection.connect(service, catalog: catalog, keys: keys, readsAccount: false)
            }, makeJob: makeJob)
            let ended = try #require(next.ended(stopAsked: false))
            if case .ran = next {} else { Issue.record("not run: \(next)") }
            #expect(ended.ending == .completed)
            #expect(ended.items.allSatisfy { $0.isAccepted })
            #expect(f.server.uploads.count == 3)
            f.expectOnlyAllowedRequests()
        }
    }

    @Test("A Stop once the retry's job has started, before its first photo, is called off by the job itself (AC21, D-10, code review C12)")
    func stopInsideRetryJobBeforeFirstPhoto() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg", "c.jpg"])
            let ids = [try await f.version("a.jpg"), try await f.version("b.jpg"), try await f.version("c.jpg")]
            // A fault stop with photos not reached (as `stopDuringRetryCheck`).
            f.server.onUploadReceived { _ in f.server.add(.drop) }
            let run = await f.job(stacking: false).run(try await f.makeRun(ids, stacking: false))
            f.server.onUploadReceived(nil)
            f.server.clearFaults()
            f.server.remove(.drop)
            #expect(run.ending == .stopped(.unreachable))
            #expect(run.retryCandidates == [ids[1], ids[2]])
            let writesBefore = f.writes

            // The job's own reads are done; it waits there until the Stop.
            let reached = AsyncStream<Void>.makeStream()
            var job = f.job(stacking: false)
            job.beforeFirstPhoto = {
                reached.continuation.yield()
                await Self.untilCancelled()
            }
            let retrying = Task { [job] in await job.retry(run) }
            for await _ in reached.stream { break }
            retrying.cancel()
            let stopped = await retrying.value
            #expect(stopped == nil, "\(String(describing: stopped))")
            #expect(f.writes == writesBefore)
            #expect(f.server.uploads.count == 1)

            // The same job, not stopped, retries both.
            job.beforeFirstPhoto = nil
            let retried = try #require(await job.retry(run))
            #expect(retried.ending == .completed)
            #expect(f.server.uploads.count == 3)
            f.expectOnlyAllowedRequests()
        }
    }

    @Test("A retry whose check fails ends with what it found, unless a Stop came before the app acted on it (D-5, D-10)")
    func retryCheckFailsOrRuns() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg"])
            let ids = [try await f.version("a.jpg"), try await f.version("b.jpg")]
            f.server.onUploadReceived { _ in f.server.add(.drop) }
            let run = await f.job(stacking: false).run(try await f.makeRun(ids, stacking: false))
            f.server.onUploadReceived(nil)
            f.server.clearFaults()
            f.server.remove(.drop)
            #expect(run.ending == .stopped(.unreachable))
            let keys = InMemoryKeyStore()
            try keys.setKey("wrong-key", account: f.service.uuid)
            let service = f.service
            let catalog = f.catalog
            let writesBefore = f.writes
            let outcome = await PublishRetry.perform(run, check: {
                await PublishConnection.connect(service, catalog: catalog, keys: keys, readsAccount: false)
            }, makeJob: { _, _ in nil })
            guard case .checkStopped(let ended) = outcome else {
                Issue.record("not stopped by its check: \(outcome)")
                return
            }
            #expect(ended.ending == .stopped(.checkFailed(.keyRejected)))
            #expect(outcome.ended(stopAsked: false)?.ending == ended.ending)
            #expect(outcome.ended(stopAsked: true) == nil, "a Stop pressed before the app acted wins (D-10)")
            #expect(f.writes == writesBefore)
        }
    }

    /// The case a check came out as, for a message (`PublishConnection` is not `Equatable`).
    static func label(_ connection: PublishConnection) -> String {
        switch connection {
        case .ready: "ready"
        case .failed(let result): "failed(\(result))"
        case .changed(.removed): "removed"
        case .changed(.connectionChanged): "connectionChanged"
        case .changed(.unchanged): "unchanged"
        case .unreadable: "unreadable"
        }
    }

    @Test("A retry whose server was changed or removed as its check started, or whose catalog can't be read, is called off: nothing sent, the run as it was (D-17, security review N7, QA Q7)")
    func retryCalledOffWhenServerChanged() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await Self.fixture(root, files: ["a.jpg", "b.jpg"])
            let ids = [try await f.version("a.jpg"), try await f.version("b.jpg")]
            // A fault stop with a photo not reached (as `stopDuringRetryCheck`).
            f.server.onUploadReceived { _ in f.server.add(.drop) }
            let run = await f.job(stacking: false).run(try await f.makeRun(ids, stacking: false))
            f.server.onUploadReceived(nil)
            f.server.clearFaults()
            f.server.remove(.drop)
            #expect(run.ending == .stopped(.unreachable))
            #expect(run.retryCandidates == [ids[1]])
            let keys = InMemoryKeyStore()
            try keys.setKey(FakeImmichServer.validKey, account: f.service.uuid)
            // What Retry Failed read before it started (the run's server).
            let held = run.service
            let catalog = f.catalog
            // The control: as saved, this record and key pass the check.
            let control = await PublishConnection.connect(held, catalog: catalog, keys: keys, readsAccount: false)
            guard case .ready = control else {
                Issue.record("the unchanged server did not pass its check: \(Self.label(control))")
                return
            }

            let jobsMade = Mutex(0)
            let writesBefore = f.writes
            let requestsBefore = f.server.requests.count
            /// Retry Failed with the real check; `expected` is the case that check must come out as.
            func retry(expecting expected: String) async {
                let seen = Mutex<String?>(nil)
                let outcome = await PublishRetry.perform(run, check: {
                    let connection = await PublishConnection.connect(held, catalog: catalog, keys: keys,
                                                                     readsAccount: false)
                    seen.withLock { $0 = Self.label(connection) }
                    return connection
                }, makeJob: { _, _ in
                    jobsMade.withLock { $0 += 1 }
                    return nil
                })
                #expect(seen.withLock { $0 } == expected)
                if case .calledOff = outcome {} else { Issue.record("\(expected): not called off: \(outcome)") }
                #expect(outcome.ended(stopAsked: false) == nil, "\(expected): the run was replaced")
                #expect(f.server.requests.count == requestsBefore, "\(expected): the server was contacted")
                #expect(f.writes == writesBefore)
            }

            // Another window saves a new address for the server.
            let heldID = try #require(held.id)
            let saved = try #require(try await catalog.remoteService(id: heldID))
            var moved = saved
            moved.address = "https://photos.example.com"
            moved.allowsUnencrypted = false
            guard case .saved = await catalog.saveRemoteService(moved, key: PublishKeyPairingTests.newKey, keys: keys) else {
                Issue.record("not saved")
                return
            }
            await retry(expecting: "connectionChanged")

            // It removes the server.
            #expect(try await catalog.removeRemoteService(moved, keys: keys) == nil)
            await retry(expecting: "removed")

            // The catalog can't be read when the check reads the row.
            try await catalog.database.write { db in
                try db.execute(sql: "ALTER TABLE remoteService RENAME TO remoteServiceUnreadable")
            }
            await retry(expecting: "unreadable")

            #expect(jobsMade.withLock { $0 } == 0, "a job was built")
            #expect(run.ending == .stopped(.unreachable))
            #expect(run.retryCandidates == [ids[1]])
            #expect(f.server.uploads.count == 1)
            f.expectOnlyAllowedRequests()
        }
    }

    @Test("An id the server gives that isn't plain ASCII is never put in a path (security review N1)")
    func strangeIDsNeverRequested() async throws {
        let server = try await FakeImmichServer()
        server.setPermissions(Self.publishing)
        let client = try RemoteConnectionTests.client(server)
        for id in ["abc\u{2028}", "abc\u{2029}", "é"] {
            #expect(try await client.asset(id: id) == nil)
            await #expect(throws: PublishFailure.self) { _ = try await client.addToAlbum(id, assetIDs: ["a"]) }
        }
        #expect(server.requests.isEmpty)
    }
}
