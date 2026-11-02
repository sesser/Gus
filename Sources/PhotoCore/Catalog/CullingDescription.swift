/// What assistive technologies say about a photo's culling state: the parts of
/// a grid cell's or the loupe's accessibility value, and what a culling action
/// announces. The UI turns these into words (section 10 of
/// docs/UI_REDESIGN.md).
public enum CullingDescription {
    public enum Part: Hashable, Sendable {
        case rating(Rating)
        case flag(Flag)
        case colorLabel(ColorLabel)
        case offline
    }

    /// Which value a culling action set.
    public enum Change: Hashable, Sendable {
        case rating, flag, colorLabel
    }

    /// A photo's values after a culling action. Both files of a RAW+JPEG pair
    /// carry the same `photo`, so the pair counts once.
    public struct Result: Hashable, Sendable {
        public var photo: Int64
        public var rating: Rating
        public var flag: Flag
        public var colorLabel: ColorLabel

        public init(photo: Int64, rating: Rating, flag: Flag, colorLabel: ColorLabel) {
            self.photo = photo
            self.rating = rating
            self.flag = flag
            self.colorLabel = colorLabel
        }

        /// The id a pair's two versions share: the smaller of the two.
        public static func photo(versionID: Int64, partnerVersionID: Int64?) -> Int64 {
            min(versionID, partnerVersionID ?? versionID)
        }

        func part(_ change: Change) -> Part {
            switch change {
            case .rating: .rating(rating)
            case .flag: .flag(flag)
            case .colorLabel: .colorLabel(colorLabel)
            }
        }
    }

    public enum Announcement: Hashable, Sendable {
        /// One photo, or several photos that all ended the same; the count is
        /// said when it is above one ("Picked", "Picked, 12 photos").
        case value(Part, count: Int)
        /// Several photos raised or lowered from different ratings, so they
        /// ended differently ("Rating raised, 12 photos").
        case ratingAdjusted(raised: Bool, count: Int)
    }

    /// The parts of a photo's value in reading order ("3 stars, Picked, Red
    /// label, Offline"). Defaults are left out, so a photo nobody has culled
    /// has an empty value.
    public static func value(rating: Rating, flag: Flag, colorLabel: ColorLabel, offline: Bool) -> [Part] {
        var parts: [Part] = []
        if rating != .unrated { parts.append(.rating(rating)) }
        if flag != .none { parts.append(.flag(flag)) }
        if colorLabel != .none { parts.append(.colorLabel(colorLabel)) }
        if offline { parts.append(.offline) }
        return parts
    }

    /// The photo Advance After Rating moved to, after the action's result:
    /// its rating always ("no rating"), then what else is set.
    public static func advancedTo(rating: Rating, flag: Flag, colorLabel: ColorLabel, offline: Bool) -> [Part] {
        [.rating(rating)] + value(rating: .unrated, flag: flag, colorLabel: colorLabel, offline: offline)
    }

    /// What to announce after a culling action, from the photos it acted on.
    /// `step` is the rating change of Raise or Lower Rating, nil otherwise. A
    /// key that changed nothing is announced all the same, so every key press
    /// is confirmed. Nil only when there are no results.
    public static func announcement(of change: Change, step: Int? = nil, results: [Result]) -> Announcement? {
        var seen = Set<Int64>()
        let photos = results.filter { seen.insert($0.photo).inserted }
        guard let first = photos.first else { return nil }
        let parts = Set(photos.map { $0.part(change) })
        if parts.count == 1 || change != .rating {
            return .value(first.part(change), count: photos.count)
        }
        return .ratingAdjusted(raised: (step ?? 1) > 0, count: photos.count)
    }
}
