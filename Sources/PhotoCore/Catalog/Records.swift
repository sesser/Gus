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

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let volumeId = Column(CodingKeys.volumeId)
        public static let projectId = Column(CodingKeys.projectId)
        public static let relativePath = Column(CodingKeys.relativePath)
        public static let contentHash = Column(CodingKeys.contentHash)
        public static let sortDate = Column(CodingKeys.sortDate)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public var metadata: ImageMetadata {
        ImageMetadata(captureDate: captureDate, captureOffsetSeconds: captureOffsetSeconds,
                      pixelWidth: pixelWidth, pixelHeight: pixelHeight, orientation: orientation,
                      cameraMake: cameraMake, cameraModel: cameraModel, lensModel: lensModel,
                      iso: iso, exposureTime: exposureTime, fNumber: fNumber, focalLength: focalLength)
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
