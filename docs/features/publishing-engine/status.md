Issue: #28 · Complexity: Hard

# Publish to Immich: status

Owner: swift-macos-engineer. Branch `feature/publishing-engine` (off `develop`).
Spec: the PRD (issue #28, revision 4, approved 2026-11-25) and [design.md](design.md)
(current against revision 4; rulings in its §16).

**State: In progress.** Engineering started 2026-11-26. The verification below
(2026-11-25, and three more items on 2026-11-26) is done; its requirements
issues and design questions are ruled (PRD revisions 3 and 4, design §16).

## Progress

Built (each step committed on the branch):

1. **Connection layer** (`Sources/PhotoCore/Remote/`): `ImmichEndpoint` gains
   `asset(id:)`, `ownAlbumsHolding`, and publishing's four writes (`upload`,
   `createAlbum`, `addToAlbum`, `createStack`); `RemoteRequestAllowlist` holds
   exactly those four writes plus `GET /assets/{id}` (`RemoteRequestAllowlist.writes`).
   `RemoteHTTPSession.exchange` returns any status with at most 64 KiB of an
   error body (the server's words, R23); `RemoteHTTPSession.upload` streams the
   multipart body from a file and ends by R17's rule (`RemoteUploadEnding`,
   which also hears URLSession's `didSendBodyData`). `ImmichClient.check(requiring:readsAccount:)`
   and `checkWithPermissions` serve both Server sheet hosts (R1).
   `ImmichPublishing.swift`: `RemotePublishDestination`, `PublishFailure`,
   `PublishStop`, `PublishUploadBody`.
2. **Catalog**: migration v18, `remotePublication` (records, R17) and
   `remotePublishSettings` (remembered choices and folder map per server, R7,
   R12; removed with the server). `Catalog/RemotePublications.swift`;
   `Catalog.publishSources` (`PublishOriginals.swift`).
3. **Rules** (`PublishOriginals.swift`, `PublishSettings.swift`):
   `OriginalRules` (R11 to R13, R15, design §7.1 as pure functions),
   `OriginalFinder` (the one function Check Originals and the run share,
   AC12), `PublishFolderMapping` (longest folder wins, by volume identity),
   `PublishPathForms` (NFC and NFD, compared by Unicode scalars),
   `PublishPermissions` (R8).
4. **Engine** (`PublishJob.swift`, `PublishRun.swift`): per photo, look for
   the original, render like an export, upload, record at once, read a
   duplicate, album, stack; `AlbumCoordinator` (R22's lost-answer rule),
   `StackSequencer` (one stack at a time per original, grid order), faults
   and the person's Stop, Retry Failed over the same `PublishRun`.
5. **Fake server** (`FakeImmichServer`): uploads with per-account duplicates,
   `GET /assets/{id}`, path search, albums (create, add with the duplicate
   answer, `assetId=` and `name=` filters), stacks as verified (merge by
   primary only, trashed members dropped, a named trashed primary kept),
   partners and unshared accounts, and faults (`refuseStack`, `loseAnswer`,
   `answer`, `holdUploadAnswer`, `stallUploadBody`).
6. **App** (`Sources/PhotoApp`): `PublishModel` (the sheet, check, albums,
   pages, Check Originals, the question, runs, results, Retry Failed, hosting
   the Server sheet), `PublishText`, `PublishSheet` (main page, File Settings,
   folder map), `PublishResultsSheet`; File ▸ Publish… (⌥⌘E), Publish
   Results…, Stop Publishing; the toolbar's Publish (`paperplane`); the
   context menu's Publish…; Activity's job row and Show Results…
   (`ActivityLog.Message.actionID`); the quit case (`QuitConfirmation.publishing`).
   Export's settings state moved to `ExportSettingsEditor` and its form to
   `ExportSettingsSections` and `ExportPresetRow`, shared by both sheets.
7. **Server sheet** (`Sources/PhotoUI/Import/ServerSheet.swift`):
   `ServerSheetHost` and `ServerSheetPurpose` (R1, design §4): required
   permissions, captions, results and Remove Server… by host; the address
   warning (R26). The Import window: published assets In Library with their
   own tooltip, updated in place (R20); "Can't Import from ‹name›"; the
   inspector captions; the Remove Server alert. `Info.plist`'s local network
   text (R27).
8. **Debug script**: `publish …` (`DebugPublishCommands.swift`) and the fake
   server's publishing faults (`import server fake fault stack|lose|answer|hold`,
   `import server fake uploads`).
9. **User guide**: the server import section's read-only wording, and a new
   section "Publishing to an Immich server".

Left: see **State** at the top and the checks below.

## Immich verification (2026-11-25)

Checked against two throwaway Immich servers in Docker on this Mac. **3.2.0** is
the app's minimum and **3.4.2** is the current release (latest non-prerelease
on GitHub, published 2026-11-18). All data was synthetic (`photobench
generate`). There were three accounts: **A** publishes; **B** is another
account; **C** is a partner who shares with A, shown in A's timeline. **A** has
an `all` key, a **minimum key** holding import's five permissions plus PRD R8's
five, and an import-only key. Both versions gave the same results everywhere;
any difference is called out. "Observed live" means a request was sent and the
answer read. "Read from source" means `server/src` at tags `v3.2.0` and
`v3.4.2`, or `open-api/immich-openapi-specs.json` at both tags. The owner's
server was not contacted.

