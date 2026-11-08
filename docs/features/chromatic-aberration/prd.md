# Chromatic aberration and color fringe removal

Status: Approved (owner, 2026-11-07)
Slug: chromatic-aberration
Roadmap: Now

## Problem

Photos often have colored fringes along high-contrast edges: branches
against the sky, window frames, backlit hair, specular highlights. There
are two kinds:

- **Fringe halos.** Purple or magenta halos, and green ones, appear
  around bright edges and out-of-focus highlights anywhere in the frame.
  This is axial fringing.
- **Lateral color edges.** Red/cyan or blue/yellow outlines get wider
  toward the corners. This is lateral chromatic aberration.

Nothing in the app removes either. The owner reports that most raw
files already have distortion and vignetting corrected by the raw decoder,
but "the fringing usually isn't". The only way out today is another app,
which goes against keeping editing in one non-destructive library.
Lightroom presets that remove fringing are imported with that part
reported as unsupported (`CameraRawMapping`: `defringe`, and
`AutoLateralCA` under `lensCorrections`).

## Goal and success

A person can make a photo's color fringes go away without leaving the
app. Fringe halos are handled the way the owner proposed: "a color picker
that will turn the fringe gray. And a slider to widen or narrow the color
range". Lateral color edges are removed by one automatic control. Both
are off unless chosen and never change a photo nobody touched. The result
in the loupe matches the export.

We will know it worked when:

- the criteria below pass on synthetic test scenes with known fringes;
- later, on real photos with fringing, the fringes are gone or nearly gone
  at 100%, and genuinely purple or green subjects keep their color (M1).
  This check is manual and does not block shipping.

## Owner rulings (2026-11-07)

1. **Priority.** Carved out of lens-corrections and made "the next item".
   Distortion and lens vignetting stay in lens-corrections (Later),
   because the decoder usually applies them.
2. **Fringe halos.** Pick the fringe color from the photo, and it turns
   gray. A slider widens or narrows the range of colors affected.
3. **Two picks.** Up to two picked colors, each with its own range, because
   purple and green fringes often appear together on opposite sides of the
   focus plane.
4. **Near edges only.** Graying acts only near high-contrast edges. Real
   purple or green subjects away from edges (flowers, clothing, leaves) keep
   their color.
5. **No amount control.** Colors at the center of a range go fully gray,
   and colors toward its edge only partly, so there is no hard boundary.
6. **Brightness kept.** "Gray" removes the fringe's color and keeps its
   brightness, so edges don't gain a dark or light outline.
7. **Lateral color edges are in scope.** One control measures the photo
   and corrects it automatically. Manual fine-tuning of the red/cyan and
   blue/yellow edges is a Should.
8. **Whole photo only.** Not inside masks. A local version would be a
   later roadmap row.
9. **All photo formats.** Raws, JPEG, HEIC and TIFF, because fringing comes
   from the lens and camera JPEGs can have it too. Videos are excluded.
10. **Presets, paste and batch** carry it like any other group. An
    automatic lateral correction is measured again on each photo that
    receives it, never copied from the source photo.
11. **Lightroom preset import** maps the equivalent settings where the
    meaning matches.
12. **Speed.** No numeric target. Times are measured and recorded.
13. **At 100%,** seeing the true result only after each change is saved
    is accepted for this feature. viewport-render-1to1 stays a separate
    item.
14. **Test photos.** The owner has none on hand. QA uses synthetic scenes,
    and the real-photo check (M1) waits without blocking.

## Users and scenarios

- **Primary.** A photographer opens a backlit tree shot at 100%. Purple
  halos line the branches against the sky. They pick the halo color from
  the photo, and the halos turn gray. Some edges still show a faint
  bluish purple, so they widen the range until those go too. They check
  the result with before/after. The blue sky stays blue.
- **Real purple subject.** A purple flower sits in the same frame. Its
  petals keep their color, because they aren't fringes at a high-contrast
  edge, even when the range covers their hue. Only the flower's own
  high-contrast outline can be affected.
- **Two kinds of fringe.** A wide-aperture portrait has purple fringes in
  front of the focus plane and green ones behind it. The person picks the
  purple, then picks the green as a second color, and sets each range on
  its own.
- **Lateral color edges.** A wide-angle shot has red/cyan outlines on
  buildings near the corners. One control removes them. Cropping
  afterwards doesn't bring them back or change the correction.
- **Many photos.** After fixing one photo from a shoot, the person pastes
  the correction onto the rest of the shoot. Each photo gets its own
  lateral measurement.

## Requirements

### Fringe halos

R1 (Must): The person can choose a fringe color by picking it from the
photo in the loupe. They can pick a second color too, each with its own
range. Each pick can be cleared or replaced on its own.

R2 (Must): Near high-contrast edges, fringes whose color falls in a
pick's range lose their color: they become neutral gray. Their brightness
stays close to what it was.

