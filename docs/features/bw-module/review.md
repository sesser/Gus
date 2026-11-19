Issue: #218

# Black & White module: design review

Reviewer: apple-ui-designer. Date: 2026-11-18. Branch `feature/bw-module`, read
against [design.md](design.md) (as amended 2026-11-18, §21), the HIG and the
PRD as `design.md` and `status.md` cite and record it (R1 to R15, AC1 to AC14,
with the owner's rulings RI-1, RI-2, DQ-1, DQ-2).

**Limits of this review.** Read-only on source, no app run, and no shell in this
session: I could not run `git diff` or `gh issue view 218`. I found the changes
by reading the files `status.md` names and by searching the tree for the
feature's identifiers. The PRD text was not re-read from the issue; where I
cite R/AC numbers I rely on `design.md` and `status.md`. A change in a file
neither names would have escaped me. Files read in full: `BlackAndWhiteSection`,
`BlackAndWhiteText`, `BlackAndWhiteActions`, `DebugBlackAndWhiteCommands`,
`PhotoCore/Edits/BlackAndWhite.swift`, `SourceColorModel`; the relevant parts of
`Adjustments`, `AdjustControls` (`AdjustSlider`, `SliderRow`, `SectionHeader`,
`AppKitCheckbox`, `AdjustText`), `AdjustView`, `AppKitSegmented`,
`AdjustmentEditor.change`, `LibraryCommands`, `LibraryMenuContext`, the String
Catalog entries and the user guide paragraph.

## Verdict

**Needs one fix, then passes.** The heading, the control, the sliders, the
captions, the menu and the words follow `design.md` closely and use only system
components. One behavior bug breaks design §3.1 and B10 ("moving a control turns
the group on"): a slider interaction that changes nothing still switches the
conversion on and turns the photo gray (F1). Two small wording fixes (F2, F3).
Everything else needs a person at the bundle (M1 to M10).

## Findings for the engineer

### F1. A slider interaction that changes no value turns the conversion on (fix)

`BlackAndWhiteActions.setBlackAndWhite` sets `blackAndWhite.isOn = true`
unconditionally inside the change. `AdjustmentEditor.change` then sees
`next != adjustments` (the `isOn` flip is a difference) and saves one undo step
named "Black & White Filter". On a photo that never had the group, these all go
through that path with the value unchanged at 0:

- pressing and releasing the knob without moving it (`SliderRow.onTrackingEnded`
  always reports `.committed` with the current value);
- double-clicking a filter's label or knob to "reset" a filter already at 0
  (`SliderRow.reset` calls `set(defaultValue)`, which always calls `onChange`);
- pressing Return in a value field without editing it.

The photo turns gray and Undo has an entry, though the person only clicked.
Design §3.1 and B10 say moving or changing a control turns the group on; a
reset of a slider that is already at 0 is not a change. Other groups don't do
this, because their `change` closures write only the value. It also breaks
"History shows one entry per change", since History gains an entry for a click.

Fix: in `setBlackAndWhite` write only the value and drop the `isOn = true` line.
`Adjustments.enableModules(changedFrom:)` already switches the conversion on
when a filter differs and neither the old nor the new state is on, and clears
the group's `disabled` flag when a value differs, which is every case the
explicit line was meant to cover. Add a test: on a never-used photo,
`setBlackAndWhite(.red, 0, .committed)` leaves `adjustments` unchanged and
records no step. (`chooseBlackAndWhite` and `clearBlackAndWhiteFilters` are
correct: each guards on the state already being in effect.)

### F2. User guide names the wrong heading (fix, minor)

`docs/USER_GUIDE.md`, the Black & White paragraph: "after White Balance, the
Tone heading's sliders, Tone Curve and the Color Mixer". The app's headings are
Light (holding the Tone, Presence, White Balance groups) and Tone Curve
(`AdjustText.title(_ section:)`); there is no "Tone heading". Say "the Light
heading's tone sliders" (design §19.5's own words), so the term matches the UI
(P5). Optionally split this one 40-line paragraph in two (what it does and how
to use it; where it sits in the order and what it does not reach): it is the
longest paragraph in the guide's Adjust section.

### F3. Translator comment is stale (nit)

The five `blackAndWhite.filter.*` comments (in `BlackAndWhiteText.name` and the
catalog) say "Yellow and Orange are new". Yellow and Orange already exist
elsewhere in the catalog (`Yellow`, `Orange` for other uses), so a translator
reading that sentence is misled. Say only what the key is: "Black & White filter
names, as colored filters on a camera lens; Red, Green and Blue have their own
keys because they are also Tone Curve channel names". No behavior change.

## Design requirements, checked against the code

| # | Requirement (design §) | Result | Notes |
|---|---|---|---|
| 1 | Heading between Color Mixer and Color Grading; folded by default; fold state remembered; check box always visible (§2, §3.1, B1, B2) | Pass | `AdjustView` places `BlackAndWhiteSection` between the two. `@InspectorExpanded(default: false)` with key `adjust.section.blackAndWhite`; Collapse All / Expand All reach it (the header is always built, so the key is known). `AppKitCheckbox` is built with its `isVisible` default of true |
| 2 | Check box on a never-used photo: on, all 0, one step "Turn On Black & White"; uncheck keeps values (§3.1) | Pass | `toggleBlackAndWhite` goes through `setEnabled(group)`, whose name is "Turn On/Off \(title)". `Adjustments.setEnabled` sets `isOn` when turning on; `blackAndWhiteApplies = isOn && isEnabled` drives the check state |
| 3 | A slider moved while off turns the group on in the same step, "Black & White Filter" (B10) | Pass for a real change; **fail for a no-change click** (F1) | `enableModules` and the explicit `isOn` both cover real changes |
| 4 | Segmented control derived, never stored; none selected when off or mixed; choosing the selected one adds no step (§3.2, B4) | Pass | `blackAndWhiteQuickSet` is nil unless the group applies; `quickSet` compares to half a step; `chooseBlackAndWhite` returns early on the selected filter. `AppKitSegmented` passes -1 straight through. It is `.selectOne`, small, `.fillEqually`, as Color Grading's |
| 5 | A quick-set: filter 100, others 0, on, one step; undo restores all five and the on state (§3.2, §4) | Pass | `BlackAndWhite.choose` plus `setEnabled(true)` inside one `change`; `quickSetAmount` is one constant in PhotoCore |
| 6 | Five rows, 0 to 100, plain numbers, step 1, clamped, double-click reset, look turned off when not applying (§3.3) | Pass | `format: .plain`, `BlackAndWhite.amountRange`; `SliderRow.set` clamps; `.environment(\.adjustGroupIsOn, applies)` makes a never-used group read as not applied, as §3.3 asks |
| 7 | Track tints are the filter system colors, hidden when turned off, fallback possible (§5, B6) | Pass in code, needs eyes (M2) | `NSColor.systemYellow` ... `systemBlue` into `trackFillColor` only when the group applies, `.clear` otherwise; `nil` tint leaves the other sliders as before; before 26 a tint replaces the neutral gray. No drawing, no new view |
| 8 | Caption and tooltips read as §3.4 and §7 and are true of the render (§7, AC4) | Pass | Strings are word for word. I checked each sentence against the built weights (status.md table) on sample colors: Yellow (R .234, G .746, B .020) lightens yellow and skin a little and darkens blue sky; Orange (.371/.624/.005) darkens sky, lightens skin; Red (.757/.240/.003) darkens sky strongly and leaves, lightens reds and skin; Green (.035/.950/.014) lightens leaves, darkens reds and skin; Blue (.040/.672/.288) lightens sky, darkens reds and skin. The static caption's "opposite" is true of all five |
| 9 | A monochrome file shows the §6 caption; RGB with no color shows the static one; a raw never (§6, B7) | Pass in code, needs a file (M6) | `SourceColorModel.isMonochrome` reads the header only (`kCGImagePropertyColorModel`), off the main actor, false for raws; reset per photo and set in the load's `apply` |
| 10 | Adjust ▸ Black & White ▸: seven items, title follows state, check marks, enablement (§8, B8) | Pass in code; **enablement not run** (M3, M4) | Submenu sits between Auto Exposure and Reset All Adjustments. Item titles are those of §8. `Toggle`s give the check marks as Spot Mode does. `canEditLoupePhoto && !isCropping && !isComparing` on every item; the submenu's title has no `.disabled`. State is published through `LibraryMenuContext` fields (`blackAndWhiteApplies`, `QuickSet`, `HasNoFilter`), not a model passed to `Commands`. No shortcut |
| 11 | Group in Save Preset / Manage Presets in tab order; paste and presets carry it (§10) | Pass | `Group.blackAndWhite` sits after `colorMixer` in both enums; titles come from `AdjustText.title`; tests per `status.md` |
| 12 | Reset returns to a stack that never had the group; dimmed with nothing to reset (§3.1, DQ-2) | Pass | `reset: isModified ? ... : nil` and `isEnabled: isModified` plus `.disabled(!isModified)`; `reset(.blackAndWhite)` uses "Reset \(title)". Context menu: Turn On/Off always, Reset only when modified |
| 13 | History labels (§9) | Pass | Switch: "Turn On / Turn Off Black & White" (`setEnabled`, check box, menu item, context menu); every slider, quick-set and No Filter: "Black & White Filter" (`filterChange`); reset: "Reset Black & White". Same string for a drag (committed at the end), a typed value and a menu choice |
| 14 | Accessibility labels and help (§11) | Pass in code | Check box: label "Black & White" with help "Turn on / Turn off Black & White to compare" from the generic strings. Segmented control: "Filter" plus a tooltip per segment. Sliders: "Yellow filter" with field "Yellow filter value" and the sentence as help, so Tone Curve's Red/Green/Blue and the Color Mixer's Reds don't clash. Heading's disclosure and title button are the shared `SectionHeader`'s |
| 15 | Strings all in the catalog with translator comments; no hard-coded colors; no new custom chrome (§13, §14) | Pass | Every UI string in `BlackAndWhiteText` has an entry (filter names under their own keys, five help sentences, five slider and five field names, five menu items, No Filter, the two captions, "Black & White Filter", "Filter"); "Turn On %@" etc. are the existing generic keys. Only system colors. The section is a small view of its own, as design §15.3 allowed, built from existing wrappers; the one wrapper change is the optional `trackTint`. Only nit: F3 |
| 16 | User guide terms match the UI (WORKFLOW) | Pass with one fix (F2) | "Black & White", the five filter names, "No Filter", "Turn On / Turn Off Black & White", "Black & White Filter", "Reset Black & White", "Adjust ▸ Black & White ▸", "Color Mixer", "Color Grading", "Tone Curve", "Look-Up Table", "Vignette", "Grain" all match. The Presets paragraph's "All settings" note is accurate |
| 17 | Render position and scope as ruled (§2, §21) | Pass | The renderer's `globalSteps` place the conversion after the Color Mixer, before Vibrance, Saturation and Color Grading; masks, table, vignette and grain after. The user guide says the same, including a mask's White Balance (DQ-1) |

What I could not verify from here: the PRD wording (above), the strength of Red
and Green at 100 on real photos (M7), and the debug-script claims in
`status.md` (I read the script's code, not its output).

## Judgment points (no change required)

- **The submenu repeats "Black & White".** The submenu is titled Black & White and
  its first item is "Turn On Black & White". It is deliberate (design §8: a bare
  "Black & White" reads as a state, not an action, and it is the undo name), and
  it reads fine in the menu bar. Leave it.
- **Inspector active, menu dimmed while cropping.** The inspector's sliders and
  check box still act during a crop session (like every other heading), while the
  menu items are dimmed (`!isCropping`). That is what design §6 describes. A
  person who moves a slider mid-crop gets the edit; the menu simply isn't a second
  route. See M5 for the check.
- **Drag to 0 leaves the group on.** After a first drag that ends at 0 the group
  is on with every filter at 0 (gray), not "never used". It is consistent with
  B10 and No Filter and a person can get out with the check box or the reset.
  Mentioned so QA doesn't file it.
- **Yellow track fill in Light mode** is the lowest-contrast tint of the five.
  The fill is decoration (label, number and knob carry the value), so this is
  allowed by design §5 and only needs an eye (M2).

## What's working

- One heading in the standard `SectionHeader`, no new component beyond an optional
  tint, and the header's shape unchanged (disclosure, title, 16 pt check slot,
  20 pt reset slot).
- The segmented control's selection is computed from the stack, so undo, History
  revert, paste and presets never leave it stale.
- The always-visible check box plus the explicit `on` value is the right model for
  "on with all 0 is an edit"; the quick-set, No Filter and the check box all
  reach it, and `blackAndWhiteApplies` is the one place that decides what the
  controls show (heading, segments, slider fills, menu).
- The menu state goes through `LibraryMenuContext` as `CLAUDE.md` requires, and
  the submenu title is left enabled as the HIG advises.
- The sentences are true of the weights, so tooltips, help and the caption won't
  contradict what the person sees.

## Manual checks for a person (M1 to M10)

Run the bundle on a scratch library as `qa.md` will describe. No VoiceOver, macOS
15 or macOS 26 checks are asked for here.

- **M1. Look.** Open the Adjust tab on a color JPEG. Black & White sits between
  Color Mixer and Color Grading, folded, with an empty check box and a dimmed
  reset arrow. Open it: the segmented control (five names, none selected), five
  sliders with grayed labels and no fill, and the two-line caption below.
  Collapse All and Expand All include it; quit and relaunch: the fold state is
  kept.
- **M2. Tints.** Choose Red from the row: the Red slider fills red from the left,
  the others stay unfilled. Move each slider in turn and look at the five fills in
  Light and in Dark appearance, and with Increase Contrast on (System Settings ▸
  Accessibility ▸ Display). Is the Yellow fill legible against its track in
  Light? Uncheck the box: the fills vanish and the rows go gray. If any tint is
  poor, the design allows dropping them all.
- **M3. Menu.** In the loupe, Adjust ▸ Black & White ▸: the first item reads
  "Turn On Black & White"; after choosing it, "Turn Off Black & White" and No
  Filter is checked. Choose Red Filter: Red Filter checked and the segment
  selected; move a slider a little: both checks clear; set it back to 100 by
  typing: both return. Choose the checked filter: no new History entry.
- **M4. Enablement.** With the loupe's photo: all seven items enabled. In the
  grid: all dimmed but the submenu title still opens. While comparing (S): dimmed.
  While cropping (C): dimmed. On a video and an offline photo: dimmed. The
  Adjust tab shows its own messages in those states.
- **M5. Cropping.** In a crop session, move a Black & White slider and tick the
  check box: confirm it behaves like another heading's slider (the edit applies),
  and Done / Cancel behave as before.
- **M6. Monochrome file.** On a gray JPEG or TIFF, the caption reads "This photo
  has no color, so the filters change nothing." and the controls still move. On
  an RGB photo with no color, and on a raw, the standard caption shows.
- **M7. Strength.** On a blue sky with clouds, a portrait and foliage, try each
  quick-set. Are Red and Green at 100 too heavy? Is Orange between Yellow and
  Red? (Design §4: if too strong, change the filters' numbers, not the 100.)
- **M8. History and undo.** Check the box (History: "Turn On Black & White"),
  drag a slider (one entry, "Black & White Filter"), choose Blue (one entry),
  uncheck (one entry), press ⌘Z once after each and confirm each undoes exactly
  one step, and the segment and check box follow. Use the heading's reset: "Reset
  Black & White", check box unchecked, segment none, reset arrow dimmed again.
- **M9. A click that moves nothing (F1, after the fix).** On a photo that never
  had the group, click a slider's knob without moving, double-click a filter's
  label, and press Return in a value field: the photo stays in color and History
  gets no entry. Then type 30 in a field: the photo turns gray, one entry.
- **M10. Presets, paste, copies.** Save Adjustments as Preset…: "Black & White"
  is listed between Color Mixer and Color Grading and checked for a converted
  photo. Copy and paste a converted photo's adjustments onto two selected photos
  from the grid: both go gray, one undo step. Duplicate a converted photo: the
  copy starts converted and then changes alone.

Keyboard: with Full Keyboard Access on, Tab should reach the check box, the
segmented control, each slider and each field, and arrow keys should move them.
Fold it with the keyboard like the other headings. (Part of M1.)

## Requirements issues

None new. Design §18's three wording points (R12/AC12's switch label, R6/AC6's
"buttons", R1's always-shown check box) stand with the product manager as filed;
the engineer's RI-1 and RI-2 were ruled by the owner on 2026-11-18.

Proposed follow-ups, unchanged from design §18 (not this branch): Black & White
on a grid selection from the menu; a Lightroom black and white mapping into this
group; and the other headings' always-enabled reset arrows (DQ-2, being filed).

## Summary for the issue

Design review of #218 (Black & White): needs one fix, then passes. The heading,
segmented quick-set, tinted sliders, captions, tooltips, Adjust ▸ Black & White ▸
submenu, history labels, accessibility names and String Catalog entries all match
design.md as amended 2026-11-18, with system components only.
F1 (fix): a click, double-click or Return that changes no value still turns the
conversion on and grays the photo, because `setBlackAndWhite` sets `isOn`
unconditionally; drop that line (`enableModules` already covers real changes) and
add a test. F2: the user guide says "Tone heading"; the heading is Light. F3: stale
translator comment ("Yellow and Orange are new").
Open: M1 to M10 for a person (look, tints in three appearances, menu enablement,
crop session, monochrome file, Red/Green strength, undo steps, no-op click after
the fix, presets and paste). I couldn't run git or the PRD fetch; reviewed against
design.md and status.md.
Full review: docs/features/bw-module/review.md
