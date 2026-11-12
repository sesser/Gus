Issue: #63

# Side by side comparison: status

Owner: swift-macos-engineer. Branch: `feature/side-by-side-comparison`. State: **Done**
(2026-11-12, after the first reviews). Every acceptance criterion is built and has a test or
a scripted check. The designer's rulings D1 to D8 (design §16) and fixes F1 to F3, and the
code review's findings C1 to C8, are answered under **Review findings**. One new **Design
question** (DQ-4) is open and blocks nothing. Next: the second pass by code-reviewer and
the designer, then qa-tester.

Spec: [`prd.md`](prd.md) (R1 to R9, AC1 to AC7, AC6a to AC6c, Decisions 1 to 12),
[`design.md`](design.md) (§1 to §16). R9 (three or four photos) is a Could and is not built;
panes, the switch key and the captions are indexed, as design §1 asks.

## Results

| | Baseline (branch point `c72d48e`, plus the PRD and design commits) | Now |
|---|---|---|
| `swift build` | clean, no warnings | clean, no warnings |
| `swift test` | 724 tests in 118 suites passed, 1 known issue | 768 tests in 119 suites passed, the same 1 known issue |
| `Scripts/build-app.sh all` | not run | both bundles built |

New suite: `ComparisonTests` (43 tests). `PaletteContrastTests` gained the ring's contrast.
No golden moved and no rendering changed: `PreviewCacheKey.currentPipelineVersion` is not
bumped. The panes show the renditions the single loupe shows, from the same
`PreviewService` calls with the same keys.

## What was built

- **PhotoCore** (no AppKit or SwiftUI, all tested):
  - `Browser/Comparison.swift`: `ComparisonState` (a version per pane, the active pane) and
    `ComparisonSide`; `ComparisonRules`: when the command is enabled (`canToggle`, by counts
    only), which two photos it compares or why it is refused (`entry`, `ComparisonRefusal`),
    the partner of a single photo, where a side walks, what a film strip click does, what a
    reload does to a comparison (`reconcile`), what the comparison selects (`selection`),
    and what Esc does; `ComparisonLink`: linked zoom and position in unit coordinates, and
    the stored preference (`compare.linksViews`, linked when absent); `ComparisonGeometry`:
    the two canvases, the gutter, the ring, the entering and leaving layout;
    `LoupeRendition`: the loupe's rendition ladder, moved here from `LoupeController` so the
    panes share it.
  - `Browser/ActionTargets.swift`: what a command acts on (the grid's selection, the loupe's
    photo), which `LibraryModel.actionTargets` now calls.
  - `BrowserSubtitle.comparing`.
