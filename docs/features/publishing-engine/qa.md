# Publish to Immich: QA

Owner: qa-tester. Date: 2026-11-27. Step 4 of `docs/WORKFLOW.md`.
Issue: #28. Spec: the issue body, PRD revision 7 (AC1 to AC25).
Tested: `feature/publishing-engine` at c7e8576, on an Apple M4 Pro, macOS
27.2.1 (26B131), macOS SDK 27.2, Swift 6.4.2. Fifth pass, narrow: Q8's fix
(5412951, test only). Earlier passes: 9d6336a (the CI fix for pull request
#307), e23d1ea (committed in bc54ded), c2ea497 and 0eac173. From 9d6336a to
c7e8576 the only change outside `docs/features/publishing-engine/` is one test
in `PublishJobTests.swift` (`git diff`). From e73cb45 (signed off) to c7e8576
the only changes under `Sources/`, `Tests/`, `Scripts/`, `Support/`,
`Package.swift`, `Package.resolved`, `Branding.xcconfig` or the user guide are
`PublishJobTests.swift` and an internal test seam in `RemoteHTTPSession.swift`
and `PublishJob.swift` that changes no behaviour (read at 9d6336a; code review,
ninth pass). So the app sessions, the live check, the bundle builds and the
owner's checks hold and were not rerun.

## Verdict

**Passes at c7e8576, and the owner's sign-off of 2026-11-26 at e73cb45 stands:**
no app behaviour has changed since. All 25 criteria are verified; AC17 by the
owner, who ran P7 on their own server. No finding is open: **Q8** is fixed
(5412951) and confirmed here, so Q1 to Q4, Q7 and Q8 are closed; Q5 and Q6 are
filed as #301 and #302. The owner named no check as left open; P1 to P6 and P8
were not recorded one by one. The owner approved the proposed `CLAUDE.md`
Network rule and the catalog table-list addition (R27). Also open: the known
issue #303 (read **Known issues** before trying the branch), and **CI has not
passed on this commit**: on 2026-11-27, during this pass, the head of pull
request #307 on GitHub was bffefbc, without Q8's fix; its app bundle job had
passed and its build and test job was still running.

## What was run

| At | What | Result |
|---|---|---|
| c7e8576 | `swift test`, once | 1671 tests in 228 suites passed (104.6 s), the AC23 tests and `personsStop` among them. `PublishLiveTests` and the other opt-in suites skipped; the RAW golden comparison skipped (as below) |
| c7e8576 | `notFullySentCancelledAtOnce` in a scratch copy of HEAD outside the checkout: unmutated, with Q8's mutation, then restored | Passed (0.26 s); failed with 1 issue (61.0 s); passed (0.26 s). See **Q8** under **Findings** |
| 9d6336a | `swift test`, once | 1671 tests in 228 suites passed (104.9 s), the AC23 tests among them. `PublishLiveTests` and the other opt-in suites skipped; the RAW golden comparison skipped (as below) |
| 9d6336a | The four AC23 tests and `personsStop` in a scratch copy of HEAD outside the checkout: unmutated, then one change to the sources at a time | See **AC23 after the CI fix** |
| 0eac173 | `swift test`, once | 1670 tests in 228 suites passed (98.4 s). `PublishLiveTests` and the other opt-in suites skipped; the RAW golden comparison skipped (goldens made on macOS build 26B123, this Mac is 26B131) |
| 0eac173 | `swift test --skip-build --filter "PublishKeyPairingTests\|ServerKeyPairingTests\|PublishJobTests\|PublishRulesTests\|PublishBoundaryTests\|RemoteConnectionTests\|RemoteSessionTests"`, 30 runs | 30 of 30 passed (105 tests). Rules out a per-run flake rate of about 1 in 10 or more (at about 95%), not rarer ones |
| 0eac173 | Q7: the same suites in a scratch copy of HEAD outside the checkout, unmutated, with three mutations of `PublishRetry.perform`, then restored | Unmutated and restored: 105 passed. Each mutation failed only the new test (see **Follow-up**) |
| 0eac173 | `swift build --build-tests` under Xcode 26.3 (Swift 6.2.4), `--scratch-path .build-xcode26.3` | Exit 0. Nothing was left to compile in that build folder, so this is not a clean build |
| c2ea497 | Nine changes made one at a time to a scratch copy of the sources, each followed by the publishing suites | Eight made the intended tests fail; the ninth (D-17) failed nothing then (Q7, closed above) |
| c2ea497 | `Scripts/build-app.sh all` | Exit 0, both bundles; both executables record SDK 27.2, minimum 15.0; both signatures verify |
| c2ea497 | Debug-script runs of a copy of the release bundle (identifier `me.sesser.gus.debugtest.qarecheck28`, re-signed ad hoc), launched from the shell, never activated | S1 to S8, S11 and S13 rerun; W1 to W6, T and L new (see **Scripts**), each with `--library-root` on a scratch library and the app's fake server |
| c2ea497 | The commands under **For a person**, extracted from this file and run in zsh | See **How the sign-off commands were checked** |
| e23d1ea | Live check against a real Immich, 3.2.0 and 3.4.2 | Passed. Not rerun since: up to 0eac173 `PublishJob`, `ImmichClient`, `ImmichAPI`, `RemoteHTTPSession` and the String Catalog were unchanged; since then only the test seam in `PublishJob` and `RemoteHTTPSession` |

## End to end: what was sent, and what was touched

At c2ea497. A relay between the app and its own fake server recorded every byte
the app sent in S1 to S6, S7a, S7b, S8, S11 and T (plain http, and https through a throwaway certificate),
and a checker went through the recordings. At that commit the checker was shown
to flag a planted `DELETE` and a planted upload of an original.

- 990 connections. Writes: `POST /assets` 165, `POST /albums` 6,
  `PUT /albums/{id}/assets` 57, `POST /stacks` 24. **No other write, no
  `DELETE` or `PATCH`, no request off the read list, no cookie.** The key went
  as `x-api-key` on every request but `/server/version`.
- Every upload carried exactly `fileCreatedAt`, `fileModifiedAt`, `filename`,
  `visibility` and the file. **No upload was byte for byte an original or a
  sidecar, and no request body held an original's or a sidecar's bytes.**
- Originals and sidecars (13 files): SHA-256, size, modification time, inode and
  extended attributes were identical between the state after two settling
  launches and the state after every session.
- S2's 40 uploads, read with exiftool: no rating or label anywhere; GPS only at
  All metadata; no date at Copyright and contact only or None; the typed
  description in all 8 files of its run; the library's description unchanged. A
  capture at 10:13:20 PM +02:00 was sent as 22:13:20 labelled UTC.
- The only thing left in the publishing temporary folder was the last launch's
  empty folder and lock file, which the next launch removes.
- The fake server's key appeared in no log and no scratch catalog.
- Not repeated: the first pass's byte comparison of uploads with `photocli
  export` (the export and upload code is unchanged).

## Acceptance criteria

Test suites: Rules = `PublishRulesTests`, Runs = `PublishJobTests`, Boundaries
= `PublishBoundaryTests`. "Test" means tests carry every clause (scripts only
confirm); "Script" means at least one clause rests on a scripted run. Each cited
test was read for whether it fails without the behaviour.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 | Script | Boundaries `noPublishingOutsideTheLibraryApp`; `photocli publish` is an unknown command (exit 2); the importer's executable has no `PublishModel`, `PublishSheet`, `PublishText` or results symbol (PhotoCore's engine is linked, with no path to it). S3: File ▸ Publish… ⌥⌘E, the context menu's Publish… and the toolbar. S2: opens with no server and adds one | Pass |
| AC2 | Script | S2: video, RAW+JPEG pair, originals, a copy and a missing original: the pair once from its DNG, the copy as its own publication, "1 video was left out.", only the missing one failed. Runs `offlineAndArchive`; `ExportTests` `pairsExportOnceFromTheirRAWAndVideosAreLeftOut`. The unedited copy renders the same bytes as its original, so the server answers one of the two "already on the server" (R19, as specified). A truly unmounted volume was not set up | Pass |
| AC3 | Script | Runs `uploadsAsExported`; Rules `captureDate`, `uploadBody`, `description`. S2 and the checker: the bullets above. Live check at e23d1ea: both servers showed the capture date and time at Copyright and contact only | Pass |
| AC4 | Script | Runs `offlineAndArchive`, `newAlbum`, `rememberedChoices`. S1: archived uploads stacked, no update request. S2: reopening shows the last settings and album with an empty description; one `POST /albums` in five runs into a newly named album | Pass |
| AC5 | Script | Rules `permissions`; Boundaries `purposes`. S3: each of the seven permissions removed in turn is named under its option, Publish dimmed, a scripted Publish refused; a two-permission key publishes with None and stacking off; a read-only key imports. S4: exactly R8's seven publish, make an album and stack. Live check at e23d1ea: the same seven on real servers | Pass |
| AC6 | Test | `RemoteConnectionTests` `allowlist` pins the writes to the four and refuses updates and deletes before a request exists; `RemoteBoundaryTests` keeps `URLSession` to one file. The checker found no other write | Pass |
| AC7 | Test | Runs `linkAndCopy`, `stackingOffAndFallThrough`, `pairBothLinkedAndCopy`, `pairJPEGLinkedAndCopy`; Boundaries `pairPartner`; Rules `ladder` | Pass |
| AC8 | Test | Rules `folderMap`, `unicodeForms`, `ownBesidePartner`, `qualifyingBesideOthers`, `pairs`; Runs `folderMapOwnBesidePartner`. A found folder-map match is not reachable by script (the fake server's seeded photos have no path) | Pass |
| AC9 | Test | Rules `moreThanOne`, `reasonOrder`, `linked`, `ladder`; Runs `noOriginalReasons`. S2: "nothing at" the mapped path; S11: no mapped folder | Pass |
| AC10 | Test | Runs `joinsExistingStack`, `stackOrderWhicheverUploadFinishesFirst`, `trashedPrimaryNamedAndRestored`, `laterPublicationDropsTrashedPrimary`, `refusedStackRetried` | Pass |
| AC11 | Test | Runs `refusedStackRetried`. S4: refused stack, Retry Failed, stacked, one upload for that photo | Pass |
| AC12 | Test | Runs `originalsTallyMatchesRun` (the check's found count and reason groups equal the run's; no write; offline photos counted and not looked for) and `originalsTallyFailureAndCancel`; with a found original not counted the first fails (3 issues). The sheet calls that function. S11: "Originals found: 1 of 9." with eight reasons, then 1 stacked and 8 not | Pass |
| AC13 | Script | S1: the question once; Cancel and Skip sent no write; New Copy added assets. S3: after Remove Server and adding it again, it still asks. Runs `records` | Pass |
| AC14 | Test | Runs `duplicateUsable`, `duplicateLeftAlone`, `duplicateReadFailsThenRetried`. S1: "already on the server" with album and stack | Pass |
| AC15 | Script | S4: published assets are marked in the Import window (4 marked, none selectable). `RemoteReviewFixTests` `selectAllRule`. Seen after a Rescan; marks changing in a listing already loaded were not driven; ⌘A could not be sent (no key window) | Pass |
| AC16 | Script | S5: a person's Stop, a 429 retried, one 400 among good photos, a rejected key and a dropped connection. S6: the quit question, Keep Publishing, Stop and Quit. Runs `faults`, `lostConnection`, `personsStop`. Temporary folder and originals: above | Pass |
| AC17 | Person | P7: the owner ran it, publishing to their own Immich server, and answered "Yes, it worked" (2026-11-26) | Pass |
| AC18 | Script | S2: a local http server saved once, published with no second question, "Not encrypted" shown. S8 and T: an https server publishes and shows no such line (snapshot looked at) | Pass |
| AC19 | Script | S3: from both hosts, a new address on a server with records warns; a name only, the same address spelt differently, and a server with neither don't. W1: the warning for a server with an import link | Pass |
| AC20 | Test | Runs `stepsFollowEachUpload` (a completed photo is in the album and stacked when the run is stopped on the next one's upload); with the album and stack steps deferred to the end of a run it fails (4 issues). S5: Stop partway, the two recorded photos are in the album | Pass |
| AC21 | Script | Runs `lostConnection`, `personsStop`, `stopDuringRetryCheck`, `stopInsideRetryJobBeforeFirstPhoto`; Boundaries `retryAndLaterRuns`, `retryNothingLeftAfterLaterRun`. S6: Stop during a retry's check sent nothing and left message and results as they were, the next retry sent the unreached; the address-changed and server-removed refusals. S7a: "A publish is already running." S5: after the person's Stop no Retry for unreached photos | Pass |
| AC22 | Script | By reading: `docs/USER_GUIDE.md` (including this pass's new import-section sentences against W1 to W5), design §4.1's strings (String Catalog unchanged since the first pass's script check), `Info.plist`'s local network text read from the built bundle. Left, as R27 assigns it: README line 66 still says the app only reads (Ship). The `CLAUDE.md` Network rule and table-list addition were approved by the owner on 2026-11-26 | Pass |
| AC23 | Script | Runs `endingRecordsAnAnswer` (answered within the bound: recorded), `endingGivesUpAtTheBound` (no answer: ends once the bound has passed, no record, not published), `notFullySentCancelledAtOnce` (never left to wait; ends before the bound), `stopKeepsEndingInEveryReport`. The quit clause has no unit test: S6 (Stop and Quit with no answer) and S7a (a quit while ending asked nothing and waited), at c2ea497; S5: "Stopping. Waiting for “Home” to answer…", Stop dimmed. See **AC23 after the CI fix** | Pass |
| AC24 | Test | Runs `lostAlbumCreate`. S4: with the create's answer lost, one create per new album | Pass |
| AC25 | Script | Boundaries `purposes`. S3: two permissions saved from Publish, refused from Import, **Can't Import from Home** (snapshot looked at), a key lacking `asset.read` refused from Publish, Album and Stacking name their permissions | Pass |

Counts: passed by test 10 (AC6, 7, 8, 9, 10, 11, 12, 14, 20, 24), passed by
script 14 (AC1, 2, 3, 4, 5, 13, 15, 16, 18, 19, 21, 22, 23, 25; AC22 partly by
reading), passed by a person 1 (AC17, the owner), open 0, failed 0.

Also shown by script, beyond the criteria: an untrusted and a changed
certificate in the publish sheet with **Review Certificate…** and Publish dimmed
(S8; snapshots looked at); D-15's line with the Skip or New Copy question given
up and D-16's end state (S7b); a long server address cut in the middle (L;
snapshot looked at); the main page, folder map and results sheets with the window
asked down to 600 × 400 points (S13; the window clamps and the sheet kept its
ideal height, so the smallest window stays with P2).

## AC23 after the CI fix

At 9d6336a, with Q8's row brought to c7e8576. CI failed two wall-clock bounds
in these tests; they now assert events and order, and `endingWaitsForFullySent`
is two tests. The source change is a seam: `RemoteUploadEnding` takes its wait
for the deadline as an internal closure (default: the same `Task.sleep`),
`end(_:)` sets the deadline first as the old call site did, still cancels a body
not fully sent at once and still starts the same detached wait for a fully sent
one; `PublishJob` has an internal hook only the tests set. Each test was read,
and run in a scratch copy of HEAD outside the checkout against one change to the
sources at a time. Unmutated, the five tests passed (2.2 s, at 9d6336a). Since
then only `notFullySentCancelledAtOnce` has changed.

| Clause of AC23 | Test | With the behaviour broken | Result |
|---|---|---|---|
| Stop, then the answer within the bound: a record | `endingRecordsAnAnswer` | A fully sent upload cancelled at once: not accepted, not recorded. The record written inside the run's cancelled task: not recorded. The run made to wait out the bound after the answer: 2 issues, after 60 s | Pass |
| No answer: the run ends once the bound passes | `endingGivesUpAtTheBound` | The deadline never cancels: 3 issues, after 121 s (the request timeout ended it). The deadline doubled: its deadline check fails. A fully sent upload cancelled at once: no wait asked for | Pass (one limit, below) |
| ...with no record and the photo counted as not published | `endingGivesUpAtTheBound` | A given-up upload counted as failed: not pending, not counted as not published. The absence of a record is asserted directly | Pass |
| A quit during the wait behaves the same | None (the quit path is in the app, which has no test target) | By reading `applicationShouldTerminate` and `PublishModel.waitUntilDone`, unchanged since c2ea497 (`git diff`), so S6 and S7a hold | Pass |
| An upload not fully sent is cancelled without waiting | `notFullySentCancelledAtOnce` | Left to wait for the deadline as a fully sent one is: 2 issues (a wait asked for, an answer reported awaited; run at 9d6336a, those assertions unchanged). Made to wait outside the injected wait: 1 issue, `endedAt < stoppedAt + bound` (c7e8576; passed before the fix) | Pass |

The other tests of that row and the fix:

- `stopKeepsEndingInEveryReport` (unchanged) fails with a fully sent upload
  cancelled at once (1 issue: no report says an answer is awaited).
- `personsStop` (AC21's row, rewritten to hold its first answer until the Stop)
  fails with the next photo started after a Stop (5 issues), with a fully sent
  upload cancelled at once (5) and with the record written inside the cancelled
  task (2).
- The tests' client timeout went from 5 s to 120 s, in the test fixture only.

One limit, no change asked: in `endingGivesUpAtTheBound`, a cancel made 8 s
after the deadline passes (run at 9d6336a). Nothing bounds how late the run ends
short of the 120 s request timeout; the old `< 6 s` did, and a tight bound is
what failed on CI. S6 saw the app quit about 10 s after Stop and Quit.

Not repeated here: repeated or loaded runs for flakiness (`status.md`, **CI fix
(PR #307)**, **C15** and **Q8**; `code-review.md`, ninth to eleventh passes) and
the Xcode 26.3 build (recorded in `status.md` under **Build and test**, the Q8
rows).

## Changed since the first pass

Source and tests from e23d1ea to 0eac173. "Mutation" is the change made to a
scratch copy; every named test passes unchanged.

| Behaviour | How | Evidence | Result |
|---|---|---|---|
| Q1: album and stack steps follow each upload | Test | See AC20 | Pass |
| Q2: Check Originals' tally | Test | See AC12 | Pass |
| Q3: scripted `quit` with a publishing sheet up | Script | S7e (Server sheet up), S7g (publish sheet up), S7h (results up) each quit by themselves; before, S7e and S7g were killed | Pass |
| Q4: the script prints the failed check's own words | Script | S7b and L print **The key couldn't be read**; L's snapshot shows the same | Pass |
| Publishing never pairs a key with another address than its row's (security N7) | Test | `PublishKeyPairingTests` `staleRecordNeverPaired`, `waitsForTheRow`, `checkDuringSave`, `saveHoldsTheGate`. Mutations: row ignored, and gate removed, each 7 issues across these and the import tests. W6: Publish with a stale record sent nothing and showed D-15's line | Pass |
| D-17: Retry Failed whose server changed or was removed as its check starts, or whose catalog can't be read, is called off | Test | `PublishJobTests` `retryCalledOffWhenServerChanged` (real `PublishConnection.connect`; each case asserted, `.calledOff`, no request, no job built, run unchanged). Mutations: the whole case ends the run, 6 issues; `.changed` alone, 4; `.unreadable` alone, 2. Not reachable by script or by hand (an instant) | Pass |
| D-18: the Import window follows a server saved from Publish | Script | `ServerKeyPairingTests` `importCheckWithSavedRow`, `importCheckWaitsForTheRow`, `sourceFollowRule` (certificate and running import ignored: 5 issues). W1: rename in place, nothing requested by the window, selection, album and typed project kept; address change: reload, selection and album gone, every later request to the new address. W2: during an import nothing moves, originals keep coming from the old address, then the window follows and keeps "Imported 6 photos". W4: follows while closed. Not raising the window or moving the keyboard: P8 | Pass |
| D-19: a Server sheet behind the saved server | Script | `ServerKeyPairingTests` `sheetBehindAtPress`, `sheetBehindAtSave`, `sheetKeyChangedAtSave`, `sheetUpToDateAndTypedKey`, `sheetRemovedAtSave`, `sheetSaveHoldsTheGate` (save unguarded: 2 issues). W3: the publish sheet's own Server sheet stale (not driven before): nothing sent to the typed address, nothing written, publish sheet back with Home as saved, checked again, album, Archive and description kept, no D-15 line, nothing published; the Import window's sheet stale: the same, no write; a name-only Save from a stale sheet renames and keeps the other address (D-16). W5: the import grid then has the keyboard. T: Trust Certificate with the key field empty saves a new address | Pass |
| F30: a rename during the import window's check stays | Test | `checkKeepsARenameTakenMeanwhile` (revision ignored: 2 issues). W4 | Pass |
| F31: cell tooltips follow a rename | Script | W1 and W4: the tooltip on a marked cell reads the new name. No test target for it | Pass |
| F32, F33: user guide | Reading | The new import-section sentences agree with W1 to W5; the stale-sheet sentence is to be read with the sentence before it (a name-only Save still saves the name) | Pass |
| C14: a sheet check that ends on a change is checked again | Test | `checkLeftWaitingIsRechecked` (nothing recorded: 4 issues). W6, observed in part: with the scratch catalog changed from outside the app, choosing the server leaves **Checking…** and sends nothing; closing the sheet's own Server sheet then checks the new address and passes. The in-app order (a Save landing while a check waits for the key) can't be scripted | Pass |
| The import connection code that moved (add, trust, changed and untrusted certificate, missing permissions, rename, removal) | Script | `RemoteConnectionTests` and the whole run; S3, S8, T, W3 | Pass |

## Findings

No failure of the app was found. No finding is open. The history of Q1 to Q8 is
under **Follow-up**.

**Q8 (minor, test strength; opened 2026-11-26 at 9d6336a). Fixed in 5412951,
confirmed 2026-11-27 at c7e8576.** `notFullySentCancelledAtOnce` caught an
upload that was not fully sent only if it was left waiting through the injected
wait. The test now has a 60 s bound and expects the upload to have ended before
the bound after a clock read taken just before `task.cancel()`.

- Mutation, in a scratch copy: in `RemoteUploadEnding.end`, the branch for a
  body not fully sent cancels from a detached task after
  `await Self.sleep(until: deadline)` instead of at once, still returning false.
- With it: 1 issue, "the upload waited for the bound"
  (`endedAt < stoppedAt + bound`, `PublishJobTests.swift` line 860), after 61.0 s.
- Unmutated, and with the source restored and compared with the checkout's:
  passed in 0.26 s.

## Known issues

- **#303 (security N9, Low; the owner chose a follow-up).** The Keychain item
  does not record the address a key was saved for. A copy of a library shares
  its keys with the original (editing or removing the server in one reaches the
  other, and the other copy can send the new key to the old address); a second
  app process on one library bypasses the in-process pairing; a failed rollback
  can leave half a Save. Related, seen in W6: a server changed by another
  process posts nothing to an open publish sheet, which can stay at
  **Checking…** until its Server sheet is closed or it is reopened.
- #301: the Import window's Date Range button stays dimmed after a server
  connects (S9 and S9b, recorded at e23d1ea, not rerun).
- #302: the same unchanged photo can export to different bytes after a relaunch,
  so **New Copy** can add a second copy instead of "already on the server".
- From the reviews, not filed as issues yet: the publish sheet keeps an earlier
  check after its own Server sheet is cancelled, and **Check Originals** there
  still asks the earlier address; a name-only Save whose catalog write fails
  says nothing (`review.md`, Follow-ups).
- Accepted: a typed key from a stale Server sheet goes to the address that sheet
  shows (security N10, D-19); a removal doesn't stop a use already under way
  (N8).

## Scripts

Each was run as `<copy>/Contents/MacOS/Gus --library-root <scratch library>
--debug-script "<script>"`. `$QA` stands for the session's scratch folder. Each
library is a copy of one made with `photobench generate --jpeg 5 --dng 1 --heic 1
--pairs 1 --videos 1` into `$QA/photosA` and `photobench import`, with GPS, a
title, a description, a keyword and an offset added to `IMG_00001.JPG` by
exiftool before the import, and then `photocli develop --set exposure.ev=…` on
versions 1 to 3, `rate` 4 on 1 and 2, `flag` picked on 2 and `label` red on 3.
An address `http://127.0.0.1:472xx` is the recording relay in front of the fake
server; to rerun without a relay, type `fake` in its place (S8 and T need a TLS
relay). S9 and S9b are listed for #301 and were not rerun.

### S1

Pristine library A (settled). Showed: Add from the import window, import two photos, duplicate, new album, folder map, Check Originals 3 of 3; 2 published, 1 already on the server, 3 stacked; Cancel and Skip sent no write; New Copy with Archive and a description, then All except location, Copyright and None. (`import key cmd+a` is not a known command and did nothing.)

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

A fresh copy of the library as imported. Showed: Exactly R8's permissions: 2 of 2 found and stacked, album made; published assets **Already in the library**; a refused stack, Retry Failed, one upload; lost album answers, one create per album. (`import menukey a` did nothing: no key window.)

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

The same library, relaunched. Showed: the key can't be read (it was in memory); after it is entered again the question counts the 8 recorded photos; D-15's line and no run; D-16: Save after removal leaves no server.

```text
wait 3; sidebar all; import server fake start 2; import server fake fault permissions all; selectall; publish sheet; wait 1; publish serversheet edit; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album none; publish stacking off; publish start; publish answer cancel; publish start; import open; wait 1; import server select Home; import server sheet edit; import server sheet field address http://localhost:47287; import server sheet field key fake; import server sheet confirm on; wait 1; import server sheet submit; wait 3; publish print; publish answer newcopy; publish job; publish serversheet edit; import server remove Home; import server confirm yes; publish serversheet field name Renamed; publish serversheet submit; wait 2; publish print; import server list; import server fake requests; publish cancel; quit
```

### S7c

Quit with the sheet up and no server saved. Showed: Quit.

```text
wait 3; sidebar all; focus IMG_00001; publish sheet; quit
```

### S7e

The first pass's combined scenario, ending with the publish Server sheet up. Showed: Quit by itself (15 s); killed at e23d1ea (Q3).

```text
wait 3; sidebar all; focus IMG_00001; import server fake start 2; import server fake fault permissions all; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address fake; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album none; publish stacking off; publish start; publish wait; import open; wait 1; import server sheet add; import server sheet close; import server select Home; import server sheet edit; import server sheet close; publish sheet; publish serversheet edit; publish serversheet print; quit
```

### S7f

The same, sheet closed first. Showed: Quit.

```text
wait 3; sidebar all; focus IMG_00001; import server fake start 2; import server fake fault permissions all; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address fake; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 2; publish album none; publish stacking off; publish start; publish wait; import open; wait 1; import server sheet add; import server sheet close; import server select Home; import server sheet edit; import server sheet close; publish sheet; publish serversheet edit; publish serversheet close; wait 1; publish print; publish cancel; quit
```

### S7g

Quit with the publish sheet up after a run. Showed: Quit by itself (11 s); killed at e23d1ea (Q3).

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

Recorded at e23d1ea for #301, not rerun. Showed: Date Range dimmed 6 s and 22 s after connecting, enabled only after the date range changed.

```text
wait 3; import server fake start 4; import server fake fault permissions all; import open; wait 1; import server add Home fake; wait 5; import server print; import snapshot $QA/shots/I1-connected.png; wait 15; import snapshot $QA/shots/I2-connected-later.png; import dates 2026-01-01 -; wait 1; import dates clear; wait 2; import server print; import snapshot $QA/shots/I3-after-dates.png; quit
```

### S9b

Recorded at e23d1ea for #301, not rerun. Showed: Still dimmed after an album change, Rescan and a checked photo.

```text
wait 3; import server fake start 4; import server fake fault permissions all; import open; wait 1; import server add Home fake; wait 3; import album Trip; wait 3; import snapshot $QA/shots/I4-after-album.png; import rescan; wait 4; import snapshot $QA/shots/I5-after-rescan.png; import toggle 0; wait 2; import snapshot $QA/shots/I6-after-check.png; menuitems Date Range; quit
```

### S11

One imported photo beside the local ones. Showed: Check Originals 1 of 9, nothing uploaded; the run: 1 stacked, 8 not, same reasons.

```text
wait 3; import server fake start 2; import server fake fault permissions all; import open; wait 1; import server add Home http://127.0.0.1:47291; import dest $QA/importedK; import toggle 0; import run; wait 2; import close; wait 1; sidebar all; wait 1; selectall; wait 1; print selection; publish sheet; publish album none; publish stacking on; publish originals; import server fake requests; publish start; publish wait; publish results; publish results close; quit
```

### S13

Window asked down to 600 × 400. Showed: Snapshots of the main page, its foot, File Settings, folder map and results.

```text
wait 3; windowsize 600 400; wait 1; import server fake start 4; import server fake fault permissions all; import open; wait 1; import server add Home fake; import close; wait 1; sidebar all; selectall; publish sheet; wait 1; snapshot $QA/shots/S1-small-main.png; publish scroll bottom; snapshot $QA/shots/S2-small-bottom.png; publish settings open; wait 1; snapshot $QA/shots/S3-small-settings.png; publish settings cancel; publish map open; publish map add $QA/photosA /mnt/media/photos/; wait 1; snapshot $QA/shots/S4-small-map.png; publish map done; publish start; publish wait; publish results; wait 1; snapshot $QA/shots/S5-small-results.png; publish results close; quit
```

### W1

A rename, then an address change, saved from Publish with the Import window open on that server. Showed: the rename in place (Trip, 2 of 4 selected, typed project name, tooltip reads Cellar; only the publish sheet's own requests); the address change warns, reloads the window (All Photos, nothing selected, project Cellar - All Photos) and sends every later request to `localhost`.

```text
wait 2; import server fake start 12; import server fake fault permissions all; import open; wait 1; import server add Home fake; import toggle 0; import dest $QA/dest-R1; import run; wait 2; import album Trip; import toggle 1; import toggle 2; import server project Typed name; import server print; import grid; sidebar all; wait 1; selectall; publish sheet; publish album new Kept; publish show archive; publish description Kept words; publish serversheet edit; publish serversheet field name Cellar; import server fake mark; publish serversheet submit; wait 3; publish print; import server list; import server print; import grid; import server fake requests since; publish serversheet edit; publish serversheet field address fakehost; publish serversheet confirm on; publish serversheet print; import server fake mark; publish serversheet submit; wait 4; publish print; publish serversheet print; import server list; import server print; import grid; import server fake requests since; publish cancel; wait 1; quit
```

### W2

The address saved from Publish during an import. Showed: the window stays on 127.0.0.1 at 0/6 and 2/6, all six originals come from 127.0.0.1, then it follows to `localhost`, subtitle Imported 6 photos.

```text
wait 2; import server fake start 30; import server fake fault permissions all; import open; wait 1; import server add Home fake; import toggle 0; import toggle 1; import toggle 2; import toggle 3; import toggle 4; import toggle 5; import dest $QA/dest-R2; sidebar all; wait 1; selectall; publish sheet; import server fake fault slow 2000; import server fake mark; import start; wait 1; import server print; publish serversheet edit; publish serversheet field address fakehost; publish serversheet confirm on; publish serversheet submit; wait 1; publish print; import server list; import server print; import server fake requests since; import server fake mark; wait 18; import server print; import print; import server fake requests since; publish cancel; quit
```

### W3

Stale Server sheets. (a) Publish's own sheet behind the saved server: nothing sent to 127.0.0.2, name not written, publish sheet back on Home at `localhost`, checked, album, Archive and description kept, no D-15 line, no run. (b) The Import window's sheet behind: the same, saved server unchanged. (c) A name-only Save from a stale sheet: renamed, other address kept.

```text
wait 2; import server fake start 12; import server fake fault permissions all; import open; wait 1; import server add Home fake; sidebar all; wait 1; selectall; publish sheet; publish album new Kept; publish show archive; publish description Kept words; publish serversheet edit; import server sheet edit; import server sheet field address fakehost; import server sheet confirm on; import server sheet submit; wait 2; import server list; publish serversheet print; publish serversheet field address http://127.0.0.2:9; publish serversheet field name From the stale sheet; publish serversheet confirm on; import server fake mark; publish serversheet submit; wait 4; publish serversheet print; publish print; import server list; import server print; import server fake requests since; publish job; publish activity; publish cancel; wait 1; import server sheet edit; publish sheet; publish serversheet edit; publish serversheet field address fake; publish serversheet confirm on; publish serversheet submit; wait 2; import server list; import server sheet print; import server sheet field address http://127.0.0.2:9; import server sheet field name From the stale import sheet; import server sheet confirm on; import server fake mark; import server sheet submit; wait 4; import server sheet print; import server list; import server print; import server fake requests since; publish cancel; wait 1; publish sheet; publish serversheet edit; import server sheet edit; import server sheet field address fakehost; import server sheet confirm on; import server sheet submit; wait 2; publish serversheet field name Renamed from stale; import server fake mark; publish serversheet submit; wait 4; publish print; import server list; import server print; import server fake requests since; publish cancel; quit
```

### W4

A rename during a held import check, then an address change with the Import window closed. Showed: Attic stays during and after the check, tooltip reads Attic; with no grid shown the window still follows to `localhost`.

```text
wait 2; import server fake start 12; import server fake fault permissions all; import open; wait 1; import server add Home fake; import toggle 0; import dest $QA/dest-R4; import run; wait 2; import grid; sidebar all; wait 1; selectall; publish sheet; import server fake fault slowcheck 6000; import server rescan; wait 1; publish serversheet edit; publish serversheet field name Attic; publish serversheet submit; wait 1; import server print; wait 9; import server print; import server list; import grid; import server fake fault slowcheck 0; import close; wait 1; import grid; publish serversheet edit; publish serversheet field address fakehost; publish serversheet confirm on; import server fake mark; publish serversheet submit; wait 4; import server print; import server fake requests since; import open; wait 2; import server print; publish cancel; quit
```

### W5

The Import window's stale sheet again, printing the grid. Showed: first responder false before, true after the sheet closed.

```text
wait 2; import server fake start 8; import server fake fault permissions all; import open; wait 1; import server add Home fake; sidebar all; wait 1; selectall; import server sheet edit; publish sheet; publish serversheet edit; publish serversheet field address fakehost; publish serversheet confirm on; publish serversheet submit; wait 2; publish cancel; wait 1; import grid; import server sheet field address http://127.0.0.2:9; import server sheet confirm on; import server fake mark; import server sheet submit; wait 4; import server sheet print; import server list; import grid; import server fake requests since; quit
```

### W6

The saved address changed outside the app: when the app first prints `import server fake mark`, run `sqlite3 <library>/Library/catalog.sqlite "UPDATE remoteService SET address = replace(address, '127.0.0.1', 'localhost')"` (scratch library only). Showed: Publish refused with D-15's line, no request, no run; choosing the server again leaves Checking… with no request; after its Server sheet is opened and closed the new address is checked and passes.

```text
wait 2; import server fake start 4; import server fake fault permissions all; sidebar all; wait 1; selectall; publish sheet; publish serversheet add; publish serversheet field name Home; publish serversheet field address fake; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit; wait 3; publish album new Kept; publish description Kept words; publish print; import server fake mark; wait 3; publish start; publish print; publish job; import server fake requests since; import server fake mark; publish server Home; publish print; import server list; import server fake requests since; wait 3; publish print; publish serversheet add; wait 1; publish serversheet close; wait 5; publish print; import server fake requests since; publish job; publish activity; publish cancel; quit
```

### T

The relay speaks TLS with a throwaway certificate on port 47295. Showed: certificate trusted; with the key field empty, a new https address goes through the certificate page, Trust saves it, the Import window and the publish sheet use it, and a photo publishes.

```text
wait 3; sidebar all; focus IMG_00001; import server fake start 2; import server fake fault permissions all; import open; wait 1; import server sheet add; import server sheet field name Secure; import server sheet field address https://127.0.0.1:47295; import server sheet field key fake; import server sheet submit; import server sheet trust; wait 3; import server list; publish sheet; publish album none; publish stacking off; publish cancel; import server sheet edit; import server sheet field address https://localhost:47295; import server sheet submit; import server sheet print; import server sheet trust; wait 4; import server sheet print; import server list; import server print; publish sheet; publish print; publish start; publish wait; publish results; publish results close; quit
```

### L

A long server address (snapshot looked at: cut in the middle). Two launches; between them run `sqlite3 <library>/Library/catalog.sqlite "UPDATE remoteService SET address = 'https://photos.a-rather-long-host-name-for-the-sheet.example.com:2283/immich/behind/a/reverse/proxy/with/a/long/path'"`.

```text
wait 3; import server fake start 2; import server fake fault permissions all; import open; wait 1; import server add Test fake; import close; quit
```

```text
wait 3; sidebar all; wait 1; selectall; publish sheet; snapshot $QA/shots/L1-long-address.png; publish cancel; quit
```

## For a person

**Status at sign-off (2026-11-26, e73cb45).** P7 is done: the owner ran it and
answered "Yes, it worked". P1 to P6 and P8 were not recorded one by one. The
owner named no check as left open. The steps below are kept as they were given.

**Before you start (known issue #303).** Do not try this branch on a copy of your
real library while your real server is saved in that copy or in the original, and
don't run two copies of the app on one library: the copies share the server's
Keychain key. The steps below use new scratch libraries. (The branch also
migrates a library, which can't be undone.)

**What matters most.** **P7 is essential** (AC17, publishing to your own server,
the one criterion no test or script could verify): do it first. Next P8, P5 and P3 (keys, window
focus and sheet changes that scripts could not fully drive). P6 is mostly
scripted; P1, P2 and P4 are by eye. This is the whole list; you may sign off with
checks left open by naming them.

The one decision besides the checks is made: on 2026-11-26 the owner approved the
proposed `CLAUDE.md` Network rule in `status.md` and the catalog table-list
addition as written, to be committed on this branch before the pull request (R27).

### Setup

Quit your installed copy first, if you have one: `build/Gus.app` shares its
preferences. Never open the bundle without `--args --library-root …` (a bare
`open` or a double-click opens your real library). Quit the app before each next
launch.

Build and make three scratch libraries (if `~/gus-signoff-28` is left from an
earlier try, delete it first):

```zsh
cd /Users/randy/Projects/Gus
Scripts/build-app.sh
swift run -c release photobench generate --output "$HOME/gus-signoff-28/photos" --jpeg 8 --dng 2 --heic 1 --pairs 1 --videos 1
swift run -c release photobench import --library-root "$HOME/gus-signoff-28/library" --source "$HOME/gus-signoff-28/photos"
swift run -c release photobench import --library-root "$HOME/gus-signoff-28/library-held" --source "$HOME/gus-signoff-28/photos"
swift run -c release photobench import --library-root "$HOME/gus-signoff-28/library-keys" --source "$HOME/gus-signoff-28/photos"
```

### P7 (AC17, M7): your server

This launch uses the real identifier, so the key goes into your Keychain (as a
new item) and preferences are shared with your installed app; the library is a
new, empty scratch one.

```zsh
cd /Users/randy/Projects/Gus
mkdir -p "$HOME/gus-signoff-28/library-real"
open -n build/Gus.app --args --library-root "$HOME/gus-signoff-28/library-real"
```

Give the Import window a destination inside `~/gus-signoff-28`, not a folder
Immich or your real library uses. macOS may ask about the local network (read
that text) and about the Keychain.

1. In Immich, pick one external-library photo and one uploaded photo that already
   have a title or description and keywords (so you add none in the app: that
   writes `.xmp` sidecars beside the originals if sidecar writing is on, and
   Immich may read them; exposure changes don't). Put one of the two in a stack
   with some other test photo, not on top if you want the stronger case. Use
   photos and stacks you can afford to rearrange.
2. File ▸ Import: add your server there with a key holding import's five
   permissions (`asset.read`, `asset.view`, `asset.download`, `album.read`,
   `user.read`) plus `asset.upload`, `albumAsset.create`, `album.create` and
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
   description and keywords read as expected; both are in the album. An https
   server shows no **Not encrypted** line.
7. Optional: publish one again as **New Copy** at Copyright and contact only (the
   date and time should still be the capture's).
8. Optional, the rest of M6: publish a large photo and press **Stop** while it
   renders (**Stopping…** until the render returns); after a run, **Rescan** in
   the Import window shows the uploads **In Library**. With a certificate macOS
   doesn't trust, **Review Certificate…** swaps sheets and comes back.
9. Afterwards delete the test uploads and the album in Immich by hand (the app
   never deletes), unstack what you stacked, and use Remove Server… to take the
   key out of the Keychain.

If something looks wrong, these are expected:

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
- Creating a stack replaces the one it joins, and members in Immich's trash drop
  out of it (documented). Archive takes the original out of the timeline.
- Publishing the same photo again may add a second copy rather than say it is
  already there (#302).

### Session A: P1, P2, P3, P4, P8, then P5

These and the next two sessions use only the app's fake server. In all three
don't rate, edit or duplicate photos: a script launch turns undo grouping off,
and an edit by hand can crash the app. Publishing is safe.

A fake server named **Test** is already added. Its key stays in memory, so keep
this one running through P8 and P5 (which removes the server). If a sheet asks
for the key, it is `fake-key-0123456789`.

```zsh
cd /Users/randy/Projects/Gus
open -n build/Gus.app --args --library-root "$HOME/gus-signoff-28/library" --debug-script "wait 3; import server fake start 12; import server fake fault permissions all; import open; wait 1; import server add Test fake; import close"
```

- **P1 (M3). Menus and toolbar.** File menu (Publish… ⌥⌘E, Publish Results…,
  Stop Publishing: order and dimming), a photo's context menu, the toolbar's
  Publish in the default set, Customize Toolbar and the overflow menu.
- **P2 (M1). Look.** Select All, ⌥⌘E. The three pages (main, Edit Settings…,
  Edit Folder Map…) and, after a run, the results, at the smallest window, also
  with Increase Contrast.
- **P3 (M2). Keyboard only.** From ⌥⌘E through every control.
  - Press **Return** right after the check finishes, with no click first: it
    publishes (or, for photos already published, asks Skip or New Copy).
  - In Description try Return and Option-Return and note what Return does
    (publishing, a new line or nothing are all acceptable).
  - In the folder map, **Add Folder…** through the real panel: the server field
    has the keyboard. Type `/mnt/media/photos`, edit its middle, paste a path
    ending in `/`.
  - After the sheet closes, focus is back on the grid.
- **P4 (M4). Mouse.** The Album pop-up ticks the current choice. Add Server…,
  Edit “Test”… and Cancel swap sheets and keep your choices and description. In
  Edit Settings…, choose a watermark PNG, delete that file in the Finder, reopen
  the sheet, choose a file at the same place again: the warning clears. The
  dimmed **New Album…** is in session C.
- **P8 (M8). The same server in both windows.** Open File ▸ Import first. The
  server's two spellings are `127.0.0.1` and `localhost`: keep the port, tick the
  unencrypted notice, leave the key field empty.
  1. With the Import window behind the library window: File ▸ Publish…, Server ▸
     **Edit “Test”…**, change the spelling, **Save**. The Import window does not
     come forward and the library window keeps the keyboard (Esc closes the
     publish sheet). Brought forward, the Import window shows the new address.
     Repeat with the Import window minimized and with it closed.
  2. Open the server's sheet in both windows (the publish sheet's **Edit
     “Test”…**, and File ▸ Edit Server… with the Import window in front). In one,
     change the spelling and **Save**. In the other, change the address to
     `http://localhost:9`, tick the notice and **Save**: it closes with no alert
     and the first sheet's address stays. When the second sheet is Publish's, the
     publish sheet comes back with Test chosen, your album and description kept
     and no line under Server; when it is Import's, the arrow keys move in the
     grid. Do it once each way round. (If the second sheet changes only the name,
     the name is saved and the other address kept.)
- **P5 (M5). Question and results.**
  1. Publish one photo twice, then several: read the Skip or New Copy wording.
     **Return** is Skip; **Esc** returns.
  2. With the question up, in the Import window change Test's address to the other
     spelling and Save: the question closes, the sheet says **This server's
     address or certificate changed. Nothing was published.**, and Activity shows
     no new run.
  3. With the question up again, note the port, then remove the server in the
     Import window: the question closes.
  4. Add it again there at the same address and port with the test key. Open
     **Edit “‹name›”…** from Publish, remove that server in the Import window,
     change the name and Save: the sheet closes once and Publish comes back with
     **This server was removed.** (or the empty state if it was the last).
  5. In results: Return and Esc close; the Run pop-up; selecting a reason's text.

### Session C: the rest of P4

The key lacks `album.read`; the publish sheet is already open:

```zsh
cd /Users/randy/Projects/Gus
open -n build/Gus.app --args --library-root "$HOME/gus-signoff-28/library-keys" --debug-script "wait 3; import server fake start 12; import server fake fault permissions asset.upload,asset.read,albumAsset.create,album.create,user.read,stack.create; sidebar all; selectall; publish sheet; publish serversheet add; publish serversheet field name Test; publish serversheet field address fake; publish serversheet field key fake; publish serversheet confirm on; publish serversheet submit"
```

Open the Album pop-up: **New Album…** is dimmed, with **Albums need album.read on
this key**.

### Session B: P6

The server takes uploads and never answers:

```zsh
cd /Users/randy/Projects/Gus
open -n build/Gus.app --args --library-root "$HOME/gus-signoff-28/library-held" --debug-script "wait 3; import server fake start 12; import server fake fault permissions all; import open; wait 1; import server add Test fake; import close; import server fake fault hold on"
```

- **P6 (M6). A run in progress.**
  1. Publish a few photos. Look at Activity's row. ⌘Q asks **Quit While
     Publishing?**; Return and Esc keep publishing.
  2. While it runs, the Import window's Edit Server… and Remove Server… for Test
     are dimmed.
  3. **Stop**: **Stopping. Waiting for “Test” to answer…** for about 10 seconds,
     Stop dimmed, then the message with **Show Results…**.
  4. Publish again, **Stop**, and ⌘Q during the stopping time: no question, the
     app quits when the wait ends.

When you are done, quit the app and delete `~/gus-signoff-28`.

## How the sign-off commands were checked

At c2ea497 the five blocks were taken from this file and run in zsh, with
`$HOME/gus-signoff-28` replaced by a scratch folder, `open -n build/Gus.app
--args` by the executable of a scratch copy of the bundle the first block built
(nothing was activated), and `quit` appended. All five exited 0. Session A added
Test and its check passed; session C showed **New Album…** dimmed with "Albums
need album.read on this key"; session B, driven on by script, showed the quit
question (Keep Publishing the default), **Stopping. Waiting for “Test” to
answer…** with Stop dimmed, and the stopped message. P7's launch was tried with a
scripted `quit` and the scratch copy's identifier; the real-identifier launch,
the Keychain and your server were not touched. At 0eac173 the blocks are
unchanged (only their order here), nothing they build or launch has changed, and
they were not run again: each passes `zsh -n`, none holds a comment line, and
every launch passes `--library-root`.

Not asked of you because scripts cover them: a long server address cut in the
middle (M1; L), an **In Library** tooltip naming a renamed server (M8; W1, W4)
and Stop while a retry checks a slow server (M6; S6).

## Safety of these runs

Fifth pass (c7e8576): the app was not launched and `open` was not run; only
builds and unit tests, once in the checkout and then in a scratch copy of HEAD
outside it (built from the checkout's already fetched dependencies; the mutated
source restored, its `Sources` and `Tests` compared with the checkout's
afterwards). The live-server tests were skipped (their variables unset), so no
server but the tests' fake ones was contacted, and the Keychain was not used.
The pull request and its CI runs were read with `gh`, nothing written. The
owner's library folder had no file newer than the start of the pass, and no
instance of the app was running when checked after the runs.

Fourth pass (9d6336a): the app was not launched and `open` was not run; only
builds and unit tests, once in the checkout and then in a scratch copy of HEAD
outside it (built from the checkout's already fetched dependencies; its sources
restored and compared with the checkout's afterwards). The live-server tests were
skipped (their variables unset), so no server but the tests' fake ones was
contacted, and the Keychain was not used. The owner's library folder had no file
newer than the start of the pass, and no instance of the app was running
afterwards.

Third pass (0eac173): the app was not launched and `open` was not run; only
builds and unit tests, in the checkout and in a scratch copy of HEAD outside it
(built offline from the checkout's already fetched dependencies). No server but
the tests' fake ones was contacted, and the tests use no Keychain item. The
owner's library folder had no file newer than the start of the pass, and no
instance of the app was running afterwards.

Second pass (c2ea497): every launch was the executable of a copy of the bundle
(or a unit test), with `--library-root` on a scratch library; nothing was opened
with `open`, activated or brought forward. No instance or relay was left running;
the owner's library folder had no file newer than the start of that pass; the
scratch copy's preferences were removed. The Keychain was not read (a script
launch keeps keys in memory), no server but the app's fake one was contacted, and
Docker was not used. The publishing temporary folder is shared by every copy of
the app (it is named from the fixed bundle identifier). The first run of S11 and
S13 still pointed at the first pass's scratch folder and wrote snapshots and two
imported files there; both were rerun with that pass's paths.

Of the checkout, each pass changed only this file (the build folders aside).

## Follow-up

2026-11-26, rerun at c2ea497 after the fix rounds:

| Finding | Result |
|---|---|
| Q1 missing test, AC20 | Fixed: `stepsFollowEachUpload`, fails with the steps deferred |
| Q2 missing test, AC12 | Fixed: the tally moved to PhotoCore, `originalsTallyMatchesRun` and `originalsTallyFailureAndCancel` |
| Q3 scripted `quit` with a publishing sheet up | Fixed (S7e, S7g, S7h) |
| Q4 script words differ from the sheet's | Fixed (S7b, L) |
| Q5 Date Range dimmed (#271's code) | Filed as #301; not fixed here |
| Q6 export bytes differ between launches | Filed as #302; the user guide and `status.md` no longer promise identical bytes; not fixed here |
| Q7 missing test, D-17 | New in that pass: nothing failed if `PublishRetry.perform` ended the run instead of calling a retry off on `.changed` or `.unreadable` |

2026-11-26, confirmation at 0eac173:

| Finding | Result |
|---|---|
| Q7 missing test, D-17 | **Fixed** (21bdca7, test only): `PublishJobTests` `retryCalledOffWhenServerChanged`. In a scratch copy, the case `.changed, .unreadable` made to set `ended.ending` and return `.checkStopped(ended)` failed it with 6 issues (not called off, and the run replaced, for each of a new address, a removal and an unreadable catalog); `.changed` alone mutated, 4 issues; `.unreadable` alone, 2. The other 104 tests of the publishing and pairing suites passed under every mutation, and all 105 pass unmutated and restored |

2026-11-26, the owner's sign-off, as relayed by the main session:

- The owner signed off in chat ("Signed off") at commit e73cb45. Code last
  changed in 21bdca7 (a test); app source last changed at c2ea497 or earlier.
- Asked separately, the owner answered that they ran P7, publishing to their own
  Immich server: "Yes, it worked". AC17 is verified by the owner.
- P1 to P6 and P8 were not recorded one by one. The owner named no check as left
  open.
- The owner reported no finding.
- R27: asked in chat about the proposed `CLAUDE.md` Network rule and the catalog
  table-list addition, the owner chose "Approve as written". The main session
  commits it to `CLAUDE.md` on this branch.

2026-11-26, confirmation of the CI fix for pull request #307 at 9d6336a (after the
sign-off):

| Item | Result |
|---|---|
| AC23 re-mapped to `endingRecordsAnAnswer`, `endingGivesUpAtTheBound`, `notFullySentCancelledAtOnce` and `stopKeepsEndingInEveryReport` | **Pass** (**AC23 after the CI fix**); full `swift test` 1671 of 1671 |
| Q8, `notFullySentCancelledAtOnce` misses a wait made outside the injected one | Open, minor |
| The owner's sign-off at e73cb45 | Stands: test changes and an internal seam, no behaviour change. No app session, live check or owner check was rerun, and none is newly asked |

2026-11-27, confirmation of Q8's fix at c7e8576:

| Item | Result |
|---|---|
| Q8, `notFullySentCancelledAtOnce` misses a wait made outside the injected one | **Fixed** (5412951, test only). With Q8's mutation in a scratch copy the test fails (1 issue, 61.0 s); unmutated and restored it passes; full `swift test` 1671 of 1671 |
| The owner's sign-off at e73cb45 | Stands: a test change only since 9d6336a. No app session, live check or owner check was rerun, and none is newly asked |
