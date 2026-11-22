Issue: #243 · Complexity: hard

# Copy Adjustments: choose what to copy: status

Owner: swift-macos-engineer. Branch `feature/copy-adjustments-selective` (off
`develop`). Spec: the PRD (issue #243, revised 2026-11-22: R1 to R14, AC1 to
AC12) and [design.md](design.md).

**State: Done** (2026-11-22, after the first review round). Every Must and
Should requirement is built, and R14's Could items as the design specifies
them, the Paste tooltip included (design §15 DQ-2). Every acceptance criterion
has a Swift Testing test or a debug-script check (below). The code review's C1
to C4 and the design review's F1 to F4 are fixed (see **Review findings**).
The second passes' nits are answered in docs only: C5 and N1 corrected, C6
recorded as a known limit (see **Review findings (second round)**). Next:
qa-tester.

## Build and test

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline (branch at ade878b, before any change) | `swift build --build-tests` passes | 1428 tests in 205 suites pass |
| First implementation (2026-11-22, 890588c) | Pass, no new warnings | 1449 tests in 206 suites pass (21 new, `CopyAdjustmentsTests`); `LibraryModalTests` expects the new modal |
| Latest (2026-11-22, after the review fixes) | `swift build --build-tests` passes, no new warnings (the two in `SmartAlbumTests` and `VirtualCopiesTests` are older) | 1452 tests in 206 suites pass (3 new: C1 twice, C3) |
| Bundle | `Scripts/build-app.sh` passes (after the fixes too) | |
| CI toolchain | `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` passes (2026-11-22, again after the fixes; `/Applications/Xcode_26.3.app` is a symlink to `/Applications/Xcode-26.3.0.app`) | |

No catalog migration. `PreviewCacheKey.currentPipelineVersion` unchanged (13).
No golden touched, `UPDATE_GOLDENS` not run. No rendering changed: the
renderer and the stack format are untouched; only which values a paste writes
changed.

## What was built

- **PhotoCore** `Edits/CopyAdjustments.swift`
  - `CopyItem`: `.crop` or `.group(Adjustments.Group)` (the Engineer question
    "how are spots and crop keyed": the crop is its own case beside the
    groups, since it is not a `Group`; Spots is `.group(.spots)`, the group it
    already is). Names for the debug script: `crop` and the groups' stored
    names. `isUncheckedByDefault`: Crop, Spots, the four Lens groups.
  - `CopyRow`: the sheet's rows, data-driven: `.crop`, then
    `.section(Section)` in the Adjust tab's visible order (`tabOrder`: Spots,
    Light, Tone Curve, Color Mixer, Black & White, Color Grading, Details,
    Lens, Effects). A section with one group is a single row. #92 adds a
    row here.
  - `CopySheetState`: the source's values frozen at open, the checked items,
    the defaults (R3), the heading's derived state (on, off, mixed), the click
    rule (design §3.4: checked unchecks all, unchecked or mixed checks all),
    Check All, Uncheck All, `canCopy` (R4), each row's note (design §3.3:
    No changes, Resets on paste, Turned off, the spot count), the summary for
    the announcement.
  - `CopiedAdjustments`: the clipboard: the checked items and only their
    values (every other module at its default). `pasted(onto:pastingSpots:)`
    replaces exactly the copied items, values and on/off, and nothing else
    (R5): masks, the stored decode, unknown operations, the camera profile
    reference and everything not copied stay the target's.
    `pastesSpots(sourceFrame:targetFrame:)` is the same-size rule (R8).
  - `SpotPastePlan`: which photos of a paste get the spots, and how many kept
    theirs because of another size or an unreadable size.
  - `PreviewGenerator.maskFrameSize(of:)` (in `Preview/PreviewGenerator.swift`,
    beside the other code that makes RAW filters, so `RAWDecodeGraphTests`'
    tripwire still lists the same files; its comment names it): the frame
    spots are placed in (below).
  - `Adjustments.pasted(onto:)` stays as "every item but Spots" through
    `CopiedAdjustments`; the app no longer uses it (tests do).
    `copyModule` is internal now (was private).
