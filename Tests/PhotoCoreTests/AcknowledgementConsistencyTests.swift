import Foundation
import Testing
@testable import PhotoCore

/// Compares the record of acknowledged projects with the places that name
/// them (issue #179, R9): `THIRD_PARTY_NOTICES.md`, the README's Credits,
/// `Package.swift` and the third-party source vendored under `Sources/`.
/// Every problem names the project (or the package or folder) it is about.
struct AcknowledgementConsistency {
    var record: [Acknowledgement]
    var notices: String
    var readme: String
    var package: String
    /// Folders under `Sources/` that hold third-party source.
    var vendored: [String]

    static let noticesFile = "THIRD_PARTY_NOTICES.md"

    /// The repository as it is.
    static func repository() throws -> AcknowledgementConsistency {
        AcknowledgementConsistency(
            record: Acknowledgements.all,
            notices: try String(contentsOf: RepositoryFiles.url(noticesFile), encoding: .utf8),
            readme: try String(contentsOf: RepositoryFiles.url("README.md"), encoding: .utf8),
            package: try String(contentsOf: RepositoryFiles.url("Package.swift"), encoding: .utf8),
            vendored: vendoredFolders(among: RepositoryFiles.files(under: "Sources")))
    }

    /// The headings of the notices file's sections.
    var noticesHeadings: [String] {
        NoticesFile(data: Data(notices.utf8)).sections.map(\.heading)
    }

    /// The README's Credits section: from its heading to the next heading of
    /// the same level, or the end.
    static func creditsSection(of readme: String) -> String? {
        let lines = readme.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Credits" }) else { return nil }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("## ") } ?? lines.count
        return lines[(start + 1)..<end].joined(separator: "\n")
    }

    /// The names the Credits section credits: what it sets in bold.
    static func creditedNames(in credits: String) -> [String] {
        let bold = try! NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#)
        let range = NSRange(credits.startIndex..., in: credits)
        return bold.matches(in: credits, range: range).compactMap { match in
            Range(match.range(at: 1), in: credits).map { credits[$0].trimmingCharacters(in: .whitespaces) }
        }
    }

