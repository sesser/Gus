Issue: #241

# Preset list view: design review

Reviewer: apple-ui-designer. Date: 2026-11-20. Branch `feature/preset-list-view`.
Against [design.md](design.md) (with its new §16), the PRD's acceptance criteria
and the HIG. Read from code, `status.md` measurements and the engineer's
scripted results. I could not run the app: everything about how it looks is
under "needs manual check".

## Verdict

**Pass, with manual checks open and no required changes.** The build follows
the design: one two-segment AppKit control, 22 pt full-width AppKit rows with
the hover, pressed, focus and applied states drawn from system colors, the
shared hover preview path untouched, the choice stored app-wide with the list as
default, and no thumbnail render in list view. Three departures are justified
and recorded in design §16. DQ-1 is ruled (a), accept. One thing I can't
settle from code is whether the focus ring on a full-bleed row is clipped (M2).

## DQ-1 and the departures

- **DQ-1: ruled (a), accept** (design §16.1). Neither (b) nor (c) gives one
  line to everyone: the room is 276 pt with an overlay scroller and 259 pt with
  a legacy one, so the same window would be one line or two by a system
  setting. (b) fits with a 0.5 pt margin that a translation or rounding would
  flip. The wrap is the designed fallback and costs one 30 pt line. The 8 pt
  gap stays. My §3 estimate (about 260 pt) was wrong; the measured 276.5 pt
  stands, and I checked the three needed widths against the code's formula
  (132 + 6 + 74.5 + 8 + 56 = 276.5; 196.0; 138.5).
- **One `Layout`, not `ViewThatFits`: accepted** (§16.2). The stronger reason is
  view identity: `ViewThatFits` makes a new set of AppKit views per variant, so
  a focused switch would lose keyboard focus as the inspector is dragged across
  a threshold. One tree with a pure, unit-tested rule (`PresetsBarGeometry`)
  avoids that. I also correct my §8: in the two-line arrangement the switch is
  above Manage…, so layout-order navigation (Save, Import, switch, Manage) is
  fine. Tree order was not worth a sort override. The engineer's stated reason
  (order) was therefore the weaker one; the departure stands on the other.
- **Applied mark reads the saved hash: accepted** (§16.3). Good catch: without
  it the list never redrew its mark after an apply. It still reads saved, not
  live, values, so a drag redraws nothing.
- **Name `PresetListRow`** (the manager sheet owns `PresetRow`): fine.

## Design requirements

