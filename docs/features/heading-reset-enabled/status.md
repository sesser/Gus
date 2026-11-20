Issue: #221

# Adjust headings' reset arrows enabled with nothing to reset: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design; `docs/WORKFLOW.md`
"Bug fixes"). Branch `bug/heading-reset-enabled`, cut from `develop` at
`d62cd4d`.

**Status: Done.** Next: code-reviewer, then qa-tester. The fix changes only
whether seven buttons are dimmed, to what the existing designs already say
(bw-module design §3.1 and DQ-2, chromatic-aberration design §"Off", remove-profile-group
design: "reset dimmed" on an unmodified heading), so a design review is
optional.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `d62cd4d`, a copy of the bundle with its own
identifier, a `photobench` scratch library).
1. Open an unedited photo in the loupe with the Adjust tab:
   `--debug-script "wait 2; focus RAW_00001; loupe; inspector on; tab adjust; wait 4; buttons; quit"`.
2. Then change Exposure and reset the Light heading:
   `… adjust exposure 0.5; wait 1; adjust reset develop; wait 1; buttons; wait 3; buttons; quit`.

**Expected.** A heading's reset arrow is dimmed while its groups are at
their defaults, as Crop & Straighten, Spots and Black & White already do.

**Actual.** Step 1: Reset Light, Tone Curve, Color Mixer, Color Grading,
Details, Lens and Effects all listed enabled (Crop, Spots and Black & White
disabled). Step 2: Light, Tone Curve, Color Mixer and Color Grading listed
disabled; Details, Lens and Effects stayed enabled at 1 s and at 4 s.
Scrolling the inspector so those three were on screen changed nothing.

**Root cause.** Not the model: `Adjustments.isModified(section)` was false
for every heading on the unedited photo, and the button was built with
`isEnabled: values.isModified(section)`. `AppKitButton.updateNSView` sets
`NSButton.isEnabled` from that, but SwiftUI also writes its environment's
enabled state onto every hosted `NSControl`. A temporary trace on
`NSButton.isEnabled` (removed) caught it: `updateNSView` set each reset to
false, then `NSView.adoptEnvironment(_:hostedSubview:)`, called from
`AppKitPlatformViewHost.coreUpdateEnvironment` during a later attribute
graph update, set it back to true, since nothing told the environment the
button was disabled. Which value a given button ends up with depends on
which of the two writes ran last for it: SwiftUI's environment pass
follows the first `updateNSView` on insertion (so every heading started
enabled), and later passes reach the hosts in an order that depends on what
else in the subtree updated (so after an edit and a reset the top four
headings were left with `updateNSView`'s false and the last three with the
environment's true; in a debug build the order differed and all seven
dimmed, which is the "lag" QA saw). The same thing was found and worked
around in 2026-11 for Crop (commit `287524f`, E5), and Spots and Black &
White copied that workaround (`.disabled(!isModified)`), which is why those
three were right. `AdjustSection`, the view behind the other seven headings,
never got it. The button's state is what AppKit draws: an `NSButton` whose
`isEnabled` is true draws its symbol undimmed, so the arrows were also shown
enabled, not only reported so.

**Fix.** `AdjustSection` (`Sources/PhotoApp/Views/AdjustControls.swift`)
computes `canReset = values.isModified(section)` once and uses it for the
context menu's Reset, the button's `isEnabled`, and a new
`.disabled(!canReset)` on the button, so SwiftUI's environment write agrees
with `updateNSView`. What Reset does is unchanged. The general fix (making
`AppKitButton` carry its own `isEnabled` into the environment for all its
uses) is issue #76, not this branch.

**What "at defaults" means here** (unchanged rule, now pinned by tests):
a heading offers its reset when `resetting(section) != self`. A group
turned off with values kept (`isEnabled` false) still has something to
reset, and the reset brings it back on at its defaults. The stored-but-unused
`rawDecode` operation (#219), a `cameraProfile` reference and operations this
build doesn't understand belong to no heading, so they never enable a
heading's reset (Reset All Adjustments removes the decode; it isn't a
heading). The Lens heading's Distortion and Lens Vignetting count as
modified when switched on (`isOn`) even at Amount 0, as Black & White does;
its reset switches them off. A stack from before machine learning noise
reduction had its own setting (decoder `9.dng`) reads as Machine Learning
on, so Details offers its reset.

