import Foundation

/// Autocomplete for a comma-separated keyword field: suggestions for the word
/// being typed (the text after the last comma) from the library's keywords.
public enum KeywordCompletion {
    /// Keywords typed before the last comma, plus the one being typed.
    public static func split(_ text: String) -> (finished: [String], current: String) {
        var parts = text.components(separatedBy: ",")
        let current = parts.removeLast().trimmingCharacters(in: .whitespaces)
        return (parts.compactMap(Catalog.normalizedKeywordName), current)
    }

    /// Every keyword in the field.
    public static func keywords(in text: String) -> [String] {
        let (finished, current) = split(text)
        return ImageMetadata.uniqueKeywords(finished + [current])
    }

    /// Suggestions for the word being typed: names starting with it first, then
    /// names with a word starting with it, then names containing it. Keywords
    /// already in the field are left out.
    public static func suggestions(for text: String, from names: [String], limit: Int = 8) -> [String] {
        let (finished, current) = split(text)
        let query = current.lowercased()
        guard !query.isEmpty else { return [] }
        let used = Set(finished.map { $0.lowercased() })
        var prefix: [String] = []
        var wordPrefix: [String] = []
        var contains: [String] = []
        for name in names {
            let lower = name.lowercased()
            guard !used.contains(lower) else { continue }
            if lower.hasPrefix(query) {
                prefix.append(name)
            } else if lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(query) }) {
                wordPrefix.append(name)
            } else if lower.contains(query) {
                contains.append(name)
            }
        }
        // Shorter prefix matches first, so "dog" comes before "dog park".
        prefix.sort { ($0.count, $0.lowercased()) < ($1.count, $1.lowercased()) }
        return Array((prefix + wordPrefix + contains).prefix(limit))
    }

    /// The field text with the word being typed replaced by `suggestion`, ready
    /// for the next keyword.
    public static func completing(_ text: String, with suggestion: String) -> String {
        let (finished, _) = split(text)
        return (finished + [suggestion]).joined(separator: ", ") + ", "
    }
}
