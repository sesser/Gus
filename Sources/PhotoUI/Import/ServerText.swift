import Foundation
import PhotoCore

/// The words of the server source (issue #271, design §3.4, §4, §6, §10). No
/// sentence names a key, a URL or the server's own text; a server is named by
/// its connection's name, and a host only where the person typed it.
public enum ServerText {
    // MARK: Check results (design §3.4)

    public struct Result: Equatable {
        public var title: String
        public var detail: String
        /// Under the address (true) or under the key (false).
        public var concernsAddress: Bool
    }

    public static func result(_ check: ConnectionCheckResult, host: String, name: String) -> Result? {
        switch check {
        case .passed, .untrustedCertificate:
            return nil
        case .unreachable(let reason, let isLocal):
            var detail = String(localized: "Check the address, that the server is running, and that this Mac can reach it.",
                                comment: "Server check: unreachable, detail")
            if !reason.isEmpty { detail += " " + reason }
            if isLocal {
                detail += " " + String(localized: "If macOS asked to allow access to your local network, check System Settings ▸ Privacy & Security ▸ Local Network.",
                                       comment: "Server check: unreachable, a local host")
            }
            return Result(title: String(localized: "Can't reach “\(host)”", comment: "Server check: unreachable, title"),
                          detail: detail, concernsAddress: true)
        case .notImmich:
            return Result(title: String(localized: "This doesn't look like an Immich server", comment: "Server check: not Immich"),
                          detail: String(localized: "“\(host)” answered, but not as Immich does. Check the address, including any path or port.",
                                         comment: "Server check: not Immich, detail"),
                          concernsAddress: true)
        case .keyRejected:
            return Result(title: String(localized: "The server rejected this API key", comment: "Server check: key rejected"),
                          detail: String(localized: "The key may be mistyped, expired or deleted. Create a new key in Immich and paste it here.",
                                         comment: "Server check: key rejected, detail"),
                          concernsAddress: false)
        case .missingPermissions(let missing):
            let list = ListFormatter.localizedString(byJoining: missing)
            return Result(title: String(localized: "This API key is missing permissions", comment: "Server check: missing permissions"),
                          detail: String(localized: "Add \(list) to the key in Immich, or create a new key with the five permissions listed above.",
                                         comment: "Server check: missing permissions, detail; the argument lists them"),
                          concernsAddress: false)
        case .tooOld(let found, let needed):
            return Result(title: String(localized: "This Immich server is too old", comment: "Server check: too old"),
                          detail: String(localized: "It runs version \(found.description). Importing needs version \(needed.description) or newer.",
                                         comment: "Server check: too old, detail; both versions"),
                          concernsAddress: true)
        case .certificateChanged:
            return Result(title: String(localized: "The server's certificate has changed", comment: "Server check: certificate changed"),
                          detail: String(localized: "It is no longer the certificate you trusted for “\(name)”. That is expected if the certificate was renewed, but it can also mean that someone is intercepting the connection. Nothing was sent to the server.",
                                         comment: "Server check: certificate changed, detail"),
                          concernsAddress: true)
        case .keychain(let message):
            return Result(title: String(localized: "The key couldn't be saved", comment: "Server check: Keychain failure"),
                          detail: keychainDetail(message), concernsAddress: false)
        }
    }

    /// The system's text loses its own final period first (design §15, DQ-5).
    public static func keychainDetail(_ message: String) -> String {
        let text = RemoteKeyStoreError.inSentence(message)
        return String(localized: "The Keychain returned an error: \(text).", comment: "Keychain failure; the system's message")
    }

    /// The alert when the Keychain won't delete a server's key (design §15, DQ-5).
    public static func removalRefused(name: String, keychain message: String) -> ServerAlert {
        let text = RemoteKeyStoreError.inSentence(message)
        return ServerAlert(
            title: String(localized: "The server “\(name)” wasn't removed",
                          comment: "Alert title: the Keychain refused to delete a server's key"),
            message: String(localized: "The Keychain wouldn't delete the API key: \(text). Nothing was removed. Choose Remove Server… to try again. If it keeps failing, delete the key in Immich so it stops working.",
                            comment: "Alert message: the Keychain refused to delete a server's key; the system's text"))
    }

    // MARK: The window

    public static func connecting(_ name: String) -> String {
        String(localized: "Connecting to \(name)…", comment: "Import window: checking a server")
    }

    public static func cantConnect(_ name: String) -> String {
        String(localized: "Can't Connect to \(name)", comment: "Import window: a server's check failed")
    }

    public static func waiting(_ name: String) -> String {
        String(localized: "Waiting for “\(name)”…", comment: "Import window: a request is being tried again")
    }

    public static var allPhotos: String { String(localized: "All Photos") }

    public static func album(_ album: RemoteAlbum) -> String {
        String(localized: "\(album.name) (\(album.assetCount))", comment: "Album pop-up item: the album and the server's count")
    }

    public static func subtitle(_ subtitle: ServerSubtitle) -> String {
        switch subtitle {
        case .selectedOf(let selected, let selectable):
            String(localized: "\(selected) of \(selectable) selected")
        case .loadedOfTotal(let selected, let loaded, let total):
            String(localized: "\(selected) selected · \(loaded) of \(total) loaded",
                   comment: "Import window subtitle: a server with pages left and a known total")
        case .loaded(let selected, let loaded):
            String(localized: "\(selected) selected · \(loaded) loaded",
                   comment: "Import window subtitle: a server with pages left")
        }
    }

