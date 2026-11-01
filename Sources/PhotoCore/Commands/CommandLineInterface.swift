import Foundation

/// The command line over a `CommandRegistry`: turns `argv` into a command id
/// and arguments, runs it, and keeps the output contract. Every command prints
/// exactly one JSON object on stdout and exits 0; a failure prints one object
/// with `error` and `code` on stderr and exits 2 (usage) or 1 (anything else).
public struct CommandLineInterface: Sendable {
    public static let toolName = "photocli"

    public struct Output: Sendable, Equatable {
        public var exitCode: Int32
        public var standardOutput: String
        public var standardError: String
    }

    public let registry: CommandRegistry
    public let environment: CommandEnvironment

    public init(registry: CommandRegistry = .standard, environment: CommandEnvironment) {
        self.registry = registry
        self.environment = environment
    }

    /// Runs `arguments` (without the program name).
    public func run(_ arguments: [String]) async -> Output {
        do throws(CommandError) {
            let (id, values) = try parse(arguments)
            if id == "help" {
                return success(try help(values.stringValue))
            }
            let result = try await registry.run(id, arguments: values.objectValue ?? [:], environment: environment)
            return success(result)
        } catch {
            return Output(exitCode: error.code.isUsageError ? 2 : 1, standardOutput: "",
                          standardError: error.json.jsonString(pretty: false) + "\n")
        }
    }

    private func success(_ value: JSONValue) -> Output {
        // A command that returned something else is still reported as one object.
        let object: JSONValue = value.objectValue != nil ? value : ["result": value]
        return Output(exitCode: 0, standardOutput: object.jsonString() + "\n", standardError: "")
    }

    // MARK: Parsing

    /// The command id and its arguments. `help` returns the topic as a string.
    func parse(_ arguments: [String]) throws(CommandError) -> (String, JSONValue) {
        guard var first = arguments.first, first != "--help", first != "-h" else { return ("help", .null) }
        var rest = arguments.dropFirst()
        if first == "help" {
            // `help query images` is about `query.images`.
            return ("help", rest.isEmpty ? .null : .string(rest.joined(separator: ".")))
        }
        // `query images` is the command `query.images`.
        if let next = rest.first, !next.hasPrefix("-"), registry.command("\(first).\(next)") != nil {
            first = "\(first).\(next)"
            rest = rest.dropFirst()
        }
        guard let command = registry.command(first) else {
            throw CommandError(.unknownCommand, "Unknown command \(first). Run \(Self.toolName) help.")
        }
        return (first, .object(try parseOptions(Array(rest), for: command)))
    }

    func parseOptions(_ tokens: [String], for command: CommandSpec) throws(CommandError) -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        var positional = command.parameters.filter(\.isPositional).makeIterator()
        var index = 0
        func add(_ parameter: CommandParameter, _ value: JSONValue) throws(CommandError) {
            if parameter.isRepeatable {
                values[parameter.name] = .array((values[parameter.name]?.arrayValue ?? []) + [value])
            } else if values[parameter.name] != nil {
                throw CommandError(.conflictingOptions, "--\(Self.optionName(parameter.name)) is given twice")
            } else {
                values[parameter.name] = value
            }
        }
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            guard token.hasPrefix("--") else {
                guard let parameter = positional.next() else {
                    throw CommandError(.unknownOption, "Unexpected argument \(token)")
                }
                try add(parameter, try Self.value(token, for: parameter))
                continue
            }
            var name = String(token.dropFirst(2))
            var inline: String?
            if let equals = name.firstIndex(of: "=") {
                inline = String(name[name.index(after: equals)...])
                name = String(name[..<equals])
            }
            guard let parameter = command.parameters.first(where: { Self.optionName($0.name) == name }) else {
                throw CommandError(.unknownOption, "\(command.id) has no option --\(name)")
            }
            if parameter.kind == .flag, inline == nil {
                try add(parameter, .bool(true))
                continue
            }
            guard let text = inline ?? (index < tokens.count ? tokens[index] : nil) else {
                throw CommandError(.missingValue, "--\(name) needs a value")
            }
            if inline == nil { index += 1 }
            try add(parameter, try Self.value(text, for: parameter))
        }
        return values
    }

    /// `libraryRoot` is `library-root`.
    static func optionName(_ name: String) -> String {
        name.reduce(into: "") { result, character in
            if character.isUppercase {
                result += "-" + character.lowercased()
            } else {
                result.append(character)
            }
        }
    }

    static func value(_ text: String, for parameter: CommandParameter) throws(CommandError) -> JSONValue {
        let option = "--" + optionName(parameter.name)
        switch parameter.kind {
        case .string, .path:
            return .string(text)
        case .integer:
            guard let value = Int64(text) else { throw CommandError(.invalidValue, "\(option) needs a whole number") }
            return .number(Double(value))
        case .number:
            guard let value = Double(text), value.isFinite else {
                throw CommandError(.invalidValue, "\(option) needs a number")
            }
            return .number(value)
        case .flag:
            switch text {
            case "true", "yes", "1": return .bool(true)
            case "false", "no", "0": return .bool(false)
            default: throw CommandError(.invalidValue, "\(option) is true or false")
            }
        case .json:
            do {
                return try JSONValue.parse(text)
            } catch {
                throw CommandError(.invalidJSON, "\(option) is not valid JSON")
            }
        }
    }

    // MARK: Help

    func help(_ topic: String?) throws(CommandError) -> JSONValue {
        if let topic {
            guard let command = registry.command(topic) else {
                throw CommandError(.unknownCommand, "Unknown command \(topic)")
            }
            return ["command": command.schema, "usage": .string(usage(command))]
        }
        return [
            "product": .string(AppBranding.displayName),
            "tool": .string(Self.toolName),
            "summary": .string("Renders, queries and edits a \(AppBranding.displayName) library without the app."),
            "usage": .string("\(Self.toolName) <command> [options]; \(Self.toolName) help <command>"),
            "output": .string("""
                One JSON object on stdout and exit 0; on failure one object with "error" and "code" on stderr, \
                exit 2 for usage errors and 1 otherwise.
                """),
            "commands": .array(registry.commands.map {
                ["id": .string($0.id), "summary": .string($0.summary), "usage": .string(usage($0))]
            }),
        ]
    }

    func usage(_ command: CommandSpec) -> String {
        let words = command.id.replacingOccurrences(of: ".", with: " ")
        let options = command.parameters.map { parameter in
            let name = "--" + Self.optionName(parameter.name)
            let text = parameter.kind == .flag ? name : "\(name) <\(parameter.kind.rawValue)>"
            let shown = parameter.isPositional ? "[\(name)] <\(parameter.kind.rawValue)>" : text
            let repeated = parameter.isRepeatable ? shown + "…" : shown
            return parameter.isRequired ? repeated : "[\(repeated)]"
        }
        return ([Self.toolName, words] + options).joined(separator: " ")
    }
}
