import AppKit
import Foundation
import PhotoCore
import PhotoFixtures
import PhotoUI

/// The debug script's server commands (issue #271, R25, design §11), words
/// after `import server`, plus `import album` and `import dates`. A scripted launch keeps keys in memory
/// (`LibraryModel.remoteKeyStore`), and nothing here prints a key: the fake
/// server's key is a fixed test string, and output names keys only as
/// "entered" or "-".
///
///     import server fake start [<count>] | stop | requests | fault drop|revoke|notimmich|clear
///                  | fault delete|corrupt|truncate|external <index> | fault unavailable <index> <times> | fault slow <ms>
///                  | fault permissions <a,b,…>
///     import server add <name> <address>|fake [<key>]   (Add Server… with the notice confirmed; waits for the check)
///     import server sheet add|edit|close|print|remove | field name|address|key <text> | confirm on|off | submit | trust | back
///                        (address `fake`, or `fakehost`: the fake server named localhost)
///                        | review [<seed>]   (the Edit sheet's changed-certificate page, a made-up certificate)
///     import server list | select <name> (waits) | check | edit | remove [<name>] | confirm yes|no | print
///     import server keychain fail|ok   (the in-memory key store refuses, or works again)
///     import server project <text>   (as typing in the Project name field; `print` shows the DQ-13 note)
///     import album <name>|all (waits) | import dates <yyyy-mm-dd|-> <yyyy-mm-dd|->|clear (waits)
/// (`import scroll <index>|end` is `ImportDebugCommands`'.)
///     import server fake … | fault stack refuse|ok | fault lose <METHOD> <path> <times>
///                  | fault answer <METHOD> <path> <status> <times> | fault hold on|off|release | uploads
///                  | fault slowcheck <ms>|0   (each check's first answer takes that long)
///     (publishing, issue #28: the fake server's refused stack, lost answers, canned statuses, held upload answers)
@MainActor
enum DebugServerCommands {
    private static var fake: FakeImmichServer?

    /// The fake server the script started (publishing's commands use it too).
    static var fakeServer: FakeImmichServer? { fake }

    /// Returns false for words it does not handle.
    static func run(_ words: [String], model: CardImportModel, window: NSWindow?) async -> Bool {
        switch words.first {
        case "server":
            await server(Array(words.dropFirst()), model: model, window: window)
        case "album":
            let name = words.dropFirst().joined(separator: " ")
            let album = model.browse?.albums.first { $0.name == name }
            model.chooseAlbum(name == "all" ? nil : album?.id)
            await waitForPage(model)
        case "dates":
            if words.dropFirst().first == "clear" {
                model.setDateRange(nil)
            } else {
                let parts = words.dropFirst().map { $0 == "-" ? nil : day($0) }
                model.setDateRange(CaptureDateRange(from: parts.first ?? nil, through: parts.dropFirst().first ?? nil))
            }
            await waitForPage(model)
        default:
            return false
        }
        return true
    }

