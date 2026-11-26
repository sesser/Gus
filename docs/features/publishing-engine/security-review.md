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
