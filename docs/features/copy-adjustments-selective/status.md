Issue: #243 · Complexity: hard

# Copy Adjustments: choose what to copy: status

Owner: swift-macos-engineer. Branch `feature/copy-adjustments-selective` (off
`develop`). Spec: the PRD (issue #243, revised 2026-11-22: R1 to R14, AC1 to
AC12) and [design.md](design.md).

**State: Done** (2026-11-22). Every Must and Should requirement is built, and
R14's Could items as the design specifies them except the Paste tooltip (not
designed: DQ-2). Every acceptance criterion has a Swift Testing test or a
debug-script check (below). One Design question is open on a string I had to
add (DQ-1); nothing waits on it. Next: code-reviewer and the designer review,
then qa-tester.

## Build and test

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline (branch at ade878b, before any change) | `swift build --build-tests` passes | 1428 tests in 205 suites pass |
| Latest (2026-11-22) | Pass, no new warnings | 1449 tests in 206 suites pass (21 new, `CopyAdjustmentsTests`); `LibraryModalTests` expects the new modal |
| Bundle | `Scripts/build-app.sh` passes | |
| CI toolchain | `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` passes (2026-11-22; `/Applications/Xcode_26.3.app` is a symlink to `/Applications/Xcode-26.3.0.app`) | |

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
  applied for everything else), before turns, straightening and crop. It
  reads headers only (no decode). The Lens heading's corrections keep that
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
| AC8 (R7) | Done | Scripted: Distortion (Manual) and Color Grading copied, pasted on a photo with a spot: the frame question asks; Cancel writes nothing; Change pastes both. A paste without a Lens group never asks. Per-photo table reads and the "left unchanged" sentence are the unchanged `confirmingLensFrameChange` and lens paste paths (their tests and #87's checks); no real files with tables were used here. |
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

- **DQ-1 (open; a string not in §10).** A paste with Spots onto a photo whose
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
- **DQ-2 (R14's Paste tooltip, not built).** R14 lists "a tooltip on the
  toolbar's Paste item naming what was copied"; design §14 noted it as a Could
  "not specified" and gives no string. I did not invent one. If wanted: the
  string (for example "Paste Adjustments: %@", the list as the announcement
  builds it) and whether the menu item gets it too. Cost: one string and a
  `.help` on the toolbar item.

## Requirements issues

None. The `hard` tag fits (spots across photos, the paste path with the write
chain and undo, file reads off the main actor).

## README

No change: no new requirement, build command or layout change.
