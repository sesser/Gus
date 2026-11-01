# Phase 6 plan: local adjustments with masks

Status: **plan, waiting for approval of the six decisions below.** Step 0
(the Phase 5 gaps) is done. No code that changes saved edit stacks has been
written.

Masks let the global adjustments act on part of a photo: a linear gradient,
a radial gradient, a brush, a luminance range and a color range, combined
into one alpha per mask. The architecture and naming rules in `CLAUDE.md`
still apply; this file records the decisions and why.

Out of scope: AI masks (subject, sky, object), people and face masks,
healing, lens corrections, mask presets, sync, and writing masks to XMP
sidecars. Presets and copy and paste leave masks out in this phase, and the
UI says so.

Reference material: LightCraft (MIT or Apache-2.0), cloned to a scratch
folder outside the repository at commit `07301cb`, read only:
`crates/pipeline/src/masks.rs`, `crates/develop/src/settings.rs`,
`crates/pipeline/src/local.rs`, `crates/ui-egui/src/panels/masking.rs`.
Where its math is ported, the code says so and `THIRD_PARTY_NOTICES.md`
carries its notice (see "Third-party code").

## Step 0: the Phase 5 gaps (done)

Three commits on `feature/phase6`, suite green (324 tests, 8.3 s, one known
issue):

- **Goldens added** (13): look-up tables (a built-in table at full
  intensity, one at half, one read in ProPhoto RGB), non-RAW noise reduction
  (two strengths), and the RAW decoder's settings over the synthetic Bayer
  DNG: as shot, Kelvin 3200, Kelvin 8000 with tint +30, the Tungsten preset,
  the flat and neutral looks, extended range (asked for by negative
  exposure) and decoder noise reduction. A test checks that each RAW setting
  changes the decode, so a setting the decoder ignores cannot pin the
  as-shot image under another name. Not covered: `decoderVersion` (the
  versions offered change with the macOS release) and the whole-sensor
  decode (`CameraFrame`, Olympus, OM System and Panasonic files only).
- **Large render** (`LargeRenderTests`, `LARGE_RENDER_TESTS=1`): the
  runtime blur kernel over an image 16 384 + 640 pixels wide, wider than an
  Apple GPU texture, so Core Image splits the render itself (12 passes
  against 4 for a narrow image, from `CIRenderInfo.passCount`). It matches
  `BlurReference` within the existing 1e-5 (measured 2.4e-7). About 22 s in
  a debug build, mostly drawing the supersampled scene and the CPU
  reference. Tiles only split along x: a render taller than a texture too
  would make the reference take minutes.
- **A new harness check**: every golden case must change its scene.

### Findings (reported, not fixed)

1. **Negative clarity does nothing.** `CIUnsharpMask` clamps its intensity
   at 0 (its attribute minimum), so `AdjustmentRenderer.clarity` with a
   negative amount returns the input, and the Phase 5 golden
   `clarity-minus40-hazyLandscape` pins the unchanged scene. The new check
   records it as a known issue. Fixing it changes the render of every stack
   with negative clarity (a `currentPipelineVersion` bump and that golden).
   Local clarity at −100 (softening) is one of the main uses of a mask, so
   this needs a decision before local clarity ships. **Question A.**
2. **`grain-coarseColor-patchChart` no longer reproduces bit for bit** on
   the machine that made it (macOS 27.2, M4 Pro): up to 0.00012 in green,
   PSNR 124 dB, well inside the tolerance. Unchanged `develop` gives the same
   numbers, so it predates this branch. The golden is unchanged.
3. **`UPDATE_GOLDENS=1` rewrites goldens that pass.** It rewrites every
   golden whose bytes differ, so adding new goldens also rewrote
   `grain-coarseColor-patchChart` (finding 2), which then had to be restored
   by hand. Rewriting only the goldens a filter names, or only those outside
   the tolerance, would prevent that. **Question B.**
4. **A RAW decode can come back empty without an error.** The synthetic DNG
   at 256 × 192 (and 258 × 194) decodes to an empty image (native size
   0 × 0) while 300 × 200 and larger decode; the cause is not found.
   `PreviewGenerator.decode` returns the empty image as a successful RAW
   decode rather than falling back to ImageIO or throwing `undecodable`. The
   RAW goldens use 320 × 240.
5. **An unreadable stack is edited as if it were empty.**
   `AdjustmentEditor.swift:134` and `AdjustmentActions.swift:16` take
   `(try? decodedEditStack()) ?? .identity`, so a stack this build cannot
   decode (one written by a newer build, `unsupportedSchemaVersion`) is
   shown unedited, and the first slider move saves over it: the newer
   edits are lost. This matters for decision 2. **Question C.**
