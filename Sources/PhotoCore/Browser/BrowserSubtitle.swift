/// The library window's subtitle (section 1 of docs/UI_REDESIGN.md); the UI
/// puts it into words.
public enum BrowserSubtitle: Hashable, Sendable {
    /// "4,623 photos".
    case photos(Int)
    /// "12 selected of 4,623", with " · Filtered" when `filtered`.
    case selected(Int, of: Int, filtered: Bool)
    /// "87 of 4,623 · Filtered".
    case filtered(Int, of: Int)
    /// The loupe: "All Photos · 12 of 87" (the source's name, the position).
    case position(Int, of: Int)

    /// The grid's subtitle: `shown` photos pass the filter out of `total` in
    /// the source (nil until counted), `selected` are selected.
    public static func grid(shown: Int, total: Int?, selected: Int, isFiltered: Bool) -> BrowserSubtitle {
        if selected > 1 { return .selected(selected, of: shown, filtered: isFiltered) }
        if isFiltered { return .filtered(shown, of: max(total ?? shown, shown)) }
        return .photos(shown)
    }

    /// The loupe's: the photo's position (0-based `index`) among `shown`.
    public static func loupe(index: Int, shown: Int) -> BrowserSubtitle {
        .position(index + 1, of: shown)
    }
}
