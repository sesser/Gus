Issue: #63

# Side by side comparison: design review

Reviewer: apple-ui-designer, 2026-11-11. Branch `feature/side-by-side-comparison` at
`b32190d`, read against `design.md` (§1 to §15, and the rulings D1 to D8 now in §16),
`prd.md` (R1 to R9, AC1 to AC7, AC6a to AC6c) and `status.md`. Code read, not built or run.

## Verdict

**Changes needed (small).** The comparison is built as designed: a state of the loupe, two
undecorated panes on the surround, a ring in the gutter, a split caption, the menus, the
context menus, the toolbar item, the film strip and the Adjust tab all match the spec. Three
changes follow from the rulings on the engineer's Design questions (F1 to F3); nothing else is
a violation.

## Rulings on the Design questions

Recorded in `design.md` §16; summary:

| Question | Ruling |
|---|---|
| DQ-1, Esc outside review | **D1: as built.** Review first, then the grid. No change |
| DQ-2, ring contrast 4.47:1 | **D2: option (a).** The rule is 3:1 (non-text) in every appearance; Increase Contrast's answer is the 3 pt width. Test change only (F3) |
| DQ-3, active side after entering with one photo | **D3: option (b)**, the partner (right) is active, matching AC6b; plus a remembered pair comes back exactly as it was left (F1) |
| VoiceOver group holds the panes only | **D4: accepted** |
| One photo that is itself a video or offline | **D5: change**, the title is "Can’t Compare This Photo" (F2) |
| Sides swap on `S S` | **D6: superseded by D3**, a remembered pair keeps its sides and active side (F1) |
| Link toggle between equal captions | **D7: accepted** |
| Click zoom keeps the point under the pointer | **D8: accepted** |

With D3, RI-E2 needs no PRD change: AC6b holds as written.

## Fixes for the engineer

- **F1 (D3, D6). Active side and re-entry.**
  1. `ComparisonRules.entry`: from the loupe (photo or video loupe) and from one selected
     photo in the grid, the partner (right) pane is active. Two selected in the grid: unchanged.
  2. When the partner is the remembered one, restore the comparison as it was left: the same
     version on each side and the same active side, even when that puts the loupe's photo on
     the right. Keep the last state per pair (or the last comparison) rather than only the
     partner map; forget it when the loupe closes, as now.
  3. The entering animation refits the loupe's photo into whichever pane it goes to
     (`ComparisonController.layoutPanes` now always moves the left pane), and the other pane
     fades in.
  4. Tests: update `theLoupesPhotoIsComparedWithItsPartnerWhateverIsSelected`,
     `oneSelectedPhotoIsComparedWithTheNext` and `thePartnerIsThePhotoLastComparedWith` for the
     active side; add one for `S S` from the right side restoring sides and active side.
  5. `docs/USER_GUIDE.md` §"Comparing two photos": say that with one photo the photo beside it
     is the active one, so the arrows and the strip choose the second photo, and that `S` once
     more brings the same two back as they were.
- **F2 (D5). Refusal title.** When comparison was entered with one photo and that photo is a
  video or offline, title the alert "Can’t Compare This Photo" (the key exists). Two selected:
  "These Photos" as now. A unit test or a scripted `alert` check from the video loupe.
- **F3 (D2). Contrast test.** In `PaletteContrastTests.theComparisonRingStandsOutOnTheSurround`,
  require 3:1 in every appearance and remove the `withKnownIssue`. The status line's "2 known
  issues" goes back to 1.

## Design requirements

