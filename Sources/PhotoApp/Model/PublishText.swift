import Foundation
import PhotoCore
import PhotoUI

/// The words of publishing (issue #28, design §2 to §10). No sentence names
/// the key or a URL; the server's own words are kept, cut at 200 characters.
enum PublishText {
    // MARK: Commands (design §2)

    static var menuTitle: String { String(localized: "Publish…", comment: "File menu and context menu: publish the selected photos") }
    static var resultsMenuTitle: String { String(localized: "Publish Results…", comment: "File menu: the last publish run's results") }
    static var stopMenu: String { String(localized: "Stop Publishing", comment: "File menu (⌘.): stops the running publish") }
    static var toolbarLabel: String { String(localized: "Publish", comment: "Toolbar item") }
    static var toolbarHelp: String { String(localized: "Publish the selected photos to a server", comment: "Toolbar item tooltip") }
    static var showResults: String { String(localized: "Show Results…", comment: "Activity: opens a publish run's results") }

    static func jobTitle(_ name: String) -> String {
        String(localized: "Publish to “\(name)”", comment: "Activity title and results sheet title; the server's name")
    }

    /// Activity messages that open a run's results carry this.
    static func resultsActionID(_ id: UUID) -> String { "publishResults:\(id.uuidString)" }

    static func runID(fromAction action: String) -> UUID? {
        guard action.hasPrefix("publishResults:") else { return nil }
        return UUID(uuidString: String(action.dropFirst("publishResults:".count)))
    }

    // MARK: The sheet (design §3)

    static func title(_ count: Int) -> String {
        String(localized: "Publish \(count) Photos", comment: "Publish sheet: title and the default button")
    }

    static func offlineLine(_ count: Int) -> String {
        String(localized: "\(count) originals are offline and won't be published.", comment: "Publish sheet header")
    }

    static func hdrLine(_ count: Int) -> String {
        String(localized: "\(count) photos have HDR on. Published photos are SDR.", comment: "Publish sheet header")
    }

    static var notEncrypted: String {
        String(localized: "Not encrypted (http). Your key and photos cross the network unprotected.",
               comment: "Publish sheet: a plain http server, always shown")
    }

    static func checking(_ name: String) -> String {
        String(localized: "Checking “\(name)”…", comment: "Publish sheet: the server is being checked")
    }

    static var keyUnreadable: String { String(localized: "The key couldn't be read", comment: "Publish sheet: Keychain failure") }

    /// A certificate the system doesn't trust, met by the publish sheet's
    /// check (review D-3).
    static var untrustedTitle: String {
        String(localized: "This server's certificate isn't trusted", comment: "Publish sheet: untrusted certificate, title")
    }

    static var untrustedDetail: String {
        String(localized: "macOS doesn't trust the certificate this server presented. Review it before publishing. Nothing was sent to the server.",
               comment: "Publish sheet: untrusted certificate, detail")
    }

    /// The title of a failed server check, as the sheet shows it.
    static func checkTitle(_ result: ConnectionCheckResult, service: RemoteServiceRecord?) -> String {
        switch result {
        case .keychain: return keyUnreadable
        case .untrustedCertificate: return untrustedTitle
        default:
            return ServerText.result(result, host: service?.serverAddress?.host ?? "", name: service?.name ?? "",
                                     purpose: .publishing)?.title ?? ""
        }
    }
    static var noServerTitle: String { String(localized: "Add a Server to Publish To", comment: "Publish sheet with no saved server") }
    static var noServerDetail: String { String(localized: "Photos are published to an Immich server.", comment: "Publish sheet with no saved server") }
    static var loadingAlbums: String { String(localized: "Loading albums…", comment: "Publish sheet: the album pop-up while albums load") }
    static var newAlbumItem: String { String(localized: "New Album…", comment: "Publish sheet: album pop-up item") }
    static var chooseAlbum: String { String(localized: "Choose an Album", comment: "Publish sheet: album pop-up when the remembered album is gone") }
    static var albumsNeedRead: String { String(localized: "Albums need album.read on this key", comment: "Publish sheet: album pop-up, dimmed line") }
    static var useExistingAlbum: String { String(localized: "Use the Existing Album", comment: "Publish sheet: button beside the note") }