    private static func day(_ text: String) -> DateComponents? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    private static func server(_ words: [String], model: CardImportModel, window: NSWindow?) async {
        let rest = Array(words.dropFirst())
        switch words.first {
        case "fake":
            await fakeCommand(rest)
        case "add":
            guard rest.count >= 2 else { return print("debug-script: import server add: name and address needed") }
            model.showAddServer()
            guard let sheet = model.serverSheet else { return print("debug-script: import server add: no sheet") }
            sheet.name = rest[0]
            // "fake" stands for the fake server's address (its port is chosen at start).
            sheet.address = rest[1] == "fake" ? fake?.address ?? "" : rest[1]
            sheet.setKey(rest.count > 2 ? rest[2] : FakeImmichServer.validKey)
            if case .unencryptedLocal = sheet.addressState { sheet.unencryptedConfirmed = true }
            sheet.submit()
            await waitForCheck(sheet)
            print("debug-script: import server add \(rest[0]): \(sheetResult(sheet))")
            await waitForConnect(model)
        case "sheet":
            await sheetCommand(rest, model: model)
        case "list":
            for service in model.servers {
                print("debug-script: import server \(service.name) \(service.address) provider \(service.provider.rawValue) "
                      + "pinned \(service.pinnedFingerprint?.colonSeparated ?? "none") http \(service.allowsUnencrypted)")
            }
            if model.servers.isEmpty { print("debug-script: import server list: none") }
        case "select":
            let name = rest.joined(separator: " ")
            guard let service = model.servers.first(where: { $0.name == name }) else {
                return print("debug-script: import server select: no server named \(name)")
            }
            model.chooseServer(service)
            await waitForConnect(model)
        case "check":
            guard let browse = model.browse else { return print("debug-script: import server check: no server") }
            if let failure = browse.failure {
                let text = ServerText.result(failure, host: browse.address?.host ?? "", name: browse.service.name)
                print("debug-script: import server check \(failure.kind) \(text?.title ?? "-")")
            } else {
                print("debug-script: import server check \(browse.info == nil ? "pending" : "passed")")
            }
        case "edit":
            model.showEditServer()
            try? await Task.sleep(for: .milliseconds(300))
        case "remove":
            let name = rest.joined(separator: " ")
            model.askToRemoveServer(name.isEmpty ? nil : model.servers.first { $0.name == name })
            try? await Task.sleep(for: .milliseconds(300))
            print("debug-script: import server remove asks \(model.removingServer?.name ?? "-")")
        case "confirm":
            if rest.first == "yes", let service = model.removingServer {
                model.removeServer(service)
            } else {
                model.removingServer = nil
            }
            try? await Task.sleep(for: .milliseconds(500))
        case "print":
            printServer(model)
        case "project":
            model.setServerProjectName(rest.joined(separator: " "))
        case "keychain":
            // The scripted launch's in-memory store refuses (DQ-5) or works again.
            guard let store = model.library?.remoteKeyStore as? InMemoryKeyStore else {
                return print("debug-script: import server keychain: not the in-memory store")
            }
            store.failing = rest.first == "fail"
        default:
            print("debug-script: unknown import server command")
        }
    }

    // MARK: The fake server