| Requirement | Where | Result |
|---|---|---|
| Comparison is a state of the loupe; focus is the active photo; commands act on it | `ComparisonActions`, `LibraryModel.setFocus`, `apply` | Pass |
| Selection while comparing is the pair; kept on leaving (RI-1) | `selectComparison`, `stopComparing` | Pass |
| Panes: equal columns, 4 pt gutter, 24 pt fit margin, radius 4, nothing drawn at the seam, on the surround, no glass | `ComparisonGeometry`, `ComparisonPane` | Pass |
| Inactive pane never dimmed or tinted | `layoutPanes` (alpha only while entering) | Pass |
| Entering: loupe photo refits into its pane, the other fades in; leaving refits the active photo; Reduce Motion at once | `beginEntering`, `beginLeaving` | Pass for the left pane; **F1.3** for a restored pair. Look: M3 |
| Entry table (§3): two in source order, focused active; one + partner; dimmed only by counts | `ComparisonRules.entry`, `canToggle` | **Fail, F1** (active side with one photo, re-entry) |
| Partner rule; skips videos, offline, the pair's other file | `ComparisonRules` | Pass |
| Refusal alert: window-modal, one OK, titles and texts per §3 | `showComparisonRefusal` | **Fail, F2** (single photo title). Keys: M5 |
| Entering turns Show Original off, ends the maps and the fringe pick; dimmed while cropping | `enterComparison`, `canToggle` | Pass |
| Keys `S` and `A`, bare, in the View menu; handled in grid, loupe, video loupe, comparison | `LibraryCommands.comparisonItems`, `handle`, `GridController`, `VideoLoupe` | Pass. Menu titles and states with a key window: M1 |
| Switch item names the side it will make active | `ComparisonText.switchTitle` | Pass |
| Link Zoom and Position: checkmark, no shortcut, remembered (`compare.linksViews`) | `LibraryCommands`, `ComparisonLink` | Pass |
| While comparing: zoom items act on the active pane; Show Original, History, Remove from Album / Library, Adjust editing items dimmed; Copy Adjustments, keywords, albums, Export, Show in Finder on the active photo | `LibraryMenuState`, `LibraryCommands` (editor detached, `canEditLoupePhoto` false) | Pass |
| Context menus: grid, loupe, video loupe gain Compare Side by Side; pane menu activates first and lists photo items, zoom, Link (checked), Stop Comparing; no adjust, no Remove | `PhotoContextMenu` | Pass |
| Toolbar: palette-only Compare toggle, `rectangle.split.2x1`, tooltip, enabled as the menu; symbol checked on macOS 15 by test | `LibraryToolbar`, `symbolsResolveOnMacOS15` | Pass. Look: M7 |
| Linked zoom and pan in unit coordinates, per frame, clamped; walking at 100% keeps the place; unlink; relink follows the active pane | `ComparisonController`, `ComparisonLink` | Pass (scripted). Real input: M2 |
| First click on the inactive pane only activates; drag from it pans; scroll and pinch do not activate; double-click shows the grid | `LoupeScrollView.onActivate`, `ComparisonPane` | Needs manual check (M2) |
| Ring: 2 pt (3 pt Increase Contrast), outer radius 8 concentric with the canvas, accent; neutral when the window is not key; no animation | `updateRing`, `ComparisonGeometry.ring` | Pass in code. Look: M4. Contrast: **F3** |
| Arrows, Home, End walk the active side, skipping videos, offline, the other side; at the ends nothing | `walkComparison`, `NavigationKey` | Pass |
| Advance After Rating moves the active side | `LibraryModel` culling | Pass |
| A compared photo leaving the source ends the comparison on the other | `reconcile` | Pass |
| Film strip: centered on the active photo; active cell focused look; other compared cell fill without border; clicks put the photo in the active side, the other side's cell activates, video or offline beeps | `FilmStrip`, `FilmStripCell` | Pass. Look: M6 |
| Caption: one 28 pt row split at the seam; name semibold primary for active, regular secondary for the other; position; centered marks; HDR, Offline; Filtered once on the right; strip toggle trailing, hidden in review | `ComparisonCaption` | Pass. Narrowing order: M8 |
| Link toggle: bordered button toggle, small, `link`, ≥ 20 × 20, tooltip says what a click does, shown in review | `ComparisonLinkToggle` | Pass in code. Bezel and size: M7 |
| VoiceOver: group "Comparison", pane values and actions, announcements | `ComparisonHostView`, `ComparisonPaneView` | Pass (scripted tree; D4). Not for the owner (see below) |
| Comparison host is one key view; Tab moves past it | `ComparisonHostView.acceptsFirstResponder` | Needs manual check (M9) |
| Info tab on the active photo; Adjust tab content-unavailable with Stop Comparing; History hidden; title the active file name, subtitle "Comparing · ‹source›" | `AdjustView`, `HistoryActions`, `WindowTitle` | Pass |
| Narrow windows: side by side at every width; no automatic hiding of sidebar or inspector | `ComparisonGeometry.canvases` | Pass. 13" look: M8 |
| Strings (§12) in the catalog | `LocalizationTests` | Pass. "Comparison" shares a key with the smart album editor: follow-up (status.md) |

