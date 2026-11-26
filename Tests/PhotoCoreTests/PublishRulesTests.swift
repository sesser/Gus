import Foundation
import Testing
@testable import PhotoCore

/// Issue #28: the rules for an original (R11 to R13, R15, design §7.1), the
/// folder map (R12), permissions (R8) and the values sent (R4).
@Suite("Publishing rules")
struct PublishRulesTests {
    static let me = "me"
    static let partner = "partner"
    static let path = "/mnt/photos/2024/IMG_1.JPG"

    func asset(_ id: String, owner: String = me, path: String = path, type: String = "IMAGE",
               visibility: String = "timeline", trashed: Bool = false, size: Int64? = 100) -> RemoteAssetInfo {
        RemoteAssetInfo(id: id, ownerID: owner, type: type, visibility: visibility, isTrashed: trashed,
                        originalPath: path, byteCount: size)
    }

    func evaluate(_ assets: [RemoteAssetInfo], published: Set<String> = [], size: Int64? = 100,
                  path: String = path) -> OriginalRules.PathOutcome {
        OriginalRules.evaluate(path: path, assets: assets, accountID: Self.me, size: size, published: published)
    }

    // MARK: AC8

    @Test("The account's asset is used beside a partner's at the same path (AC8, RI-V4)")
    func ownBesidePartner() {
        #expect(evaluate([asset("p", owner: Self.partner), asset("a")]) == .found("a"))
        // With only the partner's there, it says so.
        #expect(evaluate([asset("p", owner: Self.partner)]) == .reason(.anotherAccount(path: Self.path)))
    }

    @Test("One qualifying asset is used beside a trashed, hidden, non-photo, published or wrong-size one (AC8)")
    func qualifyingBesideOthers() {
        let others = [asset("t", trashed: true), asset("h", visibility: "hidden"), asset("v", type: "VIDEO"),
                      asset("pub"), asset("s", size: 99)]
        for other in others {
            #expect(evaluate([other, asset("ok")], published: ["pub"]) == .found("ok"), "\(other.id)")
        }
        #expect(evaluate(others + [asset("ok")], published: ["pub"]) == .found("ok"))
        // An archived asset qualifies (only trash, hidden and locked don't).
        #expect(evaluate([asset("arch", visibility: "archive")]) == .found("arch"))
        // No size from the server: not compared.
        #expect(evaluate([asset("n", size: nil)]) == .found("n"))
    }

    @Test("A name composed on one side and decomposed on the other is found; a difference of case is not (AC8, RI-V8)")
    func unicodeForms() {
        let composed = "/mnt/photos/Caf\u{E9}/IMG_1.JPG"
        let decomposed = "/mnt/photos/Cafe\u{301}/IMG_1.JPG"
        #expect(evaluate([asset("d", path: decomposed)], path: composed) == .found("d"))
        #expect(evaluate([asset("c", path: composed)], path: decomposed) == .found("c"))
        #expect(evaluate([asset("x", path: "/mnt/photos/2024/img_1.jpg")]) == .nothing(Self.path))
        let forms = PublishPathForms.forms(of: composed)
        #expect(forms.count == 2)
        #expect(PublishPathForms.forms(of: Self.path).count == 1)
    }

    // MARK: AC9

