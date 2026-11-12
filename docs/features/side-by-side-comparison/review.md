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
| D14: Duplicate dimmed while comparing, left out of the pane menu; undo / redo of a Duplicate keep the comparison (focus on the active side) or end it on the photo that remains | `canDuplicateTargets`, `replaceItems` | **Pass** (F8 confirmed, sixth pass; M11 for a person) |
| D15: a copy's caption shows its name and the Copy badge (never shed); VoiceOver and alerts use the copy's name | `ComparisonCaption`, `ComparisonActions` | **Pass** (F9 confirmed, sixth pass; narrow caption is M10) |

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

## Second pass

Reviewer: apple-ui-designer, 2026-11-12. Branch at `16fb7ac` ("review fixes"), read against
the rulings in `design.md` §16 and `status.md` §Review findings. Code read, not built or run.

**Verdict: Changes needed (one).** F1 to F3 match D2, D3 and D5; DQ-4 is ruled D9 (as
built). The code review's second-pass question on linked ⌘− is ruled D10, a change (F4).

| Fix | Ruling | Where | Result |
|---|---|---|---|
| F1.1 | D3: one photo, the partner (right) is active; two selected unchanged | `ComparisonRules.entry`; `ComparisonTests` | Pass |
| F1.2 | D3, D6: a remembered pair comes back with the same sides and active side | `comparisonMemory` keyed by both versions, updated on entering, `setComparisonActive` and `replaceComparisonActive` (walks), cleared when the loupe closes; `rememberedComparison` passed to `entry` from the loupe; test `aRememberedPairComesBackOnTheSameSidesWithTheSameOneActive` | Pass |
| F1.3 | D3: the loupe's photo refits into whichever pane it goes to; the other fades in | `comparisonEntersFrom` from the state's side of the focused item; `ComparisonView.layoutPanes` moves `enteringSide`, fades the other; Reduce Motion and video skip it | Pass in code. Not run on screen (engineer's display asleep): **M3** covers it |
| F1.5 | Guide says the partner is active with one photo and `S` brings the pair back | `docs/USER_GUIDE.md` | Pass (per `status.md`; terms unchanged) |
| F2 | D5: "Can’t Compare This Photo" when entered with one photo; "These Photos" with two | `ComparisonRefusal.concernsOnePhoto` (`video`/`offline` carry `alone`; `noPartner` is always one photo; `pairHalves` never), used by `showComparisonRefusal`; test `theRefusalSaysWhetherOnePhotoOrTwoWereAsked` | Pass. Keys: M5 |
| F3 | D2: 3:1 in every appearance, no known issue | `PaletteContrastTests.theComparisonRingStandsOutOnTheSurround`: 3:1 for dark and high-contrast dark, neutral, the set accent and the eight named system colors; `withKnownIssue` gone | Pass. The named colors as stand-ins for the accent setting are an acceptable proxy (the setting can't be changed per process); the window is dark only, so light appearances need no check |

The design requirements table above now reads Pass for the entry table (F1) and the refusal
alert (F2), and the ring's contrast (F3). The C1 to C8 code fixes change no UI that §1 to §16
specify; C2 (linked `Z` with a small photo) and C1 (a side never taken by the other side's
neighbour) bring the build closer to §5 and §6.

**DQ-4, ruled D9 (`design.md` §16): (a), as built.** Remove Project from Library… names its
own target, asks first, and is dimmed only for the library-ops reasons; comparison is a view
state, so it doesn't lock the sidebar. Removing a project that holds a compared photo ends
the comparison on the remaining photo, as any other departure from the source does. No change.

**Linked ⌘− at the active photo's fit, ruled D10 (`design.md` §16): change.**

- **F4 (D10).** In `ComparisonView.stepZoom`, a step is a magnification, not a fit command:
  the other panes take the step's magnification, clamped at their own fit, whatever the
  active pane's zoom state becomes (don't pass `leaderIsFitted: zoom == .fit` for steps; C2's
  rule stays for `Z`, Fit and click). Each pane sets its own zoom state from its result.
  While linked, Zoom Out (View menu, ⌘−, pane context menu) is enabled while any linked pane
  is above its own fit; at the active pane's floor it leaves the active pane and steps the
  other down through `LoupeZoomSteps` to its fit. Zoom In mirrors it at the maximum.
  `publishZoom`'s `canZoomIn` / `canZoomOut` follow that. Unlinked: unchanged. Test in
  `ComparisonTests` (or `ComparisonLink`) with fits 1.000 and 0.290 from 2.000: ⌘− gives
  1.000 / 1.000, further ⌘− reach 1.000 / 0.290, then Zoom Out is off; the scripted run the
  code reviewer made should read 1.000 and 1.000 after the first ⌘−.

Manual checks: unchanged (M1 to M9); M3's last sentence now also covers the animation into
the right pane, which nobody has seen yet.

## Third pass

Reviewer: apple-ui-designer, 2026-11-12. Branch at `222e274` ("second-pass fixes"), read
against `design.md` §5 and §16 (D10, and D11 below), `status.md` "Second pass". Code read
(`ComparisonLink.step` in `Sources/PhotoCore/Browser/Comparison.swift`,
`ComparisonView.stepZoom`, `publishZoom`, `setZoom`, `PhotoContextMenu`, `LibraryCommands`)
and the tests in `ComparisonTests`; not built or run.

**Verdict: Changes needed (one, small).** F4 matches D10. The engineer's note on Zoom In is
ruled D11, a change (F5).

| Check | Where | Result |
|---|---|---|
| F4 / D10: a step is a magnification; fits 1.000 and 0.290 from 2.000 give 1.000 / 1.000, 1.000 / 0.500, 1.000 / 0.290, then Zoom Out dimmed; the same with the other photo active | `ComparisonLink.step` (active pane first, then the other when the active can't; each pane at its fit only below it); test `aLinkedZoomOutStepNeverSkips100PercentOnOneSide`; engineer's scripted run (fits 1.000 / 0.489) | Pass |
| Each pane's zoom state is its own result (fit at its fit, zoomed above) | `step` returns `isZoomedIn` per pane; `stepZoom` sets `.fit` / `.actualSize` per pane | Pass |
| Menu bar Zoom In / Zoom Out enabled from the same rule | `publishZoom` computes `canZoomIn` / `canZoomOut` with `ComparisonLink.step`; `LibraryCommands` reads `loupeZoom` | Pass |
| Pane context menu follows it (items left out when they can't act, as §4 asks of context menus) | `PhotoContextMenu` lists Zoom In / Out from `loupeZoom` | Pass; scripted: no Zoom Out at 1.000 / 0.489 |
| `Z`, Fit, click keep both panes at their own fit | `setZoom` applies `.fit` to every reached pane (`applyZoom`), `follow` for fit sends the follower to `.fit`; steps no longer pass a leader, so C2's rule is used only by fit commands | Pass |
| Unlinked: a step reaches the active pane alone, as the single loupe | `reached(by:)`; test `anUnlinkedStepIsTheLoupes` | Pass |

**The engineer's note (linked ⌘= from 1.000 / 0.290 lands on 2.000 for both): not
acceptable; ruled D11 (`design.md` §16), change.** It meets §5's letter (both take the same
magnification) but breaks the reason D10 gave: 100% is where people compare sharpness, and a
step must never skip it on one side. Here the other photo goes from fit to 200% in one press
(about 7×), passing 100%, and ⌘= then ⌘− doesn't return where it started (2/2 → 1/1, not
1/0.29), so the two commands stop being inverses, which keyboard users rely on. The single
loupe from fit 0.290 would step to 0.500.

- **F5 (D11).** In `ComparisonLink.step`, for Zoom In while linked, land on the smallest of the
  panes' next `LoupeZoomSteps.zoomIn` targets rather than the active pane's; the rest is
  unchanged (each pane takes it, at its own fit when below). Zoom Out unchanged. `canZoomIn`
  follows automatically. Tests: from 1.000 / 0.290 (either side active) ⌘= gives 1.000 / 0.500,
  1.000 / 1.000, 2.000 / 2.000; update `aLinkedZoomInStepTakesBothToTheSameMagnification`
  (its first case, both at 1.000, still gives 2.000 / 2.000; its `mixed` case already gives
  1.000 / 0.500). A scripted check like the second pass's: `Z` to fit, `zoomstep in` three
  times reads 1.000 / 0.500 (0.489 fit: 1.000 / 0.500), 1.000 / 1.000, 2.000 / 2.000.

Manual checks: unchanged (M1 to M9). No USER_GUIDE term changes.

**F5 confirmed** (commit "Side by side comparison: linked Zoom In (D11)"). `ComparisonLink.step`
lands Zoom In on the smallest of the panes' next steps (`targets.min()`), whichever is
active; Zoom Out still takes the active pane first. Each pane takes the landed
magnification, at its own fit below it, and its zoom state follows. A guard keeps Zoom In
from ever taking a pane back out: if the panes' magnifications differ, the one further in
stays where it is. That matches D11's intent and is the right safety. `canZoomIn` follows
through `publishZoom`. `aLinkedZoomInStepTakesBothToTheSameMagnification` checks 1.000 /
0.500, 1.000 / 1.000, 2.000 / 2.000 with either side active, that ⌘− retraces it, the zoom
states, the same-magnification case and the top. The engineer's scripted run (fits
1.000 / 0.489) reads the same. **Pass.**

