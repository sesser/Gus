import Foundation
import GRDB

/// Why a published photo has no original to stack on (R15, design §7.1).
/// Only what the app knows or the server's answers revealed; a locked asset
/// is never revealed, so nothing here says "locked".
public enum NoOriginalReason: Hashable, Sendable, Codable {
    /// Not imported from this server, and no mapped folder holds it.
    case noMappedFolder
    /// The server didn't return the photo it was imported from; `path` nil:
    /// no mapped folder holds the photo, else nothing is at that path.
    case linkedNotReturned(path: String?)
    /// Nothing at the mapped path (a wrong case, a locked asset and an
    /// unrevealed fault read this way).
    case nothingAtPath(String)
    case moreThanOne(String)
    case sizeDiffers(String)
    /// A photo at the path was published from this library, and nothing there can be used.
    case publishedHere(String)
    /// The photo it was imported from was published from this library.
    case linkedPublishedHere
    /// Its original is in the server's trash (at a path or by its link).
    case inTrash
    case hidden
    /// `path` nil: the linked asset is another account's.
    case anotherAccount(path: String?)
    /// `path` nil: the linked asset isn't a photo.
    case notPhoto(path: String?)

    /// The group in Check Originals and the results (design §7.1).
    public enum Group: String, Hashable, Sendable, CaseIterable, Codable {
        case noMappedFolder, importedOriginalNotFound, nothingAtPath, moreThanOne, sizeDiffers, publishedHere
        case inTrash, hidden, anotherAccount, notPhoto
    }

    public var group: Group {
        switch self {
        case .noMappedFolder: .noMappedFolder
        case .linkedNotReturned: .importedOriginalNotFound
        case .nothingAtPath: .nothingAtPath
        case .moreThanOne: .moreThanOne
        case .sizeDiffers: .sizeDiffers
        case .publishedHere, .linkedPublishedHere: .publishedHere
        case .inTrash: .inTrash
        case .hidden: .hidden
        case .anotherAccount: .anotherAccount
        case .notPhoto: .notPhoto
        }
    }
}

/// The outcome of looking for one photo's original (R11 to R13).
public enum OriginalMatch: Hashable, Sendable {
    case found(assetID: String)
    case none(NoOriginalReason)
}

/// The rules for an original, without requests (R11 to R13, design §7.1).
public enum OriginalRules {
    /// Why one of the account's assets can't be an original, in R13's order
    /// of faults (an asset with several counts under the first of the last
    /// four it has; size counts only for an asset with nothing else wrong).
    public enum Fault: Int, Hashable, Sendable, Comparable {
        case sizeDiffers = 0, published, trash, hidden, notPhoto

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The fault of an own asset, nil when it qualifies. `size`: the master's
    /// byte size, checked when both it and the server's are known (path
    /// matches only).
    public static func fault(of asset: RemoteAssetInfo, published: Set<String>, size: Int64?) -> Fault? {
        if published.contains(asset.id) { return .published }
        if asset.isTrashed { return .trash }
        if asset.isHidden { return .hidden }
        if !asset.isImage { return .notPhoto }
        if let size, let server = asset.byteCount, server != size { return .sizeDiffers }
        return nil
    }

    /// What one mapped path came to.
    public enum PathOutcome: Hashable, Sendable {
        case found(String)
        case nothing(String)
        /// Something about the assets there: more than one, or the one reason.
        case reason(NoOriginalReason)
    }

    /// R13 for the assets a search returned at `path`: only spellings of the
    /// path count (case counts; composed and decomposed both), only the
    /// account's own assets count whenever it has one there, exactly one
    /// qualifying asset is the original.
    public static func evaluate(path: String, assets: [RemoteAssetInfo], accountID: String, size: Int64?,
                                published: Set<String>) -> PathOutcome {
        let here = assets.filter { $0.originalPath.map { PublishPathForms.matches($0, path) } ?? false }
        let own = here.filter { $0.ownerID == accountID }
        if own.isEmpty {
            return here.isEmpty ? .nothing(path) : .reason(.anotherAccount(path: path))
        }
        let qualifying = own.filter { fault(of: $0, published: published, size: size) == nil }
        if qualifying.count == 1 { return .found(qualifying[0].id) }
        if qualifying.count > 1 { return .reason(.moreThanOne(path)) }
        let first = own.compactMap { fault(of: $0, published: published, size: size) }.min() ?? .sizeDiffers
        switch first {
        case .sizeDiffers: return .reason(.sizeDiffers(path))
        case .published: return .reason(.publishedHere(path))
        case .trash: return .reason(.inTrash)
        case .hidden: return .reason(.hidden)
        case .notPhoto: return .reason(.notPhoto(path: path))
        }
    }

