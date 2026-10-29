import SwiftUI

/// A template text field with a menu of tokens to insert (see `ImportTemplate`).
public struct TemplateField: View {
    /// A menu item: what it is called and what it inserts.
    public struct Token: Sendable {
        public var name: String
        public var text: String

        public init(_ name: String, _ text: String) {
            self.name = name
            self.text = text
        }
    }

    let title: String
    @Binding var text: String
    let tokens: [Token]
    /// Tokens start a new path component.
    let folders: Bool

    public init(title: String, text: Binding<String>, tokens: [Token], folders: Bool = false) {
        self.title = title
        _text = text
        self.tokens = tokens
        self.folders = folders
    }

    /// Tokens every template can use.
    private static var shotTokens: [Token] {
        [
            Token(String(localized: "Capture year"), "{capture:yyyy}"),
            Token(String(localized: "Capture date"), "{capture:yyyy-MM-dd}"),
            Token(String(localized: "Capture month name"), "{capture:MMMM}"),
            Token(String(localized: "Capture time"), "{capture:HHmmss}"),
        ]
    }

    private static var cameraTokens: [Token] {
        [
            Token(String(localized: "Camera model"), "{model}"),
            Token(String(localized: "Camera make"), "{make}"),
            Token(String(localized: "Camera serial number"), "{serial}"),
            Token(String(localized: "Lens"), "{lens}"),
        ]
    }

    public static var importFolderTokens: [Token] {
        shotTokens + [
            Token(String(localized: "Import date"), "{import:yyyy-MM-dd}"),
            Token(String(localized: "Job code"), "{job}"),
        ] + cameraTokens
    }

    public static var importFileTokens: [Token] {
        importFolderTokens + [
            Token(String(localized: "Original name"), "{name}"),
            Token(String(localized: "Number in the original name"), "{number}"),
            Token(String(localized: "Sequence in this import"), "{seq:4}"),
            Token(String(localized: "Counter across imports"), "{counter:5}"),
        ]
    }

    public static var exportFileTokens: [Token] {
        shotTokens + [Token(String(localized: "Export date"), "{export:yyyy-MM-dd}")] + cameraTokens + [
            Token(String(localized: "Original name"), "{name}"),
            Token(String(localized: "Number in the original name"), "{number}"),
            Token(String(localized: "Sequence in this export"), "{seq:4}"),
        ]
    }

    public var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, text: $text)
                    .labelsHidden()
                    .font(.body.monospaced())
                Menu {
                    ForEach(tokens, id: \.text) { token in
                        Button("\(token.name)  \(token.text)") {
                            text += (folders && !text.isEmpty && !text.hasSuffix("/") ? "/" : "") + token.text
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Insert a token")
            }
        }
    }
}
