import Foundation

/// Commands defined once, with a parameter schema and a handler that returns
/// JSON, so that the command line, and later an MCP server or the app's debug
/// script, can all dispatch the same ones.
///
/// Arguments arrive as JSON values keyed by parameter name (camelCase).
/// Handlers never print: they return a value or throw a `CommandError`.
public struct CommandRegistry: Sendable {
    public let commands: [CommandSpec]

    public init(commands: [CommandSpec]) {
        self.commands = commands
    }

    public func command(_ id: String) -> CommandSpec? {
        commands.first { $0.id == id }
    }

    /// Runs `id`. Write commands first take the library lock (`LibraryLock`)
    /// and refuse with `libraryLocked` when another process, normally the
    /// app, holds it; they hold it until they are done.
    public func run(_ id: String, arguments: [String: JSONValue],
                    environment: CommandEnvironment) async throws(CommandError) -> JSONValue {
        guard let command = command(id) else { throw CommandError(.unknownCommand, "Unknown command \(id)") }
        let arguments = try command.validate(arguments)
        var lock: LibraryLock?
        if command.access.writes(arguments) {
            lock = try environment.lockLibrary(arguments)
        }
        defer { lock?.release() }
        do {
            return try await command.run(CommandInvocation(arguments: arguments, environment: environment))
        } catch let error as CommandError {
            throw error
        } catch {
            throw CommandError(.failed, String(describing: error))
        }
    }

    /// Every command's schema, for `help` and for tools.
    public var schema: JSONValue {
        .array(commands.map(\.schema))
    }
}

/// A command: its id, what it does, its parameters and its handler.
public struct CommandSpec: Sendable {
    public enum Access: String, Sendable {
        /// Reads only; always allowed.
        case read
        /// Writes the catalog.
        case write
        /// Writes the catalog unless `dryRun` is set.
        case writeUnlessDryRun

        func writes(_ arguments: CommandArguments) -> Bool {
            switch self {
            case .read: false
            case .write: true
            case .writeUnlessDryRun: !arguments.flag("dryRun")
            }
        }
    }

    /// Dotted, stable identifier (`render`, `query.images`).
    public var id: String
    public var summary: String
    public var access: Access
    public var parameters: [CommandParameter]
    public var run: @Sendable (CommandInvocation) async throws -> JSONValue

    public init(id: String, summary: String, access: Access, parameters: [CommandParameter],
                run: @escaping @Sendable (CommandInvocation) async throws -> JSONValue) {
        self.id = id
        self.summary = summary
        self.access = access
        self.parameters = parameters
        self.run = run
    }

    /// Checks names, types and required parameters.
    func validate(_ arguments: [String: JSONValue]) throws(CommandError) -> CommandArguments {
        for name in arguments.keys where !parameters.contains(where: { $0.name == name }) {
            throw CommandError(.unknownOption, "\(id) has no parameter \(name)")
        }
        for parameter in parameters {
            guard let value = arguments[parameter.name], value != .null else {
                if parameter.isRequired {
                    throw CommandError(.missingArgument, "\(id) needs \(parameter.name)")
                }
                continue
            }
            let values = parameter.isRepeatable ? (value.arrayValue ?? [value]) : [value]
            for item in values where !parameter.kind.accepts(item) {
                throw CommandError(.invalidValue, "\(parameter.name) must be \(parameter.kind.rawValue)")
            }
        }
        return CommandArguments(values: arguments)
    }

    var schema: JSONValue {
        [
            "id": .string(id),
            "summary": .string(summary),
            "access": .string(access.rawValue),
            "parameters": .array(parameters.map(\.schema)),
        ]
    }
}

/// One parameter of a command.
public struct CommandParameter: Sendable {
    public enum Kind: String, Sendable {
        case string, integer, number, flag, path, json

        func accepts(_ value: JSONValue) -> Bool {
            switch (self, value) {
            case (.string, .string), (.path, .string), (.flag, .bool), (.number, .number), (.json, _): true
            case (.integer, .number(let number)): number.rounded() == number
            default: false
            }
        }
    }

    /// camelCase; `--kebab-case` on the command line.
    public var name: String
    public var kind: Kind
    public var summary: String
    public var isRequired = false
    /// Given several times; arrives as an array.
    public var isRepeatable = false
    /// May be given without its name on the command line, in declaration order.
    public var isPositional = false

    public init(_ name: String, _ kind: Kind, _ summary: String, required: Bool = false, repeatable: Bool = false,
                positional: Bool = false) {
        self.name = name
        self.kind = kind
        self.summary = summary
        isRequired = required
        isRepeatable = repeatable
        isPositional = positional
    }

    var schema: JSONValue {
        [
            "name": .string(name),
            "type": .string(kind.rawValue),
            "summary": .string(summary),
            "required": .bool(isRequired),
            "repeatable": .bool(isRepeatable),
            "positional": .bool(isPositional),
        ]
    }
}

/// Validated arguments, with typed reads.
public struct CommandArguments: Sendable {
    public var values: [String: JSONValue]

    public func string(_ name: String) -> String? { values[name]?.stringValue }

    public func integer(_ name: String) -> Int? { values[name]?.numberValue.map { Int($0) } }

    public func flag(_ name: String) -> Bool { values[name]?.boolValue ?? false }

