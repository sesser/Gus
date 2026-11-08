import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The Lens groups in `photocli` (AC11) and in Lightroom preset import (AC14).
@Suite("Lens commands and presets")
struct LensCommandTests {
    @Test("AC11: adjustments lists the new parameters; develop sets them, measuring automatic alignment; render follows")
    func photocli() async throws {
        try await CommandTests.withLibrary { library in
            let listed = try JSONValue.parse(await library.cli.run(["adjustments"]).standardOutput)
            let modules = try #require(listed["modules"]?.arrayValue)
            let fringes = try #require(modules.first { $0["kind"] == "colorFringes" })
            #expect(fringes["group"] == "colorFringes" && fringes["section"] == "lens")
            let color1 = try #require(fringes["parameters"]?.arrayValue?.first { $0["name"] == "color1" })
            #expect(color1["type"] == "color" && color1["names"]?.arrayValue?.count == 2)
            let tolerance = try #require(fringes["parameters"]?.arrayValue?.first { $0["name"] == "tolerance1" })
            #expect(tolerance["minimum"] == 0 && tolerance["maximum"] == 100 && tolerance["default"] == .null)
            let alignment = try #require(modules.first { $0["kind"] == "colorAlignment" })
            let red = try #require(alignment["parameters"]?.arrayValue?.first { $0["name"] == "red" })
            #expect(red["minimum"] == -50 && red["maximum"] == 50 && red["default"] == 0)

            let id = String(library.versionIDs[0])
            let before = await library.run("render", "--version", id, "--out", library.root.appending(path: "a.png").path)
            let set = await library.run("develop", "--version", id, "--set", "colorFringes.color1=purple",
                                        "--set", "colorFringes.tolerance1=40", "--set", "colorFringes.color2=0.7,-0.1,0.08")
            #expect(set.output.exitCode == 0, "\(set.output.standardError)")
            let values = try Self.adjustments(set.json)
            #expect(values.colorFringes.slot1 == ColorFringes.Slot(color: CommonFringeColor.purple.color, tolerance: 40))
            #expect(values.colorFringes.slot2?.color == SIMD3(0.7, -0.1, 0.08))
            let after = await library.run("render", "--version", id, "--out", library.root.appending(path: "b.png").path)
            #expect(before.output.exitCode == 0 && after.output.exitCode == 0)
            #expect(before.json["renderHash"] != after.json["renderHash"])
            #expect(after.json["renderHash"] == .string(values.editStack.renderHash))

            // Automatic alignment measures the original and stores the values.
            let automatic = await library.run("develop", "--version", id, "--set", "colorAlignment.automatic=true")
            #expect(automatic.output.exitCode == 0, "\(automatic.output.standardError)")
            let measured = try Self.adjustments(automatic.json)
            #expect(measured.colorAlignment.automatic)
            // A value set by hand makes it hand-set.
            let hand = await library.run("develop", "--version", id, "--set", "colorAlignment.red=12")
            let handSet = try Self.adjustments(hand.json)
            #expect(handSet.colorAlignment.red == 12 && !handSet.colorAlignment.automatic)

            let invalid = await library.run("develop", "--version", id, "--set", "colorFringes.color1=teal")
            #expect(invalid.output.exitCode != 0 && invalid.json["code"] == "invalidEdit")
        }
    }