    static func albumsFailed(_ reason: String) -> String {
        String(localized: "The server's albums couldn't be listed: \(reason)", comment: "Publish sheet: album list failed")
    }

    static var albumNameTaken: String {
        String(localized: "An album with this name already exists. A second one will be made.",
               comment: "Publish sheet: the new album's name is an existing album's")
    }

    static func albumGone(_ name: String) -> String {
        String(localized: "“\(name)”, used last time, is no longer on this server. Choose another album or None.",
               comment: "Publish sheet: the remembered album is gone")
    }

    static var archivePlain: String {
        String(localized: "Published photos go to the archive, not the timeline.", comment: "Publish sheet: Archive caption")
    }

    static var archiveStacked: String {
        String(localized: "Published photos go to the archive, not the timeline. A stacked original leaves the timeline with its edit, and so does the rest of its stack. Their own visibility isn't changed.",
               comment: "Publish sheet: Archive caption with stacking on (R6)")
    }

    static var stackingCaption: String {
        String(localized: "Each photo goes on top of its original in Immich. A photo whose original isn't found is still published, unstacked. Check Originals shows which ones before anything is uploaded.",
               comment: "Publish sheet: Stack with original caption")
    }

    static var noOriginalYet: String {
        String(localized: "No original can be found yet: none of these photos was imported from this server, and no folder is mapped.",
               comment: "Publish sheet: no link and no folder map")
    }

    static func folderCount(_ count: Int) -> String {
        count == 0 ? String(localized: "No folders", comment: "Publish sheet: folder map row")
            : String(localized: "\(count) folders", comment: "Publish sheet: folder map row")
    }

    static var descriptionPrompt: String {
        String(localized: "Leave empty to keep each photo's own", comment: "Publish sheet: description field prompt")
    }

    static func descriptionNotSent(_ level: ExportSettings.Metadata) -> String {
        String(localized: "Not sent: Include is set to “\(levelName(level))”.", comment: "Publish sheet: description at a level without it")
    }

    static func filesCaption(_ level: ExportSettings.Metadata) -> String {
        let base = String(localized: "Immich is told each file's name and capture date. Ratings, flags and labels are never sent.",
                          comment: "Publish sheet: Files caption")
        guard level == .all else { return base }
        return base + " " + String(localized: "Location is included.", comment: "Publish sheet: Files caption at All metadata")
    }

    static func levelName(_ level: ExportSettings.Metadata) -> String {
        switch level {
        case .all: String(localized: "All metadata")
        case .noLocation: String(localized: "All except location")
        case .copyright: String(localized: "Copyright and contact only")
        case .none: String(localized: "None")
        }
    }

