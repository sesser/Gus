import Foundation
import Testing
@testable import PhotoCore

/// When an Adjust heading's reset arrow is available (issue #221): exactly
/// when `Adjustments.isModified(section)` says the heading has something away
/// from its defaults, and the heading's button carries that to SwiftUI's
/// environment as well as to the `NSButton`.
@Suite("Heading reset")
struct HeadingResetTests {
    /// One value away from its default in every group of a heading.
    private static func edited(_ section: Adjustments.Section) -> Adjustments {
        var values = Adjustments()
        for group in section.groups {
            switch group {
            case .whiteBalance: values.whiteBalance = .raw(.tungsten)
            case .light: values.exposure.ev = 0.5
            case .presence: values.presence.vibrance = 10
            case .toneCurve: values.toneCurve[.rgb] = [CurvePoint(x: 0, y: 0.05), CurvePoint(x: 1, y: 1)]
            case .sharpening: values.sharpen.amount = 40
            case .noiseReduction: values.noiseReduction.luminance = 20
            case .colorMixer: values.colorMixer[.blue] = .init(hue: 10)
            case .blackAndWhite: values.blackAndWhite = BlackAndWhite(isOn: true, [.red: 40])
            case .colorGrade: values.colorGrade.balance = 10
            case .lookTable: values.lookTable = LookTable(identifier: String(repeating: "ab", count: 32), name: "Film")
            case .vignette: values.vignette.amount = -20
            case .grain: values.grain.strength = 30
            case .distortion: values.distortion.isOn = true
            case .lensVignetting: values.lensVignetting.isOn = true
            case .colorFringes: values.colorFringes.slot1 = CommonFringeColor.purple.slot
            case .colorAlignment: values.colorAlignment = ColorAlignment(red: 5)
            case .spots:
                values.spots.spots = [Spot(center: MaskPoint(x: 0.2, y: 0.2), size: 0.01, source: MaskPoint(x: 0.3, y: 0.2))]
            }
        }
        return values
    }

    @Test("No heading has anything to reset on an unedited photo")
    func uneditedPhoto() {
        let values = Adjustments(stack: .identity)
        for section in Adjustments.Section.allCases {
            #expect(!values.isModified(section), "\(section) offers a reset on an unedited photo")
        }
    }

    @Test("An edit under one heading offers only that heading's reset, and the reset dims it again")
    func editAndReset() {
        for section in Adjustments.Section.allCases {
            let values = Self.edited(section)
            for other in Adjustments.Section.allCases {
                #expect(values.isModified(other) == (other == section), "\(other) after an edit under \(section)")
            }
            let reset = values.resetting(section)
            for other in Adjustments.Section.allCases {
                #expect(!reset.isModified(other), "\(other) after resetting \(section)")
            }
            // Through the stored stack too, as the editor reads a saved photo.
            let reread = Adjustments(stack: reset.editStack)
            #expect(Adjustments.Section.allCases.allSatisfy { !reread.isModified($0) })
        }
    }

    @Test("The stored decode, a camera profile and unknown operations belong to no heading")
    func operationsOutsideTheHeadings() {
        let stack = EditStack(operations: [
            EditOperation(kind: RawDecode.kind, parameters: ["look": .string("neutral"), "decoderVersion": .string("8.dng")]),
            EditOperation(kind: CameraProfileReference.kind, parameters: ["name": .string("Camera Standard")]),
            EditOperation(kind: "brush", parameters: ["size": .number(3)]),
            EditOperation(kind: "exposure", kindVersion: 2, parameters: ["ev": .number(1)]),
        ])
        let values = Adjustments(stack: stack)
        #expect(values != .none)
        for section in Adjustments.Section.allCases {
            #expect(!values.isModified(section), "\(section) offers a reset for an operation it doesn't reset")
        }
    }

    @Test("A turned-off group's kept values can be reset, and the reset turns it back on")
    func turnedOffGroup() {
        for section in Adjustments.Section.allCases {
            var values = Self.edited(section)
            for group in section.groups { values.setEnabled(group, false) }
            #expect(section.groups.allSatisfy { !values.isEnabled($0) })
            #expect(values.isModified(section), "\(section) with its edits turned off")
            let reset = values.resetting(section)
            #expect(!reset.isModified(section))
            #expect(section.groups.allSatisfy { reset.isEnabled($0) })
            #expect(reset == .none)
        }
    }

