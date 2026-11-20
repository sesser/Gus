# Tone Curve channel control width: design review

Issue #223 (bug fix). Reviewer: apple-ui-designer. Against the **Bug** section of
`status.md`, the design of the feature it touches (`docs/features/bw-module/design.md`
§3.2 and `review.md`, third pass: the same fix for the Black & White quick-set,
#218), and the HIG's Segmented controls page (fetched 2026-11-19).

**How this was read.** This session had no shell: no `git`, no `gh`, no build, no
bundle run, and I did not look at the engineer's drawings (`segmented-<n>.png`).
I read `status.md` (the issue's text is there), `AppKitSegmented` and its two new
call sites (`AdjustView.swift` lines 337 and 545), `InspectorMetrics.minimumColumnWidth`
and its use in `MainView.swift`, and `docs/USER_GUIDE.md` for mentions. I did not
enumerate the diff against `d62cd4d`, so "nothing else changed" rests on the files
`status.md` lists. Every width below is the engineer's measurement or my arithmetic
from it; the manual checks settle what I could not see.

## Verdict

**Passes.** The fix is the right shape and a one-flag change per control: both
controls stay system `NSSegmentedControl`s and now take the width the column
offers instead of forcing it past the pane. At the narrowest column every label of
both is whole with room to spare, nothing at the default or a wider pane changes,
and no control needs a different treatment (no pop-up, no abbreviations). No design
change and no Design question. One judgment point about the *Black & White*
control at 239 pt, below, which this branch does not change.

## Findings for the engineer

None.

## Design requirements, checked against the code and `status.md`

| # | Requirement | Result |
|---|---|---|
| D1 | The Adjust column stays inside the pane at every inspector width; Tone Curve's and Color Grading's controls no longer widen it (Bug "Expected") | Pass by code and measurement: `fillsWidth: true` at both sites; `sizeThatFits` answers the proposed width, so SwiftUI's minimum-width probe no longer returns 244 or 256.5 pt. Verdict `compressed`, not `overflow`, at 239 pt. Settles at M1 |
| D2 | Still system components (HIG: prefer system controls; Consistency) | Pass: the same `NSSegmentedControl`, small size, `.fillEqually`, with tooltips and accessibility label as before; no custom drawing |
| D3 | Every label whole at the narrowest column (239 pt legacy scroller, 256 pt overlay) | Pass by the engineer's drawings; see legibility below. Needs a person at M1 |
| D4 | Segments stay equal width (HIG: "keep segment size consistent") | Pass for these two (`.fillEqually`); see the Black & White note |
| D5 | Nothing changes at the default width or wider | Pass by the measurements (259 / 276 pt before and after; the controls already stretched to the column) and by the code: the flag only changes the answer when a finite width is proposed, and height stays the intrinsic small-control height. Settles at M2 |
| D6 | Spots Heal / Clone and Lens Source unaffected | Pass: both fit before and after (118 and 136 pt against 239 and 153 pt of room); Lens already had the flag |
| D7 | Tone Curve and Color Grading keep their look (text labels, no tooltips as before); no new strings | Pass: no strings added (debug output only) |
| D8 | `docs/USER_GUIDE.md` | Pass: it names Tone Curve, Color Grading and Black & White as headings and says nothing about control widths; unchanged is right |

## Legibility at the narrowest column

Arithmetic from the engineer's numbers (segment width less the widest label's text,
shared between two sides). The system's own padding in this design is about 24 pt a
segment, 12 a side.

| Control | Segment, 239 pt | Widest label | Padding a side | Segment, 256 pt | Padding a side |
|---|---|---|---|---|---|
| Tone Curve (4) | 59.8 | "Green" 36.5 | about 11.6 | 64.0 | about 13.8 |
| Color Grading (3) | 79.7 | "Highlights" 61.1 | about 9.3 | 85.3 | about 12.1 |

- **Tone Curve:** 1 pt a side under the system's default at the worst case; no
  visible difference. Four short names, all about the same weight.
- **Color Grading:** about 3 pt a side under default at 239 pt. "Highlights" is the
  longest label and has 9 pt each side, which is comfortable for a selected-segment
  capsule at the small size; with an overlay scroller it is at the system default.
- Both are well inside the HIG's segment guidance (4 and 3 segments; short nouns in
  title style; equal widths) and neither comes near truncation. This is judgment:
  the HIG gives no minimum padding.

## Judgment points (no change required)

**J1. Black & White's quick-set at 239 pt (not changed by this branch).** Five
segments make 47.8 pt each with a legacy scroller at the narrowest pane. The
engineer reports every name whole but "Yellow" and "Orange" within about 1 pt of
the dividers, and AppKit giving them wider segments than "Red". Two things follow:

