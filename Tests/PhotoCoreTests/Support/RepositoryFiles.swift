import Foundation

/// Locates files in the repository checkout the tests were compiled from.
enum RepositoryFiles {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // PhotoCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent()

    static func url(_ relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    /// Relative paths of every regular file under `relativeDirectory`.
    static func files(under relativeDirectory: String) -> [String] {
        let base = url(relativeDirectory)
        guard let enumerator = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        let rootPath = root.standardizedFileURL.path + "/"
        var result: [String] = []
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            result.append(String(file.standardizedFileURL.path.dropFirst(rootPath.count)))
        }
        return result.sorted()
    }

    /// Parses an xcconfig file into `KEY = VALUE` pairs (no includes or conditionals).
    static func xcconfig(_ relativePath: String) throws -> [String: String] {
        let text = try String(contentsOf: url(relativePath), encoding: .utf8)
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("//"), let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        return values
    }

    /// Creates a fresh temporary directory, removed when `body` returns.
    static func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async rethrows -> T {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "photocore-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await body(url)
    }
}
