# ML noise reduction for RAW files

Status: Approved (owner accepted every intake default, 2026-11-05)
Slug: ml-denoise
Roadmap: Next (top)

## Problem

Photographers who shoot at high ISO want to get rid of noise without
smearing detail. Today the app only has the classical tools. For RAW files,
the Luminance and Color sliders go straight to Apple's RAW decoder
(`CIRAWFilter`), and at 100 the effect is mild. Issue #35 reports that noise
reduction "has a similar problem" to the weak sharpening, and the owner asked
for an on-device ML denoise. The only alternative is to export and run
another app, which goes against keeping editing in one non-destructive
library.

macOS 27's RAW decoder version 9 (`9.dng`, "RAW 9") is itself an on-device
Core ML model. It demosaics and denoises in one step on the Neural Engine
(WWDC26 session 305). It is not on by default, so the app has to opt in per
file. On macOS 27 the app's Decoder pop-up already offers `9.dng` for
supported cameras, but nothing tells a person that this is the ML denoise.
Once it is chosen, the Color slider still shows but has no effect.

## Goal and success

A person can turn on ML noise reduction for a RAW photo and get visibly less
noise than the classical sliders at 100, while edges stay as sharp. It all
runs on the Mac, with no model shipped or downloaded and no new dependency.
It is off unless chosen, it never changes a photo nobody touched, and it
always says when it cannot apply.

We will know it worked when:

- the directional tests below pass on macOS 27; and
- the owner, looking at 2–3 of their own high-ISO raws at 1:1, judges the
  noise clearly lower than classical at 100 with no new artifacts.

## Owner rulings (2026-11-05)

1. **Source.** Apple's RAW 9 decoder only. A model we train, or
   third-party open weights, is a later and separate decision. It will be
   made after the owner has seen RAW 9 on their own files. No bundled or
   downloaded model, and no new dependency.
2. **Files.** Camera raws and DNG, Apple ProRAW included. JPEG, HEIC, TIFF
   and PNG keep the classical filter. Video is a non-goal.
3. **Fallback.** The classical sliders stay everywhere. A person can always
   tell whether ML denoise applies to a photo, and if not, why. On a Mac
   without RAW 9, or for an unsupported camera, a stack that asks for it
   renders with the default decoder, says so, and is never rewritten.
4. **When it runs.** At render time, stored in the edit stack. There is no
   step that writes a new file.
5. **Speed.** Smooth dragging is not required. Any wait shows progress and
   never blocks the window. Times measured with photobench on the owner's Mac
   are recorded. `viewport-render-1to1` is not a prerequisite.
6. **Control.** Opt-in per photo, never applied to existing photos. One
   control turns it on. Luminance is the amount, and Color is unavailable
   while it is on. It belongs to the Noise Reduction group, so copy and
   paste, presets and batch apply carry it. For a RAW+JPEG pair it applies to
   the RAW only. Fixing the classical sliders' strength is a separate roadmap
   item (`classical-noise-strength`).
7. **Export and command line.** Export and `photocli` (develop, render,
   export) support it. Tests are directional, with no pixel goldens. The
   owner does a manual check on 2–3 of their high-ISO raws.

## Users and scenarios