6. **Non-RAW noise reduction runs late**: after the look-up table and the
   vignette, so it smooths what they did and the vignette's gain has already
   amplified the noise. Not changed; it matters for where local sharpening
   goes (decision 3).

### Tests to watch on the first CI run

The CI runners (`macos-26`, and `macos-15` with Xcode 26.3) are the first
machines other than the one the goldens were made on (macOS 27.2), and
their GPU is virtual. In order of how likely they are to differ:

1. `GoldenTests.rawDecodeMatchesGolden` and
   `GoldenTests.rawSettingsTakeEffect`: the RAW decoder changes between
   macOS releases (its default decoder version, boost, noise reduction), so
   these may fail on both runners for reasons that are not GPU noise. The
   empty-decode quirk (finding 4) may also sit at another size there.
2. `GoldenTests.moduleMatchesGolden`: dehaze (an area reduction, the largest
   difference between contexts on this Mac), the two noise reduction cases
   and the three look-up table cases (Core Image filters whose
   implementation can change with macOS), grain.
3. `GoldenHarnessTests.rendersAreRepeatable` and
   `GoldenHarnessTests.casesChangeTheirScene`.
4. `RuntimeKernelTests`: runtime Metal compilation on a virtual GPU.
5. `ReferenceTests`: the half-float bounds should hold anywhere; a failure
   there would mean the runner's working format is not half float.

`LargeRenderTests` does not run in CI. CI does not set `GOLDENS_REPORT=1` or
keep `$TMPDIR/golden-failures`, so a failure there shows the measures but not
the image. Setting the variable on the test step and uploading that folder
as an artifact when the step fails would make the first run readable.
**Question D.**

## Decision 1: coordinate space

**Recommended**: shapes are stored in unit coordinates of the **mask frame**,
and sizes as fractions of its long edge.

- **The mask frame** is the decoded master after its EXIF orientation and
  before the quarter turns, straightening and crop: the image `Crop.apply`
  receives. Origin top left, x right, y down, 1 × 1 whatever its size (as
  `CropRect`). Changing the crop, the turns or the straightening never moves
  a mask off its subject, and a render at any size places it on the same
  pixels.
- **Sizes** (a brush's radius, a radial gradient's radii) are fractions of
  the mask frame's long edge, so a circle stays a circle in pixels. Points
  (gradient ends, brush samples, the radial center) are unit coordinates on
  each axis.
- **Rendering**: each mask is generated in the mask frame at the decode's
  pixel size, then sent through the same `Crop.apply` as the photo. Mask and
  photo then share one transform, including the crop rectangle's rounding to
  whole pixels, so alignment is by construction and not by a second copy of
  the math.
- **Mapping for the overlay** (`CropGeometry`, new functions, tested both
  ways and against `Crop.apply`). With the mask frame W × H pixels, the turned
  frame W′ × H′ (swapped for odd turns), θ = 90° × quarter turns + straighten
  angle (clockwise positive, y down) and R(θ) = [[cos θ, −sin θ], [sin θ,
  cos θ]]:
  - centered pixels: s = (u·W − W/2, v·H − H/2);
  - turned frame, unit: t = ((R(θ)s)ₓ + W′/2) / W′, ((R(θ)s)ᵧ + H′/2) / H′;
  - output, unit: o = ((tₓ − rect.x) / rect.width, (tᵧ − rect.y) /
    rect.height); the inverse runs the other way with R(−θ). This matches
    `CropGeometry.unrotated`, which is R(−angle) on the turned frame.
  - A radial gradient's rotation is stored in the mask frame; the overlay
    shows rotation + θ.
  - The overlay may sit up to half a pixel from the render, because
    `Crop.apply` rounds the crop rectangle; the render itself does not.
- **Raw files with a camera crop** (Olympus, OM System, Panasonic at 1:1,
  3:2 or 16:9): the frame the decoder gives depends on whether the stack has
  a crop (`RAWDecodeSettings.fullFrame`). The mask frame is the **whole
  sensor**, the frame a crop rectangle already uses. A stack with masks
  always decodes the whole sensor; when it has no crop of its own, the
  renderer crops to the camera's frame (`CameraFrame.rect`, passed in
  `RenderContext`), so adding a mask never changes the framing. Only these
  formats are affected, and stacks without masks decode as before.

