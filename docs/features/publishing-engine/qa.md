# Publish to Immich: QA

Owner: qa-tester. Date: 2026-11-26. Step 4 of `docs/WORKFLOW.md`.
Issue: #28. Spec: the issue body, PRD revision 7 (AC1 to AC25).
Tested: `feature/publishing-engine` at e23d1ea, on an Apple M4 Pro, macOS
27.2.1 (26B131), macOS SDK 27.2, Swift 6.4.2.

## Verdict

**Passes.** 24 of the 25 criteria are verified; AC17 is the owner's, on their
own server. No failure and no blocking finding. Four small findings are for the
engineer (Q1 to Q4, two of them missing tests) and two are older behaviour to
file as follow-ups (Q5, Q6). Before the pull request the owner also has to
approve the proposed `CLAUDE.md` Network rule (R27, `status.md`).

## What was run

| What | Result |
|---|---|
| `swift test` | 1651 tests in 226 suites passed (98.1 s). `PublishLiveTests` skipped there (opt-in) |
| `swift test --skip-build --filter "PublishJobTests\|PublishRulesTests\|PublishBoundaryTests\|RemoteConnectionTests\|RemoteSessionTests"`, 20 runs | 20 of 20 passed (86 tests). Rules out a per-run flake rate of about 1 in 7 or more (at about 95%), not rarer ones |
| `Scripts/build-app.sh all` | Both bundles built and signed; both executables record SDK 27.2, minimum 15.0 |
| `PublishLiveTests` against a temporary Immich **3.2.0** and **3.4.2** | **Run, passed on both** (see **Live check**) |
| Debug-script runs of a copy of the release bundle (identifier `me.sesser.gus.debugtest.qa28`, re-signed ad hoc) | The sessions under **Scripts**, each with `--library-root` on a `photobench` scratch library and the app's fake server |

Not run here: the CI toolchain build (Xcode 26.3). `status.md` records it for
the fourth round; the only source change since is a comment (C13).

## End to end: what was sent, and what was touched

A relay between the app and its own fake server recorded every byte the app
sent (plain http, and https through a throwaway certificate), and a checker
went through the recordings. The checker was first shown to flag a planted
upload of an original and a planted `DELETE`.

- 963 connections over the recorded sessions and both live servers. Writes:
  `POST /assets` 172, `POST /albums` 8, `PUT /albums/{id}/assets` 59,
  `POST /stacks` 26. **No other write, no `DELETE` or `PATCH`, no request off
  the read list, no cookie.** The key went as `x-api-key` on every request but
  `/server/version`.
- Every upload carried exactly `fileCreatedAt`, `fileModifiedAt`, `filename`,
  `visibility` and the file. **No upload was byte for byte an original or a
  sidecar, and no request body held an original's or a sidecar's bytes.**
- Originals and sidecars: SHA-256, size, modification time, inode and extended
  attributes were identical before and after the first two publishing sessions
  (starting from settled libraries). At the end every file of the scratch
  originals had the same bytes as at the first baseline. Sessions started from
  a copy taken before the first launch rewrote one `.xmp` with the same bytes
  (new inode and time). A launch of such a copy with no publishing does the
  same: it is the one change already waiting in the sidecar queue. The queue
  was empty in every library checked after publishing.
- Every catalogued file in every scratch library, the photos imported from the
  fake server included, still has the SHA-256 recorded when it was imported.
- Uploaded files, read with exiftool (40 files, five runs): no rating or label
  anywhere; GPS only at All metadata; no date at Copyright and contact only or
  None; a typed description in every file of its run and in none at None; the
  library's description unchanged afterwards. A capture at 10:13:20 PM +02:00
  was sent as 22:13:20 labelled UTC.
- At default settings the uploads were byte for byte what `photocli export`
  wrote for the same versions, except one photo whose export itself varies
  between processes (Q6; one of the variants equals the upload).
- No rendered file or upload body was left in the temporary folder after any
  run (only the last launch's empty folder and lock file, which the next launch
  removes).
- The fake server's key appeared in no log and no library.

## Acceptance criteria

