/// What assistive technologies say about a photo's culling state: the parts of
/// a grid cell's or the loupe's accessibility value, and the part a culling
/// change announces. The UI turns parts into words.
public enum CullingDescription {
    public enum Part: Hashable, Sendable {
        case rating(Rating)
        case flag(Flag)
        case colorLabel(ColorLabel)
        case offline
    }

    /// Which value a culling change set.
    public enum Change: Hashable, Sendable {
        case rating, flag, colorLabel
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

    /// What to announce after a change: the new value of what changed,
    /// defaults included ("No Rating"), so every key press is confirmed.
    public static func announcement(of change: Change, rating: Rating, flag: Flag, colorLabel: ColorLabel) -> Part {
        switch change {
        case .rating: .rating(rating)
        case .flag: .flag(flag)
        case .colorLabel: .colorLabel(colorLabel)
        }
    }
}
