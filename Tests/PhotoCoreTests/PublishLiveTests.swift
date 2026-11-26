import Foundation
import GRDB
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #28: the engine against a real Immich (opt-in, never in CI). Set
/// `PUBLISH_LIVE_SERVER` to a throwaway server's address (`http://127.0.0.1:2283`)
/// and `PUBLISH_LIVE_KEY_FILE` to a file holding a key with publishing's
/// permissions. The key is read from the file and never printed. Each run
/// uploads new photos to that server.
private let publishLiveIsEnabled = ProcessInfo.processInfo.environment["PUBLISH_LIVE_SERVER"] != nil
    && ProcessInfo.processInfo.environment["PUBLISH_LIVE_KEY_FILE"] != nil

@Suite("Publishing against a live server", .enabled(if: publishLiveIsEnabled))
struct PublishLiveTests {
    @Test("Upload, new album, stacking on a linked original, then a duplicate answer, as a real server answers")
    func live() async throws {
        let environment = ProcessInfo.processInfo.environment
        let address = try ServerAddress.parse(try #require(environment["PUBLISH_LIVE_SERVER"])).get()
        let key = try String(contentsOfFile: try #require(environment["PUBLISH_LIVE_KEY_FILE"]), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let client = try ImmichClient(connection: RemoteConnection(address: address, key: key, unencryptedConfirmed: true))
        guard case .passed(let info) = await client.publishCheck(readsAccount: true), let account = info.ownerID else {
            Issue.record("the live server passes the publish check with the account")
            return
        }
        try await RepositoryFiles.withTemporaryDirectory { root in
            // Seeds differ per run, so every upload is new to the server.
            let seed = UInt64(Date().timeIntervalSince1970)
            let folder = root.appending(path: "Shoot")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, name) in ["a.jpg", "b.jpg"].enumerated() {
                try SyntheticImages.writeJPEG(to: folder.appending(path: name), width: 160, height: 120,
                                              seed: seed &+ UInt64(index),
                                              exif: .init(dateTimeOriginal: "2024:05:0\(index + 1) 10:20:30"))
            }
            let catalog = try Catalog.makeInMemory()
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(folder)
            let service = try await catalog.saveRemoteService(RemoteServiceRecord(name: "Live", address: address.normalized,
                                                                                  allowsUnencrypted: true))
            let images = try await catalog.allImages()
            var ids: [Int64] = []
            for name in ["a.jpg", "b.jpg"] {
                let image = try #require(images.first { $0.fileName == name })
                let versions = try await catalog.versions(ofImage: try #require(image.id))
                ids.append(try #require(versions.first { $0.isDefault }?.id))
            }
            // An "original" for a: its master, uploaded as is, and linked.
            let body = root.appending(path: "original.multipart")
            let type = try PublishUploadBody.write(file: folder.appending(path: "a.jpg"),
                                                   fields: .init(createdAt: Date(), fileName: "a.jpg", visibility: .timeline),
                                                   to: body)
            let original = try await client.upload(bodyFile: body, contentType: type, ending: RemoteUploadEnding()).assetID
            let linkedVersion = ids[0]
            _ = try await catalog.database.write { db in
                try Catalog.insertLink(db, remoteID: original, fingerprint: "x",
                                       link: RemoteLinkTarget(provider: .immich, address: address.normalized, serviceID: nil),
                                       versionID: linkedVersion, at: Date())
            }
            let job = PublishJob(catalog: catalog, renderer: ExportRenderer(), destination: client, accountID: account,
                                 folderMap: [], temporaryRoot: root.appending(path: "Temporary"))
            let albumName = "Live \(seed)"
            var items: [PublishItem] = []
            for id in ids {
                let details = try #require(try await catalog.details(forVersion: id))
                items.append(PublishItem(versionID: id, name: details.image.fileName, album: true, stacking: true))
            }
            var settings = ExportSettings()
            settings.metadata = .copyright
            let run = await job.run(PublishRun(service: service,
                                               choices: PublishChoices(settings: settings, album: .new(name: albumName)),
                                               description: nil, items: items))
            #expect(run.ending == .completed)
            #expect(run.items.allSatisfy { $0.upload != .pending && $0.album == .done })
            #expect(run.items[0].stacking == .stacked)
            #expect(run.items[1].stacking == .noOriginal(.noMappedFolder))
            let edit = try #require(run.items[0].assetID)
            let read = try #require(try await client.asset(id: original))
            #expect(read.stack?.primaryAssetID == edit)
            guard case .ready(let albumID, _, true) = run.album else {
                Issue.record("the run made its album")
                return
            }
            let holding = try await client.ownAlbums(holding: edit)
            #expect(holding.contains { $0.id == albumID && $0.name == albumName })
            // At "Copyright and contact only" the file has no date: the server
            // dates it by the upload's, the capture's wall clock labelled UTC (R4).
            let editRead = try #require(try await client.asset(id: edit))
            #expect(editRead.isImage && !editRead.isTrashed)
            // The same photo again: the server already has the file (R19).
            let again = await job.run(PublishRun(service: service, choices: PublishChoices(settings: settings, stacking: false),
                                                 description: nil,
                                                 items: [PublishItem(versionID: ids[1], name: "b.jpg", album: false, stacking: false)]))
            #expect(again.items[0].isDuplicate)
            #expect(again.items[0].check == .usable)
            print("live publish: version \(info.version) passed")
        }
    }
}
