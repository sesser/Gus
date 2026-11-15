# Reads beside the write chain: code review

Owner: code-reviewer. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/squash-top-10`, e2f148d..cb0df4c (the #64 commit; branch head
8d87d90). Build and tests: `swift build` clean; full `swift test` at 8d87d90:
1030 tests in 152 suites passed, 1 known issue (`LiveSessionTests`, as on
`develop`).

## Verdict
Ready for QA. All five reads named in the issue, plus the sixth the engineer
found (`changeAdjustmentsMeasuringAlignment`), now read through
`WriteChain.read`, as PR #43 did for the others. I found nothing to fix.

## Findings
None.

## Questions
None.

## Checked and fine
- `WriteChain+SavedEdits.swift`: both helpers go through `read(_:apply:)` with
  an empty `apply`. The extension inherits the class's `@MainActor`
  isolation, so the value reaches the caller on the main actor with no
  suspension between the check and its use.
- No self-wait: none of the six call sites runs inside a `persist` or
  `afterPendingWrites` body. They run in `loadTask`, `batchAutoTask`, the
  preset section's task, and the copy and Save as Preset tasks, and no write
  awaits any of those. I grepped the callers of
  `changeAdjustmentsMeasuringAlignment` (paste, Apply Preset) and the
  debug script's `waitForBatchMeasuring` loop. The loop waits on
  `batchAutoTask`, which now waits on the chain, and the chain never waits on
  it.
- Error handling: Copy and Save as Preset still report an unreadable stack.
  The preview base and offline badge still fall back to the defaults. The two
  batches still stop on a failed read. Cancellation now does nothing, which
  is right for each (the old code fell back to the defaults).
- The re-read when a write is queued mid-read can't starve: writes are queued
  once per gesture or command, not continuously.
- Batch measurements read after pending saves and then write through
  `changeAdjustments`, which applies the measurement to the catalog's values
  at write time, so nothing a later write made is dropped.
- Tests (`SavedEditsReadTests`): `@MainActor`, an in-memory catalog, a gate
  instead of sleeps, so they are deterministic. 5 of 7 fail against the old
  direct reads; the two that pass pin behavior kept (unreadable stacks,
  cancellation). The app call sites have no test target (known gap O2,
  recorded in status).
- No rendering, migration, string or pipeline change.

## Follow-up
