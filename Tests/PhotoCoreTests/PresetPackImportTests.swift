import Foundation
import Testing
@testable import PhotoCore

@Suite("Preset packs: import")
struct PresetPackImportTests {
    typealias F = PackFixture

    static func importing(_ files: [String: Data], language: String = "en", into catalog: Catalog,
                          store: LookTableStore, root: URL) async throws -> PresetImport.Result {
        var urls: [URL] = []
        for name in files.keys.sorted() {
            let url = root.appending(path: name)
            try files[name]!.write(to: url)
            urls.append(url)
        }
        return try await PresetImport.run(PresetImport.scan(urls, language: language), catalog: catalog, store: store)
    }

    /// AC1, AC2, AC3: several packs at once beside an existing format, each one collection in its order,
    /// its tables in a look-up table collection of its name.
    @Test func importsPacksBesideOtherFormats() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            #expect(PresetImport.fileExtensions.contains("lnpc"))
            let catalog = try Catalog.makeInMemory()
            let store = LookTableStore(directory: root.appending(path: "LUTs"))
            let second = [F.Preset(uuid: "55555555-0000-0000-0000-000000000000", name: "Solo", german: nil,
                                   tools: [F.lutTool("B.cube", amount: 60)], resources: ["B.cube": F.swapCube])]
            let other = try PresetFile(presets: [AdjustmentPreset(name: "Bright", adjustments: {
                var values = Adjustments()
                values.exposure.ev = 0.5
                return values
            }())], store: store).data()
            let result = try await Self.importing([
                "A_Pack.lnpc": F.packData(),
                "B.lnpc": ZipWriter.archive(F.files(name: "Second Pack", germanName: nil, presets: second)),
                "Other.\(PresetFile.fileExtension)": other,
            ], into: catalog, store: store, root: root)

            #expect(result.failures.isEmpty)
            #expect(result.includesPacks)
            #expect(result.packs.map(\.name) == ["Test Pack", "Second Pack"])
            #expect(result.packs.map { $0.presets.compactMap(\.name) } == [["Beta", "Alpha"], ["Solo"]])
            #expect(result.packs.map(\.tableCount) == [1, 1])
            #expect(result.packs.map(\.addedTables) == [1, 1])
            #expect(result.packs.map(\.added) == [2, 1])
            #expect(result.otherImported.map(\.name) == ["Bright"])
            #expect(result.otherPresets.imported.count == 1)
            #expect(result.addedTables == 2)

            let saved = try await catalog.adjustmentPresets()
            #expect(Set(saved.map(\.collection)) == ["", "Test Pack", "Second Pack"])
            let alpha = try #require(saved.first { $0.name == "Alpha" })
            #expect(alpha.groups == [.lookTable, .light])
            let identifier = Digest.sha256Hex(F.identityCube)
            #expect(alpha.adjustments.lookTable.identifier == identifier)
            #expect(alpha.adjustments.lookTable.intensity == 80)
            #expect(store.contains(identifier))
            #expect(store.cube(for: identifier) != nil)
            let collections = try await catalog.lookTableCollections()
            #expect(collections.first { $0.name == "Test Pack" }?.entries.map(\.identifier) == [identifier])
            #expect(collections.first { $0.name == "Second Pack" }?.entries.map(\.identifier) == [Digest.sha256Hex(F.swapCube)])

