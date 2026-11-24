import Foundation
import GRDB
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #271, the security review (docs/features/immich-import/security-review.md):
/// F1, a server's file name must never place a file outside the destination;
/// F2, a failed save must not leave a new key beside the old address; and
/// note b, Unicode hosts are not judged as local names.
@Suite("Immich security review")
struct RemoteSecurityTests {
    static let hostileNames = ["../../x.jpg", "a/b/../../../c.jpg", "..\\..\\d.jpg", "e\u{0}.jpg", "../../../../../../../../tmp/f.jpg"]

    @Test("An empty template falls back on the original name sanitized, never on a path (F1, layer 1)")
    func templateFallback() {
        let date = Date(timeIntervalSince1970: 1_793_491_200)
        for template in ["{number}", "{model}", "{job}", "{serial}"] {
            for name in Self.hostileNames {
                let context = TemplateContext(captureDate: date, captureOffsetSeconds: nil, fileDate: date, importDate: date,
                                              make: nil, model: nil, serial: nil, lens: nil, originalName: name,
                                              sequence: 1, counter: 1, jobCode: "")
                let rendered = ImportTemplate(folder: "", fileName: template).render(context)
                #expect(rendered.folders.isEmpty)
                let file = rendered.fileName
                #expect(!file.contains("/") && !file.contains("\\") && !file.contains("\u{0}"), "\(template) \(name) → \(file)")
                #expect(!file.hasPrefix(".") && file != ".." && !file.isEmpty, "\(template) \(name) → \(file)")
            }
        }
        // Ordinary names are as before.
        let context = TemplateContext(captureDate: date, captureOffsetSeconds: nil, fileDate: date, importDate: date,
                                      make: nil, model: nil, serial: nil, lens: nil, originalName: "IMG_0001.JPG",
                                      sequence: 1, counter: 1, jobCode: "")
        #expect(ImportTemplate(folder: "", fileName: "{model}").render(context).fileName == "IMG_0001.JPG")
        #expect(ImportTemplate(folder: "", fileName: "{name}").render(context).fileName == "IMG_0001.JPG")
        // A name that sanitizes to nothing gets the constant stem.
        let dots = TemplateContext(captureDate: date, captureOffsetSeconds: nil, fileDate: date, importDate: date,
                                   make: nil, model: nil, serial: nil, lens: nil, originalName: "\u{1}\u{2}.jpg",
                                   sequence: 1, counter: 1, jobCode: "")
        #expect(ImportTemplate(folder: "", fileName: "{model}").render(dots).fileName == "photo.jpg")
        // An extension that is not plain letters and digits is dropped.
        let odd = TemplateContext(captureDate: date, captureOffsetSeconds: nil, fileDate: date, importDate: date,
                                  make: nil, model: nil, serial: nil, lens: nil, originalName: "a.j:pg",
                                  sequence: 1, counter: 1, jobCode: "")
        #expect(ImportTemplate(folder: "", fileName: "{name}").render(odd).fileName == "a")
    }

    @Test("A name with a separator, NUL, or that is . or .., is not listed (F1, layer 2)")
    func namesAtDecode() throws {
        for name in Self.hostileNames + [".", "..", ""] {
            #expect(!RemoteAsset.isPlainFileName(name), "\(name)")
            let json = try JSONSerialization.data(withJSONObject: [
                "id": "a", "type": "IMAGE", "originalFileName": name, "checksum": "x",
                "fileCreatedAt": "2026-01-01T00:00:00.000Z", "ownerId": "me", "visibility": "timeline",
            ])
            let asset = try JSONDecoder().decode(ImmichDTO.Asset.self, from: json)
            #expect(asset.remoteAsset(ownerID: "me") == nil, "\(name)")
        }
        #expect(RemoteAsset.isPlainFileName("IMG 0001 (1).JPG"))
    }

