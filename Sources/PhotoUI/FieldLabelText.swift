import PhotoCore

/// The words for each `FieldLabel`: one set for the Info tab, Changed on Disk
/// and the metadata preset editor, sentence-style as row labels are
/// (design.md I9, P5). Menu items such as the smart album rule fields stay
/// title-style and have their own words.
public enum FieldLabelText {
    public static func text(_ label: FieldLabel) -> String {
        switch label {
        case .title: String(localized: "Title")
        case .description: String(localized: "Description", comment: "Metadata field: the photo's description (caption)")
        case .altText: String(localized: "Alt text", comment: "Metadata field: alternative text for accessibility")
        case .extendedDescription: String(localized: "Extended description", comment: "Metadata field: a longer accessibility description")
        case .copyright: String(localized: "Copyright")
        case .usageTerms: String(localized: "Usage terms")
        case .creator: String(localized: "Creator")
        case .jobTitle: String(localized: "Job title", comment: "Metadata field: the creator's job title")
        case .address: String(localized: "Address")
        case .city: String(localized: "City")
        case .stateProvince: String(localized: "State/Province")
        case .postalCode: String(localized: "Postal code")
        case .countryRegion: String(localized: "Country/Region")
        case .phone: String(localized: "Phone")
        case .email: String(localized: "Email")
        case .website: String(localized: "Website")
        case .rating: String(localized: "Rating")
        case .flag: String(localized: "Flag")
        case .colorLabel: String(localized: "Color label", comment: "Metadata field: the photo's color label")
        case .keywords: String(localized: "Keywords")
        case .contact: String(localized: "Contact")
        }
    }

    public static func text(_ field: DescriptiveField) -> String { text(FieldLabel(field)) }
}
