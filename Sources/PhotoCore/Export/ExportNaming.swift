import Foundation

/// What to do with an export whose file name is already taken in the destination.
public enum ExportConflictPolicy: String, Codable, Hashable, Sendable, CaseIterable {
    case overwrite
    case skip
    /// Writes the new file under a numbered name (`IMG_1-2.jpg`).
    case keepBoth
}

/// Where one exported image goes.
public enum ExportDestination: Hashable, Sendable {
    /// `replacing` when the file exists and the policy is to overwrite it.
    case write(URL, replacing: Bool)
    /// The file exists and the policy is to leave it.
    case skip(URL)

    public var url: URL {
        switch self {
        case .write(let url, _), .skip(let url): url
        }
    }
}

/// File names for an export, decided up front for the whole batch so the
/// export window can say how many already exist before anything is written.
public enum ExportNaming {
    /// The file name, extension included, for one image before conflicts are
    /// resolved.
    public static func fileName(for context: TemplateContext, settings: ExportSettings) -> String {
        let original = (context.originalName as NSString).deletingPathExtension
        var stem = settings.naming == .template
            ? ImportTemplate.sanitize(ImportTemplate.expand(settings.fileNameTemplate, context))
            : ImportTemplate.sanitize(original)
        if stem.isEmpty { stem = ImportTemplate.sanitize(original) }
        if stem.isEmpty { stem = "Untitled" }
        return stem + "." + settings.format.fileExtension
    }

    /// Destinations in `directory` for `contexts`, in order.
    ///
    /// Two images of the batch never share a name: later ones get `-2`, `-3`…
    /// (compared ignoring case, as the file system does). A name that exists on
    /// disk is handled by `policy`.
    public static func plan(_ contexts: [TemplateContext], settings: ExportSettings, in directory: URL,
                            policy: ExportConflictPolicy,
                            fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        -> [ExportDestination] {
        var taken = Set<String>()
        var result: [ExportDestination] = []
        result.reserveCapacity(contexts.count)
        for context in contexts {
            let name = fileName(for: context, settings: settings)
            var candidate = unique(name, avoiding: taken) { _ in false }
            let url = directory.appending(path: candidate, directoryHint: .notDirectory)
            if fileExists(url) {
                switch policy {
                case .overwrite:
                    result.append(.write(url, replacing: true))
                case .skip:
                    result.append(.skip(url))
                case .keepBoth:
                    candidate = unique(name, avoiding: taken) { fileExists(directory.appending(path: $0)) }
                    result.append(.write(directory.appending(path: candidate, directoryHint: .notDirectory),
                                         replacing: false))
                }
            } else {
                result.append(.write(url, replacing: false))
            }
            taken.insert(candidate.lowercased())
        }
        return result
    }

    /// How many of the batch's names already exist in `directory`.
    public static func existingCount(_ contexts: [TemplateContext], settings: ExportSettings, in directory: URL,
                                     fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        -> Int {
        plan(contexts, settings: settings, in: directory, policy: .skip, fileExists: fileExists)
            .filter { if case .skip = $0 { true } else { false } }
            .count
    }

    /// `name`, or `name-2`, `name-3`… (before the extension), whichever is
    /// neither taken in the batch nor `inUse`.
    private static func unique(_ name: String, avoiding taken: Set<String>, inUse: (String) -> Bool) -> String {
        if !taken.contains(name.lowercased()), !inUse(name) { return name }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var number = 2
        while true {
            let candidate = "\(stem)-\(number)" + (ext.isEmpty ? "" : "." + ext)
            if !taken.contains(candidate.lowercased()), !inUse(candidate) { return candidate }
            number += 1
        }
    }
}