- **Primary.** A photographer opens a high-ISO raw in the loupe and turns on
  ML noise reduction. They wait briefly while progress shows, then set
  Luminance to taste. They save, zoom to 1:1 (Z), compare with Show Original
  (`\`) and export. The export matches what they saw.
- **Batch.** They copy the adjustments of one photo from a high-ISO set and
  paste them onto the other 40 in the grid. Each RAW gets ML noise reduction.
  The JPEGs in the selection do not.
- **Older Mac.** The same library opens on a Mac running macOS 26. Those
  photos render with the default decoder and classical noise reduction, and
  the app says ML noise reduction is not available on this Mac. The edit
  stack keeps the setting, so back on macOS 27 the photos render with ML
  again.
- **Unsupported camera.** A raw from a camera that RAW 9 does not list: the
  control says why it is unavailable.

## Requirements

**R1 (Must).** A RAW photo (one of the extensions in
`SupportedFormats.rawExtensions`, DNG and ProRAW included) can have an ML
noise reduction setting in its edit stack. When it is on and available, the
photo is decoded with RAW 9.

**R2 (Must).** It is off by default. Adding the feature changes nothing in
the rendering, previews or exports of any photo that has not turned it on.

**R3 (Must).** Exactly one state means "ML noise reduction on". The new
control and the Decoder pop-up's `9.dng` choice cannot disagree. A stack
that already chose `9.dng` before this feature shipped shows as ML noise
reduction on, and its rendering does not change.

**R4 (Must).** While it is on, Luminance is its amount. Color is shown as
unavailable, because RAW 9 ignores it. The stored Color value is kept and
applies again when ML is turned off.

**R5 (Must).** For the photo being edited, the app shows whether ML noise
reduction applies. If it does not, it names one of these reasons:

- this Mac's macOS has no RAW 9;
- this camera is not supported by RAW 9;
- the file is not RAW.

**R6 (Must).** When a stack asks for ML noise reduction where it is
unavailable (R5's first two reasons), the photo renders with the default
decoder and the stack's classical values. The app shows that ML was not
applied. Opening, viewing, exporting, or editing any other control never
removes the setting from the stack. The only exception is the person turning
it off.

**R7 (Must).** Files that are not RAW keep today's Core Image filter
unchanged. The ML control is not offered for them. Videos are unaffected.

**R8 (Must).** Rendering with ML noise reduction runs off the main thread in
the loupe, grid thumbnails and export. While the loupe waits for such a
render, it shows progress. The window stays responsive throughout: culling,
moving between photos and the other controls all keep working. There is no
frame-rate requirement while a slider is dragged.

**R9 (Must).** Turning it on or off is one undo step. Each Luminance change
is one undo step per gesture, as today.

**R10 (Must).** It belongs to the Noise Reduction group. Copy and paste,
presets that include that group, the grid's batch commands (Paste, Apply
Preset) and Reset All carry it or clear it. Applied to a selection that
mixes file types, it takes effect on RAW files only. Non-RAW photos never
show it as on.

**R11 (Must).** For a RAW+JPEG pair, it applies to the RAW file's edits
only. Edits are already per file, so this changes nothing about how pairs
work.

**R12 (Must).** Export renders ML noise reduction at full resolution, the
same way the loupe shows it.

**R13 (Must).** `photocli` supports it:

- `develop` sets and resets it;
- `adjustments` lists it among the parameters;
- `render` and `export` render with it.

The fallback (R6) also applies there, and the JSON output says whether ML
was applied.

**R14 (Must).** photobench has a case that times a 24 MP raw with ML off
and on at three outputs: thumbnail, 2560 px preview, and full-resolution
export. Times measured on the owner's Mac are recorded in this PRD
(Measurements) before the feature ships.

## Acceptance criteria

**AC1 (R1, R12).** On macOS 27, a synthetic Bayer DNG with 2 % noise (the
`RAWDecodeTests` fixture) is rendered twice: with ML at Luminance 100, and
classical at Luminance 100 and Color 100. The ML render has lower
high-frequency energy in flat areas. Both the full-resolution export path
and `photocli render` show this. On a Mac without RAW 9 the test is skipped,
and the skip names the reason.

**AC2 (R1).** On the same kind of fixture made from an edge scene, the ML
render's edge contrast is not lower than classical at 100.

**AC3 (R2).** Every existing golden, and the edit-stack corpus
(`EditStackCorpusTests`), pass unchanged. A stack without the setting
produces the same render hash and preview cache key as before.

**AC4 (R3).** A stack saved with `decode.decoderVersion = "9.dng"` loads as
ML on. A stack with ML on reports `9.dng` as its decoder. The two can never
be set to disagree, through the app or through `photocli develop`.

**AC5 (R4).** With ML on, the Color control is unavailable. Turning ML off
restores the stored Color value: the stack's `color` is unchanged across
the on/off round trip.

**AC6 (R5, R7).** Manual check, and a unit test of the availability rule. A
supported raw on macOS 27 shows ML as available. A JPEG shows the "not RAW"
reason, or no ML control at all. A camera missing from RAW 9's
`supportedCameraModels` shows "camera not supported". On macOS 15 or 26,
any raw shows "not available on this Mac".

**AC7 (R6).** On a Mac without RAW 9, take a stack with ML on and do all of
the following:

- open it in the loupe;
- change Exposure and save;
- export it;
- run `photocli develop` on another parameter.

Afterwards the stack still has ML on. The export used the default decoder.
The loupe shows that ML was not applied.

**AC8 (R8).** Manual check on the owner's Mac. Turn ML on for a 24 MP raw.
Progress shows until the frame arrives. Meanwhile, the arrow keys move to
the next photo and rating keys still work.

**AC9 (R9).** Turning ML on, then pressing ⌘Z, returns the stack to its
previous bytes. A Luminance drag is one undo step.

**AC10 (R10, R11).** Copy from a raw with ML on, then paste onto a selection
of one raw, one JPEG and one RAW+JPEG pair. The raw and the pair's RAW have
ML on. The JPEG and the pair's JPEG do not. A preset saved with the Noise
Reduction group carries the setting, and Reset All clears it.

**AC11 (R13).** `photocli adjustments` lists the parameter. `photocli
develop --dry-run` with it on prints a stack with ML on. `render` and
`export` JSON say whether ML was applied.

**AC12 (R14).** The photobench case runs. Its six times appear under
Measurements.

**AC13 (goal).** Manual check by the owner on 2–3 of their own high-ISO raws
at 1:1. Noise is clearly lower than classical at 100 and there are no new
artifacts. The cameras used are recorded here.

## Measurements

To fill in from R14 on the owner's Mac.

| Output | ML off | ML on |
|---|---|---|
| Thumbnail | | |
| 2560 px preview | | |
| Full-resolution export | | |

## Non-goals

- ML noise reduction for JPEG, HEIC, TIFF or PNG, and for video.
- A model we train, or third-party weights, bundled or downloaded.
- Writing a new denoised file (DNG or otherwise) next to, or in place of,
  the original.
- Changing the classical sliders' strength, or where the non-RAW filter runs
  in the pipeline. That is `classical-noise-strength`.
- Smooth slider dragging with ML on, and rendering the visible area at 1:1
  (`viewport-render-1to1`).
- Turning ML on by default, or for photos already in the library.
- ML noise reduction inside masks (local).
- Mapping Lightroom presets or Lightroom's own denoise onto this setting.
- The sharpening half of issue #35.

## Dependencies and impact

- **Edit stack and rendering.** The setting lives in the Noise Reduction
  group (`NoiseReduction` in `Adjustments.swift`) or in `decode`; that is
  the engineer's choice, within R3. Both reach the decoder through
  `RAWDecodeSettings` in `Edits/EditStackRenderer.swift`.
  - The render hash covers the setting, so preview caches stay separate.
  - Whether a pipeline version bump is needed is the engineer's call, under
    R2 and AC3.
- **Live editing.** A change re-decodes the photo (`LiveRenderSession`).
  RAW 9 is heavier than earlier versions. Draft and scaled decodes behave
  differently under RAW 9; see the open questions.
- **Defaults and sliders.** `RawDefaults` reads the decoder's defaults at its
  default version. With RAW 9, the defaults for Luminance and Color may
  differ.
- **Tests and CI.** CI runs on macOS 15 and 26, so the ML tests (AC1, AC2)
  are skipped there and run only on macOS 27 (the owner's Mac). RAW goldens
  are already fingerprinted per macOS build. This feature adds no pixel
  goldens.
- **Compatibility.** Older builds of the app keep unknown parameters. A
  stack with ML on, opened in an older build, renders whatever that build
  understands. If the setting is `decoderVersion = "9.dng"`, older builds
  already apply it where macOS 27 has RAW 9.
- **Strings.** New user-facing text goes into `Localizable.xcstrings`.
- **Docs.** `docs/USER_GUIDE.md` is updated with the change, by the
  engineer.

## Assumptions

- RAW 9 support is decided per file at run time: `supportedDecoderVersions`
  contains `9.dng`. Apple widens the camera list through OS updates, so a
  photo that was unsupported can become supported without any change in the
  app.
- RAW 9 ignores `colorNoiseReductionAmount`, as WWDC26 session 305 says.

## Open questions

- **Owner.** Which 2–3 cameras and high-ISO files for AC13? Are those
  cameras on RAW 9's supported list?
- **Owner.** The time ceiling, if any, once R14's measurements are in. None
  was named; none is assumed here.
- **Engineer.** I assumed macOS 27 runs only on Apple silicon, so the Neural
  Engine is always present where RAW 9 exists. If an Intel Mac can run 27,
  does RAW 9 still appear in `supportedDecoderVersions` there, and how fast
  is it?
- **Engineer.** Does RAW 9 honor `extendedDynamicRangeAmount`? This matters
  for highlight recovery, negative exposure and the HDR rendition of float
  DNGs. If not, what do the loupe and export show? Return a requirements
  issue if this needs a ruling.
- **Engineer.** Does the synthetic DNG decode through RAW 9? If not, AC1 and
  AC2 need another fixture we may commit; say what.
- **Engineer.** Do draft mode and `scaleFactor` work under RAW 9 for
  interactive frames and thumbnails?
- **Designer.** Where the control lives and its name. Whether it merges with
  the Decoder pop-up (R3). How availability, "not applied" and progress are
  shown (R5, R6, R8).

## Revisions

- 2026-11-05: first version, from intake answered with all defaults.
