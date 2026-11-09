# Sharpening map tiles: code review

Owner: code-reviewer. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/sharpening-map-tiles`, dfa0d5c..d829598 (PR #52). Build and
tests: `swift build` clean; `swift test` 637 tests in 109 suites passed, 1
known issue (the existing `withKnownIssue`); `SharpeningMapRawFileTests` with
`CAMERA_RAW_SAMPLE` on the scratch copy of `P1040037.RW2` passed, 3 of 3 cold
processes. CI: see the note under Verdict.

Experiments that needed the fix switched off, or sizes and stacks the tests
don't cover, ran in a scratch copy of the branch outside the repository,
with `deferred:` switched by a temporary environment variable and temporary
probes. Nothing under `Sources/` or `Tests/` of the branch was changed.

## Verdict

No blockers. The fix is correct and held in every mode I tried (Fit, 100%,
the loupe's order, cold processes), so it can go to qa-tester. The three
Should fix items are about a test tolerance that is not a bound, a regression
test that can go blind without saying so, and a wrong note in `status.md`;
none changes how the app behaves.

CI note for the main session: run 42671849175 on this commit is marked
`failure`, but its only listed job, macos-15, passed, and no macos-26 job
appears in it (GitHub's capacity annotation is there). I did not treat CI as
green; it needs a rerun or a look.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|----------|-------|---------|---------|------|
| C1 | Should fix | `Tests/PhotoCoreTests/SharpeningMapSessionTests.swift:356-359` (formula at `:31-33`); `docs/features/sharpening-map-tiles/status.md:177-182` | The gated test's tolerance is inherited, not tuned or loosened, but on this real file it has no margin and its model is too small. "A file that doesn't trigger the fault can only pass" is not so: a render with no fault can exceed it. `status.md` records only "worst 3, allowed 4" (Masking 30). | With the fix, cold: Masking 23 is worst 5, allowed 5 at Fit and at 1:1 in every run (the test's first comparison). The same formula on the same refiner, other Masking, no fault (worst is rounding-sized, no cell wrong): 5 gives worst 29, allowed 22 (1260 components over); 10 gives 18, allowed 15 (543 over); 15 gives 9, allowed 9; 20 gives 6, allowed 6. Worst is 1.3 to 1.4 times the formula's unrounded value (3.76 at Masking 23), so 23 passes only on the step meant for 8-bit quantization. The formula's stated assumptions don't explain it: the decoded file's largest linear value is 1.00004 (1 of 59.9 M components over 1), and 1:1 (no resampling) gives the same worst. One more step on another macOS, GPU or file fails and looks like the bug. Please find the missing term and derive it; don't raise the number by trial. Record the Masking 23 result and correct the "can only pass" sentence either way. The test still separates the fault clearly (255 against at most 5). | `CLAUDE.md`, Checking image code: a tolerance derived from the formats involved, not tuned |
| C2 | Should fix | `Tests/PhotoCoreTests/SharpeningMapSessionTests.swift:218-241` | `keptInputIsRendered` is the only regression test CI runs, and it depends on Core Image's undocumented limits. If they change it passes silently. `status.md:172-174` says so honestly; the comment beside the test does not, and nothing in the test shows its premise still holds. | The test body without `deferred: false`: at 5472 × 3648 it fails as stated (0 pulls at `materialize`, then 24 on read). At 4096 × 3072 it passes (1 pull, none more). A macOS that renders 5472 × 3648 at once, or reads it when wrapped, is that second case: green with the fix removed, and the only other check runs by hand on one file. A control in the test (the same image through the short overload and `CIImage(cgImage:)`, 0 pulls expected) could record or skip with the macOS build named, as RAW goldens do. At least say in the comment that a later macOS can make it pass without testing anything. | Tests: "would fail without the change" |
| C3 | Should fix | `docs/features/sharpening-map-tiles/status.md:264-266`; `Sources/PhotoCore/Preview/RenderEngine.swift:103`, reached from `SharpeningMapRefiner.swift:79,107`, shown at `Sources/PhotoApp/Loupe/LoupeView.swift:414,1054` | The note that outputs "aren't kept and read again" is wrong at 100%: the frame is kept and read by the layer. A lazy image still reaches the screen there. This predates the branch and is unchanged by it; not for this branch to fix. Correct the note and raise a roadmap Idea. | BGRA8 at 5472 × 3648 through the short overload: 0 pulls when created (probe). `longEdge: nil` gives that size, and nothing reads it between `makeCGImage` and `layer?.contents = image`. The render then runs at the first read (36.5 to 60 ms in `status.md`'s own 100% rows), which `CLAUDE.md` places on the main thread at commit; I did not confirm the thread, since that needs the app. `PreviewService.fullResolutionImage` (`:236`) takes the same path and its header (`:39`) says returned images are fully decoded. No wrong pixels from it: 0 of 30 at 100% with the fix. | `CLAUDE.md`, Concurrency: images fully decoded before they reach layers |
| C4 | Nit | `Sources/PhotoCore/Edits/SharpeningMapRefiner.swift:129-132` | "(measured: a side over 4096 pixels)" describes the `createCGImage` step only. What `materialize` keeps is `CIImage(cgImage:)`, which reads at once up to 16.8 MP. The comment does not claim a cause. | 4928 × 3264 (16.1 MP) at RGBAh: deferred at create, read when wrapped (probe), so it is never lazy when the mask graph reads it. A reader of the comment would take any file over 4096 to be affected. | Comment accuracy (`status.md:50-59` has it right) |
| C5 | Nit | `docs/features/sharpening-map-tiles/status.md:111-112,210,259-260` | Three places where measurements now say more than `status.md` does. | Line 210, "between the measured wrap limits": RGBAh at 5120 × 3413 stays lazy (0 at create, 0 when wrapped, 20 on read), so that row did test a lazy base; the limit is between 16.8 and 17.5 MP for RGBAh. Lines 111-112: unfixed at 100% in cold processes was wrong in 25 of 30 refinements (9, 9, 7 of 10 per process), not 1 of 3; fixed, 0 of 30. Lines 259-260: the loupe's order (session photo and map frames first, then refiner, direct map last) does reproduce it headlessly: unfixed 28 of 30, fixed 0 of 20, so "hides the fault" is specific to a full-resolution direct render. | Status records what was measured |

## Questions

None for the designer or the product manager.

## Checked and fine

- The fix: `deferred: false` makes the kept input pixels (`pulled > 0`, no pull on later reads) and removes the wrong cells. Refiner first at Fit, unfixed in the test: 3 of 3 cold processes failed (1, 12 and 13 of 15 comparisons, worst 255); fixed, 3 of 3 passed.
- `keptInputIsRendered` fails without the fix for the reason it gives: both expectations, `pulled` 0 then the later reads, exactly as `status.md` reports. The sizes it names and the "at least 16.8 MP" reading reproduce on macOS 27.2.
- `SharpeningMapRawFileTests`: the direct map is rendered last from a fresh decode with the same settings and graph order, the setup is stated at the suite and in `status.md`, and `CameraRAWMaskTests` does fail on this file ("has no camera crop") as described. Its detection is by chance per process (the 1-of-15 process above), which the comment already implies for files that don't trigger it.
- `status.md` root cause: known and not known are separated, the cause is not claimed, and the arithmetic (39 of 42, 150 frames) and the `:127` line reference are right. Not re-run by me: the lazy image's own pixels read alone, the output-only and immediate-read rows, the timings.
- Cancellation matches the doc on `render` (`:76` after the fill). Re-run with a temporary cancel right after the fill: `CancellationError`, input held, next refinement `filledCache` false, worst 3.
- Actor: `render` and `materialize` are synchronous, so no reentrancy; a cancelled request queued behind a fill returns at its first check. Holding the actor during the fill is the existing pattern. `input = nil` comes before the new render, so no double hold; the header's pixels × 8 bytes is now simply true. `deferred: false` works where the default does at very large extents (16385 × 64, 20000 × 64, 40000 × 32, 12000 × 9000).
- Leaving `LiveRenderSession.materialize` and `base(for:)` alone is supported. Beyond the 150 frames in `status.md`, I ran a map frame at four crop positions over the native 20 MP (lazy) base, cold processes, against the same graph on an eager base: 12 of 12 frames identical (worst 0). The follow-up is recorded.
- Project rules: no `PreviewCacheKey.currentPipelineVersion` bump is right. `materialize` is reached only for `.sharpeningMap`, the refiner's only caller is the map (`AdjustmentEditor.swift:636`), and `seedPreviewIfRendered` (`:776`) requires `frame.showsPhoto`, so a map never reaches a cache; `renderWhole` is unchanged. No golden in the diff. No catalog, sidecar, undo, migration, UI string, branding or dependency change (`Synchronization` is the standard library).
- No parser, subprocess, file writing or network code: `/security-review` is not needed.

## Follow-up

Filled in on the second pass.
