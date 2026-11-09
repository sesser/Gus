# Sharp live frames at 100%

Status: Approved
Slug: viewport-render-1to1
Roadmap: Now

## Problem

A photographer setting sharpening, noise reduction or any other fine-detail
control zooms to 100% to see the actual pixels. While a value changes, the
loupe doesn't show them. It shows a *live frame*, the image it draws while a
value is changing, and that frame is the whole photo at 2560 px, enlarged
(2.3× for a 6000 px photo).

- RAW white balance, profile and noise reduction are softer still while they
  move. Each new value decodes the file at half that size: 1280 px, or 4.7×.
- Holding the mouse still doesn't help, because the refinement on a pause is
  also 2560 px. Only letting go, and the save, brings the sharp image back.
- Show Original, the red mask overlay and preset and look-up table hover
  previews use the same soft frame. So before/after at 100% compares a soft
  "before" with a sharp "after".

The loop today is to guess a value, let go, wait, inspect and repeat. The
Adjust tab says as much: "Judge Amount, Radius and Detail at 100% (Z) once the
change is saved."

Why now: the owner put it in Now on 2026-11-06. Each recent detail feature
(`sharpen-mask-preview`, `ml-denoise`, `chromatic-aberration`) accepted this
limit and left it to this item.

The behavior above comes from reading the code and
`docs/archive/PHASE6_PLAN.md` ("The loupe at 100 %"). It was not measured on
screen.

## Goal and success

At 100% and above, what a person sees while a value changes is the photo's
real pixels with that value applied, so detail can be judged without letting
go.

It worked if:

- on a 24 MP raw at 100%, after a first moment that may be soft (R6), dragging
  Sharpening's Amount shows the sharpening changing in sharp pixels, and the
  image that settles after letting go looks the same as the drag's last frame;
- the speed target in R7 is met and recorded;
- after it ships the owner re-judges the sharpening and noise reduction
  sliders at 100%, and issue #35 is closed or gets its own row (ruling 7).

## Owner rulings (2026-11-09)

The owner's answer to the seven intake questions, relayed by the main session:
"Defaults are fine". That covers the questions and their defaults. The owner
confirmed the Assumptions below separately, the same day.

1. **Sharp while moving.** Every frame at the covered zooms is real pixels. If
   an edit is too heavy, frames come less often but stay sharp. If that can't
   meet the target in ruling 4, the engineer brings it back to the owner
   rather than quietly switching to sharp-on-pause.
2. **Zooms.** 100% and above.
3. **Moments.** Everything that shows a live frame at those zooms: sliders,
   curve, color wheels, mask handles, brush strokes, hover previews, Show
   Original, the red overlay. RAW white balance, profile and noise reduction
   may stay soft while moving but must be sharp once input pauses. Machine
   learning noise reduction keeps the ruling that smooth dragging isn't
   required.
4. **Speed.** A typical stack at 100% in the largest normal window: 95% of
   frames under 100 ms, and the window never blocks. Three masks are measured
   and recorded with no target. Reference: M4 Pro, 24 MP raw, largest window
   on the owner's usual display.
5. **When the sharp image isn't ready.** Never blank. The part not ready may
   be soft and a value or two behind for a moment.
6. **Histogram.** It stays whole-photo and may lag during a drag, updating
   when input pauses.
7. **Issue #35** stays separate and this feature changes no slider's
   strength. After it ships the owner re-judges at 100%, and #35 is closed or
   gets its own row. `classical-noise-strength` stays as it is.

## Users and scenarios

- **Primary.** At 100% on a 24 MP raw, the person drags Sharpening's Amount
  from 40 to 90, watching a fine edge. After a first moment that may be soft
  (R6), every frame is sharp. They let go, and once it settles the photo looks
  the same as the drag's last frame.
- **Heavy edit.** Three masks with Clarity, same drag. Frames come less often
  but stay sharp, and the window keeps responding.
- **Before and after.** At 100% they press Show Original. The "before" is as
  sharp as the "after".
- **Raw noise reduction.** They drag Luminance. Frames are soft while it moves.
  They hold still with the mouse down, and moments later the frame is sharp
  without letting go.
- **Edge: a pan just after letting go.** The area coming into view is soft for
  a moment, never empty, and then sharp.
- **Edge: back to fit.** After an edit at 100%, they press Z and see the
  photo with the new edit.

## Requirements

Terms:

- **Covered zooms:** a displayed zoom of 100% or more, however it was reached.
  At 100%, one photo pixel is one screen pixel.