    @Test("Two qualifying assets, in one or two Unicode forms, are more than one match (AC9)")
    func moreThanOne() {
        #expect(evaluate([asset("a"), asset("b")]) == .reason(.moreThanOne(Self.path)))
        let composed = "/m/Caf\u{E9}.JPG"
        #expect(evaluate([asset("a", path: composed), asset("b", path: "/m/Cafe\u{301}.JPG")], path: composed)
            == .reason(.moreThanOne(composed)))
    }

    @Test("With none qualifying, the first reason in R13's order applies; an asset counts under its first fault")
    func reasonOrder() {
        // Size differs wins over everything else.
        #expect(evaluate([asset("v", type: "VIDEO"), asset("s", size: 1), asset("t", trashed: true)])
            == .reason(.sizeDiffers(Self.path)))
        #expect(evaluate([asset("v", type: "VIDEO"), asset("pub"), asset("t", trashed: true)], published: ["pub"])
            == .reason(.publishedHere(Self.path)))
        #expect(evaluate([asset("v", type: "VIDEO"), asset("h", visibility: "hidden"), asset("t", trashed: true)])
            == .reason(.inTrash))
        #expect(evaluate([asset("v", type: "VIDEO"), asset("h", visibility: "hidden")]) == .reason(.hidden))
        #expect(evaluate([asset("v", type: "VIDEO")]) == .reason(.notPhoto(path: Self.path)))
        // A trashed asset of the wrong size counts as trashed, not as size.
        #expect(evaluate([asset("t", trashed: true, size: 1)]) == .reason(.inTrash))
        // A partner's beside an own faulty one: the own one's reason.
        #expect(evaluate([asset("p", owner: Self.partner), asset("t", trashed: true)]) == .reason(.inTrash))
        #expect(evaluate([]) == .nothing(Self.path))
    }

    @Test("A linked asset: used when it qualifies; else its revealed reason, or not returned (R11, AC9)")
    func linked() {
        let rules = OriginalRules.self
        #expect(rules.evaluate(linked: asset("a"), accountID: Self.me, published: []) == .found("a"))
        #expect(rules.evaluate(linked: nil, accountID: Self.me, published: []) == .notReturned)
        #expect(rules.evaluate(linked: asset("a", trashed: true), accountID: Self.me, published: []) == .unusable(.inTrash))
        #expect(rules.evaluate(linked: asset("a", visibility: "hidden"), accountID: Self.me, published: []) == .unusable(.hidden))
        #expect(rules.evaluate(linked: asset("a", type: "VIDEO"), accountID: Self.me, published: []) == .unusable(.notPhoto(path: nil)))
        #expect(rules.evaluate(linked: asset("a"), accountID: Self.me, published: ["a"]) == .unusable(.linkedPublishedHere))
        // Another account's, whatever else is wrong.
        #expect(rules.evaluate(linked: asset("a", owner: Self.partner, trashed: true), accountID: Self.me, published: [])
            == .unusable(.anotherAccount(path: nil)))
        // No size is compared for a link.
        #expect(rules.evaluate(linked: asset("a", size: 1), accountID: Self.me, published: []) == .found("a"))
    }

    @Test("The ladder of design §7.1 (AC7, AC9)")
    func ladder() {
        let rules = OriginalRules.self
        // The map finds one: stacked, whatever the link said.
        #expect(rules.decide(link: .notReturned, map: .found("m")) == .found(assetID: "m"))
        #expect(rules.decide(link: .unusable(.inTrash), map: .found("m")) == .found(assetID: "m"))
        // The map says something about an asset there: that.
        #expect(rules.decide(link: .unusable(.inTrash), map: .reason(.sizeDiffers("/p"))) == .none(.sizeDiffers("/p")))
        // Nothing from the map: what the server revealed about the link.
        #expect(rules.decide(link: .unusable(.inTrash), map: .nothing("/p")) == .none(.inTrash))
        #expect(rules.decide(link: .unusable(.hidden), map: nil) == .none(.hidden))
        // Not returned: never called deleted or locked; with what the map found.
        #expect(rules.decide(link: .notReturned, map: nil) == .none(.linkedNotReturned(path: nil)))
        #expect(rules.decide(link: .notReturned, map: .nothing("/p")) == .none(.linkedNotReturned(path: "/p")))
        // No link.
        #expect(rules.decide(link: .none, map: nil) == .none(.noMappedFolder))
        #expect(rules.decide(link: .none, map: .nothing("/p")) == .none(.nothingAtPath("/p")))
    }

    @Test("A pair: the raw's path first, then the JPEG's; the raw's reason wins over the JPEG's nothing (R12)")
    func pairs() {
        let rules = OriginalRules.self
        #expect(rules.combine([.nothing("/r"), .found("j")]) == .found("j"))
        #expect(rules.combine([.reason(.hidden), .nothing("/j")]) == .reason(.hidden))
        #expect(rules.combine([.nothing("/r"), .reason(.sizeDiffers("/j"))]) == .reason(.sizeDiffers("/j")))
        #expect(rules.combine([.nothing("/r"), .nothing("/j")]) == .nothing("/r"))
        #expect(rules.combine([]) == nil)
    }

    // MARK: The folder map (R12)

    @Test("The longest mapped folder wins, by volume identity, wherever the volume is mounted (AC8)")
    func folderMap() {
        let disk = "uuid:ABC"
        let broad = PublishFolderMapping(volumeIdentity: disk, folderPath: "Photos", lastKnownPath: "/Volumes/D/Photos",
                                         serverPath: "/mnt/media/photos/")
        let narrow = PublishFolderMapping(volumeIdentity: disk, folderPath: "/Photos/2024/", lastKnownPath: "",
                                          serverPath: "/mnt/archive/2024")
        let map = [broad, narrow]
        #expect(broad.serverPath == "/mnt/media/photos")
        #expect(PublishFolderMapping.winning(map, volumeIdentity: disk, relativePath: "Photos/2024/Iceland/IMG_1.JPG")?.path
            == "/mnt/archive/2024/Iceland/IMG_1.JPG")
        #expect(PublishFolderMapping.winning(map, volumeIdentity: disk, relativePath: "Photos/2023/IMG_2.JPG")?.path
            == "/mnt/media/photos/2023/IMG_2.JPG")
        // A folder named like the start of another isn't it.
        #expect(PublishFolderMapping.winning(map, volumeIdentity: disk, relativePath: "Photos2/IMG.JPG") == nil)
        // Another volume: not covered.
        #expect(PublishFolderMapping.winning(map, volumeIdentity: "uuid:OTHER", relativePath: "Photos/2023/IMG_2.JPG") == nil)
        // The volume's root.
        let root = PublishFolderMapping(volumeIdentity: disk, folderPath: "", lastKnownPath: "/Volumes/D", serverPath: "/")
        #expect(root.serverPath(volumeIdentity: disk, relativePath: "a/b.jpg") == "/a/b.jpg")
        #expect(PublishFolderMapping.issues(of: narrow, in: map + [narrow]).isEmpty == true)
        var copy = narrow
        copy.id = UUID()
        copy.serverPath = ""
        #expect(PublishFolderMapping.issues(of: copy, in: map + [copy]) == [.emptyServerPath, .duplicateFolder])
    }

    // MARK: Permissions (R8, AC5)

    @Test("Only the permissions the options use are needed; stack.read never (AC5, RI-V5)")
    func permissions() {
        let two = ["asset.upload", "asset.read"]
        #expect(PublishPermissions.missing(from: two, album: .none, stacking: false).isEmpty)
        let both = PublishPermissions.missing(from: two, album: .new(name: "Trip"), stacking: true)
        #expect(both.album == ["album.read", "albumAsset.create", "album.create"])
        #expect(both.stacking == ["user.read", "stack.create"])
        #expect(both.server.isEmpty)
        #expect(PublishPermissions.missing(from: two, album: .existing(id: "a", name: "A"), stacking: false).album
            == ["album.read", "albumAsset.create"])
        let exact = two + ["album.read", "albumAsset.create", "album.create", "user.read", "stack.create"]
        #expect(PublishPermissions.missing(from: exact, album: .new(name: "T"), stacking: true).isEmpty)
        #expect(!exact.contains("stack.read") && !exact.contains("asset.view") && !exact.contains("asset.download"))
        #expect(PublishPermissions.missing(from: ["asset.read"], album: .none, stacking: false).server == ["asset.upload"])
        #expect(PublishPermissions.missing(from: ["all"], album: .new(name: "T"), stacking: true).isEmpty)
        // Each one removed in turn is named.
        for removed in exact {
            let missing = PublishPermissions.missing(from: exact.filter { $0 != removed }, album: .new(name: "T"), stacking: true)
            #expect(missing.all == [removed], "\(removed)")
        }
    }

    // MARK: Values sent (R4, AC3)

    @Test("A photo taken at 10:20 at +02:00 is sent as 10:20 labelled UTC (R4, RI-V1)")
    func captureDate() throws {
        // The catalog stores the instant and the offset.
        let instant = try Date.ISO8601FormatStyle().parse("2019-06-15T08:20:30Z")
        let sent = PublishJob.uploadDate(captureDate: instant, offsetSeconds: 7200, modifiedAt: Date(), timeZone: .gmt)
        #expect(PublishUploadBody.isoUTC(sent) == "2019-06-15T10:20:30.000Z")
        // A floating time (no offset) is stored as its wall clock labelled UTC.
        let floating = try Date.ISO8601FormatStyle().parse("2019-06-15T10:20:30Z")
        #expect(PublishUploadBody.isoUTC(PublishJob.uploadDate(captureDate: floating, offsetSeconds: nil, modifiedAt: Date(),
                                                               timeZone: .gmt)) == "2019-06-15T10:20:30.000Z")
        // No capture date: the file's modification time as local wall clock.
        let modified = try Date.ISO8601FormatStyle().parse("2020-01-02T03:04:05Z")
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(PublishUploadBody.isoUTC(PublishJob.uploadDate(captureDate: nil, offsetSeconds: nil, modifiedAt: modified,
                                                               timeZone: zone)) == "2020-01-01T22:04:05.000Z")
    }

    @Test("A typed description replaces each photo's own; empty keeps it (R5)")
    func description() {
        let values = SidecarValues(caption: "Own")
        #expect(PublishJob.values(values, description: "Typed").caption == "Typed")
        #expect(PublishJob.values(values, description: nil).caption == "Own")
        let run = PublishRun(service: RemoteServiceRecord(name: "S", address: "https://s"),
                             choices: PublishChoices(settings: ExportSettings()), description: "  \n ", items: [])
        #expect(run.description == nil)
    }

    @Test("The upload body carries the date, name and visibility, then the file, and nothing else (R4, R24)")
    func uploadBody() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let file = folder.appending(path: "a.jpg")
            try Data([1, 2, 3, 4]).write(to: file)
            let body = folder.appending(path: "body")
            let fields = PublishUploadBody.Fields(createdAt: Date(timeIntervalSince1970: 0), fileName: "IMG\"1.jpg",
                                                  visibility: .archive)
            let type = try PublishUploadBody.write(file: file, fields: fields, to: body, boundary: "B")
            #expect(type == "multipart/form-data; boundary=B")
            let text = String(decoding: try Data(contentsOf: body), as: UTF8.self)
            let names = text.components(separatedBy: "; name=\"").dropFirst().map { $0.prefix { $0 != "\"" } }
            #expect(names == ["fileCreatedAt", "fileModifiedAt", "filename", "visibility", "assetData"])
            #expect(text.contains("1970-01-01T00:00:00.000Z"))
            #expect(text.contains("filename=\"IMG1.jpg\""))
            #expect(text.contains("\r\n\r\narchive\r\n"))
            #expect(text.hasSuffix("\r\n--B--\r\n"))
        }
    }

    // MARK: Counts and retry coverage (R23)

    @Test("Counts and what Retry Failed covers follow the latest ending (R23, design §10.1)")
    func countsAndRetry() {
        var run = PublishRun(service: RemoteServiceRecord(name: "S", address: "https://s"),
                             choices: PublishChoices(settings: ExportSettings(), album: .new(name: "A"), stacking: true),
                             description: nil,
                             items: (1...6).map { PublishItem(versionID: Int64($0), name: "\($0)", album: true, stacking: true) },
                             skipped: 2, videos: 1)
        run.items[0].upload = .accepted(.created("a"))
        run.items[0].album = .done
        run.items[0].stacking = .stacked
        run.items[1].upload = .accepted(.created("b"))
        run.items[1].album = .done
        run.items[1].stacking = .failed(.stackRefused(message: nil))
        run.items[2].upload = .accepted(.duplicate("c"))
        run.items[2].check = .alreadyThere(.inTrash)
        run.items[3].upload = .accepted(.duplicate("d"))
        run.items[3].check = .pending
        run.items[4].upload = .failed(.uploadInterrupted)
        // items[5] never reached.
        run.ending = .stopped(.stopped)
        let counts = run.counts
        #expect(counts.published == 2 && counts.alreadyOnServer == 2 && counts.alreadyThere[.inTrash] == 1)
        #expect(counts.stacked == 1 && counts.failed == 2 && counts.notFinished == 1 && counts.notPublished == 1)
        #expect(counts.skipped == 2 && counts.videos == 1)
        #expect(run.items[3].left == .check)
        // The person's Stop: the unreached photo is left out.
        #expect(run.retryCandidates == [2, 4, 5])
        #expect(run.retryLeavesOutUnreached)
        run.ending = .stopped(.unreachable)
        #expect(run.retryCandidates == [2, 4, 5, 6])
        #expect(counts.isWarning(ending: run.ending))
    }
}