    @Test("A stack from before machine learning had its own setting offers Details' reset")
    func legacyMachineLearningDecoder() {
        let stack = EditStack(operations: [
            EditOperation(kind: RawDecode.kind, parameters: ["decoderVersion": .string("9.dng")]),
        ])
        let values = Adjustments(stack: stack)
        #expect(values.noiseReduction.machineLearning)
        #expect(values.isModified(.details))
        #expect(!values.resetting(.details).isModified(.details))
    }

    /// PhotoApp has no test target, so this reads its sources. SwiftUI writes
    /// its environment's enabled state onto a hosted `NSButton` after
    /// `updateNSView` (`adoptEnvironment`), so an `AppKitButton`'s
    /// `isEnabled: false` alone left every heading's reset enabled. Each
    /// heading's reset must also carry, in its own modifier chain,
    /// `.disabled(!x)` where `x` is its `isEnabled:` argument.
    @Test("Every heading's reset is dimmed through SwiftUI's environment too")
    func headingResetsCarryDisabled() throws {
        let symbol = #"symbol:"arrow.counterclockwise""#
        var found: [String] = []
        for path in RepositoryFiles.files(under: "Sources/PhotoApp/Views") where path.hasSuffix(".swift") {
            let source = try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
            for button in SwiftCallScanner.calls(of: "AppKitButton", in: source)
            where SwiftCallScanner.squeezed(button.arguments).contains(symbol) {
                let place = "\(path):\(button.line)"
                found.append(place)
                let isEnabled = try #require(SwiftCallScanner.argument("isEnabled", in: button.arguments),
                                             "the reset at \(place) has no isEnabled: argument")
                let disabled = button.modifiers.filter { $0.name == "disabled" }.map { SwiftCallScanner.squeezed($0.arguments) }
                let expected = SwiftCallScanner.squeezed(isEnabled)
                #expect(disabled.contains { $0 == "!" + expected || $0 == "!(" + expected + ")" },
                        "the reset at \(place) has isEnabled: \(isEnabled) but its modifiers carry \(disabled), not .disabled(!\(isEnabled))")
            }
        }
        // Crop, Spots, the seven `AdjustSection` headings (one view) and Black & White.
        #expect(found.count == 4, "found \(found)")
    }

    @Test("The source scanner ties .disabled to the button's own modifier chain")
    func scannerReadsTheModifierChain() {
        let source = """
            HStack {
                AppKitButton(symbol: "x", help: String(localized: "Reset \\(title)"), isEnabled: canReset) {
                    editor.reset(section) // a call (with parentheses) in the action
                }
                // A comment, "with a quote", between the button and its modifiers.
                /* and a block comment */
                .padding(.leading, 4)
                .disabled( !canReset )
                Other().disabled(!canReset)
            }
            AppKitButton(symbol: "y", isEnabled: other)
            Text("x").disabled(!other)
            """
        let calls = SwiftCallScanner.calls(of: "AppKitButton", in: source)
        #expect(calls.count == 2)
        #expect(calls.map(\.line) == [2, 11])
        #expect(SwiftCallScanner.argument("isEnabled", in: calls[0].arguments) == "canReset")
        #expect(calls[0].modifiers.map(\.name) == ["padding", "disabled"])
        #expect(SwiftCallScanner.squeezed(calls[0].modifiers[1].arguments) == "!canReset")
        // The next statement's modifier is not the button's.
        #expect(calls[1].modifiers.isEmpty)
    }
}

/// Just enough of a Swift reader for the source checks: calls of one name,
/// their argument list, an optional trailing closure, and the modifier chain
/// that follows, skipping comments and string literals.
enum SwiftCallScanner {
    struct Modifier {
        let name: String
        let arguments: String
    }

    struct Call {
        /// The 1-based line of the call's name.
        let line: Int
        let arguments: String
        let modifiers: [Modifier]
    }

