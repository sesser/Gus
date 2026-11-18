import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

/// AC10 (PRD #203 R11): the one table of tool identifiers, its String Catalog
/// entries, the verbatim fallback, and no file type of the format's anywhere.
@Suite("Preset packs: tool table")
struct PresetPackTableTests {
    typealias F = PackFixture

    /// A template that makes the mapping report `tool`, so every case of the table is one it handles.
    static func fixture(for tool: LuminarTool) -> (tools: [[String: Any]], resources: [String: Data], layers: [[String: Any]]?) {
        let develop = "MIPLDevelopCommonEffectID"
        switch tool {
        case .develop: return ([F.tool(.develop, F.effect(develop, F.param("Contrast", 10)))], [:], nil)
        case .rawDevelop: return ([F.tool(.rawDevelop, F.effect("MIPLRawDevelopEffect", F.param("Contrast", 10)))], [:], nil)
        case .lookUpTable: return ([F.lutTool()], ["TABLE.CUBE": F.identityCube], nil)
        case .color: return ([F.tool(.color, F.effect("MIPLVibranceEffect", F.param("Vibrance", 5)))], [:], nil)
        case .colorToning:
            return ([F.tool(.colorToning, F.effect("MIPLSplitToningEffect", F.param("ShadowsSaturation", 10)))], [:], nil)
        case .grain: return ([F.tool(.grain, F.effect("MIPLGrainNewEffect", F.param("Amount", 10)))], [:], nil)
        case .vignette: return ([F.tool(.vignette, F.effect("MIPLVignetteEffect", F.param("Amount", 10)))], [:], nil)
        case .sharpening: return ([F.tool(.develop, F.effect(tool.rawValue, F.param("Amount", 10)))], [:], nil)
        case .dehaze, .goldenHour, .foliage:
            return ([F.tool("LandscapeEnhancerAdjustmentLayer", F.effect(tool.rawValue, F.param("Amount", 10)))], [:], nil)
        case .supercontrast: return ([F.tool(.supercontrast, F.effect("MIPLSmartContrastEffect", F.param("Shadows", 10)))], [:], nil)
        case .matte: return ([F.tool(.matte, F.effect("MIPLFadeEffect", F.param("Amount", 10)))], [:], nil)
        case .colorBalance, .warmAndCoolColors, .colorContrast:
            let parameter = tool == .warmAndCoolColors ? "Warm Colors" : "SRed"
            return ([F.tool("ColorEnhancerAdjustmentLayer", F.effect(tool.rawValue, F.param(parameter, 10)))], [:], nil)
        case .warmth, .vividness:
            return ([F.tool("ColorEnhancerAdjustmentLayer", F.effect("MIPLBrillianceWarmthEffect", F.param(tool.rawValue, 10)))], [:], nil)
        case .structure: return ([F.tool(.structure, F.effect("MIPLAIStructureEffect", F.param("Amount", 10)))], [:], nil)
        case .detailsEnhancer:
            return ([F.tool("DetailsEnhancerAdjustmentLayer", F.effect(tool.rawValue, F.param("Overall_Small_Detail", 10)))], [:], nil)
        case .dramatic: return ([F.tool(.dramatic, F.effect("MIPLComplexBleachEffect", F.param("Amount", 10)))], [:], nil)
        case .blackAndWhite: return ([F.tool(.blackAndWhite, F.effect("MIPLBWChannels_v1_Effect", F.param("Apply", 10)))], [:], nil)
        case .layers:
            let tools = [F.tool(.color, F.effect("MIPLVibranceEffect", F.param("Vibrance", 5)))]
            return (tools, [:], [F.layer(tools, opacity: "0.5")])
        case .accentAI, .skyEnhancer:
            return ([F.tool("AIEnhanceAdjustmentLayer", F.effect(tool.rawValue, F.param("Amount", 10)))], [:], nil)
        case .atmosphere, .glow, .highKey, .aiNoiseReduction:
            return ([F.tool(tool, F.effect("Effect", F.param("Amount", 10)))], [:], nil)
        case .hueShift, .removeColorCast:
            return ([F.tool(.color, F.effect(tool.rawValue, F.param("Amount", 10)))], [:], nil)
        case .masks: return ([F.tool(.color, F.effect("MIPLVibranceEffect", F.param("Vibrance", 5)), mask: "m")], [:], nil)
        case .smartTone, .texture: return ([F.tool(.develop, F.effect(develop, F.param(tool.rawValue, 10)))], [:], nil)
        case .noiseReduction, .lensCorrection:
            return ([F.tool(.develop, F.effect(tool.rawValue, F.param("Amount", 10)))], [:], nil)
        }
    }

    /// Every identifier in the table is one the mapping handles: each case is reported by name from a template.
    @Test(arguments: LuminarTool.allCases)
    func everyToolInTheTableIsOneTheMappingHandles(_ tool: LuminarTool) {
        let fixture = Self.fixture(for: tool)
        let result = F.convert(fixture.tools, resources: fixture.resources, layers: fixture.layers)
        #expect(result.tools.contains { $0.tool == .known(tool) }, "\(tool) is in the table but the mapping never reports it")
    }

    /// The tools PRD R6 names are all in the table, and all left out.
    @Test func theLeftOutToolsOfR6AreInTheTable() {
        let r6: [LuminarTool] = [.accentAI, .skyEnhancer, .atmosphere, .glow, .highKey, .goldenHour, .foliage,
                                 .colorContrast, .removeColorCast, .hueShift, .masks]
        for tool in r6 {
            let fixture = Self.fixture(for: tool)
            let result = F.convert(fixture.tools, resources: fixture.resources, layers: fixture.layers)
            #expect(result.tools.contains(LuminarToolReport(tool: .known(tool), status: .leftOut)), "\(tool)")
        }
    }