### How to repeat it

The compose file is our own and pulls only what the official compose file
needs to run: server, database and cache. There is no machine-learning image,
and `IMMICH_MACHINE_LEARNING_ENABLED=false` is set. 3.4.2 is the same except the
tag, the port (`127.0.0.1:2284`) and valkey digest
`418652cfb58ef879d4978c33553735d7147016032d5aefaa14c828e611eb9dfd`. The env file
holds generated `DB_PASSWORD` and `POSTGRES_PASSWORD`, plus
`DB_USERNAME=postgres`, `DB_DATABASE_NAME=immich`, `TZ=Etc/UTC` and
`IMMICH_MACHINE_LEARNING_ENABLED=false`.

```yaml
name: gusverify320
services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:v3.2.0
    volumes:
      - upload:/data
      - <scratch>/external:/mnt/media/photos:ro
    env_file: [<scratch>/secrets/env-320]
    environment: { DB_HOSTNAME: database, REDIS_HOSTNAME: redis }
    ports: ['127.0.0.1:2283:2283']
    depends_on: [redis, database]
    restart: on-failure        # the server can start before postgres accepts connections
  redis:
    image: docker.io/valkey/valkey:9@sha256:70739f85ad2ee01a726a965584a0f94895f01b0c60b3cc8b0aeef11eaa6888cf
  database:
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23
    env_file: [<scratch>/secrets/env-320]
    environment: { POSTGRES_USER: postgres, POSTGRES_DB: immich, POSTGRES_INITDB_ARGS: '--data-checksums' }
    volumes: [pgdata:/var/lib/postgresql/data]
    shm_size: 128mb
volumes: { upload: {}, pgdata: {} }
```

Setup used these requests, each under `/api`:

- `POST /auth/admin-sign-up` and `POST /auth/login`, which return `accessToken`.
- `POST /admin/users`.
- `POST /partners {sharedWithId}` as C, then `PUT /partners/{C} {inTimeline: true}` as A.
- `POST /api-keys {name, permissions}`, which returns `secret`.
- `POST /libraries {ownerId, name, importPaths: ["/mnt/media/photos"]}` and `POST /libraries/{id}/scan` (admin session). Each of A, B and C got an external library over the same read-only folder.
- Locked visibility needs an elevated session, so A's session also ran `POST /auth/pin-code`, then `POST /auth/session/unlock`, then `PUT /assets {ids, visibility: "locked"}`.

The helpers are Python with only the standard library: client, setup,
libraries, and experiments by name. Afterwards the containers, volumes and
networks were removed. The images were kept.

### Request and response shapes publishing needs (same on both)