## Decision 2: persisted shape

`EditParameter` has number, bool, string and list, but no nested object.

**Recommended: add an object case**, `case object([String: EditParameter])`,
and keep everything else as it is.

- **Unchanged bytes**: no existing stack contains an object, and the other
  cases encode exactly as before, so a stack without masks keeps identical
  JSON and render hash. A corpus test records the JSON and render hash of a
  set of stacks (every golden case, a crop, a preserved unknown operation, a
  disabled module) **before** the change, in its own commit, and asserts
  them afterwards.
- **Schema version per stack**: a stack that contains an object anywhere is
  written with `schemaVersion` 2; every other stack keeps 1. Mask-free
  stacks therefore keep their bytes, and a build that predates objects
  refuses a masked stack with the existing `unsupportedSchemaVersion` error
  instead of failing on an unknown value. Decoding accepts 1 and 2.
- **Unknown operations** stay preserved: `EditParameter` decodes objects, so
  an operation of a kind this build does not know (or a newer
  `kindVersion`) is kept whatever its parameters hold.
- **One operation** of a new generic kind, `localAdjustments`
  (`kindVersion` 1), placed in the stack at its render position, with one
  parameter `masks`: a list of objects. Defaults are left out at every level,
  as for the modules. Example:

  ```json
  {"kind": "localAdjustments", "kindVersion": 1, "isEnabled": true, "id": "…",
   "parameters": {"masks": [
     {"id": "6F1C…", "name": "Sky", "amount": 80,
      "components": [{"shape": "linear", "startX": 0.5, "startY": 0.1, "endX": 0.5, "endY": 0.45}],
      "adjustments": {"exposure": -0.7, "dehaze": 20}},
     {"id": "A03B…", "name": "Face", "isEnabled": false,
      "components": [{"shape": "brush", "strokes": [{"size": 0.02, "flow": 60,
                      "points": [0.412, 0.318, 0.415, 0.321]}]},
                     {"shape": "luminanceRange", "operation": "intersect", "lower": 0.3, "upper": 0.8}],
      "adjustments": {"clarity": -40}}]}}
  ```

  Brush points are a flat list x, y, x, y… rounded to 10⁻⁶ of the frame
  (0.006 px on a 6000 px edge), which keeps long strokes compact.
- **Limits** when reading (so a stack from `photocli` or a damaged file
  cannot stall a render): 32 masks, 16 components per mask, 8 color samples,
  and 200 000 brush points per mask; values outside a parameter's range are
  clamped as the modules do.
- **Downside**: a build from before this phase cannot read a masked stack at
  all, and because of finding 5 it would show the photo unedited and
  overwrite the stack on the first edit. Fixing finding 5 now (Question C)
  protects every build from this one on; it cannot protect builds already
  installed.

**Alternative: flat lists.** Each mask as a positional list
(`["linear", "add", false, 0.5, 0.1, 0.5, 0.45, 100]`), strokes as lists of
numbers. Older builds would read the stack and keep the unknown operation,
which is its one advantage. Against it: positions instead of names, so
every new field is a `kindVersion` bump and a migration; nested brush data
does not fit without conventions of our own; and healing and lens
corrections will need nested parameters too. Not recommended.

A disabled mask stays in the render hash (its operation is enabled), so
changing one of its sliders misses the preview cache once. Harmless; noted.

## Decision 3: position in the render order

**Recommended**: masks run **after color grading and before the look-up
table**, that is after every global tone and color module and before the
Effects heading (look-up table, vignette, grain) and the detail steps (noise
reduction, sharpening).

1. Turns, straightening, crop
2. White balance, exposure, local tone, dehaze, clarity, tone table, color
   mixer, vibrance, saturation, color grading
3. **Masks, in list order**
4. Look-up table, vignette, noise reduction (non-RAW), sharpening, grain

Why:

- Local adjustments correct scene content (a sky, a face), so they belong
  with the global corrections. The look-up table, vignette and grain are
  finishing effects of the whole frame: a vignette should darken the
  locally brightened subject like the rest, and grain should lie evenly over
  local changes instead of being smoothed or sharpened by them.
- A look-up table works on 0 … 1 values and may clip; local exposure after
  it would push values it has already clipped.
- Masks see the image the user sees after the global sliders, so a local
  adjustment adds to the global one.
- **Exceptions, so each control acts where its global module does:**
  - *Local sharpening* is applied at the sharpening step (after noise
    reduction, finding 6), as a second unsharp mask blended by the same
    mask. At the mask step it would be smoothed by noise reduction.
  - *Local dehaze* uses the haze estimate (dark channel and airlight) taken
    where global dehaze takes it, from the whole frame before any dehaze.
