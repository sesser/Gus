import Foundation

/// One value of a preset in the Camera Raw settings format: a number, text, a
/// flag, a list (curve points, local corrections) or a record of named values.
public indirect enum CameraRawValue: Hashable, Sendable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case list([CameraRawValue])
    case record([String: CameraRawValue])

    /// Numbers, and text that reads as one ("+0.50"; XMP stores everything as text).
    public var number: Double? {
        switch self {
        case .number(let value): value.isFinite ? value : nil
        case .string(let text):
            Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: ""))
                .flatMap { $0.isFinite ? $0 : nil }
        case .bool(let flag): flag ? 1 : 0
        default: nil
        }
    }

    public var bool: Bool? {
        switch self {
        case .bool(let flag): flag
        case .number(let value): value != 0
        case .string(let text):
            switch text.lowercased() {
            case "true": true
            case "false": false
            default: number.map { $0 != 0 }
            }
        default: nil
        }
    }

    public var string: String? {
        switch self {
        case .string(let text): text
        case .number(let value): String(value)
        default: nil
        }
    }

    public var list: [CameraRawValue]? {
        if case .list(let items) = self { return items }
        return nil
    }

    public var record: [String: CameraRawValue]? {
        if case .record(let values) = self { return values }
        return nil
    }
}

/// The develop settings of one preset, read from an `.lrtemplate` file (a Lua
/// table), an `.xmp` file (Camera Raw settings namespace) or a `.dng` preset
/// (a photo whose embedded XMP carries the settings, as mobile presets are
/// shared), under the names the formats share.
public struct CameraRawSettings: Sendable {
    public static let templateExtension = "lrtemplate"
    public static let xmpExtension = "xmp"
    public static let dngExtension = "dng"
    static let namespace = "http://ns.adobe.com/camera-raw-settings/1.0/"
    static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    public enum Failure: Error, Equatable {
        case malformed(line: Int)
        /// A template of another kind (metadata, export, …).
        case notADevelopPreset
        /// An XMP file without preset settings, such as a photo's sidecar.
        case noSettings
        /// A camera profile or look, which needs color tables this app cannot read.
        case profile
    }

    /// The preset's name, without the format's localization prefix.
    public var name: String?
    /// The group (collection) an XMP preset names.
    public var group: String?
    public var values: [String: CameraRawValue]

    public init(name: String? = nil, group: String? = nil, values: [String: CameraRawValue]) {
        self.name = name
        self.group = group
        self.values = values
    }

    public static func read(contentsOf url: URL) throws -> CameraRawSettings {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        switch url.pathExtension.lowercased() {
        case templateExtension:
            return try CameraRawSettings(template: String(decoding: data, as: UTF8.self))
        case dngExtension:
            guard let packet = embeddedXMP(in: data) else { throw Failure.noSettings }
            return try CameraRawSettings(xmp: packet, isPhoto: true)
        default:
            return try CameraRawSettings(xmp: data)
        }
    }

    /// The `x:xmpmeta` element stored in a file's bytes (a DNG's XMP tag).
    static func embeddedXMP(in data: Data) -> Data? {
        guard let start = data.range(of: Data("<x:xmpmeta".utf8)),
              let end = data.range(of: Data("</x:xmpmeta>".utf8), in: start.upperBound..<data.endIndex) else {
            return nil
        }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }

    // MARK: Templates

    /// Reads `s = { title = …, type = "Develop", value = { settings = { … } } }`.
    public init(template text: String) throws {
        var parser = LuaTableParser(text)
        guard let root = try parser.parseDocument()?.record else { throw Failure.malformed(line: parser.line) }
        if let type = root["type"]?.string, type != "Develop" { throw Failure.notADevelopPreset }
        guard let settings = root["value"]?.record?["settings"]?.record else { throw Failure.noSettings }
        self.init(name: (root["title"]?.string).map(Self.unlocalized), values: settings)
    }

    /// "$$$/Some/Key=Name" becomes "Name".
    static func unlocalized(_ text: String) -> String {
        guard text.hasPrefix("$$$/"), let equals = text.firstIndex(of: "=") else { return text }
        return String(text[text.index(after: equals)...])
    }

    // MARK: XMP

