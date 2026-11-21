Issue: #88

# AI masks: implementation status

Feature, branch `feature/ai-masks`, cut from `develop` at `ed423d7`. The PRD
is the issue body (`gh issue view 88`), approved 2026-11-18 and revised
2026-11-20 after the spike and the design. Design: [`design.md`](design.md).

**State: Done** (2026-11-20), review findings fixed (see **Review
findings**). Every acceptance criterion is built and has a test or a recorded
check; nothing is blocked. Next: the second pass of code-reviewer and the
designer, then qa-tester.

| Item | State |
| --- | --- |
| R1, the spike | Done, 2026-11-20 (findings below, kept as the record) |
| PRD revision, design | Done, 2026-11-20 |
| R2 to R16 | Done |

## Build and test

- Baseline, `develop` at `ed423d7`: `swift build` clean; `swift test` 1,253
  tests in 179 suites passed.
- Latest (2026-11-20, after the third-pass fixes, `dc44a26`): `swift build`
  with no warnings; `swift test` **1,305 tests in 185 suites passed** (91.4
  s); after the second-pass fixes 1,303, after the first 1,300;
  `Scripts/build-app.sh` builds the bundle. Opt-in suites not run here:
  `AI_MASK_SAMPLES` (the owner's photos). Before the fixes: 1,298 in 185.
- No `PreviewCacheKey.currentPipelineVersion` bump: no existing stack renders
  differently (a stack without detections is untouched; a detection is new
  data with its own render hash). No existing golden moved; three new ones
  (`mask-subject-patchChart`, `mask-background-edgeTarget`,
  `mask-peopleSubtractCropTurn-hazyLandscape`) in a commit of their own
  (`ad7899c`). `UPDATE_GOLDENS=1` also rewrote six RAW fingerprint files with
  this Mac's build (27.2.1, 26B131); I restored them, they are not part of
  this change.
- Two existing tests changed because a rule changed: `MaskModelTests` and
  `CommandTests` used `subject` as their example of an unknown shape; it is now
  a shape, so they use `sky`. `CatalogTests` lists the new table and v15.

## What was built, and the engineer's decisions

**Stack (R2, R3, R5, R12).** `MaskShape.detection(MaskDetection)`: the
component is stored as `{"shape": "subject"|"people"|"background", "raster":
"<sha-256>"}`, no pixels; a failed detection has no `raster`. Read strictly
(an unknown key, or a `raster` that is not 64 lowercase hex, makes the stack
unreadable). `kindVersion` stays 1: older builds read the new shape names as
unknown and refuse the whole stack, so they never write over it (the PRD's
Dependencies). Background is its own kind (design A2) and may name Subject's
row.

**Storage (R5).** Migration v15 (`CatalogSchema.addMaskRasters`): table
`maskRaster` (`digest` primary key, `encoding` `png-gray8`, `width`,
`height`, `instances`, `data`, and provenance `request`, `revision`,
`systemVersion`, `createdAt`), and a nullable `editHistory.maskRasters`
column. Rows are inserted with `INSERT OR IGNORE` and never updated (the
debug script's `raster corrupt` is the one write that changes a row, for
checks only). An empty result is a stored 1x1 black PNG with 0 instances
(design §6), so empty survives reopening and differs from missing. The
instance count lives on the row (design §4's count is cheap).

**Cleanup: at launch (the PRD's open engineer question).** History snapshots
are compressed, so each new history entry names the rows its snapshot refers
to in `editHistory.maskRasters` (rows written before v15 could name none).
`Catalog.removeUnreferencedMaskRasters()` deletes, in one transaction, every
row that no version's stack (read as text, so a stack this build can't
decode still counts) and no history entry names; `LibraryModel.start()` runs
it in the background on every launch. Not in the transaction that orphans a
row, because within a session the window's undo stack can still hold a stack
naming a row that no stored stack or history entry names (Undo a detection,
then let the history trim past it): Redo must find the row. At launch no
undo stack exists. Cost: an orphan keeps its bytes (2 to 110 KB) until the
next launch. `photocli` never sweeps.

**Rendering (R6, R7, R14).** `MaskRasterStore` (like `LookTableStore`): reads
rows from the catalog on first use and keeps up to 48 decoded results in
memory; `AdjustmentRenderer(maskRasters:)` everywhere a library renders (the
app's previews and live frames, export, `photocli render` and `export`).
`GuidedMaskFilter`: the result stretched bilinearly over the mask frame
(pixel centers aligned, edges repeated), sent through the crop like the
brush, then the guided filter (He, Sun and Tang) with the luminance of the
image entering the mask step as guide, at the render's size, window radius
one mask pixel rounded up (5 at 2560 px, 12 at 6000 px), ε = 10⁻³. Four
runtime-compiled stitchable kernels, one library each, as the Lens kernels.
The half-float cancellation the spike found is avoided by never forming
E[I²] − E[I]²: the first pass computes each row's means and moments about
those means in float, the second combines the rows exactly (equal counts).
The result is uploaded as 32-bit float: an `L8` image read in a kernel came
back up to a third of a level off. If the kernels can't compile, the result
is stretched only, with a log notice. A detection with no usable result
(failed, empty, missing, damaged, or no store) is left out whatever its
operation and Invert (design A5); a mask none of whose components contribute
leaves the image untouched, byte for byte.

**Detection (R4, R10, R11, R13).** `VisionMaskDetector` (PhotoCore
`Suggestions/MaskDetector.swift`): `VNGenerateForegroundInstanceMaskRequest`
or `VNGeneratePersonInstanceMaskRequest`, every instance, the soft mask
quantized to 8 bits. Errors meaning "can't run here" (unsupported revision,
request, compute stage or device; resource unavailable on 27) are
Unavailable, others Failed. `MaskDetectionRun.input` renders the mask frame
(a raw's whole sensor, the system decoder's or LibRaw's default decode, the
Distortion group only, no other adjustment) at 2560 px in sRGB. A run is
cancellable before and after the render.

**App (design §2 to §15).** The Detect pull-down (`wand.and.stars` with its
chevron) at the end of both shape rows; it dims as a whole, with the reason
as its tooltip (the limit, or "Wait for the current detection to finish."),
since `AppKitMenuButton` items carry no tooltips and all three share one
reason. The Detecting line with Cancel under the row that started it, or in
the component's caption slot for Update. Captions per state; the triangle and
Update only for Failed, Unavailable and Missing. Update Detection in Adjust
(after Show / Hide Mask Overlay) and in the mask's ⋯ and context menus; an
Update of a mask with Subject and People runs each request once and is one
undo step; an unchanged result writes nothing; a failed Update keeps the old
result and shows Failed for this visit. The component enters the stack only
when the result lands: the row is written first on the write chain, then the
stack, as one undo step and one History entry; a new mask is selected only if
the selection did not change meanwhile. Default values +0.3 EV, Background
−0.5 EV; default names Subject, People, Background. The overlay flash (1.5 s,
a hard cut) ends early on the eye, a slider drag, selecting another mask or
leaving the photo. Leaving the photo, closing the loupe and starting a
comparison (the loupe is torn down) cancel a pending detection. Unavailable
is remembered per request for the session and cleared by a later success.
Announcements and Activity warnings as design §6 and §12. 36 catalog entries.
`AppKitMenuButton` gained `showsArrow` and `isEnabled` (defaults keep every
existing use as it was).

**photocli (R9).** `mask add --shape subject|people|background` (no
`--kind` alias; no `--params`) detects on the original and stores the
result, then the stack (two transactions: if the second fails, the app's next
launch removes the row); `--dry-run` looks and reports `detection` (state,
instances, size, digest) and stores nothing. A failed or unavailable
detection is still added with no result, and `detection.reason` says why. A
missing original is `fileNotFound` and writes nothing. `mask list` adds each
detection's `state` and `instances`. `CommandEnvironment.maskDetector`
(Vision by default) lets tests use a fixed detector.

**R16.** `Sources/PhotoBench/AIMaskSpike.swift` and `photobench aimask-spike`
are deleted.

## Acceptance criteria

| AC | How it is checked | State |
| --- | --- | --- |
| AC1 | Spike findings below | Done |
| AC2 | `DetectionMaskRenderingTests`: `combines` (each operation, Invert, Amount, with a gradient), `background`, `storedResultRenders`; goldens. Debug script: Subject, People subtract, Background in the app | Done |
| AC3 | `MaskDetectionTests.inputIgnoresEdits` (input = 2560 px mask frame, same pixels with heavy edits, Distortion alone changes it), `runAndCancel`. Debug script (below): one undo step and one History entry on landing, Undo removes it in one step, Cancel and leaving the photo add nothing and leave undo unchanged, items dimmed while pending. Never blocks: detection runs on a detached task | Done; the window staying responsive is for a person (M2) |
| AC4 | `MaskRasterCatalogTests` (store/read, shared row, Duplicate adds no row, history names the digest, revert gives it back), `DetectionMaskModelTests.renderHashFollowsTheDigest` and round trip (kind and digest, no pixels), `DetectionMaskRenderingTests.storedResultRenders` (identical across runs). Debug script: Undo restores the earlier state without detecting | Done |
| AC5 | `MaskRasterCatalogTests.migration` (v15 leaves rows unchanged) and `cleanup` (kept while named by a stack or history; deleted after Update plus history trim, and after a version is removed), `undoDuplicateKeepsReferences`, `unreadableStacksStillName` | Done |
| AC6 | `DetectionMaskRenderingTests.idleComponentsRenderAsWithout` (empty, failed, missing, damaged; every operation and Invert; alone and beside a gradient: byte for byte), `MaskDetectionTests.states`. Debug script: each caption | Done |
| AC7 | `GuidedFilterReference` + `matchesReference` (three sizes, every pixel within a first-order half-float bound; the GPU used at most 35% of it, bound median 1.6 × 10⁻⁵, at most 0.017), `noStaircase` (stretched result off by up to 4 px in steps, filtered within 1.25 px of the true edge), `cropAndTurnKeepTheMask`, three new goldens | Done |
| AC8 | `DetectionMaskModelTests.pasteAndPresetsOmitDetections`; Duplicate copies the reference (`sharingAndDuplicate`); pairs: edits are per file, as every stack | Done |
| AC9 | `DetectionMaskCommandTests` (dry run reports and stores nothing, real run writes, list states, failures, refusals, missing row; `render` reads the stored result). Export and loupe share `AdjustmentRenderer` with the library's store | Done; an exported file beside the loupe is for a person (M7) |
| AC10 | `DetectionMaskSourceTests` (no network API, no other package, no `IterativeSegmentation`, no spike) | Done |
| AC11 | `MaskDetectionTests.requestsRunWithTheMeasuredSizes`, part of `swift test` | Done here (27.2.1); CI runs it on 15 and 26 at the pull request (see RI-E1) |
| AC12 | `DetectionMaskModelTests.strictReading`, `unreadableIsNotOverwritten` | Done |
| AC13 | `idleComponentsRenderAsWithout`, `damagedRowIsMissing`, `DetectionMaskCommandTests.missingRow`. Debug script: `raster delete` shows Missing with Update, the loupe shows the photo unchanged, Update restores Found | Done |
| AC14 | `docs/USER_GUIDE.md` (Masks from the photo), pinned by `DetectionMaskSourceTests.userGuideLimits` | Done |

## Debug-script checks (2026-11-20)

On a copy of the bundle (`CFBundleIdentifier` `me.sesser.gus.debugtest`,
ad-hoc signed) and scratch libraries from `photobench generate --jpeg 4` and
`photobench import`, a fresh copy per run, always with `--library-root`.

- `adjust mask detector disc; adjust mask detect subject`: undo `Add Subject
  Mask`, caption "1 subject found.", overlay on with `flash true`, then
  `flash false` and overlay off 2 s later. People added with Subtract:
  "2 people found."; History: Add Subject Mask, Add People to Mask, Mask
  Operation.
- Background at −3 EV: everything darkened except the subject, its edge on
  the scene's own ellipse (snapshot).
- Empty: "No people were found in this photo. It selects nothing.", no
  Activity entry. Fail: Failed caption with Update and one Activity warning
  ("Couldn't detect a subject in IMG_00001.JPG." and the detector's words).
  Unavailable: its caption; cleared by a later success.
- `hang`: pending shown, every detection and Update item dimmed (`canDetect
  false`, Adjust ▸ New Mask ▸ Subject and Update Detection disabled), Cancel
  adds nothing; moving to another photo and back: nothing added, no pending.
- `raster delete`: Missing caption with Update; the loupe shows the photo
  unchanged despite −3 EV; Update restores Found and the row.
- Real Vision from the inspector's path on a synthetic photo: Subject "1
  subject found.", People "1 person found."; Undo removes the People component
  in one step (`redo 'Add People to Mask'`).
- `print inspectorwidth`: `fits` (visible 283, controls reach 275, the same
  reach as before this branch).
- Not driven here: the menu bar items with a key window. macOS refused to
  activate the scripted copy (`key nil`, also after bringing it forward by its
  process ID), so `menupress` saw every item disabled. The enablement rules
  are `LibraryMenuState.canDetectMask` and `canUpdateDetection`; see M1.

## Review findings (2026-11-20)

From [`code-review.md`](code-review.md) and [`review.md`](review.md); all
fixed in `b56d44c` (code) and `88d1c43` (user guide) unless said otherwise.

| # | Finding | Resolution |
| --- | --- | --- |
| C1 | Update applied results by component position captured at the start | Fixed. The Update keeps each component's place, kind and stored result; the landing finds it again by kind and result (`MaskDetectionUpdate.positions`, PhotoCore), at its old place if it still matches, else the first unclaimed match, else nowhere. Tested with the review's case (`MaskDetectionTests.updatePositions`) |
| C2 | A result landing while the lens frame question is up, or after the frame changed | Fixed, chosen behavior: the result waits until the question is answered; if Distortion then differs from the one the input was rendered with, it is detected again in the new frame (at most twice more; a frame that keeps changing ends it as a Cancel would, "Detection cancelled."). `changeMasks` now returns false when `change` would refuse, so nothing is selected, announced or flashed for a change that did not happen. Not scripted (the frame question needs a real slider and alert): for the second pass and QA |
| C3 | A failure in a two-request Update named the first component's kind | Fixed: `land` iterates (request, result); Unavailable and the Activity warning use the failing request and the kind of the component that uses it (`PendingDetection.kind(for:)`). Also F3 |
| C4 | Launch cleanup could run between a detection's two writes | Fixed: the app enqueues it on the write chain (`persist`), so it runs before or after both writes; `photocli mask add` writes the result and the stack in one transaction (`setEditStacks(..., storing:)`) |
| C5 | AC11 depended on People finding a "person" in synthetic fixtures | Fixed: People's sizes are checked whenever it finds something; finding nothing in person-less fixtures passes, and says so in the log. Subject must still find the disc wherever it runs. No observation means no size, so People's sizes are seen only when it finds something (here, and in the opt-in samples). Vision gives no observation when nothing is found (probe, 27.2.1) |
| RI-E1 | AC11 on CI runners Vision can't use | Implemented as the coordinator relayed the ruling in progress: a request that throws the classified "can't run here" error (`MaskDetectionError.unavailable`: unsupported revision, request, compute stage or device; resource unavailable on 27) passes, with the error printed; any other error fails. Branches on the error, no `Test.cancel` |
| C6 | App sentences reached Activity unlocalized | Fixed: `MaskDetectionError` has `.unreadable` and `.unusableMask`, worded by the app (`MaskDetectionText.detail`, catalog); `.failed` and `.unavailable` carry the system's words only. `photocli` keeps plain English |
| C7 | A two-request Update rendered the input twice | Fixed: `MaskDetectionRun.run([requests], …)` renders once (`MaskDetectionTests.severalRequestsOneRender`) |
| C8 | Cancel did not cancel the Vision request | Fixed: `MaskDetecting.detect` is async and Vision's request is cancelled from the task's cancellation handler (`RequestCancel`, `@unchecked Sendable` with its reason in a comment) |
| F1 | Pull-down and Update looked enabled while cropping | Fixed (DR-2): tooltips "Finish cropping to detect in the photo." and "Finish cropping to detect again."; scripted: `buttons` shows both Detect pull-downs and Update disabled with them |
| F2 | A failed Update of a Found result said "It selects nothing" | Fixed (DR-1): new state `failedUpdate`, caption "Detection failed on this photo. The earlier result still applies. Choose Update to try again.", triangle and Update; scripted |
| F3 | Same as C3 | Fixed with C3 |
| F4 | Flash any landing | Fixed (DR-3): only a result that found something flashes; scripted (empty: `flash false`) |
| F5 | Invert had no on/off for VoiceOver | Fixed: `accessibilityValue` On / Off (existing keys) on every component's Invert. VoiceOver reading is not checked by hand (project rule) |
| F6 | A failed landing announced twice | Fixed: the Activity warning is posted without announcing (`LibraryModel.postActivity`); the landing's own announcement carries the caption. Scripted: one announcement |
| G1 to G4 | User guide wording | Fixed (`88d1c43`) |
| I2 | Update Detection above Show / Hide Mask Overlay | Done. Design §7 and §11 still say "after"; the designer amends them |
| I1 | Eye click during a flash | Not changed (coordinator): left for manual check M4 |
| I3 | "Detection unchanged." for VoiceOver | Not done (judgment, no ruling) |

Scripted re-check, 2026-11-20 (a copy with its own identifier
`me.sesser.gus.debugtest.aimasks`: the shared `me.sesser.gus.debugtest`
domain held a saved search from another session, which emptied the grid, and
was left as it was): Subject found, announced once; `detector fail` then
Update: the `failedUpdate` caption and announcement, one Activity warning;
`adjust crop begin`: both Detect pull-downs and Update disabled with the
cropping tooltips; an empty People landing does not flash.

## Second pass and security review (2026-11-20)

From the second passes of [`code-review.md`](code-review.md) and
[`review.md`](review.md), and [`security-review.md`](security-review.md); all
in `fe593cf`.

| # | Finding | Resolution |
| --- | --- | --- |
| C9 | AC11's test passed on any "can't run here" error | Fixed as ruled (AC11, Q2): it passes only on Vision's unsupported compute device error, code 22, recognized by the detail `classify` writes ("VNErrorDomain 22: …", pinned in `classification`). Any other error, an unsupported revision included, fails, and so does a wrong size. Subject must return its 512 x 512 mask; any People mask its 4:3 size; an empty People result passes. The app keeps its wider Unavailable classification |
| C10 | The Update's fallback match ignored operation and Invert | Fixed: `MaskDetectionUpdate.Started` also carries operation and Invert, and a component matches only with all four; tested with twins that differ in operation and in Invert |
| N1 (design) | A second failed Update turned Unavailable into Failed | Fixed: `detectionState` keeps Unavailable. Scripted: `detector unavailable`, Subject, Update, then `detector fail`, Update: the caption stays "Detection isn't available on this Mac. It selects nothing." |
| L1 | A crafted 4096-pixel row could cost gigabytes | Fixed: `MaskRaster.maximumSide` is 1024 for writing and reading; `Catalog.maskRaster` checks the row's width and height before decoding and does not load bytes over `maximumStoredBytes` (2 MiB, `CASE WHEN length(data) <= ?` in SQL). Tests `oversizedPNG`, `craftedRows` |
| L2 | A row's key was not checked against its bytes | Fixed (optional in the review): a row whose bytes don't hash to its key is damaged (`craftedRows`) |
| L3 | A damaged `editHistory.maskRasters` let the cleanup delete rows history names | Fixed: a list that is not NULL and can't be read (or names something that isn't a digest) is replaced by a scan of that entry's snapshot; if the snapshot can't be read either, that launch deletes nothing. NULL (entries before v15) stays "names none". Test `damagedHistoryList` |
| N1 (security) | No stride or size check on Vision's buffer | Fixed: width and height within the side limit, not planar, `bytesPerRow` and data size large enough, all before allocating or reading |

Not changed: the scanner's small per-quote allocation (a performance note in
the security review). A Gus process from `qa/work/Gus.app` in the session
scratchpad was running during these checks; not mine, left alone.

## Third pass (2026-11-20)

From the third pass of [`code-review.md`](code-review.md) and design DR-5;
code in `2317d05`, user guide in `dc44a26`.

| # | Finding | Resolution |
| --- | --- | --- |
| C11, DR-5 | A change to a component a pending Update covers | Fixed as ruled: the check is in one place, where every change to the open photo's values lands (`AdjustmentEditor.adjustments`' `didSet`, so the row's controls, Remove from Mask, deleting the mask, ⌘Z, Redo and a History revert all go through it). The rule is `MaskDetectionUpdate.isIntact` (PhotoCore, tested): every covered component still there with its kind, result, operation and Invert, wherever it now sits. If not, the whole Update is cancelled exactly as Cancel does, with "Detection cancelled." (no new string). Not cancelling: uncovered components, values, Amount, an added component, a reorder. Controls are not dimmed. Scripted with the `hang` detector (new `adjust mask invert`, `operation`, `removecomponent`, `move`): Invert, operation, Remove from Mask and deleting the mask each cancel an Update of both components (no undo step for the Update, the person's change on top); ⌘Z of a covered Invert cancels; inverting the uncovered component during a one-component Update, or changing Exposure, leaves it pending. User guide: "Changing or removing a component while it looks again stops that too." |
| C12 | `craftedRows` refused its rows by the hash check first | Fixed: each crafted row is keyed by the SHA-256 of its own bytes (PNGs other than the good one's, and an over-size blob), plus a row exactly at the byte limit that loads. Checked by breaking each guard in turn: without the width and height check the test fails (2 issues), without the 2 MiB cap it fails (1 issue); restored |
| C13 | A mistyped value in a row stopped the app | Fixed: `Catalog.maskRaster` converts each value from its database value, so a wrong type makes the row damaged (selects nothing, R14). Test `mistypedRow` for width, height, instances, revision, encoding, request and data. `systemVersion` can't be mistyped that way: its column has TEXT affinity, so SQLite stores a number there as text |

## For a person (manual checks proposed to QA)

- M1: the menu bar: Adjust ▸ New Mask ▸ Subject / People / Background under
  the divider, Adjust ▸ Update Detection, enabled and dimmed as design §11.
- M2: the window stays responsive while detecting (scroll, sliders) on a
  large raw; Cancel and leaving the photo mid-detection.
- M3: the pull-down's look in both rows at the narrowest inspector, its
  chevron, tooltip and dimmed state; captions wrapping at 256 pt.
- M4: the overlay flash on a real portrait: helps or annoys (design §9).
- M5: Background on a portrait at −0.5 EV; Invert on it.
- M6: the four-person caption on a crowd photo; a false People selection.
- M7: export of a photo with a detection mask beside the loupe.
- M8: edge quality at 100% on the owner's raws (the PRD's assumption).

## Known limits

- An orphaned row stays until the next launch (by design, above).
- If a row goes missing (a damaged or partly copied catalog), previews cached
  while it was there still show the mask: the render hash names the digest,
  not the row. The loupe's live render, captions and new previews are right.
  Deleting the preview cache clears it. Proposed follow-up below.
- The empty result's row is shared by every empty result, Subject's or
  People's: its provenance (`request`) is the first writer's. Only diagnosis
  reads it.
- A raw with a camera frame decodes its whole sensor for any mask, a
  detection with no result included, as before for any mask.
- The debug script's `detectcomponent <kind> <operation>` adds, then sets the
  operation: two History entries in one undo group, as the row's pop-up would.

## Requirements issues (for the product manager)

The spike's RI-1 to RI-6 were ruled on 2026-11-20 and are in the PRD's
Revisions; the design's RI-1 to RI-3 likewise. New:

- **RI-E1 and Q2, the R13 test on CI.** Ruled by the product manager (PRD
  revised on #88): only code 22 passes, an empty People result passes, sizes
  must match. Built as ruled (C9 above). Original note: On
  this Mac the foreground request refuses the CPU (`VNErrorUnsupportedComputeDevice`,
  code 22) and runs on the GPU or Neural Engine. If a CI runner on macOS 15 or
  26 gives Vision neither, the test fails there with that error in its
  message, and the person request may find nothing in the synthetic fixtures
  (the test needs one result to check sizes). The app itself would show
  Unavailable on such a Mac, as designed. If CI fails this way at the pull
  request, the question is whether AC11 accepts "Unavailable" on a runner
  with no usable compute device; I'd recommend yes, with the error recorded.

## Design questions

None blocking. Design §7 and §11 place Update Detection after Show / Hide
Mask Overlay; it is now before it (review I2), for the designer to amend. Notes for review: the pull-down dims as a whole with the
reason as its tooltip, rather than per item (all three items always share
one reason; `AppKitMenuButton` items have no tooltips). The New Mask submenu
is still dimmed as a whole when New Mask can't act, as before this branch;
the three detection items also dim while a detection runs.

## Proposed follow-ups (for the main session to file)

1. **Previews cached before a detection's stored result went missing still
   show the mask** (`bug`, low). Body: the render hash covers the digest, not
   the row, so a catalog that loses a `maskRaster` row keeps showing the old
   masked previews until the cache is deleted; the loupe's live render is
   right. Option: drop cached previews of versions whose detection rows are
   missing when the launch cleanup or the editor finds one.
2. **People beyond four** (`enhancement`): the PRD's follow-up, evaluate
   combining Vision's person instance and person segmentation requests.

## README

- `photocli mask add --shape` takes `subject`, `people` and `background`
  (with `--dry-run`); `mask list` shows their state.
- `photobench aimask-spike` is gone (it never was in the README).
- New catalog table `maskRaster` (migration v15). No build command changes.

## Not done, deliberately

- No `--kind` alias (optional in R9; one flag, as design RI-2).
- No per-item tooltips in the pull-down (see Design questions).
- macOS 15 and 26 are covered by CI only (owner ruling RI-6); no VoiceOver
  check by hand (project rule).

## Spike findings (R1), kept as the record

### How the spike was measured

(The spike's code was deleted by the feature build, R16, commit `c7650e6`:
the command below no longer exists.)

All spike code is in one file of the benchmark tool, outside every shipped
target: `Sources/PhotoBench/AIMaskSpike.swift`, the mode `photobench
aimask-spike`. Nothing in the apps or `photocli` calls it. It is throwaway:
the feature build replaces it with real code and deletes it.

```zsh
swift run -c release photobench aimask-spike --files a.JPG:b.ORF --runs 5 --upscale --devices --sizes --output /tmp/aimask
```

`--long-edge full` runs at full resolution (default 2560, the preview tier);
`--dir DIR` takes every photo in a folder. `--output` writes overlays, the
low-resolution masks and edge crops of each upscaling method as PNGs: never
commit them, they are the owner's photos.

For each file it renders the detection input (the master through an empty
stack: oriented, before any crop, the decoder's own look, 2560 px long edge,
sRGB), runs `VNGenerateForegroundInstanceMaskRequest` and
`VNGeneratePersonInstanceMaskRequest` (and, for comparison,
`VNGeneratePersonSegmentationRequest` at `.accurate`), and reports mask size
and format, instances, confidence, coverage, the share of soft pixels (between
2% and 98%), whether repeated runs agree, agreement between compute devices,
the effect of the input size, the time of each run, the stored size of the
all-instances mask under each encoding, and the upscaling comparison.

**Photos.** The owner's scratch copy of one folder of his library
(`gus-scratch/photos/2016-05-21`: 120 camera JPEGs, with their Olympus ORF
and Fujifilm RAF raws). Nothing from it is committed. Two sets:

- *Survey*: all 120 JPEGs, one run each.
- *Fixed set*: 12 files, 5 runs each, with every option. By content:
  `10M10296` (flower close-up, no person), `10M10325` (one person, clear
  edges), `X1000553` (group of four or more, people against a tent),
  `X1000587` and `X1000559` (street crowds, more than four people),
  `10M10306` (lone tree in a field), `10M10308` (object subject, no person),
  `X1000574` (portrait orientation, object subject), `10M10287` (landscape,
  no subject), `10M10292` (portrait orientation, small subject), and the raws
  `10M10296.ORF` and `X1000553.RAF` (the same scenes through the RAW path).
  Full resolution was also run on `X1000553.RAF` (4896x3264) and
  `10M10325.ORF` (4608x3072).

**Machine.** Apple M4 Pro, macOS 27.2.1 (26B131), macOS 27.2 SDK, Swift
6.4.2. Times are wall clock in one process, release build.

### Findings (R1, AC1)

#### 1. Availability

- **macOS 27.2: both requests exist and work.** `supportedRevisions` is
  `[1]` for both (and for the person segmentation).
- **macOS 15:** the SDK's own headers declare both
  `VNGenerateForegroundInstanceMaskRequest` and
  `VNGeneratePersonInstanceMaskRequest` `API_AVAILABLE(macos(14.0))`, with
  `VNInstanceMaskObservation`, and neither is deprecated in the 27.2 SDK.
  That settles the PRD's doubt (person request "confirmed only by a
  third-party source") from a first-party source; it does not show they *run*
  on macOS 15, which was not tried (below).
- **The macOS 15 "redesign"** is Vision's Swift-only API: value-type requests
  (`GenerateForegroundInstanceMaskRequest`,
  `GeneratePersonInstanceMaskRequest`, `InstanceMaskObservation`, `async`
  perform), `@available(macOS 15.0)`, beside the `VN` classes, with the same
  single revision. Either API works with the app's macOS 15 minimum. macOS 26
  and 27 add no new mask request except `GenerateIterativeSegmentationRequest`
  (macOS 27 only; seeded by a point, box or scribble; its model is downloaded
  on demand, `DownloadableAssetsRequest`). That one would conflict with R10's
  intent and is not part of this slice; it may matter later for picking one
  instance.
- **No download.** Neither mask request is a downloadable-asset request in
  the 27.2 SDK: their models come with the OS. The spike uses no network API.
  Network traffic was not monitored.
- **Not tried: macOS 15 and macOS 26.** This Mac has only 27.2, and no other
  Mac was available. See RI-6.

#### 2. Mask resolution and format

| Request | Label map | Soft mask (`generateMask(forInstances:)`) | Values |
| --- | --- | --- | --- |
| Foreground (Subject) | 512x512, 8-bit (`L008`) | 512x512, 32-bit float (`L00f`) | almost binary: 0.0% to 0.6% of pixels soft |
| Person (People) | 512x384 or 384x512, 8-bit | same, 32-bit float | soft: 2% to 60% of pixels soft |
| Person segmentation (comparison) | none | 2016x1512 or 1512x2016, float at `.accurate` | 0% to 27% soft |

- **The size is fixed by the model, not by the photo.** Foreground is always
  512x512, for 3:2 and 2:3 photos alike; person is always 4:3. The mask is
  stretched over the frame, so the stored raster must keep its own width and
  height and map to the mask frame in unit coordinates.
- **The input size barely matters.** The same file rendered at 512, 1024,
  2560 and 4096 px gave the same mask size and coverage within one percentage
  point, except one soft person mask (an ORF: 45.2%, 44.2%, 39.4% at 1024,
  2560, 4096).
- **Coarse at 100%.** On a 24 MP 3:2 file one foreground mask pixel spans
  about 9.6 x 6.4 output pixels, so edges need the upscaling of section 7.
- Vision's own `generateScaledMaskForImage` gives a mask at the image's size
  (section 7).

#### 3. Quality and instance counts (this Mac only)

Survey of 120 JPEGs: Subject found something in 65 (one instance in 51, two
in 13, three in 1); People in 56 (four instances in 22, one in 20, two in 8,
three in 6); neither in 44. In 11 photos People found people where Subject
found nothing (street crowds).

Fixed set (coverage of the frame, instances in brackets):

| File | Content | Subject | People | Person segmentation |
| --- | --- | --- | --- | --- |
| 10M10296.JPG | flower close-up | 14.0% (1) | 35.5% (1), false | 31.1%, false |
| 10M10325.JPG | one person | 22.9% (1) | 22.9% (1) | 22.8% |
| X1000553.JPG | group, 5+ people | 57.8% (1) | 59.9% (4) | 61.0% |
| X1000587.JPG | street crowd | none | 8.6% (4) | 16.8% |
| X1000559.JPG | street crowd | none | 48.3% (4) | 51.9% |
| 10M10306.JPG | tree in a field | 30.4% (1), confidence 0.28 | none | 0.0% |
| 10M10308.JPG | object | 29.5% (1) | none | 0.0% |
| X1000574.JPG | object, portrait | 12.2% (1) | none | 0.0% |
| 10M10287.JPG | landscape, no subject | none | none | 0.0% |
| 10M10292.JPG | small subject, portrait | 0.7% (1) | none | 0.0% |
| 10M10296.ORF | flower close-up | 14.1% (1) | 44.2% (1), false | 15.8% |
| X1000553.RAF | group | 56.6% (1) | 61.6% (4) | 62.4% |

What looking at the overlays showed:

- **Subject** is clean on clear subjects (a flower's petals, a cap against a
  tent, an object) and selects a tree as one blob, the sky between its
  leaves included. It found nothing in the two no-subject landscapes (the R6
  path). It often ignores people in a crowd (two street scenes: nothing), so
  Subject is not a superset of People.
- **People stops at four.** Apple says the request segments "up to four
  individuals" (WWDC23, session 111241). In one street crowd about nine people
  are visible and four are selected; several in the middle of the frame are
  not. The semantic person segmentation selected all of them (but lost a
  child's curly hair that the instance mask kept). RI-1.
- **People has false positives.** On the flower close-up both person models
  select the flower and leaves, the instance request with confidence 0.999;
  confidence does not tell this apart from real people (0.96 to 0.999). The
  person mask there also carries a fine 4-pixel grid of low soft values over
  the background. RI-2.
- **The same scene through JPEG and raw** gives the same instances and
  Subject coverage within 1.2 points; the soft People mask of the flower
  differs more (35.5% against 44.2%).
- **Determinism.** Within one process on one compute device, five runs gave
  bit-identical masks for every file and kind. Across compute devices they
  differ: People on the CPU or GPU against the Neural Engine differs by up to
  0.05 on 0.3% to 28% of pixels; Subject flips a handful of pixels (single
  values up to 0.94). Vision's default device is not fixed either: in a fresh
  process the default matched the Neural Engine, but after an earlier request
  in the same process had asked for the GPU, later default runs matched the
  GPU. So the same photo can give a different mask on a later recompute on the
  same Mac, and will on a Mac without a Neural Engine (Intel Macs run macOS
  15 and 26). This supports R5 as written: store the result, never recompute
  silently.
- **Between OS versions:** not measured (15 and 26 not tried).

#### 4. Cost of one detection (M4 Pro, macOS 27.2.1)

| Step | Time |
| --- | --- |
| Render the detection input, 2560 px, empty stack | JPEG 100 to 160 ms (median 120), ORF 330 to 410 ms, RAF 100 to 165 ms |
| Subject: perform, `generateMask`, read | warm 12 to 27 ms (survey median 14); first in a process 30 to 118 ms |
| People: the same | warm 8 to 13 ms (survey median 9); first in a process 10 to 262 ms; 2.05 s once, the first run after a new build |
| People forced to the CPU / GPU | 93 to 134 ms / 30 to 260 ms |
| Memory, first use in a process | Subject +54 MB, People +18 MB (process footprint) |

Adding a component therefore costs about 0.15 to 0.5 s, most of it the
render of the input, not the detection. The detection itself is short enough
that cancellation (R4) matters mostly for the render.

#### 5. Stored size of one mask

The all-instances soft mask quantized to 8 bits (largest error 1/510 against
the float mask), over the fixed set:

| Encoding | Subject (9 masks) min / median / max | People (7 masks) min / median / max | Person segmentation (12) min / median / max |
| --- | --- | --- | --- |
| 32-bit float, raw | 1,048,576 | 786,432 | 12,192,768 |
| 8-bit, raw | 262,144 | 196,608 | 3,048,192 |
| 8-bit, LZFSE | 621 / 3,052 / 5,360 | 10,894 / 53,646 / 110,529 | 3,816 / 262,949 / 692,056 |
| 8-bit gray PNG | 1,814 / 6,100 / 8,293 | 12,483 / 49,471 / 89,604 | 16,390 / 269,208 / 569,852 |

(bytes). Binary Subject masks compress best with LZFSE; soft People masks
with PNG.

**In the stack, against the limits.** A typical stack (`EditBenchmark.typical`,
971 bytes of JSON, a 615-byte history snapshot) with one mask whose component
carries the PNG inline as base64:

| Kind | Stack JSON | History snapshot (LZFSE) | Snapshots in 4 MiB |
| --- | --- | --- | --- |
| Subject | 3.6 to 12.3 KB | 1.9 to 8.9 KB | 473 to 2,181 |
| People | 17.9 to 120.7 KB | 13.4 to 91.7 KB (median 50.8) | 45 to 312 (median 82) |
| Person segmentation | 23 to 761 KB | 5.9 to 578 KB | 7 to 713 |

- `MaskLimits` bounds counts (32 masks, 16 components each, color samples,
  brush points), not bytes. Inline, a stack could hold 512 AI components:
  about 56 MB of JSON at the largest People mask measured.
- `EditHistory` keeps 100 entries or 4 MiB per version, the newest always
  kept. One inline People component already drops the history below 100
  entries on most photos measured (median 82, worst 45); every further AI
  component divides it again, and every entry repeats every raster.
- Stored in a table and referenced by digest, a component adds about 150
  bytes to the stack, and the history is unaffected.

#### 6. Storage recommendation

**A catalog table of rasters, content-addressed, referenced from the
component by digest.** Not inline in the stack (section 5), and not keyed by
the master's content hash and kind as R5 prefers (RI-4).

- Table `maskRaster` (new migration): `digest` (SHA-256 of the stored bytes,
  primary key), `width`, `height`, `encoding`, `data` BLOB, `createdAt`, and
  provenance for diagnosis (request, revision, OS version). Rows are never
  updated.
- The component stores its kind (`subject`, `people`, `background`) and the
  digest. A Background component can reference its Subject raster (it is
  Subject inverted), so no second detection or row is needed.
- Why the digest and not master hash plus kind:
  1. **Render hash.** The render hash covers the stack only. With the raster
     under a key the stack doesn't hold, Update would change the render while
     the render hash, and so every cached preview's key, stays the same. With
     the digest in the stack, the hash changes exactly when the raster does,
     and no pipeline version bump is ever needed for it.
  2. **Virtual copies and pairs (R8).** A master-keyed row is shared by every
     version of the master: Update on a copy would silently change the
     original. With digests, Duplicate copies the reference (no new row) and
     the two diverge only when one is updated. The two files of a RAW+JPEG
     pair have different stacks and so their own rows.
  3. **Undo and history.** An old snapshot or an undo restores the old
     digest, whose row is still there; nothing has to be recomputed (R5).
- Lifetime: a row lives while any version's stack or any `editHistory`
  snapshot names it. Removing versions and trimming history leave orphans to
  sweep (in the same transaction, or at launch); at 2 to 110 KB a row, a
  late sweep costs little.
- Encoding: **8-bit gray PNG**. Lossless, self-describing (the size is in
  it), read by ImageIO into a Core Image graph with no code of ours, and a
  reviewer can open a row's bytes as an image. LZFSE of the raw bytes would
  be 10% to 60% smaller for Subject and up to 20% larger for People; either
  fits. A PNG encoder may write different bytes for the same pixels on another
  OS: harmless, since rows are never encoded again, only copied.
- Strict reading (R12): new shape names make a stack unreadable to older
  builds, which then never write over it, the existing rule for masks. A
  digest whose row is missing (a damaged or partly copied catalog) is a
  different case: RI-5.

#### 7. Edge-aware upscaling: proposal

**The guided filter** (He, Sun and Tang, "Guided Image Filtering", ECCV 2010
and TPAMI 2013) with a gray guide, run at the render's own size:

1. The stored raster is placed in the mask frame and sent through
   `crop.apply` like the brush (`MaskRenderer.framed`), sampled bilinearly.
2. Guide: the luminance of the image entering the mask step, the image the
   luminance and color ranges select on (`MaskRenderer.selection`), in its
   perceptual encoding.
3. Window radius: one mask pixel in output pixels (the output size over the
   raster's size, rounded up: 5 at 2560 px, 9 to 10 at full size on these
   files); ε = 1e-3. Starting values for the build, to be pinned there by a
   CPU reference and goldens.
4. Implementation: two stitchable color kernels (prepare `I, p, I², Ip`;
   coefficients `a, b`; then `a·I + b`) and two box blurs, compiled at run
   time like the Lens kernels. A CPU reference (plain Swift, as in the spike)
   for `ReferenceTests`.

Evidence (overlays and crops at 2560 px and at 100% on the two raws, judged
by eye):

| Method | Result |
| --- | --- |
| Bilinear | Staircase of one mask pixel, about 10 px steps at 100% |
| Guided filter at output size, gray guide (proposed) | No staircase; follows outlines, including a black jacket against a dark red tent; slightly soft (a few pixels) where guide contrast is low |
| The same, color guide (3x3 per pixel) | No visible gain; 4 to 5 times the CPU cost, and a 3x3 solve per pixel |
| Fast guided filter (coefficients at mask resolution, He and Sun 2015), gray or color | Good at 2560 px; soft over 20 to 40 px at 100%, because its coefficients are themselves upsampled 6 to 10 times |
| Vision's `generateScaledMaskForImage` | Needs the request handler of the detection run, so it cannot be used at render time from a stored raster; acts as a plain resampler: values overshoot (−0.66 to 1.40 on People masks), visible soft halo around a cap at 2560 px |
| `CIGuidedFilter` (built in) | Close to the proposed method at radius 4; parameters undocumented; one run gave non-finite pixels on one photo, not reproduced in three later runs. Not recommended |

Cost: the spike's GPU prototype, in the app's half-float working format,
including reading the result back: at 15 to 16 MP about 75 to 90 ms against
22 to 35 ms for rendering the guide alone (about 50 to 60 ms for the filter);
at 2560 px 24 to 35 ms against 10 to 19 ms. It agrees with the CPU reference
to a mean of 0.001 to 0.0026; single pixels differ by up to 0.3 to 0.8 in
half float and up to 0.18 to 0.43 in float. The variance `E[I²] − E[I]²`
loses precision in half float: the build should compute it in float or
about a centered guide, and match its box to the reference's exactly.

Consequence: because the guide is the image entering the mask step, the
upscaled mask follows what is seen and moves very slightly with global
edits before it (the filter is invariant to linear changes of the guide only
up to ε), as the range masks already do. The stored raster never changes, and
a stack renders the same every time. No existing stack's render changes, so
no `PreviewCacheKey.currentPipelineVersion` bump.
