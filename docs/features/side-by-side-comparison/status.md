Issue: #63

# Side by side comparison: status

Owner: swift-macos-engineer. Branch: `feature/side-by-side-comparison`. State: **Done**
(2026-11-11). Every acceptance criterion is built and has a test or a scripted check.
Nothing is blocked, but three **Design questions** (DQ-1 to DQ-3) and three
**Requirements issues** (RI-E1 to RI-E3) are open: each is built the way the spec's own
text says, and a different ruling is a small change. Next: code-reviewer and the designer,
then qa-tester.

Spec: [`prd.md`](prd.md) (R1 to R9, AC1 to AC7, AC6a to AC6c, Decisions 1 to 12),
[`design.md`](design.md) (§1 to §15). R9 (three or four photos) is a Could and is not built;
panes, the switch key and the captions are indexed, as design §1 asks.

## Results

| | Baseline (`fc65c9b`) | Now |
|---|---|---|
| `swift build` | clean, no warnings | clean, no warnings |
| `swift test` | 724 tests in 118 suites passed, 1 known issue | 762 tests in 119 suites passed, 2 known issues (the same one, and DQ-2 below) |
| `Scripts/build-app.sh all` | not run | both bundles built |

New suite: `ComparisonTests` (37 tests). `PaletteContrastTests` gained the ring's contrast.
No golden moved and no rendering changed: `PreviewCacheKey.currentPipelineVersion` is not
bumped. The panes show the renditions the single loupe shows, from the same
`PreviewService` calls with the same keys.

## What was built

- **PhotoCore** (no AppKit or SwiftUI, all tested), `Browser/Comparison.swift`:
  - `ComparisonState` (a version per pane, the active pane) and `ComparisonSide`.
  - `ComparisonRules`: when the command is enabled (`canToggle`, by counts only), which
    two photos it compares or why it is refused (`entry`, `ComparisonRefusal`), the partner
    of a single photo, where a side walks, what a film strip click does, what a reload does
    to a comparison (`reconcile`), and what Esc does.
  - `ComparisonLink`: linked zoom and position in unit coordinates, and the stored
    preference (`compare.linksViews`, linked when absent).
  - `ComparisonGeometry`: the two canvases, the gutter, the ring, the entering and leaving
    layout.
  - `LoupeRendition`: the loupe's rendition ladder, moved here from `LoupeController` so
    the panes share it. `BrowserSubtitle.comparing`.
- **PhotoApp**:
  - `Model/ComparisonActions.swift`: enter, stop, switch sides, walk, strip clicks, the
    link, the refusal alerts and the feature's words (`ComparisonText`).
  - `LibraryModel`: `comparison` (nil in the single loupe), the selection and focus while
    comparing, reloads, Advance After Rating, `closeLoupe`.
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
  active." for an entry with the right photo active, which the grid's two-photo entry can
  give). The VoiceOver group's label reuses the existing key "Comparison" (the smart album
  editor's picker): one English word for two meanings, to split when the app is translated.
- **Debug script** (`Model/DebugComparisonCommands.swift`): `compare on|off|toggle`,
  `compare active left|right|switch`, `compare link on|off`, `compareclick left|right [x y]`,
  `compare panbench [seconds] [walking]`, `print compare`; `print menustate` gained
  `comparing`, `canCompare`, `linked`, `history`; `key` knows `s`, `a`, `f`, `c`.
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
in the app target, which the test target cannot import, so what they do end to end is
checked with the debug script against a copy of the bundle (its own bundle identifier,
`--library-root` on a scratch library from `photobench generate`: 6 JPEGs, 6 DNGs of
6000 × 4000, 2 RAW+JPEG pairs, 1 video).

