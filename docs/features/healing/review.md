# Spot healing and cloning: design review

Reviewer: apple-ui-designer. Date: 2026-11-18. Issue: #86 (slug `healing`).
Branch `feature/healing` at bf6518f. Against: [`design.md`](design.md) (with
the rulings of §20, including DQ-1 and DQ-2 made in this review), the PRD's
acceptance criteria as `status.md` and the design cite them, the HIG, and
`status.md`.

**How this was done, and its limits.** I read the code and the user guide and
cannot run the app or the shell here, so nothing below was seen on screen.
Every "pass" means "the code does what the design says"; what only the screen,
a mouse, a trackpad or a keyboard can show is in the manual checks (M1 to M12).
I could not run `gh issue view 86`, so the PRD's own wording of AC1 to AC15
was not read: I took each criterion from `status.md`'s table and from the
R and AC numbers the design cites. If a criterion says something about the UI
that neither states, it is unreviewed. Per the standing rule, VoiceOver is not
among the owner's checks; F1 asks the engineer to prove it with the debug
script instead.

## Verdict

**Close, with two fixes before sign-off.** The result follows the design's
structure closely: heading, inspector controls, overlay, keys, Adjust ▸ Spots,
context menus, limit, states, strings, History names, and the user guide's
words all match, and the mutual-exclusion and Esc rules are built as written.
Two things need changing: the spots' VoiceOver elements look unreachable from
the canvas (F1), and the heading's check box is pushed out of the column every
other heading uses (F2). Four smaller findings follow (F3 to F6). Design
questions DQ-1 and DQ-2 are ruled in `design.md` §20; neither needs code beyond
what the engineer already did. No Requirements issues.

## Findings for the engineer

Most severe first.

**F1. The spots' VoiceOver elements are probably not reachable (accessibility,
design §12).** `SpotOverlayView` returns one `SpotAccessibilityElement` per
spot, but the overlay is a subview of the image view, inside
`LoupeScrollView`, and `LoupeHostView.accessibilityChildren()` filters
`LoupeScrollView` out (`LoupeView.swift`, "the scroll view and image view
inside it are hidden from VoiceOver"). The host is itself an element (role
image), so there is no other route from the window to the overlay.
`AccessibilityProbe` walks `accessibilityChildren()` from the window, so
`accessibility button` or `accessibility any` should not list "Spot 3, Heal,
upper left" while the tool is on. `status.md` records no scripted
accessibility run for spots (design §17 item 14 asked for one), so this is
unproven either way. Without it a person using VoiceOver cannot select, move,
re-source or delete a spot except through the menu bar, and the "everything
after the add is keyboard- and VoiceOver-reachable" claim in §12 and the user
guide is not shown. Fix: run `accessibility any` with the tool on and put the
output in `status.md`. If the spot elements are missing, have the host return
the overlay's elements from its own `accessibilityChildren()` while the tool is
on and the overlay is shown (they are already screen-framed, so they can be
direct children), and show the run again, including a custom action (Select,
Delete Spot) through `accessibility <role> <n> <action>`. Also say in
`status.md` what a VoiceOver press on empty canvas does (design §15 asked;
R-3 accepts that it may do nothing).

**F2. The Spots heading's check box is 20 pt out of its column (UIR §4 row
grid; design §2).** `SectionHeader` places the check box in a 16 pt slot and
then the `trailing` slot. Every other heading has one 20 pt trailing control
(the reset), so their check boxes line up. `SpotsSection` puts two 20 pt
buttons (eye, reset) in the trailing slot with `trailingWidth: nil`, which
moves the check box 20 pt left of every other heading's. I could not see it,
but the arithmetic is plain from `AdjustControls.swift` (lines 597 to 611).
Design §2 asked for check box, eye and reset in the header; it did not say how
the three fit the grid, and that is my gap. Fix, either of:
(a) keep three controls and put the eye to the left of the check box (a
`SectionHeader` variant with a `leading` accessory), so the check box and reset
sit where they do on the other headings; or (b) take the eye out of the header
and put it in the context row beside the trash and ⋯ (it is a tool control, and
that row already holds the other tool controls), leaving the header as every
other heading's. I prefer (b): it needs no new header variant and the Masks
eye's precedent (the heading) is for a heading with no check box. Either way the
check box column must line up with Light's and Crop's; M3 checks it.

**F3. A spot dragged beyond the crop becomes invisible while still selected
(design §8).** `moveSpot` keeps the center inside the photo's whole frame
(`SpotGeometry.moving`), not the crop. With a crop, a drag past the visible
edge can leave the center outside the crop; the overlay then skips it
(`visibleSpots`), so the ring and its source disappear but `selectedSpotID`
stays, the context row still says "Spot 3 of 12" and the heading shows a
selection nobody can see. Not run, so unconfirmed. Fix: hold a dragged or
nudged center to the crop's rectangle (as the source is held to the photo),
or deselect when the spot leaves it; and say which in `status.md`.

