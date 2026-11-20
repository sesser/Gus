import Foundation
import Testing
@testable import PhotoCore

/// When an Adjust heading's reset arrow is available (issue #221): exactly
/// when `Adjustments.isModified(section)` says the heading has something away
/// from its defaults, and the heading's button carries that to SwiftUI's
/// environment as well as to the `NSButton`.
@Suite("Heading reset")
struct HeadingResetTests {
    /// One value away from its default in every group of a heading.
    private static func edited(_ section: Adjustments.Section) -> Adjustments {
        var values = Adjustments()
        for group in section.groups {
            switch group {
            case .whiteBalance: values.whiteBalance = .raw(.tungsten)
            case .light: values.exposure.ev = 0.5
            case .presence: values.presence.vibrance = 10
            case .toneCurve: values.toneCurve[.rgb] = [CurvePoint(x: 0, y: 0.05), CurvePoint(x: 1, y: 1)]
            case .sharpening: values.sharpen.amount = 40
            case .noiseReduction: values.noiseReduction.luminance = 20
            case .colorMixer: values.colorMixer[.blue] = .init(hue: 10)
            case .blackAndWhite: values.blackAndWhite = BlackAndWhite(isOn: true, [.red: 40])
            case .colorGrade: values.colorGrade.balance = 10
            case .lookTable: values.lookTable = LookTable(identifier: String(repeating: "ab", count: 32), name: "Film")
            case .vignette: values.vignette.amount = -20
            case .grain: values.grain.strength = 30
            case .distortion: values.distortion.isOn = true
            case .lensVignetting: values.lensVignetting.isOn = true
            case .colorFringes: values.colorFringes.slot1 = CommonFringeColor.purple.slot
            case .colorAlignment: values.colorAlignment = ColorAlignment(red: 5)
            case .spots:
                values.spots.spots = [Spot(center: MaskPoint(x: 0.2, y: 0.2), size: 0.01, source: MaskPoint(x: 0.3, y: 0.2))]
            }
        }
        return values
    }

    @Test("No heading has anything to reset on an unedited photo")
    func uneditedPhoto() {
        let values = Adjustments(stack: .identity)
        for section in Adjustments.Section.allCases {
            #expect(!values.isModified(section), "\(section) offers a reset on an unedited photo")
        }
    }

    @Test("An edit under one heading offers only that heading's reset, and the reset dims it again")
    func editAndReset() {
        for section in Adjustments.Section.allCases {
            let values = Self.edited(section)
            for other in Adjustments.Section.allCases {
                #expect(values.isModified(other) == (other == section), "\(other) after an edit under \(section)")
            }
            let reset = values.resetting(section)
            for other in Adjustments.Section.allCases {
                #expect(!reset.isModified(other), "\(other) after resetting \(section)")
            }
            // Through the stored stack too, as the editor reads a saved photo.
            let reread = Adjustments(stack: reset.editStack)
            #expect(Adjustments.Section.allCases.allSatisfy { !reread.isModified($0) })
        }
    }

    @Test("The stored decode, a camera profile and unknown operations belong to no heading")
    func operationsOutsideTheHeadings() {
        let stack = EditStack(operations: [
            EditOperation(kind: RawDecode.kind, parameters: ["look": .string("neutral"), "decoderVersion": .string("8.dng")]),
            EditOperation(kind: CameraProfileReference.kind, parameters: ["name": .string("Camera Standard")]),
            EditOperation(kind: "brush", parameters: ["size": .number(3)]),
            EditOperation(kind: "exposure", kindVersion: 2, parameters: ["ev": .number(1)]),
        ])
        let values = Adjustments(stack: stack)
        #expect(values != .none)
        for section in Adjustments.Section.allCases {
            #expect(!values.isModified(section), "\(section) offers a reset for an operation it doesn't reset")
        }
    }

    @Test("A turned-off group's kept values can be reset, and the reset turns it back on")
    func turnedOffGroup() {
        for section in Adjustments.Section.allCases {
            var values = Self.edited(section)
            for group in section.groups { values.setEnabled(group, false) }
            #expect(section.groups.allSatisfy { !values.isEnabled($0) })
            #expect(values.isModified(section), "\(section) with its edits turned off")
            let reset = values.resetting(section)
            #expect(!reset.isModified(section))
            #expect(section.groups.allSatisfy { reset.isEnabled($0) })
            #expect(reset == .none)
        }
    }

    @Test("A stack from before machine learning had its own setting offers Details' reset")
    func legacyMachineLearningDecoder() {
        let stack = EditStack(operations: [
            EditOperation(kind: RawDecode.kind, parameters: ["decoderVersion": .string("9.dng")]),
        ])
        let values = Adjustments(stack: stack)
        #expect(values.noiseReduction.machineLearning)
        #expect(values.isModified(.details))
        #expect(!values.resetting(.details).isModified(.details))
    }

    /// PhotoApp has no test target, so this reads its sources. SwiftUI writes
    /// its environment's enabled state onto a hosted `NSButton` after
    /// `updateNSView` (`adoptEnvironment`), so an `AppKitButton`'s
    /// `isEnabled: false` alone left every heading's reset enabled. Each
    /// heading's reset must also carry `.disabled(…)`.
    @Test("Every heading's reset is dimmed through SwiftUI's environment too")
    func headingResetsCarryDisabled() throws {
        let symbol = #"symbol: "arrow.counterclockwise""#
        var found: [String] = []
        for path in RepositoryFiles.files(under: "Sources/PhotoApp/Views") where path.hasSuffix(".swift") {
            let lines = try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("AppKitButton(") && line.contains(symbol) {
                found.append("\(path):\(index + 1)")
                // The button's arguments and action, then its modifiers, up to the end of the trailing closure.
                let following = lines[(index + 1)...].prefix(8).map { $0.trimmingCharacters(in: .whitespaces) }
                #expect(following.contains { $0.hasPrefix(".disabled(") },
                        "the reset at \(path):\(index + 1) sets isEnabled without .disabled(…)")
            }
        }
        // Crop, Spots, the seven `AdjustSection` headings (one view) and Black & White.
        #expect(found.count == 4, "found \(found)")
    }
}
