# Export double start: code review

Owner: code-reviewer. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/squash-top-10`, 05873e0..493b6a5 (the #163 commit; branch head
8d87d90). Build and tests: `swift build` clean; full `swift test` at 8d87d90:
1030 tests in 152 suites passed, 1 known issue (`LiveSessionTests`, as on
`develop`).

## Verdict
Ready for QA. The gate is taken before the first await, the request runs in a
task the model keeps, and its answer is shown only while it is still the
pending request. Closing or opening the sheet cancels it. Both cases in the Bug
section are closed, and I found nothing to fix.

## Findings
None.

## Questions
None.

## Checked and fine
- `requestExport`: `requests.begin(isExporting:)` runs synchronously on the
  main actor before any await, so a second Return (or a second click) is
  refused while the first request reads. It is still refused after the first
  starts, because `isExporting` is then true.
- `check`: `requests.end(request)` comes before any state is set. A request
  that was cancelled, or overtaken by a newer one, returns false without
  clearing `requestTask` (which may belong to the newer request). Only the
  pending request clears it, and then shows its issue, its alert or its
  export.
- `cancelRequest()` runs from `showsExportSheet`'s `didSet` on every close:
  Cancel, Esc through the `.sheet(isPresented:)` binding, `resolve`, a
  script. It also runs from `begin()` when a sheet opens. Cancelling the task
  stops `MasterFiles.hash` per chunk. `holdsContent` then says "master",
  which overcounts, and `ExportJob.clashes` throws at its
  `Task.checkCancellation()`, so that overcount never becomes an answer. A
  cancelled `items` read lands in `.issue`, and `end` drops it.
- Once a request has ended (export started, or alert shown), closing the sheet
  changes nothing: an export keeps running, and the alert's choice goes
  through `resolveConflict`. The alert is modal over the sheet, so Export
  can't be pressed behind it.
- `ExportJob.clashes` split: the async wrapper is unchanged in behavior. The
  static count adds `holdsMasterContent` and `fileExists`, seams that only
  tests use, defaulting to the real checks.
- Tests: the gate's rules are pure and deterministic.
  `aReadCutShortByCancelThrowsInsteadOfCounting` cancels inside the content
  read and fails if the `checkCancellation` line is removed (the test the
  issue asked for). The app wiring was checked by debug script against an
  old-behavior build (S1–S5 in status).
- The debug-script additions (`export run twice`, `export run cancel`) change
  no photos, so they need no undo group. No new UI string, no migration, no
  rendering change.

## Follow-up