    static func calls(of name: String, in source: String) -> [Call] {
        let text = Array(source)
        let pattern = Array(name + "(")
        var result: [Call] = []
        var index = 0
        while index < text.count {
            if let end = skipCommentOrString(text, index) {
                index = end
                continue
            }
            let isStart = index == 0 || !(text[index - 1].isLetter || text[index - 1].isNumber || text[index - 1] == "_")
            if isStart, text[index...].starts(with: pattern) {
                let open = index + pattern.count - 1
                guard let close = matching(text, open) else { break }
                var position = skipTrivia(text, close + 1)
                if position < text.count, text[position] == "{", let brace = matching(text, position) {
                    position = brace + 1
                }
                var modifiers: [Modifier] = []
                while true {
                    let dot = skipTrivia(text, position)
                    guard dot < text.count, text[dot] == "." else { break }
                    var nameEnd = dot + 1
                    while nameEnd < text.count, text[nameEnd].isLetter || text[nameEnd].isNumber || text[nameEnd] == "_" {
                        nameEnd += 1
                    }
                    guard nameEnd < text.count, text[nameEnd] == "(", let modifierClose = matching(text, nameEnd) else { break }
                    modifiers.append(Modifier(name: String(text[(dot + 1)..<nameEnd]),
                                              arguments: String(text[(nameEnd + 1)..<modifierClose])))
                    position = modifierClose + 1
                }
                let line = text[..<index].filter { $0 == "\n" }.count + 1
                result.append(Call(line: line, arguments: String(text[(open + 1)..<close]), modifiers: modifiers))
                index = open + 1
                continue
            }
            index += 1
        }
        return result
    }

    /// The value of a labelled argument at the top level of an argument list.
    static func argument(_ label: String, in arguments: String) -> String? {
        let text = Array(arguments)
        var parts: [String] = []
        var start = 0
        var depth = 0
        var index = 0
        while index < text.count {
            if let end = skipCommentOrString(text, index) {
                index = end
                continue
            }
            switch text[index] {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth -= 1
            case "," where depth == 0:
                parts.append(String(text[start..<index]))
                start = index + 1
            default: break
            }
            index += 1
        }
        parts.append(String(text[start...]))
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(label + ":") {
                return String(trimmed.dropFirst(label.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// The text with every white space removed, for comparing expressions.
    static func squeezed(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace })
    }

    /// The index after the bracket that closes the one at `open`.
    private static func matching(_ text: [Character], _ open: Int) -> Int? {
        var depth = 0
        var index = open
        while index < text.count {
            if let end = skipCommentOrString(text, index) {
                index = end
                continue
            }
            switch text[index] {
            case "(", "[", "{": depth += 1
            case ")", "]", "}":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            index += 1
        }
        return nil
    }

    /// White space and comments skipped from `index`.
    private static func skipTrivia(_ text: [Character], _ start: Int) -> Int {
        var index = start
        while index < text.count {
            if text[index].isWhitespace {
                index += 1
            } else if text[index] == "/", let end = skipCommentOrString(text, index) {
                index = end
            } else {
                break
            }
        }
        return index
    }

    /// When a comment or a string literal starts at `index`, the index after it.
    /// Interpolations are skipped with the string (enough for these sources).
    private static func skipCommentOrString(_ text: [Character], _ index: Int) -> Int? {
        let next = index + 1 < text.count ? text[index + 1] : nil
        if text[index] == "/", next == "/" {
            var end = index
            while end < text.count, text[end] != "\n" { end += 1 }
            return end
        }
        if text[index] == "/", next == "*" {
            var end = index + 2
            while end + 1 < text.count, !(text[end] == "*" && text[end + 1] == "/") { end += 1 }
            return min(end + 2, text.count)
        }
        let tripleQuote: [Character] = ["\"", "\"", "\""]
        if text[index...].starts(with: tripleQuote) {
            var end = index + 3
            while end < text.count, !text[end...].starts(with: tripleQuote) {
                end += text[end] == "\\" ? 2 : 1
            }
            return min(end + 3, text.count)
        }
        if text[index] == "\"" {
            var end = index + 1
            while end < text.count, text[end] != "\"" {
                end += text[end] == "\\" ? 2 : 1
            }
            return min(end + 1, text.count)
        }
        return nil
    }
}
