# Local Sharpness with the Sharpening group off: QA

Owner: qa-tester. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`. Bug fix, issue #71.
Tested: `bug/squash-top-10` at 7047bad, on a Mac16,8 (M4 Pro), macOS 27.2.1 (26B131), Xcode SDK 27.2.

## Verdict
Passes against the owner's ruling (option B). In the bundle, with the group off a mask's Sharpness 80 renders the same bytes as Sharpness 0 and the map reads "Not Applied"; on the old behavior the two differ and the map says masks still sharpen. The designer's review of the map's badge and legend and the open design question DQ-1 are still to come; nothing here needs a person.

## Acceptance criteria
The criteria are the Bug section of `status.md` (with the owner's ruling) and the issue.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| With the group off, a mask's Sharpness renders exactly as Sharpness 0 (also with another local value in the mask); a mask with only Sharpness leaves the photo untouched | Test | `LocalSharpenGroupOffTests.offRendersWithoutLocalSharpness` | Pass |
| The same mask with the group on does sharpen (the check is not vacuous) | Test | `onSharpens` | Pass |
| The stored Sharpness is kept (and survives a write and read), applies again when the group is turned on; other groups off leave it alone; no change to stored values or the render hash | Test | `storedValuesAreKept` | Pass |
| Live frames follow the rule | Test | `liveFrames` | Pass |
| Previews cached before the fix are not used (pipeline version 10; version 9's folder is removed at launch) | Test | `pipelineVersionBumped` | Pass |
| The sharpening map reads "Not Applied" with no note about masks when the group is off with a sharpening mask; Amount 0 unchanged | Test, Script | `SharpeningMapTests.notAppliedRule`; Script S1 (badge and legend) | Pass |
| In the app: with the group off the masked area is not sharpened; turning it on brings the mask's Sharpness back | Script | Script S1: snapshots equal with Sharpness 80 and 0 off, different on | Pass |
| No golden moved | Test | `GoldenTests` in the full run | Pass |

Tests that fail without the fix: in a scratch copy of the branch with `Adjustments.swift` put back to `develop`'s, `offRendersWithoutLocalSharpness` (3 issues), `storedValuesAreKept`, `liveFrames` and `SharpeningMapTests.notAppliedRule` failed; `onSharpens` and `pipelineVersionBumped` pass either way (the second tests the bump, which is in another file). I read `LocalSharpenGroupOffTests`: it compares the renderer's output with Sharpness 80 against its own output with Sharpness 0 and requires exact equality, so it cannot pass by tolerance.

Full run: `swift test` 1032 tests in 153 suites passed, 1 known issue. `Scripts/build-app.sh all` built.

## Findings
None. Two notes outside this fix's code, for the main session:
- Cross-feature: removing #170's launch carry-over (`PreviewDiskCache.carryOver`) means `white-balance-across-decoders` AC12 ("the library's previews survive") no longer holds: every cached preview is made again once the first launch after the merge, and previews of photos on offline volumes are gone until the volume is mounted. The engineer made this a plain bump on purpose and removed the two tests of AC12 (`cachedPreviewsAreRegenerated`, `carryOverSurvivesAFailedRemoval`) with the code. This also covers #181's change to edited HDR merges. That is a Requirements note for the product manager (record it against #170's PRD and Ship), not a defect here.
- `docs/features/_inventory.md:251` and `CLAUDE.md`'s "Scope so far" still describe version 9 and the carry-over (code review C1): for Ship.

## Scripts
Setup: `Scripts/build-app.sh`, the bundle copied to the scratch folder, `CFBundleIdentifier` changed to `me.sesser.gus.debugtest`, re-signed ad hoc; scratch library from `photobench generate --output lib/src --jpeg 8 --dng 0 --heic 0` and `photobench import --library-root lib/app --source lib/src`, copied for each run. Each launch: `<copy>/Contents/MacOS/Gus --library-root <library copy> --debug-script "<script>"`. "Old" is a scratch build of the branch with `Adjustments.swift` from `develop`.

S1:
```
wait 3; focus 0; loupe; wait 3; tab adjust; wait 1; zoom; wait 2; adjust amount 120; adjust radius 2; adjust detail 80; adjust masking 60; adjust mask add linear; adjust mask overlay off; adjust mask set sharpen 80; wait 2; adjust off sharpening; wait 3; sharpenmap on; wait 2; print sharpenmap; sharpenmap off; wait 2; snapshot <dir>/off80.png; adjust mask set sharpen 0; wait 3; snapshot <dir>/off0.png; adjust on sharpening; wait 3; snapshot <dir>/on0.png; adjust mask set sharpen 80; wait 3; snapshot <dir>/on80.png; adjust off sharpening; wait 3; snapshot <dir>/off80b.png; quit
```
(The default linear mask also has Exposure -0.5, so it renders. `zoom` left the view at Fit.) Results (MD5 of each PNG, within one build; windows differ in size between builds, so compare within a build only):

| Snapshot | Branch | Old |
| --- | --- | --- |
| group off, mask Sharpness 80 (`off80`) | 93e6be73… | 6fb2202d… |
| group off, Sharpness 0 (`off0`) | 93e6be73… (same as `off80`) | f7c01c62… (differs from `off80`) |
| group on, Sharpness 0 (`on0`) | 6e0cf4bc… | 30e2ecf2… |
| group on, Sharpness 80 (`on80`) | 93f10e60… (differs from `on0`) | 9cd7c3a8… |
| group off again, Sharpness 80 (`off80b`) | 93e6be73… (same as `off80`) | 6fb2202d… |

`print sharpenmap` with the group off and the mask at 80: branch, badge `Sharpening Map · Not Applied`, legend "Sharpening is turned off. Turn it on to sharpen the white areas, and the gray areas in part."; old, badge `Sharpening Map`, legend with the extra sentence "Masks with Sharpness still sharpen the areas they cover." I looked at the branch's `off80.png` and the old `off0.png`: the loupe shows the photo with the mask's handles and the film strip as expected (the glass panes are blank in snapshots, as `CLAUDE.md` says; the badge and legend were read with `print`, not seen).

## For a person
Nothing is needed for the rule. Pending, from the other agents rather than from a person's eyes: the designer's review (the map's badge and legend now read differently) and DQ-1 (with the group off, a mask's Sharpness slider still moves and changes nothing: leave it, dim it with a caption, or turn the group back on).

## Follow-up
After the first launch every thumbnail is made again once (status.md P3): expected, not a defect.

## Summary for the issue
QA passes (#71). In the bundle, with Sharpening off a mask's Sharpness 80 renders byte for byte as 0 and the map reads "Not Applied" (the old behavior differed and the legend said masks still sharpen); turning the group on brings the value back. 4 tests fail without the fix; full `swift test` 1032 passed. Still open elsewhere: the designer's review and DQ-1; note for Ship that the plain bump ends #170's AC12 (previews carried over). `docs/features/local-sharpen-group-off/qa.md`.
