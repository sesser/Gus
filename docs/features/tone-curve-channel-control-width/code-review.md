# Tone Curve channel control width: code review

Owner: code-reviewer. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md` (bug fix).
Reviewed: `bug/tone-curve-channel-control-width`, d62cd4d..64aa50c (the fix is
`6a6e6d7`; `64aa50c` is the design review, docs only). Build and tests:
`swift build` clean, no warnings (changed files recompiled); full `swift test`:
1240 tests in 176 suites passed (69.8 s; the #229 flake did not show).

## Verdict

Ready for QA. The fix is the one-flag change #218's third code review predicted,
at the two controls whose intrinsic width can exceed the narrowest column, and
nowhere else; the cause and the numbers in `status.md` hold up against the code
and an independent measurement; the debug-script additions are read-only except
for PNGs written into the folder the script names. No findings.

## Findings

None.

## Questions

None.

## Checked and fine

- **Cause and numbers.** `AppKitSegmented` (`CurveEditor.swift:218`) is an
  `NSSegmentedControl` with `.fillEqually` and `.small`; without `fillsWidth`
  `sizeThatFits` returns nil, so SwiftUI takes AppKit's intrinsic width with its
  horizontal compression resistance (750) as the minimum. I measured the same
  controls in a bare AppKit binary (SDK 27.2, not in a window): intrinsic 228 /
  244.5 / 110 / 128 pt for RGB-Red-Green-Blue, Shadows-Midtones-Highlights,
  Heal-Clone, Auto-Manual; widest label 36.5 and 61.1 pt, exactly the
  engineer's; padding about 20.4 pt a segment and constant across the four
  controls. So "segments equal to the widest label plus a fixed padding" is
  right. The engineer's in-app figures (244, 256.5, 118, 136; 345 for Black &
  White, which matches #218's own measurement) are uniformly 4 pt a segment
  wider than my bare control, consistent with the in-window context; the
  conclusion does not depend on which: Color Grading needs at least 244.5 pt
  either way, over 239.
- **Narrowest column.** `inspectorColumnWidth(min: 280, …)` in `MainView.swift`
  is now `InspectorMetrics.minimumColumnWidth` (280), the same value; the
  Adjust and Info scroll views pin the hosting view to the clip view's width
  (`AppKitScrollView`, leading and trailing constraints) and pad the VStack by
  `InspectorMetrics.padding` (12) a side. 280 − 17 (legacy scroller,
  300 − 283 measured) − 24 = 239; 280 − 24 = 256 with overlay scrollers. The
  Lens Source row's room, 153 at x 98, is 12 + 80 + 6 = 98 from
  `InspectorMetrics`. All consistent.
- **The fix.** `fillsWidth: true` on `ToneCurveControls`' and
  `ColorGradeControls`' controls (`AdjustView.swift:337, 545`). The proposal
  they get is always finite: `AppKitScrollView.Measured` fixes only the
  vertical size, and the host is constrained to the clip view's width, so
  `sizeThatFits` answers with the column's width. They lack the
  `.frame(maxWidth: .infinity)` the Lens and Black & White sites carry, which
  makes no difference here: a VStack child that answers the proposed width
  already fills it.
- **Every `AppKitSegmented` use** (five):
  1. Tone Curve channels, `AdjustView.swift:544`: now `fillsWidth` (needs
     228 to 244 > 239).
  2. Color Grading ranges, `AdjustView.swift:336`: now `fillsWidth` (244.5 to
     256.5 > 239; 0.5 over 256 with overlay scrollers).
  3. Black & White quick-set, `BlackAndWhiteSection.swift:58`: already
     `fillsWidth` (#218).
  4. Lens Source (Distortion and Vignetting rows),
     `LensCorrectionGroupView.swift:65`: already `fillsWidth`; needs 128 to
     136 against 153 pt of room.
  5. Spots Heal / Clone, `SpotsSection.swift:60`: needs 110 to 118 against
     239; no flag needed, and none added. English is the only localization.
  Other segmented controls are SwiftUI `Picker`s outside the inspector's scroll
  views (the Info / Adjust tab picker, toolbar, Export sheet): not this fault.
- **Default width unchanged.** With a finite proposal at or above the
  intrinsic width the flag gives the same width SwiftUI gave before (low
  hugging stretched the control to the column); height is still the intrinsic
  height; `makeNSView` only lowers compression resistance, which SwiftUI reads
  for nil proposals only. Matches the engineer's identical widths (259 / 276)
  in both builds.
- **`print inspectorwidth [<folder>]`.** Moved from `printState` into `run`'s
  `print` branch (to take the folder argument); the old `case` is removed, so
  there is one path. `print` is not in `changing` and the command changes no
  photo, so no undo group is right. Read-only apart from
  `<folder>/segmented-<n>.png` (fixed names via `appendingPathComponent`, no
  path from a file or the UI; a missing folder gives "could not write", no
  crash); the folder comes from the script, like `snapshot`'s path. The
  `Int(±infinity)` trap is gone: `guard minX.isFinite` prints `no controls`
  before any `Int` conversion (minX and maxX are set together), and the new
  lines use `String(format:)`. `fills` reads compression resistance below
  `.defaultHigh`, which separates 250 (`fillsWidth`) from AppKit's 750. The
  drawing copy is a fresh `NSSegmentedControl` in an off-window `Backdrop`
  (`cacheDisplay`), never attached to the window. Only the inspector's two
  `AppKitScrollView`s have an `NSHostingView` document in the library window,
  so the narrowest-width arithmetic (pane less 280) applies to every scroll
  view it visits. Header comment updated.
- **Estimate's limit, not a finding.** `scroller` says `legacy` whenever the
  style is legacy, even while `autohidesScrollers` hides it because the content
  is short; then the visible width equals the pane and the narrowest room
  assumes no scroller. That is right unless narrowing alone makes the content
  tall enough to need one, which I could not make concrete.
- **Concurrency.** `DebugScript` is `@MainActor`; `Backdrop` is an `NSView`
  subclass (main-actor); no new tasks, no `@unchecked Sendable` or
  `nonisolated(unsafe)`. The build has no warnings.
- **Scope.** No change under `Sources/PhotoCore`, `Tests`, `Scripts` or
  `Package.swift`: no migration, no pipeline bump, no golden, no new
  dependency, no UI string (debug output only), no brand value.
- **Test that fails without the fix.** None possible as a unit test (no test
  target imports PhotoApp, as #218's review found); the regression check is
  `print inspectorwidth`, whose before/after verdicts (`overflow` →
  `compressed`) the engineer recorded, plus P1 for a person. QA should re-run
  it.

## Follow-up

None yet.
