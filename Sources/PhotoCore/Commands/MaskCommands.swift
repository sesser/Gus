import Foundation

/// Masks of a version (docs/PHASE6_PLAN.md, "Scripting"). Every change edits
/// the stored mask objects and reads them back through the same strict reader
/// as a stored stack, so a command can never save what the app would refuse;
/// adding goes no further than `MaskLimits`.
enum MaskCommands {
    static let mask = CommandParameter("mask", .string, "A mask's id, or its index from 0 (see mask list).",
                                       required: true)
    static let dryRun = CommandParameter("dryRun", .flag, "Print the result; change nothing.")

    static let list = CommandSpec(
        id: "mask.list",
        summary: "Lists a version's masks as stored: shape parameters, operations, amount and local values.",
        access: .read,
        parameters: [CommandParameter("version", .integer, "The version id.", required: true), LibraryCommands.libraryRoot],
        run: { invocation in
            let (_, _, stack) = try await load(invocation)
            return ["masks": masksJSON(Adjustments(stack: stack).local)]
        })

    static let add = CommandSpec(
        id: "mask.add",
        summary: """
            Adds a mask with one component, or with --mask a component to an existing mask. --params takes the \
            shape's parameters as a JSON object (see adjustments, local.shapes); --set takes the mask's local values \
            and amount (exposure=0.5, amount=80). Not undoable.
            """,
        access: .writeUnlessDryRun,
        parameters: [
            CommandParameter("version", .integer, "The version id.", required: true),
            CommandParameter("shape", .string, "linear, radial, brush, luminanceRange or colorRange.", required: true),
            CommandParameter("params", .json, "The shape's parameters, a JSON object."),
            CommandParameter("operation", .string, "add (default), subtract or intersect."),
            CommandParameter("invert", .flag, "Invert this component."),
            CommandParameter("mask", .string, "Add the component to this mask (id or index) instead of a new one."),
            CommandParameter("name", .string, "The new mask's name."),
            CommandParameter("set", .string, "name=value for the mask: a local value or amount.", repeatable: true),
            dryRun, LibraryCommands.libraryRoot,
        ],
        run: runAdd)

    static let set = CommandSpec(
        id: "mask.set",
        summary: """
            Changes one mask: --set amount=…, exposure=…, name=…, isEnabled=false, or component.K.key=value for \
            its K-th component's parameters, operation or invert. Values may be JSON. Not undoable.
            """,
        access: .writeUnlessDryRun,
        parameters: [
            CommandParameter("version", .integer, "The version id.", required: true), mask,
            CommandParameter("set", .string, "name=value.", repeatable: true), dryRun, LibraryCommands.libraryRoot,
        ],
        run: runSet)

    static let remove = CommandSpec(
        id: "mask.remove",
        summary: "Removes a mask, or with --component K one of its components. Not undoable.",
        access: .writeUnlessDryRun,
        parameters: [
            CommandParameter("version", .integer, "The version id.", required: true), mask,
            CommandParameter("component", .integer, "Remove only this component (index from 0)."),
            dryRun, LibraryCommands.libraryRoot,
        ],
        run: runRemove)

    // MARK: Running

    static func load(_ invocation: CommandInvocation) async throws -> (OpenLibrary, Int64, EditStack) {
        let library = try invocation.environment.openLibrary(invocation.arguments)
        let id = Int64(invocation.arguments.integer("version") ?? 0)
        guard let version = try await library.catalog.version(id: id) else {
            throw CommandError(.versionNotFound, "No version \(id)")
        }
        return (library, id, try version.readableEditStack())
    }

    /// Applies `change` to the stored mask objects, reads them back strictly,
    /// and saves unless it is a dry run.
    static func change(_ invocation: CommandInvocation, creating: Bool,
                       _ change: (inout [[String: EditParameter]]) throws(CommandError) -> Void) async throws -> JSONValue {
        let (library, id, before) = try await load(invocation)
        var adjustments = Adjustments(stack: before)
        var masks = adjustments.local.masks.map(\.parameters)
        try change(&masks)
        let local: LocalAdjustments
        do {
            local = try LocalAdjustments(masks.isEmpty ? [:] : ["masks": .list(masks.map(EditParameter.object))])
        } catch .invalid(let reason) {
            throw CommandError(.invalidEdit, "Not a valid mask: \(reason)")
        } catch .exceedsLimits(let reason) {
            throw CommandError(.invalidEdit, "Over the limits: \(reason)")
        }
        if creating, !MaskLimits.allows(local) {
            throw CommandError(.invalidEdit, "Over the limits")
        }
        adjustments.local = local
        let after = adjustments.editStack
        let dryRun = invocation.arguments.flag("dryRun")
        let changed = after != before
        if changed, !dryRun {
            try await library.catalog.setEditStack(after, forVersion: id)
        }
        return [
            "versionID": JSONValue(id), "masks": masksJSON(local), "editStack": try JSONValue(encoding: after),
            "renderHash": .string(after.renderHash), "changed": .bool(changed), "written": .bool(changed && !dryRun),
            "dryRun": .bool(dryRun),
        ]
    }

