import PhotoCore
import SwiftUI

/// The Rating, Flag and Sort By choices of View ▸ Filter and View ▸ Sort By.
/// The toolbar's Filter and Sort menu (plan step 5) is built from the same
/// pickers.
enum FilterMenuItems {
    static var ratingRules: [(rule: LibraryFilter.RatingRule, title: String)] {
        [(.any, String(localized: "Any Rating")), (.unrated, String(localized: "Unrated"))]
            + (1...5).map { (.atLeast(Rating(clamping: $0)), RatingText.atLeast($0)) }
    }

    static var flagRules: [(rule: LibraryFilter.FlagRule, title: String)] {
        [(.any, String(localized: "Any Flag")), (.picked, String(localized: "Picked")),
         (.notRejected, String(localized: "Not Rejected")), (.unflagged, String(localized: "Unflagged")),
         (.rejected, String(localized: "Rejected"))]
    }

    static var sortKeys: [(key: LibrarySort.Key, title: String)] {
        [(.captureDate, String(localized: "Capture Date")), (.rating, String(localized: "Rating")),
         (.fileName, String(localized: "File Name"))]
    }
}

/// The Rating section: checkmark items.
struct RatingFilterPicker: View {
    @Binding var rule: LibraryFilter.RatingRule

    var body: some View {
        Picker("Rating", selection: $rule) {
            ForEach(FilterMenuItems.ratingRules, id: \.rule) { Text($0.title).tag($0.rule) }
        }
        .pickerStyle(.inline)
    }
}

/// The Flag section: checkmark items.
struct FlagFilterPicker: View {
    @Binding var rule: LibraryFilter.FlagRule

    var body: some View {
        Picker("Flag", selection: $rule) {
            ForEach(FilterMenuItems.flagRules, id: \.rule) { Text($0.title).tag($0.rule) }
        }
        .pickerStyle(.inline)
    }
}

/// Sort By: the key, then the order.
struct SortPickers: View {
    @Binding var sort: LibrarySort

    var body: some View {
        Picker("Sort By", selection: $sort.key) {
            ForEach(FilterMenuItems.sortKeys, id: \.key) { Text($0.title).tag($0.key) }
        }
        .pickerStyle(.inline)
        .labelsHidden()
        Divider()
        Picker("Order", selection: $sort.ascending) {
            Text("Ascending").tag(true)
            Text("Descending").tag(false)
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
