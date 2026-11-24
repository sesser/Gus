import Foundation
import GRDB
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

/// Issue #271: listing, importing and linking photos from a server, against
/// `FakeImmichServer` on 127.0.0.1.
@Suite("Immich import")
struct RemoteImportTests {
    struct Setup {
        var server: FakeImmichServer
        var client: ImmichClient
        var catalog: Catalog
        var link: RemoteLinkTarget
    }

    static func setup(assets: [FakeImmichServer.Asset]) async throws -> Setup {
        let server = try await FakeImmichServer()
        server.setAssets(assets)
        let client = try RemoteConnectionTests.client(server)
        let catalog = try Catalog.makeInMemory()
        let address = try RemoteConnectionTests.address(server.address).normalized
        return Setup(server: server, client: client, catalog: catalog,
                     link: RemoteLinkTarget(provider: .immich, address: address, serviceID: nil))
    }

    static func importer(_ setup: Setup, retry: RemoteRetryPolicy = .none) -> RemoteImporter {
        RemoteImporter(catalog: setup.catalog, sidecars: nil, source: setup.client, metadataReader: ImageIOMetadataReader(),
                       retry: retry)
    }

    static func options(_ root: URL, _ setup: Setup, project: String = "Home - All Photos",
                        template: ImportTemplate = ImportTemplate(folder: "", fileName: "{name}")) -> RemoteImportOptions {
        RemoteImportOptions(destination: root.appending(path: "Photos"), template: template, project: .named(project),
                            link: setup.link)
    }

    static func listed(_ setup: Setup, scope: RemoteScope = RemoteScope()) async throws -> [RemoteAsset] {
        var assets: [RemoteAsset] = []
        var cursor: String?
        repeat {
            let page = try await setup.client.page(scope: scope, cursor: cursor, ownerID: FakeImmichServer.ownerID)
            assets += page.assets
            cursor = page.nextCursor
        } while cursor != nil
        return assets
    }

