import PhotoCore

/// The library window's title and subtitle (section 1 of docs/UI_REDESIGN.md).
extension LibraryModel {
    /// The source in the grid, the file name in the loupe.
    var windowTitle: String {
        if mode == .loupe, let item = focusedItem { return item.fileName }
        return title(for: sidebarSelection)
    }

    /// "4,623 photos", "12 selected of 4,623", "87 of 4,623 · Filtered",
    /// "5 selected of 87 · Filtered"; in the loupe "All Photos" or "All Photos
    /// · Filtered" (the position is in the caption); while comparing
    /// "Comparing · All Photos".
    var windowSubtitle: String {
        let shown = itemCount
        let filtered = String(localized: "Filtered", comment: "Window subtitle: a filter hides some photos")
        let kind = mode == .loupe
            ? BrowserSubtitle.loupe(isFiltered: isFiltered, isComparing: isComparing)
            : BrowserSubtitle.grid(shown: shown, total: sourceTotal, selected: selection.count,
                                   isFiltered: isFiltered)
        return switch kind {
        case .photos(let count):
            String(localized: "\(count) photos")
        case .selected(let count, let total, let isFiltered):
            [String(localized: "\(count) selected of \(total)", comment: "Window subtitle"), isFiltered ? filtered : nil]
                .compactMap { $0 }.joined(separator: " · ")
        case .filtered(let count, let total):
            [String(localized: "\(count) of \(total)"), filtered].joined(separator: " · ")
        case .source(let isFiltered):
            [title(for: sidebarSelection), isFiltered ? filtered : nil].compactMap { $0 }.joined(separator: " · ")
        case .comparing(let isFiltered):
            [String(localized: "Comparing · \(title(for: sidebarSelection))",
                    comment: "Window subtitle while comparing two photos; the source's name"),
             isFiltered ? filtered : nil].compactMap { $0 }.joined(separator: " · ")
        }
    }
}
