# ML noise reduction for RAW files

Status: Shipped 2026-11-05, PR #39. Checks pending: P1–P9 in qa.md "For a person" (AC13 is P9; the RI-E6 (d) check is P8, which the owner accepted shipping without, 2026-11-06), done under `ui-redesign-onscreen-check`. Design check M9 failed in QA (qa.md Q1; roadmap `loupe-caption-narrow`).
Slug: ml-denoise
Roadmap: Shipped

## Problem

Photographers who shoot at high ISO want to get rid of noise without
smearing detail. Today the app only has the classical tools. For RAW files,
the Luminance and Color sliders go straight to Apple's RAW decoder
(`CIRAWFilter`), and at 100 the effect is mild. Issue #35 reports that noise
reduction "has a similar problem" to the weak sharpening, and the owner asked
for an on-device ML denoise. The only alternative is to export and run
another app, which goes against keeping editing in one non-destructive
library.

macOS 27's RAW decoder version 9 ("RAW 9") is itself an on-device
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
8. **Future macOS defaults (RI-7, "Yes, pin old default").** R2 covers
   these too. A raw whose stack does not ask for ML keeps decoding with the
   pre-RAW 9 default decoder, even if a later macOS makes RAW 9 Apple's
   default. The engineer pins that default.
9. **Apple's on-demand model (RI-E2, "Allowed, never trigger it").**
   macOS's own on-demand RAW 9 model may be used, but only when macOS
   already has it. The app never calls `downloadResources` or
   `downloadAllResources` and never starts a download. A missing model
   counts as "not available on this Mac", the existing reason, so nothing
   new is needed in the UI. This narrows ruling 1's "no downloaded model".
10. **Speed ceiling: "No ceiling."** The measured times are recorded and
    nothing more is required.
11. **Real-raw check (AC13).** The owner will do it later and pick the
    cameras then. It stays an open manual check for the owner.

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
This also covers future macOS releases (owner, RI-7). A raw whose stack does
not ask for ML keeps decoding with the pre-RAW 9 default decoder, even if a
later macOS makes RAW 9 Apple's default. The engineer pins that default.

**R3 (Must).** Exactly one state means "ML noise reduction on". It belongs
to the Noise Reduction group (R10). The new control and the Decoder pop-up's
RAW 9 choice cannot disagree. In this PRD, `9.dng` means RAW 9 whichever way
the decoder names it for the file: `9` for camera raws, `9.dng` for DNG
(RI-E3).

- Choosing `9.dng` in the pop-up turns ML on. Choosing another version
  turns ML off and makes that version the Profile group's decoder.
- While ML is on, the photo decodes with `9.dng`. The Profile group's own
  decoder choice is kept, and applies again when ML is turned off.
- Profile-only presets, a paste of Profile, and turning the Profile group
  off never turn ML on or off.
- Turning the Noise Reduction group off stops ML in the render and keeps
  the setting, as for any group.
- A stack saved before this feature with Profile's decoder at `9.dng` reads
  as ML on, with Profile's decoder at the default. Its rendering does not
  change. Two exceptions (RI-E4):
  - If its Profile group was off, the `9.dng` was never rendering. It reads
    as ML off and the inactive choice is dropped, so rendering stays
    unchanged.
  - If its Noise Reduction group was off, it reads as ML on inside an off
    group and renders classically, where it used RAW 9 before. Turning the
    group on brings RAW 9 back. The group is not turned on for the person.
- A preset saved before this feature with Profile's decoder at `9.dng`
  turns ML on when applied, and changes nothing else in Noise Reduction.

**R4 (Must).** While ML is on and applied, Luminance is its amount and
Color is unavailable, because RAW 9 ignores it. The stored Color value is
kept, and applies again when ML is turned off. When ML is requested but not
applied (R6), Color stays available and renders as usual.

**R5 (Must).** For a RAW photo being edited, the app shows whether ML noise
reduction applies. If it does not, the app names one of these reasons:

