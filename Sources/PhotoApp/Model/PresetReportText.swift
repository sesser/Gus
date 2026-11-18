import Foundation
import PhotoCore

/// The words of the preset manager's Import Report page (preset-pack import
/// design §2.3, §2.4, §3). Pack, preset and unknown tool names are data from
/// the pack and never pass through here as keys.
@MainActor
enum PresetReportText {
    static let separator = " · "

    /// "3 packs · 47 presets · 52 look-up tables added", zero parts left out; the VoiceOver announcement too.
    static func summary(of result: PresetImport.Result) -> String {
        var parts: [String] = []
        if !result.packs.isEmpty { parts.append(String(localized: "\(result.packs.count) packs", comment: "Import report: packs imported")) }
        if !result.imported.isEmpty {
            parts.append(String(localized: "\(result.imported.count) presets", comment: "Import report: presets imported"))
        }
        if result.addedTables > 0 {
            parts.append(String(localized: "\(result.addedTables) look-up tables added", comment: "Import report: tables new to the library"))
        }
        guard !parts.isEmpty else { return String(localized: "Nothing was imported.") }
        return parts.joined(separator: separator)
    }

    /// "12 presets · 12 look-up tables", then "· replaced" or "· 4 replaced, 8 added" after a pack was imported before.
    static func summary(of pack: PresetImport.PackReport) -> String {
        var parts = [String(localized: "\(pack.importedCount) presets", comment: "Import report: presets imported")]
        if pack.tableCount > 0 {
            parts.append(String(localized: "\(pack.tableCount) look-up tables", comment: "Import report: tables a pack's presets use"))
        }
        if pack.replaced > 0 {
            parts.append(pack.added == 0
                ? String(localized: "replaced", comment: "Import report: every preset of the pack was already in the library")
                : String(localized: "\(pack.replaced) replaced, \(pack.added) added",
                         comment: "Import report: presets of a pack already in the library, and new ones"))
        }
        return parts.joined(separator: separator)
    }

    /// "4 mapped, 1 approximated, 2 left out", zero parts left out; "Nothing carried over" when all are zero.
    static func counts(_ preset: PresetImport.PackPresetReport) -> String {
        var parts: [String] = []
        let mapped = preset.count(.mapped), approximated = preset.count(.approximated), leftOut = preset.count(.leftOut)
        if mapped > 0 { parts.append(String(localized: "\(mapped) mapped", comment: "Import report: tools of a preset carried over")) }
        if approximated > 0 {
            parts.append(String(localized: "\(approximated) approximated", comment: "Import report: tools of a preset carried over approximately"))
        }
        if leftOut > 0 { parts.append(String(localized: "\(leftOut) left out", comment: "Import report: tools of a preset with no equivalent")) }
        return parts.isEmpty ? String(localized: "Nothing carried over") : parts.joined(separator: ", ")
    }

    static func tools(_ tools: [LuminarTool]) -> String {
        tools.map(PresetText.title).formatted(.list(type: .and))
    }

    /// "Structure (as Clarity), Matte Look (as Tone Curve and Saturation)".
    static func approximated(_ tools: [(LuminarTool, [PresetControl])]) -> String {
        tools.map { tool, controls in
            guard !controls.isEmpty else { return PresetText.title(tool) }
            let names = controls.map(PresetText.title).formatted(.list(type: .and))
            return String(localized: "\(PresetText.title(tool)) (as \(names))",
                          comment: "Import report: a tool, then the app's controls it was approximated with")
        }.formatted(.list(type: .and))
    }

    /// Identifiers as the pack gives them, separated by a comma (data, not a sentence); an empty one as "(no name)".
    static func identifiers(_ identifiers: [String]) -> String {
        identifiers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "(no name)", comment: "Import report: a tool the pack names with an empty identifier") : $0 }
            .joined(separator: ", ")
    }

    /// The name of a preset that could not be read: its name, or its place in the pack.
    static func name(_ preset: PresetImport.PackPresetReport) -> String {
        preset.name ?? String(localized: "Preset \(preset.id + 1)", comment: "Import report: a preset with no readable name, by its place in the pack")
    }

    /// The page's text, one row per line, as the debug script prints it: the header,
    /// sections, each preset's name and counts, then its status lines indented.
    static func lines(of result: PresetImport.Result) -> [String] {
        var lines = [String(localized: "Import Report"), summary(of: result)]
        if !result.failures.isEmpty {
            lines.append("# " + String(localized: "Not imported"))
            for failure in result.failures { lines.append("  \(failure.url.lastPathComponent): \(reason(failure))") }
        }
        for pack in result.packs {
            lines.append("# \(pack.name) — \(summary(of: pack))")
            for preset in pack.presets {
                if preset.isUnreadable {
                    lines.append("  \(name(preset)): " + String(localized: "Its settings can't be read."))
                    continue
                }
                lines.append("  \(preset.name ?? ""): \(counts(preset))")
                if !preset.mapped.isEmpty { lines.append("    " + String(localized: "Mapped: \(tools(preset.mapped))")) }
                if !preset.approximated.isEmpty {
                    lines.append("    " + String(localized: "Approximated: \(approximated(preset.approximated))"))
                }
                if !preset.leftOut.isEmpty { lines.append("    " + String(localized: "Left out: \(tools(preset.leftOut))")) }
                if !preset.unrecognized.isEmpty {
                    lines.append("    " + String(localized: "Not recognized: \(identifiers(preset.unrecognized))"))
                }
            }
        }
        if !result.otherPresets.imported.isEmpty {
            lines.append("# " + String(localized: "Other presets"))
            let other = LibraryModel.summary(of: result.otherPresets)
            lines.append("  \(other.title) \(other.message)")
        }
        return lines
    }

    /// Why a file was not imported.
    static func reason(_ failure: PresetImport.Failure) -> String {
        switch failure.packFailure {
        case .notAZip?, .missingConfig?: String(localized: "Not a preset pack.")
        case .damaged?: String(localized: "The file is damaged or incomplete.")
        case .unreadableSettings?: String(localized: "The pack's settings can't be read.")
        case .noPresets?: String(localized: "The pack has no presets.")
        case .tooLarge?: String(localized: "Too large to read.")
        case nil: failure.reason
        }
    }
}
