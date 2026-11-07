# Editor follow edit drop and reload stale hash: code review

Owner: code-reviewer. Date: 2026-11-06. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/editor-follow-edit-drop`, 14dc0c1..975cf49 (04bf094 `WriteChain`,
feda2c0 `reloadItems`, 7976b49 `AdjustmentEditor.follow`, 975cf49 status).
Build and tests: `swift build` clean; `swift test` 562 tests in 98 suites
passed, 1 known issue (the pre-existing `LiveSessionTests` `withKnownIssue`).
`swift test --filter WriteChainTests` passed 10 runs out of 10.

Spec: no `prd.md` or `design.md` (bug fix, owner's ruling); roadmap rows
`editor-follow-edit-drop` and `reload-items-stale-hash`; `status.md` in this
folder.

## Verdict

Ready to merge. One change fixes both bugs. The ordering rule lives in
PhotoCore (`WriteChain.read`) and is tested there, and the app calls it in
one place each. I reproduced the engineer's fail-before evidence in a scratch
copy, with the same counts. Undo ordering is the same as before. No Blocker,
no Should fix, no Nit.

## Findings

None.

## Questions

- **Q1 (product-manager): the four reads left outside the chain.** They are
  listed only in `status.md` "Notes", which is not where follow-up work is
  tracked. None of them loses an edit on the photo it reads, so none belongs
  in this change (see Checked and fine). The worst is `copyAdjustments` from
  the grid (`AdjustmentActions.swift:18`). Paste onto X, then Copy
  Adjustments from X before the paste lands: the copy gets X's values from
  before the paste, and the next paste silently gives other photos the wrong
  values. Suggest one roadmap row (for example `reads-beside-write-chain`) for
  `copyAdjustments`, `focusedAdjustments` (`PresetActions.swift:52`),
  `PresetPreviewModel.baseAdjustments` (`PresetPreviewModel.swift:69`),
  `loadOfflineMachineLearning` and batch Auto Exposure's measurement
  (`BatchActions.swift:93`). Each is a one-line move onto `writes.read`.

## Checked and fine

- **Fail-before evidence is real.** In a scratch copy (outside the repo) I
  made `read` skip the rule (`if true { let value = try await fetch(); try
  apply(value); return value }`): 6 of 8 tests failed with 10 issues, the same
  lines `status.md` lists. With only the wait half (`guard mark ==
  queuedCount` replaced by `_ = mark`), 3 tests failed with 4 issues: both
  reload tests and the culling test. So each half of the rule is pinned by a
  test.
- **Tests are deterministic, no sleeps.** I traced each test. The `Latch`
  gates plus main-actor non-preemption fix the order: the fetch is held
  after reading, and the write is queued and lands while it is held. The
  in-memory `Store` tests are the deterministic fail-before proofs for both
  bugs. The catalog-backed bug 1 test fails without the fix only because the
  GRDB read starts before the held write is released. `status.md` says so,
  and it failed in my run. With the fix, every test passes regardless of
  scheduling.
- **No livelock, no spin.** `settled()` waits on a different task in each
  iteration, and a new iteration starts only if a write was queued during the
  previous wait. It returns as soon as the chain is idle. `read` retries only
  when a write was queued during its fetch, and every retry first waits for
  the chain. Every `persist` call is a person's action or its undo (I checked
  every call site; batches are one `persist` each), so retries stop when the
  person stops. One pattern can keep a reload retrying: holding a culling key
  in the grid writes on every key repeat (`perform` has no `isARepeat` or
  no-op check; that is pre-existing and outside this diff). If a reload is
  in flight then and `libraryItems` takes longer than the repeat interval,
  the reload completes when the key is released. That is a delay, not a
  livelock. The editor's single-row fetch fits in the gaps between repeats.
- **No self-wait.** No write body awaits `reloadTask`, `loadTask` or a
  `read`. Observers that `reloadItems`' `apply` notifies may queue writes
  (`follow` → `endCrop(save: true)`). Those writes come after the check and do
  not affect the value already applied.
- **Cancellation.** `read` checks for cancellation after the fetch, then runs
  the count check and `apply` synchronously. A follow from A to B and back to
  A cannot apply the first A load, even though `item?.versionID` matches
  again. A load cancelled while it waits in `settled()` still calls `fetch`
  once, and GRDB throws `CancellationError` before reading
  (`DatabasePool.swift:816`). `follow` and `reloadItems` both treat that as a
  quiet return.
- **`follow`'s reordering.** The RAW header, camera frame and cache checks
  use only `url` and `previewKey` (taken at `follow` time, as before), not
  the stack, so moving them before the read changes no result.
  `previewWasCached` still describes the rendition under the hash the photo
  arrived with, as before. An unreadable stack now shows `.unreadable` after
  the header reads rather than before, which only delays that state slightly.
  The reordering also closes a second gap in the old code. Before, the stack
  was read first and the header reads awaited afterwards; a paste or undo
  that landed in between was ignored (`catalogChanged` requires `.ready`) and
  then overwritten by the next commit. Now the fetch is the last await
  before `apply`. The check after the read (`state == .ready`) is true
  exactly when `apply` ran for this version (`state` is set only in
  `follow`), so the histogram render is still requested as before.
- **Undo while the photo loads.** `editor.apply` on the loading photo sets
  `committed` and `adjustments` and queues its write. The count changes, so
  the load reads again and gets the same values. `requestRender` without a
  session only records `pendingRender`.
- **Undo ordering.** `persist` → `WriteChain.enqueue` is the old chain: take
  the tail, start a main-actor task that awaits it, store the new task as the
  tail. Error reporting and `scheduleSidecarSync()` are unchanged inside the
  work. `afterPendingWrites` is unchanged in meaning and still not a write.
  The counter changes no order.
- **Batch paths.** `changeAdjustments` publishes hashes in `afterPendingWrites`
  (not on the chain). A reload that waited for the batch's write fetches rows
  that already have the new hash, whichever of the two resumes first.
- **Swift 6.** `WriteChain` is `@MainActor`, and its tasks inherit that.
  `fetch` and `apply` are non-escaping closures that run on the main actor,
  and `Value` never leaves it. No `@unchecked Sendable` or
  `nonisolated(unsafe)`. It builds with no new diagnostics.
- **Project rules touched.** No rendering change (no pipeline bump needed, no
  golden touched). No new strings, brand values, dependencies, migrations,
  parsers, subprocesses or network code. The new file is in
  `Sources/PhotoCore/Support/`.
- **Residual risk, already tracked.** No test fails if `follow` or
  `reloadItems` stops calling `writes.read`, because there is no app test
  target. That is the `qa-test-gaps` row. The owner's acceptance asks for the
  rule in PhotoCore with the app as a thin user, and the branch delivers
  that. `status.md` "For QA" lists the on-screen checks.

`/security-review` is not needed: the diff adds no parser, subprocess, file
writing outside the library or network code.

## Follow-up

Nothing to follow up: no findings.
