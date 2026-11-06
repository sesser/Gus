# Sharpening mask preview

Status: Shipped 2026-11-05, PR #37. Manual checks M1–M9 are still open by the owner's choice; see review.md and status.md.
Slug: sharpen-mask-preview
Roadmap: Shipped

## Problem

A photographer tuning Sharpening wants edges crisp without sharpening the
noise in skies, skin and other smooth areas. Masking does this: since PR #36
(issue #35) it holds sharpening back wherever a pixel's neighborhood contrast
is below a threshold. But Masking changes *where* sharpening goes, not what
the photo looks like at a glance. At fit-to-window its effect is invisible,
and even at 1:1 the user has to compare small regions before and after. Today
they guess a value, zoom to 1:1, wait for the save to reload the full render
(the Adjust tab's hint says so), inspect, and repeat.

## Goal and success

While setting Masking, the user can see which parts of the photo get
sharpened and which are held back, updating as the value changes, without
the preview ever ending up in the photo, its history or its caches.

It worked if a photographer can set Masking on a noisy high-ISO photo so
that the sky gets no sharpening and the subject's edges do, in one pass,
without zooming in and out to check.

## Users and scenarios

- **Primary:** at fit, the user shows the sharpening mask and raises Masking.
  Smooth areas drop out first, then fine texture, until only strong edges
  are left. They stop where the sky has dropped out and the subject's edges
  remain, go back to the photo, and see the result.
- **Keyboard or VoiceOver user:** shows the mask, changes Masking with
  keyboard increments, and hides the mask again, without a pointer or a held
  modifier.
- **Zoomed in:** at 100% or more, after the user stops changing the value,
  the mask matches what a full-size export would sharpen (R6).
- **Edge:** a photo with local masks and the red mask overlay on. Showing the
  sharpening mask replaces the overlay. Hiding it brings the overlay back.

## Requirements

R1 (Must): In the loupe, the user can switch the display from the photo to
the sharpening mask. For every pixel the mask shows how much of the
sharpening Masking lets through, from none to full. Full and none are
distinguishable at a glance, and partial amounts read as in between. The
representation is the designer's. The owner's starting point is grayscale,
with white for full and black for none.

R2 (Must): While the mask is shown, it updates as Masking changes, by any
input the slider accepts (drag, keyboard, typed value), at the same cadence
as the photo's live frames today. It does not update only on release.

R3 (Must): Showing and hiding the mask needs neither a held modifier nor a
pointer: it works from the keyboard alone, and VoiceOver announces the
control's name and on/off state. A modifier-while-dragging shortcut may exist
in addition (designer's decision).

R4 (Must): The mask is the one the renderer uses: for the same values and
render scale it equals the mask the sharpening step blends with. At
Masking 0 it is full everywhere, because the renderer sharpens everything at
0.

R5 (Must): The mask is available at every zoom level, including reduced
drafts during a drag and render scales where the renderer skips sharpening
(below 0.2). It never shows full everywhere or blank just because sharpening
was skipped at that scale.

R6 (Must, owner ruling 2): While the value is changing, the mask is a live
estimate. When input pauses, at any zoom, it is replaced by the mask
computed at full resolution and scaled to the current zoom, so that it
matches a full-size export.

R7 (Must): The mask is a view, never data. Showing it, hiding it, or
changing values while it is shown writes nothing beyond what the value
change writes today: nothing in the edit stack, no undo step of its own, no
sidecar change, and no cached preview or grid thumbnail of the mask. While
it is shown, the histogram stays the photo's. It keeps the last photo
frame's values, so it can go stale if Exposure, a curve or another slider
changes while the mask is shown. It updates again when the mask is hidden.
The owner accepted this (ruling 5).

R8 (Must): The sharpening mask is never combined with the local-mask
overlay, Show Original or a crop session. At most one of them is on screen,
and hiding the sharpening mask returns the loupe to what it showed before,
including the overlay if it was on. While the mask is shown, clicks and
drags on the photo do not paint, sample colors or move mask handles.

R9 (Must): When the loupe shows the mask instead of the photo, this is
evident on screen and to VoiceOver. The mask is off when the user leaves
the loupe (grid, review mode) and after relaunch.

R10 (Must, owner rulings 4 and RI-1): With the global Amount at 0 or the
Sharpening group turned off, the mask still shows Masking's selection (where
sharpening would go). The screen says that no sharpening is applied only when
nothing at all is sharpened, meaning no local mask in effect has Sharpness
above 0. When local masks still sharpen, the view keeps its normal state, and
its legend adds a sentence saying that local masks still sharpen. The wording
is the designer's.

R11 (Must): Where live editing is unavailable (videos, offline masters,
unreadable edit stacks), the control is disabled rather than missing or
broken.

R12 (Should): On an EDR display, with an HDR photo, the mask shows at
standard brightness: white is no brighter than the interface's white.

R13 (Must): Sharpening's rendering does not change. No pipeline version
bump, and no golden changes.

## Acceptance criteria

AC1 (R1, R4): PhotoCore test on a synthetic scene with a smooth noisy region
and a strong edge. At Masking 100 the mask is none in the smooth region and
full on the edge. At Masking 0 it is full everywhere.

AC2 (R4): PhotoCore test. For several Masking and Radius values and two
render scales, the mask equals the one the sharpening step blends with,
within half-float rounding.

AC3 (R1): PhotoCore test. On the same scene, raising Masking never raises
any pixel's mask value.

AC4 (R2): Manual check at fit. With the mask shown, drag Masking from 0 to
100: the mask darkens progressively during the drag. Repeat with keyboard
increments.

AC5 (R3): Manual check. With the keyboard only, show the mask, change
Masking and hide the mask. With VoiceOver on, the control's name and state
are spoken.

AC6 (R5): PhotoCore test at a render scale of 0.1 (a ¼ draft of a 6000 px
photo). At Masking 100 the smooth region is none, not full. Manual check:
the mask shows at fit, 100% and 400%.

AC7 (R6): Test. After input pauses, the mask at 1:1 equals the
mask computed on the full-resolution image, and at fit it equals that mask
downscaled, within a tolerance the engineer derives and states.

AC8 (R7): Test or debug-script check:
- Toggling the mask with no value change leaves the version's edit stack,
  render hash and `sidecarQueue` unchanged, and the undo menu unchanged.
- After a drag with the mask shown, one Undo restores the previous Masking
  value.
- After the mask is hidden, the cached preview and grid thumbnail show the
  photo (snapshot).
- Frames showing the mask never replace the histogram.

AC9 (R8): Debug-script checks:
- With the red overlay on, showing the sharpening mask removes the overlay,
  and hiding it brings the overlay back.
- Show Original and the sharpening mask are never both on screen.
- During a crop session the control is unavailable, or the mask ends
  (whichever the designer chooses).
- With a brush mask selected and the sharpening mask shown, a drag on the
  photo leaves the edit stack unchanged.

AC10 (R9): The debug script's `accessibility` output for the loupe says it
shows the sharpening mask. Switching to the grid or review mode, or
relaunching, ends the mask.

AC11 (R10): Test: at equal Masking, the mask with Amount 0 equals the mask
with Amount 50. Debug-script or manual checks, with the mask shown:
- Amount 0, and no local mask with Sharpness: the not-applied state shows.
- Sharpening group off, and no local mask with Sharpness: the not-applied
  state shows.
- Amount 0 or the group off, plus one local mask in effect with Sharpness
  50: the normal state shows, its legend has the extra sentence, and the
  not-applied state does not show.
- The same, with that local mask turned off: the not-applied state shows.

AC12 (R11): For a video, an offline master and an unreadable stack, the
control is disabled (menu state via `menuitems`, or the control's state).

AC13 (R12): Manual check on an EDR display with an HDR photo. The mask's
white matches the interface's white.

AC14 (R13): The existing goldens pass unchanged, and
`PreviewCacheKey.currentPipelineVersion` is unchanged.

## Non-goals

- Previews for Amount, Radius or Detail (owner ruling 1). A later feature
  could add them.
- The mask in the grid, the film strip, review mode, preset or look-up table
  hover previews, or export.
- Saving or exporting the mask as an image.
- Any `photocli` output of the mask (owner ruling 3).
- Combining local masks' areas into the view. Local sharpening uses the same
  Masking, so the view still applies to it, but it does not show where local
  masks are.
- Changing how sharpening or Masking renders. This includes making the
  sharpening shown at fit match full size (Q5, roadmap item
  `sharpen-masking-scale`).
- Viewport rendering at 1:1. That is roadmap item `viewport-render-1to1`.
- What local Sharpness renders with while the Sharpening group is off
  (RI-2). Today it uses the default Radius 1, Detail 25 and Masking 0, not
  the user's values. Until that is decided, the view shows the user's
  Masking, which local sharpening then ignores. Any fix is a rendering
  change with a pipeline bump, which R13 excludes here. Tracked as roadmap
  item `local-sharpen-group-off`.

## Dependencies and impact

- `AdjustmentRenderer.sharpen` and `edgeMask` (PhotoCore). The renderer
  bypasses the mask at Masking 0 and skips sharpening below scale 0.2.
- `LiveRenderSession` already draws a mask into a live frame (the red
  overlay). `AdjustmentEditor` keeps those frames out of the histogram and
  the preview cache (`frameHasOverlay`). The new view meets the same rules.
- Drafts (½, ¼) while dragging, and the stretched 2560 px frames at 1:1,
  limit what a live frame can show (R5, R6).
- The Adjust tab's hint ("Sharpening is easiest to judge at 1:1 (Z), once
  the change is saved") may need rewording. That is the designer's call.
- New strings go in the String Catalog. `docs/USER_GUIDE.md` is updated with
  the behavior. A debug-script command to show and hide the mask is needed
  for AC8–AC10.
- No catalog migration, edit-stack change, sidecar change or pipeline bump.

## Assumptions

- Sharpening sliders edit only in the loupe. In review mode the inspector is
  hidden, so the mask cannot be reached there anyway.
- From reading the code, not measuring: a reduced render averages away noise,
  so at fit Masking cuts out more of the smooth areas than at full size. A
  live-resolution mask would therefore show the sky as held back when a
  full-size export still sharpens its noise. This is the reason for R6. The
  engineer confirmed it (Q5, answered).
- "As responsive as the photo's own live frames" is the speed target. I have
  not set a number.
- In the owner's reference behavior the mask is shown only while dragging
  with a modifier. I take the need to be "see the mask while changing
  Masking", not that exact gesture.

## Rulings

Owner, in chat, 2026-11-05:

1. Sliders: "Masking only". Previews for Radius, Detail and Amount are
   non-goals for now; a later feature could add them.
2. Accuracy: "Estimate, refine on pause". Show a live estimate while the
   value changes, then recompute at full resolution once input pauses, at
   any zoom (R6, AC7). If the engineer finds the refinement too slow, they
   return it as a requirements issue; it does not fall back silently.
3. `photocli`: "No, non-goal".
4. Amount at 0 or the group turned off: "Show mask, note no sharpening"
   (R10, now Must).

Owner, in chat, 2026-11-05, on the designer's requirements issues:

- RI-1, R10 with local sharpening: local Sharpness keeps sharpening through
  the global Masking when the global Amount is 0 or the group is off. Ruling:
  "Only when nothing sharpens". The not-applied state shows only when
  nothing at all is sharpened, local masks included. When local masks still
  sharpen, the normal state stays, and the legend adds a sentence (R10,
  AC11).
- RI-2: with the group off, `Adjustments.effective` resets Sharpening to its
  defaults, so local Sharpness uses Masking 0, Radius 1 and Detail 25 rather
  than the user's values. Ruling: "Roadmap item to decide". It is out of
  scope here (R13) and tracked as `local-sharpen-group-off`.

Owner, in chat, 2026-11-05, on the engineer's requirements issue and
finding:

5. Histogram while the mask is shown (R7): "Accept stale histogram". The
   histogram keeps the last photo frame's values while the mask is shown.
   It can go stale if other sliders change meanwhile, and it updates when
   the mask is hidden.
6. Masking at fit versus full size (Q5): "Add Idea row". It is out of scope
   here (R13) and tracked as `sharpen-masking-scale`.

## Open questions

**Q4 (designer):**
- The interaction: a toggle, showing the mask automatically while Masking
  changes, a modifier while dragging, or a combination.
- Where the control lives (menu, shortcut, inspector).
- How the screen shows that the mask is on, and that Amount is 0 (R10).
- Which state wins between the mask, Show Original, the local-mask overlay
  and a crop session.
- Whether the mask stays on when moving to the next photo in the loupe.
- The Adjust tab hint.

**Q5 (engineer): answered 2026-11-05.** Measured on an M4 Pro debug build
with a synthetic noisy 6000 × 4000 DNG at Masking 30:
- **The assumption is confirmed.** On a noisy flat area, about 50% of the
  sharpening came through at fit (render scale 0.43), against about 93% at
  full size. The photo's own sharpening at fit holds back noise that a
  full-size export sharpens.
- **The cost of R6:**
  - A refine takes about 0.25 s the first time and about 0.16 s per pause
    after that.
  - Holding the input costs pixels × 8 bytes, which is 192 MB at 24 MP.
- **The fit-versus-full-size difference** is a rendering issue in its own
  right. The owner made it roadmap Idea `sharpen-masking-scale` (ruling 6).
  It is not fixed here.

## Revisions

- 2026-11-05: Owner rulings recorded. Q1, Q2, Q3 and Q6 are closed. R6 is no
  longer pending. R10 is raised from Should to Must. `photocli` and the
  previews for the other sliders are non-goals. Status is Approved.
- 2026-11-05: The designer's RI-1 and RI-2 were ruled on by the owner. R10
  and AC11 now treat local sharpening: "not applied" shows only when nothing
  sharpens. A non-goal now points to the new roadmap item
  `local-sharpen-group-off`.
- 2026-11-05: The owner ruled on the engineer's requirements issue and
  finding:
  - R7 now says the histogram may go stale while the mask is shown.
  - Q5 is answered with the engineer's measurements.
  - A non-goal now points to the new roadmap item `sharpen-masking-scale`.
