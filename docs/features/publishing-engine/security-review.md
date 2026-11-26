# Security review: publishing-engine (issue #28)

Branch `feature/publishing-engine`, diff against `develop` (12 commits, b9fd872 to b244b48). This is a read-only review. Nothing was built, run or sent to a server; the Keychain and the owner's library were not touched. Two of the candidate findings were checked again by separate read-only passes against the false-positive rules of `/security-review`. Both agreed they are not vulnerabilities (confidence 2/10 and 1/10).

**Verdict: nothing meets the bar for High or Medium.** The branch keeps the Network rule as `status.md` proposes to reword it, and the Referenced masters rule:

- Only the four writes are on the allowlist, and every request is checked before it exists.
- The key goes only as `x-api-key`, and only to the connection's host.
- An upload carries only a file rendered into a fresh per-run temporary folder, with three generated fields and the sanitized name.
- Nothing is written near a master.

One Low finding and four notes follow. None of them is a confidentiality or integrity issue.

Trust model: the server is one the owner added, reached through the existing transport policy and certificate pinning (#271). Its answers are untrusted input. The worst a hostile or compromised server can do through this branch is act on its own data with the owner's key, which it already holds, or stop the app (see N1). The catalog and the debug script are the owner's own (CLI flags and the library are trusted).

## Scope checks

| Item | Result |
| --- | --- |
| Request allowlist | `RemoteRequestAllowlist.entries` (`Remote/ImmichAPI.swift`) gains `GET /assets/{id}` and four writes: `POST /assets`, `POST /albums`, `PUT /albums/{id}/assets`, `POST /stacks`. There is no `DELETE` or `PATCH`. `writes` derives exactly those four. `ImmichEndpoint.method` is a fixed switch per case, so no id can change a method. `makeRequest` checks the allowlist before it builds anything (`RemoteHTTPSession.swift:128-157`). Ids in paths are limited to `[0-9A-Za-z-]{1,64}`, which excludes `/`, `.`, `?`, `#` and `%`. |
| Where the key goes | Unchanged path. `makeRequest` appends the path to the connection's API base and refuses any URL whose host differs. `setValue(connection.key, forHTTPHeaderField: "x-api-key")` is the only place the key is used. Redirects are refused (`completionHandler(nil)`, line 758), and that covers the new `uploadTask` too. HTTP auth challenges are rejected. The run holds the `ImmichClient` it checked at start, and Edit and Remove Server are dimmed for the server being published to, so an edit cannot move a running run to another host. Retry Failed refuses when the saved address changed (`PublishModel.retryRefusal`). |
| Transport and trust | `PublishModel.connect` builds the connection from the saved record (`pinnedFingerprint`, `allowsUnencrypted`), exactly as import's `ServerSource` does. `RemoteHTTPSession.init` re-applies `TransportPolicy` every time. Nothing turns checking off. |
| Key in logs, Activity, debug output | Not found. `PublishJob.log` and `PublishModel.log` are declared and never used. `RemoteConnection`'s description and mirror hide the key (unchanged). `PublishRun` keeps a `RemoteServiceRecord`, which has no key. `PublishCause` keeps the server's message and the system's sentence with URLs stripped (`RemoteHTTPSession.reason`). The URL never held the key anyway. `DebugPublishCommands` and the new `DebugServerCommands` words print names, dates, visibility and byte counts, never a key. `field key fake` sets the fake server's constant key, and a scripted launch uses `InMemoryKeyStore` (`RemoteKeyStores.forLaunch`). |
| What can be uploaded | Only the rendered file. `ItemContext.upload` (`Remote/PublishJob.swift:581-661`) renders with `ExportRenderer.export` into `<run folder>/<order>/`. `ExportSettings.FileFormat` is `jpeg` or `tiff` only, so there is no "copy original" mode. `PublishUploadBody.write` then copies that file into `body.multipart` beside it, and only the body is streamed. The temporary name is the template's name with `/` and `:` replaced (`safeFileName`); it always ends in `.jpg` or `.tif`, so it cannot be `body.multipart` or leave the folder. No sidecar is read or sent. The multipart has no `sidecarData`, `livePhotoVideoId` or other part. |
| Writes near masters | None. The new file writes are under `FileManager.default.temporaryDirectory/me.sesser.gus.publish/<UUID>/` (per user, mode 0700 under `/var/folders`), and the catalog. The folder map's Mac folders are only read for their volume identity and relative path (`PublishModel.mapping(for:)`). |
| Multipart construction | `PublishUploadBody.write` (`Remote/ImmichPublishing.swift:393-435`). The boundary is a fresh `UUID().uuidString`. `fileCreatedAt`, `fileModifiedAt` and `visibility` are generated values. The name goes through `ImportTemplate.sanitize`, then `headerSafe`, which drops `"`, `\` and every `Cc` scalar (CR, LF, NEL included), both in the `filename` field and in `Content-Disposition`. A name cannot close a quoted parameter, start a header, or reach the boundary, which is unknown to anyone typing a name. The typed description is not a multipart field: it becomes the photo's caption and is written into the rendered file's metadata by `ExportMetadata` through ImageIO, at the level chosen. |
| Response caps | 2xx answers keep their per-endpoint caps: upload 64 KiB, asset 1 MiB, album and stack answers 16 MiB, path search 32 MiB, at most 10 pages. A non-2xx body is read to at most 64 KiB (`RemoteAnswer.errorBodyLimit`). An overlong error body is dropped and its status kept. Encoded answers are still refused at their head. The unbounded decode before the head is the accepted #279. |
| Parsing of answers | `JSONDecoder` into small structs, plus `JSONSerialization` for the error `message` (64 KiB at most, cut to 200 characters). Server text reaches the UI only as plain `String`s (`PublishText.cause`, `Text(String)`), never Markdown or a link. |
| SQL | All new SQL is parameterized (`Catalog/RemotePublications.swift`, `PublishOriginals.swift` `publishSources`). `IN` lists use `databaseQuestionMarks` with bound arguments, in chunks of 10,000. |
| Migration v18 | Additive (`CatalogSchema.addPublishing`): two new tables, no existing migration edited, no key stored. `remotePublication.versionId` cascades with its version, and `serviceId` is set to null with its connection. |
| Key-permission check | The Server sheet from Publish requires `asset.upload` and `asset.read` and reads no account (`ServerSheetPurpose`). The Publish sheet's per-option check (`PublishPermissions.missing`) only shapes the UI; the server enforces the key's permissions. Captions name the least permissions. |
| Server-side effects beyond the four writes | `POST /stacks` makes Immich delete the stack rows it merges and drop trashed members (`status.md` item 10, RI-V7, and RI-E1 for a trashed primary). This is a documented, owner-ruled consequence of an allowed create, worded in the proposed Network rule. The code names only the account's own assets: `OriginalRules` requires `ownerID == accountID`, and Immich enforces ownership. |

## Finding

### L1 (Low, reliability and isolation, not a security vulnerability; confidence 9/10 in the facts, 2/10 that it is a security issue): any launch deletes every run's temporary files

`PublishJob.removeLeftovers()` (`Remote/PublishJob.swift:64-66`) removes the whole folder `$TMPDIR/me.sesser.gus.publish`, and `LibraryModel.init` calls it on every launch (`PhotoApp/Model/LibraryModel.swift:846`). The folder name comes from the constant `AppBranding.bundleIdentifier`, not from the running bundle. The app is not sandboxed: there is no entitlements file, and `build-app.sh` signs ad hoc. So every copy of the app run by the same user resolves the same folder. A scripted QA copy started with `--debug-script --library-root …` while the owner's app is publishing therefore deletes that run's rendered files and multipart bodies. The doc comment says "a run in progress is never older than launch", which holds only within one process.

The effect depends on timing:
- Deleted before the body is written: that photo fails as a render failure.
- Deleted after the body is written but before the upload starts: the missing file maps to `RemoteError.unreachable`, which counts as transient. It is retried and then stops the whole run as "server unreachable", which is misleading.
- Deleted during an upload: an upload already reading the file is not affected.

What it cannot do:
- Upload a different file. Each run uses a fresh UUID folder.
- Remove anything outside the folder. `removeItem` does not follow symbolic links, and the folder belongs to the user.

The project keeps test launches away from the owner's data (Library launch guard), so this is worth fixing. It is outside the security bar.

Fix (any one):
- Give each launch its own root, for example by process identifier or the library root's hash, and clean up only roots whose process is gone.
- Remove only run folders older than a day.
- Hold a lock file per run folder and skip locked ones.

## Notes (Info)

### N1: a server can crash the app with an id ending in U+2028 or U+2029

The allowlist matches with `path.range(of:options: .regularExpression)`. ICU's `$` without the multiline option also matches before one line terminator at the very end of the input.

`RemoteAsset.isPlainFileName`, which `ImmichClient.asset(id:)` and `addToAlbum` call first, refuses `Cc` scalars but not U+2028 and U+2029 (`Zl` and `Zp`), and ICU treats both as line terminators. So a hostile server that answers an upload with `{"status":"duplicate","id":"abc "}` gets that id past both checks into `GET /assets/{id}`. There `components.percentEncodedPath += path` receives a raw non-ASCII character. Foundation documents a `fatalError` for an incorrectly percent-encoded value, so the likely outcome is a crash. This was not run.

An id in the middle of a pattern, such as the album id in `PUT /albums/{id}/assets`, is refused as `notAllowed`. The method, host and endpoint cannot change, so the key never leaves the server. This is a denial of service by a server the owner added, which the review's exclusions leave out.

The same gap already exists for `.thumbnail` and `.original`, whose ids are checked by the regex alone (from #271).

Hardening:
- Anchor with `\z`, or check that the match covers the whole path.
- Make `isPlainFileName` (or a stricter id check: `^[0-9A-Za-z-]{1,64}\z`) refuse every non-ASCII id before it reaches a path.

### N2: server-chosen text is shown verbatim

A failed step's reason shows the server's `message`, cut to 200 characters, in the results sheet and Activity, inside quotes after the status. Album names and the server's version are shown as well.

All of it is plain text, with no Markdown and no links. A hostile server could still word a misleading instruction, for example asking the user to paste the key somewhere. This is accepted by design (R23); no action.

### N3: what crosses to the server is what the person chose

With stacking on, Check Originals and the run send the server a path search (`POST /search/metadata`, `originalPath in [...]`). The path is the folder map's server prefix plus the master's path below the mapped Mac folder, in its NFC and NFD forms. Only masters under a folder the person mapped are named, and never their Mac paths above that folder.

The upload's embedded metadata follows the export metadata level the person picked; `.all` includes location. Both are by design (R12, R5).

### N4: Edit Server sends the saved key to a newly typed address

When Edit Server changes the address and no new key is typed, the sheet reads the saved key and checks it against the new host before saving (`ServerSheetModel.submit`). This is unchanged from #271, but the sheet is now also reachable from Publish. It happens only on the person's Save, it is checked under the same transport policy, and a new address starts without a pinned certificate. R26's warning covers records and links, not the key. No action, unless the owner wants Edit to require the key again when the host changes.

## Outside security (for the code reviewer)

`CatalogSchema.swift:471-484`: the new `addPublishing` doc comment was inserted inside `addHDRChoice`'s comment. The v17 text now sits above `addPublishing`, and `addHDRChoice` has no comment.

## Summary of findings

| ID | Severity | Confidence | Where | Short |
| --- | --- | --- | --- | --- |
| L1 | Low (reliability and isolation) | 9/10 facts, 2/10 security | `PublishJob.removeLeftovers`, `LibraryModel.init` | Any launch, a scripted QA copy included, deletes the shared temporary root and breaks a run in progress in another copy |
| N1 | Info (DoS, excluded) | 6/10 | `RemoteRequestAllowlist.permits`, `RemoteAsset.isPlainFileName` | `$` and `Cc`-only filtering let an id ending in U+2028 or U+2029 reach `percentEncodedPath` (likely crash); anchor with `\z`, accept ASCII ids only |
| N2 | Info | n/a | `RemoteAnswer.serverMessage`, `PublishText.cause` | The server's own words are shown as plain text, 200 characters at most |
| N3 | Info | n/a | `OriginalFinder`, export metadata level | The path search and embedded metadata are what the person mapped and chose |
| N4 | Info (from #271) | n/a | `ServerSheetModel.submit` | Editing the address sends the saved key to the new host on Save |

## Second review, 2026-11-26

Scope: `git diff b244b48..41f6d0f -- Sources Tests` (12 commits, three review rounds). Read only, by the method of `/security-review`: nothing was built, run or sent to a server, and the Keychain and the owner's library were not touched. A code reviewer was building in the same checkout, so no test was run either; the tests named here were read, not run.

**Verdict: nothing meets the bar for High or Medium.** L1 and N1 are fixed. One new Low finding (L2) and two notes follow. None of them sends the key to a host that was not saved for it.

### L1 and N1: fixed

| Item | Result |
| --- | --- |
| L1 (shared temporary root deleted by any launch) | **Fixed.** `PublishTemporaryFolders` (new) gives each launch its own folder, `<temporary folder>/<bundle id>.publish/<UUID>/`, made on first use and held by an exclusive `flock` on `<UUID>.lock`. The lock is opened with `O_CREAT \| O_EXCL \| O_EXLOCK \| O_NONBLOCK \| O_CLOEXEC`, mode 0600, before the folder is made (`PublishTemporaryFolders.swift:36-46`). The descriptor stays open for the life of the process (`static let launch`). `O_CLOEXEC` keeps a child, such as ExifTool's `-stay_open` process, from inheriting the lock. `removeLeftovers` (`:54-70`, called from `LibraryModel.init`) removes a folder only when it can take that folder's lock, or when the folder has no lock file at all. `flock` locks belong to an open file description, not a process, so a launch can't take its own lock either and never removes its own folder. `PublishRulesTests.temporaryFoldersPerLaunch` checks a running launch, an ended one and a lock-less folder. Each run still uses its own UUID folder inside the launch folder and removes it when the run ends (`PublishJob.swift:100-102`). See N6 for the two ways a running launch's folder can still lose its protection. |
| N1 (ids ending in U+2028 or U+2029) | **Fixed, in two layers.** (1) `RemoteRequestAllowlist.permits` (`ImmichAPI.swift:170-176`) now matches with `NSRegularExpression` and requires the match to cover the whole path, so ICU's `$` matching before a final line terminator no longer matters. Every pattern is ASCII-only, so any path it permits uses only `/`, ASCII letters, digits and `-`, and `percentEncodedPath += path` can't receive a character that needs encoding. If a pattern ever failed to compile, the check would refuse. (2) `RemoteAsset.isServerID` (`RemoteAsset.swift:60`): 1 to 64 ASCII letters, digits and hyphens. It replaces `isPlainFileName` in `ImmichClient.asset(id:)` and `addToAlbum`. It also now gates import's listing (`ImmichDTO.Asset` → `RemoteAsset`, `ImmichAPI.swift:315`), so the `.thumbnail` and `.original` ids from #271 are checked before they reach a path too. Immich ids are UUIDs, so no real asset is dropped. `PublishRulesTests` (lines 355-366) and `PublishJobTests` (line 1037) cover U+2028, U+2029, LF, CR, NEL, CRLF, `é`, `/`, `.`, a space and the empty id. |
| "Outside security" note (comment inside `addHDRChoice`'s) | Fixed: the v17 comment is back above `addHDRChoice` (`CatalogSchema.swift`). |

### Scope checks (what changed)

| Item | Result |
| --- | --- |
| File deletion outside the library (`PublishTemporaryFolders`) | Deletion is limited to entries directly under the base folder. `FileManager.removeItem` removes a symbolic link, not its target, and does not follow links inside a folder it removes. What can go: (a) any entry whose name doesn't end in `.lock` and has no matching lock file; (b) a folder and its lock file once nothing holds the lock. Both happen once, at launch. The base folder is under `$TMPDIR`, the per-user 0700 folder in `/var/folders`. Only the same user (or root) can plant anything there, and a sandboxed app has its own temporary folder. Hardening for a tampered base is in N5. |
| Lock handling | Correct for the cases it names: a crashed or quit launch's lock is free and its folder goes, and a running launch's lock is held. Two narrow ways a running launch's folder can look free are in N6. They are reliability issues, like L1 was. |
| Where the key can be sent | Unchanged at the transport layer. `PublishConnection.connect` (`PublishRetry.swift`, moved out of `PublishModel`) builds the connection from the saved record (`pinnedFingerprint`, `allowsUnencrypted`) exactly as before, and `RemoteHTTPSession.init` re-applies `TransportPolicy`. **Retry Failed** reads the servers again, refuses when the address changed (`retryRefusal`, `PublishModel.swift:928`), then connects with the record it just compared. So a retry contacts only the run's address, with the key and trusted certificate as saved now (the person's current choice). **The sheet re-checking a changed server** (F28, `serversChanged` → `PublishServerChange.after` → `choose(_:keepingChoices: true)`, only while the sheet shows) sends the key only to the address just saved. `ServerFormRules.needsCheck` makes an address change pass a check with that key before the record is saved (N4). So the re-check reaches no new host. **The exception** is a Publish being confirmed, or a Skip or New Copy question, when the address changes: see L2. |
| Upload ending and progress (`RemoteHTTPSession.upload`, `RemoteUploadEnding`) | Bookkeeping only: a per-upload `Mutex` state and an awaiting count report "waiting for an answer" to the Activity row. The cancellation rule is unchanged: a body not fully sent is cancelled at once, and a fully sent one is cancelled at the run's deadline by the same detached task. Nothing can extend the deadline. No request, header, body or destination changed, and nothing new is logged. The listener runs inside locks (upload's wait, then the count, then the progress counter). The app's listener only makes a task, so there is no cycle back into those locks. |
| `PublishRetry` / `PublishRetryOutcome` | A Stop during the check is not an ending, and a failed check ends the run with `.checkFailed(result)` before anything is sent. The job applies the same later-runs rule as the button (`retryVersionIDs`), so a retry never uploads a photo a later run already published (`PublishBoundaryTests.retryNothingLeftAfterLaterRun`). |
| SQL | New queries are parameterized: `laterPublications` → `versionsPublished` (bound `IN` list in chunks of 10,000), and `rememberMadeAlbum` (one transaction, bound values). The album id it stores is gated by `isServerID` before any later `PUT /albums/{id}/assets`. |
| Server text in the UI | New `PublishCause.itemRefused` carries a bulk answer's per-photo `error` string. It is shown as plain text in quotes (`PublishText.cause`) and is not run through Markdown. See the N2 addendum. |
| Debug script and fake server | New words (`publish servers`, `fault slowcheck`, `fakehost`, held answers by file name) print names, addresses and file names, never a key. `fakehost` only rewrites the fake server's own loopback address. The fake server is still started only by a scripted launch (C10, ruled). |
| Logging | Nothing new is logged in the changed code. |

### L2 (Low, consistency of destination; confidence 8/10 in the facts, 2/10 that it matters for security): a Publish being confirmed, or the Skip or New Copy question, keeps the old address after an address change

F28 made the Publish sheet follow an address or certificate changed in the import window: `serversChanged()` (`PublishModel.swift:252-266`) calls `choose(now, keepingChoices: true)`, which re-checks the new address. But `choose` (`:302`) cancels only the check and album tasks. Unlike `chosenServerWasRemoved()` (`:275`, which calls `cancelSheetWork()` and clears `question`), it leaves two things alone:

- **A Publish being confirmed.** `requestPublish()` (`:677`) captured the old record and is checking it. When that check returns, the guard `serviceID == service.id` still passes, because the id didn't change. It then sets `self.client` to the old-address client (`:697`), possibly over the new check's client. Then it either starts the run on the old record and client, or raises the question with them.
- **The question.** `Question` holds the old `service` and `client`. `answer(skip:)` (`:723`) starts the run with them and checks neither the address nor `canPublish`.

Edit and Remove Server in the import window are dimmed only once a run holds the slot (`runningServerUUID` is set in `claim`), not while the sheet confirms or the question is up. The import window is a separate window, so it stays usable while the alert is up on the library window's sheet. (The F28 script check edited the address with the sheet up.)

Effect: the person sees the new address in the sheet, answers the question, and the photos and key go to the old address. Records are written under the old address, and Retry Failed is then refused as "address changed". The old host passed the check with this key when the question was raised, under its own pin and transport policy. So the key never reaches a host that was not saved for it, which keeps this Low. The case that matters: someone moves from a confirmed `http://` LAN address to `https://` (or to a new LAN address, because the old IP now belongs to another device) while the question waits. That publish then goes, unencrypted, to the old address. This is the same rule `retryRefusal` already enforces for retries.

Fix (either one):
- On `.connectionChanged`, give up a Publish being confirmed and the question, as removal does (`cancelSheetWork()`, `question = nil`). The person presses Publish again against the re-checked server.
- Or make `answer(skip:)` and `requestPublish()`'s continuation refuse when the captured record's address or fingerprint differs from `service`'s.

A test in the style of `PublishRulesTests.chosenServerChange` or a debug-script check can show it: raise the question, edit the address with `fakehost`, answer, and see which address the run's `service.address` names.

### Notes (Info)

#### N5: `removeLeftovers` follows a symbolic link at the base folder and at a `.lock` name

- `contentsOfDirectory(atPath: base.path)` follows `base` if it is a symbolic link. Each entry of the target folder that has no `<name>.lock` beside it is then removed. The old code removed the link itself.
- The lock probe `open(lock.path, O_RDONLY | O_EXLOCK | O_NONBLOCK …)` (`:65`) follows a link named `X.lock` and takes a lock on whatever it points to before removing the link.

Both need a process running as the same user to write into `$TMPDIR`. That process could delete those files directly, so no boundary is crossed, and the confidence that this is a vulnerability is 1/10. It would matter only if the temporary folder were ever a shared one (a `TMPDIR` pointing at `/tmp`, say). In that case the rendered photos and bodies, made with the default umask, would also be readable there, as they already were at b244b48.

Hardening, cheap and local:
- Make `base` with mode 0700.
- Before listing, check with `lstat` (or `URLResourceValues.isSymbolicLink`) that `base` is a real folder owned by the user, and skip cleanup otherwise.
- Add `O_NOFOLLOW` to both `open` calls.

#### N6: two ways a running launch's folder can look like a leftover

These are reliability issues (L1's effect for one launch), not security. Confidence 5/10 for (a), which was not run, and 4/10 for (b).

- (a) **The lock can be taken by another process first.** `O_EXLOCK` means this descriptor is never open without its lock. It does not keep another process from opening the new name before the lock is taken: the file is created and named inside `open` before the lock is applied. If another copy's cleanup opens `<UUID>.lock` in that instant, the creator's `open` fails with `EWOULDBLOCK` (it passes `O_NONBLOCK`) and returns -1. `Launch.make` makes the folder anyway, and the cleanup removes the lock file. The launch then works from a folder with no lock file, which any later launch's cleanup removes. The same happens whenever the lock can't be made (`descriptor == -1` is not handled). The window is tiny: one copy launching while another starts its first publish.
- (b) **A lock file removed by something else.** The rule "a folder with no lock file is a leftover" also catches a running launch whose lock file name was removed by something else, such as a person or a cleaner of temporary files, during a long session.

Hardening:
- In `Launch.make`, when the descriptor is -1, retry with a new UUID, or fail the run with a clear cause, rather than use an unlocked folder.
- Remove a lock-less folder only when it is old (for example, not modified for a day).

#### N2 addendum: per-photo errors are not cut to 200 characters

`addToAlbum`'s per-photo `error` (`ImmichDTO.BulkResult.error`) reaches `PublishCause.itemRefused` without the 200-character cut that `RemoteAnswer.serverMessage` applies to a top-level `message`. It is still plain text, and the answer is capped at 16 MiB. A hostile server could make one very tall row in the results sheet, which is a denial of service by a server the owner added (excluded). This is unchanged in effect: before this diff the same string went through `.server(status: 400, message:)` uncut. Cutting it in `addToAlbum` would match R23's other server text.

### Summary of second-review findings

| ID | Severity | Confidence | Where | Short |
| --- | --- | --- | --- | --- |
| L1 | Fixed | n/a | `PublishTemporaryFolders` | Per-launch folders held by `flock`; only ended or lock-less folders are removed |
| N1 | Fixed | n/a | `RemoteRequestAllowlist.permits`, `RemoteAsset.isServerID` | Whole-path match, ASCII-only ids for asset, album and import paths; tested |
| L2 | Low (destination consistency) | 8/10 facts, 2/10 security | `PublishModel.choose` / `requestPublish` / `answer(skip:)` | An address change during a confirm or the Skip or New Copy question still publishes to the old address; give them up on `.connectionChanged` as removal does |
| N5 | Info (hardening, same user only) | 1/10 | `PublishTemporaryFolders.removeLeftovers` | A symlinked base or `.lock` name is followed; add `lstat`, 0700 and `O_NOFOLLOW` |
| N6 | Info (reliability) | 5/10 (a), 4/10 (b) | `PublishTemporaryFolders.Launch.make`, `removeLeftovers` | Lock lost in a narrow race or with `-1` unhandled, and lock-less means removable; retry the name, age-gate lock-less folders |
| N2+ | Info (DoS, excluded) | n/a | `ImmichClient.addToAlbum`, `PublishCause.itemRefused` | Per-photo error text is not cut to 200 characters |

## Third review, 2026-11-26

Scope: `git diff 41f6d0f..f5d5f09` (commits e603c77 and cd55215), at HEAD f5d5f09. This pass covers four things:
- Keychain deletion and write ordering: the removed-server path in `saveRemoteService`, the second key delete in `removeRemoteService`, `renameRemoteService` and `ServerSheetModel.submit`.
- File deletion outside the library (`PublishTemporaryFolders`).
- The publish destination check (D-15).
- The items left open by the second review.

The method is that of `/security-review`, read only. Nothing was built, run or sent to a server. The Keychain, Docker and the owner's library were not touched. An engineer was editing a comment and the user guide in the same checkout, so the tests named here were read, not run.

**Verdict: nothing meets the bar for High or Medium.** L2, N5, N6 and the N2 addendum are fixed. D-16's ordering leaves no key behind in any interleaving of a Save and a Remove that reaches the row write. Two new notes follow (N7, N8), both Info. Neither is reachable without two near-simultaneous actions by the person, in two windows.

### Earlier items: status

| Item | Result |
| --- | --- |
| L2 (a Publish being confirmed, or the Skip or New Copy question, kept the old address) | **Fixed, three ways.** (1) On `.connectionChanged`, `serversChanged` (`PublishModel.swift:271-275`) now does what removal does when `confirmingSession` or `question` is set: `cancelSheetWork()` cancels `confirmTask`, the question goes, and D-15's line is shown. (2) `requestPublish` calls `stillSaved(service)` after the records lookup and before it raises the question or calls `start` (`:730`). `stillSaved` (`:773`, over `PublishServerChange.since`, `PublishSettings.swift:261`) reads the row from the catalog and refuses on any change of address or fingerprint, or on removal. The address string carries the scheme, and `allowsUnencrypted` is always derived from it on Save, so a move from `http://` to `https://` is a change. (3) `answer(skip:)` (`:748`) now runs `stillSaved(question.service)` before `start`. While that read is on its way, it sets `confirmingSession`, so a change notification arriving then cancels it. The form is disabled while confirming (`PublishSheet.swift:71`), so the server can't be switched in the sheet meanwhile. An old-address client that `requestPublish` stored in `self.client` before `stillSaved` refused is cleared by the `choose(now, …)` that follows the change. `PublishRulesTests.destinationSinceConfirmed` covers `since`, and the model wiring is shown by the debug script (`publish answer` prints whether a run started). Residual: the hop from `stillSaved`'s read back to the main actor, before `start`, is not covered. A Save landing in that instant starts the run on the address that was saved a moment before. That is L2's own bound: that host passed the check with this key under its own pin. No action. |
| N5 (symbolic links followed at the base and at a `.lock` name) | **Fixed.** `prepare` (`PublishTemporaryFolders.swift:88-98`) makes the base with mode 0700. With `lstat`, it requires a real folder (not a link) owned by `getuid()`, and sets 0700 on a base left wider by an earlier build. `removeLeftovers` (`:103`) repeats the `lstat` and ownership check before listing, and does nothing otherwise. Both `open` calls now pass `O_NOFOLLOW` (`:66`, `:122`), so a lock name that is a link fails with `ELOOP` and is skipped. Its folder is then left alone, which is the safe side. `make` (`:58`) never uses a base that fails `prepare`. It works in a 0700 folder of its own beside the base (`:75`), which no cleanup lists. `PublishRulesTests.temporaryFoldersNoLinks` covers a linked base, a wide base and a linked lock. The window between `lstat` and the listing or `chmod` is open to the same user only, as before. |
| N6 (a): a lock taken first by another copy's cleanup, and -1 unhandled | **Fixed.** `make` tries up to `lockAttempts` (8) fresh names and uses only a name whose `open` returned a descriptor. With none, it falls back to the folder outside the base. A launch never works from an unlocked folder in the base. A failed name's lock file is removed by the cleanup that holds it, or by the next one. Covered by `temporaryFoldersLockRetry`. |
| N6 (b): a lock-less folder treated as a leftover at once | **Fixed.** A lock-less entry goes only when its own `lstat` modification time is at least `unlockedAge` (24 h) old (`:110-116`). This also closes a gap the second review didn't name: `readdir` during concurrent changes can return a new launch folder without its lock file. That folder is now seconds old, so it stays. Covered by `temporaryFoldersLockLessOnlyWhenOld`. Residual, reliability only: a launch idle for a day whose lock file something else removed can still lose its folder. The next run's `createDirectory(withIntermediateDirectories: true)` (`PublishJob.swift:104`) makes it again, unlocked and with the default mode. |
| N2 addendum (per-photo errors not cut) | **Fixed.** `ImmichClient.refusals` (`ImmichPublishing.swift:362`) sends each `error` through `RemoteAnswer.shownText` (`RemoteHTTPSession.swift:557`), the same trim and 200-character cut as the top-level `message`. The `"duplicate"` test still reads the raw value. Covered by `PublishRulesTests.albumAddErrorCut`. Nit, excluded as a denial of service by a server the owner added: the cut counts `Character`s, so each of the 200 can still carry many combining scalars and draw a tall row. The same holds for `serverMessage` since the first review. |

### Scope checks (what changed)

| Item | Result |
| --- | --- |
| `saveRemoteService(_:)` no longer recreates a row | `RemoteServices.swift:119-129`: `insert` when `id` is nil, `update` otherwise. GRDB's `update` throws `RecordError.recordNotFound` when no row matches, and nothing is written. `remoteService.id` is `autoIncrementedPrimaryKey` (`CatalogSchema.swift:532`, SQLite `AUTOINCREMENT`), so a removed server's id is never given to a later Add. A stale sheet's `update` can't land on another server's row. Before this diff, GRDB's `save` re-inserted a removed server with its old uuid, and with the key the sheet had just written. |
| `saveRemoteService(_:key:keys:)`: the removed path and the write order | Order: (1) is the row there (`:175-185`; gone → delete the account's key, `.removed`; read fails → `.catalogFailed`, Keychain untouched); (2) read the previous key and write the new one; (3) `update` the row (`recordNotFound` → delete the key, `.removed`, `:197-200`; any other error → put the previous key back, or delete the new one). `removeRemoteService` (`:222-234`) deletes the key, then the row, then the key again (`:231`). Every interleaving of the two that reaches the row write ends with neither row nor key. If Remove deletes the row before Save's existence check, Save deletes the key and writes nothing. If Remove runs between the check and Save's key write, the `update` finds nothing and Save deletes its key. If Save writes key and row between Remove's first delete and the row delete, Remove's second delete takes the key. If Save finishes before Remove starts, Remove deletes both. Each extra delete targets only the account `service.uuid`, which is unique and never reused (an Add makes a new uuid), so it can't remove another server's key. `RemoteConnectionTests.saveNeverRecreatesRemoved` and `saveAndRemoveInterleaved` drive the two middle orders with a hooked key store. Residual, Info: if the `update` fails with an SQLite error other than `recordNotFound` (busy, I/O) after a Remove deleted the row, the restore path puts the previous key back, and that key stays with no server. A failed `try?` delete leaves one too. Either key stays in the person's own Keychain and is sent nowhere. |
| `renameRemoteService` | One parameterized `UPDATE remoteService SET name = ? WHERE id = ?` in a write transaction. `changesCount` counts matched rows (an unchanged name still counts), so 0 means removed. Only the name is written. This closes a downgrade the old name-only Save allowed: a sheet opened before the other window moved the server to `https://`, or trusted a new certificate, used to write back the old address, `allowsUnencrypted` and pin without any check. `renameKeepsWhatAnotherWindowSaved` covers it. |
| `ServerSheetModel.submit` | Name-only Save: `renameRemoteService`. A nil result means the row is gone, and `serverSheetFoundRemoved` closes the sheet (both hosts: `ServerSource.swift:568`, `PublishModel.swift:1111`). Checked Save (address, key or trust pending, Trust Certificate included): `remoteService(id:)` runs first (`ServerSheet.swift:226-238`). A removed server's key is then not read from the Keychain, nothing is contacted and nothing is written. The full Save then goes through the ordering above, and `.removed` closes the sheet. The record written is the sheet's own checked values, so the last writer wins. The other window's change is overwritten only by values that just passed a check. Residual, as N4: if the Remove lands after the key read and before the server check, the key of a server just removed goes to the address the person typed and saved. The save then reports `.removed` and deletes the key. |
| File deletion outside the library | Limited to direct entries of a base that is the user's own real folder. Removed: day-old lock-less entries, and the folders and lock files of launches whose lock can be taken. `removeItem` removes a link, not its target, and doesn't follow links inside a folder it removes. The fallback folder outside the base is never removed by the app: a crashed run's rendered files and bodies stay there until macOS clears the temporary folder. That folder is per user and 0700. Info, no action. |
| Server text, SQL, logging, debug script | `shownText` is shared. The only new SQL is `renameRemoteService` and `remoteService(id:)`, both bound. Nothing new is logged. The debug script's new `question up <address>` and `changedLine` print an address and a sentence, never a key. `PublishJob.beforeFirstPhoto` is an internal test hook, so it can't be set from PhotoApp. |

### Notes (Info)

#### N7: the publish check can pair the Keychain's new key with the sheet's previous address (confidence 6/10 in the facts, 2/10 that it is reachable by a person)

`requestPublish` connects with `service` (`PublishModel.swift:705`). That is `servers.first { $0.id == serviceID }`, the in-memory list. `PublishConnection.connect` (`PublishRetry.swift:12`) then reads the key by uuid from the Keychain as it is now. Suppose the import window's Edit Server saves a new address with a new key. Until this model reloads `servers`, a few awaits after the row is written, `service` still holds the previous address while the Keychain already holds the new key. A Publish pressed in that instant sends the new key to the previous address. The requests are the check's `GET`s, under that address's pin and transport policy. If it was a confirmed `http://` LAN address, the key crosses the LAN in the clear. D-15 then stops the run, so no photo goes, but the key has been sent.

The same pairing exists for the few milliseconds between Save's key write and its row write, by F2's order. That window is open to Retry Failed too, which reads the row afresh.

Reaching it takes a click in the library window within that window, right after a Save in the import window completes. That completion follows the Save's own network check, so the person can't time it. Before this diff, the same connect also happened. The second review's claim that "the key never reaches a host that was not saved for it" holds for the address but not for the key/address pair.

Hardening (cheap): in `PublishConnection.connect`, read the key, then read the row again and refuse unless its address and fingerprint equal the record passed in. This closes both windows for the sheet, the question and Retry Failed. At least, run `stillSaved(service)` before the connect in `requestPublish` as well as after it.

#### N8: a Server sheet or Remove confirmation already up when a run starts is not checked again (pre-existing, not from this diff; confidence 7/10 in the facts, 1/10 security)

Edit and Remove are dimmed only for new openings (`serverIsBusyPublishing`; `askToRemoveServer` checks `publishingServerUUID` when asked, `ServerSource.swift:478`). Neither `ServerSheetModel.submit` nor `removeServer` (`:487`) checks again. So the following can happen:
- An import-window Server sheet opened before a run starts can save a new address during the run. The run keeps its checked client and address by design, and Retry Failed is then refused.
- A Remove confirmed during the run deletes the key and the row while the run goes on using the key it holds in memory, until it ends. Its records are then written with no server: `RemotePublications.swift:74` sets `serviceId` to null when the row is gone.

No key goes anywhere new, but a removal the person confirmed doesn't stop the key's use at once. Hardening: refuse Save and Remove while `publishingServerUUID` names the server, or have Remove stop that run first.

### Summary of third-review findings

| ID | Severity | Confidence | Where | Short |
| --- | --- | --- | --- | --- |
| L2 | Fixed | n/a | `PublishModel.serversChanged`, `requestPublish`, `answer(skip:)`, `stillSaved` | Given up on `.connectionChanged`; no start or question unless the row still has the checked address and fingerprint |
| N5 | Fixed | n/a | `PublishTemporaryFolders.prepare`, `make`, `removeLeftovers` | 0700 base, `lstat` and owner checks, `O_NOFOLLOW` on both opens, fallback outside a bad base |
| N6 | Fixed | n/a | `PublishTemporaryFolders.make`, `removeLeftovers` | Eight fresh names, never an unlocked folder in the base; lock-less entries only after 24 h |
| N2+ | Fixed | n/a | `ImmichClient.refusals`, `RemoteAnswer.shownText` | Per-photo errors cut like any server text (grapheme count; DoS excluded) |
| D-16 | No finding | 8/10 | `Catalog.saveRemoteService`, `removeRemoteService`, `renameRemoteService`, `ServerSheetModel.submit` | No row recreated, no key left in any interleaving that reaches the row write; name-only Save can't write back a stale address or pin |
| N7 | Info (key to previous address, narrow race) | 6/10 facts, 2/10 reachable | `PublishModel.requestPublish`, `PublishConnection.connect` | Stale in-memory record plus the Keychain's new key at the check; re-read the row after the key |
| N8 | Info (pre-existing) | 7/10 facts, 1/10 security | `ServerSheetModel.submit`, `CardImportModel.removeServer` | A sheet or Remove alert already up when a run starts isn't checked again; Remove doesn't stop the run's use of the key |

## Fourth review, 2026-11-26

Scope: `git diff bc54ded..586cfd2 -- Sources Tests` (commits 1c84496 to 586cfd2). The security-relevant changes are 1c84496 (publishing reads a key with its row, `RemoteKeyGate`) and e840ec9 (the import window and the Server sheet do the same, D-18 and D-19). The QA fixes in a04d1ee, 82339ab, 35ec122 and 944982c were read for anything that sends, logs or writes, and touch none of it.

The method is that of `/security-review`, read only. Nothing was built, run or sent to a server. The Keychain, Docker and the owner's library were not touched. A code reviewer was building in the same checkout, so the tests named here (`PublishKeyPairingTests`, `ServerKeyPairingTests`) were read, not run.

**Verdict: nothing meets the bar for High or Medium.** N7 is closed for every path that reads a saved key, within one app process on one catalog. That covers publishing (the sheet's check, Publish, the Skip or New Copy question, Retry Failed), the import window (every check, and the thumbnails, pages, albums and running import that reuse a passed check's client), and the Server sheet with its key field empty, from both hosts. N8 is unchanged and was left on purpose. Two new notes follow:
- **N9 (Low):** the pairing rests on a gate that works only inside one process and on that process's own catalog. A copy of the library, a second copy of the app on the same library, or a failed rollback can still pair the new key with the previous address.
- **N10 (Info):** a typed key from a stale Server sheet goes to the address that sheet shows. D-19 accepts this.

### Where a key is read, and where it can go

| Read (file:line) | Reached from | Where the key can go |
| --- | --- | --- |
| `RemoteSavedKey.read` (`Remote/RemoteKeyPairing.swift:102`), under the account's gate, with the row read in the same hold | `PublishConnection.connect` (`PublishRetry.swift:28`): `PublishModel.runCheck` (the sheet's check), `requestPublish` (Publish; its client then serves the run or the question's `answer(skip:)`), `retryRun` (Retry Failed, after `retryRefusal` and with the record from that reload) | Only the address of the row as saved now, and only if that row's address and fingerprint equal the caller's record (`PublishServerChange.after`). The pin and the http confirmation come from the same row. Afterwards the `ImmichClient` built from that pair carries the key on every request of the check, the run and its retries: upload, album, stack, asset `GET`s and the path search. All of them go through `makeRequest`'s host check (unchanged). |
| same | `RemoteImportConnection.connect` (`RemoteServerChecks.swift:27`): `CardImportModel.connectServer` (choosing the server, Rescan, Try Again, the reconnect after an import, `follow(.chooseAgain)`) | The same rule. `browse.client` (that pair) then serves albums, pages, thumbnails (`remoteThumbnail`) and `RemoteImporter`'s downloads until the next check or `closeServer`. `takeSaved` changes only the name, so `browse.address`, which the links are written under, always matches the client's host. |
| same | `RemoteServerSheetCheck.key(entered: nil, opened:)` (`RemoteServerChecks.swift:139`): `ServerSheetModel.submit` and `trustCertificate`, both hosts | The key saved with `opened`'s address, only while the row still has that address and fingerprint. It is sent to the address typed in the form: the saved one, or a new one on Save (N4, unchanged and accepted), with the form's pin (`ServerFormRules.pin`) and its http confirmation. The check's client is then discarded. |
| `Catalog.saveRemoteService(_:key:keys:)` (`RemoteServices.swift:201`) | A Save with a typed key, and Add | Nowhere: the previous key is read only to put it back if the row write fails (F2), under the gate. |
| `Catalog.saveRemoteService(_:checkedWith:opened:keys:)` (`RemoteServices.swift:243`) | A checked Save or Trust Certificate with the key field empty (D-19) | Nowhere: it is only compared with the key the check used, under the gate. |
| (not read: typed) `ServerSheetModel.key` | Add, or Save with a key typed | The address on screen, in the check, then the Keychain with the row (`RemoteServerSheetCheck.save`). The key appears in no log or debug output: the script prints `key entered/-`, and the fake server's request list prints `key sent/-` and the `Host` header. |

`grep` finds no other `key(account:)`, `RemoteConnection(` or `ImmichClient(connection:)` in `Sources`. `setKey` and `deleteKey` are called only from `RemoteServices.swift`. Nothing in this diff changes `RemoteHTTPSession`, `ImmichAPI`, the allowlist, transport policy or pinning.

### N7: status

| Item | Result |
| --- | --- |
| (1) A record held since before a Save | **Closed.** All three readers compare the row they read under the gate with the record they hold. A changed address or fingerprint, or a removal, gives `.changed`, and nothing is built or sent. `allowsUnencrypted` is derived from the address scheme on every Save (`ServerSheet.swift:233`), so comparing addresses covers it. The id is an autoincrement key that is never reused, and an update keeps the uuid, so reading the key by `service.uuid` and the row by `service.id` name one server. Covered by `PublishKeyPairingTests.staleRecordNeverPaired` and `ServerKeyPairingTests.importCheckWithSavedRow` and `sheetBehindAtPress`. |
| (2) Between a Save's key write and its row write | **Closed in-process.** `saveRemoteService(_:key:keys:)` holds the account's gate from reading the previous key, through the row write and a failed row's restore (`:197`). Readers wait (`waitsForTheRow`, `importCheckWaitsForTheRow`, `checkDuringSave`, `saveHoldsTheGate`). The gate also closes a case the third review didn't name: two Saves with typed keys from two sheets used to be able to interleave as key a, key b, row b, row a, leaving key b with row a. They are now serialized. Across processes, see N9. |
| Certificate pinning paired with address and key | **Paired.** The pin comes from the same row as the address and is read in the same hold as the key. A pin saved alone is a change for every reader: publishing gives up, the import window chooses the server again, and a stale sheet gets `.changed`. Trust Certificate with the key field empty writes the pin through the guarded `checkedWith` Save, which never touches the key. |
| The import window during an import | `.changed` found by a check while an import runs leaves the grid, its state, the selection and `browse.client` alone (`ServerSource.swift:161-172`). The import keeps the address, key and pin it was checked with, which belong together. The reconnect after it (`finishServerImport`, with `importTask` already nil) follows the server as saved. Publish's Edit Server stays enabled during an import by design (§11.1), and nothing reaches a new address. |
| Save and Save (gate) | Serialized per account, so each reader sees one Save whole. A `checkedWith` Save compares the stored key and the row with what it checked, then writes, all in one hold, so no Save in this process lands in between (`sheetBehindAtSave`, `sheetKeyChangedAtSave`). |
| Save and Remove (Remove is not gated) | Remove only deletes (key, row, key). Its interleavings with a typed-key Save are as in the third review, and the gate doesn't change their order. With a `checkedWith` Save: if Remove's first delete lands before the stored-key read, the Save finds the key differs and returns `.changed` (no write; the host's next check then finds no key or no row). If both deletes land before the row read, the Save returns `.removed` and deletes the key. If they land after the comparison, the update finds no row, and the Save deletes the key and returns `.removed`. A reader that read the key before Remove and the row before its row delete sends the key to its own saved address after the person confirmed Remove. That is N8's kind (a removal doesn't stop a use already under way), not a new address. |
| Save and rename (not gated) | A rename writes only the name. A gated Save landing after it writes its own record's name. Benign. |
| The gate itself | FIFO hand-off under a `Mutex`. Bodies never take a gate again (they call only the ungated `remoteService(id:)` and `saveRemoteService(_:)`), so there is no self-deadlock. `Catalog` is a non-actor class and `RemoteSavedKey.read` is a nonisolated static, so `#isolation` is nil and the Keychain calls run off the main actor. Waiting can't be cancelled: a check cancelled while it waits still reads its pair when the gate frees, and anything it sends goes to the address saved with that key. A Keychain prompt holds the account's gate until answered, as documented (reliability only). |
| Retry Failed (D-17) | `retry` reloads, `retryRefusal` refuses a removal or an address change, and the connect uses the reloaded record. A Save landing after that reload gives `.changed`, and the retry is called off with nothing sent (`PublishRetryOutcome.calledOff`). |

### Scope checks (what changed)

| Item | Result |
| --- | --- |
| Logging, Activity, debug output | Nothing new is logged. A catalog error read under the gate is shown as `.keychain(message)` or the start issue. That is GRDB's text, which holds no key (the catalog has none). The new debug words (`fake mark`, `requests since`, `trust nowait`, `fakehost`, `importing n/m`) print request lines, hosts and counts, never a key. |
| SQL | The only new query is `remoteService(id:)`, a keyed fetch. `checkedWith` reuses the bound `update`. |
| Server text | Unchanged. `PublishText.checkDetail` routes the same strings the sheet already showed. |
| `OriginalsTally`, `PublishSheet`, `closeSheetsForQuit` | Bookkeeping and UI. No request, file or key. |

### Notes

#### N9 (Low): the key and its row are paired only within one process and one catalog (confidence 8/10 in the facts; reachable 3/10 for (a), 1/10 for (b) and (c))

The Keychain item is named by `<bundle id>.servers` and the connection's uuid (`RemoteKeyStore.swift`, `query(_:)`), and holds nothing about the address it was saved for. `RemoteKeyGate` lives in one process. `RemoteSavedKey.read` compares with the row of the catalog that process opened. So the new key can still reach the previous address three ways:

- **(a) A copy of the library.** Copying the library folder copies `remoteService.uuid`, and the last-server preference is per bundle identifier, so both copies name the same Keychain item when run from a bundle with the release identifier without `--debug-script` (`RemoteKeyStores.forLaunch`). Suppose Edit Server in one copy saves address B with a new key. The other copy's row still says A. Its next check reads the new key beside row A, which equals the record it holds, and sends the key to A, under A's pin and http confirmation. Opening Publish is enough: it checks the remembered server at once (`PublishModel.swift:226-228`). No race is needed, and the state lasts. Likewise, Remove Server in one copy deletes the other copy's key, and Edit replaces it (an integrity issue for the other library's setup). WORKFLOW's sign-off lets the owner use their real library, and trying a branch with migrations on a copy of it is the natural way to do that.
- **(b) Two app processes on one library.** `LibraryModel.open` opens anyway when another process holds the library lock (`LibraryModel.swift:866-875`: "a second copy of the app, open anyway"). The gate's doc comment, `status.md`'s N7 row and the proposed Network rule all say the lock keeps a second copy off the catalog. It does not. Between processes, the milliseconds between a Save's key write and its row write are open again (the third review's second window). D-19's compare-and-write is also not atomic against the other process's Save: it can write its row (address A, or a new C) right after the other process stored its key for B, leaving that key beside A or C.
- **(c) A failed rollback.** Suppose the row write fails after the new key is stored: a catalog error, or the sheet's task cancelled by Esc just after the check passed. GRDB's async write throws `CancellationError` before writing (#271's C1). The previous key is then put back with `try?` (`RemoteServices.swift:214-219`). If that Keychain write is refused too, for example on a second access prompt for an item an older build stored, the new key stays beside the previous row, and every later read pairs them. The gate only hides the half Save while it is under way.

Each case needs the owner to copy a library, run two copies of the app, or have a Keychain write refused right after one succeeded. The key goes only to an address the owner saved for that server before, under that address's pin and transport policy. It matters when that address now belongs to someone else: a reassigned LAN address reached in the clear, or a lapsed domain. That is N7's own concern.

Fix (one change closes all three): make the pair check itself.
- Store the normalized address the key was saved for in the Keychain item, in the same `SecItemAdd` or `SecItemUpdate` as the key (`kSecAttrGeneric` or `kSecAttrComment`).
- Have `key(account:)` return it, and have `RemoteSavedKey.read` give the key only when it equals the row's address and the caller's.
- A key-field-empty Save that changes the address (N4) then rewrites the item's address under the gate, with F2's rollback.
- An item stored before the change has no address. Either take the row's once and write it, or ask for the key again (the owner's call).
- Keep the gate for ordering.

Copies would still share one item per address (Remove in one copy still removes the other's key). Separating copies would need a per-library part in the account, and the key entered again in a copy. Whether or not the fix is taken, correct the sentence about the library lock in `RemoteKeyGate`'s comment, `status.md` and the proposed Network rule. Without the fix, the rule's "a key saved for a new address never reaches the previous one" also needs "within one process and one library".

#### N10 (Info): a typed key from a stale Server sheet goes to the address that sheet shows (confidence 7/10 in the facts, 1/10 that it matters)

The sheet starts from the record it opened on, its http confirmation included (`ServerSheet.swift:111`). With a key typed, the press checks only that the server still exists (`RemoteServerSheetCheck.key`, `:125-134`). Suppose the other window moved the server from `http://A` to `https://A`, or to another address, while this sheet was open, and the person types only a new key here. The new key then crosses the network in the clear to `http://A` in the check, and the Save writes `http://A` and its confirmation back over the other window's choice.

The person sees that address and the Not encrypted notice in the form, and D-19's "A typed key" bullet accepts last-save-wins, so this stays Info. Hardening, if the owner wants it (either one):
- On a typed-key press, compare `opened` with the row as the empty-field path does, and end with `.changed`. The person then types the key again in the refreshed sheet.
- At least drop a pre-filled http confirmation when the row's address no longer equals `opened`'s.

#### N8 and N4: unchanged

N8 is still as the third review describes it: `ServerSheetModel.submit` and `removeServer` don't check `publishingServerUUID` again. It was left on purpose, and this diff adds no path to it. N4 (Edit Server sends the saved key to a newly typed address on Save) still holds: D-19 now reads that key with `opened`'s row, so it is the key saved for the address the sheet opened on.

### Summary of fourth-review findings

| ID | Severity | Confidence | Where | Short |
| --- | --- | --- | --- | --- |
| N7 | Fixed (in-process) | 8/10 | `RemoteSavedKey.read`, `RemoteKeyGate`, `PublishConnection.connect`, `RemoteImportConnection.connect`, `RemoteServerSheetCheck`, `Catalog.saveRemoteService(_:checkedWith:…)` | Every key read is paired with its row under the account's gate and given only to the caller's address and pin; Saves are serialized; a stale sheet writes nothing |
| N9 | Low (key to a previous address) | 8/10 facts; 3/10 (a), 1/10 (b), (c) | `KeychainKeyStore` item naming, `RemoteKeyGate` (per process), `LibraryModel.open` (lock not enforced), F2's `try?` restore | Library copies share the item; a second app process bypasses the gate; a failed restore makes the half Save stick. Store the saved-for address in the Keychain item and require it to match; correct the "library lock" sentence |
| N10 | Info | 7/10 facts, 1/10 matters | `ServerSheetModel.init`, `RemoteServerSheetCheck.key` (typed key) | A stale sheet's typed key goes to its own, possibly `http://`, address and writes it back (accepted by D-19) |
| N8 | Info (pre-existing, left on purpose) | unchanged | `ServerSheetModel.submit`, `CardImportModel.removeServer` | Unchanged |
| N4 | Info (from #271, accepted) | unchanged | `RemoteServerSheetCheck.key` | Unchanged; the key sent is now the one saved with `opened`'s address |
