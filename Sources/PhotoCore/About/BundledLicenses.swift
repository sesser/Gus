import Foundation

/// A license text the About window can show in a window of its own.
public enum LicenseDocument: Hashable, Codable, Sendable {
    /// This project's own license: the bundle's copy of `LICENSE`.
    case app
    /// A project's section of the bundle's copy of the notices file.
    case project(Acknowledgement.Project)
}

/// The notices file as its second-level sections, by byte range, so a
/// section is shown exactly as it is stored (AC7).
///
/// A section starts at a line that begins with "## " outside a fenced code
/// block and runs to the byte before the next such line, or to the end of
/// the file. Its name is the rest of the heading line.
public struct NoticesFile: Sendable {
    public struct Section: Equatable, Sendable {
        /// The heading without its "## ", trimmed ("LibRaw 0.22.3").
        public var heading: String
        public var range: Range<Int>
    }

    public let data: Data
    public let sections: [Section]

    public init(data: Data) {
        self.data = data
        let bytes = [UInt8](data)
        var starts: [(heading: String, offset: Int)] = []
        var inFence = false
        var lineStart = 0
        while lineStart < bytes.count {
            let lineEnd = bytes[lineStart...].firstIndex(of: 0x0A) ?? bytes.count
            let line = bytes[lineStart..<lineEnd]
            if line.starts(with: Self.fence) {
                inFence.toggle()
            } else if !inFence, line.starts(with: Self.headingPrefix) {
                let heading = String(decoding: line.dropFirst(Self.headingPrefix.count), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                starts.append((heading, lineStart))
            }
            lineStart = lineEnd + 1
        }
        sections = starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1].offset : bytes.count
            return Section(heading: start.heading, range: start.offset..<end)
        }
    }

    private static let headingPrefix = Array("## ".utf8)
    private static let fence = Array("```".utf8)

    /// Whether a heading is a project's: its name, alone or followed by more
    /// after a space ("LibRaw 0.22.3" is LibRaw's, "LibRawSomething" is not).
    public static func heading(_ heading: String, names name: String) -> Bool {
        heading == name || heading.hasPrefix(name + " ")
    }

    public func section(named name: String) -> Section? {
        sections.first { Self.heading($0.heading, names: name) }
    }

    /// The section's bytes as text, or nil when they are not UTF-8 (the text
    /// shown must be the bytes stored, so nothing is repaired).
    public func text(of section: Section) -> String? {
        String(data: data.subdata(in: section.range), encoding: .utf8)
    }
}

/// The license files inside an app bundle: `THIRD_PARTY_NOTICES.md` and this
/// project's `LICENSE`, in the bundle's resources (issue #172 puts them
/// there; this only reads them). Nothing is cached: every question reads the
/// files again, so a control is offered only for what is there now.
public struct BundledLicenses: Sendable {
    public static let noticesFileName = "THIRD_PARTY_NOTICES.md"
    public static let licenseFileName = "LICENSE"

    /// The folder the files are looked for in; nil when there is none.
    public var directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    /// The text to show for a document, or nil when its file is missing,
    /// unreadable, not UTF-8, empty, or (for a project) has no section of
    /// that project's.
    public func text(for document: LicenseDocument) -> String? {
        switch document {
        case .app:
            guard let data = read(Self.licenseFileName), let text = String(data: data, encoding: .utf8), !text.isEmpty
            else { return nil }
            return text
        case .project(let project):
            guard let entry = Acknowledgements.entry(for: project), let notices = notices() else { return nil }
            return Self.text(for: entry, in: notices)
        }
    }

    /// The documents a View License control is offered for: this project's
    /// license when its file is there, and each project whose license asks
    /// for a notice and whose section is found. Never the others, whatever
    /// the notices file holds. Each file is read once.
    public func available(among entries: [Acknowledgement] = Acknowledgements.all) -> Set<LicenseDocument> {
        var result: Set<LicenseDocument> = []
        if text(for: .app) != nil { result.insert(.app) }
        guard let notices = notices() else { return result }
        for entry in entries where entry.requiresNotice && Self.text(for: entry, in: notices) != nil {
            result.insert(.project(entry.project))
        }
        return result
    }

    /// A missing or unreadable file is the same as none: the window then
    /// offers nothing for it, and says nothing (design §5).
    private func read(_ name: String) -> Data? {
        guard let directory else { return nil }
        return try? Data(contentsOf: directory.appending(path: name))
    }

    private func notices() -> NoticesFile? {
        read(Self.noticesFileName).map(NoticesFile.init(data:))
    }

    private static func text(for entry: Acknowledgement, in notices: NoticesFile) -> String? {
        notices.section(named: entry.name).flatMap(notices.text(of:))
    }
}
