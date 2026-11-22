# AI masks (Subject, People, Background): QA

Owner: qa-tester. Date: 2026-11-20. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/ai-masks` at `9b50009`, on an Apple M4 Pro, macOS 27.2.1
(26B131), Swift 6.4.2, macOS 27.2 SDK (the bundle records `sdk 27.2`, `minos 15.0`).
Issue: #88. PRD: the issue body, revised 2026-11-20 (R13 and AC11 as ruled).

## Verdict

**Passes, with one finding for the owner's decision and no failures.** All 14
acceptance criteria have a test or a script check and pass; `swift test` is green
(1,305 tests in 185 suites), the bundle builds, the DR-5 cancel rules, the
design-review fixes (F1, F2, N1, flash only on Found) and the migration all behave
as `status.md` says. One literal gap against AC13 (Q1: a preview cached before a
row went missing still shows the mask; known limit, owner to accept or send back).
What is left for a person is looks, the window staying responsive on a large raw,
the menu bar and the eye on edges (P1 to P7). Nothing here says whether the two
requests run on macOS 15 or 26 (AC11 covers CI only; the owner's standing ruling
is that nobody checks those by hand).

Safety: no instance of the scratch copy is still running, and nothing under
`~/Library/Application Support/Gus/Library` is newer than the start of this run
(its newest file, `catalog.sqlite-wal`, is from 16:18 today; this run began at
18:50). Another session was running `swift test` on a different worktree at the
same time; it did not touch my results.

## What was run

- `swift build`: clean (no warnings seen). `Scripts/build-app.sh`: builds
  `build/Gus.app` (`exit 0`).
- `swift test` (whole suite): **1,305 tests in 185 suites passed** in 79.8 s. No red
  test, so no question of the known flake #229 (`DeferredRenderTests`). The AC11
  test printed no "AC11:" line: on this Mac both requests ran, Subject found the
  disc in both orientations, and People found something in a fixture.
- `AI_MASK_SAMPLES` (the owner's scratch photos at `~/gus-scratch/photos/2016-05-21`
  were readable): 7 files, `swift test --filter "MaskDetectionTests/samples"` passes.
  Results match R1: 10M10325.JPG Subject 1 instance 22.9% and People 1 instance
  22.9%; X1000553.JPG/.RAF Subject 1, People 4 (the limit); X1000587.JPG People 4,
  Subject none; 10M10296.JPG/.ORF the flower, People 1 instance at 35.4% / 37.0%
  (the R15 false positive); 10M10287.JPG (landscape) neither, a 1x1 empty result.
  Sizes 512x512 and 512x384 everywhere. (Photos are never committed.)
- Scripted checks on a copy of the bundle (below), always `--library-root` on a
  scratch library from `photobench`, a fresh copy of the library per run (or the
  same library when a run reopens it on purpose).

Setup, all under `.../scratchpad/aim/qa/` of this session:

```zsh
cp -R build/Gus.app qa/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.qaaimasks qa/Gus.app/Contents/Info.plist
codesign --force --deep --sign - qa/Gus.app
swift run -c release photobench generate --output qa/synth-src --jpeg 4
swift run -c release photobench import --library-root qa/lib-synth-master --source qa/synth-src
swift run -c release photobench import --library-root qa/lib-real-master --source qa/photos-real
```

(`photos-real` holds copies of six of the owner's scratch photos: 10M10325, 10M10296,
X1000553, X1000587, 10M10287 `.JPG` and 10M10296 `.ORF`.) Each run:
`qa/Gus.app/Contents/MacOS/Gus --library-root <fresh copy of the master library> --debug-script "<script>; quit"`.
The debug script's `adjust mask detector disc|empty|fail|unavailable|hang` stands in
for Vision where a state can't be made with a synthetic photo; runs with
`detector real` (the default) used real Vision.

## Acceptance criteria

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| AC1 (R1, spike findings) | Test + record | `status.md` findings; the opt-in sample run above reproduces the sizes and instance counts on 7 of the owner's files | Pass |
| AC2 (R2, R3: each kind, add/subtract/intersect/invert, Amount) | Test, Script | `DetectionMaskRenderingTests`: "Combined with a gradient: add, subtract, intersect and invert, and Amount…", "Background selects everything but the subject…", "A stored result renders the same on every run…"; three new goldens. Script S2 (synthetic) and S9 (real portrait): Subject, People, Background added; Background at -3 EV darkens everything but the disc (snapshot looked at); Invert on it darkens the disc instead; Background minus People and Background intersect People; Amount 30 | Pass |
| AC3 (R4: never blocks, Detecting line with Cancel, nothing added until it lands, one undo step and one History entry, input = 2560 px mask frame) | Test, Script, Person | `MaskDetectionTests` "The input is the oriented mask frame at 2560 pixels, whatever edits the photo has; Distortion alone changes it", "A run renders the input… a cancelled run stops before rendering". Script S1 (landing: undo name `Add Subject Mask`, one History entry for the add; S9 on the real portrait: Add People Mask, Local Adjustment, Add Background Mask, Local Adjustment, one entry per add and per edit), S8 (`hang`: pending shown, Detect pull-downs dimmed with "Wait for the current detection to finish.", Cancel button, Cancel and moving to another photo add nothing, History stays empty, no named undo step). The window staying responsive on a large raw is P2 | Pass (responsiveness open: P2) |
| AC4 (R5: stored, never silently recomputed; kind and digest, no pixels; digest in render hash; undo/history; Duplicate adds no row; shared bytes share a row) | Test, Script | `MaskRasterCatalogTests` "A row is stored once per bytes…", "Two components naming the same bytes share one row; Duplicate adds none", "History entries name the rows… a revert gives the earlier digest back"; `DetectionMaskModelTests` "A changed digest changes the render hash…", "Each kind round-trips… no pixels". Script S11: library quit and reopened with the detector set to `fail`: the Subject component still `found`, same digest `6823b83840e7`, no recompute possible; the stored stack in SQLite is 368 characters, `{"raster":"6823…","shape":"subject"}` and no pixels; Subject and Background share one row (`6823b83840e7`); an Update with real Vision then writes a new row and digest (`56cc8c15bbdf`) | Pass |
| AC5 (R5: migration, cleanup) | Test, Script | `MaskRasterCatalogTests` "v15 adds the table and the history column and leaves existing data as it was", "Cleanup keeps rows any stack or history entry names, and deletes the rest", "A stack this build can't read still keeps the rows its text names", "Undo Duplicate takes a copy's history out…". Script S12: a library made by `develop`'s own `photobench` (v14), opened by the bundle: `grdb_migrations` ends `v15`, `maskRaster` exists, image, version, volume, project, keyword and editHistory row counts and the md5 of `version` and `image` rows are identical before and after, the pre-existing history row has `maskRasters` NULL. Script S13: an orphan row inserted by SQL is deleted at the next launch; the two rows named by stacks and by history are kept | Pass |
| AC6 (R6: empty, failed, unavailable: kept, selects nothing, reason, renders as without) | Test, Script | `DetectionMaskRenderingTests` "Nothing found, a failed detection, a missing row and damaged bytes render as without the component" (every operation, Invert, alone and beside a gradient, byte for byte); `MaskDetectionTests` "A component's state follows its digest…". Script S3: Empty caption "No people were found in this photo. It selects nothing." (no Activity entry, no flash); Failed caption with Update and one Activity warning; Unavailable caption; announcement for each. Script S10 (real portrait lib): "No subject stands out in this photo. It selects nothing." on a landscape. Failed with a master missing from disk gave Failed with "The photo could not be rendered for detection." (reached by accident, correct) | Pass |
| AC7 (R7: crop and rotate keep the mask; no staircase; matches the guided-filter CPU reference; goldens) | Test, Script, Person | `DetectionMaskRenderingTests` "The guided filter matches its CPU reference within the half-float bound" (three sizes), "At 100% on a hard edge the result follows the photo's edge, with no staircase…", "Turned and cropped, the result stays on the same pixels…", "Window radius is one mask pixel…"; three new goldens, no existing golden moved (`git diff develop...HEAD --stat -- Tests` shows three new PNGs and no changed one); `GoldenTests` pass. Script S2: crop and a quarter turn with the mask in place (snapshot looked at). Edge quality at 100% on real raws is P4 | Pass (edges by eye: P4) |
| AC8 (R8: paste and presets omit; Duplicate copies the reference; pair files own) | Test | `DetectionMaskModelTests` "Paste and presets omit detection components (AC8)"; `MaskRasterCatalogTests` Duplicate case; pairs follow the existing per-file stack rule (status.md) | Pass |
| AC9 (R9: `photocli mask add --shape … --dry-run`, real run, list, export matches the loupe) | Test, Script, Person | `DetectionMaskCommandTests` (dry run stores nothing, real run writes, failures, refusals, missing row, list states). Script S14 on a copy of the real-photo library: `mask add --version 3 --shape people --dry-run` printed `detection` (found, 1 instance, 512x384, digest `ebb7ef68…`) and left `maskRaster` empty and `mask list` empty; real runs for People and Background on version 4 wrote both, `mask list` shows `shape`, `state`, `instances`, `raster`; their digests (`e5b46017ac45`, `102ae206fb07`) are exactly the ones the app's own detection produced on the same photo (S9); `photocli render` and `photocli export` ran and the exported JPEG shows the person lifted and the background darkened as in the loupe. An exported file beside the loupe at full size is P5 | Pass (beside the loupe: P5) |
| AC10 (R10, R16: nothing leaves the Mac, no new package or asset, no iterative request, spike gone) | Test, Script | `DetectionMaskSourceTests` (four tests: no network API, no other package, no `IterativeSegmentation`, Package.swift depends on GRDB alone). `git diff develop...HEAD --stat -- Package.swift Package.resolved Sources/PhotoBench` is empty (the spike file was deleted in an earlier commit; `ls Sources/PhotoBench` has no `AIMaskSpike.swift`); `grep -rn "IterativeSegmentation\|URLSession\|aimask" Sources Package.swift` finds nothing outside CLibRaw | Pass |
| AC11 (R13: both requests on a fixture, sizes, code-22 pass) | Test | `MaskDetectionTests` "Both Vision requests run on synthetic fixtures and give masks of the measured sizes (R13, AC11)"; `classification` pins the code-22 prefix. Read: the test passes only on `VNErrorDomain 22:` (unsupported compute device), requires Subject's 512x512 mask otherwise, any People mask 4:3, and an empty People result passes; any other error or size records an issue. It ran here with both requests working. **Not shown by anything here:** whether either request works on macOS 15 or 26 (CI is the first run; on a runner without a usable device the test passes and shows nothing, as the PRD says) | Pass (here); CI only on 15 and 26 |
| AC12 (R12: unreadable stack not overwritten) | Test | `DetectionMaskModelTests` "A digest that is not one, or an unknown key, makes the stack unreadable (R12)", "A stack with a detection this build can't read is never written over (AC12)" | Pass |
| AC13 (R14: missing row: reason, selects nothing, renders as without, editable, Update restores) | Test, Script | `DetectionMaskRenderingTests` "Nothing found, a failed…, a missing row…", "A row whose bytes don't decode is missing to the store"; `DetectionMaskCommandTests` "mask list says a result whose row is gone is missing (AC13)"; `MaskRasterCatalogTests` crafted, mistyped and oversize rows. Script S4 and S11b/c: `raster delete` shows "The stored result is missing or damaged. It selects nothing. Choose Update to detect again." with Update; with the row deleted in SQL and no cached preview the loupe shows the photo as without the mask (see Q1 for the other case); other edits keep working; Update (real Vision) restores `found` with a new digest | Pass, with the limit in Q1 |
| AC14 (R15: user guide names both limits) | Test | `DetectionMaskSourceTests` "The user guide names both limits of People (R15, AC14)"; read `docs/USER_GUIDE.md` lines 395 to 410: "up to four" and "People can also select something that is not a person" with the flower | Pass |

Counts: 14 criteria, 0 failed. Passed by test alone: AC1, AC8, AC10 (with greps), AC11,
AC12, AC14 (6). Passed by test and script: AC2, AC4, AC5, AC6, AC13 (5), plus AC3,
AC7 and AC9, each also with a person's part left (P2, P4, P5). Open for a person
beyond those: the designer's M1 to M8 (list below).

## Other checks asked for

| Check | How | Result |
| --- | --- | --- |
| DR-5: Invert cancels a covered pending Update | Script S6 (`hang`, `update` on both components, `adjust mask invert 0`) | Pass: pending none at once, announcement "Detection cancelled.", the person's Invert is the top undo step (`Invert`), no Update step |
| DR-5: operation change cancels | Same, `adjust mask operation 1 subtract` | Pass, undo `Mask Operation` |
| DR-5: Remove from Mask cancels | Same, `adjust mask removecomponent 1` | Pass, undo `Remove from Mask` |
| DR-5: deleting the mask cancels | Same, `adjust mask remove` | Pass, masks 0, undo `Delete Mask` |
| DR-5: ⌘Z of a covered Invert cancels | Same, then `undo` (three, see below) | Pass: after the Invert is undone, pending none, "Detection cancelled." |
| DR-5: uncovered changes do not cancel | Script S7: a one-component Update `update 0`, then in turn Invert on component 1, mask Exposure, Amount, a new mask (`add linear`), selecting masks, `enable off` and `on`, a component added to the mask (`component radial add`), a global Exposure, Move Up | Pass: still `pending update [0]` after every one; only the explicit `adjust mask cancel` ended it ("Detection cancelled.") |
| F1: crop session dims the pull-downs and Update | Script S5: `adjust crop begin`, `buttons` | Pass: both "Detect" pull-downs disabled with tip "Finish cropping to detect in the photo."; with a Missing result, Update disabled with "Finish cropping to detect again." |
| F2: failed Update of a Found result | Script S3: Found, `detector fail`, `update` | Pass: state `failedUpdate`, caption "Detection failed on this photo. The earlier result still applies. Choose Update to try again." with Update, announced once |
| N1: Unavailable stays Unavailable after a failed Update | Script S3: `detector unavailable`, Background, `detector fail`, Update | Pass: caption stays "Detection isn't available on this Mac. It selects nothing.", state `unavailable` |
| Flash only on Found | Scripts S1, S3, S9 | Pass: `flash true` for found landings (and `overlay` off 1.5 s later), `flash false` for empty, failed and unavailable landings |
| Invert On / Off value (F5) | Code read | `MasksSection.swift:367` passes `accessibilityValue` On / Off; neither `buttons` nor `accessibility` prints it, so not scripted. VoiceOver reading is not asked | Read only |
| C14 (known limit) | Status | Recorded, not re-run: twin identical components only |
| Menu bar rows (M1, M8) | Script S15, `open -W -n --stdout`, once | macOS did not activate the copy (`key nil`), every item read "disabled" including Update Detection after a Found mask; not retried. P1 stays |

Note on scripted ⌘Z: the debug script wraps every `adjust …` command (also `detector hang`
and `overlay`) in its own undo group, so a command that changes nothing leaves an empty
group on top of the stack, and the first two or three `undo` commands pop empty groups.
Three `undo`s reached the Invert. That is the script's grouping, not the app's.

## Findings

For the engineer (or the owner to rule on):

- **Q1 (should; known limit contradicts AC13's last words, owner to accept or send
  back).** AC13: "With the raster row deleted, … the render matches the photo
  without it." With a preview cached while the row existed, the loupe still shows the
  masked render. Steps: scratch library with a Subject mask at -3 EV made in the app
  (digest `6823b83840e7`); quit; `sqlite3 …/catalog.sqlite "delete from maskRaster"`;
  launch with the Previews folder kept, focus the photo, `snapshot`. Expected: the
  photo without the mask (the caption already says Missing). Actual: the mask still
  darkens the picture (up to 127 levels of difference from the photo without the
  mask). With the Previews folder deleted too, the loupe shows the photo as without
  (differences are only the ≤22-level preview versus live-frame offset described in
  O1). `status.md` records this under Known limits and proposes follow-up 1; this is
  the evidence for it. Decision: accept as a known limit, or fix (drop cached
  previews of versions whose detection rows are missing).
- **Q2 (nit, `status.md` and the debug script).** `status.md` says the scripted
  `raster delete` showed the loupe unchanged despite -3 EV. In this run it does not:
  Found and Missing snapshots of the same photo are identical (0 pixels differ), the
  Subject mask still darkening it. Steps: `adjust mask detector disc; adjust mask detect
  subject; adjust mask set exposure -3; adjust mask raster delete; snapshot`. I did not
  find the cause; the likely one is that `damage` removes the cached preview of
  `editor.item.editStackHash`, which is the hash from before the edit made in the same
  session, so the current stack's cached preview survives (the same effect as Q1). The
  state and the caption are right; only the loupe's picture is stale. Either correct
  the status.md sentence or make the command clear the current stack's key.

Observations, not findings:

- **O1.** In every run, a photo that has never been edited (a baseline snapshot) and the
  same photo after any edit, including a mask added then removed again (stack empty
  of masks), differ by up to 22 levels in about 89% of pixels of the loupe's photo
  area. The two states differ only in that one is the cached preview and the other a
  live frame, I believe. Not caused by this branch (a linear mask added and removed
  does the same) and not checked on `develop`; it is why the missing-row and failed
  renders are compared with a state after removal, not with the first snapshot.
- **O2.** Adding a component while an Update is pending leaves the Update pending, as
  DR-5 says. Not found: any case where a covered change failed to cancel.
- **O3.** The first detection after launch with real Vision is the slow one; the
  scripted real runs finished well inside the waits (JPEGs, 24 MP not tried).

No Design questions. No Requirements issues. No missing tests found: PhotoApp has no
test target, so the DR-5 wiring, F1, F2, N1 and the flash rule have script evidence
only (above); the rule they call (`MaskDetectionUpdate.isIntact`) is unit tested
(`updateIntact`).

## Scripts

Each starts `wait 2; focus IMG_00001; loupe; wait 2; tab adjust; wait 1;` on the
synthetic library (the real-photo library for S9, S10, S14) and ends `; quit`.
`SNAP` is a folder for snapshots.

S1, landing, undo and History (AC2, AC3, AC4):

```
adjust mask detector disc; print undo; adjust mask detect subject; print undo; history open; wait 1; history; print masks; snapshot SNAP/s1-subject.png; adjust mask set exposure 0; adjust mask detectcomponent people subtract; print masks; undo; print masks; undo; print masks; redo; redo; print masks; adjust mask set amount 50; print masks
```

Showed: `undo ''` before; after the add `undo 'Add Subject Mask'`; one History row; caption
"1 subject found."; overlay on with `flash true`, then `overlay false flash false`;
People subtract "2 people found."; the first `undo` removes People and its operation in
one step; Amount 50 stored.

S2, kinds and operations (AC2, AC7): `adjust mask detector disc; adjust mask detect
background; adjust mask set exposure -3; adjust mask overlay off; snapshot …;
adjust mask invert 0; snapshot …; adjust mask invert 0; adjust mask detectcomponent
people subtract; snapshot …; adjust mask operation 1 intersect; snapshot …; adjust crop
begin; adjust crop rect 0.4 0.4 0.4 0.4; adjust crop done; snapshot …; adjust crop turn
right; snapshot …; adjust mask set amount 30; snapshot …`. Showed: Background darkens
everything but the disc, Invert darkens the disc, the Background and Subject masks name
the same row, intersect of Background with the same disc selects (nearly) nothing.

S3, states and captions (AC6, N1, F2): `print activity; adjust mask detector empty;
adjust mask detect people; print announcement; adjust mask overlay off; adjust mask
detector fail; adjust mask detect subject; print announcement; print activity; adjust
mask update; adjust mask detector unavailable; adjust mask detect background; adjust
mask detector fail; adjust mask update; print masks; adjust mask detector disc; adjust
mask update; …; adjust mask detector fail; adjust mask update; print masks; adjust mask
detector disc; adjust mask update; adjust mask raster delete; adjust mask update`. All
captions as in the table above.

S4, missing row and its render (AC13; see Q1, Q2): `adjust mask overlay off; adjust mask
add linear; adjust mask remove; wait 3; snapshot SNAP/l1.png; adjust mask detector disc;
adjust mask detect subject; adjust mask set exposure -3; adjust mask overlay off; wait 3;
snapshot SNAP/found.png; adjust mask raster delete; adjust mask overlay off; wait 3;
snapshot SNAP/missing.png; adjust mask remove; wait 3; snapshot SNAP/removed.png`, then
compare crops of the photo area pixel by pixel: `l1` against `removed`: 0 pixels
differ; `found` against `missing`: 0 pixels differ (Q2).

S5, F1 (crop) and the hang buttons: `adjust mask detector disc; adjust mask detect
subject; adjust mask overlay off; adjust mask raster delete; wait 1; adjust crop begin;
wait 1; buttons; adjust crop cancel; wait 1; adjust mask detector hang; adjust mask
update; wait 1; buttons; adjust mask cancel`. `buttons` lines: Detect disabled "Finish
cropping to detect in the photo."; Update disabled "Finish cropping to detect again.";
then, pending: Detect disabled "Wait for the current detection to finish.", a Cancel
button "Stop detecting; nothing is added or changed".

S6, DR-5 cancels (save as one line each):

```
adjust mask detector disc; adjust mask detect subject; adjust mask detectcomponent people add; adjust mask overlay off; adjust mask detector hang; adjust mask update; print masks; adjust mask invert 0; print masks; print announcement; print undo; adjust mask invert 0; adjust mask update; print masks; adjust mask operation 1 subtract; print masks; adjust mask operation 1 add; adjust mask update; adjust mask removecomponent 1; print masks; adjust mask detector disc; adjust mask detectcomponent people add; adjust mask detector hang; adjust mask update; adjust mask remove; print masks; adjust mask detector disc; adjust mask detect subject; adjust mask detectcomponent people add; adjust mask invert 0; adjust mask detector hang; adjust mask update; undo; undo; undo; print masks; print announcement
```

S7, no cancel: `adjust mask detector disc; adjust mask detect subject; adjust mask
detectcomponent people add; adjust mask detector hang; adjust mask update 0; adjust mask
invert 1; adjust mask set exposure 1; adjust mask set amount 50; adjust mask add linear;
adjust mask select 0; adjust mask component radial add; adjust mask enable off; adjust
mask enable on; adjust exposure 0.5; adjust mask move 1; print masks; adjust mask cancel`.

S8, AC3 cancel and leaving: `history open; adjust mask detector hang; adjust mask detect
subject; print masks; print announcement; history; adjust mask cancel; print masks; print
announcement; history; print undo; adjust mask detect people; print masks; focus
IMG_00002; wait 2; print masks; history; focus IMG_00001; wait 2; print masks; history;
print activity`. Showed `pending new subject`, History empty throughout, "Detection
cancelled." after Cancel, nothing after leaving, no Activity entry.

S9, real portrait (real Vision, real-photo library): `focus 10M10325; loupe; …;
history open; adjust mask overlay off; snapshot SNAP/r-base.png; adjust mask detect
people; snapshot SNAP/r-overlay.png; adjust mask overlay off; adjust mask set exposure
1.5; snapshot …; adjust mask detect background; adjust mask set exposure -2.5; adjust
mask overlay off; snapshot SNAP/r-bg-down.png; print masks; history; focus 10M10296; adjust
mask detect people; focus X1000587; adjust mask detect people; focus 10M10287; adjust mask
detect subject; print masks; print announcement`. Showed: the red overlay covers the
woman (hair, hood, strap, hands) and not the dog; with +1.5 EV on her and -2.5 EV on
the background the woman stays lit and the rest goes dark (dog included); History: Add
People Mask, Local Adjustment, Add Background Mask, Local Adjustment; the flower gets "1
person found." (R15); the crowd "4 people found, the most that can be selected. Others
in the photo may be left out."; the landscape "No subject stands out in this photo. It
selects nothing."

S10 is the last lines of S9. S11, reopen and ground truth for missing rows: library
`lib-synth-gt`: S1-like run (`detect subject; set exposure -3`), quit; second launch
`adjust mask detector fail; adjust mask select 0; print masks` (still `found`, same
digest, no recompute); then two copies with `delete from maskRaster` by `sqlite3`, one
with its `Previews` folder deleted; third launch `adjust mask select 0; print masks;
snapshot; adjust mask update; print masks; snapshot`: both `missing` with Update, Update
gives `found(instances: 3)` (real Vision on the synthetic picture), a new digest
`56cc8c15bbdf`.

S12, migration: `swift build -c release --product photobench` in `git archive develop`
extracted to a scratch folder (develop's last migration is `v14`); `import` the six photos
into `lib-dev14`; `sqlite3` counts and md5; launch the bundle with `wait 3; print items;
quit`; the same counts and md5, `v15` last, `maskRaster` empty, history `maskRasters`
NULL.

S13, cleanup: `insert into maskRaster select 'deadbeef'||substr(digest,9), … from
maskRaster where substr(digest,1,12)='102ae206fb07'`; launch with `wait 3; quit`; the
`deadbeef…` row is gone and the two referenced rows remain.

S14, `photocli` (debug build of this branch, on a copy of the real-photo library):
`photocli mask add --version 3 --shape people --dry-run --library-root …`; `mask list
--version 3`; `mask add --version 4 --shape people --set exposure=1.5`; `mask add --version
4 --shape background --set exposure=-2.5`; `mask list --version 4`; `render --version 4
--out …`; `export --version 4 --to …`.

S15, menus (not activated): `open -W -n --stdout menu.log Gus.app --args --library-root …
--debug-script "… print responder; menuitems Update Detection; menuitems Subject …"`:
`key nil`, all items disabled. Not retried.

## For a person

VoiceOver, macOS 15 and macOS 26 are not asked. Numbers M1 to M8 are the designer's
(`review.md`); the ones that are also `status.md` M-items are named. The owner's
command to build and open a scratch library with photos is in the report that came
with this file and at the end of this section.

- **P1 (M8, status M1): the Adjust menu.** With a photo open in the loupe and the Adjust
  tab: Adjust ▸ New Mask ▸ the divider, then Subject, People, Background; Adjust ▸ Update
  Detection above Show / Hide Mask Overlay. Look for: Update Detection dimmed with no
  detection mask or a Subject mask with a result selected, enabled with a Missing or
  Failed one selected, dimmed while detecting; the three items dimmed while detecting.
  Choose each once. Scripts could not activate the window (S15).
- **P2 (M6, status M2; covers AC3's responsiveness): the window stays responsive.** On the
  largest raw you have, choose Subject, then People: while the line says "Detecting…",
  scroll the inspector, drag a slider, move to another photo. Look for no beach ball and
  no stutter; Cancel adds nothing; leaving the photo adds nothing and says nothing.
- **P3 (M1, M2, M3, status M3): the row and its captions at the narrowest inspector.**
  Drag the inspector to its narrowest. In "New Mask:" and "Add to Mask:" the five shapes
  and the wand with its chevron fit, hover shows "New mask from the photo: …"; with a
  Failed, Empty, Unavailable and Missing result (the script's `detector fail`,
  `empty`, `unavailable`, `raster delete`, see the commands above) the captions wrap with
  the triangle and Update lined up; the four-person caption on a crowd; the dimmed
  pull-down's tooltip while detecting and while cropping (borderless dimmed button: does
  the tooltip show?).
- **P4 (M4, M5, status M4, M5, M8; covers AC7's edges and the PRD's success line): edges
  and the look on your own photos.** At 100% on a portrait, add People, then Background;
  raise local exposure on the person and lower it on the background; Invert on
  Background. Look for: edges without a staircase or a halo, hair and glasses, the
  person lifted cleanly; whether 1.5 s of red helps or annoys (clicking the eye while it
  flashes turns the overlay off; is that right?). Try your raws (the ORF and RAF from
  the 2016-05-21 folder). Subject on the flower and tree photos (a tree selects as one
  blob with the sky in it), People on the flower (the known false positive).
- **P5 (status M7; covers AC9's "export matches the loupe"): export beside the loupe.**
  Export a photo with a detection mask (File ▸ Export…) and open the file beside the
  loupe at the same zoom: the same lift and the same edge.
- **P6 (M5): keyboard only.** With Full Keyboard Access: Tab to the wand, open it with
  Space, choose Subject; where does focus go while it detects (the pull-down dims), can
  you Tab to Cancel and press it, and where is focus when the result lands? If focus
  falls to the window, tell the engineer.
- **P7 (M7): Update on a healthy mask.** Adjust ▸ Update Detection on a Found mask: does
  the brief "Detecting…" read as a response when the result is unchanged (I3)? And
  Q1: if you delete your preview cache, does a deleted-row mask look right (only if you
  want to try it: the steps are in Q1).

Command to build the bundle and run it on a scratch library of your own photos (copies
of six of the 2016-05-21 files; nothing touches your library), zsh:

```zsh
cd /Users/randy/Projects/Gus-ai-masks && Scripts/build-app.sh && Q=$HOME/gus-scratch/ai-masks-qa-$(date +%H%M%S) && mkdir -p $Q/photos && cp ~/gus-scratch/photos/2016-05-21/{10M10325,10M10296,X1000553,X1000587,10M10287}.JPG $Q/photos/ && cp ~/gus-scratch/photos/2016-05-21/10M10296.ORF $Q/photos/ && swift run -c release photobench import --library-root $Q/library --source $Q/photos && cp -R build/Gus.app $Q/Gus.app && plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.aimasks-signoff $Q/Gus.app/Contents/Info.plist && codesign --force --deep --sign - $Q/Gus.app && open -n $Q/Gus.app --args --library-root $Q/library
```

The portrait is 10M10325.JPG (a woman and a dog; People finds her), the crowds are
X1000553.JPG and X1000587.JPG (four people), the flower 10M10296 (the false positive),
the landscape 10M10287 (nothing found). To hold a state still for P3, launch the same
bundle executable with `--debug-script` (for example `adjust mask detector fail; adjust
mask detect subject; wait 600`) and the same `--library-root`.

## Known limits (from status.md and this run)

- C14 (nit): two identical detection components in one mask, inverting the one a running
  Update covers is read as a move to the other twin, so the Update stays pending and
  lands on the other twin. Rare; results are byte-identical unless the frame changed.
- AC11 gaps (as the PRD revision says): a runner without a usable device passes by
  Vision's code-22 error and shows nothing about macOS 15 or 26; People's mask size is
  seen only when it finds something; only 27.2.1 is measured by hand. The app says
  Unavailable where Vision can't run.
- Q1: previews cached before a row went missing still show the mask.
- An orphaned row stays until the next launch (by design); an empty result's row is
  shared by every empty result, so its provenance is the first writer's.

## Follow-up

Sign-off (#88): the owner signed off on 2026-11-21 after doing checks P1 to P7
by hand. No findings reported; no checks left open. Code signed off at
`9b50009` (this file at `9a4249a`). VoiceOver, macOS 15 and macOS 26 are
covered by CI only (standing ruling).
