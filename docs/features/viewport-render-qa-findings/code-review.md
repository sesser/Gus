# QA findings on sharp live frames at 100%: code review

Owner: code-reviewer. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/viewport-render-qa-findings`, `915d39a..643e80d`, locally against `develop`. Build and tests: `swift build` clean; `swift test` 650 tests in 110 suites passed, 1 known issue (the existing `LiveSessionTests` one). `UPDATE_GOLDENS=1` not run, and the app was not launched: the traces below are from reading the code.

## Verdict

The code is correct and I ask for no code change. It is not ready for qa-tester until `status.md` narrows its Q2 claim and names a check that pins the decode's wiring (C1, C2); that is a docs-only change and needs no further code review.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `status.md:74-75`; `LiveRegionRendererTests.swift:358` | The test the Bug section names does not pin the fix. It is a truth table of a one-line predicate, and nothing checks that the editor uses it. | `PhotoCoreTests` depends only on `PhotoCore` and `PhotoFixtures` (`Package.swift:63-65`). Remove the rule from the render loop (`AdjustmentEditor.swift:1283`) or the `!loupeLoadsFullRendition` guards in `scheduleRegionPrepare`, and `swift test` stays green while the added stall comes back. A deterministic check already exists and costs no code: a direct White Balance commit at 100%, then `print frames`. Its `still` frame ends in `decode settling` with the fix and `decode running` without it. The Bug section should name that as the check. The `q1` script does pin Q1, as an explicit manual check. | Agent rule: the named test fails without the fix and checks the behavior; WORKFLOW Rules |
| C2 | Should fix | `status.md:7,54-55,97-98,103-110` | "Q2 did not reproduce" says more than the method shows. It holds only for the longest gap on an arrival that draws a full render. | (a) QA's arrivals had two gaps, "239 + 374 ms" and "230 + 377 ms". A longest-gap column can't see the first, and `sample`'s first-draw total doesn't count other main-thread time. (b) The 22–29 ms windows are left out, and they are the other half of QA's comparison ("`develop` none over 22 ms one way"). The table leaves out 5 on the baseline against 1 on each of the others. Their stated cause is also unshown: the cache keeps one full rendition (`PreviewService.swift:355-364`), and `arrive` dwells over 4 s per arrival, so going back to a photo should miss. (c) The baseline runs 90–170 ms above QA's, and its Amount rows sit above both feature builds on an unchanged code path. That is a build or run offset of 60–130 ms, the size of the effects being compared. "No after range goes above the top of the baseline's" is weak when the baseline has up to three times the runs. (d) The text says 6 runs per build; the row has 24, 12 and 12 windows. Ask: say what was shown, keep Q2 open for qa-tester, and report every gap over 100 ms per arrival, with cheap arrivals counted per build, equal runs, alternating order. The White Balance conclusion is better supported: `CA::Transaction::commit` samples of 1928 before and 1624 after, against 1581 and 1675. | Bug section; agent rule on verifying claims |
| C3 | Nit | `status.md:72`; `viewport-render-1to1/status.md:218-219` | Two wording corrections. Ruling 9 is about a decode setting changing mid-drag, so it doesn't apply to a drag that starts soft; the right citations are R6 ("the first frame of a drag") and the check's Allowed line. And `decode settling` is documented as the first frame of new settings, but a commit's `still` frame now says it when the decode is waiting for the full rendition. | No false failure, since the rule applies to `interactive` lines only, but a reader of `print frames` is misled. | Spec accuracy |
| C4 | Nit | `LiveRegionRenderer.swift:268`; `AdjustmentEditor.swift:1283` | The rule's comment says the frame "is followed by the full rendition". Not when Fit is already 100%: `zoom` is `.fit`, no load starts (`LoupeView.swift:377`), the flag is never set, and nothing reschedules the decode. | A raw small enough to fit at 100%: after a White Balance commit the texture stays stale until the next drag's second frame starts its decode. Before this commit the commit started it. R6 allows the soft start, so this is small. Calling `scheduleRegionPrepare()` where the rule holds would close it, since its guards already handle a load that starts. | Correctness of the stated rule |

## Questions

**Requirements: none, and no ruling is needed for the trade-off.** The frame-by-frame check allows "any frame before the first sharp one", and R6 lists "the first frame of a drag". See the answer below.

**Design: none.**

## Checked and fine

**1. The trade-off complies.**
- The interactive path isn't gated. `shouldDecode(whileMoving:)` starts the decode on the drag's first or second frame whatever the full load is doing, and the drag's first live revision cancels `fullTask`.
- So the softness is one decode, not the full render: one soft frame (127–232 ms), the decode (115–204 ms), up to one more frame in flight, then the first region frame. That is about 0.5 s for a typical stack and about 1.4 s at worst (three masks), inside the 2.5 s timeout. With machine learning on it is about a decode of 1.4 s or more, under R5.
- The window is about 1 s after a commit that changed a raw decode setting, and a similar time after arriving at a photo. Amount and other controls that don't change the decode settings are unaffected.
- Only a drag shorter than that decode is soft throughout, and letting go then falls under R6 too.

**2. `loupeLoadsFullRendition` can't stick.**
- The flag is set only in `loadFullResolution`, and the task's `defer` clears it for the latest generation however the task ends: landed, failed, a stale key.
- A cancelled load leaves `WorkLane` at once (`cancelWaiter` resumes the waiter), so cancelling clears it promptly.
- Photo change and teardown go through `finishSession`, which clears it with `regionRenderer` already nil.
- A zoom below 100% leaves the load to finish, and then `scheduleRegionPrepare`'s guard makes clearing a no-op. Returning to 100% prepares through `setLoupeViewport`.
- A rendition in memory returns at once. Offline masters never set it (`sourceURL` guard). Both orders of full load and editor load are handled.
- The prepare task's 150 ms sleep resumes on the main actor, so it runs after the first draw. And since the interactive path isn't gated, even a stuck flag could not keep a drag soft.

**3. Q1's fix can't end the wait early.** It fires only when `next.values == awaitedMachineLearningValues`, the region frame is current and the base holds those settings. A newer request changes the awaited values first, so a different value's wait is untouched.

**4. Tests and Q2.** See C1 and C2.

**5. Reviews.** The design review is not required: no layout, string or control changes, Q1 restores design §2's machine learning row, and a soft start is §2's "perhaps a soft first moment". `/security-review` does not apply: no parser, subprocess, outside file writing or network code.

**Also checked.**
- `decodeWaitsForFullRendition` lets a held control, the overlay, Show Original and a hover preview decode at once.
- `fullLoadGeneration` and the flag are main-actor only, with no new `@unchecked Sendable`.
- No change under `Sources/PhotoCore/Preview`, no goldens, no pipeline bump, no new strings.
- C17 from the feature's review is done in `viewport-render-1to1/status.md`, and the ML stall conclusion (the baseline stalls as long) is supported by the table.

## Follow-up
