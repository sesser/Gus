import CoreImage
import Foundation
import Testing
@testable import PhotoCore

@Suite("Color mixer")
struct ColorMixerTests {
    @Test func roundTripsAndLeavesOutUnchangedBands() throws {
        var adjustments = Adjustments()
        adjustments.colorMixer[.blue] = .init(hue: -10, saturation: 0, luminance: -40)
        adjustments.colorMixer[.orange] = .init(saturation: 15)
        let stack = adjustments.editStack
        #expect(stack.operations.map(\.kind.rawValue) == ["colorMixer"])
        #expect(stack.operations[0].parameters == ["blueHue": .number(-10), "blueLuminance": .number(-40),
                                                   "orangeSaturation": .number(15)])
        #expect(Adjustments(stack: try EditStack.decode(from: try stack.jsonData())) == adjustments)

        adjustments.colorMixer[.blue] = .init()
        adjustments.colorMixer[.orange] = .init()
        #expect(adjustments.isDefault)
        #expect(adjustments.editStack == .identity)
    }

    @Test func bandsBlendBetweenTheirCenters() {
        var shifts = ColorMixer.Band.allCases.map { _ in ColorMixer.Shift() }
        shifts[ColorMixer.Band.allCases.firstIndex(of: .green)!] = .init(saturation: 100)
        let centers = ColorMixer.Band.allCases.map(\.centerHue)
        #expect(ColorMixerCube.blend(shifts, centers: centers, hue: 120).saturation == 100)
        #expect(ColorMixerCube.blend(shifts, centers: centers, hue: 60).saturation == 0)
        #expect(abs(ColorMixerCube.blend(shifts, centers: centers, hue: 90).saturation - 50) < 1e-9)
        #expect(ColorMixerCube.blend(shifts, centers: centers, hue: 350).saturation == 0)
        #expect(ColorMixerCube.hue(of: SIMD3(1, 0, 0), high: 1, chroma: 1) == 0)
        #expect(ColorMixerCube.hue(of: SIMD3(0, 0, 1), high: 1, chroma: 1) == 240)
        #expect(ColorMixerCube.hue(of: SIMD3(1, 0, 0.5), high: 1, chroma: 1) == 330)
    }

    /// The cube's value at a lattice point (indices 0 … dimension − 1).
    static func lattice(_ cube: ColorCube, _ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> {
        cube.data.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            let index = 4 * (r + g * cube.dimension + b * cube.dimension * cube.dimension)
            return SIMD3(floats[index], floats[index + 1], floats[index + 2])
        }
    }

    @Test func changesOnlyItsBandAndLeavesGreyAlone() {
        var mixer = ColorMixer()
        mixer[.red] = .init(saturation: -100)
        let top = ColorMixerCube.dimension - 1
        let cube = ColorMixerCube.make(mixer)
        let grey = Self.lattice(cube, top / 2, top / 2, top / 2)
        #expect(abs(grey.x - 0.5) < 1e-6 && abs(grey.y - 0.5) < 1e-6 && abs(grey.z - 0.5) < 1e-6)
        let red = Self.lattice(cube, top, 0, 0)
        #expect(abs(red.x - red.y) < 1e-4 && abs(red.y - red.z) < 1e-4)
        let blue = Self.lattice(cube, 0, 0, top)
        #expect(blue == SIMD3(0, 0, 1))

        mixer[.red] = .init(hue: 100)
        let turned = Self.lattice(ColorMixerCube.make(mixer), top, 0, 0)
        // Positive hue turns red toward orange: green rises above blue.
        #expect(turned.y > turned.z + 0.2)

        mixer[.red] = .init(luminance: -100)
        let darker = Self.lattice(ColorMixerCube.make(mixer), top, 0, 0)
        #expect(darker.x < 0.75 && darker.y == 0)
    }
}