Test suites: Rules = `PublishRulesTests`, Runs = `PublishJobTests`, Boundaries
= `PublishBoundaryTests`. "Test" means tests carry every clause (scripts only
confirm); "Script" means at least one clause rests on a scripted run. Each cited
test was read for whether it fails without the behaviour; where one doesn't, it
is said. S1 to S13 are the sessions under **Scripts**.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Script | Boundaries `noPublishingOutsideTheLibraryApp`; `photocli publish` is an unknown command; the importer's executable has no `PublishModel`, `PublishSheet` or `PublishText` symbol (PhotoCore's engine is linked, with no path to it, as `status.md` says). S3: File ▸ Publish… ⌥⌘E, the context menu's Publish… and the toolbar item. S2: opens with no server and adds one | Pass |
| AC2 | Script | S2: video, RAW+JPEG pair, originals, a copy and a missing original: the pair once from its DNG, the copy as its own publication, "1 video was left out.", only the missing one failed. Runs `offlineAndArchive`; `ExportTests` `pairsExportOnceFromTheirRAWAndVideosAreLeftOut`. The unedited copy renders the same bytes as its original, so the server answers one of the two "already on the server" (R19, as specified). A truly unmounted volume was not set up here | Pass |
| AC3 | Script | Runs `uploadsAsExported`; Rules `captureDate`, `uploadBody`, `description`. S2 and the checker: the bullets above. Live check: both servers show the capture date and time at Copyright and contact only | Pass |
| AC4 | Script | Runs `offlineAndArchive`, `newAlbum`, `rememberedChoices`. S1: archived uploads stacked, no update request, the Archive caption names the original and its stack. S2: reopening shows the last settings and album with an empty description; five runs into a newly named album made one album | Pass |
| AC5 | Script | Rules `permissions`; Boundaries `purposes`. S3: each of the seven permissions removed in turn is named under its option (`asset.upload` and `asset.read` under Server), Publish dimmed, a scripted Publish refused, nothing uploaded; a new album without `album.read` is one; a two-permission key publishes with None and stacking off; a read-only key imports. S4: exactly R8's seven publish, make an album and stack. Live check: the same seven on real servers | Pass |
| AC6 | Test | `RemoteCheckTests` `allowlist` pins the writes to the four and refuses updates and deletes before a request exists; `RemoteBoundaryTests` keeps `URLSession` to one file. The checker found no other write | Pass |
| AC7 | Test | Runs `linkAndCopy`, `stackingOffAndFallThrough`, `pairBothLinkedAndCopy`, `pairJPEGLinkedAndCopy`; Boundaries `pairPartner`; Rules `ladder` | Pass |
| AC8 | Test | Rules `folderMap` (longest folder, by volume identity), `unicodeForms`, `ownBesidePartner`, `qualifyingBesideOthers`, `pairs`; Runs `folderMapOwnBesidePartner`. A found folder-map match is not reachable by script (the fake server's seeded photos have no path) | Pass |
| AC9 | Test | Rules `moreThanOne`, `reasonOrder`, `linked`, `ladder`; Runs `noOriginalReasons`. S2: "Nothing at the mapped path" with the path; S11: "No mapped folder" | Pass |
| AC10 | Test | Runs `joinsExistingStack`, `stackOrderWhicheverUploadFinishesFirst` (both orders forced), `trashedPrimaryNamedAndRestored`, `laterPublicationDropsTrashedPrimary`, `refusedStackRetried`. S4: each later create named the new edit, the primary as read, the original | Pass |
| AC11 | Test | Runs `refusedStackRetried`. S4: refused stack, Retry Failed, stacked, one upload for that photo | Pass |
| AC12 | Script | S11: Check Originals "1 of 9" with eight reasons and no upload; the run then stacked 1 and gave the same eight reasons. No test covers the tally (Q2) | Pass |
| AC13 | Script | S1: the question once; Cancel and Skip sent no write; New Copy added assets. S3: after Remove Server and adding it again, it still asks. S2: one new photo among published ones is named ("The other 1 photo is published either way."). Runs `records` | Pass |
| AC14 | Test | Runs `duplicateUsable`, `duplicateLeftAlone`, `duplicateReadFailsThenRetried`. S1: "already on the server" with album and stack | Pass |
| AC15 | Script | S4: published assets show **Already in the library**, not a check box. `RemoteReviewFixTests` `selectAllRule` (Select All leaves marked photos out); ⌘A could not be sent (no key window). Seen after a Rescan; marks changing in place in a listing already loaded were not driven | Pass |
| AC16 | Script | S5: a person's Stop, a 429 retried, one 400 among good photos, a rejected key and a dropped connection, each with its result lines. S6: the quit question, Keep Publishing, Stop and Quit ending after the 10 s bound. Runs `faults`, `lostConnection`, `personsStop`. Temporary folder and originals: above | Pass |
| AC17 | Person | P7 | Open |
| AC18 | Script | S2: a local http server saved once, published with no second question, **Not encrypted (http)…** shown. S8: an https server (pinned certificate) publishes and shows no such line (snapshot looked at) | Pass |
| AC19 | Script | S3: from both hosts, a new address on a server with records warns; a name only, the same address spelt differently, and a server with neither records nor links don't | Pass |
| AC20 | Script | S5: a run stopped with two photos recorded and two in flight: the recorded two had gone to the album (create with the first, add of the second) before the next uploads. No test would fail if album and stack steps were left to the end of a run (Q1) | Pass |
| AC21 | Script | Runs `lostConnection`, `personsStop`, `stopDuringRetryCheck`, `stopInsideRetryJobBeforeFirstPhoto`; Boundaries `retryAndLaterRuns`, `retryNothingLeftAfterLaterRun`. S6: Stop during a retry's check sent nothing and left message and results as they were, the next retry sent the unreached; **A publish is already running.**, **This server's address has changed since this run.**, **This server was removed.** (S6, S7a). S5: after the person's Stop no Retry for unreached photos | Pass |
| AC22 | Script | By reading: `docs/USER_GUIDE.md` (import section; trashed members and the former top photo; a lost answer; unfinished steps; the lost-answer exception), the strings of design §4.1 present in the String Catalog (checked by script), `Info.plist`'s local network text. Left, as R27 assigns them: README line 66 still says the app only reads (Ship), and the `CLAUDE.md` Network rule (owner) | Pass |
| AC23 | Script | Runs `endingWaitsForFullySent`, `notFullySentCancelledAtOnce`, `stopKeepsEndingInEveryReport`. S5: "Stopping. Waiting for “Home” to answer…", Stop dimmed. S6: Stop and Quit with no answer added no record. S7a: a quit while ending asked nothing, waited, and recorded the two answers that came | Pass |
| AC24 | Test | Runs `lostAlbumCreate` (automatic and Retry Failed, with an older album of the same name). S4: with the create's answer lost, one create per new album | Pass |
| AC25 | Script | Boundaries `purposes`. S3: two permissions saved from Publish, refused from Import with "To save a key made only for publishing…", **Can't Import from Home** (snapshot looked at), a key lacking `asset.read` refused from Publish, Album and Stacking name their permissions | Pass |

Counts: passed by test 8 (AC6, 7, 8, 9, 10, 11, 14, 24), passed by script 16
(AC1, 2, 3, 4, 5, 12, 13, 15, 16, 18, 19, 20, 21, 22, 23, 25; AC22 partly by
reading), open for a person 1 (AC17), failed 0.

Also shown by script, beyond the criteria: an untrusted and a changed
certificate in the publish sheet with **Review Certificate…** and Publish dimmed
(D-3; snapshots looked at); D-15's line with the Skip or New Copy question given
up and D-16's end state (S7b); the main page, folder map and results sheets with
the window asked down to 600 × 400 points (S13; it clamps and the sheet kept its
ideal height, so the smallest window stays with P2).

## Live check

`PublishLiveTests` with `PUBLISH_LIVE_SERVER` and `PUBLISH_LIVE_KEY_FILE`, run
on 2026-11-26 at e23d1ea against temporary Immich servers in Docker on this Mac,
set up as `status.md`'s **How to repeat it** describes, from images already
present (`pull_policy: never`), on 127.0.0.1 only, with generated passwords and
a key holding exactly R8's seven permissions. No other server was contacted.
Containers, volumes and networks were removed; the images were kept.

| | 3.2.0 | 3.4.2 |
|---|---|---|
| `PublishLiveTests` | passed | passed |
| Writes seen by the relay | upload 4, album 1, add 1, stack 1; no other | the same |
| Read back from the server | edit primary of a stack of 2 with its linked original; album of 2; both photos dated `2024-05-0x 10:20:30` at Copyright and contact only; no rating | the same |

Not covered by it: the folder map against an external library, https, a reverse
proxy, the web interface (P7).

## Findings

None blocks. Q1 to Q4 are this branch's, for the engineer.

**Q1 (low to medium, missing test; AC20, R21).** No test fails if each photo's
album and stack steps were moved to the end of the run. `personsStop` stops at
the first fully sent upload, so the one photo without its album is the one in
progress, and no photo has completed; the other fault and stop tests use no
album and no stacking, or don't assert them. Expected: a run in which one photo
completes and a second is stopped (its answer held), asserting that the first
is in the album and stacked. Today the behaviour holds (S5).

**Q2 (low, missing test; AC12).** Check Originals' tally (found, checked,
offline, reason groups) is in `PublishModel.checkOriginals` and no test reads
it. The finder it calls is tested. Expected: the tally in PhotoCore with a test
against the run's outcome, or the gap accepted.

