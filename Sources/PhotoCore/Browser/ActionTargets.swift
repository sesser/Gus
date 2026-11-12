import Foundation

/// What a command acts on in the library window: the selection in the grid,
/// the photo on screen in the loupe. While two photos are compared the loupe
/// rule holds: the selection is the two photos, but the focus is the active
/// one and only it is acted on (side-by-side-comparison R3).
public enum ActionTargets {
    public static func indices(isLoupe: Bool, selection: IndexSet, focus: Int?) -> IndexSet {
        if isLoupe || selection.isEmpty {
            return focus.map { IndexSet(integer: $0) } ?? []
        }
        return selection
    }
}
