# Reads beside the write chain: QA

Owner: qa-tester. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`. Bug fix, issue #64.
Tested: `bug/squash-top-10` at 7047bad, on a Mac16,8 (M4 Pro), macOS 27.2.1 (26B131), Xcode SDK 27.2.

## Verdict
Passes. The race is proved by tests on the chain helpers (5 of 7 fail when the helpers read the catalog directly, as the app did before), and every one of the six app call sites uses the helpers (checked by grep, since PhotoApp has no test target). The scripted run of the repro gives the right result but cannot tell the old build from the new: the race window is one catalog write.

## Acceptance criteria
The criteria are the Bug section of `status.md` and the issue.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| Copy Adjustments right after a paste copies the pasted values, and the next paste gives them on | Test | `SavedEditsReadTests` "Copy right after a paste copies the pasted values, and the next paste gives them on" | Pass |
| Save as Preset from the grid right after a change holds the changed values | Test | "Save as Preset right after a change saves the changed values" | Pass |
| Batch Auto Exposure and a paste or preset that measures color alignment read each photo's stack after pending saves | Test | "A batch measurement reads every photo's stack after a pending change" | Pass |
| The preset preview's base and the offline machine learning badge read after pending saves | Test | "The offline badge reads machine learning from a stack whose save is pending" | Pass |
| A read waits for a change queued while it waits | Test | "A read waits for a change queued while it waits, and reads it" | Pass |
| Unreadable stacks are reported, not read as defaults; a cancelled read throws and returns nothing | Test | "Stacks this build can't read are reported, not read as the defaults"; "A cancelled read throws and returns nothing" | Pass |
| The six app reads go through the helpers (`copyAdjustments`, `focusedAdjustments`, batch `autoExposure`, `changeAdjustmentsMeasuringAlignment`, `PresetPreviewModel.baseAdjustments`, `loadOfflineMachineLearning`) | Script | Script S2 (grep): each is on `writes.savedAdjustments` or `writes.savedEditStacks`; the one other direct read, `AdjustmentEditor.follow`, already uses `writes.read` (PR #43) | Pass |
| The repro sequence gives C the values B has after the paste | Script | Script S1: smoke run, same result on the old build | Pass (smoke only; see Findings Q1) |

Tests that fail without the fix: in a scratch copy of the branch whose two helpers read the catalog directly (the pre-fix reads), 5 of the suite's 7 tests failed with 12 issues: copy, Save as Preset, the batch measurement, the offline badge and the queued-while-waiting read. The unreadable-stack and cancellation tests pass either way, as the engineer says (they check what the fix keeps). I read the tests: each queues a held write, then a change behind it, then starts the read and opens the gate, so a read beside the chain can only see the row from before the change.

Full run: `swift test` 1032 tests in 153 suites passed, 1 known issue. `Scripts/build-app.sh all` built.

## Findings
- Q1 (no action required; for the record). Nothing automated fails if an app call site goes back to reading the catalog directly: the tests exercise `WriteChain.savedAdjustments` and `savedEditStacks`, not the call sites. The engineer already names this (no PhotoApp test target, `qa-test-gaps`). The scripted run below does not reproduce the race on the old build, so it is not a regression guard either; S2's grep is the call-site check.

## Scripts
Setup: `Scripts/build-app.sh`, the bundle copied to the scratch folder, `CFBundleIdentifier` changed to `me.sesser.gus.debugtest`, re-signed ad hoc (`codesign --force --deep --sign -`); a scratch library from `photobench generate --output lib/src --jpeg 8 --dng 0 --heic 0` and `photobench import --library-root lib/app --source lib/src`. Every launch: `<copy>/Contents/MacOS/Gus --library-root <scratch library> --debug-script "…"`. A copy of the library for each run.

S1, the repro through the grid (new build, and the same on a scratch build of the branch with the helpers reading directly):

```
wait 3; focus 0; loupe; wait 3; adjust exposure 1.5; wait 1; grid; wait 1; focus 0; copyadjust; focus 1; pasteadjust; copyadjust; focus 2; pasteadjust; wait 1; focus 2; preset save Smoke; wait 1; quit
```
Afterwards `photocli query images --library-root <copy>`: `IMG_00001`, `IMG_00002` and `IMG_00003` each had `exposure ev 1.5`, `IMG_00004` none; `select * from adjustmentPreset` held `Smoke`, group `light`, `ev 1.5`. Both builds gave the same result.

S2, the call-site check (in the checkout):

```
grep -rn "savedAdjustments\|savedEditStacks" Sources | grep -v "^Sources/PhotoCore/Support"
grep -rn "decodedEditStack()\|catalog.editStacks(forVersions" Sources/PhotoApp
```
The first lists `AdjustmentActions.swift` (copy, alignment batch), `PresetActions.swift`, `BatchActions.swift`, `PresetPreviewModel.swift` and `AdjustmentEditor.swift` (offline badge); the second lists only `AdjustmentEditor.swift:413`, the `follow` read inside `writes.read`.

## For a person
Nothing. The race is one write wide and cannot be made on purpose by hand; the owner has said not to record extreme-scale races.

## Follow-up
Not for this fix: the engineer proposes two follow-up issues (the loupe's editor values lag a batch change on the open photo; Paste right after Copy can use the previous clipboard). They are the main session's to file; see `status.md` "Follow-ups".

## Summary for the issue
QA passes (#64). 5 of 7 tests on the chain helpers fail when they read the catalog directly (the old behavior) and all pass with the fix; all six app reads were checked by grep to use the helpers, and a scripted copy, paste, paste, preset run gives the right values. The script cannot tell old from new (the race is one write wide), and no test covers the call sites (no PhotoApp tests). Nothing for a person. `docs/features/reads-beside-write-chain/qa.md`.