@Suite("Preset groups and collections")
struct PresetGroupTests {
    @Test func applyingReplacesOnlyThePresetsGroups() {
        var look = Adjustments()
        look.presence.vibrance = -20
        look.exposure.ev = 1
        look.colorMixer[.aqua] = .init(hue: -5)
        let preset = AdjustmentPreset(name: "Look", groups: [.presence, .colorMixer, .grain], adjustments: look)
        #expect(preset.adjustments.exposure.ev == 0)

        var target = Adjustments()
        target.exposure.ev = -0.5
        target.presence.clarity = 30
        target.grain.strength = 40
        target.preserved = [EditOperation(kind: "brush")]
        let result = preset.applied(onto: target)
        #expect(result.exposure.ev == -0.5)
        #expect(result.presence == Presence(vibrance: -20))
        #expect(result.colorMixer[.aqua].hue == -5)
        #expect(result.grain.strength == 0)
        #expect(result.preserved.map(\.kind.rawValue) == ["brush"])

        let everything = AdjustmentPreset(name: "All", adjustments: look)
        #expect(everything.applied(onto: target) == look.pasted(onto: target))
    }

    @Test func groupsAndCollectionsAreStored() async throws {
        let fixture = try await CatalogFixture.make()
        var values = Adjustments()
        values.tone.contrast = 25
        _ = try await fixture.catalog.saveAdjustmentPresets([
            AdjustmentPreset(name: "Punch", collection: "Moody", groups: [.light], adjustments: values),
            AdjustmentPreset(name: "Punch", adjustments: values),
            AdjustmentPreset(name: "Alpha", collection: "Moody", adjustments: .none),
        ])
        values.tone.contrast = 35
        _ = try await fixture.catalog.saveAdjustmentPreset(
            AdjustmentPreset(name: "Punch", collection: "Moody", groups: [.light, .presence], adjustments: values))
        var presets = try await fixture.catalog.adjustmentPresets()
        #expect(presets.map { "\($0.collection)/\($0.name)" } == ["/Punch", "Moody/Alpha", "Moody/Punch"])
        #expect(presets[0].includesEveryGroup)
        #expect(presets[2].groups == [.light, .presence])
        #expect(presets[2].adjustments.tone.contrast == 35)

        let grouped = AdjustmentPresetCollection.grouping(presets)
        #expect(grouped.map(\.name) == ["", "Moody"])

        try await fixture.catalog.renameAdjustmentPresetCollection("Moody", to: "Dark")
        presets = try await fixture.catalog.adjustmentPresets()
        #expect(presets.filter { $0.collection == "Dark" }.count == 2)
        try await fixture.catalog.deleteAdjustmentPresets(inCollection: "Dark")
        #expect(try await fixture.catalog.adjustmentPresets().map(\.name) == ["Punch"])
    }
}

@Suite("Preset files")
struct PresetFileTests {
    @Test func embedsTablesAndInstallsThemElsewhere() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let source = LookTableStore(directory: root.appending(path: "A/LUTs"))
            let cubeURL = root.appending(path: "swap.cube")
            try CubeLUTTests.swapCube().write(to: cubeURL, atomically: true, encoding: .utf8)
            let table = try source.importFile(at: cubeURL)
            var values = Adjustments()
            values.lookTable = table
            values.lookTable.intensity = 60
            values.exposure.ev = 0.3
            let presets = [
                AdjustmentPreset(name: "Swap", collection: "Pack", groups: [.lookTable, .light], adjustments: values),
                AdjustmentPreset(name: "Bright", collection: "Pack", groups: [.light], adjustments: values),
            ]
            let data = try PresetFile(presets: presets, store: source).data()
            let url = root.appending(path: "Pack.\(PresetFile.fileExtension)")
            try data.write(to: url)

            let file = try PresetFile(data: data)
            #expect(file.lookTables.count == 1)
            #expect(file.presets[1].settings.operations.map(\.kind.rawValue) == ["exposure"])

