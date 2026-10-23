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
}
