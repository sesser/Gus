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
        let client = try RemoteConnectionTests.client(server)
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
            // for that answer, then does nothing more (design §9).
            // (task, asked): whichever comes second cancels, so the order of
            // the callback and the assignment doesn't matter.
            let stop = Mutex<(task: Task<PublishRun, Never>?, asked: Bool)>((nil, false))
            var job = f.job(stacking: false)
            job.onFullySent = {
                stop.withLock { state in
                    state.asked = true
                    state.task?.cancel()
                }
            }
            let task = Task { await job.run(run) }
            stop.withLock { state in
                state.task = task
                if state.asked { task.cancel() }
            }
            var ended = await task.value
            #expect(ended.ending == .stopped(.stopped))
            #expect(ended.items[0].isAccepted && ended.items[0].album == .pending)
            #expect(ended.items[1].upload == .pending)
            #expect(ended.counts.notFinished == 1 && ended.counts.notPublished == 1)
            #expect(try await f.catalog.publications(address: f.address, versionIDs: [ids[0]])[ids[0]]?.count == 1)
            #expect(ended.retryCandidates == [ids[0]])
            f.server.onUploadReceived(nil)
            ended = await f.job(stacking: false).run(ended, retrying: true)
            #expect(ended.items[0].album == .done)
            #expect(ended.items[1].upload == .pending)
            #expect(f.server.uploads.count == 1)
        }
    }

    @Test("Ending: a fully sent upload answered within the bound is recorded; with no answer the run ends at the bound (AC23)")
    func endingWaitsForFullySent() async throws {
        for answers in [true, false] {
            try await RepositoryFiles.withTemporaryDirectory { root in
                let f = try await Self.fixture(root, files: ["a.jpg"])
                let a = try await f.version("a.jpg")
                f.server.add(.holdUploadAnswer)
                let run = try await f.makeRun([a], stacking: false)
                var job = f.job(stacking: false, bound: .seconds(2))
                let sent = AsyncStream<Void>.makeStream()
                job.onFullySent = { sent.continuation.yield() }
                let task = Task { await job.run(run) }
                // The client handed the whole body to the system; the server holds its answer.
                for await _ in sent.stream { break }
                let stoppedAt = ContinuousClock.now
                task.cancel()
                if answers {
                    // Answered once the server has the body and the run is ending.
                    while f.server.heldAnswerCount == 0 { await Task.yield() }
                    f.server.releaseHeldAnswers()
                }
                let ended = await task.value
                let elapsed = ContinuousClock.now - stoppedAt
                let records = try await f.catalog.publications(address: f.address, versionIDs: [a])
                if answers {
                    #expect(ended.items[0].isAccepted)
                    #expect(records[a]?.count == 1)
                    #expect(elapsed < .seconds(2))
                } else {
                    #expect(ended.items[0].upload == .pending)
                    #expect(records[a] == nil)
                    #expect(elapsed >= .seconds(2) && elapsed < .seconds(6))
                    #expect(ended.counts.notPublished == 1)
                }
                #expect((try? FileManager.default.contentsOfDirectory(atPath: f.temporary.path)) ?? [] == [])
            }
        }
    }

    @Test("An upload not fully sent is cancelled at once, without waiting for the bound (AC23)")
    func notFullySentCancelledAtOnce() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let server = try await FakeImmichServer()
            server.setPermissions(Self.publishing)
            server.add(.stallUploadBody)
            let client = try RemoteConnectionTests.client(server)
            let body = root.appending(path: "body")
            // Far more than the loopback buffers hold (status.md: about 4 MB).
            try Data(repeating: 7, count: 48 << 20).write(to: body)
            let ending = RemoteUploadEnding(bound: .seconds(30))
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
            let start = ContinuousClock.now
            task.cancel()
            let result = await task.value
            #expect(ContinuousClock.now - start < .seconds(5))
            guard case .failure(let failure) = result else {
                Issue.record("the upload was cancelled")
                return
            }
            #expect(failure == .remote(.cancelled))
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
}
