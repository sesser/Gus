# Lens corrections (#87): design review

Reviewer: apple-ui-designer. Date: 2026-11-19. Branch `feature/lens-corrections`
(compared with develop c97d579). Inputs: [design.md](design.md) as amended
2026-11-19 (§17 checks, §21 rulings), [status.md](status.md), the code in
`Sources/PhotoApp` and `Sources/PhotoCore/Edits`, the String Catalog,
`docs/USER_GUIDE.md`, the HIG.

Limits of this review. I read code only: nothing was built or run, so every
look, hover, key and click behavior below is "needs manual check" unless the code
settles it. I had no shell, so I could not run `gh issue view 87`; the PRD (rev2)
is read through the R and AC numbers that design.md and status.md cite, and
status.md's account of what rev2 says. No VoiceOver or macOS 15/26 checks are
asked for (standing rule).

## Verdict

**Pass, with three small fixes and one PRD wording change.** The inspector work
follows the design closely and uses only system components (`AppKitSegmented`
with a per-segment flag, `AdjustSlider`, `AppKitCheckbox`, a system `NSAlert`
sheet): the placement, always-shown check boxes, Source control, Manual-only
Amount, Constrain to image, caption priority, warning symbols, alert wording and
buttons, history labels, strings and the user guide's terms all match. The
findings are an edge case in the once-per-visit flag (F1), one place where the
"starts in Manual" rule is not applied (F2), a stale translator comment (F3), and
a design amendment on the magnifier plate (F4). None blocks sign-off.

**Recorded in design.md (2026-11-19, later):** F2 as DQ-4 (§3.2, §21), F4 (§10,
§14, §17.14) and the four accepted deviations below (§6, §21 "Review rulings"),
with a Revisions note.

## Findings for the engineer (most severe first)

**F1. Low, hardening: a Reset All that changes nothing leaves the frame question
off for the next change.** `resetAll()` sets `commitSkipsLensQuestion = true`,
then calls `change`; `commit` returns at `guard adjustments != committed` before
it clears the flag (`AdjustmentEditor.swift` 893 to 902). If Reset All changes
nothing, the flag stays set until the photo closes, so the next Distortion change
that would ask (after a mask or spot is added) goes through unasked. The menu
item is off for a default photo in the loupe (`canResetAll`), so a person cannot
easily reach it; the debug script's `resetAll` can. Fix: clear the flag in a
`defer` at the top of `change`, or read it into a local before the guard.
Principle served: the warning must not silently go missing (R6, AC6).