            let catalog = try Catalog.makeInMemory()
            let destination = LookTableStore(directory: root.appending(path: "B/LUTs"))
            let scan = PresetImport.scan([url])
            #expect(scan.items.count == 2 && scan.tables.count == 1)
            let result = try await PresetImport.run(scan, catalog: catalog, store: destination)
            #expect(result.imported.count == 2)
            #expect(result.addedTables == 1)
            let identifier = try #require(table.identifier)
            #expect(destination.contains(identifier))
            let saved = try await catalog.adjustmentPresets()
            #expect(saved.first { $0.name == "Swap" }?.adjustments.lookTable.intensity == 60)
            #expect(saved.first { $0.name == "Swap" }?.groups == [.lookTable, .light])
            #expect(try await catalog.lookTableCollections().map(\.name) == ["Pack"])
        }
    }

    @Test func compressesAndStillReadsPlainJSON() throws {
        let store = LookTableStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        var values = Adjustments()
        values.exposure.ev = 0.5
        let file = PresetFile(presets: [AdjustmentPreset(name: "Bright", adjustments: values)], store: store)
        let data = try file.data()
        // An xz stream, which `xz -d` reads too.
        #expect(Array(data.prefix(6)) == [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])
        #expect(try PresetFile(data: data).presets.map(\.name) == ["Bright"])
        let plain = try JSONEncoder().encode(file)
        #expect(data.count < plain.count)
        #expect(try PresetFile(data: plain).presets.map(\.name) == ["Bright"])
        #expect(PresetImport.fileExtensions.contains(AppBranding.presetFileExtension))
        #expect(PresetImport.fileExtensions.contains("photopreset"))
    }

    @Test func rejectsOtherJSONAndNewerFormats() {
        #expect(throws: PresetFile.Failure.notAPresetFile) { try PresetFile(data: Data("{\"a\": 1}".utf8)) }
        #expect(throws: PresetFile.Failure.notAPresetFile) {
            try PresetFile(data: Data([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00, 1, 2, 3]))
        }
        let newer = #"{"format": "adjustmentPresets", "formatVersion": 99, "presets": [], "lookTables": []}"#
        #expect(throws: PresetFile.Failure.unsupportedFormatVersion(99)) { try PresetFile(data: Data(newer.utf8)) }
    }
}

