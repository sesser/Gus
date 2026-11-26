import Foundation

/// The album a run files its photos in (R6).
public enum PublishAlbumChoice: Codable, Hashable, Sendable {
    case none
    /// One of the account's own albums.
    case existing(id: String, name: String)
    /// Made by the run with its first photo that gets an album step (design §3.4).
    case new(name: String)

    public var usesAlbum: Bool { self != .none }

    /// The album's name, if any.
    public var name: String? {
        switch self {
        case .none: nil
        case .existing(_, let name), .new(let name): name
        }
    }
}

/// What a server remembers of the last run started to it (R7): saved when a
/// run starts, never on Cancel. The description is never remembered.
public struct PublishChoices: Codable, Hashable, Sendable {
    public var settings: ExportSettings
    /// The export preset the settings were taken from, if any.
    public var presetID: Int64?
    public var album: PublishAlbumChoice
    public var visibility: PublishVisibility
    public var stacking: Bool

    public init(settings: ExportSettings, presetID: Int64? = nil, album: PublishAlbumChoice = .none,
                visibility: PublishVisibility = .timeline, stacking: Bool = true) {
        self.settings = settings
        self.presetID = presetID
        self.album = album
        self.visibility = visibility
        self.stacking = stacking
    }

    /// A server never published to (design §3.7): Export's current settings,
    /// Album None, Timeline, stacking on.
    public static func firstRun(exportSettings: ExportSettings) -> PublishChoices {
        PublishChoices(settings: exportSettings)
    }

    private enum CodingKeys: String, CodingKey {
        case settings, presetID, album, visibility, stacking
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? container.decodeIfPresent(ExportSettings.self, forKey: .settings)) ?? ExportSettings()
        presetID = (try? container.decodeIfPresent(Int64.self, forKey: .presetID)) ?? nil
        album = (try? container.decodeIfPresent(PublishAlbumChoice.self, forKey: .album)) ?? .none
        visibility = (try? container.decodeIfPresent(PublishVisibility.self, forKey: .visibility)) ?? .timeline
        stacking = (try? container.decodeIfPresent(Bool.self, forKey: .stacking)) ?? true
    }
}

/// One pair of the folder map (R12, design §6): a folder on the Mac, kept as
/// its volume's identity and its path inside the volume so it is still
/// matched when the volume mounts elsewhere, and the path the server sees it
/// as.
public struct PublishFolderMapping: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// `VolumeRecord.identity` / `VolumeDescriptor.identity`.
    public var volumeIdentity: String
    /// The folder inside its volume, without a leading or trailing slash;
    /// empty for the volume's root.
    public var folderPath: String
    /// The folder's absolute path when it was chosen, for showing while its
    /// volume is away.
    public var lastKnownPath: String
    /// As typed, without a trailing slash; case counts.
    public var serverPath: String

    public init(id: UUID = UUID(), volumeIdentity: String, folderPath: String, lastKnownPath: String,
                serverPath: String) {
        self.id = id
        self.volumeIdentity = volumeIdentity
        self.folderPath = Self.trimmedSlashes(folderPath)
        self.lastKnownPath = lastKnownPath
        self.serverPath = Self.serverPathKept(serverPath)
    }

    /// The server path as kept: a trailing slash dropped (but "/" stays), the
    /// rest exactly as typed (design §6).
    public static func serverPathKept(_ typed: String) -> String {
        var text = typed
        while text.count > 1, text.hasSuffix("/") { text.removeLast() }
        return text
    }

    static func trimmedSlashes(_ path: String) -> String {
        var text = Substring(path)
        while text.hasPrefix("/") { text = text.dropFirst() }
        while text.hasSuffix("/") { text = text.dropLast() }
        return String(text)
    }

    /// The master's server path, if this pair covers it: the folder's server
    /// path, then the master's path below the folder.
    public func serverPath(volumeIdentity identity: String, relativePath: String) -> String? {
        guard identity == volumeIdentity else { return nil }
        let below: Substring
        if folderPath.isEmpty {
            below = Substring(relativePath)
        } else {
            // Compared by Unicode scalars: the folder covers the master only
            // when its path is literally the master's first components.
            let prefix = Array((folderPath + "/").unicodeScalars)
            let scalars = Array(relativePath.unicodeScalars)
            guard scalars.count > prefix.count, Array(scalars.prefix(prefix.count)) == prefix else { return nil }
            below = Substring(String(String.UnicodeScalarView(scalars.dropFirst(prefix.count))))
        }
        guard !below.isEmpty else { return nil }
        return serverPath == "/" ? "/" + below : serverPath + "/" + below
    }

    /// The pair that covers the master, the longest Mac folder winning (R12).
    public static func winning(_ map: [PublishFolderMapping], volumeIdentity: String, relativePath: String)
        -> (mapping: PublishFolderMapping, path: String)? {
        map.compactMap { mapping in
            mapping.serverPath(volumeIdentity: volumeIdentity, relativePath: relativePath).map { (mapping, $0) }
        }
        .max { $0.mapping.folderPath.unicodeScalars.count < $1.mapping.folderPath.unicodeScalars.count }
    }

    /// The issues design §6 names for one pair, in the map `map`.
    public enum Issue: Hashable, Sendable {
        case emptyServerPath
        case duplicateFolder
    }

    public static func issues(of mapping: PublishFolderMapping, in map: [PublishFolderMapping]) -> [Issue] {
        var issues: [Issue] = []
        if mapping.serverPath.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.emptyServerPath) }
        if map.contains(where: { $0.id != mapping.id && $0.volumeIdentity == mapping.volumeIdentity
                                 && $0.folderPath == mapping.folderPath }) {
            issues.append(.duplicateFolder)
        }
        return issues
    }
}

/// The spellings of a server path a match accepts (R13, RI-V8): as built,
/// wholly composed (NFC) and wholly decomposed (NFD). Compared by Unicode
/// scalars, never with `String ==`, which treats the forms as equal.
public enum PublishPathForms {
    public static func forms(of path: String) -> [String] {
        var seen: [[Unicode.Scalar]] = []
        var forms: [String] = []
        for form in [path, path.precomposedStringWithCanonicalMapping, path.decomposedStringWithCanonicalMapping] {
            let scalars = Array(form.unicodeScalars)
            if !seen.contains(scalars) {
                seen.append(scalars)
                forms.append(form)
            }
        }
        return forms
    }

    /// `candidate` is one of `path`'s accepted spellings, scalar for scalar
    /// (case counts).
    public static func matches(_ candidate: String, _ path: String) -> Bool {
        let scalars = Array(candidate.unicodeScalars)
        return forms(of: path).contains { Array($0.unicodeScalars) == scalars }
    }
}
