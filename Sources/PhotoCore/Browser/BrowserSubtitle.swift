/// The library window's subtitle (section 1 of docs/UI_REDESIGN.md); the UI
/// puts it into words.
public enum BrowserSubtitle: Hashable, Sendable {
    /// "4,623 photos".
    case photos(Int)
    /// "12 selected of 4,623", with " · Filtered" when `filtered`.
    case selected(Int, of: Int, filtered: Bool)
    /// "87 of 4,623 · Filtered".
    case filtered(Int, of: Int)
    /// The loupe: "All Photos", or "All Photos · Filtered" (the position is
    /// in the caption).
    case source(filtered: Bool)

    /// The grid's subtitle: `shown` photos pass the filter out of `total` in
    /// the source (nil until counted), `selected` are selected.
    public static func grid(shown: Int, total: Int?, selected: Int, isFiltered: Bool) -> BrowserSubtitle {
        if selected > 1 { return .selected(selected, of: shown, filtered: isFiltered) }
        if isFiltered { return .filtered(shown, of: max(total ?? shown, shown)) }
        return .photos(shown)
    }

    /// The loupe's: the source's name, and whether a filter is on.
    public static func loupe(isFiltered: Bool) -> BrowserSubtitle {
        .source(filtered: isFiltered)
    }
}
