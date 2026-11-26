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
    /// As typed (case counts). Kept without a trailing slash once saved; while
    /// the page is open it holds what is typed, and matching uses
    /// `keptServerPath` (review F6).
    public var serverPath: String

    /// The server path as matched and saved: `serverPathKept(serverPath)`.
    public var keptServerPath: String { Self.serverPathKept(serverPath) }

    /// The pair as saved: the server path as kept.
    public var kept: PublishFolderMapping {
        var kept = self
        kept.serverPath = keptServerPath
        return kept
    }

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
        let server = keptServerPath
        return server == "/" ? "/" + below : server + "/" + below
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

/// The permissions publishing needs, by option (R8, design §5). `stack.read`
/// is never asked for (RI-V5).
public enum PublishPermissions {
    /// Every publish: upload, and read every duplicate answer and original (R19).
    public static let always = ["asset.upload", "asset.read"]
    /// Any album, new or existing (DQ-V1: a lost create is looked for).
    public static let album = ["album.read", "albumAsset.create"]
    /// A new album, besides `album`.
    public static let newAlbum = ["album.create"]
    /// Stacking: the account (only its assets are originals) and the create.
    public static let stacking = ["user.read", "stack.create"]

    /// The gaps under each option, in the order the names are listed.
    public struct Missing: Hashable, Sendable {
        public var server: [String] = []
        public var album: [String] = []
        public var stacking: [String] = []

        public init(server: [String] = [], album: [String] = [], stacking: [String] = []) {
            self.server = server
            self.album = album
            self.stacking = stacking
        }

        public var isEmpty: Bool { server.isEmpty && album.isEmpty && stacking.isEmpty }
        public var all: [String] { server + album + stacking }
    }

    public static func missing(from permissions: [String], album choice: PublishAlbumChoice, stacking: Bool) -> Missing {
        func lacking(_ names: [String]) -> [String] {
            permissions.contains("all") ? [] : names.filter { !permissions.contains($0) }
        }
        var missing = Missing()
        missing.server = lacking(always)
        switch choice {
        case .none: break
        case .existing: missing.album = lacking(album)
        case .new: missing.album = lacking(album + newAlbum)
        }
        if stacking { missing.stacking = lacking(Self.stacking) }
        return missing
    }

    /// The key can list albums (design §3.4): without `album.read` only None can be chosen.
    public static func canListAlbums(_ permissions: [String]) -> Bool {
        permissions.contains("all") || permissions.contains("album.read")
    }
}

/// What a reload of the saved servers means for the server the publish
/// sheet has chosen (design §3.3).
public enum PublishServerChange: Equatable, Sendable {
    /// Still saved, and connected to as before: nothing to do.
    case unchanged
    /// Removed in the import window: the sheet keeps nothing of it and
    /// chooses no other by itself (review D-13).
    case removed
    /// Its address or trusted certificate changed: it is checked again,
    /// the person's choices kept (review F28).
    case connectionChanged(RemoteServiceRecord)

    /// `before` is the chosen record as the sheet held it, `servers` the
    /// saved servers as read again; nil `chosenID` is no server chosen.
    public static func after(reload servers: [RemoteServiceRecord], chosenID: Int64?,
                             before: RemoteServiceRecord?) -> PublishServerChange {
        guard let chosenID else { return .unchanged }
        guard let now = servers.first(where: { $0.id == chosenID }) else { return .removed }
        guard let before, before.id == chosenID else { return .unchanged }
        let connects = now.address != before.address || now.certificateFingerprint != before.certificateFingerprint
        return connects ? .connectionChanged(now) : .unchanged
    }
}
