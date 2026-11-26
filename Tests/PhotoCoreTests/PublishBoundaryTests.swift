import Foundation
import GRDB
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #28: where publishing exists (AC1, R25), the Server sheet's two
/// purposes (AC25, R1), a pair partner's link (AC7) and Retry's rules about
/// later runs and later edits (AC21).
@Suite("Publishing boundaries")
struct PublishBoundaryTests {
    @Test("The standalone importer and photocli have no publishing code (AC1, R25)")
    func noPublishingOutsideTheLibraryApp() throws {
        let folders = ["Sources/PhotoImporter", "Sources/PhotoCLI", "Sources/PhotoCore/Commands"]
        for folder in folders {
            for path in RepositoryFiles.files(under: folder) where path.hasSuffix(".swift") {
                let source = try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
                for word in ["Publish", "publish", "RemotePublishDestination", "createStack", "createAlbum"] {
                    #expect(!source.contains(word), "\(path) mentions \(word)")
                }
            }
        }
        // The command lives in the library app's menus and toolbar only.
        let commands = try String(contentsOf: RepositoryFiles.url("Sources/PhotoApp/Views/LibraryCommands.swift"), encoding: .utf8)
        #expect(commands.contains("PublishText.menuTitle"))
        #expect(commands.contains(#".keyboardShortcut("e", modifiers: [.command, .option])"#))
    }

    @Test("A key with only asset.upload and asset.read passes Publish's check and fails Import's, which says it could publish (AC25)")
    func purposes() async throws {
        let server = try await FakeImmichServer()
        server.setPermissions(["asset.upload", "asset.read"])
        let client = try RemoteConnectionTests.client(server)
        guard case .passed(let info) = await client.check(requiring: ImmichClient.publishingPermissions, readsAccount: false) else {
            Issue.record("Publish's check passes")
            return
        }
        #expect(info.ownerID.isEmpty)
        #expect(!server.requests.contains { $0.path == "/api/users/me" })
        let (result, permissions) = await client.checkWithPermissions(requiring: ImmichClient.neededPermissions,
                                                                     readsAccount: true)
        #expect(result == .missingPermissions(["asset.view", "asset.download", "album.read", "user.read"]))
        #expect(ImmichClient.missing(from: permissions ?? [], needed: ImmichClient.publishingPermissions).isEmpty)
        // Lacking one of the two, Publish's check refuses too.
        server.setPermissions(["asset.upload"])
        #expect(await client.check(requiring: ImmichClient.publishingPermissions, readsAccount: false)
            == .missingPermissions(["asset.read"]))
        // The run's check: the account only with stacking, and no failure for a missing permission.
        server.setPermissions(["asset.upload", "asset.read", "stack.create"])
        guard case .passed(let publishing) = await client.publishCheck(readsAccount: true) else {
            Issue.record("the publish check passes, naming what is missing elsewhere")
            return
        }
        #expect(publishing.ownerID == nil)
        #expect(PublishPermissions.missing(from: publishing.permissions, album: .none, stacking: true).stacking == ["user.read"])
    }

    @Test("A pair's RAW is linked through its JPEG partner and looked for at the RAW's path first (AC7, R12)")
    func pairPartner() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await PublishJobTests.fixture(root, files: ["p.DNG", "p.jpg"])
            let raw = try await f.version("p.DNG"), jpeg = try await f.version("p.jpg")
            _ = try await f.catalog.database.write { db in
                try Catalog.insertLink(db, remoteID: "asset-of-jpeg", fingerprint: "x",
                                       link: RemoteLinkTarget(provider: .immich, address: f.address, serviceID: nil),
                                       versionID: jpeg, at: Date())
            }
            let sources = try await f.catalog.publishSources(versionIDs: [raw], address: f.address)
            let source = try #require(sources[raw])
            #expect(source.linkedAssetIDs == ["asset-of-jpeg"])
            #expect(source.files.map { ($0.relativePath as NSString).lastPathComponent } == ["p.DNG", "p.jpg"])
            // Another server's link is not this one's.
            #expect(try await f.catalog.publishSources(versionIDs: [raw], address: "https://other.example")[raw]?
                .linkedAssetIDs == [])
        }
    }

    @Test("Retry leaves out a photo a later run published, and renders a re-edited photo as saved at the retry (AC21)")
    func retryAndLaterRuns() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let f = try await PublishJobTests.fixture(root, files: ["a.jpg", "b.jpg", "c.jpg"])
            let a = try await f.version("a.jpg"), b = try await f.version("b.jpg"), c = try await f.version("c.jpg")
            // a uploads; b meets a server error and the run stops; c is not reached.
            f.server.onUploadReceived { _ in
                f.server.add(.answer(method: "POST", path: "/assets", status: 503, times: 1))
            }
            var first = await f.job(stacking: false).run(try await f.makeRun([a, b, c], stacking: false))
            #expect(first.ending == .stopped(.unreachable))
            #expect(first.retryCandidates == [b, c])
            f.server.onUploadReceived(nil)
            // A later run publishes c; b is re-edited.
            _ = await f.job(stacking: false).run(try await f.makeRun([c], stacking: false))
            try await f.catalog.setEditStack(PublishJobTests.edit(0.4), forVersion: b, historyLabel: "Exposure")
            let before = f.server.uploads.count
            first = await f.job(stacking: false).run(first, retrying: true)
            #expect(f.server.uploads.count == before + 1, "only b is uploaded again")
            #expect(first.items[2].upload == .pending)
            let record = try #require(try await f.catalog.publications(address: f.address, versionIDs: [b])[b]?.last)
            let item = try #require(try await ExportJob(catalog: f.catalog, renderer: ExportRenderer()).items(for: [b]).first)
            #expect(record.pictureDigest == PublishJob.pictureDigest(item, settings: first.choices.settings))
        }
    }
}
