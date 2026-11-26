import AppKit
import Foundation
import PhotoCore
import PhotoFixtures
import PhotoUI

/// The debug script's publishing commands (issue #28, design §14), words
/// after `publish`. The server is the fake one (`import server fake start`,
/// then `import server add Home fake`); nothing here prints a key.
///
///     publish sheet                       File ▸ Publish… on the targets; waits for the check
///     publish print                       the sheet: server, check, issues, album, captions, buttons
///     publish server <name>               chooses a saved server; waits for the check
///     publish album none|new <name>|existing <name> | show timeline|archive | stacking on|off
///     publish description <text>          typed for this run
///     publish settings open|cancel|done | settings metadata all|nolocation|copyright|none
///     publish map open|cancel|done|print | map add <folder> <server path>
///     publish originals                   Check Originals; waits and prints the result
///     publish start                       Publish N Photos; prints whether it asked or started
///     publish answer skip|newcopy|cancel  the Skip or New Copy alert
///     publish stopatsent                  stops the run when the next upload is fully sent
///     publish wait                        until the run ends; prints the Activity row
///     publish stop                        File ▸ Stop Publishing
///     publish results [print|retry|close]
///     publish serversheet add|edit|close|print|submit | field name|address|key <text> | confirm on|off
///     publish menu                        what Publish, Publish Results and Stop allow
@MainActor
enum DebugPublishCommands {
    static func run(_ words: [String], model: LibraryModel) async {
        let publish = model.publish
        let rest = Array(words.dropFirst())
        switch words.first {
        case "sheet":
            publish.begin()
            await settle(publish)
            printSheet(model)
        case "print":
            printSheet(model)
        case "server":
            let name = rest.joined(separator: " ")
            guard let service = publish.servers.first(where: { $0.name == name }) else {
                return print("debug-script: publish server: no '\(name)'")
            }
            await publish.choose(service)
            await settle(publish)
        case "album":
            switch rest.first {
            case "new":
                publish.newAlbumName = rest.dropFirst().joined(separator: " ")
                publish.album = .new(name: publish.newAlbumName)
            case "existing":
                let name = rest.dropFirst().joined(separator: " ")
                if let album = publish.albums.first(where: { $0.name == name }) {
                    publish.album = .existing(id: album.id, name: album.name)
                } else {
                    print("debug-script: publish album: no '\(name)'")
                }
            default:
                publish.album = .none
            }
        case "show":
            publish.visibility = rest.first == "archive" ? .archive : .timeline
        case "stacking":
            publish.stacking = rest.first != "off"
            await settle(publish)
        case "description":
            publish.description = rest.joined(separator: " ")
        case "settings":
            switch rest.first {
            case "open": publish.showSettingsPage()
            case "cancel": publish.closeSettingsPage(keeping: false)
            case "done": publish.closeSettingsPage(keeping: true)
            case "metadata":
                let level: ExportSettings.Metadata = switch rest.dropFirst().first {
                case "nolocation": .noLocation
                case "copyright": .copyright
                case "none": .none
                default: .all
                }
                publish.editor.settings.metadata = level
            default: break
            }
        case "map":
            switch rest.first {
            case "open": publish.showFolderMapPage()
            case "cancel": publish.closeFolderMapPage(saving: false)
            case "done":
                publish.closeFolderMapPage(saving: true)
                try? await Task.sleep(for: .milliseconds(200))
            case "add":
                guard rest.count >= 3 else { return }
                publish.addFolder(URL(fileURLWithPath: (rest[1] as NSString).expandingTildeInPath, isDirectory: true))
                if let last = publish.editingMap.indices.last {
                    publish.editingMap[last].serverPath = PublishFolderMapping.serverPathKept(rest.dropFirst(2).joined(separator: " "))
                }
            default:
                for mapping in publish.editingMap {
                    let shown = publish.displayPath(mapping)
                    let example = publish.example(for: mapping).map { PublishText.lookedFor($0.name, at: $0.path) }
                        ?? PublishText.noSelectedPhotoHere
                    print("debug-script: publish map '\(shown.path)'\(shown.connected ? "" : " (not connected)") -> "
                          + "'\(mapping.serverPath)' issues \(PublishFolderMapping.issues(of: mapping, in: publish.editingMap)) "
                          + "example '\(example)'")
                }
                print("debug-script: publish map done \(publish.folderMapCanSave ? "enabled" : "dimmed")")
            }
        case "originals":
            publish.checkOriginals()
            while case .running = publish.originals { try? await Task.sleep(for: .milliseconds(50)) }
            printOriginals(publish)
        case "start":
            let started = await publish.requestPublish()
            if started { model.showsPublishSheet = false }
            if let question = publish.question {
                print("debug-script: publish asks '\(PublishText.questionTitle(question.published, server: publish.service?.name ?? ""))' "
                      + "'\(PublishText.questionMessage(published: question.published, total: question.total))'")
            } else {
                print("debug-script: publish start \(started ? "started" : "refused") issue '\(publish.startIssue ?? "-")'")
            }
        case "answer":
            switch rest.first {
            case "skip": publish.answer(skip: true)
            case "newcopy": publish.answer(skip: false)
            default: publish.question = nil
            }
        case "stopatsent":
            publish.debugOnFullySent = { Task { @MainActor in model.publish.cancel() } }
        case "wait":
            while publish.isPublishing { try? await Task.sleep(for: .milliseconds(50)) }
            publish.debugOnFullySent = nil
            printActivity(model)
        case "stop":
            if let job = model.newestStoppableJob { model.stop(job) }
            try? await Task.sleep(for: .milliseconds(100))
            printMenu(model)
            let job = ActivityToolbarItem.jobs(model).first { $0.id == "publish" }
            print("debug-script: publish activity '\(job?.detail ?? "-")' stop \(job.map { $0.stopDisabled ? "dimmed" : "enabled" } ?? "-")")
        case "results":
            switch rest.first {
            case "retry":
                if let run = publish.resultsRun { publish.retry(run.id) }
                try? await Task.sleep(for: .milliseconds(300))
            case "close":
                model.showsPublishResults = false
            default:
                if !model.showsPublishResults { publish.showResults() }
                try? await Task.sleep(for: .milliseconds(200))
                printResults(publish)
            }
        case "serversheet":
            await serverSheet(rest, publish: publish)
        case "menu":
            printMenu(model)
        default:
            print("debug-script: unknown publish command")
        }
    }