**Q3 (low, debug script).** A scripted `quit` doesn't end the app while the
publish sheet or its Server sheet is up, or with the results sheet up and the
import window open: `quit` closes the other library sheets through their
bindings but not `showsPublishSheet`, `showsPublishResults` or
`publish.serverSheet`. Seen: killed after 45 s in two scripts ending with the
publish sheet or its Server sheet up (one of them the first round's combined
scenario) and after 120 s with the results sheet and import window; the same
combined scenario with the sheet closed first quit in 17 s. This agrees with
the attribution to #276 (a real ⌘Q is ignored with any sheet up).

**Q4 (nit, debug script).** With no readable key, `publish print` shows "The key
couldn't be saved" (`ServerText`'s title) while the sheet draws **The key
couldn't be read**, so a scripted check reads a string the person doesn't see.

**Q5 (bug, #271's code, not this branch; follow-up). Reproduced.** The Import
window's **Date Range** toolbar button stays dimmed after a server connects.
Steps: library app, Import window, add or choose a server, wait until the photos
show. Actual: the calendar button is drawn dimmed, and stays so after choosing
an album, Rescan and checking a photo; it turned enabled only once the date
range itself was changed (by script). Expected: enabled as soon as the server is
connected. Evidence: toolbar snapshots before and after (S9; the same button at
brightness 52 then 86, the rescan button 86 in both). `ServerBrowse.client` is
`@ObservationIgnored` here and on `develop`, and `DateRangeButton` is disabled
on `client == nil`. Not tried with a key window (whether View ▸ Date Range… is a
way around it). Title: "Import window: Date Range stays dimmed after a server
connects". Slug: `immich-date-range-dimmed`.

**Q6 (bug, export, older than this branch; follow-up).** The same unchanged
photo can export to different bytes in different processes: six `photocli
export` runs of one photo with a caption and a capture time gave three files of
one size; they differ in the order of the IPTC `Caption-Abstract` and
`TimeCreated` records. For publishing, **New Copy** of an unchanged photo after
a relaunch can then add a second copy instead of answering "already on the
server" (R19 speaks only of identical files, so no criterion fails;
`status.md`'s "byte-identical for everything tried" and the user guide's "an
unchanged photo published again, say" promise a little more than this). Title:
"Export: the same photo can give different bytes between launches (IPTC record
order)". Slug: `export-iptc-order`.

## Scripts

Each was run as `<copy>/Contents/MacOS/Gus --library-root <scratch library> --debug-script "<script>"`.
`$QA` stands for the session's scratch folder. The libraries were
`photobench generate --jpeg 5 --dng 1 --heic 1 --pairs 1 --videos 1` imported with
`photobench import`, with GPS, a title, a description, keywords and an offset added
to one JPEG, and ratings, flags, labels and three exposure edits set with
`photocli`. An address `http://127.0.0.1:472xx` is the recording relay in front of
the fake server; to rerun without a relay, type `fake` in its place (S8 needs a
TLS relay).

### S1

Pristine library A (settled), one original moved away before the launch. Showed: Add from the import window, import two photos, duplicate, new album, folder map, Check Originals 3 of 3; 2 published, 1 already on the server, 3 stacked; assets marked in the grid; Cancel and Skip sent no write; New Copy with Archive and a description, then All except location, Copyright and None. (`import key cmd+a` is not a known command and did nothing.)

```text
wait 3; import server fake start 6; import server fake fault permissions all; import open; wait 1; import server add Home http://127.0.0.1:47281; import server print; import dest $QA/imported; import toggle 0; import toggle 1; import run; import print; import server print; wait 3; print items; focus IMG_00003; duplicate; print copies; selectall; print selection; publish menu; publish sheet; publish print; publish album new QA Trip; publish map open; publish map add $QA/photosA /mnt/media/photos; publish map print; publish map done; publish print; publish originals; snapshot $QA/shots/A1-sheet.png; publish start; publish wait; publish results; snapshot $QA/shots/A2-results.png; publish results close; import server fake uploads; import server fake requests; import server print; import grid; import key cmd+a; import server print; wait 2; publish sheet; publish print; publish start; publish answer cancel; publish print; import server fake requests; publish start; publish answer skip; publish wait; publish results; publish results close; import server fake requests; publish sheet; publish description Typed for QA; publish show archive; publish print; publish start; publish answer newcopy; publish wait; publish results; publish results close; import server fake uploads; publish sheet; publish print; publish description; publish settings open; publish settings metadata nolocation; publish settings done; publish start; publish answer newcopy; publish wait; publish sheet; publish settings open; publish settings metadata copyright; publish settings done; publish start; publish answer newcopy; publish wait; publish sheet; publish description Never sent at none; publish settings open; publish settings metadata none; publish settings done; publish print; publish start; publish answer newcopy; publish wait; publish results; publish results close; import server fake uploads; publish activity; print messages; quit
```