**F4. Cursor over the selected spot's handle and source (design §4, "The
pointer").** Over a spot or a handle the pointer should be the arrow.
`resetCursorRects` adds one arrow rectangle per spot, the ring's bounding
square: the square's corners show the arrow where a click would add a spot,
and the handle's outer half and the source ring stay a crosshair although a
click grabs them. Cursor rects can't be circles. Fix: set the cursor from
`mouseMoved` (`target(at:) == nil ? crosshair : arrow`) and drop the per-spot
rectangles, keeping the loupe's crosshair rectangle for the photo. Small,
cosmetic, but it is the one cue that says "select, don't add".

**F5. Keyboard focus after typing in a field (CLAUDE.md "Menus", the focus
rule).** Clicking the photo while an inspector value field has the keyboard
does not take it back: neither `SpotOverlayView` nor `LoupeScrollView`
makes the loupe the first responder on a click (the only paths are Return or
Esc in the field and `.browserShouldTakeFocus`). The dust workflow is "type a
Size, click twenty specks, ⌫ the wrong one": the ⌫, `H` and `V` would reach
the field. Not run; M6 checks it. Fix if confirmed: post
`.browserShouldTakeFocus` with the window when the overlay or `addSpot` handles
a click.

**F6. User guide (checked against the UI).** Terms match (Spots, Edit Spots,
Choose Source Automatically, Heal, Clone, Spot Limit, Delete All Spots, the
History names). Two additions: name **Finish Editing Spots** (the item and the
button's state while the tool is on), and say `V` is also **Adjust ▸ Spots ▸
Hide Spot Overlay** (DQ-1), since the guide mentions only the key and the eye.

After the fixes, update `status.md` (the touch limit now cites DQ-2, DQ-1 is
ruled) and say which finding each commit closes.

## Design requirements

| # | Design | Result | Notes |
|---|---|---|---|
| 1 | §2 heading after Crop & Straighten, collapsed by default, remembered (`adjust.section.spots`) | Pass | `AdjustView` order; `InspectorExpanded(default: false)` |
| 2 | §2 header: check box, eye, reset ("Delete All Spots") | Fail (layout) | All three are present and titled right; the check box is out of column (F2) |
| 3 | §2 starting the tool from a menu, key or context menu shows the inspector, Adjust tab, heading open | Pass | `LibraryModel.toggleEditingSpots` |
| 4 | §3 toggle, context row ("New spot", "Spot 3 of 12", trash, ⋯), Heal / Clone segmented control, three sliders, caption, paste note | Pass | Order, labels, tooltips, ranges, units (percent of long edge, one decimal) as designed. `bandage` symbol: confirm it renders (M4) |
| 5 | §3 ⋯ menu contents and dimming | Pass | Choose Source, Select Next / Previous, Delete Spot, Delete All Spots |
| 6 | §3 captions, nine states, priority order | Pass | `SpotCaption` follows the table in order; plurals are in the catalog |
| 7 | §3 new spots start with the values last set; kept as preferences | Pass | `SpotTemplate`, generic `spots.*` keys; selecting an older spot doesn't change them |
| 8 | §4 tool state: loupe only; ends on review, crop, comparison, photo change; one on-photo tool at a time | Pass | `isEditingSpots` and the other tools' setters; `reset`, `ReviewActions`, `ComparisonActions`, `beginCrop` |
| 9 | §4 Esc ladder: crop, pick, maps, selected spot, tool, review, loupe | Pass | `LoupeController.handle` |
| 10 | §4 pointer: crosshair with next-spot ring and feather core; solid / dashed by mode; arrow over spots; nothing over the surround | Needs manual check | Cursor logic is in code; the arrow-over-handles part fails (F4); M2 |
| 11 | §4 mouse: click adds on mouse up, drag pans, click selects, drag moves with source, handle resizes, source drags, double-click adds once, right-click selects first | Pass (by reading) | Priority order and drag threshold as designed; M1 for the feel |
| 12 | §4 source rules while moving and resizing: keeps offset, stops at the edge, pushed out as the spot grows, dragged source can't overlap or leave | Pass | `SpotGeometry` (moving, resizing, sourcing); tests are QA's. Crop edge: F3 |
| 13 | §4 overlay look: 1.5 pt white over 3 pt black 35%, dashed 4 on 3 off, selected 2.5 pt with feather core and 6 pt handle, source ring with cross and 8 pt arrowhead, only the selected spot's source, 8 pt minimum radius | Pass (by reading) | Values match; layer order is right (halo under ring). Legibility is M3 |
| 14 | §4 Increase Contrast (hairline 60%, +0.5 pt); Reduce Motion; color never the only signal | Pass | Observes `accessibilityDisplayOptionsDidChange`; implicit animations off; shape and weight carry mode and selection |
| 15 | §4 touch: tap equals click, nothing hover-dependent | Pass | Grab distance 10 pt for every event, ruled in DQ-2 |
| 16 | §5 add selects and shows the source; VoiceOver says the mode and direction; no source: nothing added, beep, caption, announcement | Pass | `placeSpot`, `refuseSpot` |
| 17 | §6 Adjust ▸ Spots ▸ items, order, keys, enablement; title always enabled | Pass | `spotsMenu` after Rotate Right, before New Mask; DQ-1 confirms `V` there |
| 18 | §6 option-arrow keys only while the loupe has the keyboard; arrows keep moving between photos | Pass | `canByKey`; `handleSpotKey` runs only with a spot selected |
| 19 | §6 ⌫ deletes the selected spot, Remove from Album dimmed meanwhile, Delete Spot shows no key | Pass | `LibraryCommands` line 444, `handleSpotKey` before `CullingKeymap`, 51 and 117 |
| 20 | §6 context menus: tool off adds Edit Spots after Crop; on a spot leads with Heal, Clone, Choose Source, Delete | Pass | The tool-on, not-on-a-spot menu puts Finish Editing / Overlay last rather than first: the design says "and the rest", so accepted |
| 21 | §6 toolbar: palette-only Edit Spots item | Pass | `showsByDefault: false`; M8 for the on-state |
| 22 | §7 limit: stays usable; refusal beep, caption with symbol, "Spot Limit" badge, VoiceOver; over-limit stack shows Can't Edit | Pass | `exceedsLimits` wording extended as asked |
| 23 | §8 comparing: tab replaced, items dimmed, `H` and `V` do nothing, spots still render; crop session dims the toggle with its tooltip; review off | Pass | `canEditSpots`, `ComparisonActions`, `ReviewActions` |
| 24 | §8 spots outside the crop are not drawn or selectable, counted in the caption | Pass | `visibleSpots`, `spotsOutsideCrop`; dragging out of the crop: F3 |
| 25 | §9 every state of the heading | Pass (by reading) | M4 for the look of each |
| 26 | §10 one undo step and History entry per action, names as listed; undo keeps the tool on; revert clears selection | Pass | Names match; held nudge is one step (key up, or 1.5 s) |
| 27 | §11 paste note in the Masks heading's words; paste, presets and Copy leave spots alone; Duplicate copies them | Pass | Note is the last line of the body; group excluded from `presetGroups` |
| 28 | §12 keyboard: value fields, `H`, menus; Tab order with Keyboard Navigation | Needs manual check | M5 |
| 29 | §12 VoiceOver: canvas elements, actions, announcements, inspector names, canvas value | Fail (reachability unproven) | Names, labels, actions and announcements are in the code and match; the elements' route to VoiceOver is F1 |
| 30 | §13 strings | Pass | Catalog entries and plural forms present; `LocalizationTests` is code review's |
| 31 | §14 one custom piece (the overlay), everything else a system or existing component; nothing on the glass layer | Pass | Overlay is a plain `NSView` in the content layer inside the image view |
| 32 | §15 order and position: the ring and the heal agree after the Fujifilm lens correction and Lens alignment | Pass (by `status.md`) | Stored in the mask frame on the corrected image; the render side is QA's |
| 33 | §16 debug-script hooks | Pass | `spots on/off/overlay/print`, `spot add/select/next/previous/delete/clear/mode/set/drag/source/nudge/enable/fill`; `snapshot` shows the overlay (content layer) |
| 34 | R-1 Choose Source Automatically; R-2 check box and `spots` group; R-3 no pointer-free add | Pass | One undo step "Choose Spot Source"; group excluded from copy, paste and presets; no Add-at-Center item anywhere |
| 35 | User guide terms | Pass, two additions | F6 |

## Improvements (judgment, not rules)

- The selected Clone ring's dark hairline is solid under a dashed white ring
  (the halo is one combined path). It reads fine and is probably more legible;
  leave it unless M3 says otherwise.
- `H` while Show Original is on leaves the original showing with the overlay on
  top until the first click (a change turns Show Original off). Defensible: the
  design only says turning the tool on turns it off, and it does.
- The loupe's tool-on context menu would be quicker to use with Finish Editing
  Spots first; keep as built unless the owner asks.

## What's working

- The one-tool-at-a-time and Esc ladders are built exactly as designed and are
  easy to reason about.
- Remove from Album dims in step with the loupe taking ⌫, so the menu never
  offers what the key won't do.
- Every spot command is in the menu bar and in the ⋯ menu with the same
  titles; the Adjust ▸ Spots submenu title never dims.
- The state caption does most of the teaching: nine states, text-and-symbol,
  nothing by color alone.
- The no-source and limit refusals each have text, a sound and a VoiceOver
  sentence.

## Manual checks (for a person)

Run the bundle on a scratch library (`photobench scenes` has a dusty sky) with
`--library-root`. VoiceOver is not asked of the owner (standing rule); F1 is
checked with the debug script.

- **M1 Real mouse and trackpad.** With Edit Spots on: a click adds a spot with
  the crosshair and size ring; a click inside a ring selects; a drag inside
  moves it and its source; the handle resizes; the source ring drags and stops
  at its spot and at the photo's edge; a drag on empty photo pans; a double
  click adds one spot and stays in the loupe; right-click on a spot selects it
  and the menu starts with Heal, Clone, Choose Source Automatically, Delete
  Spot. Scroll, pinch, `Z` and ⌥-scroll work with the tool on.
- **M2 Pointer.** Crosshair over the photo with the next spot's ring (solid
  Heal, dashed Clone, the inner feather ring); arrow over a spot, its handle
  and its source; arrow and no ring over the surround; the ring hides over an
  existing spot (F4).