    static func runAdd(_ invocation: CommandInvocation) async throws -> JSONValue {
        let arguments = invocation.arguments
        let shape = arguments.string("shape") ?? ""
        guard MaskShape.names.contains(shape) else {
            throw CommandError(.invalidValue, "--shape must be one of \(MaskShape.names.joined(separator: ", "))")
        }
        var component: [String: EditParameter] = ["shape": .string(shape)]
        if let params = arguments.values["params"] {
            guard case .object(let object) = EditParameter(params) else {
                throw CommandError(.invalidValue, "--params must be a JSON object")
            }
            component.merge(object) { _, new in new }
        }
        if let operation = arguments.string("operation") { component["operation"] = .string(operation) }
        if arguments.flag("invert") { component["invert"] = .bool(true) }
        let settings = try arguments.strings("set").map(parseSetting)
        return try await change(invocation, creating: true) { masks throws(CommandError) in
            if let reference = arguments.string("mask") {
                let index = try find(reference, in: masks)
                var components: [EditParameter] = []
                if case .list(let existing)? = masks[index]["components"] { components = existing }
                components.append(.object(component))
                masks[index]["components"] = .list(components)
            } else {
                var mask: [String: EditParameter] = ["id": .string(UUID().uuidString), "components": .list([.object(component)])]
                if let name = arguments.string("name") { mask["name"] = .string(name) }
                for (key, value) in settings { try assign(key, value, to: &mask) }
                masks.append(mask)
            }
        }
    }

    static func runSet(_ invocation: CommandInvocation) async throws -> JSONValue {
        let settings = try invocation.arguments.strings("set").map(parseSetting)
        guard !settings.isEmpty else { throw CommandError(.missingArgument, "mask set needs --set name=value") }
        return try await change(invocation, creating: false) { masks throws(CommandError) in
            let index = try find(invocation.arguments.string("mask") ?? "", in: masks)
            for (key, value) in settings { try assign(key, value, to: &masks[index]) }
        }
    }

    static func runRemove(_ invocation: CommandInvocation) async throws -> JSONValue {
        try await change(invocation, creating: false) { masks throws(CommandError) in
            let index = try find(invocation.arguments.string("mask") ?? "", in: masks)
            if let component = invocation.arguments.integer("component") {
                guard case .list(var components)? = masks[index]["components"], components.indices.contains(component) else {
                    throw CommandError(.invalidValue, "No component \(component)")
                }
                components.remove(at: component)
                masks[index]["components"] = components.isEmpty ? nil : .list(components)
            } else {
                masks.remove(at: index)
            }
        }
    }

    // MARK: Helpers

    /// A mask by id, or by its index.
    static func find(_ reference: String, in masks: [[String: EditParameter]]) throws(CommandError) -> Int {
        if let index = masks.firstIndex(where: {
            if case .string(let id)? = $0["id"] { id.caseInsensitiveCompare(reference) == .orderedSame } else { false }
        }) {
            return index
        }
        if let index = Int(reference), masks.indices.contains(index) { return index }
        throw CommandError(.invalidValue, "No mask \(reference)")
    }

    /// `name=value`; the value is JSON when it parses as JSON, text otherwise.
    static func parseSetting(_ text: String) throws(CommandError) -> (String, EditParameter) {
        guard let equals = text.firstIndex(of: "="), equals != text.startIndex else {
            throw CommandError(.invalidValue, "--set takes name=value, not \(text)")
        }
        let key = String(text[..<equals])
        let raw = String(text[text.index(after: equals)...])
        let value = (try? JSONValue.parse(raw)).map(EditParameter.init) ?? .string(raw)
        return (key, value)
    }

