/// One name per metadata field, shared by the Info tab, Changed on Disk and
/// the metadata preset editor (design.md I9); the UI puts each into words,
/// sentence-style for row labels. A field shown in two places reads the same
/// in both.
public enum FieldLabel: String, CaseIterable, Hashable, Sendable {
    case title, description, altText, extendedDescription, copyright, usageTerms
    case creator, jobTitle, address, city, stateProvince, postalCode, countryRegion, phone, email, website
    /// Changed on Disk's rows for values that aren't descriptive fields.
    case rating, flag, colorLabel, keywords, contact

    public init(_ field: DescriptiveField) {
        self = switch field {
        case .title: .title
        case .caption: .description
        case .altText: .altText
        case .extendedDescription: .extendedDescription
        case .rights: .copyright
        case .usageTerms: .usageTerms
        case .creator: .creator
        case .jobTitle: .jobTitle
        case .address: .address
        case .city: .city
        case .region: .stateProvince
        case .postalCode: .postalCode
        case .country: .countryRegion
        case .phone: .phone
        case .email: .email
        case .url: .website
        }
    }

    /// Changed on Disk compares sidecar values; the contact details are one row.
    public init(_ field: SidecarValues.Field) {
        self = switch field {
        case .rating: .rating
        case .flag: .flag
        case .colorLabel: .colorLabel
        case .keywords: .keywords
        case .creator: .creator
        case .rights: .copyright
        case .caption: .description
        case .usageTerms: .usageTerms
        case .contact: .contact
        case .title: .title
        case .altText: .altText
        case .extendedDescription: .extendedDescription
        case .jobTitle: .jobTitle
        }
    }
}

extension MetadataPreset {
    /// The fields the metadata preset editor shows, in order: its
    /// Description section, then Contact.
    public static let editorFields: (description: [DescriptiveField], contact: [DescriptiveField]) = (
        [.creator, .rights, .usageTerms, .caption],
        [.email, .phone, .url, .address, .city, .region, .postalCode, .country]
    )
}
