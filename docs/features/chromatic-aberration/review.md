# Chromatic aberration and color fringe removal: designer review

Owner: apple-ui-designer. Date: 2026-11-08. Step 4 of `docs/WORKFLOW.md`.
Reviewed: PR #48, `feature/chromatic-aberration` at `7bbdfe5`, against
[`design.md`](design.md) (DR1–DR21, §19, §20) and [`prd.md`](prd.md) (AC1–AC31),
with [`status.md`](status.md) as the engineer's record. Second pass:
`git diff 7bbdfe5 10c4013`, recorded under "Fixes confirmed" below.

**How this was reviewed.** Code was read, not run: the designer doesn't build
(`CLAUDE.md`), and no bundle was launched. Every verdict below is from reading the
source, the String Catalog, `docs/USER_GUIDE.md` and the debug-script results
status.md records. "Pass" means the code does what the design says. Nothing about
how it looks or feels on screen has been seen; that is what the manual checks are
for. Findings F1–F3 come from reading code paths, so confirm each one at the app
when fixing it.

## Verdict

**Passes the design. F1–F5 and DR22 are confirmed from code at `10c4013`, and no
design finding is open.** What remains is the on-screen list below: nobody on the
design side has seen this run, and the magnifier's legibility and feel (M3, M8) are
still the biggest open question. The first pass found three fixes to make before
merge and two small ones; they are kept below as the record.

## Findings

Severity: Medium means the person sees wrong behavior on a normal path. Low means
an edge case or polish.

| # | Severity | Finding | Departs from | Where | Must fix |
|---|---|---|---|---|---|
| F1 | Medium | **The crosshair doesn't follow a zoom while picking.** Cursor rects are invalidated only when the picking slot changes. The rect is on the scroll view, whose own frame doesn't change when the photo zooms, so it keeps the photo's area from the moment of arming. Arm at fit and press Z (the path the guide suggests): the parts of the photo outside the old rect show the arrow, though the magnifier is there and a click picks. Arm at 100% and press Z: the crosshair covers the surround, where a click does nothing and no magnifier shows. The pointer then says the opposite of what a click does (HIG Pointing devices: the pointer's shape signals the action available). **Fix:** invalidate the scroll view's cursor rects whenever the photo's rect on screen changes, from the zoom path or the existing `visibleRectChanged` | §4 step 2; §4 input table (zoom "work as always"); §20 "the same rect as the crosshair"; DR3 | `Sources/PhotoApp/Loupe/LoupeView.swift:425`, `:1093` | Yes |
| F2 | Medium | **Esc doesn't cancel picking from an inspector control.** Esc is handled only by the loupe's `handle(_:)`. With Keyboard Navigation or Full Keyboard Access, arming with Space leaves focus on the eyedropper, and the row's new pop-up and the slot menu are also in the inspector. There, Esc does nothing, while the caption directly below says "Press Esc to cancel." Keyboard users are the people this path is for. **Fix:** cancel picking on Esc while an inspector button or pop-up has the keyboard (for example `cancelOperation` up the responder chain, or a local monitor while picking). Text fields keep their own Esc first, as §4 says; a pop-up with its menu open keeps Esc to close the menu | §4 input table, Esc row ("Works while the loupe or an inspector button has the keyboard"); §11 "Esc also cancels picking"; DR14 | `Sources/PhotoApp/Loupe/LoupeView.swift:866`, `:899` | Yes |
| F3 | Medium | **The grid draws over the empty area beyond the photo.** `gridLayer` covers the whole picture at 800% and 1600%, including cells beyond the photo or crop. At a corner, half the ring shows a gridded dark area that reads as near-black pixels. That is the one thing R29 and the hairline exist to prevent: the person must be able to tell where the photo ends. **Fix:** draw grid lines only around cells that hold a photo pixel | §20 "Beyond the photo or its crop" (surround color, no pixels); R29; DR16 | `Sources/PhotoApp/Loupe/PixelMagnifierView.swift:119–131` | Yes |
| F4 | Low | **Show Sharpening Map while the fringe map is suspended leaves picking on.** With the fringe map shown and an eyedropper armed, the early branch of `showMap` switches the map but doesn't cancel picking, unlike the path below it. The sharpening map is then on screen with the crosshair and magnifier, and a click picks from a photo the person can't see. §4 keeps the eyedropper and the sharpening map apart. **Fix:** cancel picking when the switch is to the sharpening map, in both branches | §4 "Where picking is unavailable"; §6 "How the map interacts"; DR8 | `Sources/PhotoApp/Model/AdjustmentEditor.swift:559–561`, compare `:567` | Yes, one line |
| F5 | Low | **The row's context menu differs from the ⋯ menu.** The header is a plain `Text`, not a section header, and Purple and Green carry no swatch. §3 asks for the same items, and §15 for one set of entries. **Fix:** use a `Section` with the title, and give the two items their swatch image if SwiftUI context menus keep it (otherwise record that it doesn't) | §3 "The slot menu"; §15 "Slot menu"; DR2 | `Sources/PhotoApp/Views/LensControls.swift:178`, `:181` | Header yes; swatch if possible |

