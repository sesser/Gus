# Sharpening mask preview: designer review

Owner: apple-ui-designer. Date: 2026-11-05. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/sharpen-mask-preview`, fe33e97..cd08f25, against
[`design.md`](design.md) (DR1–DR14, §15 rulings) and [`prd.md`](prd.md)
(AC1–AC14), with [`status.md`](status.md) as the engineer's record. Code was
read, not run. The DR verdicts below are from reading the code and status.md.
The items marked for manual checks need a person at the bundled app.

## Verdict

**Passes the design, with three small fixes and the manual checks below.**
The UI matches design.md in placement, titles, enablement, the §6 state
rules, the §7 not-applied rule (all four AC11 cases), the strings and the
caption. One code fix is not visible on screen: a memory hold, fix 1. The
other fixes are a wording change in the guide and a scripted check to record.
None blocks merging the design, but the manual checks must happen before the
feature counts as Shipped.

## Design checks

| DR | Result | Notes |
|---|---|---|
| DR1 | **Pass in code; needs a scripted run** | Adjust ▸ Show / Hide Sharpening Map sits directly after Show / Hide Mask Overlay, its title follows the state, and it reads `canShowSharpeningMap`: loupe, photo, editor ready, no crop session, not reviewing (`LibraryCommands.swift:451`, `SharpeningMapActions.swift:12`). `print menustate` covers every state. `menuitems` with a key window has not been run yet (fix 3) |
| DR2 | **Pass; look needs a manual check** | A `.toggle` AppKitButton under Masking, enabled with the group off and at Amount 0. Tooltips for crop and review match §9 (`AdjustView.swift:424–464`). Height: see D-Q2 (design §15) and manual check M2 |
| DR3 | **Needs manual check** | Paths exist: the menu item is not a bare-key item, the value field steps with ↑ / ↓, and Esc hands back the keyboard and then hides the map |
| DR4 | **Pass in code; speech needs a manual check** | The canvas value is "Sharpening map, …" and its not-applied form. Show / Hide is a canvas action listed only when it can act. Announcements fire for menu, context, VoiceOver and Esc, not for the button (`SharpeningMapActions.swift:37–46`) |
| DR5 | **Pass** | Snapshots (status.md): neutral gray, same frame at fit and at 100%. The badge takes Original's place (`LoupeView.swift:913–927`) |
| DR6 | **Pass** | `sharpeningMapDisplay` clamps, then decodes through the sRGB curve; the test gives 0, 127.5 ± 1 and 255 |
| DR7 | **Needs manual check** | The spinner is a mini `ProgressView` with no visible label, a tooltip and an accessibility label, shown 150 + 350 ms into refinement. The synthetic 24 MP raw refined too fast to show it |
| DR8 | **Pass, two rows manual** | Overlay, Original (suspend and restore, not restored after a change), `\`, Crop (ends it and dims it), Paint, Pick Colors, New Mask, zoom, arrows, review, grid and relaunch: pass by script and in code. Handles are hidden under the map (`LoupeView.swift:390`). Still manual: a film strip click, and a brush drag with the map shown (AC9; key-window limits). Hover previews follow D-Q1 (a) as built |
| DR9 | **Pass** | `SharpeningMapStatus` uses `effective.local.renderedMasks`, so a turned-off mask doesn't count. The four AC11 cases pass by test and script. The legend sentence promises nothing about the masks following the map (RI-2) |
| DR10 | **Pass** | Menu, context menu, VoiceOver and the script reveal the inspector on Adjust with Details expanded and Masking in view. The button and Esc don't, as designed |
| DR11 | **Needs manual check** | Map frames are 8-bit, the layer is set to standard range (`LoupeView.swift:379`), and live frames clear `loupeHDRHeadroom`, so the HDR badge hides. Seeing it on an EDR display is still needed |
| DR12 | **Needs manual check** | No new colors. No transition between photo and map. The reveal scroll jumps with Reduce Motion (code) |
| DR13 | **Pass, one wording fix** | All 20 strings are in the catalog with comments, the old hint key is gone, and `LocalizationTests` pass. The guide uses §1's terms (Sharpening Map, sharpening map, Masking, Not Applied, Esc). Fix 2 is wording |
| DR14 | **Pass** | Esc order: crop, map, review, loupe (`LoupeView.swift:679`). The script ran value field → loupe → map hidden → grid |

PRD criteria covered by tests or script (status.md): AC1–AC3, AC6 (test),
AC7, AC8, AC9 (except the brush drag), AC10, AC11, AC12 (state), AC14. Still
manual: AC4, AC5, AC13, AC6's 400% check, and the `menuitems` part of AC12.

## Fixes for the engineer

1. **Showing the mask overlay over the map doesn't free the refiner.**
   `AdjustmentEditor.showsMaskOverlay`'s `didSet` (lines 75–79) ends the map
   with `sharpeningMap.end()` and `stopMapRefinement()` but keeps
   `mapRefiner`. That holds the full-resolution input (about 192 MB at 24 MP)
   until the photo changes, though no map is shown. Go through the same
   leave path as `endSharpeningMap` (stop refinement, drop `mapRefiner`).
   Every other way out of the map already does.
2. **USER_GUIDE.md, line 189: change "Press Esc, the toggle or Adjust ▸ Hide
   Sharpening Map" to "Press Esc, click the toggle, or choose Adjust ▸ Hide
   Sharpening Map".** Apple style says "click" for buttons and "choose" for
   menu items. In the same paragraph, add one sentence for D-Q1: "While the
   map is shown, hovering a preset or look-up table shows the map with it."
3. **Run `menuitems "Sharpening Map"` with the app active** (`open -W -n
   --stdout …`, CLAUDE.md) in the grid, on an editable photo, after
   `menupress`, during a crop session, in review, and on a video, an offline
   master and an unreadable stack. Record the results in status.md for DR1
   and AC12. Also add a script check for D-Q1: with the map shown, `preset
   preview` renders map frames (`print sharpenmap` stays on), and ending the
   preview returns the applied map.

## Manual checks (a person at the app)

- **M1, keyboard only (DR3, AC5).** With default keyboard settings: show
  the map from Help search, step Masking in its value field, then Esc twice.
  With Keyboard Navigation on: Tab from Masking's value field to the toggle,
  then Space.
- **M2, toggle look (DR2, D-Q2).** On macOS 26, compare the Sharpening Map
  toggle's bezel with the Original toggle's. They should be the same height
  and style in the inspector, in both layouts where the frame measured 20 and
  24 pt. If it is taller, pin it to its intrinsic height.
- **M3, VoiceOver (DR4, AC5).** The toggle speaks "Sharpening Map" and its
  state. The canvas actions offer Show / Hide Sharpening Map. The
  announcements are spoken, and showing the map from the menu doesn't
  produce two overlapping utterances (the announcement and the canvas
  value change).
- **M4, refining on a real compressed 24 MP raw (DR7, AC4).** No spinner
  during a drag. After release, the spinner appears only if the exact map
  takes over half a second, then goes away. The map darkens progressively
  while dragging and while stepping with the keyboard.
- **M5, EDR display with an HDR photo (DR11, AC13).** The map's white
  matches the interface's white, and the HDR badge is hidden while the map
  is shown.
- **M6, Increase Contrast and Reduce Motion (DR12).** The badge and legend
  stay legible, and there is no animated transition.
- **M7, film strip and brush (DR8, AC9).** Clicking another film strip
  thumbnail ends the map. With a brush mask selected and the map shown, a
  drag on the photo pans and doesn't paint.
- **M8, zoom (AC6).** The map shows at fit, 100% and 400%.
- **M9, photo edge (design §5 judgment).** On real photos with smooth areas
  at the frame's edge, check whether the black map edge is still findable
  against the loupe surround. If it isn't, that is a follow-up design
  change, not a fix here.
