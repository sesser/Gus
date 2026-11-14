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

    /// The Credits section's list items, each without its marker ("- ",
    /// "* ", "1. "), at any indent. A credit is a list item.
    static func creditItems(in credits: String) -> [String] {
        let marker = try! NSRegularExpression(pattern: #"^\s*(?:[-*+]|\d+[.)])\s+(.*)$"#)
        return credits.components(separatedBy: "\n").compactMap { line in
            guard let match = marker.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let text = Range(match.range(at: 1), in: line)
            else { return nil }
            return String(line[text])
        }
    }

    /// Whether a list item opens with a name in bold ("**LibRaw** decodes…").
    static func startsWithABoldName(_ item: String) -> Bool {
        item.range(of: #"^\*\*[^*\n]+\*\*"#, options: .regularExpression) != nil
    }

    /// The names the Credits section credits: what it sets in bold.
    static func creditedNames(in credits: String) -> [String] {
        let bold = try! NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#)
        let range = NSRange(credits.startIndex..., in: credits)
        return bold.matches(in: credits, range: range).compactMap { match in
            Range(match.range(at: 1), in: credits).map { credits[$0].trimmingCharacters(in: .whitespaces) }
        }
    }

    /// Swift source without its comments. String literals are kept whole:
    /// a URL has "//" in it.
    static func strippingComments(_ source: String) -> String {
        let characters = Array(source)
        var result = ""
        var index = 0
        var inString = false
        while index < characters.count {
            let character = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if inString {
                result.append(character)
                if character == "\\", let next {
                    result.append(next)
                    index += 1
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
                result.append(character)
            } else if character == "/", next == "/" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
                continue
            } else if character == "/", next == "*" {
                index += 2
                while index + 1 < characters.count, !(characters[index] == "*" && characters[index + 1] == "/") { index += 1 }
                index += 1
            } else {
                result.append(character)
            }
            index += 1
        }
        return result
    }

    /// Something `Package.swift` brings in from outside the repository.
    struct Dependency: Equatable {
        /// For the failure message: "GRDB.swift", a registry id, a binary target's name.
        var name: String
        /// What an entry's `packageURL` must equal: the `url:`, `path:` or `id:`.
        var location: String
    }

    /// Every external dependency `Package.swift` declares, outside
    /// comments: `.package(…)` by `url:`, `path:` or registry `id:`, and
    /// `.binaryTarget(…)` by `url:` or `path:`. A call none of these can be
    /// read from is listed with its own text, so it is never passed over.
    static func dependencies(in package: String) -> [Dependency] {
        let code = Array(strippingComments(package))
        let argument = try! NSRegularExpression(pattern: #"\b(url|path|id|name)\s*:\s*"([^"]*)""#)
        var found: [(offset: Int, dependency: Dependency)] = []
        for (marker, isBinary) in [(".package(", false), (".binaryTarget(", true)] {
            let pattern = Array(marker)
            var index = 0
            while index + pattern.count <= code.count {
                guard Array(code[index..<(index + pattern.count)]) == pattern else {
                    index += 1
                    continue
                }
                // The call's arguments, to its closing parenthesis.
                var end = index + pattern.count
                var depth = 1
                var inString = false
                while end < code.count, depth > 0 {
                    let character = code[end]
                    if inString {
                        if character == "\\" { end += 1 } else if character == "\"" { inString = false }
                    } else if character == "\"" {
                        inString = true
                    } else if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        depth -= 1
                    }
                    end += 1
                }
                let call = String(code[index..<min(end, code.count)])
                var values: [String: String] = [:]
                for match in argument.matches(in: call, range: NSRange(call.startIndex..., in: call)) {
                    if let label = Range(match.range(at: 1), in: call), let value = Range(match.range(at: 2), in: call),
                       values[String(call[label])] == nil {
                        values[String(call[label])] = String(call[value])
                    }
                }
                let unread = call.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let location = values["url"] ?? values["path"] ?? (isBinary ? values["name"] : values["id"]) ?? unread
                let name = isBinary ? (values["name"] ?? packageName(location)) : packageName(location)
                found.append((index, Dependency(name: name, location: location)))
                index = max(end, index + pattern.count)
            }
        }
        return found.sorted { $0.offset < $1.offset }.map(\.dependency)
    }

    static func packageLocations(in package: String) -> [String] {
        dependencies(in: package).map(\.location)
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
        // A credit without a bold name would not be read as one: every
        // item of the list must open with its project's name in bold.
        for item in credits.map(Self.creditItems) ?? [] where !Self.startsWithABoldName(item) {
            problems.append("The README's Credits have an item that doesn't start with a project's name in bold: “\(item)”")
        }
        // (c) Every package and every vendored folder has an entry, and no
        // entry claims one that isn't there.
        let dependencies = Self.dependencies(in: package)
        let locations = dependencies.map(\.location)
        for dependency in dependencies where !record.contains(where: { $0.packageURL == dependency.location }) {
            problems.append("Package.swift depends on \(dependency.name) (\(dependency.location)), which the record lacks")
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

    @Test("AC10: every form of outside dependency is seen: a registry id, a binary target, a named or wrapped package", arguments: [
        (#".package(id: "groue.GRDB-extras", from: "1.0.0"),"#, "groue.GRDB-extras"),
        (#".binaryTarget(name: "CWidgets", url: "https://example.org/CWidgets.xcframework.zip", checksum: "abc"),"#, "CWidgets"),
        (#".binaryTarget(name: "LocalBlob", path: "Vendor/LocalBlob.xcframework"),"#, "LocalBlob"),
        (#".package(name: "OldStyle", url: "https://example.org/someone/OldStyle.git", .upToNextMajor(from: "2.0.0")),"#, "OldStyle"),
        (".package(\n            url: \"https://example.org/someone/Wrapped.git\",\n            from: \"1.0.0\"\n        ),", "Wrapped"),
        (#".package(url: "https://example.org/someone/Trailing.git", branch: "main"), // .package(url: "https://example.org/x/Commented.git")"#, "Trailing"),
        (#".package(someFunctionOf("x")),"#, ".package(someFunctionOf"),
    ])
    func everyFormOfDependencyIsNamed(declaration: String, name: String) throws {
        var repository = try AcknowledgementConsistency.repository()
        let declared = #".package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),"#
        #expect(repository.package.contains(declared))
        repository.package = repository.package.replacingOccurrences(of: declared, with: declared + "\n        " + declaration)
        let problems = repository.problems()
        #expect(problems.count == 1, "\(problems)")
        #expect(problems.first?.contains(name) == true && problems.first?.contains("Package.swift") == true, "\(problems)")
        #expect(!problems.contains { $0.contains("Commented") })
    }

    @Test("Comments are taken out of Package.swift, and strings are not")
    func commentsAreStripped() {
        let source = """
            let a = "https://example.org/a" // .package(url: "https://example.org/b")
            /* .package(url: "https://example.org/c")
               .binaryTarget(name: "D", path: "d") */ let e = "/* not a comment */ // nor this"
            let f = "a \\"quoted\\" // word"
            """
        let code = AcknowledgementConsistency.strippingComments(source)
        #expect(code.contains(#""https://example.org/a""#))
        #expect(!code.contains("example.org/b") && !code.contains("example.org/c") && !code.contains("binaryTarget"))
        #expect(code.contains(#""/* not a comment */ // nor this""#))
        #expect(code.contains(#""a \"quoted\" // word""#))
        #expect(AcknowledgementConsistency.dependencies(in: source).isEmpty)
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

        // A credit with no bold name is not passed over: the item itself fails.
        for line in ["- OpenColorIO for the color transforms.", "* Thanks to OpenColorIO.", "  - OpenColorIO, nested.",
                     "1. OpenColorIO", "- See **OpenColorIO**."] {
            repository = try AcknowledgementConsistency.repository()
            repository.readme += line + "\n"
            problems = repository.problems()
            #expect(!problems.isEmpty, "\(line)")
            #expect(problems.allSatisfy { $0.contains("OpenColorIO") && $0.contains("Credits") }, "\(line): \(problems)")
        }
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
        // Twice: the record's project is no longer named, and its item no longer opens in bold.
        #expect(problems.count == 2)
        #expect(problems.allSatisfy { $0.contains("GRDB") && $0.contains("Credits") }, "\(problems)")

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
        #expect(credits.map(AcknowledgementConsistency.creditItems) == ["**LibRaw** decodes.", "**GRDB** stores."])
        #expect(AcknowledgementConsistency.creditItems(in: "Intro, not an item:\n\n- **A** one\n  wrapped line\n* b\n  - **C** nested\n2) d")
            == ["**A** one", "b", "**C** nested", "d"])
        #expect(AcknowledgementConsistency.startsWithABoldName("**A** one"))
        #expect(!AcknowledgementConsistency.startsWithABoldName("b **A**"))
        #expect(!AcknowledgementConsistency.startsWithABoldName("**unclosed"))
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
        // The literal `AboutText.freeSoftwareStatement` passes to
        // `String(localized:)`, read from its source: the project's name,
        // then the sentence.
        let segments = try AboutWordingTests.literalSegments(after: #"String(localized: "\(projectName) is free software"#,
                                                             startingAt: #"String(localized: ""#)
        guard segments.count == 2, segments[0] == .interpolation, case .text(let sentence) = segments[1] else {
            Issue.record("the statement should be the project's name followed by one plain sentence: \(segments)")
            return
        }
        #expect(sentence.hasPrefix(" is free software"))
        #expect(try LocalizationTests.catalog()["%@" + sentence] != nil, "the statement is not in the String Catalog")
        #expect(try Self.readmeLicenseSection().contains(AppBranding.displayName + sentence))
    }

    @Test("R11: the window's copyright line is the README's")
    func copyrightLineMatchesTheReadme() throws {
        let segments = try AboutWordingTests.literalSegments(after: #"String(localized: "Copyright ©"#, startingAt: #"String(localized: ""#)
        // "Copyright © ‹year› ‹holder›": the two values in that order.
        var values = [AppCopyright.year, AppCopyright.holder].makeIterator()
        let line = segments.map { segment -> String in
            if case .text(let text) = segment { text } else { values.next() ?? "?" }
        }.joined()
        #expect(segments.filter { $0 == .interpolation }.count == 2)
        #expect(try Self.readmeLicenseSection().contains(line + "."), "\(line)")
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