- **PhotoApp**
  - `Model/CopyAdjustmentsActions.swift`: `CopySheet` (the sheet's state, the
    thumbnail, the source's URL, the window's height at open),
    `canCopyAdjustments` (a photo focused, no other modal, no preset manager;
    design §7), `openCopySheet`, `copySource`, `confirmCopySheet`,
    `cancelCopySheet`, `pasteAdjustments` and the spots path
    `pasteMeasuringSpotFrames`.
  - `Model/AdjustmentActions.swift`: the old `copyAdjustments`,
    `pasteAdjustments` and `applyAdjustments` are gone;
    `changeAdjustmentsMeasuringAlignment` takes a per-photo transform and a
    `then` (the old signature forwards to it).
  - `Model/CopyAdjustmentsText.swift`: every string of design §10.
  - `Views/CopyAdjustmentsSheet.swift`: the sheet (design §3). Each box is an
    `AppKitCheckbox` (a system `NSButton` check box: mixed state, a Tab stop
    with Full Keyboard Access, Space toggles); its click and a click anywhere
    else on the row both go through `CopySheetState.click`. VoiceOver reads
    the name and the trailing text as the box's label; the Crop and Spots
    captions are the boxes' help.
  - `Views/AdjustControls.swift`: `AppKitCheckbox` takes a `controlSize`
    (default small, as before).
  - `Model/LibraryModal.swift`, `LibraryModel.swift`, `Views/MainView.swift`:
    `.copyAdjustments`, `showsCopySheet`, `copySheet`, the presenter with
    `onDismiss: { model.modalDidClose() }` (`LibraryModalTests` updated).
  - Entry points: the Adjust menu (`Copy Adjustments…`, ⇧⌘C, enabled by
    `canCopyAdjustments`), the grid, loupe and video loupe context menus
    (`Copy Adjustments…`), the Adjust tab's ⋯ menu, the palette's toolbar item
    (`Copy Adjustments`, tooltip "Choose which adjustments to copy"). Paste's
    places are unchanged.
  - `Views/SpotsSection.swift`: the Spots note is now "Presets leave spots out.
    Copy Adjustments can copy them to photos of the same size." (design §6).
  - Debug script: `Model/DebugCopyAdjustmentsCommands.swift` (design §11):
    `copyadjust`, `copyadjust all|<item>…`, `copyadjust sheet [check|uncheck
    <item>…|all | click <row> | mouse <row> box|label | confirm | cancel]`,
    `print copysheet`, `print clipboard`, `print stacks`, `print messages`.