    /// The `url:` or `path:` of every `.package(…)` outside comments.
    static func packageLocations(in package: String) -> [String] {
        let code = package.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let dependency = try! NSRegularExpression(pattern: #"\.package\(\s*(?:name:\s*"[^"]*"\s*,\s*)?(?:url|path):\s*"([^"]+)""#)
        let range = NSRange(code.startIndex..., in: code)
        return dependency.matches(in: code, range: range).compactMap { match in
            Range(match.range(at: 1), in: code).map { String(code[$0]) }
        }
    }

    /// "GRDB.swift" for "https://github.com/groue/GRDB.swift.git".
    static func packageName(_ location: String) -> String {
        let last = location.split(separator: "/").last.map(String.init) ?? location
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }

    /// Folders directly under `Sources/` that hold third-party source: any
    /// with a license, copyright or notice file of its own, or with C, C++
    /// or Objective-C files (this project's own code is Swift only).
    static func vendoredFolders(among files: [String]) -> [String] {
        let markers = ["LICENSE", "LICENCE", "COPYING", "COPYRIGHT", "NOTICE"]
        let foreignExtensions: Set<String> = ["c", "cc", "cpp", "cxx", "h", "hh", "hpp", "m", "mm"]
        var folders: Set<String> = []
        for file in files {
            let parts = file.split(separator: "/").map(String.init)
            guard parts.count >= 3, parts[0] == "Sources", let name = parts.last else { continue }
            let fileExtension = (name as NSString).pathExtension.lowercased()
            // "LICENSE", "LICENSE.LGPL", "COPYING.txt", "LICENSE-MIT"; not "LicenseView.swift".
            let stem = name.uppercased().split(whereSeparator: { ".-_".contains($0) }).first.map(String.init) ?? ""
            if fileExtension != "swift", markers.contains(stem) || foreignExtensions.contains(fileExtension) {
                folders.insert("Sources/" + parts[1])
            }
        }
        return folders.sorted()
    }

    func problems() -> [String] {
        var problems: [String] = []
        let headings = noticesHeadings
        let credits = Self.creditsSection(of: readme)
        let credited = credits.map(Self.creditedNames) ?? []
        if credits == nil { problems.append("README.md has no “## Credits” section") }

        // (a) Everything in the record is in the notices and the Credits.
        for entry in record {
            if !headings.contains(where: { NoticesFile.heading($0, names: entry.name) }) {
                problems.append("\(entry.name) is in the record but has no “## \(entry.name)” section in \(Self.noticesFile)")
            }
            if credits != nil, !credited.contains(where: { NoticesFile.heading($0, names: entry.name) }) {
                problems.append("\(entry.name) is in the record but the README's Credits don't name it (in bold)")
            }
        }
        // (b) Nothing is named there that the record lacks.
        for heading in headings where !record.contains(where: { NoticesFile.heading(heading, names: $0.name) }) {
            problems.append("\(Self.noticesFile) has a section “\(heading)” that the record lacks")
        }
        for name in credited where !record.contains(where: { NoticesFile.heading(name, names: $0.name) }) {
            problems.append("The README's Credits name \(name), which the record lacks")
        }
        // (c) Every package and every vendored folder has an entry, and no
        // entry claims one that isn't there.
        let locations = Self.packageLocations(in: package)
        for location in locations where !record.contains(where: { $0.packageURL == location }) {
            problems.append("Package.swift depends on \(Self.packageName(location)) (\(location)), which the record lacks")
        }
        for folder in vendored where !record.contains(where: { $0.vendoredPath == folder }) {
            problems.append("\(folder) holds third-party source, which the record lacks")
        }
        for entry in record {
            if let location = entry.packageURL, !locations.contains(location) {
                problems.append("\(entry.name) is recorded as the package \(location), which Package.swift doesn't declare")
            }
            if let folder = entry.vendoredPath, !vendored.contains(folder) {
                problems.append("\(entry.name) is recorded as vendored in \(folder), which holds no third-party source")
            }
        }
        return problems
    }
}

@Suite("Acknowledgements agree with the notices, the README and the package")
struct AcknowledgementConsistencyTests {
    @Test("AC11: the record matches THIRD_PARTY_NOTICES.md, the README's Credits, Package.swift and Sources/")
    func repositoryIsConsistent() throws {
        let repository = try AcknowledgementConsistency.repository()
        let problems = repository.problems()
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
        // Not vacuous: the real files were found and read.
        #expect(repository.noticesHeadings.count >= 5)
        #expect(AcknowledgementConsistency.creditsSection(of: repository.readme).map(AcknowledgementConsistency.creditedNames)?.count ?? 0 >= 5)
        #expect(AcknowledgementConsistency.packageLocations(in: repository.package) == ["https://github.com/groue/GRDB.swift.git"])
        #expect(repository.vendored == ["Sources/CLibRaw"])
    }

    @Test("AC10: removing a project from the record fails with its name", arguments: Acknowledgement.Project.allCases)
    func removingAnEntryIsNamed(project: Acknowledgement.Project) throws {
        var repository = try AcknowledgementConsistency.repository()
        let name = try #require(Acknowledgements.entry(for: project)).name
        repository.record.removeAll { $0.project == project }
        let problems = repository.problems()
        #expect(!problems.isEmpty)
        #expect(problems.allSatisfy { $0.contains(name) }, "\(problems)")
        // Both places that still name it say so.
        #expect(problems.contains { $0.contains(AcknowledgementConsistency.noticesFile) })
        #expect(problems.contains { $0.contains("Credits") })
    }

