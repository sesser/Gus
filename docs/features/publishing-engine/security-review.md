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
