# Chromatic aberration and color fringe removal

Status: R1–R18 Approved (owner, 2026-11-07) and built (status.md); PR #48
open, CI green, reviews not started. R19–R36, the pixel magnifier added by
the owner: Approved (owner, 2026-11-08), designed (design.md §20) and built
(status.md), with one test still owed for AC19 (Revisions, 2026-11-08). The
reviews run once that test is in.
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
15. **Filling a slot without pointing.** The owner was asked whether people
    who can't point at the photo (VoiceOver users, anyone who can't place
    the pointer precisely) should get a way to fill a fringe color slot
    from a short list of common fringe colors, in this feature or later.
    Answer: "It should go into this feature now."
16. **Pixel magnifier (2026-11-08).** After trying the feature on a raw
    ("it works well"), the owner added: "a small loupe tied to the cursor.
    Maybe a round circular window that shows pixel level when choosing a
    color", with "a zoom percentage drop down to control zoom level along
    with rgb values of the selected pixel. Zoom level should persist between
    uses and should be reusable for different features." The owner's
    reference picture shows the function wanted; the app's look is its own
    (CLAUDE.md, Clean-room constraint).
17. **Who uses the magnifier now (2026-11-08).** Only the fringe eyedropper,
    built so other features can use it and proved by a test tool. Pick
    Colors follows as its own roadmap row. Rulings 17–22 are the proposed
    defaults, which the owner accepted: "Defaults are fine."
18. **The 3-point snap goes.** The outlined pixel is the pixel picked: exactly
    the one under the pointer at the view's 100% and closer; zoomed out
    further, the most colorful photo pixel under that one screen pixel.
19. **What the magnifier draws.** The same pre-edit image its values come
    from, even where edits make it look different from the photo around it.
20. **Value scale.** Integers from 0 to 255 in Display P3.
21. **L is shown,** as a fourth value.
22. **No resize grip.** The magnifier has a fixed, small size.

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
- **Without pointing.** A VoiceOver user, or someone who can't place the
  pointer on a 2-pixel fringe, fills Color 1 with purple from a short list
  of common fringe colors. The purple fringes turn gray, and they adjust
  the range from the keyboard, exactly as after a pick.
- **Lateral color edges.** A wide-angle shot has red/cyan outlines on
  buildings near the corners. One control removes them. Cropping
  afterwards doesn't bring them back or change the correction.
- **Many photos.** After fixing one photo from a shoot, the person pastes
  the correction onto the rest of the shoot. Each photo gets its own
  lateral measurement.
- **Seeing the pixel.** At fit, a fringe is a line a screen pixel or two
  wide. The person arms the eyedropper, and a small magnifier travels with
  the pointer, showing the photo's own pixels. They move until the outline
  sits on the purple pixels, read its values, and click. They know what
  they picked before they pick it.

## Requirements

### Fringe halos

R1 (Must): The person can choose a fringe color by picking it from the
photo in the loupe. They can pick a second color too, each with its own
range. Each pick can be cleared or replaced on its own.

R1a (Must): Without pointing at the photo, the person can fill either slot
from a short list of common fringe colors. The list holds at least purple
and green, the two fringe colors the Problem names. Filling a slot this
way, setting its Tolerance, clearing it, and showing what the feature
affects (R6) can all be done from the keyboard alone and with VoiceOver.
The list is in addition to picking from the photo and replaces none of it
(ruling 2).

R1b (Must): A slot filled from the list behaves exactly like a slot filled
by picking. It holds a color the same way, follows the same rules (R2–R5:
near edges only, its own range, soft falloff), is stored and carried by
paste and presets the same way, and can be replaced by a pick or another
listed color, or cleared. Filling it is one undo step. Two slots holding
the same color render the same, whatever filled them.

R1c (Should): A listed color, at the range it starts with, grays a typical
fringe of its kind without the person needing to adjust the range first.

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
separately for the red/cyan and blue/yellow edges. Fine-tuning an
automatic correction starts from the measured values and makes them
hand-set: the correction is no longer automatic, and from then on it
behaves like any hand-set correction (R16) (RI-2 ruling, 2026-11-07).

### Both

R11 (Must): Off by default. Photos and stacks that don't use it render
exactly as before. No existing render changes, every golden stays
unchanged, and there is no `PreviewCacheKey.currentPipelineVersion` bump
for existing photos.