- **PhotoApp**:
  - `Model/ComparisonActions.swift`: enter, stop, switch sides, walk, strip clicks, the
    link, the refusal alerts and the feature's words (`ComparisonText`).
  - `LibraryModel`: `comparison` (nil in the single loupe), the selection and focus while
    comparing, reloads, Advance After Rating, `closeLoupe`, each photo's last comparison
    (`comparisonMemory`, until the loupe closes).
  - `Loupe/ComparisonView.swift`: `ComparisonController` (layout, link, animations, keys,
    ring, VoiceOver) and `ComparisonPane` (a canvas loading the saved renditions).
    `Loupe/ComparisonCaption.swift`: the split caption and the link toggle.
  - `LoupeView` (panes in place of the canvas), `LoupeScrollView` (a first click on an
    inactive pane only activates it), the `S` key in the grid, loupe and video loupe.
  - `LibraryMenuState`, `LibraryCommands` (View ▸ Compare Side by Side / Stop Comparing,
    Switch to Right / Left Photo, Link Zoom and Position; Remove, Paste and Apply Preset off
    while comparing), `PhotoContextMenu` (grid, loupe, video loupe, and the pane's menu),
    `LibraryToolbar` (the palette item `compare`), `AdjustView`, `HistoryActions`,
    `WindowTitle`, `FilmStrip` and `FilmStripCell` (the compared cell, clicks, VoiceOver),
    `LibraryWindowObserver`.
- **PhotoUI**: 32 String Catalog keys (design §12, plus "Comparing %@ and %@. Right photo
  active."). The VoiceOver group's label reuses the existing key "Comparison" (the smart
  album editor's picker): one English word for two meanings, to split when the app is
  translated.
- **Debug script** (`Model/DebugComparisonCommands.swift`): `compare on|off|toggle`,
  `compare active left|right|switch`, `compare link on|off`, `compare animate on|off`,
  `compareclick left|right [x y]`, `compare panbench [seconds] [walking]`, `print compare`;
  `print menustate` gained `comparing`, `canCompare`, `linked`, `history`; `key` knows `s`,
  `a`, `f`, `c`.
- **photobench**: `compare` (the two full-resolution renders and what they hold).
- **Docs**: `docs/USER_GUIDE.md` (two rows in the key table, three paragraphs),
  `docs/PROFILING.md` (the measurements below and how to repeat them).

How it fits together: comparison is a state of the loupe (`mode == .loupe` and
`comparison != nil`). The focus is the active photo and the selection is the two photos, so
culling, the menus, the Info tab, the title and undo act on the active photo with no second
rule. While comparing, the single loupe's canvas is not in the view tree, so the editor
follows nothing: nothing can be edited, and the editor's full-resolution copy is released.

## Acceptance criteria

Unit tests are in `Tests/PhotoCoreTests/ComparisonTests.swift`. The model and the views are
in the app target, which the test target cannot import. Where a rule could move to PhotoCore
it did, and the model calls it, so the test fails if the rule changes; what the model and
views do with the rules is checked with the debug script against a copy of the bundle (its
own bundle identifier, `--library-root` on a scratch library from `photobench generate`).

| | Unit tests | Scripted check (result) |
|---|---|---|
| AC1 | `twoSelectedPhotosAreComparedInSourceOrder`, `activeIsTheLeftPhotoWhenFocusIsNeither`, `aLoadOnlyReplacesALesserRendition`, `panesAreEqualColumnsWithAGutterRoundEach` | `focus 1; key shift+right; compare on; print compare; snapshot`: both photos, the earlier one left, each pane at fit showing its preview; at 100% each shows `rendition full`. Pass. That a pane's picture equals the single loupe's is by construction (same requests); a person compares them by eye |
| AC2 | `commandsActOnTheActivePhotoOnly`, `theGridActsOnItsSelection`: `ActionTargets.indices` and `ComparisonRules.selection` are the rules `LibraryModel.actionTargets`, `selectComparison` and `apply` call, so a command that reached both compared photos would fail the test | `key 3; print items; undo; print items`: only the active photo's rating changes, undo reverts it. A VoiceOver culling action on the inactive pane makes it active first and changes only it. Pass. **Undo is covered by the script only** (the existing culling undo step, in the app target) |
| AC3 | `sameSizeFramesLineUpPixelForPixel`, `differentlySizedPhotosStayOnTheSameRelativePoint`, `theFollowerIsClampedToItsOwnBounds`, `linkedPanesTakeTheSameMagnification`, `aPhotoAsSmallAsItsPaneStillTakesTheOtherTo100Percent`, `theLinkIsOnUntilTurnedOff` | `key z; print compare`: both at 1.000 with the same visible unit rect; `pan`, `compareclick`, `zoomstep`, `optionscroll` keep the two centers equal (also a 2048 × 1365 JPEG beside a 6000 × 4000 raw, and an 800 × 600 JPEG whose fit is 1.000 beside a 2048 px one: `Z` takes both to 100% and `Z` again both to fit, from either side); `compare link off; key z`: one at fit, the other at 100%; `compare link on`: the inactive pane goes to the active one's. Pass |
| AC4 | `leavingKeepsTheCurrentPairSelectedAndTheActivePhotoFocused`: the selection the comparison holds (`ComparisonRules.selection`, which the model calls) is the pair on screen and the active photo, and back in the grid a command acts on both. That `stopComparing` leaves that selection alone and shows the single loupe is in the app target | `key s` while comparing: `compare off`, `mode loupe`, focus on the active photo, the pair on screen selected (also after a walk), the loupe's announcement. Pass. **The single loupe coming back is covered by the script only** |
| AC5 | `escLeavesReviewFirstAndComparisonStaysOn` | `review on; print compare; key 2; key a; key x; key escape; key f; key s`: comparison stays on through entering and leaving review, culling and `A` work in it, `S` in review leaves comparison and stays in review. Pass |
| AC6 | `aVideoIsRefusedAndNamed`, `anOfflinePhotoIsRefusedAndNamed`, `whenBothFailTheFirstPhotosFirstReasonIsGiven`, `aPhotoWithNothingToCompareWithIsRefused`, `theRefusalSaysWhetherOnePhotoOrTwoWereAsked`, `theCommandIsDimmedOnlyForCounts`, `theWrongCountEntersNothing` | A photo and a video selected, `compare on; alert`: "Can’t Compare These Photos", "“MVI_00010.MOV” is a video. Only photos can be compared.", one OK button, comparison not entered. From the video loupe's context menu: "Can’t Compare This Photo" with the same text. Pass. Offline: unit test only (no offline volume in the scratch library) |
| AC6a | `theTwoFilesOfOnePairAreRefused`, `thePartnerIsNeverTheOtherFileOfThePair`, `walkingNeverPutsTheOtherFileOfThePairBesideIt`, `aStripClickNeverPutsTheOtherFileOfThePairBesideIt`, `aSideFollowsItsPairsOtherFile` | `pairs separate`, both files selected, `compare on; alert`: "“PAIR_00013.DNG” and “PAIR_00013.JPG” are the RAW and JPEG files of one photo." Grouped, a pair compares like any photo, and RAW+JPEG Pair ▸ Show the JPEG File keeps the comparison, as does its undo after switching sides. Pass |
| AC6b | `theLoupesPhotoIsComparedWithItsPartnerWhateverIsSelected`, `oneSelectedPhotoIsComparedWithTheNextWhichIsActive`, `thePartnerIsThePreviousPhotoAtTheEndOfTheSource`, `thePartnerSkipsWhatCannotBeCompared`, `walkingSkipsTheOtherSideAndWhatCannotBeCompared`, `aStripClickWalksTheActiveSideOrSwitchesSides` | `loupe; key s; print compare`: the loupe's photo left, the next one right and active ("… Right photo active."); `key right` replaces the right photo. With one photo selected in the grid, `key s` does the same. A strip cell's press (VoiceOver's, the same handler as a click) replaces the active side's photo. Pass |
| AC6c | `commandsActOnTheActivePhotoOnly`, `thePartnerIsThePhotoLastComparedWith`, `aRememberedPairComesBackOnTheSameSidesWithTheSameOneActive` | `key a`: the ring, the caption and the focus move, "Left photo active: …" is announced; `key s; key s`: the same two on the same sides with the same one active, both when left with the right photo active and after `A`; after the grid the partner is the next photo again. Pass |
| AC7 | none (a measurement) | `compare panbench 6` and `compare panbench 8 walking`: see the next section. Pass against the proposed target, which is pending the owner (PRD Assumptions) |

Other rules with tests: reloads (`aReloadKeepsTheComparisonWhileBothPhotosRemain`,
`aPhotoLeavingTheSourceEndsTheComparisonOnTheOther`, `aRemovedPhotosNeighbourNeverTakesItsSide`;
scripted with a rating filter, a change of source and a removal), the layout and ring
(`enteringRefitsTheLoupesPhotoIntoItsPane`, `theRingSitsInTheGutterConcentricWithTheCanvas`),
the symbols (`symbolsResolve`, `symbolsDateFromBeforeMacOS15`), the subtitle
(`theSubtitleSaysComparing`), the ring's contrast
(`PaletteContrastTests.theComparisonRingStandsOutOnTheSurround`), every string
(`LocalizationTests`).

Also checked by script: the pane's context menu (photo items, zoom, Link Zoom and Position
checked, Stop Comparing; no adjust items, no Remove), the loupe's and the video loupe's
Compare Side by Side, the Adjust tab's Stop Comparing button, the toolbar item `compare`,
Advance After Rating moving the active side ("Picked. IMG_00003, no rating"), VoiceOver's
tree (`accessibility AXImage`, `AXGroup`: the group "Comparison", two panes with values such
as "Right photo, active, Picked, 2 of 15" and their actions, strip cells ending "Left
photo" / "Right photo"), `S` ignored during a crop session, and the single loupe unchanged
(zoom, walk, review, Esc).

### Not checked by me (for qa-tester or a person)

- **Everything animated, in the second round.** The checks of 2026-11-12 ran while the
  Mac's display was asleep, when AppKit animations and display links do not run (a zoom's
  animation never ends, `panbench` gets no frames). They used `compare animate off`, which
  makes zoom, refits, entering and leaving happen at once through the same code. So not
  run after the review fixes: the animated `Z` and zoom steps (they ran, and passed, on
  2026-11-11 before the fixes), the entering animation into the right pane (F1.3), and C4's
  check, which is only about the animated refit:
  `compare on; filmstrip off; wait 1; filmstrip on; wait 2; print compare` with the display
  awake; each pane should report `zoom fit` and a rendition that is not `full`. With
  `compare animate off` it does.
- **Menus with a key window.** A scripted launch is not the active app, and macOS refused
  to activate the test bundle while the Mac was in use (`print responder`: `key nil`), so
  the View menu's titles and enabled states were read only as `print menustate`. `menukey s`
  and `menukey a` (posted keys) did go through the first responder and worked.
- **Real mouse and trackpad**: a first click on the inactive pane (it must only activate),
  a drag starting there, scrolling and pinching over the inactive pane, a double-click.
  `compareclick` drives the pane's own mouse methods; real clicks on a window that is not key
  do not arrive.
- **The alert's keys.** `alert` finds the OK button but reports no key for it, and
  `alert key return` / `escape` leave it open: the probe does not reach `NSAlert`'s buttons
  on macOS 27. Return and Esc on a real key window are a person's check.
- **Looks**: the entering, leaving and relinking animations (0.15 s), the ring (accent,
  neutral while the window is not key, 3 pt with Increase Contrast), the caption giving up
  the position, then the name's middle, then the HDR badge as it narrows, the link toggle's
  bezel and size, the toolbar item.
- Reduce Motion, VoiceOver itself, the HDR badge on an EDR display, a photo going offline
  while compared, macOS 15 and 26.

## The PRD's questions for the engineer

### Speed of two 100% views, and a number for AC7

Measured on 2026-11-11 on an Apple M4 Pro (14 cores, 24 GB), macOS 27.2, external display
at 60 Hz, 2×, release builds, before the review fixes (which change no rendering and add
nothing to a pan step). Full tables and commands are in `docs/PROFILING.md`.

- **Panning never renders.** At 100% a pane shows one picture of the whole photo on a
  layer; a pan moves two layers, and the other pane follows through its scroll view. The
  preview service renders the two pictures off the main thread, one after the other.
- **Panning two sharp photos**: 6 s at 1,500 pt/s, linked, two 24 MP raws: 360 frames, 0
  hitches (a hitch is a frame over 1.5 refresh intervals), in each of 4 runs. Main-thread
  time per pan step, the follow included: mean 0.06 to 0.27 ms, worst 0.85 ms. Not linked:
  the same.
- **Until they are sharp**: both panes were sharp 0.29 to 0.42 s after zooming in (no
  adjustments). `photobench compare`: 183 ms for both without adjustments, 1.19 s with a
  typical stack. Until then each pane shows its preview enlarged, and panning works.
  These are synthetic DNGs; real camera raws decode slower and were not measured.
- **When a full-resolution picture arrives** (zooming in, or walking a side at 100%): two
  long frames per arrival, 99 to 155 ms the longest in each of 4 runs (14 long frames for
  8 walks in 8 s of panning, walking once a second). The panes put the picture
  on the layer as the single loupe's canvas does; I did not measure the single loupe.

**Proposed target for AC7 (the PRD now carries it, pending the owner):** on the reference
Mac above, with two raws at 100% and both sharp, `compare panbench 6` reports 0 hitches,
linked and not linked. That is what was measured; it leaves out the frames on which a
full-resolution picture arrives.

The owner's usual raw size is not something I know or measured: the numbers are for 24 MP.
The owner can repeat both with two of their own files (a copy):
`photobench compare --sources a.RW2:b.RW2`, and `compare panbench` in a scratch library that
holds them.

### Memory of two 100% views (the full-resolution copy has no cap)

- **The editor's uncapped copy is not held while comparing.** It belongs to live editing in
  the single loupe; entering comparison takes that canvas away and the editor lets go.
- **Each pane holds one full-resolution picture** once it has been zoomed past fit, until it
  shows another photo or comparison ends: 4 bytes a pixel (8 for an HDR picture on an EDR
  display). There is no cap. Two of them: 96 MB at 12 MP, 192 MB at 24 MP, 360 MB at 45 MP,
  488 MB at 61 MP, 800 MB at 100 MP; double in HDR. The preview service's memory cache
  keeps one full-resolution picture as before; it is one of the two, not a third.
- **Measured in the app** (two 24 MP raws, no adjustments): footprint 115 MB before, 1.05 GB
  the moment both were sharp, 354 MB a few seconds later. So about 240 MB to keep, and
  about 0.9 GB for a moment while rendering.
- **The renderer's working memory is the larger part**, and it is the single loupe's too:
  in `photobench compare` the footprint was 1.18 GB after one unadjusted 24 MP render and
  4.3 to 5.0 GB after one with a typical stack; the second photo added about 0.1 GB. I did
  not measure how much of that the app keeps after a render with adjustments.
- Not measured: raws above 24 MP, real camera raws, HDR pictures.

I recommend no cap in this slice: comparing adds one picture to what the loupe at 100%
already holds. If the owner's raws are much larger than 24 MP, measure first (the commands
above).

### How a RAW+JPEG pair resolves

Grouped, a pair is one item: its pane shows the file the pair shows in the grid, culling
reaches both files as everywhere else, and RAW+JPEG Pair ▸ Show the RAW / JPEG File (or its
undo) changes the pane's file and keeps the comparison, on either side. Shown as two items,
each file is a photo of its own, but the two files of one pair are never side by side:
selecting both is refused with the alert (RI-3), a partner or a walk skips the other side's
other file, and a strip click on it beeps.

## Review findings

### Design review (`review.md`; rulings in `design.md` §16)

| | Ruling or fix | Done |
|---|---|---|
| D1 | Esc outside review goes to the grid | As built; no change |
| D2, F3 | The ring's rule is 3:1 in every appearance | `theComparisonRingStandsOutOnTheSurround` requires 3:1 in the dark and the high-contrast dark appearance; the known-issue marker is gone (the suite is back to 1 known issue) |
| D3, D6, F1 | With one photo, the partner (right) is active; a remembered pair comes back as it was left | `ComparisonRules.entry` makes the partner active from the loupe, the video loupe and one selected photo (two selected: unchanged). The model keeps each photo's last comparison (`comparisonMemory`: both versions, their sides, the active side), updated on entering, switching sides and walking, forgotten when the loupe closes; `entry` returns it when the partner is the remembered one. The entering animation moves the pane the loupe's photo goes to (`enteringSide`), left or right, and the other fades in. Tests updated and `aRememberedPairComesBackOnTheSameSidesWithTheSameOneActive` added. `docs/USER_GUIDE.md` says so. Scripted: pass; the animation into the right pane was not run (display asleep) |
| D4, D7, D8 | Accepted as built | No change |
| D5, F2 | "Can’t Compare This Photo" when comparison was entered with one photo | `ComparisonRefusal.video` and `.offline` carry `alone`; `concernsOnePhoto` picks the title. Test `theRefusalSaysWhetherOnePhotoOrTwoWereAsked`; scripted from the video loupe's context menu and with a photo and a video selected |

RI-E2 is closed by D3: AC6b holds as written.

### Code review (`code-review.md`)

| | Finding | Done |
|---|---|---|
| C1 | A removal's next-focus photo took the active side | **Fixed.** `reconcile` no longer takes the reload's focus at all. A missing side is replaced only by its own pair's other file (`pairPartner`, read from the list before it is replaced, for items that stood for a grouped pair), and never by the other side's photo. Test `aRemovedPhotosNeighbourNeverTakesItsSide`. Scripted: comparing a photo of each project, `removephotos` on the active one (the same reload as a project's removal): `compare off`, the loupe on the remaining photo |
| C2 | Linked `Z` broke when the active photo is about its pane's size or smaller | **Fixed.** A pane keeps the zoom a command gives it, as the single loupe does; only a pinch or Option-scroll on the pane itself derives it from the magnification. Whether the follower goes to its own fit is `ComparisonLink.isFitted` (the leader's commanded zoom, and its magnification during a gesture), and linked panes share the zoom state. Test `aPhotoAsSmallAsItsPaneStillTakesTheOtherTo100Percent` (fit 1 and 0.97 beside 0.12). Scripted with an 800 × 600 JPEG at fit 1.000 beside a photo at fit 0.711: `Z` gives 1.000 and 1.000, `Z` again 1.000 (its fit) and 0.711, from either side, and the menu state follows |
| C3 | The AC2 and AC4 tests only checked accessors | **Fixed where unit-testable.** The targets rule moved to PhotoCore (`ActionTargets.indices`) and `LibraryModel.actionTargets` calls it; the comparison's selection is `ComparisonRules.selection`, called by `selectComparison` and `apply`. The tests check those, so returning the selection in the loupe fails `commandsActOnTheActivePhotoOnly`. Undo, and the single loupe coming back on leaving, stay in the app target: the table above now says they are covered by the scripted checks only |
| C4 | The animated refit after a film strip change ran outside the follow suspension | **Fixed by construction, not run.** Both panes' refits are one animation group in `layoutPanes`, and following stays suspended until its completion handler. The reviewer's check needs the display awake (see Not checked); with `compare animate off` each pane reports `zoom fit`, `rendition preview` |
| C5 | The pane's copy of the loupe's loading | The follow-up issue stands. One difference closed: `preloadNeighbors` now prefetches the HDR rendition as the loupe does |
| C6 | Two machine-dependent tests | The ring test no longer depends on which accent this Mac has set to pass: 3:1 against a lowest measured 4.47:1 (the accent as set) and 4.94:1 (the named colors). It can't choose the setting: `controlAccentColor` is read once per process (setting `AppleAccentColor` in the process's argument domain changed nothing), so the eight named system colors stand in for the other settings, and the test's comment says so. The symbol test is split: `symbolsResolve` always runs (on CI's macOS 15 that is the proof), and `symbolsDateFromBeforeMacOS15` is skipped, with the reason, where the private list is missing, reshaped or does not name the symbol. `FilmStripGeometryTests.toggleSymbolResolvesOnMacOS15` has the same dependency and is not part of this change |
| C7 | Undoing a pair switch after `A` ended the comparison | **Fixed** by C1's change: either side follows its pair's other file. Test `aSideFollowsItsPairsOtherFile`; scripted (`compare active left; pairfile jpeg; compare active right; undo; redo; undo`): the comparison and the active side stay |
| C8 | Commit hashes from before the rebase | This file names commits by subject |

