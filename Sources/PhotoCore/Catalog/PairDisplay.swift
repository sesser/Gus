/// Photo ▸ RAW+JPEG Pair ▸'s checkmarks (design.md I14): which file the
/// targeted pairs show. Nil when no target is a grouped pair, which dims
/// the submenu.
public struct PairDisplay: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case on, off, mixed
    }

    /// Show the RAW File.
    public var raw: State
    /// Show the JPEG or HEIC File.
    public var companion: State

    public init(raw: State, companion: State) {
        self.raw = raw
        self.companion = companion
    }

    public init?(_ targets: some Sequence<CatalogItem>) {
        var showsRaw = false
        var showsCompanion = false
        for item in targets where item.representsPair {
            if item.fileKind == .raw { showsRaw = true } else { showsCompanion = true }
            if showsRaw && showsCompanion { break }
        }
        switch (showsRaw, showsCompanion) {
        case (false, false): return nil
        case (true, false): (raw, companion) = (.on, .off)
        case (false, true): (raw, companion) = (.off, .on)
        case (true, true): (raw, companion) = (.mixed, .mixed)
        }
    }
}
