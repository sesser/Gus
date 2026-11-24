import Foundation

/// The grid area of the import window for a server source (design §4.7).
/// The card and folder states stay `ImportGridState`'s.
public enum ServerGridState: Equatable, Sendable {
    /// "Connecting to ‹name›…".
    case connecting
    /// "Can't Connect to ‹name›" with the check's result.
    case cantConnect(ConnectionCheckResult)
    /// "Reading ‹name›…" until the first page lands.
    case loading
    case noPhotosAll
    case noPhotosInAlbum
    case noPhotosInRange
    case albumGone
    case photos

    public static func of(connecting: Bool, failure: ConnectionCheckResult?, loadingFirstPage: Bool, albumGone: Bool,
                          photoCount: Int, inAlbum: Bool, hasRange: Bool) -> ServerGridState {
        if connecting { return .connecting }
        if let failure { return .cantConnect(failure) }
        if albumGone { return .albumGone }
        if photoCount > 0 { return .photos }
        if loadingFirstPage { return .loading }
        if hasRange { return .noPhotosInRange }
        return inAlbum ? .noPhotosInAlbum : .noPhotosAll
    }
}

/// When the next page is asked for (design §4.4, D10): once the visible
/// area's bottom comes within one screen height of the last loaded photo.
public enum RemotePaging {
    public static func isNextPageDue(visibleMaxY: Double, viewportHeight: Double, lastItemMaxY: Double) -> Bool {
        visibleMaxY >= lastItemMaxY - viewportHeight
    }
}

/// The import window's subtitle for a server source (design §4.6).
public enum ServerSubtitle: Equatable, Sendable {
    /// "6 of 380 selected": everything is loaded.
    case selectedOf(selected: Int, selectable: Int)
    /// "6 selected · 250 of 3,412 loaded".
    case loadedOfTotal(selected: Int, loaded: Int, total: Int)
    /// "6 selected · 250 loaded".
    case loaded(selected: Int, loaded: Int)

    /// `total` is the number the server gave: an album's count (which may
    /// include videos, R10), nil for All Photos, which has none. Never
    /// estimated.
    public static func of(selected: Int, loaded: Int, marked: Int, hasMorePages: Bool, total: Int?) -> ServerSubtitle {
        guard hasMorePages else { return .selectedOf(selected: selected, selectable: loaded - marked) }
        if let total { return .loadedOfTotal(selected: selected, loaded: loaded, total: total) }
        return .loaded(selected: selected, loaded: loaded)
    }
}

/// The Server sheet's rules (design §3.2, §3.3): what the address field says
/// and when Add or Save is enabled.
public struct ServerFormRules: Equatable, Sendable {
    public enum AddressState: Equatable, Sendable {
        case empty
        case unsupportedScheme
        case invalid
        /// https: fine.
        case encrypted(ServerAddress)
        /// http to a local host: the notice and its check box.
        case unencryptedLocal(ServerAddress)
        /// http to another host: refused.
        case refused(host: String)
    }

    public static func addressState(_ text: String) -> AddressState {
        switch ServerAddress.parse(text) {
        case .failure(.empty): return .empty
        case .failure(.unsupportedScheme): return .unsupportedScheme
        case .failure(.invalid): return .invalid
        case .success(let address):
            switch TransportPolicy.of(address) {
            case .encrypted: return .encrypted(address)
            case .unencryptedLocal: return .unencryptedLocal(address)
            case .refused(let host): return .refused(host: host)
            }
        }
    }

    /// The name the server is saved under: the typed one, else the host.
    public static func effectiveName(_ typed: String, address: ServerAddress?) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (address?.host ?? "") : trimmed
    }

    /// Names are unique among servers, compared without regard to case.
    public static func nameTaken(_ name: String, among others: [String]) -> Bool {
        others.contains { $0.compare(name, options: [.caseInsensitive]) == .orderedSame }
    }

    /// Add: a valid address (confirmed when it is http), a key, a free name.
    /// Edit: the same, except an empty key keeps the stored one, and
    /// something must have changed; a certificate trusted on the certificate
    /// page and not yet saved is a change (design review B1).
    public static func canSubmit(address: AddressState, keyEntered: Bool, unencryptedConfirmed: Bool, nameTaken: Bool,
                                 isEdit: Bool, changed: Bool, trustedPending: Bool = false) -> Bool {
        guard !nameTaken else { return false }
        switch address {
        case .encrypted: break
        case .unencryptedLocal: guard unencryptedConfirmed else { return false }
        default: return false
        }
        return isEdit ? changed || trustedPending : keyEntered
    }

    /// A certificate trusted on the certificate page and not saved yet, with
    /// the address it was trusted for.
    public struct TrustedCertificate: Equatable, Sendable {
        public var fingerprint: CertificateFingerprint
        public var trustedAt: Date
        public var address: String

        public init(fingerprint: CertificateFingerprint, trustedAt: Date, address: String) {
            self.fingerprint = fingerprint
            self.trustedAt = trustedAt
            self.address = address
        }
    }

    /// The pin a check uses and a save stores (design §3.6, design review
    /// N-3): a certificate trusted for this very address; else the saved
    /// connection's, while its address is unchanged; else none.
    public static func pin(trusted: TrustedCertificate?, address: String, existing: RemoteServiceRecord?)
        -> (fingerprint: CertificateFingerprint, trustedAt: Date?)? {
        if let trusted, trusted.address == address { return (trusted.fingerprint, trusted.trustedAt) }
        if let existing, existing.address == address, let pinned = existing.pinnedFingerprint {
            return (pinned, existing.certificateTrustedAt)
        }
        return nil
    }

    /// Whether Save must check the server again: the address or the key
    /// changed, or a certificate was trusted and its pin is not saved yet (the
    /// check confirms it, then saves it; B1). A name-only edit saves without
    /// a check (design §3.3).
    public static func needsCheck(isEdit: Bool, addressChanged: Bool, keyEntered: Bool, trustedPending: Bool = false) -> Bool {
        !isEdit || addressChanged || keyEntered || trustedPending
    }
}

