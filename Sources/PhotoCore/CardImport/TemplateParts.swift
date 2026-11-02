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
    public static func parse(_ template: String) -> [TemplatePart] {
        var parts: [TemplatePart] = []
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            if open > rest.startIndex { parts.append(.text(String(rest[..<open]))) }
            parts.append(.token(String(rest[open...close])))
            rest = rest[rest.index(after: close)...]
        }
        if !rest.isEmpty { parts.append(.text(String(rest))) }
        return parts
    }

    public static func join(_ parts: [TemplatePart]) -> String {
        parts.map(\.syntax).joined()
    }

    /// Adjacent text merged, empty text dropped, and tokens typed as text
    /// (`{job}`) turned into tokens.
    public static func normalized(_ parts: [TemplatePart]) -> [TemplatePart] {
        parse(join(parts))
    }

    /// Inserts `token` at `location` (an offset in the editor, see
    /// `TemplatePart.editorLength`; past the end appends). With a
    /// `separator`, the token starts a new component: the separator goes
    /// before it unless it is at the start or after one already.
    /// Returns the parts and the editor offset just after the token.
    public static func inserting(_ token: String, into parts: [TemplatePart], at location: Int,
                                 separator: String? = nil) -> (parts: [TemplatePart], caret: Int) {
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
        let head = normalized(before + inserted)
        return (normalized(head + after), head.reduce(0) { $0 + $1.editorLength })
    }
}