R3 (Must): For each pick, the person can widen or narrow the range of
colors affected. Widening never leaves fewer pixels affected than before,
and narrowing never leaves more. At the narrowest setting only colors very
close to the picked one change.

R4 (Must): Within a range, colors at its center go fully gray, and colors
toward its edge are grayed less and less, with no visible hard boundary.
There is no separate amount control.

R5 (Must): Colors outside every range are unchanged. Colors inside a range
are unchanged away from high-contrast edges.

R6 (Should): The person can see which parts of the photo the current picks
and ranges affect, beyond comparing with before/after (`\`). The designer
decides how.

### Lateral color edges

R7 (Must): One control turns on correction of lateral color edges. The
app measures the photo and removes red/cyan and blue/yellow outlines that
widen toward the corners. Nothing else is required of the person.

R8 (Must): The measured correction is saved with the edit, so a photo
always renders the same way, in the loupe, in previews, in exports and in
`photocli`, on every render and at every size. It is not measured again
on each render.

R9 (Must): The correction is centered on the lens's optical axis, not on
the crop. Changing the crop, rotation or straightening doesn't change how a
given scene point is corrected. This includes raws decoded as the whole
sensor because of a crop or mask (`docs/archive/PHASE6_PLAN.md` finding 1).

R10 (Should): The person can fine-tune or set the correction by hand,
separately for the red/cyan and blue/yellow edges.

### Both

R11 (Must): Off by default. Photos and stacks that don't use it render
exactly as before. No existing render changes, every golden stays
unchanged, and there is no `PreviewCacheKey.currentPipelineVersion` bump
for existing photos.

R12 (Must): It is non-destructive like every other adjustment. It is
stored in the photo's edit stack and is part of the render hash. One
gesture or pick is one undo step. Before/after shows the photo without it,
and a reset gives back the identity render. It belongs to a group with the
group on/off control the Adjust tab already has.

R13 (Must): The loupe at fit, the cached previews and a full-size export
agree. A fringe removed in the loupe is removed in the export, and the
ranges and the edge rule cover the same pixels at every size (compare
sharpen-masking-scale, where fit and export disagree).

R14 (Must): Its parameters are described with the other modules'
(`adjustments` in `photocli`; `AdjustmentParameterTests`), and `photocli
develop` can set them.

R15 (Must): It works on raws, JPEG, HEIC and TIFF. Videos are not offered
it.

R16 (Must): Presets, copy/paste and the grid's batch commands carry it
like any other group. A photo that receives automatic lateral correction
is measured for itself and never gets the source photo's measured values.

R17 (Should): When a Lightroom preset turns on its automatic chromatic
aberration removal or sets purple or green fringe removal, the import
maps that where the meaning matches. The import report then stops listing
it as unsupported. Distortion, lens vignetting and lens profiles stay
reported as unsupported.

R18 (Should): Live frames while a control of this feature moves are about
as fast as frames while the existing color sliders move. The times are
measured and recorded; there is no fixed target.

## Acceptance criteria

Synthetic scenes: the engineer adds test scenes to `PhotoFixtures`:

- (a) high-contrast edges with a purple fringe on one side and a green
  fringe on the other;
- (b) the same, plus a large purple patch and a large green patch away
  from any edge, standing in for real purple or green subjects;
- (c) a scene whose red and blue channels are scaled radially by known
  amounts about the frame's center.

Each criterion has a CPU reference or a measurement, per CLAUDE.md
"Checking image code". The engineer sets numeric tolerances from the
reference and the formats, not by trial.

AC1 (R1, R2): On scene (a), picking the purple fringe makes those pixels
neutral within the tolerance (chroma near zero), and their brightness
stays within the tolerance of before. Adding the green fringe as a second
pick grays the green fringe too. Clearing either pick restores only that
fringe.

AC2 (R1, R3): On scene (a), a fringe pixel whose hue is a known distance
from the picked one is unchanged at the narrowest range and gray at a
wider one. Over a series of widening steps, the set of changed pixels
never shrinks. Changing one pick's range leaves the other pick's effect
unchanged.

AC3 (R4): On scene (a), going from the center of a range to its edge,
the color removed decreases without a step: at the center, the pixels
become neutral; at the edge, unchanged.

AC4 (R5): On scene (b), the purple and green patches away from edges keep
their color within the tolerance while their hue is inside a range. On
scenes (a) and (b), pixels whose colors are outside every range match the
render without the feature, within half-float rounding.

AC5 (R7, R8): On scene (c), turning the correction on leaves a residual
misregistration between channels under a tolerance the engineer derives
(well under a pixel at full size). Rendering twice, and rendering at
preview and at full size, give the same correction. The measured values
are stored in the stack.

AC6 (R9): On scene (c), two crops of the same photo show the same
correction where they overlap, within the crop test's existing allowance
(`docs/archive/PHASE6_PLAN.md` finding 2). A crop doesn't change the
measured values.

AC7 (R10): Setting the red/cyan and blue/yellow corrections by hand on
scene (c) moves each channel as set, checked against the reference.

AC8 (R11): Every existing golden passes unchanged, the hash-stability
corpus is unchanged, and no pipeline bump is made for stacks without the
feature.

AC9 (R12): With the feature on: one gesture or pick adds one undo step;
undo restores the previous render; before/after shows the photo without
it; the group check box turns it off without losing values; reset gives
the identity hash.

AC10 (R13): On scene (a), the loupe's fit render scaled to full size and a
full-size export agree on which pixels are grayed, within a tolerance
derived from the scale.

AC11 (R14): `photocli adjustments` lists the new parameters with ranges
and defaults, `photocli develop` sets them, and `render` reflects them.

AC12 (R15): The same pick and range applied to a DNG, a JPEG, a HEIC and a
TIFF of scene (a) gray the fringe in each. A video is not offered the
feature.

AC13 (R16): A preset saved from a photo with the feature, paste, and a grid
batch carry it to other photos. A pasted automatic lateral correction is
measured on each receiving photo: two photos of scene (c) with different
known scalings end up with different stored values, each matching its own
scaling.

AC14 (R17): Importing a Lightroom preset that sets purple and green fringe
removal, or automatic chromatic aberration removal, maps them, and the
report no longer lists them. A preset with a lens profile or distortion
still reports `lensCorrections`.

AC15 (R18): `photobench` records live frame times with the feature on,
next to the existing color slider times.

M1 (manual, later, not blocking): on real photos with fringing, at 100%,
the fringes are gone or nearly gone and real purple or green subjects keep
their color. It waits until someone has suitable files and is recorded as
a pending check at Ship.

## Non-goals

- Geometric distortion, lens vignetting and lens profiles. These stay in
  lens-corrections (Later).
- Perspective or keystone correction, and color moiré.
- A switch for the raw decoder's own lens correction.
- Fringe removal inside masks.
- More than two picked colors.
- A separate amount control for the fringe graying.
- A default that applies it to every new import. The app has no such
  mechanism.
- Video.

## Dependencies and impact

- **Edit stack.** New operations, or parameters of a new group. Stacks
  without them keep their bytes and hash (R11). A picked color is stored
  as values, not as a position in the photo, unless the engineer shows a
  reason otherwise.
- **Renderer.** Neither correction can be built from stock Core Image
  filters alone, which is why lens corrections were held back. The
  stitchable-kernels spike (`docs/PROFILING.md` "Stitchable kernels";
  branch `feature/stitchable-kernels-spike`, not merged) shows that custom
  per-pixel, neighborhood and warp kernels run without a Metal build step,
  at a stock filter's cost. The engineer confirms the approach. The spike
  has to merge, or be redone, as part of this work.
- **Presets, paste, batch, Lightroom import:** `Adjustments.Group`,
  `PresetFile`, `BatchEdit`, `CameraRawMapping` (R16, R17).
- **viewport-render-1to1 (Now).** At 100%, the loupe shows the 2560 px
  live frame stretched while a control moves, and the true result only
  after the change is saved. Accepted for this feature (ruling 13).
- **Camera-cropped raws** (`docs/archive/PHASE6_PLAN.md` finding 1):
  affects R9.

## Open questions

- **OQ1 (designer, engineer).** What counts as "near a high-contrast edge"
  (R2, R5): a fixed rule, or one the person can adjust? If adjustable, it is
  a control besides the range, and the designer decides whether it earns
  its place. Ruling 5 excludes only an amount control.
- **OQ2 (engineer).** Which image does the picker sample: the photo as
  shown, after the other adjustments, or the image entering this step? What
  the person sees and what gets grayed must match.
- **OQ3 (designer).** How picking works in the loupe, including at 100%;
  where the controls live; how the two picks are shown, cleared and
  replaced; and what form R6 takes, for example an overlay of the affected
  area.

## Revisions

- 2026-11-07: Draft written from the owner's color picker idea, with
  proposed defaults for the rest.
- 2026-11-07: Approved. The owner accepted every proposed default ("Defaults
  are good"): lateral color edges stay in scope, a second pick is allowed,
  graying acts near high-contrast edges only, there is no amount control
  and the falloff is soft, and A1–A7 are confirmed. These are now Owner
  rulings 3–13. Requirements were renumbered (R1–R18), AC3 (soft falloff)
  and AC7 (manual lateral) were added, and AC4 now tests "near edges only".
  Assumptions were removed, since all were confirmed. The old owner
  questions Q1 and OQ1–OQ3 are closed. The open questions now hold only the
  designer and engineer questions, renumbered OQ1–OQ3.