**Test that fails without the fix.** `HeadingResetTests`
"Every heading's reset is dimmed through SwiftUI's environment too"
(`Tests/PhotoCoreTests/HeadingResetTests.swift`; PhotoApp has no test target,
so it reads the sources, like `LibraryModalTests`): every
`AppKitButton(symbol: "arrow.counterclockwise", …)` under
`Sources/PhotoApp/Views` must carry `.disabled(…)`, and there are four
(Crop, Spots, `AdjustSection`, Black & White). Checked: with the
`AdjustControls.swift` change stashed it fails at the `AdjustSection` reset;
with it, it passes. The behavior itself is checked by the debug script
(below), which is what showed the bug.

## Changes

- `Sources/PhotoApp/Views/AdjustControls.swift`: `AdjustSection`'s reset
  carries `.disabled(!canReset)`; one `canReset` for the button, its
  `isEnabled` and the context menu.
- `Tests/PhotoCoreTests/HeadingResetTests.swift` (new): the source check
  above, and the model rule: no heading modified on an unedited photo; an
  edit under one heading makes only that heading modified and its reset
  leaves none modified (also after a round trip through the stored stack);
  the stored decode, a camera profile and unknown operations make no heading
  modified; a turned-off group is modified and its reset turns it back on at
  the defaults; the legacy machine learning decoder makes Details modified.
- No change to `docs/USER_GUIDE.md`: it doesn't describe when a heading's
  reset is dimmed. No migration, no `PreviewCacheKey.currentPipelineVersion`
  bump, no rendering changed, no String Catalog change.

## Build and tests

- Baseline at `d62cd4d`: `swift build` clean; `Scripts/build-app.sh` built.
- `swift test --filter "HeadingResetTests|AdjustmentsModelTests"`: 16 tests
  passed. With the fix stashed: `HeadingResetTests` 1 failure (the source
  check), 5 passed.
- Full `swift test` (2026-11-19, with the fix): 1246 tests in 177 suites passed (72.7 s); `DeferredRenderTests` (#229) did not flake.
- `swift build`: no new warnings in the changed file.

## Debug-script checks

Bundle copy with identifier `me.sesser.gus.check221`, scratch library from
`photobench generate --jpeg 2 --dng 2` and `photobench import`, every launch
with `--library-root`.

| Check | Script (after `wait 2; focus RAW_0000N; loupe; inspector on; tab adjust; wait 4;`) | `develop` | Branch |
|---|---|---|---|
| A1 Unedited photo | `buttons` | 7 heading resets enabled | All 10 resets disabled (Crop, Spots, Light, Tone Curve, Color Mixer, Black & White, Color Grading, Details, Lens, Effects) |
| A2 Edit Light | `adjust exposure 0.5; wait 1; buttons` | Light enabled, Details/Lens/Effects enabled | Only Reset Light enabled |
| A3 Reset Light | `adjust reset develop; wait 1; buttons; wait 3; buttons` | Details, Lens, Effects enabled at 1 s and 4 s | All disabled at 1 s and 4 s |
| A4 Scrolled to the bottom | `scroll bottom; …` then A2, A3 | Details, Lens, Effects still enabled | (not needed: A3 holds) |
| B1 Edit Details, Lens, Effects | `adjust amount 40; adjust align redcyan 5; adjust grain 30; wait 1; buttons` | — | Details, Lens, Effects enabled; Light disabled |
| B2 Turn Sharpening off | `adjust off sharpening; wait 1; buttons` | — | Details still enabled (values kept, off) |
| B3 Reset Lens and Effects | `adjust reset lens; adjust reset effects; wait 1; buttons` | — | Lens, Effects disabled; Details enabled (sharpening off, kept) |
| B4 Click Details' reset | `scroll 1700; wait 1; click 1281 255; wait 1; print adjustments; buttons` | — | stack `[]`, Reset Details disabled |
| B5 Click it dimmed, edit again | `click 1281 255; adjust amount 40; wait 1; buttons` | — | Nothing changed by the dimmed click; Reset Details enabled after the edit |

Note on B4: `click` is not one of the debug script's undo-grouped commands,
so `print undo` after a scripted click shows no step; the reset's undo step
is the existing `editor.reset(section)` path, unchanged and covered by the
`adjust reset …` command.

## For a person

- P1. On an unedited photo in the loupe's Adjust tab, every heading's reset
  arrow is drawn dimmed (Light through Effects), and an edit under one heading
  undims only that heading's arrow; a reset dims it again at once. The glass
  inspector comes out blank in `snapshot`, so the drawn look can't be
  scripted.

## Open questions

None. No design questions or requirements issues.
