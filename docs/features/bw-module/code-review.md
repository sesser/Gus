# Black & White module (film filters): code review

Owner: code-reviewer. Date: 2026-11-18. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/bw-module`, 91e4e1c..f7fc8f3 (develop's merge base to head,
7 commits). Build and tests: `swift build` passes; `swift test` passes, 1186
tests in 174 suites (`BlackAndWhiteTests` 24), on this Mac (macOS 27.2.1).

## Verdict

Not ready yet, but close. The model, render step, reference, goldens and
stack rules are right, and nothing existing moved. Two Should fix findings
remain. In the app, a slider gesture that changes no value turns the photo
gray (C1). In `photocli develop`, whether the group ends up on after a reset
and a set depends on the photo's earlier state (C2). Both are small fixes in
one place each.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoApp/Model/BlackAndWhiteActions.swift:78-83` | `setBlackAndWhite` sets `isOn = true` even when the filter's value does not change. `enableModules(changedFrom:)` already switches the group on when a filter really changes (`filtersDiffer`), and the generic `disabled` loop handles a group that was turned off. So the extra line only matters for a change that changes no value. | On a photo that never had the group, open the heading and double-click any slider (or its label), or click in a field showing `0` and press Return. `SliderRow.reset()`/`set(_:)` sends `onChange(0, .committed)` with no check against the current value. `change` then sees `isOn` false → true, so the photo turns gray and an undo step and History entry "Black & White Filter" are recorded. Nothing was moved. For every other group, the same gesture changes nothing and records no step. QA can show it with `adjust bw set red 0` on a fresh photo, which prints `on true applies true`. Fix: remove `$0.blackAndWhite.isOn = true` from `setBlackAndWhite`. | PRD R1 ("off by default"), design §3.1 and B10 ("moving a slider… while the group is off turns it on"), `CLAUDE.md` Undo ("each step records exactly what it changed") |
| C2 | Should fix | `Sources/PhotoCore/Edits/AdjustmentEdits.swift:159-165` | The rule "setting a filter switches the group on unless the edits set `on`" compares against `Adjustments(stack: self)`, the stack before the edits' resets. `runDevelop` puts every `--reset` before every `--set`. So a whole-module reset (or `--reset all`) followed by a filter set gives a result that depends on the photo's earlier state. | Reproduced with `photocli develop` on a scratch library. With version 1 at `{on: true, red: 100}`, `--reset blackAndWhite --set blackAndWhite.green=50 --dry-run` gives `{"green": 50}` with no `on`, so the photo renders in color, with `changed: true` and no error. The same command on a photo that never had the group gives `{on: true, green: 50}`. The same applies to `--reset all --set blackAndWhite.red=40`. Fix: decide `on` from the edits themselves. If `on` was set or reset by name, honor that (track a reset of `blackAndWhite.on` apart from "not mentioned": today `expected[…] = nil` erases the difference). Otherwise, if the edits set any filter, `on` is true. | Design B10 (the precedence `photocli` was meant to follow); `CLAUDE.md` photocli edits behave "as in the app" (`applying`'s doc comment) |
| C3 | Nit | `Sources/PhotoCore/Edits/AdjustmentEdits.swift:158-168` | `--set blackAndWhite.on=true` on a group that is turned off (operation `isEnabled: false`, `{on: true, …}`) succeeds and changes nothing. The parameters are equal, so `enableModules` keeps the module in `disabled`. | `photocli render IMG.JPG --stack off.json --set blackAndWhite.on=true --out …` prints an `editStack` that is still `isEnabled: false` and renders in color. In the app, Turn On does both things (`setEnabled`). For other modules, `photocli` has no way to re-enable a group either (this predates the branch), but for this module `on` reads as the switch. Either let an explicit `on=true` also clear `disabled`, or say in the `adjustments` description that it does not. | PRD R1 (explicit on state) |
| C4 | Nit | `Tests/PhotoCoreTests/BlackAndWhiteTests.swift:554-557` | `pipelineVersionUnchanged` hard-codes `== 12`. `feature/remove-profile-group` (#219) bumps the version to 13 and changes `GPUDemosaicDecodeTests` to `>=`. | Whichever of #218 and #219 merges second, this test fails after `develop` is merged in. At that merge, set it to develop's value; it is meant to say "this branch did not bump". | AC13 |

## Merge risk with #219 (`feature/remove-profile-group`)

A trial merge (`git merge-tree HEAD feature/remove-profile-group`) has one
textual conflict: `Adjustments.Group`'s first line in
`Sources/PhotoCore/Edits/Adjustments.swift` (this branch split it after
`colorMixer`; #219 removes `profile`). The resolution is the #219 line with
`blackAndWhite` before `colorGrade`. `AdjustControls.swift` (`AdjustText.title`),
`AdjustmentEditor.swift`, `DebugAdjustCommands.swift`, `AdjustView.swift`,
`Localizable.xcstrings`, `AdjustmentsTests.swift`, `GoldenTests.swift` and
`USER_GUIDE.md` merge on their own.

Semantic risks after the merge:

- C4 (the pipeline version test).
- #219's `resettingEverySectionGivesBackTheIdentity` now expects a leftover
  decode. This branch's added B&W line sits before the loop, so it still
  holds; rerun `AdjustmentsModelTests`.
- `LocalizationTests` must pass on the merged catalog, since #219 removes
  entries next to the ones added here. Nothing in this branch uses a Profile
  string.

## Questions

- **Designer (Color Fringes swatches).** `LensRenderer.swatch` renders a
  slot's swatch through `globalSteps` with the photo's effective values, so
  with Black & White on, both fringe slots' swatches come out gray. Telling a
  purple slot from a green one then rests on the labels alone. This follows
  the swatch's stated purpose ("how a pixel of that color looks in the photo
  now"), but neither design names the combination. Should the swatch leave
  the conversion out? Not seen on screen; derived from the code.

## Checked and fine

- **No existing render changed (R13, AC1, AC13).** Off by default, and
  `isOn == false` with no filters writes no operation (`ParameterBuilder`
  leaves defaults out), so stacks without the group are byte for byte and
  hash for hash as before (`EditStackCorpusTests` passes). The renderer step
  runs only when `isOn` holds on the effective values, and a turned-off group
  is reset by `effective`. `currentPipelineVersion` is still 12. No migration.
  The `ColorMixer` → `BlackAndWhite` → vibrance order in `globalSteps` matches
  R7 as amended.
- **Goldens.** The diff adds exactly three PNGs
  (`blackAndWhite-noFilter-patchChart`, `-red-hazyLandscape`,
  `-yellowGreen-hueRamp`). No existing golden and no `*.fingerprint.json`
  changed. The goldens are in their own commit (2708de2) with a reason; no
  tolerance was loosened. The hazy landscape golden was looked at: gray.
- **Math.** The weights are Rec. 709 × Π tᵢ^(aᵢ/100), divided by their sum.
  They are always positive, so the sum is never 0, and they sum to 1, which
  keeps a neutral at its level (R4). Amounts are clamped to 0…100 in the mix.
  `CIColorMatrix` puts the same row in R, G and B with zero bias, so
  R = G = B exactly, and nothing clamps (R8). The reference
  (`BlackAndWhiteReference`, exp/log in place of pow, plain loops) agrees on
  four scenes and 27 mixes within the derived half-float tolerance. Weights
  agree with the module's to 1e-12. The direction tests cover R5 and the
  Red < Orange < Yellow ordering on blue.
- **Stack handling.** Lenient read like every schema-1 module (non-numbers and
  non-finite values fall back to defaults). Stored out-of-range values are
  kept and written back unchanged, and only clamped in the mix. Unknown kinds
  and newer `kindVersion`s are still preserved. Unreadable stacks are still
  never written (`readableEditStack`, untouched). Reset (`resetModule`) clears
  values and `disabled`, so the stack is `.identity`.
- **Explicit `on`, and "changing a filter while off turns it on".**
  `setEnabled(.blackAndWhite, true)` sets `isOn`; `false` keeps the values in
  `disabled`. `enableModules` switches `on` only when filters differ and
  neither side was on. In the app, `chooseBlackAndWhite` and
  `clearBlackAndWhiteFilters` turn the group on in the same step and return
  early when nothing would change; with the group turned off, the quick-set
  reads as nil, so a click turns it back on, as design §3.2 says. No generic
  caller iterates groups through `setEnabled` (grepped), so the side effect
  reaches only Black & White.
- **Presets, paste, copies, batch (R11).** It is a preset group, so it is in
  `presetGroups` and is copied with its on/off state by `copyModule`.
  `encodeGroups` and `decodeGroups` use the generic name `blackAndWhite`.
  "All settings" (nil) replaces it, as the user guide says. `pasted(onto:)`
  carries it. Masks' `LocalValues.modules` leave it at its default (R10).
- **`AdjustmentParameters.swift`** describes `on` (boolean) and the five
  filters (0…100), in render order. `photocli` refuses 150 and −5.
- **Swift 6 concurrency.** `BlackAndWhite` is a value type made of
  `[Double]` and `Bool` (Sendable). `SourceColorModel.isMonochrome` runs in
  `Task.detached` off the main actor, and only its result is assigned on the
  main actor after the cancellation and version check. `DebugBlackAndWhiteCommands`
  is `@MainActor`. There is no new `@unchecked Sendable` or
  `nonisolated(unsafe)`.
- **`SourceColorModel` (untrusted file).** It reads only the header's
  properties through ImageIO (`kCGImageSourceShouldCache: false`); there is
  no parsing of our own and no buffer arithmetic. Raws are excluded by
  extension, and an unreadable or missing file gives false.
- **UI rules.** The menus read `LibraryMenuState` through the focused
  context (`menu?.state`), never a model passed into `Commands`. Items are
  dimmed in the grid, while cropping and while comparing. There is no
  SwiftUI `ScrollView`. The heading's controls are `AppKitCheckbox`,
  `AppKitSegmented`, `AppKitButton` and `AdjustSlider`. The track tint is nil
  for every existing slider, so their look is unchanged on both code paths.
- **Localization and branding.** All 31 new keys are in
  `Localizable.xcstrings` with comments and English values. The keyed
  entries (`blackAndWhite.filter.*`, `blackAndWhite.quickSet`) keep the Tone
  Curve's "Red", "Green" and "Blue" separate. Undo and History labels reuse
  the existing `Turn On %@`, `Turn Off %@` and `Reset %@`. Persisted names
  (`blackAndWhite`, `on`, filter names, `adjust.section.blackAndWhite`) carry
  no product name. No new dependency.
- **Debug script.** `adjust bw …` runs under `adjust`, so inside its undo
  group. The `buttons` addition only appends a check box's state and a
  segmented control's selection.
- **Dead code.** None found: every new symbol (`quickSetAmount`,
  `hasNoFilter`, `filtersDiffer`, `blackAndWhiteApplies`,
  `BlackAndWhiteText.turn`, `noFilter`, `quickSetName`) has a caller.

`/security-review` is not needed. The branch adds no parser of its own (one
ImageIO header read), no subprocess, no network code, and no file writing
outside the library.

## Follow-up

Second pass, 2026-11-18, on `9e7bfe9` (f7fc8f3..9e7bfe9, one commit: the
fixes for C1 to C4, the designer's F1 to F3 and the owner's ruling on the
Color Fringes swatches). Build: `swift build` passes. Tests: one full `swift
test` passed, 1189 tests in 174 suites, `Deferred renders` included.
`BlackAndWhiteTests` (27) passed alone three times out of three.

**Verdict: ready for QA.** All four findings are closed, and the commit adds
no new finding.

| # | State | Commit | Notes |
|---|---|---|---|
| C1 | Fixed | 9e7bfe9 | `setBlackAndWhite` writes only the value (`Adjustments.setBlackAndWhite`), so the switch-on now comes only from `change`'s `enableModules`, which needs `filtersDiffer`. A press, double-click or Return that leaves the value as it was gives `next == adjustments`. Nothing is rendered and no step is recorded, because `commit` has nothing to save. The other entry points (`chooseBlackAndWhite`, `clearBlackAndWhiteFilters`, `toggleBlackAndWhite`) are unchanged and still guard against no-ops. A drag out and back still leaves the group on, which is how every other group behaves after a drag on a turned-off module. `noChangeGestureChangesNothing` checks the helper plus `enableModules` in the order `change` runs them. It cannot see the editor's closure, but that closure is now one call to the helper. The engineer's debug-script run (`adjust bw set red 0` → `on false`, no step) is the end-to-end check, and QA should repeat it. |
| C2 | Fixed | 9e7bfe9 | Reproduced again with `photocli develop` on a scratch library. Version 1 was at `{on, red: 100}` and version 2 was fresh. `--reset blackAndWhite --set blackAndWhite.green=50 --dry-run` gives `{on: true, green: 50}` on both, and `--reset all --set blackAndWhite.red=40` gives `{on: true, red: 40}`. The result no longer depends on what the photo held. |
| C3 | Fixed | 9e7bfe9 | `photocli render … --stack` with a turned-off `{on: true, red: 50}` and `--set blackAndWhite.on=true` now gives `isEnabled: true`, which renders gray. |
| C4 | Fixed | 9e7bfe9 | Now `>= 12`. That no longer catches a bump made on this branch, but the diff does: `PreviewCacheKey.swift` is untouched (base..HEAD). This test now just survives #219's 13. |

**The new `on` logic in `EditStack.applying`.** I traced each path and ran
most of them through `photocli develop --dry-run` and `photocli render
--stack`. The only callers are `runDevelop` (every `--reset` before every
`--set`) and `runRender` (sets only).

- *Set, then reset.* A module reset or `--reset all` after a set clears both
  `blackAndWhiteOn` and `setsBlackAndWhiteFilter`, so nothing is left
  (`scriptedOnState`). A filter reset by name after a filter set does not
  clear the flag, so `{on: true}` is left behind. Neither CLI command can
  issue that order, so only a direct caller of the API could reach it. Not
  a finding.
- *Reset everything, then set.* `--reset all --set blackAndWhite.red=40`
  gives `{on, red: 40}` (above). `--reset all --set exposure.ev=1` leaves
  Black & White at identity, since `storedOn` is false.
- *An explicit `on=false` with a filter set*, in either order, or
  `--reset blackAndWhite.on --set blackAndWhite.red=40`, gives `{red: 40}`
  and renders in color: `on` set by name wins. The `expected` check passes
  because `false` is the default and is left out.
- *Turned-off interplay (`render --stack`, operation `isEnabled: false`).*
  Starting from `{on, red: 50}` turned off:
  - `on=true` turns it on (C3).
  - `red=60` turns it on.
  - `red=50` (no change) keeps it turned off and unchanged, as in the app.
  - `on=false` gives `{red: 50}` turned on, which renders the same color.
  - `exposure.ev=1` leaves it as it was.

  One corner: a turned-off `{red: 50}` with `on` false, plus `red=50`, gives
  `{on, red: 50}` still turned off. `isOn` is set after `enableModules`, so
  the group stays off: the stack changes but not its render hash. The app
  can't produce that state, since its Turn Off keeps `on` true, and
  `photocli`'s `on=false` clears the turned-off state. Only a hand-written
  stack has it. Not a finding.
- *Edits that don't touch the group* keep `storedOn` (`{on, red: 100}`
  stays).
- *Two differences from the app, both following the rule in the user guide
  ("setting a filter turns it on unless the same command sets or resets
  `blackAndWhite.on`").*
  - `--set blackAndWhite.red=0` on a fresh photo gives `{on: true}`, which
    renders gray. In the app, the same no-change gesture does nothing.
  - `--reset blackAndWhite.red` on `{red: 100}` with `on` false stays off,
    while a double-click on the slider in the app switches it on.

  An explicit command is taken as intent, and a reset by name is not a set.
  I take both as by design, so they are not findings.

**Swatch change (owner ruling).** `LensRenderer.swatch` has one caller,
`FringePicker.swatch`, which `AdjustmentEditor.refreshFringeSwatches` calls.
No golden, render path or export reaches it. The commit adds no PNG and no
fingerprint, and `GoldenTests` passed in the full run. Clearing
`blackAndWhite` on `values.effective` is safe: `effective` has already
dropped the module from `disabled`. A stack whose only change is Black &
White now takes the `isDefault` early return, which is the plain patch.
`fringeSwatchesKeepColor` would fail without the change (the swatch would be
R = G = B). It compares two renders of one identical 4×4 float graph exactly
and passed in four runs.

**Determinism.** The three new tests use no sleeps, clocks or randomness. Two
are pure value checks. The swatch test is the 4×4 render above, which has no
tiling. The one-level 8-bit variance recorded in #65 was on 24 MP Core
Animation renders.

**`DeferredRenderTests` flake: plausibly pre-existing; I did not run it on
develop.** It passed in my full run.

- The test the engineer names, `coreAnimationRendersDeferredImages`, makes
  its own `RenderEngine` and counting providers. It asserts how often Core
  Animation and Core Image pull an image's provider, which is undocumented
  behavior.
- Nothing on its path changed on this branch. The branch's sources are the
  Black & White files, `Adjustments`, `AdjustmentEdits`,
  `AdjustmentParameters`, `AdjustmentRenderer`, `LensRenderer`,
  `SourceColorModel` and the app's UI. It does not touch `RenderEngine`,
  `PreviewGenerator` or the test.
- The same file already has a recorded load-dependent flake:
  `matchesCoreAnimationsRender` failed 2 of 5 full runs in
  `docs/features/dehaze-above-white/code-review.md` and
  `full-render-main-thread-stall` C1.
- What the branch adds is GPU load running at the same time: the Black &
  White suite renders for about 56 s of the 69 s run.
- A run on develop wouldn't settle it either way: one pass there proves
  nothing about a failure seen in one run of three.

If it fails again on this branch or on develop, it should become its own
bug issue (`DeferredRenderTests.coreAnimationRendersDeferredImages` fails
under a full parallel run). It does not block this branch.

`/security-review` is still not needed: no parser, subprocess, network code
or file writing was added.

### Third pass, 2026-11-19 (owner's sign-off finding)

Reviewed `69f1ef1` and `95fa5b9` only (c5a79b6..95fa5b9): `AppKitSegmented.fillsWidth`,
its use by the quick-set control, `print inspectorwidth` in the debug script,
and `status.md`. Build: `swift build` passes. Tests: one full `swift test`
passed, 1189 tests in 174 suites. I did not launch the app (QA's job).

**Verdict: ready for QA.** The fix is correct and contained, and the two
commits add no finding.

| # | State | Commit | Notes |
|---|---|---|---|
| Owner finding (Adjust column wider than the inspector with Black & White open) | Fixed | 69f1ef1 | See below. Status's before/after (`visible 300, controls −26…326, overflow` → `8…292, fits`) is the engineer's measurement; QA should repeat it with the heading open. |

**Checked and fine.**

- *Off by default.* `fillsWidth = false` is a stored default; the other three
  callers (Tone Curve and Color Grading in `AdjustView.swift`, Spots mode in
  `SpotsSection.swift`) don't pass it. With it off, `makeNSView` sets nothing new
  and `sizeThatFits` returns nil, which is SwiftUI's default sizing (the
  intrinsic size with the control's own priorities), so their layout is as
  before.
- *Sizing logic.* With it on, `sizeThatFits` returns the proposed width and the
  intrinsic height, which doesn't depend on width. A nil proposal (ideal size) or
  an infinite one (a stack's flexibility probe) falls back to the default; a
  0 proposal returns 0. So the stack sees the control as running from 0 to
  unbounded and gives it the column's width. Nothing in the method changes the
  view, so there's no layout loop. Lowering the compression resistance only
  matters on the fallback path, and there it agrees.
- *Proposal chain.* `AppKitScrollView` pins the hosting view's leading and
  trailing edges to the clip view and turns off `sizingOptions`. `Measured` is
  `fixedSize(horizontal: false, vertical: true)`: only height is unbounded. No
  `fixedSize` or `ViewThatFits` sits above the section (`AdjustView`,
  `BlackAndWhiteSection`). So the proposal is always the clip width minus the
  padding, whether the inspector is 280 to 420 pt wide or a window resize moves
  it. `AppKitScrollView` itself is unchanged, so the Info tab and the grid-mode
  Adjust tab are unaffected.
- *Long or localized labels.* Below the labels' width, `fillEqually` segments
  truncate inside the control instead of widening the column (design §3.2
  allows this). Reduce Motion doesn't apply: nothing is animated.
- *Debug command.* `print inspectorwidth` only reads: it converts frames and
  prints. `print` isn't in `changing`, so it opens no undo group, which is
  correct for a read. It uses the library window (`DebugScript.window`), not the
  key window, so it works from a shell launch. It runs on the main actor
  (`DebugScript` is `@MainActor`). It's listed in the header comment. It isn't
  UI text, so the String Catalog doesn't apply.
- *Observation, not a finding.* `Int(minX)` would trap if a visible
  hosting-view scroll view held no visible `NSControl` (minX stays infinite).
  Every such view in the window today has one: the grid-mode Adjust tab's
  Open in Loupe button, the Presets buttons, the Info tab's fields. So I can't
  reach it. A guard would make the tool safer if it is reused elsewhere.
- *No test.* `PhotoCoreTests` is the only test target and doesn't depend on
  PhotoApp (`Package.swift`), so a SwiftUI layout test isn't possible here. The
  scripted `print inspectorwidth` stands in for one, and the 280 pt inspector
  (which a script can't set) goes to the person's list in `qa.md`.
- *Related, already on develop.* The Tone Curve's four-segment control is
  276 pt intrinsic (95fa5b9) and would push the column out by about 20 pt at
  the narrowest inspector. That's older than this branch, and the engineer
  proposes it as a follow-up issue; `fillsWidth: true` there would be the
  one-line fix.

`/security-review` is still not needed.

### Fourth pass, 2026-11-19 (merge of develop with #219, `cc0081e`)

Reviewed only the hand resolution (`git show --remerge-diff cc0081e`) and
whether the auto-merged files needed one. Build: the merged tree compiles (a
full `swift test` was running in this worktree from a bundle built at 07:06:23,
after the 07:05:54 merge, clean tree); I did not start another SwiftPM build.
Tests: from that bundle, `--filter
"BlackAndWhite|AdjustmentsModelTests|AdjustmentParameter|PresetTests|StoredLook|LocalizationTests|EditStackCorpus|CommandTests"`
passed (121 tests, 21 suites), and `GoldenTests|ReferenceTests` passed.

**Verdict: the resolution is right; no new finding.**

- *The conflict.* `Group` is develop's line without `profile`, then
  `blackAndWhite` (with its comment), then `colorGrade`, which is the
  resolution forecast under "Merge risk with #219". `presetGroups`
  (`allCases` minus `.spots`) therefore runs `…, noiseReduction, colorMixer,
  blackAndWhite, colorGrade, lookTable, …`. `placement` checks that order,
  and the order of `Section` and the stack, and it passes.
- *Auto-merged code needed nothing more.* `kinds` has no `.profile` case and
  has the `.blackAndWhite` case. `Section.develop` is develop's
  `[.whiteBalance, .light, .presence]`, and `Section.blackAndWhite` is kept.
  `AdjustText.title` has no `.profile` case, and the switch is exhaustive since
  the tree builds. `AdjustmentRenderer` keeps the branch's B&W step and
  develop's removed boost. Develop's `resettingAll()`, which the editor and
  batch Reset All both use, rebuilds from `preserved`, so it resets Black &
  White. `pasted(onto:)` (`keepingDecode`) and `replacing` don't touch B&W.
  `decodeGroups` drops a stored `profile` name, and a nil list is
  `presetGroups` with B&W included, as the user guide says. No `.profile`,
  `decode.look`, `RawDecode.Look` or `chooseDecoder` is left in `Sources/` or
  `Tests/`.
- *Tests.* `AdjustmentsModelTests`' reset-every-heading test merged with B&W
  set before the loop and develop's leftover-decode check after it, and it
  passes. The golden list has the three B&W cases and lacks `raw-lookFlat`
  and `raw-lookNeutral`. `pipelineVersionUnchanged` is `>= 12`, not hard-coded,
  and passes at develop's 13 (C4).
- *Catalog and guide.* The merged `Localizable.xcstrings` parses (1285 keys)
  and `LocalizationTests` passes. `USER_GUIDE.md` has no leftover Profile
  control text. Its Black & White section and the preset paragraph that
  mentions B&W are intact.

`/security-review` is still not needed.
