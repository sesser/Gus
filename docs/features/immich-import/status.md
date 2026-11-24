Issue: #271 · Complexity: hard

# Import from Immich: status

Owner: swift-macos-engineer. Branch `feature/immich-import` (off `develop`).
Spec: the PRD (issue #271, rev3: R1 to R25, AC1 to AC17, rulings RI-2 and
RI-6) and [design.md](design.md) (DQ-1 to DQ-4 ruled, §14.3).

**State: In progress.** Every requirement (R1 to R25, R10b and R15b
included) is built, and every acceptance criterion has a Swift Testing test,
a debug-script check, or a person's check named below. Not Done yet: three
Requirements issues need a ruling first (RI-E1 partners' photos, RI-E2
external-library checksums, RI-E3 AC16's "links no connection code"), and two
design questions (DQ-5, DQ-6) have a stopgap built. See the end of this file.

## API verification (first task, 2026-11-23)

Read from the OpenAPI spec of the tags `v3.2.0` (the minimum, Q1) and
`v3.4.2` (the latest release), and from the server's source at `v3.4.2`
(`server/src/services/search.service.ts`, `utils/database.ts`,
`services/asset-media.service.ts`, `dtos/auth.dto.ts`, `services/api-key.service.ts`,
`enum.ts`, `services/library.service.ts`). Every endpoint and field below is
the same in both tags. Not checked against the owner's server.

| Item (PRD "Not verified") | Finding | What the code does |
|---|---|---|
| `filter.albumIds` | `IdsFilter`: `{ "any": [uuid], "all": [uuid], "none": [uuid] }` | `{"albumIds": {"any": [id]}}` |
| `filter.type` | `EnumFilterAssetType`: `{ "eq" \| "ne": "IMAGE"… , "in" \| "notIn": [...] }` | `{"type": {"eq": "IMAGE"}}` |
| `filter.visibility` | `EnumFilterAssetVisibility`, values `archive`, `timeline`, `hidden`, `locked` | `{"visibility": {"eq": "timeline"}}` (archive, hidden and locked left out, Q4) |
| Trashed assets | **The v3 search does not leave trashed assets out by default** (`searchAssetBuilder` has no `deletedAt` default; only the deprecated flat shape had `withDeleted`) | `{"trashedAt": {"eq": null}}` in the filter, and every listed asset with `isTrashed`, another type or another visibility is dropped on our side too |
| Date range (R10b) | `filter.takenAt`: `DateFilter` (`gte`, `lte`, …) | `gte` start of the first day, `lt` start of the day after the last |
| Order | `orderBy: {field: fileCreatedAt \| localDateTime \| …, direction: asc \| desc}`, default `fileCreatedAt desc` | `{"field": "fileCreatedAt", "direction": "desc"}` (newest capture first, R9) |
| Paging | `size` 1 to 1000 (default 250); `cursor` is an encoded offset (`offset + size`); `nextCursor` null on the last page | 250 per page (`ImmichAPI.pageSize`) |
| `count` / `total` | `count` is the page's length; **`total` is also the page's length** (`mapResponse`: `total: assets.length`), deprecated since v3.0.0 | No exact total exists for All Photos, so All Photos never shows a count (R10, as the PRD allows) |
| Album count | `GET /albums` items carry `assetCount` (every asset, videos included) | Shown as the server's number (R10, RI-5) |
| Albums listed | `GET /albums?isOwned=true` gives the account's own albums (`isOwned` exists since before v3.2.0) | Own albums only; shared-with-me albums are a non-goal |
| **Partners' photos** | **The search universe is the account's own assets plus every partner whose timeline the account shows** (`getUserIdsToSearch`). Album-confined searches list every asset in the album, whoever owns it | See **Requirements issues**, RI-E1. Built: assets whose `ownerId` is not the account's are dropped when the account's id is known (see RI-E1) |
| `/server/version`, `/server/ping` | No security scheme: no key needed | The check reads `/server/version` without the key first (not Immich, too old), then `/api-keys/me` with it |
| `/api-keys/me` | Any valid key (`permission: false`); returns `id`, `name`, `createdAt`, `updatedAt`, `permissions` (a list; `all` for a full key); 403 "Not authenticated with an API Key" for a session | Missing permissions are read from this list (R2, R3); `all` covers the four. The read-per-permission fallback of design §3.4 is not needed on 3.2.0 or later |
| `edited` on `/assets/{id}/original` | Defaults to `false` (`isEditedOnly(auth, edited = false)`, true only for a shared link) | `edited=false` is sent explicitly on `/original` and `/thumbnail` (R21) |
| Byte ranges on `/original` | Served by Express `res.sendFile`, which honours `Range` | Not used: no resume (non-goal) |
| Rate limits | No throttling in the server (no throttler module or rate setting at v3.4.2); a reverse proxy in front may have one | Retries: see **Retries and timeouts** |
| RAW+JPEG pairs | Each uploaded file is its own asset; stacks group assets only when someone stacked them. The search lists stacked assets unless `withStacked: false` | `withStacked` is not sent, so both files of a pair are listed as two tiles (design §4.5); pairing happens after landing (R14) |
| Live Photos | The still is an `IMAGE` with `livePhotoVideoId`; the motion part is a `VIDEO` asset with visibility `hidden` | Never listed (type and visibility filters); a still with `livePhotoVideoId` counts toward "Live Photo videos were not downloaded" when imported |
| `checksum` | Base64 of 20 bytes. **For assets of an external library the checksum can be the SHA-1 of `"path:" + originalPath`, not of the file** (`ChecksumAlgorithm.sha1Path`, still written by `library.service.ts` at v3.4.2; the response does not say which) | See **Requirements issues**, RI-E2. Built as R13 says: a mismatch is a failure |
| `image.caption` | Is the library's Description (`DescriptiveField.caption` shown as Description, `FieldLabel`) | Immich `exifInfo.description` goes to `image.caption` (R17) |
| `exifInfo.rating` | 1 to 5 or null | Rating 1 to 5; null is 0 (R17) |
| `exifInfo.fileSizeInByte` | Nullable | The byte count checked is `fileSizeInByte`, else the response's `Content-Length`, else none (SHA-1 only) |
| Auth header | `x-api-key` (security scheme `api_key`) | Sent only to the connection's host; redirects are never followed (R7) |

**App Transport Security (Info.plist).** Apple's documentation for
`NSAllowsLocalNetworking`: on macOS 14 and later ATS no longer allows plain
http to IP addresses by default; the key "enable[s] access to unqualified
domains, .local domains, and IP addresses that they would otherwise restrict".
So `NSAppTransportSecurity` ▸ `NSAllowsLocalNetworking = YES` is the narrowest
setting that lets `http://192.168.1.5`, `http://nas.local` and `http://nas`
load; `NSAllowsArbitraryLoads` is not set. The key also lets an IP literal
outside the local ranges through ATS, so the code's transport policy
(`TransportPolicy`, R5) is the guard that refuses `http://8.8.8.8`.
`NSLocalNetworkUsageDescription` carries design §10's sentence. The app has
only English, so the sentence is in the Info.plist template itself (an
`InfoPlist.strings` would be needed for other languages; the String Catalog
compiler writes `Localizable.strings` only).

**Sandbox.** `Scripts/build-app.sh` signs ad hoc with no entitlements: the app
is not sandboxed, so no network-client or local-network entitlement is needed.
macOS's Local Network privacy prompt applies to unsandboxed apps too (P7).

## Sidecars: how the import writes description and rating (RI-6)

`insertMasters` inserts the image and its default version with the file's own
values and records them as the sidecar baseline (`metadataSync`); the sidecar
triggers fire on `UPDATE` only. The Immich values are then written by an
`UPDATE` of `image.caption` and of the default version's `rating`, in the same
transaction as the link, and only where the library's value is empty (caption
null or blank; rating 0). So a description or rating that came from Immich
differs from the baseline, the existing triggers (`sidecar_description`,
`sidecar_culling`) queue the photo's sidecar, and `SidecarSync` writes it under
its existing rules (only when sidecars are on; never over a sidecar another app
changed). A download has no sidecar beside it, so the first write creates one.
Nothing about the triggers changed.