| Request | Key permission | Shape (observed live) |
|---|---|---|
| Upload | `asset.upload` | `POST /assets`, multipart. Required: `assetData` (file), `fileCreatedAt`, `fileModifiedAt`. Optional: `filename` (overrides `originalFileName`), `visibility` (`timeline`, `archive`, `hidden`, `locked`), `isFavorite`, `sidecarData`, `metadata`, `livePhotoVideoId`, `duration`. There is no `deviceAssetId` or `deviceId`. New file: **201** `{"id":"…","status":"created"}`. Identical bytes already among the account's uploads: **200** `{"id":"<existing>","status":"duplicate"}` |
| Create album | `album.create` | `POST /albums {"albumName", "assetIds"?, "description"?}`, **201**, the album. Passing `assetIds` needs no further key permission (the server checks access per asset and silently drops assets it refuses) |
| Add to album | `albumAsset.create` | `PUT /albums/{id}/assets {"ids":[…]}`, **200** `[{"id","success":true}]`. An asset already there gives `{"success":false,"error":"duplicate"}` |
| Create stack | `stack.create` | `POST /stacks {"assetIds":[…]}` (at least 2; the first becomes primary), **201** `{"id","primaryAssetId","assets":[…]}`. The server also requires every asset to be the caller's own and not locked. Otherwise **400** `Not found or no asset.update access` |
| Read stack | `stack.read` | `GET /stacks/{id}` and `GET /stacks?primaryAssetId=` |
| Read one asset | `asset.read` | `GET /assets/{id}` includes `ownerId`, `type`, `visibility`, `isTrashed`, `libraryId`, `originalPath`, `exifInfo.fileSizeInByte`, `stack: {id, primaryAssetId, assetCount}` or null. A refusal and a missing asset look the same: **400** `{"message":"Not found or no asset.read access"}` |
| Find by path | `asset.read` | `POST /search/metadata {"filter":{"originalPath":{"eq": P}} , "withExif": true}`. `eq` is exact, byte for byte: case counts, and so does Unicode normalization (NFC ≠ NFD). `"in": [nfc, nfd]` matches either form in one request. The byte size is `exifInfo.fileSizeInByte`: the file's real size for external-library assets, the uploaded size for uploads |
| Own albums | `album.read` | `GET /albums?isOwned=true`, plus `assetId=` (albums holding that asset) or `name=` (exact, case-sensitive match) |
| Key's permissions | none | `GET /api-keys/me` gives `{id, name, createdAt, updatedAt, permissions}` for any key, so the app can read its key's whole list |

A request missing a key permission gets **403**
`{"message":"Missing required permission: <name>"}`.

### design.md §15, item by item

**1. Capture date for a file with none embedded (R4).** *Holds for the date. The
time of day can shift.* Observed live, both versions.

- With no date in the file, `fileCreatedAt` becomes `dateTimeOriginal`,
  `fileCreatedAt` and `localDateTime`. `fileModifiedAt` does not date the photo:
  sent as "now", it only set `exifInfo.modifyDate`.
- An offset is kept only as an instant. `2019-06-15T10:20:30+02:00` was stored
  as `localDateTime 2019-06-15T08:20:30Z`, so Immich shows 08:20, not 10:20.
- A date embedded in the file wins over `fileCreatedAt`: EXIF 2023 against an
  upload date of 2019 gave 2023.
- Our exports at **All** and **No location** keep `DateTimeOriginal`. At
  **Copyright** and **None** there is no date in the file (checked with
  exiftool), so those levels rely on `fileCreatedAt`.
- A synthetic file with an EXIF date and no offset got `fileCreatedAt =
  localDateTime` = its wall-clock time labelled `Z`.

Consequence: RI-V1.

**2. Visibility set by the upload (R6, R9).** *Holds.* Observed live, both
versions. The multipart field `visibility=archive` gives an archived asset; no
update is needed. Even `locked` was accepted from a plain API key at upload.

**3. An archived primary and the timeline original.** *Does not hold.* Observed
live through the timeline API, both versions. After a stack of [archived edit,
timeline original]:

- The timeline with `withStacked=true` shows **neither** the edit nor the
  original: the original leaves the timeline.
- The archive with `withStacked=true` shows the edit, carrying the stack.
- With `withStacked=false` the original stays in the timeline.
- Import's listing still lists the original, because it filters on the asset's
  own visibility.

`withStacked=true` is the stacked view; the web UI itself was not looked at.
Consequence: RI-V2.

**4. Import listing includes stacked, non-primary originals.** *Holds.* Observed
live, both versions. The import search (no `withStacked`) listed the non-primary
original and its timeline edit. The web timeline (`withStacked=true`) shows only
the primary. Published edits also appear in the listing, which R20 already marks
In Library.

**5. Creating a stack keeps trashed members.** *Does not hold.* Observed live,
both versions, and read from `stack.repository.ts`.

- Once a member is trashed, it drops out of `GET /stacks/{id}` and out of every
  `stack.assetCount`, although its `stackId` stays.
