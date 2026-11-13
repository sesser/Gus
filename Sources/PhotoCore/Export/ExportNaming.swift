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

/// One image of a planned export: where it goes, and what stood in the way of
/// its first-choice name.
public struct ExportPlanEntry: Hashable, Sendable {
    public var destination: ExportDestination
    /// A file of that name was already in the folder.
    public var nameExists: Bool
    /// The name is a library master's place, or the file there has a master's
    /// content (see `MasterFiles`): never written over.
    public var isMaster: Bool
}

/// The names of a batch that are already taken in its destination.
public struct ExportClashes: Hashable, Sendable {
    /// Files that exist under a name the batch would use.
    public var existing: Int
    /// Those of `existing` that are library masters: no choice replaces them.
    public var masters: Int

    public init(existing: Int = 0, masters: Int = 0) {
        self.existing = existing
        self.masters = masters
    }

    /// How many of the files in the way are originals, as the question about
    /// them puts it: each case has a message of its own (review.md R1).
    public enum Originals: Hashable, Sendable {
        /// None: every choice does what it says.
        case none
        /// Some of several: replacing replaces the others and numbers these.
        case some(Int)
        /// The one file in the way is an original: replacing does what keeping both does.
        case theOnlyFile
        /// All of several are originals: replacing does what keeping both does.
        case all
    }

    public var originals: Originals {
        if masters <= 0 { return .none }
        if masters < existing { return .some(masters) }
        return existing == 1 ? .theOnlyFile : .all
    }
}

/// File names for an export, decided up front for the whole batch so the
/// export window can say how many already exist before anything is written.
public enum ExportNaming {
    /// The file name, extension included, for one image before conflicts are
    /// resolved. A copy is named as the library shows it ("IMG_0412 copy"),
    /// under Original Name and through `{name}`, so an original and its
    /// copies exported together get different names; a template without
    /// `{name}` leaves that to `plan`'s numbering.
    public static func fileName(for context: TemplateContext, settings: ExportSettings) -> String {
        let original = context.name
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
    /// disk is handled by `policy`, except a library master's (`masters`),
    /// which no policy replaces: `.overwrite` gives that image the next free
    /// numbered name, as `.keepBoth` does. No image is ever given a master's
    /// name, numbered names included, whether or not the master's file is
    /// there now.
    ///
    /// A file is a master by its place or by its content
    /// (`MasterFiles.holdsContent(ofFileAt:)`). Content is looked at only for
    /// a file that is about to be replaced: one that exists, is no master by
    /// place, under `.overwrite`. `holdsMasterContent` stands in for that
    /// question in tests.
    public static func plan(_ contexts: [TemplateContext], settings: ExportSettings, in directory: URL,
                            policy: ExportConflictPolicy, masters: MasterFiles,
                            holdsMasterContent: ((URL) -> Bool)? = nil,
                            fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        -> [ExportDestination] {
        entries(contexts, settings: settings, in: directory, policy: policy, masters: masters,
                holdsMasterContent: holdsMasterContent, fileExists: fileExists)
            .map(\.destination)
    }

    /// `plan`, with what stood in the way of each image's first-choice name.
    public static func entries(_ contexts: [TemplateContext], settings: ExportSettings, in directory: URL,
                               policy: ExportConflictPolicy, masters: MasterFiles,
                               holdsMasterContent: ((URL) -> Bool)? = nil,
                               fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        -> [ExportPlanEntry] {
        // Every name goes into the one folder, so it is resolved once.
        entries(contexts, settings: settings, in: directory, policy: policy,
                protected: masters.names(in: directory),
                holdsMasterContent: holdsMasterContent ?? masters.holdsContent(ofFileAt:), fileExists: fileExists)
    }

    /// `entries` for masters' names taken earlier (`MasterFiles.names(in: directory)`):
    /// for a caller that makes `directory` in between. A folder resolves
    /// differently once it exists, so its masters are asked for in the same
    /// state of the disk the masters' own folders were resolved in.
    public static func entries(_ contexts: [TemplateContext], settings: ExportSettings, in directory: URL,
                               policy: ExportConflictPolicy, protected: MasterFiles.Names,
                               holdsMasterContent: (URL) -> Bool,
                               fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        -> [ExportPlanEntry] {
        entries(contexts, settings: settings, in: directory, policy: policy, protected: protected,
                contentAsked: .whereReplaced, holdsMasterContent: holdsMasterContent, fileExists: fileExists)
    }

    /// Which existing files are asked for their content.
    private enum ContentAsked {
        /// Those the policy would replace: the only ones at risk.
        case whereReplaced
        /// Every one that is no master by place: for counting before the policy is chosen.
        case everywhere
    }

    private static func entries(_ contexts: [TemplateContext], settings: ExportSettings, in directory: URL,
                                policy: ExportConflictPolicy, protected: MasterFiles.Names,
                                contentAsked: ContentAsked, holdsMasterContent: (URL) -> Bool,
                                fileExists: (URL) -> Bool) -> [ExportPlanEntry] {
        var taken = Set<String>()
        var result: [ExportPlanEntry] = []
        result.reserveCapacity(contexts.count)
        for context in contexts {
            let name = fileName(for: context, settings: settings)
            var candidate = unique(name, avoiding: taken) { _ in false }
            let url = directory.appending(path: candidate, directoryHint: .notDirectory)
            let exists = fileExists(url)
            var isMaster = protected.contains(candidate)
            // By content: read only when the answer decides something.
            if exists, !isMaster, policy == .overwrite || contentAsked == .everywhere {
                isMaster = holdsMasterContent(url)
            }
            let destination: ExportDestination
            if exists, policy == .skip {
                destination = .skip(url)
            } else if exists, policy == .overwrite, !isMaster {
                destination = .write(url, replacing: true)
            } else if exists || isMaster {
                // Keep Both, and any policy when the name is a master's.
                candidate = unique(name, avoiding: taken) {
                    protected.contains($0) || fileExists(directory.appending(path: $0, directoryHint: .notDirectory))
                }
                destination = .write(directory.appending(path: candidate, directoryHint: .notDirectory),
                                     replacing: false)
            } else {
                destination = .write(url, replacing: false)
            }
            result.append(ExportPlanEntry(destination: destination, nameExists: exists, isMaster: isMaster))
            taken.insert(candidate.lowercased())
        }
        return result
    }

    /// What the batch's names would meet in `directory`, for asking before the
    /// export starts. Every existing file that is no master by place is asked
    /// for its content here, since the choice (Replace or not) comes after.
    public static func clashes(_ contexts: [TemplateContext], settings: ExportSettings, in directory: URL,
                               masters: MasterFiles, holdsMasterContent: ((URL) -> Bool)? = nil,
                               fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        -> ExportClashes {
        let planned = entries(contexts, settings: settings, in: directory, policy: .skip,
                              protected: masters.names(in: directory), contentAsked: .everywhere,
                              holdsMasterContent: holdsMasterContent ?? masters.holdsContent(ofFileAt:),
                              fileExists: fileExists)
        return ExportClashes(existing: planned.count { $0.nameExists },
                             masters: planned.count { $0.nameExists && $0.isMaster })
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
