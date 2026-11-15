# Local Sharpness with the Sharpening group off: code review

Owner: code-reviewer. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/squash-top-10`, 493b6a5..8d87d90 (the #71 commit, branch head).
Build and tests: `swift build` clean; full `swift test` at 8d87d90: 1030 tests
in 152 suites passed, 1 known issue (`LiveSessionTests`, as on `develop`);
`GoldenTests` pass.

## Verdict
Ready for the designer's review and QA. The ruling (option B) is applied in one
place, `Adjustments.effective`, which every render path already reads. The
pipeline bump to 10 is a plain bump, and removing the #170 carry-over is
correct: nothing in code, tests or launch still depends on it. Two documents
owned by the product manager still describe the carry-over and are for Ship.

## Findings
| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C1 | Nit | `docs/features/_inventory.md:251`; `CLAUDE.md:786` | Both still say pipeline version 9 and describe `PreviewDiskCache.carryOver`. `status.md`'s README note names only `CLAUDE.md` | A reader of the inventory looks for a carry-over that no longer exists. Both files belong to the product manager: for the main session to pass to Ship, not for the engineer | Ship keeps the inventory and "Scope so far" true |

## Questions
- Relay the engineer's **DQ-1** (designer): with the group off, the mask's
  Sharpness slider still moves and does nothing.
- Relay the engineer's **RI-1** (product manager): sharpen-mask-preview's
  AC11 (c) and R10 now read "Not Applied" for a group that is off with a
  sharpening mask.

## Checked and fine
- `Adjustments.effective`: when `Sharpen.kind` is off, every mask's
  `adjustments.sharpen` is 0. That happens only in `effective`, so the stored
  values, `editStack` and `renderHash` are unchanged (the operation's
  `isEnabled` already changes the hash). Defaults are still left out, and
  turning the group back on gives the stored amount back
  (`storedValuesAreKept`).
- Every path that applies local Sharpness reads `effective`:
  `AdjustmentRenderer` (`render`, `sharpeningInput`, `downstream`'s
  callers, lines 50/223/267), `LiveRenderSession` (158, 381), the 100%
  region (through `render`), `LensRenderer`, and `SharpeningMapStatus`. I
  grepped for `MaskSharpening` and `.adjustments.sharpen` and found no path
  that bypasses it.
- A mask whose only value is Sharpness leaves the photo exactly as it came
  in. The test compares exactly, not with a tolerance.
- Pipeline: `currentPipelineVersion` 9 → 10, no golden moved (no golden case
  turns Sharpening off; the one with local Sharpness has it on), and no
  tolerance changed. `pipelineVersionBumped` checks that a version 9
  rendition is not found and is removed.
- Removing the carry-over: `git grep` finds no remaining caller, constant or
  test of `carryOver`, `versionCarriedOver` or `libRawDecodingSince` in
  `Sources/`, `Tests/` or `Scripts/`. The one call at launch
  (`LibraryModel.swift:754`) is gone, and `removeObsoletePipelineVersions`
  now does the whole job. `photocli`, `photobench` and the importer never
  called it. The two removed tests covered only the carry-over. #170's AC12
  rows in `white-balance-across-decoders/qa.md` record that feature's
  sign-off and stay as history. Removing it is also necessary: kept, it
  would have moved version 8's previews, with the old local sharpening,
  under version 10.
- The bump also covers #181's change to edited linear DNGs (see that
  review's C2).
- `SharpeningMapTests.notAppliedRule` changed its expectation for case (c)
  with the group off, to follow the owner's ruling. The Amount 0 half is
  unchanged. RI-1 records the spec change.
- User guide paragraph matches the behavior. No new string, no migration.

## Follow-up