- **Range masks select on the image entering the mask step**, the same image
  for every mask, so reordering masks never changes what a range selects.

## Decision 4: combining components

**Confirmed**, with one rule for the first component:

- Each component gives c in 0 … 1; its invert flag makes it 1 − c before it
  is combined.
- Components combine in list order into a: Add a ← max(a, c); Subtract
  a ← a · (1 − c); Intersect a ← a · c.
- **The first component** starts from the identity of its own operation:
  a₀ = 0 for Add and a₀ = 1 for Subtract and Intersect. So a first Add is c,
  a first Subtract is 1 − c ("everything except"), and a first Intersect is
  c. One rule, with no special case in the code, and no component does
  nothing. LightCraft differs: it takes a first Subtract as c (as if Add) and
  a first Intersect as nothing.
- The mask's **Amount** (0 … 100) scales the result: α = a · amount / 100.
  A mask with no components, or turned off, has α = 0.
- **Invert is per component.** A radial gradient's "invert" is that flag,
  not a second one on the shape. There is no invert for a whole mask in this
  phase (LightCraft has one); with it, "everything outside these three
  brushes" would take one click instead of a first Subtract. **Question E.**
- Reference tests with exact values on 4 × 1 planes: for a = 0.6 and
  c = 0.5, Add 0.6, Subtract 0.3, Intersect 0.3; invert, the first-component
  rule, and Amount, all in Double, and the GPU result within half-float
  rounding of them.

## Decision 5: applying local adjustments

**Confirmed**: result = blend(base, adjusted, α), where adjusted runs the
existing `AdjustmentRenderer` steps over the whole frame with only the
modules that have non-default local values, in the fixed order, and the
blend is `CIBlendWithMask`. Each mask in the list sees the result of the
ones before it.

Local controls in v1 and the module each one drives:

| control | range | module |
|---|---|---|
| exposure | −4 … +4 EV | `Exposure.ev` |
| contrast, highlights, shadows, whites, blacks | −100 … +100 | `Tone` |
| temperature, tint | −100 … +100, relative | `relativeWhiteBalance` (RAW files too: the decoder's Kelvin stays global) |
| vibrance, saturation, clarity, dehaze | −100 … +100 | `Presence` |
| sharpen | 0 … 100 | `Sharpen.amount`, at the sharpening step |

- **Whole-image estimates**: local tone's smoothed luminance comes from the
  whole frame at the mask step, and local dehaze's haze estimate from the
  whole frame before dehaze (decision 3), never from the masked region.
- **What the blend means for soft edges**: blending outputs is linear in α,
  not in the slider. Where α = 0.5, a +2 EV mask gives (1 + 4) / 2 = 2.5×
  (+1.32 EV) rather than +1 EV. Transitions stay smooth and monotonic, so
  gradients look right, but half a mask is not half the slider. Scaling the
  parameter per pixel would need a kernel for nearly every module, which is
  out of proportion for v1. Exposure alone could later be made exact with a
  gain map, as the vignette does, if it shows.
- Negative clarity depends on Question A.

## Decision 6: mask resolution and caching

- **Resolution**: masks are computed in the mask frame at the decode's pixel
  size, which is the render's resolution (enlarged by the crop's zoom, as
  the photo is), then go through `Crop.apply` with the photo.
- **Gradients and ranges** are lazy Core Image graphs of stock filters,
  rebuilt for each render and fused by Core Image with their neighbors.
  Nothing is stored.
- **Brush strokes** are stored as points and rasterized at the render size
  for each render size, never as a bitmap that gets scaled. Rasterizing
  runs on the CPU in plain Swift into a `Float` plane (the dab profile and
  accumulation are exact there, and testable against the reference); the
  plane goes to Core Image as half float. Rasterized planes are cached in
  memory by (mask hash, pixel size), least recently used first out, at most
  256 MB. While a stroke is being painted, only its new dabs are drawn into
  the cached plane.
- **Memory at 24 MP** (6000 × 4000):

  | | per mask |
  |---|---|
  | brush, while rasterizing (`Float`) | 96 MB |
  | brush, cached (half float, one channel) | 48 MB |
  | gradient or range | nothing stored; Core Image works in tiles |
  | adjusted image of a mask with a neighborhood module (local tone, clarity, dehaze) | up to one RGBA half-float frame, 192 MB, while it renders; Core Image tiles it within its memory target |

  An export with three brush masks holds about 144 MB of masks plus Core
  Image's working memory. At the loupe's 2560 × 1707 a brush plane is
  8.7 MB.

