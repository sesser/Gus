import Foundation
import Synchronization
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

    @Test("Retry Failed is not offered when a later run published every photo it would cover; a photo to finish keeps it (review D-12)")
    func retryNothingLeftRule() {
        var run = PublishRun(service: RemoteServiceRecord(name: "S", address: "https://s"),
                             choices: PublishChoices(settings: ExportSettings(), album: .new(name: "A"), stacking: false),
                             description: nil,
                             items: (1...4).map { PublishItem(versionID: Int64($0), name: "\($0)", album: true, stacking: false) })
        // 1 uploaded, its album step unfinished; 2 failed; 3 not reached; 4 uploaded and done.
        run.items[0].upload = .accepted(.created("a"))
        run.items[1].upload = .failed(.uploadInterrupted)
        run.items[3].upload = .accepted(.created("d"))
        run.items[3].album = .done
        run.ending = .stopped(.unreachable)
        #expect(run.retryCandidates == [1, 2, 3])
        #expect(run.notUploadedVersionIDs == [2, 3])
        // Nothing published later: everything is covered.
        #expect(run.retryVersionIDs(laterPublished: []) == [1, 2, 3])
        #expect(run.offersRetry(laterPublished: []) && !run.retrySentByLaterRuns(laterPublished: []))
        // 2 and 3 published later: 1 is still to finish, so the button stays.
        #expect(run.retryVersionIDs(laterPublished: [2, 3]) == [1])
        #expect(run.offersRetry(laterPublished: [2, 3]) && !run.retrySentByLaterRuns(laterPublished: [2, 3]))
        // An uploaded photo's own record is never a later publication.
        #expect(run.retryVersionIDs(laterPublished: [1, 2, 3]) == [1])
        // With 1 finished, nothing is left: no button, the caption instead.
        run.items[0].album = .done
        #expect(run.offersRetry, "the counts still record a failed and an unreached photo")
        #expect(run.retryVersionIDs(laterPublished: [2, 3]).isEmpty)
        #expect(!run.offersRetry(laterPublished: [2, 3]) && run.retrySentByLaterRuns(laterPublished: [2, 3]))
        #expect(run.counts.failed == 1 && run.counts.notPublished == 1)
        // One of the two left: the button stays, for that one.
        #expect(run.retryVersionIDs(laterPublished: [2]) == [3])
        #expect(run.offersRetry(laterPublished: [2]) && !run.retrySentByLaterRuns(laterPublished: [2]))
        // A run with nothing to retry shows neither the button nor the caption.
        run.items[1].upload = .accepted(.created("b"))
        run.items[1].album = .done
        run.ending = .stopped(.stopped)
        #expect(!run.offersRetry && !run.offersRetry(laterPublished: []) && !run.retrySentByLaterRuns(laterPublished: [3]))
    }

    @Test("A reload of the saved servers: the chosen one removed, or its address or certificate changed, or neither (review D-13, F28)")
    func chosenServerChange() {
        let home = RemoteServiceRecord(id: 1, name: "Home", address: "https://home.example")
        let other = RemoteServiceRecord(id: 2, name: "Other", address: "https://other.example")
        // Removed while chosen, another still saved: no other is chosen by itself.
        #expect(PublishServerChange.after(reload: [other], chosenID: 1, before: home) == .removed)
        #expect(PublishServerChange.after(reload: [], chosenID: 1, before: home) == .removed)
        // Another server removed, or none chosen: nothing.
        #expect(PublishServerChange.after(reload: [home], chosenID: 1, before: home) == .unchanged)
        #expect(PublishServerChange.after(reload: [other], chosenID: nil, before: nil) == .unchanged)
        // Renamed only: nothing to check again.
        var renamed = home
        renamed.name = "Cellar"
        #expect(PublishServerChange.after(reload: [renamed, other], chosenID: 1, before: home) == .unchanged)
        // A new address, or a certificate trusted or changed: checked again.
        var moved = home
        moved.address = "https://new.example"
        #expect(PublishServerChange.after(reload: [moved], chosenID: 1, before: home) == .connectionChanged(moved))
        var trusted = home
        trusted.certificateFingerprint = String(repeating: "a", count: 64)
        #expect(PublishServerChange.after(reload: [trusted], chosenID: 1, before: home) == .connectionChanged(trusted))
        // A record held for another id (chosen since) is no comparison.
        #expect(PublishServerChange.after(reload: [moved, other], chosenID: 1, before: other) == .unchanged)
    }

    @Test("A Publish starts only with the address and certificate it was checked or asked with, as saved now (review D-15)")
    func destinationSinceConfirmed() async throws {
        let catalog = try Catalog.makeInMemory()
        let home = try await catalog.saveRemoteService(RemoteServiceRecord(name: "Home", address: "https://home.example"))
        let id = try #require(home.id)
        #expect(try await PublishServerChange.since(home, in: catalog) == .unchanged)
        // A rename alone gives nothing up (D-14).
        let renamed = try #require(try await catalog.renameRemoteService(id: id, to: "Cellar"))
        #expect(try await PublishServerChange.since(home, in: catalog) == .unchanged)
        // A new address saved in the import window while the question is up: given up.
        var moved = renamed
        moved.address = "https://new.example"
        moved = try await catalog.saveRemoteService(moved)
        #expect(try await PublishServerChange.since(home, in: catalog) == .connectionChanged(moved))
        #expect(try await PublishServerChange.since(moved, in: catalog) == .unchanged)
        // A certificate trusted, or a plain-http address confirmed to https: given up too.
        var trusted = moved
        trusted.certificateFingerprint = String(repeating: "b", count: 64)
        trusted = try await catalog.saveRemoteService(trusted)
        #expect(try await PublishServerChange.since(moved, in: catalog) == .connectionChanged(trusted))
        // Removed: nothing starts (D-13 says so).
        try await catalog.deleteRemoteService(id: id)
        #expect(try await PublishServerChange.since(trusted, in: catalog) == .removed)
        #expect(try await PublishServerChange.since(RemoteServiceRecord(name: "New", address: "https://n.example"),
                                                    in: catalog) == .removed)
    }

    // MARK: Review fixes

    @Test("A server path is matched and saved without its trailing slash, but kept as typed while it is typed (review F6)")
    func serverPathAsTyped() {
        var mapping = PublishFolderMapping(volumeIdentity: "uuid:1", folderPath: "Photos", lastKnownPath: "/V/Photos",
                                           serverPath: "/mnt")
        // Typing "/mnt/media" passes through "/mnt/": the field keeps the slash.
        mapping.serverPath = "/mnt/"
        #expect(mapping.serverPath == "/mnt/")
        #expect(mapping.serverPath(volumeIdentity: "uuid:1", relativePath: "Photos/a.jpg") == "/mnt/a.jpg")
        #expect(mapping.kept.serverPath == "/mnt")
        mapping.serverPath = "/mnt/media/"
        #expect(mapping.serverPath(volumeIdentity: "uuid:1", relativePath: "Photos/2024/a.jpg") == "/mnt/media/2024/a.jpg")
        #expect(PublishFolderMapping.winning([mapping], volumeIdentity: "uuid:1", relativePath: "Photos/a.jpg")?.path
            == "/mnt/media/a.jpg")
        mapping.serverPath = "/"
        #expect(mapping.serverPath(volumeIdentity: "uuid:1", relativePath: "Photos/a.jpg") == "/a.jpg")
    }

    @Test("Only ASCII ids of letters, digits and hyphens reach a path; a trailing line terminator never passes (security review N1)")
    func serverIDsAndAnchoredAllowlist() {
        for id in ["0f3c8e2a-1b2c-4d5e-8f90-abcdef012345", "abc", "A-1"] {
            #expect(RemoteAsset.isServerID(id), "\(id)")
            #expect(RemoteRequestAllowlist.permits(method: "GET", path: "/assets/\(id)"))
        }
        for id in ["", "abc\u{2028}", "abc\u{2029}", "abc\n", "abc\r", "abc\u{85}", "é", "abc/def", "a.b", "a b",
                   String(repeating: "a", count: 65), "\u{FF21}"] {
            #expect(!RemoteAsset.isServerID(id), "\(id.unicodeScalars.map(\.value))")
        }
        // ICU's `$` matches before a final line terminator; the whole path must match.
        for path in ["/assets/abc\u{2028}", "/assets/abc\u{2029}", "/assets/abc\n", "/stacks\u{2028}",
                     "/albums/abc/assets\u{2029}", "/assets/abc/thumbnail\n", "/server/version\r\n"] {
            #expect(!RemoteRequestAllowlist.permits(method: path.hasPrefix("/albums/") ? "PUT" : (path.hasPrefix("/stacks") ? "POST" : "GET"),
                                                    path: path), "\(path.unicodeScalars.map(\.value))")
        }
    }

    @Test("A bulk add's per-photo error is cut at 200 characters like any server text (security review N2 addendum)")
    func albumAddErrorCut() throws {
        let long = String(repeating: "x", count: 5_000)
        let json = """
            [{"id": "a", "success": false, "error": "\(long)"},
             {"id": "b", "success": false, "error": "  no_permission\\n"},
             {"id": "c", "success": false, "error": "   "},
             {"id": "d", "success": false},
             {"id": "e", "success": false, "error": "duplicate"},
             {"id": "f", "success": true}]
            """
        let results = try JSONDecoder().decode([ImmichDTO.BulkResult].self, from: Data(json.utf8))
        let refused = ImmichClient.refusals(results)
        #expect(refused.keys.sorted() == ["a", "b", "c", "d"])
        #expect(refused["a"] == String(repeating: "x", count: RemoteAnswer.shownTextLimit))
        #expect(refused["a"]?.count == 200)
        #expect(refused["b"] == "no_permission")
        #expect(refused["c"] == "")
        #expect(refused["d"] == "")
        // The same cut as a top-level message.
        let answer = RemoteAnswer(status: 400, body: Data("{\"message\": \"\(long)\"}".utf8))
        #expect(answer.serverMessage == refused["a"])
    }

    @Test("Progress: ending once stopped, whatever comes after; waiting only while a request is tried again (review F2, F15, D-1)")
    func progressCounter() {
        let reports = Mutex<[PublishProgress]>([])
        let counter = ProgressCounter(total: 2) { progress in reports.withLock { $0.append(progress) } }
        counter.step(.uploading, current: 1)
        let last = { reports.withLock { reports -> PublishProgress.Phase? in reports.last?.phase } }
        counter.waiting(true)
        #expect(last() == .waiting)
        // The retried request succeeded: back to the step in hand.
        counter.waiting(false)
        #expect(last() == .uploading)
        counter.stopping()
        let stoppedAt = reports.withLock { reports -> Int in reports.count }
        // A photo still reporting after the stop doesn't bring the run back.
        counter.step(.rendering, current: 2)
        counter.waiting(true)
        counter.awaiting(true)
        counter.finished()
        counter.awaiting(false)
        counter.finished()
        let after = reports.withLock { reports -> [PublishProgress] in Array(reports.dropFirst(stoppedAt - 1)) }
        #expect(after.allSatisfy { $0.phase == .ending })
        #expect(after.map(\.awaitsAnswer) == [false, false, false, true, true, false, false])
        #expect(after.last?.done == 2)
        // The app keeps ending for a report that left before the stop and arrives after it.
        let ending = PublishProgress(done: 0, total: 2, current: 1, phase: .ending)
        #expect(ending.followed(by: PublishProgress(done: 1, total: 2, current: 2, phase: .uploading)).phase == .ending)
        #expect(PublishProgress(done: 0, total: 2, current: 1, phase: .rendering)
            .followed(by: PublishProgress(done: 0, total: 2, current: 1, phase: .uploading)).phase == .uploading)
    }

    @Test("One publish at a time: a second start is refused from the first claim until the run has ended (code review C2)")
    func oneAtATime() {
        var slot = PublishSlot()
        let first = UUID(), second = UUID()
        let claimed = slot.claim(first)
        let claimedAgain = slot.claim(second)
        #expect(claimed && !claimedAgain)
        #expect(slot.isBusy && !slot.isStopping)
        slot.stop()
        slot.release(second)
        #expect(slot.holder == first && slot.isStopping, "another run's end changes nothing")
        slot.release(first)
        #expect(!slot.isBusy && !slot.isStopping)
        let next = slot.claim(second)
        #expect(next)
        slot.stop()
        #expect(slot.isStopping)
    }

    @Test("An album a run made is remembered only while no later run to that server has started (review F18)")
    func albumRememberedOnlyByTheLatest() {
        let home = RemoteServiceRecord(name: "Home", address: "https://h.example")
        let other = RemoteServiceRecord(name: "Other", address: "https://o.example")
        let choices = PublishChoices(settings: ExportSettings(), album: .new(name: "Trip"))
        let older = PublishRun(service: home, choices: choices, description: nil, items: [],
                               startedAt: Date(timeIntervalSince1970: 100))
        let newer = PublishRun(service: home, choices: choices, description: nil, items: [],
                               startedAt: Date(timeIntervalSince1970: 200))
        let elsewhere = PublishRun(service: other, choices: choices, description: nil, items: [],
                                   startedAt: Date(timeIntervalSince1970: 300))
        #expect(!older.mayRememberItsAlbum(among: [older, newer, elsewhere]))
        #expect(newer.mayRememberItsAlbum(among: [older, newer, elsewhere]))
        #expect(older.mayRememberItsAlbum(among: [older, elsewhere]))
    }

    @Test("Runs are listed by the time they ended, a retry's ending included; the newest is the one that ended last (review F23, D-9)")
    func endedRunsByEndTime() {
        let home = RemoteServiceRecord(name: "Home", address: "https://h.example")
        let choices = PublishChoices(settings: ExportSettings(), album: .none)
        func run(started: TimeInterval, ended: TimeInterval?) -> PublishRun {
            var run = PublishRun(service: home, choices: choices, description: nil, items: [],
                                 startedAt: Date(timeIntervalSince1970: started))
            run.ending = .completed
            run.endedAt = ended.map { Date(timeIntervalSince1970: $0) }
            return run
        }
        // The first run was retried after the second ended.
        let retried = run(started: 100, ended: 400)
        let second = run(started: 200, ended: 300)
        let sameTime = run(started: 250, ended: 300)
        let ordered = PublishRun.byEnding([retried, second, sameTime])
        #expect(ordered.map(\.id) == [second.id, sameTime.id, retried.id])
        #expect(PublishRun.byEnding([sameTime, second]).map(\.id) == [sameTime.id, second.id], "ties keep their order")
    }

    @Test("A retry's outcome: called off leaves the run; a check's ending gives way to a Stop asked first; a run that ran is recorded (D-10)")
    func retryOutcomeRule() {
        var run = PublishRun(service: RemoteServiceRecord(name: "S", address: "https://s"),
                             choices: PublishChoices(settings: ExportSettings(), album: .none), description: nil, items: [])
        run.ending = .stopped(.stopped)
        #expect(PublishRetryOutcome.calledOff.ended(stopAsked: false) == nil)
        #expect(PublishRetryOutcome.calledOff.ended(stopAsked: true) == nil)
        #expect(PublishRetryOutcome.checkStopped(run).ended(stopAsked: false) != nil)
        #expect(PublishRetryOutcome.checkStopped(run).ended(stopAsked: true) == nil)
        #expect(PublishRetryOutcome.ran(run).ended(stopAsked: true)?.ending == .stopped(.stopped))
    }

    @Test("A launch removes only the temporary folders of launches that have ended (code review C5, security review L1)")
    func temporaryFoldersPerLaunch() async throws {
        try await RepositoryFiles.withTemporaryDirectory { base in
            let manager = FileManager.default
            // Another copy of the app, running: its lock is held.
            let running = PublishTemporaryFolders.makeLaunch(in: base)
            #expect(running.descriptor >= 0)
            try Data([1]).write(to: running.folder.appending(path: "body.multipart"))
            // A copy that has quit: its lock file is there, no one holds it.
            let ended = PublishTemporaryFolders.makeLaunch(in: base)
            try Data([2]).write(to: ended.folder.appending(path: "body.multipart"))
            close(ended.descriptor)
            // A run folder of the earlier layout, with no lock file, a day old.
            let stray = base.appending(path: UUID().uuidString)
            try manager.createDirectory(at: stray, withIntermediateDirectories: true)
            try manager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -25 * 3600)], ofItemAtPath: stray.path)
            PublishTemporaryFolders.removeLeftovers(in: base)
            #expect(manager.fileExists(atPath: running.folder.appending(path: "body.multipart").path))
            #expect(!manager.fileExists(atPath: ended.folder.path))
            #expect(!manager.fileExists(atPath: ended.folder.path + PublishTemporaryFolders.lockSuffix))
            #expect(!manager.fileExists(atPath: stray.path))
            close(running.descriptor)
            // Once it has quit too, the next launch removes it.
            PublishTemporaryFolders.removeLeftovers(in: base)
            #expect(!manager.fileExists(atPath: running.folder.path))
            #expect(try manager.contentsOfDirectory(atPath: base.path).isEmpty)
        }
    }

    @Test("A folder with no lock file goes only once it is a day old: a running launch whose lock file was removed keeps its folder (security review N6)")
    func temporaryFoldersLockLessOnlyWhenOld() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let manager = FileManager.default
            let base = root.appending(path: "base")
            let running = PublishTemporaryFolders.makeLaunch(in: base)
            defer { close(running.descriptor) }
            try Data([1]).write(to: running.folder.appending(path: "body.multipart"))
            // Something else removed its lock file; the launch still runs.
            try manager.removeItem(atPath: running.folder.path + PublishTemporaryFolders.lockSuffix)
            PublishTemporaryFolders.removeLeftovers(in: base)
            #expect(manager.fileExists(atPath: running.folder.appending(path: "body.multipart").path))
            // A day later with no change it counts as left over.
            PublishTemporaryFolders.removeLeftovers(in: base, now: Date(timeIntervalSinceNow: 25 * 3600))
            #expect(!manager.fileExists(atPath: running.folder.path))
        }
    }

    @Test("A launch whose first name's lock can't be taken tries a new name; it never works from an unlocked folder in the base (security review N6)")
    func temporaryFoldersLockRetry() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let manager = FileManager.default
            let base = root.appending(path: "base")
            try manager.createDirectory(at: base, withIntermediateDirectories: true)
            // Another copy's cleanup holds the lock of the first name.
            let names = ["first", "second", "third"]
            let held = open(base.appending(path: names[0] + PublishTemporaryFolders.lockSuffix).path,
                            O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK | O_CLOEXEC, 0o600)
            #expect(held >= 0)
            defer { close(held) }
            var next = names.makeIterator()
            let launch = PublishTemporaryFolders.makeLaunch(in: base, names: { next.next() ?? UUID().uuidString })
            defer { close(launch.descriptor) }
            #expect(launch.descriptor >= 0)
            #expect(launch.folder.lastPathComponent == "second")
            #expect(!manager.fileExists(atPath: base.appending(path: "first").path))
            #expect(manager.fileExists(atPath: base.appending(path: "second" + PublishTemporaryFolders.lockSuffix).path))

            // No name can be locked: a folder of its own outside the base, never an unlocked one inside it.
            let blocked = root.appending(path: "blocked")
            try manager.createDirectory(at: blocked, withIntermediateDirectories: true)
            let lock = open(blocked.appending(path: "same" + PublishTemporaryFolders.lockSuffix).path,
                            O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK | O_CLOEXEC, 0o600)
            defer { close(lock) }
            let outside = PublishTemporaryFolders.makeLaunch(in: blocked, names: { "same" })
            #expect(outside.descriptor == -1)
            #expect(outside.folder.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path)
            #expect(outside.folder.lastPathComponent.hasPrefix("blocked-"))
            #expect(try manager.contentsOfDirectory(atPath: blocked.path) == ["same" + PublishTemporaryFolders.lockSuffix])
        }
    }

    @Test("The base folder is the user's alone; a symbolic link at the base or at a lock name is never followed (security review N5)")
    func temporaryFoldersNoLinks() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let manager = FileManager.default
            let old = Date(timeIntervalSinceNow: 25 * 3600)
            // Made with mode 0700, and an existing base set to it.
            let base = root.appending(path: "base")
            let launch = PublishTemporaryFolders.makeLaunch(in: base)
            close(launch.descriptor)
            #expect((try manager.attributesOfItem(atPath: base.path)[.posixPermissions] as? Int) == 0o700)
            let wide = root.appending(path: "wide")
            try manager.createDirectory(at: wide, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            let other = PublishTemporaryFolders.makeLaunch(in: wide)
            close(other.descriptor)
            #expect((try manager.attributesOfItem(atPath: wide.path)[.posixPermissions] as? Int) == 0o700)

            // A base that is a symbolic link: nothing in its target is removed.
            let target = root.appending(path: "target")
            try manager.createDirectory(at: target, withIntermediateDirectories: true)
            let keep = target.appending(path: "keep.txt")
            try Data([1]).write(to: keep)
            let linkedBase = root.appending(path: "linked")
            try manager.createSymbolicLink(at: linkedBase, withDestinationURL: target)
            PublishTemporaryFolders.removeLeftovers(in: linkedBase, now: old)
            #expect(manager.fileExists(atPath: keep.path))

            // A lock name that is a symbolic link: its target is not locked, and its folder stays.
            let real = root.appending(path: "real")
            try manager.createDirectory(at: real, withIntermediateDirectories: true)
            let elsewhere = root.appending(path: "elsewhere.lock")
            try Data().write(to: elsewhere)
            let folder = real.appending(path: "X")
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([2]).write(to: folder.appending(path: "body.multipart"))
            try manager.createSymbolicLink(at: real.appending(path: "X" + PublishTemporaryFolders.lockSuffix),
                                           withDestinationURL: elsewhere)
            PublishTemporaryFolders.removeLeftovers(in: real)
            #expect(manager.fileExists(atPath: folder.appending(path: "body.multipart").path))
            #expect(manager.fileExists(atPath: elsewhere.path))
        }
    }
}