    /// A repeatable parameter's values (one value counts as a list of one).
    public func list(_ name: String) -> [JSONValue] {
        guard let value = values[name], value != .null else { return [] }
        return value.arrayValue ?? [value]
    }

    public func strings(_ name: String) -> [String] { list(name).compactMap(\.stringValue) }

    public func integers(_ name: String) -> [Int64] { list(name).compactMap { $0.numberValue.map { Int64($0) } } }
}

public struct CommandInvocation: Sendable {
    public var arguments: CommandArguments
    public var environment: CommandEnvironment
}

/// Where commands run: the directory relative paths start from, and the
/// library when none is named (the app's standard location).
public struct CommandEnvironment: Sendable {
    public var currentDirectory: URL
    public var defaultLibraryRoot: URL?

    public init(currentDirectory: URL, defaultLibraryRoot: URL? = nil) {
        self.currentDirectory = currentDirectory
        self.defaultLibraryRoot = defaultLibraryRoot
    }

    /// `path` resolved against the current directory, with `~` expanded.
    public func url(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, relativeTo: currentDirectory).standardizedFileURL
    }

    /// The library named by `libraryRoot`, or the standard one.
    public func libraryLocations(_ arguments: CommandArguments) throws(CommandError) -> LibraryLocations {
        if let root = arguments.string("libraryRoot") {
            return .rooted(at: url(root))
        }
        if let root = defaultLibraryRoot {
            return .rooted(at: root)
        }
        do {
            return try LibraryLocations.standard()
        } catch {
            throw CommandError(.libraryNotFound, "No standard library location: \(error)")
        }
    }

    /// Opens an existing library's catalog. Never creates one.
    public func openLibrary(_ arguments: CommandArguments) throws(CommandError) -> OpenLibrary {
        let locations = try libraryLocations(arguments)
        guard FileManager.default.fileExists(atPath: locations.catalogFileURL.path) else {
            throw CommandError(.libraryNotFound, "No library at \(locations.catalogDirectory.deletingLastPathComponent().path)")
        }
        do {
            return OpenLibrary(locations: locations, catalog: try Catalog.open(at: locations.catalogFileURL))
        } catch {
            throw CommandError(.failed, "Could not open the catalog: \(error)")
        }
    }

    func lockLibrary(_ arguments: CommandArguments) throws(CommandError) -> LibraryLock {
        let locations = try libraryLocations(arguments)
        guard FileManager.default.fileExists(atPath: locations.catalogFileURL.path) else {
            throw CommandError(.libraryNotFound, "No library at \(locations.catalogDirectory.deletingLastPathComponent().path)")
        }
        do throws(LibraryLock.Failure) {
            return try LibraryLock.acquire(locations)
        } catch .held(let processID) {
            let holder = processID.map { " (process \($0))" } ?? ""
            throw CommandError(.libraryLocked, """
                The library is open in another process\(holder), probably the app. Quit it to make changes \
                from the command line; reading is always allowed.
                """)
        } catch {
            throw CommandError(.failed, "Could not lock the library: \(error)")
        }
    }
}

/// A library opened by a command.
public struct OpenLibrary: Sendable {
    public var locations: LibraryLocations
    public var catalog: Catalog

    public var lookTables: LookTableStore { LookTableStore(locations: locations) }
}

/// A failure, reported as `{"error": message, "code": code}`.
public struct CommandError: Error, Equatable, Sendable {
    public enum Code: String, Sendable {
        case unknownCommand, unknownOption, missingArgument, missingValue, invalidValue, invalidJSON
        case conflictingOptions
        case libraryNotFound, libraryLocked
        case versionNotFound, fileNotFound, presetNotFound
        case invalidEdit
        /// The version's stored stack cannot be read (a newer build's, or damaged); it is left unchanged.
        case unreadableEditStack
        case softwareRendererUnavailable
        case renderFailed, writeFailed
        case failed

        /// Usage errors exit with 2, everything else with 1.
        public var isUsageError: Bool {
            switch self {
            case .unknownCommand, .unknownOption, .missingArgument, .missingValue, .invalidValue, .invalidJSON,
                 .conflictingOptions: true
            default: false
            }
        }
    }

    public var code: Code
    public var message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    public var json: JSONValue {
        ["error": .string(message), "code": .string(code.rawValue)]
    }
}

extension EditStack.ReadFailure {
    /// "newerVersion" or "damaged", for command output.
    var name: String {
        switch self {
        case .newerVersion: "newerVersion"
        case .damaged: "damaged"
        }
    }
}

extension VersionRecord {
    /// The stored stack, or `unreadableEditStack` naming why it cannot be read.
    func readableEditStack() throws(CommandError) -> EditStack {
        do {
            return try decodedEditStack()
        } catch {
            let id = self.id ?? 0
            switch EditStack.ReadFailure(error) {
            case .newerVersion(let schema):
                throw CommandError(.unreadableEditStack, """
                    Version \(id)'s edits were saved by a newer version of \(AppBranding.displayName) \
                    (edit format \(schema)); they are left unchanged.
                    """)
            case .damaged:
                throw CommandError(.unreadableEditStack, "Version \(id)'s edits cannot be read; they are left unchanged.")
            }
        }
    }
}
