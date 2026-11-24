import Foundation
import Testing
@testable import PhotoCore

/// Issue #271, design §3 to §6: the rules behind the Server sheet, the grid's
/// states, paging, the subtitle, the project name and the Activity report.
@Suite("Immich browse rules")
struct RemoteBrowseRulesTests {
    @Test("The grid area's state for a server (design §4.7)")
    func gridStates() {
        func state(connecting: Bool = false, failure: ConnectionCheckResult? = nil, loading: Bool = false,
                   gone: Bool = false, count: Int = 0, album: Bool = false, range: Bool = false) -> ServerGridState {
            ServerGridState.of(connecting: connecting, failure: failure, loadingFirstPage: loading, albumGone: gone,
                               photoCount: count, inAlbum: album, hasRange: range)
        }
        #expect(state(connecting: true) == .connecting)
        #expect(state(failure: .keyRejected) == .cantConnect(.keyRejected))
        #expect(state(loading: true) == .loading)
        #expect(state(count: 3, album: true) == .photos)
        #expect(state(gone: true, album: true) == .albumGone)
        #expect(state() == .noPhotosAll)
        #expect(state(album: true) == .noPhotosInAlbum)
        #expect(state(album: true, range: true) == .noPhotosInRange)
    }

    @Test("The next page is due within one screen of the last loaded photo, never earlier (D10, AC6)")
    func paging() {
        #expect(!RemotePaging.isNextPageDue(visibleMaxY: 800, viewportHeight: 800, lastItemMaxY: 8000))
        #expect(!RemotePaging.isNextPageDue(visibleMaxY: 7199, viewportHeight: 800, lastItemMaxY: 8000))
        #expect(RemotePaging.isNextPageDue(visibleMaxY: 7200, viewportHeight: 800, lastItemMaxY: 8000))
        #expect(RemotePaging.isNextPageDue(visibleMaxY: 8000, viewportHeight: 800, lastItemMaxY: 8000))
    }