    /// What the linked asset came to (R11): nil asset means not returned.
    public enum LinkOutcome: Hashable, Sendable {
        case none
        case found(String)
        case notReturned
        /// Returned, but it can't be used; the reason when the folder map has nothing.
        case unusable(NoOriginalReason)
    }

    public static func evaluate(linked asset: RemoteAssetInfo?, accountID: String, published: Set<String>) -> LinkOutcome {
        guard let asset else { return .notReturned }
        // Another account's reads as that, whatever else is wrong (design §7.1).
        guard asset.ownerID == accountID else { return .unusable(.anotherAccount(path: nil)) }
        switch fault(of: asset, published: published, size: nil) {
        case nil: return .found(asset.id)
        case .published?: return .unusable(.linkedPublishedHere)
        case .trash?: return .unusable(.inTrash)
        case .hidden?: return .unusable(.hidden)
        case .notPhoto?: return .unusable(.notPhoto(path: nil))
        case .sizeDiffers?: return .found(asset.id) // never for a link: no size is compared
        }
    }

    /// The folder map's outcome for a photo: its files' mapped paths, the raw
    /// first (R12). Nil when no mapped folder holds either file.
    public static func combine(_ outcomes: [PathOutcome]) -> PathOutcome? {
        guard !outcomes.isEmpty else { return nil }
        if let found = outcomes.first(where: { if case .found = $0 { true } else { false } }) { return found }
        // The raw's reason, else the JPEG's, else the first "nothing" (design §7.1).
        if let reason = outcomes.first(where: { if case .reason = $0 { true } else { false } }) { return reason }
        return outcomes.first
    }

    /// The ladder of design §7.1: a link that qualifies wins; else the map;
    /// else what the server revealed about the link; else what is known.
    public static func decide(link: LinkOutcome, map: PathOutcome?) -> OriginalMatch {
        if case .found(let id) = link { return .found(assetID: id) }
        switch map {
        case .found(let id)?:
            return .found(assetID: id)
        case .reason(let reason)?:
            return .none(reason)
        default:
            break
        }
        if case .unusable(let reason) = link { return .none(reason) }
        let nothingPath: String? = if case .nothing(let path)? = map { path } else { nil }
        if case .notReturned = link { return .none(.linkedNotReturned(path: nothingPath)) }
        return .none(nothingPath.map(NoOriginalReason.nothingAtPath) ?? .noMappedFolder)
    }
}

/// What the library knows about one photo for finding its original: its
/// files on the Mac (the raw first for a pair) and the assets it is linked to
/// on this server (itself, the photo a copy was made from, its pair partner;
/// only the first is tried, R11).
public struct PublishSource: Hashable, Sendable {
    public struct File: Hashable, Sendable {
        public var volumeIdentity: String
        public var relativePath: String
        public var byteSize: Int64

        public init(volumeIdentity: String, relativePath: String, byteSize: Int64) {
            self.volumeIdentity = volumeIdentity
            self.relativePath = relativePath
            self.byteSize = byteSize
        }
    }

    public var versionID: Int64
    public var imageID: Int64
    /// The raw first, then the JPEG (or HEIC) of a pair; one file otherwise.
    public var files: [File]
    /// Linked asset ids on this server, in R11's order.
    public var linkedAssetIDs: [String]

    public init(versionID: Int64, imageID: Int64, files: [File], linkedAssetIDs: [String]) {
        self.versionID = versionID
        self.imageID = imageID
        self.files = files
        self.linkedAssetIDs = linkedAssetIDs
    }

