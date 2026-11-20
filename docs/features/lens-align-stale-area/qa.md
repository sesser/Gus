# Color Alignment's input area (#228): QA

Owner: qa-tester. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md`.
Tested: `bug/lens-align-stale-area` at `80f7e59` (merge base with `origin/develop`: `1a1dc44`), on macOS 27.2 (Darwin 27.2.0), the Mac's SwiftPM toolchain. No bundle built, no app launched.

## Verdict

Passes. The branch is test-only: the source diff is one comment, the three guard tests pass on every run and leave no file behind, and no golden or pipeline version moved. Nothing for a person to check.

## Scope check

- `git diff origin/develop -- Sources` (two dots) also shows `RenderEngine.swift`, but only because `origin/develop` has moved on (PR #239, #229) and this branch has not merged it yet. The branch's own change is `git diff origin/develop...HEAD -- Sources` (merge base `1a1dc44`): `LensCorrectionRenderer.swift`, comment lines only (every added and removed line starts with `//`). Code review reached the same result with `git diff -w`.
- Three-dot file list: that comment, `Tests/PhotoCoreTests/LensAlignStaleAreaTests.swift` (new), `status.md`, `code-review.md`. Nothing under `Scripts/` or `Package.swift`.
- No file under `Tests/PhotoCoreTests/Goldens` in the diff. `PreviewCacheKey.currentPipelineVersion` is still 13 and the diff does not mention it in source.
- Note for the main session: merge `develop` before the pull request (workflow step 6); the merge should not conflict (the branch touches none of the files #239 changed).

## Acceptance criteria

There is no PRD. The criteria are the Bug section of `status.md`. #228 was closed as not planned (owner ruling RQ-1 (a), 2026-11-19), so the claims are that the fault does not occur, why, and that guards pin it.

| Claim in the Bug section | How | Evidence | Result |
| --- | --- | --- | --- |
| Rendering Color Alignment with one pair of values, then another, through one context matches a fresh context's render (the whole-extent and tile variants, scene input) | Test | `LensAlignStaleAreaTests.dragInOneContext`: 7 value pairs (1/-1 ... 50/-50, -50/50, 12/3), exact `Float` comparison of every component, shared against fresh context | Pass |
| The same on a JPEG decoded by `PreviewGenerator`, full size, through the whole pipeline, in the corner tile as the loupe renders at 100% | Test | `LensAlignStaleAreaTests.jpegDragInOneContext` | Pass |
| The inputs and the tile can show a stale area (the harness would see the fault), for the blurred scene and for the decoded JPEG | Test | `LensAlignStaleAreaTests.tileSeesTheInputArea` (cases `false` and `true`): a callback that ignores the values gives a different tile | Pass |
| The guards fail if the values reach the kernel in a way the digest doesn't see | Test, read, relying on code review's mutation run | Code review moved `red` and `blue` into a 1-pixel table image: `dragInOneContext` and `jpegDragInOneContext` failed (64 to 190 components), `tileSeesTheInputArea` passed as it should. I did not repeat the mutation; I read the tests and they compare a shared context to fresh ones with exact equality and no tolerance, which can't hide a difference. | Pass |
| Root cause: `lensAlign`'s callback reads only `center` (from the input's extent, a kernel argument) and `reach` (from the two `Float` arguments) | Read | `AdjustmentRenderer.align` in `Sources/PhotoCore/Edits/LensRenderer.swift` and the `lensAlign(sampler, float2, float, float)` kernel signature in `Kernels/LensKernels.swift`; one call site. Agrees with `code-review.md`. | Pass |
| The one gap (two `Double`s rounding to the same `Float`) is inside the callback's 2 px margin | Read | Figures in `status.md` rechecked: 2^-31 = 4.66e-10; times 3606 px = 1.7e-6 px; times 9014 px = 4.2e-6 px. | Pass |
| The `applyWarp` comment is accurate (the warp's table is a bitmap `CIImage` not in the digest; Manual 60 then -60 without Constrain has equal scalar arguments) | Read | `LensCorrectionTests.distortionMatchesReference` uses `(60.0, false), (-60.0, false)`; passes in the full run | Pass |
| No source behavior, golden, migration or pipeline version changed | Script (git) | Scope check above; full suite green, including `GoldenTests` | Pass |

The experiments status.md calls temporary (a callback too small, a table-carried value, a vector argument) were not committed and I did not rerun them; the committed guards and code review's mutation run stand in for them.

## Findings

None.

## Scripts

No debug script: no UI or behavior changed. Commands run, from the worktree:

```
git diff origin/develop...HEAD --stat
git diff origin/develop...HEAD -- Sources
git diff origin/develop...HEAD --name-only | grep -ci golden      # 0
ls $TMPDIR | grep -c 'align-stale-area-.*jpg'                      # 0 before, between and after
swift test --filter LensAlignStaleAreaTests                        # 4 runs
swift test                                                         # 1 run
```

- `LensAlignStaleAreaTests`, 4 runs: 3 tests (4 cases) passed each time, 0.689, 0.697, 0.697 and 0.694 s.
- Full `swift test`: 1252 tests in 179 suites passed (73.5 s). `status.md` and `code-review.md` record the same count. One full run was enough; the second I was allowed was not needed.
- No `align-stale-area-*.jpg` in `$TMPDIR` before the runs, after the filtered runs, or after the full run (C1's fix works).
- No app was launched. I did not open or read `~/Library/Application Support/Gus` or `~/Library/Caches/Gus`.

## For a person

Nothing.

## Follow-up

None yet. The owner's sign-off does not apply to a test-only branch (`status.md`: no sign-off or Ship); the pull request must not say `Closes #228`.
