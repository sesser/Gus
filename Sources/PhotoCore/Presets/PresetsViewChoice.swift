/// How the Adjust tab's Presets heading shows presets: a list of names or
/// rendered thumbnails (#241). One app-wide preference, never reset; the
/// list is the default (PRD R2, R3; design §6).
public enum PresetsViewChoice: String, CaseIterable, Sendable {
    case list
    case thumbnails

    /// `UserDefaults` key. Not `adjust.presets.view`: collection headings
    /// store their disclosure under `adjust.presets.<collection name>`, so a
    /// collection named "view" would share it.
    public static let defaultsKey = "adjust.presetsView"

    /// The choice stored under `defaultsKey`: the list when nothing is
    /// stored, or the value is an unknown string or not a string at all.
    public static func choice(stored: Any?) -> PresetsViewChoice {
        (stored as? String).flatMap(PresetsViewChoice.init(rawValue:)) ?? .list
    }
}
