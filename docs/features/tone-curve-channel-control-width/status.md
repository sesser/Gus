Issue: #223

# Tone Curve channel control width: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/tone-curve-channel-control-width`, cut from
`develop` at `d62cd4d`. Same fault as the Black & White quick-set control's
(#218, `docs/features/bw-module/status.md`, "Owner finding at sign-off"),
fixed the same way.

**Status: Done.** Next: code review and the designer's review (the fix
changes how two inspector controls size), then QA.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `d62cd4d`). Open a photo in the loupe with the
inspector on its Adjust tab and the Tone heading (or the Color Grading
heading) open. Drag the inspector's divider to make the pane as narrow as it
goes (280 pt). With a legacy scroller (macOS's "Show scroll bars:
Automatically" with a mouse attached, or "Always") the fault shows for both
controls; with overlay scrollers only Color Grading's control is over, by half
a point.

**Expected.** The whole Adjust column stays inside the pane at every
inspector width; the segmented controls fit the column.

**Actual.** The Tone Curve's channel control (RGB, Red, Green, Blue) and
Color Grading's range control (Shadows, Midtones, Highlights) keep their
intrinsic widths, 244 and 256.5 pt, while the column has 239 pt at the
narrowest pane with a legacy scroller (280 − 17 − 2 × 12). SwiftUI widens the
whole column to the widest control and centers it in the pane (as the #218
finding observed), so every row (slider labels, value fields, the headings'
check boxes and reset arrows) is clipped on both edges, by about 2.5 pt (Tone
Curve) or 9 pt (Color Grading) a side. Computed, not seen: no script can set
the pane's width (see below).
With overlay scrollers the column has 256 pt: Tone Curve fits, Color Grading
is 0.5 pt over (rounding, not visible).

**Root cause.** `AppKitSegmented` is an `NSViewRepresentable` around an
`NSSegmentedControl` with `.fillEqually`. With no `sizeThatFits` answer,
SwiftUI sizes it from AppKit's intrinsic width and its horizontal compression
resistance (750), so it never makes it narrower than that width. With
`.fillEqually` that width is the segment count times (the widest label plus
about 24 pt of padding): 4 × (36.5 + 24.5) = 244 for the channels, 3 × (61.1 +
24.4) = 256.5 for the ranges, in the app, current design. In a VStack, a child
wider than the offer makes the stack wider than the column. The issue's "about
276 pt" was the control's width after SwiftUI stretched it to the default
column (its horizontal hugging is low), not its need; and #218's "each segment
at least about 65 pt whatever its label" was really the widest label
("Orange") plus padding, so the doc comment on `fillsWidth` is corrected too.

**Fix.** `fillsWidth: true` on both controls (the flag #218 added: the control
takes exactly the width offered, via `sizeThatFits`, with low compression
resistance). Every label still fits at the narrowest width (drawings below).
Spots' Heal / Clone (118 pt) and Lens's Source (136 pt, already `fillsWidth`)
never come near; Black & White's quick-set already has it.

**The check that fails without the fix.** No unit test is possible: the views
are in PhotoApp, and no test target imports it (`PhotoCoreTests` depends on
PhotoCore and PhotoFixtures). The scripts can't set the inspector's width
either: `windowsize` leaves it at 300 pt, and I tried moving the split view's
divider from the debug script (`setPosition(_:ofDividerAt:)`), which SwiftUI
ignored, so that code was removed. The regression check is therefore
`print inspectorwidth`, extended here to work out the narrowest width from the
layout at the current one: after its line per scroll view it prints one line
per segmented control with its width, its need (intrinsic width), where it
starts, whether it fills the width or keeps its own, the room it has at the
narrowest pane, the room per segment, the widest label's text width and a
verdict: `fits`, `overflow` (a control that keeps its width would widen the
column) or `compressed` (a `fillsWidth` control narrower than its own width:
check the drawing). `print inspectorwidth <folder>` also draws a copy of each
control at that narrowest room (`segmented-<n>.png`, on the window's
background; the copy's intrinsic width is printed and matches the control's).
The narrowest visible width is the visible width less the pane's excess over
`InspectorMetrics.minimumColumnWidth` (new constant, now also what
`inspectorColumnWidth(min:)` reads), so a legacy scroller is counted.

## Measurements

Copies of the bundle (`Scripts/build-app.sh`, SDK 27.2) with their own
identifiers, `me.sesser.gus.debugtest.fix223before` (this branch's tree with
the two `fillsWidth: true` removed) and `…fix223after`, ad hoc re-signed; a
`photobench generate --jpeg 4 --dng 2 --heic 1` scratch library imported with
`photobench import`, copied fresh per run, every launch with
`--library-root`. Headings open through each copy's own preferences
(`adjust.section.tone`, `lens`, `blackAndWhite`, `colorGrading`, `spots` true,
the rest false); the scroller style was set per copy with `AppleShowScrollBars
WhenScrolling` in its own domain for the overlay runs (this Mac shows legacy
scrollers otherwise). Domains deleted after. Script:

```
wait 2; focus RAW_00005; loupe; wait 2; inspector on; wait 1; tab adjust; wait 2; print inspectorwidth <folder>; scroll bottom; wait 1; print inspectorwidth; tab info; wait 1; print inspectorwidth; quit
```

Default pane 300 pt in every run. "Needs" is the intrinsic width, "room" the
width it has at the narrowest pane (280 pt).

| Control | Segments | Needs | Room, legacy (239) | Before, legacy | After, legacy | Room, overlay (256) | Before, overlay | After, overlay |
|---|---|---|---|---|---|---|---|---|
| Tone Curve: RGB / Red / Green / Blue | 4 | 244.0 | 239.0 | **overflow** | compressed, labels whole | 256.0 | fits | fits |
| Color Grading: Shadows / Midtones / Highlights | 3 | 256.5 | 239.0 | **overflow** | compressed, labels whole | 256.0 | fits (0.5 over, within the check's 0.5 tolerance) | fits |
| Spots: Heal / Clone | 2 | 118.0 | 239.0 | fits | fits | 256.0 | fits | fits |
| Lens Source: Auto / Manual (two, Distortion and Vignetting) | 2 | 136.0 | 153.0 (starts at x 98, after the label) | fits | fits | 170.0 | fits | fits |
| Black & White quick-set | 5 | 345.0 | 239.0 | compressed (#218) | compressed, labels whole | 256.0 | compressed | compressed |

At the default width the column fits in both builds (`controls 10...271` in
283 visible with a legacy scroller, `10...288` in 300 with overlay), and every
control is the same width before and after (259 pt and 276 pt, full column:
the controls already stretched to the column; the flag only lets them shrink).
Lens Source rows are 173 / 190 pt in both.

**Labels at the narrowest width (drawings).** With `print inspectorwidth
<folder>` at 239 pt, the tightest case: Tone Curve 59.8 pt a segment for
"Green" (36.5 pt of text), all four whole; Color Grading 79.7 pt a segment for
"Highlights" (61.1 pt), all three whole; Heal / Clone and Auto / Manual
roomy. Black & White (not changed here) shows all five names whole at 239 pt,
but "Yellow" and "Orange" come within a point of the segment dividers
(AppKit gives them wider segments than "Red"); see the note for the designer
below. English is the only localization (`Localizable.xcstrings`).

## Changes

- `Sources/PhotoApp/Views/AdjustView.swift`: `fillsWidth: true` on the Tone
  Curve channel control and the Color Grading range control.
- `Sources/PhotoApp/Views/CurveEditor.swift`: `AppKitSegmented.fillsWidth`'s
  doc comment states the measured rule (widest label plus about 24 pt per
  segment, the widths, the legacy scroller) in place of "at least about 65 pt
  whatever its label".
- `Sources/PhotoApp/Views/AdjustControls.swift`:
  `InspectorMetrics.minimumColumnWidth` (280).
- `Sources/PhotoApp/Views/MainView.swift`: `inspectorColumnWidth(min:)` reads
  it.
- `Sources/PhotoApp/Model/DebugScript.swift`: `print inspectorwidth [<folder>]`
  prints the pane width and scroller style, a line per segmented control, and
  with a folder a drawing of each at the narrowest room; it no longer traps on
  `Int(infinity)` when a visible inspector scroll view holds no control (#218
  code review's observation): it prints `no controls`.

No PhotoCore change, no migration, no `PreviewCacheKey.currentPipelineVersion`
bump, no rendering change, no new strings (debug output only).
`docs/USER_GUIDE.md` does not describe control widths: unchanged.

## Build and tests

- Baseline at `d62cd4d`: `swift build` clean. `swift test`: 1240 tests in 176
  suites, 1 issue: `DeferredRenderTests` ("Core Animation renders an unread
  deferred image…"), the known flake #229, on a machine loaded by two other
  engineers' builds.
- During the work: one full run had the same `DeferredRenderTests` failure
  (2 issues), and it failed again run alone under the same load. This branch
  touches only PhotoApp, which no test target imports.
- Latest, with the final sources: `swift build` clean, no warnings;
  `swift test`: **1240 tests in 176 suites passed** (68.0 s, and again 69.0 s after the last PhotoApp-only edits).
  `Scripts/build-app.sh`: builds, SDK 27.2.

## Checks

| Bug section item | Check | Result |
|---|---|---|
| Column stays in the pane at the narrowest width (Tone Curve, Color Grading) | `print inspectorwidth`, before and after copies, legacy and overlay scrollers (table above) | Before: `overflow` for both with a legacy scroller. After: `compressed` with whole labels, no control keeps a width over its room |
| Every segmented control's labels fit at the narrowest width | `print inspectorwidth <folder>` drawings at 239 and 256 pt | All whole |
| Nothing changes at the default width | widths in both builds, `controls` line | Identical |
| By eye at 280 pt | For a person: drag the inspector to its narrowest with the Tone and Color Grading headings open, with a mouse attached (legacy scroller) and without | Open (P1) |

### For a person

- **P1.** In the bundle, on a scratch library, open a photo in the loupe,
  Adjust tab, Tone and Color Grading headings open (and Black & White, Lens,
  Spots). Drag the inspector's left edge until it stops (280 pt). Check that
  the column is not clipped on either side (slider labels' first letters, value
  fields, check boxes, reset arrows), that the channel control's four names and
  the range control's three are whole, and that clicking each segment still
  switches the curve's channel and the wheel's range. Do it with a mouse
  attached or System Settings ▸ Appearance ▸ Show scroll bars: Always (legacy
  scroller), and with Show scroll bars: When scrolling.

## For the designer

- Black & White's quick-set at 239 pt (narrowest pane with a legacy scroller):
  names whole, but "Yellow" and "Orange" nearly touch the dividers. Not a
  truncation and not this bug; noted in case the designer wants a look at P1.

## Noticed, not fixed (proposed follow-up)

- With a legacy scroller the **Info** tab's text fields run 5 pt under the
  scroller at the default width: `print inspectorwidth` on the Info tab gives
  `pane 300 scroller legacy visible 283 controls 12...288 … overflow` in both
  builds (`fits`, `12...288` in 300, with overlay scrollers). The Adjust tab's
  column follows the visible width (`10...271` in 283); the Info tab's follows
  the pane's. Not this bug, not touched.

## README

Nothing for the README: no change to requirements, build commands or layout.

## Open questions

None.

## Review findings

None yet.