- `POST /stacks` gathers members of merged stacks with `deletedAt is null`, so
  the new stack leaves the trashed member out. Its `stack` became null, and
  after restoring it from the trash it stayed unstacked.
- The app never sees trashed members unless it makes extra requests.

Consequence: RI-V3.

**6. What search and the read of a linked asset reveal (R15).** Observed live,
both versions.

| Asset | Search by path (as A) | `GET /assets/{id}` (as A) |
|---|---|---|
| Own, trashed | returned, `isTrashed: true` | 200, `isTrashed: true` |
| Own, hidden | returned, `visibility: hidden` | 200, `hidden` |
| Own, archived | returned, `archive` | 200, `archive` |
| Own, locked | **not returned** (same as nothing there) | **400**, same as a missing asset |
| Partner C's (shown in A's timeline) | **returned**, `ownerId` C | 200, `ownerId` C |
| B's, not shared | not returned | 400, same as missing |
| B's, in an album B shared with A | not returned | 200, `ownerId` B |
| A video at the path | returned, `type: VIDEO` | (not tried) |
| Nonexistent | n/a | 400 `Not found or no asset.read access` |

So trashed, hidden, "not a photo" and "another account's" can be revealed;
locked never can. For a path match, "another account's" is revealed only for a
partner's asset, and for a linked asset only for a partner's or a shared
album's. This matches §7.1's fallback rule. New finding: with a partner's
external library over the same share (a household setup), every path search
returns **two** assets, A's and C's. Consequence: RI-V4. Path matching is also
sensitive to Unicode normalization: RI-V8.

**7. Permission names (R8).** *Hold, with one permission to spare.* Observed
live, both versions.

- The names are exactly `asset.upload`, `album.create`, `albumAsset.create`,
  `stack.read` and `stack.create`. They exist in both versions' `Permission`
  enum; 3.4.2 adds only `passkey.*` and `clusterGroup.admin`.
- With the minimum key, every request publishing needs succeeded: upload,
  duplicate upload, create album (with and without `assetIds`), add to album,
  create stack, read stack, read asset, search, `GET /albums?assetId=`.
- With each of `asset.upload`, `album.create`, `albumAsset.create`,
  `stack.create`, `stack.read`, `asset.read` and `album.read` removed in turn,
  the request that needs it got 403 naming it. The import-only key got 403 on
  upload, album create and stack create.
- No extra permission is required.
- `GET /api-keys/me` lists the key's permissions; it worked with every key.

The spare permission is `stack.read`. The original's stack primary comes from
`GET /assets/{id}` (`asset.read`) and the create returns its members, so no
request in the flow needs `stack.read`: RI-V5. Detecting a lost album create
needs `album.read` even with New album: DQ-V1.

**8. A lost answer to create-album or create-stack.** Observed live, both
versions.

- **Stack:** repeating the same `POST /stacks` is harmless. It gives the same
  members and primary under a new stack id (the earlier row is replaced, see
  item 10), and `GET /assets/{edit}`'s `stack` tells whether it happened. *Holds.*
- **Album:** a repeated create makes a **second album** of the same name, and
  there is no idempotency key. It can be detected if the run creates the album
  with its first uploaded asset in the same request (`album.create` suffices),
  then on a lost answer looks for an owned album with that exact name holding
  that asset: `GET /albums?isOwned=true&assetId=<first>`. That read needs
  `album.read`. *Holds with that condition* (DQ-V1).

**9. Telling that a duplicate is trashed (R19).** *Holds through one read.*
Observed live, both versions.

- The duplicate answer is the same for a trashed asset (200
  `{"status":"duplicate","id":X}`), and the asset stays in the trash.
  `GET /assets/X` gives `isTrashed: true`.
- The read is required, because the server does not refuse later steps on a
  trashed asset. Adding a trashed asset to an album **succeeds**.
  `POST /stacks [new, trashedX]` returns 201 but leaves X out, a one-member
  stack.
- Also observed: a duplicate of a **locked** asset is answered `duplicate`, and
  the read is 400. A duplicate of a **hidden** asset reads as `hidden`. R19 says
  nothing about either: RI-V6.
- Duplicates are per account and only among uploads. Bytes identical to an
  external-library file, or to another account's upload, were `created`.

**10. A new primary by creating a stack, with no update (R9, R14).** *Holds, with
two conditions.* Observed live, both versions; read from `stack.repository.ts`.