## Shapes

All formulas take pixel centers. smoothstep(e₀, e₁, x) = t²(3 − 2t) with
t = clamp((x − e₀)/(e₁ − e₀), 0, 1).

- **Linear gradient**: start and end points and Feather (0 … 100, default
  100). With t the position along start → end (0 at start, 1 at end),
  c = 1 − smoothstep(½ − f/2, ½ + f/2, t), f = feather / 100: full effect
  on the start side, none past the end, the transition spread over the whole
  distance at 100 and a hard edge at the middle at 0. **Question F**: your
  scope says "two points, feather"; this is my reading of it.
- **Radial gradient**: center, radii rx and ry (long-edge fractions),
  rotation, Feather 0 … 100. With r the elliptical distance (1 on the
  ellipse), c = 1 − smoothstep(1 − f, 1, r); inside the ellipse by default,
  outside with the component's invert.
- **Brush**: strokes of points with Size (radius, long-edge fraction),
  Feather, Flow, Density and an Erase flag. Each segment between samples
  gets dabs spaced a quarter of the radius apart (in long-edge units, so the
  dabs fall on the same scene points at every resolution); a sample that
  does not move lays none. A dab paints 1 inside its hard core
  (radius × (1 − feather)) and 1 − smoothstep(core, radius, d) outside.
  Within a stroke dabs accumulate as v ← v + a · flow · (density − v), so
  coverage builds with flow and approaches Density without passing it.
  Strokes combine with max, and an erasing stroke multiplies by 1 − v. The
  dab profile and the quarter-radius spacing follow LightCraft's; the
  accumulation toward Density is ours (LightCraft adds toward 1 and clamps
  at Density).
- **Luminance range**: Lower and Upper (0 … 1) and Smoothness (0 … 1) on
  the luminance in the perceptual encoding (Rec. 2020 Y, sRGB curve):
  c = smoothstep(lower − s, lower, y) · (1 − smoothstep(upper, upper + s, y)).
- **Color range**: up to 8 sampled colors in OkLab, and Tolerance 0 … 100.
  With d the smallest distance to a sample, chroma weighted as LightCraft
  does (√(Δa² + Δb² + ¼ ΔL²)), and τ = 0.015 + 0.06 × tolerance / 100,
  c = 1 − smoothstep(τ/2, τ, d). OkLab of linear Rec. 2020 clamped to 0 … 1.
  The weighting and τ's range come from LightCraft.

## Kernels

**None planned.** Every shape fits the stock route:

- Linear: `CISmoothLinearGradient`, if a reference test shows it is exactly
  smoothstep; otherwise `CILinearGradient` through a 4096-entry
  `CIColorCurves` table (linear interpolation of smoothstep there is off by
  at most 0.75/4095², 4.5 × 10⁻⁸).
- Radial: `CIRadialGradient` scaled into the ellipse (as the vignette does)
  through a smoothstep table.
- Ranges: `CIColorMatrix`, `CIColorClamp`, `CIGammaAdjust` (cube roots for
  OkLab, a square root for the distance), `CIMultiplyCompositing` for
  squares, `CIMinimumCompositing` over samples, then a smoothstep table.
  Pointwise, so Core Image fuses them.
- Combining: `CIMaximumCompositing`, `CIMultiplyCompositing` and
  `CIColorMatrix` for 1 − c and the Amount.
- Brush: CPU (above), not a kernel.

If one of these misses its reference by more than its tolerance (the gamma
route in half float is the likeliest), the runtime-kernel route of Phase 5
is the fallback for that shape only, and this file will say which and why.
Half float throughout.

## Verification

- **Each shape**: a CPU reference of its formula in Double
  (`Reference/MaskReference.swift`), the GPU mask rendered alone and
  compared within a stated tolerance (half-float storage, plus the table
  bound where one is used), and a golden of a local adjustment through it on
  a test scene.
- **Combining**: the exact values of decision 4 on small planes.
- **Crop, straighten and mask**: the same stack with a radial mask and two
  crop rectangles that overlap, at the same straighten angle. `Crop.apply`
  rounds rectangles to whole pixels, so the overlapping pixels are the same
  resampled positions and must agree within half-float rounding. A second
  test changes the angle and checks that the mask's centroid lands where the
  decision 1 mapping puts the center, within half a pixel.
