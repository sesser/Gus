import Foundation
import Testing
@testable import PhotoCore

@Suite("Template parts")
struct TemplatePartsTests {
    static let templates = [
        "", "plain", "{capture:yyyy}/{capture:yyyy-MM-dd}", "{name}", "IMG_{seq:4}-{job}.{ext:lower}",
        "{unknown} and {capture:dd}", "open { brace", "{a{b}c}", "}{", "{}", "Café_{model} 📷 {lens}",
    ]

    @Test(arguments: templates)
    func joinGivesBackTheTemplate(_ template: String) {
        #expect(TemplateParts.join(TemplateParts.parse(template)) == template)
    }

    @Test func splitsTextAndTokens() {
        #expect(TemplateParts.parse("IMG_{seq:4}-{job}") == [.text("IMG_"), .token("{seq:4}"), .text("-"), .token("{job}")])
        #expect(TemplateParts.parse("{capture:yyyy}/{capture:yyyy-MM-dd}")
                    == [.token("{capture:yyyy}"), .text("/"), .token("{capture:yyyy-MM-dd}")])
        #expect(TemplateParts.parse("") == [])
    }

    @Test func splitsLikeExpansion() {
        // Unknown tokens are kept whole, a `{` without `}` is text, and a token
        // runs to the first `}`, as `ImportTemplate.expand` reads them.
        #expect(TemplateParts.parse("{unknown}x") == [.token("{unknown}"), .text("x")])
        #expect(TemplateParts.parse("a { b") == [.text("a { b")])
        #expect(TemplateParts.parse("{a{b}c}") == [.token("{a{b}"), .text("c}")])
        let context = TemplateContext(captureDate: nil, captureOffsetSeconds: nil, fileDate: Date(timeIntervalSince1970: 0),
                                      importDate: Date(timeIntervalSince1970: 0), make: "Make", model: "Model",
                                      serial: nil, lens: nil, originalName: "IMG_0412.NEF", sequence: 3, counter: 41,
                                      jobCode: "Job")
        for template in Self.templates {
            let partwise = TemplateParts.parse(template).map { ImportTemplate.expand($0.syntax, context) }.joined()
            #expect(partwise == ImportTemplate.expand(template, context), "\(template)")
        }
    }

    @Test func normalizingMergesTextAndFindsTypedTokens() {
        let typed: [TemplatePart] = [.text("a"), .text(""), .text("_{job"), .text("}_"), .token("{name}")]
        #expect(TemplateParts.normalized(typed) == [.text("a_"), .token("{job}"), .text("_"), .token("{name}")])
    }

    @Test func insertsAtTheCaret() {
        let parts = TemplateParts.parse("IMG_{seq:4}")
        // Inside the text: "IM" | "G_".
        let inside = TemplateParts.inserting("{job}", into: parts, at: 2)
        #expect(TemplateParts.join(inside.parts) == "IM{job}G_{seq:4}")
        #expect(inside.caret == 3)
        // After the token (offset 4 + 1).
        let end = TemplateParts.inserting("{job}", into: parts, at: 5)
        #expect(TemplateParts.join(end.parts) == "IMG_{seq:4}{job}")
        #expect(end.caret == 6)
        // Past the end appends; at 0 goes first.
        #expect(TemplateParts.join(TemplateParts.inserting("{job}", into: parts, at: 99).parts) == "IMG_{seq:4}{job}")
        #expect(TemplateParts.join(TemplateParts.inserting("{job}", into: parts, at: 0).parts) == "{job}IMG_{seq:4}")
        #expect(TemplateParts.inserting("{job}", into: [], at: 0) == ([.token("{job}")], 1))
    }

    @Test func insertsAsNewFolder() {
        let parts = TemplateParts.parse("{capture:yyyy}")
        let appended = TemplateParts.inserting("{job}", into: parts, at: 1, separator: "/")
        #expect(TemplateParts.join(appended.parts) == "{capture:yyyy}/{job}")
        #expect(appended.caret == 3)
        // Not at the start, nor after a separator already there.
        #expect(TemplateParts.join(TemplateParts.inserting("{job}", into: parts, at: 0, separator: "/").parts)
                    == "{job}{capture:yyyy}")
        #expect(TemplateParts.join(TemplateParts.inserting("{job}", into: TemplateParts.parse("a/"), at: 2,
                                                           separator: "/").parts) == "a/{job}")
    }

    @Test func unknownTokensCanBeText() {
        let known: (String) -> Bool = { TemplateToken(syntax: $0) != nil }
        #expect(TemplateParts.parse("a{x}b{job}{y}", isToken: known) == [.text("a{x}b"), .token("{job}"), .text("{y}")])
        // In the editor an unknown token is its characters, so the caret counts them.
        let parts = TemplateParts.parse("{x}_", isToken: known)
        let result = TemplateParts.inserting("{job}", into: parts, at: 4, isToken: known)
        #expect(result.parts == [.text("{x}_"), .token("{job}")])
        #expect(result.caret == 5)
    }

    @Test func caretCountsUTF16() {
        let parts = TemplateParts.parse("📷{job}")
        #expect(parts.map(\.editorLength) == [2, 1])
        #expect(TemplateParts.join(TemplateParts.inserting("{name}", into: parts, at: 2).parts) == "📷{name}{job}")
    }
}

@Suite("Template tokens")
struct TemplateTokenTests {
    @Test func readsTheGrammar() {
        #expect(TemplateToken(syntax: "{capture:yyyy}") == .date(.capture, pattern: "yyyy"))
        #expect(TemplateToken(syntax: "{import:yyyy-MM-dd}") == .date(.import, pattern: "yyyy-MM-dd"))
        #expect(TemplateToken(syntax: "{export:yyyyMM}") == .date(.export, pattern: "yyyyMM"))
        #expect(TemplateToken(syntax: "{name}") == .name)
        #expect(TemplateToken(syntax: "{number}") == .number)
        #expect(TemplateToken(syntax: "{ext}") == .ext(nil))
        #expect(TemplateToken(syntax: "{ext:lower}") == .ext(.lower))
        #expect(TemplateToken(syntax: "{ext:upper}") == .ext(.upper))
        #expect(TemplateToken(syntax: "{seq:4}") == .sequence)
        #expect(TemplateToken(syntax: "{seq}") == .sequence)
        #expect(TemplateToken(syntax: "{counter:5}") == .counter)
        #expect(TemplateToken(syntax: "{job}") == .job)
        #expect(TemplateToken(syntax: "{serial}") == .serial)
    }

    @Test func unknownTokensAreText() {
        // What `ImportTemplate.expand` leaves as written.
        for syntax in ["{}", "{capture}", "{import}", "{export}", "{unknown}", "{Name}", "plain", "{a{b}"] {
            #expect(TemplateToken(syntax: syntax) == nil, "\(syntax)")
        }
    }

    @Test func valuesComeFromTheContext() {
        let context = TemplateContext(captureDate: Date(timeIntervalSince1970: 1_780_000_000), captureOffsetSeconds: 0,
                                      fileDate: Date(timeIntervalSince1970: 0), importDate: Date(timeIntervalSince1970: 0),
                                      make: "Make", model: "Model", serial: nil, lens: nil, originalName: "DSC00328.ARW",
                                      sequence: 3, counter: 41, jobCode: "Job")
        #expect(TemplateToken.value(of: "{capture:yyyy}", in: context) == "2026")
        #expect(TemplateToken.value(of: "{number}", in: context) == "00328")
        #expect(TemplateToken.value(of: "{seq:4}", in: context) == "0003")
        #expect(TemplateToken.value(of: "{lens}", in: context) == "")
    }
}
