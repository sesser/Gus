import Foundation

/// IPTC creator contact details (Iptc4xmpCore:CreatorContactInfo).
public struct CreatorContact: Codable, Hashable, Sendable {
    public var email: String?
    public var phone: String?
    public var url: String?
    public var address: String?
    public var city: String?
    public var region: String?
    public var postalCode: String?
    public var country: String?

    public init(email: String? = nil, phone: String? = nil, url: String? = nil, address: String? = nil,
                city: String? = nil, region: String? = nil, postalCode: String? = nil, country: String? = nil) {
        self.email = email
        self.phone = phone
        self.url = url
        self.address = address
        self.city = city
        self.region = region
        self.postalCode = postalCode
        self.country = country
    }

    public var isEmpty: Bool {
        [email, phone, url, address, city, region, postalCode, country].allSatisfy { ($0 ?? "").isEmpty }
    }
}

/// The values the app keeps in step between the catalog and a sidecar: culling,
/// keywords and the descriptive fields. One per master (a RAW+JPEG pair shares
/// one, through its RAW).
public struct SidecarValues: Codable, Hashable, Sendable {
    public var rating: Rating = .unrated
    public var flag: Flag = .none
    public var colorLabel: ColorLabel = .none
    public var keywords: [String] = []
    public var creator: String?
    public var rights: String?
    public var caption: String?
    public var usageTerms: String?
    public var contact: CreatorContact?

    public init(rating: Rating = .unrated, flag: Flag = .none, colorLabel: ColorLabel = .none, keywords: [String] = [],
                creator: String? = nil, rights: String? = nil, caption: String? = nil, usageTerms: String? = nil,
                contact: CreatorContact? = nil) {
        self.rating = rating
        self.flag = flag
        self.colorLabel = colorLabel
        self.keywords = keywords
        self.creator = creator
        self.rights = rights
        self.caption = caption
        self.usageTerms = usageTerms
        self.contact = contact
    }

    /// Nothing worth a sidecar of its own.
    public var isEmpty: Bool {
        self.sameAs(SidecarValues())
    }

    /// Equal for syncing: keywords compare as sets ignoring case, empty strings
    /// equal missing ones.
    public func sameAs(_ other: SidecarValues) -> Bool {
        differingFields(from: other).isEmpty
    }

    public enum Field: String, Codable, Hashable, Sendable, CaseIterable {
        case rating, flag, colorLabel, keywords, creator, rights, caption, usageTerms, contact
    }

    public func differingFields(from other: SidecarValues) -> [Field] {
        func text(_ value: String?) -> String { (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func contact(_ value: CreatorContact?) -> CreatorContact? { value?.isEmpty == false ? value : nil }
        var fields: [Field] = []
        if rating != other.rating { fields.append(.rating) }
        if flag != other.flag { fields.append(.flag) }
        if colorLabel != other.colorLabel { fields.append(.colorLabel) }
        if Set(keywords.map { $0.lowercased() }) != Set(other.keywords.map { $0.lowercased() }) { fields.append(.keywords) }
        if text(creator) != text(other.creator) { fields.append(.creator) }
        if text(rights) != text(other.rights) { fields.append(.rights) }
        if text(caption) != text(other.caption) { fields.append(.caption) }
        if text(usageTerms) != text(other.usageTerms) { fields.append(.usageTerms) }
        if contact(self.contact) != contact(other.contact) { fields.append(.contact) }
        return fields
    }

    /// `self` with `fields` taken from `other`.
    public func taking(_ fields: some Sequence<Field>, from other: SidecarValues) -> SidecarValues {
        var result = self
        for field in fields {
            switch field {
            case .rating: result.rating = other.rating
            case .flag: result.flag = other.flag
            case .colorLabel: result.colorLabel = other.colorLabel
            case .keywords: result.keywords = other.keywords
            case .creator: result.creator = other.creator
            case .rights: result.rights = other.rights
            case .caption: result.caption = other.caption
            case .usageTerms: result.usageTerms = other.usageTerms
            case .contact: result.contact = other.contact
            }
        }
        return result
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func decode(from json: String) throws -> SidecarValues {
        try JSONDecoder().decode(SidecarValues.self, from: Data(json.utf8))
    }
}