| # | Requirement | Result |
| --- | --- | --- |
| 1.1, 2.2, 2.3 | One `AppKitSegmented` with `square.grid.2x2` and `list.bullet`, 28 pt segments, `.selectOne`, small, no custom tint; VoiceOver names Thumbnails and List, label "Presets view", one tooltip per segment | Pass (code, and scripted `buttons`: two radio buttons named, tooltips as help). Look: M1 |
| 1.2, 3 | Right-aligned on the button row; never overlaps a push button; wraps as arrangements 1 to 3; shown and enabled in every state, grid tab and no presets included | Pass by code and `PresetsBarGeometryTests` (no overlap 60 to 420 pt in 0.5 pt steps). Order and wrap by hand: M3 |
| 1.3, 4.2 | Row: 22 pt, full width, no gap, name only in callout and `labelColor`, tail truncation, name room excludes the 20 pt mark room, mark `checkmark.circle.fill` 12 pt in the accent color at 8 pt in, hover `tertiarySystemFill`, pressed `secondarySystemFill`, radius 4, rounded focus ring, no other content | Pass by code. Look and focus ring: M1, M2 |
| 4.2 Indent | Name starts where the heading's title starts (26.5 pt measured from a button built like the heading); 8 pt inset when there is no collection | Pass (measured, status.md) |
| 4.1 | Same data and order as the grid; collection disclosure state shared by both views | Pass (scripted AC3) |
| 4.4 | Context menu Apply and Manage Presets… and the tooltip from one helper shared with the tiles | Pass by code (`presetContextMenu`, `PresetItemRules.help`). The menu itself: M4 |
| 4.2 (checked state) | Marked only in the loupe with a ready editor, against saved values; one helper for both views | Pass (scripted AC8, with the §16.3 change) |
| 1.4, 5 | Rows reuse `ImageTile.HoverButton` and `PresetPreviewModel.hover`; loupe only; no undo step or History entry; moving between rows never ends the preview; click applies as one undo step | Pass (scripted AC4, AC5, AC6). A real mouse sweep: M4 |
| 1.5, 6 | `LibraryModel.presetsView`, `adjust.presetsView`, `.list` for nothing stored, garbage or a number; app-wide; survives relaunch | Pass (`PresetsViewChoiceTests`, scripted relaunch) |
| 1.6, 7 | List builds no `PresetGrid`; zero renders in list view; switching back renders as before; `PresetPreviewModel` only gained counters | Pass (scripted AC7) |
| 8 Accessibility | Rows are buttons named for the preset, value "Applied to this photo" when marked, set on the cell too; Return and Space apply; the control reachable by keyboard; mark is symbol plus color, name stays `labelColor`; no animation | Pass for names, value and Return. Tab order and Space with Full Keyboard Access: M2. VoiceOver is covered by CI only |
| 9 Localization | Five keys added by hand with comments; "Applied to this photo" comment extended | Pass (read in the catalog) |
| 10 Debug script | `preset view`, `hover`, `print presetsbar`, segment labels in `buttons` | Pass (status.md shows each used) |
| 11 User guide | Terms: Presets view, List, Thumbnails, Apply, Manage Presets…, check mark; the default change for people used to thumbnails stated; the kept choice; hover in both views; "no pictures rendered" | Pass: every term matches the UI string. The old sentence is replaced |
| 12 | No availability branch; both symbols exist on macOS 15 | Pass by code. macOS 15 and 26: CI only |
| 13 | Rendering, catalog, goldens, pipeline version and the shared preview path unchanged | Pass (status.md; `AppKitSegmented` text segments keep their old branch) |
| AC1 to AC10 | As mapped in status.md | Pass, except the looks and keys listed as M1 to M5 |

## Violations

None.

## Improvements (judgment, not rules)

1. **Focus ring on a full-bleed row** (M2). The row's ring is drawn outside its
   rounded mask, and the row spans the whole content width with rows touching.
   AppKit may clip the ring at the column edges or let the next row paint over
   its bottom edge. If M2 shows that, inset the ring's mask by 2 pt on each
   side (`focusRingMaskBounds` and `drawFocusRingMask`) so the ring falls inside
   the row, and leave the fills alone. Don't change anything before the check.
2. **Touch-display Macs.** The two segments are 28 by 24 pt, the system control
   at the small size. The rows have the full-width target. The segments are the
   one small target, and the HIG's guidance for touch is larger hit areas with
   the visual size kept. A system segmented control gives no way to do that
   short of a custom control, which I don't recommend. Accepted as is; revisit
   with the app's other small controls, not here.
3. **Right-to-left.** The row draws its name at a fixed left inset and its mark
   at the right. The catalog is English only today, so there is nothing to
   mirror. If a right-to-left language is ever added, rows need
   `userInterfaceLayoutDirection`. No action now.
4. **Pin the wrap.** `PresetsBarGeometryTests` could add one case with the
   measured widths (58.5, 67.5, 74.5, 56) at 276 and 259 pt that expects
   arrangement 2, so a later change to the gap or the segment width is a
   deliberate edit (design §16.1). Optional.

## What's working

- One segmented control instead of two toggles: no both-off state, one VoiceOver
  element, one group at every width.
- Rows reuse the thumbnails' hover and preview path, so the preview behavior the
  owner already knows carries over with no new guard.
