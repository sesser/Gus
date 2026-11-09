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

## Verdict (third pass, 2026-11-09)

**The design review passes. F1 to F5 and N1 are fixed in the code, and no design
finding is open.** Nothing has been seen on screen, so the manual checks below
remain. One known limitation (L1) stays, with a Requirements issue for the product
manager (RI-D1); neither holds this review. See "Third pass".

The first pass found the build not ready to merge, because of F1 (raw White
Balance, Profile and Noise Reduction stopped following the hand) and F2 (the
spinner appeared in the two cases §2.1 excludes). Everything else matched the
design: both hints, the guide paragraph, the tile layer's filters and animation,
pixel alignment, the histogram, and "covered" agreeing with the toolbar.

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
| DR2 | **Pass by code (second pass); look on screen** | The base uses nearest-neighbor at 1 and above only for `.full`, `.hdrFull`, and the maps and replaced fringe slot that A4 keeps (`LiveFrameRules.usesNearestFiltering`); photo live frames, previews and placeholders are smooth. `updateFiltering` follows every rendition change. The tile is always real pixels (`LiveRegionRenderer.region` is whole output pixels), so its nearest filter is right |
| DR3 | **Pass by code (third pass), with L1; look on screen** | Correct by code: the 0.5 s from the last input, one spinner, last in `spinnerLabel`, off when input resumes, off for maps and crop, the R4 row (F1 fixed), the §2.1 exclusions (F2 fixed) and the wait after letting go (N1 fixed). L1 is why that last wait can't show a spinner yet |
| DR4 | **Pass by code; macOS 27 on screen** | The machine learning flag comes before the new one in `spinnerLabel`, and its wait is unchanged. F1 also applies to a Luminance drag with machine learning on |
| DR5 | **Pass by code; look on screen** | `tileLayer.actions` turns off `contents`, `bounds`, `position` and `hidden`, and `setTile` disables actions. The tile sits on whole output pixels in a view sized to the output (`matchFrame(toOutput:)`), so it lines up by construction. Only a person can confirm the soft base lines up with it |
| DR6 | **Pass by code; look on screen** | Covered is `magnification >= 0.99` and the toolbar is within 1% of 100%. A photo whose Fit is already 100% is covered |
| DR7 | **Pass by code; look on screen** | Region frames never feed the histogram. A drag takes the `regionShown, next.interactive` path with no whole frame, and the pause renders one. The inspector and the curve backdrop both read `editor.histogram`, which is cleared only when the photo closes. A pan renders no whole frame |
| DR8 | **Pass by code; VoiceOver on screen** | No announcement added, the canvas value is unchanged, and the spinner keeps `.accessibilityLabel` |
| DR9 | **Pass** | The paragraph is before **Sharpening Map**, the keys table says "100%", and "sharp frame", "live frame", "draft" and "viewport" appear nowhere in the guide |

**PRD criteria that touch the UI.**

- R4 while moving: failed on the first pass (F1), fixed by code on the second. No
  criterion catches it, because AC6 checks only the pause, so M1 covers it.
- AC7 (R5), AC8 (never blank: the tile is always over a base, and `setTile(nil)`
  never clears the base) and AC11: pass by code.
- AC1–AC3, AC5, AC9, AC10 and AC12–AC14: the evidence is in `status.md`, and
  nothing in the UI contradicts it. They are QA's.

**HIG.** Progress indicators, Motion and Writing are honored as `design.md`
applied them. Nothing is on the glass layer, and there is no custom chrome.

## Findings for the engineer (first pass)

