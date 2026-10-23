import Foundation

/// The non-destructive edit recipe of one version: an ordered list of operations
/// applied to the decoded master in linear working space.
///
/// Stored as JSON on the `version` row. The JSON is versioned at two levels:
/// `schemaVersion` describes the container format, and each operation's
/// `kindVersion` describes the meaning of its parameters, so an operation's
/// algorithm can change later without breaking stacks written today.
public struct EditStack: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var operations: [EditOperation]

    public init(operations: [EditOperation] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.operations = operations
    }

    /// The empty stack every new version starts with.
    public static let identity = EditStack()

    /// True when rendering this stack cannot change the image.
    public var isIdentity: Bool {
        !operations.contains { $0.isEnabled }
    }

    // MARK: Persistence

    public enum DecodingFailure: Error, Equatable {
        /// Written by a newer build than this one understands.
        case unsupportedSchemaVersion(Int)
    }

    private struct Header: Decodable {
        var schemaVersion: Int
    }

    /// Canonical JSON: sorted keys, no insignificant whitespace.
    public func jsonData() throws -> Data {
        try Self.canonicalEncoder.encode(self)
    }

    public func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self)
    }

    /// Decodes a stored stack, upgrading older schema versions.
    public static func decode(from data: Data) throws -> EditStack {
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.schemaVersion <= currentSchemaVersion else {
            throw DecodingFailure.unsupportedSchemaVersion(header.schemaVersion)
        }
        // Schema upgrades go here, oldest first, once there is more than one version.
        return try decoder.decode(EditStack.self, from: data)
    }

    public static func decode(from string: String) throws -> EditStack {
        try decode(from: Data(string.utf8))
    }

    // MARK: Render identity

    private struct RenderPayload: Encodable {
        struct Operation: Encodable {
            var kind: EditOperationKind
            var kindVersion: Int
            var parameters: [String: EditParameter]
        }
        var schemaVersion: Int
        var operations: [Operation]
    }

    /// Hash of everything that affects the rendered pixels, used in preview cache
    /// keys. Operation ids and disabled operations are excluded, so two stacks that
    /// render the same share previews.
    public var renderHash: String {
        let payload = RenderPayload(
            schemaVersion: schemaVersion,
            operations: operations.filter(\.isEnabled).map {
                .init(kind: $0.kind, kindVersion: $0.kindVersion, parameters: $0.parameters)
            }
        )
        // Encoding plain values with sorted keys cannot fail.
        let data = (try? Self.canonicalEncoder.encode(payload)) ?? Data()
        return Digest.sha256Hex(data)
    }

    static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

/// One step of an edit stack.
public struct EditOperation: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: EditOperationKind
    /// Version of `kind`'s parameter semantics.
    public var kindVersion: Int
    public var isEnabled: Bool
    public var parameters: [String: EditParameter]

    public init(id: UUID = UUID(), kind: EditOperationKind, kindVersion: Int = 1,
                isEnabled: Bool = true, parameters: [String: EditParameter] = [:]) {
        self.id = id
        self.kind = kind
        self.kindVersion = kindVersion
        self.isEnabled = isEnabled
        self.parameters = parameters
    }
}

/// Identifier of an operation type. Generic, stable strings: they are persisted.
public struct EditOperationKind: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Does nothing. The only operation phase 1 renders.
    public static let passThrough: EditOperationKind = "passThrough"
}

/// A JSON-friendly parameter value. Numbers are always `Double` so that values
/// survive a JSON round trip unchanged.
public enum EditParameter: Codable, Hashable, Sendable {
    case number(Double)
    case bool(Bool)
    case string(String)
    case list([EditParameter])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([EditParameter].self) {
            self = .list(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported parameter value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .list(let value): try container.encode(value)
        }
    }
}