USER_GUIDE (§ Comparing two photos): "⌘= and ⌘− take both photos to the same size; a photo
stops at its own fit when the step would make it smaller than that, ⌘− goes on working
until both are fitted, and ⌘= goes back up through the same sizes" describes D10 and D11
correctly, in the UI's terms (View ▸ Link Zoom and Position, Zoom to Fit). No change.

**Third pass verdict: Approved.** No open design findings. Manual checks M1 to M9 stand.

## Fourth pass: C11 / Q1 and DQ-QA1 (rulings D12, D13)

Reviewer: apple-ui-designer, 2026-11-12. The owner chose to fix C11 on the branch. Read
against `code-review.md` (third pass, C11), `qa.md` (Q1, DQ-QA1), `ComparisonView.follow`,
`relink`, `animate`, `ComparisonPane.show(magnification:unitCenter:zoom:)` and
`ComparisonLink`.

**Verdict: Changes needed (F6, plus a wording fix F7).**

**C11 / Q1, ruled D12 (`design.md` §16): change.** For following, each pane's own result
replaces C2's shared zoom. A follow changes a pane's zoom state only when it changes that
pane's magnification. A fitted leader never moves a zoomed-in follower. `Z` and the View menu
title still follow the active pane's state; I did not adopt "100% while any pane is zoomed
in", because it would make `Z` on a zoomed photo behave differently from the single loupe.

