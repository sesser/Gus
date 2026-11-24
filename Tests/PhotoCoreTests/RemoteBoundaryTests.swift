import Foundation
import GRDB
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #271: where the key may go (AC1), what the standalone importer shows
/// (AC16) and the About window's network claim (AC17).
@Suite("Immich boundaries")
struct RemoteBoundaryTests {
    static let distinctiveKey = "KEY-4f1c9e-never-stored-anywhere"

    @Test("After an import the key is in the key store and in no catalog row (AC1)")
    func keyOnlyInTheStore() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let server = try await FakeImmichServer()
            server.setKey(Self.distinctiveKey)
            server.setAssets(try FakeImmichServer.jpegAssets(count: 2))
            let catalog = try Catalog.makeInMemory()
            let store = InMemoryKeyStore()
            let address = try RemoteConnectionTests.address(server.address)
            let service = try await catalog.saveRemoteService(RemoteServiceRecord(name: "Home", address: address.normalized,
                                                                                  allowsUnencrypted: true))
            try store.setKey(Self.distinctiveKey, account: service.uuid)
            #expect(try store.key(account: service.uuid) == Self.distinctiveKey)
            let client = try ImmichClient(connection: RemoteConnection(address: address, key: Self.distinctiveKey,
                                                                       unencryptedConfirmed: true))
            guard case .passed = await client.check() else {
                Issue.record("the check passes with the server's key")
                return
            }
            let page = try await client.page(scope: RemoteScope(), cursor: nil, ownerID: FakeImmichServer.ownerID)
            let result = await RemoteImporter(catalog: catalog, sidecars: nil, source: client,
                                              metadataReader: ImageIOMetadataReader(), retry: .none)
                .run(page.assets, options: RemoteImportOptions(destination: root.appending(path: "Photos"),
                                                               project: .named("Home - All Photos"),
                                                               link: RemoteLinkTarget(provider: .immich,
                                                                                      address: address.normalized,
                                                                                      serviceID: service.id)))
            #expect(result.imported == 2)
            // Every text and blob value of every table.
            let dump = try await catalog.database.read { db -> String in
                var text = ""
                let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                for table in tables {
                    for row in try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\"") {
                        for value in row.databaseValues {
                            switch value.storage {
                            case .string(let string): text += string + "\n"
                            case .blob(let data): text += String(decoding: data, as: UTF8.self) + "\n"
                            default: break
                            }
                        }
                    }
                }
                return text
            }
            #expect(!dump.isEmpty)
            #expect(!dump.contains(Self.distinctiveKey))
            // Nor in what the import reports.
            #expect(!"\(result.failures) \(RemoteImportReport(result).lines)".contains(Self.distinctiveKey))
            #expect(!"\(client.connection)".contains(Self.distinctiveKey))
        }
    }

    @Test("The key is read only to build a connection and sent only as the request header (AC1, R7)")
    func keyUsesInSources() throws {
        // The server code (ImportGridProbe's "key" is a keyboard key).
        let folders = ["Sources/PhotoCore/Remote", "Sources/PhotoUI/Import/ServerSheet.swift",
                       "Sources/PhotoUI/Import/ServerSource.swift", "Sources/PhotoUI/Import/ServerText.swift",
                       "Sources/PhotoApp/Model/DebugServerCommands.swift", "Sources/PhotoCore/Catalog/RemoteServices.swift"]
        var uses: [String] = []
        for folder in folders {
            let paths = folder.hasSuffix(".swift") ? [folder] : RepositoryFiles.files(under: folder)
            for path in paths where path.hasSuffix(".swift") {
                let source = try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
                for line in source.components(separatedBy: "\n") where line.contains("connection.key") {
                    uses.append(line.trimmingCharacters(in: .whitespaces))
                }
                // No log line or print interpolates anything named key.
                for line in source.components(separatedBy: "\n")
                where (line.contains("log.") || line.contains("print(")) && line.range(of: #"\\\([^)]*[kK]ey\b"#, options: .regularExpression) != nil {
                    Issue.record("a log or print line interpolates a key: \(path): \(line)")
                }
            }
        }
        #expect(uses == [#"if sendsKey { request.setValue(connection.key, forHTTPHeaderField: "x-api-key") }"#])
    }

    @Test("The standalone importer shows no server (AC16)")
    func importerHasNoServers() throws {
        var importer = ""
        for path in RepositoryFiles.files(under: "Sources/PhotoImporter") where path.hasSuffix(".swift") {
            importer += try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
        }
        for word in ["Server", "Remote", "Immich", "Keychain", "KeyStore"] {
            #expect(!importer.contains(word), "\(word)")
        }
        #expect(importer.contains("ImportCommands(includesLibraryItems: false)"))
        // Every server item of the shared window is behind the library: the
        // Source pop-up's rows and Add Server…, the empty state, and the menus.
        let window = try String(contentsOf: RepositoryFiles.url("Sources/PhotoUI/Import/ImportWindow.swift"), encoding: .utf8)
        #expect(window.contains("if !model.copiesOnly {\n                    ForEach(model.servers)"))
        #expect(window.contains("if !model.copiesOnly {\n                Button(\"Add Server…\")"))
        #expect(window.contains("case .noSource where model.copiesOnly:"))
        let commands = try String(contentsOf: RepositoryFiles.url("Sources/PhotoUI/Import/ImportCommands.swift"), encoding: .utf8)
        #expect(commands.contains("if includesLibraryItems {\n                // Servers"))
        // Servers are read from the library's catalog, which the importer has not.
        let source = try String(contentsOf: RepositoryFiles.url("Sources/PhotoUI/Import/ServerSource.swift"), encoding: .utf8)
        #expect(source.contains("guard let catalog = library?.catalog else { return }"))
    }

    @Test("The About window's code has no network code (AC17)")
    func aboutIsNetworkFree() throws {
        let paths = (RepositoryFiles.files(under: "Sources/PhotoUI/About") + RepositoryFiles.files(under: "Sources/PhotoCore/About"))
            .filter { $0.hasSuffix(".swift") }
        #expect(!paths.isEmpty)
        for path in paths {
            let source = try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
            for word in ["URLSession", "URLRequest", "NWConnection", "Network", "RemoteHTTPSession", "ImmichClient"] {
                #expect(!source.contains(word), "\(path) uses \(word)")
            }
        }
        // The guide says what is true: the About window contacts nothing; the
        // app contacts only a server the person added.
        let guide = try String(contentsOf: RepositoryFiles.url("docs/USER_GUIDE.md"), encoding: .utf8)
        #expect(!guide.contains("the app itself\ncontacts nothing") && !guide.contains("the app itself contacts nothing"))
        #expect(guide.contains("window contacts nothing"))
    }
}
