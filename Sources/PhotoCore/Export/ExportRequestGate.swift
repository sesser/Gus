/// The export sheet's request, from Export to the export starting or the
/// existing-files alert (issue #163): reading the photos and counting the
/// files in the way take awaits, during which Return can be pressed again or
/// the sheet cancelled and opened on another selection.
///
/// One request at a time: `begin` refuses while one is pending or an export
/// runs, so a double Return starts one export. A request answers (shows its
/// alert, starts its export) only if `end` says it is still the pending one:
/// `cancel` drops it, so a request stopped with its sheet never answers on a
/// sheet opened after it, even if its reads finish after another began.
public struct ExportRequestGate: Sendable {
    public struct Request: Hashable, Sendable {
        let number: Int
    }

    private var pending: Request?
    private var issued = 0

    public init() {}

    /// A request is reading the photos or counting the files in the way.
    public var isPending: Bool { pending != nil }

    /// Starts a request, or nil while one is pending or an export runs.
    public mutating func begin(isExporting: Bool) -> Request? {
        guard pending == nil, !isExporting else { return nil }
        issued += 1
        let request = Request(number: issued)
        pending = request
        return request
    }

    /// Ends `request`. True when it is still the pending one, so its answer
    /// may be shown; false when it was cancelled (or has already ended).
    public mutating func end(_ request: Request) -> Bool {
        guard pending == request else { return false }
        pending = nil
        return true
    }

    /// Drops the pending request: it will never answer, and another may begin.
    public mutating func cancel() {
        pending = nil
    }
}