| # | Severity | Finding | Fix |
|---|---|---|---|
| F1 | **High, blocks merge** | **R4 frames don't follow the hand once a sharp frame exists.** `editor.regionFrame` is never cleared during an R4 drag. In `showLiveFrame` (`LoupeView.swift:427–437`) each revision shows that old tile again, then returns early whenever the whole frame isn't of the current values. While the hand moves, a 127 ms frame never is. So the picture stays on the old sharp frame with the old values for the whole drag. When the hand hesitates a soft frame shows and the tile comes down; the next revision puts the old tile back, which reads as a flicker to old values. It happens after any earlier sharp frame, including "drag, hold until sharp, drag again", the natural next step after the PRD's Raw noise reduction scenario. It breaks `design.md` §2's R4 row, §3's "sharp to soft when R4 input resumes", and R6's "a value or two behind". M1 in the PRD would hit it | When a moving frame can't be a region frame (`isReady` false and `next.interactive`), drop the tile, for example by clearing `regionFrame` in that branch. Keep the guard for what it was meant for: an old whole frame landing during a drag whose tile is still being updated. Script check: after a sharp frame exists, `adjust scrub` White Balance and read `print viewport` mid-drag; it should say `tile none` |
| F2 | **Medium, blocks merge** | **The spinner appears when nothing changed.** `refreshSharpFrameWait` has no test for a change under way, and `sharpFrameIsOnItsWay` counts `regionPrepareTask` and `renderTask`. **`Z` from fit:** `setLoupeViewport` starts the prepare and arms the wait, so the spinner shows if the 150 ms pause plus the decode passes 0.5 s (masked stacks, machine learning, slower raws). It ends when the texture is ready, with no change on screen. **Arriving at a photo at 100%:** `AdjustmentEditor.swift:398–402` starts the prepare and the 250 ms histogram frame, and arrival doesn't count as input, so the delay can be zero and the spinner can flicker on each arrow key. §2.1 excludes both, and arriving is the culling path | Require a change under way in both places (`showsLive \|\| loupeAwaitsFullRendition`). Call `refreshSharpFrameWait` when `loupeAwaitsFullRendition` turns on as well as off, because today a race can miss the wait after an R4 commit. Call `noteInput()` in `catalogChanged`: Undo is "a value", and without it the delay is zero |
| F3 | Low | **Maps and the fringe slot preview lost their blocks at 100% and above.** They arrive as `.live`, so `updateFiltering` now smooths them. Before this branch they used nearest-neighbor at 1 and above. A4 and §2.2 keep them as shipped, and a refined map at 400% is real pixels | Keep nearest at 1 and above for what `canRenderRegion` excludes: a frame whose `content.isMap`, or the replaced-slot preview |
| F4 | Low | **The HDR badge stays during a drag.** `showTile` doesn't clear `loupeHDRHeadroom`, and interactive region frames return before line 449 does. On an EDR display the tile is standard range while the caption still says HDR until the pause. A4 says standard range during a live change, and today the badge goes with the first live frame. The caption must not claim what isn't on screen (SMP §5) | Clear the headroom when a tile of a change under way goes on screen |
| F5 | Low | **Three small gaps in "what was asked for" and "on its way".** (a) After `regionRenderer` is cleared (a photo over 16384 px, a failed decode), a whole-frame render still counts as on its way, so the spinner promises detail that isn't coming. (b) `sharpFrameIsOnScreen` ignores the overlay, unlike the render loop's `hasOverlay` test. (c) `loupeAwaitsFullRendition` clears only when `.full` lands, so a failed load, or a small photo at Fit (`zoom == .fit` starts no load), leaves it set | (a) Require `regionRenderer != nil` for the frame cases. (b) Compare `hasOverlay`. (c) Clear it where the load fails or isn't started |

## Second pass: the fixes in `3900e45`

I read the files on the branch at `e6dd936`, which is `3900e45` plus one commit
titled "Note that covered zooms have no memory cap for now". I have no shell, so
I did not use `git show`, and I still have not built or run anything. These
results come from the code; the script results in `status.md` are the engineer's.

