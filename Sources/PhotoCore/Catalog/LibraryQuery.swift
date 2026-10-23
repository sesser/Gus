import CoreGraphics
import Foundation
import GRDB

/// Which versions the browser shows.
public struct LibraryFilter: Hashable, Sendable {
    public enum Scope: Hashable, Sendable {
        case allPhotos
        case project(Int64)
        case album(Int64)
        case keyword(Int64)
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
    /// Show one item per RAW+JPEG pair instead of both files.
    public var groupsPairs: Bool

    public init(scope: Scope = .allPhotos, rating: RatingRule = .any, flag: FlagRule = .any, groupsPairs: Bool = true) {
        self.scope = scope
        self.rating = rating
        self.flag = flag
        self.groupsPairs = groupsPairs
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
    /// The other half's default version when this is the default version of one
    /// half of a RAW+JPEG pair.
    public var partnerVersionID: Int64? = nil
    public var partnerKind: FileKind? = nil
    /// True when pairs are grouped and this item stands for both files.
    public var representsPair = false

    public var id: Int64 { versionID }

    public var fileName: String { (relativePath as NSString).lastPathComponent }

    /// File name without its extension.
    public var baseName: String { (fileName as NSString).deletingPathExtension }

    public var fileKind: FileKind? {
        // Scanning the UTF-8 view avoids bridging to NSString, which showed up when
        // resolving 50k pair halves.
        let utf8 = relativePath.utf8
        guard let dot = utf8.lastIndex(of: UInt8(ascii: ".")),
              !utf8[dot...].contains(UInt8(ascii: "/")) else { return nil }
        return FileKind(pathExtension: String(relativePath[relativePath.index(after: dot)...]))
    }

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
        case .keyword(let id):
            clauses.append("version.id IN (SELECT versionId FROM versionKeyword WHERE keywordId = ?)")
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
                   image.pixelWidth, image.pixelHeight, image.orientation, version.isDefault
            FROM version
            JOIN image ON image.id = version.imageId
            \(whereClause)
            ORDER BY image.sortDate, image.id, version.versionNumber
            """
        let finalArguments = arguments
        let grouped = filter.groupsPairs
        return try await database.read { db in
            let hasPairs = try ImagePairRecord.fetchCount(db) > 0
            var items: [CatalogItem] = []
            var defaultIndexByImage: [Int64: Int] = [:]
            let rows = try Row.fetchCursor(db, sql: sql, arguments: finalArguments)
            while let row = try rows.next() {
                let item = CatalogItem(
                    versionID: row[0], imageID: row[1], volumeID: row[2],
                    rating: Rating(clamping: row[3]),
                    flag: Flag(rawValue: row[4]) ?? .none,
                    colorLabel: ColorLabel(rawValue: row[5]) ?? .none,
                    contentHash: row[6], editStackHash: row[7], relativePath: row[8],
                    pixelWidth: (row[9] as Int?) ?? 0, pixelHeight: (row[10] as Int?) ?? 0,
                    orientation: row[11])
                if hasPairs, row[12] as Bool { defaultIndexByImage[item.imageID] = items.count }
                items.append(item)
            }
            guard hasPairs else { return items }
            var pairs: [(raw: Int64, companion: Int64, showsCompanion: Bool)] = []
            let pairRows = try Row.fetchCursor(db, sql: "SELECT rawImageId, companionImageId, showsCompanion FROM imagePair")
            while let row = try pairRows.next() { pairs.append((row[0], row[1], row[2])) }
            Self.resolvePairs(in: &items, defaultIndexByImage: defaultIndexByImage, grouped: grouped, pairs: pairs)
            return items
        }
    }

    /// Links the two halves of each pair in `items` and, when `grouped`, drops the
    /// hidden half. A half whose partner did not match the filter stands alone, so
    /// a filter that matches only the JPEG still shows it.
    ///
    /// Only the pair table is read for this; joining pairs into the main query
    /// doubled its time on a 50k library.
    private static func resolvePairs(in items: inout [CatalogItem], defaultIndexByImage: [Int64: Int], grouped: Bool,
                                     pairs: [(raw: Int64, companion: Int64, showsCompanion: Bool)]) {
        var hidden = [Bool](repeating: false, count: grouped ? items.count : 0)
        var hiddenCount = 0
        for pair in pairs {
            guard let raw = defaultIndexByImage[pair.raw], let companion = defaultIndexByImage[pair.companion] else { continue }
            items[raw].partnerVersionID = items[companion].versionID
            items[raw].partnerKind = items[companion].fileKind
            items[companion].partnerVersionID = items[raw].versionID
            items[companion].partnerKind = items[raw].fileKind
            if grouped {
                let showsCompanion = pair.showsCompanion
                hidden[showsCompanion ? raw : companion] = true
                hiddenCount += 1
                items[showsCompanion ? companion : raw].representsPair = true
            }
        }
        guard hiddenCount > 0 else { return }
        var kept = 0
        for index in items.indices where !hidden[index] {
            items.swapAt(kept, index)
            kept += 1
        }
        items.removeLast(items.count - kept)
    }

    /// Number of versions in the whole library; with `groupingPairs` a RAW+JPEG
    /// pair counts once.
    public func versionCount(groupingPairs: Bool = true) async throws -> Int {
        try await database.read { db in
            try VersionRecord.fetchCount(db) - (groupingPairs ? try ImagePairRecord.fetchCount(db) : 0)
        }
    }

    /// Chooses which file represents each pair among `versionIDs` when pairs are
    /// grouped: the JPEG or HEIC (`showsCompanion`) or the RAW.
    public func setPairsShowCompanion(_ showsCompanion: Bool, forVersions versionIDs: [Int64]) async throws {
        guard !versionIDs.isEmpty else { return }
        try await database.write { db in
            for chunk in versionIDs.chunked(into: 10_000) {
                let placeholders = databaseQuestionMarks(count: chunk.count)
                try db.execute(sql: """
                    UPDATE imagePair SET showsCompanion = ?
                    WHERE rawImageId IN (SELECT imageId FROM version WHERE isDefault AND id IN (\(placeholders)))
                       OR companionImageId IN (SELECT imageId FROM version WHERE isDefault AND id IN (\(placeholders)))
                    """, arguments: StatementArguments([showsCompanion as (any DatabaseValueConvertible)?]
                                                         + (Array(chunk) + Array(chunk)).map { $0 }))
            }
        }
    }
}