    /// Every file under `folder`, hidden ones too, relative.
    static func files(in folder: URL) -> [String] {
        let folder = folder.resolvingSymlinksInPath()
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        var found: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                found.append(String(url.resolvingSymlinksInPath().path.dropFirst(folder.path.count + 1)))
            }
        }
        return found.sorted()
    }

    // MARK: Listing (R9, R10, AC6)

    @Test("Only the account's own timeline images are listed, newest first, in pages (AC6)")
    func listing() async throws {
        var assets = try FakeImmichServer.jpegAssets(count: 300)
        let jpeg = assets[0].data
        let date = assets[0].takenAt
        assets += [
            FakeImmichServer.Asset(fileName: "trashed.JPG", data: jpeg, isTrashed: true, takenAt: date),
            FakeImmichServer.Asset(fileName: "hidden.JPG", data: jpeg, visibility: "hidden", takenAt: date),
            FakeImmichServer.Asset(fileName: "locked.JPG", data: jpeg, visibility: "locked", takenAt: date),
            FakeImmichServer.Asset(fileName: "archived.JPG", data: jpeg, visibility: "archive", takenAt: date),
            FakeImmichServer.Asset(fileName: "clip.MOV", data: jpeg, type: "VIDEO", takenAt: date),
            FakeImmichServer.Asset(fileName: "partner.JPG", data: jpeg, ownerID: "someone-else", takenAt: date),
            FakeImmichServer.Asset(fileName: "anim.GIF", data: jpeg, takenAt: date),
        ]
        let setup = try await Self.setup(assets: assets)
        let first = try await setup.client.page(scope: RemoteScope(), cursor: nil, ownerID: FakeImmichServer.ownerID)
        // 250 on the server's page; the partner's photo and the GIF, both
        // among the newest, are dropped here.
        #expect(first.assets.count == 248)
        #expect(first.nextCursor != nil)
        // One page was asked for, not two (AC6).
        #expect(setup.server.requests.filter { $0.path.hasSuffix("/search/metadata") }.count == 1)
        let dates = first.assets.compactMap(\.metadata.captureDate)
        #expect(dates == dates.sorted(by: >))
        let all = try await Self.listed(setup)
        #expect(all.count == 300)
        #expect(Set(all.map(\.fileName)).isDisjoint(with: ["trashed.JPG", "hidden.JPG", "locked.JPG", "archived.JPG",
                                                           "clip.MOV", "partner.JPG", "anim.GIF"]))
        // The search the server got asks for exactly that.
        let body = try #require(setup.server.requests.first { $0.method == "POST" }?.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let filter = try #require(object["filter"] as? [String: Any])
        #expect((filter["type"] as? [String: String]) == ["eq": "IMAGE"])
        #expect((filter["visibility"] as? [String: String]) == ["eq": "timeline"])
        #expect((filter["trashedAt"] as? [String: Any])?["eq"] is NSNull)
        #expect((object["orderBy"] as? [String: String]) == ["field": "fileCreatedAt", "direction": "desc"])
    }

    @Test("An album lists only its photos; its count is the server's; All Photos has none (AC6, R10)")
    func albums() async throws {
        let album = FakeImmichServer.Album(name: "Trip", assetCount: 5)
        let inAlbum = try FakeImmichServer.jpegAssets(count: 3, albumIDs: [album.id])
        let outside = try FakeImmichServer.jpegAssets(count: 2, startingAt: 10)
        // Another contributor's photo in the (shared) album: never listed (R9, RI-E1).
        var contributed = try FakeImmichServer.jpegAssets(count: 1, startingAt: 20, albumIDs: [album.id])[0]
        contributed.ownerID = "someone-else"
        let setup = try await Self.setup(assets: inAlbum + outside + [contributed])
        setup.server.setAlbums([FakeImmichServer.Album(name: "zebra", assetCount: 1), album])
        let albums = try await setup.client.albums()
        #expect(albums.map(\.name) == ["Trip", "zebra"])
        #expect(albums.first?.assetCount == 5)
        let listed = try await Self.listed(setup, scope: RemoteScope(albumID: album.id))
        #expect(Set(listed.map(\.id)) == Set(inAlbum.map(\.id)))
        // A date range keeps whole days.
        let day = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: inAlbum[1].takenAt)
        let range = CaptureDateRange(from: DateComponents(year: day.year, month: day.month, day: day.day),
                                     through: DateComponents(year: day.year, month: day.month, day: day.day))
        let ranged = try await Self.listed(setup, scope: RemoteScope(dates: range))
        #expect(ranged.map(\.id) == [inAlbum[1].id])
        // An album that is gone answers as not found.
        await #expect(throws: RemoteError.status(400)) {
            _ = try await setup.client.page(scope: RemoteScope(albumID: "gone"), cursor: nil, ownerID: FakeImmichServer.ownerID)
        }
    }

    // MARK: Importing (R12, R13, AC8, AC9)

    @Test("Three photos are downloaded, verified, named by the template and cataloged (AC8)")
    func importsThree() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await Self.setup(assets: try FakeImmichServer.jpegAssets(count: 3))
            let listed = try await Self.listed(setup)
            let template = ImportTemplate(folder: "{capture:yyyy}", fileName: "Trip-{seq:2}")
            let result = await Self.importer(setup).run(listed, options: Self.options(root, setup, project: "Edited name",
                                                                                     template: template))
            #expect(result.imported == 3 && result.failures.isEmpty && result.stop == nil)
            #expect(result.project?.name == "Edited name")
            let folder = root.appending(path: "Photos")
            #expect(Self.files(in: folder) == ["2026/Trip-01.JPG", "2026/Trip-02.JPG", "2026/Trip-03.JPG"])
            for (index, asset) in listed.enumerated() {
                let original = try #require(setup.server.assets.first { $0.id == asset.id }?.data)
                let copy = try Data(contentsOf: folder.appending(path: "2026/Trip-0\(index + 1).JPG"))
                #expect(copy == original)
            }
            let images = try await setup.catalog.database.read { db in try ImageRecord.fetchAll(db) }
            #expect(images.count == 3)
            #expect(images.allSatisfy { $0.captureDate != nil })
        }
    }

    @Test("A corrupt or short download fails alone and leaves no file or row (AC8, R13)")
    func corrupt() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await Self.setup(assets: try FakeImmichServer.jpegAssets(count: 4))
            let listed = try await Self.listed(setup)
            setup.server.add(.corrupt(listed[1].id))
            setup.server.add(.truncate(listed[2].id))
            let result = await Self.importer(setup).run(listed, options: Self.options(root, setup))
            #expect(result.imported == 2)
            #expect(result.failures == [RemoteImportFailure(name: listed[1].fileName, kind: .checksumMismatch),
                                        RemoteImportFailure(name: listed[2].fileName, kind: .incomplete)])
            #expect(Self.files(in: root.appending(path: "Photos")) == [listed[0].fileName, listed[3].fileName].sorted())
            let rows = try await setup.catalog.database.read { db in try ImageRecord.fetchCount(db) }
            #expect(rows == 2)
        }
    }

    @Test("A server's file name can't place a file outside the destination")
    func hostileNames() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            var assets = try FakeImmichServer.jpegAssets(count: 2)
            assets[0].fileName = "../../escape.JPG"
            assets[1].fileName = "/etc/other.JPG"
            let setup = try await Self.setup(assets: assets)
            let result = await Self.importer(setup).run(try await Self.listed(setup), options: Self.options(root, setup))
            #expect(result.imported == 2)
            let files = Self.files(in: root)
            #expect(files.count == 2)
            #expect(files.allSatisfy { $0.hasPrefix("Photos/") && !$0.dropFirst(7).contains("/") })
        }
    }

    @Test("Content already in the library is not imported twice, and is linked (AC9, R15b)")
    func duplicates() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let assets = try FakeImmichServer.jpegAssets(count: 2)
            let setup = try await Self.setup(assets: assets)
            // The first photo is in the library already, from a card.
            let card = root.appending(path: "Card")
            try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try assets[0].data.write(to: card.appending(path: "same.jpg"))
            _ = try await Importer(catalog: setup.catalog, metadataReader: ImageIOMetadataReader()).importFolder(card)
            let listed = try await Self.listed(setup)
            let result = await Self.importer(setup).run(listed, options: Self.options(root, setup))
            #expect(result.imported == 1 && result.alreadyInLibrary == 1)
            #expect(Self.files(in: root.appending(path: "Photos")) == [assets[1].fileName])
            let linked = try await setup.catalog.linkedRemoteIDs(provider: .immich, address: setup.link.address,
                                                                 among: assets.map(\.id))
            #expect(linked == Set(assets.map(\.id)))
        }
    }

    @Test("A RAW and a JPEG of one stem form a pair; a Live Photo's video is left out and counted (AC10, R14)")
    func pairsAndLivePhotos() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let dng = root.appending(path: "IMG_0100.DNG")
            try SyntheticDNG.write(to: dng, options: .init(width: 400, height: 300, seed: 7,
                                                           dateTimeOriginal: "2026:10:01 10:00:00"))
            let jpeg = root.appending(path: "IMG_0100.JPG")
            try SyntheticImages.writeJPEG(to: jpeg, width: 64, height: 48, seed: 8,
                                          exif: .init(dateTimeOriginal: "2026:10:01 10:00:00"))
            let taken = Date(timeIntervalSince1970: 1_790_848_800)
            var live = try FakeImmichServer.jpegAssets(count: 1, startingAt: 50)[0]
            live.livePhotoVideoID = "video-of-live-photo"
            let assets = [
                FakeImmichServer.Asset(fileName: "IMG_0100.DNG", data: try Data(contentsOf: dng), takenAt: taken),
                FakeImmichServer.Asset(fileName: "IMG_0100.JPG", data: try Data(contentsOf: jpeg), takenAt: taken),
                // The Live Photo's motion part: a hidden video, never listed.
                FakeImmichServer.Asset(id: "video-of-live-photo", fileName: "IMG_0050.MOV", data: Data("mov".utf8),
                                       type: "VIDEO", visibility: "hidden", takenAt: live.takenAt),
                live,
            ]
            let setup = try await Self.setup(assets: assets)
            let listed = try await Self.listed(setup)
            #expect(listed.count == 3)
            let result = await Self.importer(setup).run(listed, options: Self.options(root, setup))
            #expect(result.imported == 3 && result.failures.isEmpty)
            #expect(result.liveVideosLeftOut == 1)
            let pairs = try await setup.catalog.database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM imagePair") }
            #expect(pairs == 1)
            #expect(!setup.server.requests.contains { $0.path.contains("video-of-live-photo") })
        }
    }

    @Test("An external library's photo is verified by size only, deduplicated and counted (AC9, R13, RI-E2)")
    func externalLibrary() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            var assets = try FakeImmichServer.jpegAssets(count: 4)
            for index in 0..<3 {
                assets[index].libraryID = "library-1"
                assets[index].checksumOverride = FakeImmichServer.Asset.pathChecksum("/mnt/photos/\(assets[index].fileName)")
            }
            // One external photo is already in the library, from a card.
            let card = root.appending(path: "Card")
            try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try assets[2].data.write(to: card.appending(path: "same.jpg"))
            let setup = try await Self.setup(assets: assets)
            _ = try await Importer(catalog: setup.catalog, metadataReader: ImageIOMetadataReader()).importFolder(card)
            let listed = try await Self.listed(setup)
            #expect(listed.filter(\.isExternalLibrary).count == 3)
            // An external photo served short fails; an uploaded one whose bytes
            // don't match its checksum still fails.
            let short = try #require(listed.first { $0.id == assets[1].id })
            setup.server.add(.truncate(short.id))
            setup.server.add(.corrupt(assets[3].id))
            let result = await Self.importer(setup).run(listed, options: Self.options(root, setup))
            #expect(result.imported == 1)
            #expect(result.verifiedBySizeOnly == 1)
            #expect(result.alreadyInLibrary == 1)
            #expect(Set(result.failures) == [RemoteImportFailure(name: assets[1].fileName, kind: .incomplete),
                                             RemoteImportFailure(name: assets[3].fileName, kind: .checksumMismatch)])
            #expect(Self.files(in: root.appending(path: "Photos")) == [assets[0].fileName])
            let name = assets[0].fileName
            let hash = try await setup.catalog.database.read { db in
                try String.fetchOne(db, sql: "SELECT contentHash FROM image WHERE fileName = ?", arguments: [name])
            }
            #expect(hash == Digest.sha256Hex(assets[0].data))
            #expect(RemoteImportReport(result).lines.contains(.verifiedBySizeOnly(1)))
        }
    }

    @Test("Size-only verification: the size must be known and exact (R13, RI-E2)")
    func sizeOnlyRules() {
        let base = RemoteAsset(id: "a", fileName: "a.jpg", checksum: "path-hash", byteCount: 100, metadata: ImageMetadata(),
                               modifiedAt: Date(), isExternalLibrary: true)
        let url = URL(fileURLWithPath: "/tmp/a.jpg")
        func download(_ count: Int64, length: Int64?) -> RemoteHTTPSession.Download {
            RemoteHTTPSession.Download(byteCount: count, sha1: "bytes-hash", expectedLength: length)
        }
        #expect(RemoteImporter.verify(download(100, length: 100), partial: url, asset: base) == nil)
        #expect(RemoteImporter.verify(download(99, length: 99), partial: url, asset: base) == .incomplete)
        #expect(RemoteImporter.verify(download(101, length: 101), partial: url, asset: base) == .incomplete)
        var unsized = base
        unsized.byteCount = nil
        #expect(RemoteImporter.verify(download(100, length: 100), partial: url, asset: unsized) == nil)
        #expect(RemoteImporter.verify(download(100, length: nil), partial: url, asset: unsized) == .unverifiable)
        // An uploaded photo still needs its SHA-1.
        var uploaded = base
        uploaded.isExternalLibrary = false
        #expect(RemoteImporter.verify(download(100, length: 100), partial: url, asset: uploaded) == .checksumMismatch)
    }

    // MARK: Links (R15, R16, AC11)

    @Test("Each imported version has one link; removal, connections and addresses behave as R16 says (AC11)")
    func links() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let assets = try FakeImmichServer.jpegAssets(count: 2)
            let setup = try await Self.setup(assets: assets)
            let service = try await setup.catalog.saveRemoteService(RemoteServiceRecord(name: "Home", address: setup.link.address))
            var options = Self.options(root, setup)
            options.link.serviceID = service.id
            let listed = try await Self.listed(setup)
            let result = await Self.importer(setup).run(listed, options: options)
            #expect(result.imported == 2)
            let links = try await setup.catalog.database.read { db in try RemoteLinkRecord.order(Column("id")).fetchAll(db) }
            #expect(links.count == 2)
            #expect(links.map(\.versionId) == result.insertedVersionIDs)
            #expect(links.map(\.remoteId) == listed.map(\.id))
            #expect(links.map(\.fingerprint) == listed.map(\.checksum))
            #expect(links.allSatisfy { $0.provider == .immich && $0.address == setup.link.address && $0.serviceId == service.id })

            // Removing the connection keeps the links.
            try await setup.catalog.deleteRemoteService(id: try #require(service.id))
            let kept = try await setup.catalog.database.read { db in try RemoteLinkRecord.fetchAll(db) }
            #expect(kept.count == 2 && kept.allSatisfy { $0.serviceId == nil })
            // The same server written another way still marks them; another address does not.
            for typed in [setup.server.address.uppercased() + "/", setup.server.address + "/api/"] {
                let same = try RemoteConnectionTests.address(typed).normalized
                #expect(try await setup.catalog.linkedRemoteIDs(provider: .immich, address: same, among: assets.map(\.id))
                    == Set(assets.map(\.id)))
            }
            let other = try RemoteConnectionTests.address("http://192.168.1.5:2283").normalized
            #expect(try await setup.catalog.linkedRemoteIDs(provider: .immich, address: other, among: assets.map(\.id)).isEmpty)
            // Importing again downloads nothing.
            setup.server.clearRequests()
            let again = await Self.importer(setup).run(listed, options: options)
            #expect(again.imported == 0 && again.alreadyInLibrary == 2)
            #expect(!setup.server.requests.contains { $0.path.hasSuffix("/original") })

            // Removing the photo removes its link in the same transaction.
            try await setup.catalog.removePhotos(versionIDs: [result.insertedVersionIDs[0]])
            let left = try await setup.catalog.database.read { db in try RemoteLinkRecord.fetchAll(db) }
            #expect(left.map(\.remoteId) == [listed[1].id])
            // Importing that asset again makes a new photo with a new link.
            let removedFile = root.appending(path: "Photos").appending(path: listed[0].fileName)
            try FileManager.default.removeItem(at: removedFile)
            let reimport = await Self.importer(setup).run([listed[0]], options: options)
            #expect(reimport.imported == 1)
            let newLinks = try await setup.catalog.database.read { db in try RemoteLinkRecord.fetchAll(db) }
            #expect(Set(newLinks.map(\.remoteId)) == Set(listed.map(\.id)))
        }
    }

    @Test("A virtual copy carries no link (Q10)")
    func copiesHaveNoLink() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await Self.setup(assets: try FakeImmichServer.jpegAssets(count: 1))
            let result = await Self.importer(setup).run(try await Self.listed(setup), options: Self.options(root, setup))
            let version = try #require(result.insertedVersionIDs.first)
            let copy = try await setup.catalog.duplicateVersion(id: version)
            #expect(try await setup.catalog.remoteLinks(versionID: try #require(copy.id)).isEmpty)
            #expect(try await setup.catalog.remoteLinks(versionID: version).count == 1)
        }
    }

    // MARK: Metadata (R17, AC12)

    @Test("The server's description and rating fill empty library values and queue the sidecar (AC12)")
    func metadata() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            var assets = try FakeImmichServer.jpegAssets(count: 2)
            assets[0].description = "From the server"
            assets[0].rating = 4
            // The second already has a rating in its file: the library's wins.
            let rated = root.appending(path: "rated.jpg")
            try SyntheticImages.writeJPEG(to: rated, width: 64, height: 48, seed: 99,
                                          exif: .init(dateTimeOriginal: "2026:10:01 10:00:00", xmpRating: 2))
            assets[1].data = try Data(contentsOf: rated)
            assets[1].rating = 5
            assets[1].description = "Ignored? No: the file has no description"
            let setup = try await Self.setup(assets: assets)
            let listed = try await Self.listed(setup)
            let result = await Self.importer(setup).run(listed, options: Self.options(root, setup))
            #expect(result.imported == 2)
            let rows = try await setup.catalog.database.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT image.caption, version.rating, version.id FROM version JOIN image ON image.id = version.imageId
                    ORDER BY version.id
                    """).map { (version: $0[2] as Int64, caption: $0[0] as String?, rating: $0[1] as Int) }
            }
            let byVersion = Dictionary(uniqueKeysWithValues: rows.map { ($0.version, $0) })
            let first = try #require(byVersion[result.insertedVersionIDs[listed.firstIndex { $0.id == assets[0].id }!]])
            #expect(first.caption == "From the server")
            #expect(first.rating == 4)
            let second = try #require(byVersion[result.insertedVersionIDs[listed.firstIndex { $0.id == assets[1].id }!]])
            #expect(second.rating == 2)
            // Both changed library values after the insert, so both photos' sidecars are queued.
            let queued = try await setup.catalog.database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sidecarQueue") }
            #expect(queued == 2)
            // The edited render was never asked for.
            #expect(setup.server.requests.filter { $0.path.hasSuffix("/original") }.allSatisfy { $0.query == "edited=false" })
        }
    }

    // MARK: Stopping and failures (R18, R20, AC13, AC14)

    @Test("Stop keeps finished photos with links, removes the partial file, and sends nothing after (AC13)")
    func stop() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await Self.setup(assets: try FakeImmichServer.jpegAssets(count: 4))
            let listed = try await Self.listed(setup)
            setup.server.add(.slow(.seconds(2)))
            let started = Mutex(0)
            let task = Task { await Self.importer(setup).run(listed, options: Self.options(root, setup)) }
            setup.server.onOriginal { _ in
                if started.withLock({ $0 += 1; return $0 }) == 3 { task.cancel() }
            }
            let result = await task.value
            #expect(result.stop == .stopped)
            #expect(result.imported == 2)
            let requestsAtEnd = setup.server.requests.count
            #expect(Self.files(in: root.appending(path: "Photos")).count == 2)
            #expect(Self.files(in: root.appending(path: "Photos")).allSatisfy { !$0.hasPrefix(".") })
            let links = try await setup.catalog.database.read { db in try RemoteLinkRecord.fetchCount(db) }
            #expect(links == 2)
            try await Task.sleep(for: .milliseconds(300))
            #expect(setup.server.requests.count == requestsAtEnd)
        }
    }

    @Test("A deleted asset is a counted failure; a revoked key and a dead server stop the job (AC14)")
    func failures() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await Self.setup(assets: try FakeImmichServer.jpegAssets(count: 4))
            let listed = try await Self.listed(setup)
            setup.server.add(.deleteAsset(listed[1].id))
            let deleted = await Self.importer(setup).run(listed, options: Self.options(root, setup))
            #expect(deleted.imported == 3 && deleted.stop == nil)
            #expect(deleted.failures == [RemoteImportFailure(name: listed[1].fileName, kind: .deletedOnServer)])

            // A revoked key mid-import: two done, then the job stops.
            let second = try await Self.setup(assets: try FakeImmichServer.jpegAssets(count: 4))
            let secondListed = try await Self.listed(second)
            let count = Mutex(0)
            second.server.onOriginal { [server = second.server] _ in
                if count.withLock({ $0 += 1; return $0 }) == 2 { server.add(.revokeKey) }
            }
            let revoked = await Self.importer(second).run(secondListed, options: Self.options(root.appending(path: "b"), second))
            #expect(revoked.stop == .keyRejected)
            // The second download had passed the key check when the key went.
            #expect(revoked.imported == 2)

            // A server that stops answering: retried, then the job stops.
            let third = try await Self.setup(assets: try FakeImmichServer.jpegAssets(count: 3))
            let thirdListed = try await Self.listed(third)
            third.server.add(.unavailable(thirdListed[0].id, times: 2))
            let retried = await Self.importer(third, retry: RemoteRetryPolicy(delays: [.milliseconds(10), .milliseconds(10)]))
                .run(thirdListed, options: Self.options(root.appending(path: "c"), third))
            #expect(retried.imported == 3 && retried.stop == nil)
            for folder in ["Photos", "b/Photos", "c/Photos"] {
                #expect(Self.files(in: root.appending(path: folder)).allSatisfy { !$0.hasPrefix(".") })
            }
        }
    }

    @Test("A server that drops every connection stops the job as unreachable (AC14)")
    func unreachable() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let setup = try await Self.setup(assets: try FakeImmichServer.jpegAssets(count: 2))
            let listed = try await Self.listed(setup)
            setup.server.add(.drop)
            let result = await Self.importer(setup, retry: RemoteRetryPolicy(delays: [.milliseconds(10)]))
                .run(listed, options: Self.options(root, setup))
            #expect(result.stop == .unreachable)
            #expect(result.imported == 0)
            #expect(Self.files(in: root.appending(path: "Photos")).isEmpty)
            // No project is made for an import that brought nothing.
            #expect(try await setup.catalog.projectSummaries().isEmpty)
        }
    }

    // MARK: Migration (R22, AC15)

    @Test("v16 adds the two tables and leaves the earlier catalog's data untouched (AC15)")
    func migration() async throws {
        let old = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(old, upTo: "v15")
        try await old.write { db in
            try db.execute(sql: "INSERT INTO volume (id, identity, name, mountPath) VALUES (1, 'V', 'V', '/Volumes/V')")
            try db.execute(sql: "INSERT INTO project (id, uuid, name, createdAt) VALUES (1, 'p', 'P', '2024-01-01 00:00:00.000')")
        }
        let snapshot = { (db: Database) in
            try Row.fetchAll(db, sql: "SELECT * FROM volume") + Row.fetchAll(db, sql: "SELECT * FROM project")
        }
        let before = try old.read(snapshot)
        let catalog = try Catalog(database: old)
        #expect(try catalog.database.read(snapshot) == before)
        #expect(try await catalog.remoteServices().isEmpty)
        let saved = try await catalog.saveRemoteService(RemoteServiceRecord(name: "Home", address: "https://photos.example.com"))
        let services = try await catalog.remoteServices()
        #expect(services.map(\.id) == [saved.id] && services.map(\.uuid) == [saved.uuid])
        #expect(services.first?.provider == .immich && services.first?.allowsUnencrypted == false)
    }
}