- **Sharp frame:** what is visible is made from the photo's full-resolution
  pixels at the photo's own scale, with the current values applied. Above
  100%, those pixels enlarged.
- **Pause:** no input for about 150 ms (assumption A7).

A requirement marked "rests on A*n*" follows from an assumption rather than a
ruling. The owner confirmed all the assumptions on 2026-11-09. See Assumptions.

R1 (Must, ruling 2): At covered zooms, every live frame is a sharp frame,
except where R4, R5 and R6 allow otherwise. Below 100% nothing changes,
including how fit behaves today.

R2 (Must, ruling 1): An edit too heavy to keep up gets fewer frames, not
softer ones. No reduced frame stands in while a value moves at covered zooms,
except where R4, R5 and R6 allow it. The next frame shows the newest value.

R3 (Must, ruling 3): R1 applies to everything that shows a live frame at
covered zooms:
- every slider, by any input it accepts (drag, keyboard, typed value);
- the tone curve and the color wheels;
- mask handles and brush strokes;
- hover previews of presets and look-up tables;
- Show Original;
- the red mask overlay.

R4 (Must, ruling 3): RAW white balance, profile and classical noise reduction
may be soft while the value moves. Once input pauses, with the control still
held, the frame is sharp.

R5 (Must, ruling 3, and `ml-denoise` ruling 5): With machine learning noise
reduction, smooth dragging is not required. Any wait shows progress as it does
today and never blocks the window. The result is a sharp frame once it is
ready.

R6 (Must, ruling 5): The loupe is never blank. When a sharp frame or part of
one isn't ready (a pan, a zoom, the first frame of a drag, just after letting
go), the part not ready may be soft and a value or two behind for a moment. A
sharp frame with the current values then replaces it with no further input.

R7 (Must, ruling 4): For a typical stack at 100% in the reference window, 95%
of frames take under 100 ms. The reference is an M4 Pro, a 24 MP raw and the
largest window on the owner's usual display. The same measurement with three
masks is recorded, with no target. If the target can't be met, the engineer
returns it to the owner as a requirements issue. Sharp-on-pause is not a
fallback unless the owner chooses it (ruling 1).

R8 (Must, ruling 4): The window never blocks. During a slow frame, panning,
zooming, menus, keys and other controls keep responding.

R9 (Must, ruling 6): The histogram always describes the whole photo, never
only the visible part. During a value change at covered zooms it may lag. When
input pauses it shows the current values.

R10 (Must, ruling 7): No slider's strength changes.

R11 (Must, existing rule): A change still saves once per gesture and is one
undo step.

R12 (Must, rests on A1): A sharp frame matches what appears after letting go:
the same area of the full-resolution render of the same values, within a
tolerance the engineer derives and states. That includes everything that
depends on the whole photo (masks, local tone, dehaze, Color Alignment,
vignette, grain).

R13 (Must, rests on A2): After an edit at covered zooms, going back to fit, the
film strip and the grid show the new edit.

R14 (Must, rests on A3): Saved renders, exports and cached previews don't
change. No pipeline version bump, and no golden moves.

## Acceptance criteria

**The frame-by-frame check** (used by AC2, AC3 and AC4). R6 lets a change start
soft, so the first frames are not held to R1. The script changes a control
outside R4 and R5, with no pan or zoom, and keeps going until a sharp frame has
landed and at least ten more frames have followed.

- Allowed: the first frame may be soft or sharp, and so may any frame before
  the first sharp one.
- Pass: every frame from the first sharp one to the end is sharp.
- Fail: a soft frame after the first sharp one, or no sharp frame within a
  timeout stated in `status.md`.
- The time from the start of the change to the first sharp frame is recorded
  in `status.md`, with no target (A8).

Pans, zooms and letting go are checked by AC8, not here.

AC1 (R1, R12): Test on a synthetic 6000 × 4000 scene with one-pixel detail and
a typical stack, at the center and at a corner, uncropped and with a crop and
straighten. The frame for the visible area at 100% equals the same area of the
full-resolution render, within the engineer's stated tolerance, and the
one-pixel detail survives.

AC2 (R1): Debug-script check at 100%, 200% and 800%: the frame-by-frame check
passes at each zoom. At fit and 50%, frames behave as before, and the existing
draft tests pass unchanged.

AC3 (R2): Test or debug-script check with three masks with Clarity at 100%:
the frame-by-frame check passes on a scripted drag, so no frame after the
first sharp one is reduced. Fewer frames are allowed.