/// The Server sheet's height (design §3.1, design review S2): about 380 pt
/// for the form, 90 more with the unencrypted notice, 60 more with a result
/// under a field; the certificate page its own; never taller than the window
/// less 40 pt nor shorter than `minimum`. The form scrolls inside it when
/// clamped.
public enum ServerSheetHeight {
    public static let minimum: Double = 300
    public static let form: Double = 380
    public static let notice: Double = 90
    public static let result: Double = 60
    public static let certificate: Double = 470
    public static let changedCertificate: Double = 540

    public static func ideal(certificatePage: Bool, changed: Bool, notice: Bool, result: Bool,
                             windowHeight: Double?) -> Double {
        let content = certificatePage ? (changed ? changedCertificate : certificate)
            : form + (notice ? Self.notice : 0) + (result ? Self.result : 0)
        guard let windowHeight, windowHeight > 0 else { return content }
        return max(minimum, min(content, windowHeight - 40))
    }
}

/// The project name a server import starts with (design §5.3, Q6):
/// "‹connection name› - ‹scope›".
public enum RemoteProjectName {
    public static func prefill(connection: String, scope: String) -> String {
        "\(connection) - \(scope)"
    }
}

/// What a finished server import says in Activity (design §6.2), as lines the
/// UI puts into words, in order; a count line only when its count is not
/// zero. At most `failureListLimit` failures are listed, then "And ‹n› more."
public struct RemoteImportReport: Equatable, Sendable {
    public static let failureListLimit = ExportActivityReport.failureListLimit

    public enum Line: Equatable, Sendable {
        case imported(Int)
        case nothingImported
        case stoppedAfter(Int)
        /// Why the job stopped early (the alert's title, §6.3).
        case stopCause(RemoteImportStop)
        case alreadyInLibrary(Int)
        case liveVideosLeftOut(Int)
        /// Imported after a size check only (R13, R19).
        case verifiedBySizeOnly(Int)
        case couldNotImport(Int)
        case failure(RemoteImportFailure)
        case more(Int)
    }

    public var lines: [Line]
    /// A warning row when anything failed or a failure stopped the job.
    public var isWarning: Bool
    /// One alert on the import window (§6.2, §6.3): not for a clean finish or
    /// a person's Stop.
    public var needsAlert: Bool

    public init(_ result: RemoteImportResult) {
        var lines: [Line] = []
        switch result.stop {
        case .stopped?:
            lines.append(.stoppedAfter(result.imported))
        case let cause?:
            lines.append(result.imported > 0 ? .imported(result.imported) : .nothingImported)
            lines.append(.stopCause(cause))
        case nil:
            lines.append(result.imported > 0 ? .imported(result.imported) : .nothingImported)
        }
        if result.alreadyInLibrary > 0 { lines.append(.alreadyInLibrary(result.alreadyInLibrary)) }
        if result.liveVideosLeftOut > 0 { lines.append(.liveVideosLeftOut(result.liveVideosLeftOut)) }
        if result.verifiedBySizeOnly > 0 { lines.append(.verifiedBySizeOnly(result.verifiedBySizeOnly)) }
        if !result.failures.isEmpty {
            lines.append(.couldNotImport(result.failures.count))
            lines += result.failures.prefix(Self.failureListLimit).map(Line.failure)
            if result.failures.count > Self.failureListLimit {
                lines.append(.more(result.failures.count - Self.failureListLimit))
            }
        }
        self.lines = lines
        let stoppedByFailure = result.stop != nil && result.stop != .stopped
        isWarning = !result.failures.isEmpty || stoppedByFailure
        needsAlert = stoppedByFailure || (result.stop == nil && !result.failures.isEmpty)
    }
}
