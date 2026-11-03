import Foundation

/// A naming template split the way the template field shows it: literal text
/// between tokens. Splitting follows `ImportTemplate.expand` exactly (a token
/// runs from `{` to the next `}`; a `{` with no `}` after it is text), so
/// `join(parse(t)) == t` for every template and stored templates never change.
public enum TemplatePart: Hashable, Sendable {
    case text(String)
    /// The token's syntax with its braces, e.g. `{capture:yyyy}`.
    case token(String)

    /// Length in the field's editor: a token is one attachment character,
    /// text is its UTF-16 length (`NSTextView` ranges).
    public var editorLength: Int {
        switch self {
        case .text(let text): text.utf16.count
        case .token: 1
        }
    }

    public var syntax: String {
        switch self {
        case .text(let text), .token(let text): text
        }
    }
}

public enum TemplateParts {
    /// With `isToken`, braces it rejects are text (the template field shows
    /// tokens the grammar does not know as text, see `TemplateToken`).
    public static func parse(_ template: String, isToken: (String) -> Bool = { _ in true }) -> [TemplatePart] {
        var parts: [TemplatePart] = []
        func append(_ text: Substring) {
            guard !text.isEmpty else { return }
            if case .text(let last) = parts.last {
                parts[parts.count - 1] = .text(last + text)
            } else {
                parts.append(.text(String(text)))
            }
        }
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            append(rest[..<open])
            let token = rest[open...close]
            if isToken(String(token)) { parts.append(.token(String(token))) } else { append(token) }
            rest = rest[rest.index(after: close)...]
        }
        append(rest)
        return parts
    }

    public static func join(_ parts: [TemplatePart]) -> String {
        parts.map(\.syntax).joined()
    }

    /// Adjacent text merged, empty text dropped, and tokens typed as text
    /// (`{job}`) turned into tokens.
    public static func normalized(_ parts: [TemplatePart], isToken: (String) -> Bool = { _ in true }) -> [TemplatePart] {
        parse(join(parts), isToken: isToken)
    }

    /// Inserts `token` at `location` (an offset in the editor, see
    /// `TemplatePart.editorLength`; past the end appends). With a
    /// `separator`, the token starts a new component: the separator goes
    /// before it unless it is at the start or after one already.
    /// Returns the parts and the editor offset just after the token.
    public static func inserting(_ token: String, into parts: [TemplatePart], at location: Int,
                                 separator: String? = nil,
                                 isToken: (String) -> Bool = { _ in true }) -> (parts: [TemplatePart], caret: Int) {
        var before: [TemplatePart] = []
        var after: [TemplatePart] = []
        var offset = 0
        for part in parts {
            let length = part.editorLength
            if offset + length <= location {
                before.append(part)
            } else if offset >= location {
                after.append(part)
            } else if case .text(let text) = part {
                // The caret is inside this text: split it (by UTF-16 offset).
                let utf16 = Array(text.utf16)
                let split = location - offset
                before.append(.text(String(decoding: utf16[..<split], as: UTF16.self)))
                after.append(.text(String(decoding: utf16[split...], as: UTF16.self)))
            }
            offset += length
        }
        var inserted: [TemplatePart] = []
        if let separator, !before.isEmpty, !join(before).hasSuffix(separator) {
            inserted.append(.text(separator))
        }
        inserted.append(.token(token))
        let head = normalized(before + inserted, isToken: isToken)
        return (normalized(head + after, isToken: isToken), head.reduce(0) { $0 + $1.editorLength })
    }
}

/// What a `{…}` token means, read the way `ImportTemplate` expands it.
/// `nil` from `init(syntax:)` is a token the grammar does not know: it
/// renders as written, so the template field shows it as plain text.
public enum TemplateToken: Hashable, Sendable {
    public enum DateSource: String, Sendable {
        case capture, `import`, export
    }

    public enum Case: String, Sendable {
        case lower, upper
    }

    case date(DateSource, pattern: String)
    case make, model, serial, lens
    case name, number
    case ext(Case?)
    case sequence, counter
    case job

    public init?(syntax: String) {
        guard syntax.hasPrefix("{"), syntax.hasSuffix("}"), syntax.count >= 2 else { return nil }
        let body = syntax.dropFirst().dropLast()
        let parts = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let argument = parts.count > 1 ? parts[1] : nil
        switch parts.first ?? "" {
        case "capture", "import", "export":
            guard let argument, let source = DateSource(rawValue: parts[0]) else { return nil }
            self = .date(source, pattern: argument)
        case "make": self = .make
        case "model": self = .model
        case "serial": self = .serial
        case "lens": self = .lens
        case "name": self = .name
        case "number": self = .number
        case "ext": self = .ext(argument.flatMap(Case.init(rawValue:)))
        case "seq": self = .sequence
        case "counter": self = .counter
        case "job": self = .job
        default: return nil
        }
    }

    /// The token's value for one photo, as the template would render it.
    public static func value(of syntax: String, in context: TemplateContext) -> String {
        ImportTemplate.expand(syntax, context)
    }
}