AC4 (R3): Debug-script or manual check at 100%, one line per moment in R3:
- For what moves over many frames (a slider drag, the curve, a wheel, a mask
  handle, a brush stroke): the frame-by-frame check passes. For a control
  under R4 or R5, AC6 or AC7 applies instead.
- For a one-off change (a keyboard step, a typed value, a preset hover, a
  look-up table hover, Show Original, the red overlay): the first frame after
  it may be soft (R6). Once no frame is pending, the frame on screen is sharp
  and has the current values.

`qa.md` says which moments only a person can check.

AC5 (R3, R12): At 100% with Show Original on and no frame pending, the visible
area equals the same area of the full-resolution render with no adjustments,
within the stated tolerance.

AC6 (R4): Debug-script check at 100% for RAW white balance, profile and
Luminance. After a scripted change with no commit and then a pause, the frame
reports as sharp and matches R12. The time from pause to sharp frame is
recorded in `status.md`.

AC7 (R5): On macOS 27 with a supported raw, at 100%. A change to Luminance
with machine learning on keeps the window responding, shows progress when the
wait passes today's threshold, and ends in a sharp frame. Skipped where macOS
27 isn't available, as `ml-denoise`'s tests are.

AC8 (R6): Debug-script snapshots of the content area at 100%: at the start of
a value change, during a pan, during a zoom, and in a pan right after a commit.
None has an empty area. After waiting with no input, the content area matches
R12.

AC9 (R7): `photobench`, release build, M4 Pro, 24 MP raw, typical stack (as in
`docs/PROFILING.md` Phase 3), at 100% in the reference window: 95% of frames
under 100 ms. `status.md` records the Mac, the window's size in pixels, the
figures, and the same run with three masks (as in `photobench masks`).

AC10 (R8): With a stack whose frames take over 100 ms at 100%, during scripted
value changes, a key (next photo, a rating) is handled while a frame renders,
the check `ml-denoise` AC8 used. Manual: no spinning cursor during a real drag.

AC11 (R9): At 100% after a pause, the histogram equals the whole photo's at the
same values, within a stated tolerance. Panning to an area of different tone
leaves it unchanged.

AC12 (R10, R14): The existing goldens pass unchanged, and
`PreviewCacheKey.currentPipelineVersion` is unchanged.

AC13 (R11): After a drag at 100%, the stack was written once and one Undo
restores the previous value.

AC14 (R13): Debug-script check: at 100%, change Exposure, commit, and go to fit
at once. After it settles the loupe shows the new edit, and the cached preview
and grid thumbnail are of the new edit's hash.

M1 (R1, R4, goal; owner): on a real 24 MP raw at 100%, drag Amount, Radius,
Detail and Luminance. A soft moment at the start of a drag or around letting
go is allowed (R6). For Amount, Radius and Detail, detail can be judged as the
value changes. For Luminance, it can be judged once input pauses with the
control still held (R4). For all four, the image that settles after letting go
looks the same as the last sharp frame.

## Non-goals

- Zooms below 100%, including the softness between fit and 100%. A drag at 99%
  stays soft while one at 100% is sharp, and that step is accepted (ruling 2).
- Changing any slider's strength (ruling 7). That is issue #35 and
  `classical-noise-strength`.
- Sharpening at fit matching full size (`sharpen-masking-scale`).
- Smooth dragging with machine learning noise reduction (ruling 3).
- Crop sessions, and HDR frames during a live change (A4).
- The sharpening map, the fringe map and the fringe slot preview: they keep
  their shipped behavior (A4).
- New controls or settings. None is expected.

## Dependencies and impact

- **Live editing.** Frames, drafts and the stage cache all work on the whole
  photo today (`LiveRenderSession`, `AdjustmentEditor`, the loupe).
  `docs/archive/PHASE6_PLAN.md` "Roadmap" has the original note.
- **Speed baselines.** Apple M4 Pro, release build, a 6000 × 4000 DNG, 2560 px
  frames, from `docs/PROFILING.md` Phase 3 and `PHASE6_PLAN.md`:

  | Case | Mean | p95 |
  |---|---|---|
  | Typical stack, next frame | 36 ms | 43 ms |
  | RAW white balance (half-size decode) | 87 ms | 104 ms |
  | Three masks, whole frame | 141–167 ms | 173–197 ms |
  | Three masks, cached | 23–35 ms | 32–130 ms |

  With machine learning on, a 24 MP decode takes about 1.4 s
  (`ml-denoise/status.md`). The app already treats a live frame over 100 ms as
  too slow (`draftDropThreshold`), which is where R7's number comes from. The
  repo has no measurement of how long today's sharp render takes after letting
  go.
