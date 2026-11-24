# Import from Immich: code review

Owner: code-reviewer. Date: 2026-11-23. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/immich-import`, 4f8ea58..2552143 (code; ec4b29b, the
designer's review, came in during this pass and touches `docs/` only).
Build and tests: `swift build --build-tests` clean; `swift test` 1492 tests in
211 suites pass; the Immich suites (`--filter "Immich|Remote"`) 10 of 10 runs
clean here, plus `CatalogTests`, `BrandingTests` and `LocalizationTests`.

## Verdict

Not ready for QA yet. The connection layer holds the PRD's network posture
(https default, local-only plain http after confirmation, pin decided in the
TLS challenge, allowlist enforced before every request, no redirects, no
cookies or cache, the key only in the key store and the header), and no master
can be overwritten. But seven Should-fix findings remain: a verified download
left on disk uncataloged when Stop or a catalog error lands after the move
(C1), server values that split a RAW+JPEG pair (C2), a crash on server-reported
sizes (C3), unbounded response bodies (C4), a numeric host that gets around R5
(C5), a key-store fallback that reaches the real app's Keychain items from a
test launch (C6), and partial files left by Quit (C7).

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoCore/Remote/RemoteImporter.swift:280-314` | After `moveItem(at: partial, to: final)` (line 282), any error from `insertRemoteMaster` goes to the `catch` at 310, which removes `partial` (already gone) and leaves `final`. GRDB's async `write` throws `CancellationError` when the task is already cancelled (`SerializedDatabase.execute`: `try Task.checkCancellation()` before the block), so Stop causes it reliably. | Press Stop while the importer reads the downloaded file's metadata (ExifTool or ImageIO, line 267, between the duplicate check and the insert). `metadata` swallows the error (`try?`), the move runs, `insertRemoteMaster` throws `CancellationError`. The verified file stays in the destination under its template name with no catalog row and no link. The report counts a failure whose reason is "The operation couldn't be completed. (Swift.CancellationError error 1.)". A later import of that asset names its copy `-1`. Any catalog error (busy, disk full on the catalog's volume) does the same. A Stop during `verifyStored` makes `linkRemoteDuplicate` throw the same way: no stray file, but the same bogus failure. If Stop lands inside `makeTarget` after `createProject`, an empty project is left. The `stop` test cancels only during a download, so it never reaches this window. | R18 ("finished photos kept and their links recorded"; Stop leaves no stray file), AC13 |
| C2 | Should fix | `Sources/PhotoCore/Catalog/RemoteServices.swift:190-205` | The server's description and rating are written by `UPDATE` to the new image and version only, after `insertMasters` has already paired them and merged culling values (`ImagePairing.mergeDefaultVersions`). The partner never gets the value. | `IMG_1.RW2` (no rating on the server) and `IMG_1.JPG` (rated 4, description "Beach" on the server) are imported in one run, RAW first. The JPEG is inserted and paired, both versions at 0, then only the JPEG's version becomes 4 and only its image gets the caption. The pair now disagrees. The grid shows the RAW at 0 with no description. The JPEG's queued sidecar resolves to its owner, the RAW (`sidecarOwners`), whose values have neither, so the server's rating and description reach neither the visible photo nor `IMG_1.xmp`. Fix: apply the server values before pairing, or apply them to `ImagePairing.partnerVersionIDs` and `descriptiveImages` as every other write does. | CLAUDE.md, RAW+JPEG pairs: "every catalog write on a pair's default version also reaches the partner (`ImagePairing`)"; R17, AC12 |
| C3 | Should fix | `Sources/PhotoCore/Remote/RemoteImporter.swift:145` | `assets.map { $0.byteCount ?? 0 }.reduce(0, +)` adds server-reported `exifInfo.fileSizeInByte` values (decoded as `Int64`, never range-checked in `ImmichAPI.swift:236`). Int64 addition traps on overflow, `-O` included. | A server (hostile, or buggy) reports `"fileSizeInByte": 9223372036854775807` on two photos. The person selects both and presses Import, and the app crashes in `RemoteImporter.run`. A negative size is accepted too (it reaches the progress totals and `verify`). Clamp at decode: reject or nil any size `< 0` or above a sane maximum. | Security: outside data checked before use |
| C4 | Should fix | `Sources/PhotoCore/Remote/RemoteHTTPSession.swift:138-149`, `:245-259` | `perform` uses `session.data(for:)`, which holds the whole body in memory with no cap. That covers every JSON answer (`/server/version` from an address that may not be Immich at all, `/albums`, each search page) and every thumbnail. `DownloadSink` writes every byte it is sent, even past the size it is checking against. | A host typed in Add Server… (not yet known to be Immich), or a hostile server, streams an endless body at `/api/server/version` or `/api/albums`: memory grows until the app dies. An original whose listing gave 5 MB but that streams without end fills the destination's disk before the size check (after the download) can fail it. Fix: cap JSON and thumbnail bodies (refuse a larger `expectedContentLength` at once, and stop when the bytes pass the cap), and cancel a download when its byte count passes the expected size. The main session asked for a bound on JSON sizes. | Security: "bounds, sizes and counts checked before allocation" |
| C5 | Should fix | `Sources/PhotoCore/Remote/ServerAddress.swift:133-136` | A host made only of digits, or `0x` and hex digits, fails `inet_pton` (dotted quad only), so it falls through to "a name with no dots" and is counted as local. `URLSession` resolves such names as IPv4 numbers (checked here: `http://2130706433:18765/` and `http://0x7f000001:18765/` both reached a server on 127.0.0.1), and `NSAllowsLocalNetworking` lets unqualified names through ATS. | `http://134744072:2283` is 8.8.8.8. `TransportPolicy.of` returns `.unencryptedLocal`, the sheet offers the notice, and after the check box the key and the photos travel in plain text to a public address. R5 and AC3 say `http://8.8.8.8` is refused. Fix: parse single-label hosts with `inet_aton` semantics (or refuse an all-numeric or `0x` label), then classify the resulting address. | R5, AC3 |
| C6 | Should fix | `Sources/PhotoCore/Remote/RemoteKeyStore.swift:61-67`; `Sources/PhotoApp/Model/LibraryModel.swift:155-156` | With no bundle (`swift run PhotoApp`, a test launch by `LibraryLaunchGuard`'s own definition), `KeychainKeyStore` falls back to `AppBranding.bundleIdentifier + ".servers"`, the release app's service. The in-memory store is used only for `--debug-script`, not for `--benchmark-scroll` or a bundle-less launch. | `swift run PhotoApp --library-root <copy of the real library>`, then choose the saved server. The copied `remoteService.uuid` is the Keychain account, so the test process reads the real app's key (behind a Keychain prompt, which a person may allow), and Add Server… writes into the real service. Fix: use `InMemoryKeyStore` whenever `LibraryLaunchGuard` would count the launch as a test launch, and never fall back to the release identifier. | PRD, Dependencies and impact: "a test launch must never read the real app's Keychain item"; R1 |
| C7 | Should fix | `Sources/PhotoApp/PhotoApplication.swift:119-127` | Stop and Quit cancels the server import and terminates at once. It waits only for a merge (`merge.waitUntilDone`). Deleting the in-flight `.download-<uuid>.<ext>` file happens in the import task after URLSession reports the cancel, which never runs before exit. | ⌘Q during a 40 MB download, then Stop and Quit: a hidden partial file stays in the person's destination folder. A card import has the same race, but its window is one local file copy; a network download is seconds long. The HDR merge review fixed the same issue (C2 there) with a bounded wait. | R18 (Stop and Quit "as in card import"; partial files removed) |
| C8 | Nit | `Sources/PhotoUI/Import/ServerSource.swift:162-172`, `ServerSheet.swift:133-142`, `:172-176` | `SecItemCopyMatching` and `SecItemAdd`/`SecItemUpdate` run on the main actor (`check` is a static on the `@MainActor` model; the sheet is `@MainActor`). | With the file-based keychain and a new ad hoc signature each build, macOS shows its access prompt (P5), and the call blocks the main thread until it is answered. The import window shows a spinning cursor behind the prompt. Move key-store calls off the main actor. | Concurrency (main thread) |
| C9 | Nit | `Sources/PhotoUI/Import/ServerSource.swift:325-331` | `reason(_:)` falls back to `String(describing: error)` for `.malformed`, `.certificate`, `.notAllowed`, `.transportRefused` and `.cancelled`, and that text goes into Activity. | The album list fails to decode, and Activity reads "Couldn't load the albums of “Home”: malformed. Choose Rescan to try again." This is unlocalized developer text in a UI string. It holds no key. | Strings in the String Catalog |
| C10 | Nit | `Package.swift:88-92`; `Sources/PhotoFixtures/FakeImmichServer.swift:223-235` | PhotoApp now links PhotoFixtures, so the release app carries the fake HTTP server and every synthetic fixture (DNG, HDR bracket, test scenes). Only `import server fake start` under `--debug-script` starts it, and it binds 127.0.0.1 only, so it is not harmful. But it widens what a release binary contains, and CLAUDE.md's Layout describes the target as tests and benchmarks only. The fake's `receive` also appends to its buffer with no limit. | Under a scripted launch, another local process can send the fake an endless header and grow the app's memory. Reachable only by a person running the debug script. An alternative is in Questions. | CLAUDE.md Layout (PhotoFixtures' role) |
| C11 | Nit | `Tests/PhotoCoreTests/RemoteBoundaryTests.swift:13-64` | AC1 asks for a test that greps catalog rows, preferences, log lines, Activity messages and debug output for the key. The test covers catalog rows, the import report and the connection's description. Logs are covered by a source grep (`keyUsesInSources`), and preferences and debug output by the engineer's scripted runs. | None as built: I found no place that prints, logs or stores the key. The criterion's "a test" is only partly met, so QA should record which parts are scripted checks. | AC1 |

## Questions

- **For the owner (C10).** Should the debug script's fake server run in its own
  process (`photobench fake-immich --port N`; photobench already links
  PhotoFixtures) instead of being linked into the app? `import server add … http://127.0.0.1:N`
  would then reach it like any server, and the app would not link
  PhotoFixtures. Keeping it as built is defensible: the fake is reachable only
  under `--debug-script` and listens on loopback. Either way, CLAUDE.md's
  Layout entry for PhotoFixtures needs updating at Ship (status.md already
  says so).
- **For the product manager (R5).** Is `100.64.0.0/10` (carrier-grade NAT, the
  range Tailscale gives devices) the local network? As built, plain
  `http://100.x.y.z` and MagicDNS names (`nas.tailnet.ts.net`) are refused, so
  a homelab reached over Tailscale needs https. That follows R5's list exactly.
  The question is whether the owner's setup needs it.
- **For the product manager.** The PRD asks for `NSLocalNetworkUsageDescription`
  "through the String Catalog". It is plain English in `Support/Info.plist`,
  because the catalog compiler writes only `Localizable.strings` (status.md
  explains this). Accept for an English-only app, or ask for an
  `InfoPlist.strings`?

## Checked and fine

- **Allowlist.** Enforced in `RemoteHTTPSession.makeRequest` before any
  request is built, for `data` and `download` alike. The patterns are
  anchored, the asset id is limited to `[0-9A-Za-z-]{1,64}`, so a hostile id
  can't change the path, and the built URL's host is checked against the
  connection's. GET everywhere except the one POST search. `edited=false` is
  sent on originals and thumbnails.
- **TLS.** The decision is made in the server-trust challenge, for that host
  only. A pin compares the leaf's SHA-256 and wins over the system's trust.
  With no pin, the system SSL policy is evaluated for the host. There is no
  bypass, and other challenge types are rejected, so no credential is ever
  sent.
- **Redirects and session.** Redirects are refused (the 3xx is the answer).
  The session is ephemeral, with no cookie store, URL cache or credential
  storage.
- **The key.** It never appears in a description: `RemoteConnection`'s
  `description`, `debugDescription` and `customMirror` leave it out, and
  `RemoteHTTPSession`, `ImmichClient`, `RemoteError` and
  `ConnectionCheckResult` hold no key text. The debug script prints "entered"
  or "-". No log line interpolates it. The Keychain account is the row's
  UUID, the service comes from the bundle (apart from C6), and the item is
  `WhenUnlocked`. A failed save of a new server deletes its key.
- **Transport policy.** `TransportPolicy` is enforced in
  `RemoteHTTPSession.init`, not only in the sheet. Address normalization
  (scheme, case, default port, trailing slash and `/api`, path prefix kept)
  matches R16. The ATS key goes into the library app's `Info.plist` only
  (`Importer-Info.plist` is untouched), and `NSAllowsArbitraryLoads` is not
  set.
- **Hostile file names.** Template components go through
  `ImportTemplate.sanitize`, which turns `/`, `:` and `\` into `-`, drops
  control characters (NUL included), strips leading dots and caps at 200
  characters. The unsanitized fallback stem can only be dots, spaces or
  control characters, plus a known `FileKind` extension, so it stays one path
  component. `freeName` and `moveItem` never replace a file, so no master is
  overwritten. A case collision is numbered on a case-insensitive volume. A
  name too long for the file system fails that one photo and leaves no file.
- **Downloads.** Streamed to a file with a running SHA-1, never held in
  memory. Size and SHA-1, or size only for a `libraryId` asset (with
  "unverifiable" when no size is known), match R13 as revised. The file is
  then read back with `F_NOCACHE` for SHA-1 and SHA-256, deduplicated on
  SHA-256 and linked (R15b). Every verify failure, disk error or download
  error removes the partial file.
- **Migration v16.** New and numbered, no earlier migration edited, generic
  names. `remoteLink` is unique on (provider, address, remoteId) and on
  (versionId, provider, address). It cascades with its version, so
  `LibraryRemoval` removes the link in the same transaction, and
  `serviceId` is set to null when its connection goes.
- **`insertMasters` split.** Behavior is unchanged for existing callers
  (`pairsCreated` is now `+=` on a fresh result). Master, link and server
  values go in one transaction in `insertRemoteMaster`, which also re-checks
  "already linked" and "content duplicate" inside it.
- **Sidecars.** The engineer's account is correct: the triggers fire on
  `UPDATE` only, the values are written only where the library's are empty
  (caption null or blank, rating 0), and `SidecarSync`'s unchanged rules keep
  a sidecar another app changed from being overwritten. The import adds no
  new write path. The exception is pairs (C2).
- **Concurrency.** No `@unchecked Sendable` or `nonisolated(unsafe)`.
  `Mutex` and `OSAllocatedUnfairLock` guard shared state. Thumbnails are
  decoded and converted to the window's color space off the main thread
  before they reach a layer. Cancellation reaches URLSession through
  `withTaskCancellationHandler` (downloads) and `data(for:)` (requests).
  Stop is `importTask.cancel()`. Page and connect tasks are dropped when
  `browse` changes.
- **Standalone importer.** It reads no servers (`library` is nil), and every
  server item is behind `copiesOnly` or `includesLibraryItems`, as AC16 as
  revised asks.
- **Rules.** `BrandingTests` and `LocalizationTests` pass. Menus read
  `ImportMenuContext` (focused values). No SwiftUI `ScrollView` was added.
  No rendering changed, no pipeline bump, no golden touched. No new package
  dependency (Foundation, Security, CryptoKit; Network in the fake only).
- **Determinism.** The `stop` test cancels on the third original request
  while the fake holds that body for 2 s. The importer is sequential, so
  exactly two photos import. The revoked-key test's fake reads the key before
  its hook revokes it. `unreachable` uses refused connections, with no timing
  involved. I accept these structural arguments. Runs: the engineer's 30 plus
  10 of 10 here, so 40 clean runs, which rule out a flake rate above about 1
  in 13 at 95%. The structural argument is the stronger evidence.
- **Scope.** Nothing outside #271: the `ActivityToolbarItem`,
  `CopyImportProgress.waitingForServer` and `CopyImportResult.init` changes
  serve the server import.

## Follow-up

Second pass, 2026-11-23, at efb8425 (fixes in 977427c, 1deda12, efb8425).

| # | Status | Commit | Evidence |
|---|---|---|---|
| C1 | Fixed | 977427c | After verification, a Stop check removes the partial file. From there `finish` runs in an unstructured `Task` that the Stop does not cancel, so GRDB's cancellation checks never fire inside it. `failed()` removes the partial file and the moved file only when this call moved it (`moved` is set after `moveItem` succeeds, and `moveItem` never replaces a file), so no master is touched. `makeTarget` now runs inside the step, so a Stop can't leave an empty project. I ran `stopWhileFinishing` against 2552143: it fails there (a `CancellationError` failure, 0 imported, and the stray file the finding described). `catalogErrorAfterMove` does not test what its name says (C13). |
| C2 | Partly fixed | 977427c | When the RAW is listed first, both files now get the rating and the description, and `pairGetsServerValues` tests this. When the JPEG is listed first, the description still splits the pair (C12). |
| C3 | Fixed | 977427c | `saneSize` (0 to 64 GiB) is applied at decode, in the total, in the download limit and in `verify`. The total is added with overflow checking. `insaneSizes` would trap on the old `reduce(0, +)`. |
| C4 | Fixed | 977427c | JSON and thumbnail answers are capped by `Content-Length` and while reading. A download stops past its limit (`tooLarge`, reported as incomplete) and its partial file is removed. The caps are ample for a real library: a 250-asset search page is about 1 to 3 MB against 32 MiB; an album without its assets is about 1 to 2 KB, so 16 MiB holds about 8,000 albums; a `size=thumbnail` webp is tens of KB against 16 MiB. The tests cover only the `Content-Length` path (C16). |
| C5 | Fixed | 977427c, efb8425 | `inet_aton` forms are now read as addresses. A numeric-looking name is never local, and only ASCII names are local. `isHexDigit` also accepts fullwidth digits, but the ASCII guard and `inet_aton` both reject them, so those hosts are refused. A trailing-dot host is refused too. Every failure refuses, never allows. |
| C6 | Fixed | 977427c | `RemoteKeyStores.forLaunch` uses memory when there is no bundle, for `--debug-script` and for `--benchmark-scroll`. `KeychainKeyStore` takes the identifier and has no release fallback. |
| C7 | Fixed | 977427c | Stop and Quit waits up to 10 s for `importTask` to become nil, after the merge's own 10 s wait. Residual: a finish that takes longer than that (a stuck ExifTool read; its `PendingResponse` was never cancellable after queueing, so this is not a regression) can exit between the move and the insert. That case is bounded and rare. |
| C8 | Fixed | 977427c, efb8425 | `check` is `nonisolated`. The sheet reads the stored key in `Task.detached`. `Catalog.saveRemoteService(_:key:keys:)` is a nonisolated async method on a `Sendable` final class, so its key-store calls run off the main actor. `RemoteKeyStore: Sendable`. No key text is logged or put into a result. |
| C9 | Fixed | 977427c | Every `RemoteError` now maps to the system's words or a catalogued sentence. `LocalizationTests` passes. |
| C10 | Held for the owner | | No change, as agreed. |
| C11 | Accepted | 977427c | `status.md` says which AC1 parts are tests (`keyOnlyInTheStore`) and which are a source check or scripted checks. QA should record the same split. |
| B1, S1 to S4 (design review) | Not harmful | 977427c, 1deda12 | B1: `trustedPending` applies only in Edit. Add still needs a key and a check, and `trusted` is set only on the certificate page. S1: the key lives in an observed property of the sheet model, in memory only; it is never shown, printed or reflected (the same as the ignored property before), and it is released with the sheet. S2: a fixed frame that follows `idealHeight` (the designer's N-1 covers the certificate page). S3: the confirmation is asked from `onDismiss`. S4: a one-shot flag taken when the new grid enters the window. |
| F1 (security) | Verified | efb8425 | See the Second pass section. |
| F2 (security) | Verified | efb8425 | When the row fails, the previous key is put back. A new connection has its key deleted. A refused read of the previous key changes nothing. `keyRollback` covers all three. If putting the key back also fails, that failure is swallowed, but the store has just accepted a write, so this is unlikely. |

## Second pass

Reviewed: `feature/immich-import`, 2552143..efb8425 (code commits 977427c,
1deda12, efb8425). Build and tests: `swift build --build-tests` clean.
`swift test --filter Remote` passes: 54 tests in 7 suites, 15 of 15 runs
(`--skip-build`). `LocalizationTests` and `BrandingTests` pass. I did not run
the full suite; the engineer reports 1507 tests passing after the security
fixes. Two probes were run in throwaway copies under the scratchpad, never in
the repository: the new tests against 2552143, and the C12 and C14 scenarios
against efb8425.

### Verdict

Not ready for QA yet. Two findings need code fixes and one needs a test. The
fixes for C1, C3 to C9 and both security findings hold. But C2 is fixed in
only one listing order (C12). The test said to cover C1's cleanup after the
move never reaches the move (C13). F1's decode check hides legitimate photos
whose names hold invisible format characters (C14). All three are small.

### Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C12 | Should fix | `Sources/PhotoCore/Catalog/RemoteServices.swift:243-248` | The description is filled per image: any image of the pair whose caption is empty gets the server's value. That works when the file with the description is inserted after its partner. It fails the other way round, because pairing (`ImagePairing.mergeDefaultVersions`) merges ratings, flags, labels, keywords and albums, but not captions. | `IMG_0200.JPG` (rated 4, "Beach" on the server) is listed before `IMG_0200.DNG` (newer `fileCreatedAt`, or an equal one in the server's order). A probe at efb8425 gave rows `DNG caption=nil rating=4` and `JPG caption=Beach rating=4`, one pair, and `descriptiveSummary` for the photo returned `mixed = [caption]`. The Info tab shows Description as mixed for one photo. The sidecar is written from its owner, the RAW, so it has no description. A second case: the RAW has a description and the JPEG gets a different one from the server. Both are kept, so the pair is again mixed. The code comment says "only where the pair's own value is empty", but the description code does not do that. Fix: treat the pair as one. When the new image is paired and a partner has a caption, copy it to the new image if its caption is empty. Write the server's description only when every image of the pair is empty. Add a test with the companion listed first. | CLAUDE.md, RAW+JPEG pairs; R17, AC12 |
| C13 | Should fix | `Tests/PhotoCoreTests/RemoteReviewFixTests.swift:47-63` | `catalogErrorAfterMove` sets `.existing(9_999)`, so `createImportRun` fails on the `importRun.projectId` foreign key inside `makeTarget`, before the move. The test never reaches the code it is named for, the removal of the moved file (`moved`) after a failed insert. That path has no test. | Run against 2552143 (the unfixed code), the test **passes**. It printed "SQLite error 19: FOREIGN KEY constraint failed - while executing `INSERT INTO "importRun"`…", so it would not catch a regression of C1's cleanup after the move. Fix: make the failure come after `moveItem`. For example, catalog a first photo, then make the insert fail for the second (drop or rename the project or volume row between photos through a test hook), or have `relativePath` return nil. Assert that no file is left and that the reason is the system's. | WORKFLOW, tests that fail without the fix; C1 |
| C14 | Should fix | `Sources/PhotoCore/Remote/RemoteAsset.swift:46-49`, used at `ImmichAPI.swift:237` | `isPlainFileName` refuses every scalar in `CharacterSet.controlCharacters`. That set is Unicode categories Cc **and Cf**: zero-width joiner U+200D, zero-width non-joiner U+200C, LRM and RLM, the soft hyphen and the BOM. F1 needs only `/`, `\`, NUL and Cc refused; `sanitize` already drops Cf characters when it builds a name. | A probe at efb8425: `isPlainFileName("Family 👨‍👩‍👧.jpg")` is false (emoji ZWJ sequence), and a Persian name with the ZWNJ its spelling requires is false. Such a photo is dropped by `compactMap` in `ImmichClient.page` and never listed. Nothing tells the person, and an album shows the server's count with fewer tiles. `a..b.jpg` is accepted, as it should be. Fix: refuse `/`, `\` and Cc (NUL included), not Cf. Layers 1 and 3 do not depend on this check. | R9 and R10 (the account's photos are listed); F1 |
| C15 | Nit | `Sources/PhotoCore/Remote/RemoteImporter.swift:277` | `result.project` is read with `try?` in the import's own task. When a Stop lands while the first photo finishes, GRDB's read throws `CancellationError` and the project is nil. | That photo is cataloged in its new project, but `didFinishCopyImport` gets `project == nil`. It does not select the project, warm its previews or suggest keywords for the photo. Fix: return the project summary from `finish`, which runs in the task that isn't cancelled. | R18 |
| C16 | Nit | `Sources/PhotoCore/Remote/RemoteHTTPSession.swift:167-172` (the read loop), `:291-295` (`DownloadSink.received(_ data:)`) | The fake always sends `Content-Length`, so `caps` exercises only the up-front refusal. The checks that stop a body while it streams (a chunked answer, as a proxy can send) are untested. | They read correctly, but a regression there would not be caught. Fix: add a fault to the fake that sends a chunked or length-less body, for one JSON endpoint and for an original. | C4 |
| C17 | Nit | `Tests/PhotoCoreTests/RemoteReviewFixTests.swift:33-34` | `reader.task` is set after the import's `Task` has started. If the import reaches its first metadata read before that assignment, `cancel()` acts on nil and the test fails. The run has to make a localhost download, two hashes and three catalog writes first, so the window is small. | This can only cause a false failure, never a false pass. 15 of 15 runs were clean here. Fix: have `CancellingReader` wait until the task is set. | Determinism |
| C18 | Nit | `Sources/PhotoCore/CardImport/ImportTemplate.swift:173` | The doc comment "Makes a value safe as one path component." now sits above `fallbackStem`, not above `sanitize`. | It documents the wrong declaration. | Documentation |

### Questions

- **For the main session (a possible follow-up, not this branch).** When Stop
  lands, `writeSidecars(forImages:)` at the end of `run` fails in the
  cancelled task (`try?`). Photos imported before the Stop with a metadata
  preset then get no sidecar until something changes them: the preset's
  values are their baseline, so nothing queues them. The card import has
  the same gap (its `run` throws on cancellation before the same call), so
  this branch keeps R18's "as in card import". It may deserve an issue for
  both imports.

### Checked and fine

- **F1, layer 3 (`isInside`).** The final URL is built by appending
  sanitized parts to `options.destination`, so the destination's text is
  always its prefix. Trailing slashes, `.`, `..` within the destination's own
  path, case, Unicode normalization and a destination that is itself a
  symlink all compare equal by text. Symlinks inside the destination are the
  person's own folders, and folder names can't contain `/` or start with
  `.`, so a server can't add one. `/a/bc` is not inside `/a/b`, and the
  `/private/tmp` case is tested. The check refuses before the move and
  removes the partial file.
- **F1, layer 1 (`render`).** For a name without `/` or `\` whose extension
  is plain, the extension is the same as before. The only change for card
  imports is that an empty template's fallback is now sanitized, so it equals
  what `{name}` gives. Every extension `FileKind` accepts (`cr3 cr2 nef arw
  dng raf orf rw2 jpg jpeg heic heif tif tiff png`, and the video ones) is
  ASCII alphanumeric and at most 4 characters. No file that passes
  `FileKind`, at a server's decode or a card's scan, can lose its extension,
  so no master ends up without one. `3FR`, `IIQ` and `X3F` would also pass
  the rule, but they are not supported formats. Names with spaces, several
  dots or `.jpeg` are not pinned by a test of `render`, but the code they go
  through is unchanged.
- **C1 and Stop.** R18 is respected: a verified download counts as finished
  (the card import also finishes a verified copy), and `finish` sends no
  request. Stop waits for at most one photo's metadata read, move and
  transaction. Before this change, a queued ExifTool read could not be
  interrupted either.
- **`perform` over `session.bytes(for:)`.** The trust challenge, the redirect
  refusal and the ephemeral configuration are still session-level and work
  as before. Answers that are not 2xx cancel the body. `tooLarge` is not
  transient, so it is not retried.
- **Concurrency.** No new `@unchecked Sendable` or `nonisolated(unsafe)`.
  `FinishStep`, `Target` and `FinishOutcome` are `Sendable`.
- **Determinism.** 15 clean runs here plus the engineer's runs, which
  `status.md` doesn't count for the new tests. On their own, 15 runs rule
  out a flake rate above about 1 in 5. The structural argument is the
  stronger evidence: `caps`, `insaneSizes`, `keyRollback`, `endToEnd` and
  `containment` have no timing. In `stopWhileFinishing`, the cancel happens
  in step with the first metadata read, and `finish` can't be cancelled.
  Its only race is C17, and that race can only cause a false failure.
- **Held, not findings:** C10, the Tailscale `100.64.0.0/10` range and the
  `Info.plist` string wait on the owner.

## Third pass

Reviewed: `feature/immich-import`, 3093030..22103c2 (one code commit, 22103c2;
47bfd58 after it is the designer's `review.md` only). Build and tests:
`swift build --build-tests` clean. `swift test --filter Remote`: 59 tests in
7 suites pass. Full `swift test`: 1512 tests in 213 suites pass (76.9 s). One probe ran in a throwaway copy
of 2552143 under the scratchpad, never in the repository: the new
`catalogErrorAfterMove` body, with its temporary trigger.

### Verdict

Ready for QA from the code-review side. C12 to C18 are fixed. The new code
has no defect that needs a fix before QA. One nit: half of the new streaming
test cannot fail (C19).

### Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C19 | Nit | `Tests/PhotoCoreTests/RemoteReviewFixTests.swift:323-331` (`streamingCaps`, the original's half) | The chunked original 1 KiB past its listed size fails as `.incomplete` whether or not `DownloadSink.received(_ data:)` stops it. Without the cap the sink writes the whole body. `verify` (`RemoteImporter.swift:426`) then finds `byteCount != expected` and gives the same `.incomplete`. The partial is removed and the same single file is left. | If the limit check in `received(_ data:)` (`RemoteHTTPSession.swift:292-295`) is deleted, this half still passes. A server that streams an endless original fills the disk before `verify` runs, and no test catches that. The album half does discriminate: without the read-loop cap, 17 MiB of spaces would fail to decode as `malformed`, not `tooLarge`. Fix: call `setup.client.download(assetID:to:limit:)` directly on the chunked oversize asset. Expect `RemoteError.tooLarge` and a file no larger than the limit. | C16; WORKFLOW, tests that fail without the fix |

### Confirmations

| Finding | Status | Evidence |
|---|---|---|
| C12 | Fixed | `Catalog.fillPairCaption` runs inside `insertRemoteMaster`'s `database.write`, after the insert and the pairing, in the same transaction. I checked all four cases. **Neither image has a caption:** the server's trimmed description goes to both, and nothing is written when it is empty. **One image has one:** the empty one takes that caption, read back untrimmed. The server's is ignored, so the library wins (R17). **Both have different ones:** `empty` is empty and the function returns without writing (`pairCaptionsKept`). **No partner:** `descriptiveImages` returns the image alone, which is the old behavior. The function writes only to rows whose caption is NULL or blank after trimming, so a caption the person wrote is never overwritten. It is a plain `UPDATE … caption`, so `sidecar_description` queues each changed image. The RAW's sidecar, which owns the pair's, is queued when the RAW takes the value. One difference from card import is intended: when the photo just imported has a caption from its own file, that caption also fills the partner's empty one. This is C12's "treat the pair as one". |
| C13 | Fixed | The probe at 2552143 reached the insert. It failed with "SQLite error 19: the test refuses this insert … `INSERT OR IGNORE INTO "image"`" (`RAISE(ABORT)` wins over `OR IGNORE`), left `Photos/IMG_0001.JPG` behind, and failed the files expectation. At 22103c2 it passes. The trigger is `TEMP` on the test's own `Catalog.makeInMemory()` queue, so it lives only as long as that test's private connection and cannot reach another test. It is never dropped, and doesn't need to be. |
| C14 | Fixed | The test now refuses `generalCategory == .control` (Cc) and accepts Cf. `formatCharacters` covers both sides, including NEL (U+0085, Cc). See "Checked and fine" for names that hold bidi or zero-width characters. |
| C15 | Fixed | `makeTarget` reads the `ProjectRecord` inside `finish`, which runs in its own unstructured `Task` that Stop doesn't cancel. The loop takes `made.project`, so no read is left in the cancelled task. On the old code, `stopWhileFinishing`'s new expectation would read nil: the cancel lands at the first metadata read, before the `try?` read in the cancelled task. |
| C16 | Partly | The `.chunked` fault sends `Transfer-Encoding: chunked` with no `Content-Length`, in 64 KiB chunks. `.huge` sets no length header, so the album half reaches the read loop's cap (`expectedContentLength` is -1). The original's half does not test the sink (C19). |
| C17 | Fixed | The import's task first waits on an `AsyncStream`. `reader.task` is set before `yield`, so `cancel()` can no longer act on nil. That was the only race. The test is now structurally deterministic: the cancel happens inside the first metadata read, and `finish` cannot be cancelled. |
| C18 | Fixed | The comment is on `sanitize`. |
| N-3 (design), `ServerFormRules.pin` | Correct | The fields are `.disabled(isChecking)` and the certificate page replaces the form, so the address at Trust time is the address the check ran for. `trusted.address` is therefore the right binding. `addressEdited` clears `trusted` on any change, cosmetic ones included. `pin` also compares normalized addresses on both branches, so a pin from address A is never sent with address B. The saved pin is used only while `existing.address` equals the normalized address. A trailing slash normalizes to the same address, so that edit keeps the saved pin. After a real address change there is no pin. When a cleared or unused trust drops a pin, it is never silent. Either the next check shows the certificate page again (untrusted or changed), or the new address has a certificate the system trusts and the record saves with no pin. That is design §3.6's "a pin is for one address". A name-only edit saves `existing` and keeps its pin. `pinFollowsAddress` covers the four branches. |
| N-1 (design), certificate page | Correct | Only the body is in the `ScrollView`. The header (Back, ⌘[) and the button bar (Cancel with `.cancelAction`, then Trust Certificate with no shortcut) are outside it, so neither is ever scrolled away. There is still no default button: Return does nothing on this page. The scroll view is in a sheet, not under the window's toolbar. `CopyAdjustmentsSheet` and `LookTableBrowserSheet` use the same pattern. The body is static text and the fingerprint elements, so focus order is unchanged. VoiceOver scrolls the fingerprint into view. How it looks in a short window is M1 and M2 for the person. |
| N-4, N-5, DQ-11 | Fine | `focusesGridWhenShown` is cleared on a failed connect. The comment was corrected. The new alert sentence has one catalog key with both plural forms, and `LocalizationTests` passes. |

### Checked and fine

- **Names with format characters (C14), path safety.** `sanitize` still drops
  Cc and Cf (`CharacterSet.controlCharacters`), so no bidi control (U+202A
  to U+202E, U+2066 to U+2069), zero-width character, LRM or RLM reaches a
  file name on disk or the library's `fileName`. A name made only of format
  characters (`"\u{200B}.jpg"`) gives an empty `{name}`, then an empty
  fallback stem, then `photo.jpg`. `"\u{202E}..\u{202E}.jpg"` sanitizes to
  `..`, loses its leading dots and becomes `photo.jpg`. Dots and a separator
  can't form `..` as a component: every value goes through `sanitize` (it
  turns `/`, `\` and `:` into `-` and strips leading dots), and the extension
  is appended to the stem. A Cf character in an extension makes it
  non-plain, and `FileKind` refuses it at decode anyway. `a\u{200B}.jpg`
  next to `a.jpg` lands as `a.jpg`, then `freeName` numbers it. Combining
  sequences (Mn) were accepted before this change too. APFS's
  normalization-insensitive lookup sends NFC/NFD twins through `freeName`
  as well. `isInside` (layer 3) does not depend on any of this.
- **Names with format characters, display.** An RLO in a server's name only
  changes how that name is drawn where the server's name is shown as is.
  The browse tile draws the stem without its extension (`ImportCell`), and
  the type badge comes from the real kind. Failure lines in Activity and
  the alerts use the full name, so `a\u{202E}2wr.jpg` would read
  "agpj.rw2". Nothing is decided from the drawn text. The file lands as
  `a2wr.jpg`. The names come from the person's own account, and Finder draws
  such names the same way. This doesn't matter for safety and is not a
  finding.
- **`fillPairCaption`'s blank test.** It trims `.whitespacesAndNewlines`;
  the old SQL `trim()` trimmed spaces only. So a caption that is only a tab
  or a newline now counts as empty and is filled. That is not a value a
  person writes, and Info treats blank the same way.
- **`makeTarget` ordering.** The extra read comes after `createImportRun`. A
  failure there throws inside `finish`, and the partial is removed as before.
  A target that was made when the photo then fails still names its project,
  as the old `projectSummaries` read did.
- **Determinism.** `pairCaptionEitherOrder`, `pairCaptionsKept`,
  `formatCharacters`, `streamingCaps`, `pinFollowsAddress` and
  `catalogErrorAfterMove` have no timing or shared state. Each uses its own
  fake server and in-memory catalog. Listing order comes from `takenAt`,
  one second apart. `stopWhileFinishing`: see C17 above. That is a
  structural argument, not a run count.
- **Held, not findings:** C10, the Tailscale `100.64.0.0/10` range and the
  `Info.plist` string.

### Follow-up

C19 is a nit and does not block QA. If it is taken, record it here with
its commit.

## Fourth pass

Reviewed: `feature/immich-import`, 23438c7..1176625 (0877051: C19's test and
the certificate footer, N-7; 1176625: QA Q1 to Q4). Date: 2026-11-23. Build and
tests: `swift build --build-tests` clean. `swift test --filter "Remote|Import"`:
127 tests in 23 suites pass. Full `swift test`: 1514 tests in 213 suites pass
(77.6 s), no failure.

### Verdict

Ready for the owner's sign-off checks from the code-review side. C19 is fixed,
the four QA fixes do what `status.md` says, and none of them reaches a normal
launch. One nit, older than this pass: `importerHasNoServers` proves that one
guarded server item exists, not that none is unguarded (C20).

### Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C20 | Nit | `Tests/PhotoCoreTests/RemoteBoundaryTests.swift:105-121` | The window and menu checks are `contains` checks on one guarded occurrence. They do not count occurrences, and they do not check the second `if includesLibraryItems {` block in `ImportCommands.swift:80` (Album and Date Range…). The order of the two `.noSource` cases in `ImportWindow.swift:324` and `:330` is not checked either. Collapsing white space does not make this weaker. It turns runs of white space into one space and adds none, so `{ForEach` with no space would now fail (too strict, harmless). A pattern split across a comment line matched before as well. | Each of these passes the test while the importer shows a server item: (a) a fourth `Button("Add Server…")` added outside `if !model.copiesOnly`, such as a toolbar item; (b) `Menu("Album")` or `Date Range…` moved out of the line-80 block; (c) `case .noSource:` moved above `case .noSource where model.copiesOnly:`, so the importer's empty state says "…or Add a Server" and has an Add Server… button. QA's scripted S11 on the importer bundle would catch all three, so this is a nit. Fix if wanted: count `Button("Add Server…")` and `model.servers` occurrences against the guarded ones, check the line-80 block's text, and check that the `where model.copiesOnly` case comes before the bare one. | Tests that fail without the fix |

### Confirmations

| Item | Status | Evidence |
|---|---|---|
| C19 | Fixed (0877051) | The test calls `client.download(assetID:to:limit:)` directly on the chunked oversize asset. It expects `RemoteError.tooLarge`, at most `limit` bytes reported, and no file left. `DownloadSink.received(_:)` (`RemoteHTTPSession.swift:289-307`) reports a chunk to `progress` only after the chunk is under the cap and written. If the cap check is deleted, every chunk is written and reported, the sum is `limit + 1 KiB`, and the download finishes without `tooLarge`. Both expectations then fail. No timing: the fake is in-process and the result does not depend on how the bytes are split into chunks. |
| Q2, Select All | Same behavior | `ImportSelection.all(of:)` is the old expression moved as is: `Set(shots.filter { !$0.isDuplicate }.map(\.id))`. `CardImportModel.selectAll()` is still the only place that sets the selection to all, and every way in calls it: the window's Select All button (`ImportWindow.swift:138`), the grid's context menu (`ImportGrid.swift:218`), and ⌘A or Edit ▸ Select All through the grid's `selectAll(_:)` override (`:273`, validated by `canSelectAll` at `:341`). It covers loaded shots only, since `shots` is what has been listed. Marked shots stay out because `SourceShot.isDuplicate` is true only when every file is a duplicate, so a pair with one new file is still taken. Nothing loaded gives an empty set. Videos and offline sources have no special case, before or after. The test builds its shots with the product's own `RemoteAsset.shot(linked:)`, so marked means the real `isDuplicate`. It covers the loaded, marked, not-yet-loaded and empty cases. |
| Q2, AC12 fake | Fine | The fake's listing now carries `isFavorite` and a `tags` array. Its routes, the paths it accepts, the headers it checks and the faults are unchanged, so the allowlist and posture tests (`RemoteBoundaryTests`, the request log) assert the same things. The client's decoder ignores the new keys. `favoritesTagsAlbumsIgnored` would fail if the importer ever mapped a favorite to a flag, tags to keywords or membership to an album, because each of those makes a count non-zero. Deterministic: its own fake and in-memory catalog, no timing. |
| Q3, `import server sheet review` | Debug only | It lives in `DebugServerCommands`, reached only from `DebugScript.runImportCommand`. `DebugScript.startIfRequested` returns at once unless `LaunchOptions.current.debugScript` is set. The made-up `CertificateSummary` is built in PhotoApp's debug file. The commit adds nothing to PhotoUI or PhotoCore for it: `ServerSheet.page` was already public, and `CertificateSummary.init` and `CertificateFingerprint(certificateData:)` were already used by the product. So no new path exists in a normal launch that puts a certificate the server didn't present on the page. Trust from that page still goes through `trustCertificate()`, which runs the check again with that pin. Against a real TLS server a made-up pin would fail the check. The fake's plain HTTP is what lets the scripted B1 save it. `server list` now prints the pinned fingerprint, which is public, and never the key. |
| Q1, debug `quit` | Debug only | The four new lines are inside `DebugScript`'s `case "quit":`, beside the library sheets it already closed. `applicationShouldTerminate`, `QuitGuard` and `ImportCommands` are unchanged by 1176625, so a real ⌘Q runs exactly as at the third pass. |
| Q4, zero-import text | Fine | The new branch comes after the alert branch and the Stopped branch, so a stop or a failure still says what it said before. "No photos were imported" is a key of its own with no argument, so it needs no plural. "Imported %lld photos" keeps its plural variations for 1 and more. The trailing period differs from Activity's "No photos were imported." on purpose, as the subtitle and report lines do elsewhere. `LocalizationTests` passes. |
| N-7, certificate footer | Fine | The interpolation is unchanged, so the catalog key with `%@` matches. The old key was replaced, not left behind. |

### Question answered: ⌘Q with a sheet up

I agree with the engineer. The question is whether a real ⌘Q with the Server
sheet up is ignored for every sheet alike, and so is not something this branch
broke.

- **The app has no sheet check.** `AppDelegate.applicationShouldTerminate`
  (`PhotoApplication.swift:104-111`) returns `.terminateNow` whenever no import,
  folder add, export or merge runs. It never looks at sheets, and neither does
  `QuitGuard`. So when a quit with a sheet up does nothing, AppKit refuses it
  before or around the delegate, not this app's code.
- **It is older than this branch.** The debug script's `quit` has closed the
  library's sheets first since c008987 (2026-10-27), with the comment "An open
  sheet would keep the app from quitting". The engineer's control shows the
  same thing: the Copy Adjustments sheet, which this branch doesn't touch,
  blocks `NSApp.terminate` exactly as the Server sheet does.
- **What this branch changes.** Its only change to quitting is
  `cardImport.waitUntilDone(timeout: 10 s)` after Stop and Quit (C7). That runs
  only after the person chose Stop and Quit, and only while a server import
  runs. The branch adds one more sheet of the same kind (the Server sheet,
  certificate page included), and alerts and a confirmation dialog on the
  import window that behave the way other SwiftUI alerts do. None of this is
  worse than the other sheets.

That rests on reading the code and on the engineer's scripted runs; I did not
launch the app. P8 stays a check for a person. Making ⌘Q close sheets would be
an app-wide follow-up, not a change for this branch.

### Checked and fine

- **The debug `quit` after a removal.** `ServerSheet.remove()` sets
  `removalAfterSheet`, and `serverSheetDidDismiss` asks the removal question
  when the sheet has gone. `quit` clears `removingServer` but not
  `removalAfterSheet`. So `import server sheet remove; quit` with no wait
  between them could raise the confirmation after `quit` cleared it, and hang
  as Q1 did. That is a debug script's own ordering: a `wait` avoids it. It is
  not a finding.
- **Determinism.** `selectAllRule` is pure. `favoritesTagsAlbumsIgnored` and
  C19's half of `streamingCaps` have no timing or shared state (structural
  argument). This rests on the full run here, not on a repeated-run count.
- **Held for the owner, not findings:** C10, the Tailscale range and the
  `Info.plist` text.

### Follow-up

C20 is a nit and does not block sign-off. If it is taken, record it here with
its commit.

## Fifth pass

Reviewed: `feature/immich-import`, 3e90686..54760d1 (f334d9d: owner finding
O1, a server import adds to an existing project of the same name; 1978f2a:
design DQ-12 to DQ-14, docs only; 54760d1: the DQ-13 note and the DQ-14
stacked field). c3ea072, the designer's fourth review, came in during this
pass and touches `review.md` only. Date: 2026-11-24. Build and tests:
`swift build --build-tests` clean. `RemoteProjectReuseTests` 7 of 7, 20 of 20
runs clean. `LocalizationTests`, `BrandingTests`, `RemoteImportTests`,
`RemoteReviewFixTests` and `ImportTemplate` pass. Full `swift test`: 1521
tests in 214 suites pass (78.4 s). Two probes ran in a throwaway worktree
under the scratchpad, never in the repository; they are described under
Checked and fine.

### Verdict

Ready for QA and the owner's M1 from the code-review side. The lookup and the
insert are one serialized write. The note and the importer use the same
cleaning, the same comparison, the same fallback to the address and the same
address, so the note shows exactly when the import would reuse a project, as
far as the loaded project list is current. The new tests fail without the
change, and the concurrency test catches a lookup split from its insert. One
nit: a test comment claims a check the test doesn't make (C21).

### Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C21 | Nit | `Tests/PhotoCoreTests/RemoteProjectReuseTests.swift:76-78` | The comment says "An empty field falls back on the address, and that name is reused too". The test checks only `RemoteProjectName.cleaned` (`" / "` gives `-`, blanks give the address). It never calls `projectForImport` twice with the address, and no test runs an import with an empty field. | None today: the fallback goes through the same `projectForImport` as any name, and `reuseNote`'s `shows("   ")` covers the note's side. But if `makeTarget` stopped applying `cleaned` (or passed a different address than the note uses), no test would catch it, and the comment says one would. Fix if wanted: add a second `projectForImport(named: cleaned("  ", address:))` and expect `!created`, or change the comment. | Tests that fail without the fix |

### Checked and fine

- **One serialized write.** `Catalog.projectForImport` reads every project
  and inserts inside one `database.write`, and GRDB serializes writes. So no
  other write can create the twin between the lookup and the insert. Probe:
  with the lookup moved to its own `database.read` before the write,
  `concurrentLookups` failed 5 of 5 runs (two issues each). The test does
  detect the race it is meant for. On the code as built its pass is
  structural: 16 writes in series, the first inserts and the other 15 find
  that row. Reading the whole `project` table in the write is one small query
  per import, made once (the target is kept for the run).
- **Tests fail without the change.** Probe: with `makeTarget` put back to
  `createProject` (the cleaned name kept), `secondImportReuses` failed with 4
  issues and `keepsSourcePath` with 1, which confirms `status.md`. The other
  four tests call the new functions directly. `comparison`,
  `severalWithTheName` (explicit `createdAt`, the tie on `id`), `reuseNote`
  and `differentNameCreates` have no timing or shared state. Each import test
  has its own fake server, in-memory catalog and temporary folder. This is a
  structural argument; the 20 clean runs alone would rule out only a flake
  rate above about 1 in 7.
- **First photo fails after the target is made.** `makeTarget` still runs
  inside `finish` (the task Stop doesn't cancel, C1), after the duplicate
  check. An import whose photos are all already in the library therefore
  touches no project. When the first verified photo then fails (the move,
  `outsideDestination`, `pathTaken`, a catalog error), `failed` returns the
  target and the run keeps it. A **created** project stays empty, with an
  `importRun` and no images. That was already so before O1 (third pass,
  "`makeTarget` ordering"). Now the next import of that name reuses the empty
  project instead of making a second one. A **reused** project is untouched
  apart from one more `importRun` row with no images. `lastImportRun` skips
  runs with no image, so Last Import still shows the previous import. When
  `createImportRun` throws after `projectForImport` created the project, the
  target stays nil. The next photo then calls `makeTarget` again and finds
  that project instead of making another. That is better than before. DQ-12's
  "an import that brings nothing touches none" is true except in that rare
  failure, as it was before.
- **Note against importer.** The importer gets `.named(browse.projectName)`
  and `options.link.address = browse.address.normalized`
  (`ServerSource.swift:389-394`). The note uses
  `cleaned(browse.projectName, address: browse.address?.normalized ?? service.address)`.
  The `??` side matters only when the address can't be parsed, and then
  `startServerImport` returns at its guard, so nothing is imported. Both sides
  compare with Swift `==` (case counts, canonical equivalence), and both
  search every project row: `projectSummaries` has no `WHERE`, and the
  importer fetches the whole table. Several projects with the name show the
  note, and the oldest takes the photos. Add to set to a project hides the
  field and the note, and the importer gets `.existing`. A stored name that
  `cleaned` can never give (a double space or a `/` from a rename) matches on
  neither side. The one gap is staleness: `library.projects` is a snapshot
  that `refreshProjects` renews after imports, renames and removals. A project
  made by another path in the moment before Import would make the note lag,
  never the import. The design accepts "the library's list not loaded yet"
  as hidden. A running import doesn't refresh the list, but its name is
  already fixed in `options`.
- **Observation.** `addsToExistingProject` reads `browse.projectName`,
  `existingProjectID` (both observed) and `library.projects`. `LibraryModel`
  is `@Observable`, so a read through the `@ObservationIgnored` weak
  reference still registers. The note appears after the import that creates
  the project, as `status.md`'s scripted run shows.
- **Swift 6 concurrency.** No new `@unchecked Sendable` or
  `nonisolated(unsafe)`. `projectForImport` returns a `Sendable` tuple from
  the write. `addsToExistingProject` and `announceProjectNote` are on the
  model's main actor and read only in-memory state: no catalog access on the
  main actor. `projectForImport` runs in `finish`'s unstructured task, so a
  Stop can't make GRDB throw `CancellationError` inside it.
- **VoiceOver.** The visible label and the caption are both
  `accessibilityHidden`. The field keeps "Project name" as its label
  (`labelsHidden` hides it only visually). The sentence is the field's hint
  while it shows, and the hint is empty otherwise. That is the same pattern as
  `ServerSheet`'s result hints. The announcement fires only on a change of
  the name: `setServerProjectName`, or `chooseAlbum`'s prefill when the field
  wasn't edited. It fires only on a hidden-to-shown change, at medium
  priority. Changing the server (`chooseServer`), opening the window, Add to
  and a refreshed project list don't announce. Nothing reads the sentence
  twice: the caption is hidden, and a changed hint is not spoken until focus
  returns to the field.
- **Strings.** One new key, its English text, with the designer's comment,
  `en` and `translated`, read through `String(localized:comment:)`.
  `Text(cond ? sentence : "")` is a `String`, so it is shown verbatim and
  needs no key. "Project name" is an existing key. `LocalizationTests` and
  `BrandingTests` pass. The debug script's `project` command only types into
  the field. It changes no photo, so it needs no undo group.
- **Undo, History, `importRun`.** Imports register no undo step and write no
  edit history, and this diff changes neither. Each import is still its own
  `importRun` (`secondImportReuses` checks two runs in one project), so Last
  Import (`.importRun(lastImportRunID)`) shows only the newest import's
  photos. `didFinishCopyImport` refreshes the projects and selects the reused
  project, or reloads it when it is already selected. It never adds a row of
  its own, so the sidebar can't list the project twice. A reused project keeps
  its `sourcePath`, as `CopyImporter`'s `.existing` does.
- **RAW+JPEG pairs and sidecars.** Pairing is by volume, project and folder
  plus stem (`ImagePairing.pair`). With reuse, a RAW from an earlier server
  import and a JPEG from a later one, in the same folder, now pair. Before
  O1 they sat in two projects and didn't pair. This is the library's rule, the
  same as a card import set to Add to. `mergeDefaultVersions` lets the RAW's
  culling values win and combines keywords and albums. Then the C2 and C12
  writes fill the server's rating and description only where the pair is
  empty (`insertRemoteMaster`), so they can now reach a photo imported
  earlier whose value is empty. A rating or caption the person set is never
  replaced. Each `UPDATE` queues the owner's sidecar through the existing
  triggers, and `SidecarSync` still refuses a sidecar another app changed.
  QA may want one scripted case: import a RAW, then its JPEG in a second
  import of the same scope.
- **Scope.** Card and folder imports still call `createProject`
  (`CopyImporter.swift:225`, `Importer.swift:256`). `RemoteImporter` has one
  caller (`ServerSource.swift:395`). No migration, no pipeline bump, no
  golden. Nothing touches the network, a parser or file writing, so
  `/security-review` doesn't need to run again.
- **Held for the owner, not findings:** C10, the Tailscale range and the
  `Info.plist` text, as before.

### Follow-up

C21 is a nit and does not block QA or sign-off. If it is taken, record it here
with its commit.

## Sixth pass

Reviewed: `feature/immich-import`, e143423..96e1e60 (96e1e60: a test change
in `RemoteProjectReuseTests.swift`, the user guide and `status.md`; no
source). Date: 2026-11-24. Build and tests: `swift test --filter
RemoteProjectReuseTests` 8 of 8 pass.

### Verdict

C21 is fixed and the guide edit (N-9) is true to the code and design. No new
findings. Ready for QA and the owner's look check (the design review's M12).

### Follow-up

| # | Status | Commit | Check |
|---|---|---|---|
| C21 | Fixed | 96e1e60 | `comparison` now calls `projectForImport` with `cleaned("  ")` (created, named the address) and then `cleaned("")` (found, same id). The new `emptyFieldImportsReuse` runs two real imports through `RemoteImporter.run`, so through `makeTarget`, with the field `"  "` then `""`. Two probes ran in a throwaway worktree under the scratchpad (removed afterwards; the repository was never edited). (1) `makeTarget` passes the raw name instead of `cleaned`: the new test fails 3 expectations (`RemoteProjectReuseTests.swift:102, 103, 105`), as `status.md` says. (2) `makeTarget` falls back on a different address (`options.destination.lastPathComponent`) than the one the note uses: it fails 2 (`:102, :105`), and the other 7 tests still pass. So the test catches both drifts C21 named. Determinism, a structural argument: the test has its own `FakeImmichServer`, in-memory catalog and temporary folder. The two imports are awaited one after the other, and nothing depends on timing or pool order. |

Guide (N-9), checked against the code: `ImportWindow.swift:413` shows the
server's Project name field, and the note inside it, only while
`existingProjectID == nil`, meaning Add to is New Project.
`ServerSource.swift:389` sends `.existing(id)` otherwise, so `makeTarget`
uses that project and never looks up the name.
`RemoteProjectName.addsToExistingProject` returns false for an existing
project. This matches design §5.3 ("When **Add to** names an existing project
the field is absent") and DQ-13. The guide's "A card or folder import set to
**New Project** still always makes a new one" still holds:
`CopyImporter` and `Importer` call `createProject`.