    @Test func aToolNotInTheTableIsReportedVerbatim() {
        for identifier in ["MIPLSomethingNew_v3", "mixed Case tool", "", "  ", "Ünïcode"] {
            #expect(LuminarToolReference(identifier: identifier) == .unknown(identifier))
            let result = F.convert([F.tool(identifier, F.effect("E", F.param("Amount", 3)))])
            #expect(result.tools == [LuminarToolReport(tool: .unknown(identifier), status: .leftOut)])
        }
        #expect(LuminarToolReference(identifier: "MIPLSkyEnhancerEffect") == .known(.skyEnhancer))
    }

    /// The catalog's tool names are the table's localization: one entry per case, none other, each with its comment;
    /// and the app's name switch uses each key once.
    @Test func theCatalogHoldsExactlyTheTablesToolNames() throws {
        let catalog = try LocalizationTests.catalog()
        let prefix = "presetPackTool."
        let comment = "Name of a tool in an imported preset pack. A proper name: leave it as is if there is no usual translation."
        let keys = Set(catalog.keys.filter { $0.hasPrefix(prefix) })
        #expect(keys == Set(LuminarTool.allCases.map { "\(prefix)\($0)" }))
        let commented = catalog.filter { ($0.value as? [String: Any])?["comment"] as? String == comment }.map(\.key)
        #expect(Set(commented) == keys, "an entry with the tool-name comment that is not one of the table's")
        let source = try String(contentsOf: RepositoryFiles.url("Sources/PhotoApp/Model/PresetActions.swift"), encoding: .utf8)
        for tool in LuminarTool.allCases {
            #expect(source.components(separatedBy: "\"\(prefix)\(tool)\"").count == 2, "\(tool) named once in PresetText")
        }
        // Nowhere else in the app's code.
        for path in ["Sources/PhotoApp", "Sources/PhotoUI", "Sources/PhotoImporter"].flatMap(RepositoryFiles.files(under:))
            where path.hasSuffix(".swift") && !path.hasSuffix("PresetActions.swift") {
            #expect(!(try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)).contains(prefix), "\(path)")
        }
    }

    /// No file type, UTI or document type for packs, and the Finder's open path takes only the app's preset files.
    @Test func packsAreNotAFileTypeOfTheApps() throws {
        for plist in ["Support/Info.plist", "Support/Importer-Info.plist"] {
            let text = try String(contentsOf: RepositoryFiles.url(plist), encoding: .utf8).lowercased()
            #expect(!text.contains("lnpc"), "\(plist)")
            #expect(!text.contains("luminar"), "\(plist)")
        }
        #expect(!PresetFile.fileExtensions.contains(LuminarPack.fileExtension))
        let application = try String(contentsOf: RepositoryFiles.url("Sources/PhotoApp/PhotoApplication.swift"), encoding: .utf8)
        #expect(application.contains("PresetFile.fileExtensions.contains($0.pathExtension.lowercased())"))
        #expect(!application.contains("PresetImport.fileExtensions"))
    }

    /// The open panel filters by these types: an extension without one would be dropped silently by
    /// `compactMap` and its files greyed out (design §1.1, review F1). No type is declared for any.
    @Test func everyImportExtensionHasAType() {
        for fileExtension in PresetImport.fileExtensions {
            #expect(UTType(filenameExtension: fileExtension) != nil, "\(fileExtension)")
        }
        #expect(PresetImport.fileExtensions.compactMap { UTType(filenameExtension: $0) }.count
                == PresetImport.fileExtensions.count)
    }

    /// No string of ours names the format's application or its maker.
    @Test func noStringNamesTheFormatsApplication() throws {
        let catalog = try LocalizationTests.catalog()
        for (key, value) in catalog {
            let text = (key + " " + String(describing: value)).lowercased()
            #expect(!text.contains("luminar") && !text.contains("skylum"), "\(key)")
        }
    }
}

@Suite("Preset packs: report lines")
struct PresetPackReportLineTests {
    @Test func linesGroupByStatusInToolOrder() {
        let report = PresetImport.PackPresetReport(id: 0, name: "Look", isUnreadable: false, tools: [
            LuminarToolReport(tool: .known(.develop), status: .mapped),
            LuminarToolReport(tool: .known(.structure), status: .approximated, controls: [.clarity]),
            LuminarToolReport(tool: .unknown("MIPLNew"), status: .leftOut),
            LuminarToolReport(tool: .known(.accentAI), status: .leftOut),
            LuminarToolReport(tool: .known(.grain), status: .mapped),
            LuminarToolReport(tool: .unknown(""), status: .leftOut),
        ])
        #expect(report.mapped == [.develop, .grain])
        let approximated: [LuminarTool] = report.approximated.map(\.0)
        let controls: [PresetControl] = report.approximated.flatMap(\.1)
        #expect(approximated == [.structure])
        #expect(controls == [.clarity])
        #expect(report.leftOut == [.accentAI])
        #expect(report.unrecognized == ["MIPLNew", ""])
        // Tools not recognized count as left out.
        let counts: [Int] = [report.count(LuminarToolReport.Status.mapped), report.count(LuminarToolReport.Status.approximated),
                             report.count(LuminarToolReport.Status.leftOut)]
        #expect(counts == [2, 1, 3])
    }
}
