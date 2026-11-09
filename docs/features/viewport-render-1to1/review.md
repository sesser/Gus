# Sharp live frames at 100%: designer review

Owner: apple-ui-designer. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`. PR #49.

**What was reviewed.** `feature/viewport-render-1to1` from `ca3f67d`, against
[`design.md`](design.md) (DR1–DR9), [`prd.md`](prd.md) (including owner ruling
8) and the HIG. [`status.md`](status.md) is the engineer's record.

**How.** I read the code; I did not build or run it, and nothing has been seen
on screen. Each result below comes from the code, the String Catalog, the guide
and the script results in `status.md`.

**Code read.** `Loupe/LoupeView.swift` (`showLiveFrame`, `showTile`,
`updateFiltering`, `updateLoupeViewport`, zoom paths, `LoupeImageView`,
`spinnerLabel`), `Model/AdjustmentEditor.swift` (render loop, the sharp-frame
wait, inputs, `catalogChanged`), `PhotoCore/Edits/LiveRegionRenderer.swift`,
`Views/InspectorView.swift`, the two hints, the String Catalog and
`docs/USER_GUIDE.md`.

The rectangle in the Sharpening Map at Fit reproduces on `develop` and is out
of scope here.

## Verdict

**Not ready to merge. F1 and F2 must be fixed first.**

- **F1:** raw White Balance, Profile and Noise Reduction stop following the hand
  once a sharp frame exists.
- **F2:** the spinner appears in the two cases §2.1 excludes.

The rest matches the design: both hints, the guide paragraph, the tile layer's
filters and animation, pixel alignment, the histogram, and "covered" agreeing
with the toolbar. F3 to F5 are small and belong in the same pass.

## Owner ruling 8 and the design

**The lower frame rate changes nothing in the design.**

- **"No mark while input moves" stands.** A picture updating 6 to 7 times a
  second is its own feedback, and a frame or two is about 300 ms, under the
  spinner's 0.5 s.
- **The spinner still means what it should.** For a typical stack the last
  value's frame lands within about 320 ms of the last input (the frame in flight
  plus one more), so no spinner should show at the end of a drag. With three
  masks at the largest canvas (p95 279–436 ms) the last frame can run past 0.5 s
  and the spinner shows briefly. That is a real wait, so it is correct.
- **§3's case against a crossfade gets stronger.** Each frame is now more
  expensive.
- **The step at 100% now includes frame rate** (about 20 to 30 a second at Fit, 6
  to 7 at 100% on the Dell). That is what ruling 8 accepted, so there is nothing to
  design. M9 asks a person whether it feels acceptable.

## Design checks

| DR | Result | Notes |
|---|---|---|
| DR1 | **Pass** | Both hints are exact in Swift and the catalog, the old keys are gone, and "Refining the photo" has the wider comment. `LocalizationTests` passed (`status.md`) |
| DR2 | **Pass by code for the photo; fails A4 for maps (F3); look on screen** | The base uses nearest-neighbor only for `.full` and `.hdrFull` at 1 and above (`LoupeView.swift:556–559`); `.live`, previews and placeholders are smooth. `updateFiltering` follows every rendition change. The tile is always real pixels (`LiveRegionRenderer.region` is whole output pixels), so its nearest filter is right |
| DR3 | **Fail (F1, F2)** | Correct by code: the 0.5 s from the last input, one spinner, last in `spinnerLabel`, off when input resumes, off for maps and crop. Wrong: the R4 row (F1) and the §2.1 exclusions (F2) |
| DR4 | **Pass by code; macOS 27 on screen** | The machine learning flag comes before the new one in `spinnerLabel`, and its wait is unchanged. F1 also applies to a Luminance drag with machine learning on |
| DR5 | **Pass by code; look on screen** | `tileLayer.actions` turns off `contents`, `bounds`, `position` and `hidden`, and `setTile` disables actions. The tile sits on whole output pixels in a view sized to the output (`matchFrame(toOutput:)`), so it lines up by construction. Only a person can confirm the soft base lines up with it |
| DR6 | **Pass by code; look on screen** | Covered is `magnification >= 0.99` and the toolbar is within 1% of 100%. A photo whose Fit is already 100% is covered |
| DR7 | **Pass by code; look on screen** | Region frames never feed the histogram. A drag takes the `regionShown, next.interactive` path with no whole frame, and the pause renders one. The inspector and the curve backdrop both read `editor.histogram`, which is cleared only when the photo closes. A pan renders no whole frame |
| DR8 | **Pass by code; VoiceOver on screen** | No announcement added, the canvas value is unchanged, and the spinner keeps `.accessibilityLabel` |
| DR9 | **Pass** | The paragraph is before **Sharpening Map**, the keys table says "100%", and "sharp frame", "live frame", "draft" and "viewport" appear nowhere in the guide |

**PRD criteria that touch the UI.**

- R4 while moving: fails by F1. No criterion catches it, because AC6 checks only
  the pause. M1 and the script note under F1 cover it.
- AC7 (R5), AC8 (never blank: the tile is always over a base, and `setTile(nil)`
  never clears the base) and AC11: pass by code.
- AC1–AC3, AC5, AC9, AC10 and AC12–AC14: the evidence is in `status.md`, and
  nothing in the UI contradicts it. They are QA's.

**HIG.** Progress indicators, Motion and Writing are honored as `design.md`
applied them. Nothing is on the glass layer, and there is no custom chrome.

## Findings for the engineer

| # | Severity | Finding | Fix |
|---|---|---|---|
| F1 | **High, blocks merge** | **R4 frames don't follow the hand once a sharp frame exists.** `editor.regionFrame` is never cleared during an R4 drag. In `showLiveFrame` (`LoupeView.swift:427–437`) each revision shows that old tile again, then returns early whenever the whole frame isn't of the current values. While the hand moves, a 127 ms frame never is. So the picture stays on the old sharp frame with the old values for the whole drag. When the hand hesitates a soft frame shows and the tile comes down; the next revision puts the old tile back, which reads as a flicker to old values. It happens after any earlier sharp frame, including "drag, hold until sharp, drag again", the natural next step after the PRD's Raw noise reduction scenario. It breaks `design.md` §2's R4 row, §3's "sharp to soft when R4 input resumes", and R6's "a value or two behind". M1 in the PRD would hit it | When a moving frame can't be a region frame (`isReady` false and `next.interactive`), drop the tile, for example by clearing `regionFrame` in that branch. Keep the guard for what it was meant for: an old whole frame landing during a drag whose tile is still being updated. Script check: after a sharp frame exists, `adjust scrub` White Balance and read `print viewport` mid-drag; it should say `tile none` |
| F2 | **Medium, blocks merge** | **The spinner appears when nothing changed.** `refreshSharpFrameWait` has no test for a change under way, and `sharpFrameIsOnItsWay` counts `regionPrepareTask` and `renderTask`. **`Z` from fit:** `setLoupeViewport` starts the prepare and arms the wait, so the spinner shows if the 150 ms pause plus the decode passes 0.5 s (masked stacks, machine learning, slower raws). It ends when the texture is ready, with no change on screen. **Arriving at a photo at 100%:** `AdjustmentEditor.swift:398–402` starts the prepare and the 250 ms histogram frame, and arrival doesn't count as input, so the delay can be zero and the spinner can flicker on each arrow key. §2.1 excludes both, and arriving is the culling path | Require a change under way in both places (`showsLive \|\| loupeAwaitsFullRendition`). Call `refreshSharpFrameWait` when `loupeAwaitsFullRendition` turns on as well as off, because today a race can miss the wait after an R4 commit. Call `noteInput()` in `catalogChanged`: Undo is "a value", and without it the delay is zero |
| F3 | Low | **Maps and the fringe slot preview lost their blocks at 100% and above.** They arrive as `.live`, so `updateFiltering` now smooths them. Before this branch they used nearest-neighbor at 1 and above. A4 and §2.2 keep them as shipped, and a refined map at 400% is real pixels | Keep nearest at 1 and above for what `canRenderRegion` excludes: a frame whose `content.isMap`, or the replaced-slot preview |
| F4 | Low | **The HDR badge stays during a drag.** `showTile` doesn't clear `loupeHDRHeadroom`, and interactive region frames return before line 449 does. On an EDR display the tile is standard range while the caption still says HDR until the pause. A4 says standard range during a live change, and today the badge goes with the first live frame. The caption must not claim what isn't on screen (SMP §5) | Clear the headroom when a tile of a change under way goes on screen |
| F5 | Low | **Three small gaps in "what was asked for" and "on its way".** (a) After `regionRenderer` is cleared (a photo over 16384 px, a failed decode), a whole-frame render still counts as on its way, so the spinner promises detail that isn't coming. (b) `sharpFrameIsOnScreen` ignores the overlay, unlike the render loop's `hasOverlay` test. (c) `loupeAwaitsFullRendition` clears only when `.full` lands, so a failed load, or a small photo at Fit (`zoom == .fit` starts no load), leaves it set | (a) Require `regionRenderer != nil` for the frame cases. (b) Compare `hasOverlay`. (c) Clear it where the load fails or isn't started |

## Requirements issues

None. Ruling 8 needs no design change, and RI2 (photos above 24 MP) has no UI
consequence.

## Manual checks

These need the bundled app, active, on a real 24 MP raw on the owner's Mac unless
noted. M1 to M3 assume F1 and F2 are fixed. The PRD's M1 is separate and stays
with the owner.

| # | Check | DR |
|---|---|---|
| M1 | **R4 while moving.** At 100%: drag White Balance, hold until the detail arrives, drag again. The picture follows the hand softly throughout, and never freezes or pops back to older values. Same for Profile and Luminance | DR3 |
| M2 | **Soft looks soft.** At 100% and 400%, a White Balance drag and the moment after a pan are smooth with no blocks. At 400% a settled photo shows real pixels as blocks | DR2 |
| M3 | **Spinner.** None during any drag. With White Balance held still, it shows only if the detail takes more than 0.5 s, and goes when the detail lands or movement resumes. Tooltip "Refining the photo". None when arrowing through raws at 100%, and none on `Z` from Fit, including a photo with machine learning on and a masked photo | DR3 |
| M4 | **Machine learning** (macOS 27). One spinner with its own label, the last frame stays, the window responds | DR4 |
| M5 | **The swap.** No fade and no shift, soft to sharp and back, with Reduce Motion on and off. The soft frame lines up with the sharp one at a fine edge, near the center and near a corner | DR5 |
| M6 | **The 100% boundary.** Real pixels at 100% by `Z`, the toolbar, ⌘=, and a pinch that selects the 100% segment. Soft just below. Say whether landing just below by pinch is a trap | DR6 |
| M7 | **Histogram and curve.** During a drag at 100% both hold, never blank or dim, and catch up on a pause. A pan leaves them alone. At Fit they stay live | DR7 |
| M8 | **VoiceOver.** Nothing is announced at the swap, the slider speaks its value, the spinner reads its label, the canvas value is unchanged | DR8 |
| M9 | **Ruling 8 on the Dell** (maximized, sidebar and inspector showing, typical stack). An Amount drag reads as continuous at 6 to 7 frames a second. No spinner at the end of the drag. A brush stroke at 100% still feels attached to the pointer. If it doesn't, that is the follow-up already in `status.md`, not a redesign | — |
| M10 | **HDR** (EDR display, after F4). During a drag at 100% the caption has no HDR badge. It returns when the HDR rendition lands | — |
| M11 | **Maps** (after F3). At 400% a refined sharpening map and fringe map show blocks, as on `develop` | — |

qa-tester can script part of M1 and M3 with `print viewport` (`tile`, `spinner`).
The rest needs a person.

**Next step.** The engineer fixes F1 to F5 and updates `status.md`. I then
confirm the fixes in this file.
