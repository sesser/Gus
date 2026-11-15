Issue: #163

# Export double start: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or `design.md`,
`docs/WORKFLOW.md` "Bug fixes") for GitHub issue #163, a follow-up from #160
(code review C4 and C7). Branch `bug/squash-top-10`, on top of `05873e0`.

**Status: Done.** Next: code-reviewer, then qa-tester. No design review: the
sheet, its buttons and its alert look and read as before.

States: Not started · In progress · Done · Blocked · Deferred.

## Bug

**Steps to reproduce** (at `05873e0`).
1. Select photos, File ▸ Export…, and pick a destination folder.
2. Press Return twice quickly (or click Export twice) before the sheet closes.
   The second press lands while the first request is still reading the
   photos and counting the files in the way, which reads files since #160.

Second case:
1. Export into a folder that already holds files with the export's names, so
   the count has work to do.
2. Press Export, then Cancel (or Esc) before the existing-files alert shows.
3. Reopen the sheet on another selection.

**Expected.** One export starts however often Export is pressed. Cancel stops
the count: nothing is exported and no alert shows, on this sheet or a later
one.

**Actual.** Two export jobs start and plan the same names into one folder;
`ExportModel.task` holds only the second, so Stop reaches only that one, and
the loser's photos are reported as "could not be written". After Cancel the
count runs on: with no files in the way the cancelled request starts its
export anyway; with files in the way its alert can appear on the reopened
sheet, and Replace then exports the old request's photos.

**Root cause.** `requestExport` guarded only on `isExporting`, which becomes
true in `start`, after two awaits (`job.items`, `job.clashes`). Between the
guard and `start` nothing marked a request as under way, so a second call
passed the guard too. The count ran in the button's own unstructured `Task`,
which nothing kept, so Cancel (which only set `showsExportSheet = false`)
could not cancel it, and nothing tied the request's answer (alert or start)
to the sheet that asked.

**Fix.**
- `ExportRequestGate` (PhotoCore, `Export/ExportRequestGate.swift`): the rule.
  `begin(isExporting:)` gives a request only when none is pending and no
  export runs; `end(_:)` says whether that request is still the pending one
  (only then may it answer); `cancel()` drops it.
- `ExportModel.requestExport` takes the gate before its first await, runs the
  reads in a kept `Task` (`requestTask`), and shows its issue, alert or
  export only if `end` returns true. `cancelRequest()` cancels that task (so
  `ExportJob.clashes` stops reading and throws) and drops the request.
- `LibraryModel.showsExportSheet`'s `didSet` calls `cancelRequest()` whenever
  the sheet closes (Cancel, Esc, a script), and `ExportModel.begin()` calls it
  when a sheet opens. A request that already started its export, or put up
  its alert, has ended, so closing the sheet then changes nothing (an export
  keeps running; Stop is still the way to stop it).
- `ExportJob.clashes` split: the synchronous count and its
  `Task.checkCancellation()` are an internal static function, so a test can
  cancel the task inside the content read, exactly where Cancel lands.

**Tests that fail without the fix.**
- `ExportRequestGateTests` (`Tests/PhotoCoreTests/ExportRequestTests.swift`):
  a second request while one reads is refused; none while an export runs; a
  cancelled request never answers; an old request ending after a new one
  began neither answers nor frees the new one's place. (The rule did not
  exist before: the tests don't compile at `05873e0`.)
- `ExportClashesCancellationTests.aReadCutShortByCancelThrowsInsteadOfCounting`:
  the test the issue asks for. Checked by deleting the
  `Task.checkCancellation()` line: it then fails with "an error was expected
  but none was thrown and ExportClashes(existing: 1, masters: 1) was
  returned"; with the line it passes.
- The app wiring (PhotoApp has no test target) is checked by debug script,
  below, against a build with the old behavior and against the fix.

No migration, no pipeline bump, no rendering change, no new string.

## Results

- Baseline at `05873e0`: `swift build` clean.
- `swift build`: clean, no new warnings.
- `swift test`: 1027 tests in 151 suites passed, 1 known issue (not this
  change's).
- `Scripts/build-app.sh`: built.

## Debug-script checks

Bundle copy with `CFBundleIdentifier` `me.sesser.gus.debugtest163`, re-signed
ad hoc, on a scratch library from `photobench generate --jpeg 8` and
`photobench import`, each run as
`Gus --library-root <lib> --debug-script "wait 2; selectall; export window; export set dest=<folder> reveal=off size=long:200; <command>; quit"`.
"Old" is the same build with the gate made permissive and `cancelRequest` a
no-op (the behavior at `05873e0`), built, run and then reverted.

| Check | Command | Old | Fixed |
| --- | --- | --- | --- |
| S1 double Return, empty folder | `export run twice` | `started 2 of 2`; the surviving job `exported 2 … failed 6` | `started 1 of 2`; `exported 8 … failed 0` |
| S2 Cancel during the count, 8 files in the way | `export run cancel` | (not run) | `closed while counting true: started false alert false exporting false` |
| S3 Cancel during the count, empty folder | `export run cancel; wait 3` | `started true`, 8 files written | `started false alert false exporting false`, folder empty |
| S4 the alert still works | `export run keepboth` into S1's folder | | `export conflicts 8 originals 0`, then 8 written as `-2` |
| S5 closing after the export started | `export run nowait; export close; wait 4; print activity` | | Activity `Exported 8 photos.`, 8 files |

`export run twice` and `export run cancel` are new debug-script options
(`DebugExportCommands`) for these checks.

## For a person

- P1. A real double Return on the sheet (keyboard repeat or two quick
  presses) starts one export, with one Activity row.
- P2. Export into a folder of large files that already have the export's
  names (so the count takes a while), then Cancel at once: no alert, nothing
  written; reopen the sheet on other photos and export: only those.

## Open questions

None.

## Notes

- The Export button is not dimmed while a request reads: the second press is
  simply refused. Dimming it would be a visible change, so it is left to the
  design side if wanted.
- Pressing Stop (⌘.) while a request is still counting does nothing to the
  request (there is no job yet); the sheet's Cancel is the way, as before.

## README

No change to requirements, build commands or layout.
