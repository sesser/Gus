import Foundation
import Testing
@testable import PhotoCore

/// The About window's rules (issue #179): the record of acknowledged
/// projects, the version line, the notices file's sections and which
/// license texts a bundle can show.
@Suite("About window")
struct AboutTests {
    // MARK: The record (R2, R3, R6; AC3)

    @Test("AC3: the record lists exactly the five projects, in the window's order")
    func recordListsTheFiveProjects() {
        #expect(Acknowledgements.all.map(\.name) == ["LibRaw", "darktable", "LightCraft", "GRDB", "ExifTool"])
        #expect(Acknowledgements.all.map(\.project) == Acknowledgement.Project.allCases)
        #expect(Set(Acknowledgements.all.map(\.project)).count == Acknowledgements.all.count)
    }

    @Test("R3: each project's relationship and license are what the notices say")
    func relationshipsAndLicenses() throws {
        func entry(_ project: Acknowledgement.Project) throws -> Acknowledgement {
            try #require(Acknowledgements.entry(for: project))
        }
        #expect(try entry(.libRaw).relationship == .included)
        #expect(try entry(.grdb).relationship == .included)
        #expect(try entry(.darktable).relationship == .studied)
        #expect(try entry(.lightCraft).relationship == .reimplemented)
        #expect(try entry(.exifTool).relationship == .optionalTool)
        #expect(try entry(.libRaw).license == .lgpl21)
        #expect(try entry(.darktable).license == .gpl3OrLater)
        #expect(try entry(.lightCraft).license == .mit)
        #expect(try entry(.grdb).license == .mit)
        #expect(try entry(.exifTool).license == .sameAsPerl)
    }

    @Test("R6: only LibRaw, LightCraft and GRDB carry a notice")
    func noticeIsRequiredForThree() {
        let required = Acknowledgements.all.filter(\.requiresNotice).map(\.project)
        #expect(required == [.libRaw, .lightCraft, .grdb])
    }