- this Mac's macOS has no RAW 9, or macOS does not have the RAW 9 model on
  this Mac yet (owner ruling 9; the app never starts a download). The
  missing-model case applies once the app can tell (RI-E6). Until then, a
  missing model that fails the decode shows "could not be applied to this
  photo";
- this camera is not supported by RAW 9;
- it could not be applied to this photo (the RAW 9 decode failed).

For files that are not RAW, the control is not offered (R7).

**R6 (Must).** When a stack asks for ML noise reduction and it does not
apply (any of R5's reasons), the photo renders with the default decoder and
the stack's classical values. The app shows that ML was not applied, and
why. This holds in the loupe, in export and in `photocli`. Opening, viewing,
exporting, or editing any other control never removes the setting from the
stack. The only exception is the person turning it off.

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
show it as on. It is stored on every RAW file a command reaches, including
raws where ML is not available on this Mac or for this camera; there R6
applies until the Mac or Apple's camera list catches up.

**R11 (Must).** For a RAW+JPEG pair, it applies to the RAW file's edits
only. Edits are already per file, so this changes nothing about how pairs
work.

**R12 (Must).** Export renders ML noise reduction at full resolution, the
same way the loupe shows it.

**R13 (Must).** `photocli` supports it:

- `develop` sets and resets it. On a file that is not RAW, `develop`
  refuses to turn it on (`invalidEdit`), as it already refuses values that
  would have no effect (RI-E5);
- `adjustments` lists it among the parameters;
- `render` and `export` render with it.

The fallback (R6) also applies there, and the JSON output says whether ML
was applied.

**R14 (Must).** photobench has a case that times a 24 MP raw with ML off
and on at three outputs: thumbnail, 2560 px preview, and full-resolution
export. Times measured on the owner's Mac are recorded in this PRD
(Measurements) before the feature ships.

## Acceptance criteria

**AC1 (R1, R4, R12).** On macOS 27, a synthetic Bayer DNG with 2 % noise and
a DNG `NoiseProfile` tag is rendered with ML at Luminance 0 and at Luminance
100. The render at 100 has lower high-frequency energy in flat areas. Both
the full-resolution export path and `photocli render` show this. On a Mac
without RAW 9 the test is skipped, and the skip names the reason.

Whether ML is quieter than classical at 100 is not tested on synthetic data
(RI-E1); AC13 decides it on real raws.

**AC2 (R1).** On the same kind of fixture made from an edge scene, the ML
render's edge contrast is not lower than classical at 100.

**AC3 (R2).** Every existing golden, and the edit-stack corpus
(`EditStackCorpusTests`), pass unchanged. A stack without the setting
produces the same render hash and preview cache key as before. With the
decoder's default reported as `9.dng` (through a test seam), a stack that
does not ask for ML still decodes with the pinned pre-RAW 9 default, not
`9.dng`.

**AC4 (R3).** Each of these is checked:

- A stack saved with `decode.decoderVersion` at `9.dng` (a DNG) or `9` (a
  camera raw) loads as ML on, with Profile's decoder at the default, and
  renders as before.
- The same stack with its Profile group off loads as ML off and renders as
  before. With its Noise Reduction group off, it loads as ML on inside the
  off group (RI-E4).
- A stack with ML on and Profile's decoder at `7.dng` decodes with `9.dng`.
  Turning ML off makes it decode with `7.dng`.
- On a photo with ML on, each of these leaves ML on: applying a
  Profile-only preset, pasting only Profile, and turning the Profile group
  off.
- A pre-feature preset with Profile's decoder at `9.dng` turns ML on and
  leaves the target's Luminance and Color unchanged.
- ML and the decoder choice can never be set to disagree, through the app
  or through `photocli develop`.

**AC5 (R4).** With ML on and applied, the Color control is unavailable.
Turning ML off restores the stored Color value: the stack's `color` is
unchanged across the on/off round trip. With ML requested but not applied
(on macOS 15 or 26, or an unsupported camera), Color is available and
changing it changes the render.

**AC6 (R5, R7).** Manual check, and a unit test of the availability rule:

- A supported raw on macOS 27 shows ML as available.
- A JPEG shows no ML control.
- A camera missing from RAW 9's `supportedCameraModels` shows "camera not
  supported".
- On macOS 15 or 26, any raw shows "not available on this Mac".
- On macOS 27 with the RAW 9 model reported missing (through a test seam),
  a supported raw shows "not available on this Mac", not "could not be
  applied". Nothing in production reports a missing model yet (RI-E6).
- No source file calls `downloadResources` or `downloadAllResources`. A
  test checks this, the way `BrandingTests` scans sources.

**AC7 (R6).** On a Mac without RAW 9, take a stack with ML on and do all of
the following:

- open it in the loupe;
- change Exposure and save;
- export it;
- run `photocli develop` on another parameter.

Afterwards the stack still has ML on. The export used the default decoder.
The loupe shows that ML was not applied.

**AC7a (R5, R6).** On macOS 27, with a RAW 9 decode failure forced through a
test seam on a supported file:

- the render uses the default decoder and the stack's classical values;
- the stack is unchanged;
- the loupe, the export's Activity row and `photocli render` and `export`
  JSON all give the reason "could not be applied to this photo".

**AC8 (R8).** Manual check on the owner's Mac. Turn ML on for a 24 MP raw.
Progress shows until the frame arrives. Meanwhile, the arrow keys move to
the next photo and rating keys still work.

**AC9 (R9).** Turning ML on, then pressing ⌘Z, returns the stack to its
previous bytes. A Luminance drag is one undo step.

**AC10 (R10, R11).** Copy from a raw with ML on. Paste onto a selection of
one raw, one JPEG and one RAW+JPEG pair; the pair shows its RAW, which is
the default.

- The raw and the pair's RAW have ML on.
- The JPEG and the pair's JPEG do not.
- A preset saved with the Noise Reduction group carries the setting.
- Reset All clears it.
- Run the same paste on macOS 15 or 26, or onto a raw from an unsupported
  camera. The raw stores ML on and shows that ML was not applied.

A pair shown as its JPEG is not covered: batch commands reach the file the
grid shows, and a JPEG never gets ML (R11).

**AC11 (R13).** `photocli adjustments` lists the parameter. `photocli
develop --dry-run` with it on prints a stack with ML on. On a JPEG, the
same command fails with `invalidEdit`. `render` and `export` JSON say
whether ML was applied.

**AC12 (R14).** The photobench case runs. Its six times appear under
Measurements.

**AC13 (goal).** Manual check by the owner on 2–3 of their own high-ISO raws
at 1:1. Noise is clearly lower than classical at 100 and there are no new
artifacts. The cameras used are recorded here.

Since RI-E1, this is the only check that ML beats classical. The owner does
it later and picks the cameras then (owner ruling 11). Merging the branch
didn't wait for it, because the feature is off unless chosen. Until it
passes, the roadmap records the feature as "Shipped, checks pending" (see
Revisions, 2026-11-06). A real raw committed as a
test fixture would automate the check, but only with the owner's file and
consent.

## Measurements

R14, measured by the engineer on 2026-11-05:

- File: a synthetic 6000 × 4000 DNG (24 MP), not a real camera raw.
- Build and method: release build, median of 5 runs.
- Machine: Apple M4 Pro, macOS 27.2.

| Output | ML off | ML on |
|---|---|---|
| Thumbnail | 0.06 s | 0.32 s |
| 2560 px preview | 0.07 s | 1.34 s |
| Full-resolution export | 0.11 s | 1.38 s |

The first ML decode in a cold process took 3.05 s, because the model has to
load.

At these times, generating thumbnails for 500 photos with ML on would take
roughly 160 s of decode time, against 30 s with ML off. That is an estimate
from the table, not a measurement. There is no time ceiling (owner ruling
10).

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
  RAW 9 is heavier than earlier versions. Under RAW 9 only `scaleFactor`
  speeds up interactive frames; draft mode is ignored (see the engineer's
  answers under Open questions).
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

- **Owner, AC13 (open manual check).** The owner picks 2–3 cameras and
  high-ISO files when doing the check (ruling 11). Tip for that check: if
  you use DNGs made by a converter, include one. The engineer found that
  RAW 9 barely denoises a DNG with no `NoiseProfile` tag.
- **Owner.** Optional: may one of those files be committed as a test fixture
  to automate the ML-against-classical comparison (RI-E1)? Default: no; AC13
  stays manual.
- **Designer.** For a Mac on macOS 27 whose RAW 9 model is missing, check
  that the "not available on this Mac" text stays true there. One planned
  text reads "this Mac needs macOS 27 or later", which would be false on
  such a Mac. Owner ruling 9 adds no new reason, so only the wording may
  need to change.
- **Engineer, follow-up (Should, RI-E6 option d).** On a test Mac or VM
  whose RAW 9 model was never fetched, see what a decode does without
  triggering a download. Does it fail, or fall back silently? If it falls
  back silently, the app would claim ML applied when it did not, which
  breaks owner ruling 3. That would come back as a requirements issue.
  Should be done before the roadmap marks the feature Shipped, if such a
  machine can be had. If none can be had, the owner decides whether to ship
  without it. The branch merged (PR #39) before this check was done; it is
  recorded as pending, and the owner is asked to confirm shipping without
  it (Revisions, 2026-11-06).

Closed: the time ceiling (owner ruling 10: none) and RI-E2 (owner ruling
9).

Answered by the engineer, 2026-11-05, on an M4 Pro with macOS 27.2 (details
in `status.md`):

- **Apple silicon.** macOS 27 is Apple-silicon-only, so RAW 9 never appears
  on an Intel Mac. The earlier assumption holds.
- **Extended range.** `extendedDynamicRangeAmount` is honored under RAW 9.
  Floating-point DNGs were not measured; if their decoder doesn't list
  version 9, they are "camera not supported" and render as today.
- **Synthetic DNG.** It decodes through RAW 9, but is barely denoised without
  a `NoiseProfile` tag. The fixture writer now has that tag as an opt-in.
- **Draft and scale.** `scaleFactor` is honored; draft mode is ignored. ML
  frames get faster only from a smaller decode, which R8 allows.
- **Failure seam.** The test seam for AC7a exists.
- **Designer.** Answered in `design.md` §14.

## Revisions

- 2026-11-05: first version, from intake answered with all defaults.
- 2026-11-05: product manager's rulings on design.md §13 RI-1 to RI-6. The
  designer's recommendation was accepted in each case; none needed the owner,
  since each follows from owner rulings 3 and 6. RI-7 is with the owner.
  - **RI-1.** ML belongs to Noise Reduction. Profile's decoder choice
    applies only while ML is off, and comes back when ML is turned off.
    Profile presets, paste and the Profile group's on/off never touch ML.
    Pre-feature stacks and presets holding `9.dng` read as ML on.
    Addition: such a preset changes nothing else in Noise Reduction, so it
    keeps doing what it did. Changed R3 and AC4.
  - **RI-2.** Color is unavailable only while ML is on and applied. In the
    fallback it is available and renders. Changed R4 and AC5.
  - **RI-3.** Non-RAW is "not offered", not a named reason. Changed R5 and
    AC6.
  - **RI-4.** Batch commands store ML on every RAW file they reach, even
    where it is not available. R6 applies there. Changed R10 and AC10.
  - **RI-5.** AC10 now says the pair shows its RAW. R11 is unchanged.
  - **RI-6.** A failed RAW 9 decode on a supported file is a fourth reason,
    "could not be applied to this photo", handled as in R6. Changed R5 and
    R6; added AC7a.
- 2026-11-05: owner ruling on design.md §13 RI-7, "Yes, pin old default":
  R2 covers future macOS defaults, and the pre-RAW 9 default decoder is
  pinned for stacks that do not ask for ML. Added owner ruling 8; changed R2
  and AC3.
- 2026-11-05: product manager's rulings on the engineer's requirements
  issues (`status.md`). RI-E2 is with the owner.
  - **RI-E1.** On synthetic noise, classical at 100 smooths more than RAW 9.
    AC1 now checks that ML at Luminance 100 is quieter than ML at 0, on the
    synthetic DNG with a `NoiseProfile` tag. The ML-against-classical
    comparison moves entirely to AC13, the owner's check on real raws, which
    now gates shipping. AC2 is unchanged and passes.
    - Why: owner ruling 7 asked for directional tests that show ML beats
      classical, but the synthetic fixture can't show that. The comparison
      is kept; only where it is checked has moved.
    - The owner may still provide a real raw as a test fixture to automate
      it.
  - **RI-E3.** Confirmed. RAW 9 is `9` for camera raws and `9.dng` for DNG,
    and both count as ML everywhere. Changed R3 and AC4, and the Problem
    text.
  - **RI-E4.** The engineer's handling is intended:
    - Legacy `9.dng` with the Profile group off reads as ML off, so
      rendering stays unchanged.
    - Legacy `9.dng` with the Noise Reduction group off reads as ML on in
      the off group, and renders classically until the group is turned on.
    - Why: turning on a group the person turned off would override their
      choice. The case is rare, shows on screen, and one click recovers it.
    - Changed R3 and AC4.
  - **RI-E5.** Confirmed. `photocli develop` refuses ML on a file that is not
    RAW with `invalidEdit`. Batch commands in the app skip such files and
    count them in Activity, because they act on many files at once. Changed
    R13 and AC11.
  - Measurements filled in from R14. The engineer's answers to the open
    questions are recorded.
- 2026-11-05: owner rulings 9–11.
  - **RI-E2, "Allowed, never trigger it".** macOS's own on-demand model may
    be used only when macOS already has it. The app never starts a
    download, and a missing model reads as "not available on this Mac".
    Changed R5 and AC6.
  - **Speed: "No ceiling".** The open question is closed; the Measurements
    section is updated.
  - **AC13.** The owner does it later and picks the cameras then. I added
    that AC13 holds the roadmap short of Shipped but does not hold up a
    merge, because the feature is off unless chosen.
- 2026-11-05: product manager's ruling on RI-E6. The macOS 27.2 SDK has no
  public way to tell whether the RAW 9 model is present without
  downloading it.
  - **Ruling: (c) now, (d) as a follow-up.** For now, a failed decode keeps
    the "could not be applied to this photo" reason. When a Mac or VM that
    never fetched the model can be had, check what a decode does there.
  - Rejected (a): calling every failure "not available on this Mac" would
    give real decode failures a false reason, against owner ruling 3.
  - Rejected (b): reading macOS's undocumented private asset folder is
    fragile and unsupported.
  - Owner ruling 9's mapping (missing model shows "not available on this
    Mac") stays the goal. It is built and tested through a test seam;
    nothing in production triggers it until the app can tell the model is
    missing.
  - Ruling 9's "never trigger a download" is unaffected.
  - Changed R5, AC6 and Open questions.
- 2026-11-06: Ship pass. The branch merged into `develop` in PR #39 (merge
  commit 334312c, 2026-11-05). `docs/WORKFLOW.md` step 6 now says a merge is
  what ships, and checks still open are recorded as "Shipped, checks
  pending", never dropped. So AC13 and the RI-E6 (d) check no longer hold
  the roadmap short of Shipped; they are listed as pending on the Status
  line and the roadmap. Changed the Status and Roadmap lines, AC13's last
  paragraph and the RI-E6 (d) open question. The (d) follow-up, if a
  silent fallback is found, is the roadmap row ml-denoise-missing-model.