### S2

Library B (settled), `IMG_00005.JPG` moved away before the launch, put back after. Showed: Empty state, Add Server from Publish with the seven permissions; 9 photos and 1 video skipped; Check Originals 0 of 9 with paths; 7 published, 1 already there, 8 not stacked, 1 failed (offline), 1 video left out; the question once per run; each reopening shows the last settings and album, description empty; one `POST /albums` in five runs.

```text
wait 3; sidebar all; import server fake start 2; import server fake fault permissions asset.upload,asset.read,album.read,albumAsset.create,album.create,user.read,stack.create; wait 1; focus IMG_00003; duplicate; selectall; print selection; publish sheet; publish print; snapshot $QA/shots/B1-empty-state.png; publish serversheet add; publish serversheet field name Home; publish serversheet field address http://127.0.0.1:47282; publish serversheet field key fake; publish serversheet confirm on; publish serversheet print; publish serversheet submit; wait 3; publish print; snapshot $QA/shots/B2-sheet.png; publish album new QA New; publish map open; publish map add $QA/photosA /mnt/media/photos; publish map done; publish originals; publish start; publish wait; publish results; publish results close; publish sheet; publish print; publish start; publish answer newcopy; publish wait; publish sheet; publish description Typed for this run; publish settings open; publish settings metadata nolocation; publish settings done; publish start; publish answer newcopy; publish wait; publish sheet; publish settings open; publish settings metadata copyright; publish settings done; publish description; publish start; publish answer newcopy; publish wait; publish sheet; publish settings open; publish settings metadata none; publish settings done; publish description Never at none; publish start; publish answer newcopy; publish wait; publish sheet; publish description; publish print; publish cancel; import server fake requests; quit
```

### S3

A copy of the library as imported (one sidecar change waiting). Showed: Two-permission key saved from Publish, publishes with None and stacking off; Can't Import; refused from Import; a key lacking `asset.read` refused from Publish; read-only key imports; each permission removed in turn named and refused; address warning in both hosts; removed and added again, the question is still asked. Its later `publish originals` and refused-stack steps ran with stacking remembered off, and its imported-photo publish stopped at the question; S4 covers those.

```text
wait 3; sidebar all; menuitems Publish; contextmenu cell 0; toolbar; import server fake start 4; import server fake fault permissions asset.upload,asset.read; focus IMG_00001; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address http://127.0.0.1:47283; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish print; publish album new Never; publish print; publish start; publish album none; publish stacking off; publish print; publish start; publish wait; publish results; publish results close; import open; wait 1; import server select Home; import server print; import server check; import snapshot $QA/shots/C1-cant-import.png; import server add Other http://localhost:47283; import server sheet print; import server sheet close; import server list; import server fake fault permissions asset.upload; publish sheet; publish serversheet add; publish serversheet field name Third; publish serversheet field address http://localhost:47283; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; publish serversheet print; publish serversheet close; wait 1; publish servers; publish cancel; import server fake fault permissions asset.read,asset.view,asset.download,album.read,user.read; import server select Home; import server print; import dest $QA/importedC; import toggle 0; import toggle 1; import run; import print; wait 2; sidebar all; focus IMG_0001; import server fake fault permissions asset.read,album.read,albumAsset.create,album.create,user.read,stack.create; print title; publish sheet; publish album new Never; publish stacking on; publish print; publish start; publish cancel; import server fake fault permissions asset.upload,album.read,albumAsset.create,album.create,user.read,stack.create; print title; publish sheet; publish album new Never; publish stacking on; publish print; publish start; publish cancel; import server fake fault permissions asset.upload,asset.read,albumAsset.create,album.create,user.read,stack.create; print title; publish sheet; publish album new Never; publish stacking on; publish print; publish start; publish cancel; import server fake fault permissions asset.upload,asset.read,album.read,album.create,user.read,stack.create; print title; publish sheet; publish album new Never; publish stacking on; publish print; publish start; publish cancel; import server fake fault permissions asset.upload,asset.read,album.read,albumAsset.create,user.read,stack.create; print title; publish sheet; publish album new Never; publish stacking on; publish print; publish start; publish cancel; import server fake fault permissions asset.upload,asset.read,album.read,albumAsset.create,album.create,stack.create; print title; publish sheet; publish album new Never; publish stacking on; publish print; publish start; publish cancel; import server fake fault permissions asset.upload,asset.read,album.read,albumAsset.create,album.create,user.read; print title; publish sheet; publish album new Never; publish stacking on; publish print; publish start; publish cancel; import server fake requests; import server fake fault permissions asset.upload,asset.read,album.read,albumAsset.create,album.create,user.read,stack.create; publish sheet; publish album new Exact; publish stacking on; publish print; publish originals; publish start; publish wait; publish results; publish results close; focus IMG_0002; import server fake fault stack refuse; publish sheet; publish originals; publish start; publish wait; publish results; import server fake fault stack ok; publish results retry; publish wait; publish results; publish results close; import server fake uploads; import server select Home; import server sheet edit; import server sheet field name Home renamed; import server sheet print; import server sheet field address http://localhost:47283; import server sheet print; import server sheet field address HTTP://127.0.0.1:47283/api/; import server sheet print; import server sheet close; publish sheet; publish serversheet add; publish serversheet field name Spare; publish serversheet field address http://localhost:47283; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish print; publish serversheet edit; publish serversheet field address http://127.0.0.1:1; publish serversheet print; publish serversheet close; wait 1; publish server Home; publish serversheet edit; publish serversheet print; publish serversheet field address http://localhost:9; publish serversheet print; publish serversheet field name Spare; publish serversheet close; wait 1; publish cancel; import server remove Home; import server confirm yes; import server list; publish sheet; publish serversheet add; publish serversheet field name Home again; publish serversheet field address http://127.0.0.1:47283; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish print; publish start; publish answer cancel; publish cancel; import server fake requests; quit
```

