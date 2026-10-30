import Foundation
import GRDB

/// A descriptive field the Info tab edits, kept on `image` (shared by every
/// version of a master, and by both halves of a RAW+JPEG pair). Each one is an
/// IPTC Core or Extension property, written to sidecars and exports.
public enum DescriptiveField: String, CaseIterable, Hashable, Sendable {
    /// dc:title (IPTC-IIM Object Name).
    case title
    /// dc:description (IPTC-IIM Caption/Abstract, EXIF ImageDescription).
    case caption
    /// Iptc4xmpCore:AltTextAccessibility.
    case altText
    /// Iptc4xmpCore:ExtDescrAccessibility.
    case extendedDescription
    /// dc:rights (EXIF Copyright).
    case rights
    /// xmpRights:UsageTerms.
    case usageTerms
    /// dc:creator (EXIF Artist, IPTC-IIM By-line).
    case creator
    /// photoshop:AuthorsPosition (IPTC-IIM By-line Title).
    case jobTitle
    // Fields of Iptc4xmpCore:CreatorContactInfo.
    case address, city, region, postalCode, country, phone, email, url

    /// The Metadata heading's fields, in order.
    public static let general: [DescriptiveField] = [.title, .caption, .altText, .extendedDescription, .rights, .usageTerms]
    /// The Contact heading's fields, in order.
    public static let contact: [DescriptiveField] = [
        .creator, .jobTitle, .address, .city, .region, .postalCode, .country, .phone, .email, .url,
    ]

    /// Fields whose text usually runs to more than a line.
    public var isMultiline: Bool {
        switch self {
        case .caption, .altText, .extendedDescription, .usageTerms, .address: true
        default: false
        }
    }

    public func value(in values: SidecarValues) -> String? {
        switch self {
        case .title: values.title
        case .caption: values.caption
        case .altText: values.altText
        case .extendedDescription: values.extendedDescription
        case .rights: values.rights
        case .usageTerms: values.usageTerms
        case .creator: values.creator
        case .jobTitle: values.jobTitle
        case .address: values.contact?.address
        case .city: values.contact?.city
        case .region: values.contact?.region
        case .postalCode: values.contact?.postalCode
        case .country: values.contact?.country
        case .phone: values.contact?.phone
        case .email: values.contact?.email
        case .url: values.contact?.url
        }
    }

    public func set(_ value: String?, in values: inout SidecarValues) {
        var contact = values.contact ?? CreatorContact()
        switch self {
        case .title: values.title = value
        case .caption: values.caption = value
        case .altText: values.altText = value
        case .extendedDescription: values.extendedDescription = value
        case .rights: values.rights = value
        case .usageTerms: values.usageTerms = value
        case .creator: values.creator = value
        case .jobTitle: values.jobTitle = value
        case .address: contact.address = value
        case .city: contact.city = value
        case .region: contact.region = value
        case .postalCode: contact.postalCode = value
        case .country: contact.country = value
        case .phone: contact.phone = value
        case .email: contact.email = value
        case .url: contact.url = value
        }
        if isContactInfo {
            values.contact = contact.isEmpty ? nil : contact
        }
    }

    /// Stored in `CreatorContact` rather than in a column of its own.
    private var isContactInfo: Bool {
        switch self {
        case .address, .city, .region, .postalCode, .country, .phone, .email, .url: true
        default: false
        }
    }

    /// Surrounding white space trimmed; nil when nothing is left.
    public static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// The descriptive fields of a set of photos.
public struct DescriptiveSummary: Hashable, Sendable {
    /// Number of masters the photos stand for.
    public var imageCount = 0
    /// Each field's value when every master has the same one (missing when
    /// they all have none).
    public var values: [DescriptiveField: String] = [:]
    /// Fields whose value differs between the masters.
    public var mixed: Set<DescriptiveField> = []

