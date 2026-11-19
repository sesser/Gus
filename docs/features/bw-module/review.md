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

## Follow-up: second pass (2026-11-18, commit 9e7bfe9)

Read-only again, no shell: I read the changed code, tests, catalog, guide and
`status.md` rather than the diff, and ran nothing. "Closed" below means the code
now says what I asked for; the behavior at the bundle is M9.

| Finding | Result | Evidence |
|---|---|---|
| F1: a no-change slider gesture turned the conversion on | Closed | `Adjustments.setBlackAndWhite` writes only `blackAndWhite[filter] = value`; the `isOn = true` line is gone and `BlackAndWhiteActions.setBlackAndWhite` just calls it inside `change`. `enableModules(changedFrom:)` switches the conversion on only when the filters differ and neither state was on, so a real change still turns it on in the same step (B10). `noChangeGestureChangesNothing` covers never-used at 0, turned off at the same value, and a real change from both |
| F2: "Tone heading" in the guide | Closed | `USER_GUIDE.md` now says "the Light heading's tone sliders". Paragraph split in two (what it does; where it sits and what reaches it). The terms I checked in review still match the UI. The guide also gained the sentence that a click leaving a value as it was does nothing, which is true of the code |
| F3: stale translator comment | Closed | The catalog's five filter entries and `BlackAndWhiteText.name` now read "colored filters on a camera lens"; the "Yellow and Orange are new" text is gone from the Sources tree (design.md §13 still carries the old sentence; it is the spec, and the catalog is what ships) |

**No-change gesture, design §3.1 and B10: pass.** The three routes I named
(press and release of the knob, double-click reset of a filter at 0, Return in an
unedited field) all reach `change` with the same value. The subscript write leaves
`amounts` equal, `enableModules` flips nothing, `next == adjustments`, and
`change` skips the whole save branch (`if next != adjustments`), so there is no
undo step and no History entry. The same value on a turned-off group leaves it
off, as §3.1 says moving a control turns it on only when the control changes. The
other two routes (`chooseBlackAndWhite`, `clearBlackAndWhiteFilters`) guard on the
state already in effect, as before. One residual to know about, not a defect: the
test mirrors the editor's write-then-`enableModules` sequence in PhotoCore rather
than driving the editor, so the guarantee that `change` records nothing rests on
the `next != adjustments` check, which I read in `AdjustmentEditor.change`. The
debug-script run `status.md` reports (`adjust bw set red 0`) was not run by me.