| Finding | Status | What the code does |
|---|---|---|
| F1 | **Fixed by code; M1 on screen** | A whole frame standing in for the region sets `regionFrame = nil` just before `show(rendered)` (`AdjustmentEditor.swift:1282`), and `showLiveFrame` no longer returns early. White Balance, Profile and Noise Reduction change their decode settings on every frame, so `shouldDecode(whileMoving:)` stays false and they wait for the pause. **§3:** `setTile(nil)` and `setImage` run in one pass of `updateNSView`, so they reach the screen together, with no empty or stale moment between them. The layer's actions stay off. The whole frame fills the view and resizes it only on an aspect change over 1%, so nothing moves. Whether soft and sharp frames line up at a fine edge is M5 |
| F2 | **Fixed by code, one gap (N1); M3 on screen** | `sharpFrameWaitApplies` (`AdjustmentEditor.swift:1083–1086`) needs `showsLive \|\| loupeAwaitsFullRendition`, and the timer tests it again when it fires. Arriving at a photo and `Z` from Fit with nothing changing set neither, so the prepare and the histogram frame no longer start it. It still applies when an R4 control is held still, after a heavy edit's last value, on a pan during a change, on a hover, on Show Original turned on, and on a pan while a sharp frame of the saved values waits for the full rendition. `noteInput` is in `catalogChanged`, and the flag re-evaluates when it turns on. Undo at 100% loads as today unless a live frame was on screen; R6 doesn't name it, so I accept that |
| F3 | **Fixed by code; M11 on screen** | `LiveFrameRules.usesNearestFiltering` keeps nearest at 1 and above for `.live` frames that are maps or the replaced slot's preview, and linear below 1, as on `develop`. Photo live frames stay smooth and `.full` and `.hdrFull` stay nearest, so §2.2 holds for the photo and A4 for the rest |
| F4 | **Fixed by code; not seen (M10)** | `showLiveFrame` clears `loupeHDRHeadroom` on every live revision (`LoupeView.swift:431`), and `display` of an HDR rendition sets it again (`:537`). The tile no longer returns over the HDR rendition (`:416`, code review C6) |
| F5 | **Fixed by code** | (a) `sharpFrameIsOnItsWay` needs `regionRenderer` for the frame cases. (b) `sharpFrameIsOnScreen` uses `LiveFrameRules.isCurrent`, with the overlay's mask. (c) The flag is cleared where no load starts or it fails (`:579`, `:584`, `:598`) and isn't set at Fit |

DR1 and DR9 still pass. §3's tile layer and §4 are unchanged.

**New.**

| # | Severity | Finding | Fix |
|---|---|---|---|
| N1 | Low, **fixed (third pass)** | **No spinner for the wait after letting go when no sharp frame of the saved values exists.** `LoupeView.swift:411–412` now sets `loupeAwaitsFullRendition` only when `regionFrame` holds the saved values. Let go of White Balance, Profile or Luminance without a pause, and if the whole frame and the save land before the region decode, `regionFrame` is nil, `showsLive` goes false and the flag stays false. The soft frame then stays until the full rendition lands (656–867 ms, E4) with no spinner. The same happens when Show Original is turned off and the full rendition isn't cached. §2's table lists "just after letting go". The clause isn't needed for C6, because line 416 tests the tile's values itself | Remove `&& editor.regionFrame?.adjustments == editor.savedAdjustments` from line 412 and keep the `zoom == .actualSize` test |
| N2 | Info, no fix asked | **The first drag on a photo can blink soft.** When no sharp frame exists yet (usual after arriving at 100% or `Z`), the first live update puts the older whole frame on the base, over the full rendition, before the first sharp frame lands (about 150 ms on the Dell). R6 allows a soft first frame and `develop` did the same, so it isn't a violation. M5 judges it. If it reads as a blink, the fix is to keep the full rendition until a new frame exists | None for now |

Also for the record: on a raw, Exposure or Highlights crossing 0 can go soft for a
few frames mid-drag while its one decode runs (`status.md`, C4). The owner allowed
it (ruling 9) and §2's no-mark rule applies. The guide's "can look soft for a
moment" is still true.