## Retries and timeouts (R20)

- Each request: 30 s without a byte (`timeoutIntervalForRequest`); the
  connection check as a whole is bounded by 20 s per request and stops on
  Cancel.
- A request that fails for a transport reason (timeout, connection lost,
  cannot connect, DNS) or answers 502, 503 or 504 is tried again up to **3
  times**, after 1 s, 2 s and 4 s (so about 7 s plus the timeouts). Then the job
  stops ("stopped responding").
- 401 stops the job at once (key rejected); 403 stops it with the permission
  the request needs. 404 on one asset is a counted failure and the job goes on.
  Other statuses on one asset are a counted failure with the number.
- Thumbnails: at most 6 at once, no retry (a failed one leaves the
  placeholder).

## Build and test

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline (branch at ba1ff03, before any change) | `swift build --build-tests` passes | 1453 tests in 206 suites pass |
| Core step (515ae7a) | passes, no new warnings | 1475 tests in 209 suites pass |
| UI step (536845f) | passes, no new warnings (the two in `SmartAlbumTests` and `VirtualCopiesTests` are older) | 1483 tests in 210 suites pass |
| Latest (2026-11-23, end of session) | `swift build --build-tests` passes, no new warnings | 1489 tests in 211 suites pass; 9 of 10 full runs this session passed, one failed with output lost to a pipe (not identified; see **Determinism**) |
| Bundle | `Scripts/build-app.sh` passes | |
| CI toolchain | passes (see **CI toolchain**) | |