### S4

A fresh copy of the library as imported. A first run on library B, which already held a server named Home, failed at the key check and is not counted. Showed: Exactly R8's permissions: 2 of 2 found and stacked, album made; published assets **Already in the library**; a refused stack, Retry Failed, one upload; lost album answers, one create per album. (`import menukey a` did nothing: no key window.)

```text
wait 3; import server fake start 4; import server fake fault permissions asset.read,asset.view,asset.download,album.read,user.read; import open; wait 1; import server add Home http://127.0.0.1:47284; import dest $QA/importedD; import toggle 0; import toggle 1; import run; import print; wait 2; print items; import server fake fault permissions asset.upload,asset.read,album.read,albumAsset.create,album.create,user.read,stack.create; selectall; publish sheet; publish album new Exact; publish stacking on; publish print; publish originals; publish start; publish answer newcopy; publish wait; publish results; publish results close; import server fake requests; import server fake fault permissions all; import rescan; wait 3; import server print; import grid; import menukey a; import server print; focus IMG_0002; import server fake fault stack refuse; publish sheet; publish description second round; publish album none; publish stacking on; publish originals; publish start; publish answer newcopy; publish wait; publish results; snapshot $QA/shots/D1-refused-stack.png; import server fake fault stack ok; publish results retry; publish wait; publish results; publish results close; import server fake uploads; import server fake requests; selectall; import server fake fault lose POST /albums 1; publish sheet; publish album new Lost; publish description third round; publish stacking on; publish start; publish answer newcopy; publish wait; publish results; publish results close; publish sheet; publish print; publish cancel; import server fake fault lose POST /albums 9; publish sheet; publish album new Lost twice; publish description fourth round; publish start; publish answer newcopy; publish wait; publish results; import server fake fault clear; publish results retry; publish wait; publish results; publish results close; publish sheet; publish print; publish cancel; import server fake requests; quit
```

### S5

A copy of the library as imported. Showed: Stop with answers held: Stopping and waiting, Stop dimmed, 2 on the server and 6 not published, the two in the album; 429 retried; 400 fails one photo and Retry Failed sends it; rejected key and lost connection stop the run and say which. Two of its retry steps picked the wrong run of the pop-up; S6 and S7a repeat them.

```text
wait 3; sidebar all; import server fake start 2; import server fake fault permissions all; selectall; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address http://127.0.0.1:47285; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album new Stop run; publish stacking off; import server fake fault hold on; publish start; wait 2; publish job; import server fake fault hold release; wait 2; publish job; publish stop; publish job; wait 1; publish job; publish activity; publish wait; import server fake fault hold off; publish results; publish results close; import server fake fault answer POST /assets 429 1; publish sheet; publish album none; publish description r429; publish start; publish answer newcopy; publish wait; publish results; publish results close; import server fake fault clear; import server fake fault answer POST /assets 400 1; publish sheet; publish description r400; publish start; publish answer newcopy; publish wait; publish results; publish results retry; publish wait; publish results; publish results close; import server fake fault clear; import server fake fault hold on; publish sheet; publish description rkey; publish start; publish answer newcopy; wait 2; import server fake fault revoke; import server fake fault hold release; publish wait; publish results; import server fake fault clear; import server fake fault permissions all; publish results retry; publish wait; publish results; publish results close; import server fake fault hold on; publish sheet; publish description rdrop; publish start; publish answer newcopy; wait 2; import server fake fault drop; import server fake fault hold release; publish wait; publish results; import server fake fault clear; import server fake fault permissions all; import server fake fault slowcheck 30000; publish activity; publish results retry; publish job; publish results; publish menu; publish activity; publish stop; wait 1; publish job; publish activity; publish results; import server fake fault slowcheck 0; import server fake requests; publish results retry; publish wait; publish results; publish results close; wait 1; import server fake fault answer POST /assets 400 1; publish sheet; publish description ru; publish start; publish answer newcopy; publish wait; import server fake fault clear; import server fake fault hold on; publish sheet; publish description ru2; publish start; publish answer newcopy; wait 2; publish results run 2; publish menu; publish results close; publish stop; publish wait; import server fake fault hold off; import open; wait 1; import server select Home; import server sheet edit; import server sheet field address http://localhost:47285; import server sheet print; import server sheet confirm on; import server sheet submit; wait 2; publish results; publish results run 3; publish results retry; publish results close; import server remove Home; import server confirm yes; publish results; publish results run 3; publish results retry; publish results close; print messages; quit
```

### S6

A copy of the library as imported. Showed: Stop during a retry's check (request list unchanged, message and results unchanged), the next retry publishes all 8; address changed and server removed dim Retry Failed with their reasons; ⌘Q's menu item asks, Keep Publishing keeps, Stop and Quit ends the app about 10 s later; no record for the unanswered uploads.