    @Test("Hostile names imported end to end land inside the destination or not at all (F1)")
    func endToEnd() async throws {
        for template in ["{job}", "{number}"] {
            try await RepositoryFiles.withTemporaryDirectory { root in
                let setup = try await RemoteImportTests.setup(assets: try FakeImmichServer.jpegAssets(count: Self.hostileNames.count))
                // Past the decoder, as a server bug or a later decoder change might.
                let listed = try await RemoteImportTests.listed(setup)
                let hostile = zip(listed, Self.hostileNames).map { asset, name in
                    var asset = asset
                    asset.fileName = name
                    return asset
                }
                let destination = root.appending(path: "Photos/Inner")
                let options = RemoteImportOptions(destination: destination, template: ImportTemplate(folder: "", fileName: template),
                                                  project: .named("Home - All Photos"), link: setup.link)
                let result = await RemoteImportTests.importer(setup).run(hostile, options: options)
                let files = RemoteImportTests.files(in: root)
                #expect(result.imported + result.failures.count == hostile.count, "\(template)")
                #expect(files.count == result.imported)
                #expect(files.allSatisfy { $0.hasPrefix("Photos/Inner/") && !$0.dropFirst(13).contains("/") }, "\(template) \(files)")
                let paths = try await setup.catalog.database.read { db in try String.fetchAll(db, sql: "SELECT relativePath FROM image") }
                #expect(paths.allSatisfy { !$0.contains("..") })
                #expect(paths.count == files.count)
            }
        }
    }

    @Test("Containment compares path components, not text (F1, layer 3)")
    func containment() {
        let folder = URL(fileURLWithPath: "/a/b")
        #expect(RemoteImporter.isInside(URL(fileURLWithPath: "/a/b/c.jpg"), folder: folder))
        #expect(RemoteImporter.isInside(URL(fileURLWithPath: "/a/b/x/y/c.jpg"), folder: folder))
        #expect(!RemoteImporter.isInside(URL(fileURLWithPath: "/a/bc/c.jpg"), folder: folder))
        #expect(!RemoteImporter.isInside(URL(fileURLWithPath: "/a/b/../c.jpg"), folder: folder))
        #expect(!RemoteImporter.isInside(URL(fileURLWithPath: "/a/b/x/../../c.jpg"), folder: folder))
        #expect(!RemoteImporter.isInside(URL(fileURLWithPath: "/a/b"), folder: folder))
        #expect(RemoteImporter.isInside(URL(fileURLWithPath: "/a/b/./c.jpg"), folder: URL(fileURLWithPath: "/a/b/")))
        // A folder that exists under /private/tmp and a new file in it agree
        // (standardizedFileURL would drop /private from one and not the other).
        let existing = FileManager.default.temporaryDirectory
        #expect(RemoteImporter.isInside(existing.appending(path: "new-\(UUID().uuidString)/a.jpg"), folder: existing))
        #expect(RemoteImporter.isInside(URL(fileURLWithPath: "/private/tmp/new-\(UUID().uuidString)/x/a.jpg"),
                                        folder: URL(fileURLWithPath: "/private/tmp")))
    }

    @Test("A failed save puts the previous key back, or removes a new one (F2)")
    func keyRollback() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let url = root.appending(path: "catalog.sqlite")
            let writable = try Catalog.open(at: url)
            let store = InMemoryKeyStore()
            let existing = try await writable.saveRemoteService(RemoteServiceRecord(name: "Home", address: "https://old.example.com"))
            try store.setKey("old-key", account: existing.uuid)
            // A catalog that refuses every write.
            let readOnly = try Catalog.openForReading(at: url)
            var edited = existing
            edited.address = "https://new.example.com"
            guard case .catalogFailed = await readOnly.saveRemoteService(edited, key: "new-key", keys: store) else {
                Issue.record("the save should fail")
                return
            }
            #expect(try store.key(account: existing.uuid) == "old-key")
            let added = RemoteServiceRecord(name: "Other", address: "https://other.example.com")
            guard case .catalogFailed = await readOnly.saveRemoteService(added, key: "fresh", keys: store) else {
                Issue.record("the save should fail")
                return
            }
            #expect(try store.key(account: added.uuid) == nil)
            // A save that works stores both.
            guard case .saved = await writable.saveRemoteService(edited, key: "new-key", keys: store) else {
                Issue.record("the save should pass")
                return
            }
            #expect(try store.key(account: existing.uuid) == "new-key")
            #expect(try await writable.remoteServices().first?.address == "https://new.example.com")
            // A refusing store changes nothing.
            store.failing = true
            guard case .keychainRefused = await writable.saveRemoteService(added, key: "x", keys: store) else {
                Issue.record("the store should refuse")
                return
            }
            store.failing = false
            #expect(try await writable.remoteServices().count == 1)
        }
    }

    @Test("Hosts with Unicode digits or letters are not local names (note b)")
    func unicodeHosts() {
        #expect(!LocalNetwork.isLocal(host: "⒏⒏"))
        #expect(!LocalNetwork.isLocal(host: "１２７"))
        #expect(!LocalNetwork.isLocal(host: "ｎａｓ"))
        #expect(!LocalNetwork.isLocal(host: "nås"))
        #expect(LocalNetwork.isLocal(host: "nas"))
    }
}
