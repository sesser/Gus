import Foundation
import GRDB

// Row types for the catalog tables. Table and column names are generic on purpose:
// they are persisted and must survive a product rename unchanged.

/// A storage volume that holds masters: the boot disk, an external drive, a share.
public struct VolumeRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "volume"

    public var id: Int64?
    /// Volume UUID when the file system reports one, otherwise a fallback built
    /// from the volume name and mount point.
    public var identity: String
    public var name: String
    /// Where the volume was mounted when last seen.
    public var mountPath: String
    public var isRemovable: Bool
    public var isNetwork: Bool
    public var lastSeenAt: Date?

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let identity = Column(CodingKeys.identity)
        public static let mountPath = Column(CodingKeys.mountPath)
        public static let lastSeenAt = Column(CodingKeys.lastSeenAt)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    /// Absolute URL of a file on this volume at its last known mount point.
    public func url(forRelativePath relativePath: String) -> URL {
        URL(fileURLWithPath: mountPath, isDirectory: true)
            .appending(path: relativePath, directoryHint: .notDirectory)
    }
}

/// A named group of masters, created by an import or by hand. Each master belongs
/// to exactly one project.
public struct ProjectRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "project"

    public var id: Int64?
    public var uuid: String
    public var name: String
    /// Folder the project was imported from, if any.
    public var sourcePath: String?
    public var createdAt: Date

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let name = Column(CodingKeys.name)
        public static let createdAt = Column(CodingKeys.createdAt)
    }

    public init(id: Int64? = nil, uuid: String = UUID().uuidString, name: String,
                sourcePath: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.sourcePath = sourcePath
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// A master file. Never modified by the app; the catalog only references it.
public struct ImageRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "image"

    public var id: Int64?
    public var volumeId: Int64
    public var projectId: Int64
    /// Path relative to the volume's mount point, without a leading slash.
    public var relativePath: String
    public var fileName: String
    public var fileSize: Int64
    /// File modification date when imported.
    public var modifiedAt: Date
    /// Lowercase hex SHA-256 of the file contents.
    public var contentHash: String
    /// Lowercased file extension, e.g. "cr3".
    public var format: String
    public var captureDate: Date?
    public var captureOffsetSeconds: Int?
    /// `captureDate`, or `modifiedAt` when the file has no capture date.
    public var sortDate: Date
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var orientation: Int
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var iso: Int?
    public var exposureTime: Double?
    public var fNumber: Double?
    public var focalLength: Double?
    public var importedAt: Date
    /// Lowercased relative path without the extension; RAW and JPEG files that
    /// share it (on one volume, in one project) form a pair.
    public var pairingKey: String?
    public var importRunId: Int64?
    /// Capture day as `YYYY-MM-DD` in the capture's own time zone.
    public var localDate: String?
    public var artist: String?
    public var copyright: String?
    public var caption: String?
    public var cameraSerial: String?
    public var latitude: Double?
    public var longitude: Double?
    public var flashFired: Bool?
    public var exposureCompensation: Double?
    public var whiteBalance: Int?
    public var exposureProgram: Int?
    public var meteringMode: Int?
    public var focalLength35mm: Double?
    /// `ImageMetadata.revision` of the reader that filled the metadata columns.
    public var metadataRevision: Int
    /// JSON of `CreatorContact`.
    public var creatorContact: String?
    public var usageTerms: String?

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let volumeId = Column(CodingKeys.volumeId)
        public static let projectId = Column(CodingKeys.projectId)
        public static let relativePath = Column(CodingKeys.relativePath)
        public static let contentHash = Column(CodingKeys.contentHash)
        public static let sortDate = Column(CodingKeys.sortDate)
        public static let pairingKey = Column(CodingKeys.pairingKey)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    static func contactJSON(_ contact: CreatorContact) -> String? {
        guard !contact.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(contact)).map { String(decoding: $0, as: UTF8.self) }
    }

    public var metadata: ImageMetadata {
        var metadata = ImageMetadata(captureDate: captureDate, captureOffsetSeconds: captureOffsetSeconds,
                                     pixelWidth: pixelWidth, pixelHeight: pixelHeight, orientation: orientation,
                                     cameraMake: cameraMake, cameraModel: cameraModel, lensModel: lensModel,
                                     iso: iso, exposureTime: exposureTime, fNumber: fNumber, focalLength: focalLength)
        metadata.artist = artist
        metadata.copyright = copyright
        metadata.caption = caption
        metadata.cameraSerial = cameraSerial
        metadata.latitude = latitude
        metadata.longitude = longitude
        metadata.flashFired = flashFired
        metadata.exposureCompensation = exposureCompensation
        metadata.whiteBalance = whiteBalance
        metadata.exposureProgram = exposureProgram
        metadata.meteringMode = meteringMode
        metadata.focalLength35mm = focalLength35mm
        metadata.creatorContact = creatorContact.flatMap { try? JSONDecoder().decode(CreatorContact.self, from: Data($0.utf8)) }
        metadata.usageTerms = usageTerms
        return metadata
    }

    /// Copies the descriptive and technical columns from `metadata` (not the
    /// capture date, size or orientation, which are fixed at import).
    mutating func applyExtendedMetadata(_ metadata: ImageMetadata) {
        artist = metadata.artist
        copyright = metadata.copyright
        caption = metadata.caption
        cameraSerial = metadata.cameraSerial
        latitude = metadata.latitude
        longitude = metadata.longitude
        flashFired = metadata.flashFired
        exposureCompensation = metadata.exposureCompensation
        whiteBalance = metadata.whiteBalance
        exposureProgram = metadata.exposureProgram
        meteringMode = metadata.meteringMode
        focalLength35mm = metadata.focalLength35mm
        creatorContact = metadata.creatorContact.flatMap(Self.contactJSON)
        usageTerms = metadata.usageTerms
        metadataRevision = ImageMetadata.revision
    }
}