- The mark is the same symbol and color the look-up table browser uses, with the
  check cut out of the circle, and it never turns the name accent-colored.
- Hover fill is drawn only from system fills, so Dark and Increase Contrast follow.
- Row name room always excludes the mark, so a name doesn't re-truncate when
  the mark comes and goes.
- The geometry as a pure rule with a test over 60 to 420 pt.

## Manual checks (for a person at the bundle)

VoiceOver, macOS 15 and macOS 26 are not asked (standing ruling).

- **M1. Look of the list.** Run the bundle on a scratch library with 20 or more
  presets, one with a very long name. In Light, Dark and Increase Contrast:
  the hover fill (a soft rounded highlight across the full row), the pressed
  fill while the mouse is down, the check mark on the applied preset (accent
  circle with the check cut out), 22 pt density, the long name cut at its tail
  with its full name in the tooltip. Change the accent color (including
  Graphite) with the app open: the mark follows, and the segmented control's
  selected segment is clear in each. Look at the switch beside the push
  buttons: same height, same baseline.
- **M2. Keyboard.** Turn on Full Keyboard Access. Tab from the Presets buttons:
  the switch is reached once and each row after; note the order at the default
  width (Save, Import, switch, Manage is as acceptable as the tree order;
  skipping or repeating a control is not). Left and right arrows move between
  the segments; Space on a segment changes the view. On a row: the focus ring is
  visible on all four sides (first row, last row, a row under an open
  collection), not cut at the column's edge or painted over by the next row;
  Space and Return apply.
- **M3. The button row.** Default inspector width, with an overlay scroller
  (trackpad) and with "Always show scroll bars": Manage… under Save…, the switch
  at the right of the first line (design §16.1: expected). Drag the inspector
  from its narrowest to wide and back: the switch is never on a push button,
  nothing flickers, and a keyboard-focused switch stays focused while you drag.
  Check the same with no presets and in the grid tab.
- **M4. A real mouse.** In the loupe, sweep the pointer slowly and fast down
  the list: the photo shows each preset in turn, with no flash of the original
  between rows, and goes back to its own edits on leaving the list. Scroll the
  list with the wheel under a still pointer. Right-click a row: Apply and
  Manage Presets…. Click a row: one undo step; the mark appears and goes with
  undo and redo.
- **M5. Switching views.** Switch to Thumbnails and back with a long list
  scrolled halfway: the page doesn't jump to somewhere unexpected, thumbnails
  fill in, the list returns at once. Quit and reopen: the choice is kept. Open a
  collection in one view and find it open in the other.

## Findings for the engineer

No required changes. Closed on my side: DQ-1 (ruled (a), design §16.1), the
Layout departure (§16.2) and the applied-mark departure (§16.3).

1. Record in `status.md` that DQ-1 is closed with ruling (a), and that no code
   changes for it.
2. Optional: the test in Improvements 4.
3. Conditional on M2: the ring inset in Improvements 1. Don't make it before
   the owner or QA reports it.

## Requirements issues

None new. The two wording notes in design §15 (R1 and AC1 say two buttons,
the build is one two-segment control; AC6 says "or comparing", which has no
hover to test) stand unless the PRD was revised for them. I haven't read the
current issue body.

## Summary for the issue

Design review: pass, no required changes, from code and status.md (I couldn't
run the app). Built result matches design.md: one two-segment switch, 22 pt
AppKit rows with system fills and the shared hover preview, list as the
stored default, no thumbnail renders in list view. DQ-1 ruled (a): at the
default column Manage… wraps under Save… and the 8 pt gap stays, because a
7 pt gap or 26 pt segments would give one line only with an overlay scroller,
with a half-point margin. One `Layout` instead of `ViewThatFits` accepted
(keeps focus and controls as the inspector is dragged). Rulings are design.md
§16. Open: manual checks M1 to M5 (look, focus ring on full-width rows,
keyboard order, button-row wrap, real mouse), in
docs/features/preset-list-view/review.md.