    /// The mapped server path of each file the map covers, raw first.
    public func mappedPaths(_ map: [PublishFolderMapping]) -> [String] {
        files.compactMap { PublishFolderMapping.winning(map, volumeIdentity: $0.volumeIdentity,
                                                        relativePath: $0.relativePath)?.path }
    }
}

extension Catalog {
    /// What finding the originals of `versionIDs` needs, for the server at
    /// `address` (R11, R12).
    public func publishSources(versionIDs: [Int64], provider: RemoteProvider = .immich, address: String) async throws
        -> [Int64: PublishSource] {
        try await database.read { db in
            var sources: [Int64: PublishSource] = [:]
            func file(imageID: Int64) throws -> (file: PublishSource.File, isRaw: Bool)? {
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT volume.identity, image.relativePath, image.fileSize FROM image
                    JOIN volume ON volume.id = image.volumeId WHERE image.id = ?
                    """, arguments: [imageID]) else { return nil }
                let path: String = row[1]
                let kind = FileKind(pathExtension: (path as NSString).pathExtension)
                return (PublishSource.File(volumeIdentity: row[0], relativePath: path, byteSize: row[2]), kind == .raw)
            }
            func link(versionID: Int64?) throws -> String? {
                guard let versionID else { return nil }
                return try String.fetchOne(db, sql: """
                    SELECT remoteId FROM remoteLink WHERE versionId = ? AND provider = ? AND address = ?
                    """, arguments: [versionID, provider.rawValue, address])
            }
            for versionID in versionIDs {
                guard let version = try VersionRecord.fetchOne(db, key: versionID),
                      let own = try file(imageID: version.imageId) else { continue }
                let partnerImage = try Int64.fetchOne(db, sql: """
                    SELECT companionImageId FROM imagePair WHERE rawImageId = ?
                    UNION SELECT rawImageId FROM imagePair WHERE companionImageId = ?
                    """, arguments: [version.imageId, version.imageId])
                var files = [own.file]
                var partnerDefault: Int64?
                if let partnerImage, let partner = try file(imageID: partnerImage) {
                    if partner.isRaw && !own.isRaw { files.insert(partner.file, at: 0) } else { files.append(partner.file) }
                    partnerDefault = try Int64.fetchOne(db, sql: "SELECT id FROM version WHERE imageId = ? AND isDefault",
                                                        arguments: [partnerImage])
                }
                // A copy's original is its master's default version (virtual
                // copies); a copy is never half of a pair, so its partner is
                // its original's, found by the shared image.
                let ownDefault = version.isDefault ? nil
                    : try Int64.fetchOne(db, sql: "SELECT id FROM version WHERE imageId = ? AND isDefault",
                                         arguments: [version.imageId])
                // R11: its own, then for a copy its original's, then the pair
                // partner's, so a copy takes the link its original takes.
                var links: [String] = []
                for id in [try link(versionID: versionID), try link(versionID: ownDefault),
                           try link(versionID: partnerDefault)].compactMap({ $0 }) where !links.contains(id) {
                    links.append(id)
                }
                sources[versionID] = PublishSource(versionID: versionID, imageID: version.imageId, files: files,
                                                   linkedAssetIDs: links)
            }
            return sources
        }
    }
}

/// Looks for photos' originals on one server (R11 to R13): the same function
/// for Check Originals and the run, so they agree (AC12). Reads only: one
/// `GET /assets/{id}` for a link, one search for a mapped file's spellings.
public struct OriginalFinder: Sendable {
    public let destination: any RemotePublishDestination
    public let catalog: Catalog
    public let address: String
    /// The key's account (`user.read`): only its assets can be originals.
    public let accountID: String
    public let folderMap: [PublishFolderMapping]

    public init(destination: any RemotePublishDestination, catalog: Catalog, address: String, accountID: String,
                folderMap: [PublishFolderMapping]) {
        self.destination = destination
        self.catalog = catalog
        self.address = address
        self.accountID = accountID
        self.folderMap = folderMap
    }

    /// The original of `source`, or why there is none. Throws when a request
    /// failed: looking for the original then counts as a failed stacking step,
    /// never as a reason (R15).
    public func find(_ source: PublishSource) async throws(PublishFailure) -> OriginalMatch {
        var link = OriginalRules.LinkOutcome.none
        if let linked = source.linkedAssetIDs.first {
            let asset = try await destination.asset(id: linked)
            let published = try await published(asset.map { [$0.id] } ?? [])
            link = OriginalRules.evaluate(linked: asset, accountID: accountID, published: published)
            if case .found(let id) = link { return .found(assetID: id) }
        }
        var outcomes: [OriginalRules.PathOutcome] = []
        for file in source.files {
            guard let path = PublishFolderMapping.winning(folderMap, volumeIdentity: file.volumeIdentity,
                                                          relativePath: file.relativePath)?.path else { continue }
            let assets = try await destination.assets(atPaths: PublishPathForms.forms(of: path))
            let published = try await published(assets.map(\.id))
            let outcome = OriginalRules.evaluate(path: path, assets: assets, accountID: accountID, size: file.byteSize,
                                                 published: published)
            outcomes.append(outcome)
            if case .found = outcome { break }
        }
        return OriginalRules.decide(link: link, map: OriginalRules.combine(outcomes))
    }

    private func published(_ ids: [String]) async throws(PublishFailure) -> Set<String> {
        do {
            return try await catalog.publishedRemoteIDs(address: address, among: ids)
        } catch {
            throw .remote(.disk(error.localizedDescription))
        }
    }
}

/// Check Originals' tally (design §7, AC12): what `OriginalFinder` says of
/// each photo, the run's own function, so the check and the run agree.
public struct OriginalsTally: Equatable, Sendable {
    public typealias Photo = (name: String, reason: NoOriginalReason)

    /// Photos whose original was found.
    public var found: Int
    /// Photos looked for: every photo but the offline ones.
    public var checked: Int
    /// Photos without an original, by group, groups in the order first met.
    public var groups: [(group: NoOriginalReason.Group, photos: [Photo])]
    /// Offline photos, left out of the check.
    public var offline: Int

    public init(found: Int = 0, checked: Int, groups: [(group: NoOriginalReason.Group, photos: [Photo])] = [],
                offline: Int) {
        self.found = found
        self.checked = checked
        self.groups = groups
        self.offline = offline
    }

    /// Counts one photo's outcome.
    public mutating func add(_ match: OriginalMatch, name: String) {
        switch match {
        case .found:
            found += 1
        case .none(let reason):
            if let at = groups.firstIndex(where: { $0.group == reason.group }) {
                groups[at].photos.append((name, reason))
            } else {
                groups.append((reason.group, [(name, reason)]))
            }
        }
    }

    /// Check Originals over `versionIDs` in their order: offline photos are
    /// counted and not looked for; a photo with no source is checked and
    /// counted in neither found nor a group. `progress` gets the photos done
    /// and the total after each. Nil when cancelled; throws the first failed
    /// request (the check then stops, saying why).
    public static func check(_ versionIDs: [Int64], offline: Set<Int64>, sources: [Int64: PublishSource],
                             names: [Int64: String], isolation: isolated (any Actor)? = #isolation,
                             find: (PublishSource) async throws(PublishFailure) -> OriginalMatch,
                             progress: (_ done: Int, _ total: Int) -> Void = { _, _ in })
        async throws(PublishFailure) -> OriginalsTally? {
        let checkable = versionIDs.filter { !offline.contains($0) }
        var tally = OriginalsTally(checked: checkable.count, offline: versionIDs.count - checkable.count)
        for (index, id) in checkable.enumerated() {
            if let source = sources[id] {
                do throws(PublishFailure) {
                    tally.add(try await find(source), name: names[id] ?? "")
                } catch {
                    if Task.isCancelled { return nil }
                    throw error
                }
            }
            if Task.isCancelled { return nil }
            progress(index + 1, checkable.count)
        }
        return tally
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.found == rhs.found && lhs.checked == rhs.checked && lhs.offline == rhs.offline
            && lhs.groups.map(\.group) == rhs.groups.map(\.group)
            && lhs.groups.map { $0.photos.map(\.name) } == rhs.groups.map { $0.photos.map(\.name) }
            && lhs.groups.map { $0.photos.map(\.reason) } == rhs.groups.map { $0.photos.map(\.reason) }
    }
}
