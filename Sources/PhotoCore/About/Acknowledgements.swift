import Foundation

/// One project the About window thanks (issue #179, R2, R3, R9).
///
/// `Acknowledgements.all` is the only record of them. The About window is
/// built from it, and `AcknowledgementConsistencyTests` fails when it and
/// `THIRD_PARTY_NOTICES.md`, the README's Credits, `Package.swift` or the
/// vendored source under `Sources/` stop agreeing. The words shown for each
/// project (what it gave, its license's short name) are the UI's, one per
/// case of `Project` and `License`.
public struct Acknowledgement: Equatable, Sendable, Identifiable {
    public enum Project: String, CaseIterable, Codable, Sendable {
        case libRaw, darktable, lightCraft, grdb, exifTool
    }

    /// What the project is to this one. The description's wording follows
    /// it (R3): code that is in the apps is not described like an approach
    /// that was studied, formulas that were written again, or a program the
    /// apps only run when it is installed.
    public enum Relationship: Equatable, Sendable {
        /// Its code is compiled into the apps.
        case included
        /// Its approach was read; none of its code is in the apps.
        case studied
        /// Its formulas were written again in this project's code.
        case reimplemented
        /// A separate program the apps run when it is installed.
        case optionalTool
    }

    /// The project's own license, by its short name in the window.
    public enum License: String, CaseIterable, Sendable {
        case lgpl21, gpl3OrLater, mit
        /// "The same terms as Perl itself": the Artistic License or the GPL.
        case sameAsPerl
    }

    public var project: Project
    /// A proper name: shown as it is, never translated, and matched against
    /// the notices file's headings and the README's Credits.
    public var name: String
    /// The project's own page, opened in the browser from the window.
    public var page: URL
    public var relationship: Relationship
    public var license: License
    /// Whether its license asks for a notice to travel with the apps. Only
    /// these offer View License, which shows the project's section of the
    /// bundled notices file.
    public var requiresNotice: Bool
    /// The `url:` of its `.package` in `Package.swift`, when it is one.
    public var packageURL: String?
    /// Where its source is vendored in this repository, when it is.
    public var vendoredPath: String?

    public var id: Project { project }

    /// The page as the window shows it: no scheme, no "www.", no trailing
    /// slash ("libraw.org", "github.com/groue/GRDB.swift").
    public var displayAddress: String {
        var text = page.absoluteString
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        if text.hasPrefix("www.") { text = String(text.dropFirst(4)) }
        while text.hasSuffix("/") { text = String(text.dropLast()) }
        return text
    }
}

public enum Acknowledgements {
    /// In the order the window lists them.
    public static let all: [Acknowledgement] = [
        Acknowledgement(project: .libRaw, name: "LibRaw", page: URL(string: "https://www.libraw.org")!,
                        relationship: .included, license: .lgpl21, requiresNotice: true,
                        vendoredPath: "Sources/CLibRaw"),
        Acknowledgement(project: .darktable, name: "darktable", page: URL(string: "https://www.darktable.org")!,
                        relationship: .studied, license: .gpl3OrLater, requiresNotice: false),
        Acknowledgement(project: .lightCraft, name: "LightCraft",
                        page: URL(string: "https://github.com/storytold/lightcraft")!,
                        relationship: .reimplemented, license: .mit, requiresNotice: true),
        Acknowledgement(project: .grdb, name: "GRDB", page: URL(string: "https://github.com/groue/GRDB.swift")!,
                        relationship: .included, license: .mit, requiresNotice: true,
                        packageURL: "https://github.com/groue/GRDB.swift.git"),
        Acknowledgement(project: .exifTool, name: "ExifTool", page: URL(string: "https://exiftool.org")!,
                        relationship: .optionalTool, license: .sameAsPerl, requiresNotice: false),
    ]

    public static func entry(for project: Acknowledgement.Project) -> Acknowledgement? {
        all.first { $0.project == project }
    }
}

/// Who holds the copyright in this project, and from when: the About
/// window's copyright line. The README's License section says the same, and
/// a test fails when the two differ.
public enum AppCopyright {
    public static let year = "2026"
    public static let holder = "Randy Sesser"
}