- **M3 Overlay legibility.** At fit and at 100%: on a white sky and on a dark
  foreground; a 6 pt speck (the 8 pt minimum ring); the selected spot's handle,
  cross and arrowhead; with Increase Contrast on (heavier strokes, darker
  hairline); with Reduce Motion on nothing animates.
- **M4 The Spots heading, light and dark.** Collapsed on a new photo; layout of
  the toggle, context row, full-width Heal / Clone control, three sliders and
  captions at the inspector's narrowest width; the `bandage` symbol; every
  caption state of design §9, including the limit's symbol and the wrap of the
  longest sentence; **the check box lines up with Light's and Crop's (F2)**;
  with the heading's check box off the controls show secondary.
- **M5 Menus and keys, window key.** Adjust ▸ Spots items and dimming in the
  loupe, grid, review, a crop session and comparing; the submenu title never
  dims. `H` and `V` bare; ⌫ deletes a selected spot and Remove from Album is
  dimmed then, and with no spot selected ⌫ is Remove from Album as before;
  ⌥ arrows and ⌥⌘ arrows move the spot and the source (⇧ for ten); in a text
  field ⌥← and ⌥→ still move by word. With Full Keyboard Access the Tab order
  of design §12 is right.
- **M6 Keyboard focus.** Type a Size in the field and press Return or click
  the photo: do `H`, `V` and ⌫ then reach the loupe, or the field? (F5.)