    /// The adjustments of a command's `editStack`.
    static func adjustments(_ json: JSONValue) throws -> Adjustments {
        Adjustments(stack: try EditStack.decode(from: JSONEncoder().encode(try #require(json["editStack"]))))
    }

    static func xmp(_ attributes: String) -> String {
        """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Test">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
           crs:PresetType="Normal" crs:Version="15.0" crs:ProcessVersion="11.0" \(attributes)>
           <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">Lens</rdf:li></rdf:Alt></crs:Name>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
    }

    @Test("AC14: purple and green fringe removal and automatic chromatic aberration removal are mapped, not reported")
    func lightroomImport() throws {
        let fringes = CameraRawMapping.convert(try CameraRawSettings(xmp: Data(Self.xmp("""
            crs:DefringePurpleAmount="5" crs:DefringePurpleHueLo="30" crs:DefringePurpleHueHi="70" \
            crs:DefringeGreenAmount="3" crs:DefringeGreenHueLo="40" crs:DefringeGreenHueHi="70" crs:AutoLateralCA="1"
            """).utf8)))
        #expect(fringes.groups == [.colorFringes, .colorAlignment])
        #expect(fringes.adjustments.colorFringes.slot1 == CommonFringeColor.purple.slot)
        // A hue range half again as wide as its default: a Tolerance half again as wide.
        #expect(fringes.adjustments.colorFringes.slot2
            == ColorFringes.Slot(color: CommonFringeColor.green.color, tolerance: CommonFringeColor.green.startingTolerance * 1.5))
        #expect(fringes.adjustments.colorAlignment.automatic)
        #expect(fringes.unsupported.isEmpty)

        let off = CameraRawMapping.convert(try CameraRawSettings(xmp: Data(Self.xmp(
            #"crs:DefringePurpleAmount="0" crs:DefringeGreenAmount="0" crs:AutoLateralCA="0""#).utf8)))
        #expect(off.groups == [.colorFringes, .colorAlignment] && off.adjustments.colorFringes.isIdentity)
        #expect(off.unsupported.isEmpty)

        let profile = CameraRawMapping.convert(try CameraRawSettings(xmp: Data(Self.xmp(
            #"crs:LensProfileEnable="1" crs:AutoLateralCA="1""#).utf8)))
        #expect(profile.unsupported == [.lensCorrections])
        let distortion = CameraRawMapping.convert(try CameraRawSettings(xmp: Data(Self.xmp(
            #"crs:LensManualDistortionAmount="5""#).utf8)))
        #expect(distortion.unsupported == [.lensCorrections])
    }
}

/// AC13b (RI-E2 ruling): presets with every group replace the Lens groups too.
@Suite("Lens groups in presets")
struct LensPresetTests {
    /// A scene (a) photo's values with both slots filled and automatic alignment on.
    static var photo: Adjustments {
        var values = Adjustments()
        values.colorFringes = ColorFringes(slot1: CommonFringeColor.purple.slot, slot2: CommonFringeColor.green.slot)
        values.colorAlignment = ColorAlignment(automatic: true, red: 12, blue: -8)
        return values
    }

    /// What a preset saved before the Lens groups existed holds: other values only.
    static var older: Adjustments {
        var values = Adjustments()
        values.tone.contrast = 20
        return values
    }

    static func expectLensCleared(_ values: Adjustments, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(values.colorFringes.isIdentity, sourceLocation: sourceLocation)
        #expect(values.colorAlignment == ColorAlignment(), sourceLocation: sourceLocation)
        #expect(values.tone.contrast == 20, sourceLocation: sourceLocation)
    }

    @Test("AC13b: a stored preset with no group list clears the slots and alignment")
    func storedPresetWithEveryGroup() async throws {
        let fixture = try await CatalogFixture.make()
        // Every group: stored with no group list, as presets saved before this feature are.
        let saved = AdjustmentPreset(name: "Older", adjustments: Self.older)
        #expect(AdjustmentPreset.encodeGroups(saved.groups) == nil)
        _ = try await fixture.catalog.saveAdjustmentPreset(saved)
        let read = try #require(try await fixture.catalog.adjustmentPresets().first)
        #expect(read.includesEveryGroup)
        #expect(read.groups.isSuperset(of: [.colorFringes, .colorAlignment]))
        let applied = read.applied(onto: Self.photo)
        Self.expectLensCleared(applied)
        // No automatic alignment to measure: the app applies it as one change (one undo step).
        #expect(!applied.needsAlignmentMeasurement)
    }

    @Test("AC13b: a preset file with no group list reads as every group")
    func presetFileWithEveryGroup() throws {
        let stack = String(decoding: try Self.older.editStack.jsonData(), as: UTF8.self)
        // A file written before this feature: no "groups" key.
        let json = #"{"format":"adjustmentPresets","formatVersion":1,"lookTables":[],"presets":[{"name":"Older","settings":"#
            + stack + "}]}"
        let presets = try PresetFile(data: Data(json.utf8)).adjustmentPresets()
        let preset = try #require(presets.first)
        #expect(preset.includesEveryGroup)
        Self.expectLensCleared(preset.applied(onto: Self.photo))
    }

    @Test("AC13b: a preset whose group list leaves out the Lens groups keeps the photo's")
    func presetWithoutTheLensGroups() {
        let groups = Set(Adjustments.Group.allCases).subtracting([.colorFringes, .colorAlignment])
        let preset = AdjustmentPreset(name: "Older", groups: groups, adjustments: Self.older)
        #expect(AdjustmentPreset.encodeGroups(preset.groups) != nil)
        let applied = preset.applied(onto: Self.photo)
        #expect(applied.colorFringes == Self.photo.colorFringes)
        #expect(applied.colorAlignment == Self.photo.colorAlignment)
        #expect(applied.tone.contrast == 20)
    }
}