- **Window size warning.** The phase 6 note assumed a 1500 × 1000 view, about
  1.5 MP. A full-window loupe on a 5K display is roughly 10 MP against today's
  4.4 MP frame (my arithmetic, not a measurement), and radii render at full
  size. So R7 can't be assumed easy.
- **Memory.** Holding a full-resolution decoded photo costs about 192 MB at
  24 MP (`sharpen-mask-preview/prd.md` Q5), plus whatever caching adds. Larger
  photos need checking.
- **Limits on R12's tolerance.** Two crops of the same photo differ by up to
  2.9 × 10⁻³ at patch edges (`PHASE6_PLAN.md` finding 2), and one filter gives
  region-dependent edge pixels on macOS 26 (finding 6).
- **Cached previews.** Today the last whole frame becomes the new edit's cached
  preview. A frame of only the visible part can't do that, and R13 has to hold
  under the stale-preview rule (`stale-preview-after-save`).
- **Precedents.** The sharpening map and the fringe slot preview show an
  estimate and then refine zoomed in. `chromatic-aberration` ruling 13 accepted
  soft drags for its own sliders until this item; R3 now covers them.
- **Checking it.** The criteria need a test or script to tell whether the frame
  on screen is sharp. `sharpen-mask-preview` shipped without that for its
  refined frame (roadmap `qa-test-gaps`).
- **Issue #35.** After this ships the owner re-judges at 100% (ruling 7). Ship
  records that as a follow-up.
- `docs/USER_GUIDE.md` is updated with the behavior, and any new strings go in
  the String Catalog. No catalog migration, edit-stack change or sidecar change.

## Assumptions

The owner confirmed all of these on 2026-11-09, relayed by the main session
after A1–A9 were listed: "Yes, as written".

- **A1.** What a drag shows matches what appears after letting go, within a
  tolerance the engineer derives.
- **A2.** After a zoomed edit, going back to fit shows the new edit.
- **A3.** Saved renders, exports and previews don't change: no pipeline bump,
  no golden moves.
- **A4.** HDR photos stay as they are today (standard range during a live
  change), and crop sessions are out of scope. The sharpening map keeps its
  shipped behavior. So do the fringe map and fringe slot preview, which shipped
  after intake and which the rulings don't mention.
- **A5.** The memory cost under Dependencies is acceptable at 24 MP. Larger
  photos are checked, and a problem comes back as a requirements issue.
- **A6.** The Adjust tab hint needs rewording, and that is the designer's job.
- **A7.** "Pause" is the editor's existing one, about 150 ms without input.
- **A8.** No numeric limit applies to "a moment" in R6 or to the time to sharp
  after a pause in R4. Those times are recorded, not targeted.
- **A9.** "Typical stack" is the one `docs/PROFILING.md` Phase 3 defines, and
  `photobench`'s synthetic 6000 × 4000 DNG counts as the 24 MP raw.

## Open questions

**Owner:** answered 2026-11-09. A1–A9 are right as written, A4's fringe items
included.

**Designer:**

- D1. The Adjust tab hint, "Judge Amount, Radius and Detail at 100% (Z) once
  the change is saved. Sharpening Map shows Masking's effect at any zoom.", is
  no longer true as written. Reword it or remove it. The Grain hint still says
  "1:1" where the View menu says 100%.
- D2. Whether anything on screen, or anything VoiceOver says, should mark a
  frame that is soft or still sharpening (R4, R6). The app has a caption
  spinner after 0.5 s for the refining maps. Expected: no new UI.
- D3. Whether the swap from soft to sharp needs any treatment.

**Engineer:**

- E1. Which display is the reference. The owner gave none, so record the window
  size used. Also record a roughly 10 MP case, so the result doesn't depend on
  the test Mac's display.
- E2. The tolerance for R12, AC5 and AC11.
- E3. Whether R4 and R5 can reach a sharp frame at acceptable cost, and the
  memory cost above 24 MP. A problem with either comes back as a requirements
  issue.
- E4. Today's time from letting go to the sharp render, as the baseline for R6.

## Revisions

- 2026-11-09: AC2, AC3, AC4, AC5, M1, the Primary scenario and the goal's first
  bullet now allow what R6 allows (a soft start and a soft moment around
  letting go), and M1 what R4 allows for Luminance. Added the frame-by-frame
  check, which says how the first frame is treated. No requirement changed.
- 2026-11-09: The owner confirmed A1–A9 ("Yes, as written"). Status is
  Approved. No requirement changed.