**The mask handles (code review's design question).** Layer order is settled, and
one look remains. The tile joins the image view's layer in `init`, before
`imageView.addSubview(maskView)` (`LoupeView.swift:202`). `MaskOverlayView` has its
own layer, and nothing in the app sets `zPosition`, re-adds that view or uses
`canDrawSubviewsIntoLayer`. `layers tile,view` confirms both halves: the mask view
has a separate layer, and the tile is under it. It can't show the composited
picture, or the order after a later pass by AppKit, which as far as I know makes
no promise about a sublayer added by hand to a layer-backed view (my judgment).
So it stays a manual check, M12, at low risk.

**HDR.** F4 is confirmed from the code only, because no HDR photo was run. All of
M10 stays manual, on a display with extended dynamic range. Accepted: a pan during
a tile-only drag can show the HDR base beside the standard-range tile for a moment,
until the pause's frame replaces it. It is rare and brief, and R6 allows it.

## Third pass: N1 in `8b27864`

I read the files on the branch at `105cfa7`, which is `8b27864` plus a commit titled
"Record the second-pass reviews and ruling 9 on mid-drag decodes". As before: no
shell, no build, nothing run.

**N1: closed, fixed in the code.** The finding was that the wait for the full
rendition wasn't set when no sharp frame of the saved values existed. The clause is
gone (`LoupeView.swift:411`), so the flag now depends only on being covered at
`zoom == .actualSize`. The tile's own test at `:415` is unchanged, so code review's
C6 still holds. A live revision that cancels the load clears the flag (`:430`), and
the next save sets it again. The engineer's script shows the wait count rising.

**L1: known limitation, not a finding against this branch.** After letting go with
no sharp frame on screen, the soft frame can last until the full rendition is drawn,
with no spinner. I confirmed the cause from the code:

- `fullResolutionImage` calls `generator.cgImage`, and `RenderEngine.makeCGImage`
  uses `createCGImage` without `deferred: false`.
- `DecodedImage(cgImage:)` only stores the image, so nothing reads the pixels before
  `display` hands it to the layer.
- `display` clears the wait at that hand-off, well under the 0.5 s. The render then
  happens at the layer's first draw (656–867 ms at 24 MP, E4).

I close N1 and don't hold it open for this, for three reasons. The cause is a
different path, outside this branch and already on `develop`. A spinner couldn't help
while that first draw runs on the main thread, because neither its timer nor its
drawing would get a turn. And once the render moves off the main thread, the wait
lasts as long as the render and §2.1 applies with no further change. §2.1 stands as
the intended behavior. The picture is never blank, and a sharp tile, where one
exists, stays on screen through the draw, so the limitation only shows after a raw
control is released with no pause, or after Show Original is turned off with the
full rendition uncached.

## Requirements issues

**RI-D1, for the product manager (the owner if it's theirs): does R8 cover the first
draw of the full rendition after letting go?** R8 says the window never blocks. By the
code path above, the full rendition's render runs inside the layer's first draw. On
the main thread that would stall the window for about 0.7 to 0.9 s at 24 MP after
letting go at 100%, on every control, and likely longer with machine learning on
(R5). `status.md` records the same mechanism in a main-thread sample for the map.
It hasn't been measured for the full rendition, and M13 gets that evidence. AC10
covers only scripted value changes, so nothing tests this. It is on `develop` too,
and this branch doesn't make it worse.

- **Proposed default:** R8 doesn't hold this branch. Add a bug-fix row to the roadmap
  (none exists) to read the full rendition's pixels off the main thread, the
  `deferred: false` change the engineer proposes for the map's input and notes in
  `status.md`. `CLAUDE.md`'s concurrency rule already asks for images to be decoded
  before they reach layers. That fix also makes L1's spinner visible.

Ruling 8 needs no design change, and RI2 (photos above 24 MP) has no UI consequence.

## Manual checks

Current after the third pass. These need the bundled app, active, on a real 24 MP
raw on the owner's Mac unless noted. The PRD's M1 is separate and stays with the
owner.

| # | Check | DR |
|---|---|---|
| M1 | **R4 while moving.** At 100%: drag White Balance, hold until the detail arrives, drag again. The picture follows the hand softly throughout, and never freezes or pops back to older values. Same for Profile and Luminance. Exposure crossing 0 may go soft for a few frames, then stays sharp | DR3 |
| M2 | **Soft looks soft.** At 100% and 400%, a White Balance drag and the moment after a pan are smooth with no blocks. At 400% a settled photo shows real pixels as blocks | DR2 |
| M3 | **Spinner.** None during any drag. With White Balance held still, it shows only if the detail takes more than 0.5 s, and goes when the detail lands or movement resumes. Tooltip "Refining the photo". None when arrowing through raws at 100%, and none on `Z` from Fit, including a photo with machine learning on and a masked photo. Known limitation L1: after letting go with no pause the spinner doesn't appear, and that is not a failure (M13) | DR3 |
| M4 | **Machine learning** (macOS 27). One spinner with its own label, the last frame stays, the window responds | DR4 |
| M5 | **The swap.** No fade and no shift, soft to sharp and back, with Reduce Motion on and off. The soft frame lines up with the sharp one at a fine edge, near the center and near a corner. Also N2: does the start of the first drag on a photo read as a blink? | DR5 |
| M6 | **The 100% boundary.** Real pixels at 100% by `Z`, the toolbar, ⌘=, and a pinch that selects the 100% segment. Soft just below. Say whether landing just below by pinch is a trap | DR6 |
| M7 | **Histogram and curve.** During a drag at 100% both hold, never blank or dim, and catch up on a pause. A pan leaves them alone. At Fit they stay live | DR7 |
| M8 | **VoiceOver.** Nothing is announced at the swap, the slider speaks its value, the spinner reads its label, the canvas value is unchanged | DR8 |
| M9 | **Ruling 8 on the Dell** (maximized, sidebar and inspector showing, typical stack). An Amount drag reads as continuous at 6 to 7 frames a second. No spinner at the end of the drag. A brush stroke at 100% still feels attached to the pointer. If it doesn't, that is the follow-up already in `status.md`, not a redesign | — |
| M10 | **HDR** (display with extended dynamic range; an HDR photo has not been run). During a drag at 100% the caption has no HDR badge. It returns when the HDR rendition lands. After that, a rating key doesn't bring the standard-range tile back over the HDR image | — |
| M11 | **Maps and the replaced fringe slot.** At 400% a refined sharpening map, a fringe map and the preview while replacing a pick show blocks, as on `develop` | — |
| M12 | **Mask handles over the tile.** At 100% with a linear or radial mask selected, the handles stay visible over the sharp frame during and after a drag, after resizing the window, and after entering and leaving review. The brush cursor too | — |
| M13 | **After letting go (L1, RI-D1).** At 100%, let go of White Balance with no pause, then of Amount, and press an arrow key or try to pan within the next second. Record how long the soft frame stays after White Balance, whether the window stalls or the spinning cursor appears after either, and the same with machine learning on (macOS 27). The photo never goes blank, and after Amount the sharp frame stays until the full rendition replaces it. The stall figures go to the product manager for RI-D1 | DR3 |

qa-tester can script parts of these with `print viewport` (`tile`, `spinner`,
`layers`, `nearest`, `fullWaits`) for M1, M3, M11, M12 and that the wait is set in
M13, and `snapshot` of the content area for M12. The rest needs a person.

**Next step.** No design fix is waiting. `8b27864` changed source, so it needs its
second pass from code-reviewer if that isn't done. The product manager takes RI-D1,
and qa-tester runs last and carries these checks into `qa.md`.
