import Foundation
import Testing
@testable import PhotoCore

/// The About window's words (issue #179, R2, R3; AC3, AC4). The sentences
/// live in PhotoUI, which the tests don't link, so they are read from its
/// source the way `LocalizationTests` reads UI strings: one literal per
/// project, on the line of its case.
@Suite("About wording")
struct AboutWordingTests {
    static let textFile = "Sources/PhotoUI/About/AboutText.swift"

    /// The string literal of `case .<name>: String(localized: "…")`.
    static func literal(forCase name: String) throws -> String {
        let source = try String(contentsOf: RepositoryFiles.url(textFile), encoding: .utf8)
        let marker = "case .\(name): String(localized: \""
        let lines = source.components(separatedBy: "\n").filter { $0.contains(marker) }
        #expect(lines.count == 1, "expected one line for case .\(name) in \(textFile), found \(lines.count)")
        let line = try #require(lines.first)
        let start = try #require(line.range(of: marker)).upperBound
        let characters = Array(line)
        let segments = try #require(LocalizationTests.parseLiteral(characters, from: line.distance(from: line.startIndex, to: start)))
        guard segments.count == 1, case .text(let text) = segments[0] else {
            Issue.record("case .\(name) should be one plain literal")
            return ""
        }
        return text
    }

    static func sentence(_ project: Acknowledgement.Project) throws -> String {
        try literal(forCase: project.rawValue)
    }

    @Test("AC3: every project has the approved sentence, and it is in the String Catalog")
    func sentencesAreTheApprovedOnes() throws {
        // The PRD's R2 wording, approved by the owner (ruling 5); design §8.
        let approved: [Acknowledgement.Project: String] = [
            .libRaw: "Reads raw files macOS can't.",
            .darktable: "Showed how to apply the lens corrections Fujifilm stores in its raw files. This app's version was written after reading how darktable does it; no code was copied.",
            .lightCraft: "The formulas behind brush and color range masks, reimplemented in Swift.",
            .grdb: "The database toolkit under the catalog.",
            .exifTool: "Reads metadata when it is installed; not part of the app.",
        ]
        let catalog = try LocalizationTests.catalog()
        for entry in Acknowledgements.all {
            let sentence = try Self.sentence(entry.project)
            #expect(sentence == approved[entry.project], "\(entry.name)")
            #expect(catalog[sentence] != nil, "\(entry.name)'s sentence is not in the String Catalog")
        }
    }

    @Test("AC3: every license has its short name, and it is in the String Catalog")
    func licenseNamesAreTheApprovedOnes() throws {
        let approved: [Acknowledgement.License: String] = [
            .lgpl21: "LGPL 2.1", .gpl3OrLater: "GPL 3 or later", .mit: "MIT",
            .sameAsPerl: "Artistic License / GPL, as ExifTool states",
        ]
        let catalog = try LocalizationTests.catalog()
        for license in Acknowledgement.License.allCases {
            let name = try Self.literal(forCase: license.rawValue)
            #expect(name == approved[license], "\(license)")
            #expect(catalog[name] != nil, "\(license)'s name is not in the String Catalog")
        }
    }

    @Test("AC4: a project that was studied, reimplemented or is optional is never said to be built on or included")
    func wordingFollowsTheRelationship() throws {
        for entry in Acknowledgements.all where entry.relationship != .included {
            let sentence = try Self.sentence(entry.project).lowercased()
            for phrase in ["built on", "includes", "is included", "contains"] {
                #expect(!sentence.contains(phrase), "\(entry.name): “\(phrase)”")
            }
        }
        let darktable = try Self.sentence(.darktable)
        #expect(darktable.contains("written after reading how darktable does it"))
        #expect(darktable.contains("no code was copied"))
        let exifTool = try Self.sentence(.exifTool)
        #expect(exifTool.contains("when it is installed"))
        #expect(exifTool.contains("not part of the app"))
        #expect(try Self.sentence(.lightCraft).contains("reimplemented"))
    }

    @Test("AC2: the dedication, the statement and the titles take the name as an argument")
    func namesAreArguments() throws {
        let catalog = try LocalizationTests.catalog()
        for key in ["About %@", "%@ stands on other people's work. Thank you to:", "View %@ License", "%@ License",
                    "The license text is missing from this copy of %@.", "Version %@ (build %@)", "Copyright © %@ %@",
                    "View License", "Can't Show the License"] {
            #expect(catalog[key] != nil, "“\(key)” is not in the String Catalog")
        }
    }
}

/// How the About window is wired into the two apps (R1, R7, R8; AC1, AC8,
/// AC9), as far as the sources can say. The debug scripts' `about menus`,
/// `about open` and `about windows` check the running apps.
@Suite("About menu wiring")
struct AboutWiringTests {
    static func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
    }

    @Test("R8: the About item replaces the system's in the app menu and SwiftUI's in Help, and both open the one window")
    func commandsReplaceBothItems() throws {
        let source = try Self.source("Sources/PhotoUI/About/AboutView.swift")
        #expect(source.contains("CommandGroup(replacing: .appInfo)"))
        #expect(source.contains("CommandGroup(replacing: .help)"))
        let opens = source.components(separatedBy: "Button(AboutText.aboutTitle(appName)) { openWindow(id: AboutWindowID.about) }")
        #expect(opens.count - 1 == 2, "both items should open the About window by its id")
        // One window by construction: a Window scene, not a group of them.
        #expect(source.contains("Window(AboutText.aboutTitle(appName), id: AboutWindowID.about)"))
    }

    @Test("R1, R7: both apps add the commands and the scenes, under their own names, after their main window", arguments: [
        ("Sources/PhotoApp/PhotoApplication.swift", "AppBranding.displayName"),
        ("Sources/PhotoImporter/ImporterApplication.swift", "AppBranding.importerDisplayName"),
    ])
    func bothAppsUseIt(path: String, name: String) throws {
        let source = try Self.source(path)
        #expect(source.contains("AboutCommands(appName: \(name))"), "\(path)")
        let scenes = try #require(source.range(of: "AboutScenes(appName: \(name))"), "\(path)")
        let mainWindow = try #require(source.range(of: "Window("), "\(path)")
        #expect(mainWindow.lowerBound < scenes.lowerBound, "\(path): a Window scene that comes first is shown at launch")
        // The Help group is the About commands', not emptied a second time.
        #expect(!source.contains("CommandGroup(replacing: .help)"), "\(path)")
    }

    @Test("RI-A1: the dedication and the statement name the project in both apps")
    func projectNameIsTheLibraryApps() throws {
        let source = try Self.source("Sources/PhotoUI/About/AboutView.swift")
        #expect(source.contains("public init(appName: String, projectName: String = AppBranding.displayName)"))
        for path in ["Sources/PhotoApp/PhotoApplication.swift", "Sources/PhotoImporter/ImporterApplication.swift"] {
            #expect(!(try Self.source(path)).contains("projectName:"), "\(path)")
        }
    }

    @Test("R8: nothing opens the system's About panel")
    func systemPanelIsNotUsed() throws {
        // The debug command names the selector only to look for it in the menus.
        let allowed = "Sources/PhotoUI/About/AboutDebugCommands.swift"
        let users = try RepositoryFiles.files(under: "Sources")
            .filter { $0.hasSuffix(".swift") && $0 != allowed }
            .filter { try Self.source($0).contains("orderFrontStandardAboutPanel") }
        #expect(users.isEmpty, "\(users)")
    }
}