R12 (Must): It is non-destructive like every other adjustment. It is
stored in the photo's edit stack and is part of the render hash. One
gesture, pick or choice from the list is one undo step. Before/after shows the photo without it,
and a reset gives back the identity render. Fringe removal and lateral
correction may each be their own group, each with the group on/off
control the Adjust tab already has and its own entry in a preset's group
list. One group for both would also satisfy this requirement.

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
A hand-set or fine-tuned correction (R10) is copied as it is.
A preset that includes every group ("All settings") replaces Color
Fringes and Color Alignment too, including a preset saved with every
group before this feature existed: applying it clears the photo's fringe
slots and alignment (RI-E2 ruling, 2026-11-08).

R16a (Must): A paste, preset or grid batch that carries automatic lateral
correction leaves unchanged any target photo it can't measure, because
the original is offline or can't be read. None of the command's groups
are applied to that photo, so it is never half-pasted. The person is
told how many photos were left unchanged and why, using the existing
Activity warning that batch automatic exposure gives. The other targets
are changed as usual. This is the same rule batch automatic exposure
follows today (RI-1 ruling, 2026-11-07).

R17 (Should): When a Lightroom preset turns on its automatic chromatic
aberration removal or sets purple or green fringe removal, the import
maps that where the meaning matches. The import report then stops listing
it as unsupported. Distortion, lens vignetting and lens profiles stay
reported as unsupported.

R18 (Should): Live frames while a control of this feature moves are about
as fast as frames while the existing color sliders move. The times are
measured and recorded; there is no fixed target.

### Pixel magnifier (ruling 16)

The owner's "small loupe". The app already calls its one-photo view "the
loupe" (and "the view" below means that view), so this PRD says **pixel
magnifier**; the designer chooses the name people see (OQ12). "Picking" means
any tool in R35 is armed and waiting for a click on the photo.

R19 (Must): While a tool is picking and the pointer is over the photo, a
small round magnifier moves with the pointer. It appears on its own when
picking starts and goes when picking ends (a pick, Esc, or anything else
that ends picking today). The person never has to position it.

R20 (Must): It shows the pixels of the image the tool samples (R25), at
full resolution, whatever the view's zoom and whichever frame the view is
showing (a stretched live frame included). Each photo pixel is a hard-edged
square, with no smoothing between pixels. Until those pixels are available,
it shows no pixels and no values rather than coarser or stale ones, and a
click still picks.

R21 (Should): A thin grid separates the pixels at levels where that helps.
The designer decides where it fades or goes.

R22 (Must): One pixel is outlined, and it is the pixel a click would pick.
A click never picks any other pixel, and the 3-point snap is gone at every
zoom (ruling 18). At the view's 100% and closer, the outlined pixel is exactly
the one under the pointer. Zoomed out further, where one screen pixel covers
several photo pixels, it is the most colorful of the photo pixels under that
one screen pixel, so a thin fringe stays reachable at fit. Where the outline
sits in the picture is the designer's (design.md §20 keeps it centered). A
click made before the magnifier's pixels are
ready (R20) follows the same rule. The outlined pixel is always inside the
magnifier and inside the photo.

R23 (Must): With its picture, the magnifier shows the outlined pixel's
R, G and B values, where they hide none of the picture's pixels. They are the same data a click would use, converted for
reading; a pick stores the full-precision color as it does today. They are
integers from 0 to 255, as in the owner's reference, in Display P3 (the app's
output space) with its usual tone curve. Values beyond that range
read as 0 or 255.

R24 (Should): A fourth value, L, shows the same pixel's
luminance on the same scale: the brightness R2 keeps (Rec. 2020 luminance).

R25 (Must): The values come from the image the tool samples, so that what
is read is what is picked. For the fringe tool that is OQ2's image: the
decoded master, aligned as the photo renders, before any graying and every
other adjustment. The magnified pixels come from that same image, so a picture and its numbers always agree, even where edits make the
magnifier look different from the photo around it.

R26 (Must): Before clicking, the person can tell that a click at this spot
would be refused for having almost no color (design §4). The refusal itself
doesn't change.

R27 (Must): A percentage list sets the magnifier's level: 100%, 200%, 400%,
800% and 1600%. A percentage means what it means in the view: at 100%, one
photo pixel is one screen pixel, so at 800% a photo pixel is 8 screen pixels
wide on any display, standard or Retina. The level does not depend on the
view's zoom. The person can change it without ending picking.

R28 (Must): The level persists between uses, across photos, libraries and
relaunches. It is the person's preference on this Mac, not part of a photo
or a library, and one level is shared by both fringe slots and by every tool
that uses the magnifier.