```text
wait 3; sidebar all; import server fake start 2; import server fake fault permissions all; selectall; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address http://127.0.0.1:47286; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album none; publish stacking off; import server fake fault hold on; publish start; wait 2; import server fake fault drop; import server fake fault hold release; publish wait; publish results; publish results close; import server fake fault clear; import server fake fault permissions all; import server fake fault slowcheck 30000; publish activity; import server fake requests; publish results; publish results retry; publish job; publish stop; wait 1; publish job; publish activity; import server fake requests; publish results; publish results close; import server fake fault slowcheck 0; publish results; publish results retry; publish wait; publish results; publish results close; import server fake fault answer POST /assets 400 1; publish sheet; publish album none; publish stacking off; publish description f1; publish start; publish answer newcopy; publish wait; publish results; publish results close; import server fake fault clear; import server fake fault hold on; publish sheet; publish album none; publish stacking off; publish description f2; publish start; publish answer newcopy; wait 2; publish results run 2; publish menu; publish results close; publish stop; publish wait; import server fake fault hold off; publish results run 2; publish results close; import open; wait 1; import server select Home; import server sheet edit; import server sheet field address http://localhost:47286; import server sheet confirm on; wait 1; import server sheet submit; wait 3; import server list; publish results; publish results run 2; publish results retry; publish results close; import server sheet edit; import server sheet field address http://127.0.0.1:47286; import server sheet confirm on; wait 1; import server sheet submit; wait 3; publish results; publish results run 2; publish results close; import server remove Home; import server confirm yes; publish results; publish results run 2; publish results retry; publish results close; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address http://127.0.0.1:47286; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album none; publish stacking off; import server fake fault hold on; publish description q1; publish start; publish answer newcopy; wait 2; menuitems Quit; menupress Quit Gus; wait 1; alert; alert press Keep Publishing; wait 1; publish job; import server fake uploads; menupress Quit Gus; wait 1; alert; alert press Stop and Quit; publish job; wait 30; print messages; quit
```

### S7a

A copy of the library as imported. Showed: **A publish is already running.**; Stop, then Quit: no question; answers released, 2 more records (9 in all), the app quit.

```text
wait 3; sidebar all; import server fake start 2; import server fake fault permissions all; selectall; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address http://127.0.0.1:47287; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; import server fake fault answer POST /assets 400 1; publish sheet; publish album none; publish stacking off; publish description g1; publish start; publish wait; publish results; publish results close; import server fake fault clear; import server fake fault hold on; publish sheet; publish album none; publish stacking off; publish description g2; publish start; publish answer newcopy; wait 2; publish results run 1; publish results retry; publish results close; publish stop; menupress Quit Gus; wait 1; alert; publish job; import server fake fault hold release; wait 30; print messages; quit
```

### S7b

The same library, relaunched. Showed: The question counts the 8 recorded photos; D-15's line and no run; D-16: Save after removal leaves no server.

```text
wait 3; sidebar all; import server fake start 2; import server fake fault permissions all; selectall; publish sheet; wait 1; publish serversheet edit; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album none; publish stacking off; publish start; publish answer cancel; publish start; import open; wait 1; import server select Home; import server sheet edit; import server sheet field address http://localhost:47287; import server sheet field key fake; import server sheet confirm on; wait 1; import server sheet submit; wait 3; publish print; publish answer newcopy; publish job; publish serversheet edit; import server remove Home; import server confirm yes; publish serversheet field name Renamed; publish serversheet submit; wait 2; publish print; import server list; import server fake requests; publish cancel; quit
```

### S7c

Quit with the sheet up and no server saved. Showed: Quit.

```text
wait 3; sidebar all; focus IMG_00001; publish sheet; quit
```

### S7e

The first round's combined scenario, ending with the publish Server sheet up. Showed: Did not quit; killed after 45 s.

```text
wait 3; sidebar all; focus IMG_00001; import server fake start 2; import server fake fault permissions all; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address fake; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album none; publish stacking off; publish start; publish wait; import open; wait 1; import server sheet add; import server sheet close; import server select Home; import server sheet edit; import server sheet close; publish sheet; publish serversheet edit; publish serversheet print; quit
```

### S7f

The same, sheet closed first. Showed: Quit after 17 s.

```text
wait 3; sidebar all; focus IMG_00001; import server fake start 2; import server fake fault permissions all; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address fake; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album none; publish stacking off; publish start; publish wait; import open; wait 1; import server sheet add; import server sheet close; import server select Home; import server sheet edit; import server sheet close; publish sheet; publish serversheet edit; publish serversheet close; wait 1; publish print; publish cancel; quit
```

### S7g

Quit with the publish sheet up after a run. Showed: Did not quit; killed after 45 s.

```text
wait 3; sidebar all; focus IMG_00001; import server fake start 2; import server fake fault permissions all; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address fake; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album none; publish stacking off; publish start; publish wait; publish sheet; quit
```

### S7h

Quit with the results sheet up. Showed: Quit.

```text
wait 3; sidebar all; focus IMG_00001; import server fake start 2; import server fake fault permissions all; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address fake; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album none; publish stacking off; publish start; publish wait; publish sheet; publish cancel; publish results; quit
```

### S8

The relay speaks TLS with a throwaway certificate, changes to a second one once `publish job` has printed, and the scratch catalog's stored fingerprint is cleared after the next `publish activity`. Showed: Certificate page and Trust; https publish with no Not encrypted line; changed certificate, then untrusted, each with Review Certificate… and Publish refused.

```text
wait 3; sidebar all; focus IMG_00001; import server fake start 2; import server fake fault permissions all; import open; wait 1; import server sheet add; import server sheet field name Secure; import server sheet field address https://127.0.0.1:47290; import server sheet field key fake; import server sheet submit; import server sheet print; import server sheet trust; wait 3; import server list; publish sheet; publish album none; publish stacking off; publish print; snapshot $QA/shots/T1-https.png; publish start; publish wait; publish results; publish results close; publish job; wait 1; publish sheet; publish print; snapshot $QA/shots/T2-certificate-changed.png; publish start; publish cancel; publish serversheet add; publish serversheet close; wait 1; publish cancel; publish activity; wait 6; publish sheet; publish print; snapshot $QA/shots/T3-untrusted.png; publish start; publish cancel; quit
```

### S9

A copy of the library as imported. Showed: Date Range dimmed 6 s and 22 s after connecting, enabled only after the date range changed (Q5).

