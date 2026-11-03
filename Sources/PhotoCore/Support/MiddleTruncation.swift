import Foundation

/// Fits a status line such as `Export to “Exports”` into a width by
/// shortening only the name, in the middle (`Export to “Ex…ts”`): the words,
/// counts and quotation marks around it never truncate (section 5 of
/// docs/UI_REDESIGN.md).
public enum MiddleTruncation {
    public static let ellipsis = "…"

    /// `name` with `kept` of its characters, the extra one at the front:
    /// "Exports" keeping 4 is "Ex…ts".
    public static func truncate(_ name: String, keeping kept: Int) -> String {
        let characters = Array(name)
        guard kept < characters.count else { return name }
        let kept = max(kept, 0)
        let head = (kept + 1) / 2
        let tail = kept - head
        return String(characters.prefix(head)) + ellipsis + String(characters.suffix(tail))
    }

    /// The whole line, `line(name)` with the name shortened just enough that
    /// `width` of it is at most `maxWidth`. Keeps at least two characters of
    /// the name; a line that cannot fit even then comes back at that length.
    public static func fit(_ name: String, maxWidth: Double, line: (String) -> String,
                           width: (String) -> Double) -> String {
        let full = line(name)
        guard width(full) > maxWidth else { return full }
        var low = min(2, name.count)
        var high = name.count - 1
        // The longest kept count that fits; widths grow with it.
        var best = low
        while low <= high {
            let mid = (low + high) / 2
            if width(line(truncate(name, keeping: mid))) <= maxWidth {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return line(truncate(name, keeping: best))
    }
}
