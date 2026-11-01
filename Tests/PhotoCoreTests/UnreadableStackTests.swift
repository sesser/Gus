import Foundation
import GRDB
import Testing
@testable import PhotoCore

/// A stored stack this build cannot read (written by a newer build, or
/// damaged) is never written over: it may hold edits this build would lose.
@Suite("Unreadable edit stacks")
struct UnreadableStackTests {
    /// What a later build might write: a schema this build does not know.
    static let newerJSON = #"{"operations":[{"id":"7D6F0B0A-3C55-4C8E-9A64-0F1D2E3C4B5A","isEnabled":true,"#
        + #""kind":"localAdjustments","kindVersion":1,"parameters":{"masks":[{"amount":80}]}}],"schemaVersion":99}"#
    static let damagedJSON = #"{"operations": [{"kind": "#
    static let storedHash = String(repeating: "ab", count: 32)

    /// Writes `json` as the stored stack of `id`, as another build would.
    static func store(_ json: String, forVersion id: Int64, in catalog: Catalog) async throws {
        try await catalog.database.write { db in
            _ = try VersionRecord.filter(key: id).updateAll(db, [
                VersionRecord.Columns.editStack.set(to: json),
                VersionRecord.Columns.editStackHash.set(to: storedHash),
            ])
        }
    }

    static func stored(_ id: Int64, in catalog: Catalog) async throws -> (json: String, hash: String) {
        let version = try #require(try await catalog.version(id: id))
        return (version.editStack, version.editStackHash)
    }

    @Test("A newer schema and damaged JSON are told apart")
    func readFailures() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        try await Self.store(Self.newerJSON, forVersion: ids[0], in: fixture.catalog)
        try await Self.store(Self.damagedJSON, forVersion: ids[1], in: fixture.catalog)
        #expect(try await fixture.catalog.version(id: ids[0])?.editStackReadFailure == .newerVersion(99))
        #expect(try await fixture.catalog.version(id: ids[1])?.editStackReadFailure == .damaged)
    }

    @Test("Saving over an unreadable stack is refused and leaves its bytes", arguments: [newerJSON, damagedJSON])
    func singleWriteIsRefused(json: String) async throws {
        let fixture = try await CatalogFixture.make()
        let id = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        try await Self.store(json, forVersion: id, in: fixture.catalog)
        var bright = Adjustments()
        bright.exposure.ev = 1
        await #expect(throws: UnreadableEditStacks.self) {
            try await fixture.catalog.setEditStack(bright.editStack, forVersion: id)
        }
        let after = try await Self.stored(id, in: fixture.catalog)
        #expect(after.json == json && after.hash == Self.storedHash)
    }

    /// Paste Adjustments and applying a preset both go through `changeEditStacks`.
    @Test("Paste and presets change the readable photos and leave the unreadable one byte for byte")
    func bulkChangeSkipsUnreadable() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        try await Self.store(Self.newerJSON, forVersion: ids[0], in: fixture.catalog)
        var copied = Adjustments()
        copied.tone.contrast = 25
        let pasted = try await fixture.catalog.changeEditStacks(ofVersions: ids) { copied.pasted(onto: $0) }
        #expect(pasted.unreadable == [ids[0]: .newerVersion(99)])
        #expect(Array(pasted.after.keys) == [ids[1]])
        #expect(Adjustments(stack: try #require(try await fixture.catalog.version(id: ids[1])?.decodedEditStack()))
                .tone.contrast == 25)

        var warm = Adjustments()
        warm.whiteBalance.relativeTemperature = 30
        let preset = AdjustmentPreset(name: "warm", groups: [.whiteBalance], adjustments: warm)
        let applied = try await fixture.catalog.changeEditStacks(ofVersions: ids) { preset.applied(onto: $0) }
        #expect(applied.unreadable.keys.sorted() == [ids[0]])

        let after = try await Self.stored(ids[0], in: fixture.catalog)
        #expect(after.json == Self.newerJSON && after.hash == Self.storedHash)
    }

    @Test("A batch write that includes an unreadable stack writes nothing")
    func batchWriteIsRefused() async throws {
        let fixture = try await CatalogFixture.make()
        let ids = try await fixture.addMasters([CatalogFixture.master(1), CatalogFixture.master(2)])
        try await Self.store(Self.newerJSON, forVersion: ids[0], in: fixture.catalog)
        let readableBefore = try await Self.stored(ids[1], in: fixture.catalog)
        var bright = Adjustments()
        bright.exposure.ev = 1
        await #expect(throws: UnreadableEditStacks.self) {
            try await fixture.catalog.setEditStacks([ids[0]: bright.editStack, ids[1]: bright.editStack])
        }
        #expect(try await Self.stored(ids[0], in: fixture.catalog).json == Self.newerJSON)
        #expect(try await Self.stored(ids[1], in: fixture.catalog) == readableBefore)
    }

    @Test("photocli develop refuses an unreadable stack; render says why; query lists it without its stack")
    func commandsRefuse() async throws {
        try await CommandTests.withLibrary { library in
            let id = library.versionIDs[0]
            let catalog = try Catalog.open(at: library.locations.catalogFileURL)
            try await Self.store(Self.newerJSON, forVersion: id, in: catalog)

            let develop = await library.run("develop", "--version", String(id), "--set", "exposure.ev=1")
            #expect(develop.output.exitCode == 1)
            #expect(develop.json["code"] == "unreadableEditStack")
            #expect(develop.json["error"]?.stringValue?.contains("newer version") == true)
            let after = try await Self.stored(id, in: catalog)
            #expect(after.json == Self.newerJSON && after.hash == Self.storedHash)

            let render = await library.run("render", "--version", String(id), "--out",
                                           library.root.appending(path: "a.png").path)
            #expect(render.json["code"] == "unreadableEditStack")

            let query = await library.run("query", "images")
            #expect(query.output.exitCode == 0, "\(query.output.standardError)")
            let row = query.json["images"]?.arrayValue?.first { $0["versionID"] == JSONValue(id) }
            #expect(row?["editStack"] == .null)
            #expect(row?["unreadableEditStack"] == "newerVersion")
            #expect(row?["renderHash"] == .string(Self.storedHash))
        }
    }
}