    @Test("R5: each page is an https address, shown without scheme, www or trailing slash")
    func pagesAndTheirDisplayAddresses() {
        for entry in Acknowledgements.all {
            #expect(entry.page.scheme == "https", "\(entry.name)")
            #expect(entry.page.host() != nil, "\(entry.name)")
        }
        #expect(Acknowledgements.all.map(\.displayAddress) == [
            "libraw.org", "darktable.org", "github.com/storytold/lightcraft", "github.com/groue/GRDB.swift",
            "exiftool.org",
        ])
        var entry = Acknowledgements.all[0]
        entry.page = URL(string: "https://www.example.org/a/b/")!
        #expect(entry.displayAddress == "example.org/a/b")
    }

    // MARK: Version line (R4; AC5)

    @Test("R4: the version line needs both values")
    func versionNeedsBothValues() {
        let version = AppVersion(infoDictionary: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"])
        #expect(version?.short == "0.1.0")
        #expect(version?.build == "1")
    }

    @Test("R4: no bundle, or a value missing, empty or not text, leaves the line out", arguments: [
        nil,
        [:],
        ["CFBundleShortVersionString": "0.1.0"],
        ["CFBundleVersion": "1"],
        ["CFBundleShortVersionString": "", "CFBundleVersion": "1"],
        ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "  "],
        ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "\n"],
    ] as [[String: String]?])
    func versionIsLeftOut(info: [String: String]?) {
        #expect(AppVersion(infoDictionary: info) == nil)
    }

    @Test("R4: a value that is not text counts as missing")
    func versionIgnoresValuesThatAreNotText() {
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": 1, "CFBundleVersion": "1"]) == nil)
    }

    @Test("AC5: the plist templates and Version.xcconfig give the bundle both values")
    func bundleTemplatesCarryTheVersion() throws {
        let versions = try RepositoryFiles.xcconfig("Support/Version.xcconfig")
        let info = ["CFBundleShortVersionString": versions["MARKETING_VERSION"] ?? "",
                    "CFBundleVersion": versions["CURRENT_PROJECT_VERSION"] ?? ""]
        #expect(AppVersion(infoDictionary: info) != nil)
        for template in ["Support/Info.plist", "Support/Importer-Info.plist"] {
            let text = try String(contentsOf: RepositoryFiles.url(template), encoding: .utf8)
            let data = try #require(text.data(using: .utf8))
            let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            #expect(plist["CFBundleShortVersionString"] as? String == "$(MARKETING_VERSION)", "\(template)")
            #expect(plist["CFBundleVersion"] as? String == "$(CURRENT_PROJECT_VERSION)", "\(template)")
        }
    }

    // MARK: Notices sections (R6; AC7)

    static let sampleNotices = """
        # Third-party notices

        ## LightCraft

        Mask math.

        ```
        MIT License
        ## not a heading: inside a fence
        ```

        ## LibRaw 0.22.3

        Vendored.

        ## LibRawExtras

        Another project whose name only starts the same.

        """

    @Test("A section runs from its heading to the byte before the next one")
    func sectionsAreByteRanges() throws {
        let data = Data(Self.sampleNotices.utf8)
        let notices = NoticesFile(data: data)
        #expect(notices.sections.map(\.heading) == ["LightCraft", "LibRaw 0.22.3", "LibRawExtras"])
        // The sections tile the file from the first heading to its end.
        let first = try #require(notices.sections.first)
        #expect(String(decoding: data[..<first.range.lowerBound], as: UTF8.self) == "# Third-party notices\n\n")
        for (section, next) in zip(notices.sections, notices.sections.dropFirst()) {
            #expect(section.range.upperBound == next.range.lowerBound)
        }
        #expect(notices.sections.last?.range.upperBound == data.count)

        let lightCraft = try #require(notices.section(named: "LightCraft"))
        let text = try #require(notices.text(of: lightCraft))
        #expect(text.hasPrefix("## LightCraft\n"))
        #expect(text.contains("## not a heading: inside a fence"))
        #expect(text.hasSuffix("```\n\n"))
        #expect(Data(text.utf8) == data.subdata(in: lightCraft.range))
    }

    @Test("A heading belongs to a project by its whole name")
    func headingsMatchWholeNames() throws {
        let notices = NoticesFile(data: Data(Self.sampleNotices.utf8))
        #expect(notices.section(named: "LibRaw")?.heading == "LibRaw 0.22.3")
        #expect(notices.section(named: "GRDB") == nil)
        #expect(NoticesFile.heading("LibRaw 0.22.3", names: "LibRaw"))
        #expect(NoticesFile.heading("LibRaw", names: "LibRaw"))
        #expect(!NoticesFile.heading("LibRawExtras", names: "LibRaw"))
        #expect(!NoticesFile.heading("About LibRaw", names: "LibRaw"))
    }

    @Test("A file with no heading, or none at all, has no sections")
    func emptyNotices() {
        #expect(NoticesFile(data: Data()).sections.isEmpty)
        #expect(NoticesFile(data: Data("# Title only\n\ntext\n".utf8)).sections.isEmpty)
    }

    @Test("Windows line endings don't end up in a heading")
    func carriageReturnsAreNotPartOfAHeading() {
        let notices = NoticesFile(data: Data("## GRDB\r\ntext\r\n".utf8))
        #expect(notices.sections.map(\.heading) == ["GRDB"])
    }

    // MARK: What a bundle can show (design §5; AC7, AC13)

    /// A folder standing in for a bundle's resources.
    private func withResources<T>(notices: Data?, license: Data?, _ body: (BundledLicenses) throws -> T) async throws -> T {
        try await RepositoryFiles.withTemporaryDirectory { directory in
            if let notices { try notices.write(to: directory.appending(path: BundledLicenses.noticesFileName)) }
            if let license { try license.write(to: directory.appending(path: BundledLicenses.licenseFileName)) }
            return try body(BundledLicenses(directory: directory))
        }
    }

    @Test("AC7, AC13: with the repository's own files, three projects and the app offer their text, byte for byte")
    func repositoryFilesAreShownByteForByte() async throws {
        let noticesData = try Data(contentsOf: RepositoryFiles.url("THIRD_PARTY_NOTICES.md"))
        let licenseData = try Data(contentsOf: RepositoryFiles.url("LICENSE"))
        try await withResources(notices: noticesData, license: licenseData) { licenses in
            #expect(licenses.available() == [.app, .project(.libRaw), .project(.lightCraft), .project(.grdb)])

            let license = try #require(licenses.text(for: .app))
            #expect(Data(license.utf8) == licenseData)

            let notices = NoticesFile(data: noticesData)
            for project in [Acknowledgement.Project.libRaw, .lightCraft, .grdb] {
                let name = try #require(Acknowledgements.entry(for: project)).name
                let section = try #require(notices.section(named: name), "no section for \(name)")
                let text = try #require(licenses.text(for: .project(project)))
                #expect(Data(text.utf8) == noticesData.subdata(in: section.range), "\(name)")
                #expect(text.hasPrefix("## \(name)"), "\(name)")
            }
        }
    }

    @Test("Design §5: darktable and ExifTool never offer a license, even with a section in the file")
    func studiedAndOptionalProjectsOfferNoLicense() async throws {
        let noticesData = try Data(contentsOf: RepositoryFiles.url("THIRD_PARTY_NOTICES.md"))
        let notices = NoticesFile(data: noticesData)
        #expect(notices.section(named: "darktable") != nil)
        #expect(notices.section(named: "ExifTool") != nil)
        try await withResources(notices: noticesData, license: nil) { licenses in
            let available = licenses.available()
            #expect(!available.contains(.project(.darktable)))
            #expect(!available.contains(.project(.exifTool)))
            #expect(!available.contains(.app))
        }
    }

    @Test("Design §5: before the files are in the bundle, nothing is offered")
    func noFilesNoControls() async throws {
        try await withResources(notices: nil, license: nil) { licenses in
            #expect(licenses.available().isEmpty)
            #expect(licenses.text(for: .app) == nil)
            #expect(licenses.text(for: .project(.libRaw)) == nil)
        }
        #expect(BundledLicenses(directory: nil).available().isEmpty)
    }

    @Test("Design §5: a project whose section is missing gets no control; the others keep theirs")
    func oneSectionMissing() async throws {
        let notices = Data("## LightCraft\n\nMIT\n\n## GRDB\n\nMIT\n".utf8)
        try await withResources(notices: notices, license: Data("license\n".utf8)) { licenses in
            #expect(licenses.available() == [.app, .project(.lightCraft), .project(.grdb)])
        }
    }

    @Test("Design §5: a file that is empty or not UTF-8 counts as missing")
    func unreadableFiles() async throws {
        let notUTF8 = Data([0x23, 0x23, 0x20, 0x47, 0x52, 0x44, 0x42, 0x0A, 0xFF, 0xFE, 0x0A])
        try await withResources(notices: notUTF8, license: Data()) { licenses in
            #expect(licenses.available().isEmpty)
        }
        try await withResources(notices: Data(), license: Data([0xFF, 0xFE])) { licenses in
            #expect(licenses.available().isEmpty)
        }
    }

    @Test("Design §5: the content follows the bundle, case by case")
    func contentFollowsTheBundle() async throws {
        let info = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"]
        let noticesData = try Data(contentsOf: RepositoryFiles.url("THIRD_PARTY_NOTICES.md"))
        let licenseData = try Data(contentsOf: RepositoryFiles.url("LICENSE"))

        // A built bundle with the files.
        try await withResources(notices: noticesData, license: licenseData) { licenses in
            let content = AboutContent(infoDictionary: info, licenses: licenses)
            #expect(content.version == AppVersion(infoDictionary: info))
            #expect(content.entries == Acknowledgements.all)
            #expect(content.entries.filter(content.offersLicense).map(\.project) == [.libRaw, .lightCraft, .grdb])
            #expect(content.offersAppLicense)
        }
        // A built bundle before the files are in it.
        try await withResources(notices: nil, license: nil) { licenses in
            let content = AboutContent(infoDictionary: info, licenses: licenses)
            #expect(content.version != nil)
            #expect(content.entries.count == 5)
            #expect(content.entries.filter(content.offersLicense).isEmpty)
            #expect(!content.offersAppLicense)
        }
        // No bundle.
        let bare = AboutContent(infoDictionary: nil, licenses: BundledLicenses(directory: nil))
        #expect(bare.version == nil)
        #expect(bare.entries.count == 5)
        #expect(bare.availableLicenses.isEmpty)
        // The files there, the version not.
        try await withResources(notices: noticesData, license: licenseData) { licenses in
            let content = AboutContent(infoDictionary: ["CFBundleVersion": "1"], licenses: licenses)
            #expect(content.version == nil)
            #expect(content.offersAppLicense)
        }
    }

    @Test("Nothing is cached: a file removed after a check is gone at the next question")
    func filesAreReadEachTime() async throws {
        try await RepositoryFiles.withTemporaryDirectory { directory in
            let file = directory.appending(path: BundledLicenses.licenseFileName)
            try Data("license\n".utf8).write(to: file)
            let licenses = BundledLicenses(directory: directory)
            #expect(licenses.text(for: .app) == "license\n")
            try FileManager.default.removeItem(at: file)
            #expect(licenses.text(for: .app) == nil)
        }
    }
}