## USER_GUIDE terms

The guide's names match the UI: View ▸ Compare Side by Side, Stop Comparing, Switch to Right
Photo / Switch to Left Photo, Link Zoom and Position, Advance After Rating, the Adjust tab's
Stop Comparing, review (F). "Its name is bold" describes semibold; fine for a guide. The Esc
row and paragraph match D1. Needs the F1.5 update.

## What's working (keep it)

- No chrome on the photos: no badge, divider, dimming or glass; the surround is the separator.
- The ring in the gutter so activation never moves a photo, and it moves without animation.
- Dimming only for counts and an alert for the reason otherwise.
- The editor detached while comparing, so every edit path is off by construction rather than
  by a list of `disabled` checks.
- Captions that give up position, then name, then HDR, and never the marks.

## Manual checks (for a person at the bundled app)

- **M1.** With the window key, open the View menu while comparing: Stop Comparing (S), Switch to
  Right Photo or Left Photo (A, naming the inactive side), Link Zoom and Position with a check;
  Show Original and Show History dimmed. In the grid with three photos selected, Compare Side by
  Side is dimmed.
- **M2.** With a mouse and a trackpad: a click on the inactive photo only moves the ring; the next
  click zooms. A drag starting on it activates and pans. Scrolling and pinching over the inactive
  photo leave the ring where it is and, linked, move both. Double-click shows the grid.
- **M3.** From the loupe press S: the photo shrinks into its pane and the other fades in, in about
  a sixth of a second; S again: the active photo grows back. With Reduce Motion on, both happen at
  once. After F1: S, S brings back the same two on the same sides with the same one active.
- **M4.** The ring is the accent color and clearly visible on the dark surround; with another app
  in front it turns gray; with Increase Contrast it is thicker. Its corners follow the photo's
  rounded corners.
- **M5.** The refusal alert (a video and a photo selected, S): Return and Esc both close it. After
  F2, S on a video in the loupe says "Can’t Compare This Photo".
- **M6.** In the film strip the active photo is outlined and the other compared photo is
  highlighted without an outline, and the two read as different at a glance.
- **M7.** The caption's link button shows a bezel while linked and none while unlinked, is easy to
  hit, and its tooltip says what a click will do. The toolbar's Compare item (add it with
  Customize Toolbar) shows its bezel while comparing.
- **M8.** On a 13" display (or a window of about 1,000 pt) with the sidebar and inspector shown,
  both photos are usable at fit and the captions show names, marks and badges; narrowing further,
  the position goes first, then the name shortens in the middle, and the stars, flag and label
  name stay.
- **M9.** With Full Keyboard Access on, Tab from the sidebar lands on the comparison once and the
  next Tab goes on to the inspector; the arrow keys walk the active side while it has focus.

Not for the owner (README disclaims them): VoiceOver itself, and macOS 15 and 26.

## Follow-ups

None new from this review; the engineer's proposed issues in `status.md` stand, including the
"Comparison" string key split.
