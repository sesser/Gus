import CoreGraphics
import Foundation
import GRDB

/// Which versions the browser shows.
public struct LibraryFilter: Hashable, Sendable {
    public enum Scope: Hashable, Sendable {
        case allPhotos
        case project(Int64)
        case album(Int64)
    }

    public enum RatingRule: Hashable, Sendable {
        case any
        case unrated
        case atLeast(Rating)
        case exactly(Rating)
    }

    public enum FlagRule: Hashable, Sendable, CaseIterable {
        case any
        case picked
        case rejected
        case unflagged
        case notRejected
    }

    public var scope: Scope
    public var rating: RatingRule
    public var flag: FlagRule

    public init(scope: Scope = .allPhotos, rating: RatingRule = .any, flag: FlagRule = .any) {
        self.scope = scope
        self.rating = rating
        self.flag = flag
    }

    /// True when `item` passes the rating and flag rules (scope is not checked).
    public func matchesCulling(_ item: CatalogItem) -> Bool {
        let ratingOK: Bool = switch rating {
        case .any: true
        case .unrated: item.rating == .unrated
        case .atLeast(let minimum): item.rating >= minimum
        case .exactly(let value): item.rating == value
        }
        let flagOK: Bool = switch flag {
        case .any: true
        case .picked: item.flag == .picked
        case .rejected: item.flag == .rejected
        case .unflagged: item.flag == .none
        case .notRejected: item.flag != .rejected
        }
        return ratingOK && flagOK
    }
}

/// A compact row for the browser: everything a grid cell and the preview pipeline
/// need, nothing more, so that 50k of them stay cheap to fetch and hold.
public struct CatalogItem: Hashable, Sendable, Identifiable {
    public let versionID: Int64
    public let imageID: Int64
    public let volumeID: Int64
    public var rating: Rating
    public var flag: Flag
    public var colorLabel: ColorLabel
    public let contentHash: String
    public let editStackHash: String
    public let relativePath: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let orientation: Int

    public var id: Int64 { versionID }

    public var fileName: String { (relativePath as NSString).lastPathComponent }

    /// Displayed size after EXIF orientation, or nil when unknown.
    public var orientedSize: CGSize? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        return ImageMetadata.swapsDimensions(orientation)
            ? CGSize(width: pixelHeight, height: pixelWidth)
            : CGSize(width: pixelWidth, height: pixelHeight)
    }
}

extension Catalog {
    /// Versions matching `filter`, in capture order.
    public func libraryItems(matching filter: LibraryFilter) async throws -> [CatalogItem] {
        var clauses: [String] = []
        var arguments = StatementArguments()
        switch filter.scope {
        case .allPhotos:
            break
        case .project(let id):
            clauses.append("image.projectId = ?")
            arguments += [id]
        case .album(let id):
            clauses.append("version.id IN (SELECT versionId FROM albumMember WHERE albumId = ?)")
            arguments += [id]
        }
        switch filter.rating {
        case .any:
            break
        case .unrated:
            clauses.append("version.rating = 0")
        case .atLeast(let minimum):
            clauses.append("version.rating >= ?")
            arguments += [minimum.rawValue]
        case .exactly(let value):
            clauses.append("version.rating = ?")
            arguments += [value.rawValue]
        }
        switch filter.flag {
        case .any: break
        case .picked: clauses.append("version.flag = 1")
        case .rejected: clauses.append("version.flag = -1")
        case .unflagged: clauses.append("version.flag = 0")
        case .notRejected: clauses.append("version.flag >= 0")
        }
        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = """
            SELECT version.id, version.imageId, image.volumeId, version.rating, version.flag,
                   version.colorLabel, image.contentHash, version.editStackHash, image.relativePath,
                   image.pixelWidth, image.pixelHeight, image.orientation
            FROM version
            JOIN image ON image.id = version.imageId
            \(whereClause)
            ORDER BY image.sortDate, image.id, version.versionNumber
            """
        let finalArguments = arguments
        return try await database.read { db in
            var items: [CatalogItem] = []
            let rows = try Row.fetchCursor(db, sql: sql, arguments: finalArguments)
            while let row = try rows.next() {
                items.append(CatalogItem(
                    versionID: row[0], imageID: row[1], volumeID: row[2],
                    rating: Rating(clamping: row[3]),
                    flag: Flag(rawValue: row[4]) ?? .none,
                    colorLabel: ColorLabel(rawValue: row[5]) ?? .none,
                    contentHash: row[6], editStackHash: row[7], relativePath: row[8],
                    pixelWidth: (row[9] as Int?) ?? 0, pixelHeight: (row[10] as Int?) ?? 0,
                    orientation: row[11]))
            }
            return items
        }
    }

    /// Number of versions in the whole library.
    public func versionCount() async throws -> Int {
        try await database.read { db in try VersionRecord.fetchCount(db) }
    }
}
