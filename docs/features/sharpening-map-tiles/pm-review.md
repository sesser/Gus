# Sharpening map tiles: product review

Owner: product-manager. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/sharpening-map-tiles` at ed68004 (PR #52, base `develop` at dfa0d5c).

## Verdict

Delivers what was asked, as far as the files can show: the wrong rectangles are
gone from the bundled app at Fit and at 100%, regression checks exist and
`swift test` passes. One check remains: the owner's own look on a real display (P1).

## What was asked

| Requirement, AC or Bug section item | Result | Evidence |
|---|---|---|
| Owner: no hard-edged, noisier rectangle in the map at Fit on a 20 MP Panasonic RW2, in the app | Yes | `qa.md` B1 and B3, scripted in the bundled app on `P1040037.RW2`. 33 of 76 Fit snapshots on `develop` had whole wrong cells; 0 of 84 on the branch, on first refinements and after Masking moves, with the preview cache cold and warm. |
| The same, by hand on the owner's display | Awaiting a person (P1) | `qa.md` B12: nobody has looked at the fix on a real display. The scripts set each value in one step, while a hand drag sends live frames first. The reviewer's headless run in that order: 28 of 30 wrong unfixed, 0 of 20 fixed (`status.md`, Reproduction counts). |
| Owner: a regression check exists. Bug: a test that fails without the fix | Yes | Two, and both fail on `develop` and pass on the branch (`qa.md` B8). `keptInputIsRendered` runs in the normal suite and CI; it checks the cause (the kept image is pixels), not the picture. `SharpeningMapRawFileTests` checks the picture but needs the RW2, so it runs only by hand. |
| Owner: `swift test` passes | Yes | 637 tests in 109 suites, 1 known issue, the existing `withKnownIssue` (`qa.md` B10, at a452c86). CI green at a452c86 (B11). The later commit, ed68004, is named as QA's record. |
| Bug, Steps to reproduce: the fault shows on the unfixed code | Yes | `qa.md` B1 and B2 in the app; `status.md`, Reproduction counts, headless. |
| Bug, Expected: every refinement is the map computed directly from the full-resolution master, apart from the kept input's half-float rounding | Yes | A clean refinement differs from the direct map by at most 5 of 255 at Masking 23 and 3 at 30 (`code-review.md` Follow-up, C1). With a float32 input the two are bit-identical, so the difference is the half-float step (`status.md`, The direct-map tolerance). `qa.md` B6: worst 0 against the same graph over eagerly rendered pixels. |
| Bug: gone at 100% and back at Fit | Yes | `qa.md` B4: 0 of 39 at 100% on the branch. B3 includes the return-to-Fit frames. |
| Bug: the refinement after a cancelled one is correct (`status.md`, For QA 3) | Yes | `qa.md` B5: 0 of 12 wrong. |
| `sharpen-mask-preview` R6: after a pause the map is the full-resolution one scaled to the zoom, so it matches a full-size export | Yes | The wrong cells were the breach of R6, and they are gone (rows above). The refinement decodes at full size and computes the mask there (`SharpeningMapRefiner.swift:70-78`). Limit: on this real file, at low Masking the rounding exceeds AC7's stated tolerance (Masking 5: worst 29 of 255, allowed 22, 1260 components over), and why is only partly explained (`code-review.md` C1; `status.md`, The direct-map tolerance and Follow-up 2). That is rounding on a few pixels, not wrong cells. No check compares the map with an exported file; the direct map stands in for one. |
| `sharpen-mask-preview` R13: sharpening's rendering is unchanged | Yes | `qa.md` B9: no golden changed, `currentPipelineVersion` still 7. |
| The map is no slower | Yes | `status.md`, Timings, before to after. Fit: first refinement 232 to 206 ms, later ones 42 to 32 ms. 100%: 244 to 202 ms and 51 to 40 ms. |
| `docs/USER_GUIDE.md`: the map after a pause is "the map of the full-size photo, which is what an export sharpens" | Yes | Unchanged, and true for this file again (`status.md`, Bug checks 7). |

## Findings

None for the engineer.

For the owner before merging. None of these blocks the merge.

- **P1 says more with a cold preview cache.** On `develop` with previews already
  cached, only the first map after launch went wrong; with a cold cache later
  maps did too (`qa.md` S1, S2, O2). The owner's report was of a map after a
  value moved. If `gus-playground` already has previews for this photo, look
  hardest at P1 step 2, because the Masking moves in step 3 would probably have
  looked clean even before the fix. P1's fresh-library option starts cold.
- **If the slider moved at the time wasn't Masking, move it in P1 too.** QA moved
  only Masking with the map on. Amount, Radius and Detail reuse the same kept
  input (`SharpeningMapRefiner.swift:62-66`), so they take the tested path, but
  nobody has run them.
- **The fix removes the trigger; the cause is still unknown.** Core Image returned
  wrong cells when the mask read an image that wasn't rendered yet, and why is
  not known (`status.md`, Not known). The fix applies to every file over about
  17 MP. The only real file tested is this RW2.
- **`status.md` Follow-up 3 is the one to know about.** The photo's own live
  frames on tightly cropped large raws still keep that kind of unrendered image.
  No wrong frame in 162 tried (150 in `status.md`, 12 in `code-review.md`), so
  leaving it is reasonable, but with the cause unknown that is not proof. A
  rectangle in the photo itself, not the map, would point here. The Fringe Map
  keeps no input, so it is not on the path that was fixed
  (`SharpeningMapRefiner.swift:93-116`; read, not run on this file).
- **Follow-up 1 doesn't affect this merge.** At 100% the loupe can receive a frame
  not yet rendered. If its first read is on the main thread that costs about 36
  to 60 ms per new frame; the thread is unconfirmed. It predates the branch,
  gave no wrong pixels (0 of 30), and changing it alone did not cure this bug.
  It should become a roadmap Idea.
- **Follow-up 2 is a test matter.** Its effect on R6 is in the table above.

## Follow-up

No findings to close.