    @Test("AC10: a package the record lacks fails with the package's name")
    func addingAPackageIsNamed() throws {
        var repository = try AcknowledgementConsistency.repository()
        let declared = #".package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),"#
        #expect(repository.package.contains(declared))
        repository.package = repository.package.replacingOccurrences(
            of: declared,
            with: declared + "\n        .package(url: \"https://example.org/someone/SwiftWidgets.git\", from: \"1.0.0\"),")
        let problems = repository.problems()
        #expect(problems.count == 1)
        #expect(problems.first?.contains("SwiftWidgets") == true, "\(problems)")
        #expect(problems.first?.contains("Package.swift") == true)

        // A local package counts too; one in a comment does not.
        repository.package += "\n// .package(url: \"https://example.org/commented/Out.git\", from: \"1.0.0\")\n"
            + "let extra: Package.Dependency = .package(path: \"../LocalThing\")\n"
        let more = repository.problems()
        #expect(more.contains { $0.contains("LocalThing") })
        #expect(!more.contains { $0.contains("Out") })
    }

    @Test("AC10: vendored source the record lacks fails with its folder")
    func addingVendoredSourceIsNamed() throws {
        var repository = try AcknowledgementConsistency.repository()
        repository.vendored = AcknowledgementConsistency.vendoredFolders(among: [
            "Sources/CLibRaw/LICENSE.LGPL", "Sources/CZlib/zlib.h", "Sources/CZlib/src/inflate.c",
            "Sources/PhotoCore/Catalog/Catalog.swift", "Sources/Other/COPYING.txt", "Sources/Deep/a/b/NOTICE",
            "Sources/PhotoUI/About/LicenseView.swift", "Sources/PhotoUI/NoticesList.swift", "Sources/MIT/LICENSE-MIT",
        ])
        #expect(repository.vendored == ["Sources/CLibRaw", "Sources/CZlib", "Sources/Deep", "Sources/MIT", "Sources/Other"])
        let problems = repository.problems()
        #expect(problems.count == 4)
        for folder in ["Sources/CZlib", "Sources/Deep", "Sources/MIT", "Sources/Other"] {
            #expect(problems.contains { $0.contains(folder) }, "\(problems)")
        }
    }

    @Test("AC10: a project added to the notices or the Credits without the record fails with its name")
    func addingToTheNoticesOrCreditsIsNamed() throws {
        var repository = try AcknowledgementConsistency.repository()
        repository.notices += "\n## Halide\n\nSomething taken.\n"
        var problems = repository.problems()
        #expect(problems.count == 1)
        #expect(problems.first?.contains("Halide") == true && problems.first?.contains(AcknowledgementConsistency.noticesFile) == true,
                "\(problems)")

        repository = try AcknowledgementConsistency.repository()
        repository.readme += "- **OpenColorIO** for something.\n"
        problems = repository.problems()
        #expect(problems.count == 1)
        #expect(problems.first?.contains("OpenColorIO") == true && problems.first?.contains("Credits") == true, "\(problems)")
    }

    @Test("R9 (a): a project dropped from the notices or the Credits fails with its name")
    func droppingFromTheNoticesOrCreditsIsNamed() throws {
        var repository = try AcknowledgementConsistency.repository()
        repository.notices = repository.notices.replacingOccurrences(of: "\n## ExifTool\n", with: "\n### ExifTool\n")
        var problems = repository.problems()
        #expect(problems.count == 1)
        #expect(problems.first?.contains("ExifTool") == true && problems.first?.contains(AcknowledgementConsistency.noticesFile) == true,
                "\(problems)")

        repository = try AcknowledgementConsistency.repository()
        repository.readme = repository.readme.replacingOccurrences(of: "**GRDB**", with: "GRDB")
        problems = repository.problems()
        #expect(problems.count == 1)
        #expect(problems.first?.contains("GRDB") == true && problems.first?.contains("Credits") == true, "\(problems)")

