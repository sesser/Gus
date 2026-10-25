import PhotoCore
import SwiftUI

/// Review of what another app changed in the selected photos' sidecars or
/// files: the library's values against the file's, field by field.
struct DiskChangeSection: View {
    let model: LibraryModel
    let changes: [DiskChange]
    @State private var useFile: Set<SidecarValues.Field> = []
    @State private var mergeKeywords = true

    /// The fields any of the changes touch, in display order.
    private var fields: [SidecarValues.Field] {
        let touched = Set(changes.flatMap(\.changedFields))
        return SidecarValues.Field.allCases.filter(touched.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Changed on Disk", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let first = changes.first {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("")
                        Text("Library").font(.caption.weight(.semibold))
                        Text("File").font(.caption.weight(.semibold))
                    }
                    ForEach(fields, id: \.self) { field in
                        GridRow {
                            Toggle(DiskChangeText.field(field), isOn: Binding(
                                get: { useFile.contains(field) },
                                set: { if $0 { useFile.insert(field) } else { useFile.remove(field) } }))
                                .toggleStyle(.checkbox)
                                .help("Take this value from the file")
                            Text(DiskChangeText.value(field, first.library))
                                .foregroundStyle(useFile.contains(field) ? .secondary : .primary)
                            Text(DiskChangeText.value(field, first.disk))
                                .foregroundStyle(useFile.contains(field) ? .primary : .secondary)
                        }
                        .font(.caption)
                    }
                }
                if fields.contains(.keywords) {
                    Toggle("Keep the keywords from both", isOn: $mergeKeywords)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .disabled(useFile.contains(.keywords))
                }
            }
            HStack {
                AppKitButton(title: String(localized: "Keep Library Values"),
                             help: String(localized: "Write the library's values to the file")) {
                    model.resolveDiskChanges(changes, with: .keepLibrary)
                }
                AppKitButton(title: String(localized: "Use File Values"),
                             help: String(localized: "Take every value from the file")) {
                    model.resolveDiskChanges(changes, with: .useFile)
                }
            }
            AppKitButton(title: String(localized: "Apply Choices"),
                         help: String(localized: "Take the checked values from the file and keep the others"),
                         isEnabled: !useFile.isEmpty || (mergeKeywords && fields.contains(.keywords))) {
                model.resolveDiskChanges(changes, with: .fields(useFile, mergeKeywords: mergeKeywords && !useFile.contains(.keywords)))
            }
        }
        .onChange(of: changes.map(\.imageID)) {
            useFile = []
            mergeKeywords = true
        }
    }

    private var summary: String {
        let first = changes[0]
        switch (changes.count, first.source) {
        case (1, .sidecar): return String(localized: "Another app changed the sidecar of \(first.fileName).")
        case (1, .embedded): return String(localized: "Another app changed the metadata inside \(first.fileName). The original is not written; keeping the library's values only updates the sidecar.")
        default: return String(localized: "Another app changed the sidecars or files of \(changes.count) selected photos. The values shown are the first photo's; your choice applies to all of them.")
        }
    }
}

enum DiskChangeText {
    static func field(_ field: SidecarValues.Field) -> String {
        switch field {
        case .rating: String(localized: "Rating")
        case .flag: String(localized: "Flag")
        case .colorLabel: String(localized: "Color Label")
        case .keywords: String(localized: "Keywords")
        case .creator: String(localized: "Creator")
        case .rights: String(localized: "Copyright")
        case .caption: String(localized: "Caption")
        case .usageTerms: String(localized: "Usage Terms")
        case .contact: String(localized: "Contact")
        }
    }

    static func value(_ field: SidecarValues.Field, _ values: SidecarValues) -> String {
        let none = String(localized: "None", comment: "No value in a metadata comparison")
        switch field {
        case .rating:
            return values.rating == .unrated ? none : RatingText.stars(values.rating.rawValue)
        case .flag:
            switch values.flag {
            case .picked: return String(localized: "Picked")
            case .rejected: return String(localized: "Rejected")
            case .none: return none
            }
        case .colorLabel:
            return values.colorLabel == .none ? none : ColorLabelText.name(values.colorLabel)
        case .keywords:
            return values.keywords.isEmpty ? none : values.keywords.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .joined(separator: ", ")
        case .creator: return values.creator ?? none
        case .rights: return values.rights ?? none
        case .caption: return values.caption ?? none
        case .usageTerms: return values.usageTerms ?? none
        case .contact:
            guard let contact = values.contact else { return none }
            return [contact.email, contact.phone, contact.url, contact.city, contact.country].compactMap { $0 }
                .joined(separator: ", ")
        }
    }
}