    private static func fakeCommand(_ words: [String]) async {
        switch words.first {
        case "start":
            fake?.stop()
            do {
                let count = words.dropFirst().first.flatMap(Int.init) ?? 30
                let server = try await FakeImmichServer()
                let album = FakeImmichServer.Album(name: "Trip", assetCount: 7)
                var assets = try FakeImmichServer.jpegAssets(count: count)
                for index in assets.indices where index < 5 { assets[index].albumIDs = [album.id] }
                if assets.count > 2 { assets[1].isEdited = true }
                if assets.count > 3 { assets[2].livePhotoVideoID = UUID().uuidString.lowercased() }
                if assets.count > 4 {
                    assets[3].description = "From the server"
                    assets[3].rating = 4
                }
                server.setAssets(assets)
                server.setAlbums([album, FakeImmichServer.Album(name: "Empty", assetCount: 0)])
                fake = server
                print("debug-script: import server fake \(server.address) assets \(count)")
            } catch {
                print("debug-script: import server fake start failed: \(error)")
            }
        case "stop":
            fake?.stop()
            fake = nil
        case "uploads":
            for upload in fake?.uploads ?? [] {
                print("debug-script: import server upload \(upload.duplicate ? "duplicate" : "created") "
                      + "name \(upload.fields["filename"] ?? "-") date \(upload.fields["fileCreatedAt"] ?? "-") "
                      + "visibility \(upload.fields["visibility"] ?? "-") bytes \(upload.data.count)")
            }
        case "requests":
            for request in fake?.requests ?? [] {
                print("debug-script: import server request \(request.method) \(request.path) "
                      + "\(request.query.isEmpty ? "" : "?" + request.query) key \(request.sentKey ? "sent" : "-")")
            }
        case "fault":
            guard let fake else { return print("debug-script: import server fault: no fake") }
            let rest = Array(words.dropFirst())
            let assets = fake.assets.sorted { $0.takenAt > $1.takenAt }
            func asset(_ text: String?) -> String? {
                text.flatMap(Int.init).flatMap { assets.indices.contains($0) ? assets[$0].id : nil }
            }
            switch rest.first {
            case "drop": fake.add(.drop)
            case "revoke": fake.add(.revokeKey)
            case "notimmich": fake.add(.notImmich)
            case "clear": fake.clearFaults()
            case "delete": if let id = asset(rest.dropFirst().first) { fake.add(.deleteAsset(id)) }
            case "corrupt": if let id = asset(rest.dropFirst().first) { fake.add(.corrupt(id)) }
            case "truncate": if let id = asset(rest.dropFirst().first) { fake.add(.truncate(id)) }
            case "unavailable":
                if let id = asset(rest.dropFirst().first) {
                    fake.add(.unavailable(id, times: rest.dropFirst(2).first.flatMap(Int.init) ?? 1))
                }
            case "slow": fake.add(.slow(.milliseconds(rest.dropFirst().first.flatMap(Int.init) ?? 500)))
            case "slowcheck":
                fake.removeSlowCheck()
                if let ms = rest.dropFirst().first.flatMap(Int.init), ms > 0 { fake.add(.slowCheck(.milliseconds(ms))) }
            case "permissions": fake.setPermissions(rest.dropFirst().first?.split(separator: ",").map(String.init) ?? [])
            case "stack":
                if rest.dropFirst().first == "refuse" { fake.add(.refuseStack) } else { fake.remove(.refuseStack) }
            case "lose":
                let parts = Array(rest.dropFirst())
                guard parts.count >= 2 else { return }
                fake.add(.loseAnswer(method: parts[0], path: parts[1], times: parts.dropFirst(2).first.flatMap(Int.init) ?? 1))
            case "answer":
                let parts = Array(rest.dropFirst())
                guard parts.count >= 3, let status = Int(parts[2]) else { return }
                fake.add(.answer(method: parts[0], path: parts[1], status: status,
                                 times: parts.dropFirst(3).first.flatMap(Int.init) ?? 1))
            case "hold":
                switch rest.dropFirst().first {
                case "on": fake.add(.holdUploadAnswer)
                case "release": fake.releaseHeldAnswers()
                default:
                    fake.remove(.holdUploadAnswer)
                    fake.releaseHeldAnswers()
                }
            case "external":
                // The asset at <index> is an external library's, its checksum the path's (RI-E2).
                guard let id = asset(rest.dropFirst().first) else { return }
                fake.setAssets(fake.assets.map { asset in
                    guard asset.id == id else { return asset }
                    var external = asset
                    external.libraryID = "library-1"
                    external.checksumOverride = FakeImmichServer.Asset.pathChecksum("/mnt/photos/\(asset.fileName)")
                    return external
                })
            default: print("debug-script: import server fault: unknown")
            }
        default:
            print("debug-script: unknown import server fake command")
        }
    }

    // MARK: The sheet