    public static var notEncryptedSuffix: String {
        String(localized: " · Not encrypted", comment: "Import window subtitle suffix: a plain http server")
    }

    public static func dateRangeText(_ range: CaptureDateRange?) -> String {
        guard let range, !range.isEmpty else { return String(localized: "Any date", comment: "Date Range: no range") }
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: TimeZone(secondsFromGMT: 0)!)
        let from = CaptureDateRange.utc(range.from).map { $0.formatted(style) }
        let through = CaptureDateRange.utc(range.through).map { $0.formatted(style) }
        switch (from, through) {
        case let (from?, through?):
            return String(localized: "\(from) to \(through)", comment: "A range of dates, or a certificate's validity")
        case let (from?, nil):
            return String(localized: "On or after \(from)", comment: "Date Range: only a start")
        case let (nil, through?):
            return String(localized: "On or before \(through)", comment: "Date Range: only an end")
        default:
            return String(localized: "Any date", comment: "Date Range: no range")
        }
    }

    // MARK: Activity and alerts (design §6.2, §6.3)

    public static func activityLines(_ report: RemoteImportReport, name: String) -> String {
        report.lines.map { line(for: $0, name: name) }.joined(separator: "\n")
    }

    static func line(for line: RemoteImportReport.Line, name: String) -> String {
        switch line {
        case .imported(let count):
            String(localized: "Imported \(count) photos.", comment: "Server import report: first line")
        case .nothingImported:
            String(localized: "No photos were imported.", comment: "Server import report: first line")
        case .stoppedAfter(let count):
            String(localized: "Import stopped after \(count) photos.", comment: "Server import report: stopped by the person")
        case .stopCause(let cause):
            stopTitle(cause, name: name)
        case .alreadyInLibrary(let count):
            String(localized: "\(count) were already in the library.", comment: "Server import report")
        case .liveVideosLeftOut(let count):
            String(localized: "\(count) Live Photo videos were not downloaded.", comment: "Server import report")
        case .verifiedBySizeOnly(let count):
            String(localized: "\(count) were checked by size only (photos in an Immich external library).",
                   comment: "Server import report: photos verified by byte count only (R13)")
        case .couldNotImport(let count):
            String(localized: "\(count) could not be imported.", comment: "Server import report")
        case .failure(let failure):
            failureLine(failure)
        case .more(let count):
            String(localized: "And \(count) more.")
        }
    }

    static func failureLine(_ failure: RemoteImportFailure) -> String {
        let name = failure.name
        switch failure.kind {
        case .checksumMismatch:
            return String(localized: "\(name): the download did not match the server's checksum and was discarded.",
                          comment: "Server import report: a failed photo")
        case .incomplete:
            return String(localized: "\(name): the download was incomplete and was discarded.",
                          comment: "Server import report: a failed photo")
        case .unverifiable:
            return String(localized: "\(name): the server gave no size to check the download against, so it was discarded.",
                          comment: "Server import report: an external-library photo with no size to verify")
        case .deletedOnServer:
            return String(localized: "\(name): it was deleted on the server during the import.",
                          comment: "Server import report: a failed photo")
        case .serverError(let status):
            return String(localized: "\(name): the server could not provide the original (\(String(status))).",
                          comment: "Server import report: a failed photo; the HTTP status")
        case .disk(let reason):
            return String(localized: "\(name): \(reason)", comment: "Server import report: a photo that could not be written; the system's reason")
        }
    }

    static func stopTitle(_ cause: RemoteImportStop, name: String) -> String {
        switch cause {
        case .stopped: ""
        case .unreachable: String(localized: "“\(name)” stopped responding", comment: "Server import alert title")
        case .keyRejected: String(localized: "“\(name)” rejected the API key", comment: "Server import alert title")
        case .missingPermission: String(localized: "The API key for “\(name)” is missing a permission",
                                        comment: "Server import alert title")
        case .certificateChanged: String(localized: "The certificate of “\(name)” has changed", comment: "Server import alert title")
        }
    }

    /// The one alert a server import may end with: title and message.
    public static func alert(_ result: RemoteImportResult, name: String) -> (title: String, message: String)? {
        guard RemoteImportReport(result).needsAlert else { return nil }
        let done = result.imported
        switch result.stop {
        case .unreachable?:
            return (stopTitle(.unreachable, name: name),
                    String(localized: "\(done) photos were imported before the import stopped. Photos already imported are marked, so importing again takes only the rest.",
                           comment: "Server import alert: unreachable"))
        case .keyRejected?:
            return (stopTitle(.keyRejected, name: name),
                    String(localized: "\(done) photos were imported before the import stopped. The key may have been deleted or expired. Choose Edit Server… to enter a new one.",
                           comment: "Server import alert: key rejected"))
        case .missingPermission(let permission)?:
            return (stopTitle(.missingPermission(permission), name: name),
                    String(localized: "\(done) photos were imported before the import stopped. Add \(permission) to the key in Immich, or choose Edit Server… to enter another key.",
                           comment: "Server import alert: missing permission"))
        case .certificateChanged?:
            return (stopTitle(.certificateChanged, name: name),
                    String(localized: "\(done) photos were imported before the import stopped. Nothing more was downloaded. Choose Edit Server…, then Review Certificate…, to see the new one.",
                           comment: "Server import alert: certificate changed"))
        case .stopped?, nil:
            return (String(localized: "Imported \(done) photos. \(result.failures.count) could not be imported.",
                           comment: "Server import alert title: some photos failed"),
                    String(localized: "The reasons are listed in Activity in the library window.",
                           comment: "Server import alert message"))
        }
    }
}
