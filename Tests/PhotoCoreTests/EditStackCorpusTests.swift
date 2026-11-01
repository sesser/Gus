import Foundation
import Testing
@testable import PhotoCore

/// Stacks without masks must keep their exact bytes and render hashes when the
/// stack format grows (docs/PHASE6_PLAN.md, decision 2). The corpus was
/// recorded before the format changed, in `Fixtures/edit-stack-corpus.json`,
/// and is never rewritten: to record it again, delete the file and run with
/// `RECORD_EDIT_STACK_CORPUS=1`.
@Suite("Edit stack corpus")
struct EditStackCorpusTests {
    struct Entry: Codable, Equatable {
        var name: String
        var json: String
        var renderHash: String
    }

    static let url = RepositoryFiles.url("Tests/PhotoCoreTests/Fixtures/edit-stack-corpus.json")

    /// Operation ids are random; the corpus gives them fixed ones so the JSON repeats.
    static func fixingIDs(_ stack: EditStack) -> EditStack {
        var stack = stack
        for index in stack.operations.indices {
            stack.operations[index].id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
        }
        return stack
    }

    /// Every golden case, the RAW decode cases, and stacks that exercise the
    /// container: identity, a module turned off, an operation of an unknown
    /// kind with every parameter type, and everything at once.
    static var stacks: [(String, EditStack)] {
        var result: [(String, EditStack)] = [("identity", .identity)]
        result += GoldenTests.cases.map { ($0.name, $0.adjustments.editStack) }
        result += GoldenTests.rawCases.map { ($0.name, $0.adjustments.editStack) }

        var off = Adjustments()
        off.exposure.ev = 1
        off.tone.contrast = 20
        off.setEnabled(.light, false)
        result.append(("light-turnedOff", off.editStack))

        var unknown = Adjustments()
        unknown.presence.vibrance = 15
        unknown.preserved = [EditOperation(kind: "futureModule", kindVersion: 3, parameters: [
            "number": .number(0.125), "flag": .bool(true), "name": .string("a/b \"c\""),
            "list": .list([.number(1), .list([.number(2), .string("x")]), .bool(false)]),
        ])]
        result.append(("unknownOperationPreserved", unknown.editStack))

        var everything = Adjustments()
        everything.crop = Crop(rect: CropRect(x: 0.1, y: 0.05, width: 0.8, height: 0.9), quarterTurns: 3, angle: 2.5)
        everything.decode = RawDecode(look: .neutral, decoderVersion: "8")
        everything.whiteBalance = WhiteBalance(preset: .custom, temperature: 5100, tint: 7,
                                               relativeTemperature: 10, relativeTint: -5)
        everything.exposure.ev = 0.33
        everything.tone = Tone(contrast: 12, highlights: -40, shadows: 30, whites: 5, blacks: -8)
        everything.presence = Presence(clarity: -20, dehaze: 10, vibrance: 25, saturation: -10)
        everything.toneCurve.rgb = [CurvePoint(x: 0, y: 0.02), CurvePoint(x: 0.5, y: 0.55), CurvePoint(x: 1, y: 1)]
        everything.colorMixer[.blue] = ColorMixer.Shift(hue: -10, saturation: 20, luminance: -15)
        everything.colorGrade.shadows = GradeWheel(hue: 210, amount: 15)
        everything.lookTable = LookTable(identifier: String(repeating: "c", count: 64), name: "Look", intensity: 70,
                                         colorSpace: .displayP3)
        everything.vignette = Vignette(amount: -30, size: 60, roundness: 20)
        everything.noiseReduction = NoiseReduction(luminance: 20, color: 30)
        everything.sharpen = Sharpen(amount: 60, radius: 1.2, detail: 30, masking: 10)
        everything.grain = Grain(strength: 40, roughness: 70, color: 10, size: 1.5)
        result.append(("everything", everything.editStack))
        return result.map { ($0.0, fixingIDs($0.1)) }
    }

    static func entries() throws -> [Entry] {
        try stacks.map { name, stack in Entry(name: name, json: try stack.jsonString(), renderHash: stack.renderHash) }
    }

    @Test("Stacks without masks keep their bytes and render hashes")
    func corpusIsUnchanged() throws {
        let current = try Self.entries()
        guard let data = try? Data(contentsOf: Self.url) else {
            if ProcessInfo.processInfo.environment["RECORD_EDIT_STACK_CORPUS"] == "1" {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try encoder.encode(current).write(to: Self.url)
                print("edit stack corpus recorded: \(Self.url.path)")
            } else {
                Issue.record("Missing \(Self.url.path)")
            }
            return
        }
        let recorded = try JSONDecoder().decode([Entry].self, from: data)
        #expect(recorded.map(\.name) == current.map(\.name), "the corpus's cases changed")
        for (old, new) in zip(recorded, current) {
            #expect(new.json == old.json, "\(old.name): JSON changed")
            #expect(new.renderHash == old.renderHash, "\(old.name): render hash changed")
            // The stored bytes read back and write out unchanged.
            let decoded = try EditStack.decode(from: old.json)
            #expect(try decoded.jsonString() == old.json, "\(old.name): decode and encode changed the bytes")
            #expect(decoded.renderHash == old.renderHash, "\(old.name)")
            // Read into the typed values and written back, as the editor saves.
            #expect(Self.fixingIDs(Adjustments(stack: decoded).editStack) == decoded, "\(old.name): Adjustments changed it")
        }
    }
}
