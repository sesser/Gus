# Editor follow edit drop and reload stale hash: implementation status

Owner: swift-macos-engineer. One bug fix for two roadmap bugs (no `prd.md`
or `design.md`, owner's ruling): `editor-follow-edit-drop` and
`reload-items-stale-hash` (`docs/roadmap.md`, Next). Branch
`bug/editor-follow-edit-drop`, cut from `develop` at `14dc0c1`.

**Status: Done.** Code review and QA passed (`code-review.md`, `qa.md`).

States: Not started · In progress · Done · Blocked · Deferred.

## The bugs

1. **editor-follow-edit-drop** (data loss). Leave a photo in the loupe and
   come back to it before the last commit's write lands, then change
   something. The editor loaded the stack from before that commit, and the
   new commit writes those older values back, dropping the earlier edit.
2. **reload-items-stale-hash** (display only). A library reload that read
   the row before an edit's write can apply after it and put the old render
   hash back, so a grid cell shows the previous look or stays blank until the
   next reload.

## Root cause

The product manager's diagnosis is right for both: each read the catalog
outside the model's write chain (`LibraryModel.persist`). For bug 2 it is
only half the cause. Line numbers are those at `14dc0c1`.

- **Bug 1.** `AdjustmentEditor.follow` started `loadTask`, which read
  `catalog.version(id:)` at once (`AdjustmentEditor.swift:247`) and set
  `adjustments` and `committed` from it (`:261-262`). A commit made before
  leaving the photo sets `committed` synchronously and queues its write on
  the chain (`apply`, `:557`). Leaving resets `committed`
  (`finishSession`). Coming back before that write lands reads the older
  row. The next `commit` then saves `older + change`, with undo pointing at
  `older`. Waiting for pending writes before reading fixes this.
- **Bug 2.** `reloadItems` read `libraryItems` in its own task
  (`LibraryModel.swift:696`) and applied the result whenever it arrived
  (`:698`). Waiting for pending writes before reading would **not** be
  enough here. The race code review described is a write queued *while the
  read is in flight*: the read returns the old row, the write lands and
  `showSaved` publishes the new hash, then `apply(items)` puts the old hash
  back. Writes queued before the reload started are not the problem.
- **Same window, wider than the roadmap row, and not display only.**
  Culling (`applyCulling`, `LibraryModel.swift:1084`) changes `items` before
  it queues its write. A reload whose read was already in flight then put
  the old rating, flag or label back on screen. That also reached the
  catalog. `perform` builds all three values from the row on screen
  (`CullingValues(item)`, `:1035`), and `applyCulling` saves rating, flag and
  label together (`setCulling`, `:1105`). So the next culling key after a
  stale reload saved the stale values of the other two. QA reproduced it on
  `develop` (`qa.md` Q1, S4): after `U` cleared a reject, the catalog ended
  with the flag stored as rejected. On the branch every round showed the
  right values and the catalog ended right. The same fix covers it (test
  below). (An earlier version of this file said the catalog stayed right;
  that was wrong, corrected after QA's Q1.)

So the rule has two halves. A read whose result is applied must (1) run only
after every write queued before it has landed, and (2) be applied only if no
write was queued while it read. Otherwise it reads again. The tests show
each half is needed: with only (1), the two reload tests and the culling
test fail (below).

## Fix

- **PhotoCore: `WriteChain`** (`Sources/PhotoCore/Support/WriteChain.swift`,
  `@MainActor`). This is the chain `persist` ran, moved here so it can be
  tested, per stale-preview-after-save `qa.md` O2:
  - `enqueue(_:)` runs work after every earlier write and counts it
    (`queuedCount`).
  - `afterPendingWrites(_:)` is unchanged in meaning: it waits for the writes
    queued so far, and later writes do not wait for it.
  - `read(_:apply:)` is the rule. It waits until no write is pending
    (`settled()`, which also waits for writes queued while it waits), takes
    the count, fetches, and calls `apply` only if the count is unchanged.
    Otherwise it fetches again. `apply` runs synchronously inside `read`, so
    no await separates the check from the use.
  - It throws `CancellationError` when the calling task is cancelled, and
    passes on what `fetch` throws. `apply` is not called in either case.
- **App, thin users** (`Sources/PhotoApp/Model/LibraryModel.swift`). The
  model owns `let writes = WriteChain()`. `persist` keeps its error
  reporting and `scheduleSidecarSync` and enqueues them on the chain.
  `afterPendingWrites` forwards to the chain. `reloadItems` reads through
  `writes.read`. The old `writeChain` task property is gone.
- **App, editor** (`Sources/PhotoApp/Model/AdjustmentEditor.swift`, `follow`).
  The load reads the stack through `writes.read`, and its `apply` sets
  `adjustments`, `committed`, the session and `state = .ready` in the same
  main-actor turn as the check. The RAW header, camera frame and cache
  checks do not depend on the stack, so they now run before the read rather
  than after it. An unreadable stack still sets `.unreadable`, and a
  cancelled load (another photo, or the loupe closed) still does nothing.
- Undo is unaffected: undo steps still go through `persist`, in order.

### Cases checked

- **Leave and return, save in flight (bug 1).** The read waits for the
  save. Its `showSaved` runs while the editor is `.loading`, so it updates
  `item`'s hash. With no frame, `seedPreviewIfRendered` does nothing.
- **Undo or a paste on the photo while it loads.** Either write bumps the
  count, so the load reads again and gets the new stack. Before this fix, a
  paste that landed during the load was ignored (`catalogChanged` requires
  `.ready`), and the next commit wrote over it. That is the same data loss
  by another route, and it is now closed too.
- **Commit during a reload's read (bug 2).** The reload reads again after
  `showSaved`.
- **Culling during a reload's read.** The reload reads again. The new rows
  have the new rating, which the screen already shows, so the next culling
  key saves from the right row (on `develop` it saved the stale one; QA Q1).
- **No self-wait.** Nothing on the chain awaits a read: no `persist` body
  awaits `reloadTask` or `loadTask` (checked with grep).
- **Retries.** A read retries only when a write was queued during its fetch.
  Writes are person-paced, and every batch is a single `persist`
  (`changeAdjustments`, batch undo, Auto Exposure's final write), so a
  stream of writes long enough to keep a reload retrying does not occur.
  Each retry first waits for the chain, so it does not spin.
- **Rendering is unchanged.** No pipeline version bump, no golden touched,
  `UPDATE_GOLDENS` never run.

## Build and test

- **Baseline at `14dc0c1`:** `swift build` clean. `swift test`: **554 tests
  in 97 suites passed**, 1 known issue (`LiveSessionTests`, pre-existing
  `withKnownIssue`). One pre-existing warning: `SmartAlbumTests.swift:165`
  (unused result).
- **Latest (`7976b49` plus this file):** `swift build` clean, no new
  warnings. `swift test`: **562 tests in 98 suites passed**, 1 known issue
  (the same one). Large-render and camera-RAW suites were skipped as usual
  (environment variables not set).
- No linter or formatter is configured in the repository.

### The tests

`Tests/PhotoCoreTests/WriteChainTests.swift`, suite "Reads ordered with the
write chain". Swift Testing, `@MainActor`, no sleeps. A `Latch` (a
continuation-based one-shot gate) holds a write or a fetch at a known
point. The tests rely only on actor non-preemption: a task runs on the main
actor until it suspends. So when a test resumes from a latch, the task that
opened it has either finished its read or is waiting for the chain. With
the rule in place each test passes in either case. Only a read that ignores
the chain can fail.

| Test | Bug | What it does |
| --- | --- | --- |
| Writes run in the order they were queued | (existing behavior) | first write held; order 1, 2, 3 |
| A read started while a save is queued sees that save | 1 | save queued behind a held write; the load must see it, and the next save keeps both |
| Coming back to a photo before its save lands keeps that edit | 1 | same, on an in-memory `Catalog`: +1 EV saved behind a held write, load, then contrast 20; the stored stack has both |
| A reload that read before an edit's save lands reads again | 2 | fetch held after reading "old"; the edit's write and publish land; the reload must show "new" and have fetched twice |
| A reload that read the row before an edit's save does not show the old hash | 2 | same, with `libraryItems` on an in-memory `Catalog` and the real render hashes |
| A change shown before its write survives a read already in flight | culling | rating shown at once, then written, while a read is held |
| A cancelled read applies nothing | — | cancel while the fetch is held |
| A failed read applies nothing and passes the error on | — | `fetch` throws |

### Proof they fail without the fix

The new tests were run with `read` made to behave like the old direct reads
(first line of `read`: `if true { let value = try await fetch(); try
apply(value); return value }`). Result: **6 of 8 tests failed, 10 issues**:

```
A read started while a save is queued sees that save:     loaded → []          store.saved → ["contrast"]
Coming back to a photo before its save lands keeps it:    next.exposure.ev → 0.0   saved.exposure.ev → 0.0
A reload that read before an edit's save lands:           store.shownHash → "old"  store.fetches → 1
A reload that read the row before an edit's save:         store.shownHash → "6c76a50e5dc3f0cd…" (identity)
                                                          editStack.renderHash → "822f9568f0de6aea…" (+1.5 EV)
A change shown before its write survives a read:          store.shownRating → 0
A cancelled read applies nothing:                         no error thrown; store.shownHash → "new"
```

The two passing tests (write order, failed read) do not depend on the rule.
The disabled run was repeated 10 more times: it failed with the same 10
issues every time. That includes the catalog-backed bug 1 test, whose
failure depends on GRDB's queue order once the rule is off. The in-memory
test for bug 1 is the deterministic one.

Second check, with only half the rule: waiting for pending writes, but no
re-check of the count (`guard mark == queuedCount` replaced by `_ = mark`).
**3 tests failed, 4 issues:** both reload tests and the culling test. Both
bug 1 tests passed. This is the evidence for the correction under Root
cause.

The file was then restored from a saved copy (`cmp` identical). With the
fix: 8 of 8 passed, in 11 consecutive runs of the suite.

## Acceptance (from the owner's rulings and the task)

| # | Criterion | How checked | State |
| --- | --- | --- | --- |
| 1 | Root cause confirmed or corrected from the code | Above; the correction for bug 2 is shown by the half-rule run | Done |
| 2 | Bug 1: a test that fails without the fix and passes with it | `readWaitsForQueuedWrites`, `returningBeforeTheSaveLandsKeepsTheEdit` | Done |
| 3 | Bug 2: a test that fails without the fix and passes with it | `readOvertakenByAWriteReadsAgain`, `reloadDoesNotPutTheOldHashBack` | Done |
| 4 | Ordering rule in PhotoCore and tested there; app code a thin user | `WriteChain`; `persist`, `afterPendingWrites`, `reloadItems` and `follow` call it | Done |
| 5 | Undo steps stay on the ordered write chain | `persist` enqueues on `WriteChain`; order test | Done |
| 6 | No change to how existing stacks render | No renderer, pipeline version or golden touched; all goldens pass | Done |
| 7 | `swift build` and `swift test` green after each step | Each commit built and passed the full suite (562 tests, 1 known issue) | Done |
| 8 | User-visible strings through the catalog | None added | Done |
| 9 | `USER_GUIDE.md` updated with behavior | No change: it already says changes are saved at once; this restores that | Done |

## Debug-script check (bundled app)

The bundle was built with `Scripts/build-app.sh` and copied to the scratch
folder. The copy's `CFBundleIdentifier` was set to
`local.scratch.editfollowcheck` and the copy re-signed ad hoc. The library
was a scratch one from `photobench generate` plus `photobench import`.
Every launch passed `--library-root`. Script:

```
wait 2; focus 0; loupe; wait 3; adjust exposure 1.5; wait 1; focus 1; wait 2;
focus 0; wait 3; adjust contrast 20; wait 2; print adjustments; focus 1;
focus 0; adjust highlights -30; wait 3; print adjustments; quit
```

Result:
- The editor showed `ready` with exposure 1.5 and contrast 20, then with
  exposure 1.5, contrast 20 and highlights -30.
- After quit, `photocli query images` showed `IMG_00001.JPG` stored with all
  three edits, and a `renderHash` (`95dca2c59b2b…`) equal to the editor's
  last hash.

This is a smoke check of normal editing through the new read path. It does
not reproduce the race: the window is one write's latency, and the script's
`focus` reaches `follow` only through the loupe view's next update. The
tests above cover the race. The scratch bundle and library were deleted.

## For QA (in the bundled app)

Not run by engineering beyond the smoke check above. Use a copy with its own
bundle identifier and a scratch library, with `--library-root` on every
launch.

1. In the loupe, commit an edit and press → then ← at once. Commit another
   change. Both edits must remain, after relaunch too. Repeat with Paste
   Adjustments made while the photo loads.
2. In the grid, commit edits on a photo while a reload runs (for example,
   change the sidebar source or the search field at the same moment). The
   cell must end on the new look.
3. Rate photos quickly while changing the filter or source. No rating may
   revert on screen.

## Notes (not fixed here: the same family, outside these two bugs)

These read a stack outside the chain and could adopt `writes.read` in one
line each. They are left alone to keep this change to its two bugs.

- `LibraryModel.copyAdjustments` (grid path, `AdjustmentActions.swift:18`).
  Copy right after a paste or preset whose write has not landed copies the
  older values. Pasting them elsewhere is then wrong, but nothing is lost on
  the source photo.
- `focusedAdjustments` (Save as Preset from the grid,
  `PresetActions.swift:52`). Same window: the preset can get the older
  values.
- `AdjustmentEditor.loadOfflineMachineLearning` (`AdjustmentEditor.swift`,
  offline photos only) and `PresetPreviewModel` (`PresetPreviewModel.swift:69`).
  Display only: a badge, and the preset preview's base.
- Batch Auto Exposure measures from `catalog.editStacks` read outside the
  chain (`BatchActions.swift:93`). Its write applies only the measured EV
  onto the catalog's current values, so nothing is dropped. The measurement
  may use the older values for the other modules.

## Code review

`code-review.md`: ready to merge, no findings.

## QA (`qa.md`, 2026-11-06: passes)

`qa.md` is the record. QA tested the branch at `975cf49` against `develop`
at `14dc0c1`. On `develop`, all three routes (edit drop, stale hash,
culling) reproduce with scripts that widen the race. None of them
reproduces on the branch.

| # | Finding | Response |
| --- | --- | --- |
| Q1 | The culling route was not display only on `develop`: the next culling key saved the stale values (flag stored as rejected after `U` cleared it) | Record corrected under Root cause and Cases checked. No code change: the branch already fixes this route. |
| O1 | Observation. `read` waits for every queued write by design. Behind a batch undo of 29,894 photos, the Adjust tab showed `loading` for about 3 s; `develop` showed ready at once, with the wrong values. A reload waits the same way. Batches of normal size take milliseconds | Expected cost of the rule. The alternative is starting from values that may be overwritten. No change was asked for. QA's P1 (pending the owner, optional) lets the owner judge it with real files. |
| O2 | Nothing automated fails if `follow` or `reloadItems` stops calling `writes.read` (no PhotoApp test target) | Already tracked under `qa-test-gaps`. QA's scripts S2, S3b, S3c, S4 and S5b reproduce on `develop` and are the regression check for the app side. |

## Open questions

None. No design questions; no requirements issues.

## README

No change: requirements, build commands and repository layout are unchanged.