R29 (Must): The outlined pixel and its values stay fully visible at every
pointer position on the photo, the corners included. Parts of the magnifier
beyond the photo's edge, or beyond its crop, show no photo pixels: no
repeated edge pixels and no pixels the crop has removed. A photo turned by
quarter turns appears the same way up as in the view.

R30 (Must): The magnifier stays true when the pointer doesn't move. If the
photo under it pans or zooms, or Color Alignment or anything else that
changes the sampled image changes, it shows the new pixel and values.

R31 (Must): It is a viewing aid only. Showing it or changing its level is
never in the edit stack or the render hash, is never an undo step, and
never reaches a preview, an export or `photocli`. R11 holds.

R32 (Must): It changes no other input while picking. A click anywhere on
the photo picks, drags pan, and scroll, pinch, `Z`, ⌘= / ⌘−, Esc, the
double-click rule and the context menu do what design §4 says. The level's
own control is the only exception.

R33 (Must): It takes no keyboard focus. Its level can be changed from the
keyboard and with VoiceOver, without a pointer. It adds nothing VoiceOver
stops on and announces nothing as the pointer moves; R1a stays the way to
fill a slot without pointing. The outline and values stay legible over any
photo content, white and black pixels included, and with Increase Contrast.

R34 (Must): It is built to serve other features. A tool that uses it
supplies the image to sample and its own rule for which pixel a click
picks; the magnifier knows nothing about fringes.

R35 (Must): In this change, only the fringe eyedropper (both
slots, and Pick from Photo) uses it. The Color Range mask's Pick Colors, the
only other color picker in the app, is unchanged.

R36 (Should): The magnifier feels attached to the pointer, and arming the
eyedropper causes no visible hitch, on the same terms as ruling 12: no
fixed target, times measured and recorded. It doesn't slow R18's live
frames, and whatever it holds in memory for picking is released when
picking ends.

## Acceptance criteria

Synthetic scenes: the engineer adds test scenes to `PhotoFixtures`:

- (a) high-contrast edges with a purple fringe on one side and a green
  fringe on the other, plus a defocused bright disc with a soft purple
  rim (the out-of-focus highlight case the Problem names);
- (b) the same, plus a large purple patch and a large green patch away
  from any edge, standing in for real purple or green subjects;
- (c) a scene whose red and blue channels are scaled radially by known
  amounts about the frame's center;
- (d) a scene whose every pixel has a known, distinct color, out to its
  outermost rows and columns (pixel magnifier).

Each criterion has a CPU reference or a measurement, per CLAUDE.md
"Checking image code". The engineer sets numeric tolerances from the
reference and the formats, not by trial.

AC1 (R1, R2): On scene (a), picking the purple fringe makes those pixels
neutral within the tolerance (chroma near zero), and their brightness
stays within the tolerance of before. The purple rim of the defocused
disc is grayed too. Adding the green fringe as a second pick grays the
green fringe too. Clearing either pick restores only that fringe.

AC1a (R1a, R1c): On scene (a), with no click on the photo, filling Color 1
with purple and Color 2 with green from the list grays the purple fringe,
the defocused disc's purple rim and the green fringe, at the ranges the
listed colors start with, within AC1's tolerances. This is checked
through the debug script, and through the accessibility actions and
values the `accessibility` command lists: the list can be reached and
used, and each slot then reports its color. Not one step of it needs a
pointer.

AC1b (R1b): A slot filled with the listed purple stores its color the same
way as a picked one. When a pick stores the same color value, the two
renders are identical. Its range widens and narrows as in AC2. Replacing
it with a pick, replacing a pick with a listed color, and clearing it each
work and are one undo step. A preset and a paste carry a listed color, and
it arrives indistinguishable from a picked one.

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
Changing either one after an automatic measurement starts from the
measured values and leaves the correction no longer automatic.

AC8 (R11): Every existing golden passes unchanged, the hash-stability
corpus is unchanged, and no pipeline bump is made for stacks without the
feature.

AC9 (R12): With the feature on: one gesture or pick adds one undo step;
undo restores the previous render; before/after shows the photo without
it; each group's check box turns its part off without losing values;
reset gives the identity hash.

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
scaling. A fine-tuned (hand-set) correction pasted onto those photos
arrives with the source's values unchanged.

