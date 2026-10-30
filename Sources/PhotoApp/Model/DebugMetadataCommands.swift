import Foundation
import PhotoCore

/// The debug script's commands for the Info tab's Metadata heading:
///
///     metadata <field> [<text>]   (title, caption, altText, extendedDescription, rights, usageTerms,
///                                 creator, jobTitle, address, city, region, postalCode, country,
///                                 phone, email, url; no text clears it)
///     print metadata              (the selection's values, "*" for mixed)
///     sidecars on|off             (the Settings switch for writing XMP sidecars)
///
@MainActor
enum DebugMetadataCommands {
    static func run(_ verb: String, _ arguments: [String], model: LibraryModel) async {
        if verb == "sidecars" {
            model.writesSidecars = arguments.first != "off"
            return
        }
        guard let field = arguments.first.flatMap(DescriptiveField.init(rawValue:)) else {
            print("debug-script: unknown metadata field \(arguments.first ?? "")")
            return
        }
        model.setDescriptiveField(field, to: arguments.dropFirst().joined(separator: " "),
                                  for: model.actionTargetVersionIDs)
    }

    static func printSummary(model: LibraryModel) async {
        let summary = (try? await model.catalog.descriptiveSummary(forVersions: model.actionTargetVersionIDs))
            ?? DescriptiveSummary()
        let fields = DescriptiveField.allCases.compactMap { field -> String? in
            if summary.mixed.contains(field) { return "\(field.rawValue)=*" }
            return summary.values[field].map { "\(field.rawValue)=\($0)" }
        }
        print("debug-script: metadata \(fields.joined(separator: " | "))")
    }
}