## Fixes confirmed (`10c4013`)

Confirmed from code only, as before: read in the diff, with the engineer's unit and
debug-script results in status.md "Review round (PR #48)" as evidence. Nothing was
built or launched here.

| Item | State | What was checked |
|---|---|---|
| F1 crosshair and zoom | **Confirmed** | `visibleRectChanged` now invalidates the scroll view's cursor rects while picking. Zoom and pan both change the clip view's bounds, so Z, ⌘= / ⌘−, pinch and scrolling all reach it, and the rect is now in document coordinates. Seen on screen: M8 |
| F2 Esc from the inspector | **Confirmed** | See below |
| F3 grid over empty area | **Confirmed** | `Picture.gridLines` draws only along cells that hold a photo pixel, in runs clipped to the picture. The hairline still marks the edge on the surround side. Unit test at corners, and the engineer's snapshot. Seen on screen: M3 |
| F4 sharpening map while suspended | **Confirmed** | The early branch of `showMap` now cancels picking when switching to the sharpening map, as the path below it does |
| F5 context menu | **Confirmed in structure; swatch color needs M4** | A real `Section` header, and Purple and Green get a `Label` with the swatch; Clear dims; order and single separators match the ⋯ menu (script: `[section]`, `[image]`). The script shows that an image is there, not that SwiftUI keeps its palette color in a menu |
| DQ-4, DR22 | **Confirmed** | See below |
| Grid inside the outlined pixel | Not taken | It was optional, and stays open as a judgment call. No action |

**F2, the key monitor, against §4 and §11.** The monitor exists only while picking,
and is removed when picking ends and when the loupe closes. It takes Esc only when
the event is for the library window and the first responder isn't a text view.

| What might own Esc | Result | Why |
|---|---|---|
| A text field (Tolerance, a search field, a rename) | Keeps it | The field editor is an `NSText`, so the event passes. The first Esc hands the keyboard back and the next cancels, as §4 says |
| An open pop-up, ⋯ menu, context menu or menu bar menu | Keeps it; picking stays on | Apple's documentation: a local monitor's handler is "not called for events that are consumed by nested event-tracking loops such as control tracking, menu tracking" |
| A sheet (Export, look-up tables, presets, smart album, alerts, open panels) | Keeps it; picking stays on | A sheet is its own window, so `event.window` differs. Every `.cancelAction` in the app is inside a sheet |
| A popover (⌘K keywords, Activity) | Keeps it | Popovers are their own windows |
| The Import window | Keeps it | Another window |
| The crop session | Can't coincide | A crop session ends picking |
| The fringe map, review, closing the loupe | Picking goes first | The DR14 order: only the next Esc reaches them |

It goes further than §4 said: Esc now also works with the keyboard in the sidebar,
toolbar or film strip. Nothing there owns Esc outside a text field, and picking is a
mode of the whole window, so this is better than what I specified. §4's Esc row is
updated to say it. The monitor doesn't check modifiers, so ⌘Esc also cancels; that
is harmless.

**DQ-4.** The failure branch is reached only for the render picking is waiting for.
It ends picking and then sets the flag, so ending doesn't wipe it, and announces
once. Ending picking also clears the sample key, so arming again retries. A click
waiting for those pixels gets none and fails its check that the slot is still
picking, so it is dropped with no undo step.

- **Caption order:** after every picking caption and before the fringe map legend, as ruled.
- **Clearing:** on arming, on any change (`change`, and both undo and redo paths), and
  on another photo. A hover preview or showing the map doesn't clear it, which is right.