    /// Waits while the server is checked and albums load.
    private static func settle(_ publish: PublishModel) async {
        for _ in 0..<200 {
            try? await Task.sleep(for: .milliseconds(50))
            if publish.check != .checking, publish.albumsState != .loading { break }
        }
    }

    // MARK: Printing

    static func printSheet(_ model: LibraryModel) {
        let publish = model.publish
        var lines: [String] = []
        lines.append("sheet \(model.showsPublishSheet ? "open" : "closed") page \(publish.page) "
                     + "title '\(PublishText.title(publish.versionIDs.count))' videos \(publish.skippedVideos) "
                     + "offline \(publish.offlinePhotos) hdr \(publish.hdrPhotos)")
        let service = publish.service
        lines.append("server '\(service?.name ?? "-")' address '\(service?.address ?? "-")' "
                     + "notEncrypted \(service?.serverAddress?.scheme == .http) servers \(publish.servers.map(\.name))")
        switch publish.check {
        case .idle: lines.append("check idle")
        case .checking: lines.append("check checking")
        case .passed(let info): lines.append("check passed version \(info.version) account \(info.ownerID == nil ? "-" : "read")")
        case .failed(let result):
            let text = ServerText.result(result, host: service?.serverAddress?.host ?? "", name: service?.name ?? "",
                                         purpose: .publishing)
            lines.append("check failed \(result.kind) '\(text?.title ?? "")' '\(text?.detail ?? "")'")
        }
        let missing = publish.missing
        if !missing.server.isEmpty { lines.append("issue server '\(PublishText.cantPublish(missing.server))'") }
        if !missing.album.isEmpty { lines.append("issue album '\(PublishText.albumNeeds(missing.album))'") }
        if !missing.stacking.isEmpty { lines.append("issue stacking '\(PublishText.stackingNeeds(missing.stacking))'") }
        let canList = publish.serverInfo.map { PublishPermissions.canListAlbums($0.permissions) } ?? false
        lines.append("album \(publish.album) items [None, New Album…\(canList ? "" : " (dimmed: \(PublishText.albumsNeedRead))")"
                     + "\(canList ? publish.albums.map { ", " + ServerText.album($0) }.joined() : "")] "
                     + "state \(publish.albumsState) gone \(publish.rememberedAlbumGone) "
                     + "nameTaken \(publish.newAlbumNameTaken != nil)")
        let archive = publish.visibility == .archive ? (publish.stacking ? PublishText.archiveStacked : PublishText.archivePlain) : "-"
        lines.append("show \(publish.visibility.rawValue) caption '\(archive)'")
        lines.append("stacking \(publish.stacking) folders \(publish.folderMap.count) "
                     + "noOriginalYet \(publish.folderMap.isEmpty && publish.noneLinked) checkOriginals \(publish.canCheckOriginals ? "enabled" : "dimmed")")
        lines.append("settings '\(PublishText.settingsSummary(publish.editor.settings))' issue '\(publish.settingsIssue ?? "-")' "
                     + "description '\(publish.description)' sent \(publish.descriptionIsSent) "
                     + "caption '\(PublishText.filesCaption(publish.editor.settings.metadata))'")
        lines.append("publish \(publish.canPublish ? "enabled" : "dimmed") confirming \(publish.isConfirming)")
        for line in lines { print("debug-script: publish " + line) }
    }

