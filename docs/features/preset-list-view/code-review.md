# Preset list view: code review

Owner: code-reviewer. Date: 2026-11-20. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/preset-list-view`, 97e0d46..a755063 (five signed commits).
Build and tests: `swift build` clean; `swift test` 1264 tests in 181 suites
passed (74 s), the same count `status.md` gives. No golden changed, no
migration, `PreviewCacheKey.currentPipelineVersion` untouched.

## Verdict

Ready for the designer's review and QA. The feature code is correct and
small. The one Should fix is in the debug script: the change to
`print inspectorwidth` hides the overflow that #223 was found with. Two nits.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoApp/Model/DebugScript.swift:1307` | The new `trailing` exemption in `printSegmentedWidth` applies to **any** keeps-width segmented control whose right edge is at the column's trailing padding. Keeps-width `NSSegmentedControl`s stretch to the column (they are not `fillsWidth`, and their hugging lets SwiftUI widen them), so every full-width one meets the test, not only the Presets switch. | Spots' Heal / Clone control: `buttons` shows it 259 pt wide at x 12 in a 283 pt visible column (`docs/features/tone-curve-channel-control-width/qa.md` S3), so `frame.maxX` = 271 = `clip.bounds.width - padding`. It now prints `trailing (see print presetsbar)` instead of `fits`. Worse: before #223's fix, Tone Curve was the same kind of control (keeps width, 259 pt at x 12, needs 244 against 239 pt of room), and that QA run caught it as `keepsWidth ... overflow`. With this rule the same layout prints `trailing`, so the only check for the #223 kind of overflow stops finding it. Fix: exempt only a control that keeps its own width and does not start at the column's edge (for example `abs(frame.width - needs) < 0.5 && frame.minX > InspectorMetrics.padding + 0.5`), or match the switch by its accessibility label ("Presets view"). | `CLAUDE.md` UI rules; #223 |
| C2 | Nit | `Sources/PhotoApp/Views/PresetList.swift:152-156` | The `"\u{3}"` (Enter) branch never matches. It requires an empty set of device-independent modifier flags. Keypad Enter carries `.numericPad` (bit 21), and fn+Return carries `.function` (bit 23). Both bits are inside `deviceIndependentFlagsMask` (0xffff0000). | Enter on a focused row goes to `super.keyDown`, which does nothing. Return works. `status.md` says "Return and Enter apply a focused row", but the user guide says only Space or Return, so nothing a user reads is wrong. Fix: drop `.numericPad` and `.function` from the flags before the test, or drop the Enter branch and the claim in `status.md`. | Correctness |
| C3 | Nit | `Sources/PhotoApp/Model/DebugScript.swift:204-207` | `preset row <name> focus` changes nothing, but it is grouped (`preset` is in `changing`, and only `view` and `heading` are excluded). An empty group is still an undo step. I checked: with `groupsByEvent` false, an empty begin/end pair makes `canUndo` true, and the next `undo()` consumes it instead of the step before it. | A QA script that runs `preset row Look 03 focus` and then `undo`, expecting to undo the earlier apply, undoes nothing. Fix: add `row … focus` to the exclusion next to `view` and `heading`. | `CLAUDE.md` (debug script undo groups) |

## Questions

None about the spec from this review. DQ-1 (`status.md`) is still the
designer's. It is real, not a measuring artefact: with the measured sizes the
one-line row needs 276.5 pt, and the default column with overlay scrollers has
276 pt (`PresetsBarGeometry.arrangement` uses a 0.001 pt tolerance). So at the
default width the row now wraps, where before this branch it fit on one line.

## The engineer's departures from design

- **One `Layout` (`PresetsBarLayout`) instead of `ViewThatFits`.** Accepted,
  and better than the design's letter. `ViewThatFits` builds three view
  trees, and in variant 2 the switch comes before Manage… in view order,
  which breaks design §8 (the switch after Manage… in every variant). The
  `Layout` keeps one tree in one order and places it by
  `PresetsBarGeometry`, a pure rule in PhotoCore. Its tests cover no
  overlap at every half point from 60 to 420 pt, right alignment, the
  wrapping order, centring on a line, and never squeezing below the needed
  width. Subviews are measured with `.unspecified`, which gives the push
  buttons' and the `.fixedSize()` switch's intrinsic sizes. An ideal-size
  query (nil width) gets the one-line arrangement, and a narrower width than
  any arrangement needs overflows, as the old variant 2 did.
