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