- **Strings**: 18 keys added to `Localizable.xcstrings` (design §10 plus
  DQ-1's), "Presets and Paste Adjustments leave spots out." removed, the
  comments of `Copy`, `Copy Adjustments`, `From %@`, `%lld spots` and the masks
  note extended.
- **`docs/USER_GUIDE.md`**: the crop, Spots, AI masks, machine learning noise
  reduction and Lens passages, and a new paragraph on the sheet and what Paste
  does, after the ⋯ menu sentence.

## The PRD's questions for the engineer

- **How spots and crop are keyed.** `CopyItem.crop` and `CopyItem.group(_)`;
  Spots is `.group(.spots)`. The clipboard is a set of items with their
  values only, so a later Masks row (#92) is one more case.
- **The frame-size test for spots.** `PreviewGenerator.maskFrameSize(of:)`:
  the size in pixels of the decode the renderer places spots in for a photo
  with spots: the oriented decode of the whole sensor (`CameraFrame`'s full
  frame for Olympus, OM System and Panasonic raws, else the system decoder's;
  LibRaw's frame for raws only LibRaw reads; ImageIO with the orientation
  applied for everything else), before turns, straightening and crop. Nothing
  is decoded (only the decoder's output extent is asked for), and most files
  are read only as far as their headers; an Olympus, OM System or Panasonic
  raw with a camera crop is read whole into memory, since `CameraFrame`
  patches a copy of its bytes to get the whole sensor (code review C2: this
  said "headers only" before). The Lens heading's corrections keep that
  size (`LensCorrectionRenderer` crops its result to its input), so the frame
  "after the Lens corrections the paste leaves" has the same size as before
  it: one measurement per photo is the R8 test. Sizes are compared in whole
  pixels, with no remapping: a portrait and a landscape frame of one camera
  differ (seen in the scratch library: photobench writes some JPEGs with a
  turned orientation, and those correctly kept their spots). A test pins the
  measure to the renderer's own full-sensor decode's extent for a JPEG, a
  turned JPEG and a DNG. The source's master is remembered with the copy and
  measured at paste time with the targets, so a copy made while the source is
  offline pastes no spots ("could not be read", DQ-1).
- **Where the sheet's source comes from relative to pending saves.** In the
  loupe, with the editor ready on that photo, the editor's *saved* values
  (`savedAdjustments`), not `adjustments`: those can run ahead (a slider being
  dragged, a preset hover preview). Elsewhere the catalog's, read through the
  write chain after pending saves (`WriteChain.savedAdjustments`), as Copy did
  before; the sheet opens when the read answers, and a second request while it
  runs does nothing. Unreadable edits open no sheet and post the existing
  Activity warning (seen with a stack of schema 99, grid and loupe). The values
  are frozen in `CopySheetState` when the sheet opens.
- **The debug script's `copy` behavior.** `copyadjust` keeps its name and now
  copies with the sheet's defaults and no sheet (⇧⌘C then Return); a source
  with nothing checked copies nothing, as Copy is dimmed. `copyadjust all`
  and `copyadjust <item>…` copy exactly those items. `copyadjust sheet …`
  drives the real sheet. `pasteadjust` is unchanged.

## Acceptance criteria

| AC | State | Test or check |
|---|---|---|
| AC1 (R1, R4) | Done | Scripted: `copyadjust sheet` then `alert key escape` closes it and `print clipboard` is `none` (and an earlier copy stays: `confirm` and `cancel` print it); `alert key return` with Tone checked closes it, clipboard `light`, announcement "Copied Tone.", ⇧⌘V enabled; Copy with defaults then Paste in the scripted paste runs. Video: no sheet; unreadable edits: no sheet, the warning. |
| AC2 (R2) | Done | `CopyAdjustmentsTests.rowsFollowTheTab`, `headingStateIsDerived`; scripted `print copysheet`: 22 boxes in the order Crop & Straighten, Spots, Light (White Balance, Tone, Presence), Tone Curve, Color Mixer, Black & White, Color Grading, Details (Sharpening, Noise Reduction), Lens (4), Effects (3), the tab's names. |
| AC3 (R3) | Done | `defaultsFollowTheSource`, `uncheckedByDefault`, `turnedOffCountsAsChanged`; scripted on IMG_00001 with Exposure, Contrast and a crop: Tone on, Light mixed, Crop & Straighten off with no note, Spots, Lens and every other group off with "No changes". |
| AC4 (R4) | Done | `nothingCheckedCannotCopy`, `noChangesAtAll`; scripted: Copy off and "Check something to copy." with nothing checked; Return does nothing then. |
| AC5 (R5) | Done | `onlyColorGrading` (stored stacks compared by content and render hash); scripted: Color Grading and Spots pasted on a grid selection changed only those; crops, exposure and other photos' values unchanged (`print stacks`). |
| AC6 (R5) | Done | `copiedDefaultsReset` (a turned-off Tone Curve reset and on). |
| AC7 (R5, R6) | Done | `batchPasteHistory` (three photos, one write each, "Paste Adjustments" once per photo, undo restores all); scripted: one undo step "Paste Adjustments", Undo restored all five photos, Redo again, History rows "Paste Adjustments", "Undo …", "Redo …". |
| AC8 (R7) | Done | Scripted: Distortion (Manual) and Color Grading copied, pasted on a photo with a spot: the frame question asks; Cancel writes nothing; Change pastes both. A paste without a Lens group never asks. Only a target's own spots and masks count, not those the paste brings (C1: `frameQuestionIgnoresPastedSpots`, `frameQuestionCountsTheTargetsOwn`). Per-photo table reads and the "left unchanged" sentence are the unchanged `confirmingLensFrameChange` and lens paste paths (their tests and #87's checks); no real files with tables were used here. |
| AC9 (R8) | Done | `spotsPasteBySize`, `sameSizeRule`, `spotPastePlan`, `maskFrameSizeMatchesTheDecode`; scripted: spots copied from a 1200×800 photo went onto the other 1200×800 photo (one undo step with the rest), and the 900×600 and the turned 800×1200 photos kept theirs, with "Spots were not pasted onto 3 photos: their size differs from the photo the spots were copied from." |
| AC10 (R9) | Done | `cropPastesAsStored`; scripted: Crop unchecked by default, so pastes left every crop alone. |
| AC11 (R6) | Done | Scripted `menuitems`: Copy Adjustments… dimmed for a video (and `copyadjust sheet` opens nothing), Paste dimmed until a copy exists and while comparing; while comparing Copy takes the active photo ("From SML_00002"). |
| AC12 (R12) | Done, plus a person's check | Every box is a system check box; scripted `copyadjust sheet click <row>` presses each through AppKit (`performClick`, the path Space takes) and `mouse <row> box|label` posts real mouse events: one toggle each, never two; Return and Esc through `alert key`. Tab order with Full Keyboard Access is M2 for a person. |

## Debug-script checks (2026-11-22)

A copy of the bundle with `CFBundleIdentifier`
`me.sesser.gus.debugtest.copyadjust`, re-signed ad hoc, against a scratch
library: `photobench generate --output $S/src1 --jpeg 3 --jpeg-size 1200x800
--dng 0 --heic 0 --videos 1` and `--output $S/src2 --jpeg 2 --jpeg-size
900x600 --videos 0` (renamed SML_*), both imported with `photobench import`,
a fresh copy of the library per run, every launch with `--library-root`.

- **Sheet, defaults, heading rule** (`focus IMG_00001; loupe; adjust exposure
  0.5; adjust contrast 20; adjust crop …; grid; copyadjust sheet; copyadjust
  sheet click develop` twice, `click light`, `click crop`, `confirm`): as AC3;
  the mixed Light box clicked became on (all three), clicked again off; Tone
  alone back to mixed; Crop on; the clipboard `crop light`, announcement
  "Copied Crop & Straighten, Tone."
- **Paste with Spots** (see AC9): IMG_00002 the source (crop, Color Grading,
  2 spots), through the real sheet (`copyadjust sheet` opened with Color
  Grading checked and Spots saying "2 spots"; `click spots; confirm`), then
  `selectall; pasteadjust`: "1 video was left unchanged." and the spots
  warning for 3 photos; IMG_00003 got 2 spots and the grading and kept its
  Exposure 1; no crop moved; one undo step. Also run with `copyadjust
  colorGrade spots` (no sheet) and Undo, Redo: every photo back, then again.
- **Lens frame question** (see AC8).
- **Short window** (`windowsize 760 480`): the sheet clamps to 420 × 480 (the
  window under its toolbar), the list scrolls (content 520 pt, 326 shown), the
  header, footer and buttons stay.
- **Height** (design §3.8): the list's content is 520 pt, the rest 140 pt:
  660 pt for the default case (not scrolled, 4 pt to spare), 680 pt with the
  note for a photo with no adjustments. No cut needed. Check boxes measure 16
  pt (18 pt in some runs); the groups' indent is 22 pt.
- **Keyboard after the sheet**: Esc in the grid leaves `PhotoCollectionView`
  first responder, Return in the loupe `LoupeHostView`: ⇧⌘V and the arrows
  work at once, no `.browserShouldTakeFocus` needed.
- **Unreadable edits** (a stack of schema 99 set with `sqlite3` on the scratch
  copy): no sheet, "These edits were saved by a newer version of Gus. Editing
  is off so they are not lost." under Copy Adjustments, grid and loupe.

## For a person (the designer's M1 to M6)

M1 the sheet's look beside Export's with Increase Contrast; M2 keyboard with
Full Keyboard Access (Tab through every box, Space, Return, Esc, a hidden row
scrolled in); M3 the narrowest window by eye; M4 a real mouse on a mixed
heading; M5 the real flow with keys (⇧⌘C, Space, Return, ⇧⌘V, one undo); M6 a
preset pack import ending while the sheet is up. VoiceOver, macOS 15 and macOS
26: CI only.

## Design questions

Both ruled in design §15 (2026-11-22) and built (F1, F2 below).

- **DQ-1 (ruled: a second warning, the designer's wording).** A paste with Spots onto a photo whose
  size can't be read (its original offline or unreadable, or the source's
  original offline when the paste runs) keeps that photo's spots. The design's
  one sentence says "their size differs", which would be wrong there, so I
  added a second warning: "Spots were not pasted onto %lld photos: their size
  could not be read." (one: "…onto 1 photo: its size could not be read."),
  posted the same way. Options: (a) keep it; (b) fold those photos into the
  "size differs" sentence (no new string, a wrong reason); (c) other words.
  Recommendation (a). Note: with a Color Alignment paste, offline photos are
  left out whole and already reported by the measuring paste, so they are not
  counted here.
- **DQ-2 (ruled: built as design §15 specifies).** R14 lists "a tooltip on the
  toolbar's Paste item naming what was copied"; design §14 noted it as a Could
  "not specified" and gives no string. I did not invent one. If wanted: the
  string (for example "Paste Adjustments: %@", the list as the announcement
  builds it) and whether the menu item gets it too. Cost: one string and a
  `.help` on the toolbar item.

## Review findings (first round, 2026-11-22)

From [code-review.md](code-review.md) (C1 to C4) and [review.md](review.md)
(F1 to F4). Commits: 05b0e8b (C1 to C4), b034487 (F1 to F3), and the commit
that adds this section (F4, the user guide and this file).

| # | Outcome | What was done |
|---|---|---|
| C1 | Fixed, 05b0e8b | The frame question now tests `CopiedAdjustments.pastedForFrameQuestion(onto:)` (the paste with the target's own spots kept), on both the loupe path and the selection path, so only spots and masks a target already has count (R7, design §5.2). The candidate rule (`frameCandidates`, `FrameCandidate`, the masks-and-spots count) moved unchanged from `LensCorrectionActions.swift` to PhotoCore `Edits/LensFrameQuestion.swift`, so the tests run the app's rule. The stale comment on `noteLensFrameAnswered` now says spots a paste brings were not asked about and a later change that moves them asks. Tests: `frameQuestionIgnoresPastedSpots`, `frameQuestionCountsTheTargetsOwn`; both fail with the old transform (`pasted(onto:)`, spots included): run with the body swapped back, 3 issues recorded, then restored. Scripted: Spots and Distortion pasted in the loupe onto a photo with no spots asks nothing; onto a photo with its own spot asks "1 of 1"; on all five photos (one with its own spot) the alert said "1 of the 5 photos has masks or spots" (the old rule gave 3). |
| C2 | Fixed (the record), 05b0e8b | `maskFrameSize(of:)`'s comment and this file no longer say header-only: a cropped Olympus, OM System or Panasonic raw is read whole (tens of MB), four at a time on a batch. The behavior is unchanged: the whole-sensor size comes from the system decoder on the patched bytes, and working it out from the tags instead would be a second rule that has to match the decoder's extent exactly, with no real files here to check it. The test's title no longer says "read from the header". |
| C3 | Fixed, 05b0e8b | `SpotPastePlan` keeps the ids per reason (`otherSizeIDs`, `unknownSizeIDs`) and `reaching(_:)` narrows it to the photos the change wrote. `changeAdjustments` (and the measuring paste) hand `then` the versions written (`EditStackChange.after`'s keys: readable stacks only), and the warnings use that set. Unreadable stacks and originals a Color Alignment measurement could not read (or offline then) are reported once, by what left them out. Test: `spotPastePlanReachesWrittenPhotosOnly`. Scripted: a schema-99 photo of another size in the selection gave "1 photo was left unchanged: its edits can't be changed…" and the size-differs row counted 2, not 3. |
| C4 | Fixed for one photo, 05b0e8b; the many-photo case stays the known limit | A Spots paste that reaches one photo (the loupe's, or one selected) without Color Alignment measures both frames on the write chain (`changeAdjustments(preparing:then:)`: the transform is worked out inside `persist`, just before the write), so in the loupe its undo step is registered before `pasteAdjustments` returns and ⌘Z runs after the paste lands (narrowed by C5: in the grid, even with one photo selected, the frame question's catalog read, `writes.savedEditStacks` in `lensQuestionTask`, comes before the body, so a ⌘Z in that window undoes the step before the paste, the window every grid paste and preset has had since #87). Structural: `registerEditStacksUndo` is called synchronously and its undo is queued on the same ordered chain as the change. The loupe's own decode does not give the frame size (its live session decodes a reduced, often camera-framed image), so taking the target's frame from the editor was not possible without a wait. A paste onto several photos still measures first, with progress and Stop in Activity, and ⌘Z during that read undoes the step before the paste (the measuring paste's limit from #87; recorded in the user guide's Spots passage). A paste that also measures Color Alignment is as before. |
| F1 | Fixed, b034487 | `Spots were not pasted onto %lld photos: their size, or the size of the photo they were copied from, could not be read.` (1: `…onto %lld photo: its size, …`), new key and comment, the old key removed; at most two rows, the size-differs row first. No test pinned the old wording (the app target has no unit tests). Scripted: the source's master renamed before a paste: "…onto 5 photos: their size, or …" for the grid and "…onto 1 photo: its size, or …" for the loupe; a missing target master with two of another size: both rows, differs first. |
| F2 | Fixed, b034487 | `.help(CopyAdjustmentsText.pasteHelp(state.copiedSummary))` on the toolbar's Paste Adjustments item only. `CopyAdjustmentsText.list(_:)` is the one list function for the announcement and the tooltip (five names or fewer, else `%lld items`); key `Paste Adjustments: %@` with a comment; plain `Paste Adjustments` with nothing copied. `LibraryMenuState.copiedSummary` is what enables the item (`hasCopiedAdjustments` is now derived from it), so the tooltip follows the clipboard. Scripted: `print clipboard` prints the tooltip from that state: `'Paste Adjustments'` before a copy, `'Paste Adjustments: Spots, Distortion'`, then `'Paste Adjustments: Tone'` after another copy. Hovering the real item is M8 for QA or a person. |
| F3 | Fixed, b034487 | `AppKitCheckbox.accessibilityHelp: String??` (default: the tooltip, so the inspector's boxes are unchanged); the sheet's rows pass `.some(caption)`. Scripted (`print copysheet` now prints each box's VoiceOver help and tooltip): Crop & Straighten and Spots have their captions as help; every other row has no help and keeps its name as the tooltip. |
| F4 | Fixed, this commit | `docs/USER_GUIDE.md`: the Spots passage says a photo whose size can't be read (its original, or the copied-from photo's, offline or unreadable) keeps its spots, with its own Activity line after the size one; how a many-photo and a one-photo Spots paste measure, and the ⌘Z limit while a many-photo one measures. The sheet paragraph: VoiceOver says what was copied, the toolbar Paste item's tooltip names it, and a photo with no adjustments says so under the title. The Lens passage: a paste counts only the masks and spots a photo already has. |

Debug-script checks of these fixes: a copy of the bundle with
`CFBundleIdentifier` `me.sesser.gus.debugtest.copyadjust`, re-signed ad hoc, on
a fresh copy of a scratch library per run (`photobench generate` 3 JPEGs
1200×800 and 2 at 900×600, renamed SML_*, imported with `photobench import`;
`IMG_00001` and `SML_00001` carry EXIF orientation 6, so they are turned and
of another size), every launch with `--library-root`. Results as above. Not
scripted: the Color Alignment path with an unreadable original (it shares
`reaching` and `then` with the plain path) and the ⌘Z race itself (the script
waits after each paste; the C4 claim rests on the structural argument).

## Review findings (second round, 2026-11-22)

From the second passes of [code-review.md](code-review.md) (C5, C6, both
nits) and [review.md](review.md) (N1, a nit). Docs only: no source or test
changed, so no build or test was run for them.

| # | Outcome | What was done |
|---|---|---|
| C5 | Fixed (the record) | C4's row above and the user guide's Spots passage now say ⌘Z right after a one-photo Spots paste undoes the paste in the loupe; in the grid a catalog read still comes before the undo step is registered (as for every grid paste since #87), so a ⌘Z in that instant can undo the change before it. Nothing regressed; only the claim was too broad. |
| C6 | Known limit, not fixed | A one-photo Spots paste reads two files (the source's original and the target's) inside a write-chain step, with no progress and no Stop, so later saves, the loupe's photo loads and every `afterPendingWrites` wait for it: about a millisecond for a local JPEG, up to about 100 ms for a cropped RW2 or ORF on a local disk (read whole, see C2), seconds on a slow card reader or network share, and until the read fails on a share that has stopped answering. The source's frame is measured again on every paste, though it cannot change between pastes. Not fixed: measuring the source once at copy time would turn design §15 DQ-1's "offline at paste" rule into "offline at copy", a design change. The several-photo path reads outside the chain and has Stop. The user guide's Spots passage gains one sentence (slow card or share: no Stop, saving and moving to the next photo can wait a few seconds). Beside C4's many-photo ⌘Z limit, these are this feature's known limits. |
| N1 | Fixed (the user guide) | The Lens passage now reads: spots that Copy Adjustments… brings are not asked about; they are placed in the frame they had on the photo they were copied from, and a later Distortion change asks as usual (the review's wording). The old sentence implied the source's Distortion always came along, which holds only when the Lens group was copied too. |

## Requirements issues

None. The `hard` tag fits (spots across photos, the paste path with the write
chain and undo, file reads off the main actor).

## README

No change: no new requirement, build command or layout change.