Also changed in this round: `compare animate on|off`, and `compare panbench` now says so
instead of waiting for ever when the display link does not fire.

## Design questions (for apple-ui-designer)

**DQ-4. Remove Project from Library… while comparing.** File ▸ Remove Project from Library…
and the sidebar row's menu stay enabled while comparing; Remove from Library… and Remove
from Album (the photo commands) are dimmed, as design §4 says. With C1 fixed, removing a
project that holds a compared photo ends the comparison on the photo that remains, or
closes the loupe's photo as now when neither remains; removing another project changes
nothing on screen.
Options: (a) as built: the command is about the sidebar's project, it asks first, and the
comparison ends cleanly; (b) dim it while comparing too, for one rule ("nothing is removed
while comparing"). Cost: (b) is one condition in `LibraryCommands` and the sidebar's row
menu.
Recommendation: (a). §4's reason for dimming the photo commands is that they act on the
active photo, which this one does not.

## Requirements issues (for product-manager)

RI-E1 (AC7's number) and RI-E3 (the long frames when a full-resolution picture arrives) are
in the PRD as proposals pending the owner. RI-E2 is closed by D3. Nothing new.

## Deliberately not done

- R9 (three or four photos): a Could.
- No cap on the two full-resolution pictures (see Memory).
- No change to `PreviewService`: its cache still keeps one full-resolution picture; each
  pane keeps its own while it shows the photo.
- `ComparisonPane` loads renditions with its own copy of the single loupe's loading code
  rather than a shared type: `LoupeController` is tied to the editor (live frames, crop,
  masks, the magnifier), and pulling the loading out of it would have put the single loupe's
  behavior at risk in this change. Proposed as a follow-up.

## Proposed issues

- **Loupe: a full-resolution picture arriving costs one or two long frames**
  (`enhancement`): measured in comparison at 24 MP, 99 to 155 ms; the single loupe uses the
  same image view. Measure it there, then decide (tiles or a shared surface).
- **Measure and bound the renderer's working memory after a full-resolution render**
  (`enhancement`): 1.18 GB after an unadjusted 24 MP render and 4.3 to 5.0 GB with a typical
  stack in `photobench compare`; in the app 1.05 GB for a moment, 354 MB after (no
  adjustments). Existing behavior of the loupe's 100%.
- **Share rendition loading between the loupe's canvas and the comparison's panes**
  (`enhancement`): one type for "show this version's saved renditions, at fit or zoomed",
  with the fit margin and the zoomed-in threshold in one place.
- **Debug script: `alert` does not reach an `NSAlert`'s buttons** (`bug`, tooling): on macOS
  27 it reports no key for the default button, and `alert key return` leaves the alert open.
- **String Catalog: "Comparison" has two meanings** (`enhancement`): the smart album
  editor's picker and the comparison's VoiceOver group share a key; split before translating.
- **Tests: the film strip's symbol test reads a private system list** (`enhancement`):
  `FilmStripGeometryTests.toggleSymbolResolvesOnMacOS15` fails if a macOS release moves it;
  skip with a reason, as the comparison's now does.

## README

No change to requirements, build commands or the repository layout. `photobench` gained
`compare` (listed by `photobench help`); the README needs it only if it lists the
benchmark commands.

## Commits

By subject (`git log --oneline c72d48e..`): "Side by side comparison: rules in PhotoCore",
"… two panes in the loupe", "… benchmarks and user guide", "… status, Done", then, after the
reviews, "… review fixes".