    private static func printOriginals(_ publish: PublishModel) {
        switch publish.originals {
        case .notRun: print("debug-script: publish originals not run")
        case .running(let done, let total): print("debug-script: publish originals running \(done) of \(total)")
        case .failed(let reason): print("debug-script: publish originals '\(PublishText.checkStopped(reason))'")
        case .result(let result):
            print("debug-script: publish originals '\(PublishText.originalsSummary(found: result.found, of: result.checked))' "
                  + "offline \(result.offline)")
            for group in result.groups {
                for photo in group.photos {
                    print("debug-script: publish originals \(PublishText.groupTitle(group.group)): \(photo.name): "
                          + PublishText.reason(photo.reason))
                }
            }
        }
    }

    private static func printActivity(_ model: LibraryModel) {
        guard let message = model.activity.messages.last else { return print("debug-script: publish activity none") }
        print("debug-script: publish activity \(message.isWarning ? "warning" : "info") '\(message.title ?? "")' "
              + "action \(message.actionID == nil ? "-" : PublishText.showResults)")
        for line in message.text.components(separatedBy: "\n") { print("debug-script: publish activity line '\(line)'") }
    }

    private static func printResults(_ publish: PublishModel) {
        guard let run = publish.resultsRun else { return print("debug-script: publish results none") }
        let album = run.album.name ?? ""
        for item in run.items {
            var notes: [String] = []
            notes += item.failures.map { PublishText.failure($0, already: item.isDuplicate) }
            if let left = item.left { notes.append(PublishText.notFinished(left, album: album)) }
            if case .noOriginal(let reason)? = item.stacking { notes.append(PublishText.reason(reason)) }
            if let reason = item.alreadyThere { notes.append(PublishText.alreadyThereReason(reason)) }
            if item.stacking == .stacked { notes.append("stacked") }
            let upload = switch item.upload {
            case .pending: "not uploaded"
            case .accepted(.created): "published"
            case .accepted(.duplicate): "already on the server"
            case .failed: "failed"
            }
            print("debug-script: publish results \(item.name): \(upload); \(notes.joined(separator: " "))")
        }
        let refusal = publish.retryRefusal(run).map(PublishText.retryRefusal)
        print("debug-script: publish results retry \(run.offersRetry ? (refusal == nil ? "enabled" : "dimmed '\(refusal!)'") : "absent") "
              + "leavesOut \(run.retryLeavesOutUnreached) album \(run.album)")
    }

    private static func printMenu(_ model: LibraryModel) {
        let state = LibraryMenuState(model)
        let stop = state.stoppableJob.map { "\($0)" } ?? "-"
        let stopOn = state.stoppableJob != nil && !(state.stoppableJob == .publish && state.publishIsEnding)
        print("debug-script: publish menu publish \(state.canPublish ? "enabled" : "dimmed") results "
              + "\(state.hasPublishResults ? "enabled" : "dimmed") stop \(stop) \(stopOn ? "enabled" : "dimmed") "
              + "ending \(state.publishIsEnding)")
    }

    // MARK: The Server sheet from Publish (design §4)

    private static func serverSheet(_ words: [String], publish: PublishModel) async {
        let rest = Array(words.dropFirst())
        switch words.first {
        case "add":
            publish.showServerSheet(editing: false)
            try? await Task.sleep(for: .milliseconds(600))
        case "edit":
            publish.showServerSheet(editing: true)
            try? await Task.sleep(for: .milliseconds(600))
        case "close":
            publish.serverSheet?.cancel()
            try? await Task.sleep(for: .milliseconds(600))
        case "field":
            guard let sheet = publish.serverSheet, let field = rest.first else { return }
            let text = rest.dropFirst().joined(separator: " ")
            switch field {
            case "name": sheet.name = text
            case "address": sheet.address = text
            case "key": sheet.setKey(text == "fake" ? FakeImmichServer.validKey : text)
            default: break
            }
        case "confirm":
            publish.serverSheet?.unencryptedConfirmed = rest.first == "on"
        case "submit":
            guard let sheet = publish.serverSheet else { return }
            sheet.submit()
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(50))
                if !sheet.isChecking { break }
            }
            try? await Task.sleep(for: .milliseconds(600))
        default:
            guard let sheet = publish.serverSheet else { return print("debug-script: publish serversheet: none") }
            var parts = ["publish serversheet \(sheet.isEdit ? "edit" : "add") purpose \(sheet.purpose)"]
            parts.append("remove \(sheet.offersRemove ? "offered" : "absent")")
            parts.append("captions '\(ServerText.keyCaptions(sheet.purpose).joined(separator: "' '"))'")
            if sheet.showsAddressWarning { parts.append("warning '\(ServerText.addressChangeWarning)'") }
            if let result = sheet.result,
               let text = ServerText.result(result, host: sheet.parsedAddress?.host ?? "", name: sheet.effectiveName,
                                            purpose: sheet.purpose, keyCanPublish: sheet.keyCanPublish) {
                parts.append("result \(result.kind) '\(text.title)' '\(text.detail)'")
            }
            parts.append("default \(sheet.canSubmit ? "enabled" : "dimmed")")
            print("debug-script: " + parts.joined(separator: " "))
        }
    }
}