- **M7 Esc ladder.** With a spot selected: Esc deselects, Esc again turns the
  tool off, Esc again leaves review or the loupe as before; Esc during a crop
  session, a fringe pick and a map keep their order.
- **M8 Toolbar.** Customize Toolbar offers Edit Spots with `bandage`; added,
  it shows the tool's state and follows `H`.
- **M9 The limit and no source.** At 100 spots the next click beeps, the
  caption and context row show the limit with its symbol, the "Spot Limit"
  badge shows in the loupe caption, selecting and deleting still work. A very
  large Size on a small crop gives the no-source caption and no spot.
- **M10 Undo and History.** Each action is one step with the History names of
  design §10; undo keeps the tool on and deselects a spot it removes; reverting
  a History entry clears the selection.
- **M11 Crop, straighten and turns.** With a crop and a straighten the ring is
  round, the handle is at 3 o'clock on screen, and the ring sits on the healed
  pixels; a spot dragged past the crop edge (F3); Reset Crop brings spots back.
- **M12 Touch Mac, only if the owner has one.** A tap adds and selects; the
  resize handle is reachable with a finger; touch-and-hold opens the context
  menu. If the handle is too small, the remedy is a larger uniform grab
  distance (DQ-2).

## Summary for the issue

Design review of #86 (`docs/features/healing/review.md`): matches the design closely (heading, controls, overlay, keys, menus, limit, states, strings, History names, user guide); two fixes before sign-off. F1: the spots' VoiceOver elements sit inside the scroll view the loupe hides from VoiceOver, so they are probably unreachable; prove with `accessibility any` or expose them from the host. F2: the heading's check box is 20 pt out of the check-box column (two trailing buttons); move the eye into the context row. F3 to F6 are small (spot dragged past the crop edge, cursor over handles, keyboard focus after typing in a field, two guide additions). Rulings in design.md §20: DQ-1 Show / Hide Spot Overlay (`V`) stays in Adjust ▸ Spots (the app's tool overlays live in Adjust); DQ-2 one 10 pt grab distance, no touch detection. Not seen on screen: manual checks M1 to M12 for the owner. I could not read the PRD (no shell), so criteria were taken from `status.md`.
