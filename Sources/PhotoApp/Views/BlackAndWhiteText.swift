import PhotoCore

/// The Black & White heading's words (docs/features/bw-module/design.md §7, §13).
enum BlackAndWhiteText {
    static let title = String(localized: "Black & White",
                              comment: "Adjust tab heading and group: turns the photo to gray by a mix of colored filters; also the Adjust ▸ Black & White submenu and undo names (Turn On Black & White)")

    /// The undo and History name of every filter change: a slider, a typed
    /// value, a quick-set, No Filter (design §9).
    static let filterChange = String(localized: "Black & White Filter", comment: "Undo action name")

    /// The segment and slider label.
    static func name(_ filter: BlackAndWhite.Filter) -> String {
        let comment: StaticString = "Black & White filter names, as colored filters on a camera lens; Red, Green and Blue have their own keys because they are also Tone Curve channel names"
        return switch filter {
        case .yellow: String(localized: "blackAndWhite.filter.yellow", defaultValue: "Yellow", comment: comment)
        case .orange: String(localized: "blackAndWhite.filter.orange", defaultValue: "Orange", comment: comment)
        case .red: String(localized: "blackAndWhite.filter.red", defaultValue: "Red", comment: comment)
        case .green: String(localized: "blackAndWhite.filter.green", defaultValue: "Green", comment: comment)
        case .blue: String(localized: "blackAndWhite.filter.blue", defaultValue: "Blue", comment: comment)
        }
    }

    /// VoiceOver's name of the slider row: "Red" alone is also a Tone Curve channel.
    static func accessibilityName(_ filter: BlackAndWhite.Filter) -> String {
        switch filter {
        case .yellow: String(localized: "Yellow filter", comment: "VoiceOver name of the Black & White Yellow slider")
        case .orange: String(localized: "Orange filter", comment: "VoiceOver name of the Black & White Orange slider")
        case .red: String(localized: "Red filter", comment: "VoiceOver name of the Black & White Red slider")
        case .green: String(localized: "Green filter", comment: "VoiceOver name of the Black & White Green slider")
        case .blue: String(localized: "Blue filter", comment: "VoiceOver name of the Black & White Blue slider")
        }
    }

    /// VoiceOver's name of the slider's value field.
    static func fieldAccessibilityName(_ filter: BlackAndWhite.Filter) -> String {
        switch filter {
        case .yellow: String(localized: "Yellow filter value", comment: "VoiceOver name of the Black & White Yellow field")
        case .orange: String(localized: "Orange filter value", comment: "VoiceOver name of the Black & White Orange field")
        case .red: String(localized: "Red filter value", comment: "VoiceOver name of the Black & White Red field")
        case .green: String(localized: "Green filter value", comment: "VoiceOver name of the Black & White Green field")
        case .blue: String(localized: "Blue filter value", comment: "VoiceOver name of the Black & White Blue field")
        }
    }

    /// The tooltip of the segment, and the tooltip and VoiceOver help of the
    /// slider row (design §7): one whole sentence each, so translators can
    /// reorder them.
    static func help(_ filter: BlackAndWhite.Filter) -> String {
        switch filter {
        case .yellow: String(localized: "Yellow filter: slightly darker skies, lighter yellows and skin.",
                             comment: "What a yellow filter does to a black and white photo")
        case .orange: String(localized: "Orange filter: darker skies, lighter skin and warm tones.",
                             comment: "What an orange filter does to a black and white photo")
        case .red: String(localized: "Red filter: much darker skies, lighter reds and skin, darker leaves.",
                          comment: "What a red filter does to a black and white photo")
        case .green: String(localized: "Green filter: lighter leaves and grass, darker reds and skin.",
                            comment: "What a green filter does to a black and white photo")
        case .blue: String(localized: "Blue filter: lighter skies and haze, darker reds and skin.",
                           comment: "What a blue filter does to a black and white photo")
        }
    }

    /// Adjust ▸ Black & White ▸ items (design §8).
    static func menuItem(_ filter: BlackAndWhite.Filter) -> String {
        switch filter {
        case .yellow: String(localized: "Yellow Filter", comment: "Adjust ▸ Black & White menu item; choose one filter alone")
        case .orange: String(localized: "Orange Filter", comment: "Adjust ▸ Black & White menu item; choose one filter alone")
        case .red: String(localized: "Red Filter", comment: "Adjust ▸ Black & White menu item; choose one filter alone")
        case .green: String(localized: "Green Filter", comment: "Adjust ▸ Black & White menu item; choose one filter alone")
        case .blue: String(localized: "Blue Filter", comment: "Adjust ▸ Black & White menu item; choose one filter alone")
        }
    }

    static let noFilter = String(localized: "No Filter", comment: "Adjust ▸ Black & White menu item: all five filters at 0")

    /// The menu item that is the heading's check box; its title follows the
    /// state, and is the undo name of the change (design §8, §9).
    static func turn(on: Bool) -> String {
        on ? String(localized: "Turn On \(title)", comment: "Undo action name; the group's name")
            : String(localized: "Turn Off \(title)", comment: "Undo action name; the group's name")
    }

    /// VoiceOver's name of the quick-set control.
    static let quickSetName = String(localized: "blackAndWhite.quickSet", defaultValue: "Filter",
                                     comment: "VoiceOver name of the Black & White segmented control: the five quick filters")

    static let caption = String(localized: "Each filter lightens colors like itself and darkens the opposite ones. Color Grading can tint the result.",
                                comment: "Black & White heading caption; “Color Grading” is the heading's name below")

    static let monochromeCaption = String(localized: "This photo has no color, so the filters change nothing.",
                                          comment: "Black & White caption when the photo's file is already monochrome")
}
