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

(For the second pass: each finding with Fixed, Not fixed (and why) or
Withdrawn, and the commit.)
