Issue: #241

# Preset list view: status

Owner: swift-macos-engineer. Branch `feature/preset-list-view` (off
`develop`). Spec: the PRD (issue #241, revised 2026-11-20) and
[design.md](design.md).

**State: Done** (2026-11-20). Every acceptance criterion is built and has a
unit test or a scripted check (below). Three checks only a person can make are
listed under "For a person". One design question (DQ-1, the button row wraps at
the default inspector width) is open and does not block. Next: code review and
the designer's review, then QA.

## Build and test

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline (branch at a58ce8d, before any change) | Pass | 1253 tests in 179 suites pass |
| Latest (2026-11-20) | Pass, no warnings | 1264 tests in 181 suites pass (the 11 new: `PresetsViewChoiceTests` 5, `PresetsBarGeometryTests` 6) |
| Bundle | `Scripts/build-app.sh` passes | |

No migration. `PreviewCacheKey.currentPipelineVersion` unchanged (13). No
golden touched, `UPDATE_GOLDENS` not run. No rendering changed.

## What was built

- **PhotoCore**
  - `Presets/PresetsViewChoice.swift`: `list` or `thumbnails`, stored under
    `adjust.presetsView`; `choice(stored:)` gives `list` for nothing stored,
    an unknown string or another type (design §6).
  - `Browser/PresetsBarGeometry.swift`: the button row's three arrangements
    (design §3) as a pure rule: needed widths, the first that fits, each
    item's frame. The switch is at the right edge and never on a push button.
- **PhotoApp**
  - `Views/PresetsSection.swift`: the switch (`AppKitSegmented` with symbols,
    `square.grid.2x2` and `list.bullet`, VoiceOver names Thumbnails and List,
    tooltips, label "Presets view"); the row laid out by `PresetsBarLayout`
    (a SwiftUI `Layout` over `PresetsBarGeometry`); each collection shows
    `PresetList` or `PresetGrid` by `LibraryModel.presetsView`;
    `PresetItemRules` holds what both views share (tooltip, applied mark) and
    `presetContextMenu` their context menu.
  - `Views/PresetList.swift`: `PresetList` (a `LazyVStack` of rows, no gaps),
    `PresetListRow` (representable) and `PresetListRowButton`, a subclass of
    `ImageTile.HoverButton` that draws the hover fill (`tertiarySystemFill`),
    the pressed fill (`secondarySystemFill`), the name (callout, label color,
    tail truncation, 20 pt kept for the mark) and the applied mark
    (`checkmark.circle.fill`, 12 pt, accent color), with a rounded focus ring.
    Return and Enter apply a focused row; Space is AppKit's own.
    `PresetListMetrics` holds the row's numbers and measures the heading's
    title inset from an AppKit button built like the heading.
  - `Views/AdjustControls.swift`: `ImageTile.HoverButton` is open for the row,
    exposes `isHovered` and `hoverDidChange()`, and has `simulateHover(_:)`
    for the debug script. Its behavior is unchanged.
  - `Views/CurveEditor.swift`: `AppKitSegmented` takes `symbols`: icon-only
    segments 28 pt wide each, the labels becoming the images' descriptions.
  - `Model/LibraryModel.swift`: `presetsView`, written to `UserDefaults` on
    change.
  - `Model/PresetPreviewModel.swift`: two debug counters only
    (`debugRenderedCount`, `debugHoverEnds`). `render`, `hover` and the 120 ms
    hold are unchanged.
  - `Model/AdjustmentEditor.swift`: `isPreviewing` readable and
    `debugPreviewValues`, for the debug script. `preview` and `endPreview` are
    unchanged.
  - `Model/DebugPresetViewCommands.swift` and `DebugScript.swift`: `preset view
    list|thumbnails|print`, `preset row <name> press|focus`, `preset heading
    <collection>`, `hover <x> <y>|name <preset>|end`, `print presetsbar`;
    `buttons` prints segment names, segment tooltips and a button's
    accessibility value; `print inspectorwidth` no longer reports a false
    overflow for a control held at the column's trailing edge, and draws
    icon-only segmented controls.
  - `Resources/Localizable.xcstrings` (PhotoUI): Presets view, Thumbnails,
    List, Show presets as thumbnails, Show presets as a list; the comment of
    Applied to this photo now names its second use.
- **Tests**: `PresetsViewChoiceTests` (5), `PresetsBarGeometryTests` (6).
- **Docs**: `docs/USER_GUIDE.md`, the Presets paragraph (both views, the
  default change for people used to thumbnails, the kept choice, hover, the
  mark, the context menu, keyboard, no pictures rendered in the list).

### Departures from the design's letter, same intent

- **One `Layout`, not `ViewThatFits`** (design §3, §8). `ViewThatFits`
  variant 2 would put the switch before Manage… in view order, so VoiceOver
  and the keyboard would reach it before Manage…; design §8 asks for it after
  Manage… in every variant. `PresetsBarLayout` keeps the four items in one
  order (Save, Import, Manage, switch) and places them in the same three
  arrangements, the first that fits. The rule is pure and unit-tested.
- **Names**: `PresetRow` already exists in the preset manager sheet, so the
  row is `PresetListRow` (and `PresetListRowButton`, `PresetListMetrics`).
- **The applied mark follows saves**. `editor.savedAdjustments` is not
  observed, so the list, which reads nothing else that changes on a save,
  never redrew its mark (found in a scripted run: no mark after applying).
  `PresetItemRules.markedAgainst` now also reads the open photo's saved hash,
  which is observed and changes after every save, undo and outside change.
  Still the saved values, never the live ones, so a drag redraws nothing. The
  thumbnails' outline uses the same helper; before, it followed only because
  their render key read the focused item.
- **The row's cell**: the row's title is its name (never drawn) and its
  accessibility value is set on the cell as well as the view, and the row
  keeps no on/off state, so whichever element VoiceOver reads names the
  preset and none says "1" after a press.

## Measurements (design §3, §4.2, §10)

On this Mac (macOS 27.2, the bundle from `Scripts/build-app.sh`, current
design), a fresh preferences domain: the inspector pane is 300 pt with a
legacy scroller showing, visible content 283 pt, the row's room 259 pt.

| | Measured | Design's estimate |
|---|---|---|
| Save…, Import…, Manage… (small push buttons) | 58.5, 67.5, 74.5 pt wide, 24 pt tall | |
| View switch | 56 pt (two 28 pt segments), 24 pt tall | about 56 pt |
| Arrangement 1 (one line) needs | 276.5 pt | roughly 260 pt |
| Arrangement 2 (switch beside Import…) needs | 196.0 pt | |
| Arrangement 3 (switch beside Manage…) needs | 138.5 pt | |
| Narrowest column, overlay scroller (256 pt room) | arrangement 2 | 2 |
| Narrowest column, legacy scroller (239 pt room) | arrangement 2 | 3 as the safety net |
| Default column here (259 pt room) | arrangement 2, gap to the switch 71 pt, clear | |
| One line from | a column of 300.5 pt (overlay), 317.5 pt (legacy) | |
| Rows | 22 pt, full width (259 pt here), no gap | 22 pt |
| Row name inset, no collection | 20 pt (push buttons' edge 12 + 8) | 8 pt in |
| Row name inset, under an open heading | 26.5 pt; the heading's title starts at 26.5 pt | where the title starts |
| 40 presets (10 + two collections of 15, both open) | list 946 pt; thumbnails 4,557 pt (21%) | 880 against about 2,180 |
| 10 presets, no collection | list 220 pt; thumbnails 1,067 pt | |

The thumbnails' height depends on the focused photo's shape: the test photo
gives tiles about 125 x 196 pt, taller than the design's 3:2 estimate. Before
this change Save…, Import… and Manage… needed 212.5 pt and fitted on one line
at every width; see DQ-1. `print inspectorwidth` still says `fits` with the
list open (the rows are the widest controls, 259 pt).

## Acceptance criteria

Scripted runs used a copy of the bundle with its own identifier
(`me.sesser.gus.debugtest.presetlist`, re-signed ad hoc), a `photobench`
library (`generate --jpeg 4 --dng 1`, 105 items with its default HEICs) seeded
by a script with 40 presets (10 without a collection, one with a long name;
Cool and Warm, 15 each, imported from folders), a fresh copy of that library
per run, and `--library-root` on every launch. The preferences domain was
deleted before the first run.

| AC | Check | Result |
|---|---|---|
| AC1 (R1) | `PresetsBarGeometryTests`: no overlap at any width from 60 to 420 pt in 0.5 pt steps, switch at the right edge, push buttons wrap as before. Scripted `print presetsbar`: the switch at the right of the first line, `clear`; needed widths and the arrangement at the narrowest column with both scrollers (table above). `buttons`: one `NSSegmentedControl` 'Presets view', `selected 1`, segments 'Thumbnails'/'List', tooltips 'Show presets as thumbnails'/'Show presets as a list'. Its accessibility: two `AXRadioButton`s named Thumbnails and List, with the tooltips as help | Pass. The look of the selected segment and the narrow inspector by dragging are for a person (P1, P2) |
| AC2 (R2, R3) | `PresetsViewChoiceTests` (nothing stored, both values, garbage, a number, a round trip through a defaults domain). Scripted: on the fresh domain `preset view print` says `list stored nothing`; `preset view thumbnails`, quit, relaunch: `thumbnails`; `preset view list`, quit, relaunch: `list` | Pass |
| AC3 (R4) | Scripted with Cool open: list shows the 10 rows, the Cool heading, its 15 rows in order, then Warm closed; thumbnails the same groups and order. `preset heading Warm` opens it in the list (40 rows, stored 1), the thumbnails show it open (40 tiles); closing Warm and Cool in the thumbnails (25, then 10 tiles, stored 0) shows them closed in the list (10 rows); opening both again gives 40 rows | Pass |
| AC4 (R5) | Scripted in the loupe: `preset row Look 03 press` (the button's press): undo 'Apply Preset Look 03', History 51 to 52 entries, top 'Apply Preset Look 03'. In the grid with one photo selected: undo 'Apply Preset Look 02', and that photo's History starts with it. Return on a focused row applies ('Apply Preset Look 06'). The context menu comes from the same modifier as the thumbnails' (`presetContextMenu`: Apply, Manage Presets…) | Pass. The debug script can't open SwiftUI context menus (thumbnails' included): P3 |
| AC5 (R6) | Scripted `hover name Look 03`, `Look 04`, `Look 05`, `end` in the loupe: each says `preview on loupe preview` (the loupe frame has the previewed values), `ends 0` while moving from row to row (the 120 ms hold ended no preview between them), then `preview off loupe saved ends 1`. Undo stack empty and History 51 entries before and after; the preview cache folder's file list identical before and after the run | Pass |
| AC6 (R6, R7) | Scripted: thumbnails in the loupe preview on hover and end on leaving, as before. During a crop session (`adjust crop begin`) hover previews in both views alike (the existing path, no rule added). In the grid, hover in both views: `preview off`, no render requested | Pass |
| AC7 (R8) | Scripted counter: a list-view launch shows `thumbnailRenders 0` with 10, 25 or 40 rows; switching to thumbnails renders 10, 25 or 40 pictures and the tiles appear; a relaunch in list renders 0 | Pass |
| AC8 (R9) | Scripted: after pressing Look 03 its row's accessibility value is 'Applied to this photo' (no other row has one); after `undo` none; after `redo` Look 03 again; after `adjust exposure 0.9` none | Pass. The mark's look: P1 |
| AC9 (R11) | Scripted: the switch's segments and the rows are AppKit controls with names (above); `preset row … focus` makes a row first responder (it accepts it); Return applies. Space is AppKit's own handling of a focused button: a scripted copy can't be made the active app here (`key nil`), so Space did nothing, for the thumbnails too | Pass for names, focus and Return; Tab order and Space with Full Keyboard Access: P2 |
| AC10 (R12) | Full `swift test`; no file under `Tests/PhotoCoreTests/Goldens` changed; no migration, no `currentPipelineVersion` change in the diff | Pass |

## For a person

- **P1** (design §14) Look of the row in Light, Dark and Increase Contrast:
  hover fill, pressed fill, the check mark, the focus ring, 22 pt density;
  the long name's tail truncation and its tooltip; the switch beside the push
  buttons and its selected segment.
- **P2** The inspector dragged to its narrowest, with and without a legacy
  scroller: the switch never on a push button, and where the row wraps. Tab
  with Full Keyboard Access reaches the switch after Manage… and then each
  row; Space applies a focused row; left and right arrows move between the
  segments.
- **P3** A real mouse: a sweep down a long list with the loupe watching (no
  flash of the original between rows), scrolling the list under a still
  pointer, a right-click on a row (Apply, Manage Presets…).

VoiceOver, macOS 15 and macOS 26 are covered by CI only (the owner's standing
ruling).

## Answers to the PRD's questions for the engineer

- Skipping the thumbnail renders needs no change to `PresetPreviewModel`: the
  list builds no `PresetGrid`, whose task is the only caller of `render`
  (AC7's counter is the only addition).
- A row that scrolls under a still pointer behaves as a thumbnail does: the
  same `HoverButton` and tracking area. Not scripted (P3).

## Design questions

- **DQ-1 (open, does not block).** The one-line arrangement needs 276.5 pt,
  not about 260. The default inspector column here is 300 pt: with an overlay
  scroller its room is 276 pt, half a point short, and with a legacy one
  259 pt. So at the default width the row takes two lines (Manage… under Save…),
  where before this change it was always one line (212.5 pt). Options:
  (a) accept, as the design expected at narrow widths (no cost);
  (b) a 7 pt least gap instead of 8 (one constant; one line at the default
  width with an overlay scroller, still two with a legacy one);
  (c) 26 pt segments (one constant; 4 pt less, same effect as b, smaller
  targets). Recommendation: (a), unless the designer wants one line at the
  default width for trackpad users, then (b).

## Requirements issues

None.

## README

Nothing for the README: no requirement, build command or layout change beyond
the new source files.