**F2. Low, design gap I now rule: Constrain to image (and any other change that
turns a group on) must follow the "starts in Manual where Auto cannot apply"
rule.** `toggleLensGroup` applies it, `setConstrainToImage` does not.
`setConstrainToImage` goes through `enableModules`, which switches the group on
with Source left at Auto. On a JPEG, or a raw the decoder already corrected, a
click on Constrain to image on a never-touched photo then leaves the group
checked, Auto stored, no segment selected, caption row 9 or 1a, and nothing
happening: the dead end that RI-5 and L3 exist to prevent. Ruling (DQ-4,
proposed; I add it to design.md on the main session's word): any change that
switches a lens group on from "never on" follows `startsInManual`, in the same
undo step. Fix: apply it in `setConstrainToImage` when the group is not on.
Amount needs nothing (only shown in Manual).

**F3. Trivial: translator comment still says "zoom".** `constrainTitle`'s comment
in `LensCorrectionText.swift` line 21 and the catalog entry "Constrain to image"
(comment: "Check box under Distortion: zoom so the corrected photo has no empty
edge") contradict DQ-1. Design §14 gives the comment "Scale the corrected photo
to fill its frame". Change both (the catalog is edited by hand).

**F4. Design amendment, small: the magnifier plate should read "After lens
correction" when either group applies.** Design §10 said "when Distortion
applies". But Lens Vignetting's gain also runs first, and the fringe picker and
Color Alignment read the corrected image, so with only Lens Vignetting on the
plate says "Before edits" over pixels that are not. Ruling: "After lens
correction" while the plan has a warp or a gain. Fix in
`fringeMagnifierTool` (`AdjustmentEditor.swift` 1813): `plan.warp != nil ||
plan.gain != nil`. The user guide's sentence ("after lens correction while
Distortion applies") then reads "while Distortion or Lens Vignetting applies".

**F5. Docs, trivial.** `USER_GUIDE.md` 616 to 618 lists the undo names but not
**Turn Off Distortion** (and its Lens Vignetting form) or **Reset Lens**, which
design §19.8 lists. Add them.

## Deviations I accept (the design text should follow the build)

- **The frame question comes after the change is on screen, not before.** Design
  §6 says a check box, segment, menu or paste asks "before the change is made".
  Built: `change` applies the values and starts the render, then `commit` asks;
  Cancel puts the saved values back (`finishLensFrameQuestion`). So a check box
  shows checked, and the photo shows the new frame, behind the sheet. That is
  the same mechanism as the slider drag, it is one code path, and Cancel
  restores everything, so I accept it; I will amend §6's wording. It is a manual
  check (M5) because a check box that flips and flips back is something to see.
- **The question does not wait behind other sheets (`LibraryModal`).** Design §6
  said it would. Menus and the inspector are blocked while a sheet is up, so the
  only gap is the short async read between a paste or preset command and its
  alert. Accepted. Nit: a second ⌘V in that gap replaces `lensQuestionTask`;
  harmless unless it is easy to guard.
- **"Once per visit" compares counts** (`count > answer`): removing one mask and
  adding another is not "a mask added" and does not ask again. Accepted as the
  simplest rule that honors "again after one is added".
- **Row 4 (Reading the camera's table) is not built.** Design allowed this if the
  read is instant, and status.md Q3 measured it (0.6 ms; the flag comes with the
  tab's load). Pass.
- **Offline photos in a paste or preset** read as "no lens" when only Auto would
  matter, so they are not counted in the question. They cannot render anyway
  until the volume is back. Accepted; the guide does not need to say it.

## Requirements issues (for the product manager)

**RI-A. AC13's "DNG-opcode sample" has no by-eye check for distortion.** The only
real DNG on this Mac with a `WarpRectilinear` opcode (Adobe's sample) has a green
plane that moves nothing, so Auto correctly finds no distortion table, and there
is no real file with a distortion table on this Mac at all (the XF14 and XF23
tables are all zeros; Panasonic, Olympus and Sony tables are not read in this
build). Distortion read from a table is therefore verified by the CPU reference,
the five goldens and the synthetic opcode DNGs, not by eye. The PRD wording is
the problem, not the build: an acceptance criterion that names a check no one can
perform will stay "open" forever. **Yes, it needs a PRD wording fix.** Suggested
text for AC13:

> Against a CPU reference (a derived tolerance) and recorded goldens, Distortion
> and Lens Vignetting render within tolerance for Manual and for synthetic DNG
> opcode lists, and Auto reads a Fujifilm RAF's vignetting table. By eye, Lens
> Vignetting on Auto matches the camera's own JPEG within about 1 px in the outer
> quarter on the XF14 and XF23 files. Auto's distortion by eye is not checked
> until a real file with a distortion table is available (a follow-up with the
> other makers' readers, F2 to F4).

The by-eye check for the sign and size of Manual distortion is M9 below (a JPEG
of straight lines), which the PRD may name as the check for AC2.

No other requirements issue: the rev2 PRD, design.md and the build agree
everywhere I could compare them.

## Design requirements against the build

| # | Requirement (design.md) | Result | Evidence |
|---|---|---|---|
| 1 | §2, §17.1: Lens heading holds Distortion, Lens Vignetting, Color Fringes, Color Alignment in that order; heading check box, Reset Lens and context menu reach all four | Pass | `LensControls` body order; `Section.lens.groups`; `Group` declared in that order; `setEnabled(section)` and `reset(section)` use `section.groups` |
| 2 | §3.1, L2: group check boxes always shown, unchecked on a new photo, same undo step for checking, uncheck keeps values | Pass | `AppKitCheckbox` has no `isVisible`; `toggleLensGroup`; `setEnabled(group, false)` keeps parameters because `on` is stored; undo name "Turn On/Off Distortion" through the existing "Turn On %@" key |
| 3 | §3.2: Source row, label "Source", 11 pt secondary, 80 pt column; `AppKitSegmented` Auto / Manual, `fillsWidth`; fits 256 pt | Pass in code; **needs manual check** at 256 pt (M1) | `sourceRow`; the control takes the width offered, so it cannot widen the column; `print inspectorwidth` reported `fits` at 283 only (the narrowest inspector can't be set by script) |
| 4 | §3.2: tooltips per segment; Auto tooltip names the reason when dimmed; Manual never dimmed; Auto-only per-segment enabled | Pass in code; **needs manual check** that a dimmed segment still shows its tooltip (M2) | `toolTips: [autoHelp, manualHelp]`, `enabledSegments: [autoUnavailable == nil, true]`; reasons in `autoUnavailableHelp` match design §5 word for word |
| 5 | §3.2, DQ-2: a click on a segment while the group is off turns it on in one step "Distortion Source"; on the selected segment of an on group: nothing, no undo step | Pass in model (`choosingLensSource`, `setLensSource`); **needs manual check** that a real click on the already-selected segment sends the action (M2); the scripted check S5 calls the editor, not the control | `choosingLensSource` returns nil when nothing changes |
| 6 | §3.2, RI-5: a group checked where Auto can't apply starts in Manual; a stored Auto shows no segment selected | Pass for the check box; **fail for Constrain** (F2) | `toggleLensGroup`/`startsInManual`; `selectedSegment` nil when Auto stored and unavailable |
| 7 | §3.3: Amount shown only in Manual; `AdjustSlider`, signed, -100 to +100, default 0; labels, help, VoiceOver names; undo "Distortion Amount" | Pass | `showsAmount`; `AdjustSlider(... range: -100...100, defaultValue: 0, format: .signed)`; `amountHelp`, `amountLabel`, `amountValueLabel`; `amountUndoName`; typed out-of-range refused by `setAmount` |
| 8 | §3.3: turned-off look while unchecked; changing the Amount checks the group in one step | Pass in code; manual check M7 | `.environment(\.adjustGroupIsOn, status.isChecked)`; `enableModules` |
| 9 | §3.4, DQ-1: Constrain to image, Distortion only, on by default, check box at `SliderRow.height`, help "Scale the corrected photo to fill its frame, with no empty edge."; undo "Turn On/Off Constrain to Image" | Pass (string, placement, labels); stale comment F3 | `LensCorrectionText.constrainHelp`; catalog entry matches; `constrainUndoName` |
| 10 | §4: one caption, first applicable row wins; row 3 beats 1b/2b; rows 1 and 2 beat everything below; rows 3 and 5 carry the symbol | Pass | `LensCorrectionStatus.init` walks the order exactly; `isWarning` for rows 3 and 5; symbol `.accessibilityHidden(true)` in `caption(_:)` |
| 11 | §4 wording of rows 1a to 10 and both groups' forms | Pass | `LensCorrectionText.caption` strings equal the design table; all have catalog entries (checked: 1a, 1b, 2a, 2b, 6, 7, 8, 9, 10, 3, 5) |
| 12 | §4 notes: row 7 built, row 4 not (instant read) | Pass | status.md Q3 |
| 13 | §5: Auto-inert states: group not dimmed, Auto segment only; Constrain and check box enabled; Manual works on top | Pass | `enabledSegments`; no whole-control disable; Constrain has no condition |
| 14 | §6: alert only when the frame moves, a photo has a mask or spot, and the edit is deliberate; never for undo, redo, History, Reset All, Lens Vignetting, a hover preview | Pass in code (F1 hardens the Reset All path) | `asksLensFrameQuestion` (`movesFrame` compares warps only, so Vignetting never asks); undo, redo and History go through `apply`; hover previews don't `commit` |
| 15 | §6: Amount drag asks at commit; Cancel restores knob, field and frame, records nothing; Change saves one step | Pass in code; **needs manual check** (M4) | `finishLensFrameQuestion`; `AdjustSlider` with a bound value, so the knob should follow `adjustments`; a real drag has not been done |
| 16 | §6: alert titles, messages (singular and plural forms), buttons **Change** (default) and **Cancel** (Esc, ⌘.), app icon, no suppression checkbox | Pass in code; **needs manual check** of keys and look (M4) | `lensFrameAlert`: first button Change, second titled "Cancel"; default `.warning` style (app icon, no caution badge); catalog has the plural variants ("1 of the 107 photos has masks or spots. They are placed...") |
| 17 | §6: once per visit; again after another photo, the grid, review, or an added mask or spot; one alert for a whole paste or preset with counts, Cancel cancels the command | Pass in code; manual check M5 | `lensFrameAnswer` cleared in `finishSession`; `confirmingLensFrameChange` counts affected photos, Cancel returns before `body()` |
| 18 | §9: Save Preset and Manage Presets list Distortion, Lens Vignetting before Color Fringes; "All settings" preset turns them off and asks | Pass in code; manual check M12 | `Group` order, `presetGroups`; `applyAdjustmentPreset` asks when the preset's groups include `.distortion`; 16 groups, so the Save Preset 2-column grid stays even |
| 19 | §9: paste and preset carry both groups; each photo reads its own table; no photo refused | Pass | render-time lookup (status.md Q2) |
| 20 | §10: "After lens correction" plate when Distortion applies | Pass as written; amended by F4 | `fringeMagnifierTool` |
| 21 | §8, L13: no menu item, shortcut, toolbar item | Pass | none added in `LibraryCommands` or the toolbar |
| 22 | §11 accessibility: names, help, order, announcements | Pass in code (no VoiceOver check asked) | strings in `LensCorrectionText`; `announceStatus` after check and Source; order is view order; fallbacks keep labels on the check boxes (`label: title`) |
| 23 | §11 Increase Contrast, Reduce Transparency, Reduce Motion: no new colors, no glass, no own animation | Pass | system controls only; `.secondary` text; the symbol is the system's; manual check M1 for Increase Contrast |
| 24 | §13: no custom chrome, no SwiftUI `ScrollView` | Pass | `AppKitSegmented` gained a flag only |
| 25 | §14: strings by hand in the catalog, no product name, reuse of keys | Pass, one stale comment (F3) | every `LensCorrectionText` literal has an entry; `Cancel` entry's comment was extended |
| 26 | §16: debug hooks (`lens print`, `lens …`, `lens force`, `alert`) | Pass | `DebugLensCorrectionCommands`; `lens print` reports the caption row, selected segment, enabled Auto, amount shown and warning; tooltips come through `buttons` |
| 27 | §19: `docs/USER_GUIDE.md` terms match the UI | Pass, with F5 | terms checked: Distortion, Lens Vignetting, Source, Auto, Manual, Amount, Constrain to image, Change, Cancel, the quoted captions; scope statement matches the ruling (Fujifilm and DNG only, "no table was found" elsewhere); Lens opening sentence says four groups |
| 28 | §17.15: Show Original removes the correction; Reset returns the identity stack (AC12) | Pass in tests (status.md), manual check M13 | `resetAndRoundTrip` |

## Improvements (judgment, not violations)

- **A person who wants "the camera's correction, a bit weaker" still has to leave
  Auto** and set their own value; the design accepted that and the guide says it.
  The Strength slider (among F5 to F8 in status.md's follow-ups) is the right
  next step, not now.
- **Rows 2a and 2b (Fujifilm built-in) cannot be seen in a real file on this Mac**
  (no LibRaw RAF), so they are checked only through `lens print` and tests.
  They share all their code with 1a and 1b, so the risk is low.
- **Keep the Lens heading expanded by default.** The tab is about 190 pt longer;
  design §2 flagged the one-key change if people find it too long. No evidence
  yet.

## What's working

- Every row is a system control in the existing wrappers; the group reads like
  Color Alignment and Black & White, so there is nothing new to learn.
- One status function (`LensCorrectionStatus`) drives the caption, the dimmed
  segment, the selected segment, VoiceOver and `lens print`, so the UI cannot say
  one thing and the debug output another.
- The caption never changes during a drag, so the layout holds still.
- The frame question is one code path for check boxes, segments, drags and
  commands, and its wording is the design's.

## Manual checks for a person

No VoiceOver or macOS 15/26. Use a scratch library copy with a mask or a spot on
at least one photo. `lens force` rows 3 and 5 are scripted, not manual.

- **M1. Lens heading look.** Narrowest and widest inspector, light, dark and
  Increase Contrast: both Source rows fit (nothing clipped, no horizontal
  scrolling), the longest captions wrap without cutting, the check boxes are
  always visible and line up with the other groups' check boxes, Constrain to
  image sits under the caption.
- **M2. Real clicks on Source.** Group off, click the selected segment: the group
  turns on, one undo step, "Distortion Source". Group on, click the selected
  segment: nothing, no new undo step. Hover each segment, including the dimmed
  Auto on a JPEG, a Lumix RW2 (system decoder corrects) and an X-E3 raw the
  system corrects: the tooltip reads as in design §5 and §3.2 (a dimmed segment
  must still show it; if not, the reason is lost and I rule a caption fallback).
- **M3. Caption rows by file.** Lumix 12-32 RW2: 1a (Auto stored, no segment
  selected), then Manual: 1b. XF14 raw: Lens Vignetting row 7 off, 6 on;
  Distortion row 8. A Canon raw or a manual lens: row 8. A JPEG: row 9 after a
  paste of Auto, row 10 in Manual. Read the words against design §4.
- **M4. The alert and its keys.** Real keyboard: a check box, a Source click,
  an Amount drag released over a photo with a spot, a typed value with Return,
  Constrain to image, Reset Lens. Each shows the title and message of §6;
  Change is the highlighted button; Return changes, Esc and ⌘. cancel. After
  Cancel the knob, the field, the check box and the photo are back as before and
  Undo shows no new step. After Change, Undo is one step.
- **M5. Once per visit and where it flips.** After Change a second change asks
  nothing; go to another photo and back and it asks again; add a spot and it
  asks again. Look at the check box and Source control behind the sheet: they
  show the new value until you answer (accepted deviation); confirm Cancel puts
  them back without a flash that looks broken.
- **M6. A selection.** Select photos mixing a photo with a table, one without, a
  JPEG, and one with a mask; Paste Adjustments from a photo with Distortion
  Manual 40, then Apply Preset with both groups on Auto. One alert each with
  "N of the M photos"; Cancel changes none; Change is one undo step.
- **M7. Turned-off look.** Uncheck a group: its rows turn secondary and stay
  usable; moving Amount checks the group again in one step.
- **M8. Constrain to image.** On a wide raw or JPEG with Manual distortion at
  +40 and -40: on, the photo fills the frame at both signs; off, a black edge
  appears for the pincushion setting. Crop still applies after.
- **M9. Sign and size of Manual.** A JPEG with straight lines bowed outward:
  positive straightens them; negative bends them inward. For Lens Vignetting:
  positive lightens dark corners, negative darkens them; one step of Amount is a
  change you can just see at 100% in a corner.
- **M10. P1 in status.md.** Lens Vignetting Auto on an XF14 or XF23 raw beside
  the camera's JPEG: corners within about 1 px in the outer quarter, by eye.
- **M11. Parity.** At fit and at 100%, a live drag of Amount and an export of
  the same value agree (status.md P5); the crop overlay and Straighten are
  usable while Distortion changes; a spot ring lands on the same pixels after a
  correction (design §7).
- **M12. Presets.** Save Adjustments as Preset and Manage Presets list
  Distortion and Lens Vignetting before Color Fringes in a tidy grid; applying an
  old "All settings" preset to a corrected photo turns Distortion off and asks
  when the photo has a mask or spot.
- **M13. Reset and Show Original.** Reset Lens returns the four groups to their
  starting state, with the heading's check box mixed while some are on; `\`
  shows the photo without the correction; History lists "Turn On Distortion",
  "Distortion Source", "Distortion Amount", "Turn On/Off Constrain to Image".
- **M14. Magnifier plate.** While picking a fringe color with Distortion on, the
  plate reads "After lens correction" (and, after F4, with only Lens Vignetting on).
- **M15. RAW+JPEG pair.** The JPEG's Auto is dimmed and a group checked on it
  starts in Manual; editing one file leaves the other (status.md P3).
- **M16. Keyboard Navigation on** (System Settings): Tab reaches check box,
  Source (arrows move, Space chooses), Amount field (arrows step), Constrain to
  image, in that order for each group.

## Summary for the issue

Design review of #87: **pass**, no blockers. Placement, always-shown check
boxes, Source control, Amount, Constrain to image, captions and their priority,
the frame-question alert (Change default, Esc and ⌘. cancel, once per visit,
counts for paste and preset), history labels, strings and the user guide all
match design.md. To fix: F1 (a no-op Reset All leaves the question off, low),
F2 (Constrain should start a new group in Manual where Auto can't apply), F3
(stale "zoom" comment), F4 (magnifier plate also for Lens Vignetting), F5 (guide
undo names). Requirements issue: AC13's "DNG-opcode sample" has no by-eye
distortion check; reword it (text proposed). Open for a person: M1 to M16 (real
clicks on Source, dimmed-segment tooltips, the alert's keys and Cancel on a
drag, 256 pt look). Details: `docs/features/lens-corrections/review.md`.