@Suite("Camera Raw presets")
struct CameraRawPresetTests {
    /// The structure of a develop template, with values of our own.
    static let template = #"""
    s = {
      id = "1A2B",
      internalName = "Cool Fade",
      title = "$$$/Presets/CoolFade=Cool Fade",
      type = "Develop",
      value = {
        settings = {
          -- An empty gradient, as many templates carry.
          GradientBasedCorrections = {
            {
              CorrectionActive = true,
              CorrectionAmount = 1,
              CorrectionMasks = { { What = "Mask/Gradient", ZeroX = 0.000000 }, },
              LocalExposure2012 = 0.000000,
              LocalTemperature = 0,
              What = "Correction",
            },
          },
          ProcessVersion = "11.0",
          WhiteBalance = "Custom",
          IncrementalTemperature = -12,
          IncrementalTint = 4,
          Exposure2012 = 0.35,
          Contrast2012 = -15,
          Highlights2012 = -60,
          Shadows2012 = 25,
          Blacks2012 = 18,
          Clarity2012 = -10,
          Texture = 12,
          Vibrance = 10,
          Saturation = -5,
          ParametricShadows = 0,
          HueAdjustmentBlue = -8,
          SaturationAdjustmentOrange = -12,
          LuminanceAdjustmentAqua = 20,
          SplitToningShadowHue = 210,
          SplitToningShadowSaturation = 15,
          SplitToningHighlightHue = 40,
          SplitToningHighlightSaturation = 10,
          SplitToningBalance = -20,
          ColorGradeShadowLum = -5,
          ColorGradeBlending = 70,
          Sharpness = 30,
          LuminanceSmoothing = 10,
          PostCropVignetteAmount = -18,
          PostCropVignetteMidpoint = 40,
          GrainAmount = 20,
          GrainSize = 25,
          RedHue = 8,
          CameraProfile = "Camera Neutral",
          ToneCurvePV2012 = { 0, 20, 128, 120, 255, 240, },
          ToneCurvePV2012Red = { 0, 0, 255, 255, },
          ["Quoted Key"] = 'it\'s',
          Note = [[a long
    string]],
        },
        uuid = "1A2B",
      },
      version = 0,
    }
    """#

    static let xmp = #"""
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Test">
     <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about=""
        xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
       crs:PresetType="Normal"
       crs:Version="15.0"
       crs:ProcessVersion="11.0"
       crs:WhiteBalance="Daylight"
       crs:Exposure2012="-0.50"
       crs:Contrast2012="+20"
       crs:ConvertToGrayscale="True"
       crs:GrayMixerBlue="-30"
       crs:HueAdjustmentRed="+40"
       crs:ParametricShadows="+40"
       crs:ParametricHighlights="-30"
       crs:HasCrop="True">
       <crs:Name>
        <rdf:Alt>
         <rdf:li xml:lang="x-default">Silver Morning</rdf:li>
        </rdf:Alt>
       </crs:Name>
       <crs:Group>
        <rdf:Alt>
         <rdf:li xml:lang="x-default">Mono Pack</rdf:li>
        </rdf:Alt>
       </crs:Group>
       <crs:ToneCurvePV2012>
        <rdf:Seq>
         <rdf:li>0, 0</rdf:li>
         <rdf:li>255, 255</rdf:li>
        </rdf:Seq>
       </crs:ToneCurvePV2012>
       <crs:Look>
        <rdf:Description crs:Name="Adobe Monochrome" crs:Amount="1"/>
       </crs:Look>
       <crs:CircularGradientBasedCorrections>
        <rdf:Seq>
         <rdf:li>
          <rdf:Description crs:What="Correction" crs:CorrectionAmount="1" crs:CorrectionActive="true"
            crs:LocalExposure2012="-0.4"/>
         </rdf:li>
        </rdf:Seq>
       </crs:CircularGradientBasedCorrections>
      </rdf:Description>
     </rdf:RDF>
    </x:xmpmeta>
    """#

    @Test func readsTemplates() throws {
        let settings = try CameraRawSettings(template: Self.template)
        #expect(settings.name == "Cool Fade")
        #expect(settings.values["Exposure2012"] == .number(0.35))
        #expect(settings.values["ToneCurvePV2012"]?.list?.count == 6)
        #expect(settings.values["Quoted Key"] == .string("it's"))
        #expect(settings.values["Note"] == .string("a long\nstring"))
        #expect(settings.values["GradientBasedCorrections"]?.list?.first?.record?["What"] == .string("Correction"))

        #expect(throws: CameraRawSettings.Failure.notADevelopPreset) {
            try CameraRawSettings(template: #"s = { title = "Export", type = "Export", value = {} }"#)
        }
        #expect(throws: CameraRawSettings.Failure.self) { try CameraRawSettings(template: "s = { a = ") }
    }

    @Test func convertsTemplates() throws {
        let conversion = CameraRawMapping.convert(try CameraRawSettings(template: Self.template))
        let values = conversion.adjustments
        #expect(values.whiteBalance == WhiteBalance(preset: .custom, relativeTemperature: -12, relativeTint: 4))
        #expect(values.exposure.ev == 0.35)
        #expect(values.tone == Tone(contrast: -15, highlights: -60, shadows: 25, whites: 0, blacks: 18))
        #expect(values.presence == Presence(clarity: -10, vibrance: 10, saturation: -5))
        #expect(values.toneCurve.rgb.map(\.y).map { ($0 * 255).rounded() } == [20, 120, 240])
        #expect(values.colorMixer[.blue].hue == -8)
        #expect(values.colorMixer[.orange].saturation == -12)
        #expect(values.colorMixer[.aqua].luminance == 20)
        #expect(values.colorGrade.shadows == GradeWheel(hue: 210, amount: 15, luminance: -5))
        #expect(values.colorGrade.highlights == GradeWheel(hue: 40, amount: 10))
        #expect(values.colorGrade.balance == -20 && values.colorGrade.blending == 70)
        #expect(values.sharpen.amount == 30)
        #expect(values.noiseReduction == NoiseReduction(luminance: 10))
        #expect(values.vignette == Vignette(amount: -18, size: 40))
        #expect(values.grain.strength == 20 && values.grain.size == 1)
        #expect(values.decode.look == .neutral)
        #expect(conversion.groups == [.profile, .whiteBalance, .light, .presence, .toneCurve, .colorMixer, .colorGrade,
                                      .sharpening, .noiseReduction, .vignette, .grain])
        // The empty gradient changes nothing, so it is not reported.
        #expect(conversion.unsupported == [.texture, .calibration])
    }

    @Test func readsAndConvertsXMP() throws {
        let settings = try CameraRawSettings(xmp: Data(Self.xmp.utf8))
        #expect(settings.name == "Silver Morning")
        #expect(settings.group == "Mono Pack")
        #expect(settings.values["Look"]?.record?["Name"] == .string("Adobe Monochrome"))
        let conversion = CameraRawMapping.convert(settings)
        let values = conversion.adjustments
        #expect(values.whiteBalance == .raw(.daylight))
        #expect(values.exposure.ev == -0.5 && values.tone.contrast == 20)
        #expect(values.presence.saturation == -100)
        // Black and white uses the grey mix, not the color adjustments.
        #expect(values.colorMixer[.blue] == .init(luminance: -30))
        #expect(values.colorMixer[.red] == .init())
        #expect(values.toneCurve.rgb.count == ParametricCurve.sampleCount)
        #expect(values.toneCurve.rgb[4].y > 0.25)
        #expect(values.toneCurve.rgb[14].y < 14.0 / 16)
        #expect(conversion.unsupported == [.blackAndWhite, .crop, .localAdjustments])
        #expect(!conversion.groups.contains(.lookTable))

        let sidecar = #"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:Exposure2012="+1"/></rdf:RDF></x:xmpmeta>"#
        #expect(throws: CameraRawSettings.Failure.noSettings) { try CameraRawSettings(xmp: Data(sidecar.utf8)) }
        let profile = Self.xmp.replacingOccurrences(of: #"crs:PresetType="Normal""#, with: #"crs:PresetType="Look""#)
        #expect(throws: CameraRawSettings.Failure.profile) { try CameraRawSettings(xmp: Data(profile.utf8)) }
    }

    @Test func readsTheXMPOfADNGPreset() throws {
        let photoXMP = #"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:HasSettings="True" crs:Vibrance="+15"/></rdf:RDF></x:xmpmeta>"#
        var bytes = Data([0x49, 0x49, 0x2A, 0x00, 0xFF, 0x00])
        bytes.append(Data(photoXMP.utf8))
        bytes.append(Data([0x00, 0xFE]))
        let packet = try #require(CameraRawSettings.embeddedXMP(in: bytes))
        let settings = try CameraRawSettings(xmp: packet, isPhoto: true)
        #expect(CameraRawMapping.convert(settings).adjustments.presence.vibrance == 15)
        #expect(CameraRawSettings.embeddedXMP(in: Data([1, 2, 3])) == nil)
    }

    @Test func importsAPackOncePerPreset() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let pack = root.appending(path: "cool-pack")
            try FileManager.default.createDirectory(at: pack.appending(path: "XMP"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: pack.appending(path: "Templates"), withIntermediateDirectories: true)
            try Self.template.write(to: pack.appending(path: "Templates/Cool Fade.lrtemplate"), atomically: true,
                                    encoding: .utf8)
            let coolXMP = Self.xmp.replacingOccurrences(of: "Silver Morning", with: "Cool Fade")
                .replacingOccurrences(of: "<rdf:li xml:lang=\"x-default\">Mono Pack</rdf:li>", with: "<rdf:li xml:lang=\"x-default\"></rdf:li>")
            try coolXMP.write(to: pack.appending(path: "XMP/Cool Fade.xmp"), atomically: true, encoding: .utf8)
            try "nonsense".write(to: pack.appending(path: "XMP/Broken.xmp"), atomically: true, encoding: .utf8)

            let scan = PresetImport.scan([pack])
            #expect(scan.items.count == 1)
            #expect(scan.items[0].source.pathExtension == "xmp")
            #expect(scan.items[0].preset.collection == "Cool Pack")
            #expect(scan.failures.map(\.url.lastPathComponent) == ["Broken.xmp"])

            let catalog = try Catalog.makeInMemory()
            let result = try await PresetImport.run(scan, catalog: catalog,
                                                    store: LookTableStore(directory: root.appending(path: "LUTs")))
            #expect(result.imported.map(\.name) == ["Cool Fade"])
            #expect(result.unsupported[.blackAndWhite] == 1)
        }
    }
}