    /// Mask keys (`amount`, `name`, `isEnabled`), local values (`exposure`, …),
    /// or `component.K.key`.
    static func assign(_ key: String, _ value: EditParameter, to mask: inout [String: EditParameter]) throws(CommandError) {
        let parts = key.split(separator: ".", maxSplits: 2).map(String.init)
        if parts.count == 3, parts[0] == "component", let index = Int(parts[1]) {
            guard case .list(var components)? = mask["components"], components.indices.contains(index),
                  case .object(var component) = components[index] else {
                throw CommandError(.invalidValue, "No component \(index)")
            }
            component[parts[2]] = value
            components[index] = .object(component)
            mask["components"] = .list(components)
        } else if ["amount", "name", "isEnabled"].contains(key) {
            mask[key] = value
        } else if LocalValues.controls.contains(where: { $0.name == key }) {
            var local: [String: EditParameter] = [:]
            if case .object(let existing)? = mask["adjustments"] { local = existing }
            local[key] = value
            mask["adjustments"] = .object(local)
        } else {
            throw CommandError(.invalidValue, "Unknown mask setting \(key)")
        }
    }

    static func masksJSON(_ local: LocalAdjustments) -> JSONValue {
        .array(local.masks.enumerated().map { index, mask in
            var object = JSONValue(EditParameter.object(mask.parameters)).objectValue ?? [:]
            object["index"] = JSONValue(index)
            return .object(object)
        })
    }

    /// The local controls, shapes and limits, for `adjustments`.
    static var description: JSONValue {
        func number(_ name: String, _ range: ClosedRange<Double>, _ value: Double?) -> JSONValue {
            ["name": .string(name), "type": "number", "minimum": .number(range.lowerBound),
             "maximum": .number(range.upperBound), "default": value.map(JSONValue.number) ?? .null]
        }
        let coordinate = LinearGradient.coordinateRange
        return [
            "controls": .array(LocalValues.controls.map { number($0.name, $0.range, 0) }),
            "mask": .array([number("amount", Mask.amountRange, 100),
                            ["name": "name", "type": "text", "default": ""],
                            ["name": "isEnabled", "type": "flag", "default": true]]),
            "operations": .array(MaskOperation.allCases.map { .string($0.rawValue) }),
            "shapes": [
                "linear": .array([number("startX", coordinate, nil), number("startY", coordinate, nil),
                                  number("endX", coordinate, nil), number("endY", coordinate, nil),
                                  number("feather", LinearGradient.featherRange, 100)]),
                "radial": .array([number("centerX", coordinate, nil), number("centerY", coordinate, nil),
                                  number("radiusX", RadialGradient.radiusRange, nil),
                                  number("radiusY", RadialGradient.radiusRange, nil),
                                  number("rotation", RadialGradient.rotationRange, 0),
                                  number("feather", RadialGradient.featherRange, 50)]),
                "brush": .array([["name": "strokes", "type": "list", "items": .array([
                    ["name": "points", "type": "points"], number("size", BrushStroke.sizeRange, 0.03),
                    number("feather", BrushStroke.percentRange, 50), number("flow", BrushStroke.flowRange, 100),
                    number("density", BrushStroke.flowRange, 100), ["name": "erase", "type": "flag", "default": false],
                ])]]),
                "luminanceRange": .array([number("lower", LuminanceRange.range, 0.5),
                                          number("upper", LuminanceRange.range, 1),
                                          number("smoothness", LuminanceRange.range, 0.1)]),
                "colorRange": .array([["name": "samples", "type": "list of OkLab [L, a, b]"],
                                      number("tolerance", ColorRange.toleranceRange, 30)]),
            ],
            "limits": ["masks": JSONValue(MaskLimits.masks), "componentsPerMask": JSONValue(MaskLimits.componentsPerMask),
                       "colorSamples": JSONValue(MaskLimits.colorSamples),
                       "brushPointsPerMask": JSONValue(MaskLimits.brushPointsPerMask)],
        ]
    }
}

extension EditParameter {
    /// A JSON value as a parameter (null becomes an empty list, which no reader accepts as a value).
    init(_ json: JSONValue) {
        switch json {
        case .null: self = .list([])
        case .bool(let value): self = .bool(value)
        case .number(let value): self = .number(value)
        case .string(let value): self = .string(value)
        case .array(let values): self = .list(values.map(EditParameter.init))
        case .object(let values): self = .object(values.mapValues(EditParameter.init))
        }
    }
}