**Color Fringes swatches keeping true colors: no conflict with the design.**
`design.md` never mentions the fringe swatches (its "swatch" hits are the Color
Mixer's row), and §2's render position is untouched: the conversion still renders
after the Color Mixer in the photo, and `LensRenderer.swatch` only omits it from
the small patch (it already omits crop, alignment, fringes, masks, vignette,
sharpening, grain and noise reduction). The reason holds on Mac conventions too: a
swatch labels the color the fringe step targets, and that step runs before the
conversion, so a gray swatch would show the person a color that isn't the one they
picked, and two slots would look identical. Judgment, not HIG: the swatch still
follows the other color adjustments (a Saturation of -100 would still gray it), so
the rule is "true to the fringe color, except the tone and color edits", slightly
less clean than "pre-adjustment" but the ruling is the owner's and it fixes the
visible case. `fringeSwatchesKeepColor` pins equality with and without the
conversion and that the purple is not gray. The user guide says it ("The Color
Fringes swatches keep showing their colors") and that is accurate. No String
Catalog or UI text changed with it.

**Verdict: passes.** F1, F2 and F3 are closed; nothing new found; no design
requirement changed status (table rows 3 and 15 and 16 now pass outright).

**Manual checks, updated.** M1 to M8 and M10 unchanged. M9 stands as written (it is
the one that proves F1 at the bundle) and gains the History half: after the three
no-op gestures, History has no new entry and Edit ▸ Undo is not "Undo Black & White
Filter". New:

- **M11. Fringe swatches under Black & White.** On a photo with a Color Fringes
  slot filled (Purple, say), turn Black & White on: the photo goes gray, and the
  slot's swatch in the Lens heading stays purple. Turn it off: the swatch is
  unchanged. Other tint-changing edits (Saturation to -100) still gray the swatch;
  that is expected.

Requirements issues: none. The proposed follow-ups in the first review stand.

## Summary for the issue (second pass)

Design review, second pass, of #218: passes. F1 (a no-change slider gesture turned
the photo gray), F2 (user guide heading name) and F3 (translator comment) are closed
in 9e7bfe9; a no-change gesture now records no step or History entry (design §3.1, B10).
Color Fringes swatches keeping true colors fits the design: the spec never covered
them, and the render position is unchanged.
Open for a person: M1 to M11 (M9 proves the F1 fix, M11 is new for the swatches); read, not run.
Full review: docs/features/bw-module/review.md

## Follow-up: third pass (2026-11-19, commits 69f1ef1 and 95fa5b9)

Read-only, and this session had no shell (no `git`, no build, no bundle run). I
read the changed code (`AppKitSegmented` in `CurveEditor.swift`,
`BlackAndWhiteSection.swift`), design §3.2 and `status.md`'s "Owner finding at
sign-off" rather than the diff, and ran nothing. Every width below is the
engineer's measurement or my arithmetic, not mine at the bundle; M12 is the
check that settles it. Whether anything outside those files changed in the two
commits I couldn't enumerate; `95fa5b9` reads as a `status.md` correction (the
Tone Curve control's width), and the only other code the finding names is the
debug script's `print inspectorwidth`.

**Verdict: passes.** The finding was real (a segmented control reporting an
intrinsic width larger than its container makes SwiftUI widen the column, so the
whole tab, not just this control, broke) and the fix is the right shape: the
control is still a system `NSSegmentedControl`, now sized by the layout instead
of by its own minimum. The design is unchanged.

**Does the fix hold up?**

- **Mechanism.** With `fillsWidth`, `sizeThatFits` answers the width it is
  proposed, so SwiftUI's minimum-width probe (proposal 0) no longer returns 345 pt
  and cannot force the column wider than the pane. A nil or infinite proposal
  falls back to the intrinsic size, so any other container still gets today's
  behavior. The flag is off by default; of the other three users (Color Grading,
  Tone Curve, Spots) none sets it, so nothing else moves. The
  compression-resistance line is belt and braces for AppKit hosting; SwiftUI's
  `sizeThatFits` is what does the work. Height stays the intrinsic small-control
  height, so the row doesn't change vertically. The control is still a standard
  component with its tooltips and VoiceOver label (HIG: system components,
  Consistency).
- **Design §3.2 "full-width".** Now literally true at every pane width; before,
  it was wider than full.

**Legibility at the narrowest inspector (256 pt of content).**

- Width: 256 / 5 = 51.2 pt a segment (276 / 5 = 55 pt at the default 300 pt, as
  §3.2 says; 396 / 5 = about 79 pt at the widest). `inspectorColumnWidth` 280 to
  420 minus 12 pt of padding each side gives the 256 to 396 pt.
- English: "Orange" is the longest of the five and the only one near the limit. At
  the 11 pt small size it is roughly 38 to 40 pt of text, so about 11 pt of
  padding is left in a 51 pt segment. It fits, with less room than the
  system's own segments usually leave. The engineer's offscreen drawing found all
  five uncut; I agree it should be, and I rate it tight rather than comfortable.
- German: the app's String Catalog has no German entries (English only), so there
  are no German strings in the build to look at. The ones named in `status.md`
  (Gelb, Orange, Rot, Grün, Blau) are the usual translations and are no longer
  than the English, so they would fit as well. Treat that as an expectation, not
  a result. Longer names in other languages (Spanish "Amarillo", "Naranja", about
  45 pt) would be the first to truncate, as §3.2 already anticipated.
- Judgment, not HIG: Apple's segments are normally at least about 65 pt in this
  design (the engineer's measurement), so 51 pt is outside what the system
  draws on its own. AppKit will draw narrower, but the selected segment's capsule
  gets tight around "Orange". That is the thing to look at in M12.

**Truncation and compression: acceptable.** Segments stay equal width
(`.fillEqually`), and a label that doesn't fit truncates at the tail inside its
own segment; the control never clips at its edges, never overflows, and never
changes the pane. The full name stays available three ways: the tooltip, the
VoiceOver name, and the slider label below (§3.2's wording). No selected-state
or contrast concern is introduced. I'd prefer not to shorten the names or
switch to a pop-up for the narrowest pane: that would give up the one-click
compare the design chose the control for. If M12 shows "Orange" clipping in
English at 256 pt, the fallback is the small-size font rather than the control.

**Related and now larger: the Tone Curve control.** `status.md` says its four
segments are 276 pt intrinsic and would overflow by about 20 pt at 256 pt, and
that it did before this branch. That means the Adjust tab still widens, at the
narrowest inspector width, as soon as the Tone Curve heading is open: the same
bug the owner found, not caused here. It is a one-line change (`fillsWidth: true`
there; its names are shorter than these) and the segments become 64 pt, so it is
a safe fix. Not this branch's scope; I'd file it as a bug (title: "Tone Curve
channel control widens the Adjust tab at the narrowest inspector width") and
have the engineer apply the same flag to Color Grading and Spots only if they
measure over 256 pt (they are three segments, so probably not). The debug
script's `inspectorwidth` check is the test for all of it.

**Design change: none.** §3.2 needs no amendment; its "truncates in its segment"
sentence covers this, and the engineer did the narrowest-width check it asked
for (offscreen, not on screen).

**Manual checks, updated.** M1 to M11 unchanged. New:

- **M12. Quick-set width at three inspector widths.** Open the Adjust tab on a
  color photo with the Black & White heading open, then drag the inspector
  divider.
  - At the narrowest width (280 pt wide pane, 256 pt of content): the five names
    read in full, "Orange" included, with no ellipsis; no horizontal clipping of
    the tab (the Presets buttons, slider labels, value fields and the heading's
    check box all fully visible and not shifted); the selected segment's capsule
    still has air around its name. Choose each segment and look at the selected
    state.
  - At the default 300 pt: the row exactly fills the column (276 pt), the same
    left and right edges as the sliders; nothing cut off.
  - At a wide pane (420 pt): the segments stretch evenly, the row still lines up
    with the sliders, nothing else moves.
  - With the Tone Curve heading open instead: note whether it clips at the
    narrowest width (expected, the follow-up above), and record it, don't fail
    this branch for it.
  - Switch the system's text size if offered, or run with Increase Contrast,
    and look again at the narrowest width.

Requirements issues: none. Proposed follow-up (new, not this branch): the Tone
Curve control at the narrowest inspector width (bug), as above.

## Summary for the issue (third pass)

Design review, third pass, of #218: passes. The segmented quick-set now takes the offered width (`AppKitSegmented.fillsWidth`), so it can no longer widen the Adjust tab; design §3.2 is unchanged and no other control uses the flag.
At 256 pt of content each segment is 51 pt: all five English names fit (Orange is tightest), German would fit too (no German entries ship yet), and a longer name truncates inside its segment as §3.2 allows.
Open for a person: M12 (three inspector widths). Proposed follow-up: the Tone Curve control still overflows at the narrowest width (existing, one-line fix). Read, not run: no shell.
Full review: docs/features/bw-module/review.md
