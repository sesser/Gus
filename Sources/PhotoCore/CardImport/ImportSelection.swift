import Foundation

/// Which shots of a card or folder a copying import includes, across scans of
/// the same source.
///
/// Scanning a source again (videos shown or hidden, Rescan, after an import)
/// keeps the person's picks: shots they left out stay out, shots new to the
/// scan come in included, and shots no longer there drop out. A new source
/// starts over with every shot that is not already in the library. Shot ids
/// are the primary file's URL, so they are stable across scans.
public enum ImportSelection {
    /// The shots left out so far, to carry into the next scan of the same
    /// source: those `remembered` from earlier scans that are not shown now
    /// (a video hidden for a while), plus every shown shot the person
    /// unchecked. Shots already in the library are never counted as left out:
    /// they were not the person's choice.
    public static func leftOut(remembered: Set<URL>, shown: [SourceShot], selection: Set<URL>) -> Set<URL> {
        let shownIDs = Set(shown.map(\.id))
        let unchecked = shown.filter { !$0.isDuplicate && !selection.contains($0.id) }.map(\.id)
        return remembered.subtracting(shownIDs).union(unchecked)
    }

    /// The selection after a scan: every shot not already in the library and
    /// not left out. Pass an empty `leftOut` for a new source.
    public static func selection(for shots: [SourceShot], leftOut: Set<URL>) -> Set<URL> {
        Set(shots.filter { !$0.isDuplicate && !leftOut.contains($0.id) }.map(\.id))
    }
}