    /// `isPhoto`: the XMP of a photo used as a preset, which has settings but
    /// none of a preset file's markers (its type or name).
    public init(xmp data: Data, isPhoto: Bool = false) throws {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [])
        } catch {
            throw Failure.malformed(line: 0)
        }
        var values: [String: CameraRawValue] = [:]
        for description in Self.descriptions(in: document.rootElement()) {
            values.merge(Self.record(from: description)) { _, new in new }
        }
        guard !values.isEmpty, isPhoto || values["PresetType"] != nil || values["Name"] != nil else {
            throw Failure.noSettings
        }
        if isPhoto, values["HasSettings"]?.bool == false { throw Failure.noSettings }
        if let type = values["PresetType"]?.string, type != "Normal" { throw Failure.profile }
        self.init(name: values["Name"]?.string.map(Self.unlocalized),
                  group: values["Group"]?.string.map(Self.unlocalized).flatMap { $0.isEmpty ? nil : $0 },
                  values: values)
    }

    /// The top-level `rdf:Description` elements under `rdf:RDF`.
    private static func descriptions(in root: XMLElement?) -> [XMLElement] {
        guard let root else { return [] }
        if root.localName == "RDF", root.uri == rdfNamespace {
            return root.elements(forLocalName: "Description", uri: rdfNamespace)
        }
        return (root.children ?? []).compactMap { $0 as? XMLElement }.flatMap { descriptions(in: $0) }
    }

    /// Camera Raw attributes and child elements of `element`, by local name.
    private static func record(from element: XMLElement) -> [String: CameraRawValue] {
        var values: [String: CameraRawValue] = [:]
        for attribute in element.attributes ?? [] where attribute.uri == namespace {
            if let name = attribute.localName { values[name] = .string(attribute.stringValue ?? "") }
        }
        for child in (element.children ?? []).compactMap({ $0 as? XMLElement }) where child.uri == namespace {
            if let name = child.localName { values[name] = value(of: child) }
        }
        return values
    }

    /// A property element: an RDF container, a nested resource, or text.
    private static func value(of element: XMLElement) -> CameraRawValue {
        let children = (element.children ?? []).compactMap { $0 as? XMLElement }
        if let container = children.first(where: { $0.uri == rdfNamespace && ["Seq", "Bag", "Alt"].contains($0.localName ?? "") }) {
            let items = container.elements(forLocalName: "li", uri: rdfNamespace).map(value(of:))
            return container.localName == "Alt" ? items.first ?? .string("") : .list(items)
        }
        if let description = children.first(where: { $0.uri == rdfNamespace && $0.localName == "Description" }) {
            return .record(record(from: description))
        }
        let nested = record(from: element)
        if !nested.isEmpty || element.attribute(forLocalName: "parseType", uri: rdfNamespace) != nil {
            return .record(nested)
        }
        return .string(element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}

/// Reads the table constructors of a Lua source file: `name = { … }` or
/// `return { … }`. Comments, both quote styles with escapes, long brackets,
/// named, bracketed and positional fields are understood; a call with one
/// argument (`ZSTR "…"`) reads as its argument.
struct LuaTableParser {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    private(set) var line = 1

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    private var current: Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }

    private func peek(_ offset: Int) -> Unicode.Scalar? {
        index + offset < scalars.count ? scalars[index + offset] : nil
    }

    private mutating func advance() {
        if current == "\n" { line += 1 }
        index += 1
    }

    private var failure: CameraRawSettings.Failure { .malformed(line: line) }

    mutating func parseDocument() throws -> CameraRawValue? {
        skipTrivia()
        if let word = peekWord(), word == "return" {
            _ = readWord()
        } else if peekWord() != nil {
            _ = readWord()
            skipTrivia()
            guard current == "=" else { throw failure }
            advance()
        }
        return try parseValue()
    }

    /// A value, or nil for `nil`.
    mutating func parseValue() throws -> CameraRawValue? {
        skipTrivia()
        guard let character = current else { throw failure }
        switch character {
        case "{":
            return try parseTable()
        case "\"", "'":
            return .string(try parseQuoted())
        case "[" where peek(1) == "[" || peek(1) == "=":
            return .string(try parseLongBracket())
        case "-", "+", ".", "0"..."9":
            return .number(try parseNumber())
        default:
            guard let word = readWord() else { throw failure }
            switch word {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "nil": return nil
            default:
                // A call: `f "text"`, `f { … }` or `f(value)`.
                skipTrivia()
                if current == "(" {
                    advance()
                    let value = try parseValue()
                    skipTrivia()
                    guard current == ")" else { throw failure }
                    advance()
                    return value
                }
                if current == "\"" || current == "'" || current == "{" { return try parseValue() }
                throw failure
            }
        }
    }

    /// A table: a record when any field is named, otherwise a list.
    private mutating func parseTable() throws -> CameraRawValue {
        advance()
        var named: [String: CameraRawValue] = [:]
        var positional: [CameraRawValue] = []
        while true {
            skipTrivia()
            guard let character = current else { throw failure }
            if character == "}" {
                advance()
                break
            }
            if character == "[" && peek(1) != "[" && peek(1) != "=" {
                advance()
                let key = try parseValue()
                skipTrivia()
                guard current == "]" else { throw failure }
                advance()
                try expectEquals()
                let value = try parseValue()
                if let key = key?.string, let value { named[key] = value }
            } else if let word = peekWord(), !["true", "false", "nil"].contains(word), followedByEquals(word) {
                _ = readWord()
                try expectEquals()
                if let value = try parseValue() { named[word] = value }
            } else if let value = try parseValue() {
                positional.append(value)
            }
            skipTrivia()
            if current == "," || current == ";" { advance() }
        }
        guard !named.isEmpty else { return .list(positional) }
        for (offset, value) in positional.enumerated() { named[String(offset + 1)] = value }
        return .record(named)
    }

    private mutating func expectEquals() throws {
        skipTrivia()
        guard current == "=", peek(1) != "=" else { throw failure }
        advance()
    }

    /// True when the word at the cursor is followed by `=` (not `==`).
    private func followedByEquals(_ word: String) -> Bool {
        var offset = word.unicodeScalars.count
        while let next = peek(offset), next == " " || next == "\t" || next == "\r" || next == "\n" { offset += 1 }
        return peek(offset) == "=" && peek(offset + 1) != "="
    }

    private func peekWord() -> String? {
        guard let first = current, Self.isWordStart(first) else { return nil }
        var word = String.UnicodeScalarView()
        var offset = 0
        while let next = peek(offset), Self.isWordPart(next) {
            word.append(next)
            offset += 1
        }
        return String(word)
    }

    private mutating func readWord() -> String? {
        guard let word = peekWord() else { return nil }
        for _ in word.unicodeScalars { advance() }
        return word
    }

    private static func isWordStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || (scalar.properties.isAlphabetic && scalar.isASCII)
    }

    private static func isWordPart(_ scalar: Unicode.Scalar) -> Bool {
        isWordStart(scalar) || ("0"..."9").contains(scalar)
    }

    private mutating func parseNumber() throws -> Double {
        var text = String.UnicodeScalarView()
        if current == "-" || current == "+" {
            text.append(current!)
            advance()
            skipTrivia()
        }
        let isHex = current == "0" && (peek(1) == "x" || peek(1) == "X")
        while let character = current {
            let isExponentSign = (character == "-" || character == "+")
                && !isHex && (text.last == "e" || text.last == "E")
            guard character.properties.isASCIIHexDigit || character == "." || character == "x" || character == "X"
                    || isExponentSign else { break }
            text.append(character)
            advance()
        }
        let string = String(text)
        if isHex || string.lowercased().contains("0x") {
            let negative = string.hasPrefix("-")
            let digits = string.drop { $0 == "-" || $0 == "+" }.dropFirst(2)
            guard let value = UInt64(digits, radix: 16) else { throw failure }
            return negative ? -Double(value) : Double(value)
        }
        guard let value = Double(string) else { throw failure }
        return value
    }

    private mutating func parseQuoted() throws -> String {
        let quote = current!
        advance()
        var text = String.UnicodeScalarView()
        while let character = current {
            if character == quote {
                advance()
                return String(text)
            }
            if character == "\n" { throw failure }
            if character == "\\" {
                advance()
                guard let escaped = current else { throw failure }
                switch escaped {
                case "n": text.append("\n")
                case "t": text.append("\t")
                case "r": text.append("\r")
                case "a", "b", "f", "v": break
                case "\n": text.append("\n")
                case "0"..."9":
                    var digits = ""
                    while digits.count < 3, let digit = current, ("0"..."9").contains(digit) {
                        digits.unicodeScalars.append(digit)
                        advance()
                    }
                    if let code = UInt32(digits), let scalar = Unicode.Scalar(code) { text.append(scalar) }
                    continue
                default: text.append(escaped)
                }
                advance()
                continue
            }
            text.append(character)
            advance()
        }
        throw failure
    }

    /// `[[ … ]]` or `[==[ … ]==]`.
    private mutating func parseLongBracket() throws -> String {
        advance()
        var level = 0
        while current == "=" {
            level += 1
            advance()
        }
        guard current == "[" else { throw failure }
        advance()
        if current == "\n" { advance() }
        var text = String.UnicodeScalarView()
        while let character = current {
            if character == "]" && closesLongBracket(level: level) {
                for _ in 0..<(level + 2) { advance() }
                return String(text)
            }
            text.append(character)
            advance()
        }
        throw failure
    }

    private func closesLongBracket(level: Int) -> Bool {
        for offset in 1...max(level, 1) where level > 0 && peek(offset) != "=" { return false }
        return peek(level + 1) == "]"
    }

    /// Spaces and comments (`-- …` to the end of the line, `--[[ … ]]`).
    private mutating func skipTrivia() {
        while let character = current {
            if character == " " || character == "\t" || character == "\r" || character == "\n" {
                advance()
            } else if character == "-" && peek(1) == "-" {
                advance()
                advance()
                if current == "[", peek(1) == "[" || peek(1) == "=" {
                    _ = try? parseLongBracket()
                } else {
                    while let next = current, next != "\n" { advance() }
                }
            } else {
                return
            }
        }
    }
}