```text
wait 3; import server fake start 4; import server fake fault permissions all; import open; wait 1; import server add Home fake; wait 5; import server print; import snapshot $QA/shots/I1-connected.png; wait 15; import snapshot $QA/shots/I2-connected-later.png; import dates 2026-01-01 -; wait 1; import dates clear; wait 2; import server print; import snapshot $QA/shots/I3-after-dates.png; quit
```

### S9b

The same. Showed: Still dimmed after an album change, Rescan and a checked photo (Q5).

```text
wait 3; import server fake start 4; import server fake fault permissions all; import open; wait 1; import server add Home fake; wait 3; import album Trip; wait 3; import snapshot $QA/shots/I4-after-album.png; import rescan; wait 4; import snapshot $QA/shots/I5-after-rescan.png; import toggle 0; wait 2; import snapshot $QA/shots/I6-after-check.png; menuitems Date Range; quit
```

### S11

One imported photo beside the local ones. Showed: Check Originals 1 of 9, nothing uploaded; the run: 1 stacked, 8 not, same reasons. A first form that left the results sheet and import window up did not quit (Q3).

```text
wait 3; import server fake start 2; import server fake fault permissions all; import open; wait 1; import server add Home http://127.0.0.1:47291; import dest $QA/importedK; import toggle 0; import run; wait 2; import close; wait 1; sidebar all; wait 1; selectall; wait 1; print selection; publish sheet; publish album none; publish stacking on; publish originals; import server fake requests; publish start; publish wait; publish results; publish results close; quit
```

### S12a

The sign-off command's session A, with a publish appended. Showed: Server added, check passed, 12 published.

```text
wait 3; import server fake start 12; import server fake fault permissions all; import open; wait 1; import server add Test fake; import close; wait 1; sidebar all; selectall; publish sheet; publish print; publish start; publish wait; publish results; publish results close; quit
```

### S12b

Session B with a quit appended. Showed: Held run, quit question, Stop and Quit ended it.

```text
wait 3; import server fake start 12; import server fake fault permissions all; import open; wait 1; import server add Test fake; import close; import server fake fault hold on; wait 1; sidebar all; selectall; publish sheet; publish start; wait 3; publish job; menupress Quit Gus; wait 1; alert; alert press Stop and Quit; wait 30; quit
```

### S13

Window asked down to 600 × 400. Showed: Snapshots of the main page, its foot, File Settings, folder map and results.

```text
wait 3; windowsize 600 400; wait 1; import server fake start 4; import server fake fault permissions all; import open; wait 1; import server add Home fake; import close; wait 1; sidebar all; selectall; publish sheet; wait 1; snapshot $QA/shots/S1-small-main.png; publish scroll bottom; snapshot $QA/shots/S2-small-bottom.png; publish settings open; wait 1; snapshot $QA/shots/S3-small-settings.png; publish settings cancel; publish map open; publish map add $QA/photosA /mnt/media/photos/; wait 1; snapshot $QA/shots/S4-small-map.png; publish map done; publish start; publish wait; publish results; wait 1; snapshot $QA/shots/S5-small-results.png; publish results close; quit
```

## For a person

Do them in this order. P1 to P6 cover review.md's M1 to M6 and need only the
app's fake server; P7 is AC17 (M7) on your own server. VoiceOver and older macOS
releases are not asked for.

Build and make two scratch libraries:

```zsh
cd /Users/randy/Projects/Gus
Scripts/build-app.sh
swift run -c release photobench generate --output "$HOME/gus-signoff-28/photos" --jpeg 8 --dng 2 --heic 1 --pairs 1 --videos 1
swift run -c release photobench import --library-root "$HOME/gus-signoff-28/library" --source "$HOME/gus-signoff-28/photos"
swift run -c release photobench import --library-root "$HOME/gus-signoff-28/library-held" --source "$HOME/gus-signoff-28/photos"
```

Session A, for P1 to P5 (a fake server named **Test** is already added; keys
stay in memory):

```zsh
cd /Users/randy/Projects/Gus
open -n build/Gus.app --args --library-root "$HOME/gus-signoff-28/library" --debug-script "wait 3; import server fake start 12; import server fake fault permissions all; import open; wait 1; import server add Test fake; import close"
```

In sessions A and B don't rate, edit or duplicate photos: a script launch turns
undo grouping off, and an edit by hand can crash the app. Publishing is safe.
Never open the bundle without `--args --library-root …` (a bare `open` or a
double-click opens your real library). Quit your installed copy first:
`build/Gus.app` shares its preferences.

- **P1 (M3). Menus and toolbar.** File menu (Publish… ⌥⌘E, Publish Results…,
  Stop Publishing: order and dimming), a photo's context menu, the toolbar's
  Publish in the default set, Customize Toolbar and the overflow menu.
- **P2 (M1). Look.** Select All, ⌥⌘E. The three pages (main, Edit Settings…,
  Edit Folder Map…) and, after a run, the results, at the smallest window, also
  with Increase Contrast. A long address truncates in the middle (see it with a
  long path added to the address, or in P7).
- **P3 (M2). Keyboard only.** From ⌥⌘E through every control. Press **Return**
  right after the check finishes, with no click first: it publishes. In
  Description try Return and Option-Return and note what Return does (publishing,
  a new line or nothing are all acceptable). In the folder map, **Add Folder…**
  through the real panel: the server field has the keyboard; type
  `/mnt/media/photos`, edit its middle, paste a path ending in `/`. Focus goes
  back to the grid after the sheet closes.
- **P4 (M4). Mouse.** The Album pop-up ticks the current choice. Add Server…,
  Edit “Test”… and Cancel swap sheets and keep your choices and description. In
  Edit Settings…, choose a watermark PNG, delete that file in the Finder, reopen
  the sheet, choose a file at the same place again: the warning clears. The
  dimmed **New Album…** and Review Certificate… need a real server: P7.
