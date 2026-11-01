import CoreImage
import Foundation
import Testing
@testable import PhotoCore

@Suite("Edit stack")
struct EditStackTests {
    private func exposure(_ value: Double, enabled: Bool = true, id: UUID = UUID()) -> EditOperation {
        EditOperation(id: id, kind: "exposure", isEnabled: enabled, parameters: ["ev": .number(value)])
    }

    @Test func identityStackHasStableJSONAndHash() throws {
        #expect(try EditStack.identity.jsonString() == #"{"operations":[],"schemaVersion":1}"#)
        // Golden value: changing it invalidates every cached preview, so it should
        // only change on purpose.
        #expect(EditStack.identity.renderHash == "6c76a50e5dc3f0cd68d308e680249e3d6630fa08627df6456a5d9e701b20b9f8")
        #expect(EditStack.identity.isIdentity)
    }

    @Test func roundTripsEveryParameterType() throws {
        let stack = EditStack(operations: [
            EditOperation(kind: "sample", kindVersion: 3, parameters: [
                "amount": .number(0.25),
                "whole": .number(2),
                "on": .bool(true),
                "mode": .string("fast"),
                "curve": .list([.number(0), .number(0.5), .list([.bool(false)])]),
            ]),
            EditOperation(kind: .passThrough, isEnabled: false),
        ])
        let decoded = try EditStack.decode(from: try stack.jsonData())
        #expect(decoded == stack)
        #expect(try decoded.jsonString() == stack.jsonString())
    }

    @Test func renderHashIgnoresIdsAndDisabledOperations() {
        let a = EditStack(operations: [exposure(1)])
        let b = EditStack(operations: [exposure(1), exposure(3, enabled: false)])
        #expect(a.renderHash == b.renderHash)
        #expect(a.renderHash != EditStack.identity.renderHash)
        #expect(EditStack(operations: [exposure(1, enabled: false)]).renderHash == EditStack.identity.renderHash)
        #expect(EditStack(operations: [exposure(1, enabled: false)]).isIdentity)
    }

    @Test func renderHashDependsOnParametersOrderAndKindVersion() {
        let base = EditStack(operations: [exposure(1), EditOperation(kind: "contrast")])
        let reordered = EditStack(operations: [EditOperation(kind: "contrast"), exposure(1)])
        let changed = EditStack(operations: [exposure(1.5), EditOperation(kind: "contrast")])
        var newer = base
        newer.operations[0].kindVersion = 2
        #expect(base.renderHash != reordered.renderHash)
        #expect(base.renderHash != changed.renderHash)
        #expect(base.renderHash != newer.renderHash)
    }

    @Test func encodingIsCanonical() throws {
        let id = UUID()
        var first = EditOperation(id: id, kind: "x")
        first.parameters = ["b": .number(1), "a": .number(2)]
        var second = EditOperation(id: id, kind: "x")
        second.parameters["a"] = .number(2)
        second.parameters["b"] = .number(1)
        #expect(try EditStack(operations: [first]).jsonString() == EditStack(operations: [second]).jsonString())
        let json = try EditStack(operations: [first]).jsonString()
        #expect(json.contains(#""parameters":{"a":2,"b":1}"#))
    }

    @Test func rejectsStacksFromNewerSchemas() {
        let json = #"{"operations":[],"schemaVersion":99}"#
        #expect(throws: EditStack.DecodingFailure.unsupportedSchemaVersion(99)) {
            try EditStack.decode(from: json)
        }
    }

    @Test func passThroughRendererReturnsInput() throws {
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let output = try PassThroughRenderer().apply(EditStack(operations: [exposure(2)]), to: image)
        #expect(output === image)
    }

    // MARK: Objects (schema version 2)

    @Test("Objects round-trip with sorted keys and make the stack schema 2")
    func objectsNeedSchemaTwo() throws {
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let masked = EditStack(operations: [
            exposure(1, id: id),
            EditOperation(id: id, kind: "localAdjustments", parameters: [
                "masks": .list([.object(["name": .string("Sky"), "amount": .number(80),
                                         "adjustments": .object(["exposure": .number(-0.5)])])]),
            ]),
        ])
        #expect(masked.schemaVersion == 2)
        let json = try masked.jsonString()
        #expect(json.hasSuffix(#""schemaVersion":2}"#))
        #expect(json.contains(#"{"adjustments":{"exposure":-0.5},"amount":80,"name":"Sky"}"#))
        let decoded = try EditStack.decode(from: json)
        #expect(decoded == masked)
        #expect(try decoded.jsonString() == json)

        // Without the object the stack is version 1 again, byte for byte.
        let plain = EditStack(operations: [exposure(1, id: id)])
        var removed = decoded
        removed.operations.removeLast()
        #expect(removed.schemaVersion == 1)
        #expect(try removed.jsonString() == plain.jsonString())
        #expect(removed.renderHash == plain.renderHash)
        #expect(masked.renderHash != plain.renderHash)
    }

    @Test("An object inside a list counts; only enabled operations reach the render hash")
    func nestedObjectsCount() {
        let nested = EditParameter.list([.number(1), .list([.object([:])])])
        #expect(nested.containsObject)
        #expect(!EditParameter.list([.number(1), .list([.string("x")])]).containsObject)
        let off = EditStack(operations: [EditOperation(kind: "localAdjustments", isEnabled: false,
                                                       parameters: ["masks": nested])])
        // The container needs version 2 to hold it, even turned off.
        #expect(off.schemaVersion == 2)
    }

    @Test("Unknown operations holding objects are kept by Adjustments")
    func unknownObjectsArePreserved() throws {
        let future = EditOperation(kind: "futureShape", kindVersion: 2, parameters: [
            "shape": .object(["points": .list([.number(0.1), .number(0.2)]), "closed": .bool(true)]),
        ])
        let stack = EditStack(operations: [exposure(0.5), future])
        let adjustments = Adjustments(stack: try EditStack.decode(from: stack.jsonString()))
        #expect(adjustments.preserved == [future])
        #expect(adjustments.editStack.schemaVersion == 2)
    }

    @Test("A schema newer than this build's is refused")
    func newerSchemaIsRefused() throws {
        #expect(throws: EditStack.DecodingFailure.unsupportedSchemaVersion(3)) {
            try EditStack.decode(from: #"{"operations":[],"schemaVersion":3}"#)
        }
        // A version 2 header with nothing that needs it reads, and writes back as 1.
        #expect(try EditStack.decode(from: #"{"operations":[],"schemaVersion":2}"#) == .identity)
    }
}
