import Foundation
import Testing
@testable import PhotoCore

/// Finds spellings of the product name in text.
///
/// Two checks: exact substrings (the display name as written, the bundle
/// identifier, the XMP namespace), and whole words after splitting identifiers on
/// punctuation and camelCase, compared case-insensitively. The second catches
/// `GusCore`, `gus_cache` or `GUS` without flagging words like "August".
struct BrandScanner {
    var literals: [String]
    var wordTokens: Set<String>

    /// Current brand values plus the names recorded for earlier brands, so that
    /// leftovers of an old name are caught after a rename too.
    static let current = BrandScanner(
        literals: [AppBranding.displayName, AppBranding.bundleIdentifier,
                   AppBranding.cacheDirectoryName, AppBranding.sidecarNamespace]
            + AppBranding.previousAppSupportDirectoryNames + AppBranding.previousCacheDirectoryNames,
        wordTokens: Set(([AppBranding.displayName, AppBranding.appSupportDirectoryName,
                          AppBranding.urlScheme, AppBranding.sidecarNamespacePrefix]
                         + AppBranding.previousAppSupportDirectoryNames)
            .filter { $0.count >= 3 }
            .map { $0.lowercased() })
    )

    struct Hit: CustomStringConvertible {
        var file: String
        var line: Int
        var text: String
        var description: String { "\(file):\(line): \(text)" }
    }

    func hits(in text: String, file: String) -> [Hit] {
        var result: [Hit] = []
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            let literalHit = literals.contains { !$0.isEmpty && line.contains($0) }
            let wordHit = Self.words(in: line).contains { wordTokens.contains($0.lowercased()) }
            if literalHit || wordHit {
                result.append(Hit(file: file, line: index + 1, text: line.trimmingCharacters(in: .whitespaces)))
            }
        }
        return result
    }

    /// Splits on non-alphanumerics, then on camelCase and acronym boundaries.
    static func words(in line: String) -> [String] {
        var words: [String] = []
        for chunk in line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let characters = Array(chunk)
            var current = ""
            for (i, character) in characters.enumerated() {
                if !current.isEmpty, character.isUppercase {
                    let previous = characters[i - 1]
                    let nextIsLower = i + 1 < characters.count && characters[i + 1].isLowercase
                    if previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLower) {
                        words.append(current)
                        current = ""
                    }
                }
                current.append(character)
            }
            if !current.isEmpty { words.append(current) }
        }
        return words
    }
}

@Suite("Branding")
struct BrandingTests {
    /// Files under Sources/ that may spell the product name.
    static let allowedInSources: Set<String> = ["Sources/PhotoCore/Branding/AppBranding.swift"]

    static func isAllowed(_ path: String) -> Bool {
        allowedInSources.contains(path) || path.hasSuffix(".xcstrings")
    }

    @Test("Product name appears in Sources only in AppBranding and the String Catalog")
    func productNameDoesNotLeakIntoSources() throws {
        let files = RepositoryFiles.files(under: "Sources")
        #expect(files.count > 5, "expected to find the source tree at \(RepositoryFiles.root.path)")
        var hits: [BrandScanner.Hit] = []
        for path in files where !Self.isAllowed(path) {
            guard let text = try? String(contentsOf: RepositoryFiles.url(path), encoding: .utf8) else { continue }
            hits += BrandScanner.current.hits(in: text, file: path)
        }
        #expect(hits.isEmpty, "product name found outside AppBranding:\n\(hits.map(\.description).joined(separator: "\n"))")
    }

    @Test("Build files outside Sources read the name from Branding.xcconfig")
    func buildFilesDoNotSpellTheName() throws {
        let paths = ["Package.swift"] + RepositoryFiles.files(under: "Scripts") + RepositoryFiles.files(under: "Support")
        var hits: [BrandScanner.Hit] = []
        for path in paths {
            guard let text = try? String(contentsOf: RepositoryFiles.url(path), encoding: .utf8) else { continue }
            hits += BrandScanner.current.hits(in: text, file: path)
        }
        #expect(hits.isEmpty, "product name found in build files:\n\(hits.map(\.description).joined(separator: "\n"))")
    }