- *Legibility.* Whole, not truncated, and not a conflict with the selected state
  except that the capsule will hug the text of the two longest names. At 256 pt
  (overlay scroller) the segments are 51 pt and Orange has about 5 to 6 pt a side,
  as the #218 third pass found (tight, not comfortable). The control is the
  narrowest in two stacked conditions: the smallest pane, and a legacy scroller
  (a mouse attached, or "Always"). I do not think that corner justifies a new
  treatment: shortening the names would be a wording change (design §7) that makes
  them worse everywhere for one width; a pop-up gives up the one-click compare the
  control was chosen for (§3.2); the small size is already the smallest the system
  draws. The full name stays in the tooltip, in VoiceOver and in the slider label
  below, as §3.2 says.
- *Unequal widths.* The HIG says "in general, keep segment size consistent". If
  the five segments really are drawn unequal at 239 pt (the engineer's observation,
  which I could not reproduce), that is AppKit overriding `.fillEqually` once the
  control is compressed below its intrinsic width. It is the system's behavior,
  small, and only in that corner; I would note it and not fight it. M3 asks a person
  to look.

If M3 shows Yellow or Orange touching the capsule in a way the owner dislikes, the
options for a Design question are: (a) accept, (b) raise the inspector's minimum
pane from 280 to about 296 pt, which gives every control back the 16 pt a legacy
scroller takes and fixes all of them together at the cost of 16 pt of loupe at the
narrowest (a global layout change, so the owner's call), or (c) leave as is and
treat the legacy-scroller narrowest case as a known tight spot. I recommend (a)
unless M3 shows a clash. Not a Design question now.

## Noticed, not this bug

- The engineer's note that the **Info** tab's text fields run 5 pt under a legacy
  scroller at the default width (`12...288` in a 300 pt pane that has 283 pt
  visible) is a real fault of the same kind (content under the scroller; HIG:
  layout respects the safe area / insets), and I support filing it as its own bug,
  as proposed in `status.md`. Not touched, not checked here.

## What's working

- The control is still the system control, at the small size, and keeps its
  tooltips and VoiceOver label.
- `fillsWidth` is opt-in, so any other container still gets today's intrinsic
  sizing; the four controls that matter use it, and Heal / Clone and Auto / Manual
  already fit.
- The regression check, `print inspectorwidth`, now covers every segmented control
  at the narrowest width (verdicts `fits`, `overflow`, `compressed`), which a unit
  test could not.
- The corrected doc comment on `fillsWidth` states the measured rule (widest label
  plus about 24 pt a segment) in place of #218's "about 65 pt whatever its label".

## Manual checks for a person

Build the bundle and run it on a scratch library (`--library-root`). No
VoiceOver, macOS 15 or macOS 26 items (owner's ruling). The inspector's narrowest
width is 280 pt: drag its left edge until it stops. Open a color photo in the
loupe, inspector on, Adjust tab, with the Tone, Color Grading, Black & White, Lens
and Spots headings open.

- **M1. Narrowest pane, legacy scroller.** (A mouse attached, or System Settings
  Appearance Show scroll bars: Always.) The whole column sits inside the pane: the
  first letters of the slider labels, the value fields, the headings' check boxes
  and reset arrows are not clipped on either side, and the column does not shift
  sideways when you scroll to Tone Curve and to Color Grading. Tone Curve's
  RGB / Red / Green / Blue and Color Grading's Shadows / Midtones / Highlights read
  in full, with visible air each side of the name in the selected segment. Click
  every segment of both and confirm the curve's channel and the wheel's range
  change.
- **M2. Narrowest pane, overlay scroller** (Show scroll bars: When scrolling, or
  no mouse). The same, with 17 pt more room: nothing clipped, labels roomier.
  Then the default 300 pt pane and a wide one (about 420 pt): the segmented
  controls fill the column and line up with the sliders' left and right edges as
  before, and nothing else has moved. Compare with the main checkout's build if in
  doubt.
- **M3. Black & White beside them, at the narrowest pane with a legacy scroller.**
  All five names whole; look at "Yellow" and "Orange" selected: is the capsule
  tight but readable, and are the five segments visibly equal in width? Record
  what you see; a clash is a Design question (see J1), not a fail of this branch.
- **M4. Light, Dark and Increase Contrast** (System Settings Accessibility
  Display), at the narrowest pane: selected and unselected segments of the three
  controls are distinct, labels readable, the divider lines visible.
- **M5. Spots and Lens.** Heal / Clone and Lens Source's Auto / Manual look and
  behave as before at the narrowest and default panes.

## Requirements issues

None.

## Summary for the issue

Design review of #223: passes. Tone Curve's channel control and Color Grading's range control now take the offered width (`fillsWidth`), so neither widens the Adjust column at the narrowest pane; both are still system segmented controls.
At 239 pt (legacy scroller) each label has about 9 to 12 pt a side, nothing truncated; default and wider widths unchanged. No Design question; Black & White's Yellow / Orange at 239 pt are tight but whole (judgment, M3).
Open for a person: M1 to M5 (narrowest 280 pt pane, legacy and overlay scroller, light / dark / Increase Contrast). Read, not run: no shell.
File: `docs/features/tone-curve-channel-control-width/review.md`.
