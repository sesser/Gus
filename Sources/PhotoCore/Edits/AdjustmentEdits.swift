import Foundation

/// Changes to single parameters of an edit stack, checked against
/// `Adjustments.moduleDescriptions`, as scripts make them. Values go through
/// `Adjustments`, so defaults are left out exactly as when the app saves.
public enum AdjustmentEdit: Hashable, Sendable {
    /// `kind.parameter=value`, the value given as text.
    case set(kind: EditOperationKind, parameter: String, value: String)
    /// One parameter back to its default, or the whole module when `parameter` is nil.
    case reset(kind: EditOperationKind, parameter: String?)
    /// Every module back to its default: the original.
    case resetAll

    public enum Failure: Error, Hashable, Sendable {
        case malformed(String)
        case unknownModule(String)
        case unknownParameter(kind: String, parameter: String)
        case invalidValue(kind: String, parameter: String, reason: String)
        /// The module ignored the value, for example one edge of a crop without the others.
        case noEffect(kind: String, parameter: String)
    }

    /// Parses `kind.parameter=value`.
    public static func parseSet(_ text: String) throws(Failure) -> AdjustmentEdit {
        guard let equals = text.firstIndex(of: "="), let dot = text[..<equals].firstIndex(of: ".") else {
            throw .malformed(text)
        }
        let kind = String(text[..<dot])
        let parameter = String(text[text.index(after: dot)..<equals])
        guard !kind.isEmpty, !parameter.isEmpty else { throw .malformed(text) }
        return .set(kind: EditOperationKind(rawValue: kind), parameter: parameter,
                    value: String(text[text.index(after: equals)...]))
    }

    /// Parses `kind.parameter`, `kind` or `all`.
    public static func parseReset(_ text: String) throws(Failure) -> AdjustmentEdit {
        if text == "all" { return .resetAll }
        let parts = text.split(separator: ".", maxSplits: 1).map(String.init)
        guard let kind = parts.first, !kind.isEmpty else { throw .malformed(text) }
        return .reset(kind: EditOperationKind(rawValue: kind), parameter: parts.count > 1 ? parts[1] : nil)
    }

    /// The typed value of `text` for `parameter` of `kind`.
    public static func value(_ text: String, for parameter: AdjustmentParameter,
                             of kind: EditOperationKind) throws(Failure) -> EditParameter {
        switch value(text, for: parameter) {
        case .success(let value): value
        case .failure(let failure): throw .invalidValue(kind: kind.rawValue, parameter: parameter.name,
                                                        reason: failure.reason)
        }
    }

    private struct InvalidValue: Error {
        var reason: String
        init(_ reason: String) { self.reason = reason }
    }

    private static func value(_ text: String, for parameter: AdjustmentParameter) -> Result<EditParameter, InvalidValue> {
        switch parameter.type {
        case .integer(let range):
            guard let number = Int(text) else { return .failure(InvalidValue("not a whole number: \(text)")) }
            guard range.contains(number) else {
                return .failure(InvalidValue("\(number) is outside \(range.lowerBound) … \(range.upperBound)"))
            }
            return .success(.number(Double(number)))
        case .integer(let range):
            guard let number = Int(text) else { return .failure(InvalidValue("not a whole number: \(text)")) }
            guard range.contains(number) else {
                return .failure(InvalidValue("\(number) is outside \(range.lowerBound) … \(range.upperBound)"))
            }
            return .success(.number(Double(number)))
        case .number(let range):
            guard let number = Double(text), number.isFinite else {
                return .failure(InvalidValue("not a number: \(text)"))
            }
            guard range.contains(number) else {
                return .failure(InvalidValue("\(number) is outside \(range.lowerBound) … \(range.upperBound)"))
            }
            return .success(.number(number))
        case .choice(let choices):
            guard choices.contains(text) else {
                return .failure(InvalidValue("one of \(choices.joined(separator: ", "))"))
            }
            return .success(.string(text))
        case .text:
            return .success(.string(text))
        case .points:
            let items = text.split(separator: ",")
            let values = items.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard values.count == items.count, values.count >= 4, values.count.isMultiple(of: 2),
                  values.allSatisfy({ (0...1).contains($0) })
            else { return .failure(InvalidValue("a list x0,y0,x1,y1,… of at least two points, each 0 … 1")) }
            return .success(.list(values.map(EditParameter.number)))
        }
    }
}

extension EditStack {
    /// The stack with `edits` applied in order, normalized once at the end as
    /// the app saves it (so the edges of a crop can be set one at a time).
    /// Changing a module that is turned off turns it back on, as in the app.
    /// Fails when a value set does not end up in the stack (one edge of a
    /// crop without the others).
    public func applying(_ edits: [AdjustmentEdit]) throws(AdjustmentEdit.Failure) -> EditStack {
        var stack = self
        // The last edit of each parameter decides what it should be at the end.
        var expected: [String: (kind: EditOperationKind, name: String, value: EditParameter?)] = [:]
        for edit in edits {
            switch edit {
            case .resetAll:
                stack = .identity
                expected = [:]
            case .reset(let kind, let name):
                guard let module = Adjustments.moduleDescription(kind) else { throw .unknownModule(kind.rawValue) }
                if let name {
                    guard module.parameters.contains(where: { $0.name == name }) else {
                        throw .unknownParameter(kind: kind.rawValue, parameter: name)
                    }
                    stack.changeOperation(kind) { $0[name] = nil }
                    expected["\(kind.rawValue).\(name)"] = nil
                } else {
                    stack.changeOperation(kind) { $0 = [:] }
                    expected = expected.filter { $0.value.kind != kind }
                }
            case .set(let kind, let name, let text):
                guard let module = Adjustments.moduleDescription(kind) else { throw .unknownModule(kind.rawValue) }
                guard let parameter = module.parameters.first(where: { $0.name == name }) else {
                    throw .unknownParameter(kind: kind.rawValue, parameter: name)
                }
                let value = try AdjustmentEdit.value(text, for: parameter, of: kind)
                stack.changeOperation(kind) { $0[name] = value }
                expected["\(kind.rawValue).\(name)"] = (kind, name, value == parameter.defaultValue ? nil : value)
            }
        }
        var after = Adjustments(stack: stack)
        after.enableModules(changedFrom: Adjustments(stack: self))
        for (kind, name, value) in expected.values where after.parameters(of: kind)[name] != value {
            throw .noEffect(kind: kind.rawValue, parameter: name)
        }
        return after.editStack
    }

    /// Changes the parameters of the module's operation, adding one when the stack has none.
    private mutating func changeOperation(_ kind: EditOperationKind, _ change: (inout [String: EditParameter]) -> Void) {
        if let index = operations.firstIndex(where: { $0.kind == kind && $0.kindVersion == 1 }) {
            change(&operations[index].parameters)
        } else {
            var parameters: [String: EditParameter] = [:]
            change(&parameters)
            operations.append(EditOperation(kind: kind, parameters: parameters))
        }
    }
}