/// One non-destructive rendition of a master: culling state plus an edit stack.
public struct VersionRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "version"

    public var id: Int64?
    public var uuid: String
    public var imageId: Int64
    /// 1 for the version created at import, then increasing per master.
    public var versionNumber: Int
    /// Custom name; nil shows the localized default ("Version 1").
    public var name: String?
    public var isDefault: Bool
    public var rating: Rating
    public var flag: Flag
    public var colorLabel: ColorLabel
    /// Canonical JSON of the `EditStack`.
    public var editStack: String
    /// `EditStack.renderHash` of `editStack`, kept in sync on every write.
    public var editStackHash: String
    public var createdAt: Date
    public var modifiedAt: Date

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let imageId = Column(CodingKeys.imageId)
        public static let versionNumber = Column(CodingKeys.versionNumber)
        public static let rating = Column(CodingKeys.rating)
        public static let flag = Column(CodingKeys.flag)
        public static let colorLabel = Column(CodingKeys.colorLabel)
        public static let editStack = Column(CodingKeys.editStack)
        public static let editStackHash = Column(CodingKeys.editStackHash)
        public static let modifiedAt = Column(CodingKeys.modifiedAt)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public func decodedEditStack() throws -> EditStack {
        try EditStack.decode(from: editStack)
    }

    static func makeDefault(imageId: Int64, at date: Date) -> VersionRecord {
        VersionRecord(id: nil, uuid: UUID().uuidString, imageId: imageId, versionNumber: 1, name: nil,
                      isDefault: true, rating: .unrated, flag: .none, colorLabel: .none,
                      editStack: identityStackJSON, editStackHash: EditStack.identity.renderHash,
                      createdAt: date, modifiedAt: date)
    }

    static let identityStackJSON: String = (try? EditStack.identity.jsonString()) ?? #"{"operations":[],"schemaVersion":1}"#
}

public struct AlbumRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "album"

    public var id: Int64?
    public var uuid: String
    public var name: String
    /// Owning project, or nil for a library-level album.
    public var projectId: Int64?
    public var createdAt: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct AlbumMemberRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "albumMember"

    public var albumId: Int64
    public var versionId: Int64
    public var position: Int

    public enum Columns {
        public static let albumId = Column(CodingKeys.albumId)
        public static let versionId = Column(CodingKeys.versionId)
        public static let position = Column(CodingKeys.position)
    }
}

/// Groups versions of related shots; `pickVersionId` is the one shown on top.
public struct StackRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "stack"

    public var id: Int64?
    public var uuid: String
    public var pickVersionId: Int64?
    public var createdAt: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct StackMemberRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "stackMember"

    public var stackId: Int64
    public var versionId: Int64
    public var position: Int

    public enum Columns {
        public static let stackId = Column(CodingKeys.stackId)
        public static let position = Column(CodingKeys.position)
    }
}

/// A keyword; `parentId` makes them hierarchical.
public struct KeywordRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "keyword"

    public var id: Int64?
    public var name: String
    public var parentId: Int64?

    public enum Columns {
        public static let name = Column(CodingKeys.name)
        public static let parentId = Column(CodingKeys.parentId)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct VersionKeywordRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "versionKeyword"

    public var versionId: Int64
    public var keywordId: Int64
}

/// One run of the importer: the masters it added share it, which is what
/// "Last Import" shows.
public struct ImportRunRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "importRun"

    public var id: Int64?
    public var startedAt: Date
    public var sourcePath: String?
    public var projectId: Int64?

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// A saved query over the library (or one project); `rules` is the JSON of
/// `SmartAlbumRules`.
public struct SmartAlbumRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "smartAlbum"

    public var id: Int64?
    public var uuid: String
    public var name: String
    public var projectId: Int64?
    public var rules: String
    public var createdAt: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Sidecar bookkeeping for one master (see the v5 migration).
public struct MetadataSyncRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "metadataSync"

    public enum Status: Int, Codable, Sendable {
        case inStep = 0
        case changedOnDisk = 1
        case writeFailed = 2
    }

    public enum Source: Int, Codable, Sendable {
        case sidecar = 0
        case embedded = 1
    }

    public var imageId: Int64
    public var sidecarName: String?
    public var sidecarSize: Int64?
    public var sidecarModifiedAt: Date?
    public var sidecarDigest: String?
    /// JSON of the `SidecarValues` last read or written.
    public var baseline: String
    public var status: Status
    /// JSON of the `SidecarValues` found on disk, while `status` is `changedOnDisk`.
    public var diskValues: String?
    public var diskSource: Source
    public var checkedAt: Date?
    public var error: String?
}

/// A RAW master and the JPEG or HEIC shot with it. When pairs are grouped, the
/// browser shows one of the two (the RAW unless `showsCompanion`).
public struct ImagePairRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "imagePair"

    public var id: Int64?
    public var rawImageId: Int64
    public var companionImageId: Int64
    public var showsCompanion: Bool

    public enum Columns {
        public static let rawImageId = Column(CodingKeys.rawImageId)
        public static let companionImageId = Column(CodingKeys.companionImageId)
        public static let showsCompanion = Column(CodingKeys.showsCompanion)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