`POST /stacks` merges only the stacks whose **primary** is in `assetIds`. It
deletes those stack rows server-side and makes a new stack, with the first id
as primary:

- `[E, P]`, where P is the primary of {P, M1}, gave {E, P, M1}, with E primary.
- `[E2, E1]`, where E1 was the current primary, gave a new primary E2 with every
  member kept.
- `[E1, O]`, where O is a **non-primary** member, moves O out alone. Its former
  stack is left with P only (P's `stack` reads null).

So the app must read the original's `stack.primaryAssetId` (`GET /assets/{id}`)
and send `[edit, currentPrimary, original]`. The server's deletion of the
replaced stack row is a server-side delete caused by a create: RI-V7.

**11. Album and stack steps right after each upload (R21, R14).** *Holds, if
stack requests are serialized per original.* Observed live, both versions.

- A stack and an album add sent immediately after the upload, while metadata
  extraction was still running, succeeded and survived the extraction.
- Two creates naming the same original sent concurrently left one edit outside
  the original's stack in 5 of 5 tries on each version. Sent one after the
  other with the original named both times, the same happens (item 10).
- The sequence that works: create, then read the original's current primary,
  then the next create names that primary. Ending primary as intended, 3
  members.

This constrains the build: one stack request at a time per original. It needs no
PRD change.

### Other items asked for

**External library, read-only (task 4).** Observed live, both versions. All 7
files of a read-only bind mount were checked:

- `checksum` was the base64 SHA-1 of `"path:" + originalPath`, never of the
  content, so the PRD's non-goal stands.
- `originalPath` is the server's path (`/mnt/media/photos/2024/Iceland/…`).
- `exifInfo.fileSizeInByte` equals the real byte count.
- `libraryId` is set and `isOffline` is false.
- A's external asset can be stacked under an uploaded edit, with the edit as
  primary. Partner C's cannot (400 `no asset.update access`).

**Can URLSession tell that the body is fully sent (R17, task 5)?** *Yes, with a
known meaning.* Observed live with a throwaway Swift program: `uploadTask(with:
fromFile:)`, the delegate's `didSendBodyData`, `countOfBytesSent`, and
`URLSessionTaskMetrics`.

- Against Immich, `totalBytesSent == totalBytesExpectedToSend` arrived 5 to 6 ms
  (27 KB JPEG) and 29 to 33 ms (48 MB DNG) before the 201's headers, on both
  versions.
- Against a local server reading 2 MB/s, "fully sent" came **2.2 s before** the
  server had read the last byte (8 MB body). About 4 MB was still in loopback
  socket buffers. `metrics.requestEndDate` was early too.
- Cancelling at "fully sent" left that server with 6.9 of 8 MB: no upload.

So the signal means "handed to the operating system". It never comes after the
server has the whole body, so:

- (a) an upload treated as fully sent but cut off during the wait leaves no
  asset, which is the safe direction;
- (b) "not fully sent, cancel" can only be wrong in the moment between reading
  `countOfBytesSent` and the cancel taking effect, when the last unsent bytes
  might still go out.

That remaining window is the gap R17 already documents. Read the count at stop
time, not a flag set by a delegate callback that may not have arrived yet. No
Requirements issue.

**Are two renders of an unchanged photo byte-identical (R19, task 6)?** *Yes, for
everything tried.* Observed with `photocli export --library-root <scratch>` on a
`photobench` library (`ExportJob`, the export path the app shares).

- Each export ran 2 or 3 times in separate processes, and every file was
  identical.
- Tried: JPEG at all four metadata levels; TIFF (full size, and long edge 800);
  ImageIO JPEG and HEIC sources; system-decoder DNGs; unedited and edited
  (`exposure.ev`) versions.

Not tried: raws LibRaw decodes, gain-map files, across a macOS update, a
pipeline-version bump or another GPU. Consequence: publishing an unchanged photo
again (New Copy) on the same Mac and build gets the duplicate answer. R19's
"already on the server" is real, not theoretical.

### Not verified

- An https server or certificate trust; a reverse proxy in front.
- The owner's server, deliberately: its version is unknown.
- The web UI itself; the timeline API it uses was read instead.
- Upload throughput on a real network.
- LibRaw-decoded exports.
- Whether a storage template changes `originalPath` for uploads. It doesn't
  matter: path matching applies only to external libraries.
- Behaviour above a few dozen assets.

### Images kept (Docker)

| Image | Disk |
|---|---|
| `ghcr.io/immich-app/immich-server:v3.2.0` | 1.62 GB |
| `ghcr.io/immich-app/immich-server:v3.4.2` | 1.6 GB |
| `ghcr.io/immich-app/postgres@sha256:bcf63357…` (14-vectorchord0.4.3-pgvectors0.2.0) | 1 GB |
| `valkey/valkey@sha256:70739f85…` (3.2.0's) | 189 MB |
| `valkey/valkey@sha256:418652cf…` (3.4.2's) | 191 MB |

### Open items verified 2026-11-26

Observed live on both 3.2.0 and 3.4.2 (`exp2.py`, synthetic data, the same
compose files; servers removed afterwards).

**A. The original's stack primary is in the trash (PRD open question 1).**
*Holds.* Stack {P primary, O, M}; P trashed. `GET /assets/O` still gives
`stack.primaryAssetId` = P. `POST /stacks [E, P, O]` returned 201 with E
primary and listed members {E, O, M}: the other members are kept and the edit
is primary. One nuance: P, named in the create, takes the new stack's id while
in the trash, and **is back in the stack when restored** (count 4). Other
trashed members, not named, stay unstacked when restored (item 5). The user
guide says so; R14's sentence ("Members in the trash drop out … and stay
unstacked if restored") is true of every member but the primary: see RI-E1.

**B. Archive with a stack of more than two (task).** *Holds.* Stack {O, M1,
M2}, all timeline; `POST /stacks [E archived, O]` gave 4 members, E primary.
Timeline with `withStacked=true` shows none of O, M1, M2; the archive shows E.
Each keeps its own visibility (`timeline`). R6's caption is right for any
stack size.

**C. A lost album create told from an older album of the same name (PRD open
question 2).** *Holds.* An older album "Trip" holds X; the run publishes X
again (answered `duplicate`), reads the account's albums named "Trip" (the
older one), creates "Trip" with X and treats the answer as lost. `GET
/albums?isOwned=true&assetId=X` gives both albums; of those named "Trip", the
one not in the set read before is exactly the run's, and the older one is
excluded. `name=` filters by exact name on both versions; album answers carry
`id`, `albumName`, `assetCount`, `createdAt`. The engine uses the set read
before the create, not dates.

## Verification requirements issues (ruled 2026-11-25: PRD revision 3, design §16.4)

Kept as raised; every one is ruled. The rulings are in the PRD's revision 3
and design §16.4.

- **RI-V1 (R4, item 1): the time of day at Copyright and None.** Immich dates a
  file with no embedded date by the upload's `fileCreatedAt`, but shows its UTC
  time: a 10:20 capture at +02:00 shows as 08:20. Options:
  - (a) Accept it and say so in the user guide.
  - (b) Send the capture's wall-clock time labelled UTC. Immich then shows the
    right time, as it does for files whose EXIF date has no offset. The instant
    is off by the offset, which matters only to sorting across zones.
  - (c) Keep the date in the file at every level. This changes what None means
    and is the owner's decision.

  Recommendation: (b). No UI change.
- **RI-V2 (R6, R14, item 3): an archived primary takes the original out of the
  timeline.** Options:
  - (a) Keep both. The Archive caption says that a stacked original leaves the
    timeline with its edit.
  - (b) Archive and Stack with original exclude each other.
  - (c) With Archive, stack but leave the original primary. This contradicts
    R14.

  Recommendation: (a), the cheapest; it keeps both capabilities and states
  Immich's rule. Product decides, the owner if product prefers.
- **RI-V3 (R14, item 5): trashed members leave the stack.** A stack the app
  creates drops members that are in the trash, and they stay unstacked when
  restored. The app can't see them without requests made only to find out
  (R15's principle). Options:
  - (a) Accept it and document it in the user guide, with no results line.
  - (b) Read each member of the original's stack to report it. Extra requests
    are made, and the stack read lists no trashed members anyway, so this does
    not work.

  Recommendation: (a). design §15.5's results line is dropped.
- **RI-V4 (R13, item 6): a partner's asset at the mapped path.** The path search
  returns partners' assets too (C's external library over the same share), so
  "the only match" would fail for every photo in a household setup. Options:
  - (a) Count only assets of the key's account. A partner's asset is used only
    for the "another account's" reason when no own asset matches.
  - (b) Count every returned asset, so these become "more than one match".

  Recommendation: (a).
- **RI-V5 (R8, item 7): `stack.read` is not needed.** No request in the flow
  needs it: `GET /assets/{id}` (`asset.read`) gives the stack and its primary,
  and the create returns its members. Options:
  - (a) Drop it from R8.
  - (b) Keep asking for it.

  Recommendation: (a), least privilege. design §4.1 and §5 follow.
- **RI-V6 (R19, item 9): a duplicate that is hidden or locked.** The server
  answers `duplicate` for an asset that is hidden (readable) or locked (the read
  fails, the same as a missing asset). R19 covers only the trash. Options:
  - (a) Treat both like the trash: report "already on the server" with the
    reason (hidden, or "couldn't be read on the server") and do nothing else.
  - (b) Album and stack anyway. A locked one fails, and a hidden primary hides
    the stack.

  Recommendation: (a).
- **RI-V7 (R9, item 10), the owner decides: a stack create replaces the stacks it
  merges.** The app sends only `POST /stacks`, but the server deletes the merged
  stack rows and makes a new one; the stack id changes, and members in the trash
  are dropped (RI-V3). Nothing else is deleted. Options:
  - (a) Accept it and reword R9: "creating a stack replaces the stack it joins".
  - (b) Don't join existing stacks: stack only an original that is unstacked,
    else publish unstacked with a reason. This loses R14's main case.

  Recommendation: (a).
- **RI-V8 (R13, item 6): Unicode normalization of paths.** Path equality on the
  server is byte for byte. A name can be NFD on one side and NFC on the other,
  depending on how files reached the share. Options:
  - (a) Treat canonically equivalent forms as equal: send both forms with `in`,
    in one request. Case still counts.
  - (b) Exact bytes only, so such photos read "nothing at the mapped path".

  Recommendation: (a). It matches the project-name rule of #271 and needs no new
  request.

## Verification design questions (ruled 2026-11-25: design §16.4)

Kept as raised; every one is ruled in design §16.4.

- **DQ-V1 (§5, §3.4; items 7 and 8): `album.read` with New album.** Retry Failed
  can avoid a second album only by finding the one a lost create made, which
  needs `album.read`. Options:
  - (a) List `album.read` under "Any album" in §5's table.
  - (b) Keep §5 as is, and accept a possible second album after a lost answer.
    R23 would then need an exception like R17's.

  Recommendation: (a). The key caption in §4.1 then names it for albums.
- **DQ-V2 (§3.4, after RI-V2's ruling): the Archive caption.** It depends on the
  ruling. If (a), it needs a sentence that a stacked original leaves the
  timeline with its edit.
- **DQ-V3 (§7.1, item 6): "Hidden or locked".** Only hidden is ever revealed;
  locked reads as not returned or nothing there, as §7.1 step 4 already says.
  Options:
  - (a) Keep the combined wording.
  - (b) Rename the group and sentences to "Hidden".

  Recommendation: (b), since nothing ever reports locked. Low priority.

## Requirements issues (open, for the product manager)

- **RI-E1 (R14, AC22; verified item A): a trashed primary returns to the
  stack.** R14 says members in the trash "drop out of the stack and stay
  unstacked if restored". Live, that is true of every trashed member except
  the original's stack primary: the create must name it (R14's first
  condition), and Immich then gives it the new stack's id although it is in
  the trash, so restoring it puts it back in the stack (not as primary). No
  request is added and nothing in the app changes. Options:
  - (a) Reword R14's sentence: "Members in the trash drop out of the stack;
    restored, they stay unstacked, except the stack's former top photo, which
    returns to it." The user guide already says this.
  - (b) Leave R14 as is (it is about what the app does, which is unchanged).

  Recommendation: (a), so the PRD and the user guide agree. Not blocking.

## Build and test

| When | Command | Result |
|---|---|---|
| 2026-11-25, baseline | `swift build --product photocli`; `swift run -c release photobench …` | Built clean (Swift 6.4.2). No code was changed, so `swift test` was not run |
| 2026-11-26, baseline at a58d943 | `swift build --build-tests` | Built clean, no errors |
| 2026-11-26, engine | `swift test --filter "Remote\|Publish\|CatalogTests\|LibraryRemoval"` | 159 tests in 15 suites passed |
| 2026-11-26, engine | `swift test --filter PublishJobTests`, three runs | 20 of 20 each time |

## README

Nothing yet.