- **`PresetListRow`, `PresetListRowButton` and `PresetListMetrics` instead
  of `PresetRow`.** Accepted. `PresetRow` is already a (file-private) view in
  `PresetManagerSheet.swift:140`, so a second one would compile but would be
  hard to read.
- **The applied mark reads `editor.item?.editStackHash`.** Accepted;
  without it the design's rule is wrong. `savedAdjustments` (`committed`) is
  `@ObservationIgnored`, so the list never redrew its mark. The thumbnails
  only redrew because their render key read `focusedItem`. I traced the
  three paths that change `committed`, and in each one the hash changes no
  earlier than `committed` does:
  - The editor's `apply` sets `committed` at once and the hash in
    `showSaved`, after the write.
  - Batch writes (`showEditStacks`) call `setEditStackHash` and then
    `catalogChanged` in the same main-actor turn, so SwiftUI's update reads
    the final `committed`.
  - `catalogChanged` sets both together.

  A saved change that leaves the render hash as it is cannot come from the
  UI: editing a group that is turned off turns it back on
  (`showsTurnedOff`), which changes the hash. The mark still never reads
  live values, so a drag redraws nothing.

## Checked and fine

- R8 / AC7: `PresetGrid`'s `.task(id:)` is the only caller of
  `PresetPreviewModel.render`. The list view builds no `PresetGrid`, and
  switching away cancels a running task, which `render` checks between
  frames. `PresetPreviewModel` changed only by two `@ObservationIgnored`
  debug counters. `render`, `hover` and the 120 ms hold are unchanged.
- R6 / R7: list rows call the same `previews.hover(preset, isInside:)` as
  tiles. The rule that hover works only in the loupe sits in `hover`. Rows
  are flush (`spacing: 0`), so the 120 ms hold covers moving from row to row.
  The `HoverButton` refactor into `enter`, `leave` and `simulateHover` is
  behavior-preserving: `leave` keeps the old `guard isHovered`, and
  `viewWillMove(toWindow: nil)` still ends a hover when a collection
  collapses or the view switches.
- R5: click, context menu and tooltip come from one place for both views
  (`presetContextMenu`, `PresetItemRules.help`). Applying goes through the
  unchanged `applyAdjustmentPreset`, so undo, `persist` and History are as
  before.
- R3 / R12: `PresetsViewChoice` parses defensively. Its key
  `adjust.presetsView` can't collide with `adjust.presets.<collection>` and
  contains no product name. `LibraryModel.presetsView` writes the key on
  change. No catalog, stack, render or golden change.
- R1 / R11: the `AppKitSegmented` symbols path (`.selectOne`, two 28 pt
  segments, image descriptions as VoiceOver names, per-segment tooltips) and
  the text path are as before. Rows are `NSButton`s named for the preset. The
  applied value uses the existing "Applied to this photo" string. A press
  leaves no state (`setNextState` is empty).
- Drawing: the fills, label color and accent color are resolved when the
  row draws. The focus ring is shaped to the row. `tertiarySystemFill` and
  `secondarySystemFill` exist on macOS 14 and later, so they are safe at the
  macOS 15 minimum.
- Concurrency: every new type is main-actor UI or a pure value type. No
  decoding, file I/O or database work on the main actor was added.
- Localization: five new catalog keys with comments, and one comment
  extended. `LocalizationTests` and `BrandingTests` pass.
- Debug script: `preset view` and `preset heading` are correctly left out of
  undo groups. `preset row … press` runs grouped and waits on
  `waitForBatchWork` like the other apply commands.
- Tests: `PresetsViewChoiceTests` and `PresetsBarGeometryTests` use Swift
  Testing, are deterministic and have no sleeps. The rest of the ACs are UI
  checks the debug script makes (no test target imports PhotoApp), which QA
  repeats.
- Dependencies, clean room and the security surface: nothing new. No
  package, no parser, no subprocess, no file writes beyond `UserDefaults`,
  no network.

## Follow-up

(After the engineer's fixes.)