| | Unit tests | Scripted check (result) |
|---|---|---|
| AC1 | `twoSelectedPhotosAreComparedInSourceOrder`, `activeIsTheLeftPhotoWhenFocusIsNeither`, `aLoadOnlyReplacesALesserRendition`, `panesAreEqualColumnsWithAGutterRoundEach` | `focus 1; key shift+right; compare on; print compare; snapshot`: both photos, the earlier one left, each pane at fit showing its preview; at 100% each shows `rendition full`. Pass. That a pane's picture equals the single loupe's is by construction (same requests); a person compares them by eye |
| AC2 | `commandsActOnTheActivePhotoOnly` | `key 3; print items; undo; print items`: only the active photo's rating changes, undo reverts it. A VoiceOver culling action on the inactive pane makes it active first and changes only it. Pass |
| AC3 | `sameSizeFramesLineUpPixelForPixel`, `differentlySizedPhotosStayOnTheSameRelativePoint`, `theFollowerIsClampedToItsOwnBounds`, `linkedPanesTakeTheSameMagnification`, `theLinkIsOnUntilTurnedOff` | `key z; print compare`: both at 1.000 with the same visible unit rect; `pan`, `compareclick`, `zoomstep`, `optionscroll` keep the two centers equal (also a 2048 × 1365 JPEG beside a 6000 × 4000 raw); `compare link off; key z`: one at fit, the other at 100%; `compare link on`: the inactive pane goes to the active one's. Pass |
| AC4 | `leavingKeepsTheCurrentPairSelectedAndTheActivePhotoFocused` | `key s` while comparing: `compare off`, `mode loupe`, focus on the active photo, the pair on screen selected (also after a walk), the loupe's announcement. Pass |
| AC5 | `escLeavesReviewFirstAndComparisonStaysOn` | `review on; print compare; key 2; key a; key x; key escape; key f; key s`: comparison stays on through entering and leaving review, culling and `A` work in it, `S` in review leaves comparison and stays in review. Pass |
| AC6 | `aVideoIsRefusedAndNamed`, `anOfflinePhotoIsRefusedAndNamed`, `whenBothFailTheFirstPhotosFirstReasonIsGiven`, `aPhotoWithNothingToCompareWithIsRefused`, `theCommandIsDimmedOnlyForCounts`, `theWrongCountEntersNothing` | A photo and a video selected, `compare on; alert`: "Can’t Compare These Photos", "“MVI_00015.MOV” is a video. Only photos can be compared.", one OK button, comparison not entered. The same from the video loupe's context menu. Pass. Offline: unit test only (no offline volume in the scratch library) |
| AC6a | `theTwoFilesOfOnePairAreRefused`, `thePartnerIsNeverTheOtherFileOfThePair`, `walkingNeverPutsTheOtherFileOfThePairBesideIt`, `aStripClickNeverPutsTheOtherFileOfThePairBesideIt` | `pairs separate`, both files selected, `compare on; alert`: "“PAIR_00013.DNG” and “PAIR_00013.JPG” are the RAW and JPEG files of one photo." Grouped, a pair compares like any photo, and RAW+JPEG Pair ▸ Show the JPEG on the active photo keeps the comparison (`theActiveSideFollowsItsPairsOtherFile`). Pass |
| AC6b | `theLoupesPhotoIsComparedWithItsPartnerWhateverIsSelected`, `oneSelectedPhotoIsComparedWithTheNext`, `thePartnerIsThePreviousPhotoAtTheEndOfTheSource`, `thePartnerSkipsWhatCannotBeCompared`, `walkingSkipsTheOtherSideAndWhatCannotBeCompared`, `aStripClickWalksTheActiveSideOrSwitchesSides` | `loupe; key s`: the loupe's photo left, the next one right. Arrows, Home, End and a strip cell's press (VoiceOver's, the same handler as a click) replace the active side's photo; a press on the other side's cell makes that side active. Pass, with DQ-3: the keys and the strip act on the active side, which is the left one right after entering |
| AC6c | `commandsActOnTheActivePhotoOnly`, `thePartnerIsThePhotoLastComparedWith` | `key a`: the ring, the caption and the focus move, "Right photo active: …" is announced; `key s; key s`: the same pair comes back; after closing the loupe the partner is the next photo again. Pass |
| AC7 | none (a measurement) | `compare panbench 6` and `compare panbench 8 walking`: see the next section. Pass against the proposed target; the target is an assumption until the owner accepts it (RI-E1) |

Other rules with tests: reloads (`aReloadKeepsTheComparisonWhileBothPhotosRemain`,
`aPhotoLeavingTheSourceEndsTheComparisonOnTheOther`; scripted with a rating filter and a
change of source), the layout and ring (`enteringRefitsTheLoupesPhotoIntoItsPane`,
`theRingSitsInTheGutterConcentricWithTheCanvas`), the symbols on macOS 15
(`symbolsResolveOnMacOS15`), the subtitle (`theSubtitleSaysComparing`), the ring's contrast
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

Measured on an Apple M4 Pro (14 cores, 24 GB), macOS 27.2, external display at 60 Hz, 2×,
release builds. Full tables and commands are in `docs/PROFILING.md`.

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

**Proposed target for AC7 (assumption until the owner accepts it):** on the reference Mac
above, with two raws of the owner's usual size at 100% and both sharp, `compare panbench 6`
reports 0 hitches, linked and not linked. That is what was measured; it leaves out the
frames on which a full-resolution picture arrives (RI-E3).

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
reaches both files as everywhere else, and RAW+JPEG Pair ▸ Show the RAW / JPEG File on the
active photo changes the pane's file and keeps the comparison. Shown as two items, each file
is a photo of its own, but the two files of one pair are never side by side: selecting both
is refused with the alert (RI-3), a partner or a walk skips the other side's other file,
and a strip click on it beeps.

## Design questions (for apple-ui-designer)

**DQ-1. Esc while comparing, outside review.** Design §1 says Esc "backs out one level" as
in the loupe and that comparison is not a mode; §4 lists Return, Space, double-click and ⌘↩
as going to the grid but not Esc. Built: Esc leaves review first, otherwise goes to the grid
(the two photos stay selected), exactly as in the loupe.
Options: (a) as built; (b) Esc stops comparing first (comparison, then the loupe, then the
grid). Cost: one line either way (`ComparisonRules.escape`, with its test).
Recommendation: (a), since `S` already toggles and the design says comparison adds no level;
but (b) is what "one level" suggests to someone who thinks of comparison as a view.

**DQ-2. The ring's contrast with Increase Contrast.** Design §10 asks for 3:1, and 4.5:1
with Increase Contrast, and for both ring colors in `PaletteContrastTests`. Measured against
the 0.09 surround: neutral (`secondaryLabelColor`) 6.09:1; `controlAccentColor` as this Mac
has it (the default blue) 4.47:1, the same in the high-contrast appearance, since the accent
color does not change with it. The system's eight accent colors as dynamic colors are 4.94:1
(purple) to 12.7:1 (yellow). So the default accent misses 4.5:1 by 0.03; it passes 3:1
(WCAG's figure for non-text). The same accent draws the grid's and the film strip's
selection borders, which no test covered before.
Options: (a) accept 4.47:1 and state the rule as 3:1 for the ring; (b) with Increase
Contrast draw the ring in a lighter color (`systemBlue`'s dark variant is 5.55:1, or the
label color), which then differs from the grid's and the strip's border unless they change
too; (c) blend the accent toward white with Increase Contrast, here and in the grid and the
strip. Cost: (a) none; (b) and (c) a few lines and a palette entry, plus the grid and strip
for consistency. The test records the gap as a known issue (it depends on the Mac's accent
setting) until this is ruled.
Recommendation: (c) if 4.5:1 is meant strictly, else (a).

**DQ-3. Which side the arrows and the strip change right after entering from the loupe.**
§3's table makes the loupe's photo (left) the active one, and §6 and §7 make the arrows and
strip clicks act on the active side. But §3 also says the second photo is chosen by walking
"the right side" or clicking a thumbnail "to put it there", and AC6b says the same. Built:
the table and §6/§7. So after `S` from the loupe, the arrows and the strip replace the
*left* photo (the one that was in the loupe); to choose another second photo, press `A` (or
click the right photo) first.
Options: (a) as built; (b) entering from the loupe or from one selected photo makes the
partner (right) pane active, so the arrows and the strip pick the second photo at once, at
the price of the next culling key hitting the partner instead of the photo the person was
on (what §3 set out to avoid); (c) keep the left active for culling but let the arrows and
strip act on the right side until `A` is pressed, which is a second rule. Cost: (b) one
line and two tests; (c) more state and more to explain.
Recommendation: (a) or (b), not (c); (b) matches the PRD's words.

Smaller points, built as stated, to confirm:

- **VoiceOver's group** (§10) holds the two panes; the film strip and the caption row
  follow it as siblings rather than sitting inside it. Putting them inside means making the
  loupe's whole SwiftUI stack one accessibility container, which changes the single loupe's
  tree too, and SwiftUI's tree can't be read by the debug script.
- **A single photo that is itself a video or offline** (the video loupe's Compare Side by
  Side, one selected video): the table's only video and offline rows are used, so the title
  is "Can’t Compare These Photos" for one photo.
- **Leaving with the right photo active and pressing `S` again** brings the same two photos
  back with their sides swapped (the loupe's photo is always left, §3).
- **The link toggle** sits between two captions of equal width rather than over them, so it
  is on the seam and a long name can never run under it.
- **A click's zoom** keeps the clicked point under the pointer, as the single loupe does;
  both panes zoom about the same unit point.

## Requirements issues (for product-manager)

**RI-E1. AC7's number.** Proposed above: 0 hitches in a 6 s pan of two sharp 100% views on
the reference Mac. It needs the owner's acceptance, and "the owner's usual size" needs a
number (I measured 24 MP).

**RI-E2. AC6b's wording.** "Walking the right side with the arrow keys or clicking a film
strip thumbnail replaces the right photo" holds once the right side is the active one, not
right after `S` from the loupe (DQ-3). Either the criterion says "the active side", or the
design changes which side is active on entering.

**RI-E3. Does AC7 cover the moment a full-resolution picture arrives?** Two frames of about
0.1 to 0.16 s per arrival were measured while panning and walking at 100%. If R8 means no
long frame at all while two raws are at 100%, that is new work in how the loupe puts a
24 MP picture on screen (tiles, or a surface the layer shares), for the single loupe as
well, and belongs in its own issue.

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
  (`enhancement`): one type for "show this version's saved renditions, at fit or zoomed".
- **Debug script: `alert` does not reach an `NSAlert`'s buttons** (`bug`, tooling): on macOS
  27 it reports no key for the default button, and `alert key return` leaves the alert open.
- **String Catalog: "Comparison" has two meanings** (`enhancement`): the smart album
  editor's picker and the comparison's VoiceOver group share a key; split before translating.

## README

No change to requirements, build commands or the repository layout. `photobench` gained
`compare` (listed by `photobench help`); the README needs it only if it lists the
benchmark commands.

## Commits

`93cca7a` rules in PhotoCore and their tests; `cca0b91` the app; `85d5cb8` benchmarks, user
guide and profiling notes; then this file.