- **Brush at two resolutions**: the mask rasterized for a full-size export
  and the one for the 2560 px preview, scaled up bilinearly, compared. Linear
  interpolation of the dab profile is off by at most (1/8) · max|c″| =
  0.75 / w² for a falloff w preview pixels wide; the test uses a stroke with
  w ≥ 8 (bound 0.012) plus half-float rounding, and says so.
- **Hash stability**: the corpus test (decision 2) and every existing golden
  unchanged. If an existing output has to change, I stop and say why; an
  intended change bumps `PreviewCacheKey.currentPipelineVersion` in its own
  commit with a one-line reason.

## UI

- **Masks** heading in the Adjust tab (after Color Grading): the list with
  Add (a menu of the five shapes), rename, an on/off check box, delete, and
  move up and down (`AppKitButton`s, inside `AppKitScrollView`). The selected
  mask shows its components (shape, operation menu, invert check box, add
  and remove), Amount, and the local sliders.
- **On the loupe** (`MaskOverlayView`, built like `CropOverlayView`, driven
  by `AdjustmentEditor`): handles for gradient ends, the radial center,
  radii and rotation; a brush cursor with its size and feather rings; a
  toggle for a red overlay of the selected mask's α. Each drag, stroke or
  typed value is one undo step through `AdjustmentEditor`, rendered live
  through the `LiveRenderSession`.
- Presets and copy and paste leave masks out; the Presets section and the
  paste command say "Masks are not included".
- Strings go through the String Catalog. Shapes get SF Symbols, no icons of
  another app.

## Scripting

- Command registry: `mask list --version N`, `mask add --version N --shape
  linear|radial|brush|luminanceRange|colorRange …`, `mask set --version N
  --mask ID mask.amount=… local.exposure=… component.0.feather=…`, `mask
  remove --version N --mask ID`. Writes take the library lock, like
  `develop`.
- `render --stack` accepts masked stacks unchanged (they are stacks).
- `adjustments` gains the local controls and each shape's parameters
  (name, type, range, default), described next to the model as the modules
  are.
- Debug script: `mask add <shape> …`, `mask select N`, `mask overlay on|off`,
  `brush <x0> <y0> <x1> <y1> …`, for snapshots of each state.

## Performance

`photobench masks`: a 6000 × 4000 synthetic DNG, a live session at the
loupe's 2560 px, three masks (linear, radial, a brush of 20 strokes), each
with exposure, contrast and clarity. Reported: milliseconds per frame (first,
mean, p95), brush rasterization alone, and memory (physical footprint). The
budget is the one live edits meet today with a typical stack (36 ms per
frame for a DNG): three masks should stay under 100 ms p95. Over budget, the
report says where the time goes (which mask's modules, rasterization, the
blend) before anything is optimized.

## Order of work after approval

1. The hash-stability corpus, recorded on today's code.
2. `EditParameter.object` and per-stack schema versions.
3. The mask model in `Adjustments` (reading, writing, limits), with tests.
4. Mask-frame mapping in `CropGeometry`, with tests.
5. Shapes, one commit each with its reference and golden; combining.
6. Renderer: the mask step, local sharpening at the sharpening step, the
   dehaze estimate, the camera-frame crop; the crop and resolution tests.
7. Commands, then the debug-script commands.
8. UI: the Masks heading, the overlay, the brush.
9. `photobench masks`, profiling, and this file's results.

`swift build` and `swift test` after each commit.

## Questions before code that persists data

1. **Decisions 1–6**: approve, or change.
2. **A.** Fix negative clarity (finding 1) before local clarity ships, as its
   own commit with a pipeline version bump and the changed golden?
3. **B.** Change `UPDATE_GOLDENS` to rewrite only goldens outside the
   tolerance (finding 3)?
4. **C.** Make the editor refuse to edit a stack it cannot read instead of
   starting from an empty one (finding 5), before any schema 2 stack exists?
5. **D.** Set `GOLDENS_REPORT=1` in CI and upload `golden-failures` when tests
   fail?
6. **E.** An invert for a whole mask, besides each component's?
7. **F.** The linear gradient's Feather as described under Shapes?

## Third-party code

Ported from LightCraft, with a comment at each place and its MIT notice in
`THIRD_PARTY_NOTICES.md` when the code lands: the brush dab profile and
quarter-radius spacing, the radial falloff, and the color range's distance
weighting and tolerance range. The combine operations are standard. Its
code, UI, icons, presets and strings are not used.