- **Text:** the string, its catalog entry and the guide's sentence match the ruling.
- Pixels already held keep working after an eject (engineer's script).

## Improvements (judgment, not violations)

- **Keep the grid out of the outlined pixel.** Grid lines fall on each cell's first
  device row and column, so the outlined pixel has a 30% gray line along two of its
  inner edges at 800% and 1600%. §20 wants that pixel unobstructed, though it says so
  only of the outline. Skipping the lines at that cell is cheap, and F3's change
  touches the same code.
- **If the held pixels can't be made.** Ruled as design.md §19 DQ-4, and built;
  confirmed above.

## What's working

- **One rule for click and outline** (`FringePicker.pickedPixel`), with the snap gone
  and the picture always re-centered on the pixel taken.
- **The reuse boundary** is clean: `PixelMagnifierTool` supplies image, rule, verdict
  and note, and the level, keys and menus belong to the magnifier (R34).
- **The plate never changes size,** refusals included, and the refusal doesn't rely
  on color.
- **Placement** is pure and tested (flips, hysteresis, clamp), and the magnifier takes
  no clicks, focus or accessibility element.
- **DQ-2's row** reuses the export's layout and strings, as ruled.
- **Strings:** every §12 key is in the catalog, and reused keys had their comments
  extended as §12 asks.

## Design checks

| # | Check | Result |
|---|---|---|
| DR1 | Lens heading, groups, mixed box, Reset Lens | Pass (code); glass pane is M4 |
| DR2 | Slot rows and the slot menu | Pass (F5 confirmed); swatch color is M4 |
| DR2a | The list | Pass (code); look is M4 |
| DR2b | No-pointer fringe task | Pass (code); M5 (with PRD M2) |
| DR3 | Picking gestures | Pass (F1 confirmed). Real clicks are M1 |
| DR4 | The pixel rule | Pass (`PixelMagnifierTests` AC18, `ColorFringesTests` "The pixel rule") |
| DR5 | Replacing a pick | Pass (code); M6 at 100% on a large photo |
| DR6 | Fringe Map commands and enablement | Pass (code) |
| DR7 | Map look, badge, legend | Pass (code, status.md); look is M4 |
| DR8 | One map slot | Pass (F4 confirmed) |
| DR9 | Color Alignment states and captions | Pass (code) |
| DR10 | Paste and presets | Pass (code, status.md) |
| DR11 | Keyboard and VoiceOver | Needs manual check: M5 |
| DR12 | Increase Contrast, Reduce Motion | Needs manual check: M3 |
| DR13 | Strings and guide terms | Pass |
| DR14 | Esc order | Pass (F2 confirmed); by hand in M5 |
| DR15 | Magnifier shows and hides | Pass (code, status.md) |
| DR16 | Placement, corners, nothing beyond the photo | Pass (F3 confirmed); look is M3 |
| DR17 | Picture, center, grid levels, outline | Pass (code, tests); legibility is M3 |
| DR18 | Plate states | Pass (code, tests); not-ready is M2 |
| DR19 | Level on every path | Pass (code, status.md) |
| DR20 | No focus, no element, announcements | Pass (code, status.md); speech is M5 |
| DR21 | Increase Contrast; terms | Terms pass; contrast is M3 |
| DR22 | The pixels can't be made (DQ-4) | Pass (code, status.md script); caption seen in M9 |

**§19 rulings.** DQ-1: the guide's sentence is the one ruled. DQ-2: built as ruled
(one warning row, plural summary, per-file lines to the limit, "And N more.",
VoiceOver hears the summary, nothing on Stop, offline row first). DQ-3: title
confirmed, and Apply Preset's toolbar title is fitted. Seeing that title needs M7.

**Acceptance criteria.** AC1–AC15 and AC16–AC31 are built and mapped to tests or
debug-script checks in status.md. QA runs those. From the design side, AC16, AC24,
AC25 and AC27 were affected by F1 and F3 only, both now confirmed; none is
contradicted by the code. AC27's real click while the magnifier is clamped is M1.

**User guide.** Terms match §1 and §12: Lens, Color Fringes, Color 1 / Color 2,
Tolerance, Fringe Map, Color Alignment, Align automatically, Red/cyan, Blue/yellow,
Pixel magnifier (row), View ▸ Pixel Magnifier (menu). The snap sentence is replaced
with §20's text, the added passage and the key-table row are in, and no mention of
the snap remains. "Before edits" and "Almost no color" are explained. At `10c4013` a
sentence covers DQ-4 in the same terms. No changes needed.

## On-screen checks for a person

None of these has been seen by the designer. Run them on the bundled app, against a
copy with its own bundle identifier and a scratch library, always with
`--library-root`. These are this review's own numbers; the PRD's M1–M3 are named as
"PRD M1" and so on.

| # | Check | Where |
|---|---|---|
| M1 | **Real input (AC27, DR3).** With the magnifier showing: a click picks; a drag pans and the magnifier follows; a double-click picks once and stays in the loupe; right-click opens the context menu with Pixel Magnifier ▸ and picking stays on, the magnifier staying put while the menu is open and updating when a level is chosen. In a window small enough to clamp it, a click over its drawing picks | Owner's Mac, `open` launch |
| M2 | **Not ready (R20, DR18).** On a large raw, arm the eyedropper: an empty ring, dashes and the level, a spinner only after about half a second, and a click in that moment still stores the pick | 24 MP or larger raw |
| M3 | **Legibility (R33, PRD M3, DR12, DR17, DR21).** Outline, ring and plate read over white, black and busy content, at each level, on Retina and a standard display, and after moving the window between them. With Increase Contrast: heavier outline, stronger grid, no dimmed text on the plate. The outline encloses exactly its pixel at 100%, where the pixel is one device pixel. The picture is the same way up as the view, and a quarter-turned photo matches. At a photo corner at 800% and 1600%, the grid stops at the photo's edge and the hairline marks it (F3). Reduce Motion: nothing animates | Owner's Mac |
| M4 | **The inspector's look (DR1, DR2, DR2a, DR7).** Glass panes don't snapshot. Lens after Details; "Pixel magnifier" fits its 80 pt label column; the pop-up row sits between Fringe Map and the caption and only the caption moves when it appears; swatches are the Color Mixer's size and readable when dark; right-click anywhere on a slot row, and in that menu the "Common Fringe Colors" header is a real section header and Purple and Green show their own colors (F5); the fringe map in the frame at fit and 100% | Owner's Mac |
| M5 | **Keyboard and VoiceOver (R1a, R33, DR2b, DR11, DR20, PRD M2).** With Keyboard Navigation on: the §11 Tab order, the pop-up after Fringe Map, and Space opening it. Esc with the keyboard on the eyedropper or a closed pop-up cancels picking. Esc with a pop-up or ⋯ menu open only closes it, and picking stays on. Esc in the Tolerance field hands the keyboard back first. With picking on, Esc in the Export sheet or the ⌘K popover closes only that (F2). `-` and `=` at default settings. VoiceOver: the slot group, "Pick Color 1", "Color 1 commands", the menu's header and items, "Color 1 tolerance", "Pixel magnifier zoom" and its value, "Pixel magnifier at 800%." after a key, the canvas actions, and nothing spoken as the pointer moves | Owner's Mac |
| M6 | **Replacing at 100% (DR5).** On a 24 MP photo, arming a filled slot shows the photo without that slot's graying at full resolution, the spinner only after 0.5 s, and Esc restores | 24 MP photo |
| M7 | **Long preset title (§19 DQ-3).** Apply a preset with a long name and Align automatically to several photos: the toolbar shortens the name in the middle, and the popover shows it whole with "‹n› of ‹m›" and Stop | Owner's library copy |
| M8 | **Feel (R36, PRD M3).** The magnifier feels attached to the pointer and flips without flicker at the right and bottom edges; arming has no hitch; arming at fit then Z, and arming at 100% then Z, leave the crosshair over the photo only, agreeing with the magnifier, with no flicker during the zoom (F1) | Owner's Mac, real raw |
| M9 | **Pixels can't be read (DQ-4, DR22).** With the file moved away before arming (`magnifier hideoriginal` on a scratch library): the eyedropper turns off, the pointer is the arrow, and the sentence is readable under the slots in the inspector's glass pane. VoiceOver says it once. Restoring the file and clicking the eyedropper works | Bundle copy, scratch library only |

## Requirements issues

None.
