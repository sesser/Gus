import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// One slim row under the grid and loupe: minimum rating, flag, search and sort
/// for whatever the sidebar has selected.
struct FilterBar: View {
    @Bindable var model: LibraryModel

    var body: some View {
        HStack(spacing: 12) {
            StarFilter(rule: $model.ratingRule)
            AppKitPopUp(items: Self.flagItems.map { AppKitPopUp.Item(title: $0.title, tag: $0.tag) },
                        selection: Self.flagItems.first { $0.rule == model.flagRule }?.tag ?? "any") { tag in
                model.flagRule = Self.flagItems.first { $0.tag == tag }?.rule ?? .any
            }
            .fixedSize()
            .help("Show photos by flag")
            SearchField(text: $model.searchText, placeholder: String(localized: "Keywords, file type, camera, lens")) {
                NotificationCenter.default.post(name: .browserShouldTakeFocus, object: model)
            }
            .frame(minWidth: 140, idealWidth: 240, maxWidth: 280)
            .help("Commas separate alternatives: “orf, arw”. Words must all match: “sony jpg”.")
            if model.isFiltered {
                Button("Clear") { model.clearFilter() }
                    .buttonStyle(.link)
                    .help("Show every photo again")
            }
            Spacer(minLength: 8)
            Text("Sort")
                .foregroundStyle(.secondary)
            AppKitPopUp(items: Self.sortItems, selection: model.sort.key.rawValue) { tag in
                if let key = LibrarySort.Key(rawValue: tag) { model.sort.key = key }
            }
            .fixedSize()
            .help("Sort order")
            Button {
                model.sort.ascending.toggle()
            } label: {
                Image(systemName: model.sort.ascending ? "arrow.up" : "arrow.down")
                    .frame(width: 14)
            }
            .buttonStyle(.borderless)
            .help(model.sort.ascending ? "Ascending" : "Descending")
        }
        .controlSize(.small)
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
    }

    // AppKit pop-ups: SwiftUI menu pickers in this bar collapsed to their arrows
    // on first layout.
    private static let flagItems: [(title: String, tag: String, rule: LibraryFilter.FlagRule)] = [
        (String(localized: "Any flag"), "any", .any),
        (String(localized: "Picked"), "picked", .picked),
        (String(localized: "Not rejected"), "notRejected", .notRejected),
        (String(localized: "Unflagged"), "unflagged", .unflagged),
        (String(localized: "Rejected"), "rejected", .rejected),
    ]

    private static let sortItems = [
        AppKitPopUp.Item(title: String(localized: "Capture Date"), tag: LibrarySort.Key.captureDate.rawValue),
        AppKitPopUp.Item(title: String(localized: "Rating"), tag: LibrarySort.Key.rating.rawValue),
        AppKitPopUp.Item(title: String(localized: "File Name"), tag: LibrarySort.Key.fileName.rawValue),
    ]
}

/// Five stars: clicking one shows photos rated at least that many, clicking
/// the highest lit one again turns the rule off.
private struct StarFilter: View {
    @Binding var rule: LibraryFilter.RatingRule

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { stars in
                Button {
                    rule = rule.clickingStar(stars)
                } label: {
                    Image(systemName: stars <= rule.litStars ? "star.fill" : "star")
                        .foregroundStyle(stars <= rule.litStars ? Color(nsColor: Palette.rating) : .secondary)
                        .frame(width: 16, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(RatingText.atLeast(stars))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Minimum rating")
    }
}

/// An AppKit search field: its own clear button, Escape clears, and Return or
/// Escape hand the keyboard back to the grid or loupe for culling.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        field.sendsWholeSearchString = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingHead
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField

        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onFinish()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                control.stringValue = ""
                parent.text = ""
                parent.onFinish()
                return true
            default:
                return false
            }
        }
    }
}
