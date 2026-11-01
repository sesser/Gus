import Foundation
import Testing
@testable import PhotoCore

@Suite("Mask model")
struct MaskModelTests {
    static let ids = (0..<40).map { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", $0))! }

    /// One mask of every shape, and local values.
    static func sample() -> Adjustments {
        var adjustments = Adjustments()
        adjustments.exposure.ev = 0.5
        var values = LocalValues()
        values.exposure = -0.7
        values.dehaze = 20
        values.sharpen = 30
        adjustments.local.masks = [
            Mask(id: ids[0], name: "Sky", amount: 80, components: [
                MaskComponent(.linear(LinearGradient(start: MaskPoint(x: 0.5, y: 0.1), end: MaskPoint(x: 0.5, y: 0.45)))),
                MaskComponent(.luminanceRange(LuminanceRange(lower: 0.6, upper: 1, smoothness: 0)), operation: .intersect),
            ], adjustments: values),
            Mask(id: ids[1], isEnabled: false, components: [
                MaskComponent(.radial(RadialGradient(center: MaskPoint(x: 0.4, y: 0.6), radiusX: 0.2, radiusY: 0.1,
                                                     rotation: 30, feather: 0)), invert: true),
                MaskComponent(.brush(Brush(strokes: [
                    BrushStroke(points: [MaskPoint(x: 0.1, y: 0.2), MaskPoint(x: 0.1234567, y: 0.2)], size: 0.02,
                                flow: 60),
                    BrushStroke(points: [MaskPoint(x: 0.3, y: 0.3)], erase: true),
                ])), operation: .subtract),
                MaskComponent(.colorRange(ColorRange(samples: [SIMD3(0.7, 0.05, -0.1)], tolerance: 45))),
            ], adjustments: values),
        ]
        return adjustments
    }

    static func fixed(_ stack: EditStack) -> EditStack { EditStackCorpusTests.fixingIDs(stack) }

    @Test("Masks round-trip through the stack, defaults left out")
    func roundTrip() throws {
        let adjustments = Self.sample()
        let stack = adjustments.editStack
        #expect(stack.schemaVersion == 2)
        #expect(stack.operations.map(\.kind.rawValue) == ["exposure", "localAdjustments"])
        let json = try Self.fixed(stack).jsonString()
        let decoded = try EditStack.decode(from: json)
        #expect(Adjustments(stack: decoded) == adjustments)
        #expect(try Self.fixed(Adjustments(stack: decoded).editStack).jsonString() == json)

        // Defaults are left out at every level.
        #expect(json.contains(#""components":[{"endX":0.5,"endY":0.45,"shape":"linear","startX":0.5,"startY":0.1}"#))
        #expect(json.contains(#"{"lower":0.6,"operation":"intersect","shape":"luminanceRange","smoothness":0}"#))
        #expect(json.contains(#""points":[0.1,0.2,0.123457,0.2]"#), "points are rounded to 10⁻⁶")
        #expect(json.contains(#"{"erase":true,"points":[0.3,0.3]}"#))
        #expect(json.contains(#""isEnabled":false"#))
        #expect(!json.contains(#""amount":100"#))
    }

    @Test("Removing every mask gives back the stack without masks, byte for byte")
    func noMasksNoTrace() throws {
        var adjustments = Self.sample()
        adjustments.local = LocalAdjustments()
        var plain = Adjustments()
        plain.exposure.ev = 0.5
        #expect(try Self.fixed(adjustments.editStack).jsonString() == Self.fixed(plain.editStack).jsonString())
        #expect(adjustments.editStack.renderHash == plain.editStack.renderHash)
        #expect(adjustments.editStack.schemaVersion == 1)
    }

    static func stack(masks json: String) -> String {
        #"{"operations":[{"id":"00000000-0000-4000-8000-000000000000","isEnabled":true,"kind":"localAdjustments","#
            + #""kindVersion":1,"parameters":{"masks":"# + json + "}}],\"schemaVersion\":2}"
    }

    @Test("Anything unknown or mistyped makes the stack unreadable instead of dropping it",
          arguments: [
            #"[{"id":"00000000-0000-4000-8000-000000000001","refine":10}]"#,
            #"[{"id":"00000000-0000-4000-8000-000000000001","components":[{"shape":"subject"}]}]"#,
            #"[{"id":"00000000-0000-4000-8000-000000000001","components":[{"shape":"linear","operation":"xor"}]}]"#,
            #"[{"id":"00000000-0000-4000-8000-000000000001","amount":"lots"}]"#,
            #"[{"id":"00000000-0000-4000-8000-000000000001","components":[{"shape":"brush","strokes":[{"points":[0.1]}]}]}]"#,
            #"[{"id":"not a uuid"}]"#,
            #"[{"id":"00000000-0000-4000-8000-000000000001","adjustments":{"texture":20}}]"#,
          ])
    func strictReading(masks: String) {
        #expect(throws: EditStack.DecodingFailure.self) { try EditStack.decode(from: Self.stack(masks: masks)) }
        do {
            _ = try EditStack.decode(from: Self.stack(masks: masks))
        } catch {
            #expect(EditStack.ReadFailure(error) == .damaged)
        }
    }

    @Test("Numbers out of range are clamped, as the modules do")
    func clamping() throws {
        let json = Self.stack(masks: #"[{"id":"00000000-0000-4000-8000-000000000001","amount":150,"adjustments":{"exposure":9}}]"#)
        let mask = try #require(Adjustments(stack: EditStack.decode(from: json)).local.masks.first)
        #expect(mask.amount == 100 && mask.adjustments.exposure == 4)
    }

    @Test("A stack over the limits is unreadable, never truncated, and never written over")
    func limits() async throws {
        let masks = (0...MaskLimits.masks).map { #"{"id":"\#(Self.ids[$0].uuidString)"}"# }.joined(separator: ",")
        let json = Self.stack(masks: "[" + masks + "]")
        #expect(throws: EditStack.DecodingFailure.self) { try EditStack.decode(from: json) }
        do {
            _ = try EditStack.decode(from: json)
        } catch {
            #expect(EditStack.ReadFailure(error) == .exceedsLimits)
        }

        let fixture = try await CatalogFixture.make()
        let id = try #require(try await fixture.addMasters([CatalogFixture.master(1)]).first)
        try await UnreadableStackTests.store(json, forVersion: id, in: fixture.catalog)
        await #expect(throws: UnreadableEditStacks.self) {
            try await fixture.catalog.setEditStack(Adjustments().editStack, forVersion: id)
        }
        #expect(try await UnreadableStackTests.stored(id, in: fixture.catalog).json == json)

        var local = LocalAdjustments(masks: (0..<MaskLimits.masks).map { Mask(id: Self.ids[$0]) })
        #expect(MaskLimits.allows(local))
        local.masks.append(Mask())
        #expect(!MaskLimits.allows(local))
        let samples = Array(repeating: SIMD3(0.5, 0.0, 0.0), count: MaskLimits.colorSamples + 1)
        #expect(!MaskLimits.allows(LocalAdjustments(masks: [Mask(components: [MaskComponent(.colorRange(
            ColorRange(samples: samples)))])])))
    }

    @Test("Paste and presets leave masks alone")
    func pasteAndPresetsSkipMasks() {
        let masked = Self.sample()
        var target = Adjustments()
        target.local.masks = [Mask(id: Self.ids[9], name: "Mine")]
        #expect(masked.pasted(onto: target).local == target.local)
        #expect(masked.pasted(onto: target).exposure.ev == 0.5)

        let preset = AdjustmentPreset(name: "all", adjustments: masked)
        #expect(preset.adjustments.local.isIdentity)
        #expect(preset.applied(onto: target).local == target.local)
    }

    @Test("A newer kindVersion is kept as it is and not checked")
    func newerKindVersionIsPreserved() throws {
        let json = #"{"operations":[{"id":"00000000-0000-4000-8000-000000000000","isEnabled":true,"#
            + #""kind":"localAdjustments","kindVersion":2,"parameters":{"masks":[{"shape":"subject"}]}}],"schemaVersion":2}"#
        let stack = try EditStack.decode(from: json)
        let adjustments = Adjustments(stack: stack)
        #expect(adjustments.local.isIdentity)
        #expect(adjustments.preserved == stack.operations)
        #expect(try adjustments.editStack.jsonString() == json)
    }

    @Test("Masks that change nothing are not rendered")
    func renderedMasks() {
        var values = LocalValues()
        values.contrast = 10
        let local = LocalAdjustments(masks: [
            Mask(id: Self.ids[0], components: [MaskComponent(.radial(RadialGradient(center: .init(x: 0.5, y: 0.5),
                                                                                    radiusX: 0.1, radiusY: 0.1)))],
                 adjustments: values),
            Mask(id: Self.ids[1], isEnabled: false, components: [MaskComponent(.brush(Brush()))], adjustments: values),
            Mask(id: Self.ids[2], adjustments: values),
            Mask(id: Self.ids[3], components: [MaskComponent(.brush(Brush()))]),
            Mask(id: Self.ids[4], amount: 0, components: [MaskComponent(.brush(Brush()))], adjustments: values),
        ])
        #expect(local.renderedMasks.map(\.id) == [Self.ids[0]])
    }
}