    private static func sheetCommand(_ words: [String], model: CardImportModel) async {
        let rest = Array(words.dropFirst())
        switch words.first {
        case "add":
            model.showAddServer()
            try? await Task.sleep(for: .milliseconds(400))
        case "edit":
            model.showEditServer()
            try? await Task.sleep(for: .milliseconds(400))
        case "close":
            model.serverSheet?.cancel()
            try? await Task.sleep(for: .milliseconds(300))
        case "field":
            guard let sheet = model.serverSheet, let field = rest.first else { return }
            let text = rest.dropFirst().joined(separator: " ")
            switch field {
            case "name": sheet.name = text
            // `fakehost`: the fake server under the name localhost, another
            // address for the same server (publishing review F28).
            case "address":
                sheet.address = switch text {
                case "fake": fake?.address ?? ""
                case "fakehost": fake?.address.replacingOccurrences(of: "127.0.0.1", with: "localhost") ?? ""
                default: text
                }
            case "key": sheet.setKey(text == "fake" ? FakeImmichServer.validKey : text)
            default: print("debug-script: import server sheet field: unknown")
            }
            try? await Task.sleep(for: .milliseconds(150))
        case "confirm":
            model.serverSheet?.unencryptedConfirmed = rest.first == "on"
            try? await Task.sleep(for: .milliseconds(150))
        case "submit":
            guard let sheet = model.serverSheet else { return }
            sheet.submit()
            await waitForCheck(sheet)
            print("debug-script: import server sheet submit: \(sheetResult(sheet))")
        case "trust":
            guard let sheet = model.serverSheet else { return }
            sheet.trustCertificate()
            await waitForCheck(sheet)
        case "back":
            model.serverSheet?.back()
        case "review":
            // The Edit sheet's Review Certificate page for a changed
            // certificate, with a made-up one (the fake has no TLS): what
            // Review Certificate… opens after a real change (QA Q3; B1).
            guard let sheet = model.serverSheet, sheet.isEdit else {
                return print("debug-script: import server sheet review: open the Edit sheet first")
            }
            let seed = rest.isEmpty ? UUID().uuidString : rest.joined(separator: " ")
            let summary = CertificateSummary(subject: sheet.parsedAddress?.host ?? "", issuer: "debug script", notBefore: nil,
                                             notAfter: nil, fingerprint: CertificateFingerprint(certificateData: Data(seed.utf8)))
            sheet.page = .certificate(summary, changed: true)
            try? await Task.sleep(for: .milliseconds(300))
            print("debug-script: import server sheet review \(summary.fingerprint.colonSeparated)")
        case "remove":
            // Remove Server… in the sheet: the confirmation follows its closing.
            model.serverSheet?.remove()
            try? await Task.sleep(for: .milliseconds(800))
            print("debug-script: import server sheet remove: sheet \(model.serverSheet == nil ? "closed" : "open") "
                  + "asks \(model.removingServer?.name ?? "-")")
        case "print":
            printSheet(model)
        default:
            print("debug-script: unknown import server sheet command")
        }
    }

    private static func sheetResult(_ sheet: ServerSheetModel) -> String {
        switch sheet.page {
        case .certificate(let summary, let changed):
            return "certificate \(changed ? "changed" : "untrusted") \(summary.fingerprint.colonSeparated)"
        case .form:
            return sheet.result?.kind ?? "saved or none"
        }
    }

    /// The sheet's rows as the person sees them, never the key's text.
    private static func printSheet(_ model: CardImportModel) {
        guard let sheet = model.serverSheet else { return print("debug-script: import server sheet: none") }
        var parts = ["import server sheet \(sheet.isEdit ? "edit" : "add")"]
        parts.append("name '\(sheet.name)' effective '\(sheet.effectiveName)' taken \(sheet.nameTaken)")
        parts.append("address '\(sheet.address)' echo '\(sheet.echo ?? "-")'")
        parts.append("key \(sheet.keyEntered ? "entered" : "-")")
        switch sheet.addressState {
        case .unencryptedLocal: parts.append("notice shown confirmed \(sheet.unencryptedConfirmed)")
        case .refused(let host): parts.append("refused \(host)")
        case .unsupportedScheme: parts.append("scheme error")
        default: break
        }
        if let result = sheet.result,
           let text = ServerText.result(result, host: sheet.parsedAddress?.host ?? "", name: sheet.effectiveName,
                                        purpose: sheet.purpose, keyCanPublish: sheet.keyCanPublish) {
            parts.append("result \(result.kind) '\(text.title)' under \(text.concernsAddress ? "address" : "key") "
                         + "detail '\(text.detail)'")
        }
        // Publishing (issue #28): the host's captions and the address warning (R26).
        parts.append("captions '\(ServerText.keyCaptions(sheet.purpose).joined(separator: "' '"))'")
        if sheet.showsAddressWarning { parts.append("warning '\(ServerText.addressChangeWarning)'") }
        parts.append("checking \(sheet.isChecking) default \(sheet.canSubmit ? "enabled" : "dimmed")")
        // The sheet's size against its ideal (design §11, S2).
        let size = model.window?.attachedSheet?.frame.size
        parts.append("size \(size.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-") ideal \(Int(sheet.idealHeight))")
        if case .certificate(let summary, let changed) = sheet.page {
            parts.append("page certificate \(changed ? "changed" : "new") subject '\(summary.subject)' "
                         + "fingerprint \(summary.fingerprint.displayLines.joined(separator: " / "))")
        }
        print("debug-script: " + parts.joined(separator: " "))
    }

