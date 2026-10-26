import Foundation
import Testing

/// Keeps the String Catalog in step with the UI code. The Command Line Tools
/// cannot extract strings the way Xcode does, so this test does the checking:
/// every literal passed to a localizing API in the app targets (the library
/// app, the shared UI and the standalone importer) must have a catalog entry
/// with an English value.
@Suite("Localization")
struct LocalizationTests {
    /// Calls whose string-literal argument is a `LocalizedStringKey` or `String.LocalizationValue`.
    static let localizingCalls = [
        "Text(\"", "String(localized: \"", "Button(\"", "Label(\"", "Section(\"", "Picker(\"",
        "Toggle(\"", "Menu(\"", "CommandMenu(\"", ".help(\"", "TextField(\"", ".alert(\"",
        ".confirmationDialog(\"",
    ]

    enum Segment: Equatable {
        case text(String)
        case interpolation
    }

    struct Literal: CustomStringConvertible {
        var file: String
        var line: Int
        var segments: [Segment]

        var description: String {
            "\(file):\(line): \"" + segments.map { if case .text(let t) = $0 { t } else { "%…" } }.joined() + "\""
        }

        /// Matches catalog keys, where each interpolation became a format specifier.
        var pattern: String {
            "^" + segments.map { segment in
                switch segment {
                case .text(let text): NSRegularExpression.escapedPattern(for: text)
                case .interpolation: #"%(?:\d+\$)?(?:lld|ld|llu|lu|d|u|@|lf|f)"#
                }
            }.joined() + "$"
        }
    }

    /// Reads a Swift string literal starting just after its opening quote.
    static func parseLiteral(_ characters: [Character], from start: Int) -> [Segment]? {
        var segments: [Segment] = []
        var text = ""
        var index = start
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if !text.isEmpty { segments.append(.text(text)) }
                return segments
            }
            if character == "\n" { return nil }
            if character == "\\", index + 1 < characters.count {
                let next = characters[index + 1]
                if next == "(" {
                    if !text.isEmpty { segments.append(.text(text)) }
                    text = ""
                    segments.append(.interpolation)
                    // Skip to the matching parenthesis, stepping over nested strings.
                    var depth = 1
                    var inString = false
                    index += 2
                    while index < characters.count, depth > 0 {
                        let c = characters[index]
                        if c == "\"" { inString.toggle() }
                        if !inString {
                            if c == "(" { depth += 1 }
                            if c == ")" { depth -= 1 }
                        }
                        index += 1
                    }
                    continue
                }
                let escapes: [Character: Character] = ["n": "\n", "t": "\t", "\"": "\"", "\\": "\\"]
                text.append(escapes[next] ?? next)
                index += 2
                continue
            }
            text.append(character)
            index += 1
        }
        return nil
    }

    static func literals(in source: String, file: String) -> [Literal] {
        var result: [Literal] = []
        for (lineIndex, line) in source.components(separatedBy: "\n").enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let characters = Array(line)
            let text = String(characters)
            for call in localizingCalls {
                var searchRange = text.startIndex..<text.endIndex
                while let range = text.range(of: call, range: searchRange) {
                    let start = text.distance(from: text.startIndex, to: range.upperBound)
                    if let segments = parseLiteral(characters, from: start), !segments.isEmpty {
                        result.append(Literal(file: file, line: lineIndex + 1, segments: segments))
                    }
                    searchRange = range.upperBound..<text.endIndex
                }
            }
        }
        return result
    }

    static func catalog() throws -> [String: Any] {
        let data = try Data(contentsOf: RepositoryFiles.url("Sources/PhotoUI/Resources/Localizable.xcstrings"))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["strings"] as? [String: Any])
    }

    @Test func parsesLiteralsWithInterpolations() {
        let source = #"Text("Imported \(count) of \(names.joined(separator: ", ")) items") // Text("skip")"#
        let found = Self.literals(in: source, file: "x")
        #expect(found.first?.segments == [.text("Imported "), .interpolation, .text(" of "), .interpolation, .text(" items")])
        #expect(found.first.map { "Imported %lld of %@ items".range(of: $0.pattern, options: .regularExpression) != nil } == true)
    }

    @Test func everyUIStringHasACatalogEntry() throws {
        let keys = Array(try Self.catalog().keys)
        var missing: [Literal] = []
        var count = 0
        let paths = ["Sources/PhotoApp", "Sources/PhotoUI", "Sources/PhotoImporter"].flatMap(RepositoryFiles.files(under:))
        for path in paths where path.hasSuffix(".swift") {
            let source = try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
            for literal in Self.literals(in: source, file: path) {
                count += 1
                let regex = try NSRegularExpression(pattern: literal.pattern)
                let found = keys.contains { key in
                    regex.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
                }
                if !found { missing.append(literal) }
            }
        }
        #expect(count > 40, "expected to find the UI strings, found \(count)")
        #expect(missing.isEmpty, "missing from Localizable.xcstrings:\n\(missing.map(\.description).joined(separator: "\n"))")
    }

    @Test func everyCatalogEntryHasAnEnglishValueWithMatchingArguments() throws {
        let specifier = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|llu|lu|d|u|@|lf|f)"#)
        func arguments(_ text: String) -> Int {
            specifier.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        }
        for (key, value) in try Self.catalog() {
            let english = ((value as? [String: Any])?["localizations"] as? [String: Any])?["en"] as? [String: Any]
            let entry = try #require(english, "no English value for \"\(key)\"")
            var texts: [String] = []
            if let unit = entry["stringUnit"] as? [String: Any], let text = unit["value"] as? String {
                texts.append(text)
            }
            if let plural = (entry["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                texts += plural.values.compactMap { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
                #expect(plural["other"] != nil, "plural \"\(key)\" needs an \"other\" form")
            }
            #expect(!texts.isEmpty, "no English text for \"\(key)\"")
            for text in texts {
                #expect(arguments(text) == arguments(key), "\"\(text)\" has different arguments than its key \"\(key)\"")
            }
        }
    }
}