            // Applying it renders with that table at the mapped intensity (the renderer's input).
            let applied = alpha.applied(onto: Adjustments())
            #expect(applied.effective.lookTable == LookTable(identifier: identifier, name: "Look", intensity: 80))
        }
    }

    /// AC2: German names with a German system language.
    @Test func namesInTheSystemLanguage() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let catalog = try Catalog.makeInMemory()
            let result = try await Self.importing(["p.lnpc": F.packData()], language: "de", into: catalog,
                                                  store: LookTableStore(directory: root.appending(path: "LUTs")), root: root)
            #expect(result.packs.first?.name == "Testpaket")
            #expect(try await catalog.adjustmentPresets().map { "\($0.collection)/\($0.name)" } == ["Testpaket/Alfa", "Testpaket/Beta"])
        }
    }

    /// AC5: a converted preset replaces only the groups it sets.
    @Test func applyingChangesOnlyTheGroupsItSets() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let catalog = try Catalog.makeInMemory()
            _ = try await Self.importing(["p.lnpc": F.packData()], into: catalog,
                                         store: LookTableStore(directory: root.appending(path: "LUTs")), root: root)
            let beta = try #require(try await catalog.adjustmentPresets().first { $0.name == "Beta" })
            #expect(beta.groups == [.presence])
            var photo = Adjustments()
            photo.exposure.ev = 1.2
            photo.presence.clarity = 30
            photo.grain.strength = 40
            photo.colorMixer[.red] = .init(hue: 8)
            let applied = beta.applied(onto: photo)
            #expect(applied.presence == Presence(vibrance: 20))
            var expected = photo
            expected.presence = Presence(vibrance: 20)
            #expect(applied == expected)
        }
    }

    /// AC7: importing the same pack again adds nothing; R8: the report says they were replaced.
    @Test func importingAgainDuplicatesNothing() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let catalog = try Catalog.makeInMemory()
            let store = LookTableStore(directory: root.appending(path: "LUTs"))
            let first = try await Self.importing(["p.lnpc": F.packData()], into: catalog, store: store, root: root)
            let presets = try await catalog.adjustmentPresets()
            let collections = try await catalog.lookTableCollections()
            let tableFiles = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "LUTs").path)
            #expect(first.packs[0].added == 2 && first.packs[0].replaced == 0)

            let again = try await Self.importing(["p.lnpc": F.packData()], into: catalog, store: store, root: root)
            #expect(again.packs[0].replaced == 2 && again.packs[0].added == 0)
            #expect(again.packs[0].addedTables == 0 && again.addedTables == 0)
            let presetsAfter = try await catalog.adjustmentPresets()
            #expect(presetsAfter.count == presets.count)
            #expect(presetsAfter.map(\.id) == presets.map(\.id))
            #expect(Set(presetsAfter.map(\.collection)).count == Set(presets.map(\.collection)).count)
            let collectionsAfter = try await catalog.lookTableCollections()
            #expect(collectionsAfter.count == collections.count)
            #expect(collectionsAfter.flatMap(\.entries).count == collections.flatMap(\.entries).count)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "LUTs").path).count == tableFiles.count)
        }
    }

    /// AC8: bad files are refused with their reason; a good one chosen with them imports.
    @Test func badFilesAreRefusedAndTheRestImport() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let catalog = try Catalog.makeInMemory()
            let good = F.packData()
            var noConfig = F.files(presets: F.twoPresets())
            noConfig["Config/config.json"] = nil
            let result = try await Self.importing([
                "a-truncated.lnpc": good.prefix(good.count - 100),
                "b-no-config.lnpc": ZipWriter.archive(noConfig),
                "c-text.lnpc": Data("just text".utf8),
                "d-good.lnpc": good,
            ], into: catalog, store: LookTableStore(directory: root.appending(path: "LUTs")), root: root)
            #expect(result.failures.map(\.url.lastPathComponent) == ["a-truncated.lnpc", "b-no-config.lnpc", "c-text.lnpc"])
            #expect(result.failures.map(\.packFailure) == [.damaged, .missingConfig, .notAZip])
            #expect(result.packs.map(\.source.lastPathComponent) == ["d-good.lnpc"])
            #expect(result.includesPacks)
            #expect(try await catalog.adjustmentPresets().count == 2)
        }
    }

    /// Design §3: a preset that can't be read is skipped and named in its pack's report.
    @Test func anUnreadablePresetIsReportedAndTheRestImport() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            var files = F.files(presets: F.twoPresets())
            files["\(F.packID)/22222222-0000-0000-0000-000000000000.lnp/template.lmps"] = Data("{".utf8)
            let catalog = try Catalog.makeInMemory()
            let result = try await Self.importing(["p.lnpc": ZipWriter.archive(files)], into: catalog,
                                                  store: LookTableStore(directory: root.appending(path: "LUTs")), root: root)
            let pack = try #require(result.packs.first)
            #expect(pack.presets.map(\.isUnreadable) == [true, false])
            #expect(pack.importedCount == 1)
            #expect(try await catalog.adjustmentPresets().map(\.name) == ["Alpha"])
        }
    }

    /// A table that is not a readable cube is not installed: the preset leaves it out and says so, keeps
    /// the table tool's contrast and saturation and says so too, and the pack counts no table (code review C6).
    @Test func anUnreadableTableKeepsItsApproximatedValues() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let presets = [F.Preset(uuid: "77777777-0000-0000-0000-000000000000", name: "Broken", german: nil,
                                    tools: [F.lutTool("X.cube", contrast: 20)], resources: ["X.cube": Data("not a cube".utf8)])]
            let catalog = try Catalog.makeInMemory()
            let result = try await Self.importing(["p.lnpc": F.packData(presets)], into: catalog,
                                                  store: LookTableStore(directory: root.appending(path: "LUTs")), root: root)
            let pack = try #require(result.packs.first)
            #expect(pack.tableCount == 0)
            #expect(pack.presets.first?.tools == [
                LuminarToolReport(tool: .known(.lookUpTable), status: .approximated, controls: [.contrast, .saturation]),
                LuminarToolReport(tool: .known(.lookUpTable), status: .leftOut),
            ])
            let saved = try #require(try await catalog.adjustmentPresets().first)
            #expect(saved.groups == [.light])
            #expect(saved.adjustments.tone.contrast == 20)
        }
    }

    /// A table that is not a readable cube is not installed: the preset leaves it out and says so.
    @Test func anUnreadableTableIsLeftOut() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let presets = [F.Preset(uuid: "66666666-0000-0000-0000-000000000000", name: "Broken", german: nil,
                                    tools: [F.lutTool("X.cube"), F.tool(.grain, F.effect("MIPLGrainNewEffect", F.param("Amount", 10)))],
                                    resources: ["X.cube": Data("not a cube".utf8)])]
            let catalog = try Catalog.makeInMemory()
            let result = try await Self.importing(["p.lnpc": F.packData(presets)], into: catalog,
                                                  store: LookTableStore(directory: root.appending(path: "LUTs")), root: root)
            let report = try #require(result.packs.first?.presets.first)
            #expect(report.tools.map(\.status) == [.mapped, .leftOut])
            #expect(report.tools.last?.tool == .known(.lookUpTable))
            let saved = try #require(try await catalog.adjustmentPresets().first)
            #expect(saved.groups == [.grain])
            #expect(saved.adjustments.lookTable == LookTable())
        }
    }

    /// Design §1.2: a pack in a chosen folder keeps its own name; the folder's other presets keep today's rule.
    @Test func aFolderNeverNamesAPack() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "My Folder")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try F.packData().write(to: folder.appending(path: "p.lnpc"))
            var values = Adjustments()
            values.exposure.ev = 1
            try PresetFile(presets: [AdjustmentPreset(name: "Loose", adjustments: values)],
                           store: LookTableStore(directory: root.appending(path: "x"))).data()
                .write(to: folder.appending(path: "Loose.\(PresetFile.fileExtension)"))
            let catalog = try Catalog.makeInMemory()
            let result = try await PresetImport.run(PresetImport.scan([folder], language: "en"), catalog: catalog,
                                                    store: LookTableStore(directory: root.appending(path: "LUTs")))
            #expect(result.packs.map(\.name) == ["Test Pack"])
            let saved = try await catalog.adjustmentPresets()
            #expect(Set(saved.map { "\($0.collection)/\($0.name)" }) == ["Test Pack/Alpha", "Test Pack/Beta", "My Folder/Loose"])
        }
    }

    /// Two packs with presets of the same name are never taken for copies of each other.
    @Test func samePresetNamesInTwoPacksStayApart() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let catalog = try Catalog.makeInMemory()
            let result = try await Self.importing([
                "one.lnpc": F.packData(name: "One"),
                "two.lnpc": ZipWriter.archive(F.files(name: "Two", germanName: nil, presets: F.twoPresets())),
            ], into: catalog, store: LookTableStore(directory: root.appending(path: "LUTs")), root: root)
            #expect(result.packs.map(\.importedCount) == [2, 2])
            #expect(try await catalog.adjustmentPresets().count == 4)
        }
    }
}
