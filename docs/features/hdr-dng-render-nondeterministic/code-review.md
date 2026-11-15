# A render of an HDR DNG is not deterministic: code review

Owner: code-reviewer. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/squash-top-10`, cb0df4c..1e855e7 (the #181 commit; branch head
8d87d90). Build and tests: `swift build` clean; full `swift test` at 8d87d90:
1030 tests in 152 suites passed, 1 known issue (`LiveSessionTests`, as on
`develop`). `LinearDNGRenderSoakTests` skipped (no `LINEAR_DNG_SAMPLE` here).

## Verdict
The workaround is sound and narrowly scoped (DNGs whose main image is linear
raw). It is ready for QA once C1 is fixed. C1 is a wrong claim about memory in
the code and in `status.md`, not wrong behavior.

## Findings
| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C1 | Should fix | `Sources/PhotoCore/Preview/LinearRawDecode.swift:36-42`; `status.md` "Cost" | The comment says the single-context engine makes these bitmaps "one at a time", which "bounds the memory their bitmaps take". `RenderEngine.withContext` (`RenderEngine.swift:76-84`) does not serialize: with one context, every caller uses it at once. Each bitmap is also held after the render, until its `Decoded` image is released | Scrolling the grid over a folder of HDR merges runs the generate lane (`min(8, max(4, cores/2))` at once), plus the HDR lane (2), the full lane (1) and export (2). Each decode allocates its own bitmap at full size: 8 bytes a pixel, 127 MB for the issue's 16 MP merge, so roughly 0.5 to 1.3 GB in flight where `status.md` counts one. Larger merges and panoramas scale up from there. This matters only with many or large linear DNGs at once (owner context: noted, not escalated). Fix: correct the comment and the Cost section to give the real bound. A lock around `rendered` would bound only how many are made at once, not how many are held, so add one only if the owner wants a cap | Accuracy; memory on the decode path (`CLAUDE.md` Concurrency) |
| C2 | Nit | `status.md` "Open questions" and lines 125, 167-169 | The pipeline-bump question is still open, and the text still says `WhiteBalanceAcrossDecodersTests` pins version 9. On this branch, 8d87d90 (#71) bumps `currentPipelineVersion` to 10 and removes the carry-over. Every version 9 preview, edited linear DNGs included, is made again: option (c) in effect | The status reads as if edited linear DNGs keep previews from before the fix. They don't, once the branch merges. Close the question with a pointer to 8d87d90. If these fixes are ever split into separate pull requests, #181 needs its own bump | Rendering: a change to how a stack renders bumps the version. The branch as a whole satisfies it |

## Questions
- For the owner: `status.md` proposes adding
  `LINEAR_DNG_SAMPLE=path/to/merge-HDR.dng swift test --filter LinearDNGRenderSoakTests`
  to `CLAUDE.md`'s command list (owner's section), as the check to run on
  each new macOS, like `RAWEdgeSmearTests`.
- Floating-point Bayer and JPEG XL Bayer DNGs stay lazy (no sample to test).
  This is recorded in status; it is the owner's call if such files turn up.

## Checked and fine
- `DNGLayout.hasLinearRaw`: the main image (`subfileType == 0`) with
  PhotometricInterpretation 34892. `DNGLayout(contentsOf:)` returns nil for
  anything not named `.dng` without opening it. Computing `layout` for every
  raw decode, not only scaled ones, costs nothing for camera raws and one
  small header read for DNGs.
- `LinearRawDecode.rendered`: takes the image from `RAWDecodeGraph.output(of:)`,
  so it keeps the per-decode graph rule. It renders `.RGBAh` in the working
  space, so extended-range values survive (the HDR rendition), and returns a
  `CGImage`-backed image over the same extent (offset handled). It falls back
  to the lazy image, with a log line, on an empty, infinite or fractional
  extent or a failed render. The logged extent is public; no path is logged.
- Downstream: the live session and the 100% region make their own half-float
  copy and drop the `Decoded`, so the extra bitmap is transient there (a
  second whole render, as status says). Auto White Balance samples the lazy
  decode directly (`AutoAdjust.swift:234`) with no multi-program graph,
  outside the fault as bisected.
- Precision: half float matches what the live session already keeps.
  Unedited and white-balance-only renders are unchanged bit for bit; the
  table of edited differences is measured, not tuned.
- Tests: `linearDNGDecodeIsRenderedWhole` / `reducedLinearDecodeIsRenderedWhole`
  fail without the fix (no `cgImage`). The tolerance (2⁻¹⁰ relative) comes
  from two half-float roundings, not trial and error.
  `cameraRawDecodeStaysLazy` guards the scope. The non-determinism itself is
  checked only by the opt-in soak on a real merge; the synthetic file can't
  trigger it, which status records.
- `SyntheticDNG.linearRaw`: the Bayer path is unchanged (the default is
  `false`; the CFA tags are written only for CFA images), and the goldens
  pass.
- No golden moved, no tolerance loosened, no migration. `RenderEngine` is
  `Sendable`, so the static engine is fine under Swift 6.
- Security: no new parsing. `hasLinearRaw` reads IFDs already parsed with
  their existing bounds.

## Follow-up

### Second pass (2026-11-15, `7047bad`)

Reviewed only `7047bad`. `swift build` clean; full `swift test` at `7047bad`:
1032 tests in 153 suites passed, 1 known issue (`LiveSessionTests`, as on
`develop`).

| # | Status | Commit | Note |
| --- | --- | --- | --- |
| C1 | Fixed | `7047bad` | The comments in `LinearRawDecode.swift` (the type's cost note and `engine`) and `status.md`'s Cost section now say 127 MB per decode, held until the `Decoded` is released, with no bound, and give roughly 0.5 to 1.3 GB over the concurrent lanes. `withContext` is described correctly. Comments and docs only, no cap (the owner's call, as `status.md` records). |
| C2 | Fixed | `7047bad` | `status.md` closes the pipeline question: `currentPipelineVersion` is 10 on this branch (`PreviewCacheKey.swift:43`, from `8d87d90`), which covers #181. It also says #181 needs its own bump if the fixes are ever split. |

No new findings.