AC13a (R16a): A grid paste that carries automatic lateral correction,
onto a selection that includes a photo whose original is offline, leaves
that photo's stack and render hash byte for byte unchanged. Activity
reports it with the existing "left unchanged: originals offline" warning,
and the online photos are pasted and measured. A paste without automatic
lateral correction treats offline photos as it does today.

AC13b (R16): A preset stored with every group and no group list, as
presets saved before this feature are, applied to a photo of scene (a)
with both fringe slots filled and automatic alignment on, leaves both
slots empty and alignment off, in one undo step. A preset file with no
group list reads the same way. A preset whose group list leaves out the
two Lens groups keeps the photo's slots and alignment.

AC14 (R17): Importing a Lightroom preset that sets purple and green fringe
removal, or automatic chromatic aberration removal, maps them, and the
report no longer lists them. A preset with a lens profile or distortion
still reports `lensCorrections`.

AC15 (R18): `photobench` records live frame times with the feature on,
next to the existing color slider times.

Pixel magnifier. The debug script reports what the magnifier shows (visible,
level, the outlined pixel's coordinates, its values, the pixels drawn), so
each of these can be checked without a person.

AC16 (R19): Arming either eyedropper or Pick from Photo shows the magnifier
over the photo; over the surround it isn't shown. A pick, Esc, moving to
another photo, starting a crop and entering review each remove it. Filling a
slot from the list never shows it.

AC17 (R20, R21): On scene (d), at the view's fit and at 100%, and while a
stretched live frame is on screen, every pixel drawn in the magnifier has the
exact color of its photo pixel, with no in-between colors, at every level.
While the pixels aren't ready, none are drawn, no values are reported, and a
click still stores the same color it would have.

AC18 (R22): On scene (a), at the view's fit, 100% and 800%, across many
pointer positions on and near the fringes, the outlined pixel is the pixel
the click then stores (`print fringe`'s last sample point). At
100% and 800% it is exactly the pixel under the pointer, even when a
neighbor is more colorful; at fit it is the most colorful photo pixel under
the pointer's screen pixel.

AC19 (R23, R25): On scene (d) and scene (a), the values shown match a CPU
reference's conversion of the color the click stores, within 1. Changing
Exposure, Saturation or a look-up table, or filling the other slot, leaves
the values at a pixel unchanged. Turning on Color Alignment changes them as
the sampled image changes. The pixels drawn match the same image. A color
outside 0–255 reads as 0 or 255.

AC20 (R24): A neutral pixel reads R = G = B = L. On scene (d),
L matches the reference.

AC21 (R26): On scene (a)'s light ground, the magnifier reports a click there
would be refused, and the click is then refused as design §4 says. On a
fringe, it does not.

AC22 (R27): At each of the five levels, a photo pixel is the level ÷ 100
screen pixels wide (8 at 800%), at backing scale 1 and 2, and at the view's
fit, 100% and 800%. Changing the level leaves picking armed and the slot's
state unchanged.

AC23 (R28): With a level other than the default chosen, picking on another
photo, on the other slot, after a relaunch and with another `--library-root`
all open at that level. The photo's stack, its render hash and the catalog
are unchanged by the change of level.

AC24 (R29): With scene (d) filling the view and the pointer on each of its
four corner pixels, the outlined pixel and its values are entirely inside
the window. No pixel beyond the photo's edge is drawn. On a cropped photo,
none beyond the crop is drawn, and the outlined pixel is never beyond it. On
a photo turned a quarter turn, the outlined pixel at a known position is the
right one and the picture is the same way up as the view.

AC25 (R30): With the pointer still, panning, zooming the view, changing
Color Alignment and undoing that change each update the outlined pixel and
values to what a click would then store.

AC26 (R31): Picking with the magnifier and changing its level adds no undo
step beyond the pick's one. Every golden, the hash-stability corpus and the
pipeline version are unchanged (AC8).

AC27 (R32): With the magnifier showing, every row of design §4's "Mouse and
keys while picking" table still passes as DR3 checks it. The magnifier takes
no clicks: with it showing, the debug script's `hit` over its drawing reaches
the photo. It sits beside the pointer, so a click can land on its drawing
only when the canvas is too small to fit it on any side and it is clamped
under the pointer (design.md §20). That real click, which picks, is part of
M3.

AC28 (R33): The `accessibility` command lists no element for the magnifier.
The level can be read and changed with the keyboard and through the
accessibility actions, with no pointer. Keyboard focus is where it was
before arming.

AC29 (R34): A test uses the magnifier with a tool of its own: a synthetic
image and a different picking rule. The outlined pixel and values follow
that tool's image and rule. Code review confirms the magnifier refers to
no fringe type.

AC30 (R35): Arming the Color Range mask's Pick Colors shows no
magnifier, and it samples as it does today.

AC31 (R36): `photobench` records, on 6000 × 4000 files next to R18's times:
time from arming to the first pixels, time for an update as the pointer
moves, and memory held while picking. R18's live frame times don't get
worse with the magnifier showing. Memory held for picking is gone after
picking ends.

M1 (manual, later, not blocking): on real photos with fringing, at 100%,
the fringes are gone or nearly gone and real purple or green subjects keep
their color. It waits until someone has suitable files and is recorded as
a pending check at Ship. When M1 runs, it also notes whether the listed
colors match the fringes found, which is input for any change to the list.
M1 includes at least one photo with strongly out-of-focus bright
highlights (bokeh) that have colored rims, since the fixed edge rule only
fully reaches rims softened over up to about 60 full-size pixels (status.md
OQ1). For those rims it records whether they are grayed; where they are
not, whether the Fringe Map shows them outside the edge rule and whether
widening Tolerance fixes them (RI-E1 ruling, 2026-11-08).

M2 (manual, R1a): with VoiceOver on and no pointer use, on a synthetic
scene (a) photo, a person fills both slots from the list, changes each
range, shows and hides what the feature affects, and clears a slot. Each
step is announced understandably. QA lists it under "For a person".

M3 (manual, R19, R21, R27, R32, R33, R36): on a real raw, on a Retina display
and on a standard one if available, and after moving the window between
them: the magnifier feels attached to the pointer, the level can be changed
in practice while picking, and the outline and values read clearly over
bright, dark and busy content, and with Increase Contrast. With the window
small enough that the magnifier lies under the pointer, a click there picks.
QA lists it under "For a person".

## Non-goals

- Geometric distortion, lens vignetting and lens profiles. These stay in
  lens-corrections (Later).
- Perspective or keystone correction, and color moiré.
- A switch for the raw decoder's own lens correction.
- Fringe removal inside masks.
- More than two picked colors.
- A general color chooser for the slots, any color from a color picker
  or the screen. The list holds common fringe colors only, and a pick
  comes from the photo's data.
- A separate amount control for the fringe graying.
- A default that applies it to every new import. The app has no such
  mechanism.
- Video.
- Pixel magnifier: a magnifier outside picking (a general way to inspect
  pixels); a setting to turn it off; moving the outline pixel by pixel with
  keys (arrows move between photos); copying its values; sampling anything
  outside the photo. A White Balance eyedropper: the app has none today (only
  presets, sliders and Auto), and this change doesn't add one.
- Resizing the magnifier (ruling 22). The reference's resize grip is left
  out. Its fixed, small size is the designer's to set.

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
  `PresetFile`, `BatchEdit`, `CameraRawMapping` (R16, R17). Color Fringes
  and Color Alignment are the first adjustment groups added since presets
  shipped. A preset saved with every group stores no group list and means
  every group, now including these two (`AdjustmentPresets.encodeGroups`,
  `docs/archive/PHASE3_PLAN.md` "Partial presets"); no stored preset or preset file is
  migrated (R16, AC13b).
- **viewport-render-1to1 (Now).** At 100%, the loupe shows the 2560 px
  live frame stretched while a control moves, and the true result only
  after the change is saved. Accepted for this feature (ruling 13).
- **Camera-cropped raws** (`docs/archive/PHASE6_PLAN.md` finding 1):
  affects R9.
- **Pixel magnifier and what is already built.** design.md needs §4 (the
  snap, what the person sees while picking, the input table), §14 and the
  checks revised, and a new section for the magnifier. The 3-point snap
  goes (ruling 18), which changes `FringePicker.snapRadius`, status.md's
  "R1 snap and refusal" check and its test, design §4 and the user guide's
  sentence on it. Today a pick decodes the full image once per click
  (`FringePicker.sample`), so following the pointer needs the sampled pixels
  ready while picking (R20, R36, OQ14). The level is a preference like the
  app's other view settings; a debug copy with its own bundle identifier
  keeps its own, as it should.
- **Pick Colors, for a later adoption (ruling 17; roadmap
  `pick-colors-magnifier`).** It samples differently from
  the fringe tool: the frame on screen, after edits, at that frame's
  resolution, with no snap, and it stays on for several clicks. It would
  need its own answers to R22 and R25.

## Assumptions

These are not owner rulings. The owner saw the first three listed as
assumptions on 2026-11-08 and did not object. The last two were not put to
the owner as assumptions: the shared level was presented as settled, and
straightening was not shown. Correct any of these freely.

- **Starting level.** The magnifier starts at 800%, on a list of 100–1600%
  in doublings (R27; the list itself was not put to the owner). The app's 100% is one photo pixel per screen pixel, so on a Retina display
  400% draws a photo pixel only 2 points wide. 800% is 4 points, which reads
  as squares; 1600% is for a 1–3 pixel fringe.
- **It appears every time** a tool picks, with no off switch.
- **HDR photos** are drawn in standard range in the magnifier; their values
  read 255 at the top of that range (R23).
- **One level for every tool**, not one per tool (R28).
- **Straightening** can leave the picture a few degrees off the view's,
  because photo pixels stay square in the magnifier. Quarter turns match
  (R29).

## Open questions

- **OQ1 (engineer): closed.** Answered in status.md ("Decisions on the
  engineer's open questions"): luminance span over a 24 full-resolution
  pixel window, scaled with the render, smoothstep 0.2–0.4. Its limit on
  very soft rims is RI-E1 below. The question as it was asked: how
  exactly "near a high-contrast edge" is defined
  (R2, R5). The person's side is settled: it is a fixed rule with no
  control (design.md §14). The rule must catch the soft edges of
  out-of-focus highlights as well as sharp ones (scene (a)'s defocused
  disc, AC1), and must count the same pixels at every size (R13, AC10).
  If M1 later shows misses that Tolerance can't fix, an adjustable rule
  is a follow-up, not part of this feature.
- **OQ2 (engineer): closed.** Answered in status.md: the decoded master,
  aligned, before any graying, at full resolution; a raw's own white
  balance coming first is the designer's DQ-1. The question as it was
  asked: which image does the picker sample? What the person
  must see is set in design.md §14: the clicked color is the one grayed,
  and a pick keeps finding the same fringe when other adjustments change
  later. If the chosen image can't hold that, it goes back to the designer
  as a Design question.
- **OQ3 (designer): closed.** Answered in design.md §2–§6 and §10.
- **OQ4 (designer): closed.** Answered in design.md. The question as it
  was asked: the list of common fringe colors (R1a): where it
  lives, how it is presented and reached (pointer, keyboard, VoiceOver),
  how a slot shows a listed color, and how it fits with the eyedropper,
  the slot's context menu and the debug-script hooks. design.md §3, §4,
  §11, §12, §15, §16 and §18 Q1 are affected.
- **OQ5 (engineer): closed.** Answered in status.md (Purple at Tolerance
  25, Green at 20, derived in `FringeToleranceDerivationTests`). The
  question as it was asked: the exact color value of each listed color
  and the range it starts with (R1c), set from the reference against
  scene (a), not by trial.

Pixel magnifier. All closed. The owner's six closed on 2026-11-08 ("Defaults
are fine.").

- **OQ6 (owner): closed.** Ruling 17: the fringe eyedropper only, built
  reusable and proved by a test tool (R34, R35, AC29, AC30). The question as
  it was asked: who uses it now?
- **OQ7 (owner): closed.** Ruling 18: the snap goes (R22, AC18). Rejected:
  keeping the 3-point snap with the outline hopping to the pixel it will
  take, and no reach at all when zoomed out. The question as it was asked:
  what about the 3-point snap?
- **OQ8 (owner): closed.** Ruling 19: the pre-edit image (R25, AC19).
  Rejected: drawing the photo as edited with pre-edit values. The question
  as it was asked: whose pixels does it draw?
- **OQ9 (owner): closed.** Ruling 20: 0–255 in Display P3 (R23, AC19).
  Rejected: 0–255 sRGB, and percentages of the working space. The question
  as it was asked: what scale are the values?
- **OQ10 (owner): closed.** Ruling 21: yes, as a Should (R24, AC20). The
  question as it was asked: show L?
- **OQ11 (owner): closed.** Ruling 22: no grip, a fixed small size. The
  question as it was asked: resize grip?
- **OQ12 (designer): closed.** Answered in design.md §20: named Pixel
  Magnifier, a round picture beside the pointer with a plate of values
  under it. The question as it was asked: the look and the name people see
  (not "loupe"): whether it sits on the pointer or beside it, its size, how
  the crosshair and the outline relate, where the values go, how it marks
  a refused spot (R26), and where the grid fades (R21).
- **OQ13 (designer): closed.** Answered in design.md §20: no control on the
  magnifier; the percentage pop-up is in the inspector, with keys `-` and
  `=` while picking, the photo's context menu and the View menu as other
  paths. The question as it was asked: how the percentage list is reached,
  since a control on a window that follows the pointer can't be reached with
  that pointer, and its keyboard and VoiceOver route (R33).
- **OQ14 (engineer): closed.** Answered in status.md ("OQ14, holding the
  pixels while picking"). The question as it was asked: how the sampled
  pixels are held while picking within R20, R30 and R36, and confirming
  R23's and R24's conversions against a CPU reference.

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
- 2026-11-07: rulings on the designer's requirements issues
  (design.md §17). The requirements stay Approved; none of these widens
  the owner's scope.
  - **RI-1, offline originals receiving automatic lateral correction:
    option A** (designer's recommendation). A paste, preset or grid batch
    that carries automatic lateral correction leaves any photo it can't
    measure (offline or unreadable) completely unchanged, and Activity
    reports it with the existing warning. This is the rule batch
    automatic exposure already follows, so no photo is half-pasted, and R8
    (measured values always stored) holds. B was rejected: it would apply a
    different look from the one pasted, with nothing to show why. C was
    rejected: it would need a new unmeasured state and break R8. New: R16a
    and AC13a.
  - **RI-2, fine-tuning an automatic correction: option A** (designer's
    recommendation). Moving either lateral slider after an automatic
    measurement starts from the measured values and makes them hand-set,
    and paste and presets copy hand-set values as they are. This follows
    the White Balance pattern the app already has (automatic, then a
    slider move makes it custom), and each slider keeps one meaning (0 is
    no shift). B was rejected: offsets tuned on one photo's measurement
    may be wrong for another's, and the sliders would no longer show the
    correction. It is consistent with ruling 10: only an automatic
    correction is measured again. R10, R16, AC7 and AC13 were updated.
  - **R12, one group or two:** the designer's two groups (fringe removal
    and lateral correction, each with its own on/off and its own preset
    group entry) satisfy R12, which I meant as "has group on/off like
    every module", not "exactly one group". R12 and AC9 were reworded. No
    change to design.md.
  - **Clarification, not new scope:** the Problem names halos around
    out-of-focus highlights, so scene (a) gains a defocused disc with a
    soft purple rim, and AC1 checks it (raised in design.md §14). OQ1 now
    holds only the engineer's definition of the edge rule; the person's
    side (fixed, no control) is settled by design.md §14. OQ3 is closed
    by design.md.
- 2026-11-07: owner ruling 15. The designer asked (design.md §18 Q1)
  whether to offer a way to fill a fringe slot from a short list of
  common fringe colors, without pointing at the photo. The owner
  answered: "It should go into this feature now." Added: R1a (Must: the
  list, plus doing the whole fringe task by keyboard and VoiceOver), R1b
  (Must: a listed color behaves exactly like a picked one), R1c (Should:
  works at its starting range), AC1a, AC1b, M2, a non-goal (no general
  color chooser), and OQ4 (designer) and OQ5 (engineer). R12 counts a
  choice from the list as one undo step. What I decided from the
  existing rulings, without going back to the owner:
  - **The list holds at least purple and green.** These are the two
    fringe colors the Problem names, and the two the designer's proposal
    named, which the owner accepted. Red/cyan and blue/yellow edges
    belong to lateral correction (R7). Any further colors wait for M1's
    evidence.
  - **Listed and picked colors are the same thing once in a slot.** This
    follows R2–R5, which apply to "a pick's range" whatever filled it, and
    design.md §10 ("Whatever their source, picks look and behave the
    same").
  - **The list adds to picking and replaces none of it.** Ruling 2's
    color picker stays the main way.

  The PRD stays Approved. The design needs revising for R1a (OQ4), so the
  roadmap row goes back from Designed to Specified until design.md is
  updated. The Later row `fringe-color-presets` is not added.
- 2026-11-08: rulings on the engineer's requirements issues (status.md
  "Requirements issues"). The requirements stay Approved; neither widens
  the owner's scope.
  - **RI-E1, soft rims beyond the fixed edge rule: accepted as built.**
    The 24-pixel rule meets OQ1 and AC1 (scene (a)'s defocused disc) and
    counts the same pixels at every size, which is all the PRD asked of a
    fixed rule. Very defocused highlights softer than about 60 full-size
    pixels may keep some color. That is a known limit, not a defect. M1 now
    checks soft bokeh rims explicitly and records what it finds. An
    adjustable edge rule stays a follow-up that is added to the roadmap only
    if M1 shows misses that Tolerance can't fix (OQ1). No engineer change.
    No roadmap row now.
  - **RI-E2, presets saved with every group: option A** (engineer's
    recommendation). "All settings" means every group, the new Lens groups
    included, so applying such a preset, old or new, clears a photo's fringe
    slots and alignment. Reasons: it is the rule the app already chose when
    presets shipped (no group list means every group, so older presets
    "keep replacing everything"); the preset list already labels these
    presets "All settings", so they do what they say; new presets check
    only the groups the photo changes, and Lightroom imports carry only the
    groups they set, so only presets someone saved with every group checked
    are affected; Manage Presets already lets the person take groups out of
    a preset; and the change is one undo step. B was rejected: it would
    need a migration of the `groups` column and of preset files, would make
    old "All settings" presets silently stop being all settings, and would
    have to be repeated for every group added later. Added: a sentence in
    R16, AC13b, and a note under Dependencies and impact. The engineer adds
    a test for AC13b, and a sentence in the user guide's Presets paragraph
    saying that a preset with all settings, including one saved before
    Color Fringes and Color Alignment existed, also replaces those two, and
    that Manage Presets can take them out of it. The behavior is built.
- 2026-11-08: scope added by the owner (ruling 16): a pixel magnifier tied
  to the pointer while picking a color. Added R19–R36, AC16–AC31, M3, scene
  (d), non-goals, Assumptions, and OQ6–OQ14. R1–R18 and their criteria are
  unchanged, except that OQ7's default would narrow the snap design §4
  specifies (no PRD criterion depends on it). What the existing record
  settled: the values come from the image the picker samples (OQ2), the app
  has one other color picker and no White Balance eyedropper, and the level
  is a preference, never part of a photo. Six questions go to the owner,
  each with its default written into the requirement it affects. R19–R36 are
  Draft until the owner answers, then the row goes to the designer. The
  engineer's Done in status.md covers R1–R18 only.
- 2026-11-08: the owner accepted all six defaults for the pixel magnifier
  ("Defaults are fine."). They are now Owner rulings 17–22, OQ6–OQ11 are
  closed, and R19–R36 move from Draft to Approved. The wording of R22, R23,
  R24, R25, R35, AC18, AC19, AC20, AC30 and the resize non-goal lost its
  open markers. What each one requires is unchanged. R22 now says outright
  that the 3-point snap is gone at every zoom, and that a click before the
  pixels are ready follows the same rule, and Dependencies says the snap goes
  rather than "if". The Pick Colors adoption is the Later roadmap row
  `pick-colors-magnifier`. Assumptions now says which ones the owner saw
  without objecting; none of them is a ruling. OQ12 and OQ13 (designer) and
  OQ14 (engineer) stay open. Next: apple-ui-designer.
- 2026-11-08: rulings on the designer's three wording issues, and on one
  check the engineer reported, after the magnifier was built. The
  requirements stay Approved; none of these widens the owner's scope.
  - **R23, "beside the outline": reworded to match design.md §20.** OQ12
    left placement to the designer, and the owner asked for values with the
    picture, not for a position. A plate under the picture hides no pixels,
    which is now what R23 asks.
  - **R22, "a pixel or two off center": removed.** It described a consequence
    I expected, not a requirement. The design and the build re-center the
    picture on the pixel taken, so the outline stays centered. The rule for
    which pixel is taken doesn't change.
  - **AC27, a click over the magnifier's drawing: split.** The debug
    script's `hit` confirms the magnifier takes no clicks. A real click can
    land on it only when the magnifier is clamped under the pointer, so that
    click moves to M3 as a person's check. R32 is unchanged.
  - **AC19's look-up table case: not satisfied as written; a test is
    needed.** AC19 names Exposure, Saturation, a look-up table and filling
    the other slot. The tests run only the first two. The code supports the
    engineer's argument (`fringeInput` depends only on Color Alignment), but
    the criterion exists to check that claim, so it can't be met by the claim.
    The engineer adds a look-up table and a filled other slot to the existing
    AC19 test ("Color Alignment changes the sampled image"). AC19's text is
    unchanged. The other slot matters most: it is the "before any graying"
    half of R25.
  - **OQ12, OQ13 and OQ14 are closed,** answered by design.md §20 and
    status.md. The Status line now says the magnifier is designed and built.
