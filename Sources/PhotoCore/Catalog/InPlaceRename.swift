import Foundation

/// What a name typed in a sidebar row for a project or an album becomes
/// (docs/features/library-ops, R2 and design §4;
/// docs/features/rename-albums-in-place, R2 and design §2.4): white space
/// around it is dropped and white space inside it is kept, an empty name is
/// refused, and the name it already has changes nothing. Two projects, or
/// two albums, may share a name.
public enum InPlaceRename: Equatable, Sendable {
    /// Save this name.
    case rename(String)
    /// The name it already has: nothing to save, no undo step.
    case unchanged
    /// Empty or only white space: the old name stays.
    case refused

    public static func resolve(typed: String, current: String) -> InPlaceRename {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .refused }
        return name == current ? .unchanged : .rename(name)
    }
}
