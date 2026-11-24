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