        repository = try AcknowledgementConsistency.repository()
        repository.readme = repository.readme.replacingOccurrences(of: "## Credits", with: "## Thanks")
        #expect(repository.problems().contains { $0.contains("no “## Credits” section") })
    }

    @Test("A record that claims a package or a folder that isn't there fails with its name")
    func staleClaimsAreNamed() throws {
        var repository = try AcknowledgementConsistency.repository()
        repository.vendored = []
        #expect(repository.problems().contains { $0.contains("LibRaw") && $0.contains("Sources/CLibRaw") })

        repository = try AcknowledgementConsistency.repository()
        repository.package = repository.package.replacingOccurrences(of: "GRDB.swift.git", with: "Other.git")
        let problems = repository.problems()
        #expect(problems.contains { $0.contains("GRDB") && $0.contains("doesn't declare") })
        #expect(problems.contains { $0.contains("Other") && $0.contains("the record lacks") })
    }

    @Test("Bold in other README sections is not a credit; a heading with a version still matches")
    func creditsAreReadFromTheirSectionOnly() {
        let readme = "## Building\n\n**Xcode** is needed.\n\n## Credits\n\n- **LibRaw** decodes.\n- **GRDB** stores.\n\n## After\n\n**Other**\n"
        let credits = AcknowledgementConsistency.creditsSection(of: readme)
        #expect(credits.map(AcknowledgementConsistency.creditedNames) == ["LibRaw", "GRDB"])
        #expect(AcknowledgementConsistency.creditsSection(of: "## Building\n") == nil)
    }

    // MARK: Copyright and the free-software statement (R11)

    /// The README's License section, as one line of plain text.
    static func readmeLicenseSection() throws -> String {
        let readme = try String(contentsOf: RepositoryFiles.url("README.md"), encoding: .utf8)
        let lines = readme.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex(of: "## License"))
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("## ") } ?? lines.count
        var text = lines[(start + 1)..<end].joined(separator: " ")
        // "[words](target)" reads as its words.
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    @Test("R11: the copyright line's year and holder are the README's")
    func copyrightMatchesTheReadme() throws {
        let license = try Self.readmeLicenseSection()
        #expect(license.contains("Copyright © \(AppCopyright.year) \(AppCopyright.holder)."), "\(license)")
    }

    @Test("R11: the window's free-software statement is the README's paragraph")
    func statementMatchesTheReadme() throws {
        let key = "%@ is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3 or (at your option) any later version. It is distributed in the hope that it will be useful, but without any warranty; see the license for details."
        #expect(try LocalizationTests.catalog()[key] != nil, "the statement is not in the String Catalog")
        let statement = key.replacingOccurrences(of: "%@", with: AppBranding.displayName)
        #expect(try Self.readmeLicenseSection().contains(statement))
    }
}

/// License text is never typed into the app (issue #179, R11, AC13; non-goal
/// "no full licence text typed into the app by hand"): the windows read the
/// bundle's files. This looks for the text of a license itself, not for a
/// license's name or the short notice that says which license applies.
@Suite("No license text in Swift sources or the String Catalog")
struct LicenseTextTests {
    /// Phrases from the body of the licenses involved (GPL 3, LGPL 2.1, MIT,
    /// Apache 2.0, CDDL, Artistic), none of which a notice or a name has.
    static let phrases = [
        "TERMS AND CONDITIONS",
        "Everyone is permitted to copy and distribute verbatim copies",
        "Permission is hereby granted, free of charge",
        "THE SOFTWARE IS PROVIDED \"AS IS\"",
        "WITHOUT WARRANTY OF ANY KIND",
        "THERE IS NO WARRANTY FOR THE PROGRAM",
        "BECAUSE THE LIBRARY IS LICENSED FREE OF CHARGE",
        "IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE",
        "COVERED SOFTWARE IS PROVIDED UNDER THIS LICENSE",
        "Unless required by applicable law or agreed to in writing",
        "The above copyright notice and this permission notice shall be included",
    ]