    @Test("The scanner is not vacuous")
    func scannerFindsKnownSpellings() throws {
        let scanner = BrandScanner.current
        let branding = try String(contentsOf: RepositoryFiles.url("Sources/PhotoCore/Branding/AppBranding.swift"),
                                  encoding: .utf8)
        #expect(!scanner.hits(in: branding, file: "AppBranding.swift").isEmpty)

        let name = AppBranding.displayName
        let flagged = [
            "let title = \"\(name)\"",
            "final class \(name)Core {}",
            "let folder = \"\(name.lowercased())_cache\"",
            "case \(name.uppercased())Mode",
            "open \(AppBranding.urlScheme)://item/1",
        ]
        for line in flagged {
            #expect(!scanner.hits(in: line, file: "sample").isEmpty, "should flag: \(line)")
        }
        let clean = ["let month = \"August\"", "struct PhotoGrid {}", "// nothing to see"]
        for line in clean {
            #expect(scanner.hits(in: line, file: "sample").isEmpty, "should not flag: \(line)")
        }
    }

    @Test("Branding.xcconfig agrees with AppBranding")
    func buildSettingsMatchAppBranding() throws {
        let settings = try RepositoryFiles.xcconfig("Branding.xcconfig")
        #expect(settings["PRODUCT_DISPLAY_NAME"] == AppBranding.displayName)
        #expect(settings["PRODUCT_BUNDLE_IDENTIFIER"] == AppBranding.bundleIdentifier)
        #expect(settings["PRODUCT_URL_SCHEME"] == AppBranding.urlScheme)
        let productName = try #require(settings["PRODUCT_NAME"])
        #expect(!productName.isEmpty && !productName.contains("/"))
        #expect(settings["IMPORTER_PRODUCT_DISPLAY_NAME"] == AppBranding.importerDisplayName)
        #expect(settings["IMPORTER_PRODUCT_BUNDLE_IDENTIFIER"] == AppBranding.importerBundleIdentifier)
        let importerName = try #require(settings["IMPORTER_PRODUCT_NAME"])
        #expect(!importerName.isEmpty && !importerName.contains("/") && importerName != productName)
        #expect(AppBranding.importerBundleIdentifier != AppBranding.bundleIdentifier)
    }

    @Test("Info.plist template is driven by build variables")
    func infoPlistUsesBuildVariables() throws {
        let template = try String(contentsOf: RepositoryFiles.url("Support/Info.plist"), encoding: .utf8)
        for variable in ["$(PRODUCT_NAME)", "$(PRODUCT_DISPLAY_NAME)", "$(PRODUCT_BUNDLE_IDENTIFIER)",
                         "$(PRODUCT_URL_SCHEME)", "$(EXECUTABLE_NAME)"] {
            #expect(template.contains(variable), "Info.plist should reference \(variable)")
        }
        let importer = try String(contentsOf: RepositoryFiles.url("Support/Importer-Info.plist"), encoding: .utf8)
        for variable in ["$(PRODUCT_NAME)", "$(PRODUCT_DISPLAY_NAME)", "$(PRODUCT_BUNDLE_IDENTIFIER)", "$(EXECUTABLE_NAME)"] {
            #expect(importer.contains(variable), "Importer-Info.plist should reference \(variable)")
        }
    }

    @Test("String Catalog refers to the product name only through arguments")
    func stringCatalogUsesArguments() throws {
        let data = try Data(contentsOf: RepositoryFiles.url("Sources/PhotoUI/Resources/Localizable.xcstrings"))
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        let text = String(decoding: data, as: UTF8.self)
        let hits = BrandScanner.current.hits(in: text, file: "Localizable.xcstrings")
        #expect(hits.isEmpty, "catalog should use %@ for the product name:\n\(hits.map(\.description).joined(separator: "\n"))")
        #expect(!strings.isEmpty)
    }

    @Test("Persisted file names are generic")
    func persistedNamesAreGeneric() throws {
        let scanner = BrandScanner.current
        for name in [LibraryLocations.catalogFileName, LibraryLocations.catalogFolderName,
                     LibraryLocations.previewFolderName] {
            #expect(scanner.hits(in: name, file: "name").isEmpty, "\(name) must not embed the product name")
        }
        let standard = try LibraryLocations.standard()
        #expect(standard.catalogFileURL.pathComponents.suffix(3)
            == [AppBranding.appSupportDirectoryName, LibraryLocations.catalogFolderName, LibraryLocations.catalogFileName])
        #expect(standard.previewCacheDirectory.pathComponents.suffix(2)
            == [AppBranding.cacheDirectoryName, LibraryLocations.previewFolderName])
    }
}
