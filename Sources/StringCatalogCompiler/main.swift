import Foundation

// Compiles a String Catalog (.xcstrings) into per-language .strings / .stringsdict
// files, the subset of what Xcode's xcstringstool does that this project needs.
// The Command Line Tools ship without xcstringstool, so Scripts/build-app.sh runs
// this instead. Supports plain string units and plural variations.
//
// usage: catalog-strings <Catalog.xcstrings> <output Resources directory>

struct CatalogError: Error, CustomStringConvertible {
    let description: String
}

/// Returns the printf conversion of the first format specifier in `format`
/// without the leading `%` or positional prefix, e.g. "lld" for "%1$lld photos".
func firstFormatSpecifier(in format: String) -> String? {
    let pattern = #"%(?:\d+\$)?([-+ 0#']*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[dDiuUxXoOfFeEgGcCsSpaA@])"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: format, range: NSRange(format.startIndex..., in: format)),
          let range = Range(match.range(at: 1), in: format)
    else { return nil }
    return String(format[range])
}

func stringsdictEntry(key: String, forms: [String: String]) throws -> [String: Any] {
    guard let other = forms["other"] else {
        throw CatalogError(description: "plural entry \"\(key)\" has no \"other\" form")
    }
    guard let valueType = firstFormatSpecifier(in: other) ?? firstFormatSpecifier(in: key) else {
        throw CatalogError(description: "plural entry \"\(key)\" has no format specifier")
    }
    var rule: [String: Any] = [
        "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
        "NSStringFormatValueTypeKey": valueType,
    ]
    for (form, value) in forms {
        rule[form] = value
    }
    return ["NSStringLocalizedFormatKey": "%#@value@", "value": rule]
}

func compile(input: URL, output: URL) throws {
    let data = try Data(contentsOf: input)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = root["strings"] as? [String: Any]
    else { throw CatalogError(description: "\(input.path) is not a String Catalog") }

    let sourceLanguage = root["sourceLanguage"] as? String ?? "en"
    let table = input.deletingPathExtension().lastPathComponent
    var plain: [String: [String: String]] = [:]
    var plural: [String: [String: Any]] = [:]

    for (key, value) in strings {
        let entry = value as? [String: Any] ?? [:]
        let localizations = entry["localizations"] as? [String: Any] ?? [:]
        if localizations[sourceLanguage] == nil {
            plain[sourceLanguage, default: [:]][key] = key
        }
        for (language, localizationValue) in localizations {
            guard let localization = localizationValue as? [String: Any] else { continue }
            if let unit = localization["stringUnit"] as? [String: Any], let text = unit["value"] as? String {
                plain[language, default: [:]][key] = text
            } else if let variations = localization["variations"] as? [String: Any],
                      let pluralForms = variations["plural"] as? [String: Any] {
                var forms: [String: String] = [:]
                for (form, formValue) in pluralForms {
                    if let unit = (formValue as? [String: Any])?["stringUnit"] as? [String: Any],
                       let text = unit["value"] as? String {
                        forms[form] = text
                    }
                }
                plural[language, default: [:]][key] = try stringsdictEntry(key: key, forms: forms)
            } else {
                throw CatalogError(description: "unsupported localization for \"\(key)\" (\(language))")
            }
        }
    }

    let fileManager = FileManager.default
    for language in Set(plain.keys).union(plural.keys) {
        let folder = output.appending(path: "\(language).lproj", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let stringsData = try PropertyListSerialization.data(fromPropertyList: plain[language] ?? [:],
                                                             format: .binary, options: 0)
        try stringsData.write(to: folder.appending(path: "\(table).strings"))
        if let entries = plural[language] {
            let dictData = try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
            try dictData.write(to: folder.appending(path: "\(table).stringsdict"))
        }
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: catalog-strings <Catalog.xcstrings> <output directory>\n".utf8))
    exit(64)
}
do {
    try compile(input: URL(fileURLWithPath: arguments[1]),
                output: URL(fileURLWithPath: arguments[2], isDirectory: true))
} catch {
    FileHandle.standardError.write(Data("catalog-strings: \(error)\n".utf8))
    exit(1)
}
