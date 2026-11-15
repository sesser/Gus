# Export double start: QA

Owner: qa-tester. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`. Bug fix, issue #163.
Tested: `bug/squash-top-10` at 7047bad, on a Mac16,8 (M4 Pro), macOS 27.2.1 (26B131), Xcode SDK 27.2.

## Verdict
Passes. Both cases of the bug reproduce on a scratch build with the old behavior (two jobs start and one reports failures; Cancel does not stop the count and the export starts anyway) and are gone on the branch (one job; Cancel stops the request, no alert, nothing written). One optional check for a person (P1).

## Acceptance criteria
The criteria are the Bug section of `status.md` and the issue.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| One export starts however often Export is pressed (a second request while one reads is refused) | Test, Script | `ExportRequestGateTests.aSecondRequestWhileOneReadsIsRefused`, `noRequestWhileAnExportRuns`, `aRequestCanFollowOneThatEnded`; Script S1 | Pass |
| Cancel stops the count: nothing exported, no alert (empty folder: no export; files in the way: no alert) | Test, Script | `aCancelledRequestEndsUnanswered`; Scripts S2 and S3 | Pass |
| An old request ending after the sheet was reopened neither answers nor frees the new request's place (the alert never appears on the reopened sheet) | Test | `anOldRequestEndingLateLeavesTheNewOneAlone`, `endingTwiceAnswersOnce`; S2 shows no alert after the cancel | Pass |
| The cancellation in `ExportJob.clashes` is exercised (the test the issue asks for) | Test | `ExportClashesCancellationTests.aReadCutShortByCancelThrowsInsteadOfCounting` (and `theCountIsGivenWhenNothingCancels`) | Pass |
| The existing-files alert still works (Keep Both numbers the files) | Script | Script S4 | Pass |
| Closing the sheet after the export started does not stop it | Script | Script S5 | Pass |
| The real double Return and Cancel/Esc through the UI | Person | P1 | Open |

Tests that fail without the fix: in a scratch copy of the branch with `ExportRequestGate` made permissive (it grants a request while one is pending, never ends or cancels one), 4 of the 6 `ExportRequestGateTests` failed with 7 issues (`aSecondRequestWhileOneReadsIsRefused`, `aCancelledRequestEndsUnanswered`, `anOldRequestEndingLateLeavesTheNewOneAlone`, `endingTwiceAnswersOnce`; the other two check what stays true; the engineer notes the suite did not compile at `05873e0`). I did not repeat the engineer's check that `ExportClashesCancellationTests` fails without the `Task.checkCancellation()` line (it exercises that function directly). The gate tests cover the rule only; that `ExportModel` uses it and that the sheet closing cancels the request is covered by the scripts, not by a test (PhotoApp has no test target).

Full run: `swift test` 1032 tests in 153 suites passed, 1 known issue. `Scripts/build-app.sh all` built.

## Findings
None. Observation, not caused by this change: most launches of the bundle copy after its first few (about 10 in all) crashed at startup inside SwiftUI (`AppKitToolbarStrategy.applyItemCustomizations`, `EXC_BREAKPOINT`, exit 133) while the copy's preferences held a saved `NSToolbar Configuration library`; deleting that key (my scratch bundle identifier only) cured it, and it did not come back in about 40 more launches of the branch, of `develop` and of the old-behavior copy. No toolbar file is in this branch's diff; I did not find the trigger. The scripts below clear the key before each launch (`run-app.zsh`). If the owner sees a launch crash in the toolbar, that is this.

## Scripts
Setup: `Scripts/build-app.sh`, the bundle copied to the scratch folder, `CFBundleIdentifier` changed to `me.sesser.gus.debugtest`, re-signed ad hoc; scratch library from `photobench generate --output lib/src --jpeg 8 --dng 0 --heic 0` and `photobench import --library-root lib/app --source lib/src`. Each run, with `defaults delete me.sesser.gus.debugtest "NSToolbar Configuration library"` first:

```
<copy>/Contents/MacOS/Gus --library-root <scratch library> --debug-script "<script>"
```
`<out>` is a new empty folder; the sheet's default is a TIFF export, so the files are `half-IMG_0000n.tif`.

S1, double Return, empty folder:
```
wait 2; selectall; export window; export set dest=<out> reveal=off size=long:200; export run twice; wait 1; quit
```
Branch: `export requests started 1 of 2`, `exported 8 … failed 0`, 8 files. Old-behavior copy: `started 2 of 2`, the surviving job `exported 6 … failed 2`.

S2, Cancel while counting, 8 files already in the way (the folder holds S1's output):
```
wait 2; selectall; export window; export set dest=<out> reveal=off size=long:200; export run cancel; wait 3; quit
```
Branch: `closed while counting true: started false alert false exporting false`, still 8 files. Old copy: `started true`, 16 files (it exported with the files in the way).

S3, Cancel while counting, empty folder (same script, an empty folder):
Branch: `started false alert false exporting false`, 0 files. Old copy: `started true`, 8 files.

S4, the alert still works (S1's folder, `export run keepboth` in place of `export run cancel`): `export conflicts 8 originals 0, using keepBoth`, then 8 more files as `half-IMG_0000n-2.tif`, 16 in all.

S5, closing after the export started:
```
wait 2; selectall; export window; export set dest=<out> reveal=off size=long:200; export run nowait; export close; wait 4; print activity; quit
```
`Exported 8 photos.` in Activity; 8 files.

The old-behavior copy is the branch with `ExportRequestGate` permissive (grants a request while one is pending; `end` always true; `cancel` does nothing) and `ExportModel.cancelRequest` a no-op, built in a scratch folder with the other fixes put back as well; it exists only to show the bug.

## For a person
- P1 (optional, one minute; covers the real input path, which the script reaches through the model). Select a few photos, File ▸ Export…, pick a folder with the existing-files alert in mind: (a) press Return twice quickly, or double-click Export: one export starts, one Activity row, no "could not be written". (b) Pick a folder that already holds files with the export's names, press Export and then Cancel or Esc at once: no alert appears, now or after reopening the sheet on other photos, and nothing is exported.

## Follow-up
Noted by the engineer, not changed: the Export button is not dimmed while a request reads (the second press is just refused), and Stop (⌘.) does nothing to a request still counting (Cancel is the way). Dimming would be a visible change for the designer to decide.

## Summary for the issue
QA passes (#163). Scripted on a scratch library: double Return starts 1 job (the old behavior started 2, one reporting 2 failures); Cancel during the count stops it, no alert, nothing written (the old behavior exported anyway); the alert, Keep Both and closing after the start work as before. 4 of 6 gate tests fail without the fix. One optional check for a person (real double Return, Cancel/Esc). `docs/features/export-double-start/qa.md`.