    /// The license files in the repository; a share of their longer lines is
    /// looked for too, so a pasted passage without any of `phrases` is found.
    static let licenseFiles = ["LICENSE", "Sources/CLibRaw/LICENSE.LGPL", "Sources/CLibRaw/LICENSE.CDDL",
                               "THIRD_PARTY_NOTICES.md"]

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Every fifth line of 50 characters or more, of a license file (for
    /// the notices file, of its fenced license texts only).
    static func sampledLines(of file: String) throws -> [String] {
        let text = try String(contentsOf: RepositoryFiles.url(file), encoding: .utf8)
        var lines: [String] = []
        var inFence = false
        let fencedOnly = file.hasSuffix(".md")
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if fencedOnly, !inFence { continue }
            let trimmed = normalized(line).trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 50 { lines.append(String(trimmed.prefix(120))) }
        }
        return lines.enumerated().filter { $0.offset % 5 == 0 }.map(\.element)
    }

    static func needles() throws -> [String] {
        try phrases + licenseFiles.flatMap(sampledLines)
    }

    /// The needles found in a text, whatever its line breaks and indents.
    static func licenseText(in text: String, needles: [String]) -> [String] {
        let haystack = normalized(text) as NSString
        return needles.filter { haystack.range(of: $0).location != NSNotFound }
    }

    @Test("AC13: no Swift source and no catalog string holds license text")
    func sourcesHoldNoLicenseText() throws {
        let needles = try Self.needles()
        let files = RepositoryFiles.files(under: "Sources").filter { $0.hasSuffix(".swift") || $0.hasSuffix(".xcstrings") }
        #expect(files.count > 100, "expected to find the source tree at \(RepositoryFiles.root.path)")
        #expect(files.contains("Sources/PhotoUI/Resources/Localizable.xcstrings"))
        var hits: [String] = []
        for path in files {
            let text = try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
            for needle in Self.licenseText(in: text, needles: needles) {
                hits.append("\(path): “\(needle)”")
            }
        }
        #expect(hits.isEmpty, "license text belongs in the bundle's files, not in code or strings:\n\(hits.joined(separator: "\n"))")
    }

    @Test("The search is not vacuous, and a license's name or short notice is not license text")
    func searchFindsLicenseTextOnly() throws {
        let needles = try Self.needles()
        #expect(needles.count > 100)
        // The real files are full of what is looked for.
        for file in Self.licenseFiles {
            let text = try String(contentsOf: RepositoryFiles.url(file), encoding: .utf8)
            #expect(Self.licenseText(in: text, needles: needles).count >= 3, "\(file)")
        }
        // A passage pasted into a Swift string, re-wrapped, is found.
        let pasted = """
            let text = \"\"\"
                Permission is hereby granted,
                   free of charge, to any person obtaining a copy
                \"\"\"
            """
        #expect(!Self.licenseText(in: pasted, needles: needles).isEmpty)
        let gpl = try String(contentsOf: RepositoryFiles.url("LICENSE"), encoding: .utf8)
        let passage = gpl.components(separatedBy: "\n").dropFirst(200).prefix(12).joined(separator: "\n        // ")
        #expect(!Self.licenseText(in: "// " + passage, needles: needles).isEmpty)

        // Names and the short notice are fine: the window shows both.
        let allowed = [
            "GNU General Public License, version 3 or (at your option) any later version",
            "%@ is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3 or (at your option) any later version. It is distributed in the hope that it will be useful, but without any warranty; see the license for details.",
            "LGPL 2.1", "MIT", "GPL 3 or later", "Artistic License / GPL, as ExifTool states",
            "// License (Sources/CLibRaw/LICENSE.LGPL; LibRaw also offers CDDL 1.0,",
        ]
        for text in allowed {
            #expect(Self.licenseText(in: text, needles: needles).isEmpty, "\(text)")
        }
    }
}