No `PreviewCacheKey.currentPipelineVersion` bump, no golden touched, no
rendering changed. One migration, **v16** (`remoteService`, `remoteLink`); no
existing migration edited. No new package dependency: `URLSession`, the
Security framework, `Network` (the test fake only) and CryptoKit.

## What was built

**PhotoCore `Remote/`** (no AppKit or SwiftUI):
- `ServerAddress.swift`: normalization (design §3.2, R16's key), `LocalNetwork`
  (RFC 1918, loopback, link-local, IPv6 ULA and link-local, IPv4-mapped,
  `localhost`, `.local`, single-label names) and `TransportPolicy` (R5).
- `RemoteKeyStore.swift`: the `RemoteKeyStore` protocol, `KeychainKeyStore`
  (generic password items, service `<running bundle id>.servers`, account =
  the connection's `uuid`, file-based keychain) and `InMemoryKeyStore` (tests
  and every `--debug-script` launch; `failing` simulates a Keychain refusal).
- `RemoteTrust.swift`: `CertificateFingerprint` (SHA-256 of the DER; display,
  colon and spoken forms), `CertificateSummary`, `TrustDecision.decide` (pin
  wins; no pin: the system's SSL policy for the host; no bypass).
- `ImmichAPI.swift`: `ImmichEndpoint` (the seven requests),
  `RemoteRequestAllowlist`, `ImmichVersion` (minimum 3.2.0), the DTOs, the
  search body, and the asset filter (images, timeline, not trashed, the
  account's own when known, a format the library catalogs).
- `RemoteHTTPSession.swift`: the one HTTP path (R7, R23): an ephemeral session
  with no cookies, cache or credential storage; every request checked against
  the allowlist before it is built; the key only as `x-api-key` and only to
  the connection's host; redirects never followed; the certificate decided in
  the TLS challenge (so "Nothing was sent" in design §3.4 holds: the request is
  written only after the handshake accepts); downloads streamed to a file with
  a running SHA-1.
- `ImmichClient.swift`: `RemotePhotoSource` (the protocol the window and the
  importer use) and `ImmichClient`: the check (version without the key, then
  `/api-keys/me`, then the owner id: see RI-E1), albums, pages, thumbnails,
  downloads. `ConnectionCheckResult` has the seven named failures plus the
  untrusted-certificate page.
- `RemoteImporter.swift`: download to `.download-<uuid>.<ext>` in the
  destination, size and SHA-1 checks, read back around the file cache (SHA-1
  again and SHA-256), the catalog's duplicate rule, the template name after the
  file's own metadata is read, move into place, catalog and link in one
  transaction; retries and the stop causes (R20); `RemoteRetryPolicy`; the
  project is made when the first photo verifies, so an import that brings
  nothing leaves no empty project.
- `RemoteAsset.swift`: `RemoteAsset` (provider-neutral), the grid's
  `remote-asset:` URLs, `RemoteScope`, `CaptureDateRange`, `RemoteAlbum`,
  `RemotePage`.
- `RemoteBrowseRules.swift`: `ServerGridState`, `RemotePaging`,
  `ServerSubtitle`, `ServerFormRules`, `RemoteProjectName`,
  `RemoteImportReport` (the Activity lines and the alert rule).

**PhotoCore `Catalog/`**: `CatalogSchema` v16; `RemoteServices.swift`
(`RemoteServiceRecord`, `RemoteLinkRecord`, `RemoteProvider`, connection CRUD,
`linkedRemoteIDs`, `insertRemoteMaster`, `linkRemoteDuplicate`);
`Catalog.insertMasters` split so the remote importer adds a master and its
link in one transaction (behaviour unchanged for every other caller).
`CopyImportProgress.waitingForServer`; `CopyImportResult` gained a public init.

**PhotoFixtures `FakeImmichServer.swift`**: an Immich in the test process on
127.0.0.1 (Network framework), filtering the search as the real server does,
recording requests, and faults (drop, revoke, not Immich, delete, corrupt,
truncate, unavailable n times, slow, redirect).

**PhotoUI `Import/`**: `CardImportModel` (servers, `browse`, `hasSource`,
`sourceName`; a server source takes the place of `source`), `ServerSource.swift`
(`ServerBrowse`: check, albums, pages, linked marks; the model's server
actions; `RemoteThumbnails`, six at once, memory only), `ServerSheet.swift`
(`ServerSheetModel` and the two pages), `ServerText.swift` (every sentence of
design §3.4, §4, §6), `ImportWindow` (Source pop-up rows and items, Album
pop-up, Date Range popover, grid states, Server section, plain project name,
no After Import, the removal confirmation, the import alert), `ImportGrid`
(appending pages with `insertItems`, paging on scroll), `ImportCell` (Edited
badge, server tooltips, remote thumbnails), `ImportCommands` (File ▸ Add /
Edit / Remove Server…, View ▸ Album ▸, Date Range…; Show Videos and Show
Photos Already in Library dimmed for a server), debug commands `scroll`,
`stop`, and `rescan` following a server.

**PhotoApp**: `LibraryModel.remoteKeyStore`; the Activity job named by
`sourceName`; `DebugServerCommands.swift` (design §11). `Package.swift`:
PhotoApp links PhotoFixtures for the fake server (only a scripted launch
starts it).

**Support/Info.plist** (library app only): `NSAppTransportSecurity` ▸
`NSAllowsLocalNetworking`, `NSLocalNetworkUsageDescription`.

**String Catalog**: 120 entries added by hand (design §10's list, plus
"Version", "Connection", "%lld photos loaded").

**docs/USER_GUIDE.md**: the import paragraph, a new "Importing from an Immich
server" section, and the About line ("the About window contacts nothing").

## Requirements

| R | State | Where / how checked |
|---|---|---|
| R1 key in the Keychain only | Done | `KeychainKeyStore`; AC1 tests; scripted runs' output grepped for the key: 0 hits |
| R2 the check, seven results | Done | `ImmichClient.check`, `ServerText.result`; AC2 |
| R3 four permissions, more accepted | Done | `ImmichClient.missing`; AC2 |
| R4 edit, remove (asks; key deleted) | Done | `ServerSheetModel`, `removeServer`; scripted |
| R5 transport policy | Done | `TransportPolicy`, enforced in `RemoteHTTPSession.init`; AC3 |
| R6 pinning, no off switch | Done | `TrustDecision`, `SessionDelegate`; AC4 (logic); P1 (a real TLS server) |
| R7 host only, no redirects, no cookies or cache, allowlist | Done | AC5 |
| R8 documented claims | Partly | USER_GUIDE done; README, `CLAUDE.md`, roadmap principle 3 are the product manager's at Ship (see **README**) |
| R9 own images, newest first, pages, thumbnails | Done | AC6; scripted (250 then 300) |
| R10 album pop-up and counts | Done | AC6; scripted |
| R10b date range (Should) | Done | `CaptureDateRange`; AC6's range case; scripted |
| R11 nothing checked; Select All loaded unmarked | Done | AC7 (scripted); `selectAll` unchanged |
| R12 originals, template, project name | Done | AC8 |
| R13 size, SHA-1, SHA-256 dedupe | Done | AC8, AC9 (see RI-E2) |
| R14 ordinary masters, pairs, Live Photos | Done | AC10 |
| R15 links; R15b duplicate linked | Done | AC9, AC11 |
| R16 address-keyed links, cascade | Done | AC11 |
| R17 description and rating | Done | AC12 |
| R18 Stop and quit | Done | AC13 (test and scripted) |
| R19 Activity job and report | Done | `RemoteImportReport` test; scripted |
| R20 retries and failures | Done | AC14 |
| R21 original, Edited mark | Done | AC5, AC12 (`edited=false`); scripted (Edited badge) |
| R22 generic tables | Done | AC15; `CatalogTests.schemaNamesDoNotEmbedTheProductName` |
| R23 one component behind a protocol | Done | `RemotePhotoSource`, `RemoteKeyStore` |
| R24 not in the importer | Done, see RI-E3 | AC16 |
| R25 debug-script commands | Done | below |

## Acceptance criteria

| AC | State | Test or check |
|---|---|---|
| AC1 | Done | `RemoteBoundaryTests.keyOnlyInTheStore` (every value of every catalog table), `keyUsesInSources` (the key is read only for the header; no log or print interpolates a key); scripted runs: stdout, the scratch catalog, the test copy's preferences grepped, 0 hits |
| AC2 | Done | `RemoteCheckTests.sevenResults` (unreachable, not Immich, key rejected, too old with both versions, each missing permission, a pass with extra and with `all`); certificate changed in `certificates`; Keychain refusal `keyStore` and the sheet's `.keychain` path |
| AC3 | Done | `RemoteConnectionTests.transportPolicy` and `RemoteBrowseRulesTests.form` |
| AC4 | Done for the decision; a real TLS server is P1 | `RemoteCheckTests.certificates` (two self-signed certificates made with openssl), `noTrustBypass` |
| AC5 | Done | `RemoteCheckTests.allowlist` (recorder: only allowlisted, no PUT/PATCH/DELETE, one POST, `edited=false`; seven off-list requests refused before sending), `redirectNotFollowed` |
| AC6 | Done | `RemoteImportTests.listing` (one search for the first screen; trashed, hidden, locked, archived, video, partner, GIF absent; order; the body), `albums` (album filter, server count, date range); scripted: 250 loaded, `scroll end`, 300 |
| AC7 | Done (scripted) | `import server print` after opening: selected 0; marked photos are `AXImage` "Already in the library" and Select All leaves them (scripted re-add: 3 marked, 0 selected); `links` test: a second import of linked assets downloads nothing |
| AC8 | Done | `importsThree` (template names, byte-equal, edited project name), `corrupt` (checksum and short file: no file, no row) |
| AC9 | Done | `duplicates` |
| AC10 | Done | `pairsAndLivePhotos`; `photocli render` and `photocli export` of imported photos on the scripted library worked |
| AC11 | Done | `links`, `copiesHaveNoLink` |
| AC12 | Done | `metadata` (fill if empty, the file's rating wins, two sidecars queued, `edited=false`); scripted: the photo with a server description got its sidecar written. An existing sidecar changed by another app is protected by the unchanged `SidecarSync` rules (its tests) |
| AC13 | Done | `stop` (finished photos with links, no partial file, no request after); scripted: Stop after 2, no hidden file; quitting asks "Quit While Importing?" and Keep Importing keeps it running |
| AC14 | Done | `failures` (deleted asset, revoked key, 503 retried), `unreachable`; scripted revoke mid-import: alert "“Home” rejected the API key", 5 imported, then the grid's Can't Connect state |
| AC15 | Done | `RemoteImportTests.migration`, `CatalogTests` |
| AC16 | Done as the window shows it; see RI-E3 | `RemoteBoundaryTests.importerHasNoServers` |
| AC17 | Partly | `aboutIsNetworkFree` (About code, user guide); README, roadmap and `CLAUDE.md` wording at Ship |

## Debug-script checks (2026-11-23)

A copy of the bundle with `CFBundleIdentifier` `me.sesser.gus.debugtest.immich`,
re-signed ad hoc, a scratch library per run (`photobench generate --jpeg 2 …`,
`photobench import`), every launch with `--library-root`; the key store is in
memory in these launches.

- **Browse and import**: `import server fake start 300; import server add Home
  fake` → state photos, 250 loaded, "0 selected · 250 loaded · Not encrypted",
  albums "Empty(0), Trip(7)", Edited badge on IMG_0002; `import scroll end` →
  300, "0 of 300 selected"; `import album Trip` → 5 photos, total 7, project
  "Home - Trip"; four toggled, `import run` → four files under
  `{capture:yyyy}/{capture:yyyy-MM-dd}`, four links, "Imported 4 photos", the
  four marked In Library. Every request was GET except the search; originals
  and thumbnails carried `edited=false`.
- **Sheet**: `http://example.com` refused ("refused example.com", Add dimmed);
  the fake's http address shows the notice, Add dimmed until confirmed; a wrong
  key gives `keyRejected` under the key; the right key saves.
- **Failures**: a deleted asset gives the alert "Imported 3 photos. 1 could not
  be imported."; a revoked key mid-import gives "“Home” rejected the API key"
  with the count, then the grid's Can't Connect (keyRejected); a stopped fake
  and Rescan give Can't Connect (unreachable).
- **Remove and add again**: Remove asks, the server goes, the source clears;
  added again at the same address under another name, the three imported
  photos are still marked.
- **Stop and quit**: see AC13.

## Decisions made within the spec (for review)

- Formats the library does not catalog (a GIF, WebP) are not listed, as a
  card's scan leaves them out.
- The project is created when the first photo verifies (a card import makes it
  first); an import that brings nothing leaves no empty project.
- The template is rendered after the file's own metadata is read from the
  download (as a card's copy reads the file), with the listing's values where
  the file has none.
- A name-only edit saves without a check (design §3.3); the sheet's pass then
  checks again when the server becomes the source (three requests more).
- A missing Keychain item for a saved server is shown as the Keychain result
  with the system's text ("The specified item could not be found in the
  keychain.").
- When the album list fails, Activity gets the reason alone under the
  server's title (DQ-6).
- If removing the key from the Keychain fails, nothing is removed and the
  window's alert gives the Keychain sentence (DQ-5).

## README

For the product manager at Ship (R8, AC17; not edited here):
- `README.md`: one line under What works today (import from an Immich server)
  and a privacy note: the app contacts only a server you add, and sends it only
  the key and read requests.
- `CLAUDE.md`: a Network architecture rule (one connection component in
  PhotoCore `Remote/`; the read-only allowlist; the key only in the Keychain;
  the transport policy; nothing else uses `URLSession`), the new tables in the
  Catalog rule's list (`remoteService`, `remoteLink`), and Layout: PhotoCore
  `Remote/`, PhotoApp now links PhotoFixtures (the debug script's fake server).
- `docs/roadmap.md` principle 3: as the PRD words it.
- About design R5 ("the app makes no network calls") now holds for the About
  window only; the PRD asks for that record to stay and the scope to be noted.

## Requirements issues

**RI-E1. Partners' photos are in the search (R9, non-goals).** Immich's v3
search lists the account's own assets plus those of every partner whose
timeline the account shows (status above, "API verification"), and an album
lists every asset in it, whoever owns it. The asset carries `ownerId`, but the
account's own id needs `GET /users/me`, which needs `user.read`, a fifth
permission R3 does not list. Options: (a) add `user.read` to the needed set
(R3, AC2, the sheet's caption and the user guide change; one more permission
on the key); (b) accept partners' photos and other contributors' album photos
when the person enabled them; (c) what is built now: `/users/me` when the key
has `user.read` or `all`, else the owner of one of the account's own albums
(the first of an album's users is its owner), else no filter. (c) misses when
the account owns no album. Recommendation: (a), the only reliable way.

**RI-E2. External-library checksums are of the path (R13).** For assets of an
Immich external library, the server can store `checksum` as the SHA-1 of
`"path:" + originalPath`, not of the bytes (`ChecksumAlgorithm.sha1Path`,
written by `library.service.ts` at v3.4.2); the API does not say which. As
built (R13 literally), every such photo fails with "the download did not match
the server's checksum". Options: (a) keep it; (b) for an asset with a
`libraryId`, accept when the SHA-1 of `"path:" + originalPath` matches, then
verify by size only (the download is still read back, hashed and deduplicated
by SHA-256); (c) leave external-library assets out of the listing.
Recommendation: (b); it keeps the end-to-end check for uploaded photos and
says exactly what was checked for the others. Unknown: whether the owner's
server uses external libraries.

**RI-E3. AC16's "the importer links no connection code".** The standalone
importer shows no server (tested), but it links PhotoCore and the shared
PhotoUI, which now hold the connection, Keychain and server-window code
(`nm` on a release `PhotoImporter` finds `ImmichClient` and `SecItemAdd`).
Nothing reaches them: servers are read from the library's catalog, which the
importer does not have, and every server item is behind `copiesOnly` or
`includesLibraryItems`. Options: (a) read AC16 as "has no path to"; (b) move
the connection code into a target only PhotoApp links, and the server UI
behind a protocol seam in the shared window (a sizeable refactor: PhotoCore
`Remote/` and `Catalog/RemoteServices.swift` to a new target, `ServerSheet`,
`ServerSource` and `ServerText` to PhotoApp, `CardImportModel` reaching them
through a protocol). Recommendation: (a) now, with (b) as a follow-up when
Publish (#28) adds writers, which is when a separate module pays for itself.

## Design questions

**DQ-5. Removing a server when the Keychain refuses to delete the key.** Design
§3.7 doesn't say. Built: nothing is removed, and the window's alert shows "The
Keychain returned an error: ‹system text›." (design §10's Keychain sentence).
Option: remove the row anyway and warn that the key stays in the Keychain (new
copy needed). Recommendation: as built; the person can try again, and no key
is left behind without its row.

**DQ-6. The album list fails but photos load.** Design §4.2 says "Activity gets
one warning with the reason", with no sentence. Built: the reason alone, under
the "Import from “‹name›”" title. Option: a sentence such as "Couldn't read the
albums of “‹name›”: ‹reason›." (new string). Recommendation: a sentence, from
the designer.

## Known limits

- The check runs in the sheet and again when the saved server becomes the
  source (three extra requests).
- A changed certificate met while browsing (not in the sheet) is shown as the
  grid's Can't Connect with Review Certificate…; the changed-certificate page
  compares with the pinned fingerprint and its trusted date.
- Downloads are one at a time; thumbnails six at a time.
- An asset listed while the account's own id is unknown can be a partner's
  (RI-E1).
- `Retries and timeouts` numbers are the engineer's (R20); the PRD asked for a
  proposal.

## Determinism

The fake server runs on 127.0.0.1 in the test process; no test contacts
another host. Structural arguments for the timing-sensitive tests:
- `stop`: the importer is sequential, so the third original request arrives
  only after the second photo is cataloged; the test cancels when that request
  arrives, and the server holds the third body for 2 s, far beyond the
  cancellation's milliseconds. So exactly two photos import.
- `failures` (revoked key): the fake reads its state (the key) before it calls
  the `onOriginal` hook that revokes the key, so the second download passes
  and the third, sent only after the second is cataloged, gets 401: exactly
  two import.
- `unreachable` and `sevenResults`' closed port: no timing (connection
  refused).

Run counts: the three remote suites (`RemoteImport`, `RemoteCheck`,
`RemoteBoundary`) passed 20 of 20 runs in a row. The full suite passed 9 of
10 runs; the one failure's output was cut by `tail`, so which test failed is
not known (the known flaky `DeferredRenderTests`, #229, is a candidate; a
remote test is not ruled out). 20 clean runs rule out a remote-suite flake
rate above about 1 in 7 at 95%, no tighter.

## CI toolchain

`DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build
--build-tests --scratch-path .build-xcode26.3` passes (2026-11-23, at the
last commit of the session; only the two older test warnings).
`/Applications/Xcode_26.3.app` is a symlink to `/Applications/Xcode-26.3.0.app`.
