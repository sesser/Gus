import Foundation

/// What a name typed for a project becomes (docs/features/library-ops,
/// R2 and design §4): white space around it is dropped, an empty name is
/// refused, and the name it already has changes nothing. Two projects may
/// share a name.
public enum ProjectRename: Equatable, Sendable {
    /// Save this name.
    case rename(String)
    /// The name the project already has: nothing to save, no undo step.
    case unchanged
    /// Empty or only white space: the old name stays.
    case refused

    public static func resolve(typed: String, current: String) -> ProjectRename {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .refused }
        return name == current ? .unchanged : .rename(name)
    }
}
