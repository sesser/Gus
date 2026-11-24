# Import from Immich: QA

Owner: qa-tester. Date: 2026-11-23. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/immich-import` at 0877051 (issue #271, PRD rev4), on an Apple M4
Pro, macOS 27.2.1 (26B131), Swift 6.4.2 (the local toolchain); the CI toolchain
build used Xcode 26.3.

## Verdict

Passes: all 17 acceptance criteria and every review finding (C1 to C19, F1, F2,
B1, S1 to S6) are shown by a test, a scripted check, or both; AC17's
README, roadmap and `CLAUDE.md` halves are the product manager's at Ship. No
blocking finding. Two things only a person can settle came out of this run and
are on the list below: a real self-signed `https://` server through the real
sheet (P2, P3), and whether a real ⌘Q with the Server sheet open quits (P8,
Q1).

Safety, as the prompt requires: every launch carried `--library-root` on a
scratch library; the copy of the bundle had its own bundle identifier. After the
run no instance of mine was running, the owner's library folder
(`~/Library/Application Support/Gus/Library`) has 0 files newer than my start,
and the owner's preferences file has the same checksum as before. The owner's own
`/Applications/Gus.app` (pid 96460, started 15:16 today, not by me) was running
the whole time and was left alone.

## Builds and the full run

| Check | Result |
|---|---|
| `swift build` | Complete, 0 warnings |
| `swift test` (full) | 1512 tests in 213 suites passed after 79.4 s (wall 1:22); 0 failures. Neither known flake (`PreviewTests.serviceGeneratesOnceThenServesFromCache` #274, `DeferredRenderTests` #229) failed |
| `swift test --filter Remote` | 59 tests in 7 suites passed (4.7 s); repeated 15 of 15 clean runs |
| `swift test --filter "LocalizationTests\|BrandingTests\|CatalogTests"` | 40 tests in 5 suites passed |
| `Scripts/build-app.sh all` | Both bundles built and signed (Gus.app and Gus Importer.app), 72 s |
| CI toolchain: `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` | Complete, 0 warnings (an up-to-date incremental build, 0.14 s: the engineer's build at this commit was current) |

The 15 repeats are a smoke run, not a determinism claim; the structural
arguments in `status.md` ("Determinism") are what the code review accepted.

Every test named below exists (`swift test list`) and passes.

## Acceptance criteria

How is Test, Script or Person. Evidence is the test (suite "Immich …" /
function), or the script (S-numbers, in "Scripts" below). Tests are in
`Tests/PhotoCoreTests/Remote*.swift`.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 key only in the Keychain | Test, Script | `RemoteBoundaryTests.keyOnlyInTheStore` (every value of every catalog table, the report, the connection's description), `RemoteCheckTests.keyHidden`, `keyUsesInSources` (the one use of the key is the header; no log or print interpolates a key). Preferences and debug output are scripted, not a test (code review C11): after S1 to S9 the key texts `fake-key-0123456789`, `SECRETWRONGKEY` and `tls-key-ABCDEF` occur in no script output, no scratch catalog (WAL included), and not in the test copy's preferences (`defaults read`). The scripted launch uses the in-memory store (S10) | Pass |
| AC2 seven named failures | Test, Script | `RemoteCheckTests.sevenResults` (unreachable, not Immich, rejected, too old with both versions, each of the five permissions missing including `user.read`, extra permissions and `all` pass), `certificates` (a changed certificate), `keyStore`, `removal`; scripted S3 gave `keyRejected`, `notImmich`, `keychain`, `missingPermissions`, `unreachable` under the real sheet, S7 `certificateChanged` through real TLS | Pass |
| AC3 transport policy | Test, Script | `RemoteConnectionTests.transportPolicy` (the three local forms only after the notice, `example.com` and `8.8.8.8` refused), `RemoteReviewFixTests.numericHosts`, `RemoteSecurityTests.unicodeHosts`; S3: `http://example.com` and `http://134744072` (= 8.8.8.8) refused with Add dimmed, the fake's `http://127.0.0.1` shows the notice, Add dimmed until confirmed | Pass |
| AC4 certificates | Test, Script | `RemoteCheckTests.certificates` (untrusted offers its fingerprint, pinned passes, another fails), `noTrustBypass` (source and Info.plist). The swift tests have no TLS server, so the delegate itself was run for real in S7 against a Python HTTPS mock (below): the untrusted page showed the SHA-256 that `openssl` printed for the certificate, nothing authenticated was sent before Trust (the only keyless request is `/server/version`), after Trust the server was browsed and 2 photos imported over TLS, and after the mock switched certificates the check failed as `certificateChanged`, the grid showed Can't Connect, and the Edit sheet's check showed the same result, never a prompt. The real sheet's look and keys are P2 | Pass (look and keys: P2) |
| AC5 request allowlist | Test, Script | `RemoteCheckTests.allowlist` (every recorded request is on the list, no PUT, PATCH or DELETE, one POST and it is the search, `edited=false` on originals and thumbnails, seven off-list requests refused before sending), `redirectNotFollowed`; S1 `import server fake requests` showed only GET plus the one POST search | Pass |
| AC6 listing, pages, scopes | Test, Script | `RemoteImportTests.listing` (one search for the first screen, trashed, hidden, locked, archived, video, partner, GIF absent, newest first, the body), `albums` (an album lists only its own photos, a contributor's photo in it absent, the server's count, date range, a gone album); `RemoteBrowseRulesTests.paging`. S2: 250 loaded, no second search until `scroll end`, then 300; All Photos has no count (`total -`); Album Trip: 5 loaded, `total 7` (the server's number); date range gives 3 | Pass |
| AC7 nothing checked, marks, Select All | Script | S4: a source opens with `selected 0`; after importing 3 and the re-search, `marked 3`; the grid's context-menu Select All (the same `selectAll()` ⌘A reaches) gave `247 selected · 250 loaded` (250 loaded minus 3 marked), and after `scroll end` and Select All again `297 of 297`; a second import of linked assets sends no `/original` (`RemoteImportTests.links`). There is no Swift test of Select All itself (Q2) and ⌘A with a key window could not be scripted (macOS would not activate the copy): P5 | Pass |
| AC8 import, name, corrupt, short | Test | `RemoteImportTests.importsThree` (3 files by template, byte for byte equal, no temporary names, the edited project name used), `corrupt` (right size wrong bytes, and a short read: each one failure, no file, no row, others import); `RemoteBrowseRulesTests.projectName` (the prefill). Scripted S1: the project name is "Home - All Photos" and "Home - Trip" | Pass |
| AC9 duplicates, external library | Test, Script | `duplicates`, `externalLibrary` (path-hash checksum imports, counted as size only, cataloged with its SHA-256; one already in the library is a duplicate; a short one fails; an uploaded one with wrong bytes still fails), `sizeOnlyRules` (one byte short or long fails; no size and no `Content-Length` fails). S6: an external-library asset served short failed, an uploaded one corrupted failed, one external imported; Activity lists each reason | Pass |
| AC10 ordinary masters, pairs, Live Photos | Test, Script | `pairsAndLivePhotos` (RAW and JPEG of one stem pair; the Live Photo's video is not requested; counted). `photocli render` and `photocli export` of two imported photos on the scripted library worked (decoder `imageIO`; two JPEGs written). Opening in the loupe was not scripted: they are ordinary catalog masters | Pass |
| AC11 links | Test, Script | `links` (one link per version with provider, address, remote id and checksum; the connection's removal keeps them; other spellings of the address (case, slash, `/api`) find them; another address does not; no download again; removal of the photo removes its link; re-import makes a new link), `copiesHaveNoLink`. S5: server removed, added again under another name: `marked 3`; the catalog still held the link rows | Pass |
| AC12 description and rating | Test, Script | `metadata` (fills when empty, the file's own rating wins, two sidecars queued by the existing triggers, `edited=false`), `pairCaptionEitherOrder`, `pairCaptionsKept`, `pairGetsServerValues`. S1: IMG_0004 arrived with "From the server" and rating 4, the others with none. Not asserted by any test: favorite, tags and albums change nothing (nothing reads them; the code has no path) and that a sidecar another app changed is not overwritten (the unchanged `SidecarSync` tests own that). See Q2 | Pass |
| AC13 Stop and quit | Test, Script | `stop` (finished photos with links, no partial file, no request after), `stopWhileFinishing`, `catalogErrorAfterMove`. S8: Stop kept 5 photos with 5 links and no hidden file; ⌘Q during an import asked "Quit While Importing?", Keep Importing kept it running; Stop and Quit mid-download exited with 2 photos cataloged and linked and no partial file or process left | Pass |
| AC14 failures | Test, Script | `failures` (deleted asset, revoked key mid-import, a 503 retried), `unreachable`. S6 deleted asset: "3 could not be imported" with the reason in Activity; S9 revoked key mid-import: alert "“Home” rejected the API key" with the count, then Can't Connect (keyRejected); dropped connection mid-import: alert "“Home” stopped responding", 3 photos kept, no stray file. Pulling a real cable is P4 | Pass |
| AC15 migration | Test | `RemoteImportTests.migration` (v16 on a v15 catalog, the older data identical), `CatalogTests.schemaNamesDoNotEmbedTheProductName`, `BrandingTests.persistedNamesAreGeneric`, `CatalogTests.migrationsCreateTheExpectedTables` | Pass |
| AC16 standalone importer | Test, Script | `RemoteBoundaryTests.importerHasNoServers` (no server word in `Sources/PhotoImporter`, the library-only gates, Importer-Info.plist has no ATS key; this test reads source text, see Q2); S11: the importer's window, menus' items and bundle `Info.plist` have no server, Add Server… or network key; its window snapshot shows "No Card Connected" and Choose Folder… only | Pass |
| AC17 documented claims | Test, Person | `aboutIsNetworkFree` (the About code has no network word; the guide says "window contacts nothing"). The guide (`docs/USER_GUIDE.md` lines 33 to 126 and 1136) is complete and matches the UI terms. README, roadmap principle 3 and `CLAUDE.md` are the product manager's at Ship: see "Docs" | Pass for what is built; Open for Ship (README, `CLAUDE.md`, roadmap, inventory) |

Counts: 17 criteria, 0 failed. By test alone: 2 (AC8, AC15). By test and script
together: 13 (AC1 to AC6, AC9 to AC14, AC16). By script alone: 1 (AC7). AC17: a
test for what is built (the About code and the guide); README, roadmap and
`CLAUDE.md` wait for Ship. Open for a person: none for want of a check, but the real
sheet and TLS (AC4: P1 to P3), a real cable and key revocation (AC14: P4) and a
real ⌘A (AC7: P5) are on the list.

### Review findings

| Finding | How | Evidence | Result |
|---|---|---|---|
| C1 verified file stranded; Stop as failure | Test, Script | `RemoteReviewFixTests.stopWhileFinishing`, `catalogErrorAfterMove`; S8 | Pass |
| C2 server values split a pair | Test | `pairGetsServerValues` | Pass |
| C3 overflow on sizes | Test | `insaneSizes` | Pass |
| C4 unbounded bodies | Test | `caps` | Pass |
| C5 numeric hosts | Test, Script | `numericHosts`; S3 (`http://134744072` refused) | Pass |
| C6 Keychain reach from a test launch | Test, Script | `keyStoreForLaunch`; S10 | Pass |
| C7 Quit leaves a partial | Script | S8 (Stop and Quit mid-download: no partial file) | Pass |
| C8 Keychain on the main thread | Code | `nonisolated` check and detached key-store tasks read in `ServerSource.swift`, `ServerSheet.swift`; the prompt itself is P7 | Pass (code); P7 |
| C9 developer text in Activity | Code, Script | `reason(_:)` read; Activity texts in S6 and S9 are all sentences | Pass |
| C10 fake server linked into the app | Held for the owner | | Held |
| C11 AC1's parts | Recorded | AC1 row | Pass |
| C12 pair caption either order | Test | `pairCaptionEitherOrder`, `pairCaptionsKept` | Pass |
| C13 after-move test | Test | `catalogErrorAfterMove` (the code reviewer ran it against the unfixed code; I did not repeat that) | Pass |
| C14 names with format characters | Test | `formatCharacters` | Pass |
| C15 Stop in the first photo keeps the project | Test | `stopWhileFinishing` | Pass |
| C16, C19 streaming caps | Test | `streamingCaps` (album list and the download's own limit; the engineer and the code reviewer showed C19's half fails without the limit check; not repeated here) | Pass |
| C17 handoff race | Test | `stopWhileFinishing` (a structural argument, not a run count) | Pass |
| C18 doc comment | Code | | Pass |
| F1 path traversal | Test, Script | `RemoteSecurityTests` (`templateFallback`, `namesAtDecode`, `endToEnd`, `containment`); S6 with the template `{job}`: names inside the destination | Pass |
| F2 key rollback | Test | `keyRollback` | Pass |
| B1 trust-only save in Edit | Test | `trustedPendingIsAChange`; the real Review Certificate page is P2 (the script cannot open the sheet on that page, Q3) | Pass; P2 |
| S1 key field empties | Person | P2 (view state) | Open |
| S2 sheet height | Test, Script | `sheetHeight`; S3: 460×380, with the notice 460×470, with the notice and a result 460×530, ideal equal | Pass; look P1 |
| S3 confirmation during close | Script | S12: from the Edit sheet, Remove: "sheet closed asks Home"; No keeps the server, Yes removes it | Pass; keys P3 |
| S4 grid keyboard after Add | Script | S5: after Add the grid is first responder (`first responder true`) | Pass; keys P5 |
| S5 `.contain` for the result block | Code | | Pass |
| S6 toolbar titles | Person | P6 | Open |
| N-1, N-3, N-4, N-7 | Test, Code | `pinFollowsAddress`; the footer wording read in `ServerSheet.swift`; look P1 | Pass |

## Findings

No blocking finding.

**Should fix (harness, with a real-app question)**

- **Q1. The debug script's `quit` does not quit while the Server sheet is up.**
  Steps: `import open; wait 2; import server sheet add; quit`. Expected: the
  app exits (every script must end with `quit`). Actual: the process idles
  forever (a `sample` showed it in its event loop, no deadlock); with
  `import server sheet close` before `quit` it exits. `quit` closes the library
  window's sheets by name (`showsExportSheet = false` and the others) then calls
  `endSheet` on attached sheets; the Server sheet is on the import window and
  survives that. The same happened with `import close` and `import terminate`
  in place of `quit`. For the engineer: close `model.cardImport.serverSheet`
  (and any other import-window sheet) in `quit`. Whether a real ⌘Q with the
  sheet open quits is not known: the copy could not be activated, so I could
  not press it. P8 asks for it; if it fails by hand, it is a product bug and
  blocks.

**Nits (for the engineer; none blocks)**

- **Q2. Two assertions live in source text or in nothing.** (a) Select All's
  rule (loaded, unmarked only) has no Swift test: `selectAll()` is one line
  with `filter { !$0.isDuplicate }`; I checked it through the grid's
  context-menu Select All in S4. A unit test on the model (or a debug command
  that posts ⌘A) would pin it. (b) AC12's "favorite, tags and albums change
  nothing" has no assertion (the fake does not model them) and "an existing
  sidecar changed by another app is not overwritten" relies on the unchanged
  `SidecarSync` tests. (c) `importerHasNoServers` matches exact whitespace in
  `ImportWindow.swift` (`"if !model.copiesOnly {\n                    ForEach(…"`);
  a reformat breaks it with a message that does not say why.
- **Q3. The script cannot reach the Review Certificate page.** `sheet edit`
  opens page 1; the result block's Review Certificate… button has no command,
  and `sheet trust` on page 1 is a no-op. B1's path (trust with nothing else
  edited, from a grid's Can't Connect state) therefore has its unit test
  (`trustedPendingIsAChange`) and P2, nothing in between. A `sheet review`
  command would let QA run it against a TLS server.
- **Q4. "Imported 0 photos" in the window after a run that only found
  duplicates.** In S7's duplicate run the window's done text read "Imported 0
  photos" while Activity said "No photos were imported. 3 were already in the
  library." Same cosmetic family as design review N4; worth the same fix.

**Docs (for Ship, not the engineer):** see below.

## Docs the feature must change

`docs/USER_GUIDE.md` is in step (new section, the About line, the permission
list once; terms match the UI; the claims "the About window contacts nothing" and
"the app contacts a network only to reach an Immich server you added" are true).

`status.md`'s README list (README, `CLAUDE.md`, roadmap principle 3, the About
design note) is **not complete**. I grepped README, `CLAUDE.md`, the roadmap and the
guide for "contacts nothing", "no network", "never contacts", "leaves the Mac",
"telemetry", "URLSession". Findings:

| File | What it says | What Ship must do |
|---|---|---|
| `docs/roadmap.md` line 33, principle 3 | "nothing leaves the Mac unless the user sends it" | The PRD's wording (connecting to a server the user adds is the user's act and sends only the key and read requests to it) |
| `README.md` | No network claim anywhere (no "no network" or "private" text); What works today lists import of cards and folders only; the layout table (lines 248 to 251) lists no `Remote/`, and PhotoApp's new link to PhotoFixtures is not there | One line under What works today, a short privacy note, the layout row, and the "Not yet" list (publishing, other servers, Immich edits) |
| `CLAUDE.md` | No Network rule, no `remoteService` / `remoteLink` in the Catalog tables list, Layout has no PhotoCore `Remote/`; Layout describes PhotoFixtures as tests and benchmarks only (now also linked by PhotoApp for the debug script's fake server, C10); line 771 "no network code" is About's and stays true, but needs its scope said; the "Library launch guard" paragraph does not mention that a test launch uses an in-memory key store; the Info.plist (`NSAllowsLocalNetworking`, `NSLocalNetworkUsageDescription`) | A Network architecture rule (one component, read-only allowlist, key only in the Keychain, transport policy, nothing else uses `URLSession`: I checked, only `RemoteHTTPSession.swift` and the fake server do); the tables; Layout; Scope so far and Not yet |
| `docs/features/_inventory.md` | Not in status.md's list | An entry for this feature (the product manager owns it) |
| `THIRD_PARTY_NOTICES.md`, `Acknowledgements.all` | Immich is an API the app talks to, not code included or studied; design §12 leaves listing it to the product manager and the owner | A decision, not an edit by default |
| `docs/features/about-gus-dedication/design.md` R5 | "the app makes no network calls" | Leave the record; note its scope |

## Scripts

All run with a copy of `build/Gus.app` (identifier
`me.sesser.gus.debugtest.immichqa`, re-signed ad hoc), the executable run
directly with `--library-root` on a fresh copy of a scratch library each time
(`photobench generate --output src --jpeg 4 --dng 0 --heic 0`, then `photobench
import --library-root lib --source src`; note `generate` makes 100 DNGs and 100
HEICs unless told not), and the debug script's in-memory key store. `$S` is the
scratch folder; `fake` stands for the in-process fake server's address.

```
run() {  # run <name> "<script>"
  rm -rf lib-$1 dest-$1; mkdir dest-$1; cp -R lib lib-$1
  timeout 180 app/Gus.app/Contents/MacOS/Gus --library-root lib-$1 --debug-script "$2"
}
```

- **S1, browse and import**: `import open; wait 2; import server fake start 300; import server add Home fake; import server print; import grid; import server fake requests; quit` then, on 30 assets with four toggled: `…; import dest $S/dest; import toggle 0; import toggle 1; import toggle 2; import toggle 3; import run; import server print; import server fake requests; quit`. Showed: state photos, 250 loaded, `0 selected · 250 loaded · Not encrypted`, albums `Empty(0),Trip(7)`, the Edited tile (IMG_0002), the check once without the key (`/server/version`) and with it (`/api-keys/me`, `/users/me`), one POST search, thumbnails only for visible tiles; four files under `{capture:yyyy}/{capture:yyyy-MM-dd}`, four `remoteLink` rows (provider immich, address, remote id, the server's checksum), "Imported 4 photos", four marked; every request GET except the search; originals with `edited=false`.
- **S2, paging, album, dates**: `import open; wait 2; import server fake start 300; import server add Home fake; import scroll end; import server print; import snapshot $S/page.png; import album Trip; import server print; import dates 2026-10-30 2026-11-01; import server print; import dates clear; import album all; import server print; quit`. 250, then 300 after the scroll (the second POST only then); Trip 5 of `total 7`; range 3; the snapshot (looked at) shows the thumbnails, empty check boxes, the title bar "Home / All Photos" and "0 of 300 selected · Not encrypted" (the inspector is blank: the known glass-pane limit).
- **S3, the sheet**: `import server fake start 10; import server sheet add; import server sheet field name Home; import server sheet field address http://example.com; import server sheet field key abc; import server sheet print; …address http://134744072…; …https://example.com…; …address fake…; import server sheet submit; import server sheet confirm on; import server sheet submit; import server sheet field key SECRETWRONGKEY; import server sheet submit; import server sheet print; import server sheet close`, then `import server fake fault notimmich; import server add NI fake`, `import server keychain fail; import server add KC fake`, `import server fake fault permissions asset.read,asset.view; import server add Perm fake`, `… permissions all; import server add Full fake`, `import server add Bad http://127.0.0.1:9`. Refused (Add dimmed) for `example.com` and `134744072`, the notice and a dimmed Add for the fake until confirmed, `keyRejected` under the key, `notImmich`, `keychain`, `missingPermissions`, a pass with `all`, `unreachable`; sheet sizes 460×380, 460×470 (notice), 460×530 (notice and result), each equal to its ideal.
- **S4, Select All and marks**: `import server fake start 300; import server add Home fake; import dest $S/dest; import toggle 0; import toggle 1; import toggle 2; import run; import contextmenu 5 Select All; import server print; import scroll end; import server print; import contextmenu 5 Select All; import server print`. 247 selected of 250 loaded with 3 marked; 247 of 297 after the second page; 297 of 297 after Select All again.
- **S5, remove and add again**: `import server fake start 30; import server add Home fake; import dest $S/dest; import toggle 0; import toggle 1; import toggle 2; import run; import server remove Home; import server confirm no; import server remove Home; import server confirm yes; import server add Again fake; import server print; import grid`. No kept the server, Yes removed it; added again as "Again": `marked 3`, the grid first responder.
- **S6, failures**: `import server fake start 12; import server add Home fake; import dest $S/dest; import server fake fault external 1; import server fake fault truncate 1; import server fake fault delete 2; import server fake fault corrupt 3; import toggle 0 … import toggle 4; import template file {job}; import run; print activity`. Imported 2 (the external-library photo served short failed as incomplete, the deleted asset failed, the uploaded corrupted one failed on its checksum), alert "Imported 2 photos. 3 could not be imported.", Activity listing the three reasons in words, files named by their original names inside the destination.
- **S7, real TLS**: a Python mock Immich over HTTPS (below) on `127.0.0.1:18443` with a self-signed certificate (swapped for another after 28 s), then `import server sheet add; import server sheet field name Tls; import server sheet field address https://127.0.0.1:18443; import server sheet field key tls-key-ABCDEF; import server sheet submit; import server sheet trust; import server select Tls; import toggle 0; import toggle 1; import run; print activity; wait 22; import server select Tls; import server sheet edit; import server sheet field key tls-key-ABCDEF; import server sheet submit; import server sheet print`. The page showed `C9:11:8F:9B:…:FB:86`, the value `openssl x509 -fingerprint -sha256` gave for the certificate; Trust saved it (`pinned true`); 2 photos imported over TLS; after the swap `cantConnect(certificateChanged)` and the sheet's result `certificateChanged` "The server's certificate has changed". A third run with the same photos already in the library: "No photos were imported. 3 were already in the library." (Q4 for the window's text.)
- **S8, Stop and quit**: `import server fake start 12; import server add Home fake; import dest $S/dest; import server fake fault slow 700; import toggle 0 … import toggle 5; import start; wait 1.5; import terminate; import alert; import alert Keep Importing; wait 1; import stop; print activity` (alert "Quit While Importing? / The rest is not copied."; Keep Importing kept the import going; Stop: 5 photos, 5 links, no hidden file, "Stopped after 5 photos"), and with `fault slow 1500`, three toggled, `import start; wait 2; import terminate; import alert Stop and Quit`: the app exited, 2 photos cataloged and linked, no partial file, no process left.
- **S9, revoked key and dropped connection mid-import**: `…fault slow 700; import toggle 5 … import toggle 9; import start; wait 1.5; import server fake fault revoke; …; import alert; import server print` gave the alert "“Home” rejected the API key", "3 photos were imported before the import stopped. The key may have been deleted or expired. Choose Edit Server… to enter a new one.", the grid's `cantConnect(keyRejected)`; with `fault drop` instead: "“Home” stopped responding", 3 kept, Live Photo line in Activity.
- **S10, Keychain**: the debug launch reports the in-memory store (`import server keychain fail` works only on it); `security find-generic-password -s me.sesser.gus.debugtest.immichqa.servers` finds nothing after all runs (the copy never wrote to the Keychain); `RemoteKeyStores.forLaunch` read: no bundle, `--debug-script` or `--benchmark-scroll` means memory. With `import server keychain fail; import server remove Home; import server confirm yes; import alert`: "The server “Home” wasn't removed", the designed text, OK default (`\r`), the server still listed; with the store working it is removed.
- **S11, the standalone importer**: a copy of `build/Gus Importer.app` (own identifier), `--debug-script "wait 2; import print; import snapshot $S/imp.png; quit"`. No server, "No Card Connected", Choose Folder…; the plist has no `NSAppTransportSecurity` or local-network key.
- **S12, Remove from the sheet**: `import server fake start 5; import server add Home fake; import server sheet edit; import server sheet remove; import server confirm no; import server sheet edit; import server sheet remove; import server confirm yes; import server list`. "sheet closed asks Home" both times; the server stayed after No and went after Yes.

The mock for S7 (a scratch file, never committed; `cert{A,B}.pem` and `key{A,B}.pem` made with `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 -subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1`; run as `python3 -I mock.py <port> <certdir> A <folder of JPEGs> [swap-after-seconds]`):

```python
import sys, ssl, json, hashlib, base64, glob, os, threading
from http.server import BaseHTTPRequestHandler, HTTPServer
port, certdir, certname = int(sys.argv[1]), sys.argv[2], sys.argv[3]
KEY = "tls-key-ABCDEF"
SRC = sorted(glob.glob(sys.argv[4] + "/**/*.JPG", recursive=True) + glob.glob(sys.argv[4] + "/**/*.jpg", recursive=True))[:3]
assets = []
for i, p in enumerate(SRC):
    data = open(p, "rb").read()
    assets.append(dict(id=f"00000000-0000-0000-0000-00000000000{i+1}", name=os.path.basename(p), data=data,
                       checksum=base64.b64encode(hashlib.sha1(data).digest()).decode()))
class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        sys.stderr.write("REQ %s %s key=%s\n" % (self.command, self.path, "sent" if self.headers.get("x-api-key") else "-"))
    def send(self, obj, status=200, ctype="application/json", raw=None):
        body = raw if raw is not None else json.dumps(obj).encode()
        self.send_response(status); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def authed(self):
        if self.headers.get("x-api-key") != KEY:
            self.send({"message": "Invalid API key"}, 401); return False
        return True
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/server/version":
            return self.send({"major": 3, "minor": 4, "patch": 2, "prerelease": None, "featureLevel": 1})
        if not self.authed(): return
        if path == "/api/api-keys/me":
            return self.send({"id": "k", "name": "n", "createdAt": "2026-01-01T00:00:00.000Z", "updatedAt": "2026-01-01T00:00:00.000Z", "permissions": ["all"]})
        if path == "/api/users/me":
            return self.send({"id": "owner-1", "name": "O", "email": "o@example.invalid"})
        if path == "/api/albums":
            return self.send([])
        parts = path.strip("/").split("/")
        if len(parts) == 4 and parts[1] == "assets":
            a = next((a for a in assets if a["id"] == parts[2]), None)
            if a: return self.send(None, ctype="image/jpeg", raw=a["data"])
        self.send({"message": "nf"}, 404)
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); self.rfile.read(n)
        if not self.authed(): return
        items = [{"id": a["id"], "type": "IMAGE", "originalFileName": a["name"], "checksum": a["checksum"],
                  "fileCreatedAt": "2026-10-0%dT10:00:00.000Z" % (i+1), "fileModifiedAt": "2026-10-0%dT10:00:00.000Z" % (i+1),
                  "localDateTime": "2026-10-0%dT10:00:00.000Z" % (i+1), "ownerId": "owner-1", "isTrashed": False, "isEdited": False,
                  "isFavorite": False, "isArchived": False, "visibility": "timeline", "livePhotoVideoId": None, "libraryId": None,
                  "exifInfo": {"fileSizeInByte": len(a["data"]), "description": "", "rating": None}} for i, a in enumerate(assets)]
        self.send({"albums": {"total": 0, "count": 0, "items": [], "facets": []},
                   "assets": {"total": len(items), "count": len(items), "items": items, "facets": [], "nextPage": None, "nextCursor": None}})
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(os.path.join(certdir, f"cert{certname}.pem"), os.path.join(certdir, f"key{certname}.pem"))
if len(sys.argv) > 5:
    def swap():
        ctx.load_cert_chain(os.path.join(certdir, "certB.pem"), os.path.join(certdir, "keyB.pem"))
    threading.Timer(float(sys.argv[5]), swap).start()
srv = HTTPServer(("127.0.0.1", port), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
```

**What I could not cover.** ⌘A and other keys with a real key window (macOS would
not activate the copy; `print responder` showed `key nil`; I tried once and did not retry);
the sheet's look and the certificate page in the smallest window; Light, Dark and
Increase Contrast; a real Keychain prompt (the scripted launch never uses the
Keychain); the Local Network prompt; a real Immich server (versions, external
libraries, partners' photos, thumbnails at scale); a real cable pull; a hostile file
name through the script (the fake cannot name an asset; `RemoteSecurityTests.endToEnd`
does it through the fake server, and S6 used the `{job}` template); the "too old"
and "no size" cases by script (tests only); thumbnails' scroll smoothness; the
macOS 15 and 26 paths and VoiceOver (the owner does not run these; CI only).

## For a person

Build the bundle and run a copy of it on a scratch library. The copy has its own
bundle identifier, so its preferences and its Keychain service
(`me.sesser.gus.immichqa.servers`) are separate from the installed app's.
Every launch carries `--library-root`; never open the copy without it.

```
cd ~/Projects/Gus
Scripts/build-app.sh
mkdir -p ~/immich-qa
rm -rf ~/immich-qa/Gus.app ~/immich-qa/src ~/immich-qa/lib
cp -R build/Gus.app ~/immich-qa/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.immichqa ~/immich-qa/Gus.app/Contents/Info.plist
codesign --force --deep --sign - ~/immich-qa/Gus.app
swift run -c release photobench generate --output ~/immich-qa/src --jpeg 20 --dng 0 --heic 0
swift run -c release photobench import --library-root ~/immich-qa/lib --source ~/immich-qa/src
open -n ~/immich-qa/Gus.app --args --library-root ~/immich-qa/lib
```

Then File ▸ Import from Card or Folder…, Source pop-up ▸ Add Server…. Use a
**scratch API key** for your server with the five permissions (asset.read,
asset.view, asset.download, album.read, user.read) and delete it afterwards. The
first connect may show macOS's Keychain prompt (P7) and, for a LAN address, the
Local Network prompt (P13). The numbers P1 to P8 and P14 are the ones I ask before
sign-off: they are the designer's required M1 to M6 and M12 plus the two that
came out of this QA (the Keychain prompt, PRD P5; ⌘Q with the sheet up, P8). P9 to P13 are
optional. None asks for VoiceOver, macOS 15 or macOS 26.

Required:

1. **P1 (M1; PRD P6). Sheet size and the certificate page.** Add Server… with
   the import window at its smallest height (480 pt) and taller. Look for: the
   form scrolls between title and buttons and **Add** never leaves; typing
   `http://192.168.1.5` or getting a result grows the sheet without a jump; on
   the certificate page, first-time and changed, title, Back, Cancel and Trust
   Certificate are all visible, and whether it is obvious that the body scrolls
   (N-6). In Light, Dark and Increase Contrast.
2. **P2 (M2; PRD P1, AC4, B1, S1). Trusting a certificate, end to end.** Needs an
   `https://` Immich with a self-signed certificate (the Python mock in this
   file stands in if you have none: `python3 -I mock.py 18443 <certdir> A
   <folder of JPEGs>`, address `https://127.0.0.1:18443`, key `tls-key-ABCDEF`).
   Add: the certificate page; **Back** brings the key's dots back and Add is
   enabled; Return does nothing, Esc goes back; Trust Certificate checks and
   closes. Renew the certificate and choose the server: **Review Certificate…**
   opens "Trusted before / Now" and **Trust Certificate saves with nothing else
   edited**, with no prompt afterwards. Change a trusted server's address in
   Edit and Save: a first-time page appears, not the changed one. Does anything
   on the page nudge you to trust?
3. **P3 (M3; D4, S3). Remove Server… three ways.** From the sheet, the Source
   pop-up and File ▸ Remove Server…: the confirmation appears each time (from
   the sheet, after it closes); Return does nothing, Esc cancels, Remove removes.
   Then make the Keychain refuse (Keychain Access ▸ lock the keychain, or deny
   the prompt) and read the "wasn't removed" alert.
4. **P4 (M4; PRD P3 and P4, DQ-5). Alert keys and a real outage.** On the
   "wasn't removed" alert and each stop alert: do Return and Esc both dismiss? If
   Esc does not, the engineer adds `role: .cancel` to OK. Import a few hundred
   photos, pull the network cable (or switch Wi-Fi off) mid-import: the wording
   of "stopped responding", what is kept, the state the window lands in. Revoke the
   key on the server mid-import: "rejected the API key", same questions.
5. **P5 (M5; S4; AC7). Keyboard.** Full Keyboard Access on: Source pop-up to Add
   Server…, Tab through the sheet in order, Space on the notice's check box, Return
   with it unticked does nothing. After **Add** and after **Save**, with no click:
   ⌘A (takes only the loaded, unmarked photos), Space, arrows, End (next page),
   Return.
6. **P6 (M6; S6). Toolbar at 900 pt.** A long album name and a date range set:
   titles cut in the middle near 180 pt, Import and Stop still reachable, View ▸
   Date Range… still opens its popover from the overflow menu.
7. **P7 (PRD P5; C8). The Keychain prompt.** On the first Add, the wording and
   behavior of macOS's Keychain prompt, that the window is not frozen behind it
   (C8), that Always Allow or Deny gives sensible results, and that quitting and
   reopening the copy with `--library-root ~/immich-qa/lib` still finds the
   key (the server connects without asking for it).
8. **P8 (Q1). ⌘Q with the Server sheet open.** Add Server… and, with the sheet
   up, press ⌘Q. **Expect it to be ignored**, like every other sheet in the app
   (AppKit does not terminate while a window has a sheet attached; the engineer
   showed the same with the library window's Copy Adjustments sheet, and it is
   not a regression of this branch: follow-up #276). The app should quit once
   the sheet is closed (Cancel, then ⌘Q). If ⌘Q with the sheet up quits, or if it
   stays after the sheet is closed, say so. Also try ⌘Q with the certificate page
   up (same expectation). The script's `quit` was fixed (Q1) and exits with the
   sheet up.

14. **P14 (M12; review.md Fourth pass; new, DQ-13 and DQ-14). The Project name
    field and its note.** Needs a project named like the field: import one
    photo from the server first (File ▸ Import…, Source ▸ your server, check one
    photo, Import 1 Photo), then open the window again. With **Add to** set to
    **New Project**:
    - Short name ("Home - All Photos"): label **Project name** above, the field
      across the column, text starting at its left edge (not flush right), and
      **Adds to the existing project with this name.** under it in small grey
      type. Type "Trip": the line goes and the form below moves up, nothing else
      jumps; type the name again: it returns. Capital letters count ("home - all
      photos" has no line).
    - Long name, 60 characters, no match: the start shows at rest, it scrolls to
      the caret while typing, nothing cut at the inspector's trailing edge. A long
      name that matches (rename a project to it first, then type the same):
      the line shows.
    - Inspector at 300 pt (minimum), 320 and 400 (maximum): label, field and note
      stay on one left edge; the note is one or two lines (say which at 300 pt,
      N-8) and never cut with "…"; the field is no wider than the section's other
      rows.
    - **Add to** set to an existing project: field and note both go; back to
      **New Project**: both return.
    - Light, Dark and Increase Contrast: stronger field border, readable label,
      the note as legible as the captions under **Server** and **Preset**.
    - Mixed row shapes: **Add to** (label left, value right), the stacked
      **Project name**, **Job code** (label left, field right): does the section
      read tidily? "No" is a follow-up to stack Job code (the owner's to file),
      not a fault of this branch.
    - Behavior to confirm by eye: import All Photos twice; the sidebar shows one
      project and its count is the sum. (Scripted: S13.)

Optional:

9. **P9 (M7). Narrowest inspector.** Long server and project names,
   "Encrypted, certificate trusted by you": nothing clipped; `print
   inspectorwidth` says `fits`.
10. **P10 (M8; PRD P2). The grid.** An album of a few hundred photos: thumbnails
    arrive, no hitch, the scroll position holds as a page appends; an **Edited**
    and an **In Library** photo at the smallest tile size, both badges legible in
    Light and Dark.
11. **P11 (M9). Menus and empty state.** The dimmed Server, **Album** and **Date
    Range…** items in the library window's menus (does a dimmed **Album** read as
    the library's own albums? If so, **Server Album**); **Open Server** beside
    **Choose Folder…** looks like the other action buttons.
12. **P12 (M10). Wording of the Activity lines.** Read the external-library line
    (DQ-8) and, with a photo the server gives no size for, DQ-9; and the line
    after an import that found only duplicates ("No photos were imported. 3
    were already in the library.") beside the window's own "Imported 0 photos" (Q4).
13. **P13 (M11; PRD P7). The local network prompt** on first connecting to a
    `192.168.x.x` server, its wording, and the unreachable result's System
    Settings sentence.

## Follow-up

Reruns after fixes: none yet.
Owner's sign-off: not yet given.

## Follow-up 2 (2026-11-24): owner finding O1, DQ-13, DQ-14

Owner: qa-tester. Tested: `feature/immich-import` at b349266 (everything after
3e90686: f334d9d O1, 54760d1 DQ-13 and DQ-14, 96e1e60 C21 and N-9; the design
and code-review commits in between touch docs only), on the same Mac and
macOS 27.2.1 (26B131), Swift 6.4.2. The bundle was rebuilt at 08:17 today from
this commit (`Scripts/build-app.sh all`, 85 s, both bundles signed).

### Verdict

Passes. O1's rule (a server import adds to the oldest project whose name is
the cleaned Project name, else makes one), DQ-13's note and its announcement
rule, and the new pairing consequence (a RAW and a JPEG of one stem arriving in
two imports of one scope pair, in either order, by the library's own rule) are
each shown by a test and by a scripted run; the earlier criteria that the
change could touch re-ran unchanged. No finding for the engineer. What only a
person can see is the look of the stacked field and its note, now **P14**
(M12). Safety held: every launch carried `--library-root` on a scratch
library, the copy's bundle identifier was `me.sesser.gus.debugtest.immichqa2`
(the importer's `….immichqa2.importer`), no instance of mine is left running,
the owner's library folder has no file newer than my start and his
preferences have the same checksum as before; the copy never wrote to the
Keychain (`security find-generic-password` for its service finds nothing).

### Builds and tests

| Check | Result |
|---|---|
| `swift test` (full) | 1522 tests in 214 suites passed after 79.3 s (wall 1:23); 0 failures; neither known flake (#274, #229) failed |
| `swift test --filter RemoteProjectReuseTests` | 8 of 8 passed |
| `Scripts/build-app.sh all` | Passed; Gus.app records SDK 27.2, minos 15.0 |
| CI toolchain (Xcode 26.3) build | Not rerun; the engineer's and the code reviewer's passes are on `status.md` and `code-review.md` |

### Mapping

| New behavior | How | Evidence | Result |
|---|---|---|---|
| O1: a second import of one scope adds to the first project, none made | Test, Script | `RemoteProjectReuseTests.secondImportReuses` (two imports of All Photos: one project, both results name it, four images, two import runs in it); S13 below: `Home - All Photos=2` then `=3`, still one project | Pass |
| O1: a different name (an album's) makes its own project | Test, Script | `differentNameCreates`; S13: `import album Trip` prefills "Home - Trip", note hidden | Pass |
| O1: comparison is exact after the field's cleaning (case counts, extra spaces and NFD against NFC do not) | Test, Script | `comparison`; S13: "home - all photos" has no note | Pass |
| O1: the oldest of several twins; ties by id | Test | `severalWithTheName` | Pass |
| O1: a reused project keeps its source folder | Test | `keepsSourcePath` | Pass |
| O1: lookup and insert are one write (no race makes two) | Test | `concurrentLookups` (16 tasks, one project). Structural argument: one serialized GRDB write each; the code reviewer showed it fails 5 of 5 with the lookup moved out of the write | Pass |
| O1, C21: an empty field falls back on the address, and that name is reused | Test, Script | `emptyFieldImportsReuse` (two real imports through `RemoteImporter.run` with `"  "` then `""`); S14: one project named by the address with 2 photos | Pass |
| The new tests fail without the change | Script (scratch copy) | `git archive` of this commit in the scratchpad with `makeTarget` put back to `createProject` (cleaned name kept): `swift test --filter RemoteProjectReuseTests` failed 7 issues in 3 tests: `secondImportReuses` (projects were two, results named different projects, runs not in one project), `keepsSourcePath` (`projects.count == 1`), `emptyFieldImportsReuse` (names and ids). The other five test the new catalog functions directly. Checkout untouched | Pass |
| DQ-13 rule: shown only when the cleaned name equals a project's name and Add to is New Project | Test, Script | `reuseNote` (match, after cleaning, case, NFD, empty field as the address, no match, no projects, Add to set); S13 `import server print` shows `note shown|hidden`: hidden on open with no project, shown after the first import (project list changed), hidden for Trip, shown when "Home - All Photos" is typed, hidden for "home - all photos", shown again, hidden for the empty field when no project has the address as name; S14: shown for the empty field once the address-named project exists | Pass |
| DQ-13: Add to set to a project hides the field and the note | Test, Person | `reuseNote` (the Add to case). Not scriptable (`existingProjectID` is internal to PhotoUI): P14 | Pass (rule); look P14 |
| DQ-13 announcement: once, only when the note appears because the name changed | Code, Script | Read `setServerProjectName` and `chooseAlbum`'s prefill in `ServerSource.swift`. The debug script has no VoiceOver output beyond `AccessibilityText.lastAnnouncement` and I did not add a command; the engineer's scripted run in `status.md` (typing shows "Adds to the existing project with this name.") was not repeated. VoiceOver is the owner's standing exclusion | Pass (code); VoiceOver not checked |
| DQ-13 string and catalog entry | Test | `LocalizationTests`, `BrandingTests` (full run) | Pass |
| DQ-14 stacked, leading-aligned field | Person | The inspector is a glass pane: `snapshot` leaves it blank (confirmed: the import window's inspector is blank in my snapshot) and the import window has no `print inspectorwidth`. P14 | Open (P14) |
| An import that brings nothing touches no project | Test, Script | `RemoteImportTests.duplicates`; S16: a second server with the same 3 photos: "No photos were imported. 3 were already in the library.", the catalog's projects are `src` and `Home - All Photos` only (no "Second - All Photos") and no extra `importRun` | Pass |
| Card and folder imports unchanged (`createProject`) | Code, Test | `CopyImporter.swift:225` and `Importer.swift:256` still call `createProject` (read); the card and folder import suites in the full run pass | Pass |
| User guide's claims for the rule | Code | The server paragraph (`docs/USER_GUIDE.md` lines 93 to 108) read against S13, S14 and the code: exact name after cleaning (S13), extra spaces do not count (`comparison`), each album keeps its own project (S13), the line quoted character for character, the oldest twin keeps the folder (`severalWithTheName`, `keepsSourcePath`), Add to hides the field and the line (code), card and folder import unchanged (code). True | Pass |

### Scripted case the code review asked for: RAW and JPEG in two imports

A plain-HTTP mock Immich (script below, a scratch file) serves four assets:
`PAIRA.JPG`, `PAIRA.DNG`, `PAIRB.JPG`, `PAIRB.DNG` (a photobench JPEG and DNG
each), with the server's rating and description different between the two files
of a stem. Two scratch libraries, the folder template a literal `pair`, so each
stem's two files land in one folder; `sidecars on` so the app writes sidecars.
The scripted launch's key store is in memory, so each later launch removes and
adds the server again (the links stay: AC11). Results, read from the catalog
with `sqlite3 -readonly` and from the files on disk:

| Order | What the person had set before the second import | Result after the second import | Matches the library's rule |
|---|---|---|---|
| RAW, then JPEG (`lib-pair`) | A: RAW rating 2, flag picked, label red (`photocli`). B: RAW kept the server's 3 | Both stems pair (`imagePair`: RAW = raw, JPEG = companion), one project, three import runs in it. A: the JPEG took 2, picked, red; B: JPEG's server rating 5 not applied, both 3. Both JPEGs' captions became the RAW's ("RAW A", "RAW B"), the server's "JPEG A", "JPEG B" not applied | Pass: RAW's values win; the server's rating and description only fill empties |
| JPEG, then RAW (`lib-pair2`) | A: JPEG rating 1, flag picked, label green (`photocli`). B: JPEG kept the server's 5 | Both stems pair. A: the new RAW (unrated) took 1, picked, green; B: both 5 (the RAW's server 3 not applied). Both RAWs' captions became the JPEG's | Pass: `mergeDefaultVersions` takes the RAW's value unless it is unset; the server's values fill only where the pair is empty |
| Sidecars, both orders | `sidecars on`, a wait after each import | One `PAIRA.xmp` and one `PAIRB.xmp` in the folder, nothing named after the JPEG or the DNG; `sidecarQueue` empty after; their rating, flag, label and description are those of the pair (A in the first order: rating 2, flag 1, label Red, "RAW A"; in the second: rating 1, flag 1, label Green, "JPEG A") | Pass: no sidecar for the wrong file |

The pair forming is the consequence of reuse that the code review called out
(before O1 the two files sat in two projects and never paired); it follows the
library's rule, the same as a card import set to Add to. Not scripted: a pair
in which the person has edited the description and then the second file arrives
(`pairCaptionsKept` covers it); a sidecar another app changed
(`SidecarSync`'s own tests).

### Re-verified earlier criteria (new bundle, scratch library each time)

| Earlier item | Re-run | Result |
|---|---|---|
| AC6, AC8 (S1, S2): listing, paging, album and date scopes, the project name | S1: 30 loaded, the Edited badge on IMG_0002, one POST search, thumbnails; 4 imported, marked 4, "Imported 4 photos", project "Home - All Photos". S2: 300 loaded after the scroll, Trip 5 of `total 7`, the range 3, snapshot looked at (thumbnails, empty check boxes, title bar "Home / All Photos", "0 of 300 selected · Not encrypted") | Pass |
| AC7 (S4): marks and Select All | 247 of 250 loaded with 3 marked; 247 of 297 after the second page; 297 of 297 after Select All again; the note shows (the project now exists) | Pass |
| AC3, AC2 (S3): the sheet | `example.com` and `134744072` refused, Add dimmed; the fake's `http://127.0.0.1` shows the notice, Add dimmed until confirmed; sizes 460×380, 460×470, 460×530, each equal to its ideal; `keyRejected`, `notImmich`, `missingPermissions` (pass with `all`), `unreachable` | Pass |
| AC2 (S10): the Keychain | `keychain fail`: Add gives `keychain`; Remove Server: the "wasn't removed" alert with the designed text and the server still listed | Pass |
| AC11 (S5): remove and add again | No kept the server, Yes removed it; added again as "Again": `marked 3`, the grid first responder; its project name default is "Again - All Photos" (the connection's name) | Pass |
| AC9, AC14 (S6): failures and Activity | "Imported 2 photos. 3 could not be imported."; Activity lists the three reasons in words (incomplete, deleted on the server, checksum mismatch) | Pass |
| AC13 (S8): Stop and quit | Quit While Importing? alert, Keep Importing kept it running, Stop: "Import stopped after 5 photos." and the Live Photo line | Pass |
| S12: Remove from the sheet | "sheet closed asks Home" both times; No kept, Yes removed | Pass |
| Q1 (scripted `quit` with the Server sheet up) | `import open; wait 2; import server sheet add; quit` exits | Pass |
| AC16 (S11): the standalone importer | Copy of `Gus Importer.app` with its own identifier: window "No Card Connected", Choose Folder…, no server item (snapshot looked at); `Info.plist` has no `NSAppTransportSecurity`, local-network or Bonjour key; the Server UI and the note are not in it (`addsToExistingProject` is nil there, and `importerHasNoServers` passes in the full run) | Pass |

Not re-run, because the change cannot touch it: the real-TLS run (S7), the
slow-link and revoked-key runs (S9), AC1's key leak checks (nothing here reads
or writes a key; `keyOnlyInTheStore` passes in the full run; the key texts
`pair-key-ABCDEF` and `fake-key-0123456789` do not occur in the scratch
catalogs I read), AC4, AC5, AC10, AC12 beyond the pair cases above, AC15
(no migration in this range: the diff touches no `Migrations` file).

One thing a script needs to know: the copy's preferences persist per bundle
identifier, so the folder template I set in the pair run (`pair`) stayed for
later runs under the same identifier (S1's four files went to `…/pair/`). The
templates were reset by nothing; not a product issue.

### Findings

None for the engineer. Two observations, neither a finding:

- A renamed connection starts a new project name: the Project name default is
  "‹connection name› - ‹scope›", so renaming "Home" to "Home Server" in Edit
  Server… and importing All Photos again makes "Home Server - All Photos", not
  an addition to "Home - All Photos". It follows the owner's ruling (the field's
  text decides), and the guide says the field starts from the server's name; the
  guide does not say outright that renaming the server changes the default. A
  sentence is optional (Ship).
- The note lags only when a project is made by another path between opening the
  window and pressing Import (`library.projects` is a snapshot; the code review
  recorded it). The import is right either way.

### Docs for Ship (project reuse)

`docs/USER_GUIDE.md` is in step (read above). `docs/features/immich-import/design.md`
§5.3 was corrected by the designer and says the same as the guide and the code.
Still for the product manager, in addition to the list under "Docs the feature
must change" above:

- `README.md`: the line under What works today for the Immich import should say
  that importing the same album or All Photos again goes into the project of that
  name (no second project), and that card and folder imports are unchanged.
- `CLAUDE.md` "Scope so far": the Immich entry should carry the rule (a server
  import adds to the oldest project whose name is exactly the cleaned Project
  name, else makes one; a reused project keeps its folder; the note under the
  field; `Catalog.projectForImport`, `RemoteProjectName` in
  `Remote/RemoteBrowseRules.swift`), and the consequence that a RAW and a JPEG of
  one stem imported in two runs of one scope now pair. Also the `Remote` rule's
  statement that a server import "makes one project" if the entry says so
  (grep "project" in the entry when written).
- `docs/features/_inventory.md`: the entry should name project reuse.
- Optional: one sentence in the guide that renaming the server changes the
  default Project name (above).

### Scripts (Follow-up 2)

Run with a copy of `build/Gus.app` (identifier
`me.sesser.gus.debugtest.immichqa2`, re-signed ad hoc) on fresh copies of a
photobench scratch library (`photobench generate --jpeg 4 --dng 0 --heic 0`,
then `photobench import`), `--library-root` on every launch; `$Q` is the scratch
folder. The first helper is `run <name> "<script>"` from the Scripts section
above, with `lib-<name>`.

- **S13, reuse and the note**: `import open; wait 2; import server fake start 5; import server add Home fake; import server print; import dest $Q/dest-s13; import toggle 0; import toggle 1; import run; import server print; print projects; import toggle 2; import run; import server print; print projects; import album Trip; import server print; import album all; import server print; import server project Home - All Photos; import server print; import server project home - all photos; import server print; import server project Home - All Photos; import server print; import server project   ; import server print; quit`. Showed `project 'Home - All Photos' note hidden` on open, `note shown` after 2 imported (`Home - All Photos=2`), `Home - All Photos=3` after a third with still one project of that name, `Home - Trip` hidden, `Home - All Photos` shown after `album all`, shown when typed, hidden for the lower-case name, shown again, and the empty field hidden.
- **S14, the empty field**: `import open; wait 2; import server fake start 5; import server add Home fake; import dest $Q/dest-s14; import server project; import server print; import toggle 0; import run; import server print; print projects; import toggle 1; import run; print projects; import server project Home - Trip; import server print; import toggle 2; import run; print projects; quit`. One project named `http://127.0.0.1:<port>` with 1 then 2 photos, the note shown for the empty field after the first import, then "Home - Trip=1" as its own project.
- **S16, nothing imported, no project**: `import open; wait 2; import server fake start 5; import server add Home fake; import dest $Q/dest-s16; import toggle 0; import toggle 1; import toggle 2; import run; print projects; import server fake start 5; import server add Second fake; import toggle 0; import toggle 1; import toggle 2; import run; print projects; print activity; quit`, then `select id,name from project; select id,projectId from importRun`.
- **S15, RAW and JPEG in two imports** (the pair table above): the mock, started with `python3 -I pairmock.py 18081 $Q/pairsrc` (`photobench generate --output $Q/pairsrc --jpeg 2 --dng 2 --heic 0`). Launch 1: `sidecars on; import open; wait 2; import server add Pair http://127.0.0.1:18081 pair-key-ABCDEF; import dest $Q/dest-pair; import template folder pair; import toggle 3; import toggle 1; import run; import server print; wait 4; print projects; print activity; quit` (indices 1 and 3 are the two DNGs; for the other order, 0 and 2, the JPEGs). Then `swift run photocli rate --version 6 --rating 2 --library-root $Q/lib-pair`, `… flag --version 6 --flag picked …`, `… label --version 6 --label red …` (version 6 is PAIRA's first file; the app must not have the library open). Launch 2: `sidecars on; import open; wait 2; import server remove Pair; import server confirm yes; import server add Pair http://127.0.0.1:18081 pair-key-ABCDEF; import dest $Q/dest-pair; import template folder pair; import toggle 2; import toggle 0; import run; import server print; wait 4; print projects; print activity; quit` (the other files of each stem). Read with `sqlite3 -readonly $Q/lib-pair/Library/catalog.sqlite "select … from image join version …; select * from imagePair; select count(*) from sidecarQueue"` and the `.xmp` files.
- **S1 to S6, S8, S10 to S12 and Q1** re-run as listed above with the scripts of the first run, the destination folder `$Q/dest-<name>`; a helper `rerun.zsh` in the scratchpad (not committed) holds them.

The mock for S15 (scratch, never committed; plain HTTP on 127.0.0.1; it is the S7 mock with the TLS removed, four fixed assets, and a rating and description per asset):

```python
import sys, json, hashlib, base64, os
from http.server import BaseHTTPRequestHandler, HTTPServer
port, src = int(sys.argv[1]), sys.argv[2]
KEY = "pair-key-ABCDEF"
SPEC = [  # (file name, source file in <src>/Shoot-001, capture time, rating, description)
    ("PAIRB.JPG", "IMG_00002.JPG", "2026-10-06T10:00:00.000Z", 5, "JPEG B"),
    ("PAIRB.DNG", "RAW_00004.DNG", "2026-10-05T10:00:00.000Z", 3, "RAW B"),
    ("PAIRA.JPG", "IMG_00001.JPG", "2026-10-04T10:00:00.000Z", 5, "JPEG A"),
    ("PAIRA.DNG", "RAW_00003.DNG", "2026-10-03T10:00:00.000Z", 3, "RAW A"),
]
# handlers as in S7's mock: /api/server/version, /api/api-keys/me, /api/users/me,
# /api/albums (empty), GET /api/assets/<id>/original|thumbnail, POST search returning all four
```

(The full file is in the session's scratchpad; the S7 mock above shows the
handlers, which differ only in the list of assets and in `exifInfo.description`
and `exifInfo.rating` per asset.)

### Follow-up

Findings: none. Owner's sign-off for this range: not yet given. P1 to P14 are
open (P14 is new); P8 is corrected to expect the app to ignore ⌘Q with a sheet
up.
