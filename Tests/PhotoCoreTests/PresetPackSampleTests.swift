import Foundation
import Testing
@testable import PhotoCore

/// Checks with real preset packs, which are never committed. Opt in with
/// `LUMINAR_PACKS=<folder of .lnpc files>`; add
/// `LUMINAR_PROTOTYPE_OUTPUT=<folder of the prototype's preset files>` to
/// compare every converted preset with the prototype's conversion of it.
@Suite("Preset packs: real files")
struct PresetPackSampleTests {
    static let folder = ProcessInfo.processInfo.environment["LUMINAR_PACKS"].map { URL(fileURLWithPath: $0) }
    static let prototypeFolder = ProcessInfo.processInfo.environment["LUMINAR_PROTOTYPE_OUTPUT"].map { URL(fileURLWithPath: $0) }

    static var packFiles: [URL] {
        guard let folder else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == LuminarPack.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test(.enabled(if: folder != nil, "set LUMINAR_PACKS to a folder of .lnpc files"))
    func everyPresetImportsWithItsTables() async throws {
        let files = Self.packFiles
        try #require(!files.isEmpty, "no .lnpc files in LUMINAR_PACKS")
        try await RepositoryFiles.withTemporaryDirectory { root in
            let catalog = try Catalog.makeInMemory()
            let store = LookTableStore(directory: root.appending(path: "LUTs"))
            let start = ContinuousClock.now
            let scan = PresetImport.scan(files, language: "en")
            let scanned = ContinuousClock.now
            let result = try await PresetImport.run(scan, catalog: catalog, store: store)
            let finished = ContinuousClock.now
            print("Read and converted \(files.count) packs in \(scanned - start); saved in \(finished - scanned)")
            let tablesStart = ContinuousClock.now
            let file = PresetFile(format: PresetFile.formatName, formatVersion: PresetFile.currentFormatVersion,
                                  presets: [], lookTables: scan.tables)
            _ = file.installTables(into: LookTableStore(directory: root.appending(path: "Timing")))
            print("Of which checking and installing \(scan.tables.count) tables alone takes \(ContinuousClock.now - tablesStart)")
            #expect(result.failures.isEmpty)
            #expect(result.packs.count == files.count)
            for pack in result.packs {
                #expect(pack.presets.allSatisfy { !$0.isUnreadable }, "\(pack.name)")
                #expect(pack.importedCount > 0)
                let left = pack.presets.flatMap(\.tools).filter { $0.status == .leftOut }.map(\.tool)
                let unknown = left.filter { if case .unknown = $0 { true } else { false } }
                let totals = [LuminarToolReport.Status.mapped, .approximated, .leftOut].map { status in
                    pack.presets.reduce(0) { $0 + $1.count(status) }
                }
                print("\(pack.name): \(pack.importedCount) presets, \(pack.tableCount) tables, \(pack.addedTables) added; "
                      + "\(totals[0]) mapped, \(totals[1]) approximated, \(totals[2]) left out; not recognized: \(unknown)")
            }
            let again = try await PresetImport.run(PresetImport.scan(files, language: "en"), catalog: catalog, store: store)
            #expect(again.addedTables == 0)
            #expect(again.packs.allSatisfy { $0.added == 0 })
        }
    }

    @Test(.enabled(if: folder != nil && prototypeFolder != nil,
                   "set LUMINAR_PACKS and LUMINAR_PROTOTYPE_OUTPUT"))
    func conversionsMatchThePrototype() throws {
        let prototypeFolder = try #require(Self.prototypeFolder)
        var compared = 0
        for file in Self.packFiles {
            for pack in try LuminarPack.read(contentsOf: file, language: "en") {
                let url = prototypeFolder.appending(path: "\(pack.name).\(PresetFile.fileExtension)")
                guard FileManager.default.fileExists(atPath: url.path) else {
                    print("No prototype output for \(pack.name)")
                    continue
                }
                let prototype = try PresetFile(data: Data(contentsOf: url))
                let byName = Dictionary(prototype.presets.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
                for preset in pack.presets {
                    let ours = LuminarMapping.convert(preset.template, resources: preset.resources)
                    guard let theirs = byName[preset.name] else {
                        #expect(ours.groups.isEmpty, "\(pack.name)/\(preset.name) is missing from the prototype's output")
                        continue
                    }
                    let theirGroups = Set((theirs.groups ?? []).compactMap(Adjustments.Group.init(rawValue:)))
                    #expect(ours.groups == theirGroups, "\(pack.name)/\(preset.name) groups")
                    let difference = Self.difference(ours.adjustments.editStack, theirs.settings)
                    #expect(difference == nil, "\(pack.name)/\(preset.name): \(difference ?? "")")
                    compared += 1
                }
            }
        }
        print("Compared \(compared) presets with the prototype's")
        #expect(compared > 0)
    }

    /// The first parameter that differs by more than rounding, or nil.
    static func difference(_ a: EditStack, _ b: EditStack) -> String? {
        let ours = Dictionary(a.operations.map { ($0.kind.rawValue, $0.parameters) }, uniquingKeysWith: { x, _ in x })
        let theirs = Dictionary(b.operations.map { ($0.kind.rawValue, $0.parameters) }, uniquingKeysWith: { x, _ in x })
        guard Set(ours.keys) == Set(theirs.keys) else { return "kinds \(ours.keys.sorted()) vs \(theirs.keys.sorted())" }
        for (kind, parameters) in ours {
            let other = theirs[kind] ?? [:]
            guard Set(parameters.keys) == Set(other.keys) else {
                return "\(kind) keys \(parameters.keys.sorted()) vs \(other.keys.sorted())"
            }
            for (key, value) in parameters where !close(value, other[key]!) {
                return "\(kind).\(key): \(value) vs \(other[key]!)"
            }
        }
        return nil
    }

    static func close(_ a: EditParameter, _ b: EditParameter) -> Bool {
        switch (a, b) {
        case (.number(let x), .number(let y)): abs(x - y) <= 2e-4
        case (.list(let x), .list(let y)): x.count == y.count && zip(x, y).allSatisfy { close($0, $1) }
        default: a == b
        }
    }
}