- **F6 (D12).**
  1. **PhotoCore.** Add a pure function to `ComparisonLink`, for example
     `follow(leader: PaneZoom, follower: PaneZoom, maximum: Double) -> PaneZoom?`, where `nil`
     means "leave the follower as it is: magnification, position and zoom". `leader.isZoomedIn`
     is the one rule's answer (`isZoomedIn(wasZoomedIn:magnification:fit:)`).
     - Leader zoomed in: `m = min(max(leader.magnification, follower.fit), max(maximum,
       follower.fit))`. If `|m − follower.magnification| ≤ tolerance × follower.fit`, return
       the follower with `m` and its **old** `isZoomedIn`. Otherwise return
       `isZoomedIn = m > follower.fit × (1 + tolerance)` (tolerance `LoupeZoomSteps.tolerance`,
       as in `step`).
     - Leader fitted: a follower with `isZoomedIn` true gives `nil`. A fitted follower gives
       `follower.fit × max(leader.magnification / leader.fit, 1)`, `isZoomedIn` false (the
       current C9 formula).
  2. **`ComparisonView.follow`.** Call it. On `nil`, do nothing to the follower (no `show`, no
     recentering). Otherwise `show(magnification:unitCenter:zoom:)` with the leader's unit
     center and `.actualSize` / `.fit` from the result. Its `setZoom` is then the only thing
     that starts a full-resolution render, so a pane that stays fitted renders nothing new.
  3. **Walk** (`apply`, the `follow(leader, pane)` for a new photo): pass the new pane as
     `PaneZoom(magnification: fit, fit: fit, isZoomedIn: false)`, whatever zoom its previous
     photo had.
  4. **`relink`.** With a zoomed-in leader, use the same function for the follower instead of
     an unconditional `setZoom(.actualSize)` (animated as now). Fitted leader: unchanged.
  5. **Tests** (PhotoCore, `ComparisonTests`):
     - Q1's case: leader 0.500 zoomed (fit 0.165), follower 1.000 fitted (fit 1.000) gives 1.000
       **fitted**.
     - C2's case: leader 1.000 zoomed (fit 0.165), follower 1.000 zoomed (fit 1.000) gives 1.000
       **zoomed**.
     - The reverse case: leader 1.03 fitted (fit 1.000), follower 0.500 zoomed (fit 0.165) gives
       `nil`. The same leader at 1.06, now zoomed, gives the follower 1.06 zoomed.
     - A zoomed follower brought down to its fit: leader 0.25 zoomed (fit 0.22), follower 0.5
       zoomed (fit 0.329) gives 0.329 fitted.
     - Equal fits, both zoomed: unchanged from today.
  6. **Scripted.** Rerun QA's C11 script. After `pan 300 200`, IMG_00006 should read `1.000
     zoom fit rendition preview` with menustate `isZoomed: false`, and `Z` should give 1.000 /
     1.000. Also run `Z`, `pan` and `Z` with equal-size raws (C2), and a walk at 100% (§5 row 4).

**DQ-QA1, ruled D13: accept as built.** Zoom Out's extra stop at the active photo's fit is the
single loupe's own clamp. It shows the whole active photo, never skips 100%, and every press
changes something. D11's wording is amended to "retraces through the loupe's steps".

- **F7 (D13, wording).**
  - In the `ComparisonLink.step` doc comment, say Zoom Out may stop once more at a pane's own
    fit when that fit is not a step.
  - In `docs/USER_GUIDE.md` (Comparing two photos), "and ⌘= goes back up through the same
    sizes" is no longer exact. Change it to "and ⌘= takes them back up". No other term changes.

Manual checks: M2 gains one item for a person. With a raw beside a small JPEG, linked, press
⌘= twice, then drag the raw. The JPEG must not change, View must still say Zoom to 100%, and
`Z` must give 100% on both.

## Fifth pass: the merge with virtual copies (C14, C15; rulings D14, D15)

Reviewer: apple-ui-designer, 2026-11-12. Read against `code-review.md` ("Merge with develop
(#155, #156)", C14 and C15), `docs/features/virtual-copies/design.md` (§4.2, §4.3, §5, §6.3,
§6.4, D-V2), `LibraryModel.apply` / `replaceItems`, `DuplicateActions.canDuplicateTargets`,
`PhotoContextMenu.comparison` / `addPhotoItems`, `ComparisonCaption` and `ComparisonActions`.
Code read, not built or run.

**Verdict: Changes needed (F8, F9).** Neither design covered the other feature. D14 dims
Duplicate while comparing and makes every list replacement keep the comparison's rules; D15
names a copy in the comparison as the rest of the app does.

- **F8 (D14). Duplicate while comparing.**
  1. **`DuplicateActions.canDuplicateTargets`:** add `&& !isComparing`. File ▸ Duplicate and
     ⌘D are then dimmed while comparing (review included), and `LibraryMenuState.canDuplicate`
     follows.
  2. **`PhotoContextMenu.addPhotoItems`:** nothing to add if `state.canDuplicate` reads
     `canDuplicateTargets` (it does, `LibraryMenuContext.swift:244`); the pane menu then leaves
     Duplicate out, and the separator rule before Export… stays right. Confirm the pane menu's
     items: no Duplicate, separator only when Export…, Show in Finder or RAW+JPEG Pair follow.
  3. **`LibraryModel.replaceItems` while comparing:** reconcile as `apply` does. Before the
     list is replaced, collect `pairPartners` as `apply` does; after, run
     `ComparisonRules.reconcile`:
     - `.kept`: keep the comparison (and the memory update `apply` makes); then focus and
       selection come from `ComparisonRules.selection(of:indexOf:)`, ignoring the `selecting`
       and `focusVersionID` arguments. Do not touch the panes' zoom or position.
     - `.ended(remaining)`: `comparison = nil`, `comparisonHDRHeadroom = [:]`; focus
       `remaining ?? focusVersionID` (the undo's original when both compared photos went),
       selection that photo alone (the loupe rule already in `replaceItems`). The comparison
       view must leave as it does for a removal (refit to the whole loupe, §10's Leaving
       announcement).
     The simplest route is one private helper shared by `apply` and `replaceItems`, so the
     two can't drift apart again; that is the engineer's call.
  4. **Tests.** PhotoCore where the rule is pure (`ComparisonRules.reconcile` with a list that
     gains copies: `.kept`, sides and active unchanged; one that loses the active copy: `.ended`
     on the other; loses both: `.ended(remaining: nil)`). In the app target or by script:
     `compare on`, `duplicate` reports unavailable, `menuitems Duplicate` shows it disabled.
  5. **Scripted (for QA):** (a) grid, `duplicate` on A, `compare on` on A′ with its neighbor,
     undo, `print compare`: not comparing, the loupe on the neighbor, focus and selection it
     alone. (b) `duplicate` on A and B in the grid, `compare on` on A′ and B′, undo: not
     comparing, the loupe on the active copy's original. (c) ⌘D in the loupe on A, `S` (A′ and
     its partner), then an undo of an earlier Duplicate of another photo C: `print compare`
     unchanged, focus the active side. (d) the same with a redo: unchanged, the copy only in the
     strip, `5` rates the active photo.
  6. **`docs/USER_GUIDE.md`** ("Comparing two photos"): add Duplicate to the sentence that says
     which commands are off while comparing (with Remove from Album and Remove from Library…).
- **F9 (D15). A copy's name in the comparison.**
  1. **`ComparisonCaption.name`:** `Text(verbatim: PhotoName.inFull(item))` in place of
     `item.fileName`.
  2. **`ComparisonCaption.badges`:** after the HDR badge and before Offline,
     `if item.isCopy { CaptionBadge(title: DuplicateText.badge, help: DuplicateText.badgeHelp(item.fileName)) }`,
     exactly as `LoupeCaption` builds it. It is in all four `ViewThatFits` rows (never shed).
     Update the struct's doc comment: the Copy and Offline badges never go.
  3. **`ComparisonActions`:** `:125` and `:187` use `PhotoName.display(item)` in place of
     `item.baseName`; `:205`'s `name` uses `PhotoName.inFull` in place of `fileName`.
  4. **Debug script:** `print compare`'s caption line (`DebugComparisonCommands.swift:102`)
     prints the name as the caption shows it (`PhotoName.inFull`) and `copy` when the badge is
     shown; the pane line in `ComparisonView.swift:668` may keep the file name (it identifies
     the pane, not what it shows), engineer's choice.
  5. **Check:** `ComparisonPane`'s accessibility label goes through `PhotoAccessibility.label`
     (copy-aware since #156); if anything in the comparison builds a label from `baseName` or
     `fileName`, switch it to `PhotoName.display`.
  6. **Scripted (for QA):** compare `IMG_x` with its copy; `print compare` shows
     `IMG_x.ext` and `IMG_x copy` with `copy` on the copy's side only; at a narrow window
     (`windowsize` small enough to truncate) the badge is still printed.

Design requirements: two rows added to the table above (D14, D15), both **Fail** until F8 and
F9 land. The VoiceOver wording is checked by script and unit test, not by a person.

Manual checks: **M10** (new). In a comparison of a photo and its copy at a narrow window
(sidebar and inspector shown on a 13" display, or the window made narrow), the copy's caption
keeps its Copy badge and its marks while the name truncates. **M11** (new). While comparing, ⌘D beeps and File ▸
Duplicate is dimmed; right-click on a pane shows no Duplicate.

## Sixth pass: D14 and D15 confirmed (F8, F9)

Reviewer: apple-ui-designer, 2026-11-12. Commit "Duplicate while comparing and a copy's name
(D14, D15)", read against `design.md` §16 D14 and D15, this file's fifth pass and `status.md`
"Fifth pass": `DuplicateActions.canDuplicateTargets`, `PhotoContextMenu.comparison` /
`addPhotoItems`, `LibraryCommands` (File ▸ Duplicate), `LibraryModel.apply`,
`reconcileComparison`, `replaceItems`, `ComparisonCaption`, `ComparisonActions` and
`docs/USER_GUIDE.md`. Code read, not built or run; the engineer's scripted runs (a) to (d) in
`status.md` are taken as the evidence for behavior.

**Verdict: Pass. F8 and F9 are closed; no change needed.**

- **F8 (D14).**
  1. *Dimmed while comparing.* `canDuplicateTargets` requires `!isComparing`; `isComparing` is
     `comparison != nil`, which review keeps, so review is covered. File ▸ Duplicate disables on
     `canDuplicate`, which reads it, and ⌘D goes through that item. Pass.
  2. *Pane menu.* `PhotoContextMenu.comparison` builds through `addPhotoItems`, which adds
     Duplicate only when `state.canDuplicate`; the separator before the group appears only when
     Export…, Show in Finder or RAW+JPEG Pair follow. Pass.
  3. *Undo / redo.* One helper, `reconcileComparison`, serves `apply` and `replaceItems`, as
     asked. In `replaceItems`: `.kept` takes focus and selection from
     `ComparisonRules.selection` and returns before `selecting` / `focusVersionID` apply; the
     panes are not told anything beyond `libraryItemsReloaded` (grid and strip only), so each
     pane's zoom and position stay. `.ended(remaining)` focuses the remaining photo alone;
     with nothing remaining it focuses the active copy's original (`activeOriginal`, found
     before the list is replaced), falling back to the undo's own focus only if that original
     is not in the list. The copy's side is never refilled (`ComparisonRules.reconcile` keeps a
     side only for a pair's other file). A redo only adds items, so it always reconciles to
     `.kept` and never starts or restores a comparison. All four D14 cases pass.
  4. *Announcements.* `.ended` calls `announceLoupePhoto` (§10 Leaving); `.kept` announces
     nothing, as D14 asks. Pass.
- **F9 (D15).**
  1. *Caption name:* `PhotoName.inFull`, weight and color by active side as before. Pass.
  2. *Copy badge order:* Filtered (right only), HDR, Copy, Offline, the film strip toggle, with
     the single loupe's title and tooltip (`DuplicateText.badgeHelp(item.fileName)`, the master's
     file name). Pass.
  3. *Narrow captions:* the four `ViewThatFits` rows drop the position, then middle-truncate
     the name, then drop HDR; the Copy badge is in all four, and the doc comment says so. Pass
     in code; seeing it truncate stays **M10**.
  4. *VoiceOver:* entering and switching use `PhotoName.display`; walking uses
     `PhotoAccessibility.loupeMove`, and the panes `PhotoAccessibility.label`, both copy-aware.
     No separate "Copy" word. Pass.
  5. *Refusal alerts:* every case names photos through `PhotoName.inFull`. Pass.
  6. No new strings. Pass.
- **User guide.** "Comparing two photos" lists Duplicate with the commands that are off while
  comparing, in the menu's own word. The Copies section's terms (Duplicate, Copy badge, Undo
  Duplicate) match the UI. Pass.

**The engineer's extra change: `apply` now announces the remaining photo when a compared photo
leaves the source. Accepted.** §10's Leaving row is "the loupe's photo announcement for the
photo now shown alone", and it is not limited to `S`: §6 and D9 make a removal end the
comparison on the remaining photo, so that is a leaving, and before this change VoiceOver heard
nothing while the screen went from two photos to one. It is limited correctly: only when the
source stays the same (`keepsComparison`; a source change has its own feedback), and
`announceLoupePhoto` speaks only in the loupe, so a list that empties and closes the loupe says
nothing extra. `apply` and `replaceItems` now behave the same, which is what D14 asked for.
This is what §10 already says, so `design.md` needs no change.

Optional, not required (judgment, not a finding): the Copies section of the user guide says
Duplicate is "dimmed while a crop is being edited"; it could add "or while comparing" so a
reader of that section alone finds it. Engineer's call.

Manual checks M10 and M11 stand as written in the fifth pass. Add to M11: after a Duplicate of
another photo, `S` on a pair zoomed to 100%, then Edit ▸ Undo Duplicate; both panes keep their
zoom and position.

## Follow-ups

None new from this review; the engineer's proposed issues in `status.md` stand, including the
"Comparison" string key split.