    public init() {}
}

/// What setting a field changed, for undo: each master's earlier value.
public struct DescriptiveChange: Hashable, Sendable {
    public var field: DescriptiveField
    public var previous: [Int64: String] = [:]
    /// Masters written, including those that had no value.
    public var imageIDs: [Int64] = []
}

extension ImageRecord {
    /// Sets the descriptive columns from `values` (culling and keywords are not on `image`).
    mutating func applyDescriptiveValues(_ values: SidecarValues) {
        artist = values.creator
        copyright = values.rights
        caption = values.caption
        usageTerms = values.usageTerms
        creatorContact = values.contact.flatMap(Self.contactJSON)
        title = values.title
        altText = values.altText
        extendedDescription = values.extendedDescription
        jobTitle = values.jobTitle
    }
}

extension Catalog {
    /// The masters of `versionIDs` and their pair partners.
    static func descriptiveImages(_ db: Database, versions versionIDs: [Int64]) throws -> [Int64] {
        var images: Set<Int64> = []
        for chunk in versionIDs.chunked(into: 10_000) {
            images.formUnion(try Int64.fetchAll(db, sql: """
                SELECT imageId FROM version WHERE id IN (\(databaseQuestionMarks(count: chunk.count)))
                """, arguments: StatementArguments(Array(chunk))))
        }
        let own = Array(images)
        for chunk in own.chunked(into: 5_000) {
            let list = databaseQuestionMarks(count: chunk.count)
            images.formUnion(try Int64.fetchAll(db, sql: """
                SELECT companionImageId FROM imagePair WHERE rawImageId IN (\(list))
                UNION SELECT rawImageId FROM imagePair WHERE companionImageId IN (\(list))
                """, arguments: StatementArguments(Array(chunk) + Array(chunk))))
        }
        return images.sorted()
    }

    /// The descriptive fields shared by the masters of `versionIDs`.
    public func descriptiveSummary(forVersions versionIDs: [Int64]) async throws -> DescriptiveSummary {
        guard !versionIDs.isEmpty else { return DescriptiveSummary() }
        return try await database.read { db in
            let imageIDs = try Self.descriptiveImages(db, versions: versionIDs)
            var summary = DescriptiveSummary()
            var first = true
            for chunk in imageIDs.chunked(into: 2_000) {
                for image in try ImageRecord.fetchAll(db, keys: Array(chunk)) {
                    let values = image.descriptiveValues
                    for field in DescriptiveField.allCases where !summary.mixed.contains(field) {
                        let value = DescriptiveField.normalized(field.value(in: values))
                        if first {
                            summary.values[field] = value
                        } else if summary.values[field] != value {
                            summary.mixed.insert(field)
                            summary.values[field] = nil
                        }
                    }
                    first = false
                    summary.imageCount += 1
                }
            }
            return summary
        }
    }

    /// Sets one field on the masters of `versionIDs` (and their pair
    /// partners); `value` is trimmed, and empty clears the field.
    @discardableResult
    public func setDescriptiveField(_ field: DescriptiveField, to value: String?,
                                    forVersions versionIDs: [Int64]) async throws -> DescriptiveChange {
        let value = DescriptiveField.normalized(value)
        return try await database.write { db in
            let imageIDs = try Self.descriptiveImages(db, versions: versionIDs)
            var change = DescriptiveChange(field: field, imageIDs: imageIDs)
            for imageID in imageIDs {
                guard let image = try ImageRecord.fetchOne(db, key: imageID) else { continue }
                change.previous[imageID] = field.value(in: image.descriptiveValues)
                try Self.write(db, field, value, to: image)
            }
            return change
        }
    }

    /// Puts back what `change` replaced; returns what that replaced in turn
    /// (so restoring the result redoes the change).
    @discardableResult
    public func restoreDescriptiveField(_ change: DescriptiveChange) async throws -> DescriptiveChange {
        try await database.write { db in
            var replaced = DescriptiveChange(field: change.field, imageIDs: change.imageIDs)
            for imageID in change.imageIDs {
                guard let image = try ImageRecord.fetchOne(db, key: imageID) else { continue }
                replaced.previous[imageID] = change.field.value(in: image.descriptiveValues)
                try Self.write(db, change.field, change.previous[imageID], to: image)
            }
            return replaced
        }
    }

    /// Writes only the columns that change, so the sidecar trigger sees exactly those.
    private static func write(_ db: Database, _ field: DescriptiveField, _ value: String?, to image: ImageRecord) throws {
        var image = image
        var values = image.descriptiveValues
        field.set(value, in: &values)
        try image.updateChanges(db) { $0.applyDescriptiveValues(values) }
    }
}