- **P5 (M5). Question and results.** Publish one photo twice, then several: the
  Skip or New Copy wording; **Return** is Skip; **Esc** returns. With the alert
  up, in the Import window change Test's address from `127.0.0.1` to `localhost`
  (keep the port, tick the unencrypted notice) and Save: the alert closes, the
  sheet says **This server's address or
  certificate changed. Nothing was published.**, and Activity shows no new run.
  With the alert up again, note the port, then remove the server there: the
  alert closes. Add it again at the same address (the fake server's test key is
  `fake-key-0123456789`), open **Edit “‹name›”…** from Publish, remove that
  server in the Import window, change the name and Save: the sheet closes once
  and Publish comes back with **This server was removed.** (or the empty state if
  it was the last). In results: Return and Esc close; the Run pop-up; selecting a
  reason's text.

Session B, for P6. Quit A first. The server takes uploads and never answers:

```zsh
cd /Users/randy/Projects/Gus
open -n build/Gus.app --args --library-root "$HOME/gus-signoff-28/library-held" --debug-script "wait 3; import server fake start 12; import server fake fault permissions all; import open; wait 1; import server add Test fake; import close; import server fake fault hold on"
```

- **P6 (M6). A run in progress.** Publish a few photos. Look at Activity's row;
  ⌘Q: **Quit While Publishing?**, Return and Esc keep publishing. **Stop**:
  **Stopping. Waiting for “Test” to answer…** for about 10 seconds, Stop dimmed,
  then the message with **Show Results…**. Publish again and ⌘Q during the
  stopping time: no question, the app quits when the wait ends. During a run the
  Import window's Edit Server… and Remove Server… for Test are dimmed. The rest
  of M6 (Stop while a large photo renders, Stop while a retry checks a slow
  server, new uploads marked In Library in the Import window) needs a real
  server: look during P7.

- **P7 (AC17, M7). Your server.** This launch uses the real identifier, so the
  key goes into your Keychain and preferences are shared with your installed
  app; the library is a new, empty scratch one.

```zsh
cd /Users/randy/Projects/Gus
mkdir -p "$HOME/gus-signoff-28/library-real"
open -n build/Gus.app --args --library-root "$HOME/gus-signoff-28/library-real"
```

  Give the Import window a destination inside `~/gus-signoff-28`, not a folder
  Immich or your real library uses. macOS may ask about the local network (read
  that text) and about the Keychain.

  1. In Immich, pick one external-library photo and one uploaded photo that
     already have a title or description and keywords. Put one of the two in a
     stack with some other test photo, not on top if you want the stronger case.
     Use photos and stacks you can afford to rearrange.
  2. File ▸ Import: add your server there with a key holding import's five
     permissions plus `asset.upload`, `albumAsset.create`, `album.create` and
     `stack.create`. Import the uploaded photo.
  3. File ▸ Add Folder Without Copying…: the folder, as this Mac mounts it, that
     holds the external-library photo (a small one).
  4. Change each of the two slightly (exposure). Select both, ⌥⌘E. **Edit Folder
     Map…**: that Mac folder, and the path Immich shows in the asset's info panel
     up to the same folder. **Check Originals** must say 2 of 2 before you go on.
  5. Album **New Album…**, Show in **Timeline**, stacking on, All metadata.
     Publish.
  6. In Immich: each shows as a stack with the edit on top; the earlier stack
     members are still in it; the date and time are the capture's; title or
     description and keywords read as expected; both are in the album; an https
     server shows no **Not encrypted** line.
  7. Optional: publish one again as **New Copy** at Copyright and contact only
     (the date and time should still be the capture's).
  8. Optional, for the rest of M4 to M6: publish a large photo and press
     **Stop** while it renders (**Stopping…** until the render returns); after a
     run, **Rescan** in the Import window shows the uploads **In Library**; edit
     the key in Immich to drop `album.read`, then **New Album…** is dimmed over
     **Albums need album.read on this key**. With a certificate macOS doesn't
     trust, **Review Certificate…** swaps sheets and comes back.
  9. Afterwards delete the test uploads and the album in Immich by hand (the app
     never deletes), unstack what you stacked, use Remove Server… to take the key
     out of the Keychain, and delete `~/gus-signoff-28`.

  What could go wrong:

  - Adding keywords or editing metadata in the app writes `.xmp` sidecars beside
    the originals if sidecar writing is on, and Immich may read them. Exposure
    changes don't. Pick photos that already carry their metadata.
  - "Nothing at the mapped path": the server path is the one inside Immich's
    container, not the host's; capital letters count; the external library must
    belong to the key's account (a partner's doesn't count). "Size differs": the
    file changed since Immich scanned it.
  - A reverse proxy: an upload limit gives "the server didn't accept the upload
    (413)" (nginx's default is 1 MB); a short timeout cuts large TIFFs;
    compressing unasked makes the server read as not Immich.
  - A certificate macOS doesn't trust: the sheet says so with **Review
    Certificate…** (read that wording, F10). Plain http is refused except to a
    local address; Tailscale addresses count as not local.
  - A key missing a permission: named under the option, Publish dimmed.
  - Creating a stack replaces the one it joins, and members in Immich's trash
    drop out of it (documented). Archive takes the original out of the timeline.
  - Publishing the same photo again may add a second copy rather than say it is
    already there (Q6).

Owner's decision, not a check: approve or change the proposed `CLAUDE.md`
Network rule in `status.md`, to be committed on this branch before the pull
request (R27).

## Safety of these runs

Every launch carried `--library-root` on a scratch library. The owner's library
folder had no file newer than the start of QA; no instance, relay, container,
volume or added network was left; the scratch copy's preferences were removed.
The Keychain was not read (a script launch keeps keys in memory), and the
owner's server was not looked for or contacted. One extra run opened the copy
as the active app; keyboard input from outside the run reached its Import
window, so its output was deleted and nothing here rests on it.

## Follow-up

None yet.

