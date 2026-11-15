Issue: #64

# Reads beside the write chain: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design). Branch
`bug/squash-top-10`, on top of `e2f148d` (the #166 fix).

**Status: Done.** Waiting for code review, then QA. No UI change, so no
design review.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (the worst case; the window is one catalog write,
longer when a large batch is queued ahead of it):

1. In the grid, copy adjustments from photo A (say +1.5 EV).
2. Select photo B and choose Paste Adjustments.
3. Before the paste's write lands, choose Copy Adjustments with B focused.
4. Select photo C and choose Paste Adjustments.

**Expected:** C gets B's values after the paste (+1.5 EV).
**Actual:** step 3 could copy B's values from before the paste, so C
silently got the wrong edits (here, none).

The same window affected four other reads:

- Save Adjustments as Preset… from the grid: the preset could hold the
  values from before the latest paste or preset.
- Auto Exposure on a selection in the grid: each photo was measured with
  older values of the other modules. Its write sets only the measured EV on
  the catalog's current values, so nothing was dropped.
- The Adjust tab's preset previews: their base could be the older values
  (display only).
- The offline machine learning badge: it could read the older stack
  (display only).

**Root cause.** The model's catalog writes run one after another on its
write chain (`WriteChain`, used through `LibraryModel.persist`). A batch
change such as a paste, a preset or Auto Exposure reaches the catalog only
when its write runs. These five reads went to the catalog straight away,
beside the chain, so a read made right after a change could get the row
from before it. Places, at `e2f148d`:

| Read | Where | Use |
| --- | --- | --- |
| `copyAdjustments` (grid path) | `AdjustmentActions.swift:18` | the clipboard for the next paste |
| `focusedAdjustments` (grid path) | `PresetActions.swift:64` | Save as Preset |
| batch `autoExposure` | `BatchActions.swift:96` | measurement |
| `PresetPreviewModel.baseAdjustments` (when the editor is not ready) | `PresetPreviewModel.swift:69` | preset previews |
| `AdjustmentEditor.loadOfflineMachineLearning` | `AdjustmentEditor.swift:1029` | offline badge |
| `changeAdjustmentsMeasuringAlignment` | `AdjustmentActions.swift:71` | a paste or preset that measures color alignment |

The sixth row is not in the issue. It was added after the issue was written
(chromatic aberration, PR #48), and it is the same read as batch Auto
Exposure: it measures each photo's alignment from the stack read before
pending saves, then applies the result to the current values. It is fixed
the same way here; see Scope.

PR #43 fixed two reads of this family (`AdjustmentEditor.follow`,
`LibraryModel.reloadItems`) with `WriteChain.read(_:apply:)`. That read runs
only once every write queued before it has landed, and reads again if a
write was queued while it read. These six reads now go through it too.

**Tests that fail without the fix.**
`Tests/PhotoCoreTests/SavedEditsReadTests.swift`, suite "Saved edits read
after pending saves". See the table under Tests.

## Fix

- **PhotoCore** (`Sources/PhotoCore/Support/WriteChain+SavedEdits.swift`,
  new): two reads on `WriteChain` that go through `read(_:apply:)`.
  - `savedAdjustments(ofVersion:in:)` returns a version's saved
    `Adjustments`, or the defaults when the version is gone. It throws
    `CancellationError` when the task is cancelled and the catalog's error
    when the stack can't be read.
  - `savedEditStacks(forVersions:in:)` returns `StoredEditStacks`, with the
    unreadable stacks listed apart, as `Catalog.editStacks` does.

  They live in PhotoCore so they can be tested. The app has no test target.
- **App, one call each.** Each call site uses one of the two reads above:
  - `copyAdjustments`, `focusedAdjustments`, `PresetPreviewModel.baseAdjustments`
    and `loadOfflineMachineLearning` use `writes.savedAdjustments`. The last
    one now takes the chain as a parameter.
  - batch `autoExposure` and `changeAdjustmentsMeasuringAlignment` use
    `writes.savedEditStacks`.
- **Error handling is unchanged**, apart from cancellation:
  - Copy and Save as Preset still report an unreadable stack in Activity.
  - The preset previews and the offline badge still fall back to the
    defaults for an unreadable stack.
  - The two batches still stop when the read fails.
  - A cancelled read now does nothing in all four places that handle it.
    Before, the preview base and the offline badge fell back to the defaults
    and relied on a later `isCancelled` check.
- **Not changed:**
  - When the editor has the focused photo loaded (`state == .ready`), Copy,
    Save as Preset and the preview base still take the editor's values. See
    Follow-ups: those values can also lag a batch change on the open photo.
  - `follow` keeps its own `writes.read` call, because its `apply` sets the
    editor's state.

### Cases checked

- **No self-wait.** None of these reads runs on the chain, and no `persist`
  or `afterPendingWrites` body awaits the tasks they run in (`loadTask`,
  `batchAutoTask`, the preset section's `.task`, the copy and preset tasks).
  Checked with grep.
- **Re-read.** A read whose fetch is overtaken by a newly queued write reads
  again. For the batch measurements this means the values used are closer to
  the ones the final write applies to. For Copy and Save as Preset it means
  a change made within one read's latency after the command is included.
  That is acceptable for a person-paced command, and it matches the PR #43
  rule.
- **Waiting.** Behind a very large batch (editor-follow-edit-drop `qa.md`
  O1: about 3 s for about 30,000 photos), Copy, Save as Preset and the
  preview base wait for the batch before reading. The batch measurements
  show their progress at 0 while they wait. Ordinary batches take
  milliseconds.
- **No rendering change.** No renderer, pipeline version, golden or migration
  was touched, and `UPDATE_GOLDENS` was never run.

## Build and test

- **Baseline at `e2f148d`:** `swift build` clean. `swift test` passed
  **1001 tests in 145 suites**, with 1 known issue (`LiveSessionTests`,
  pre-existing `withKnownIssue`). One pre-existing warning:
  `SmartAlbumTests.swift:165` (unused result).
- **Latest (this change):** `swift build` clean, no new warnings.
  `swift test` passed **1008 tests in 146 suites**, with the same 1 known
  issue. The large-render and camera-RAW suites were skipped as usual (their
  environment variables were not set).
- `Scripts/build-app.sh` builds the bundle.
- No linter or formatter is configured in the repository.

### Tests

`Tests/PhotoCoreTests/SavedEditsReadTests.swift`: Swift Testing,
`@MainActor`, in-memory `Catalog` (`CatalogFixture`), no sleeps.

Each race test works the same way:

1. It queues a held write.
2. Behind the held write, it queues a change through
   `Catalog.changeEditStacks`, the paste and preset write.
3. It starts the read and opens the gate.

A read beside the chain is sent to the catalog before the held write is
released, so it can only see the row from before the change. A read
through the chain waits for the change.

| Test | Call site | What it checks |
| --- | --- | --- |
| Copy right after a paste copies the pasted values, and the next paste gives them on | `copyAdjustments` | +1.5 EV and contrast 20 pasted onto A, then copied from A before the write lands, then pasted onto C. C must store both. |
| Save as Preset right after a change saves the changed values | `focusedAdjustments` | −0.7 EV pending. The preset saved from the read must hold −0.7 and the Light group. |
| A batch measurement reads every photo's stack after a pending change | batch `autoExposure`, `changeAdjustmentsMeasuringAlignment` | Highlights −40 pending on three photos. All three stacks read must have it. |
| The offline badge reads machine learning from a stack whose save is pending | `loadOfflineMachineLearning`, `PresetPreviewModel.baseAdjustments` | machine learning noise reduction turned on, pending. The read must see it. |
| A read waits for a change queued while it waits, and reads it | all | a change queued after the read started, while it waits. The read must see it. |
| Stacks this build can't read are reported, not read as the defaults | all | a newer build's stack: `savedAdjustments` throws, `savedEditStacks` lists it as unreadable |
| A cancelled read throws and returns nothing | preview base, offline badge, batches | cancel while waiting: `CancellationError` |

**Proof that they fail without the fix.** The tests were written first,
against the two helpers written as the app read before the fix (straight to
the catalog, no chain). Result: **5 of 7 failed, with 11 issues**, the same
in 10 of 10 runs:

```
Copy right after a paste …:           copied.exposure.ev == 1.5, copied.tone.contrast == 20,
                                      result.exposure.ev == 1.5, result.tone.contrast == 20 (C got nothing)
Save as Preset right after a change:  saved.adjustments.exposure.ev == -0.7, saved.groups.contains(.light)
A batch measurement reads …:          tone.highlights == -40 (3 photos)
The offline badge reads …:            values.asksForMachineLearning
A read waits for a change queued …:   exposure.ev == 2
```

The two that pass without the fix check behavior the fix keeps: unreadable
stacks, and cancellation. With the fix, 7 of 7 pass. Together with
`WriteChainTests`, 15 of 15 pass, in 10 of 10 runs.

**What the tests do not cover.** Nothing automated fails if an app call
site stops using these reads, because there is no PhotoApp test target.
This gap is already known (editor-follow-edit-drop `qa.md` O2,
`qa-test-gaps`).

## Debug-script check (bundled app)

Setup:

- The bundle was built with `Scripts/build-app.sh` and copied to the
  scratchpad.
- The copy's `CFBundleIdentifier` was set to
  `local.scratch.readsbesidechain` and the copy was re-signed ad hoc.
- The library was a scratch one from `photobench generate --jpeg 4` plus
  `photobench import`.
- The launch passed `--library-root`.

Script:

```
wait 3; focus 0; loupe; wait 3; adjust exposure 1.5; wait 1; grid; wait 1;
focus 0; copyadjust; focus 1; pasteadjust; copyadjust; focus 2; pasteadjust;
wait 1; focus 2; preset save Smoke; wait 1; quit
```

The second `copyadjust` comes straight after `pasteadjust`, with no wait, so
it takes the grid path while the paste's write may still be queued.

Result:

- `photocli query images`: `IMG_00001.JPG`, `IMG_00002.JPG` and
  `IMG_00003.JPG` were stored with `exposure ev 1.5`.
- The `adjustmentPreset` table held `Smoke` with group `light` and
  `ev 1.5`.

This is a smoke check of the new paths. It was not run against `develop`,
so it does not show that the race reproduces there. The unit tests above
are the proof of the fix. The scratch bundle and library were deleted.

The grid's batch Auto Exposure has no debug-script command; `adjust auto`
runs the loupe's editor. It was not run in the app. Its read is covered by
the batch-measurement test.

## For QA

Use a copy of the bundle with its own bundle identifier and a scratch
library, and pass `--library-root` on every launch.

1. The repro above, by script (the sequence in the debug-script check), and
   if possible with the window widened: queue a large batch first, for
   example Paste onto a few thousand photos, then paste onto B, copy from B
   and paste onto C. C must end up with B's post-paste values.
2. Save as Preset from the grid right after a paste: the preset must hold
   the pasted values.
3. Auto Exposure in the grid right after a paste onto the same photos (with
   a real menu or key): it completes, and the other modules keep the pasted
   values.

## USER_GUIDE

No change. The guide already describes Copy and Paste Adjustments, presets
and Auto Exposure acting on the photo's current values. This fix restores
that behavior.

## Scope

- Fixed: the issue's five reads, plus `changeAdjustmentsMeasuringAlignment`,
  the same read added later. A main-session or review ruling can take the
  sixth out if it is unwanted. It is one line and one test row.
- Not fixed (proposed below as follow-ups): the editor's in-memory values in
  the loupe, and Paste right after Copy.

## Follow-ups (proposed issues; not fixed here)

1. **The loupe's values lag a batch change on the open photo** (bug).
   Found by reading the code; not reproduced.
   - In the loupe, a paste, preset or batch undo on the photo on screen
     reaches the editor only when its write lands
     (`showEditStacks` → `catalogChanged`).
   - Until then, Copy, Save as Preset and the preset previews in the loupe
     take the editor's values from before the change.
   - A slider change committed in that window saves the editor's whole
     stack after the paste's write, so it writes over the paste.
   - The window is one write. It is longer behind a large batch.
2. **Paste right after Copy can use the previous clipboard** (bug).
   - Copy from the grid sets the clipboard only when its read returns.
   - A Paste before that pastes the previous values, or nothing.
   - The read now also waits for pending saves, so the window is longer
     behind a large batch.
   - Paste could wait for a pending copy.

## Open questions

None. No design questions, no requirements issues.

## README

No change: requirements, build commands and repository layout are unchanged.
