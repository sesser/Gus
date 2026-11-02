import Foundation

/// How one sidebar source is filtered and sorted: rating, flag, search text
/// and sort order belong to each source and survive relaunches (decision 6
/// of docs/UI_REDESIGN.md). The catalog does not store them.
public struct SourceViewSettings: Hashable, Sendable, Codable {
    public var rating: LibraryFilter.RatingRule
    public var flag: LibraryFilter.FlagRule
    public var search: String
    public var sort: LibrarySort

    public init(rating: LibraryFilter.RatingRule = .any, flag: LibraryFilter.FlagRule = .any, search: String = "",
                sort: LibrarySort = LibrarySort()) {
        self.rating = rating
        self.flag = flag
        self.search = search
        self.sort = sort
    }
}

/// The settings of every source, as JSON in user defaults, keyed by a string
/// naming the source ("album:12"). A source with none gets the defaults,
/// sorted the way the last one was unless told otherwise.
public struct SourceViewSettingsStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "browser.sourceSettings") {
        self.defaults = defaults
        self.key = key
    }

    private var all: [String: SourceViewSettings] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: SourceViewSettings].self, from: data) else { return [:] }
        return decoded
    }

    /// The settings saved for `source`, or the defaults with `defaultSort`.
    public func settings(for source: String, defaultSort: LibrarySort = LibrarySort()) -> SourceViewSettings {
        all[source] ?? SourceViewSettings(sort: defaultSort)
    }

    /// Saves `settings` for `source`; the defaults are not stored.
    public func save(_ settings: SourceViewSettings, for source: String, defaultSort: LibrarySort = LibrarySort()) {
        var all = all
        all[source] = settings == SourceViewSettings(sort: defaultSort) ? nil : settings
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }

    /// Forgets a source that no longer exists.
    public func remove(_ source: String) {
        var all = all
        guard all.removeValue(forKey: source) != nil, let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }
}

extension LibraryFilter.RatingRule: Codable {
    private enum CodingKeys: String, CodingKey { case rule, stars }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stars = Rating(clamping: try container.decodeIfPresent(Int.self, forKey: .stars) ?? 0)
        switch try container.decode(String.self, forKey: .rule) {
        case "unrated": self = .unrated
        case "atLeast": self = .atLeast(stars)
        case "exactly": self = .exactly(stars)
        default: self = .any
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any: try container.encode("any", forKey: .rule)
        case .unrated: try container.encode("unrated", forKey: .rule)
        case .atLeast(let stars):
            try container.encode("atLeast", forKey: .rule)
            try container.encode(stars.rawValue, forKey: .stars)
        case .exactly(let stars):
            try container.encode("exactly", forKey: .rule)
            try container.encode(stars.rawValue, forKey: .stars)
        }
    }
}

extension LibraryFilter.FlagRule: Codable {
    private var name: String {
        switch self {
        case .any: "any"
        case .picked: "picked"
        case .rejected: "rejected"
        case .unflagged: "unflagged"
        case .notRejected: "notRejected"
        }
    }

    public init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        self = Self.allCases.first { $0.name == name } ?? .any
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

extension LibrarySort: Codable {
    private enum CodingKeys: String, CodingKey { case key, ascending }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(key: Key(rawValue: try container.decode(String.self, forKey: .key)) ?? .captureDate,
                  ascending: try container.decode(Bool.self, forKey: .ascending))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key.rawValue, forKey: .key)
        try container.encode(ascending, forKey: .ascending)
    }
}