    // MARK: The window

    /// The source, scope, range, counts, status, subtitle parts, the grid
    /// state and the inspector's Server rows (design §11).
    private static func printServer(_ model: CardImportModel) {
        guard let browse = model.browse else { return print("debug-script: import server: none") }
        var parts = ["import server \(browse.service.name) \(browse.service.address)"]
        parts.append("state \(stateName(browse.gridState))")
        parts.append("scope \(browse.scopeName) albums \(browse.albums.map { "\($0.name)(\($0.assetCount))" }.joined(separator: ","))")
        parts.append("range \(ServerText.dateRangeText(browse.dates))")
        parts.append("loaded \(browse.assets.count) total \(browse.total.map(String.init) ?? "-") more \(browse.hasMorePages)")
        parts.append("marked \(model.duplicateCount) selected \(model.selectedShots.count)")
        parts.append("status \(browse.isConnecting ? "connecting" : browse.isLoadingPage ? "loading" : "-")")
        if let line = subtitleLine(model, browse) { parts.append("subtitle '\(line)'") }
        parts.append("version \(browse.info?.version.description ?? "-") "
                     + "connection \(browse.isUnencrypted ? "http" : browse.service.certificateFingerprint != nil ? "pinned" : "https") "
                     + "morePermissions \(browse.info?.hasMoreThanNeeded == true)")
        parts.append("project '\(browse.projectName)' note \(model.addsToExistingProject ? "shown" : "hidden")"
                     + " done \(model.doneText ?? "-")")
        if let alert = model.serverAlert { parts.append("alert '\(alert.title)' '\(alert.message)'") }
        print("debug-script: " + parts.joined(separator: " "))
    }

    private static func subtitleLine(_ model: CardImportModel, _ browse: ServerBrowse) -> String? {
        guard !model.shots.isEmpty else { return nil }
        return ServerText.subtitle(ServerSubtitle.of(selected: model.selection.count, loaded: model.shots.count,
                                                     marked: model.duplicateCount, hasMorePages: browse.hasMorePages,
                                                     total: browse.total))
            + (browse.isUnencrypted ? ServerText.notEncryptedSuffix : "")
    }

    private static func stateName(_ state: ServerGridState) -> String {
        switch state {
        case .connecting: "connecting"
        case .cantConnect(let result): "cantConnect(\(result.kind))"
        case .loading: "loading"
        case .noPhotosAll: "noPhotosAll"
        case .noPhotosInAlbum: "noPhotosInAlbum"
        case .noPhotosInRange: "noPhotosInRange"
        case .albumGone: "albumGone"
        case .photos: "photos"
        }
    }

    // MARK: Waiting

    private static func waitForCheck(_ sheet: ServerSheetModel) async {
        try? await Task.sleep(for: .milliseconds(100))
        for _ in 0..<300 where sheet.isChecking { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .milliseconds(200))
    }

    private static func waitForConnect(_ model: CardImportModel) async {
        try? await Task.sleep(for: .milliseconds(100))
        for _ in 0..<300 where model.browse?.isConnecting == true { try? await Task.sleep(for: .milliseconds(50)) }
        await waitForPage(model)
    }

    private static func waitForPage(_ model: CardImportModel) async {
        try? await Task.sleep(for: .milliseconds(100))
        for _ in 0..<300 where model.browse?.isLoadingPage == true || model.browse?.albumsLoaded == false {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(300))
    }
}