    /// "JPEG 90% · sRGB · Full Size · All metadata · Watermark" (design §3.6).
    static func settingsSummary(_ settings: ExportSettings) -> String {
        var parts: [String] = []
        switch settings.format {
        case .jpeg:
            parts.append(String(localized: "JPEG \(settings.jpegQuality.formatted(.percent.precision(.fractionLength(0))))",
                                comment: "Publish sheet settings summary: format and quality"))
        case .tiff:
            parts.append(String(localized: "TIFF \(settings.tiffBitDepth)-bit", comment: "Publish sheet settings summary: format and depth"))
        }
        let space = switch settings.colorSpace {
        case .sRGB: String(localized: "sRGB")
        case .displayP3: String(localized: "Display P3")
        case .adobeRGB: String(localized: "Adobe RGB (1998)")
        case .proPhoto: String(localized: "ProPhoto RGB")
        }
        parts.append(space)
        let size = switch settings.sizing {
        case .full: String(localized: "Full Size")
        case .fit: String(localized: "Fit \(settings.boxWidth) × \(settings.boxHeight)", comment: "Publish sheet settings summary")
        case .longEdge: String(localized: "Long Edge \(settings.edgeLength)", comment: "Publish sheet settings summary")
        case .shortEdge: String(localized: "Short Edge \(settings.edgeLength)", comment: "Publish sheet settings summary")
        case .percent: (settings.percent / 100).formatted(.percent.precision(.fractionLength(0)))
        }
        parts.append(size)
        parts.append(levelName(settings.metadata))
        if settings.activeWatermark != nil { parts.append(String(localized: "Watermark", comment: "Publish sheet settings summary")) }
        if settings.naming == .template { parts.append(String(localized: "Template names", comment: "Publish sheet settings summary")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Permissions (design §5)

    static func list(_ names: [String]) -> String { ListFormatter.localizedString(byJoining: names) }

    static func cantPublish(_ names: [String]) -> String {
        String(localized: "This key can't publish. It is missing \(list(names)).", comment: "Publish sheet: Server section issue")
    }

    static func albumNeeds(_ names: [String]) -> String {
        names.count == 1
            ? String(localized: "An album needs \(list(names)) on this key. Add it, or choose None.", comment: "Publish sheet: Album issue, one permission")
            : String(localized: "An album needs \(list(names)) on this key. Add them, or choose None.", comment: "Publish sheet: Album issue, several permissions")
    }

    static func stackingNeeds(_ names: [String]) -> String {
        names.count == 1
            ? String(localized: "Stacking needs \(list(names)) on this key. Add it, or turn off Stack with original.", comment: "Publish sheet: Stacking issue, one permission")
            : String(localized: "Stacking needs \(list(names)) on this key. Add them, or turn off Stack with original.", comment: "Publish sheet: Stacking issue, several permissions")
    }

    static var fixPermissions: String {
        String(localized: "Add the permissions in Immich, or choose Edit Server… to enter another key.", comment: "Publish sheet: under the Server section for any gap")
    }

    // MARK: Folder map (design §6)

    static func folderMapTitle(_ name: String) -> String {
        String(localized: "Folder Map for “\(name)”", comment: "Publish sheet: folder map page title")
    }

    static var folderMapExplanation: String {
        String(localized: "Tell the app where Immich sees your folders, so it can find originals Immich reads from an external library. Photos imported from this server don't need this. When folders overlap, the longest one wins.",
               comment: "Folder map page")
    }

    static var folderPanelMessage: String {
        String(localized: "Choose a folder Immich reads from an external library.", comment: "Folder map: open panel message")
    }

    static var notConnected: String { String(localized: "(not connected)", comment: "Folder map: the folder's volume is away") }

    static func lookedFor(_ name: String, at path: String) -> String {
        String(localized: "\(name) is looked for at \(path)", comment: "Folder map: the example")
    }

    static var noSelectedPhotoHere: String { String(localized: "No selected photo is in this folder.", comment: "Folder map: no example") }
    static var enterServerPath: String { String(localized: "Enter the path on the server, or remove this folder.", comment: "Folder map issue") }
    static var folderAlreadyMapped: String { String(localized: "This folder is already in the map.", comment: "Folder map issue") }
    static var pathsStartWithSlash: String { String(localized: "Server paths usually start with /.", comment: "Folder map note") }

    // MARK: Check Originals and reasons (design §7)

    static func originalsProgress(_ done: Int, _ total: Int) -> String {
        String(localized: "Checking originals… \(done) of \(total)", comment: "Check Originals progress")
    }

    static func originalsSummary(found: Int, of total: Int) -> String {
        // Two numbers and no noun after them, so one photo reads right (review D-6).
        String(localized: "Originals found: \(found) of \(total).", comment: "Check Originals result")
    }

    static func originalsOffline(_ count: Int) -> String {
        String(localized: "\(count) photos are offline and wouldn't be published.", comment: "Check Originals result")
    }

    static var unstackedNote: String {
        String(localized: "Photos without an original are published unstacked.", comment: "Check Originals result")
    }

    static func checkStopped(_ reason: String) -> String {
        String(localized: "The check stopped: \(reason)", comment: "Check Originals failed")
    }

    static func andMore(_ count: Int) -> String { String(localized: "And \(count) more.") }

    static func groupTitle(_ group: NoOriginalReason.Group) -> String {
        switch group {
        case .noMappedFolder: String(localized: "No mapped folder", comment: "No original: group")
        case .importedOriginalNotFound: String(localized: "Imported original not found", comment: "No original: group")
        case .nothingAtPath: String(localized: "Nothing at the mapped path", comment: "No original: group")
        case .moreThanOne: String(localized: "More than one match", comment: "No original: group")
        case .sizeDiffers: String(localized: "Size differs", comment: "No original: group")
        case .publishedHere: String(localized: "Published from here", comment: "No original: group")
        case .inTrash: String(localized: "In the trash", comment: "No original: group")
        case .hidden: String(localized: "Hidden", comment: "No original: group")
        case .anotherAccount: String(localized: "Another account's", comment: "No original: group")
        case .notPhoto: String(localized: "Not a photo", comment: "No original: group")
        }
    }

    /// The reason sentence (design §7.1). Never says deleted or locked.
    static func reason(_ reason: NoOriginalReason) -> String {
        let capitals = String(localized: "Capital letters count.", comment: "No original: after a path")
        switch reason {
        case .noMappedFolder:
            return String(localized: "not imported from this server, and no mapped folder holds it.", comment: "No original")
        case .linkedNotReturned(nil):
            return String(localized: "the server didn't return the photo it was imported from, and no mapped folder holds it.",
                          comment: "No original")
        case .linkedNotReturned(let path?):
            return String(localized: "the server didn't return the photo it was imported from, and nothing is at \(path).",
                          comment: "No original") + " " + capitals
        case .nothingAtPath(let path):
            return String(localized: "nothing at \(path).", comment: "No original") + " " + capitals
        case .moreThanOne(let path):
            return String(localized: "more than one photo at \(path).", comment: "No original")
        case .sizeDiffers(let path):
            return String(localized: "a photo at \(path) has a different size.", comment: "No original")
        case .publishedHere(let path):
            return String(localized: "a photo at \(path) was published from your library, and nothing there can be used.",
                          comment: "No original")
        case .linkedPublishedHere:
            return String(localized: "the photo it was imported from was published from your library.", comment: "No original")
        case .inTrash:
            return String(localized: "its original is in the server's trash.", comment: "No original")
        case .hidden:
            return String(localized: "its original is hidden on the server.", comment: "No original")
        case .anotherAccount(let path?):
            return String(localized: "a photo at \(path) belongs to another account.", comment: "No original")
        case .anotherAccount(nil):
            return String(localized: "its original belongs to another account.", comment: "No original")
        case .notPhoto(let path?):
            return String(localized: "an item at \(path) isn't a photo.", comment: "No original")
        case .notPhoto(nil):
            return String(localized: "its original isn't a photo.", comment: "No original")
        }
    }

    // MARK: Skip or New Copy (design §8)

    static func questionTitle(_ count: Int, server: String) -> String {
        String(localized: "\(count) photos were already published to “\(server)”", comment: "Skip or New Copy alert title")
    }

    static func questionMessage(published: Int, total: Int) -> String {
        // One published photo is "it" (review D-7).
        let base = published == 1
            ? String(localized: "Skip leaves it as it is on the server. New Copy publishes it again; no photo on the server is replaced, and a file that hasn't changed may be reported as already there.",
                     comment: "Skip or New Copy alert message: one photo was already published")
            : String(localized: "Skip leaves them as they are on the server. New Copy publishes them again; no photo on the server is replaced, and a file that hasn't changed may be reported as already there.",
                     comment: "Skip or New Copy alert message")
        let others = total - published
        guard others > 0 else { return base }
        return base + " " + String(localized: "The other \(others) photos are published either way.", comment: "Skip or New Copy alert message")
    }

    static var skip: String { String(localized: "Skip", comment: "Skip or New Copy alert button") }
    static var newCopy: String { String(localized: "New Copy", comment: "Skip or New Copy alert button") }

    // MARK: Running (design §9)

    static func detail(_ progress: PublishProgress, name: String) -> String {
        switch progress.phase {
        case .checking:
            checking(name)
        case .rendering:
            String(localized: "Rendering \(progress.current) of \(progress.total)", comment: "Activity: publishing")
        case .uploading:
            String(localized: "Uploading \(progress.current) of \(progress.total)", comment: "Activity: publishing")
        case .waiting:
            ServerText.waiting(name)
        case .ending where progress.awaitsAnswer:
            String(localized: "Stopping. Waiting for “\(name)” to answer…", comment: "Activity: an ending publish waits for answers")
        case .ending:
            // Nothing fully sent is awaited (review D-1).
            String(localized: "Stopping…", comment: "Activity: a publish is ending, no answer awaited")
        }
    }

    static var quitTitle: String { String(localized: "Quit While Publishing?", comment: "Quit alert in the library app") }

    static var quitMessage: String {
        String(localized: "Photos already on the server stay there, but unfinished steps can't be retried after quitting. The rest are not published.",
               comment: "Quit alert in the library app: a publish runs")
    }

    static var keepPublishing: String { String(localized: "Keep Publishing", comment: "Quit alert button") }

    // MARK: Results (design §10)

    static func stopTitle(_ stop: PublishStop, service: RemoteServiceRecord) -> String {
        let name = service.name
        return switch stop {
        case .stopped: ""
        case .unreachable: String(localized: "“\(name)” stopped responding", comment: "Server import alert title")
        case .keyRejected: String(localized: "“\(name)” rejected the API key", comment: "Server import alert title")
        case .certificateChanged: String(localized: "The certificate of “\(name)” has changed", comment: "Server import alert title")
        case .missingPermission(let permission):
            String(localized: "The API key is missing \(permission)", comment: "Publish results: a permission stopped the run")
        // What a retry's check found, in its own title (review D-5).
        case .checkFailed(let result): checkTitle(result, service: service)
        }
    }

    /// The Activity row's lines, in design §10.1's order, only those not zero.
    static func activityLines(_ run: PublishRun) -> [String] {
        let counts = run.counts
        var lines: [String] = []
        if let stop = run.ending?.stop {
            if stop == .stopped {
                let done = run.items.filter(\.isAccepted).count
                // Two numbers and no noun after them (review D-6).
                lines.append(String(localized: "Publishing stopped. Photos on the server: \(done) of \(run.items.count).",
                                    comment: "Publish results: the person stopped"))
            } else {
                lines.append(String(localized: "Publishing stopped: \(stopTitle(stop, service: run.service)).",
                                    comment: "Publish results: a fault stopped the run"))
            }
        }
        if counts.published > 0 {
            lines.append(String(localized: "Published \(counts.published) photos.", comment: "Publish results"))
        } else if counts.alreadyOnServer == 0 {
            lines.append(String(localized: "No photos were published.", comment: "Publish results"))
        }
        if counts.alreadyOnServer > 0 {
            lines.append(String(localized: "\(counts.alreadyOnServer) were already on the server.", comment: "Publish results"))
        }
        for reason in AlreadyThereReason.allCases {
            if let count = counts.alreadyThere[reason], count > 0 { lines.append(alreadyThereLine(reason, count)) }
        }
        if counts.skipped > 0 { lines.append(String(localized: "\(counts.skipped) were skipped.", comment: "Publish results")) }
        if counts.stacked > 0 {
            lines.append(String(localized: "\(counts.stacked) were stacked on their originals.", comment: "Publish results"))
        }
        if counts.notStacked > 0 {
            lines.append(String(localized: "\(counts.notStacked) are not stacked: no original was found.", comment: "Publish results"))
        }
        if counts.videos > 0 { lines.append(String(localized: "\(counts.videos) videos were left out.", comment: "Publish results")) }
        if counts.failed > 0 { lines.append(String(localized: "\(counts.failed) failed.", comment: "Publish results")) }
        if counts.notFinished > 0 {
            lines.append(String(localized: "\(counts.notFinished) are on the server but not finished.", comment: "Publish results"))
        }
        if counts.notPublished > 0 {
            lines.append(String(localized: "\(counts.notPublished) were not published because publishing stopped.",
                                comment: "Publish results"))
        }
        return lines
    }

    static func alreadyThereLine(_ reason: AlreadyThereReason, _ count: Int) -> String {
        switch reason {
        case .inTrash:
            String(localized: "\(count) already there is in the server's trash; nothing else was done with it.", comment: "Publish results")
        case .hidden:
            String(localized: "\(count) already there is hidden on the server; nothing else was done with it.", comment: "Publish results")
        case .unreadable:
            String(localized: "\(count) already there couldn't be read on the server; nothing else was done with it.",
                   comment: "Publish results")
        }
    }

    static func alreadyThereReason(_ reason: AlreadyThereReason) -> String {
        switch reason {
        case .inTrash: String(localized: "in the server's trash.", comment: "Publish results: already there")
        case .hidden: String(localized: "hidden on the server.", comment: "Publish results: already there")
        case .unreadable: String(localized: "couldn't be read on the server.", comment: "Publish results: already there")
        }
    }

    static func alreadyThereCount(_ reason: AlreadyThereReason) -> String {
        switch reason {
        case .inTrash: String(localized: "In the server's trash", comment: "Publish results: count row")
        case .hidden: String(localized: "Hidden on the server", comment: "Publish results: count row")
        case .unreadable: String(localized: "Couldn't be read on the server", comment: "Publish results: count row")
        }
    }

    /// A cause in words: the server's status and its own message in quotes
    /// (review D-4), or the system's sentence.
    static func cause(_ cause: PublishCause) -> String {
        switch cause {
        case .server(let status, let message):
            String(localized: "The server answered \(status).", comment: "Publish results: a server's status; its message follows")
                + (message.map { " “\($0)”" } ?? "")
        case .itemRefused(let message):
            message.map { "“\($0)”" } ?? ""
        case .unreachable(let reason): reason
        case .certificate: String(localized: "The server's certificate has changed", comment: "Server check: certificate changed")
        case .answerUnreadable:
            String(localized: "The server's answer could not be read", comment: "Activity: a server's answer was not what the app reads; ends a sentence")
        case .system(let reason): reason
        }
    }

    /// The failure sentence (design §10.2). `already`: an already-there photo.
    static func failure(_ failure: PublishItemFailure, already: Bool) -> String {
        let published = already ? String(localized: "already on the server, but", comment: "Publish results: starts a failure")
            : String(localized: "published, but", comment: "Publish results: starts a failure")
        switch failure {
        case .offline: return String(localized: "not published: its original is offline.", comment: "Publish results")
        case .unreadable: return String(localized: "not published: its original couldn't be read.", comment: "Publish results")
        case .missingWatermark:
            return String(localized: "not published: it couldn't be rendered.", comment: "Publish results") + " "
                + String(localized: "The watermark image is missing. Choose it again.")
        case .render(let reason):
            return String(localized: "not published: it couldn't be rendered.", comment: "Publish results") + " " + reason
        case .uploadRefused(.server(let status, let message)):
            // Design §10.2 as ruled (review D-4).
            return String(localized: "not published: the server didn't accept the upload (\(status)).", comment: "Publish results")
                + (message.map { " “\($0)”" } ?? "")
        case .uploadRefused(let cause):
            return String(localized: "not published: the server didn't accept the upload.", comment: "Publish results") + " " + Self.cause(cause)
        case .uploadInterrupted:
            return String(localized: "not published: the upload didn't finish.", comment: "Publish results")
        case .removedFromLibrary:
            return String(localized: "it was removed from the library before it was published.", comment: "Publish results")
        case .checkFailed(let cause):
            return String(localized: "already on the server, but the app couldn't check it.", comment: "Publish results") + " " + Self.cause(cause)
        case .makeAlbum(let album, let cause):
            return "\(published) " + String(localized: "the album “\(album)” couldn't be made.", comment: "Publish results") + " " + Self.cause(cause)
        case .albumUnknown(let album, let cause):
            return "\(published) " + String(localized: "the app couldn't tell whether the album “\(album)” was made.", comment: "Publish results")
                + " " + Self.cause(cause)
        case .addToAlbum(let album, let cause):
            return ["\(published) " + String(localized: "not added to “\(album)”.", comment: "Publish results"), Self.cause(cause)]
                .filter { !$0.isEmpty }.joined(separator: " ")
        case .findOriginal(let cause):
            return "\(published) " + String(localized: "not stacked: the original couldn't be checked.", comment: "Publish results")
                + " " + Self.cause(cause)
        case .stackRefused(let message):
            let base = "\(published) " + String(localized: "not stacked: the server refused the stack.", comment: "Publish results")
            return message.map { base + " “\($0)”" } ?? base
        case .stack(let cause):
            return "\(published) " + String(localized: "not stacked.", comment: "Publish results") + " " + Self.cause(cause)
        case .record(let reason):
            return "\(published) " + String(localized: "the app couldn't record it.", comment: "Publish results") + " " + reason
        }
    }

    /// What is left of an unfinished photo (design §10.2). `already`: an
    /// already-there photo, which reads "already on the server, but" (review F16).
    static func notFinished(_ left: PublishItem.Left, album: String, already: Bool) -> String {
        if already {
            return switch left {
            case .check: String(localized: "already on the server, but not checked before publishing stopped.", comment: "Publish results")
            case .album:
                String(localized: "already on the server, but not added to “\(album)” before publishing stopped.", comment: "Publish results")
            case .stack: String(localized: "already on the server, but not stacked before publishing stopped.", comment: "Publish results")
            case .albumAndStack:
                String(localized: "already on the server, but not added to “\(album)” or stacked before publishing stopped.",
                       comment: "Publish results")
            }
        }
        return switch left {
        case .check: String(localized: "already on the server, but not checked before publishing stopped.", comment: "Publish results")
        case .album: String(localized: "published, but not added to “\(album)” before publishing stopped.", comment: "Publish results")
        case .stack: String(localized: "published, but not stacked before publishing stopped.", comment: "Publish results")
        case .albumAndStack:
            String(localized: "published, but not added to “\(album)” or stacked before publishing stopped.", comment: "Publish results")
        }
    }

    static func retryRefusal(_ refusal: PublishModel.RetryRefusal) -> String {
        switch refusal {
        case .running: String(localized: "A publish is already running.", comment: "Publish results: Retry Failed is off")
        case .serverRemoved: String(localized: "This server was removed.", comment: "Publish results: Retry Failed is off")
        case .addressChanged: String(localized: "This server's address has changed since this run.", comment: "Publish results: Retry Failed is off")
        }
    }

    static var retryLeavesOut: String {
        String(localized: "Photos not yet uploaded when you stopped aren't included.", comment: "Publish results: beside Retry Failed")
    }

    /// In Retry Failed's place when a later publish sent every photo it
    /// would cover (review D-12).
    static var retryAlreadySent: String {
        String(localized: "A later publish already sent the photos left to retry.",
               comment: "Publish results: in place of Retry Failed")
    }

    static var retryFailed: String { String(localized: "Retry Failed", comment: "Publish results button") }

    /// Under the publish sheet's Server pop-up when its server was removed
    /// in the import window (review D-13); the results sheet's words.
    static var chosenServerRemoved: String {
        String(localized: "This server was removed.", comment: "Publish sheet: under Server")
    }

    /// Under the publish sheet's Server pop-up when the chosen server's
    /// address or certificate changed while Publish was being confirmed or
    /// its Skip or New Copy question was up (review D-15).
    static var connectionChanged: String {
        String(localized: "This server's address or certificate changed. Nothing was published.",
               comment: "Publish sheet: under Server, after a Publish was given up")
    }
}