    @Test("The subtitle says how many are selected and loaded (design §4.6)")
    func subtitle() {
        #expect(ServerSubtitle.of(selected: 6, loaded: 380, marked: 0, hasMorePages: false, total: nil)
            == .selectedOf(selected: 6, selectable: 380))
        #expect(ServerSubtitle.of(selected: 6, loaded: 380, marked: 10, hasMorePages: false, total: 400)
            == .selectedOf(selected: 6, selectable: 370))
        #expect(ServerSubtitle.of(selected: 6, loaded: 250, marked: 0, hasMorePages: true, total: 3412)
            == .loadedOfTotal(selected: 6, loaded: 250, total: 3412))
        #expect(ServerSubtitle.of(selected: 6, loaded: 250, marked: 0, hasMorePages: true, total: nil)
            == .loaded(selected: 6, loaded: 250))
    }

    @Test("The sheet's address field, name and buttons (design §3.2, §3.3, AC3)")
    func form() throws {
        #expect(ServerFormRules.addressState("") == .empty)
        #expect(ServerFormRules.addressState("ftp://x") == .unsupportedScheme)
        #expect(ServerFormRules.addressState("http://example.com") == .refused(host: "example.com"))
        #expect(ServerFormRules.addressState("http://8.8.8.8") == .refused(host: "8.8.8.8"))
        guard case .unencryptedLocal = ServerFormRules.addressState("http://nas.local:2283") else {
            Issue.record("a .local name is local")
            return
        }
        let https = ServerFormRules.addressState("photos.example.com")
        guard case .encrypted(let address) = https else {
            Issue.record("no scheme means https")
            return
        }
        #expect(ServerFormRules.effectiveName("  ", address: address) == "photos.example.com")
        #expect(ServerFormRules.effectiveName(" Home ", address: address) == "Home")
        #expect(ServerFormRules.nameTaken("home", among: ["Home", "Other"]))
        #expect(!ServerFormRules.nameTaken("Home 2", among: ["Home"]))
        let local = ServerFormRules.addressState("http://192.168.1.5")
        // Add needs the key and, for http, the ticked box.
        #expect(ServerFormRules.canSubmit(address: https, keyEntered: true, unencryptedConfirmed: false, nameTaken: false,
                                          isEdit: false, changed: true))
        #expect(!ServerFormRules.canSubmit(address: https, keyEntered: false, unencryptedConfirmed: false, nameTaken: false,
                                           isEdit: false, changed: true))
        #expect(!ServerFormRules.canSubmit(address: local, keyEntered: true, unencryptedConfirmed: false, nameTaken: false,
                                           isEdit: false, changed: true))
        #expect(ServerFormRules.canSubmit(address: local, keyEntered: true, unencryptedConfirmed: true, nameTaken: false,
                                          isEdit: false, changed: true))
        #expect(!ServerFormRules.canSubmit(address: https, keyEntered: true, unencryptedConfirmed: false, nameTaken: true,
                                           isEdit: false, changed: true))
        #expect(!ServerFormRules.canSubmit(address: ServerFormRules.addressState("http://example.com"), keyEntered: true,
                                           unencryptedConfirmed: true, nameTaken: false, isEdit: false, changed: true))
        // Save needs a change; an empty key keeps the stored one.
        #expect(ServerFormRules.canSubmit(address: https, keyEntered: false, unencryptedConfirmed: false, nameTaken: false,
                                          isEdit: true, changed: true))
        #expect(!ServerFormRules.canSubmit(address: https, keyEntered: false, unencryptedConfirmed: false, nameTaken: false,
                                           isEdit: true, changed: false))
        #expect(!ServerFormRules.needsCheck(isEdit: true, addressChanged: false, keyEntered: false))
        #expect(ServerFormRules.needsCheck(isEdit: true, addressChanged: true, keyEntered: false))
        #expect(ServerFormRules.needsCheck(isEdit: false, addressChanged: false, keyEntered: true))
    }

    @Test("The project name starts as ‹connection› - ‹scope› (Q6)")
    func projectName() {
        #expect(RemoteProjectName.prefill(connection: "Home Server", scope: "All Photos") == "Home Server - All Photos")
    }

    @Test("The Activity report: order, no zero lines, the ten-line cap, the alert rule (design §6.2, AC14)")
    func report() {
        var result = RemoteImportResult(nextCounter: 1)
        result.imported = 46
        #expect(RemoteImportReport(result).lines == [.imported(46)])
        #expect(!RemoteImportReport(result).needsAlert && !RemoteImportReport(result).isWarning)
        result.alreadyInLibrary = 3
        result.liveVideosLeftOut = 2
        result.verifiedBySizeOnly = 5
        result.failures = (1...12).map { RemoteImportFailure(name: "IMG_\($0).HEIC", kind: .deletedOnServer) }
        let report = RemoteImportReport(result)
        #expect(Array(report.lines.prefix(5)) == [.imported(46), .alreadyInLibrary(3), .liveVideosLeftOut(2),
                                                  .verifiedBySizeOnly(5), .couldNotImport(12)])
        #expect(report.lines.filter { if case .failure = $0 { true } else { false } }.count == 10)
        #expect(report.lines.last == .more(2))
        #expect(report.needsAlert && report.isWarning)

        var stopped = RemoteImportResult(nextCounter: 1)
        stopped.imported = 12
        stopped.stop = .stopped
        #expect(RemoteImportReport(stopped).lines == [.stoppedAfter(12)])
        #expect(!RemoteImportReport(stopped).needsAlert && !RemoteImportReport(stopped).isWarning)

        var failed = RemoteImportResult(nextCounter: 1)
        failed.stop = .keyRejected
        #expect(RemoteImportReport(failed).lines == [.nothingImported, .stopCause(.keyRejected)])
        #expect(RemoteImportReport(failed).needsAlert && RemoteImportReport(failed).isWarning)
    }

    @Test("Remote assets stand in the grid as one-file shots keyed by a URL of their own")
    func gridURLs() {
        let asset = RemoteAsset(id: "abc-123", fileName: "IMG 1.HEIC", checksum: "x", byteCount: 10,
                                metadata: ImageMetadata(), modifiedAt: Date(), isEdited: true)
        let shot = asset.shot(linked: true)
        #expect(shot.files.count == 1 && shot.isDuplicate)
        #expect(shot.primary.name == "IMG 1.HEIC")
        #expect(shot.primary.kind == .heic)
        #expect(RemoteAssetURL.assetID(of: shot.id) == "abc-123")
        #expect(RemoteAssetURL.isRemote(shot.id))
        #expect(!RemoteAssetURL.isRemote(URL(fileURLWithPath: "/tmp/a.jpg")))
    }

    @Test("A date range's bounds are whole days; a reversed one is refused (R10b)")
    func dateRange() {
        let range = CaptureDateRange(from: DateComponents(year: 2026, month: 11, day: 1),
                                     through: DateComponents(year: 2026, month: 11, day: 30))
        let bounds = range.bounds
        #expect(bounds.start == Date(timeIntervalSince1970: 1_793_491_200))
        #expect(bounds.endExclusive == Date(timeIntervalSince1970: 1_793_491_200 + 30 * 86_400))
        #expect(!range.isReversed)
        #expect(CaptureDateRange(from: range.through, through: range.from).isReversed)
        #expect(CaptureDateRange(from: nil, through: nil).isEmpty)
        #expect(CaptureDateRange(from: nil, through: range.through).bounds.start == nil)
    }
}
