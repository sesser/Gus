# Color Alignment's input area: code review

Owner: code-reviewer. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/lens-align-stale-area`, `1a1dc44..b7545d0` (merge base with
`origin/develop` is `1a1dc44`). Build and tests: `swift build` clean;
`swift test --filter LensAlignStaleAreaTests` 3 tests (4 cases) pass, run 3
times, about 0.68 s each; full `swift test` once: 1252 tests in 179 suites,
pass.

Test-only branch: #228 was closed as not planned (not reproducible) by the
owner (RQ-1 option (a), `status.md`). The diff is three files: the guard suite
`Tests/PhotoCoreTests/LensAlignStaleAreaTests.swift`, a comment in
`LensCorrectionRenderer.applyWarp`, and `status.md`.

## Verdict

Ready for QA. The root-cause claim holds against the code, the source change is
comment only, and the guards demonstrably fail when the premise breaks (a
mutation run, below). Two nits on wording, neither blocking.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C1 | Nit | `Tests/PhotoCoreTests/LensAlignStaleAreaTests.swift:48` | The doc comment says the test JPEG is "removed when the suite's process ends"; nothing removes it. | Each run leaves `$TMPDIR/align-stale-area-<pid>.jpg` (92 KB). Seven were present on this Mac after today's runs. `GoldenTests.master` follows the same pattern (existing), so the leak itself matches surrounding code; the comment is what is wrong. Fix the comment (or remove the file). | Correctness of comments |
| C2 | Nit | `docs/features/lens-align-stale-area/status.md:75-77` | "Their reach differs by less than 10⁻⁶ of a pixel at any corner" is slightly understated. | Two `Double`s that round to the same `Float` near the maximum scale 0.005 differ by under one ulp, 2⁻³¹ ≈ 4.7 × 10⁻¹⁰. At a 6000 × 4000 frame's corner (≈ 3600 px from the center) that is ≈ 1.7 × 10⁻⁶ px, and more at the 150 MP cap. The conclusion stands (the callback's 2 px margin covers it); only the number is off. "A few millionths of a pixel" would be right. | Accuracy of the record |

## Questions

None.

## Checked and fine

- **Root cause.** `AdjustmentRenderer.align` (`Sources/PhotoCore/Edits/LensRenderer.swift:40-52`):
  the ROI closure captures only `center` (a `CIVector` from `image.extent`,
  passed as the kernel's `center` argument) and `reach` (from `redScale` and
  `blueScale`, passed as the `Float` arguments `red` and `blue`); everything
  else it reads is the `rect` asked of it. The kernel
  (`Kernels/LensKernels.swift:183-191`, `lensAlign(sampler, float2, float,
  float)`) has no image argument other than the source, so no value reaches it
  through a bitmap. It is the only `lensAlign` call site. The one gap, values
  that round to the same `Float`, is covered by the 2 px margin (C2 corrects
  the size only).
- **Comment-only change.** `git diff -w 1a1dc44...HEAD -- Sources/` has no
  changed line outside `//` comments. The comment's claims match the code
  (the warp's area depends on `table`, a bitmap `CIImage`; the scalar and
  vector arguments are identical for Manual 60 and −60 without Constrain,
  where `scale`, `radius`, `reach` and `tangential` don't change) and the test
  it cites (`LensCorrectionTests.distortionMatchesReference`, arguments
  `(60.0, false), (-60.0, false)`).
- **The guards fail when the premise breaks.** In a throwaway copy of the
  branch (scratchpad, deleted after; nothing in the worktree changed) I moved
  `red` and `blue` out of the kernel's arguments into a 1-pixel `RGBAf` table
  image read by the kernel, keeping the same value-dependent ROI. The suite
  then failed: `dragInOneContext` at (35, −30), (50, −50), (−50, 50) with 64,
  128 and 190 components differing; `jpegDragInOneContext` at (50, −50) and
  (−50, 50) with 61 and 90. `tileSeesTheInputArea` passed, as it should (it
  uses fresh contexts only).
- **Detection control.** `tileSeesTheInputArea` shows the tile's pixels depend
  on the area asked for (an identity-sized ROI gives a different tile) for both
  the blurred scene and the decoded JPEG, so an input that uploads every pixel
  cannot hide a stale area. It proves sensitivity to the ROI, not that a shared
  context reuses; that second half rests on the mutation run above and the
  engineer's uncommitted experiments, which is adequate for a guard.
- **The drag has sensitive steps.** At the tile (≈ 1130 px from the center) the
  reach grows by more than the bilinear neighbor from 8 → 20, 20 → 35 and
  35 → 50, so a stale smaller area would show; the mutation run confirms it.
- **Determinism.** Exact `Float` comparison of the same graph in a shared and a
  fresh context on one device; no sleeps, no tolerances, no randomness (fixed
  seed 228). `.serialized` is harmless. Stable over four runs.
- **Nothing else moved.** No golden touched, no tolerance loosened, no
  `currentPipelineVersion` bump needed (no rendering changed), no migration, no
  UI, no strings, no new dependency.
- **Process.** `status.md` records the owner's ruling and says the pull request
  must not say `Closes #228`.

`/security-review` is not needed: no parser of outside files, subprocess,
file writing outside the library or network code changed (the test writes a
synthetic JPEG to the temporary folder only).

## Follow-up

(For the engineer's fixes, if any.)
